import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeyStorage {
  static const _key = 'gemini_api_key';
  static const _secureStorage = FlutterSecureStorage();

  static Future<String?> read() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } else {
      return await _secureStorage.read(key: _key);
    }
  }

  static Future<void> write(String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value);
    } else {
      await _secureStorage.write(key: _key, value: value);
    }
  }

  static Future<void> delete() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } else {
      await _secureStorage.delete(key: _key);
    }
  }
}
