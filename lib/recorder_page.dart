import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import 'animated_button.dart';
import 'audio_file_stub.dart' if (dart.library.io) 'audio_file_io.dart';
import 'audio_mime.dart';
import 'error_utils.dart';
import 'gemini_file_service.dart';
import 'history_page.dart';
import 'history_service.dart';
import 'key_storage.dart';
import 'model_settings.dart';
import 'pending_audio_service.dart';
import 'platform_support_stub.dart'
    if (dart.library.io) 'platform_support_io.dart';
import 'recording_visualizer.dart';
import 'settings_page.dart';
import 'templates.dart';
import 'transitions.dart';
import 'update_service.dart';
import 'web_recorder.dart' if (dart.library.io) 'web_recorder_stub.dart';

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  static const _serviceChannel = MethodChannel(
    'com.example.meeting_notes/recording_service',
  );
  static const _inlineLimitBytes = 20 * 1024 * 1024;

  final AudioRecorder _recorder = AudioRecorder();
  final WebRecorder _webRecorder = WebRecorder();
  Timer? _timer;

  bool _isRecording = false;
  bool _isAnalyzing = false;
  int _recordSeconds = 0;

  String _statusText = '準備錄音或上傳音檔';
  String? _lastFilePath;
  Uint8List? _webAudioBytes;
  String? _uploadedFileName;
  String? _currentMimeType;
  PendingAudio? _pendingAudio;
  String? _analysisResult;
  MeetingTemplate _selectedTemplate = kTemplates[0];

  @override
  void initState() {
    super.initState();
    _restorePendingAudio();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) UpdateService.checkForUpdate(context);
    });
  }

  bool get _hasAudio => _lastFilePath != null || _webAudioBytes != null;

  Future<void> _restorePendingAudio() async {
    final pending = await PendingAudioService.load();
    if (pending == null || !mounted) return;

    setState(() {
      _pendingAudio = pending;
      _uploadedFileName = pending.fileName;
      _currentMimeType = pending.mimeType;
      if (pending.isWebBytes) {
        _webAudioBytes = pending.bytes;
        _lastFilePath = pending.bytes == null ? null : 'web_pending';
      } else {
        _lastFilePath = pending.path;
        _webAudioBytes = null;
      }
      _statusText = '偵測到尚未完成分析的音檔，是否重新分析？';
    });
  }

  Future<void> _savePendingWebBytes(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    final persisted = await PendingAudioService.saveWebBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    _pendingAudio = PendingAudio(
      source: 'web_bytes',
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      createdAt: DateTime.now(),
    );
    if (!persisted) {
      _statusText = '音檔已暫時保留，可直接重試分析。Web 版大型音檔重新整理後無法復原。';
    }
  }

  Future<void> _savePendingNativePath(
    String path,
    String fileName,
    String mimeType,
  ) async {
    await PendingAudioService.saveNative(
      path: path,
      fileName: fileName,
      mimeType: mimeType,
    );
    _pendingAudio = PendingAudio(
      source: 'native_path',
      fileName: fileName,
      mimeType: mimeType,
      path: path,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _clearPendingAudio({bool deleteFile = false}) async {
    final path = _pendingAudio?.path;
    await PendingAudioService.clear();
    if (deleteFile && path != null) {
      await deleteAudioFile(path);
    }
    if (!mounted) return;
    setState(() {
      _pendingAudio = null;
      _lastFilePath = null;
      _webAudioBytes = null;
      _uploadedFileName = null;
      _currentMimeType = null;
      _statusText = '準備錄音或上傳音檔';
    });
  }

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
          title: const Text('分析設定'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '筆記名稱',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '請輸入筆記名稱',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '選擇模板（可複選）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  '每個模板都會產生一份分析結果',
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
                              textAlign: TextAlign.center,
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
    final mimeType = AudioMime.fromFileName(file.name);
    if (mimeType == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('不支援此音檔格式。請使用：${AudioMime.supportedList()}')),
        );
      }
      return;
    }

    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _statusText = '無法讀取音檔，請重新選擇。');
        return;
      }
      await _savePendingWebBytes(bytes, file.name, mimeType);
      setState(() {
        _uploadedFileName = file.name;
        _currentMimeType = mimeType;
        _webAudioBytes = bytes;
        _lastFilePath = 'web_upload';
        _analysisResult = null;
        _statusText = _statusText.startsWith('音檔已暫時保留')
            ? _statusText
            : '已選擇 ${file.name}\n可開始 AI 分析';
      });
      return;
    }

    if (file.path == null) {
      setState(() => _statusText = '無法讀取音檔路徑，請重新選擇。');
      return;
    }

    final pendingPath = await copyAudioToPending(file.path!, file.name);
    await _savePendingNativePath(pendingPath, file.name, mimeType);
    setState(() {
      _uploadedFileName = file.name;
      _currentMimeType = mimeType;
      _lastFilePath = pendingPath;
      _webAudioBytes = null;
      _analysisResult = null;
      _statusText = '已選擇 ${file.name}\n可開始 AI 分析';
    });
  }

  Future<void> _analyzeWithTemplates(
    List<MeetingTemplate> templates,
    String noteName,
  ) async {
    if (!_hasAudio) return;

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
          _statusText = '尚未設定 API Key，請先到設定輸入。';
        });
        return;
      }

      final modelName = await ModelSettings.read();
      final mimeType = _currentMimeType ?? _pendingAudio?.mimeType;
      if (mimeType == null) {
        throw GeminiServiceException('不支援此音檔格式');
      }

      Uint8List? audioBytes;
      String? fileUri;
      final fileService = GeminiFileService(apiKey);

      if (kIsWeb) {
        audioBytes = _webAudioBytes;
        if (audioBytes == null) {
          throw GeminiServiceException('Web 音檔已不存在，請重新選擇。');
        }
        if (audioBytes.length > _inlineLimitBytes) {
          setState(() => _statusText = '音檔較大，正在上傳...');
          fileUri = await fileService.uploadAudioBytes(
            audioBytes,
            mimeType: mimeType,
            fileName: _uploadedFileName ?? 'recording.webm',
          );
          audioBytes = null;
          setState(() => _statusText = '音檔處理中...');
          await fileService.waitUntilActive(fileUri);
        }
      } else {
        final path = _lastFilePath;
        if (path == null) {
          throw GeminiServiceException('音檔已不存在，請重新選擇。');
        }
        final fileSize = await audioFileLength(path);
        if (fileSize <= _inlineLimitBytes) {
          audioBytes = await readAudioFileBytes(path);
        } else {
          setState(() => _statusText = '音檔較大，正在上傳...');
          fileUri = await fileService.uploadAudioPath(
            path,
            mimeType: mimeType,
            fileName: _uploadedFileName ?? 'recording.wav',
          );
          setState(() => _statusText = '音檔處理中...');
          await fileService.waitUntilActive(fileUri);
        }
      }

      // ── 第一步：產生逐字稿（含說話者識別）──
      setState(() => _statusText = '正在產生逐字稿...');
      String transcript;
      if (audioBytes != null) {
        transcript = await _generateInline(
          apiKey: apiKey,
          modelName: modelName,
          mimeType: mimeType,
          audioBytes: audioBytes,
          prompt: _transcriptPrompt(),
        );
      } else {
        transcript = await fileService.analyzeWithFileUri(
          fileUri!,
          _transcriptPrompt(),
          modelName,
          mimeType: mimeType,
        );
      }

      // ── 第二步：依選擇的模板逐一分析 ──
      final results = <String>[];
      for (int i = 0; i < templates.length; i++) {
        final template = templates[i];
        setState(
          () => _statusText =
              'AI 分析中 ${i + 1}/${templates.length}：${template.name}',
        );
        final prompt = _enhancedPrompt(template);
        if (audioBytes != null) {
          final result = await _generateInline(
            apiKey: apiKey,
            modelName: modelName,
            mimeType: mimeType,
            audioBytes: audioBytes,
            prompt: prompt,
          );
          results.add(result);
        } else {
          final result = await fileService.analyzeWithFileUri(
            fileUri!,
            prompt,
            modelName,
            mimeType: mimeType,
          );
          results.add(result);
        }
      }

      final combinedResult = results.join('\n\n---\n\n');
      _selectedTemplate = templates.first;
      await HistoryService().save(
        HistoryRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          templateName: noteName,
          templateIcon: templates.map((t) => t.icon).join(''),
          result: combinedResult,
          createdAt: DateTime.now(),
          templateNames: templates.map((t) => t.name).toList(),
          templateIcons: templates.map((t) => t.icon).toList(),
          transcript: transcript,
        ),
      );

      final pendingPath = _pendingAudio?.path;
      await PendingAudioService.clear();
      if (pendingPath != null) {
        await deleteAudioFile(pendingPath);
      }
      setState(() {
        _pendingAudio = null;
        _lastFilePath = null;
        _webAudioBytes = null;
        _uploadedFileName = null;
        _currentMimeType = null;
        _isAnalyzing = false;
        _analysisResult = combinedResult;
        _statusText = 'AI 分析完成';
      });
    } catch (error) {
      debugPrint('Analysis failed: ${sanitizeForDebug(error)}');
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _statusText = sanitizeErrorForUser(error);
      });
    }
  }

  Future<String> _generateInline({
    required String apiKey,
    required String modelName,
    required String mimeType,
    required Uint8List audioBytes,
    required String prompt,
  }) async {
    return _withInlineRetry(() async {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final response = await model
          .generateContent([
            Content.multi([DataPart(mimeType, audioBytes), TextPart(prompt)]),
          ])
          .timeout(const Duration(seconds: 90));
      return response.text ?? '未取得分析結果';
    });
  }

  Future<String> _withInlineRetry(Future<String> Function() action) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } catch (error) {
        if (!isTemporaryFailure(error) || attempt == 2) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw GeminiServiceException('暫時無法連線', retryable: true);
  }

  String _transcriptPrompt() {
    return '''
你是一位專業的逐字稿記錄員。請仔細聆聽這段錄音，產生完整的繁體中文逐字稿。

規則如下：
1. 盡量還原錄音中說話的每一句話，不要省略或改寫。
2. 若錄音中有多位說話者，請以「說話者A：」「說話者B：」等方式標示，若能辨識說話者身份（例如老師、學生、主持人、受訪者等）則直接以身份標示。
3. 若某段錄音不清楚無法辨識，請以「【聽不清楚】」標示。
4. 不需要加入任何格式標題，直接輸出純文字逐字稿即可。
5. 語氣詞（例如「嗯」「啊」「那個」）可適度保留以反映真實對話，但過多重複時可酌情省略。
''';
  }

  String _enhancedPrompt(MeetingTemplate template) {
    return '''
${template.prompt}

---
請用繁體中文整理成清楚的 Markdown 筆記：
1. 使用 # 與 ## 建立層級標題。
2. 使用 **粗體** 標示重點。
3. 使用條列或編號整理資訊。
4. 行動項目請使用 - [ ] 格式。
5. 不同段落可使用 --- 分隔。
''';
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      if (kIsWeb) {
        final bytes = Uint8List.fromList(await _webRecorder.stop());
        await _savePendingWebBytes(bytes, 'recording.webm', 'audio/webm');
        _timer?.cancel();
        _timer = null;

        setState(() {
          _isRecording = false;
          _uploadedFileName = 'recording.webm';
          _currentMimeType = 'audio/webm';
          _webAudioBytes = bytes;
          _lastFilePath = 'web_recording';
          _statusText = '錄音完成，可開始 AI 分析';
        });
      } else {
        final path = await _recorder.stop();
        if (isAndroidPlatform) {
          await _serviceChannel.invokeMethod('stopService');
        }
        _timer?.cancel();
        _timer = null;

        if (path != null) {
          final fileName =
              'recording_${DateTime.now().millisecondsSinceEpoch}.wav';
          final pendingPath = await copyAudioToPending(path, fileName);
          await _savePendingNativePath(pendingPath, fileName, 'audio/wav');
          setState(() {
            _uploadedFileName = fileName;
            _currentMimeType = 'audio/wav';
            _lastFilePath = pendingPath;
            _webAudioBytes = null;
            _statusText = '錄音完成，可開始 AI 分析';
          });
        }

        setState(() => _isRecording = false);
      }
      return;
    }

    if (kIsWeb) {
      final hasPermission = await _webRecorder.hasPermission();
      if (!hasPermission) {
        setState(() => _statusText = '需要麥克風權限才能錄音。');
        return;
      }
      await _webRecorder.start();
    } else {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() => _statusText = '需要麥克風權限才能錄音。');
        return;
      }
      if (isAndroidPlatform) {
        await Permission.notification.request();
      }

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
      if (isAndroidPlatform) {
        await _serviceChannel.invokeMethod('startService');
      }
    }

    _recordSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    setState(() {
      _isRecording = true;
      _analysisResult = null;
      _webAudioBytes = null;
      _lastFilePath = null;
      _pendingAudio = null;
      _statusText = '錄音中...';
    });
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
                      _formatDuration(_recordSeconds),
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
            const SizedBox(height: 24),
            if (_pendingAudio != null && !_isRecording) _pendingAudioCard(),
            if (_pendingAudio != null && !_isRecording)
              const SizedBox(height: 16),
            Row(
              children: [
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
            if (_hasAudio) ...[
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
                        ).colorScheme.outline.withValues(alpha: 0.3),
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

  Widget _pendingAudioCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '偵測到尚未完成分析的音檔，是否重新分析？',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _pendingAudio?.fileName ?? 'pending audio',
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing
                        ? null
                        : _showAnalysisSettingsDialog,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新分析'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _clearPendingAudio(deleteFile: true),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('刪除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }
}
