// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore: depend_on_referenced_packages, unnecessary_import
import 'package:characters/characters.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminMessagesScreen extends StatefulWidget {
  const AdminMessagesScreen({super.key});

  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isLoading = false; // show UI immediately
    _startMessagesListener();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startMessagesListener() {
    // Do NOT order by a potentially-missing server field; fetch all and sort client-side.
    _messagesSub = _firestore
        .collection('support_messages')
        .snapshots()
        .listen(
          (snapshot) {
            try {
              final list = snapshot.docs.map((d) => _mapMessageDoc(d)).toList();
              _applyMessages(list);
            } catch (e) {
              debugPrint('Error processing messages snapshot: $e');
            }
          },
          onError: (e) {
            debugPrint('Messages listener error: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error listening to messages: $e')),
              );
            }
          },
        );

    // Also fetch once as a fallback (in case listener yields empty initially)
    Future.microtask(() => _fetchOnce());
  }

  Future<void> _fetchOnce() async {
    try {
      final snap = await _firestore.collection('support_messages').get();
      final list = snap.docs.map((d) => _mapMessageDoc(d)).toList();
      if (list.isNotEmpty) _applyMessages(list);
    } catch (e) {
      debugPrint('One-time fetch failed: $e');
    }
  }

  Map<String, dynamic> _mapMessageDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    // Support several timestamp fields: timestamp, createdAt, createdAtString
    final rawTs =
        data['timestamp'] ?? data['createdAt'] ?? data['createdAtString'];
    final ts = _parseTimestamp(rawTs);

    // Support several name/email variants
    final userName =
        (data['userName'] as String?) ?? (data['name'] as String?) ?? 'Unknown';
    final userEmail =
        (data['userEmail'] as String?) ?? (data['email'] as String?) ?? '';

    final subject =
        (data['subject'] as String?) ??
        (data['title'] as String?) ??
        userName; // fallback to sender name when subject is missing

    return {
      'id': d.id,
      'userId': data['userId'] as String? ?? '',
      'userName': userName,
      'userEmail': userEmail,
      'subject': subject,
      'message': data['message'] as String? ?? '',
      'timestamp': ts,
      'isRead': data['isRead'] as bool? ?? false,
      'isResolved': data['isResolved'] as bool? ?? false,
      'adminResponse': data['adminResponse'] as String?,
      'responseTimestamp': _parseTimestamp(data['responseTimestamp']),
      'raw': data,
    };
  }

  void _applyMessages(List<Map<String, dynamic>> list) {
    // Deduplicate by id and sort descending by timestamp
    final map = <String, Map<String, dynamic>>{};
    for (final m in list) {
      map[m['id'] as String] = m;
    }
    final deduped = map.values.toList();
    deduped.sort(
      (a, b) =>
          (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime),
    );

    if (mounted) {
      setState(() {
        _messages = deduped;
      });
    }
  }

  DateTime _parseTimestamp(dynamic ts) {
    try {
      if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (ts is Timestamp) return ts.toDate();
      if (ts is DateTime) return ts;
      if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
      if (ts is String) {
        // Try parsing ISO-like strings
        return DateTime.parse(ts);
      }
    } catch (e) {
      debugPrint('Failed to parse timestamp: $e (value=$ts)');
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatDate(dynamic dt) {
    try {
      final d = dt is DateTime ? dt : _parseTimestamp(dt);
      if (d.millisecondsSinceEpoch == 0) return '-';
      return DateFormat('MMM dd, yyyy hh:mm a').format(d);
    } catch (_) {
      return '-';
    }
  }

  String _initialLetter(String? name) {
    try {
      final s = (name ?? '').trim();
      if (s.isEmpty) return '?';
      return s.characters.first.toUpperCase();
    } catch (_) {
      return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilter(_messages);
    final unreadCount = _messages.where((m) => !(m['isRead'] as bool)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('User Messages')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search messages...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedFilter == 'all',
                  selectedColor: const Color(0xFF274647),
                  labelStyle: TextStyle(
                    color: _selectedFilter == 'all' ? Colors.white : null,
                  ),
                  onSelected: (_) => setState(() => _selectedFilter = 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Unread ($unreadCount)'),
                  selected: _selectedFilter == 'unread',
                  selectedColor: const Color(0xFF274647),
                  labelStyle: TextStyle(
                    color: _selectedFilter == 'unread' ? Colors.white : null,
                  ),
                  onSelected: (_) => setState(() => _selectedFilter = 'unread'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Resolved'),
                  selected: _selectedFilter == 'resolved',
                  selectedColor: const Color(0xFF274647),
                  labelStyle: TextStyle(
                    color: _selectedFilter == 'resolved' ? Colors.white : null,
                  ),
                  onSelected: (_) =>
                      setState(() => _selectedFilter = 'resolved'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      _messages.isEmpty
                          ? 'No messages yet'
                          : 'No messages match your filter',
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final m = filtered[i];
                      final isUnread = !(m['isRead'] as bool);
                      final isResolved = (m['isResolved'] as bool);
                      final isPending =
                          ((m['raw'] as Map?)?['status'] as String?) ==
                          'pending';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (isPending || isUnread)
                                ? Colors.blue
                                : Colors.grey[300],
                            child: Text(
                              _initialLetter(m['userName'] as String?),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m['subject'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isUnread
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isResolved)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Resolved',
                                    style: TextStyle(
                                      color: Colors.green,
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
                              const SizedBox(height: 6),
                              Text(
                                m['message'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatDate(m['timestamp']),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _showMessageDetails(m),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _fetchOnce(),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> msgs) {
    var filtered = msgs;
    final q = _searchController.text.trim().toLowerCase();
    if (_selectedFilter == 'unread') {
      filtered = filtered.where((m) => !(m['isRead'] as bool)).toList();
    }
    if (_selectedFilter == 'resolved') {
      filtered = filtered.where((m) => (m['isResolved'] as bool)).toList();
    }
    if (q.isNotEmpty) {
      filtered = filtered.where((m) {
        return (m['userName'] as String).toLowerCase().contains(q) ||
            (m['userEmail'] as String).toLowerCase().contains(q) ||
            (m['subject'] as String).toLowerCase().contains(q) ||
            (m['message'] as String).toLowerCase().contains(q);
      }).toList();
    }
    return filtered;
  }

  // ignore: unused_element
  Future<void> _markMessageAsRead(String messageId) async {
    try {
      await _firestore.collection('support_messages').doc(messageId).update({
        'isRead': true,
      });
      debugPrint('Message $messageId marked as read');
      // Refresh the messages list
      _fetchOnce();
    } catch (e) {
      debugPrint('Failed to mark message as read: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _firestore.collection('support_messages').doc(messageId).delete();
      debugPrint('Message $messageId deleted');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted successfully'),
            backgroundColor: Color(0xFF274647),
          ),
        );
      }
      // Refresh the messages list
      _fetchOnce();
    } catch (e) {
      debugPrint('Failed to delete message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showMessageDetails(Map<String, dynamic> m) async {
    // Do not mark read on open; admin must click REPLY to mark as read.

    // Start a timer: if admin does not click REPLY within 1 minute,
    // set 'status' => 'pending' on the message, unless isRead is true.
    Timer? pendingTimer;
    var replied = false;

    pendingTimer = Timer(const Duration(seconds: 20), () async {
      if (replied) return;
      try {
        final doc = await _firestore
            .collection('support_messages')
            .doc(m['id'] as String)
            .get();
        final isReadRemote = doc.data()?['isRead'] as bool? ?? false;
        if (!isReadRemote) {
          await _firestore
              .collection('support_messages')
              .doc(m['id'] as String)
              .update({'status': 'pending'});
          debugPrint('Auto-marked message ${m['id']} as pending after timeout');
        }
      } catch (e) {
        debugPrint('Failed to auto-mark pending: $e');
      }
    });

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(m['subject'] as String),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From: ${m['userName']} <${m['userEmail']}>'),
              const SizedBox(height: 8),
              Text('Message:'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(m['message'] as String),
              ),
              const SizedBox(height: 12),
              if (m['adminResponse'] != null) ...[
                const Divider(),
                const SizedBox(height: 8),
                Text('Admin Response:'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(m['adminResponse'] as String),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Open reply input dialog
              final TextEditingController replyController =
                  TextEditingController();

              final send = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('Reply to user'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('To: ${(m['userEmail'] as String?) ?? ''}'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: replyController,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText: 'Type your reply here...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('CANCEL'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      child: const Text('SEND'),
                    ),
                  ],
                ),
              );

              if (send != true) return;

              final replyText = replyController.text.trim();
              if (replyText.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reply cannot be empty')),
                  );
                }
                return;
              }

              // Prevent auto-pending and mark replied
              replied = true;
              pendingTimer?.cancel();

              // Close the message details dialog
              if (mounted) Navigator.pop(context);

              final to = (m['userEmail'] as String?) ?? '';
              if (to.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No recipient email available'),
                    ),
                  );
                }
                return;
              }

              // Save reply to Firestore collection 'admin_replies'
              try {
                final currentUser = _auth.currentUser;
                final replyDoc = {
                  'supportMessageId': m['id'],
                  'toEmail': to,
                  'fromEmail': 'moneymint.care@gmail.com',
                  'subject': 'Support_Feedback',
                  'body': replyText,
                  'replyBy': currentUser?.displayName ?? 'Admin',
                  'replyByEmail': currentUser?.email ?? '',
                  'isRead': false,
                  'createdAt': FieldValue.serverTimestamp(),
                };

                await _firestore.collection('admin_replies').add(replyDoc);

                // Update the original support message with reply metadata
                await _firestore
                    .collection('support_messages')
                    .doc(m['id'] as String)
                    .update({
                      'adminResponse': replyText,
                      'responseTimestamp': FieldValue.serverTimestamp(),
                      'isReplied': true,
                      'isRead': true,
                      'lastReplyTime': FieldValue.serverTimestamp(),
                      'lastReplyBy': currentUser?.displayName ?? 'Admin',
                      'lastReplyEmail': currentUser?.email ?? '',
                    });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reply saved and opening mail client'),
                      backgroundColor: Color(0xFF274647),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Failed to save reply: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save reply: $e')),
                  );
                }
              }

              // Compose mailto body per requested format
              final body = StringBuffer()
                ..writeln('From : moneymint.care@gmail.com')
                ..writeln('To : $to')
                ..writeln('Subject : Support_Feedback')
                ..writeln()
                ..writeln('Dear customer,')
                ..writeln('   $replyText');

              final uri = Uri(
                scheme: 'mailto',
                path: to,
                queryParameters: {
                  'subject': 'Support_Feedback',
                  'body': body.toString(),
                },
              );

              try {
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );

                if (launched) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Reply saved — mail client opened'),
                        backgroundColor: Color(0xFF274647),
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open mail client'),
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint('Failed to launch mailto: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to open mail client')),
                  );
                }
              }
            },
            child: const Text('REPLY'),
          ),
          TextButton(
            onPressed: () async {
              // Show confirmation dialog
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Message'),
                  content: const Text(
                    'Are you sure you want to delete this message? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'DELETE',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                // cancel pending timer and prevent auto-pending
                replied = true;
                pendingTimer?.cancel();
                if (mounted) {
                  Navigator.pop(context); // Close message details dialog
                }
                await _deleteMessage(m['id'] as String);
              }
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              // cancel pending timer when closing dialog
              replied = true;
              pendingTimer?.cancel();
              Navigator.pop(context);
            },
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
    // ensure timer is cleaned up if dialog is dismissed without using actions
    pendingTimer.cancel();
  }
}
