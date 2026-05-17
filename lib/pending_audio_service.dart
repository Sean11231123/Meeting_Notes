import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class PendingAudio {
  final String source;
  final String fileName;
  final String mimeType;
  final String? path;
  final Uint8List? bytes;
  final DateTime createdAt;

  const PendingAudio({
    required this.source,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
    this.path,
    this.bytes,
  });

  bool get isWebBytes => source == 'web_bytes';
}

class PendingAudioService {
  static const _metaKey = 'pending_audio_meta';
  static const _bytesKey = 'pending_audio_bytes';
  static const maxStoredWebBytes = 5 * 1024 * 1024;

  static Future<PendingAudio?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw == null) return null;

    final meta = jsonDecode(raw) as Map<String, dynamic>;
    Uint8List? bytes;
    if (meta['source'] == 'web_bytes') {
      final encoded = prefs.getString(_bytesKey);
      if (encoded == null) return null;
      bytes = base64Decode(encoded);
    }

    return PendingAudio(
      source: meta['source'] as String,
      fileName: meta['fileName'] as String,
      mimeType: meta['mimeType'] as String,
      path: meta['path'] as String?,
      bytes: bytes,
      createdAt:
          DateTime.tryParse(meta['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static Future<void> saveNative({
    required String path,
    required String fileName,
    required String mimeType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bytesKey);
    await prefs.setString(
      _metaKey,
      jsonEncode({
        'source': 'native_path',
        'path': path,
        'fileName': fileName,
        'mimeType': mimeType,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<bool> saveWebBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (bytes.length > maxStoredWebBytes) {
      await clear();
      return false;
    }
    await prefs.setString(_bytesKey, base64Encode(bytes));
    await prefs.setString(
      _metaKey,
      jsonEncode({
        'source': 'web_bytes',
        'fileName': fileName,
        'mimeType': mimeType,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
    return true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_metaKey);
    await prefs.remove(_bytesKey);
  }
}
