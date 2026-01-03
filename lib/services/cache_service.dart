import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
          DateTime.now().millisecondsSinceEpoch - timestamp > _cacheDuration.inMilliseconds) {
        return [];
      }
      
      final usersData = decodedData['data'] as List?;
      return usersData?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      return [];
    }
  }
}
