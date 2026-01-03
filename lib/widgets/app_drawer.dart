// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'subadmin_password_dialog.dart';
import 'package:path_provider/path_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../screens/help_screen.dart';
// Home screen import removed because AddTransaction flow was removed from drawer.

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final bool _isLoading = false;
  String? _cachedUserRole;
  StreamSubscription<DocumentSnapshot>? _roleSubscription;

  @override
  void initState() {
    super.initState();
    _setupRoleListener();
  }

  @override
  void dispose() {
    _roleSubscription?.cancel();
    super.dispose();
  }

  void _setupRoleListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;


    _roleSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final userData = snapshot.data();
        if (userData != null) {
          final role = userData['role'] as String?;
          if (role != null) {
            setState(() {
              _cachedUserRole = role;
            });
          }
        }
      } else {
      }
    });
  }

  Future<void> _handleProfileDoubleTap(String userRole) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isAdmin = userRole == 'user/admin';
    final isSubadmin = userRole == 'user/subadmin';

    if (!isAdmin && !isSubadmin) return;

    // Show password reset dialog
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Reset Admin Password'),
        content: Text(
          'Do you want to reset your ${isAdmin ? 'admin' : 'sub-admin'} password?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the confirmation dialog
              _showPasswordResetDialog(isAdmin);
            },
            child: const Text('RESET'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPasswordResetDialog(bool isAdmin) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SubadminPasswordDialog(
        onPasswordSet: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Password reset successfully!'),
                backgroundColor: Color(0xFF274647),
              ),
            );
            if (isAdmin) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/admin',
                (route) => false,
              );
            } else {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/admin/login',
                (route) => false,
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _handleAdminButtonPress(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Fetch fresh user data from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              throw TimeoutException('Failed to fetch user data');
            },
          );

      // ignore: unnecessary_cast
      final userData = userDoc.data() as Map<String, dynamic>?;
      final userRole = userData?['role'] as String?;

      if (!mounted) return;

      // Handle navigation based on role
      if (userRole == 'user/admin' || userRole == 'admin') {
        if (mounted) {
          Navigator.pushNamed(context, '/admin');
        }
      } else if (userRole == 'user/subadmin' || userRole == 'subadmin') {
        final hasSetPassword = userData?['hasSetPassword'] == true;

        if (hasSetPassword) {
          if (mounted) {
            Navigator.pushNamed(context, '/admin/login');
          }
          return;
        }

        // Show password dialog
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => SubadminPasswordDialog(
              onPasswordSet: () {
                if (mounted) {
                  Navigator.pop(context); // Close password dialog
                  Navigator.pushNamed(context, '/admin/login');
                }
              },
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You do not have admin access'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection timeout. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(color: theme.primaryColor),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Profile image and admin badge
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _buildDefaultAvatar(theme);
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildDefaultAvatar(theme);
                    }

                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return _buildDefaultAvatar(theme);
                    }

                    final userData =
                        snapshot.data?.data() as Map<String, dynamic>?;
                    final userRole = userData?['role'] as String? ?? _cachedUserRole ?? '';
                    final isAdmin = userRole == 'user/admin' || userRole == 'admin';
                    final isSubadmin = userRole == 'user/subadmin' || userRole == 'subadmin';
                    final showAdminButton = isAdmin || isSubadmin;

                    // Debug logging to help troubleshoot
                    
                    

                    Widget avatar;

                    // Check for base64 image first
                    if (userData?['profileImageBase64'] != null) {
                      avatar = _buildBase64Avatar(
                        userData!['profileImageBase64'],
                        theme,
                      );
                    } else {
                      // Fallback order: prefer explicit local absolute path,
                      // then stored relative path, then auth photoURL.
                      final imagePath =
                          userData?['profileImageLocalPath'] ??
                          userData?['profileImagePath'] ??
                          user?.photoURL;

                      if (imagePath == null) {
                        avatar = _buildDefaultAvatar(theme);
                      } else if (imagePath.startsWith('http')) {
                        avatar = _buildNetworkAvatar(imagePath, theme);
                      } else {
                        avatar = _buildLocalAvatar(imagePath, theme);
                      }
                    }

                    return Stack(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onDoubleTap: () =>
                                  _handleProfileDoubleTap(userRole),
                              child: avatar,
                            ),
                            const Spacer(), // This will push the icon to the right
                          ],
                        ),
                        // Debug indicator - remove this in production
                        if (userRole.isNotEmpty)
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isAdmin ? Colors.red : Colors.blue,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                userRole,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (showAdminButton)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isLoading
                                    ? null
                                    : () {
                                        Navigator.pop(context); // Close the drawer
                                        _handleAdminButtonPress(context);
                                      },
                                borderRadius: BorderRadius.circular(20),
                                child: const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.admin_panel_settings,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  user?.displayName ?? 'Welcome',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user?.email != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    user!.email!,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.dashboard,
            text: 'Home Dashboard',
            onTap: () => _navigateTo(context, '/home'),
            routeName: '/home',
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.add_circle_outline,
            text: 'Add Expense / Income',
            onTap: () => _navigateTo(context, '/transaction'),
            routeName: '/transaction',
          ),
          // Removed duplicate Export & Backup item
          _createDrawerItem(
            context: context,
            icon: Icons.history,
            text: 'Transactions History',
            onTap: () => _navigateTo(context, '/transactions'),
            routeName: '/transactions',
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.account_balance_wallet,
            text: 'Budget Setup & Tracking',
            onTap: () => _navigateTo(context, '/budget'),
            routeName: '/budget',
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.account_balance,
            text: 'Bank Accounts',
            onTap: () => _navigateTo(context, '/bank-accounts'),
            routeName: '/bank-accounts',
          ),
         
          _createDrawerItem(
            context: context,
            icon: Icons.backup,
            text: 'Export & Backup',
            onTap: () => _navigateTo(context, '/export'),
            routeName: '/export',
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.help_outline,
            text: 'Help',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
            routeName: '/help',
          ),
          const Divider(),
           _createDrawerItem(
            context: context,
            icon: Icons.person,
            text: 'Profile',
            onTap: () => _navigateTo(context, '/profile'),
            routeName: '/profile',
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.settings,
            text: 'Settings',
            onTap: () => _navigateTo(context, '/settings'),
            routeName: '/settings',
          ),
          _createDrawerItem(
            context: context,
            icon: Icons.logout,
            text: 'Logout',
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: () => _signOut(context),
            routeName: '/logout',
          ),
        ],
      ),
    );
  }

  Widget _createDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String text,
    Color? textColor,
    Color? iconColor,
    required VoidCallback onTap,
    required String routeName,
    bool isCurrentPage = false,
  }) {
    final theme = Theme.of(context);
    final isCurrent =
        isCurrentPage || ModalRoute.of(context)?.settings.name == routeName;

    const Color highlightColor = Color(0xFF274647);

    return ListTile(
      selected: isCurrent,
      selectedTileColor: highlightColor,
      selectedColor: Colors.white,
      leading: Icon(
        icon,
        color: isCurrent ? Colors.white : (iconColor ?? theme.primaryColor),
      ),
      title: Text(
        text,
        style: TextStyle(
          color: isCurrent ? Colors.white : (textColor ?? Colors.black87),
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      trailing: isCurrent
          ? const Text(
              '>',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      enabled: !isCurrent,
      onTap: isCurrent ? null : onTap,
    );
  }

  void _navigateTo(BuildContext context, String routeName) {
    Navigator.pop(context); // Close the drawer
    Navigator.pushNamed(context, routeName);
  }

  // The drawer now navigates directly to the Transactions screen.
  // If you want a dedicated 'Add Transaction' flow, implement it from
  // the transactions screen or re-add the screen and route.

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildDefaultAvatar(ThemeData theme) {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.white,
      child: Icon(Icons.person, size: 40, color: theme.primaryColor),
    );
  }

  Widget _buildNetworkAvatar(String imageUrl, ThemeData theme) {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.white,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildDefaultAvatar(theme),
          errorWidget: (context, url, error) => _buildDefaultAvatar(theme),
        ),
      ),
    );
  }

  Widget _buildLocalAvatar(String imagePath, ThemeData theme) {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.white,
      child: ClipOval(
        child: FutureBuilder<String>(
          // Resolve the imagePath: if it's an absolute path and exists use it;
          // otherwise try resolving it relative to application documents dir.
          future: () async {
            try {
              final provided = File(imagePath);
              if (provided.isAbsolute && await provided.exists()) {
                return provided.path;
              }

              // Try resolving relative path inside app documents directory
              final dir = await getApplicationDocumentsDirectory();
              final candidate = '${dir.path}/$imagePath';
              final candidateFile = File(candidate);
              if (await candidateFile.exists()) return candidateFile.path;

              // Last resort: check the provided path as-is
              if (await provided.exists()) return provided.path;
            } catch (e) {
              debugPrint('Error resolving local avatar path: $e');
            }
            return '';
          }(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildDefaultAvatar(theme);
            }

            final resolved = snapshot.data ?? '';
            if (resolved.isNotEmpty) {
              return Image.file(
                File(resolved),
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildDefaultAvatar(theme),
              );
            }

            return _buildDefaultAvatar(theme);
          },
        ),
      ),
    );
  }

  Widget _buildBase64Avatar(String base64Image, ThemeData theme) {
    try {
      return CircleAvatar(
        radius: 30,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image.memory(
            base64Decode(base64Image),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildDefaultAvatar(theme),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return _buildDefaultAvatar(theme);
    }
  }
}
