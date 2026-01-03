import 'package:flutter/material.dart';

class AdminSplashScreen extends StatefulWidget {
  const AdminSplashScreen({super.key});

  @override
  State<AdminSplashScreen> createState() => _AdminSplashScreenState();
}

class _AdminSplashScreenState extends State<AdminSplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    try {
      // Wait for 1 second for smooth transition
      await Future.delayed(const Duration(seconds: 1));
      
      if (!mounted) return;
      
      // Always redirect to admin login screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/admin/login');
      }
    } catch (e) {
      // If any error occurs, go to admin login
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/admin/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAD5DA), // Light gray background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo
            Image.asset(
              'assets/images/mm.png',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            // App name
            const Text(
              'Money Mint',
              style: TextStyle(
                color: Color(0xFF264547), // Dark teal text
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Admin Panel',
              style: TextStyle(
                color: Color(0xFF264547), // Dark teal text
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF264547)), // Dark teal loader
            ),
          ],
        ),
      ),
    );
  }
}
