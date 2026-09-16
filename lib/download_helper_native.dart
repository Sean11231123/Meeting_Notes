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
  final dir = await _exportDir();
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
  final dir = await _exportDir();
  final file = File('${dir.path}/$fileName');
  // 明確用 UTF-8 寫入，避免部分裝置用系統編碼
  await file.writeAsBytes(utf8.encode(text));
  await Share.shareXFiles([
    XFile(file.path, mimeType: mimeType),
  ], subject: fileName);
}

/// 專用的匯出暫存資料夾。
///
/// 每次匯出前會先清掉「上一次」留下的檔案，避免每次「下載筆記」都在裝置
/// 暫存空間留下永久不會消失的檔案。不在分享完成後立刻刪除本次檔案，是因為
/// 分享（例如透過 Email／通訊軟體）在 share_plus 回傳後，接收端 App 有時仍在
/// 非同步讀取同一個檔案，太快刪除可能造成分享失敗；清理上一批檔案則沒有這個風險，
/// 因為那次分享流程一定早已結束。
Future<Directory> _exportDir() async {
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}/exports');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
    return dir;
  }
  for (final entity in dir.listSync()) {
    if (entity is File) {
      try {
        await entity.delete();
      } catch (_) {
        // 忽略單一檔案刪除失敗（例如仍被佔用），不影響本次匯出。
      }
    }
  }
  return dir;
}
