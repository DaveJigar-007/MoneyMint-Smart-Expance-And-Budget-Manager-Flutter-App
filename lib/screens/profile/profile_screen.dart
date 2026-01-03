import 'dart:io';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import '../../widgets/app_scaffold.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  // Image picker instance
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  String? _profileImageUrl;
  String? _profileImageBase64;
  bool _isUploading = false;

  // Get the application documents directory
  late final Directory _appDocDir;

  @override
  void initState() {
    super.initState();
    _initDirectories();
    _loadUserData();
  }

  Future<void> _initDirectories() async {
    _appDocDir = await getApplicationDocumentsDirectory();
    final assetsDir = Directory('${_appDocDir.path}/assets/usersPic');
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
      );

      if (pickedFile != null) {
        setState(() => _isUploading = true);

        if (kIsWeb) {
          // For web, save to temporary directory first
          final bytes = await pickedFile.readAsBytes();
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            '${tempDir.path}/temp_profile_${DateTime.now().millisecondsSinceEpoch}${p.extension(pickedFile.path)}',
          );
          await tempFile.writeAsBytes(bytes);
          _imageFile = tempFile;
        } else {
          // For mobile, use the picked file directly
          _imageFile = File(pickedFile.path);
        }

        await _uploadImage();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to pick image. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _uploadImage() async {
    if (_imageFile == null || _user == null) return;

    try {
      setState(() => _isUploading = true);

      // Ensure the assets/usersPic directory exists
      final assetsDir = Directory('${_appDocDir.path}/assets/usersPic');
      if (!await assetsDir.exists()) {
        await assetsDir.create(recursive: true);
      }

      // Generate a unique filename
      final fileExtension = p.extension(_imageFile!.path).toLowerCase();
      final fileName =
          'profile_${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      final localPath = '${assetsDir.path}/$fileName';
      final relativePath = 'assets/usersPic/$fileName';

      // Copy the file to the assets directory
      if (kIsWeb) {
        final bytes = await _imageFile!.readAsBytes();
        final file = File(localPath);
        await file.writeAsBytes(bytes);
      } else {
        await _imageFile!.copy(localPath);
      }

      // Update user's profile with the new image path in Firestore
      await _firestore.collection('users').doc(_user!.uid).set({
        'profileImagePath': relativePath,
        'profileImageLocalPath': localPath,
        'profileImageBase64': base64Encode(await _imageFile!.readAsBytes()),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _user!.uid,
      }, SetOptions(merge: true));

      // Update the local state
      setState(() {
        _profileImageUrl = localPath; // Use local path for display
        try {
          _profileImageBase64 = base64Encode(_imageFile!.readAsBytesSync());
        } catch (_) {
          _profileImageBase64 = null;
        }
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error saving image locally: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save image. Please try again.'),
          ),
        );
      }
      setState(() => _isUploading = false);
    }
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      _user = _auth.currentUser;

      if (_user != null) {
        _nameController.text = _user!.displayName ?? '';
        _emailController.text = _user!.email ?? '';

        // Load additional user data from Firestore
        final doc = await _firestore.collection('users').doc(_user!.uid).get();
        if (doc.exists) {
          _userData = doc.data() as Map<String, dynamic>;
          _profileImageBase64 = _userData?['profileImageBase64'];
          _phoneController.text = _userData?['phone'] ?? '';

          // Check for local image path first
          if (_userData?['profileImageLocalPath'] != null) {
            final localFile = File(_userData!['profileImageLocalPath']);
            if (await localFile.exists()) {
              _profileImageUrl = _userData!['profileImageLocalPath'];
            } else if (_userData?['profileImagePath'] != null) {
              // Try with the relative path
              final relativePath = _userData!['profileImagePath'];
              final fullPath = '${_appDocDir.path}/$relativePath';
              if (await File(fullPath).exists()) {
                _profileImageUrl = fullPath;
              }
            }
          }

          // If still no image, check the photoURL from Auth
          if (_profileImageUrl == null &&
              _profileImageBase64 == null &&
              _user!.photoURL != null) {
            _profileImageUrl = _user!.photoURL;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // Update display name in Firebase Auth
      if (_user != null && _nameController.text != _user!.displayName) {
        await _user!.updateDisplayName(_nameController.text);
        await _user!.reload();
        _user = _auth.currentUser; // Refresh user data
      }

      // Update user data in Firestore
      await _firestore.collection('users').doc(_user!.uid).set({
        'name': _nameController.text,
        'email': _user!.email,
        'phone': _phoneController.text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint('Error signing out: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
      }
    }
  }

  Widget _buildProfileImage() {
    // If base64 is available, prefer it (works across platforms)
    if (_profileImageBase64 != null && _profileImageBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(_profileImageBase64!);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 120,
          height: 120,
          errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
        );
      } catch (e) {
        debugPrint('Error decoding base64 profile image: $e');
      }
    }

    if (_profileImageUrl == null) {
      return const Icon(Icons.person, size: 60);
    }

    try {
      final file = File(_profileImageUrl!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: 120,
          height: 120,
          errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
        );
      } else if (_profileImageUrl!.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: _profileImageUrl!,
          placeholder: (context, url) => const CircularProgressIndicator(),
          errorWidget: (context, url, error) => _buildDefaultAvatar(),
          fit: BoxFit.cover,
          width: 120,
          height: 120,
        );
      }
    } catch (e) {
      debugPrint('Error loading profile image: $e');
    }

    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Profile',
      actions: [
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: _isLoading ? null : _updateProfile,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile Picture
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).primaryColor,
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: _isUploading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _imageFile != null
                                  ? Image.file(
                                      _imageFile!,
                                      fit: BoxFit.cover,
                                      width: 120,
                                      height: 120,
                                    )
                                  : _profileImageUrl != null
                                  ? _buildProfileImage()
                                  : const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _isUploading ? null : _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: _isUploading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Email Field (read-only)
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                      readOnly: true,
                      enabled: false,
                    ),
                    const SizedBox(height: 16),

                    // Phone Field
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: const Icon(Icons.phone),
                        border: const OutlineInputBorder(),
                        hintText: 'Enter your phone number',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your phone number';
                        }
                        // basic numeric check
                        final cleaned = value.replaceAll(
                          RegExp(r'[^0-9+]'),
                          '',
                        );
                        if (cleaned.length < 7) {
                          return 'Please enter a valid phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Update Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _updateProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const Text(
                              'UPDATE PROFILE',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),

                    const SizedBox(height: 16),

                    // Sign Out Button
                    OutlinedButton(
                      onPressed: _signOut,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'SIGN OUT',
                        style: TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    ),

                    // Account Actions
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 8),

                    ListTile(
                      leading: const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                      ),
                      title: const Text('About'),
                      trailing: Text(
                        'v1.0.4',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
