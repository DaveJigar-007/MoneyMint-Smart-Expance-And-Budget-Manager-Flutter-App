// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminUsersScreen extends StatefulWidget {
  final bool showOnlySubAdmins;
  const AdminUsersScreen({super.key, this.showOnlySubAdmins = false});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _currentUserRole;

  // Check if current user is a subadmin
  bool _isCurrentUserSubadmin() {
    return _currentUserRole == 'user/subadmin' || _currentUserRole == 'subadmin';
  }

  // Check if current user is an admin
  bool _isCurrentUserAdmin() {
    return _currentUserRole == 'user/admin' || _currentUserRole == 'admin';
  }

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;

  void _filterUsers(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = List.from(_users);
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredUsers = _users.where((user) {
        final name = user['name']?.toString().toLowerCase() ?? '';
        final email = user['email']?.toString().toLowerCase() ?? '';
        final phone =
            user['phoneNumber']?.toString() ?? user['mobile']?.toString() ?? '';

        return name.contains(lowerQuery) ||
            email.contains(lowerQuery) ||
            phone.contains(query); // Keep phone search case-sensitive
      }).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(() {
      _filterUsers(_searchController.text);
    });
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get current user role first
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
        if (userDoc.exists) {
          _currentUserRole = userDoc.data()?['role'];
        }
      }

      // If current user is not an admin or subadmin, redirect
      if (!_isCurrentUserAdmin() && !_isCurrentUserSubadmin()) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
        return;
      }

      Query<Map<String, dynamic>> query = _firestore.collection('users');

      // Handle user type filtering based on the screen context
      if (widget.showOnlySubAdmins) {
        // Show only subadmins
        query = query.where('role', isEqualTo: 'user/subadmin');
      } else if (_isCurrentUserAdmin()) {
        // Admins can see regular users (not subadmins, not other admins)
        query = query.where('role', isEqualTo: 'user');
      } else if (_isCurrentUserSubadmin()) {
        // Subadmins can only see regular users
        query = query.where('role', isEqualTo: 'user');
      }

      // Listen to realtime updates so UI reflects changes immediately
      _usersSub?.cancel();
      _usersSub = query.snapshots().listen(
        (usersSnapshot) {
          final currentUserId = _auth.currentUser?.uid;
          final users = usersSnapshot.docs
              .where((doc) => doc.id != currentUserId)
              .map<Map<String, dynamic>>(
                (doc) => {
                  'id': doc.id,
                  ...?doc.data() as Map<String, dynamic>?,
                },
              )
              .toList();

          if (!mounted) return;
          setState(() {
            _users = users;
            _filteredUsers = List.from(users);
            _isLoading = false;
          });
        },
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
            setState(() => _isLoading = false);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleUserStatus(String userId, bool isBlocked) async {
    // Only allow admins to block/unblock users
    if (!_isCurrentUserAdmin()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only admins can block/unblock users'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Additional security check
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userRole = userDoc.data()?['role'] as String?;
        // Allow blocking sub-admins but not other admins
        if (userRole == 'user/admin' || userRole == 'admin') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot modify admin accounts'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      await _firestore.collection('users').doc(userId).update({
        'isBlocked': !isBlocked,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          final userIndex = _users.indexWhere((user) => user['id'] == userId);
          if (userIndex != -1) {
            _users[userIndex]['isBlocked'] = !isBlocked;
            _filterUsers(_searchController.text);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isBlocked ? 'User has been unblocked' : 'User has been blocked',
            ),
            backgroundColor: const Color(0xFF274647),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating user status: $e')),
        );
      }
    }
  }

  Future<void> _promoteToSubadmin(String userId, String userName) async {
    // Only allow admins to promote users to sub-admin
    if (!_isCurrentUserAdmin()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only admins can promote users to sub-admin'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      await _firestore.collection('users').doc(userId).update({
        'role': 'user/subadmin',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          final userIndex = _users.indexWhere((user) => user['id'] == userId);
          if (userIndex != -1) {
            _users[userIndex]['role'] = 'user/subadmin';
            _filterUsers(_searchController.text);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User has been promoted to Sub-Admin'),
            backgroundColor: Color(0xFF274647),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error promoting user: $e')));
      }
    }
  }

  Future<void> _removeSubadmin(String userId, String userName) async {
    // Only allow admins to remove subadmin status
    if (!_isCurrentUserAdmin()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only admins can remove Sub-Admin status'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Confirmation dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Sub-Admin'),
        content: Text('Remove Sub-Admin status from $userName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performRemoveSubadmin(userId, userName);
            },
            child: const Text('REMOVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRemoveSubadmin(String userId, String userName) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'role': 'user',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          final userIndex = _users.indexWhere((user) => user['id'] == userId);
          if (userIndex != -1) {
            _users[userIndex]['role'] = 'user';
            _filterUsers(_searchController.text);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sub-Admin status has been removed'),
            backgroundColor: Color(0xFF274647),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error removing Sub-Admin: $e')));
      }
    }
  }

  Future<void> _deleteUserAccount(String userId, String userName) async {
    // Only allow admins to delete users
    if (!_isCurrentUserAdmin()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only admins can delete user accounts'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Additional security check
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userRole = userDoc.data()?['role'] as String?;
        // Allow deleting sub-admins but not other admins
        if (userRole == 'user/admin' || userRole == 'admin') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot delete admin accounts'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error verifying user permissions'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User Account'),
        content: Text(
          'Are you sure you want to delete $userName\'s account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Try to delete the user from Firebase Auth if it's the current user
      final currentUser = _auth.currentUser;
      if (currentUser?.uid == userId) {
        await currentUser?.delete();
      } else {
        // For non-current users: copy the user doc into `deletedUsers` with a flag
        // so a server-side admin process (Cloud Function / admin SDK) can remove
        // the Authentication record. Then delete the original users doc so UI updates in real-time.
        final userDocSnap = await _firestore
            .collection('users')
            .doc(userId)
            .get();
        if (userDocSnap.exists) {
          final data = userDocSnap.data() ?? {};
          final deletedData = {
            ...data,
            'deletedAt': FieldValue.serverTimestamp(),
            'deletedBy': currentUser?.uid,
            'markedForAuthDeletion': true,
          };
          // write to deletedUsers collection with same id
          await _firestore
              .collection('deletedUsers')
              .doc(userId)
              .set(deletedData);
        }
        // remove from users collection (this triggers realtime UI update)
        await _firestore.collection('users').doc(userId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'User removed. Authentication deletion queued for server-side processing.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _users.removeWhere((user) => user['id'] == userId);
          _filteredUsers.removeWhere((user) => user['id'] == userId);
        });

        // Close the bottom sheet if it's open
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User has been removed from the system'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting user account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildUserAvatar(Map<String, dynamic> user) {
    final base64Image = user['profileImageBase64'] as String?;

    if (base64Image?.isNotEmpty ?? false) {
      try {
        return CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFF274647).withOpacity(0.1),
          child: ClipOval(
            child: Image.memory(
              base64Decode(base64Image!),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildDefaultAvatar(),
            ),
          ),
        );
      } catch (e) {
        debugPrint('Error decoding base64 image: $e');
        return _buildDefaultAvatar();
      }
    }

    return _buildDefaultAvatar();
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF274647).withOpacity(0.1),
      child: const Icon(Icons.person, size: 24, color: Color(0xFF274647)),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String? value, {
    bool isStatus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value ?? 'Not provided',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isStatus 
                    ? (value == 'Active' ? Colors.green : Colors.red)
                    : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserDetails(Map<String, dynamic> user) {
    final isBlocked = user['isBlocked'] == true;
    final createdAt = user['createdAt'] != null
        ? (user['createdAt'] as Timestamp).toDate()
        : null;
    final lastLogin = user['lastLogin'] != null
        ? (user['lastLogin'] as Timestamp).toDate()
        : null;
    final userRole = user['role'] as String?;
    final isAdmin = userRole == 'user/admin' || userRole == 'admin';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // User avatar and name
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF2D5A3D).withOpacity(0.1),
                child: _buildUserAvatar(user),
              ),
              const SizedBox(height: 16),
              Text(
                user['name'] ?? 'No Name',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user['email'] ?? 'No Email',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 20),

              // User details section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      Icons.phone,
                      'Mobile Number',
                      user['phoneNumber'] ?? user['mobile'] ?? 'Not provided',
                    ),
                    _buildDetailRow(
                      Icons.calendar_today,
                      'Joined On',
                      createdAt != null
                          ? _formatDateTime(createdAt)
                          : 'N/A',
                    ),
                    if (lastLogin != null)
                      _buildDetailRow(
                        Icons.login,
                        'Last Login',
                        '${_formatTimeAgo(lastLogin)} (${_formatDateTime(lastLogin)})',
                      ),
                    _buildDetailRow(
                      Icons.account_circle,
                      'Status',
                      isBlocked ? 'Blocked' : 'Active',
                      isStatus: true,
                    ),
                    if (userRole != null)
                      _buildDetailRow(
                        Icons.security,
                        'Role',
                        userRole.toUpperCase().replaceAll('USER/', ''),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Show action buttons based on current user's role
              if (_isCurrentUserAdmin())
                Column(
                  children: [
                    // Block/Unblock button for admin
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _toggleUserStatus(user['id'], isBlocked);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isBlocked
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFE53935),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          isBlocked ? 'Unblock User' : 'Block User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Delete Account button for admin (only for non-admin users)
                    if (!isAdmin)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteUserAccount(
                              user['id'],
                              user['name'] ?? 'the user',
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFEBEE),
                            foregroundColor: const Color(0xFFE53935),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.red[300]!),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_outline, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Delete Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),
                  ],
                )
              else
                const SizedBox.shrink(), // Hide action buttons for non-admin users
              // Add some spacing before the close button if no action buttons are shown
              if (!_isCurrentUserAdmin()) const SizedBox(height: 20),

              // Close button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFF274647)),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Color(0xFF274647),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Add bottom padding for better scrolling on smaller devices
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.showOnlySubAdmins ? 'Manage Sub-Admins' : 'Manage Users',
        ),
        backgroundColor: const Color(0xFF274647),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Color(0xFF274647)),
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or phone',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF274647),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            _filterUsers('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                ),
              ),
            ),
          ),
          // User list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'No users found'
                          : 'No users match your search',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isBlocked = user['isBlocked'] == true;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _showUserDetails(user),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: _buildUserAvatar(user),
                            title: Text(
                              user['name'] ?? 'No Name',
                              style: TextStyle(
                                color: isBlocked
                                    ? Colors.grey
                                    : const Color(0xFF274647),
                                fontWeight: FontWeight.w500,
                                decoration: isBlocked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['email'] ?? 'No email',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (user['role'] == 'user/subadmin')
                                  const Text(
                                    'Sub-Admin',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (user['role'] == 'user/admin' || user['role'] == 'admin')
                                  const Text(
                                    'Admin',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (user['role'] != 'user/subadmin' &&
                                    user['role'] != 'user/admin' &&
                                    user['role'] != 'subadmin' &&
                                    user['role'] != 'admin' &&
                                    _isCurrentUserAdmin())
                                  IconButton(
                                    icon: const Icon(
                                      Icons.person_add_alt_1,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'Promote to Sub-Admin',
                                    onPressed: () => _promoteToSubadmin(
                                      user['id'],
                                      user['name'] ?? 'User',
                                    ),
                                  ),
                                if (user['role'] == 'user/subadmin' &&
                                    _isCurrentUserAdmin())
                                  IconButton(
                                    icon: const Icon(
                                      Icons.person_remove_alt_1,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Remove Sub-Admin',
                                    onPressed: () => _removeSubadmin(
                                      user['id'],
                                      user['name'] ?? 'User',
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                isBlocked
                                    ? _isCurrentUserAdmin() &&
                                              user['role'] != 'user/admin' &&
                                              user['role'] != 'admin'
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.block,
                                                color: Colors.red,
                                                size: 24,
                                              ),
                                              tooltip:
                                                  'User is blocked - Click to unblock',
                                              onPressed: () =>
                                                  _toggleUserStatus(
                                                    user['id'],
                                                    true,
                                                  ),
                                            )
                                          : const Icon(
                                              Icons.block,
                                              color: Colors.grey,
                                              size: 24,
                                            )
                                    : _isCurrentUserAdmin() &&
                                          user['role'] != 'user/admin' &&
                                          user['role'] != 'admin'
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.lock_open,
                                          color: Colors.green,
                                          size: 24,
                                        ),
                                        tooltip:
                                            'User is active - Click to block',
                                        onPressed: () => _toggleUserStatus(
                                          user['id'],
                                          false,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.lock_open,
                                        color: Colors.grey,
                                        size: 24,
                                      ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
