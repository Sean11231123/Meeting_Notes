import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryRecord {
  final String id;
  final String templateName;
  final String templateIcon;
  final String result;
  final DateTime createdAt;
  // 支援多模板
  final List<String> templateNames;
  final List<String> templateIcons;
  // 標籤（例如：課程名稱、週次），用於歷史紀錄的篩選／搜尋
  final List<String> tags;

  HistoryRecord({
    required this.id,
    required this.templateName,
    required this.templateIcon,
    required this.result,
    required this.createdAt,
    List<String>? templateNames,
    List<String>? templateIcons,
    List<String>? tags,
  }) : templateNames = templateNames ?? [templateName],
       templateIcons = templateIcons ?? [templateIcon],
       tags = tags ?? const [];

  /// 存進 Hive 用的格式。Hive 原生支援 Map / List / String / DateTime，
  /// 不需要額外寫 TypeAdapter 或跑 build_runner。
  Map<String, dynamic> toMap() => {
    'id': id,
    'templateName': templateName,
    'templateIcon': templateIcon,
    'templateNames': templateNames,
    'templateIcons': templateIcons,
    'result': result,
    'createdAt': createdAt,
    'tags': tags,
  };

  factory HistoryRecord.fromMap(Map<dynamic, dynamic> map) {
    final templateName = map['templateName'] as String? ?? '';
    final templateIcon = map['templateIcon'] as String? ?? '';
    final rawCreatedAt = map['createdAt'];
    final createdAt = rawCreatedAt is DateTime
        ? rawCreatedAt
        : (DateTime.tryParse(rawCreatedAt?.toString() ?? '') ??
              DateTime.now());

    return HistoryRecord(
      id: map['id'] as String,
      templateName: templateName,
      templateIcon: templateIcon,
      result: map['result'] as String? ?? '',
      createdAt: createdAt,
      templateNames:
          (map['templateNames'] as List?)?.map((e) => e.toString()).toList() ??
          [templateName],
      templateIcons:
          (map['templateIcons'] as List?)?.map((e) => e.toString()).toList() ??
          [templateIcon],
      tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  /// 相容舊版（SharedPreferences 存的 JSON 字串）格式，僅用於一次性搬遷。
  factory HistoryRecord.fromLegacyJson(Map<String, dynamic> json) {
    final templateName = json['templateName'] as String? ?? '';
    final templateIcon = json['templateIcon'] as String? ?? '';
    return HistoryRecord(
      id: json['id'] as String,
      templateName: templateName,
      templateIcon: templateIcon,
      result: json['result'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      templateNames:
          (json['templateNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [templateName],
      templateIcons:
          (json['templateIcons'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [templateIcon],
    );
  }

  HistoryRecord copyWith({
    String? templateName,
    List<String>? templateNames,
    List<String>? tags,
  }) {
    return HistoryRecord(
      id: id,
      templateName: templateName ?? this.templateName,
      templateIcon: templateIcon,
      result: result,
      createdAt: createdAt,
      templateNames: templateNames ?? this.templateNames,
      templateIcons: templateIcons,
      tags: tags ?? this.tags,
    );
  }

  // 顯示用：把所有模板名稱合併成一行
  String get displayName => templateNames.join(' · ');
  String get displayIcons => templateIcons.join('');
}

/// 歷史紀錄的本地儲存。
///
/// 原本用 SharedPreferences 存一整包 JSON 字串陣列，每次新增/刪除/改名都要
/// 整包讀出、反序列化、修改、再整包寫回，且有 50 筆的上限。
/// 改用 Hive（純 Dart、支援 Web／Android／iOS／桌面，含 Web 也是靠
/// IndexedDB 儲存，不像 sqflite 在 Web 上需要額外的 wasm 設定）之後，
/// 每筆紀錄各自存取，拿掉了筆數上限，也讓後續搜尋/標籤功能有更合理的基礎。
class HistoryService {
  static const _boxName = 'history_records_v2';
  static const _legacyPrefsKey = 'history_records';
  static const _migratedFlagKey = 'history_migrated_to_hive_v2';

  static Box? _box;

  /// 必須在 runApp() 之前呼叫一次（見 main.dart）。
  static Future<void> init() async {
    _box ??= await Hive.openBox(_boxName);
    await _migrateFromSharedPreferencesIfNeeded();
  }

  static Box get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError(
        'HistoryService.init() 尚未被呼叫，請確認 main.dart 有在 runApp() 前 await 它。',
      );
    }
    return box;
  }

  /// 把舊版存在 SharedPreferences 的歷史紀錄搬進 Hive，只會執行一次。
  static Future<void> _migrateFromSharedPreferencesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyMigrated = prefs.getBool(_migratedFlagKey) ?? false;
    if (alreadyMigrated) return;

    final raw = prefs.getStringList(_legacyPrefsKey) ?? [];
    for (final entry in raw) {
      try {
        final json = jsonDecode(entry) as Map<String, dynamic>;
        final record = HistoryRecord.fromLegacyJson(json);
        await _requireBox.put(record.id, record.toMap());
      } catch (_) {
        // 忽略單筆無法解析的舊資料，不影響其餘紀錄搬遷。
      }
    }

    await prefs.setBool(_migratedFlagKey, true);
    await prefs.remove(_legacyPrefsKey);
  }

  Future<List<HistoryRecord>> loadAll() async {
    final records = _requireBox.values
        .map(
          (e) => HistoryRecord.fromMap(Map<dynamic, dynamic>.from(e as Map)),
        )
        .toList();
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  Future<void> save(HistoryRecord record) async {
    await _requireBox.put(record.id, record.toMap());
  }

  Future<void> delete(String id) async {
    await _requireBox.delete(id);
  }

  Future<void> updateName(String id, String newName) async {
    final raw = _requireBox.get(id);
    if (raw == null) return;
    final record = HistoryRecord.fromMap(
      Map<dynamic, dynamic>.from(raw as Map),
    );
    final updated = record.copyWith(
      templateName: newName,
      templateNames: [newName],
    );
    await _requireBox.put(id, updated.toMap());
  }

  Future<void> updateTags(String id, List<String> tags) async {
    final raw = _requireBox.get(id);
    if (raw == null) return;
    final record = HistoryRecord.fromMap(
      Map<dynamic, dynamic>.from(raw as Map),
    );
    final updated = record.copyWith(tags: tags);
    await _requireBox.put(id, updated.toMap());
  }

  /// 目前所有紀錄中出現過的標籤（去重、依字母排序），給篩選用的標籤清單使用。
  Future<List<String>> allTags() async {
    final records = await loadAll();
    final tagSet = <String>{};
    for (final r in records) {
      tagSet.addAll(r.tags);
    }
    final list = tagSet.toList()..sort();
    return list;
  }

  /// 依關鍵字（比對名稱與內容）與標籤（需同時符合所有選取標籤）篩選歷史紀錄。
  Future<List<HistoryRecord>> search({
    String query = '',
    List<String> tags = const [],
  }) async {
    final all = await loadAll();
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty && tags.isEmpty) return all;

    return all.where((r) {
      final matchesKeyword =
          keyword.isEmpty ||
          r.displayName.toLowerCase().contains(keyword) ||
          r.result.toLowerCase().contains(keyword);
      final matchesTags = tags.isEmpty || tags.every((t) => r.tags.contains(t));
      return matchesKeyword && matchesTags;
    }).toList();
  }
}
