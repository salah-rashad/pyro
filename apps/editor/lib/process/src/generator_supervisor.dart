import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'build_lock.dart';
import 'generator_output.dart';
import 'generator_state.dart';
import 'play_client.dart' show ProcessStarter;
import 'play_defaults.dart';

/// Runs and follows `build_runner` for the open project (spec 007,
/// contracts/generator-supervisor.md; project plan §9.2, *Q48*, *Q77*).
///
/// Pyro runs `build_runner watch` unless another run holds the project's
/// lock, in which case it only watches the lock and takes over when the
/// other run ends. It stops its own run when the project closes, never an
/// external one (FR-022).
final class GeneratorSupervisor {
  /// Creates the supervisor of [projectPath]'s generator, run with [dart].
  ///
  /// A non-null [setUpProblem] (no `build_runner`, one older than 2.14, or an
  /// incompatible Runtime) makes the generator [GeneratorStatus.notSetUp]:
  /// nothing is probed or spawned.
  GeneratorSupervisor({
    required this.projectPath,
    required this.dart,
    this.setUpProblem,
    this._startProcess = Process.start,
    this._probe = const BuildLockProbe(),
    this.reprobeEvery = PlayDefaults.lockReprobe,
    this.stopTimeout = PlayDefaults.stopTimeout,
  });

  /// The project whose generator this is.
  final String projectPath;

  /// The `dart` executable: `<flutter root>/bin/dart` of the detected SDK.
  final String dart;

  /// Why the generator cannot run in this project, or null.
  final String? setUpProblem;

  /// How often an external run's lock is looked at.
  final Duration reprobeEvery;

  /// How long a stopping run gets before SIGKILL.
  final Duration stopTimeout;

  final ProcessStarter _startProcess;
  final BuildLockProbe _probe;
  final _states = StreamController<GeneratorState>.broadcast();
  final _lines = StreamController<String>.broadcast();
  var _state = GeneratorState.initial;
  Process? _process;
  Timer? _timer;
  Timer? _kill;
  var _starting = false;
  var _disposed = false;
  var _stopRequested = false;
  var _sawTakeover = false;
  var _sawWaiting = false;
  String? _severeFile;
  String? _severeMessage;
  var _expectMessage = false;

  /// Where the generator is.
  GeneratorState get state => _state;

  /// Every change of [state].
  Stream<GeneratorState> get states => _states.stream;

  /// `build_runner`'s output, line by line, for the Console.
  Stream<String> get lines => _lines.stream;

  /// Starts the generator: on project open, and for the *Start* button.
  /// Does nothing while Pyro's own run lives or an attempt is in flight.
  Future<void> start() async {
    if (_disposed || _starting || _process != null) return;
    if (setUpProblem case final problem?) {
      _set(_state.to(GeneratorStatus.notSetUp, reason: problem));
      return;
    }
    _timer?.cancel();
    _starting = true;
    try {
      final lock = await _probe.check(projectPath);
      if (_disposed) return;
      if (lock == LockProbeResult.held) {
        _goExternal();
      } else {
        await _spawn();
      }
    } finally {
      _starting = false;
    }
  }

