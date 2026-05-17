class AudioMime {
  static const supportedExtensions = {
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'mp4': 'audio/mp4',
    'wav': 'audio/wav',
    'webm': 'audio/webm',
    'ogg': 'audio/ogg',
    'aac': 'audio/aac',
    'flac': 'audio/flac',
  };

  static String? fromFileName(String fileName) {
    final parts = fileName.toLowerCase().split('.');
    if (parts.length < 2) return null;
    return supportedExtensions[parts.last];
  }

  static String? extensionFromFileName(String fileName) {
    final parts = fileName.toLowerCase().split('.');
    if (parts.length < 2) return null;
    final ext = parts.last;
    return supportedExtensions.containsKey(ext) ? ext : null;
  }

  static bool isSupported(String fileName) => fromFileName(fileName) != null;

  static String supportedList() => supportedExtensions.keys.join(', ');
}
