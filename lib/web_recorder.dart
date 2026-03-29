// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:async';
import 'package:web/web.dart' as web;

class WebRecorder {
  web.MediaRecorder? _mediaRecorder;
  final List<web.Blob> _chunks = [];
  Completer<List<int>>? _completer;

  Future<bool> hasPermission() async {
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      stream.getTracks().toDart.forEach((track) => track.stop());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    _chunks.clear();
    _completer = Completer<List<int>>();

    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;

    _mediaRecorder = web.MediaRecorder(stream);

    _mediaRecorder!.ondataavailable = (web.BlobEvent event) {
      if (event.data.size > 0) {
        _chunks.add(event.data);
      }
    }.toJS;

    _mediaRecorder!.onstop = (web.Event _) {
      final blob = web.Blob(
        _chunks.toJS,
        web.BlobPropertyBag(type: 'audio/webm'),
      );
      final reader = web.FileReader();
      reader.onloadend = (web.Event _) {
        final result = reader.result;
        if (result != null && !_completer!.isCompleted) {
          final buffer = (result as JSArrayBuffer).toDart;
          final bytes = buffer.asUint8List().toList();
          _completer!.complete(bytes);
        }
      }.toJS;
      reader.readAsArrayBuffer(blob);
    }.toJS;

    _mediaRecorder!.start();
  }

  Future<List<int>> stop() async {
    _mediaRecorder?.stop();
    return await _completer!.future;
  }

  bool get isRecording => _mediaRecorder?.state == 'recording';
}