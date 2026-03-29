import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiFileService {
  final String apiKey;
  GeminiFileService(this.apiKey);

  // 第一步：上傳檔案，取得 file_uri
  Future<String> uploadAudio(File audioFile) async {
    final bytes = await audioFile.readAsBytes();
    final mimeType = 'audio/wav';
    final displayName = audioFile.path.split('/').last;

    // 初始化上傳（Resumable Upload）
    final initResponse = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/upload/v1beta/files'
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

    // 上傳實際檔案內容
    final uploadResponse = await http.post(
      Uri.parse(uploadUrl),
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

  // 第二步：輪詢等待檔案處理完成
  Future<void> waitUntilActive(String fileUri) async {
    // 從 uri 取出 file name，例如 files/abc123
    final fileName = fileUri.replaceFirst(
      'https://generativelanguage.googleapis.com/v1beta/',
      '',
    );

    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 5));

      final response = await http.get(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/'
          '$fileName?key=$apiKey',
        ),
      );

      if (response.statusCode != 200) continue;

      final json = jsonDecode(response.body);
      final state = json['file']['state'] as String?;

      if (state == 'ACTIVE') return;
      if (state == 'FAILED') throw Exception('檔案處理失敗');
    }

    throw Exception('檔案處理逾時，請稍後再試');
  }

  // 第三步：用 file_uri 呼叫 Gemini 分析
  Future<String> analyzeWithFileUri(
    String fileUri,
    String prompt,
    String model,
  ) async {
    final response = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/'
        'models/$model:generateContent?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'file_data': {'mime_type': 'audio/wav', 'file_uri': fileUri},
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
