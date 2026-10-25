import 'dart:async';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../assets/asset_source.dart';
import '../scene/errors.dart';
import '../scene/scene_codec.dart';
import '../scene/values.dart';
import 'built_scene.dart';
import 'hot_swap.dart';
import 'load_exception.dart';
import 'load_warnings.dart';
import 'registry.dart';
import 'repair_warning.dart';
import 'scene_builder.dart';
import 'unknown_type.dart';

/// What a [hotSwapReportLine] says.
@visibleForTesting
enum HotSwapReport {
  /// A `PyroScene` built its first tree.
  loaded,

  /// A Hot-swap rebuilt the tree because the content changed.
  reloaded,

  /// A Hot-swap could not rebuild; the game keeps the Scene it had.
  notReloaded,
}

/// The one-line report the Runtime prints in debug builds for a load or a
/// Hot-swap (spec 007, contracts/hot-swap-reports.md): Pyro reads it from
/// the game's output to tell that a Hot-swap reached the game. The format
/// is a contract; a change to it is noted in `ARCHITECTURE.md`.
@visibleForTesting
String hotSwapReportLine(HotSwapReport kind, String path, [String? reason]) =>
    switch (kind) {
      HotSwapReport.loaded => '[pyro] Scene loaded: $path',
      HotSwapReport.reloaded => '[pyro] Scene reloaded: $path',
      HotSwapReport.notReloaded =>
        '[pyro] Scene not reloaded: $path: '
            '${(reason ?? '').split('\n').first.trim()}',
    };

/// Called after a Hot-swap rebuilt [scene]; re-run lookups here (*Q71*).
///
/// The new Nodes are in [scene] and lookups return them, but their own
/// `onLoad`s haven't run yet, just as after [PyroScene.load] returns. Read
/// their Editable fields and transforms here, not state they set up in
/// `onLoad`.
typedef SceneReloaded = void Function(PyroScene scene);

/// A loaded Scene: the Flame component standing for its root Node, holding
/// every Node of the Scene as a Flame component (project plan §6.2).
///
/// ```dart
/// final scene = await PyroScene.load(
///   'assets/scenes/level1.scene.json',
///   registry: pyroRegistry,
///   onReloaded: _lookUpNodes,
/// );
/// world.add(scene);
/// ```
///
/// In debug builds it Hot-swaps itself: after a hot reload, it rebuilds if
/// its Scene file or an animation file it uses changed, and calls
/// `onReloaded`.
final class PyroScene extends Component {
  PyroScene._(
    this.path,
    this._registry,
    this._onUnknownType,
    this.onReloaded,
    this._source,
  );

  /// Loads the Scene at [path], a project-relative asset path such as
  /// `assets/scenes/level1.scene.json`, building Custom components and
  /// Behaviors through [registry].
  ///
  /// Completes once every Node is built and every asset loaded, with the
  /// Scene's Nodes queued as children; their `onLoad`s run when the result
  /// is added to a game, and see every Override already set. Lookups work
  /// at once.
  ///
  /// Every file is read through [assets]; by default one
  /// `AssetSource.bundle()` per Scene, kept across Hot-swaps so images are
  /// decoded once. Throws a [SceneLoadException] on any failure and returns
  /// nothing.
  static Future<PyroScene> load(
    String path, {
    required PyroRegistry registry,
    UnknownType onUnknownType = UnknownType.error,
    SceneReloaded? onReloaded,
    AssetSource? assets,
  }) async {
    final scene = PyroScene._(
      AssetPath(path),
      registry,
      onUnknownType,
      onReloaded,
      assets ?? AssetSource.bundle(),
    );
    scene._adopt(await scene._build());
    if (kDebugMode) debugPrint(hotSwapReportLine(HotSwapReport.loaded, path));
    return scene;
  }

  /// The Scene's asset path.
  final AssetPath path;

  /// Called after each successful Hot-swap.
  final SceneReloaded? onReloaded;

  final PyroRegistry _registry;
  final UnknownType _onUnknownType;
  final AssetSource _source;
  late BuiltScene _built;
  Future<void> _pending = Future.value();
  StaleWatch? _staleWatch;

