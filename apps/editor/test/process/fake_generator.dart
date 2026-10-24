import 'dart:collection';
import 'dart:io';

import 'package:pyro/process/process.dart';

import 'fake_process.dart';

/// A lock probe answering from a queue, then with [fallback].
final class FakeProbe implements BuildLockProbe {
  final results = Queue<LockProbeResult>();
  var fallback = LockProbeResult.absent;
  var calls = 0;

  @override
  Future<LockProbeResult> check(String projectPath) async {
    calls++;
    return results.isEmpty ? fallback : results.removeFirst();
  }
}

/// Every `build_runner` the supervisor spawns, newest last.
final class Spawns {
  final processes = <FakeProcess>[];
  final commands = <List<String>>[];
  final directories = <String?>[];
  Exception? error;

  FakeProcess get last => processes.last;

  Future<Process> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    commands.add([executable, ...arguments]);
    directories.add(workingDirectory);
    final error = this.error;
    if (error != null) throw error;
    final process = FakeProcess();
    processes.add(process);
    return process;
  }
}
