import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

import 'fake_generator.dart';
import 'fake_process.dart';

/// A supervisor over fakes.
final class Harness {
  Harness({String? setUpProblem}) {
    supervisor = GeneratorSupervisor(
      projectPath: projectPath,
      dart: '/sdk/bin/dart',
      setUpProblem: setUpProblem,
      startProcess: spawns.call,
      probe: probe,
    );
    supervisor.states.listen(states.add);
    supervisor.lines.listen(lines.add);
  }

  final spawns = Spawns();
  final probe = FakeProbe();
  late final GeneratorSupervisor supervisor;
  final states = <GeneratorState>[];
  final lines = <String>[];

  List<GeneratorStatus> get statuses => [
    for (final state in states) state.status,
  ];

  /// Writes [name]'s lines to the newest process, up to and including the
  /// first for which [until] holds (all of them by default).
  void replay(String name, {bool Function(String line)? until}) {
    spawns.last.queueLines(recorded(name));
    until == null ? spawns.last.emitAll() : spawns.last.emitUntil(until);
  }
}

void main() {
  group('not set up', () {
    test('a problem found before starting spawns nothing', () {
      fakeAsync((async) {
        final h = Harness(
          setUpProblem: 'build_runner 2.13.9 is too old; Pyro needs 2.14.0.',
        );
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.notSetUp);
        expect(h.supervisor.state.reason, contains('2.13.9'));
        expect(h.supervisor.state.reason, contains('2.14'));
        expect(h.spawns.processes, isEmpty);
        expect(h.probe.calls, 0, reason: 'nothing is even probed');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('start() does not change its mind', () {
      fakeAsync((async) {
        final h = Harness(setUpProblem: 'The Runtime is not compatible.');
        unawaited(h.supervisor.start());
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.statuses, [GeneratorStatus.notSetUp]);
      });
    });
  });

  group('starting', () {
    test('a free lock spawns `dart run build_runner watch`', () {
      fakeAsync((async) {
        final h = Harness()..probe.fallback = LockProbeResult.free;
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.spawns.commands, [
          ['/sdk/bin/dart', 'run', 'build_runner', 'watch'],
        ]);
        expect(h.spawns.directories, [projectPath]);
        expect(
          h.spawns.commands.single,
          isNot(contains('--delete-conflicting-outputs')),
        );
        expect(h.supervisor.state.status, GeneratorStatus.starting);
        expect(h.supervisor.state.ownedByPyro, isTrue);
      });
    });

    test('an absent lock file spawns too', () {
      fakeAsync((async) {
        final h = Harness()..probe.fallback = LockProbeResult.absent;
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.spawns.processes, hasLength(1));
      });
    });

    test('goes starting → generating → upToDate and counts the build', () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        h.replay('build-runner-watch.txt', until: (l) => l.contains('Built'));
        async.flushMicrotasks();
        expect(h.statuses, [
          GeneratorStatus.starting,
          GeneratorStatus.generating,
          GeneratorStatus.upToDate,
        ]);
        expect(h.supervisor.state.generation, 1);
        // A save: the second build in the transcript.
        h.spawns.last.emitAll();
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.upToDate);
        expect(h.supervisor.state.generation, 2);
        expect(h.statuses.where((s) => s == GeneratorStatus.generating), [
          GeneratorStatus.generating,
          GeneratorStatus.generating,
        ]);
        expect(h.lines, contains('Starting build #2.'));
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });

    test('start() while its own run lives spawns nothing more', () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.spawns.processes, hasLength(1));
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });

    test('a build_runner that cannot be spawned is an error', () {
      fakeAsync((async) {
        final h = Harness();
        h.spawns.error = const ProcessException('/sdk/bin/dart', ['run']);
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.error);
        expect(h.supervisor.state.message, contains("couldn't start"));
        async.elapse(const Duration(seconds: 10));
        expect(h.spawns.processes, isEmpty, reason: 'no automatic retry');
      });
    });
  });

  group('an external build_runner', () {
    test('a held lock is external and spawns nothing', () {
      fakeAsync((async) {
        final h = Harness()..probe.fallback = LockProbeResult.held;
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.external);
        expect(h.supervisor.state.ownedByPyro, isFalse);
        expect(h.spawns.processes, isEmpty);
        unawaited(h.supervisor.dispose());
        async.flushMicrotasks();
      });
    });

    test('is re-probed every second and replaced when it ends', () {
      fakeAsync((async) {
        final h = Harness()..probe.fallback = LockProbeResult.held;
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.probe.calls, 1);
        async.elapse(PlayDefaults.lockReprobe * 3);
        expect(h.probe.calls, 4);
        expect(h.spawns.processes, isEmpty);
        h.probe.fallback = LockProbeResult.free;
        async.elapse(PlayDefaults.lockReprobe);
        expect(h.spawns.processes, hasLength(1));
        expect(h.supervisor.state.status, GeneratorStatus.starting);
        expect(h.supervisor.state.ownedByPyro, isTrue);
        final calls = h.probe.calls;
        async.elapse(const Duration(seconds: 5));
        expect(h.probe.calls, calls, reason: 'the re-probe stopped');
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });
  });

  group('the takeover table (Q77)', () {
    Harness started() {
      final h = Harness()..probe.fallback = LockProbeResult.free;
      unawaited(h.supervisor.start());
      return h;
    }

    test('held after the exit: external, then Pyro runs again when free', () {
      fakeAsync((async) {
        final h = started();
        async.flushMicrotasks();
        h.replay('build-runner-takeover.txt');
        async.flushMicrotasks();
        // The user's own `build_runner build` took the lock.
        h.probe.fallback = LockProbeResult.held;
        h.spawns.last.exit(0);
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.external);
        expect(h.supervisor.state.ownedByPyro, isFalse);
        expect(h.spawns.processes, hasLength(1));
        async.elapse(PlayDefaults.lockReprobe * 2);
        expect(h.supervisor.state.status, GeneratorStatus.external);
        // …and finished.
        h.probe.fallback = LockProbeResult.free;
        async.elapse(PlayDefaults.lockReprobe);
        expect(h.spawns.processes, hasLength(2));
        expect(h.supervisor.state.status, GeneratorStatus.starting);
        expect(
          h.statuses.where((s) => s == GeneratorStatus.error),
          isEmpty,
          reason: 'a takeover is not an error',
        );
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });

    test('free after the exit: stopped, and Pyro does not restart', () {
      fakeAsync((async) {
        final h = started();
        async.flushMicrotasks();
        h.replay('build-runner-stop.txt');
        h.spawns.last.exit(0);
        async.flushMicrotasks();
        async.elapse(PlayDefaults.lockReprobe * 2);
        expect(h.supervisor.state.status, GeneratorStatus.stopped);
        expect(h.supervisor.state.ownedByPyro, isTrue);
        expect(h.spawns.processes, hasLength(1));
        async.elapse(const Duration(seconds: 30));
        expect(h.spawns.processes, hasLength(1));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a new run that takes the lock just after the exit is external', () {
      fakeAsync((async) {
        final h = started();
        async.flushMicrotasks();
        h.replay('build-runner-takeover.txt');
        // Free at the exit, held a moment later: the new run was starting.
        h.probe.results.add(LockProbeResult.free);
        h.spawns.last.exit(0);
        async.flushMicrotasks();
        h.probe.fallback = LockProbeResult.held;
        async.elapse(PlayDefaults.lockReprobe);
        expect(h.supervisor.state.status, GeneratorStatus.external);
        unawaited(h.supervisor.dispose());
        async.flushMicrotasks();
      });
    });

    test('Start restarts a stopped generator', () {
      fakeAsync((async) {
        final h = started();
        async.flushMicrotasks();
        h.replay('build-runner-stop.txt');
        h.spawns.last.exit(0);
        async.elapse(PlayDefaults.lockReprobe * 2);
        expect(h.supervisor.state.status, GeneratorStatus.stopped);
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.spawns.processes, hasLength(2));
        expect(h.supervisor.state.status, GeneratorStatus.starting);
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });

    test('a code-0 exit with no takeover line is treated the same way', () {
      fakeAsync((async) {
        final h = started();
        async.flushMicrotasks();
        h.spawns.last.exit(0);
        async.elapse(PlayDefaults.lockReprobe * 2);
        expect(h.supervisor.state.status, GeneratorStatus.stopped);
      });
    });

    test('the waiting case: stops its own run and goes external', () {
      fakeAsync((async) {
        final h = started();
        async.flushMicrotasks();
        // Another run took the lock between the probe and the spawn.
        h.replay('build-runner-waiting.txt', until: (l) => l.contains('Wait'));
        async.flushMicrotasks();
        expect(h.spawns.last.signals, [ProcessSignal.sigterm]);
        h.probe.fallback = LockProbeResult.held;
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.external);
        expect(h.spawns.processes, hasLength(1));
        unawaited(h.supervisor.dispose());
        async.flushMicrotasks();
      });
    });
  });

  group('errors', () {
    test('a failed build carries its file and message, then recovers', () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        h.replay('build-runner-error.txt', until: (l) => l.contains('Failed'));
        async.flushMicrotasks();
        final state = h.supervisor.state;
        expect(state.status, GeneratorStatus.error);
        expect(state.file, 'lib/behaviors/spin.dart');
        expect(state.message, '11:27: Expected an identifier.');
        expect(state.ownedByPyro, isTrue);
        // The fix is saved: the watcher builds again.
        h.spawns.last.emitAll();
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.upToDate);
        expect(h.supervisor.state.file, isNull);
        expect(h.supervisor.state.message, isNull);
        expect(h.supervisor.state.generation, 3);
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });

    test(
      'a non-zero exit is an error with the last severe line, no restart',
      () {
        fakeAsync((async) {
          final h = Harness();
          unawaited(h.supervisor.start());
          async.flushMicrotasks();
          h.spawns.last
            ..emitLine('E pyro_generator:pyro_scan on lib/a.dart:')
            ..emitLine('  1:1: Something is wrong.')
            ..exit(78);
          async.elapse(const Duration(seconds: 10));
          expect(h.supervisor.state.status, GeneratorStatus.error);
          expect(h.supervisor.state.message, contains('Something is wrong'));
          expect(h.spawns.processes, hasLength(1));
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('a crash with no severe line says what exited', () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        h.spawns.last.exit(255);
        async.flushMicrotasks();
        expect(h.supervisor.state.status, GeneratorStatus.error);
        expect(h.supervisor.state.message, contains('255'));
      });
    });

    test('Start after an error runs build_runner again', () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        h.spawns.last.exit(1);
        async.flushMicrotasks();
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        expect(h.spawns.processes, hasLength(2));
        unawaited(h.supervisor.dispose());
        h.spawns.last.exit(-15);
        async.flushMicrotasks();
      });
    });
  });

  group('dispose', () {
    test(
      'stops its own child with SIGTERM, then SIGKILL, and leaves no timer',
      () {
        fakeAsync((async) {
          final h = Harness();
          unawaited(h.supervisor.start());
          async.flushMicrotasks();
          var done = false;
          unawaited(h.supervisor.dispose().then((_) => done = true));
          async.flushMicrotasks();
          expect(h.spawns.last.signals, [ProcessSignal.sigterm]);
          async.elapse(PlayDefaults.stopTimeout);
          expect(h.spawns.last.signals, [
            ProcessSignal.sigterm,
            ProcessSignal.sigkill,
          ]);
          h.spawns.last.exit(-9);
          async.flushMicrotasks();
          expect(done, isTrue);
          expect(async.pendingTimers, isEmpty);
          expect(
            h.spawns.processes,
            hasLength(1),
            reason: 'its exit is not a takeover to answer',
          );
        });
      },
    );

    test('never touches an external run and cancels the re-probe', () {
      fakeAsync((async) {
        final h = Harness()..probe.fallback = LockProbeResult.held;
        unawaited(h.supervisor.start());
        async.flushMicrotasks();
        unawaited(h.supervisor.dispose());
        async.flushMicrotasks();
        final calls = h.probe.calls;
        async.elapse(const Duration(seconds: 10));
        expect(h.probe.calls, calls);
        expect(h.spawns.processes, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a probe that answers after dispose spawns nothing', () {
      fakeAsync((async) {
        final h = Harness()..probe.fallback = LockProbeResult.free;
        unawaited(h.supervisor.start());
        unawaited(h.supervisor.dispose());
        async.flushMicrotasks();
        expect(h.spawns.processes, isEmpty);
      });
    });
  });
}
