import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Gemini 4 系列的型號名稱（模型 ID 為 `gemini-4-<名稱>`），依「快→強」排序，
/// 也是選單中的顯示順序。Google 改用這些名稱取代 Flash／Pro 命名，所以 ID 裡
/// 沒有 "flash"。之後出現新型號時，在這裡加上名稱即可。
const List<String> kGemini4Families = ['hydrogen', 'neon', 'carbon', 'argon'];

/// 代表一個從 Gemini API 動態取得的模型
class GeminiModel {
  final String id;
  final String displayName;

  const GeminiModel({required this.id, required this.displayName});
}

class GeminiModelService {
  // 與 gemini_file_service.dart 完全一致的路由邏輯
  static const _proxyBase =
      'https://gemini-proxy.sean9611231123.workers.dev/proxy';
  static const _directBase = 'https://generativelanguage.googleapis.com';

  static String get _base => kIsWeb ? _proxyBase : _directBase;

  static Future<List<GeminiModel>> fetchAvailableModels(String apiKey) async {
    try {
      final uri = Uri.parse('$_base/v1beta/models?key=$apiKey&pageSize=200');
      // 網址含 API Key，不能印在日誌裡（日誌常會被貼出來求助）。
      debugPrint('[ModelService] fetching: $_base/v1beta/models (isWeb=$kIsWeb)');

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      debugPrint('[ModelService] status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('[ModelService] error body: ${response.body}');
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        debugPrint(
          '[ModelService] unexpected response type: ${decoded.runtimeType}',
        );
        return [];
      }

      final rawList = decoded['models'] as List<dynamic>? ?? [];
      debugPrint('[ModelService] raw model count: ${rawList.length}');

      final rawModels = rawList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final results = filterModels(
        rawModels,
        onRejected: (message) => debugPrint('[ModelService] rejected: $message'),
      );

      debugPrint('[ModelService] filtered model count: ${results.length}');
      for (final r in results) {
        debugPrint('[ModelService]   ${r.id}');
      }

      return results;
    } catch (e, stack) {
      debugPrint('[ModelService] exception: $e');
      debugPrint('[ModelService] stack: $stack');
      return [];
    }
  }

  /// 從 `models.list` 的原始資料挑出「適合拿來分析錄音」的模型，並排好順序。
  ///
  /// 挑選依據是模型 ID 的格式，而不是「名稱含不含 flash」：
  /// - Flash 系列：`gemini-X.Y-flash` 與 `gemini-X.Y-flash-lite`，版本 2.5 以上；
  /// - Gemini 4 系列：`gemini-4-<名稱>`，名稱見 [kGemini4Families]。
  /// 其他一律不收，例如 `gemini-omni-*`（影片生成，不支援音訊輸入）。
  ///
  /// models.list 不提供「可輸入哪些媒體」的欄位，所以只能靠 ID 判斷；
  /// 被排除的模型會透過 [onRejected] 回報原因，方便除錯。
  static List<GeminiModel> filterModels(
    List<Map<String, dynamic>> rawModels, {
    void Function(String message)? onRejected,
  }) {
    final results = <GeminiModel>[];
    for (final m in rawModels) {
      final rawName = m['name'] as String? ?? '';
      final modelId = rawName.replaceFirst('models/', '');
      final displayName = m['displayName'] as String? ?? '';
      final methods = [
        ...((m['supportedGenerationMethods'] as List<dynamic>?) ?? []),
        ...((m['supportedActions'] as List<dynamic>?) ?? []),
      ].map((e) => e.toString()).toList();

      final reason = rejectReason(modelId, displayName, methods);
      if (reason != null) {
        // 只回報 gemini- 開頭的（embedding、gemma 等不相關的不吵）。
        if (modelId.startsWith('gemini-')) onRejected?.call('$modelId — $reason');
        continue;
      }
      results.add(
        GeminiModel(id: modelId, displayName: _buildDisplayName(modelId)),
      );
    }

    results.sort(_compareForDisplay);
    return results;
  }

  static final RegExp _flashPattern = RegExp(
    r'^gemini-(\d+)(?:\.(\d+))?-flash(-lite)?$',
  );
  static final RegExp _gemini4Pattern = RegExp(
    '^gemini-4-(${kGemini4Families.join('|')})\$',
  );

  static const _specializedKeywords = [
    'omni', // 影片生成模型，不支援 generateContent 的音訊輸入
    'image',
    'imagen',
    'tts',
    'speech',
    'native-audio',
    'live',
    'dialog',
    'embedding',
    'aqa',
  ];

  /// 不適合的原因；適合時回傳 null。
  static String? rejectReason(
    String modelId,
    String displayName,
    List<String> supportedMethods,
  ) {
    if (!modelId.startsWith('gemini-')) return '不是 gemini- 開頭';

    // App 用 generateContent 呼叫模型，不支援的就無法使用。
    if (!supportedMethods.contains('generateContent')) {
      return '不支援 generateContent（支援：${supportedMethods.join(', ')}）';
    }

    final name = displayName.toLowerCase();
    for (final kw in _specializedKeywords) {
      if (modelId.contains(kw) || name.contains(kw)) return '特化模型（$kw）';
    }

    if (modelId.endsWith('-latest') || modelId.endsWith('-stable')) {
      return '別名（-latest／-stable）';
    }
    if (RegExp(r'(preview|exp\b|experimental)').hasMatch(modelId)) {
      return 'preview／experimental';
    }
    if (modelId.contains('thinking')) return 'thinking 系列';
    if (RegExp(r'-\d{3}$').hasMatch(modelId)) return '末尾三位數 revision';

    if (_gemini4Pattern.hasMatch(modelId)) return null;

    final flash = _flashPattern.firstMatch(modelId);
    if (flash != null) {
      final major = int.parse(flash.group(1)!);
      final minor = int.tryParse(flash.group(2) ?? '') ?? 0;
      if (major < 2 || (major == 2 && minor < 5)) return '版本低於 2.5';
      return null;
    }

    return '不是 Flash 或 Gemini 4 系列';
  }

  /// 版本新的在前；同版本內 Gemini 4 依 [kGemini4Families] 的順序，
  /// Flash 排在 Flash Lite 之前。
  static int _compareForDisplay(GeminiModel a, GeminiModel b) {
    final ka = _sortKey(a.id);
    final kb = _sortKey(b.id);
    for (var i = 0; i < ka.length; i++) {
      if (ka[i] != kb[i]) return ka[i].compareTo(kb[i]);
    }
    return a.id.compareTo(b.id);
  }

  /// [-主版本, -次版本, Gemini 4 型號順序, 是否 lite]：全部由小到大比較。
  static List<int> _sortKey(String modelId) {
    final g4 = _gemini4Pattern.firstMatch(modelId);
    if (g4 != null) {
      return [-4, 0, kGemini4Families.indexOf(g4.group(1)!), 0];
    }
    final flash = _flashPattern.firstMatch(modelId);
    if (flash != null) {
      return [
        -int.parse(flash.group(1)!),
        -(int.tryParse(flash.group(2) ?? '') ?? 0),
        0,
        flash.group(3) != null ? 1 : 0,
      ];
    }
    return [0, 0, 0, 0];
  }

  /// gemini-2.5-flash      → Gemini 2.5 Flash
  /// gemini-2.5-flash-lite → Gemini 2.5 Flash Lite
  static String _buildDisplayName(String modelId) {
    final withoutPrefix = modelId.replaceFirst('gemini-', '');
    final parts = withoutPrefix.split('-');
    final capitalized = parts
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    return 'Gemini $capitalized';
  }
}
