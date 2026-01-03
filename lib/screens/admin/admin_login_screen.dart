// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/admin_auth_service.dart';

enum AlertType {
  success,
  error,
  warning,
  info,
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isVerifyingPattern = false;
  bool _obscurePassword = true;

  // Admin auth service
  late final AdminAuthService _adminAuthService;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _adminAuthService = context.read<AdminAuthService>();
    // Load user role in background without blocking UI
    _loadUserRoleBackground();
  }

  void _loadUserRoleBackground() {
    // Load role asynchronously in background
    Future.microtask(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 5));

          if (mounted) {
            setState(() {
              _userRole = userDoc.data()?['role'] as String?;
            });
          }
        } catch (e) {
          debugPrint('Error loading user role: $e');
        }
      }
    });
  }
  
  void _showAlert({
    required String title,
    required String message,
    required AlertType type,
    VoidCallback? onDismiss,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        IconData icon;
        Color iconColor;
        Color buttonColor;
        
        switch (type) {
          case AlertType.success:
            icon = Icons.check_circle;
            iconColor = Colors.green;
            buttonColor = Colors.green;
            break;
          case AlertType.error:
            icon = Icons.error;
            iconColor = Colors.red;
            buttonColor = Colors.red;
            break;
          case AlertType.warning:
            icon = Icons.warning;
            iconColor = Colors.orange;
            buttonColor = Colors.orange;
            break;
          case AlertType.info:
            icon = Icons.info;
            iconColor = Colors.blue;
            buttonColor = Colors.blue;
            break;
        }
        
        return AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (onDismiss != null) {
                  onDismiss();
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: buttonColor,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPatternLock() async {
    if (_isVerifyingPattern) return;

    setState(() {
      _isVerifyingPattern = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Get user role with timeout
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final userRole = userData['role'] as String?;
      final isAdmin = userRole == 'user/admin' || userRole == 'admin';
      final isSubadmin = userRole == 'user/subadmin' || userRole == 'subadmin';

      if (!isAdmin && !isSubadmin) {
        if (mounted) {
          setState(() => _isVerifyingPattern = false);
          // Show access denied alert
          _showAlert(
            title: 'Access Denied',
            message: 'You do not have admin or sub-admin privileges. Redirecting to home...',
            type: AlertType.error,
            onDismiss: () => Navigator.pushReplacementNamed(context, '/home'),
          );
        }
        return;
      }

      // For subadmin, check if they need to set a password
      if (isSubadmin && userData['hasSetPassword'] != true) {
        if (mounted) {
          setState(() => _isVerifyingPattern = false);
          _showAlert(
            title: 'Password Setup Required',
            message: 'You need to set your admin password before continuing.',
            type: AlertType.info,
            onDismiss: () => Navigator.of(context).pushReplacementNamed('/admin/password'),
          );
        }
        return;
      }

      // Check pattern lock only for admin
      if (isAdmin) {
        final hasPatternLock = await _adminAuthService.hasPatternLock();

        if (!hasPatternLock) {
          if (mounted) {
            setState(() => _isVerifyingPattern = false);
            // Pattern lock must be set up before accessing dashboard
            _showAlert(
              title: 'Pattern Lock Required',
              message: 'Pattern lock must be set up by admin first. Please contact the main administrator.',
              type: AlertType.warning,
            );
          }
          return;
        }

        // Show pattern lock for admin - navigation is handled in the success callback
        final patternVerified = await _verifyPatternInModal(context);

        // If pattern was verified, navigate to dashboard
        if (patternVerified == true && mounted) {
          _showAlert(
            title: 'Pattern Verified',
            message: 'Pattern verified successfully! Redirecting to dashboard...',
            type: AlertType.success,
            onDismiss: () => Navigator.of(context).pushNamedAndRemoveUntil('/admin/dashboard', (route) => false),
          );
        }
      } else {
        // For subadmin, password verification is required through the login form
        if (mounted) {
          setState(() => _isVerifyingPattern = false);
          _showAlert(
            title: 'Password Required',
            message: 'Please enter your password to continue to the sub-admin portal.',
            type: AlertType.info,
          );
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _isVerifyingPattern = false);
        _showAlert(
          title: 'Connection Timeout',
          message: 'Network timeout. Please check your internet connection and try again.',
          type: AlertType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifyingPattern = false);
        _showAlert(
          title: 'Authentication Error',
          message: 'An error occurred during authentication: ${e.toString()}',
          type: AlertType.error,
        );
      }
    }
  }

  Future<bool> _verifyPatternInModal(BuildContext modalContext) async {
    try {
      // Use the admin auth service directly to avoid double dialogs
      final completer = Completer<bool>();
      
      final result = await _adminAuthService.verifyPattern(
        context: modalContext,
        onSuccess: () {
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (message) {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      );

      return result;
    } catch (e) {
      if (mounted) {
        _showAlert(
          title: 'Pattern Error',
          message: 'An error occurred during pattern verification: ${e.toString()}',
          type: AlertType.error,
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return; // Prevent multiple clicks

    // Show loading state immediately
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isVerifyingPattern = false;
      });
    }

    // Cache context and password to avoid using them in async gap
    final currentContext = context;
    final password = _passwordController.text;

    try {
      // Clear the password field early for security
      _passwordController.clear();

      final loginSuccess = await _adminAuthService.verifyPassword(
        password,
        onError: (message) {
          if (mounted) {
            _showAlert(
              title: 'Login Failed',
              message: message,
              type: AlertType.error,
            );
          }
        },
      );

      if (!mounted) return;

      if (loginSuccess) {
        // Show success message before navigation
        if (mounted) {
          _showAlert(
            title: 'Login Successful',
            message: 'Authentication successful! Redirecting to dashboard...',
            type: AlertType.success,
            onDismiss: () => Navigator.of(currentContext).pushNamedAndRemoveUntil(
              '/admin/dashboard',
              (Route<dynamic> route) => false,
            ),
          );
        }
        return; // Exit early on success
      }
    } catch (e) {
      if (mounted) {
        _showAlert(
          title: 'Login Error',
          message: 'Login failed. Please check your credentials and try again.',
          type: AlertType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F0F1),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFF5A7D7E),
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pushReplacementNamed(
                              context,
                              '/home',
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // App logo and name
                  Column(
                    children: [
                      Image.asset(
                        'assets/images/app_logo.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _userRole == 'user/admin' || _userRole == 'admin'
                            ? 'Admin Portal'
                            : 'Sub-Admin Portal',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF274647),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sign in to continue',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF5A7D7E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF274647),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Admin Password',
                      filled: true,
                      fillColor: Colors.white,
                      labelStyle: const TextStyle(color: Color(0xFF5A7D7E)),
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: Color(0xFF5A7D7E),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: const Color(0xFF5A7D7E),
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF274647),
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (!_isLoading) {
                              _login();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF274647),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'LOGIN',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (_userRole != 'user/subadmin')
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF274647),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.pattern,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: _isLoading ? null : _showPatternLock,
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.of(
                              context,
                            ).pushNamedAndRemoveUntil('/', (route) => false);
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF5A7D7E),
                    ),
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
