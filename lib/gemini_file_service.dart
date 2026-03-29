import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeminiFileService {
  final String apiKey;
  GeminiFileService(this.apiKey);

  // 手機版：從 File 上傳
  Future<String> uploadAudio(File audioFile) async {
    final bytes = await audioFile.readAsBytes();
    return _uploadBytes(bytes, 'audio/wav', audioFile.path.split('/').last);
  }

  // 網頁版：從 Uint8List 上傳
  Future<String> uploadAudioBytes(Uint8List bytes) async {
    return _uploadBytes(
      bytes,
      'audio/webm',
      'recording_${DateTime.now().millisecondsSinceEpoch}.webm',
    );
  }

  // 共用上傳邏輯
  Future<String> _uploadBytes(
    Uint8List bytes,
    String mimeType,
    String displayName,
  ) async {
    // 網頁版走代理，手機版直連
    const proxyBase = 'https://gemini-proxy.sean9611231123.workers.dev/proxy';
    const directBase = 'https://generativelanguage.googleapis.com';
    final base = kIsWeb ? proxyBase : directBase;

    final initResponse = await http.post(
      Uri.parse(
        '$base/upload/v1beta/files'
        '?key=$apiKey&uploadType=resumable',
      ),
      headers: {
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': bytes.length.toString(),
        'X-Goog-Upload-Header-Content-Type': mimeType,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'file': {'display_name': displayName},
      }),
    );

    if (initResponse.statusCode != 200) {
      throw Exception('上傳初始化失敗：${initResponse.body}');
    }

    final uploadUrl = initResponse.headers['x-goog-upload-url'];
    if (uploadUrl == null) throw Exception('找不到上傳 URL');

    // 網頁版需要把上傳 URL 也換成代理
    final finalUploadUrl = kIsWeb
        ? uploadUrl.replaceFirst(
            'https://generativelanguage.googleapis.com',
            proxyBase,
          )
        : uploadUrl;

    final uploadResponse = await http.post(
      Uri.parse(finalUploadUrl),
      headers: {
        'Content-Length': bytes.length.toString(),
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
      },
      body: bytes,
    );

    if (uploadResponse.statusCode != 200) {
      throw Exception('檔案上傳失敗：${uploadResponse.body}');
    }

    final responseJson = jsonDecode(uploadResponse.body);
    final fileUri = responseJson['file']['uri'] as String?;
    if (fileUri == null) throw Exception('找不到 file_uri');

    return fileUri;
  }

  // 輪詢等待檔案處理完成
  Future<void> waitUntilActive(String fileUri) async {
    final fileName = fileUri.replaceFirst(
      'https://generativelanguage.googleapis.com/v1beta/',
      '',
    );

    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 5));

      const proxyBase = 'https://gemini-proxy.sean9611231123.workers.dev/proxy';
      const directBase = 'https://generativelanguage.googleapis.com';
      final base = kIsWeb ? proxyBase : directBase;

      final response = await http.get(
        Uri.parse('$base/v1beta/$fileName?key=$apiKey'),
      );

      if (response.statusCode != 200) continue;

      final json = jsonDecode(response.body);
      final state = json['file']['state'] as String?;

      if (state == 'ACTIVE') return;
      if (state == 'FAILED') throw Exception('檔案處理失敗');
    }

    throw Exception('檔案處理逾時，請稍後再試');
  }

  // 用 file_uri 呼叫 Gemini 分析
  Future<String> analyzeWithFileUri(
    String fileUri,
    String prompt,
    String model,
  ) async {
    final mimeType = fileUri.contains('.webm') ? 'audio/webm' : 'audio/wav';

    const proxyBase = 'https://gemini-proxy.sean9611231123.workers.dev/proxy';
    const directBase = 'https://generativelanguage.googleapis.com';
    final base = kIsWeb ? proxyBase : directBase;

    final response = await http.post(
      Uri.parse('$base/v1beta/models/$model:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'file_data': {'mime_type': mimeType, 'file_uri': fileUri},
              },
              {'text': prompt},
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini 分析失敗：${response.body}');
    }

    final json = jsonDecode(response.body);
    final text =
        json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    return text ?? '無法取得分析結果';
  }
}
