import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
      debugPrint('[ModelService] fetching: $uri (isWeb=$kIsWeb)');

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

      final results = <GeminiModel>[];

      for (final m in rawModels) {
        final rawName = m['name'] as String? ?? '';
        final modelId = rawName.replaceFirst('models/', '');

        final supportedMethods = [
          ...((m['supportedGenerationMethods'] as List<dynamic>?) ?? []),
          ...((m['supportedActions'] as List<dynamic>?) ?? []),
        ].map((e) => e.toString()).toList();

        // ── 過濾規則 ───────────────────────────────────────────
        // 1. 必須以 gemini- 開頭
        if (!modelId.startsWith('gemini-')) continue;

        // 2. 版本號必須 >= 2.5（排除 gemini-2.0-flash 等舊版本）
        //    modelId 格式：gemini-X.Y-flash[-lite]
        final versionMatch = RegExp(
          r'^gemini-(\d+)\.(\d+)-',
        ).firstMatch(modelId);
        if (versionMatch != null) {
          final major = int.tryParse(versionMatch.group(1)!) ?? 0;
          final minor = int.tryParse(versionMatch.group(2)!) ?? 0;
          final version = major * 10 + minor; // e.g. 2.5 → 25, 2.0 → 20
          if (version < 25) continue; // 排除 2.0、1.x 等舊版本
        }

        // 3. 必須含 flash
        if (!modelId.contains('flash')) continue;

        // 4. 必須支援 generateContent
        if (!supportedMethods.contains('generateContent')) continue;

        // 5. 排除 -latest / -stable alias
        if (modelId.endsWith('-latest') || modelId.endsWith('-stable'))
          continue;

        // 6. 排除 preview / exp / experimental
        if (RegExp(r'(preview|exp\b|experimental)').hasMatch(modelId)) continue;

        // 7. 排除 thinking 系列
        if (modelId.contains('thinking')) continue;

        // 8. 排除末尾三位數 revision（-001、-002 與主模型重複）
        if (RegExp(r'-\d{3}$').hasMatch(modelId)) continue;

        // 9. 排除 image / imagen / tts / speech / embedding 等特化模型
        //    同時檢查 modelId 和 displayName
        final displayNameRaw = (m['displayName'] as String? ?? '')
            .toLowerCase();
        final specializedKeywords = [
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
        if (specializedKeywords.any(
          (kw) => modelId.contains(kw) || displayNameRaw.contains(kw),
        ))
          continue;

        results.add(
          GeminiModel(id: modelId, displayName: _buildDisplayName(modelId)),
        );
      }

      debugPrint('[ModelService] filtered model count: ${results.length}');
      for (final r in results) {
        debugPrint('[ModelService]   ${r.id}');
      }

      // 排序：版本號大的排前，lite 排在同版本 flash 之後
      results.sort((a, b) {
        final aBase = a.id.replaceAll('-lite', '').replaceAll('-flash', '');
        final bBase = b.id.replaceAll('-lite', '').replaceAll('-flash', '');
        if (aBase != bBase) return bBase.compareTo(aBase);
        final aLite = a.id.contains('lite');
        final bLite = b.id.contains('lite');
        return aLite ? 1 : (bLite ? -1 : 0);
      });

      return results;
    } catch (e, stack) {
      debugPrint('[ModelService] exception: $e');
      debugPrint('[ModelService] stack: $stack');
      return [];
    }
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
