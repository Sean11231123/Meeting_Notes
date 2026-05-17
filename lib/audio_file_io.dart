import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<int> audioFileLength(String path) => File(path).length();

Future<Uint8List> readAudioFileBytes(String path) => File(path).readAsBytes();

Future<String> copyAudioToPending(String sourcePath, String fileName) async {
  final dir = await getApplicationSupportDirectory();
  final pendingDir = Directory('${dir.path}/pending_audio');
  if (!await pendingDir.exists()) {
    await pendingDir.create(recursive: true);
  }
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final targetPath =
      '${pendingDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
  await File(sourcePath).copy(targetPath);
  return targetPath;
}

Future<void> deleteAudioFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
