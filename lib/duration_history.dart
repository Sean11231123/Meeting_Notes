import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 預估的時間範圍（例如「約 3–6 分鐘」）。
class EstimateRange {
  final Duration low;
  final Duration high;
  const EstimateRange(this.low, this.high);

  String format() {
    if (high < const Duration(seconds: 90)) {
      final lo = _roundTo5(low.inSeconds, up: false);
      final hi = _roundTo5(high.inSeconds, up: true);
      return lo >= hi ? '約 $hi 秒' : '約 $lo–$hi 秒';
    }
    final lo = (low.inSeconds / 60).round().clamp(1, 100000);
    final hi = (high.inSeconds / 60).ceil().clamp(lo, 100000);
    return lo >= hi ? '約 $hi 分鐘' : '約 $lo–$hi 分鐘';
  }

  static int _roundTo5(int seconds, {required bool up}) {
    final v = up ? (seconds / 5).ceil() * 5 : (seconds / 5).floor() * 5;
    return v < 5 ? 5 : v;
  }
}

/// 在本機記錄最近幾次的實測耗時，用來預估「上傳／Google 處理／模型分析」
/// 要花多久。這些階段（除了上傳過程中的即時速度）沒有可靠的進度資訊，
/// 所以只能靠歷史資料推估；沒有資料時回傳 null，畫面就不顯示預估。
class DurationHistory {
  static const maxSamples = 5;
  static const _maxAnalysisKeys = 20;

  /// 上傳速度（位元組／秒）。
  final List<double> uploadSpeeds;

  /// Google 處理音檔：每 MB 花幾秒。
  final List<double> processingSecondsPerMb;

  /// 分析：每分鐘音檔花幾秒，key 為「模型|模板數」。
  final Map<String, List<double>> analysisSecondsPerAudioMinute;

  DurationHistory({
    List<double>? uploadSpeeds,
    List<double>? processingSecondsPerMb,
    Map<String, List<double>>? analysisSecondsPerAudioMinute,
  }) : uploadSpeeds = uploadSpeeds ?? [],
       processingSecondsPerMb = processingSecondsPerMb ?? [],
       analysisSecondsPerAudioMinute = analysisSecondsPerAudioMinute ?? {};

  static const _mb = 1024 * 1024;

  // ── 記錄 ──

  /// 太小的檔案或太短的傳輸不具代表性，不記錄。
  void recordUpload({required int bytes, required double seconds}) {
    if (bytes < 5 * _mb || seconds < 3) return;
    _push(uploadSpeeds, bytes / seconds);
  }

  void recordProcessing({required int bytes, required double seconds}) {
    if (bytes < 5 * _mb || seconds < 1) return;
    _push(processingSecondsPerMb, seconds / (bytes / _mb));
  }

  void recordAnalysis({
    required String model,
    required int templateCount,
    required double audioMinutes,
    required double seconds,
  }) {
    if (audioMinutes < 1 || seconds <= 0) return;
    final key = _analysisKey(model, templateCount);
    final list = analysisSecondsPerAudioMinute.remove(key) ?? <double>[];
    _push(list, seconds / audioMinutes);
    analysisSecondsPerAudioMinute[key] = list; // 重新插入：最近用過的排在最後
    while (analysisSecondsPerAudioMinute.length > _maxAnalysisKeys) {
      analysisSecondsPerAudioMinute.remove(
        analysisSecondsPerAudioMinute.keys.first,
      );
    }
  }

  // ── 預估 ──

  EstimateRange? estimateUpload(int bytes) {
    // 速度越快花越少時間，所以「每位元組幾秒」才是可以直接取範圍的量。
    final perByte = [for (final s in uploadSpeeds) if (s > 0) 1 / s];
    return _range(perByte, bytes.toDouble());
  }

  EstimateRange? estimateProcessing(int bytes) =>
      _range(processingSecondsPerMb, bytes / _mb);

  EstimateRange? estimateAnalysis({
    required String model,
    required int templateCount,
    required double audioMinutes,
  }) {
    final list =
        analysisSecondsPerAudioMinute[_analysisKey(model, templateCount)];
    if (list == null) return null;
    return _range(list, audioMinutes);
  }

  // ── 序列化 ──

  Map<String, dynamic> toJson() => {
    'uploadSpeeds': uploadSpeeds,
    'processingSecondsPerMb': processingSecondsPerMb,
    'analysis': analysisSecondsPerAudioMinute,
  };

  factory DurationHistory.fromJson(Map<String, dynamic> json) {
    List<double> numbers(Object? v) => v is List
        ? [
            for (final e in v)
              if (e is num && e.isFinite && e > 0) e.toDouble(),
          ]
        : <double>[];

    final analysis = <String, List<double>>{};
    final raw = json['analysis'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final list = numbers(v);
        if (k is String && list.isNotEmpty) analysis[k] = list;
      });
    }
    return DurationHistory(
      uploadSpeeds: numbers(json['uploadSpeeds']),
      processingSecondsPerMb: numbers(json['processingSecondsPerMb']),
      analysisSecondsPerAudioMinute: analysis,
    );
  }

  // ── 內部 ──

  static String _analysisKey(String model, int templateCount) =>
      '$model|$templateCount';

  static void _push(List<double> list, double value) {
    if (!value.isFinite || value <= 0) return;
    list.add(value);
    while (list.length > maxSamples) {
      list.removeAt(0);
    }
  }

  /// 以歷史樣本（每單位幾秒）乘上單位數，得到時間範圍。
  /// 只有一筆樣本時沒有分布可看，給 0.7～1.5 倍；多筆時用最小到最大，
  /// 且至少涵蓋中位數的 ±15%，避免樣本剛好很接近時範圍窄得不合理。
  static EstimateRange? _range(List<double> perUnit, double units) {
    if (perUnit.isEmpty || units <= 0) return null;
    final sorted = [...perUnit]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
    double lo;
    double hi;
    if (sorted.length == 1) {
      lo = median * 0.7;
      hi = median * 1.5;
    } else {
      lo = sorted.first;
      hi = sorted.last;
      if (lo > median * 0.85) lo = median * 0.85;
      if (hi < median * 1.15) hi = median * 1.15;
    }
    return EstimateRange(
      Duration(milliseconds: (lo * units * 1000).round()),
      Duration(milliseconds: (hi * units * 1000).round()),
    );
  }
}

class DurationHistoryStore {
  static const _key = 'duration_history_v1';

  /// 讀不到或資料毀損時回傳空的歷史，不影響主流程。
  static Future<DurationHistory> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return DurationHistory();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return DurationHistory();
      return DurationHistory.fromJson(decoded);
    } catch (_) {
      return DurationHistory();
    }
  }

  static Future<void> save(DurationHistory history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(history.toJson()));
    } catch (_) {
      // 預估用的資料存不下來不影響使用。
    }
  }
}
