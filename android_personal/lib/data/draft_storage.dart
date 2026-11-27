import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DraftStorage {
  static const String orderDraftKey = 'sweet_studio_order_draft_v1';
  static const String recipeDraftKey = 'sweet_studio_recipe_draft_v1';
  static const String timerStateKey = 'sweet_studio_work_timer_v1';

  Future<void> saveJson(String key, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> loadJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
