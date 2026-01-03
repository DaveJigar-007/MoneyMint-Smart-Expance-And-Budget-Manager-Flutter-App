// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_users_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_transactions_screen.dart';
import 'admin_messages_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _adminData;
  bool _isLoading = true;
  int _totalUsers = 0;
  int _dailyActiveUsers = 0;
  int _pendingMessages = 0;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    // Set loading to false immediately for instant UI display
    _isLoading = false;
    // Load all data in background without blocking UI
    _loadAdminDataBackground();
    _fetchTotalUsersBackground();
    _fetchPendingMessagesBackground();
    _fetchDailyActiveUsersBackground();
  }

  Future<void> _fetchPendingMessagesBackground() async {
    Future.microtask(() async {
      try {
        final snapshot = await _firestore
            .collection('support_messages')
            .where('isRead', isEqualTo: false)
            .get()
            .timeout(const Duration(seconds: 5));

        if (mounted) {
          setState(() {
            _pendingMessages = snapshot.size;
          });
        }
      } catch (e) {
        // Silent fail; show a snackbar only if mounted and helpful
        debugPrint('Failed to fetch pending messages: $e');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh active users count when the screen is focused
    _fetchDailyActiveUsers();
  }

  Future<void> _fetchTotalUsersBackground() async {
    // Fetch total users in background non-blocking
    Future.microtask(() async {
      try {
        final usersSnapshot = await _firestore
            .collection('users')
            .get()
            .timeout(const Duration(seconds: 5));
        if (mounted) {
          setState(() {
            _totalUsers = usersSnapshot.size;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to fetch user count')),
          );
        }
      }
    });
  }

  Future<void> _fetchDailyActiveUsersBackground() async {
    // Fetch daily active users in background non-blocking
    Future.microtask(() async {
      try {
        final now = DateTime.now();
        final startOfDay = DateTime(now.year, now.month, now.day);

        // Query the 'user_activity' collection for today's activities
        final activitySnapshot = await _firestore
            .collection('user_activity')
            .where('lastActive', isGreaterThanOrEqualTo: startOfDay)
            .get()
            .timeout(const Duration(seconds: 5));

        // Get unique user IDs to count distinct users
        final uniqueUserIds = activitySnapshot.docs
            .map((doc) => doc.id)
            .toSet()
            .toList();

        if (mounted) {
          setState(() {
            _dailyActiveUsers = uniqueUserIds.length;
          });
        }

        // Calculate time until midnight
        final nextMidnight = startOfDay.add(const Duration(days: 1));
        final timeUntilMidnight = nextMidnight.difference(now);

        // Schedule next refresh: either at midnight or after 5 minutes, whichever comes first
        final refreshDuration = timeUntilMidnight.inMinutes > 5
            ? const Duration(minutes: 5)
            : timeUntilMidnight + const Duration(seconds: 1);

        if (mounted) {
          Future.delayed(refreshDuration, () {
            if (mounted) {
              _fetchDailyActiveUsersBackground();
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to fetch daily active users')),
          );
        }
      }
    });
  }

  Future<void> _fetchDailyActiveUsers() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      // Query the 'user_activity' collection for today's activities
      final activitySnapshot = await _firestore
          .collection('user_activity')
          .where('lastActive', isGreaterThanOrEqualTo: startOfDay)
          .get();

      // Get unique user IDs to count distinct users
      final uniqueUserIds = activitySnapshot.docs
          .map((doc) => doc.id)
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          _dailyActiveUsers = uniqueUserIds.length;
        });
      }

      // Calculate time until midnight
      final nextMidnight = startOfDay.add(const Duration(days: 1));
      final timeUntilMidnight = nextMidnight.difference(now);

      // Schedule next refresh: either at midnight or after 5 minutes, whichever comes first
      final refreshDuration = timeUntilMidnight.inMinutes > 5
          ? const Duration(minutes: 5)
          : timeUntilMidnight + const Duration(seconds: 1);

      if (mounted) {
        Future.delayed(refreshDuration, () {
          if (mounted) {
            _fetchDailyActiveUsers();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch daily active users')),
        );
      }
    }
  }

  Future<void> _loadAdminDataBackground() async {
    // Load admin data in background non-blocking
    Future.microtask(() async {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/admin/login');
        }
        return;
      }

      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5));

        if (!mounted) return;

        final userRole = userDoc.data()?['role'];
        if (!userDoc.exists ||
            (userRole != 'user/admin' && userRole != 'admin' && 
             userRole != 'user/subadmin' && userRole != 'subadmin')) {
          await _auth.signOut();
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/admin/login');
          }
          return;
        }

        if (mounted) {
          setState(() {
            _adminData = userDoc.data();
            _userRole = userRole;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading admin data: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC9D6D9),
      appBar: AppBar(
        title: Text(
          (_userRole == 'user/admin' || _userRole == 'admin') ? 'Admin Dashboard' : 'Sub-Admin Dashboard',
        ),
        backgroundColor: const Color(0xFF274647),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
          tooltip: 'Back to Home',
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Admin info card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildAdminAvatar(),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _adminData?['name'] ?? 'Admin',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _adminData?['email'] ?? '',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text(
                            'Admin Privileges',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_userRole == 'user/admin' || _userRole == 'admin') ...[
                            _buildStatCard(
                              'User Messages',
                              Icons.mail_outline,
                              badgeCount: _pendingMessages,
                              showDot: _pendingMessages > 0,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminMessagesScreen(),
                                  ),
                                );
                                // Refresh pending count after returning from messages
                                if (mounted) _fetchPendingMessagesBackground();
                              },
                            ),
                            _buildStatCard(
                              'Admin Replies',
                              Icons.reply_all,
                              onTap: () {
                                Navigator.pushNamed(context, '/admin/replies');
                              },
                            ),
                            _buildStatCard(
                              'View All Transactions',
                              Icons.receipt_long,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminTransactionsScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildStatCard(
                              'System Settings',
                              Icons.settings,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminSettingsScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildStatCard(
                              'Manage Sub-Admins',
                              Icons.admin_panel_settings,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminUsersScreen(
                                          showOnlySubAdmins: true,
                                        ),
                                  ),
                                );
                              },
                            ),
                            _buildStatCard(
                              'Manage Users',
                              Icons.people_outline,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminUsersScreen(
                                          showOnlySubAdmins: false,
                                        ),
                                  ),
                                );
                              },
                            ),
                          ] else ...[
                            _buildStatCard(
                              'View Users',
                              Icons.people_outline,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminUsersScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildStatCard(
                              'User Messages',
                              Icons.mail_outline,
                              badgeCount: _pendingMessages,
                              showDot: _pendingMessages > 0,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminMessagesScreen(),
                                  ),
                                );
                                // Refresh pending count after returning from messages
                                if (mounted) _fetchPendingMessagesBackground();
                              },
                            ),
                            _buildStatCard(
                              'Admin Replies',
                              Icons.reply_all,
                              onTap: () {
                                Navigator.pushNamed(context, '/admin/replies');
                              },
                            ),
                            _buildStatCard(
                              'View Transactions',
                              Icons.receipt_long_outlined,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminTransactionsScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Smart Board section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          'Smart Board',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF274647),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isSmallScreen = constraints.maxWidth < 400;
                            final cardSpacing = isSmallScreen ? 12.0 : 16.0;

                            return Row(
                              children: [
                                // First card with right margin - Total Users
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: cardSpacing / 2,
                                    ),
                                    child: _buildStatBox(
                                      'Total Users',
                                      _totalUsers.toString(),
                                      Icons.people_outline,
                                      const Color(0xFF2196F3), // Blue
                                      isSubadmin: _userRole == 'user/subadmin',
                                    ),
                                  ),
                                ),
                                // Second card with left margin - Active Today
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: cardSpacing / 2,
                                    ),
                                    child: _buildStatBox(
                                      'Active Today',
                                      _dailyActiveUsers.toString(),
                                      Icons.trending_up,
                                      const Color(0xFF4CAF50), // Green
                                      isSubadmin: _userRole == 'user/subadmin',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatBox(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isSubadmin = false,
  }) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isSubadmin
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSubadmin ? Colors.grey[700] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSubadmin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Sub-Admin',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: isSubadmin
                          ? FontWeight.w800
                          : FontWeight.bold,
                      color: isSubadmin
                          ? const Color(0xFF274647)
                          : Colors.black87,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: isSubadmin ? color.withOpacity(0.8) : color,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminAvatar() {
    // Check for base64 image first (same as app drawer)
    if (_adminData?['profileImageBase64'] != null) {
      return _buildBase64Avatar(_adminData!['profileImageBase64']);
    }

    // Then check for local path or photoURL (same as app drawer)
    final imagePath =
        _adminData?['profileImageLocalPath'] ?? _adminData?['photoURL'];

    if (imagePath != null) {
      if (imagePath.toString().startsWith('http')) {
        return _buildNetworkAvatar(imagePath);
      } else {
        return _buildLocalAvatar(imagePath);
      }
    }

    // Default avatar if no image is available
    return _buildDefaultAvatar();
  }

  Widget _buildBase64Avatar(String base64Image) {
    try {
      return CircleAvatar(
        radius: 30,
        backgroundColor: const Color(0xFF274647).withOpacity(0.1),
        child: ClipOval(
          child: Image.memory(
            base64Decode(
              base64Image.contains(',')
                  ? base64Image.split(',').last
                  : base64Image,
            ),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return _buildDefaultAvatar();
    }
  }

  Widget _buildNetworkAvatar(String imageUrl) {
    try {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null ||
          !(uri.isAbsolute) ||
          !(uri.scheme == 'http' || uri.scheme == 'https')) {
        return _buildDefaultAvatar();
      }

      return CircleAvatar(
        radius: 30,
        backgroundColor: const Color(0xFF274647).withOpacity(0.1),
        child: ClipOval(
          child: Image.network(
            imageUrl,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildDefaultAvatar();
            },
            errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Network avatar error: $e');
      return _buildDefaultAvatar();
    }
  }

  Widget _buildLocalAvatar(String imagePath) {
    return CircleAvatar(
      radius: 30,
      backgroundColor: const Color(0xFF274647).withOpacity(0.1),
      child: FutureBuilder<bool>(
        future: _fileExists(imagePath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildDefaultAvatar();
          }

          if (snapshot.data == true) {
            try {
              return ClipOval(
                child: Image.file(
                  File(imagePath),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildDefaultAvatar(),
                ),
              );
            } catch (e) {
              debugPrint('Local avatar load error: $e');
              return _buildDefaultAvatar();
            }
          }

          return _buildDefaultAvatar();
        },
      ),
    );
  }

  Future<bool> _fileExists(String path) async {
    try {
      if (path.isEmpty) return false;
      final f = File(path);
      return await f.exists();
    } catch (e) {
      debugPrint('File exists check failed for $path: $e');
      return false;
    }
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      radius: 30,
      backgroundColor: const Color(0xFF274647).withOpacity(0.1),
      child: const Icon(
        Icons.admin_panel_settings,
        size: 32,
        color: Color(0xFF274647),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    IconData icon, {
    VoidCallback? onTap,
    int? badgeCount,
    bool showDot = false,
  }) {
    final hasUnread = (badgeCount != null && badgeCount > 0) || showDot;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D5A3D).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF2D5A3D)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: (badgeCount != null && badgeCount > 0)
          ? Text(
              '$badgeCount pending',
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasUnread) ...[
            // Show red dot with optional count badge
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: badgeCount != null && badgeCount > 0
                    ? Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    );
  }
}
