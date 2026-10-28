import 'dart:async';
import 'dart:io' show FileSystemEvent, FileSystemMoveEvent;

import 'package:file/file.dart';
import 'package:pyro_runtime/pyro_runtime.dart';

import '../../project/asset_folders.dart';
import 'image_watching.dart';
import 'play_defaults.dart';
import 'scene_watcher.dart';

/// Which images the running game uses, and when one of them changes on disk
/// (spec 007, FR-013, research R11).
///
/// The images in use are those a Scene names: a Sprite Node's image and any
/// Image-path Override of a Behavior or Custom component (`{"asset": path}`).
/// The Scenes are read with the Runtime's `SceneCodec` and read again when a
/// Scene file changes. A change to one of those images is reported once per
/// batch, and stays in [changed] until [clear] (the game was restarted). An
/// image no Scene names is ignored.
final class ImageUse implements ImageWatching {
  /// Watches the asset folders [projectPath]'s `pubspec.yaml` declares, and
  /// calls [onChanged] with the project-relative paths of each batch of
  /// changed images in use.
  ImageUse({
    required FileSystem fileSystem,
    required this._projectPath,
    required this._watch,
    required this._onChanged,
    this._quietPeriod = PlayDefaults.sceneQuiet,
  }) : _fs = fileSystem;

  final FileSystem _fs;
  final String _projectPath;
  final DirectoryWatcher _watch;
  final void Function(Set<String> paths) _onChanged;
  final Duration _quietPeriod;
  final _subscriptions = <StreamSubscription<FileSystemEvent>>[];
  final _images = <String>{};
  final _changed = <String>{};
  final _pendingImages = <String>{};
  var _pendingScenes = false;
  Timer? _quiet;
  var _closed = false;

  /// The project-relative image paths some Scene names.
  Set<String> get images => Set.unmodifiable(_images);

  /// The images in use that changed since the start or the last [clear].
  Set<String> get changed => Set.unmodifiable(_changed);

  /// Reads the Scenes and starts watching the declared asset folders.
  @override
  Future<void> start() async {
    final folders = await discoverAssetFolders(_projectPath, fileSystem: _fs);
    if (_closed) return;
    _readScenes(folders.scenes);
    final watched = {...folders.declared, 'assets/scenes'};
    for (final folder in watched) {
      final directory = _fs.directory(
        _fs.path.joinAll([_projectPath, ...folder.split('/')]),
      );
      if (!directory.existsSync()) continue;
      // A folder that can't be watched has nothing to report; the Scenes
      // still Hot-swap.
      try {
        _subscriptions.add(
          _watch(directory).listen(_onEvent, onError: (Object _) {}),
        );
      } on Object {
        continue;
      }
    }
  }

  /// *Restart game*: forgets the reported changes (the restarted game loaded
  /// the new images) and reads the Scenes again.
  @override
  Future<void> clear() async {
    _changed.clear();
    _pendingImages.clear();
    _quiet?.cancel();
    _quiet = null;
    final folders = await discoverAssetFolders(_projectPath, fileSystem: _fs);
    if (_closed) return;
    _readScenes(folders.scenes);
  }

  /// Stops watching; a batch waiting for quiet is dropped.
  @override
  void close() {
    _closed = true;
    _quiet?.cancel();
    _quiet = null;
    _pendingImages.clear();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _onEvent(FileSystemEvent event) {
    if (event.isDirectory) return;
    final path = event is FileSystemMoveEvent
        ? event.destination ?? event.path
        : event.path;
    final context = _fs.path;
    final relative = context
        .split(context.relative(path, from: _projectPath))
        .join('/');
    if (relative.endsWith('.scene.json')) {
      _pendingScenes = true;
    } else if (_images.contains(relative)) {
      _pendingImages.add(relative);
    } else {
      return;
    }
    _quiet?.cancel();
    _quiet = Timer(_quietPeriod, _flush);
  }

  void _flush() {
    _quiet = null;
    if (_pendingScenes) {
      _pendingScenes = false;
      _readScenes(_sceneFiles());
    }
    if (_pendingImages.isEmpty) return;
    // A Scene change in the same batch may have dropped an image.
    final batch = _pendingImages.intersection(_images);
    _pendingImages.clear();
    if (batch.isEmpty) return;
    _changed.addAll(batch);
    _onChanged(batch);
  }

  Iterable<String> _sceneFiles() {
    final scenes = _fs.directory(
      _fs.path.join(_projectPath, 'assets', 'scenes'),
    );
    return [
      if (scenes.existsSync())
        for (final entity in scenes.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.scene.json'))
            _fs.path
                .split(_fs.path.relative(entity.path, from: _projectPath))
                .join('/'),
    ];
  }

  void _readScenes(Iterable<String> scenePaths) {
    _images.clear();
    for (final path in {...scenePaths, ..._sceneFiles()}) {
      final file = _fs.file(
        _fs.path.joinAll([_projectPath, ...path.split('/')]),
      );
      final Scene scene;
      try {
        scene = SceneCodec.decode(file.readAsStringSync()).scene;
      } on Object {
        // A Scene that can't be read names no images; the game can't load
        // it either, and saving it reports why.
        continue;
      }
      for (final node in scene.nodes.values) {
        switch (node) {
          case SpriteNode(:final image):
            _images.add(image);
          case EntityNode(:final behaviors):
            _collect(behaviors);
          case CustomNode(:final fields, :final behaviors):
            _collectOverrides(fields);
            _collect(behaviors);
          default:
            break;
        }
      }
    }
  }

  void _collect(List<BehaviorAttachment> behaviors) {
    for (final behavior in behaviors) {
      _collectOverrides(behavior.fields);
    }
  }

  void _collectOverrides(Overrides overrides) {
    for (final value in overrides.values.values) {
      final ref = AssetRef.fromJson(value);
      if (ref != null) _images.add(ref.path);
    }
  }
}