  /// Completes when the last Hot-swap check has finished.
  @visibleForTesting
  Future<void> get pendingCheck => _pending;

  /// The watch on the Nodes the last Hot-swap removed.
  @visibleForTesting
  StaleWatch? get staleWatch => _staleWatch;

  /// The one Node component matching [nameOrPath], which must be a [T].
  ///
  /// [nameOrPath] is a Node name, or Node names joined by `/` for a Node and
  /// its nearest ancestors (`arena/boss`); a leading `/` starts at the
  /// root's children (`/arena/boss`). Throws a [StateError] if no Node or
  /// several match, listing their paths, or if the match isn't a [T].
  T find<T extends Component>(String nameOrPath) {
    final matches = _built.match(nameOrPath: nameOrPath).toList();
    if (matches.isEmpty) {
      throw StateError('$path: no Node matches "$nameOrPath"');
    }
    if (matches.length > 1) {
      throw StateError(
        '$path: ${matches.length} Nodes match "$nameOrPath": '
        '${matches.map((m) => m.path).join(', ')}. Use findAll, or a longer '
        'path such as "${matches.first.path}"',
      );
    }
    final entry = matches.single;
    final component = entry.component;
    if (component is! T) {
      throw StateError(
        // ignore: avoid_type_to_string, a debug message; native builds keep type names.
        '$path: Node ${entry.label} is a ${component.runtimeType}, not a $T',
      );
    }
    return component;
  }

  /// Every Node component matching all the filters given, in tree order
  /// (depth first, `childIds` order). [name] takes a Node name or a path,
  /// as [find] does.
  List<T> findAll<T extends Component>({String? name, String? tag}) => [
    for (final entry in _built.match(nameOrPath: name, tag: tag))
      if (entry.component case final T component) component,
  ];

  Future<BuiltScene> _build() async {
    final String text;
    try {
      text = await _source.loadText(path);
    } on Object catch (error, stackTrace) {
      throw SceneLoadException(
        path,
        "couldn't be read. Is it declared under flutter: assets: in "
        'pubspec.yaml?',
        asset: path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
    final SceneReadResult result;
    try {
      result = SceneCodec.decode(text);
    } on SceneFormatException catch (error, stackTrace) {
      throw SceneLoadException(
        path,
        error.message,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
    warnAboutRepairs(path, result.repairs);
    final built = await SceneBuilder(
      path: path,
      text: text,
      scene: result.scene,
      registry: _registry,
      source: _source,
      onUnknownType: _onUnknownType,
      root: this,
    ).build();
    warnAboutSkipped(path, built.skipped);
    warnAboutUnusedOverrides(path, built.unusedOverrides);
    return built;
  }

  void _adopt(BuiltScene built) {
    _built = built;
    unawaited(addAll(built.children));
  }

  @override
  void onHotReload() {
    super.onHotReload();
    if (kDebugMode) {
      // Each link catches its own error, so one failure (such as an
      // onReloaded that throws) never stops later Hot-swaps.
      _pending = _pending.then((_) => _checkForChanges()).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'pyro_runtime',
            context: ErrorDescription('while Hot-swapping $path'),
          ),
        );
      });
    }
  }

  Future<void> _checkForChanges() async {
    if (isRemoved || !await contentChanged(_source, _built.texts)) return;
    final BuiltScene built;
    try {
      built = await _build();
    } on Object catch (error) {
      debugPrint(
        "══ Pyro couldn't Hot-swap $path ══\n$error\n"
        'The game keeps the Scene it had. Fix the file and save it again.',
      );
      debugPrint(hotSwapReportLine(HotSwapReport.notReloaded, path, '$error'));
      return;
    }
    final old = _built;
    _staleWatch?.close();
    removeAll(old.children);
    _adopt(built);
    _staleWatch = StaleWatch(path, old.entries);
    debugPrint(hotSwapReportLine(HotSwapReport.reloaded, path));
    onReloaded?.call(this);
  }

  @override
  void onRemove() {
    _staleWatch?.close();
    _staleWatch = null;
    super.onRemove();
  }
}
