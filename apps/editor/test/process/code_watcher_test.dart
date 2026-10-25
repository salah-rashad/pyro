import 'dart:async';
import 'dart:io'
    show FileSystemEvent, FileSystemModifyEvent, FileSystemMoveEvent;

import 'package:fake_async/fake_async.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

import 'fake_process.dart';

const lib = '$projectPath/lib';

void main() {
  // A broadcast stream the test drives; nothing to release.
  // ignore: close_sinks
  late StreamController<FileSystemEvent> changes;
  // ignore: close_sinks
  late StreamController<GeneratorState> states;
  late GeneratorState state;
  late int reloads;

  setUp(() {
    changes = StreamController<FileSystemEvent>.broadcast();
    states = StreamController<GeneratorState>.broadcast();
    state = const GeneratorState(GeneratorStatus.upToDate);
    reloads = 0;
  });

  MemoryFileSystem withLib() =>
      projectFileSystem()..directory(lib).createSync(recursive: true);

  CodeWatcher watcher() => CodeWatcher(
    fileSystem: withLib(),
    projectPath: projectPath,
    watch: (_) => changes.stream,
    generatorState: () => state,
    generatorStates: states.stream,
    onReload: () => reloads++,
  )..start();

  void save(String path) =>
      changes.add(FileSystemModifyEvent(path, false, true));

  void generator(GeneratorStatus status) {
    state = GeneratorState(status);
    states.add(state);
  }

  void elapse(FakeAsync async, Duration duration) {
    async.elapse(duration);
    async.flushMicrotasks();
  }

  group('with the generator idle', () {
    test('a batch of saves asks for one reload after 150 ms of quiet', () {
      fakeAsync((async) {
        watcher();
        save('$lib/main.dart');
        elapse(async, const Duration(milliseconds: 100));
        save('$lib/game/ship.dart');
        elapse(async, const Duration(milliseconds: 100));
        save('$lib/main.dart');
        elapse(async, const Duration(milliseconds: 149));
        expect(reloads, 0);
        elapse(async, const Duration(milliseconds: 1));
        expect(reloads, 1);
        elapse(async, const Duration(seconds: 10));
        expect(reloads, 1);
      });
    });

    for (final status in [
      GeneratorStatus.upToDate,
      GeneratorStatus.stopped,
      GeneratorStatus.notSetUp,
      GeneratorStatus.error,
    ]) {
      test('${status.name} reloads at once', () {
        fakeAsync((async) {
          state = GeneratorState(status);
          watcher();
          save('$lib/main.dart');
          elapse(async, const Duration(milliseconds: 150));
          expect(reloads, 1);
        });
      });
    }

    test('a move onto a Dart file counts, other files do not', () {
      fakeAsync((async) {
        watcher();
        for (final path in [
          '$projectPath/assets/scenes/a.scene.json',
          '$projectPath/pubspec.yaml',
          '$projectPath/test/a_test.dart',
          '$lib/notes.txt',
          '$lib/main.dart.swp',
        ]) {
          save(path);
        }
        changes.add(FileSystemModifyEvent(lib, true, true));
        elapse(async, const Duration(seconds: 5));
        expect(reloads, 0);
        changes.add(FileSystemMoveEvent('$lib/.tmp', false, '$lib/main.dart'));
        elapse(async, const Duration(milliseconds: 150));
        expect(reloads, 1);
      });
    });
  });

  group('while the generator generates', () {
    for (final busy in [GeneratorStatus.generating, GeneratorStatus.starting]) {
      for (final done in [GeneratorStatus.upToDate, GeneratorStatus.error]) {
        test('${busy.name}: waits for ${done.name}', () {
          fakeAsync((async) {
            state = GeneratorState(busy);
            watcher();
            save('$lib/main.dart');
            elapse(async, const Duration(seconds: 30));
            expect(reloads, 0);
            generator(done);
            elapse(async, Duration.zero);
            expect(reloads, 1);
          });
        });
      }
    }

    test('more saves while waiting share the one reload', () {
      fakeAsync((async) {
        state = const GeneratorState(GeneratorStatus.generating);
        watcher();
        save('$lib/main.dart');
        elapse(async, const Duration(seconds: 1));
        save('$lib/other.dart');
        elapse(async, const Duration(seconds: 1));
        generator(GeneratorStatus.upToDate);
        elapse(async, const Duration(seconds: 5));
        expect(reloads, 1);
      });
    });

    test('a state change without a save reloads nothing', () {
      fakeAsync((async) {
        watcher();
        generator(GeneratorStatus.generating);
        generator(GeneratorStatus.upToDate);
        elapse(async, const Duration(seconds: 5));
        expect(reloads, 0);
      });
    });

    test('the build ending in stopped does not leave the save waiting', () {
      fakeAsync((async) {
        state = const GeneratorState(GeneratorStatus.generating);
        watcher();
        save('$lib/main.dart');
        elapse(async, const Duration(seconds: 1));
        generator(GeneratorStatus.stopped);
        elapse(async, Duration.zero);
        expect(reloads, 1);
      });
    });
  });

  group('with an External build_runner (FR-012)', () {
    setUp(() => state = const GeneratorState(GeneratorStatus.external));

    test('reloads 2 s after the save when nothing is regenerated', () {
      fakeAsync((async) {
        watcher();
        save('$lib/main.dart');
        elapse(async, const Duration(milliseconds: 1999));
        expect(reloads, 0);
        elapse(async, const Duration(milliseconds: 1));
        expect(reloads, 1);
      });
    });

    for (final generated in ['pyro.g.dart', 'pyro.manifest.json']) {
      test('waits until $generated has been quiet for 2 s', () {
        fakeAsync((async) {
          watcher();
          save('$lib/main.dart');
          elapse(async, const Duration(milliseconds: 1500));
          save('$lib/$generated');
          elapse(async, const Duration(milliseconds: 1999));
          expect(reloads, 0);
          save('$lib/$generated');
          elapse(async, const Duration(milliseconds: 1999));
          expect(reloads, 0);
          elapse(async, const Duration(milliseconds: 1));
          expect(reloads, 1);
        });
      });
    }

    test('the manifest alone, with no save of Dart code, reloads nothing', () {
      fakeAsync((async) {
        watcher();
        save('$lib/pyro.manifest.json');
        elapse(async, const Duration(seconds: 10));
        expect(reloads, 0);
      });
    });

    test('the generator turning idle meanwhile reloads at once', () {
      fakeAsync((async) {
        watcher();
        save('$lib/main.dart');
        elapse(async, const Duration(milliseconds: 500));
        generator(GeneratorStatus.upToDate);
        elapse(async, Duration.zero);
        expect(reloads, 1);
        elapse(async, const Duration(seconds: 5));
        expect(reloads, 1);
      });
    });
  });

  group('while no game runs', () {
    test('nothing is watched before start() and after close()', () {
      fakeAsync((async) {
        final unstarted = CodeWatcher(
          fileSystem: withLib(),
          projectPath: projectPath,
          watch: (_) => changes.stream,
          generatorState: () => state,
          generatorStates: states.stream,
          onReload: () => reloads++,
        );
        expect(changes.hasListener, isFalse);
        unstarted.start();
        expect(changes.hasListener, isTrue);
        save('$lib/main.dart');
        elapse(async, const Duration(milliseconds: 100));
        unstarted.close();
        elapse(async, const Duration(seconds: 10));
        expect(reloads, 0, reason: 'a closed watcher drops its batch');
        expect(changes.hasListener, isFalse);
        expect(states.hasListener, isFalse);
      });
    });

    test('a reload waiting for the generator is dropped by close()', () {
      fakeAsync((async) {
        state = const GeneratorState(GeneratorStatus.generating);
        final w = watcher();
        save('$lib/main.dart');
        elapse(async, const Duration(seconds: 1));
        w.close();
        generator(GeneratorStatus.upToDate);
        elapse(async, const Duration(seconds: 5));
        expect(reloads, 0);
      });
    });

    test('a project without lib/ is noted once and watches nothing', () {
      fakeAsync((async) {
        final fs = MemoryFileSystem();
        fs.directory(projectPath).createSync(recursive: true);
        final notes = <String>[];
        CodeWatcher(
          fileSystem: fs,
          projectPath: projectPath,
          watch: (_) => changes.stream,
          generatorState: () => state,
          generatorStates: states.stream,
          onReload: () => reloads++,
          onNote: notes.add,
        ).start();
        expect(changes.hasListener, isFalse);
        expect(notes, hasLength(1));
        expect(notes.single, contains('lib/'));
      });
    });
  });
}
