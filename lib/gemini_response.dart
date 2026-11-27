import 'dart:convert';

import 'error_utils.dart';

/// 從 generateContent 的回應取出分析文字。
///
/// - 把所有文字片段串起來（模型可能把答案分成多段）；
/// - 略過思考摘要（`thought: true`）與只帶 thoughtSignature 等沒有文字的片段，
///   不會因為出現不認識的片段就整個失敗；
/// - 沒有任何文字時丟出 [GeminiServiceException]，而不是回傳一段假的「結果」：
///   分析成功後 App 會刪掉暫存音檔，空結果若被當成成功，錄音就沒了。
String extractAnalysisText(String responseBody) {
  final Object? decoded;
  try {
    decoded = jsonDecode(responseBody);
  } on FormatException {
    throw GeminiServiceException('無法解析 Gemini 的回應格式');
  }
  if (decoded is! Map) {
    throw GeminiServiceException('無法解析 Gemini 的回應格式');
  }

  final candidates = decoded['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    final feedback = decoded['promptFeedback'];
    final blockReason = feedback is Map ? feedback['blockReason'] : null;
    throw GeminiServiceException(
      blockReason != null ? '內容被模型拒絕處理（$blockReason）' : '模型沒有回傳任何內容',
    );
  }

  final candidate = candidates.first;
  final content = candidate is Map ? candidate['content'] : null;
  final parts = content is Map ? content['parts'] : null;

  final text = StringBuffer();
  if (parts is List) {
    for (final part in parts) {
      if (part is! Map || part['thought'] == true) continue;
      final value = part['text'];
      if (value is String) text.write(value);
    }
  }

  final result = text.toString();
  if (result.trim().isEmpty) {
    final reason = candidate is Map ? candidate['finishReason'] : null;
    throw GeminiServiceException(
      '模型沒有回傳分析文字${reason != null ? '（結束原因：$reason）' : ''}',
    );
  }
  return result;
}
