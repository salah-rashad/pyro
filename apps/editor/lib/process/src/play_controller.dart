import 'dart:async';

import 'code_watcher.dart';
import 'console_buffer.dart';
import 'console_line.dart';
import 'image_watching.dart';
import 'play_block.dart';
import 'play_event.dart';
import 'play_session.dart';
import 'run_link.dart';

/// What the toolbar shows about the game (spec 007, data model "PlayPhase").
/// A session's `reloading` shows as [running].
enum PlayPhase {
  /// No game runs; Play is available unless a `PlayBlock` applies.
  stopped,

  /// `flutter run` is building and launching the game.
  starting,

  /// The game runs; saved Scenes are Hot-swapped.
  running,

  /// A stop was asked for; waiting for the game to exit.
  stopping,
}

/// Something the editor window shows the user about the running game, once
/// (contracts/play-orchestration.md, "Notices"). A notice replaces the
/// previous one of its kind.
sealed class PlayNotice {
  const PlayNotice();
}

/// The game exited and Pyro did not ask it to (FR-014).
final class GameStopped extends PlayNotice {
  const GameStopped(this.exitCode);

  /// The `flutter run` process's exit code.
  final int exitCode;

  @override
  String toString() => 'Game stopped (exit $exitCode)';
}

/// Scene saves stopped reaching the game (FR-011); *Restart game* recovers.
final class HotSwapFailed extends PlayNotice {
  const HotSwapFailed(this.paths);

  /// The Scenes of the last unreported save.
  final Set<String> paths;

  @override
  String toString() => 'Hot-swap stopped working';
}

/// An image the running game uses changed on disk (FR-013); *Restart game*
/// shows the new one.
final class ImageChanged extends PlayNotice {
  const ImageChanged(this.paths);

  /// The project-relative paths of the images that changed since the game
  /// started or was last restarted.
  final Set<String> paths;

  @override
  String toString() => 'Image changed';
}

/// Starts a Play session for a project; `PlayClient.start` in the app,
/// a fake in tests.
typedef PlayStarter =
    Future<PlaySession> Function(String projectPath, {RunLink? runLink});

/// Makes the run link of a project; null when it can't (research R2).
typedef RunLinkMaker = Future<RunLink?> Function(String projectPath);

/// Makes the watcher of Dart code saves; [onReload] is what it asks for
/// (research R10).
typedef CodeWatcherMaker = CodeWatcher Function(void Function() onReload);

/// Makes the watcher of the images in use; [onChanged] is told each batch of
/// changed ones (research R11).
typedef ImageWatcherMaker =
    ImageWatching Function(void Function(Set<String> paths) onChanged);

/// The open project's Play (spec 007, contracts/play-orchestration.md): at
/// most one Play session at a time, its phase for the toolbar, its output
/// and lifecycle in the Console, and its unasked-for ends as notices.
final class PlayController {
  /// Creates the controller of [projectPath]; [block] says why Play is
  /// disabled, when it is.
  PlayController({
    required this.projectPath,
    required this._console,
    required this._start,
    this.block,
    this._makeRunLink,
    this._makeCodeWatcher,
    this._makeImageWatcher,
  });

  /// The project the game runs from.
  final String projectPath;

  /// Why Play is disabled, or null when it is available (FR-003).
  final PlayBlock? block;

  final ConsoleBuffer _console;
  final PlayStarter _start;
  final RunLinkMaker? _makeRunLink;
  final CodeWatcherMaker? _makeCodeWatcher;
  final ImageWatcherMaker? _makeImageWatcher;
  RunLink? _runLink;
  CodeWatcher? _codeWatcher;
  ImageWatching? _imageWatcher;
  final _changedImages = <String>{};
  final _phases = StreamController<PlayPhase>.broadcast();
  final _notices = StreamController<PlayNotice>.broadcast();
  var _phase = PlayPhase.stopped;
  PlaySession? _session;
  Future<void>? _ended;
  var _disposed = false;
  var _restarting = false;

