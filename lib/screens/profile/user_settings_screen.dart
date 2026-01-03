// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pattern_lock/pattern_lock.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_scaffold.dart';

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

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isPatternLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        setState(() {
          _isPatternLockEnabled =
              userDoc.data()?['patternLockEnabled'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePatternLock(bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      if (value) {
        // Show confirmation dialog before enabling pattern lock
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Enable Pattern Lock'),
                content: const Text(
                  'Do you want to enable pattern lock for this account?\n\n'
                  'You will need to draw your pattern to log in to the app.',
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

        bool patternVerified = await _verifyPattern();

        if (!patternVerified) {
          if (mounted) {
            setState(() => _isPatternLockEnabled = false);
          }
          return;
        }

        // Save pattern lock setting to Firestore
        await _firestore.collection('users').doc(user.uid).update({
          'patternLockEnabled': true,
          'patternLockSetAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Disable pattern lock
        await _firestore.collection('users').doc(user.uid).update({
          'patternLockEnabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      setState(() => _isPatternLockEnabled = value);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Pattern lock enabled successfully'
                  : 'Pattern lock disabled',
            ),
            backgroundColor: value ? const Color(0xFF274647) : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating pattern lock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update pattern lock'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isPatternLockEnabled = !value);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _verifyPattern() async {
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
                              
                              // Auto-redirect to confirm pattern if pattern is valid
                              if (input.length >= 4 && isFirstPattern) {
                                firstPattern = List.from(input);
                                setState(() {
                                  isFirstPattern = false;
                                  pattern = null;
                                  patternKey = 'pattern2'; // Change key to force rebuild
                                });
                              }
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
                      if (!isFirstPattern)
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
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('CANCEL'),
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: pattern != null && pattern!.length >= 4
                                  ? () {
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
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF274647),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('CONFIRM'),
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

    // Save the pattern to Firestore if confirmed
    if (isConfirmed && pattern != null && pattern!.length >= 4) {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'patternLockData': pattern,
          'patternLockSetAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
    }

    return false;
  }

  bool _patternsMatch(List<int> pattern1, List<int> pattern2) {
    if (pattern1.length != pattern2.length) return false;
    for (int i = 0; i < pattern1.length; i++) {
      if (pattern1[i] != pattern2[i]) return false;
    }
    return true;
  }

  // Toggle password visibility state
  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  // Function to copy text to clipboard
  Future<void> _copyToClipboard(String text, String message) async {
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF274647),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _updatePassword() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No user is currently logged in')),
        );
      }
      return;
    }

    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    String? errorMessage;

    // Reset visibility states
    _isCurrentPasswordVisible = false;
    _isNewPasswordVisible = false;
    _isConfirmPasswordVisible = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Update Password'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      // Current Password Field with visibility toggle and copy
                      TextFormField(
                        controller: currentPasswordController,
                        obscureText: !_isCurrentPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Copy button
                              if (currentPasswordController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 20),
                                  onPressed: () => _copyToClipboard(
                                    currentPasswordController.text,
                                    'Password copied to clipboard',
                                  ),
                                  tooltip: 'Copy password',
                                ),
                              // Toggle visibility button
                              IconButton(
                                icon: Icon(
                                  _isCurrentPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isCurrentPasswordVisible =
                                        !_isCurrentPasswordVisible;
                                  });
                                },
                                tooltip: _isCurrentPasswordVisible
                                    ? 'Hide password'
                                    : 'Show password',
                              ),
                            ],
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your current password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // New Password Field with visibility toggle
                      TextFormField(
                        controller: newPasswordController,
                        obscureText: !_isNewPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isNewPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isNewPasswordVisible = !_isNewPasswordVisible;
                              });
                            },
                            tooltip: _isNewPasswordVisible
                                ? 'Hide password'
                                : 'Show password',
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a new password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Confirm New Password Field with visibility toggle
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: !_isConfirmPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isConfirmPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isConfirmPasswordVisible =
                                    !_isConfirmPasswordVisible;
                              });
                            },
                            tooltip: _isConfirmPasswordVisible
                                ? 'Hide password'
                                : 'Show password',
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your new password';
                          }
                          if (value != newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setState(() {
                              isLoading = true;
                              errorMessage = null;
                            });

                            try {
                              // Re-authenticate user
                              final credential = EmailAuthProvider.credential(
                                email: user.email!,
                                password: currentPasswordController.text,
                              );
                              await user.reauthenticateWithCredential(
                                credential,
                              );

                              // Update password
                              await user.updatePassword(
                                newPasswordController.text,
                              );

                              if (mounted) {
                                Navigator.pop(context, true);
                              }
                            } on FirebaseAuthException catch (e) {
                              String message = 'Failed to update password';
                              if (e.code == 'wrong-password') {
                                message = 'Incorrect current password';
                              } else if (e.code == 'weak-password') {
                                message = 'The password is too weak';
                              } else if (e.code == 'requires-recent-login') {
                                message =
                                    'Session expired. Please log in again.';
                              }
                              setState(() {
                                errorMessage = message;
                                isLoading = false;
                              });
                            } catch (e) {
                              setState(() {
                                errorMessage =
                                    'An error occurred. Please try again.';
                                isLoading = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF274647),
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('UPDATE'),
                ),
              ],
            );
          },
        );
      },
    ).then((success) async {
      if (success == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Password updated successfully. You will be logged out.',
              ),
              backgroundColor: Color(0xFF274647),
              duration: Duration(seconds: 3),
            ),
          );

          // Wait for the snackbar to show before logging out
          await Future.delayed(const Duration(seconds: 3));

          // Sign out and navigate to login screen
          await _auth.signOut();
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/login',
              (route) => false,
            );
          }
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Settings',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Security Section
                  _buildSectionHeader('Security'),

                  // Change Password
                  _buildSettingItem(
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    subtitle: 'Update your login password',
                    onTap: _updatePassword,
                  ),
                  _buildDivider(),

// Pattern Lock
                  _buildSettingItem(
                    icon: Icons.pattern,
                    title: 'Pattern Lock',
                    subtitle: 'Enable pattern lock for additional security',
                    trailing: Switch(
                      value: _isPatternLockEnabled,
                      onChanged: _togglePatternLock,
                      activeColor: theme.primaryColor,
                    ),
                  ),
                  _buildDivider(),

                  // About Section
                  _buildSectionHeader('About'),
                  _buildSettingItem(
                    icon: Icons.info,
                    title: 'About MoneyMint',
                    subtitle: 'Version 1.0.4',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'MoneyMint',
                        applicationVersion: '1.0.4',
                        applicationIcon: const Icon(
                          Icons.account_balance_wallet,
                          size: 40,
                        ),
                        applicationLegalese:
                            '© 2026 MoneyMint. All rights reserved.\n\nA smart expense and budget manager.',
                      );
                    },
                  ),
                  _buildDivider(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 1, indent: 56);
  }
}
