import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<int> audioFileLength(String path) => File(path).length();

Future<Uint8List> readAudioFileBytes(String path) => File(path).readAsBytes();

Future<String> copyAudioToPending(String sourcePath, String fileName) async {
  final targetPath = await _pendingTargetPath(fileName);
  await File(sourcePath).copy(targetPath);
  return targetPath;
}

/// 將「App 自己產生的」暫存錄音檔搬到 pending 資料夾。
///
/// 與 [copyAudioToPending] 不同：這個函式假設呼叫端擁有來源檔案的所有權
/// （例如錄音剛結束、存在系統暫存目錄的檔案），因此搬移後來源檔案不應再留著，
/// 避免每次錄音都在裝置上留下兩份檔案。
///
/// 只用於「App 自己的暫存錄音」，**不要**用在使用者透過檔案選擇器選取的檔案上，
/// 那些檔案不屬於 App，貿然刪除來源會出乎使用者預期。
Future<String> moveAudioToPending(String sourcePath, String fileName) async {
  final targetPath = await _pendingTargetPath(fileName);
  final source = File(sourcePath);
  try {
    // 優先用 rename：同一個檔案系統內幾乎是瞬間完成，且不會有兩份資料同時存在。
    await source.rename(targetPath);
    return targetPath;
  } catch (_) {
    // rename 在來源與目的地跨檔案系統（例如暫存分區與 App 專屬儲存分區不同）時
    // 可能會失敗，這時退回「複製完就刪除來源」，效果等同搬移，只是多一次 I/O。
    await source.copy(targetPath);
    await deleteAudioFile(sourcePath);
    return targetPath;
  }
}

Future<String> _pendingTargetPath(String fileName) async {
  final dir = await getApplicationSupportDirectory();
  final pendingDir = Directory('${dir.path}/pending_audio');
  if (!await pendingDir.exists()) {
    await pendingDir.create(recursive: true);
  }
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return '${pendingDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
}

Future<void> deleteAudioFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
