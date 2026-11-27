import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'analysis_timeouts.dart';
import 'audio_file_stub.dart' if (dart.library.io) 'audio_file_io.dart';
import 'error_utils.dart';
import 'gemini_response.dart';

/// Google 端某個已上傳音檔目前的狀態。
enum RemoteFileState { active, processing, failed, gone }

class GeminiFileService {
  static const _proxyBase =
      'https://gemini-proxy.sean9611231123.workers.dev/proxy';
  static const _directBase = 'https://generativelanguage.googleapis.com';
  static const _requestTimeout = Duration(seconds: 60);

  /// 上傳「連線中斷」類錯誤的最大重試次數（逾時不重試，見 [uploadAudioBytes]）。
  static const _uploadMaxRetries = 2;

  final String apiKey;
  final http.Client Function() _newClient;

  /// [clientFactory] 供測試注入假的 HTTP 連線；正式使用時不需傳入。
  GeminiFileService(this.apiKey, {http.Client Function()? clientFactory})
    : _newClient = clientFactory ?? http.Client.new;

  String get _base => kIsWeb ? _proxyBase : _directBase;

  Future<String> uploadAudioPath(
    String path, {
    required String mimeType,
    required String fileName,
    AnalysisDiagnostics? diag,
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await readAudioFileBytes(path);
    return uploadAudioBytes(
      bytes,
      mimeType: mimeType,
      fileName: fileName,
      diag: diag,
      onProgress: onProgress,
    );
  }

  /// 上傳音檔，回傳 Google 端的 fileUri。
  ///
  /// 逾時依檔案大小計算（見 [AnalysisTimeouts.upload]）。
  /// **上傳逾時不重試**：逾時代表這個大小在這個網速下傳不完，重傳整份只是
  /// 重複失敗，還可能與尚未中止的舊上傳搶頻寬。只有連線中斷、伺服器暫時
  /// 錯誤這類「很快就失敗」的情況才重試。
  ///
  /// 傳入 [onProgress] 時（網頁版除外，瀏覽器端無法取得上傳進度），
  /// 會以串流方式上傳並回報「已送出位元組／總位元組」，逾時規則也改為
  /// 「連續一段時間完全沒有進度」才算逾時。每次（重試）開始都會先回報 0。
  Future<String> uploadAudioBytes(
    Uint8List bytes, {
    required String mimeType,
    required String fileName,
    AnalysisDiagnostics? diag,
    void Function(int sent, int total)? onProgress,
  }) async {
    final trackProgress = onProgress != null && !kIsWeb;
    final uploadTimeout = AnalysisTimeouts.upload(bytes.length);
    diag?.beginStage(
      AnalysisStage.uploading,
      timeout: trackProgress ? AnalysisTimeouts.uploadOverallCap : uploadTimeout,
      timeoutRule: trackProgress
          ? '連續 ${AnalysisTimeouts.uploadStall.inSeconds} 秒無上傳進度'
                '（總上限 ${AnalysisTimeouts.uploadOverallCap.inMinutes} 分鐘）'
          : null,
    );

    for (var attempt = 0; ; attempt++) {
      diag?.noteAttempt();
      try {
        return await _uploadBytesOnce(
          bytes,
          mimeType,
          fileName,
          uploadTimeout,
          trackProgress ? onProgress : null,
        );
      } catch (error) {
        if (isTimeoutFailure(error) ||
            !isTemporaryFailure(error) ||
            attempt >= _uploadMaxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }

  Future<String> _uploadBytesOnce(
    Uint8List bytes,
    String mimeType,
    String displayName,
    Duration uploadTimeout,
    void Function(int sent, int total)? onProgress,
  ) async {
    // 用專屬的 Client：逾時後 close() 會真的中止進行中的請求，
    // 而不是只讓 Dart 端不再等待（Future.timeout 不會取消底層請求）。
    final client = _newClient();
    try {
      final initResponse = await client
          .post(
            Uri.parse(
              '$_base/upload/v1beta/files'
              '?key=$apiKey&uploadType=resumable',
            ),
            headers: {
              'X-Goog-Upload-Protocol': 'resumable',
              'X-Goog-Upload-Command': 'start',
              'X-Goog-Upload-Header-Content-Length': bytes.length.toString(),
              'X-Goog-Upload-Header-Content-Type': mimeType,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'file': {'display_name': displayName},
            }),
          )
          .timeout(_requestTimeout);

      if (initResponse.statusCode != 200) {
        throw exceptionFromResponse(initResponse, '音檔上傳初始化失敗');
      }

      final uploadUrl = initResponse.headers['x-goog-upload-url'];
      if (uploadUrl == null) {
        throw GeminiServiceException('音檔上傳初始化失敗');
      }

      final finalUploadUrl = kIsWeb
          ? uploadUrl.replaceFirst(_directBase, _proxyBase)
          : uploadUrl;

      final uploadHeaders = {
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
      };
      final http.Response uploadResponse;
      if (onProgress != null) {
        uploadResponse = await _sendWithProgress(
          client,
          Uri.parse(finalUploadUrl),
          uploadHeaders,
          bytes,
          onProgress,
        );
      } else {
        uploadResponse = await client
            .post(
              Uri.parse(finalUploadUrl),
              headers: {
                'Content-Length': bytes.length.toString(),
                ...uploadHeaders,
              },
              body: bytes,
            )
            .timeout(uploadTimeout);
      }

      if (uploadResponse.statusCode != 200) {
        throw exceptionFromResponse(uploadResponse, '音檔上傳失敗');
      }

      final responseJson = jsonDecode(uploadResponse.body);
      final fileUri = responseJson['file']?['uri'] as String?;
      if (fileUri == null) {
        throw GeminiServiceException('音檔上傳失敗');
      }

      return fileUri;
    } finally {
      client.close();
    }
  }

  /// 以串流方式送出上傳內容並回報進度。
  ///
  /// 內容是邊被系統取走邊產生的（有背壓），所以「已送出」的數字大致等於
  /// 交給系統去送的位元組，不會一下子就衝到 100%。逾時規則：
  /// - 傳送中：連續 [AnalysisTimeouts.uploadStall] 沒有任何進度；
  /// - 全數送出後：等伺服器確認最多 [AnalysisTimeouts.uploadFinalizeWait]；
  /// - 另有總時間安全上限 [AnalysisTimeouts.uploadOverallCap]。
  /// 逾時時會 close() 連線，真的中止請求。
  Future<http.Response> _sendWithProgress(
    http.Client client,
    Uri url,
    Map<String, String> headers,
    Uint8List bytes,
    void Function(int sent, int total) onProgress,
  ) {
    final total = bytes.length;
    final watch = Stopwatch()..start();
    var lastProgressAt = Duration.zero;
    var allSent = false;
    final completer = Completer<http.Response>();

    final request = _ProgressRequest('POST', url, bytes, (sent) {
      lastProgressAt = watch.elapsed;
      if (sent >= total) allSent = true;
      onProgress(sent, total);
    })..headers.addAll(headers);

    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (completer.isCompleted) return;
      final idle = watch.elapsed - lastProgressAt;
      final idleLimit = allSent
          ? AnalysisTimeouts.uploadFinalizeWait
          : AnalysisTimeouts.uploadStall;
      final overCap = watch.elapsed > AnalysisTimeouts.uploadOverallCap;
      if (idle > idleLimit || overCap) {
        completer.completeError(
          TimeoutException(
            '上傳逾時',
            overCap ? AnalysisTimeouts.uploadOverallCap : idleLimit,
          ),
        );
        client.close();
      }
    });

    client
        .send(request)
        .then(http.Response.fromStream)
        .then(
          (response) {
            if (!completer.isCompleted) completer.complete(response);
          },
          onError: (Object error, StackTrace stack) {
            if (!completer.isCompleted) completer.completeError(error, stack);
          },
        );

    return completer.future.whenComplete(timer.cancel);
  }

  String _fileNameFromUri(String fileUri) => fileUri.replaceFirst(
    'https://generativelanguage.googleapis.com/v1beta/',
    '',
  );

  /// 查詢先前上傳的檔案是否還在、目前是什麼狀態。
  /// 403／404 視為「已不存在」（過期、被刪除，或換了不同的 API Key）。
  Future<RemoteFileState> getFileState(String fileUri) async {
    final fileName = _fileNameFromUri(fileUri);
    final response = await _withRetry(
      () => http
          .get(Uri.parse('$_base/v1beta/$fileName?key=$apiKey'))
          .timeout(_requestTimeout),
    );

    if (response.statusCode == 403 || response.statusCode == 404) {
      return RemoteFileState.gone;
    }
    if (response.statusCode != 200) {
      throw exceptionFromResponse(response, '查詢音檔狀態失敗');
    }

    final json = jsonDecode(response.body);
    final fileData = json['file'] ?? json;
    switch (fileData['state'] as String?) {
      case 'ACTIVE':
        return RemoteFileState.active;
      case 'FAILED':
        return RemoteFileState.failed;
      default:
        return RemoteFileState.processing;
    }
  }

  /// 等待 Google 把音檔處理到 ACTIVE。上限由呼叫端依檔案大小決定
  /// （見 [AnalysisTimeouts.processing]）；前 30 秒每 5 秒查一次，之後每 10 秒。
  Future<void> waitUntilActive(
    String fileUri, {
    Duration? maxWait,
    AnalysisDiagnostics? diag,
  }) async {
    final limit = maxWait ?? AnalysisTimeouts.processing(0);
    diag?.beginStage(AnalysisStage.processing, timeout: limit);

    final fileName = _fileNameFromUri(fileUri);
    final watch = Stopwatch()..start();

    while (watch.elapsed < limit) {
      await Future.delayed(
        watch.elapsed < const Duration(seconds: 30)
            ? const Duration(seconds: 5)
            : const Duration(seconds: 10),
      );

      final response = await _withRetry(
        () => http
            .get(Uri.parse('$_base/v1beta/$fileName?key=$apiKey'))
            .timeout(_requestTimeout),
      );

      if (response.statusCode != 200) continue;

      final json = jsonDecode(response.body);
      final fileData = json['file'] ?? json;
      final state = fileData['state'] as String?;

      if (state == 'ACTIVE') return;
      if (state == 'FAILED') {
        throw GeminiServiceException('音檔處理失敗', status: 'FAILED');
      }
    }

    throw GeminiServiceException('音檔處理逾時', retryable: true, isTimeout: true);
  }

  /// 用已上傳的檔案（fileUri）分析。
  Future<String> analyzeWithFileUri(
    String fileUri,
    String prompt,
    String model, {
    required String mimeType,
    Duration? timeout,
    AnalysisDiagnostics? diag,
  }) {
    return _generateContent(
      base: _base,
      mediaPart: {
        'file_data': {'mime_type': mimeType, 'file_uri': fileUri},
      },
      prompt: prompt,
      model: model,
      limit: timeout ?? _requestTimeout,
      diag: diag,
    );
  }

  /// 把音檔直接內嵌在請求裡分析（檔案要夠小，見
  /// [AnalysisTimeouts.inlineAudioLimitBytes]）。
  ///
  /// 與 [analyzeWithFileUri] 共用同一套請求、錯誤分類與回應解析，所以 503、
  /// 429 等錯誤會帶有 HTTP 狀態碼，畫面上能顯示對應的說明。網頁版固定直接
  /// 連 Google（不經代理），與原本內嵌分析的行為一致。
  Future<String> analyzeInline(
    Uint8List audioBytes,
    String prompt,
    String model, {
    required String mimeType,
    required Duration timeout,
    AnalysisDiagnostics? diag,
  }) {
    return _generateContent(
      base: _directBase,
      mediaPart: {
        'inline_data': {
          'mime_type': mimeType,
          'data': base64Encode(audioBytes),
        },
      },
      prompt: prompt,
      model: model,
      limit: timeout,
      diag: diag,
    );
  }

  Future<String> _generateContent({
    required String base,
    required Map<String, Object?> mediaPart,
    required String prompt,
    required String model,
    required Duration limit,
    AnalysisDiagnostics? diag,
  }) async {
    diag?.beginStage(AnalysisStage.analyzing, timeout: limit);

    // 請求內容只編碼一次：內嵌時約有 18MB，不必每次重試都重做。
    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            mediaPart,
            {'text': prompt},
          ],
        },
      ],
    });

    final response = await retryAnalysis(() async {
      // 專屬 Client，逾時後 close() 會中止請求（同 [_uploadBytesOnce]）。
      final client = _newClient();
      try {
        final response = await client
            .post(
              Uri.parse('$base/v1beta/models/$model:generateContent?key=$apiKey'),
              headers: {'Content-Type': 'application/json'},
              body: requestBody,
            )
            .timeout(limit);
        if (response.statusCode != 200) {
          throw exceptionFromResponse(response, 'Gemini 分析失敗');
        }
        return response;
      } finally {
        client.close();
      }
    }, diag: diag);

    return extractAnalysisText(response.body);
  }

  /// 給「短請求」（查詢檔案狀態）用的重試：任何暫時性錯誤都重試，最多 3 次。
  Future<T> _withRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (!isTemporaryFailure(error) || attempt == 2) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw lastError ?? GeminiServiceException('暫時無法連線', retryable: true);
  }
}

/// 邊被讀取邊回報進度的請求：內容以固定大小的區塊產生，每個區塊被取走後
/// 才會繼續產生下一個，所以回報的進度會跟著實際送出的速度走。
class _ProgressRequest extends http.BaseRequest {
  static const _chunkSize = 128 * 1024;

  final Uint8List _bytes;
  final void Function(int sent) _onProgress;

  _ProgressRequest(String method, Uri url, this._bytes, this._onProgress)
    : super(method, url) {
    contentLength = _bytes.length;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    var offset = 0;
    _onProgress(0);
    while (offset < _bytes.length) {
      final end = offset + _chunkSize < _bytes.length
          ? offset + _chunkSize
          : _bytes.length;
      yield Uint8List.sublistView(_bytes, offset, end);
      // 程式會在下一個區塊被要求時才回到這裡，也就是上一個區塊已被取走。
      offset = end;
      _onProgress(offset);
    }
  }
}
