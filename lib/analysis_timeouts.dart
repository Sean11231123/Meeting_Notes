import 'dart:typed_data';

/// 依檔案大小／音檔長度推算「上傳、等待處理、分析」各階段的逾時。
///
/// 原本全部是固定 60～90 秒：90 分鐘的 WAV 約 173MB，光上傳就不可能在
/// 60 秒內完成，每次都會以 TimeoutException 收場，換模型也沒用。
/// 這裡的係數是保守估計值，不是實測值，之後可依實際使用情況微調。
class AnalysisTimeouts {
  AnalysisTimeouts._();

  static const _bytesPerMb = 1024 * 1024;

  /// 內嵌（inline）送出音檔的原始檔案大小上限。
  ///
  /// Google 限制 generateContent「單次請求總大小」為 20MB（含提示文字與
  /// 內嵌的檔案），而內嵌音檔要先轉成 base64，體積變成約 4/3 倍。
  /// 所以原始檔案不能用 20MB 當門檻：20MB 的檔案送出時約 26.7MB，會超限。
  /// 14,000,000 位元組轉 base64 後約 18.7MB，留下約 1.3MB 給提示文字與
  /// JSON 外框（即使 Google 的「MB」是 1,000,000 位元組也不會超過）。
  /// 超過這個大小改走 Files API（先上傳，再用 fileUri 分析）。
  static const inlineAudioLimitBytes = 14000000;

  /// 這個大小的音檔是否要走 Files API，而不是直接內嵌。
  static bool shouldUseFileApi(int audioBytes) =>
      audioBytes > inlineAudioLimitBytes;

  /// App 自己錄的 WAV：16kHz、單聲道、16-bit。
  static const _wavBytesPerSecond = 32000;

  /// 其他（壓縮）格式取不到長度時的換算位元率。刻意取偏低的值（約 64kbps），
  /// 讓估出來的長度偏長、逾時偏寬鬆，而不是偏短。
  static const _compressedBytesPerSecond = 8000;

  /// 有進度回報時（Android／iOS），上傳改用「連續這麼久完全沒有進度」才算逾時，
  /// 而不是用檔案大小去猜總時間：慢但持續在傳的上傳不會被切斷，真正卡住才會。
  static const uploadStall = Duration(seconds: 60);

  /// 位元組全數送出後，等伺服器確認（finalize）的上限。
  static const uploadFinalizeWait = Duration(minutes: 3);

  /// 有進度回報時的總時間安全上限。
  static const uploadOverallCap = Duration(hours: 1);

  /// 沒有進度回報時（網頁版）上傳「檔案本體」的逾時：60 秒 + 每 MB 3 秒（約假設上傳速度至少 2.7Mbps），
  /// 下限 2 分鐘、上限 30 分鐘。
  static Duration upload(int bytes) {
    final seconds = 60 + (bytes / _bytesPerMb * 3).ceil();
    return _clamp(
      Duration(seconds: seconds),
      const Duration(minutes: 2),
      const Duration(minutes: 30),
    );
  }

  /// 等待 Google 處理音檔（PROCESSING → ACTIVE）的上限：
  /// 2 分鐘 + 每 100MB 加 1 分鐘，上限 15 分鐘。
  static Duration processing(int bytes) {
    final seconds = 120 + (bytes / (100 * _bytesPerMb) * 60).ceil();
    return _clamp(
      Duration(seconds: seconds),
      const Duration(minutes: 2),
      const Duration(minutes: 15),
    );
  }

  /// 分析請求的逾時：90 秒 + 每分鐘音檔 2 秒，上限 15 分鐘；
  /// 走檔案 API 的大型音檔下限 3 分鐘（inline 的小檔案下限 90 秒）。
  /// 多模板合併成單一請求時，每多一個模板再加 45 秒（沿用原本的做法）。
  static Duration analyze({
    required Duration audio,
    required bool viaFileApi,
    int templateCount = 1,
  }) {
    final audioMinutes = (audio.inSeconds / 60).ceil();
    final base = Duration(seconds: 90 + 2 * audioMinutes);
    final minimum = viaFileApi
        ? const Duration(minutes: 3)
        : const Duration(seconds: 90);
    final clamped = _clamp(base, minimum, const Duration(minutes: 15));
    final extraTemplates = templateCount > 1 ? templateCount - 1 : 0;
    return clamped + Duration(seconds: 45 * extraTemplates);
  }

  /// 估計音檔長度。
  ///
  /// WAV 會讀檔頭的 byteRate（[header] 為檔案開頭至少 44 位元組）；
  /// 讀不到、或不是 WAV 時，改用檔案大小保守換算。
  static Duration estimateAudioDuration({
    required int fileBytes,
    required String mimeType,
    Uint8List? header,
  }) {
    final isWav = mimeType == 'audio/wav' || mimeType == 'audio/x-wav';
    int bytesPerSecond;
    if (isWav) {
      bytesPerSecond =
          (header == null ? null : parseWavByteRate(header)) ??
          _wavBytesPerSecond;
    } else {
      bytesPerSecond = _compressedBytesPerSecond;
    }
    final payload = isWav && fileBytes > 44 ? fileBytes - 44 : fileBytes;
    return Duration(seconds: (payload / bytesPerSecond).ceil());
  }

  /// 讀取標準 WAV 檔頭（RIFF/WAVE/fmt 為前三個區塊）的 byteRate。
  /// 檔頭不符合預期時回傳 null。
  static int? parseWavByteRate(Uint8List header) {
    if (header.length < 36) return null;
    bool tagAt(int offset, String tag) {
      for (var i = 0; i < 4; i++) {
        if (header[offset + i] != tag.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (!tagAt(0, 'RIFF') || !tagAt(8, 'WAVE') || !tagAt(12, 'fmt ')) {
      return null;
    }
    final byteRate = ByteData.sublistView(
      header,
    ).getUint32(28, Endian.little);
    return byteRate > 0 ? byteRate : null;
  }

  static Duration _clamp(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
