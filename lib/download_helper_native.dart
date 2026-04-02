import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native 平台下載實作：存到暫存目錄後用 share_plus 分享
Future<void> platformDownloadBytes(
  List<int> bytes,
  String mimeType,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  // 傳入 mimeType 讓 Android Intent 正確識別檔案類型
  await Share.shareXFiles([
    XFile(file.path, mimeType: mimeType),
  ], subject: fileName);
}

Future<void> platformDownloadText(
  String text,
  String mimeType,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  // 明確用 UTF-8 寫入，避免部分裝置用系統編碼
  await file.writeAsBytes(utf8.encode(text));
  await Share.shareXFiles([
    XFile(file.path, mimeType: mimeType),
  ], subject: fileName);
}
