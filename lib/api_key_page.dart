import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'recorder_page.dart'; // 確保能跳轉到錄音頁
import 'transitions.dart';
import 'key_storage.dart';

class ApiKeyPage extends StatefulWidget {
  final bool isUpdate;
  const ApiKeyPage({super.key, this.isUpdate = false});

  @override
  State<ApiKeyPage> createState() => _ApiKeyPageState();
}

class _ApiKeyPageState extends State<ApiKeyPage> {
  final _controller = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingKey();
  }

  Future<void> _loadExistingKey() async {
    final key = await KeyStorage.read();
    if (key != null && key.isNotEmpty) {
      if (mounted) {
        Navigator.pushReplacement(context, FadeRoute(page: RecorderPage()));
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveKey() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入 API Key')));
      return;
    }
    await KeyStorage.write(key);
    if (mounted) {
      if (widget.isUpdate) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('API Key 已更新')));
      } else {
        Navigator.pushReplacement(
          context,
          FadeRoute(page: const RecorderPage()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定 API Key'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.key, size: 64, color: Colors.indigo),
            const SizedBox(height: 24),
            const Text(
              '請輸入你的 Gemini API Key',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '前往 aistudio.google.com 免費申請',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              obscureText: _obscureText,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveKey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('儲存並開始使用'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