  /// Stops Pyro's own run (SIGTERM, then SIGKILL after [stopTimeout]) and the
  /// re-probe timer. An external run is left alone.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    final process = _process;
    if (process != null) {
      _stopRequested = true;
      _stop(process);
      await process.exitCode;
      _kill?.cancel();
    }
    await _states.close();
    await _lines.close();
  }

  Future<void> _spawn() async {
    _set(_state.to(GeneratorStatus.starting));
    _sawTakeover = false;
    _sawWaiting = false;
    _stopRequested = false;
    _severeFile = _severeMessage = null;
    _expectMessage = false;
    final Process process;
    try {
      process = await _startProcess(dart, const [
        'run',
        'build_runner',
        'watch',
      ], workingDirectory: projectPath);
    } on ProcessException catch (error) {
      _set(
        _state.to(
          GeneratorStatus.error,
          message: "build_runner couldn't start: ${error.message}",
        ),
      );
      return;
    }
    if (_disposed) {
      _stop(process);
      return;
    }
    _process = process;
    final out = _follow(process.stdout);
    final err = _follow(process.stderr);
    unawaited(
      Future.wait([out, err, process.exitCode]).then((results) {
        _onExit(process, results.last as int);
      }),
    );
  }

  Future<void> _follow(Stream<List<int>> stream) => stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(_onLine);

  void _onLine(String line) {
    if (_disposed) return;
    _lines.add(line);
    if (_expectMessage) {
      _expectMessage = false;
      if (line.startsWith(' ')) {
        _severeMessage = line.trim();
        return;
      }
    }
    switch (classifyGeneratorLine(line)) {
      case GeneratorLine.building:
        if (_state.status != GeneratorStatus.generating) {
          _set(_state.to(GeneratorStatus.generating));
        }
      case GeneratorLine.succeeded:
        _severeFile = _severeMessage = null;
        _set(
          _state.to(
            GeneratorStatus.upToDate,
            generation: _state.generation + 1,
          ),
        );
      case GeneratorLine.severe:
        _severeFile = severeFile(line);
        _severeMessage = line.substring(2).trim();
        _expectMessage = true;
      case GeneratorLine.failed:
        _set(
          _state.to(
            GeneratorStatus.error,
            generation: _state.generation + 1,
            file: _severeFile,
            message: _severeMessage ?? 'The build failed.',
          ),
        );
        _severeFile = _severeMessage = null;
      case GeneratorLine.takeover:
        _sawTakeover = true;
      case GeneratorLine.waiting:
        // Another run took the lock between the probe and the spawn.
        _sawWaiting = true;
        final process = _process;
        if (process != null) _stop(process);
      case GeneratorLine.other:
        break;
    }
  }

  void _onExit(Process process, int code) {
    _kill?.cancel();
    if (!identical(_process, process)) return;
    _process = null;
    if (_disposed || (_stopRequested && !_sawWaiting)) return;
    if (_sawWaiting) {
      unawaited(_afterExit(restartIfFree: true));
    } else if (_sawTakeover || code == 0) {
      unawaited(_afterExit(restartIfFree: false));
    } else {
      _set(
        _state.to(
          GeneratorStatus.error,
          file: _severeFile,
          message: _severeMessage ?? 'build_runner exited with code $code.',
        ),
      );
    }
  }

  /// The takeover table: who holds the lock now decides what happened. A
  /// free lock is looked at twice, one interval apart, because the run that
  /// asked this one to exit may not have taken the lock yet.
  Future<void> _afterExit({required bool restartIfFree}) async {
    _starting = true;
    try {
      var lock = await _probe.check(projectPath);
      if (_disposed) return;
      if (lock != LockProbeResult.held) {
        await Future<void>.delayed(reprobeEvery);
        if (_disposed) return;
        lock = await _probe.check(projectPath);
        if (_disposed) return;
      }
      if (lock == LockProbeResult.held) {
        _goExternal();
      } else if (restartIfFree) {
        await _spawn();
      } else {
        _set(_state.to(GeneratorStatus.stopped));
      }
    } finally {
      _starting = false;
    }
  }

  void _goExternal() {
    _set(_state.to(GeneratorStatus.external));
    _schedule();
  }

  /// Looks at the lock again after [reprobeEvery]; Pyro's own run starts
  /// when the external one has gone.
  void _schedule() {
    _timer?.cancel();
    _timer = Timer(reprobeEvery, () async {
      if (_disposed) return;
      final lock = await _probe.check(projectPath);
      if (_disposed) return;
      if (lock == LockProbeResult.held) {
        _schedule();
        return;
      }
      _starting = true;
      try {
        await _spawn();
      } finally {
        _starting = false;
      }
    });
  }

  void _stop(Process process) {
    process.kill();
    _kill?.cancel();
    _kill = Timer(stopTimeout, () => process.kill(ProcessSignal.sigkill));
  }

  void _set(GeneratorState state) {
    if (state == _state || _disposed) return;
    _state = state;
    _states.add(state);
  }
}
