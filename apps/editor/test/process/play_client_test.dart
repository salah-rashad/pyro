import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

import 'fake_process.dart';

/// Every file and folder in [fs], for checking that nothing was written.
List<String> entries(MemoryFileSystem fs) =>
    fs.directory('/').listSync(recursive: true).map((e) => e.path).toList()
      ..sort();

void main() {
  group('spawn', () {
    test(
      'runs flutter run --machine on macOS in the project, writing nothing',
      () {
        fakeAsync((async) {
          const awkward = '/work/My Game ñ';
          final fs = projectFileSystem(path: awkward);
          final before = entries(fs);
          final process = FakeProcess();
          final starter = FakeStarter(process);
          late PlaySession session;
          unawaited(
            PlayClient(
              startProcess: starter.call,
              fileSystem: fs,
              watchDirectory: (_) => const Stream.empty(),
            ).start(awkward).then((s) => session = s),
          );
          async.flushMicrotasks();

          expect(starter.executable, 'flutter');
          expect(starter.arguments, [
            'run',
            '--machine',
            '-d',
            'macos',
            '--debug',
          ]);
          expect(starter.workingDirectory, awkward);
          expect(session.projectPath, awkward);

          process.play('start.txt');
          unawaited(session.stop());
          process.exit(0);
          async.elapse(const Duration(seconds: 2));
          expect(entries(fs), before);
        });
      },
    );

    test('uses the given flutter executable', () {
      fakeAsync((async) {
        final starter = FakeStarter(FakeProcess());
        unawaited(
          PlayClient(
            flutter: '/sdk/flutter/bin/flutter',
            startProcess: starter.call,
            fileSystem: projectFileSystem(),
            watchDirectory: (_) => const Stream.empty(),
          ).start(projectPath),
        );
        async.flushMicrotasks();
        expect(starter.executable, '/sdk/flutter/bin/flutter');
      });
    });
  });

  group('start failures', () {
    Future<PlaySession> start(
      MemoryFileSystem fs, {
      Exception? error,
      FakeProcess? process,
    }) => PlayClient(
      startProcess: FakeStarter(process ?? FakeProcess(), error: error).call,
      fileSystem: fs,
      watchDirectory: (_) => const Stream.empty(),
    ).start(projectPath);

    Matcher startException(String detail) => throwsA(
      isA<PlayStartException>()
          .having((e) => e.projectPath, 'projectPath', projectPath)
          .having((e) => '$e', 'message', contains(detail)),
    );

    test('a folder without pubspec.yaml', () {
      final fs = projectFileSystem()
        ..file('$projectPath/pubspec.yaml').deleteSync();
      expect(start(fs), startException('pubspec.yaml'));
    });

    test('a project without a macos/ folder', () {
      final fs = projectFileSystem()
        ..directory('$projectPath/macos').deleteSync();
      expect(start(fs), startException('macos/'));
    });

    test('flutter missing from PATH', () {
      expect(
        start(
          projectFileSystem(),
          error: const ProcessException(
            'flutter',
            ['run'],
            'No such file or directory',
            2,
          ),
        ),
        startException('could not start "flutter": No such file or directory'),
      );
    });

    test('flutter exiting before the game starts quotes its output', () {
      fakeAsync((async) {
        final process = FakeProcess();
        final events = <PlayEvent>[];
        unawaited(
          start(
            projectFileSystem(),
            process: process,
          ).then((s) => s.events.listen(events.add)),
        );
        async.flushMicrotasks();
        process.play('no_macos_target.txt');
        process.exit(1);
        async.elapse(const Duration(seconds: 2));

        final failed = events.whereType<PlayFailed>().single;
        expect(failed.exitCode, 1);
        expect(failed.message, contains('exited with code 1'));
        expect(failed.outputTail, [
          'Launching lib/main.dart on macOS in debug mode...',
          contains('No macOS desktop project configured'),
        ]);
        expect(events.last, isA<PlayStopped>());
      });
    });

    test('keeps only the last 20 lines', () {
      fakeAsync((async) {
        final process = FakeProcess();
        final events = <PlayEvent>[];
        unawaited(
          start(
            projectFileSystem(),
            process: process,
          ).then((s) => s.events.listen(events.add)),
        );
        async.flushMicrotasks();
        for (var i = 1; i <= 30; i++) {
          process.emitLine('line $i');
        }
        process.exit(1);
        async.elapse(const Duration(seconds: 2));
        final tail = events.whereType<PlayFailed>().single.outputTail;
        expect(tail, hasLength(20));
        expect(tail.first, 'line 11');
      });
    });

    test('app.stop with an error before the start is the reason', () {
      fakeAsync((async) {
        final process = FakeProcess();
        final events = <PlayEvent>[];
        unawaited(
          start(
            projectFileSystem(),
            process: process,
          ).then((s) => s.events.listen(events.add)),
        );
        async.flushMicrotasks();
        process.emitLine(
          '[{"event":"app.stop","params":{"appId":"app-1",'
          '"error":"Unable to start the app on the device."}}]',
        );
        process.exit(1);
        async.elapse(const Duration(seconds: 2));
        expect(
          events.whereType<PlayFailed>().single.message,
          contains('Unable to start the app on the device.'),
        );
      });
    });

    test('a second session after a stop works', () {
      fakeAsync((async) {
        final fs = projectFileSystem();
        for (var run = 0; run < 2; run++) {
          final process = FakeProcess();
          late PlaySession session;
          unawaited(start(fs, process: process).then((s) => session = s));
          async.flushMicrotasks();
          process.play('start.txt');
          async.flushMicrotasks();
          expect(session.state, PlayState.running, reason: 'run $run');
          unawaited(session.stop());
          process.exit(0);
          async.elapse(const Duration(seconds: 2));
          expect(session.state, PlayState.stopped);
        }
      });
    });
  });

  test('lib/process/ imports no Flutter and touches no file directly', () {
    // providers.dart is the Riverpod layer beside the units (spec 007,
    // plan.md): nothing else in lib/process/, and not bin/play.dart,
    // imports it.
    final sources = Directory('lib/process')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => !f.path
              .replaceAll('\\', '/')
              .endsWith('lib/process/providers.dart'),
        );
    expect(sources, isNotEmpty);
    for (final source in [...sources, File('bin/play.dart')]) {
      expect(
        source.readAsStringSync(),
        isNot(contains('providers.dart')),
        reason: source.path,
      );
    }
    for (final source in sources) {
      final text = source.readAsStringSync();
      expect(text, isNot(contains('package:flutter')), reason: source.path);
      expect(text, isNot(contains('riverpod')), reason: source.path);
      expect(
        text,
        isNot(matches(RegExp(r'\b(File|Directory)\('))),
        reason: '${source.path}: use the injected FileSystem',
      );
    }
  });
}
