import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
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
  bool _isStopping = false;
  // true 代表「不知道原生/瀏覽器端的錄音器現在是不是真的已經停止」
  // （stop() 逾時或丟出非預期例外）。在搞清楚之前鎖住所有錄音操作，
  // 避免在舊的錄音工作階段狀態不明的情況下又疊加一個新的。
  bool _stopResultUnknown = false;
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

  /// 在新的錄音／上傳即將取代目前的 pending 音檔之前呼叫，
  /// 避免舊的 pending 音檔實體檔案變成沒人參照的孤兒檔案。
  Future<void> _deleteOldPendingFileIfAny() async {
    final oldPath = _pendingAudio?.path;
    if (oldPath != null) {
      await deleteAudioFile(oldPath);
    }
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
                            const SizedBox(height: 3),
                            Text(
                              template.description,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onPrimary.withOpacity(0.75)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.55),
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
      await _deleteOldPendingFileIfAny();
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

    // 確定新檔案可用之後，才清掉舊的 pending 音檔，避免挑選失敗時
    // 平白把使用者原本還沒分析的舊音檔刪掉。
    await _deleteOldPendingFileIfAny();
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

      // ── 分析：單一模板照舊；多模板則合併成單一請求送出 ──
      // (多模板若逐一呼叫，音訊內容等於被重複計費 N 次；改成一次請求、
      //  請模型依序輸出每個模板的段落，再依標記切開，音訊只需被處理一次。)
      final List<String> results;
      if (templates.length == 1) {
        final template = templates.first;
        setState(() => _statusText = 'AI 分析中：${template.name}');
        final prompt = _enhancedPrompt(template);
        final raw = audioBytes != null
            ? await _generateInline(
                apiKey: apiKey,
                modelName: modelName,
                mimeType: mimeType,
                audioBytes: audioBytes,
                prompt: prompt,
              )
            : await fileService.analyzeWithFileUri(
                fileUri!,
                prompt,
                modelName,
                mimeType: mimeType,
              );
        results = [raw];
      } else {
        setState(
          () => _statusText = 'AI 分析中（單次請求同時處理 ${templates.length} 個模板）...',
        );
        final prompt = _combinedPrompt(templates);
        // 一次要產生多個模板份量的內容，回應會比單模板長，適度拉長逾時時間。
        final extendedTimeout = Duration(
          seconds: 90 + 45 * (templates.length - 1),
        );
        final raw = audioBytes != null
            ? await _generateInline(
                apiKey: apiKey,
                modelName: modelName,
                mimeType: mimeType,
                audioBytes: audioBytes,
                prompt: prompt,
                timeout: extendedTimeout,
              )
            : await fileService.analyzeWithFileUri(
                fileUri!,
                prompt,
                modelName,
                mimeType: mimeType,
                timeout: extendedTimeout,
              );
        results = _splitCombinedResult(raw, templates.length);
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
    Duration timeout = const Duration(seconds: 90),
  }) async {
    return _withInlineRetry(() async {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final response = await model
          .generateContent([
            Content.multi([DataPart(mimeType, audioBytes), TextPart(prompt)]),
          ])
          .timeout(timeout);
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

  static final RegExp _taskMarkerPattern = RegExp(r'===TASK_(\d+)===');

  /// 將多個模板的需求合併成單一個 prompt，讓 Gemini 一次分析同一段音訊、
  /// 依序產生每個模板各自的段落，避免每個模板都重新送一次音訊而重複計費。
  String _combinedPrompt(List<MeetingTemplate> templates) {
    final buffer = StringBuffer()
      ..writeln('你是一位多功能的錄音分析助理。')
      ..writeln('這段錄音需要「同時」完成以下 ${templates.length} 項各自獨立的分析任務。')
      ..writeln('請務必嚴格遵守以下規則：')
      ..writeln(
        '1. 每一項任務開始前，請先單獨一行輸出對應的任務標記，格式為 ===TASK_數字===（例如 ===TASK_1===），標記文字請完全照抄、不要更動或翻譯。',
      )
      ..writeln('2. 標記後才開始撰寫該任務的完整分析內容，各任務內容需彼此獨立，不要互相參照或重複。')
      ..writeln('3. ${templates.length} 項任務都必須完成，不可省略、合併或跳過任何一項。')
      ..writeln();

    for (int i = 0; i < templates.length; i++) {
      buffer
        ..writeln('===TASK_${i + 1}===')
        ..writeln('【任務 ${i + 1}：${templates[i].name}】')
        ..writeln(templates[i].prompt)
        ..writeln();
    }

    buffer
      ..writeln('---')
      ..writeln('每一項任務的內容都請用繁體中文整理成清楚的 Markdown 筆記：')
      ..writeln('1. 使用 # 與 ## 建立層級標題。')
      ..writeln('2. 使用 **粗體** 標示重點。')
      ..writeln('3. 使用條列或編號整理資訊。')
      ..writeln('4. 行動項目請使用 - [ ] 格式。')
      ..writeln('5. 不同段落可使用 --- 分隔（但不要拿來取代 ===TASK_數字=== 標記）。');

    return buffer.toString();
  }

  /// 依 ===TASK_數字=== 標記把單一回應切回每個模板各自的段落。
  /// 如果模型沒有照格式輸出（標記數量不足），就整段當作單一結果，
  /// 至少讓使用者拿到完整內容，不會因為格式解析失敗而整批報錯。
  List<String> _splitCombinedResult(String raw, int expectedCount) {
    final matches = _taskMarkerPattern.allMatches(raw).toList();
    if (matches.length < expectedCount) {
      return [raw.trim()];
    }

    final sections = <String>[];
    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : raw.length;
      final section = raw.substring(start, end).trim();
      if (section.isNotEmpty) sections.add(section);
    }
    return sections.isEmpty ? [raw.trim()] : sections;
  }

  Future<void> _toggleRecording() async {
    // 狀態不明時完全鎖住（按鈕本身也會停用，這裡是防呆用的第二層）。
    if (_stopResultUnknown) return;

    if (_isRecording) {
      // 防止在原生 stop() 還沒回應時被連續點擊：連點會讓 stop() 被重複呼叫，
      // 可能讓錄音器進入不明狀態，讓「按了沒反應」變得更難恢復。
      if (_isStopping) return;
      setState(() => _isStopping = true);

      if (kIsWeb) {
        await _stopWebRecording();
      } else {
        await _stopNativeRecording();
      }
      return;
    }

    await _startRecording();
  }

  /// 停止原生（Android）錄音。
  ///
  /// `Future.timeout()` 只是讓 Dart 端不再等待，並不會真的取消底層仍在執行
  /// 的原生呼叫——逾時或丟出非預期例外時，我們沒辦法分辨錄音器到底是
  /// 「其實已經停了、只是回應遺失」還是「真的還在錄」。在搞清楚之前絕對不能
  /// 讓使用者開始新錄音（可能疊加在還沒真正結束的舊錄音上），所以進入
  /// [_stopResultUnknown] 鎖定狀態，而不是直接恢復成平常的待機畫面。
  Future<void> _stopNativeRecording() async {
    String? rawPath;
    Object? stopError;
    var nativeStopConfirmed = false;

    try {
      rawPath = await _recorder.stop().timeout(const Duration(seconds: 15));
      nativeStopConfirmed = true;
    } catch (e) {
      stopError = e;
    }

    // 停前景服務、取消計時器是「我方自己」的狀態清理，跟 record 套件內部
    // 是否真的停止錄音無關；不應該因為上面 stop() 失敗就被跳過，
    // 否則前景通知可能永遠留著、計時畫面也會卡住。用巢狀 try/finally
    // 確保這兩步一定會執行，彼此也不會因為對方失敗而被跳過。
    try {
      if (isAndroidPlatform) {
        try {
          await _serviceChannel.invokeMethod('stopService');
        } catch (e) {
          debugPrint('[Recorder] stopService 失敗（不影響錄音狀態判定）: $e');
        }
      }
    } finally {
      _timer?.cancel();
      _timer = null;
    }

    if (!nativeStopConfirmed) {
      debugPrint('[Recorder] 原生 stop() 無法確認結果: $stopError');
      if (mounted) {
        setState(() {
          _isStopping = false;
          _isRecording = false;
          _stopResultUnknown = true;
          _statusText = stopError is TimeoutException
              ? '停止錄音逾時，無法確認錄音是否已經真的停止。為避免疊加錄音，請重新開啟 App 後再操作。'
              : '停止錄音時發生非預期錯誤，無法確認錄音狀態（$stopError）。請重新開啟 App 後再操作。';
        });
      }
      return;
    }

    if (mounted) setState(() => _statusText = '處理錄音檔中…');

    if (rawPath != null) {
      try {
        final fileName =
            'recording_${DateTime.now().millisecondsSinceEpoch}.wav';
        // 錄音檔是 App 自己在暫存目錄產生的，搬移即可，不需要保留原始檔。
        final pendingPath = await moveAudioToPending(rawPath, fileName);
        await _savePendingNativePath(pendingPath, fileName, 'audio/wav');
        if (mounted) {
          setState(() {
            _uploadedFileName = fileName;
            _currentMimeType = 'audio/wav';
            _lastFilePath = pendingPath;
            _webAudioBytes = null;
            _statusText = '錄音完成，可開始 AI 分析';
          });
        }
      } catch (e) {
        // 錄音本身確定已經停止、檔案也確定還在 rawPath，只是搬移／保存
        // pending 這一步失敗了。不能靜默吞掉、讓使用者以為錄音不見了，
        // 所以把原始路徑留在畫面訊息裡，而不是只把按鈕恢復正常。
        debugPrint('[Recorder] 保存 pending 音檔失敗: $e');
        if (mounted) {
          setState(() {
            _statusText = '錄音已停止，但儲存時發生錯誤：$e\n原始檔案仍保留在：$rawPath';
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isStopping = false;
      });
    }
  }

  /// 停止 Web 錄音，邏輯對應 [_stopNativeRecording]（見其註解說明逾時的限制）。
  Future<void> _stopWebRecording() async {
    List<int>? rawBytes;
    Object? stopError;
    var stopConfirmed = false;

    try {
      rawBytes = await _webRecorder.stop().timeout(const Duration(seconds: 15));
      stopConfirmed = true;
    } catch (e) {
      stopError = e;
    }

    _timer?.cancel();
    _timer = null;

    if (!stopConfirmed) {
      debugPrint('[Recorder] Web stop() 無法確認結果: $stopError');
      if (mounted) {
        setState(() {
          _isStopping = false;
          _isRecording = false;
          _stopResultUnknown = true;
          _statusText = stopError is TimeoutException
              ? '停止錄音逾時，無法確認錄音是否已經真的停止。請重新整理頁面後再操作。'
              : '停止錄音時發生非預期錯誤，無法確認錄音狀態（$stopError）。請重新整理頁面後再操作。';
        });
      }
      return;
    }

    if (mounted) setState(() => _statusText = '處理錄音檔中…');

    try {
      final bytes = Uint8List.fromList(rawBytes!);
      await _savePendingWebBytes(bytes, 'recording.webm', 'audio/webm');
      if (mounted) {
        setState(() {
          _uploadedFileName = 'recording.webm';
          _currentMimeType = 'audio/webm';
          _webAudioBytes = bytes;
          _lastFilePath = 'web_recording';
          _statusText = '錄音完成，可開始 AI 分析';
        });
      }
    } catch (e) {
      // Web 版沒有檔案路徑可以留給使用者手動復原（資料是記憶體中的 bytes），
      // 只能誠實告知保存失敗，請使用者重新錄一次。
      debugPrint('[Recorder] 保存 Web 錄音失敗: $e');
      if (mounted) {
        setState(() => _statusText = '錄音已停止，但儲存時發生錯誤：$e\n請重新錄音一次。');
      }
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isStopping = false;
      });
    }
  }

  Future<void> _startRecording() async {
    if (kIsWeb) {
      final hasPermission = await _webRecorder.hasPermission();
      if (!hasPermission) {
        setState(() => _statusText = '需要麥克風權限才能錄音。');
        return;
      }
      try {
        await _webRecorder.start();
      } catch (e) {
        if (mounted) setState(() => _statusText = '錄音啟動失敗：$e');
        return;
      }
    } else {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() => _statusText = '需要麥克風權限才能錄音。');
        return;
      }
      if (isAndroidPlatform) {
        await Permission.notification.request();
      }

      // 注意：這裡「不能」用 getTemporaryDirectory()（對應 Android 的 cache
      // 目錄）。cache 目錄的檔案系統隨時可能自行清掉，不會通知 App——
      // 錄音檔案開著持續寫入時不會立刻出錯，但只要錄得夠久（實測約 90
      // 分鐘以上就會發生），系統可能在錄音過程中把目錄項清掉，
      // 等 stop() 關閉檔案後，資料就真的不見了，recorder 的收尾或後續
      // 搬移動作就會對著一個已經不存在的路徑操作，行為不可預期（曾經是
      // 停止按鈕卡死的成因之一）。改用應用程式自己的持久化儲存空間，
      // 系統不會中途清除，不管錄多久都不受影響。
      final filePath = await activeRecordingFilePath(
        'recording_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      try {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: filePath,
        );
      } catch (e) {
        if (mounted) setState(() => _statusText = '錄音啟動失敗：$e');
        return;
      }

      if (isAndroidPlatform) {
        try {
          await _serviceChannel.invokeMethod('startService');
        } catch (e) {
          // 錄音器已經開始錄了，但前景服務沒有啟動成功——App 進背景很可能
          // 被系統中斷在錄到一半的狀態。與其留著這種不一致的狀態，
          // 補償性地立刻停止這次錄音，讓使用者看到明確訊息、從乾淨狀態重來。
          debugPrint('[Recorder] 前景服務啟動失敗，補償性停止錄音: $e');
          try {
            await _recorder.stop();
          } catch (stopErr) {
            // 補償停止也失敗了——比單純的啟動失敗更不確定，一樣要鎖住。
            debugPrint('[Recorder] 補償性停止也失敗: $stopErr');
            if (mounted) {
              setState(() {
                _stopResultUnknown = true;
                _statusText = '錄音服務啟動失敗，且補償性停止也失敗，無法確認錄音狀態。請重新開啟 App。';
              });
            }
            return;
          }
          if (mounted) {
            setState(() => _statusText = '錄音服務啟動失敗，已取消本次錄音，請再試一次。');
          }
          return;
        }
      }
    }

    // 錄音已經確定成功開始了，這時候才清掉舊的 pending 音檔實體檔案。
    // 放在權限請求「之前」的話，一旦使用者拒絕權限、沒有真的開始錄音，
    // 反而會平白把使用者原本還沒分析的舊錄音刪掉。
    await _deleteOldPendingFileIfAny();

    _recordSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    if (mounted) {
      setState(() {
        _isRecording = true;
        _analysisResult = null;
        _webAudioBytes = null;
        _lastFilePath = null;
        _pendingAudio = null;
        _statusText = '錄音中...';
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
                    onPressed:
                        (_isAnalyzing || _isStopping || _stopResultUnknown)
                        ? null
                        : _toggleRecording,
                    scaleFactor: 0.97,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_isAnalyzing || _isStopping || _stopResultUnknown)
                          ? null
                          : _toggleRecording,
                      icon: _isStopping
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _stopResultUnknown
                                  ? Icons.warning_amber_rounded
                                  : (_isRecording
                                        ? Icons.stop
                                        : Icons.fiber_manual_record),
                            ),
                      label: Text(
                        _stopResultUnknown
                            ? '狀態不明，請重啟 App'
                            : (_isStopping
                                  ? '停止中…'
                                  : (_isRecording ? '停止' : '錄音')),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _stopResultUnknown
                            ? Colors.grey
                            : (_isRecording
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary),
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
                    onPressed:
                        (_isAnalyzing || _isRecording || _stopResultUnknown)
                        ? null
                        : _pickAudioFile,
                    scaleFactor: 0.97,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_isAnalyzing || _isRecording || _stopResultUnknown)
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
