import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RepliesScreen extends StatelessWidget {
  const RepliesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email;

    if (userEmail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support Replies')),
        body: const Center(child: Text('Please sign in to view replies')),
      );
    }

    // Avoid requiring a Firestore composite index by not ordering server-side.
    // We fetch a small set and pick the latest reply locally.
    final stream = FirebaseFirestore.instance
        .collection('admin_replies')
        .where('toEmail', isEqualTo: userEmail)
        .limit(10)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Support Replies')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No replies'));

          // Sort locally by `createdAt` (descending) to pick the most recent reply.
          docs.sort((a, b) {
            final aCreated = a.data()['createdAt'];
            final bCreated = b.data()['createdAt'];

            DateTime aDt;
            DateTime bDt;

            if (aCreated is Timestamp) {
              aDt = aCreated.toDate();
            } else if (aCreated is DateTime) {
              aDt = aCreated;
            } else {
              aDt = DateTime.fromMillisecondsSinceEpoch(0);
            }

            if (bCreated is Timestamp) {
              bDt = bCreated.toDate();
            } else if (bCreated is DateTime) {
              bDt = bCreated;
            } else {
              bDt = DateTime.fromMillisecondsSinceEpoch(0);
            }

            return bDt.compareTo(aDt);
          });

          final d = docs.first.data();
          final body = d['body'] as String? ?? '';
          final subject = d['subject'] as String? ?? '';
          final from = d['fromEmail'] as String? ?? '';
          final created = d['createdAt'];
          DateTime when;
          if (created is Timestamp) {
            when = created.toDate();
          } else if (created is DateTime)
            // ignore: curly_braces_in_flow_control_structures
            when = created;
          else
            // ignore: curly_braces_in_flow_control_structures
            when = DateTime.now();

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'From: $from',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Subject: $subject',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(body),
                    const SizedBox(height: 12),
                    Text(
                      'Received: ${when.toString()}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