  /// Where the game is.
  PlayPhase get phase => _phase;

  /// Whether *Attach debugger* has an address to give: the game runs.
  bool get canAttach => _phase == PlayPhase.running;

  /// Every change of [phase].
  Stream<PlayPhase> get phases => _phases.stream;

  /// Notices for the user, such as [GameStopped].
  Stream<PlayNotice> get notices => _notices.stream;

  /// Starts the game. Does nothing unless the phase is stopped and no
  /// block applies (FR-002, FR-003). Completes once the game has been
  /// spawned or failed to spawn.
  Future<void> play() async {
    if (_disposed || _phase != PlayPhase.stopped || block != null) return;
    _setPhase(PlayPhase.starting);
    _pyro('Starting the game…');
    final link = await _makeRunLink?.call(projectPath);
    if (_makeRunLink != null && link == null) {
      _pyro(
        "Couldn't make the link that keeps an attached IDE from breaking "
        'Hot-swap; the game runs without it, and attaching an IDE may stop '
        'Hot-swap.',
        ConsoleSeverity.warning,
      );
    }
    _runLink = link;
    final PlaySession session;
    try {
      session = await _start(projectPath, runLink: link);
    } on PlayStartException catch (error) {
      _pyro('$error', ConsoleSeverity.error);
      await _removeRunLink();
      _setPhase(PlayPhase.stopped);
      return;
    } on Object catch (error) {
      _pyro("Can't play $projectPath: $error", ConsoleSeverity.error);
      await _removeRunLink();
      _setPhase(PlayPhase.stopped);
      return;
    }
    _session = session;
    final ended = Completer<void>();
    _ended = ended.future;
    session.events.listen(
      _onEvent,
      onDone: () async {
        if (identical(_session, session)) _session = null;
        _restarting = false;
        _stopWatching();
        await _removeRunLink();
        _setPhase(PlayPhase.stopped);
        ended.complete();
      },
    );
    // A stop asked for while `flutter run` was being spawned.
    if (_phase == PlayPhase.stopping) unawaited(session.stop());
  }

  /// Stops the game: `app.stop`, then SIGTERM and SIGKILL (FR-004). Safe
  /// in any phase; completes once the game has exited.
  Future<void> stop() async {
    final session = _session;
    if (_phase == PlayPhase.stopped) return;
    if (_phase != PlayPhase.stopping) {
      _setPhase(PlayPhase.stopping);
      _pyro('Stopping the game…');
    }
    _stopWatching();
    if (session == null) return;
    await session.stop();
    await _ended;
  }

  /// The debugger address of the running game, for *Attach debugger* to put
  /// on the clipboard; null unless the game runs. The only way to read it:
  /// the Console, the notices and every log leave it out (FR-024).
  String? copyDebuggerAddress() => canAttach ? _session?.debuggerAddress : null;

  /// *Restart game*: a full restart of the running game, which also makes
  /// Scene Hot-swaps work again after a failure. Does nothing unless the
  /// game runs.
  Future<void> restartGame() async {
    final session = _session;
    if (session == null || _phase != PlayPhase.running) return;
    _restarting = true;
    _changedImages.clear();
    _watchImages(_imageWatcher?.clear());
    try {
      await session.restart();
    } on StateError {
      // The game stopped meanwhile; its stop is reported on its own.
      _restarting = false;
    }
  }

  Future<void> _removeRunLink() async {
    final link = _runLink;
    _runLink = null;
    await link?.remove();
  }

