// ignore_for_file: use_build_context_synchronously, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pattern_lock/pattern_lock.dart';

// Custom widget to display a pattern
class PatternDisplay extends StatelessWidget {
  final List<int> pattern;
  final Color selectedColor;
  final double pointRadius;

  const PatternDisplay({
    super.key,
    required this.pattern,
    this.selectedColor = const Color(0xFF274647),
    this.pointRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PatternDisplayPainter(
        pattern: pattern,
        selectedColor: selectedColor,
        pointRadius: pointRadius,
      ),
      child: Container(),
    );
  }
}

class PatternDisplayPainter extends CustomPainter {
  final List<int> pattern;
  final Color selectedColor;
  final double pointRadius;

  PatternDisplayPainter({
    required this.pattern,
    required this.selectedColor,
    required this.pointRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = selectedColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = selectedColor;

    final dimension = 3;
    final padding = size.width * 0.15; // Same as relativePadding 0.7
    final availableSize = size.width - (2 * padding);
    final pointSpacing = availableSize / (dimension - 1);

    // Calculate point positions
    final List<Offset> points = [];
    for (int i = 0; i < dimension * dimension; i++) {
      final row = i ~/ dimension;
      final col = i % dimension;
      points.add(Offset(
        padding + col * pointSpacing,
        padding + row * pointSpacing,
      ));
    }

    // Draw lines between pattern points
    if (pattern.isNotEmpty) {
      for (int i = 0; i < pattern.length - 1; i++) {
        final startPoint = points[pattern[i]];
        final endPoint = points[pattern[i + 1]];
        canvas.drawLine(startPoint, endPoint, paint);
      }
    }

    // Draw points
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final isSelected = pattern.contains(i);
      
      canvas.drawCircle(
        point,
        pointRadius,
        pointPaint,
      );
      
      if (isSelected) {
        canvas.drawCircle(
          point,
          pointRadius * 0.4,
          Paint()..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  bool _isPatternLockEnabled = false;
  List<int>? _adminPattern; // Store the admin pattern
  String? _userRole; // Store the user's role

  // Pattern lock state

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadSettings();
    _loadAdminPattern();
  }

  Future<void> _loadUserRole() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        if (mounted) {
          setState(() {
            _userRole = userDoc.data()?['role'] as String?;
          });
        }
      } catch (e) {
        debugPrint('Error loading user role: $e');
      }
    }
  }

