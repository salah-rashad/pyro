import 'dart:async';
import 'dart:convert';
import 'dart:io' show Process, ProcessSignal;

import 'package:clock/clock.dart';
import 'package:file/file.dart';

import 'daemon_message.dart';
import 'hot_swap_monitor.dart';
import 'play_event.dart';
import 'redact.dart';
import 'scene_watcher.dart';
import 'vm_service_link.dart';

/// How long the process may take to exit after SIGTERM before SIGKILL
/// (research R10).
const _killDelay = Duration(seconds: 2);

/// How long to wait, after the process exits, for its last output lines: a
/// grandchild that inherited the pipe could keep it open for ever.
const _drainLimit = Duration(seconds: 1);

/// How many output lines a start failure quotes (research R11).
const _tailLength = 20;

/// Creates the session for an already spawned `flutter run --machine`.
/// `PlayClient.start` is the only caller; it isn't exported.
PlaySession startPlaySession({
  required Process process,
  required String command,
  required String projectPath,
  required FileSystem fileSystem,
  required DirectoryWatcher watchDirectory,
  required Duration quietPeriod,
  required Duration stopTimeout,
  void Function(String line)? onStdoutLine,
  bool repoint = false,
  Future<VmServiceLink> Function(String wsUri)? vmConnect,
}) => PlaySession._(
  process: process,
  command: command,
  projectPath: projectPath,
  fileSystem: fileSystem,
  watchDirectory: watchDirectory,
  quietPeriod: quietPeriod,
  stopTimeout: stopTimeout,
  onStdoutLine: onStdoutLine,
  repoint: repoint,
  vmConnect: vmConnect,
);