  /// Stops the game and closes the streams; the project is closing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _phases.close();
    await _notices.close();
  }

  void _onEvent(PlayEvent event) {
    switch (event) {
      case PlayStarting(:final command):
        _pyro('Running `$command`.');
      case PlayDebuggerAvailable():
        break;
      case PlayStarted(:final elapsed):
        if (_phase == PlayPhase.starting) {
          _setPhase(PlayPhase.running);
          _startWatching();
        }
        _pyro(
          'The game is running '
          '(started in ${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s).',
        );
      case PlayOutput(:final line, :final source):
        // Build output and the tool's notes are part of the game's output
        // for the user; stderr carries the compiler's errors.
        _console.add(
          line,
          source: ConsoleSource.game,
          severity: source == PlayOutputSource.stderr
              ? ConsoleSeverity.error
              : ConsoleSeverity.info,
        );
      case PlayReloading(:final paths):
        _pyro(
          _restarting
              ? 'Restarting the game…'
              : paths.isEmpty
              ? 'Reloading the game…'
              : 'Hot-swap: ${paths.join(', ')}',
        );
      case PlayReloaded(:final elapsed):
        _pyro(
          '${_restarting ? 'Restarted' : 'Reloaded'} in '
          '${elapsed.inMilliseconds} ms.',
        );
        _restarting = false;
      case PlayReloadFailed(:final message):
        _pyro('Reload failed: $message', ConsoleSeverity.error);
        _restarting = false;
      case PlayHotSwapFailed(:final paths):
        _pyro(
          'Saved Scenes stopped reaching the game: the last two saves got '
          'no answer from it. An attached IDE or a stale game can cause '
          'this; restart the game to Hot-swap again.',
          ConsoleSeverity.error,
        );
        _notify(HotSwapFailed(paths));
      case PlayFailed(:final message):
        // The output tail is already in the Console as game lines.
        _pyro("The game couldn't start: $message", ConsoleSeverity.error);
      case PlayStopped(:final exitCode, :final requested):
        final wasRunning =
            _phase == PlayPhase.running || _phase == PlayPhase.stopping;
        if (requested) {
          _pyro('The game was stopped.');
        } else if (wasRunning) {
          _pyro('Game stopped.');
          _notify(GameStopped(exitCode));
        }
    }
  }

  /// While the game runs: Dart saves reload its code once the generator is
  /// done, and a changed image it uses is a notice.
  void _startWatching() {
    _stopWatching();
    _codeWatcher = _makeCodeWatcher?.call(_reloadCode)?..start();
    final images = _imageWatcher = _makeImageWatcher?.call(_onImagesChanged);
    if (images != null) _watchImages(images.start());
  }

  /// Lets an image watcher's start or clear run on its own. Reading the
  /// Scenes can fail (a folder removed by a `git checkout`): that is a line in
  /// the Console, not an uncaught error with the image notice dead.
  void _watchImages(Future<void>? work) {
    if (work == null) return;
    unawaited(
      work.catchError((Object error) {
        _pyro(
          "Can't watch the images the game uses: $error",
          ConsoleSeverity.warning,
        );
      }),
    );
  }

  void _stopWatching() {
    _codeWatcher?.close();
    _codeWatcher = null;
    _imageWatcher?.close();
    _imageWatcher = null;
    _changedImages.clear();
  }

  void _reloadCode() {
    final session = _session;
    if (session == null || _phase != PlayPhase.running) return;
    try {
      unawaited(session.reload().then<void>((_) {}, onError: (Object _) {}));
    } on StateError {
      // The game stopped meanwhile; its stop is reported on its own.
    }
  }

  void _onImagesChanged(Set<String> paths) {
    if (_phase != PlayPhase.running) return;
    _changedImages.addAll(paths);
    final names = (paths.toList()..sort()).join(', ');
    _pyro(
      'Image changed: $names. The game keeps the old one until it restarts.',
      ConsoleSeverity.warning,
    );
    _notify(ImageChanged(Set.of(_changedImages)));
  }

  void _pyro(String text, [ConsoleSeverity severity = ConsoleSeverity.info]) =>
      _console.add(text, source: ConsoleSource.pyro, severity: severity);

  void _setPhase(PlayPhase phase) {
    if (phase == _phase) return;
    _phase = phase;
    if (!_phases.isClosed) _phases.add(phase);
  }

  void _notify(PlayNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }
}
