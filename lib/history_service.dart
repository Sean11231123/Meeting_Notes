import 'dart:convert';
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

  HistoryRecord({
    required this.id,
    required this.templateName,
    required this.templateIcon,
    required this.result,
    required this.createdAt,
    List<String>? templateNames,
    List<String>? templateIcons,
  }) : templateNames = templateNames ?? [templateName],
       templateIcons = templateIcons ?? [templateIcon];

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateName': templateName,
    'templateIcon': templateIcon,
    'templateNames': templateNames,
    'templateIcons': templateIcons,
    'result': result,
    'createdAt': createdAt.toIso8601String(),
    // transcript 欄位已移除，不再寫入
  };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) {
    final templateName = json['templateName'] as String? ?? '';
    final templateIcon = json['templateIcon'] as String? ?? '';
    return HistoryRecord(
      id: json['id'] as String,
      templateName: templateName,
      templateIcon: templateIcon,
      result: json['result'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      // 資料遷移：舊紀錄沒有 templateNames 就用單一模板補上
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
      // 注意：舊紀錄的 transcript 欄位在讀取時直接忽略
    );
  }

  // 顯示用：把所有模板名稱合併成一行
  String get displayName => templateNames.join(' · ');
  String get displayIcons => templateIcons.join('');
}

class HistoryService {
  static const _key = 'history_records';

  Future<List<HistoryRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) => HistoryRecord.fromJson(jsonDecode(e)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> save(HistoryRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(record.toJson()));
    if (raw.length > 50) raw.removeAt(0);
    await prefs.setStringList(_key, raw);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((e) => jsonDecode(e)['id'] == id);
    await prefs.setStringList(_key, raw);
  }

  Future<void> updateName(String id, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final updated = raw.map((e) {
      final json = jsonDecode(e);
      if (json['id'] == id) {
        json['templateName'] = newName;
        json['templateNames'] = [newName];
        return jsonEncode(json);
      }
      return e;
    }).toList();
    await prefs.setStringList(_key, updated);
  }
}