/// One run of a game through `flutter run --machine`, from spawn to exit
/// (*Play session* in the glossary; spec 005, data model).
///
/// It reads the daemon's messages, reports them as [events], hot-reloads the
/// game when its Scene files change (one reload at a time, at most one more
/// queued), and stops it on request. It writes nothing to the project.
final class PlaySession {
  PlaySession._({
    required this._process,
    required String command,
    required this.projectPath,
    required FileSystem fileSystem,
    required DirectoryWatcher watchDirectory,
    required Duration quietPeriod,
    required this._stopTimeout,
    this._onStdoutLine,
    this._repoint = false,
    this._vmConnect,
  }) : _fs = fileSystem {
    _monitor = HotSwapMonitor(
      contentOf: _readScene,
      onFailed: (paths, misses) => _emit(PlayHotSwapFailed(paths, misses)),
      onUnannounced: (path) => _output(
        "$path was saved, but the game hasn't said it loaded it, so Pyro "
        "can't tell whether the save reached the game.",
        PlayOutputSource.tool,
      ),
    );
    _watcher = SceneWatcher(
      fileSystem: fileSystem,
      projectPath: projectPath,
      watch: watchDirectory,
      quietPeriod: quietPeriod,
      onChanges: _onSceneChanges,
      onNote: (note) => _output(note, PlayOutputSource.tool),
    );
    _emit(PlayStarting(command: command, projectPath: projectPath));
    // Watch from the spawn: the game can read its Scene before the daemon
    // reports app.started, and a save in between must not be lost.
    _watcher.start();
    final stdoutDone = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdout)
        .asFuture<void>();
    final stderrDone = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _output(line, PlayOutputSource.stderr))
        .asFuture<void>();
    // A write after the process exited fails the sink; the exit is
    // reported on its own, so that error carries nothing new.
    _process.stdin.done.ignore();
    unawaited(
      _process.exitCode.then(
        (code) => _onExit(code, Future.wait([stdoutDone, stderrDone])),
      ),
    );
  }

  /// The project the game runs from.
  final String projectPath;

  final Process _process;
  final Duration _stopTimeout;
  final void Function(String line)? _onStdoutLine;
  final bool _repoint;
  final Future<VmServiceLink> Function(String wsUri)? _vmConnect;
  final FileSystem _fs;
  late final SceneWatcher _watcher;
  late final HotSwapMonitor _monitor;
  VmServiceLink? _vm;
  String? _wsUri;
  String? _baseUri;
  final _events = StreamController<PlayEvent>();
  final _stopwatch = clock.stopwatch()..start();
  final _pending = <int, Completer<DaemonResponse>>{};
  final _tail = <String>[];
  final _changedWhileStarting = <String>{};
  final _done = Completer<void>();
  var _nextId = 1;
  var _state = PlayState.starting;
  String? _appId;
  bool _debuggerReported = false;
  bool _started = false;
  bool _stopRequested = false;
  Object? _stopError;
  bool _reloadInFlight = false;
  Set<String>? _queuedPaths;
  var _queuedFull = false;
  Completer<ReloadResult>? _queuedReload;
  Timer? _terminate;
  Timer? _kill;

  /// Where the session is in its life.
  PlayState get state => _state;

  /// The daemon's id for the running app, once `flutter run` reports it.
  String? get appId => _appId;

  /// The address an IDE attaches to, with its authentication code, while the
  /// game runs; null before the game reports it and after the session ends.
  ///
  /// For *Attach debugger* only (spec 007, FR-024, research R3): it grants
  /// full control of the game, so it is in no event, string or log. Every
  /// run has its own (FR-028).
  String? get debuggerAddress {
    final ws = _wsUri;
    if (ws == null) return null;
    final uri = Uri.parse(ws);
    final path = uri.path.endsWith('/ws')
        ? uri.path.substring(0, uri.path.length - 2)
        : uri.path;
    return uri.replace(scheme: 'http', path: path).toString();
  }

  /// Every event of this session, in order; closes after [PlayStopped].
  /// Single subscription: events wait until it is listened to.
  Stream<PlayEvent> get events => _events.stream;

  /// Completes with the `flutter run` process's exit code.
  Future<int> get exitCode => _process.exitCode;

  /// Hot-reloads now, without waiting for a Scene change. Queued behind a
  /// reload already in flight.
  ///
  /// Throws [StateError] unless the game is running or reloading. The
  /// returned future fails with a [StateError] if the session stops first.
  Future<ReloadResult> reload() {
    if (_state != PlayState.running && _state != PlayState.reloading) {
      throw StateError(
        "Can't hot-reload $projectPath while the Play session is "
        '${_state.name}.',
      );
    }
    return _requestReload(const {});
  }

  /// A full restart of the game (*Restart game*): a new isolate, the Scenes
  /// loaded again, the Hot-swap monitor armed afresh. Not repointed.
  ///
  /// Throws [StateError] unless the game is running or reloading.
  Future<ReloadResult> restart() {
    if (_state != PlayState.running && _state != PlayState.reloading) {
      throw StateError(
        "Can't restart $projectPath while the Play session is "
        '${_state.name}.',
      );
    }
    _monitor.rearm();
    return _requestReload(const {}, full: true);
  }

  /// Sends `app.stop`, then SIGTERM after the stop timeout and SIGKILL two
  /// seconds later if the process still hasn't exited (research R10).
  /// Completes once it has exited. Safe to call more than once.
  Future<void> stop() {
    if (_stopRequested || _state == PlayState.stopped) return _done.future;
    _stopRequested = true;
    _state = PlayState.stopping;
    final appId = _appId;
    if (appId == null) {
      // Still building: there is no app to stop, only the tool.
      _process.kill(ProcessSignal.sigterm);
    } else {
      _send('app.stop', {'appId': appId}).ignore();
    }
    _terminate = Timer(_stopTimeout, () {
      _process.kill(ProcessSignal.sigterm);
      _kill = Timer(_killDelay, () => _process.kill(ProcessSignal.sigkill));
    });
    return _done.future;
  }

  void _onStdout(String line) {
    _onStdoutLine?.call(redactAuthCodes(line));
    for (final message in parseDaemonLine(line)) {
      switch (message) {
        case RawLine(:final text):
          _output(text, PlayOutputSource.game);
        case DaemonResponse(:final id):
          _pending.remove(id)?.complete(message);
        case DaemonEvent(:final name, :final params):
          _onEvent(name, params);
      }
    }
  }

  void _onEvent(String name, Map<String, Object?> params) {
    switch (name) {
      case 'daemon.connected':
        break;
      case 'app.start':
        _appId = params['appId'] as String?;
      case 'app.debugPort':
        // Kept privately, for the repoint and for Attach; the event says
        // only that it exists (research R3, R5).
        if (!_debuggerReported) {
          _debuggerReported = true;
          _wsUri = params['wsUri'] as String?;
          _baseUri = params['baseUri'] as String?;
          _emit(const PlayDebuggerAvailable());
        }
      case 'device.added' || 'device.removed' || 'device.changed':
        // The daemon's device list: not the game's output.
        break;
      case 'app.devTools' || 'app.dtd':
        // DevTools and the tooling daemon: addresses, dropped like the VM
        // service's (research R5).
        break;
      case 'app.started':
        if (_state == PlayState.starting) {
          _state = PlayState.running;
          _started = true;
          _appId ??= params['appId'] as String?;
          _emit(PlayStarted(appId: _appId ?? '', elapsed: _stopwatch.elapsed));
          final missed = _changedWhileStarting;
          if (missed.isNotEmpty) _requestReload(Set.of(missed)).ignore();
          missed.clear();
        }
      case 'app.log':
        final log = params['log'];
        if (log is String) _output(log.trimRight(), PlayOutputSource.game);
      case 'app.progress':
        final message = params['message'];
        if (params['finished'] != true && message is String) {
          _output(message, PlayOutputSource.tool);
        }
      case 'daemon.logMessage':
        final message = params['message'];
        if (message is String) _output(message, PlayOutputSource.tool);
      case 'app.stop':
        _stopError = params['error'];
      default:
        _output('$name ${jsonEncode(params)}', PlayOutputSource.tool);
    }
  }

  void _onSceneChanges(Set<String> paths) {
    if (_state == PlayState.starting) {
      // Reloaded once the game has started (it may already have read
      // the old file); the Runtime ignores it if the game read the new one.
      _changedWhileStarting.addAll(paths);
      return;
    }
    if (_state != PlayState.running && _state != PlayState.reloading) return;
    // Scene reloads stopped until *Restart game* (FR-011).
    if (_monitor.failed) return;
    // Watcher-driven reloads report through events; a failure has already
    // been reported as PlayReloadFailed, and a stop as PlayStopped.
    _requestReload(paths).ignore();
  }

  Future<ReloadResult> _requestReload(Set<String> paths, {bool full = false}) {
    if (!_reloadInFlight) return _runReload(paths, full: full);
    (_queuedPaths ??= {}).addAll(paths);
    _queuedFull = _queuedFull || full;
    return (_queuedReload ??= Completer<ReloadResult>()).future;
  }

  Future<ReloadResult> _runReload(
    Set<String> paths, {
    bool full = false,
  }) async {
    _reloadInFlight = true;
    _state = PlayState.reloading;
    _emit(PlayReloading(paths.toList()..sort()));
    final started = clock.now();
    if (paths.isNotEmpty) _monitor.onBatch(paths);
    final DaemonResponse response;
    try {
      response = _repoint && paths.isNotEmpty && !full
          ? await _reloadScenes(paths)
          : await _sendRestart(full: full);
    } finally {
      _reloadInFlight = false;
    }
    final result = _reloadResult(response, clock.now().difference(started));
    final failure = result.ok ? null : result.message ?? 'unknown error';
    if (paths.isNotEmpty) {
      result.ok ? _monitor.onReloadFinished() : _monitor.onReloadFailed();
    }
    _emit(
      failure == null
          ? PlayReloaded(result.elapsed)
          : PlayReloadFailed(failure, code: _code(response)),
    );
    if (_state == PlayState.reloading) _state = PlayState.running;
    final queued = _queuedPaths;
    final queuedFull = _queuedFull;
    final waiting = _queuedReload;
    _queuedPaths = null;
    _queuedFull = false;
    _queuedReload = null;
    if (queued != null && waiting != null) {
      // A stop requested while the reload was in flight fails the queued
      // one instead of restarting an app that is being stopped.
      if (_stopRequested) {
        waiting.completeError(_stoppedError());
      } else {
        waiting.complete(_runReload(queued, full: queuedFull));
      }
    }
    return result;
  }

  Future<DaemonResponse> _sendRestart({required bool full}) => _send(
    'app.restart',
    {'appId': _appId, 'fullRestart': full, 'pause': false, 'reason': 'pyro'},
  );

  /// A Scene reload (research R5): point the engine at the project's own
  /// assets, then hot reload. When the engine refuses (the folder isn't
  /// there yet, or an IDE recreated the game's file system), reload first so
  /// it is, point again, evict the changed Scenes and reload once more.
  Future<DaemonResponse> _reloadScenes(Set<String> paths) async {
    if (await _repointAssets() != null) return _sendRestart(full: false);
    final first = await _sendRestart(full: false);
    if (!_reloadResult(first, Duration.zero).ok) return first;
    final view = await _repointAssets();
    if (view != null) await _evict(view, paths);
    return _sendRestart(full: false);
  }

  /// `_flutter.setAssetBundlePath` to the game's own `build/flutter_assets`;
  /// the view on success, null when the VM service or the engine refused.
  Future<ViewInfo?> _repointAssets() async {
    final ws = _wsUri;
    final base = _baseUri;
    if (ws == null || base == null) return null;
    try {
      final vm = _vm ??= await (_vmConnect ?? VmServiceLink.connect)(ws);
      final views = await vm.listViews();
      if (views.isEmpty) return null;
      final view = views.first;
      await vm.setAssetBundlePath(
        viewId: view.id,
        isolateId: view.isolateId,
        // A file path, not a URI: Flutter's own tool sends `toFilePath()`.
        assetDirectory: Uri.parse(
          base.endsWith('/') ? base : '$base/',
        ).resolve('build/flutter_assets').toFilePath(),
      );
      return view;
    } on VmServiceCallFailed {
      return null;
    }
  }

  Future<void> _evict(ViewInfo view, Set<String> paths) async {
    for (final path in paths) {
      try {
        await _vm?.evict(isolateId: view.isolateId, asset: path);
      } on VmServiceCallFailed {
        // The reload that follows still rebuilds from disk.
      }
    }
  }

  String? _readScene(String path) {
    try {
      return _fs.file(_fs.path.join(projectPath, path)).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  ReloadResult _reloadResult(DaemonResponse response, Duration elapsed) {
    final error = response.error;
    if (error != null) {
      return ReloadResult(
        ok: false,
        message: redactAuthCodes('$error'),
        elapsed: elapsed,
      );
    }
    final result = response.result;
    final message = result is Map<String, Object?> ? result['message'] : null;
    return ReloadResult(
      ok: _code(response) == 0,
      message: message is String && message.isNotEmpty
          ? redactAuthCodes(message)
          : null,
      elapsed: elapsed,
    );
  }

  int? _code(DaemonResponse response) {
    final result = response.result;
    final code = result is Map<String, Object?> ? result['code'] : null;
    return code is int ? code : null;
  }

  Future<DaemonResponse> _send(String method, Map<String, Object?> params) {
    if (_state == PlayState.stopped) {
      return Future.error(_stoppedError());
    }
    final id = _nextId++;
    final response = Completer<DaemonResponse>();
    _pending[id] = response;
    _process.stdin.writeln(
      jsonEncode([
        {'id': id, 'method': method, 'params': params},
      ]),
    );
    return response.future;
  }

  void _output(String line, PlayOutputSource source) {
    final redacted = redactAuthCodes(line);
    if (source == PlayOutputSource.game) _monitor.onLine(redacted);
    _tail.add(redacted);
    if (_tail.length > _tailLength) _tail.removeAt(0);
    _emit(PlayOutput(redacted, source));
  }

  void _emit(PlayEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  StateError _stoppedError() =>
      StateError('The Play session for $projectPath has stopped.');

  Future<void> _onExit(int code, Future<void> outputDone) async {
    // Report the last lines before the stop, but don't wait for ever.
    await Future.any([
      outputDone.catchError((Object _) {}),
      Future<void>.delayed(_drainLimit),
    ]);
    _terminate?.cancel();
    _kill?.cancel();
    _watcher.close();
    _monitor.dispose();
    _wsUri = _baseUri = null;
    final vm = _vm;
    _vm = null;
    if (vm != null) unawaited(vm.close());
    _state = PlayState.stopped;
    final error = _stoppedError();
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    _queuedReload?.completeError(error);
    _queuedReload = null;
    if (!_started && !_stopRequested) {
      final reason = _stopError;
      _emit(
        PlayFailed(
          message: reason != null
              ? "The game couldn't start: ${redactAuthCodes('$reason')}"
              : 'flutter run exited with code $code before the game started.',
          exitCode: code,
          outputTail: List.unmodifiable(_tail),
        ),
      );
    }
    _emit(PlayStopped(exitCode: code, requested: _stopRequested));
    await _events.close();
    _done.complete();
  }
}
