import 'package:shared_preferences/shared_preferences.dart';

/// Hardcoded fallback 清單：當 API 無法取得模型時使用
/// 只需維護「當下確定可用」的最小集合
const List<String> kFallbackModelIds = [
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
];

const String kDefaultModelId = 'gemini-2.5-flash';

class ModelSettings {
  static const _key = 'gemini_model';

  static Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? kDefaultModelId;
  }

  static Future<void> write(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, modelId);
  }
}
