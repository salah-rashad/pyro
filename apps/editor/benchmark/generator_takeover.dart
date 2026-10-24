// Drives the generator supervisor against the real `build_runner` in
// `example/` (spec 007, quickstart §3.3), for the parts that need no window:
//
//   SC-004  a new annotated Behavior reaches lib/pyro.manifest.json in at
//           most 5 s (the catalog's own reload adds `manifestQuietPeriod`);
//   SC-008  ten times, the user's own `dart run build_runner build` while
//           Pyro's run is active always finishes its build, and Pyro's run
//           comes back;
//   Q77     `build_runner stop` leaves the generator stopped, restarting
//           nothing;
//   FR-019  a syntax error in an annotated class is an error naming the file.
//
// Usage, from apps/editor, with no build_runner running in the project:
//   dart run benchmark/generator_takeover.dart [project] [dart]
//   (defaults: ../../example, `dart` on PATH)
//
// It rewrites files under example/lib/behaviors/ and restores them when it
// ends; check `git status` afterwards. Prints a Markdown table and exits 1
// if a criterion fails.
import 'dart:async';
import 'dart:io';

import 'package:pyro/process/process.dart';

const _spin = 'lib/behaviors/spin.dart';
const _manifest = 'lib/pyro.manifest.json';

Future<void> main(List<String> args) async {
  final project = Directory(
    args.isEmpty ? '../../example' : args.first,
  ).absolute.path;
  final dart = args.length > 1 ? args[1] : 'dart';
  final spin = File('$project/$_spin');
  final spinText = spin.readAsStringSync();
  final supervisor = GeneratorSupervisor(projectPath: project, dart: dart);
  final trail = <GeneratorStatus>[];
  supervisor.states.listen((state) => trail.add(state.status));
  final created = <File>[];
  final rows = <List<String>>[];
  var ok = true;

  Future<GeneratorState> until(
    bool Function(GeneratorState state) test, {
    int seconds = 90,
  }) async {
    if (test(supervisor.state)) return supervisor.state;
    return supervisor.states
        .firstWhere(test)
        .timeout(
          Duration(seconds: seconds),
          onTimeout: () => throw StateError(
            'timed out in ${supervisor.state}; trail ${trail.join(' → ')}',
          ),
        );
  }

  try {
    await supervisor.start();
    await until((s) => s.status == GeneratorStatus.upToDate);

    // SC-004: a new annotated Behavior, to the Manifest on disk.
    final manifest = File('$project/$_manifest');
    final times = <int>[];
    for (var i = 1; i <= 3; i++) {
      final file = File('$project/lib/behaviors/bench_probe_$i.dart');
      created.add(file);
      final watch = Stopwatch()..start();
      file.writeAsStringSync(_probeBehavior(i));
      while (!manifest.readAsStringSync().contains('BenchProbe$i')) {
        if (watch.elapsed > const Duration(seconds: 30)) {
          throw StateError('BenchProbe$i never reached the Manifest');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      times.add(watch.elapsedMilliseconds);
      final generation = supervisor.state.generation;
      file.deleteSync();
      await until(
        (s) =>
            s.status == GeneratorStatus.upToDate && s.generation > generation,
      );
    }
    times.sort();
    final sc004 = times.last <= 5000;
    ok &= sc004;
    rows.add([
      'SC-004 save → Manifest on disk',
      'median ${times[1]} ms, worst ${times.last} ms (limit 5000 ms)',
      sc004 ? 'pass' : 'FAIL',
    ]);

    // FR-019: a syntax error names its file; the fix recovers.
    spin.writeAsStringSync(
      spinText.replaceFirst('double turnsPerSecond = 0.25;', 'double x = ;'),
    );
    final error = await until((s) => s.status == GeneratorStatus.error);
    spin.writeAsStringSync(spinText);
    await until((s) => s.status == GeneratorStatus.upToDate);
    final fr019 = error.file == _spin && (error.message ?? '').isNotEmpty;
    ok &= fr019;
    rows.add([
      'FR-019 syntax error',
      'file ${error.file}, "${error.message}"',
      fr019 ? 'pass' : 'FAIL',
    ]);

    // SC-008: the user's `build` while Pyro's run is active, ten times.
    var finished = 0;
    var back = 0;
    var stoppedAfter = 0;
    for (var attempt = 1; attempt <= 10; attempt++) {
      await until((s) => s.status == GeneratorStatus.upToDate);
      final trailStart = trail.length;
      final result = await Process.run(dart, [
        'run',
        'build_runner',
        'build',
      ], workingDirectory: project);
      if (result.exitCode == 0 && '${result.stdout}'.contains('Built with')) {
        finished++;
      } else {
        stderr.writeln('attempt $attempt: exit ${result.exitCode}');
        stderr.writeln('${result.stdout}${result.stderr}');
      }
      // Pyro's run comes back by itself, or (the user's build was over
      // before the lock was looked at twice) stops and offers Start.
      final settled = await until(
        (s) =>
            (s.status == GeneratorStatus.upToDate &&
                trail.skip(trailStart).contains(GeneratorStatus.external)) ||
            s.status == GeneratorStatus.stopped,
      );
      if (settled.status == GeneratorStatus.stopped) {
        stoppedAfter++;
        await supervisor.start();
      } else {
        back++;
      }
    }
    final sc008 = finished == 10;
    ok &= sc008;
    rows.add([
      'SC-008 user\'s `build` finishes (10 attempts)',
      '$finished of 10 finished; Pyro\'s run came back by itself $back times, '
          'stopped $stoppedAfter times (the build was over first)',
      sc008 ? 'pass' : 'FAIL',
    ]);

    // Q77: `build_runner stop` leaves it stopped, and nothing restarts.
    await until((s) => s.status == GeneratorStatus.upToDate);
    await Process.run(dart, [
      'run',
      'build_runner',
      'stop',
    ], workingDirectory: project);
    await until((s) => s.status == GeneratorStatus.stopped, seconds: 30);
    await Future<void>.delayed(const Duration(seconds: 5));
    final q77 = supervisor.state.status == GeneratorStatus.stopped;
    ok &= q77;
    rows.add([
      'Q77 `build_runner stop`',
      'still ${supervisor.state.status.name} after 5 s',
      q77 ? 'pass' : 'FAIL',
    ]);
  } on Object catch (error, stack) {
    ok = false;
    stderr
      ..writeln('The run failed: $error')
      ..writeln(stack);
  } finally {
    spin.writeAsStringSync(spinText);
    for (final file in created) {
      if (file.existsSync()) file.deleteSync();
    }
    await supervisor.dispose();
  }

  stdout
    ..writeln('| Criterion | Measured | Result |')
    ..writeln('|---|---|---|');
  for (final row in rows) {
    stdout.writeln('| ${row.join(' | ')} |');
  }
  stdout.writeln('\nStatus trail: ${trail.map((s) => s.name).join(' → ')}');
  await stdout.flush();
  exit(ok ? 0 : 1);
}

String _probeBehavior(int n) =>
    '''
import 'package:pyro_runtime/pyro_runtime.dart';

/// A probe the generator benchmark adds and removes.
@PyroBehavior()
class BenchProbe$n extends Behavior<PyroEntity> {
  /// A field, so the Manifest has something to describe.
  @Editable()
  bool on = true;
}
''';
