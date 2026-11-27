import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiServiceException implements Exception {
  final String message;
  final int? statusCode;
  final String? status;
  final bool retryable;

  /// true 代表是「App 端等太久」造成的逾時（例如等音檔處理逾時），
  /// 而不是 Google 回了錯誤。逾時不該被當成一般的暫時性錯誤立刻重試。
  final bool isTimeout;

  GeminiServiceException(
    this.message, {
    this.statusCode,
    this.status,
    this.retryable = false,
    this.isTimeout = false,
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

/// 是否為「App 端逾時」：`Future.timeout()` 丟出的 [TimeoutException]，
/// 或自行標記為逾時的 [GeminiServiceException]。
bool isTimeoutFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is GeminiServiceException) return error.isTimeout;
  return false;
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

String sanitizeErrorForUser(Object error, {AnalysisDiagnostics? diag}) {
  if (isTimeoutFailure(error)) {
    return _timeoutMessage(diag);
  }

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

String _timeoutMessage(AnalysisDiagnostics? diag) {
  final minutes = diag?.audioDuration?.inMinutes;
  final sizeHint = (minutes == null || minutes <= 0) ? '' : '（約 $minutes 分鐘）';
  final tail = diag?.uploadCompleted == true
      ? '音檔已上傳完成，再次重試不需重傳。'
      : '音檔已保留，可再次重試。';
  return '上傳或分析逾時，音檔較大$sizeHint。$tail';
}

/// 分析流程的各個階段，供錯誤診斷顯示用。
enum AnalysisStage {
  checkingFile('檢查先前上傳的音檔'),
  uploading('上傳音檔'),
  processing('等待音檔處理'),
  analyzing('AI 分析');

  final String label;
  const AnalysisStage(this.label);
}

/// 記錄一次分析流程的進度與參數，失敗時用來產生「技術細節」。
/// 只放診斷用的數值，不放音檔內容、路徑或筆記文字。
class AnalysisDiagnostics {
  AnalysisStage? stage;
  Duration? timeoutLimit;

  /// 該階段的逾時規則說明（例如「連續 60 秒無上傳進度」）；有設定時，
  /// 技術細節顯示它，而不是顯示單一的逾時上限。
  String? timeoutRule;
  int attempts = 0;
  int? fileBytes;
  Duration? audioDuration;
  bool uploadCompleted = false;

  final Stopwatch _stageWatch = Stopwatch();

  Duration get stageElapsed => _stageWatch.elapsed;

  void beginStage(
    AnalysisStage next, {
    Duration? timeout,
    String? timeoutRule,
  }) {
    stage = next;
    timeoutLimit = timeout;
    this.timeoutRule = timeoutRule;
    attempts = 0;
    _stageWatch
      ..reset()
      ..start();
  }

  void noteAttempt() => attempts++;

  void endStage() => _stageWatch.stop();
}

/// 分析請求（`generateContent`）的重試策略：
/// - 逾時最多重試 1 次（逾時多半是檔案大／處理久，連續重試只是重複等待）；
/// - 其他暫時性錯誤（503、連線中斷…）最多重試 2 次；
/// - 非暫時性錯誤不重試。
Future<T> retryAnalysis<T>(
  Future<T> Function() action, {
  AnalysisDiagnostics? diag,
}) async {
  var timeoutRetries = 0;
  for (var attempt = 0; ; attempt++) {
    diag?.noteAttempt();
    try {
      return await action();
    } catch (error) {
      if (!isTemporaryFailure(error)) rethrow;
      if (isTimeoutFailure(error)) {
        if (timeoutRetries >= 1) rethrow;
        timeoutRetries++;
      } else if (attempt >= 2) {
        rethrow;
      }
      await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
    }
  }
}

/// 產生可展開顯示、可複製的「技術細節」。
/// 內容一律經過 [sanitizeForDebug]，不含 API Key、上傳網址查詢字串、
/// 音檔內容與檔案路徑。
String buildTechnicalDetails(
  Object error, {
  AnalysisDiagnostics? diag,
  String? modelName,
  String? appVersion,
}) {
  String fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  var message = sanitizeForDebug(error);
  if (message.length > 600) message = '${message.substring(0, 600)}…';

  final lines = <String>[];
  if (diag?.stage != null) lines.add('失敗階段：${diag!.stage!.label}');
  lines.add('錯誤類型：${error.runtimeType}');
  lines.add('訊息：$message');
  if (error is GeminiServiceException) {
    if (error.statusCode != null) lines.add('HTTP 狀態碼：${error.statusCode}');
    if (error.status != null) lines.add('Gemini 狀態：${error.status}');
  }
  if (diag != null) {
    if (diag.stage != null) {
      lines.add('該階段已用時間：${fmtDuration(diag.stageElapsed)}');
    }
    if (diag.timeoutRule != null) {
      lines.add('該階段逾時規則：${diag.timeoutRule}');
    } else if (diag.timeoutLimit != null) {
      lines.add('該階段逾時上限：${fmtDuration(diag.timeoutLimit!)}');
    }
    if (diag.attempts > 0) lines.add('該階段嘗試次數：${diag.attempts}');
    if (diag.fileBytes != null) {
      lines.add(
        '檔案大小：${(diag.fileBytes! / (1024 * 1024)).toStringAsFixed(1)} MB',
      );
    }
    if (diag.audioDuration != null) {
      lines.add('音檔長度（估計）：約 ${diag.audioDuration!.inMinutes} 分鐘');
    }
    lines.add('音檔是否已上傳：${diag.uploadCompleted ? '是' : '否'}');
  }
  if (modelName != null) lines.add('模型：$modelName');
  if (appVersion != null) lines.add('App 版本：$appVersion');
  lines.add('時間：${DateTime.now().toIso8601String()}');
  return lines.join('\n');
}
