import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemEvent, FileSystemModifyEvent, ProcessSignal;

import 'package:fake_async/fake_async.dart';
import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

import 'fake_process.dart';
import 'fake_vm.dart';

/// The watcher of the images in use, recording what the controller asks.
final class FakeImages implements ImageWatching {
  void Function(Set<String> paths)? onChanged;
  var starts = 0;
  var clears = 0;
  var closed = false;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> clear() async => clears++;

  @override
  void close() => closed = true;
}

/// A controller over a fake `flutter run` that replays recordings.
final class Harness {
  Harness({this.block, bool link = false, this.linkFails = false}) {
    fs.directory('$projectPath/lib').createSync(recursive: true);
    controller = PlayController(
      projectPath: projectPath,
      console: console,
      block: block,
      makeRunLink: link
          ? (path) async => linkFails
                ? null
                : RunLink.create(path, supportDir: '/support', fileSystem: fs)
          : null,
      makeCodeWatcher: (onReload) => CodeWatcher(
        fileSystem: fs,
        projectPath: projectPath,
        watch: (_) => codeChanges.stream,
        generatorState: () => generator,
        generatorStates: generatorStates.stream,
        onReload: onReload,
      ),
      makeImageWatcher: (onChanged) {
        final images = FakeImages()..onChanged = onChanged;
        imageWatchers.add(images);
        return images;
      },
      start: (path, {runLink}) {
        starts++;
        return PlayClient(
          startProcess: starter.call,
          fileSystem: fs,
          watchDirectory: (_) => changes.stream,
          vmConnect: vm.connect,
        ).start(path, runLink: runLink);
      },
    );
    controller.phases.listen(phases.add);
    controller.notices.listen(notices.add);
  }

  final PlayBlock? block;
  final bool linkFails;
  final fs = projectFileSystem();
  final vm = FakeVm();
  // Closed with the test's zone; nothing to release.
  // ignore: close_sinks
  final changes = StreamController<FileSystemEvent>.broadcast();
  // ignore: close_sinks
  final codeChanges = StreamController<FileSystemEvent>.broadcast();
  // ignore: close_sinks
  final generatorStates = StreamController<GeneratorState>.broadcast();
  var generator = const GeneratorState(GeneratorStatus.upToDate);
  final imageWatchers = <FakeImages>[];
  final process = FakeProcess();
  late final starter = FakeStarter(process);
  final console = ConsoleBuffer();
  late final PlayController controller;
  final phases = <PlayPhase>[];
  final notices = <PlayNotice>[];
  var starts = 0;

  /// Answers every daemon request with success; `app.stop` also ends the
  /// process the way the recording did.
  void answerRequests() {
    process.onRequest = (request) {
      process.emitLine(
        jsonEncode([
          {
            'id': request['id'],
            'result': request['method'] == 'app.restart'
                ? {'code': 0, 'message': ''}
                : true,
          },
        ]),
      );
      if (request['method'] == 'app.stop') {
        process.emitLine('Application finished.');
        process.exit(0);
      }
    };
  }

  /// A debug port line with [code] in its address.
  String debugPort(String code) =>
      '[{"event":"app.debugPort","params":{"appId":"app-1","port":5001,'
      '"wsUri":"ws://127.0.0.1:5001/$code=/ws","baseUri":"file:///p/"}}]';

  /// Replays [name] up to and including its `app.started` event.
  void startedFrom(String name) {
    process.queueLines(recorded(name));
    process.emitUntil((line) => line.contains('"app.started"'));
  }

  /// The requests of method [method] the game was sent.
  List<Map<String, Object?>> requestsOf(String method) =>
      process.requests.where((r) => r['method'] == method).toList();

  void saveCode(String relative) => codeChanges.add(
    FileSystemModifyEvent('$projectPath/$relative', false, true),
  );

  Iterable<ConsoleLine> linesFrom(ConsoleSource source) =>
      console.lines.where((line) => line.source == source);
}

