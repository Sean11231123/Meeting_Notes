import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'audio_file_stub.dart' if (dart.library.io) 'audio_file_io.dart';
import 'error_utils.dart';

class GeminiFileService {
  static const _proxyBase =
      'https://gemini-proxy.sean9611231123.workers.dev/proxy';
  static const _directBase = 'https://generativelanguage.googleapis.com';
  static const _requestTimeout = Duration(seconds: 60);

  final String apiKey;
  GeminiFileService(this.apiKey);

  String get _base => kIsWeb ? _proxyBase : _directBase;

  Future<String> uploadAudioPath(
    String path, {
    required String mimeType,
    required String fileName,
  }) async {
    final bytes = await readAudioFileBytes(path);
    return uploadAudioBytes(bytes, mimeType: mimeType, fileName: fileName);
  }

  Future<String> uploadAudioBytes(
    Uint8List bytes, {
    required String mimeType,
    required String fileName,
  }) async {
    return _withRetry(() => _uploadBytesOnce(bytes, mimeType, fileName));
  }

  Future<String> _uploadBytesOnce(
    Uint8List bytes,
    String mimeType,
    String displayName,
  ) async {
    final initResponse = await http
        .post(
          Uri.parse(
            '$_base/upload/v1beta/files'
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
        )
        .timeout(_requestTimeout);

    if (initResponse.statusCode != 200) {
      throw exceptionFromResponse(initResponse, '音檔上傳初始化失敗');
    }

    final uploadUrl = initResponse.headers['x-goog-upload-url'];
    if (uploadUrl == null) {
      throw GeminiServiceException('音檔上傳初始化失敗');
    }

    final finalUploadUrl = kIsWeb
        ? uploadUrl.replaceFirst(_directBase, _proxyBase)
        : uploadUrl;

    final uploadResponse = await http
        .post(
          Uri.parse(finalUploadUrl),
          headers: {
            'Content-Length': bytes.length.toString(),
            'X-Goog-Upload-Offset': '0',
            'X-Goog-Upload-Command': 'upload, finalize',
          },
          body: bytes,
        )
        .timeout(_requestTimeout);

    if (uploadResponse.statusCode != 200) {
      throw exceptionFromResponse(uploadResponse, '音檔上傳失敗');
    }

    final responseJson = jsonDecode(uploadResponse.body);
    final fileUri = responseJson['file']?['uri'] as String?;
    if (fileUri == null) {
      throw GeminiServiceException('音檔上傳失敗');
    }

    return fileUri;
  }

  Future<void> waitUntilActive(String fileUri) async {
    final fileName = fileUri.replaceFirst(
      'https://generativelanguage.googleapis.com/v1beta/',
      '',
    );

    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 5));

      final response = await _withRetry(
        () => http
            .get(Uri.parse('$_base/v1beta/$fileName?key=$apiKey'))
            .timeout(_requestTimeout),
      );

      if (response.statusCode != 200) continue;

      final json = jsonDecode(response.body);
      final fileData = json['file'] ?? json;
      final state = fileData['state'] as String?;

      if (state == 'ACTIVE') return;
      if (state == 'FAILED') {
        throw GeminiServiceException('音檔處理失敗');
      }
    }

    throw GeminiServiceException('音檔處理逾時', retryable: true);
  }

  Future<String> analyzeWithFileUri(
    String fileUri,
    String prompt,
    String model, {
    required String mimeType,
  }) async {
    final response = await _withRetry(() async {
      final response = await http
          .post(
            Uri.parse(
              '$_base/v1beta/models/$model:generateContent?key=$apiKey',
            ),
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
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw exceptionFromResponse(response, 'Gemini 分析失敗');
      }
      return response;
    });

    final json = jsonDecode(response.body);
    final text =
        json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    return text ?? '未取得分析結果';
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (!isTemporaryFailure(error) || attempt == 2) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw lastError ?? GeminiServiceException('暫時無法連線', retryable: true);
  }
}
