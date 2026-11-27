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

  /// 這份音檔已成功上傳到 Google 時的檔案位址與上傳時間。
  /// 重試分析時可直接沿用，不必再傳一次大檔案。
  final String? fileUri;
  final DateTime? fileUriAt;

  const PendingAudio({
    required this.source,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
    this.path,
    this.bytes,
    this.fileUri,
    this.fileUriAt,
  });

  bool get isWebBytes => source == 'web_bytes';

  /// Google 會保留上傳的檔案 48 小時；這裡取 40 小時，留一點餘裕。
  static const remoteFileMaxAge = Duration(hours: 40);

  /// 仍在有效期內、值得先查詢一下是否還能用的 fileUri；否則為 null。
  String? get reusableFileUri {
    final uri = fileUri;
    final at = fileUriAt;
    if (uri == null || at == null) return null;
    return DateTime.now().difference(at) < remoteFileMaxAge ? uri : null;
  }

  PendingAudio withRemoteFile(String? uri, DateTime? at) {
    return PendingAudio(
      source: source,
      fileName: fileName,
      mimeType: mimeType,
      createdAt: createdAt,
      path: path,
      bytes: bytes,
      fileUri: uri,
      fileUriAt: at,
    );
  }
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
      fileUri: meta['fileUri'] as String?,
      fileUriAt: DateTime.tryParse(meta['fileUriAt'] as String? ?? ''),
    );
  }

  /// 記下「這份待分析音檔已上傳成功」的 fileUri。
  /// 沒有待分析資料時不做任何事。換成新的音檔（saveNative／saveWebBytes
  /// 會重寫整份 meta）時，這筆記錄會自然被清掉。
  static Future<void> saveRemoteFile({required String fileUri}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw == null) return;
    final meta = jsonDecode(raw) as Map<String, dynamic>;
    meta['fileUri'] = fileUri;
    meta['fileUriAt'] = DateTime.now().toIso8601String();
    await prefs.setString(_metaKey, jsonEncode(meta));
  }

  /// 清除已上傳檔案的記錄（檔案已過期／失效、或更換 API Key 時呼叫）。
  static Future<void> clearRemoteFile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw == null) return;
    final meta = jsonDecode(raw) as Map<String, dynamic>;
    if (!meta.containsKey('fileUri') && !meta.containsKey('fileUriAt')) return;
    meta.remove('fileUri');
    meta.remove('fileUriAt');
    await prefs.setString(_metaKey, jsonEncode(meta));
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
