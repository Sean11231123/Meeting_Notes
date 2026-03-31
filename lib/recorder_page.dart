import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'templates.dart';
import 'history_service.dart';
import 'history_page.dart';
import 'gemini_file_service.dart';
import 'transitions.dart';
import 'settings_page.dart';
import 'animated_button.dart';
import 'recording_visualizer.dart';
import 'package:flutter/foundation.dart';
import 'web_recorder.dart' if (dart.library.io) 'web_recorder_stub.dart';
import 'key_storage.dart';
import 'update_service.dart';
import 'package:file_picker/file_picker.dart';

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  final AudioRecorder _recorder = AudioRecorder();
  final WebRecorder _webRecorder = WebRecorder();
  Uint8List? _webAudioBytes;
  Timer? _timer;
  String? _uploadedFileName;
  int _recordSeconds = 0;
  static const _serviceChannel = MethodChannel(
    'com.example.meeting_notes/recording_service',
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) UpdateService.checkForUpdate(context);
    });
  }

  bool _isRecording = false;
  bool _isAnalyzing = false;
  String _statusText = '按下按鈕開始錄音';
  String? _lastFilePath;
  String? _analysisResult;
  MeetingTemplate _selectedTemplate = kTemplates[0];
  String _noteName = '';

  // 停止錄音後彈出設定視窗，讓使用者選模板與命名
  Future<void> _showAnalysisSettingsDialog() async {
    List<MeetingTemplate> selectedTemplates = [kTemplates[0]];
    final nameController = TextEditingController(
      text: '錄音_${DateTime.now().month}月${DateTime.now().day}日',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            '選擇分析設定',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 筆記名稱
                const Text(
                  '筆記名稱',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '輸入筆記名稱',
                  ),
                ),
                const SizedBox(height: 20),
                // 模板選擇（多選）
                const Text(
                  '選擇模板（可多選）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  '每個模板會分別整理一份摘要',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kTemplates.map((template) {
                    final isSelected = selectedTemplates.contains(template);
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          if (isSelected) {
                            if (selectedTemplates.length > 1) {
                              selectedTemplates.remove(template);
                            }
                          } else {
                            selectedTemplates.add(template);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: (MediaQuery.of(context).size.width - 120) / 2,
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              template.icon,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              template.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(
                selectedTemplates.length > 1
                    ? '分析 ${selectedTemplates.length} 個模板'
                    : '開始分析',
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final name = nameController.text.trim().isEmpty
          ? '錄音_${DateTime.now().month}月${DateTime.now().day}日'
          : nameController.text.trim();
      await _analyzeWithTemplates(selectedTemplates, name);
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    // 檢查副檔名是否為音訊格式
    final ext = file.name.split('.').last.toLowerCase();
    const supportedFormats = [
      'mp3',
      'm4a',
      'wav',
      'webm',
      'ogg',
      'aac',
      'flac',
    ];
    if (!supportedFormats.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('不支援的格式：.$ext\n請上傳 mp3、m4a、wav 等音訊檔案')),
        );
      }
      return; // ← 這裡要 return，不繼續執行
    }

    setState(() {
      _uploadedFileName = file.name;
      _analysisResult = null;

      if (kIsWeb) {
        _webAudioBytes = file.bytes;
        _lastFilePath = 'web_upload';
      } else {
        _lastFilePath = file.path;
        _webAudioBytes = null;
      }

      _statusText = '已選取：${file.name}\n按下 AI 分析開始整理。';
    });
  }

  Future<void> _analyzeWithTemplates(
    List<MeetingTemplate> templates,
    String noteName,
  ) async {
    String _getMimeType(String fileName) {
      final ext = fileName.split('.').last.toLowerCase();
      switch (ext) {
        case 'mp3':
          return 'audio/mpeg';
        case 'm4a':
          return 'audio/mp4';
        case 'wav':
          return 'audio/wav';
        case 'webm':
          return 'audio/webm';
        case 'ogg':
          return 'audio/ogg';
        case 'aac':
          return 'audio/aac';
        case 'flac':
          return 'audio/flac';
        default:
          return 'audio/mpeg';
      }
    }

    if (_lastFilePath == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _statusText = 'AI 分析中（${templates.length} 個模板）...';
    });

    try {
      final apiKey = await KeyStorage.read();
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _isAnalyzing = false;
          _statusText = '找不到 API Key，請重新設定';
        });
        return;
      }

      const modelName = 'gemini-2.5-flash';
      Uint8List? audioBytes;
      String? fileUri;

      if (kIsWeb) {
        if (_webAudioBytes == null) {
          setState(() {
            _isAnalyzing = false;
            _statusText = '找不到錄音資料，請重新錄音';
          });
          return;
        }
        final fileSizeMB = _webAudioBytes!.length / (1024 * 1024);
        if (fileSizeMB <= 20) {
          // 小檔案直接送
          audioBytes = _webAudioBytes;
        } else {
          // 大檔案用 File API 上傳
          final fileService = GeminiFileService(apiKey);
          setState(
            () => _statusText = '上傳音訊中（${fileSizeMB.toStringAsFixed(0)}MB）...',
          );
          fileUri = await fileService.uploadAudioBytes(
            _webAudioBytes!,
            mimeType: _uploadedFileName != null
                ? _getMimeType(_uploadedFileName!)
                : 'audio/webm',
            fileName: _uploadedFileName ?? 'recording.webm',
          );
          setState(() => _statusText = '等待 Google 處理音訊...');
          await fileService.waitUntilActive(fileUri);
        }
      } else {
        final audioFile = File(_lastFilePath!);
        final fileSize = await audioFile.length();
        final fileSizeMB = fileSize / (1024 * 1024);

        if (fileSizeMB <= 20) {
          audioBytes = await audioFile.readAsBytes();
        } else {
          final fileService = GeminiFileService(apiKey);
          setState(
            () => _statusText = '上傳音訊中（${fileSizeMB.toStringAsFixed(0)}MB）...',
          );
          fileUri = await fileService.uploadAudio(audioFile);
          setState(() => _statusText = '等待 Google 處理音訊...');
          await fileService.waitUntilActive(fileUri);
        }
      }

      // 對每個模板分別分析
      final List<String> results = [];
      for (int i = 0; i < templates.length; i++) {
        final template = templates[i];
        setState(
          () => _statusText =
              'AI 分析中（${i + 1}/${templates.length}）：${template.name}...',
        );

        final enhancedPrompt =
            '''
${template.prompt}

---
請務必使用以下 Markdown 格式美化輸出：
1. **標題層級**：使用 # 代表大標題，## 代表各分類標題。
2. **重點強調**：重要關鍵字請用 **雙星號粗體**。
3. **結構化**：使用清單符號 `*` 或 `1.` 整理要點。
4. **互動感**：待辦清單請使用 `- [ ]` 語法。
5. **視覺分隔**：不同章節間請加入 `---` 分隔線。
''';

        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        GenerateContentResponse response;

        if (audioBytes != null) {
          response = await model.generateContent([
            Content.multi([
              DataPart(
                _uploadedFileName != null
                    ? _getMimeType(_uploadedFileName!)
                    : (kIsWeb ? 'audio/webm' : 'audio/wav'),
                audioBytes,
              ),
              TextPart(enhancedPrompt),
            ]),
          ]);
        } else {
          final fileService = GeminiFileService(apiKey);
          final result = await fileService.analyzeWithFileUri(
            fileUri!,
            enhancedPrompt,
            modelName,
          );
          results.add(result);
          continue;
        }

        results.add(response.text ?? '無法取得分析結果');
      }

      // 合併所有模板結果
      final combinedResult = results.join('\n\n---\n\n');

      await HistoryService().save(
        HistoryRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          templateName: noteName,
          templateIcon: templates.map((t) => t.icon).join(''),
          result: combinedResult,
          createdAt: DateTime.now(),
          templateNames: templates.map((t) => t.name).toList(),
          templateIcons: templates.map((t) => t.icon).toList(),
        ),
      );

      setState(() {
        _isAnalyzing = false;
        _analysisResult = combinedResult;
        _statusText = 'AI 分析完成！';
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _statusText = '分析失敗：${e.toString()}';
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      if (kIsWeb) {
        // 網頁版：停止並取得音訊 bytes
        final bytes = await _webRecorder.stop();
        _webAudioBytes = Uint8List.fromList(bytes);
        _timer?.cancel();
        _timer = null;

        final minutes = _recordSeconds ~/ 60;
        final seconds = _recordSeconds % 60;
        final duration =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        setState(() {
          _isRecording = false;
          _lastFilePath = 'web_recording';
          _statusText = '錄音完成！時長 $duration\n按下 AI 分析開始整理。';
        });
      } else {
        final path = await _recorder.stop();
        await _serviceChannel.invokeMethod('stopService');
        _timer?.cancel();
        _timer = null;

        final minutes = _recordSeconds ~/ 60;
        final seconds = _recordSeconds % 60;
        final duration =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        setState(() {
          _isRecording = false;
          _lastFilePath = path;
          _statusText = '錄音完成！時長 $duration\n按下 AI 分析開始整理。';
        });
      }
    } else {
      if (kIsWeb) {
        // 網頁版：直接讓瀏覽器處理權限
        final hasPermission = await _webRecorder.hasPermission();
        if (!hasPermission) {
          setState(() => _statusText = '需要麥克風權限才能錄音');
          return;
        }
        await _webRecorder.start();
      } else {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          setState(() => _statusText = '需要麥克風權限才能錄音');
          return;
        }
        await Permission.notification.request();

        final dir = await getTemporaryDirectory();
        final filePath =
            '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: filePath,
        );
        await _serviceChannel.invokeMethod('startService');
      }

      _recordSeconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });

      setState(() {
        _isRecording = true;
        _analysisResult = null;
        _webAudioBytes = null;
        _statusText = '錄音中...';
        _lastFilePath = null;
      });
    }
  }

  Future<void> _analyzeRecording() async {
    if (_lastFilePath == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _statusText = 'AI 分析中，請稍候...';
    });

    try {
      final apiKey = await KeyStorage.read();
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _isAnalyzing = false;
          _statusText = '找不到 API Key，請重新設定';
        });
        return;
      }

      final audioFile = File(_lastFilePath!);
      final fileSize = await audioFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);

      const modelName = 'gemini-2.5-flash';

      final enhancedPrompt =
          '''
${_selectedTemplate.prompt}

---
請務必使用以下 Markdown 格式美化輸出：
1. **標題層級**：使用 # 代表大標題，## 代表各分類標題。
2. **重點強調**：重要關鍵字請用 **雙星號粗體**。
3. **結構化**：使用清單符號 `*` 或 `1.` 整理要點。
4. **互動感**：待辦清單請使用 `- [ ]` 語法。
5. **視覺分隔**：不同章節間請加入 `---` 分隔線。
''';

      String result;

      if (fileSizeMB <= 20) {
        setState(() => _statusText = '上傳音訊中...');
        final audioBytes = await audioFile.readAsBytes();
        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        final response = await model.generateContent([
          Content.multi([
            DataPart('audio/wav', audioBytes),
            TextPart(enhancedPrompt),
          ]),
        ]);
        result = response.text ?? '無法取得分析結果';
      } else {
        final fileService = GeminiFileService(apiKey);
        setState(
          () => _statusText = '上傳音訊中（${fileSizeMB.toStringAsFixed(0)}MB）...',
        );
        final fileUri = await fileService.uploadAudio(audioFile);

        setState(() => _statusText = '等待 Google 處理音訊...');
        await fileService.waitUntilActive(fileUri);

        setState(() => _statusText = 'AI 分析中，請稍候...');
        result = await fileService.analyzeWithFileUri(
          fileUri,
          enhancedPrompt,
          modelName,
        );
      }

      await HistoryService().save(
        HistoryRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          templateName: _noteName.isEmpty ? _selectedTemplate.name : _noteName,
          templateIcon: _selectedTemplate.icon,
          result: result,
          createdAt: DateTime.now(),
        ),
      );

      setState(() {
        _isAnalyzing = false;
        _analysisResult = result;
        _statusText = 'AI 分析完成！';
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _statusText = '分析失敗：${e.toString()}';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('會議筆記'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.push(context, SlideRoute(page: const SettingsPage())),
            tooltip: '設定',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () =>
                Navigator.push(context, FadeRoute(page: const HistoryPage())),
            tooltip: '歷史紀錄',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // 錄音狀態圖示與計時器
            Center(
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isRecording
                        ? const Icon(
                            Icons.mic,
                            size: 80,
                            color: Colors.red,
                            key: ValueKey('mic_on'),
                          )
                        : Icon(
                            Icons.mic_none,
                            size: 80,
                            color: Theme.of(context).colorScheme.primary,
                            key: const ValueKey('mic_off'),
                          ),
                  ),
                  const SizedBox(height: 16),
                  RecordingVisualizer(isRecording: _isRecording),
                  const SizedBox(height: 16),
                  if (_isRecording) ...[
                    Text(
                      () {
                        final m = _recordSeconds ~/ 60;
                        final s = _recordSeconds % 60;
                        return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                      }(),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 錄音按鈕
            Row(
              children: [
                // 錄音按鈕
                Expanded(
                  child: AnimatedButton(
                    onPressed: _isAnalyzing ? null : _toggleRecording,
                    scaleFactor: 0.97,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing ? null : _toggleRecording,
                      icon: Icon(
                        _isRecording ? Icons.stop : Icons.fiber_manual_record,
                      ),
                      label: Text(_isRecording ? '停止' : '錄音'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 上傳音檔按鈕
                Expanded(
                  child: AnimatedButton(
                    onPressed: _isAnalyzing || _isRecording
                        ? null
                        : _pickAudioFile,
                    scaleFactor: 0.97,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing || _isRecording
                          ? null
                          : _pickAudioFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('上傳音檔'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // AI 分析按鈕（停止後才出現）
            if (_lastFilePath != null) ...[
              const SizedBox(height: 16),
              AnimatedButton(
                onPressed: _isAnalyzing ? null : _showAnalysisSettingsDialog,
                scaleFactor: 0.97,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing
                        ? null
                        : _showAnalysisSettingsDialog,
                    icon: _isAnalyzing
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_isAnalyzing ? 'AI 分析中...' : 'AI 分析'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ],

            // 分析結果
            if (_analysisResult != null) ...[
              const SizedBox(height: 32),
              Row(
                children: [
                  const Text(
                    'AI 整理結果',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedTemplate.icon} ${_selectedTemplate.name}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.3),
                      ),
                    ),
                    child: MarkdownBody(
                      data: _analysisResult!,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        h1: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 2.0,
                        ),
                        p: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        listBullet: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.share_rounded,
                            size: 20,
                            color: Colors.grey,
                          ),
                          tooltip: '分享',
                          onPressed: () {
                            Share.share(
                              _analysisResult!,
                              subject:
                                  '${_selectedTemplate.icon} ${_selectedTemplate.name}',
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.copy_rounded,
                            size: 20,
                            color: Colors.grey,
                          ),
                          tooltip: '複製',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _analysisResult!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已複製到剪貼簿')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
