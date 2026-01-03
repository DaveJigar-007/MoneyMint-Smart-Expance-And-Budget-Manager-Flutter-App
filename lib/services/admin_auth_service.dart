import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pattern_lock/pattern_lock.dart';

class AdminAuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _failedPatternAttempts = 0;
  DateTime? _patternLockUntil;

  // Check if pattern lock is temporarily disabled
  bool _isPatternLocked() {
    if (_patternLockUntil != null) {
      if (DateTime.now().isBefore(_patternLockUntil!)) {
        return true;
      } else {
        // Lock period is over, reset
        _patternLockUntil = null;
        _failedPatternAttempts = 0;
        return false;
      }
    }
    return false;
  }

  // Verify if patterns match
  bool _patternsMatch(List<int> pattern1, List<int> pattern2) {
    if (pattern1.length != pattern2.length) return false;
    for (int i = 0; i < pattern1.length; i++) {
      if (pattern1[i] != pattern2[i]) return false;
    }
    return true;
  }

  // Cache for admin data to reduce Firestore reads
  static Map<String, dynamic>? _cachedAdminData;
  static DateTime? _lastCacheTime;
  
  // Verify admin or subadmin password
  Future<bool> verifyPassword(
    String password, {
    required Function(String) onError,
  }) async {
    try {
      // Use cached data if it's less than 5 minutes old
      final now = DateTime.now();
      if (_cachedAdminData == null || 
          _lastCacheTime == null || 
          now.difference(_lastCacheTime!) > const Duration(minutes: 5)) {
            
        // Get admin or subadmin user
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          onError('User not authenticated');
          return false;
        }

        // Get the user's document to check their role
        final userDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get(const GetOptions(source: Source.serverAndCache));

        if (!userDoc.exists) {
          onError('User data not found');
          return false;
        }

        final userData = userDoc.data()!;
        final userRole = userData['role'] as String?;
        final isAdmin = userRole == 'user/admin' || userRole == 'admin';
        final isSubadmin = userRole == 'user/subadmin' || userRole == 'subadmin';

        if (!isAdmin && !isSubadmin) {
          onError('Access denied. Admin or subadmin privileges required.');
          return false;
        }

        // For subadmin, check if they have set a password
        if (isSubadmin && userData['hasSetPassword'] != true) {
          onError('Please set your admin password first');
          return false;
        }

        _cachedAdminData = userData;
        _lastCacheTime = now;
      }

      final storedPassword = _cachedAdminData!['admin_pass'] as String?;

      if (storedPassword != password) {
        onError('Incorrect password');
        return false;
      }

      // Update last login timestamp in the background
      _firestore.collection('users')
          .where('role', whereIn: ['user/admin', 'admin'])
          .limit(1)
          .get()
          .then((querySnapshot) {
            if (querySnapshot.docs.isNotEmpty) {
              querySnapshot.docs.first.reference.update({
                'lastLogin': FieldValue.serverTimestamp(),
              });
            }
          });

      return true;
    } catch (e) {
      onError('An error occurred. Please try again.');
      return false;
    }
  }

  // Check if admin has pattern lock enabled
  Future<bool> hasPatternLock() async {
    try {
      // Check for both 'user/admin' and 'admin' roles
      final querySnapshot = await _firestore
          .collection('users')
          .where('role', whereIn: ['user/admin', 'admin'])
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return false;

      final adminData = querySnapshot.docs.first.data();
      return adminData['adminPatternLockEnabled'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // Show pattern lock dialog
  Future<bool> verifyPattern({
    required BuildContext context,
    required VoidCallback onSuccess,
    required Function(String) onError,
  }) async {
    // Check if pattern is locked first
    if (_isPatternLocked()) {
      final remainingTime = _patternLockUntil!.difference(DateTime.now());
      final minutes = (remainingTime.inSeconds / 60).ceil();
      onError('Pattern lock disabled. Try again in $minutes minutes.');
      return false;
    }
    
    // Success callback that handles navigation
    void successCallback() {
      // Navigate to admin dashboard immediately
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/admin/dashboard',
          (route) => false,
        );
      }
      onSuccess();
    }

    try {
      // Get admin pattern data - check for both 'user/admin' and 'admin' roles
      final querySnapshot = await _firestore
          .collection('users')
          .where('role', whereIn: ['user/admin', 'admin'])
          .limit(1)
          .get(const GetOptions(source: Source.cache));

      if (querySnapshot.docs.isEmpty) {
        onError('Admin data not found');
        return false;
      }

      final adminData = querySnapshot.docs.first.data();
      final storedPattern = List<int>.from(adminData['adminPatternLockData'] ?? []);

      if (storedPattern.isEmpty) {
        successCallback();
        return true;
      }

      bool? result = await showDialog<bool>(
        // ignore: use_build_context_synchronously
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Draw Pattern'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Draw your pattern to continue',
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
                          onInputComplete: (List<int> pattern) async {
                            if (pattern.length < 4) {
                              onError('Please connect at least 4 dots');
                              return;
                            }

                            if (_patternsMatch(pattern, storedPattern)) {
                              _failedPatternAttempts = 0;
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                                // Add a small delay to ensure the dialog is fully dismissed
                                Future.delayed(Duration(milliseconds: 200), () {
                                  successCallback();
                                });
                              }
                            } else {
                              _failedPatternAttempts++;
                              if (_failedPatternAttempts >= 3) {
                                _patternLockUntil = DateTime.now().add(const Duration(minutes: 5));
                                if (context.mounted) {
                                  Navigator.of(context).pop(false);
                                }
                                onError('Too many failed attempts. Pattern lock disabled for 5 minutes.');
                                return;
                              }
                              onError('Incorrect pattern. ${3 - _failedPatternAttempts} attempts remaining.');
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('CANCEL'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (result == true) {
        onSuccess();
        return true;
      }
      return false;
    } catch (e) {
      onError('An error occurred during pattern verification');
      return false;
    }
  }
}