void main() {
  test('goes stopped → starting → running → stopping → stopped', () {
    fakeAsync((async) {
      final h = Harness()..answerRequests();
      expect(h.controller.phase, PlayPhase.stopped);
      unawaited(h.controller.play());
      async.flushMicrotasks();
      expect(h.controller.phase, PlayPhase.starting);
      h.startedFrom('run-scene-save.txt');
      async.flushMicrotasks();
      expect(h.controller.phase, PlayPhase.running);
      unawaited(h.controller.stop());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(h.controller.phase, PlayPhase.stopped);
      expect(h.phases, [
        PlayPhase.starting,
        PlayPhase.running,
        PlayPhase.stopping,
        PlayPhase.stopped,
      ]);
      expect(h.notices, isEmpty, reason: 'a requested stop is no notice');
    });
  });

  test('play() while starting, running or stopping starts nothing more', () {
    fakeAsync((async) {
      final h = Harness()..answerRequests();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.startedFrom('run-scene-save.txt');
      async.flushMicrotasks();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.process.onRequest = null; // app.stop goes unanswered
      unawaited(h.controller.stop());
      async.flushMicrotasks();
      expect(h.controller.phase, PlayPhase.stopping);
      unawaited(h.controller.play());
      async.flushMicrotasks();
      expect(h.starts, 1);
      h.process.exit(0);
      async.elapse(const Duration(seconds: 2));
      expect(h.controller.phase, PlayPhase.stopped);
    });
  });

  test('a build that fails ends stopped and never shows running', () {
    fakeAsync((async) {
      final h = Harness();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.process
        ..queueLines(recorded('build-failure.txt'))
        ..emitAll()
        ..emitStderr(
          "lib/code_marker.dart:5:20: Error: A value of type 'String' can't "
          "be assigned to a variable of type 'int'.",
        )
        ..exit(1);
      async.elapse(const Duration(seconds: 2));
      expect(h.phases, [PlayPhase.starting, PlayPhase.stopped]);
      expect(h.notices, isEmpty);
      final errors = h.console.lines.where(
        (line) => line.severity == ConsoleSeverity.error,
      );
      expect(
        errors.map((line) => line.text),
        contains(contains('lib/code_marker.dart:5:20: Error')),
      );
      expect(
        h.linesFrom(ConsoleSource.pyro).map((line) => line.text),
        contains(contains("couldn't start")),
      );
    });
  });

  test(
    'a game that exits on its own ends stopped with a GameStopped notice',
    () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.startedFrom('exit-without-stop.txt');
        async.flushMicrotasks();
        h.process
          ..emitAll()
          ..exit(0);
        async.elapse(const Duration(seconds: 2));
        expect(h.controller.phase, PlayPhase.stopped);
        expect(h.notices, [isA<GameStopped>()]);
        expect(
          h.linesFrom(ConsoleSource.pyro).map((line) => line.text),
          contains('Game stopped.'),
        );
      });
    },
  );

  test('stop() ends stopped even when app.stop is ignored', () {
    fakeAsync((async) {
      final h = Harness();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.startedFrom('run-scene-save.txt');
      async.flushMicrotasks();
      var stopped = false;
      unawaited(h.controller.stop().then((_) => stopped = true));
      async.elapse(PlayDefaults.stopTimeout);
      expect(h.process.signals, [ProcessSignal.sigterm]);
      async.elapse(const Duration(seconds: 2));
      expect(h.process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
      h.process.exit(-9);
      async.elapse(const Duration(seconds: 2));
      expect(stopped, isTrue);
      expect(h.controller.phase, PlayPhase.stopped);
      expect(h.notices, isEmpty);
    });
  });

  test('a block makes play() start nothing', () {
    fakeAsync((async) {
      final h = Harness(
        block: PlayBlock.of(
          projectError: null,
          hasSdk: true,
          runtimeProblem: null,
          hasMacosFolder: false,
        ),
      );
      unawaited(h.controller.play());
      async.flushMicrotasks();
      expect(h.starts, 0);
      expect(h.controller.phase, PlayPhase.stopped);
      expect(h.phases, isEmpty);
    });
  });

  test("a project flutter can't start goes back to stopped", () {
    fakeAsync((async) {
      final console = ConsoleBuffer();
      final controller = PlayController(
        projectPath: projectPath,
        console: console,
        start: (path, {runLink}) async =>
            throw PlayStartException(path, 'could not start "flutter".'),
      );
      unawaited(controller.play());
      async.flushMicrotasks();
      expect(controller.phase, PlayPhase.stopped);
      expect(
        console.lines.last.text,
        "Can't play $projectPath: could not start \"flutter\".",
      );
      expect(console.lines.last.severity, ConsoleSeverity.error);
    });
  });

  test('lifecycle events are pyro lines, game output game lines', () {
    fakeAsync((async) {
      final h = Harness()..answerRequests();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.startedFrom('run-scene-save.txt');
      async.flushMicrotasks();
      h.process.emitAll();
      async.flushMicrotasks();
      expect(
        h.linesFrom(ConsoleSource.game).map((line) => line.text),
        contains(
          'flutter: [pyro] Scene loaded: assets/scenes/level1.scene.json',
        ),
      );
      final pyro = h.linesFrom(ConsoleSource.pyro).map((line) => line.text);
      expect(pyro, contains(startsWith('Starting the game')));
      expect(pyro, contains(startsWith('The game is running')));
      expect(
        h.linesFrom(ConsoleSource.game).map((line) => line.text),
        isNot(contains(startsWith('[{'))),
        reason: 'daemon messages are parsed, not printed',
      );
      unawaited(h.controller.stop());
      async.elapse(const Duration(seconds: 2));
    });
  });

  test('dispose() stops a running game', () {
    fakeAsync((async) {
      final h = Harness()..answerRequests();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.startedFrom('run-scene-save.txt');
      async.flushMicrotasks();
      unawaited(h.controller.dispose());
      async.elapse(const Duration(seconds: 2));
      expect(
        h.process.requests.map((request) => request['method']),
        contains('app.stop'),
      );
      expect(h.process.exited, isTrue);
    });
  });

  group('the run link (FR-015, research R2)', () {
    test('is made before the game starts and removed once it stopped', () {
      fakeAsync((async) {
        final h = Harness(link: true)..answerRequests();
        unawaited(h.controller.play());
        async.flushMicrotasks();
        final args = h.starter.arguments!;
        final link = args[args.indexOf('--project-root') + 1];
        expect(link, startsWith('/support/run/'));
        expect(h.fs.link(link).existsSync(), isTrue);
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
        expect(h.controller.phase, PlayPhase.stopped);
        expect(h.fs.link(link).existsSync(), isFalse);
        expect(h.fs.directory(h.fs.path.dirname(link)).existsSync(), isFalse);
      });
    });

    test('a link that cannot be made is a Console note, and Play starts', () {
      fakeAsync((async) {
        final h = Harness(link: true, linkFails: true)..answerRequests();
        unawaited(h.controller.play());
        async.flushMicrotasks();
        expect(h.starts, 1);
        expect(h.starter.arguments, isNot(contains('--project-root')));
        final note = h
            .linesFrom(ConsoleSource.pyro)
            .firstWhere((line) => line.severity == ConsoleSeverity.warning);
        expect(note.text, contains('IDE'));
        expect(note.text, contains('Hot-swap'));
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        expect(h.controller.phase, PlayPhase.running);
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
      });
    });

    test('is removed when the game could not start', () {
      fakeAsync((async) {
        final h = Harness(link: true);
        unawaited(h.controller.play());
        async.flushMicrotasks();
        final args = h.starter.arguments!;
        final link = args[args.indexOf('--project-root') + 1];
        h.process
          ..queueLines(recorded('build-failure.txt'))
          ..emitAll()
          ..exit(1);
        async.elapse(const Duration(seconds: 2));
        expect(h.controller.phase, PlayPhase.stopped);
        expect(h.fs.link(link).existsSync(), isFalse);
      });
    });
  });

  group('Attach and Restart game', () {
    test('copyDebuggerAddress is null until the game runs and after', () {
      fakeAsync((async) {
        final h = Harness()..answerRequests();
        expect(h.controller.canAttach, isFalse);
        expect(h.controller.copyDebuggerAddress(), isNull);
        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.process.emitLine(h.debugPort('AbCdEf123456'));
        async.flushMicrotasks();
        expect(h.controller.copyDebuggerAddress(), isNull, reason: 'starting');
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        expect(h.controller.canAttach, isTrue);
        expect(
          h.controller.copyDebuggerAddress(),
          'http://127.0.0.1:5001/AbCdEf123456=/',
        );
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
        expect(h.controller.canAttach, isFalse);
        expect(h.controller.copyDebuggerAddress(), isNull);
      });
    });

    test('the address is in no Console line and no notice', () {
      fakeAsync((async) {
        final h = Harness()..answerRequests();
        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.process
          ..emitLine(h.debugPort('AbCdEf123456'))
          ..emitLine(
            'A Dart VM Service on macOS is available at: '
            'http://127.0.0.1:5001/AbCdEf123456=/',
          )
          ..emitStderr('Lost ws://127.0.0.1:5001/AbCdEf123456=/ws');
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        h.process.emitAll();
        h.controller.copyDebuggerAddress();
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
        for (final line in h.console.lines) {
          expect(line.text, isNot(contains('AbCdEf123456')));
        }
        for (final notice in h.notices) {
          expect('$notice', isNot(contains('AbCdEf123456')));
        }
      });
    });

    test('restartGame is a full restart with its own Console lines', () {
      fakeAsync((async) {
        final h = Harness()..answerRequests();
        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        unawaited(h.controller.restartGame());
        async.elapse(const Duration(seconds: 1));
        final restart = h.process.requests.last;
        expect(restart['method'], 'app.restart');
        expect(restart['params'], containsPair('fullRestart', true));
        final pyro = h.linesFrom(ConsoleSource.pyro).map((l) => l.text);
        expect(pyro, contains('Restarting the game…'));
        expect(pyro, contains(startsWith('Restarted in ')));
        expect(h.controller.phase, PlayPhase.running);
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
      });
    });

    test('restartGame does nothing unless the game runs', () {
      fakeAsync((async) {
        final h = Harness()..answerRequests();
        unawaited(h.controller.restartGame());
        async.flushMicrotasks();
        expect(h.process.requests, isEmpty);
        expect(h.console.lines, isEmpty);
      });
    });

    test('a Hot-swap that stopped working is a notice and a Console line', () {
      fakeAsync((async) {
        final h = Harness(link: true)..answerRequests();
        h.process.onRequest = (request) {
          h.process.emitLine(
            '[{"id":${request['id']},"result":{"code":0,"message":""}}]',
          );
        };
        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        const scene = 'assets/scenes/level1.scene.json';
        final file = h.fs.file('$projectPath/$scene')
          ..createSync(recursive: true)
          ..writeAsStringSync('v1');
        h.process.emitLine('flutter: [pyro] Scene loaded: $scene');
        async.flushMicrotasks();
        for (final content in ['v2', 'v3']) {
          file.writeAsStringSync(content);
          h.changes.add(FileSystemModifyEvent(file.path, false, true));
          async.elapse(const Duration(seconds: 5));
        }
        expect(h.notices.whereType<HotSwapFailed>(), hasLength(1));
        expect(
          h.linesFrom(ConsoleSource.pyro).map((l) => l.text),
          contains(contains('restart the game')),
        );
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
      });
    });
  });

  group('a whole run writes nothing in the project (FR-030)', () {
    bool underSupport(String path) =>
        path.startsWith('/support') || path.startsWith('support');

    Map<String, String> tree(Harness h) => {
      for (final entity
          in h.fs.directory('/').listSync(recursive: true, followLinks: false))
        if (entity is File && !underSupport(entity.path))
          entity.path: entity.readAsStringSync(),
    };

    test('Play, saves, Attach and Stop', () {
      fakeAsync((async) {
        final h = Harness(link: true)..answerRequests();
        const scene = '$projectPath/assets/scenes/level1.scene.json';
        h.fs.file(scene).writeAsStringSync('v1');
        final before = tree(h);
        final directories = {
          for (final e
              in h.fs
                  .directory('/')
                  .listSync(recursive: true, followLinks: false))
            if (e is Directory) e.path,
        };

        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.process.emitLine(h.debugPort('AbCdEf123456'));
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        h.changes.add(FileSystemModifyEvent(scene, false, true));
        async.elapse(const Duration(seconds: 1));
        expect(h.controller.copyDebuggerAddress(), isNotNull);

        final arguments = h.starter.arguments!;
        for (final forbidden in [
          '--disable-service-auth-codes',
          '--disable-dds',
          '--dds-port',
          '--host-vmservice-port',
          '--vm-service-port',
          '--observatory-port',
          '--target',
          '-t',
        ]) {
          expect(arguments, isNot(contains(forbidden)));
        }
        // The one new thing anywhere is the link, under the support folder.
        final created = {
          for (final e
              in h.fs
                  .directory('/')
                  .listSync(recursive: true, followLinks: false))
            if (!directories.contains(e.path) && !before.containsKey(e.path))
              e.path,
        };
        expect(created, isNotEmpty);
        expect(created.every(underSupport), isTrue);

        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
        expect(tree(h), before, reason: 'byte-identical');
        for (final entity
            in h.fs
                .directory('/')
                .listSync(recursive: true, followLinks: false)) {
          expect(entity.path, isNot(contains('.dart_tool/pyro')));
          expect(entity.path, isNot(contains('.vscode')));
        }
        expect(
          h.fs
              .directory('/support')
              .listSync(recursive: true)
              .whereType<Link>(),
          isEmpty,
        );
      });
    });
  });

  group('a whole run never shows its auth code (FR-024, SC-005)', () {
    const code = 'Zq8Lm2Xw9Pk4';

    /// Everything the user or a log could see after a run: the Console, the
    /// notices, the phases and the controller itself.
    Iterable<String> everythingShown(Harness h) => [
      ...h.console.lines.map((line) => line.text),
      ...h.console.lines.map((line) => '$line'),
      ...h.notices.map((notice) => '$notice'),
      ...h.phases.map((phase) => '$phase'),
      '${h.controller}',
    ];

    for (final name in ['run-scene-save.txt', 'ide-attached.txt']) {
      test('replaying $name with a real code in every address', () {
        fakeAsync((async) {
          final h = Harness(link: name == 'ide-attached.txt');
          unawaited(h.controller.play());
          async.flushMicrotasks();
          h.process.queueLines(
            recorded(name).map((line) => line.replaceAll('<auth-code>', code)),
          );
          h.process.emitAll();
          // What the engine prints on its own, and what a tool can print
          // on stderr.
          h.process
            ..emitLine(
              'flutter: Dart VM service on http://127.0.0.1:5001/$code=/',
            )
            ..emitLine(
              'The Dart Tooling Daemon is at ws://127.0.0.1:5000/$code=',
            )
            ..emitStderr('observatory: ws://127.0.0.1:5001/$code=/ws');
          async.flushMicrotasks();
          expect(h.controller.phase, PlayPhase.running);
          expect(h.console.lines, isNotEmpty);

          // Only the explicit action gives the address out.
          expect(h.controller.copyDebuggerAddress(), contains(code));

          unawaited(h.controller.stop());
          async.elapse(const Duration(seconds: 10));
          h.process.exit(0);
          async.elapse(const Duration(seconds: 2));
          expect(h.controller.phase, PlayPhase.stopped);
          expect(h.controller.copyDebuggerAddress(), isNull);

          for (final shown in everythingShown(h)) {
            expect(shown, isNot(contains(code)));
          }
        });
      });
    }

    test('a game that ends on its own leaves no code in its notice', () {
      fakeAsync((async) {
        final h = Harness();
        unawaited(h.controller.play());
        async.flushMicrotasks();
        h.process.emitLine(h.debugPort(code));
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        h.process.exit(1);
        async.elapse(const Duration(seconds: 2));
        expect(h.notices.whereType<GameStopped>(), hasLength(1));
        for (final shown in everythingShown(h)) {
          expect(shown, isNot(contains(code)));
        }
      });
    });
  });

  group('code reloads and changed images while the game runs', () {
    Harness running(FakeAsync async) {
      final h = Harness()..answerRequests();
      unawaited(h.controller.play());
      async.flushMicrotasks();
      h.startedFrom('run-scene-save.txt');
      async.flushMicrotasks();
      expect(h.controller.phase, PlayPhase.running);
      return h;
    }

    test('nothing is watched until the game runs', () {
      fakeAsync((async) {
        final h = Harness()..answerRequests();
        expect(h.codeChanges.hasListener, isFalse);
        unawaited(h.controller.play());
        async.flushMicrotasks();
        expect(h.controller.phase, PlayPhase.starting);
        expect(h.codeChanges.hasListener, isFalse);
        expect(h.imageWatchers, isEmpty);
        h.startedFrom('run-scene-save.txt');
        async.flushMicrotasks();
        expect(h.codeChanges.hasListener, isTrue);
        expect(h.imageWatchers.single.starts, 1);
      });
    });

    test('a Dart save reloads the code, without the Scene re-point', () {
      fakeAsync((async) {
        final h = running(async);
        h.saveCode('lib/main.dart');
        async.elapse(const Duration(milliseconds: 150));
        final restarts = h.requestsOf('app.restart');
        expect(restarts, hasLength(1));
        expect((restarts.single['params']! as Map)['fullRestart'], false);
        expect(h.vm.log, isEmpty, reason: 'no listViews, no re-point');
        expect(
          h.linesFrom(ConsoleSource.pyro).map((l) => l.text),
          contains('Reloading the game…'),
        );
      });
    });

    test('the reload waits for the generator through its state', () {
      fakeAsync((async) {
        final h = running(async);
        h.generator = const GeneratorState(GeneratorStatus.generating);
        h.saveCode('lib/main.dart');
        async.elapse(const Duration(seconds: 5));
        expect(h.requestsOf('app.restart'), isEmpty);
        h.generator = const GeneratorState(GeneratorStatus.upToDate);
        h.generatorStates.add(h.generator);
        async.flushMicrotasks();
        expect(h.requestsOf('app.restart'), hasLength(1));
      });
    });

    test('a save the generator reports as broken is held, in the Console', () {
      fakeAsync((async) {
        final h = running(async);
        h.generator = const GeneratorState(
          GeneratorStatus.error,
          file: 'lib/behaviors/spin.dart',
          message: 'Expected an identifier.',
        );
        h.saveCode('lib/behaviors/spin.dart');
        async.elapse(const Duration(seconds: 10));
        expect(h.requestsOf('app.restart'), isEmpty);
        // The note reaches the Console through the watcher's onNote in the app;
        // here the held save is what matters, and the fix reloads it once.
        h.generator = const GeneratorState(GeneratorStatus.upToDate);
        h.generatorStates.add(h.generator);
        async.flushMicrotasks();
        expect(h.requestsOf('app.restart'), hasLength(1));
      });
    });

    test('a save after the stop reloads nothing', () {
      fakeAsync((async) {
        final h = running(async);
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
        expect(h.controller.phase, PlayPhase.stopped);
        expect(h.codeChanges.hasListener, isFalse);
        final before = h.requestsOf('app.restart').length;
        h.saveCode('lib/main.dart');
        async.elapse(const Duration(seconds: 5));
        expect(h.requestsOf('app.restart'), hasLength(before));
        expect(h.imageWatchers.single.closed, isTrue);
      });
    });

    test('the game ending on its own closes the watchers', () {
      fakeAsync((async) {
        final h = running(async);
        h.process.exit(1);
        async.elapse(const Duration(seconds: 2));
        expect(h.codeChanges.hasListener, isFalse);
        expect(h.imageWatchers.single.closed, isTrue);
      });
    });

    test('disposing the controller (the project closes) stops the game', () {
      fakeAsync((async) {
        final h = running(async);
        unawaited(h.controller.dispose());
        async.elapse(const Duration(seconds: 2));
        expect(h.controller.phase, PlayPhase.stopped);
        expect(
          h.process.requests.map((r) => r['method']),
          contains('app.stop'),
        );
        expect(h.codeChanges.hasListener, isFalse);
        expect(h.imageWatchers.single.closed, isTrue);
      });
    });

    test('a changed image is a notice and a Console line', () {
      fakeAsync((async) {
        final h = running(async);
        h.imageWatchers.single.onChanged!({'assets/images/ship.png'});
        async.flushMicrotasks();
        final notice = h.notices.whereType<ImageChanged>().single;
        expect(notice.paths, {'assets/images/ship.png'});
        expect('$notice', 'Image changed');
        expect(
          h.linesFrom(ConsoleSource.pyro).map((l) => l.text),
          contains(contains('assets/images/ship.png')),
        );
        // Nothing restarts by itself.
        expect(h.requestsOf('app.restart'), isEmpty);
      });
    });

    test('a second change adds to the notice, and a restart clears it', () {
      fakeAsync((async) {
        final h = running(async);
        final images = h.imageWatchers.single;
        images.onChanged!({'assets/images/ship.png'});
        images.onChanged!({'assets/images/glow.png'});
        async.flushMicrotasks();
        expect(h.notices.whereType<ImageChanged>().last.paths, {
          'assets/images/ship.png',
          'assets/images/glow.png',
        });
        unawaited(h.controller.restartGame());
        async.elapse(const Duration(seconds: 1));
        expect(images.clears, 1);
        expect(
          (h.requestsOf('app.restart').single['params']! as Map)['fullRestart'],
          true,
        );
        images.onChanged!({'assets/images/bg.png'});
        async.flushMicrotasks();
        expect(h.notices.whereType<ImageChanged>().last.paths, {
          'assets/images/bg.png',
        });
      });
    });

    test('an image change while no game runs is ignored', () {
      fakeAsync((async) {
        final h = running(async);
        final images = h.imageWatchers.single;
        unawaited(h.controller.stop());
        async.elapse(const Duration(seconds: 2));
        images.onChanged!({'assets/images/ship.png'});
        async.flushMicrotasks();
        expect(h.notices.whereType<ImageChanged>(), isEmpty);
      });
    });
  });
}
