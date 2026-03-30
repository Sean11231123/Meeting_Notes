import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const _versionUrl =
      'https://raw.githubusercontent.com/Sean11231123/Meeting_Notes/refs/heads/main/version.json';

  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.split('+').first;

      debugPrint('目前版本：$currentVersion');

      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 5));

      debugPrint('HTTP 狀態碼：${response.statusCode}');
      debugPrint('回應內容：${response.body}');

      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body);
      final latestVersion = json['version'] as String?;

      debugPrint('最新版本：$latestVersion');
      debugPrint('是否需要更新：${_isNewer(latestVersion ?? '', currentVersion)}');

      final message = json['message'] as String? ?? '有新版本可用';
      final url =
          json['url'] as String? ??
          'https://github.com/Sean11231123/Meeting_Notes';

      if (latestVersion == null) return;
      if (!_isNewer(latestVersion, currentVersion)) return;

      if (context.mounted) {
        _showUpdateDialog(context, latestVersion, message, url);
      }
    } catch (e) {
      debugPrint('更新檢查失敗：$e');
    }
  }

  static bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final lv = i < l.length ? l[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String message,
    String url,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            Icon(
              Icons.system_update,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text('有新版本！'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '版本 $version 已發布',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍後再說'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('前往更新'),
          ),
        ],
      ),
    );
  }
}
