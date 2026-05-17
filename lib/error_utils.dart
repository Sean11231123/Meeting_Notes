import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiServiceException implements Exception {
  final String message;
  final int? statusCode;
  final String? status;
  final bool retryable;

  GeminiServiceException(
    this.message, {
    this.statusCode,
    this.status,
    this.retryable = false,
  });

  @override
  String toString() => message;
}

bool isRetryableStatusCode(int? statusCode) {
  return const {408, 429, 500, 502, 503, 504}.contains(statusCode);
}

bool isTemporaryFailure(Object error) {
  if (error is GeminiServiceException) return error.retryable;
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('connection abort') ||
      text.contains('503') ||
      text.contains('timed out') ||
      text.contains('unavailable');
}

GeminiServiceException exceptionFromResponse(
  http.Response response,
  String fallbackMessage,
) {
  String message = fallbackMessage;
  String? status;
  try {
    final body = jsonDecode(response.body);
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      message = error['message'] as String? ?? fallbackMessage;
      status = error['status'] as String?;
    }
  } catch (_) {
    // Keep the fallback message; user-facing text is sanitized elsewhere.
  }

  return GeminiServiceException(
    message,
    statusCode: response.statusCode,
    status: status,
    retryable:
        isRetryableStatusCode(response.statusCode) || status == 'UNAVAILABLE',
  );
}

String sanitizeErrorForUser(Object error) {
  if (error is GeminiServiceException) {
    if (error.statusCode == 503 || error.status == 'UNAVAILABLE') {
      return '模型目前繁忙，請稍後重試，或到設定切換模型。錄音已暫時保留。';
    }
    if (error.retryable) {
      return '連線暫時不穩，請稍後重試。音檔已暫時保留。';
    }
    if (error.statusCode == 400) {
      return '音檔格式或內容無法分析，請換一個支援的音檔。';
    }
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'API Key 無效或權限不足，請到設定重新確認。';
    }
    return '分析失敗，請稍後重試。音檔已暫時保留。';
  }

  if (isTemporaryFailure(error)) {
    return '服務或連線暫時不穩，請稍後重試，或到設定切換模型。音檔已暫時保留。';
  }

  return '分析失敗，請稍後重試。音檔已暫時保留。';
}

String sanitizeForDebug(Object error) {
  return error
      .toString()
      // Gemini request URLs can carry sensitive query parameters. Strip the
      // entire query string from Gemini URLs before any debug output.
      .replaceAllMapped(
        RegExp(
          r'(https?:\/\/[^\s]*generativelanguage\.googleapis\.com[^\s\?]*)\?[^\s\)]*',
        ),
        (match) => '${match[1]}?REDACTED',
      )
      .replaceAll(RegExp(r'key=[^&\s]+'), 'key=REDACTED')
      .replaceAll(RegExp(r'upload_id=[^&\s]+'), 'upload_id=REDACTED');
}