  Future<void> _loadAdminPattern() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['adminPatternLockData'] != null) {
        setState(() {
          _adminPattern = List<int>.from(
            doc.data()?['adminPatternLockData'] as List,
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading admin pattern: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        setState(() {
          _isPatternLockEnabled =
              userDoc.data()?['adminPatternLockEnabled'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading settings: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePatternLockSetting(bool value) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      if (value) {
        // Show confirmation dialog before enabling pattern lock
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Enable Pattern Lock'),
                content: const Text(
                  'Do you want to enable pattern lock for this account?\n\n'
                  'You will need to draw your pattern to log in to the admin panel.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF274647),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('ENABLE'),
                  ),
                ],
              ),
            ) ??
            false;

        if (!confirmed) {
          setState(() => _isPatternLockEnabled = false);
          return;
        }

        // For demo purposes, we're using a simple pattern lock implementation
        // In production, you would want to use a proper pattern lock package
        // and store the pattern hash securely

        // Get the verified pattern
        final pattern = await _verifyPattern();

        if (pattern == null || pattern.isEmpty) {
          if (mounted) {
            setState(() => _isPatternLockEnabled = false);
          }
          return;
        }

        // Store the pattern in memory
        _adminPattern = pattern;

        // Save admin pattern lock setting to Firestore with admin-specific fields
        await _firestore.collection('users').doc(user.uid).update({
          'adminPatternLockEnabled': true,
          'adminPatternLockData': _adminPattern, // Using the stored pattern
          'patternLockSetAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() => _isPatternLockEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pattern lock enabled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Disable admin pattern lock
        await _firestore.collection('users').doc(user.uid).update({
          'adminPatternLockEnabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() => _isPatternLockEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pattern lock disabled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating settings: $e')));
      }
      // Revert the switch if there was an error
      if (mounted) {
        setState(() => _isPatternLockEnabled = !value);
      }
    }
  }

  Future<List<int>?> _verifyPattern() async {
    if (_adminPattern != null) {
      // If we already have a pattern, verify against it
      final verified = await _verifyExistingPattern(_adminPattern!);
      return verified ? _adminPattern : null;
    }
    // Otherwise, create a new pattern
    List<int>? pattern;
    bool isConfirmed = false;
    bool isFirstPattern = true;
    List<int> firstPattern = [];
    String patternKey = 'pattern1'; // Key to force rebuild
    bool showFirstPattern = false; // State to control showing first pattern

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                isFirstPattern
                    ? 'Draw your pattern'
                    : 'Draw pattern again to confirm',
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Connect at least 4 dots to create your pattern',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: PatternLock(
                            key: ValueKey(patternKey), // Key to force rebuild
                            selectedColor: const Color(0xFF274647),
                            pointRadius: 12,
                            showInput: true,
                            dimension: 3,
                            relativePadding: 0.7,
                            selectThreshold: 25,
                            fillPoints: true,
                            onInputComplete: (List<int> input) {
                              setState(() {
                                pattern = input;
                                showFirstPattern = false; // Hide pattern when user starts drawing
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (pattern != null && pattern!.length < 4)
                        const Text(
                          'Connect at least 4 dots',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (!isFirstPattern && firstPattern.isNotEmpty)
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      showFirstPattern = !showFirstPattern;
                                    });
                                  },
                                  icon: const Icon(Icons.more_vert),
                                  tooltip: showFirstPattern ? 'Hide pattern' : 'Show pattern',
                                ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text('CANCEL'),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: pattern != null && pattern!.length >= 4
                                ? () {
                                    if (isFirstPattern) {
                                      firstPattern = List.from(pattern!);
                                      setState(() {
                                        isFirstPattern = false;
                                        pattern = null;
                                        patternKey = 'pattern2'; // Change key to force rebuild
                                      });
                                    } else {
                                      // Verify patterns match
                                      if (_patternsMatch(firstPattern, pattern!)) {
                                        isConfirmed = true;
                                        Navigator.pop(context);
                                      } else {
                                        // Show error and reset
                                        setState(() {
                                          isFirstPattern = true;
                                          firstPattern = [];
                                          pattern = null;
                                          patternKey = 'pattern1'; // Reset key
                                          showFirstPattern = false;
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Patterns do not match. Please try again.',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF274647),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(isFirstPattern ? 'CONTINUE' : 'CONFIRM'),
                          ),
                        ],
                      ),
                      if (!isFirstPattern && showFirstPattern && firstPattern.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Your first pattern:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: PatternDisplay(
                                    pattern: firstPattern,
                                    selectedColor: Colors.blue,
                                    pointRadius: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // Return the pattern if confirmed and valid
    if (isConfirmed && pattern != null && pattern!.length >= 4) {
      return pattern;
    }

    return null;
  }

  Future<bool> _verifyExistingPattern(List<int> storedPattern) async {
    bool isVerified = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Verify Pattern'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Draw your existing pattern to verify',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: PatternLock(
                        selectedColor: const Color(0xFF274647),
                        pointRadius: 12,
                        showInput: true,
                        dimension: 3,
                        relativePadding: 0.7,
                        selectThreshold: 25,
                        fillPoints: true,
                        onInputComplete: (List<int> input) {
                          if (_patternsMatch(input, storedPattern)) {
                            isVerified = true;
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Incorrect pattern. Please try again.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
              ],
            );
          },
        );
      },
    );

    return isVerified;
  }

  bool _patternsMatch(List<int> pattern1, List<int> pattern2) {
    if (pattern1.length != pattern2.length) return false;
    for (int i = 0; i < pattern1.length; i++) {
      if (pattern1[i] != pattern2[i]) return false;
    }
    return true;
  }

  Future<void> _handleForgotPassword() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final TextEditingController passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Admin Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter new admin password:'),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                try {
                  // Update password in Firebase Authentication
                  await user.updatePassword(passwordController.text);

                  // Also update in Firestore if you store passwords there (not recommended)
                  await _firestore.collection('users').doc(user.uid).update({
                    'password': passwordController.text,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  if (mounted) {
                    Navigator.pop(context); // Close the dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password updated successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } on FirebaseAuthException catch (e) {
                  String message = 'Failed to update password';
                  if (e.code == 'requires-recent-login') {
                    message = 'Please re-authenticate before changing password';
                  }
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    // ignore: duplicate_ignore
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF274647),
              foregroundColor: Colors.white,
            ),
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
        backgroundColor: const Color(0xFF274647),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Security Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF274647),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Forgot Password
                        ListTile(
                          leading: const Icon(
                            Icons.lock_reset,
                            color: Color(0xFF274647),
                          ),
                          title: const Text('Reset Password'),
                          subtitle: const Text(
                            'Send a password reset link to your email',
                          ),
                          trailing: ElevatedButton(
                            onPressed: _handleForgotPassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF274647),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Reset'),
                          ),
                        ),
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        if (_userRole != 'user/subadmin') ...[
                          const Divider(height: 1, indent: 20, endIndent: 20),
                          // Pattern Lock - Only show for admin users
                          SwitchListTile(
                            title: const Text('Pattern Lock'),
                            subtitle: const Text(
                              'Enable pattern lock for admin access',
                            ),
                            value: _isPatternLockEnabled,
                            onChanged: _updatePatternLockSetting,
                            activeColor: const Color(0xFF274647),
                            secondary: const Icon(
                              Icons.pattern,
                              color: Color(0xFF274647),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // App Version
                  Center(
                    child: Text(
                      'App Version 1.0.4',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
