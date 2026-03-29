class WebRecorder {
  Future<bool> hasPermission() async => false;
  Future<void> start() async {}
  Future<List<int>> stop() async => [];
  bool get isRecording => false;
}
