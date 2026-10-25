import 'dart:io' show Process, ProcessException;

import 'package:file/file.dart';
import 'package:file/local.dart';

import 'play_defaults.dart';
import 'play_event.dart';
import 'play_session.dart';
import 'run_link.dart';
import 'scene_watcher.dart';
import 'vm_service_link.dart';

/// Starts a process; [Process.start]'s shape, so tests can pass a fake.
typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Connects to the game's VM service; [VmServiceLink.connect] in the app, a
/// fake in tests.
typedef VmServiceConnector = Future<VmServiceLink> Function(String wsUri);

/// The arguments for `flutter run`: the macOS desktop target in debug mode,
/// with VM service auth codes on (Q81) and no IDE workarounds (research R9).
const _runArguments = ['run', '--machine', '-d', 'macos', '--debug'];

/// Starts the developer's game with `flutter run --machine` and Hot-swaps its
/// Scenes when they change on disk (project plan §9.3; spec 005).
final class PlayClient {
  /// Creates a client that runs [flutter] (on `PATH` by default) through
  /// [startProcess] and checks and watches files through [fileSystem] and
  /// [watchDirectory]. A burst of Scene changes becomes one hot reload after
  /// [quietPeriod]; [PlaySession.stop] escalates to SIGTERM after
  /// [stopTimeout].
  PlayClient({
    this.flutter = 'flutter',
    this._startProcess = Process.start,
    FileSystem fileSystem = const LocalFileSystem(),
    this._watchDirectory = watchRecursively,
    this.quietPeriod = PlayDefaults.sceneQuiet,
    this.stopTimeout = PlayDefaults.stopTimeout,
    this._vmConnect = VmServiceLink.connect,
  }) : _fs = fileSystem;

  /// The `flutter` executable.
  final String flutter;

  /// How long Scene files must stay unchanged before a hot reload (R8).
  final Duration quietPeriod;

  /// How long [PlaySession.stop] waits after `app.stop` (R10).
  final Duration stopTimeout;

  final ProcessStarter _startProcess;
  final FileSystem _fs;
  final DirectoryWatcher _watchDirectory;
  final VmServiceConnector _vmConnect;

  /// Spawns `flutter run --machine -d macos --debug` in [projectPath].
  ///
  /// [onStdoutLine] receives every stdout line of the process, auth codes
  /// masked, before it is parsed (the CLI's `--record`).
  ///
  /// With a [runLink], the game runs with `--project-root <link>` (the
  /// working directory stays the real project) and every Scene Hot-swap
  /// points the engine's asset reads at the project first, so an IDE attached
  /// to the game cannot break it (spec 007, research R2, R5). Without one the
  /// behavior is spec 005's.
  ///
  /// Throws [PlayStartException] when the project has no `pubspec.yaml` or
  /// `macos/` folder, or when the executable can't be started.
  Future<PlaySession> start(
    String projectPath, {
    RunLink? runLink,
    void Function(String line)? onStdoutLine,
  }) async {
    final path = _fs.path.normalize(_fs.path.absolute(projectPath));
    if (!_fs.file(_fs.path.join(path, 'pubspec.yaml')).existsSync()) {
      throw PlayStartException(path, 'there is no pubspec.yaml in it.');
    }
    if (!_fs.directory(_fs.path.join(path, 'macos')).existsSync()) {
      throw PlayStartException(
        path,
        'it has no macos/ folder; add the macOS target with '
        '`flutter create --platforms=macos .`.',
      );
    }
    final arguments = [
      ..._runArguments,
      if (runLink != null) ...['--project-root', runLink.path],
    ];
    final Process process;
    try {
      process = await _startProcess(flutter, arguments, workingDirectory: path);
    } on ProcessException catch (error) {
      throw PlayStartException(
        path,
        'could not start "${error.executable}": ${error.message}',
      );
    }
    return startPlaySession(
      process: process,
      command: [flutter, ...arguments].join(' '),
      projectPath: path,
      fileSystem: _fs,
      watchDirectory: _watchDirectory,
      quietPeriod: quietPeriod,
      stopTimeout: stopTimeout,
      onStdoutLine: onStdoutLine,
      repoint: runLink != null,
      vmConnect: _vmConnect,
    );
  }
}
