/// Where a Play session is in its life (spec 005, data model "States").
enum PlayState {
  /// `flutter run` is building and launching the game.
  starting,

  /// The game is running; Scene changes trigger hot reloads.
  running,

  /// A hot reload is in flight.
  reloading,

  /// `PlaySession.stop` was called; waiting for the process to exit.
  stopping,

  /// The process has exited. Final.
  stopped,
}

/// Where a [PlayOutput] line came from.
enum PlayOutputSource {
  /// The game: `app.log`, or a raw stdout line (desktop targets pass the
  /// game's stdout through unchanged).
  game,

  /// flutter_tools: build progress and its log messages.
  tool,

  /// The `flutter run` process's stderr.
  stderr,
}

/// The outcome of one hot reload.
final class ReloadResult {
  const ReloadResult({required this.ok, required this.elapsed, this.message});

  /// Whether the daemon reported success (`code` 0).
  final bool ok;

  /// The daemon's message; for a failure, why (a compile error names the
  /// file and line).
  final String? message;

  /// From sending the request to its response.
  final Duration elapsed;
}

/// What a Play session tells its caller, in order. No event carries the VM
/// service address (spec 005, FR-021).
sealed class PlayEvent {
  const PlayEvent();
}

/// `flutter run` was spawned.
final class PlayStarting extends PlayEvent {
  const PlayStarting({required this.command, required this.projectPath});

  /// The command line, such as `flutter run --machine -d macos --debug`.
  final String command;

  /// The project it runs in.
  final String projectPath;

  @override
  String toString() => 'starting: $command  (in $projectPath)';
}

/// The game's debugger is available. Attach (#11) reads the address from the
/// daemon itself; this event deliberately has none.
final class PlayDebuggerAvailable extends PlayEvent {
  const PlayDebuggerAvailable();

  @override
  String toString() => 'debugger available';
}

/// The game is running and hot reloads can be sent.
final class PlayStarted extends PlayEvent {
  const PlayStarted({required this.appId, required this.elapsed});

  /// The daemon's id for the running app.
  final String appId;

  /// From spawning `flutter run` to this event.
  final Duration elapsed;

  @override
  String toString() =>
      'started (app $appId) in ${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

/// One line of output, with any auth code masked.
final class PlayOutput extends PlayEvent {
  const PlayOutput(this.line, this.source);

  /// The line, redacted.
  final String line;

  /// Where it came from.
  final PlayOutputSource source;

  @override
  String toString() => '${source.name}: $line';
}

/// A hot reload was requested.
final class PlayReloading extends PlayEvent {
  const PlayReloading(this.paths);

  /// The changed Scene files, project-relative with `/` separators; empty for
  /// a manual reload.
  final List<String> paths;

  @override
  String toString() =>
      paths.isEmpty ? 'reloading' : 'reloading: ${paths.join(', ')}';
}

/// The hot reload succeeded. Whether a Scene was rebuilt is the Runtime's
/// call (it rebuilds only changed content).
final class PlayReloaded extends PlayEvent {
  const PlayReloaded(this.elapsed);

  /// From sending the request to its response.
  final Duration elapsed;

  @override
  String toString() => 'reloaded in ${elapsed.inMilliseconds}ms';
}

/// The hot reload failed; the game keeps running its previous code.
final class PlayReloadFailed extends PlayEvent {
  const PlayReloadFailed(this.message, {this.code});

  /// The daemon's reason, redacted.
  final String message;

  /// The daemon's non-zero result code, when it sent one.
  final int? code;

  @override
  String toString() => 'reload failed: $message';
}

/// Scene saves stopped reaching the game: two in a row got no report from it
/// (FR-011, research R6). Scene Hot-swaps stop until the game is restarted.
final class PlayHotSwapFailed extends PlayEvent {
  const PlayHotSwapFailed(this.paths, this.misses);

  /// The Scenes of the last missed save, project-relative.
  final Set<String> paths;

  /// How many saves in a row got no report.
  final int misses;

  @override
  String toString() => 'Hot-swap failed ($misses saves unreported)';
}

/// The game couldn't start: `flutter run` ended before the app started.
final class PlayFailed extends PlayEvent {
  const PlayFailed({
    required this.message,
    required this.outputTail,
    this.exitCode,
  });

  /// What failed.
  final String message;

  /// `flutter run`'s exit code.
  final int? exitCode;

  /// The last output lines (at most 20, redacted), where the tool says why.
  final List<String> outputTail;

  @override
  String toString() => [
    'failed: $message',
    for (final line in outputTail) '    $line',
  ].join('\n');
}

/// The `flutter run` process exited. Always the last event.
final class PlayStopped extends PlayEvent {
  const PlayStopped({required this.exitCode, required this.requested});

  /// Its exit code.
  final int exitCode;

  /// Whether `PlaySession.stop` asked for it, rather than the game quitting,
  /// crashing or failing to start.
  final bool requested;

  @override
  String toString() => 'stopped (exit $exitCode)';
}

/// The project can't be played, or `flutter` can't be started.
final class PlayStartException implements Exception {
  const PlayStartException(this.projectPath, this.message);

  /// The project that was to be played.
  final String projectPath;

  /// What's wrong, naming the file, folder or executable.
  final String message;

  @override
  String toString() => "Can't play $projectPath: $message";
}
