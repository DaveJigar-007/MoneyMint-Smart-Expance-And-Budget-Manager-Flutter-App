import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SubadminPasswordDialog extends StatefulWidget {
  final VoidCallback onPasswordSet;

  const SubadminPasswordDialog({super.key, required this.onPasswordSet});

  @override
  State<SubadminPasswordDialog> createState() => _SubadminPasswordDialogState();
}

class _SubadminPasswordDialogState extends State<SubadminPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorText;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  Future<void> _getCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      setState(() {
        _userEmail = user!.email;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _setPassword() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if new password is same as login password
    if (_userEmail != null) {
      try {
        // Try to sign in with current email and new password
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _userEmail!,
          password: _passwordController.text,
        );
        
        // If sign in succeeds, it means the password is the same as login password
        if (mounted) {
          setState(() {
            _errorText = 'New password cannot be the same as your login password';
            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        // Sign in failed, which means the password is different - this is what we want
      }
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Update password in Firebase Auth
      await user.updatePassword(_passwordController.text);

      // Save the admin password and mark as set in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'admin_pass': _passwordController.text, // Save the admin password
        'hasSetPassword': true,
        'role': 'user/subadmin', // Ensure role is set
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onPasswordSet();
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorText = e.message ?? 'An error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set Admin Password'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please set a secure password for admin access.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              if (_errorText != null) ...{
                const SizedBox(height: 16),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.red),
                ),
              },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _setPassword,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('SET PASSWORD'),
        ),
      ],
    );
  }
}