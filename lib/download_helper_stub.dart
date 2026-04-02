/// Stub：讓靜態分析在非 web/native 環境下不報錯
Future<void> platformDownloadBytes(
  List<int> bytes,
  String mimeType,
  String fileName,
) async {}

Future<void> platformDownloadText(
  String text,
  String mimeType,
  String fileName,
) async {}
