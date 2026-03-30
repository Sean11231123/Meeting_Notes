import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'api_key_page.dart';
import 'transitions.dart';
import 'feedback_page.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // API Key 區塊
          _SectionHeader(title: 'API 設定'),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.key_outlined,
            title: '更改 API Key',
            subtitle: '重新輸入 Gemini API Key',
            onTap: () => Navigator.push(
              context,
              SlideRoute(page: const ApiKeyPage(isUpdate: true)),
            ),
          ),

          const SizedBox(height: 32),

          // 主題區塊
          _SectionHeader(title: '外觀'),
          const SizedBox(height: 12),
          _ThemeSelector(themeProvider: themeProvider),

          const SizedBox(height: 32),

          // 意見反饋區塊
          _SettingsTile(
            icon: Icons.feedback_outlined,
            title: '提供意見 / 回報問題',
            subtitle: '告訴我們你的想法或遇到的問題',
            onTap: () =>
                Navigator.push(context, SlideRoute(page: const FeedbackPage())),
          ),

          const SizedBox(height: 32),

          // 關於區塊（新增）
          _SectionHeader(title: '關於'),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.code,
            title: '開源專案',
            subtitle: '在 GitHub 上查看原始碼',
            onTap: () async {
              final uri = Uri.parse(
                'https://github.com/Sean11231123/Meeting_Notes',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.secondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.secondary,
            fontSize: 13,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final ThemeProvider themeProvider;
  const _ThemeSelector({required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _ThemeOption(
              icon: Icons.brightness_auto,
              title: '跟隨系統',
              isSelected: themeProvider.themeMode == ThemeMode.system,
              onTap: () => themeProvider.setThemeMode(ThemeMode.system),
            ),
            const Divider(height: 1, indent: 56),
            _ThemeOption(
              icon: Icons.light_mode_outlined,
              title: '亮色模式',
              isSelected: themeProvider.themeMode == ThemeMode.light,
              onTap: () => themeProvider.setThemeMode(ThemeMode.light),
            ),
            const Divider(height: 1, indent: 56),
            _ThemeOption(
              icon: Icons.dark_mode_outlined,
              title: '暗色模式',
              isSelected: themeProvider.themeMode == ThemeMode.dark,
              onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? scheme.primary : scheme.secondary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? scheme.primary : scheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: scheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
