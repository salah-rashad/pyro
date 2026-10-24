import 'dart:async';

import 'console_buffer.dart';
import 'console_line.dart';
import 'play_block.dart';
import 'play_event.dart';
import 'play_session.dart';

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

/// Starts a Play session for a project; `PlayClient.start` in the app,
/// a fake in tests.
typedef PlayStarter = Future<PlaySession> Function(String projectPath);

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
  });

  /// The project the game runs from.
  final String projectPath;

  /// Why Play is disabled, or null when it is available (FR-003).
  final PlayBlock? block;

  final ConsoleBuffer _console;
  final PlayStarter _start;
  final _phases = StreamController<PlayPhase>.broadcast();
  final _notices = StreamController<PlayNotice>.broadcast();
  var _phase = PlayPhase.stopped;
  PlaySession? _session;
  Future<void>? _ended;
  var _disposed = false;

  /// Where the game is.
  PlayPhase get phase => _phase;

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
    final PlaySession session;
    try {
      session = await _start(projectPath);
    } on PlayStartException catch (error) {
      _pyro('$error', ConsoleSeverity.error);
      _setPhase(PlayPhase.stopped);
      return;
    }
    _session = session;
    final ended = Completer<void>();
    _ended = ended.future;
    session.events.listen(
      _onEvent,
      onDone: () {
        if (identical(_session, session)) _session = null;
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
    if (session == null) return;
    await session.stop();
    await _ended;
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
        if (_phase == PlayPhase.starting) _setPhase(PlayPhase.running);
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
          paths.isEmpty
              ? 'Reloading the game…'
              : 'Hot-swap: ${paths.join(', ')}',
        );
      case PlayReloaded(:final elapsed):
        _pyro('Reloaded in ${elapsed.inMilliseconds} ms.');
      case PlayReloadFailed(:final message):
        _pyro('Reload failed: $message', ConsoleSeverity.error);
      case PlayHotSwapFailed():
        _pyro(
          'Saved Scenes stopped reaching the game: the last two saves got '
          'no answer from it. Restart the game to Hot-swap again.',
          ConsoleSeverity.error,
        );
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
