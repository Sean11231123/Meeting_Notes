import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_key_page.dart';
import 'feedback_page.dart';
import 'model_settings.dart';
import 'theme_provider.dart';
import 'transitions.dart';

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
          const _SectionHeader(title: 'API 設定'),
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
          const SizedBox(height: 12),
          const _ModelSelector(),
          const SizedBox(height: 32),
          const _SectionHeader(title: '外觀'),
          const SizedBox(height: 12),
          _ThemeSelector(themeProvider: themeProvider),
          const SizedBox(height: 32),
          _SettingsTile(
            icon: Icons.feedback_outlined,
            title: '意見回饋 / 問題回報',
            subtitle: '告訴我們你的想法或遇到的問題',
            onTap: () =>
                Navigator.push(context, SlideRoute(page: const FeedbackPage())),
          ),
          const SizedBox(height: 32),
          const _SectionHeader(title: '關於'),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.code,
            title: '原始碼',
            subtitle: '在 GitHub 查看專案',
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

class _ModelSelector extends StatefulWidget {
  const _ModelSelector();

  @override
  State<_ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<_ModelSelector> {
  String _selectedModel = ModelSettings.defaultModel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = await ModelSettings.read();
    if (!mounted) return;
    setState(() {
      _selectedModel = model;
      _isLoading = false;
    });
  }

  Future<void> _setModel(String? model) async {
    if (model == null) return;
    await ModelSettings.write(model);
    if (!mounted) return;
    setState(() => _selectedModel = model);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.auto_awesome,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        title: const Text('Gemini 模型'),
        subtitle: _isLoading
            ? const Text('讀取中...')
            : DropdownButton<String>(
                value: _selectedModel,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: ModelSettings.options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: _setModel,
              ),
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
              title: '淺色模式',
              isSelected: themeProvider.themeMode == ThemeMode.light,
              onTap: () => themeProvider.setThemeMode(ThemeMode.light),
            ),
            const Divider(height: 1, indent: 56),
            _ThemeOption(
              icon: Icons.dark_mode_outlined,
              title: '深色模式',
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
