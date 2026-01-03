import 'package:flutter/material.dart';
import 'package:money_mint2/services/firebase_service.dart' show FirebaseService;

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseService.signOut();
      if (context.mounted) {
        // Clear all routes and push login screen
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (Route<dynamic> route) => false, // This removes all previous routes
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error signing out. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Disable back button and system navigation
    return WillPopScope(
      onWillPop: () async => false, // Prevent back navigation
      child: PopScope(
        canPop: false, // Prevent back navigation on Android
        child: Scaffold(
          backgroundColor: const Color(0xFFE9F0F1),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.block,
                    size: 80,
                    color: Colors.red,
                  ),
              const SizedBox(height: 24),
              const Text(
                'Account Blocked',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account has been blocked by the administrator.\n\n'
                'If you believe this is a mistake, please contact support.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => _signOut(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF274647),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/replies');
                },
                icon: const Icon(Icons.mail, color: Colors.white),
                label: const Text(
                  'View Support Replies',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
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
