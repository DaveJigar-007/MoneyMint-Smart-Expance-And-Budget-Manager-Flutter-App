import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final firestore = FirebaseFirestore.instance;

      // Save to Firestore
      await firestore.collection('support_messages').add({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'userId': user?.uid ?? 'anonymous',
        'userEmail': user?.email,
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'pending', // pending, in_progress, resolved
        'isRead': false,
      });

      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent. Support will contact you soon.'),
            backgroundColor: Color(0xFF274647),
            duration: Duration(seconds: 3),
          ),
        );

        // Delay navigation to allow snackbar to be visible
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          // Redirect to home screen after showing success notification
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Support')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Your name'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter your name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Your email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  final emailRe = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
                  if (!emailRe.hasMatch(v)) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                decoration: const InputDecoration(labelText: 'Message'),
                maxLines: 5,
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Please enter at least 10 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Or email directly: support@moneymint.com',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
