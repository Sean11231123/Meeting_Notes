/// 上傳進度的速度與剩餘時間估算（純 Dart，不依賴 Flutter，方便單元測試）。
///
/// 速度取「最近約 10 秒」的平均，並一律算到「現在」為止：連線停滯時
/// 速度會自然下降，而不是停在最後一次的數值。剩餘時間再做輕度平滑，
/// 讓倒數在每秒之間穩定遞減，只在速度明顯改變時才跟著調整。
class TransferSnapshot {
  final int sentBytes;
  final int totalBytes;

  /// 目前的平均速度（位元組／秒）；暖機期間為 null（顯示「計算中」）。
  final double? bytesPerSecond;

  /// 預估剩餘時間；暖機中、停滯中或已全數送出時為 null。
  final Duration? remaining;

  /// 已經一段時間沒有任何進度（連線不穩）。
  final bool stalled;

  /// 位元組已全數交給系統送出，正在等伺服器確認。
  final bool waitingForServer;

  const TransferSnapshot({
    required this.sentBytes,
    required this.totalBytes,
    this.bytesPerSecond,
    this.remaining,
    this.stalled = false,
    this.waitingForServer = false,
  });

  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = sentBytes / totalBytes;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }
}

class TransferEstimator {
  /// 計算速度所用的時間窗。
  static const window = Duration(seconds: 10);

  /// 剛開始傳送後，這段時間內資料太少，不顯示速度與剩餘時間。
  static const warmUp = Duration(seconds: 3);

  /// 超過這段時間沒有進度，視為停滯。
  static const stallAfter = Duration(seconds: 8);

  /// 取樣最小間隔，避免進度回呼太頻繁時累積過多樣本。
  static const _minSampleGap = Duration(milliseconds: 200);

  final int totalBytes;
  final Duration Function() _now;

  final List<_Sample> _samples = [];
  int _sent = 0;
  Duration? _firstAt;
  Duration? _lastProgressAt;
  Duration? _shownRemaining;
  Duration? _lastSnapshotAt;

  TransferEstimator({required this.totalBytes, Duration Function()? now})
    : _now = now ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  int get sentBytes => _sent;

  /// 回報目前已送出的位元組數。數字比上次小代表上傳重新開始（重試），
  /// 此時會把統計歸零。
  void update(int sentBytes) {
    final t = _now();
    if (sentBytes < _sent) reset();
    _sent = sentBytes;
    _firstAt ??= t;
    _lastProgressAt = t;

    final isLast = totalBytes > 0 && sentBytes >= totalBytes;
    if (_samples.isEmpty ||
        isLast ||
        t - _samples.last.at >= _minSampleGap) {
      _samples.add(_Sample(t, sentBytes));
    }
    // 只保留時間窗內的樣本，外加一筆更早的當作計算基準。
    while (_samples.length > 2 && t - _samples[1].at > window) {
      _samples.removeAt(0);
    }
  }

  void reset() {
    _samples.clear();
    _sent = 0;
    _firstAt = null;
    _lastProgressAt = null;
    _shownRemaining = null;
    _lastSnapshotAt = null;
  }

  TransferSnapshot snapshot() {
    final t = _now();
    final lastSnapshot = _lastSnapshotAt;
    _lastSnapshotAt = t;

    if (totalBytes > 0 && _sent >= totalBytes) {
      _shownRemaining = null;
      return TransferSnapshot(
        sentBytes: _sent,
        totalBytes: totalBytes,
        waitingForServer: true,
      );
    }

    final first = _firstAt;
    final lastProgress = _lastProgressAt;
    final stalled =
        lastProgress != null && t - lastProgress > stallAfter;

    if (first == null || t - first < warmUp || _samples.length < 2) {
      return TransferSnapshot(
        sentBytes: _sent,
        totalBytes: totalBytes,
        stalled: stalled,
      );
    }

    final base = _samples.first;
    final seconds = (t - base.at).inMicroseconds / 1e6;
    final speed = seconds > 0 ? (_sent - base.sent) / seconds : 0.0;

    Duration? raw;
    if (!stalled && speed > 1) {
      raw = Duration(
        milliseconds: ((totalBytes - _sent) / speed * 1000).round(),
      );
    }

    if (raw == null) {
      _shownRemaining = null;
    } else if (_shownRemaining == null || lastSnapshot == null) {
      _shownRemaining = raw;
    } else {
      var predicted = _shownRemaining! - (t - lastSnapshot);
      if (predicted < Duration.zero) predicted = Duration.zero;
      _shownRemaining = Duration(
        microseconds:
            (predicted.inMicroseconds * 0.6 + raw.inMicroseconds * 0.4)
                .round(),
      );
    }

    return TransferSnapshot(
      sentBytes: _sent,
      totalBytes: totalBytes,
      bytesPerSecond: speed,
      remaining: _shownRemaining,
      stalled: stalled,
    );
  }
}

class _Sample {
  final Duration at;
  final int sent;
  const _Sample(this.at, this.sent);
}

/// 「m:ss」或「h:mm:ss」。
String formatClock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// 例如「12.3 MB」。
String formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// 例如「2.4 MB/s」或「350 KB/s」。
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSecond / 1024).round()} KB/s';
}
