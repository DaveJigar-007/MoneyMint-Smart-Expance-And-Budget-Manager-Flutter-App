import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pattern_lock/pattern_lock.dart';

class PatternVerificationScreen extends StatefulWidget {
  const PatternVerificationScreen({super.key});

  @override
  State<PatternVerificationScreen> createState() => _PatternVerificationScreenState();
}

class _PatternVerificationScreenState extends State<PatternVerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  int _failedAttempts = 0;
  DateTime? _lockUntil;
  List<int>? _storedPattern;
  
  @override
  void initState() {
    super.initState();
    _loadPattern();
  }
  
  Future<void> _loadPattern() async {
    final user = _auth.currentUser;
    if (user == null) {
      _navigateToLogin();
      return;
    }
    
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final isPatternEnabled = userDoc.data()?['patternLockEnabled'] ?? false;
        
        if (!isPatternEnabled) {
          _navigateToHome();
          return;
        }
        
        setState(() {
          _storedPattern = List<int>.from(userDoc.data()?['patternLockData'] ?? []);
          _isLoading = false;
        });
      } else {
        _navigateToHome();
      }
    } catch (e) {
      debugPrint('Error loading pattern: $e');
      _navigateToHome();
    }
  }
  
  bool _isLocked() {
    if (_lockUntil != null) {
      if (DateTime.now().isBefore(_lockUntil!)) {
        return true;
      } else {
        // Lock period is over, reset
        _lockUntil = null;
        _failedAttempts = 0;
        return false;
      }
    }
    return false;
  }
  
  void _onPatternComplete(List<int> pattern) async {
    if (_isLocked()) {
      final remainingTime = _lockUntil!.difference(DateTime.now());
      final minutes = (remainingTime.inSeconds / 60).ceil();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Too many attempts. Try again in $minutes minutes.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    
    if (_storedPattern == null) return;
    
    if (_patternsMatch(pattern, _storedPattern!)) {
      // Correct pattern
      _failedAttempts = 0;
      _navigateToHome();
    } else {
      // Incorrect pattern
      _failedAttempts++;
      
      // Check if we should lock the pattern
      if (_failedAttempts >= 3) {
        _lockUntil = DateTime.now().add(const Duration(minutes: 5));
        if (mounted) {
          // Lock the pattern by setting the lock time
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Too many failed attempts. Pattern lock disabled for 5 minutes.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      
      // Show error for incorrect pattern
      final remainingAttempts = 3 - _failedAttempts;
      String message = 'Incorrect pattern. ';
      message += remainingAttempts > 0 
          ? '$remainingAttempts attempts remaining.'
          : 'No more attempts left.';
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  bool _patternsMatch(List<int> pattern1, List<int> pattern2) {
    if (pattern1.length != pattern2.length) return false;
    for (int i = 0; i < pattern1.length; i++) {
      if (pattern1[i] != pattern2[i]) return false;
    }
    return true;
  }
  
  void _navigateToHome() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }
  
  void _navigateToLogin() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_isLocked()) {
      final remainingTime = _lockUntil!.difference(DateTime.now());
      final minutes = (remainingTime.inSeconds / 60).ceil();
      
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 80,
                color: Colors.orange,
              ),
              const SizedBox(height: 20),
              Text(
                'Too many attempts',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Try again in $minutes ${minutes == 1 ? 'minute' : 'minutes'}.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(
              Icons.lock_outline,
              size: 60,
              color: Color(0xFF274647),
            ),
            const SizedBox(height: 20),
            Text(
              'Draw your pattern to continue',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 300,
                height: 300,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PatternLock(
                  selectedColor: const Color(0xFF274647),
                  pointRadius: 12,
                  showInput: true,
                  dimension: 3,
                  relativePadding: 0.7,
                  selectThreshold: 25,
                  fillPoints: true,
                  onInputComplete: _onPatternComplete,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await _auth.signOut();
                _navigateToLogin();
              },
              child: const Text('Sign in with different account'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
