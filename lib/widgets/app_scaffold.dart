import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_drawer.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showDrawer;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showDrawer = true,
  });

  @override
  Widget build(BuildContext context) {
    // Support icon with unread indicator. Tapping navigates to replies
    // screen and marks unread replies as read for the current user.
    final supportAction = Builder(
      builder: (context) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          return IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Support Replies',
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
              Navigator.pushNamed(context, '/support/replies');
            },
          );
        }

        // Fetch all replies for this user and filter unread client-side
        // to avoid composite index requirement.
        final stream = FirebaseFirestore.instance
            .collection('admin_replies')
            .where('toEmail', isEqualTo: user.email)
            .snapshots();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            // Count documents where isRead is false or missing
            final allDocs = snap.data?.docs ?? [];
            final unreadDocs = allDocs.where((doc) {
              final data = doc.data();
              final isRead = data['isRead'];
              return isRead is! bool || !isRead;
            }).toList();
            final hasUnread = unreadDocs.isNotEmpty;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.email_outlined),
                  tooltip: 'Support Replies',
                  onPressed: () async {
                    Navigator.popUntil(context, (route) => route.isFirst);

                    // Mark all unread replies as read immediately so the indicator
                    // disappears when the user navigates to the replies screen.
                    try {
                      final q = await FirebaseFirestore.instance
                          .collection('admin_replies')
                          .where('toEmail', isEqualTo: user.email)
                          .get();

                      if (q.docs.isNotEmpty) {
                        final batch = FirebaseFirestore.instance.batch();
                        for (var d in q.docs) {
                          final data = d.data();
                          final isRead = data['isRead'];
                          // Mark as read only if not already true
                          if (isRead is! bool || !isRead) {
                            batch.update(d.reference, {'isRead': true});
                          }
                        }
                        await batch.commit();
                      }
                    } catch (e) {
                      // If marking fails, still navigate — do not block user.
                      if (kDebugMode) {
                        print('Failed to mark replies as read: $e');
                      }
                    }

                    // ignore: use_build_context_synchronously
                    await Navigator.pushNamed(context, '/support/replies');
                  },
                ),

                if (hasUnread)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [...(actions ?? []), supportAction],
      ),
      drawer: showDrawer ? const AppDrawer() : null,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
