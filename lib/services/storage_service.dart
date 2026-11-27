import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class StorageService {
  static const String _storageKey = 'medquiz_studio_v3';

  static Future<AppDataState> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return AppDataState();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppDataState.fromJson(decoded);
      }
    } catch (_) {}
    return AppDataState();
  }

  static Future<void> saveState(AppDataState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, state.toJsonString());
    } catch (_) {}
  }

  static String buildBackupJson(AppDataState state) {
    final payload = {
      'app': 'Batch 27 MCQ Studio',
      'version': '6.0.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'data': state.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
