// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Web 平台下載實作：Blob URL + <a download>
Future<void> platformDownloadBytes(
  List<int> bytes,
  String mimeType,
  String fileName,
) async {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  _triggerDownload(blob, fileName);
}

Future<void> platformDownloadText(
  String text,
  String mimeType,
  String fileName,
) async {
  // 用 Dart 原生 utf8.encode() 取得 Uint8List，再 .toJS 傳給 Blob
  // 避免 TextEncoder 的 JSString / .buffer 型別問題
  final bytes = Uint8List.fromList(utf8.encode(text));
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  _triggerDownload(blob, fileName);
}

void _triggerDownload(web.Blob blob, String fileName) {
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Future.delayed(const Duration(seconds: 2), () {
    web.URL.revokeObjectURL(url);
  });
}
