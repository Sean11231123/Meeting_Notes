import 'package:shared_preferences/shared_preferences.dart';

class GeminiModelOption {
  final String id;
  final String label;

  const GeminiModelOption(this.id, this.label);
}

class ModelSettings {
  static const _key = 'gemini_model';
  static const defaultModel = 'gemini-2.5-flash';

  static const options = [
    GeminiModelOption('gemini-2.5-flash', 'Gemini 2.5 Flash'),
    GeminiModelOption('gemini-2.5-flash-lite', 'Gemini 2.5 Flash Lite'),
    GeminiModelOption('gemini-2.0-flash', 'Gemini 2.0 Flash'),
  ];

  static Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (options.any((option) => option.id == value)) {
      return value!;
    }
    return defaultModel;
  }

  static Future<void> write(String model) async {
    if (!options.any((option) => option.id == model)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, model);
  }
}
