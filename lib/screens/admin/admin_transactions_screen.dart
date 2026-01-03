import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'user_transactions_screen.dart';

class CacheService {
  static const String _usersKey = 'cached_users';
  static const Duration _cacheDuration = Duration(hours: 1);

  Future<void> cacheUsers(List<Map<String, dynamic>> users) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': users,
      };
      await prefs.setString(_usersKey, jsonEncode(cacheData));
    } catch (e) {
      // Silent fail - caching is optional
    }
  }

  Future<List<Map<String, dynamic>>> getCachedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_usersKey);

      if (cachedData == null) return [];

      final decodedData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = decodedData['timestamp'] as int?;

      // Check if cache is expired
      if (timestamp == null ||
          DateTime.now().millisecondsSinceEpoch - timestamp >
              _cacheDuration.inMilliseconds) {
        return [];
      }

      final usersData = decodedData['data'] as List?;
      return usersData?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      return [];
    }
  }
}

class AdminTransactionsScreen extends StatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  State<AdminTransactionsScreen> createState() =>
      _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends State<AdminTransactionsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  Map<String, Map<String, dynamic>> _users = {};
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _filterUsers);
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = List.from(_users.values);
      });
      return;
    }

    setState(() {
      _filteredUsers = _users.values.where((user) {
        final name = user['name']?.toString().toLowerCase() ?? '';
        final email = user['email']?.toString().toLowerCase() ?? '';
        return name.contains(query) || email.contains(query);
      }).toList();
    });
  }

  Future<void> _loadUsers() async {
    try {
      // Try to load from cache first
      final cachedUsers = await _getCachedUsers();
      if (cachedUsers.isNotEmpty) {
        setState(() {
          _users = Map.fromEntries(
            cachedUsers.map((user) => MapEntry(user['id'] as String, user)),
          );
          _filteredUsers = List.from(_users.values);
          _isLoading = false;
        });
      }

      // Then load from Firestore
      final usersSnapshot = await _firestore
          .collection('users')
          .limit(20)
          .get(const GetOptions(source: Source.server));

      // Get user data
      final users = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();

      // Cache the users
      await _cacheUsers(users);

      if (mounted) {
        setState(() {
          _users = Map.fromEntries(
            users.map((user) => MapEntry(user['id'] as String, user)),
          );
          _filteredUsers = List.from(_users.values);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  // Cache methods
  Future<List<Map<String, dynamic>>> _getCachedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_users');

      if (cachedData == null) return [];

      final decodedData = jsonDecode(cachedData) as Map<String, dynamic>;
      final timestamp = decodedData['timestamp'] as int?;

      // Check if cache is expired (1 hour)
      if (timestamp == null ||
          DateTime.now().millisecondsSinceEpoch - timestamp > 3600000) {
        return [];
      }

      final usersData = decodedData['data'] as List?;
      return usersData?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<void> _cacheUsers(List<Map<String, dynamic>> users) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': users,
      };
      await prefs.setString('cached_users', jsonEncode(cacheData));
    } catch (e) {
      // Silent fail - caching is optional
    }
  }

  Widget _buildUserList() {
    if (_isLoading && _filteredUsers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredUsers.isEmpty) {
      return const Center(child: Text('No users found'));
    }

    return ListView.builder(
      itemCount: _filteredUsers.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _filteredUsers.length) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = _filteredUsers[index];
        final userName = user['name'] ?? 'User';

        return Card(
          key: ValueKey(user['id']),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                userName[0].toString().toUpperCase(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(userName),
            subtitle: Text(user['email'] ?? 'No Email'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserTransactionsScreen(
                    userId: user['id'],
                    userName: userName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }
}
