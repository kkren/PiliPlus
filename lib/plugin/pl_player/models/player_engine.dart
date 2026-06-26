import 'dart:io' show Platform;

enum PlayerEngine {
  mediaKit('当前播放器 (mpv/media_kit)'),
  media3('Media3 (Android 实验性)');

  final String label;
  const PlayerEngine(this.label);

  bool get isSupported => this != PlayerEngine.media3 || Platform.isAndroid;

  static PlayerEngine fromIndex(Object? index) {
    if (index is int && index >= 0 && index < PlayerEngine.values.length) {
      final engine = PlayerEngine.values[index];
      if (engine.isSupported) {
        return engine;
      }
    }
    return PlayerEngine.mediaKit;
  }
}
