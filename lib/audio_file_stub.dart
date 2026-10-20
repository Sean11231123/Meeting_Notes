import 'dart:typed_data';

Future<String> activeRecordingFilePath(String fileName) {
  throw UnsupportedError('File paths are not available on this platform.');
}

Future<int> audioFileLength(String path) {
  throw UnsupportedError('File paths are not available on this platform.');
}

Future<Uint8List> readAudioFileBytes(String path) {
  throw UnsupportedError('File paths are not available on this platform.');
}

Future<String> copyAudioToPending(String sourcePath, String fileName) {
  throw UnsupportedError('File paths are not available on this platform.');
}

Future<String> moveAudioToPending(String sourcePath, String fileName) {
  throw UnsupportedError('File paths are not available on this platform.');
}

Future<void> deleteAudioFile(String path) async {}
