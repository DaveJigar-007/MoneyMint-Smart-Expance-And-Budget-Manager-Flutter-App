import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminRepliesScreen extends StatefulWidget {
  const AdminRepliesScreen({super.key});

  @override
  State<AdminRepliesScreen> createState() => _AdminRepliesScreenState();
}

class _AdminRepliesScreenState extends State<AdminRepliesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _repliesStream;
  final String _selectedFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupStream();
  }

  void _setupStream() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = 'User not authenticated. Please log in again.';
        });
        return;
      }

      setState(() {
        _errorMessage = null;
        _isLoading = true;
      });
      
      _repliesStream = _firestore
          .collection('admin_replies')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .handleError((error) {
        setState(() {
          _errorMessage = _getErrorMessage(error);
          _isLoading = false;
        });
      });
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to setup stream: $e';
        _isLoading = false;
      });
    }
  }

  void _refreshData() {
    _setupStream();
  }

  String _getErrorMessage(dynamic error) {
    if (error.toString().contains('permission-denied')) {
      return 'Permission denied. You need admin privileges to access this data.';
    } else if (error.toString().contains('unavailable')) {
      return 'Service temporarily unavailable. Please try again.';
    } else if (error.toString().contains('not-found')) {
      return 'No admin replies found.';
    } else {
      return 'An error occurred: ${error.toString()}';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic timestamp) {
    try {
      DateTime dt;
      if (timestamp is Timestamp) {
        dt = timestamp.toDate();
      } else if (timestamp is DateTime) {
        dt = timestamp;
      } else {
        return '-';
      }
      return DateFormat('MMM dd, yyyy hh:mm a').format(dt);
    } catch (_) {
      return '-';
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _searchController.text.trim().toLowerCase();
    var filtered = docs;

    if (_selectedFilter == 'read') {
      filtered = filtered
          .where((d) => (d.data()['isRead'] as bool?) == true)
          .toList();
    } else if (_selectedFilter == 'unread') {
      filtered = filtered
          .where((d) => (d.data()['isRead'] as bool?) != true)
          .toList();
    }

    if (q.isNotEmpty) {
      filtered = filtered.where((d) {
        final data = d.data();
        final toEmail = (data['toEmail'] as String?) ?? '';
        final subject = (data['subject'] as String?) ?? '';
        final body = (data['body'] as String?) ?? '';
        final replyBy = (data['replyBy'] as String?) ?? '';

        return toEmail.toLowerCase().contains(q) ||
            subject.toLowerCase().contains(q) ||
            body.toLowerCase().contains(q) ||
            replyBy.toLowerCase().contains(q);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Replies'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              _refreshData();
            },
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search replies...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _repliesStream,
              builder: (context, snap) {
                if (_errorMessage != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            _refreshData();
                          },
                          child: _isLoading 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getErrorMessage(snap.error),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            _refreshData();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final allDocs = snap.data?.docs ?? [];
                final filtered = _applyFilter(allDocs);

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      allDocs.isEmpty
                          ? 'No replies sent yet'
                          : 'No replies match your filter',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data();

                    final toEmail = data['toEmail'] as String? ?? '';
                    final subject = data['subject'] as String? ?? '';
                    final body = data['body'] as String? ?? '';
                    final replyBy = data['replyBy'] as String? ?? 'Admin';
                    final createdAt = data['createdAt'];
                    final isRead = (data['isRead'] as bool?) == true;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? Colors.grey[300]
                              : Colors.blue,
                          child: Text(
                            (replyBy.isNotEmpty ? replyBy[0] : '?')
                                .toUpperCase(),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'To: $toEmail',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'By: $replyBy',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isRead)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Unread',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              subject.isNotEmpty
                                  ? 'Subject: $subject'
                                  : 'No subject',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sent: ${_formatDate(createdAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          // Show detailed reply dialog
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Reply Details'),
                              content: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('To: $toEmail'),
                                    const SizedBox(height: 8),
                                    Text('Sent by: $replyBy'),
                                    const SizedBox(height: 8),
                                    Text('Subject: $subject'),
                                    const SizedBox(height: 12),
                                    const Text('Message:'),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(body),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Sent: ${_formatDate(createdAt)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('CLOSE'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
