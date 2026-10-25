/// What the Play controller needs from the watcher of the images the game
/// uses (spec 007, research R11). `ImageUse` is the implementation; it reads
/// Scenes with the Runtime, which imports Flutter, so the controller is given
/// one instead of building it and `process.dart` stays free of Flutter.
abstract interface class ImageWatching {
  /// Reads the Scenes and starts watching.
  Future<void> start();

  /// *Restart game*: forgets the reported changes and reads the Scenes
  /// again.
  Future<void> clear();

  /// Stops watching.
  void close();
}
