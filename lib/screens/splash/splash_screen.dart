import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firebase_service.dart';

class SplashScreenPage extends StatefulWidget {
  const SplashScreenPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SplashScreenPageState createState() => _SplashScreenPageState();
}

class _SplashScreenPageState extends State<SplashScreenPage> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    // Wait for 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    // Check if user is already logged in
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (user != null) {
      try {
        // Check if user is blocked
        final isBlocked = await FirebaseService.isCurrentUserBlocked();
        if (isBlocked) {
          // User is blocked, go to blocked screen
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/blocked');
          }
          return;
        }

        // Check if pattern lock is enabled
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final isPatternLockEnabled =
            userDoc.data()?['patternLockEnabled'] ?? false;

        // Navigate based on pattern lock status
        if (mounted) {
          if (isPatternLockEnabled) {
            // Navigate to pattern verification screen
            Navigator.pushReplacementNamed(context, '/pattern-verify');
          } else {
            // No pattern lock, go to home screen
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      } catch (e) {
        // If there's an error, log out and go to login
        if (mounted) {
          debugPrint('Error in splash navigation: $e');
          await FirebaseService.signOut();
          // ignore: use_build_context_synchronously
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } else {
      // User is not logged in, go to login screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F0F1), // #e9f0f1
      body: Center(
        child: Image.asset(
          'assets/images/app_logo.png',
          width: 300,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

// This widget will be shown while the splash screen is visible
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SplashScreenPage();
  }
}
