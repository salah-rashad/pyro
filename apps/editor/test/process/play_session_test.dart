import 'dart:async';
import 'dart:io' show FileSystemEvent, FileSystemModifyEvent, ProcessSignal;

import 'package:fake_async/fake_async.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

import 'fake_process.dart';
import 'fake_vm.dart';

/// The known fake auth code in every transcript (research R5).
const authCode = 'AbCdEf123456';

/// The app id in the recorded transcripts (quickstart §5.10).
const appId = '00808424-aefd-42c9-8db9-e2f7eb776262';

const scene = '$projectPath/assets/scenes/level1.scene.json';

/// A Play session on a [FakeProcess], a memory file system and a watcher the
/// test drives, all under [FakeAsync].
final class Harness {
  Harness(this.async, {MemoryFileSystem? fileSystem})
    : fs = fileSystem ?? projectFileSystem();

  final FakeAsync async;
  final MemoryFileSystem fs;
  final process = FakeProcess();
  late final starter = FakeStarter(process);
  final vm = FakeVm();
  RunLink? runLink;
  // Closed with the test's zone; nothing to release.
  // ignore: close_sinks
  final changes = StreamController<FileSystemEvent>.broadcast();
  final events = <PlayEvent>[];
  late final PlaySession session;
  var closed = false;

  /// Spawns the session and listens to it; with [link], through a run link.
  void start({bool link = false}) {
    if (link) {
      unawaited(
        RunLink.create(
          projectPath,
          supportDir: '/support',
          fileSystem: fs,
        ).then((l) => runLink = l),
      );
      async.flushMicrotasks();
    }
    unawaited(
      PlayClient(
        startProcess: starter.call,
        fileSystem: fs,
        watchDirectory: (_) => changes.stream,
        vmConnect: vm.connect,
      ).start(projectPath, runLink: runLink).then((s) {
        session = s;
        s.events.listen(events.add, onDone: () => closed = true);
      }),
    );
    async.flushMicrotasks();
  }

  /// Spawns the session and replays `start.txt` to `app.started`.
  void startGame({bool link = false}) {
    start(link: link);
    process.play('start.txt');
    async.flushMicrotasks();
  }

  /// Answers every `app.restart` with [code] after [delay].
  void answerReloads({
    int code = 0,
    String message = '',
    Duration delay = Duration.zero,
  }) {
    process.onRequest = (request) {
      if (request['method'] != 'app.restart') return;
      vm.log.add('app.restart');
      Timer(delay, () {
        process.emitLine(
          '[{"id":${request['id']},"result":{"code":$code,"message":"$message"}}]',
        );
      });
    };
  }

  /// A save of [path], as FSEvents reports a modify.
  void save([String path = scene]) =>
      changes.add(FileSystemModifyEvent(path, false, true));

  List<Map<String, Object?>> get restarts => [
    for (final r in process.requests)
      if (r['method'] == 'app.restart') r,
  ];

  List<T> only<T extends PlayEvent>() => events.whereType<T>().toList();
}

void main() {
  group('lifecycle', () {
    test('reports the start in order, with no auth code anywhere', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();

        expect(
          h.events.first,
          isA<PlayStarting>()
              .having(
                (e) => e.command,
                'command',
                'flutter run --machine -d macos --debug',
              )
              .having((e) => e.projectPath, 'projectPath', projectPath),
        );
        expect(h.events.map((e) => e.runtimeType).toSet(), {
          PlayStarting,
          PlayOutput,
          PlayDebuggerAvailable,
          PlayStarted,
        });
        final started = h.events.indexWhere((e) => e is PlayStarted);
        expect(
          h.events.indexWhere((e) => e is PlayDebuggerAvailable),
          lessThan(started),
        );
        expect(h.only<PlayStarted>().single.appId, appId);
        expect(
          h.events.last,
          isA<PlayOutput>()
              .having((e) => e.source, 'source', PlayOutputSource.game)
              .having((e) => e.line, 'line', contains('Scene loaded')),
        );
        expect(
          h.only<PlayOutput>().map((e) => e.line),
          contains('Building macOS application...'),
        );
        for (final event in h.events) {
          expect('$event', isNot(contains(authCode)));
          expect('$event', isNot(contains('devtools')));
          expect('$event', isNot(contains('55817')), reason: 'app.dtd');
          expect('$event', isNot(contains('ws://')), reason: 'wsUri');
        }
        expect(h.session.state, PlayState.running);
        expect(h.session.appId, appId);
      });
    });

    test('is starting until app.started', () {
      fakeAsync((async) {
        final h = Harness(async)..start();
        h.process
          ..queue('start.txt')
          ..emitUntil((line) => line.contains('app.debugPort'));
        async.flushMicrotasks();
        expect(h.session.state, PlayState.starting);
        expect(h.events, isNot(contains(isA<PlayStarted>())));
      });
    });

    test('reports stderr lines', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        h.process.emitStderr('Oops at ws://127.0.0.1:1/$authCode=/ws');
        async.flushMicrotasks();
        expect(
          h.events.last,
          isA<PlayOutput>()
              .having((e) => e.source, 'source', PlayOutputSource.stderr)
              .having(
                (e) => e.line,
                'line',
                'Oops at ws://127.0.0.1:1/<auth-code>=/ws',
              ),
        );
      });
    });

    test('reports an exit it did not ask for and closes', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        h.process.exit(0);
        async.elapse(const Duration(seconds: 2));
        expect(
          h.events.last,
          isA<PlayStopped>()
              .having((e) => e.exitCode, 'exitCode', 0)
              .having((e) => e.requested, 'requested', false),
        );
        expect(h.events, isNot(contains(isA<PlayFailed>())));
        expect(h.closed, isTrue);
        expect(h.session.state, PlayState.stopped);
      });
    });
  });

  group('reload', () {
    test('a Scene save sends one app.restart after the quiet period', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        h.process.onRequest = (_) => h.process.play('reload_ok.txt');
        h.save();
        async.elapse(const Duration(milliseconds: 149));
        expect(h.restarts, isEmpty);
        async.elapse(const Duration(milliseconds: 1));

        expect(h.restarts.single, {
          'id': 1,
          'method': 'app.restart',
          'params': {
            'appId': appId,
            'fullRestart': false,
            'pause': false,
            'reason': 'pyro',
          },
        });
        expect(h.only<PlayReloading>().single.paths, [
          'assets/scenes/level1.scene.json',
        ]);
        expect(h.only<PlayReloaded>(), hasLength(1));
        expect(h.session.state, PlayState.running);
      });
    });

    test('is reloading while the request is in flight', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads(delay: const Duration(milliseconds: 60));
        unawaited(h.session.reload());
        async.flushMicrotasks();
        expect(h.session.state, PlayState.reloading);
        async.elapse(const Duration(milliseconds: 60));
        expect(h.session.state, PlayState.running);
      });
    });

    test('a failed reload reports the daemon\'s message', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        h.process.onRequest = (_) => h.process.play('reload_failed.txt');
        ReloadResult? result;
        unawaited(h.session.reload().then((r) => result = r));
        async.flushMicrotasks();

        expect(result!.ok, isFalse);
        expect(
          h.only<PlayReloadFailed>().single,
          isA<PlayReloadFailed>()
              .having(
                (e) => e.message,
                'message',
                // The compile error itself comes on stderr, not here.
                'DevFS synchronization failed',
              )
              .having((e) => e.code, 'code', 1),
        );
        expect(h.session.state, PlayState.running);
      });
    });

    test('an error response is a failed reload', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        h.process.onRequest = (request) => h.process.emitLine(
          '[{"id":${request['id']},"error":"Unknown appId"}]',
        );
        unawaited(h.session.reload());
        async.flushMicrotasks();
        expect(h.only<PlayReloadFailed>().single.message, 'Unknown appId');
      });
    });

    test('reload() before the game started is a StateError', () {
      fakeAsync((async) {
        final h = Harness(async)..start();
        expect(h.session.reload, throwsStateError);
      });
    });

    test('never sends two reloads at once, and queues at most one', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads(delay: const Duration(milliseconds: 500));
        h.save();
        async.elapse(const Duration(milliseconds: 150));
        expect(h.restarts, hasLength(1));

        // Three more settled batches while the first is in flight.
        for (final name in ['a', 'b', 'c']) {
          h.save('$projectPath/assets/scenes/$name.scene.json');
          async.elapse(const Duration(milliseconds: 160));
        }
        expect(h.restarts, hasLength(1));

        async.elapse(const Duration(milliseconds: 100));
        expect(h.restarts, hasLength(2));
        expect(h.only<PlayReloading>().last.paths, [
          'assets/scenes/a.scene.json',
          'assets/scenes/b.scene.json',
          'assets/scenes/c.scene.json',
        ]);
        async.elapse(const Duration(seconds: 1));
        expect(h.restarts, hasLength(2));
        expect(h.only<PlayReloaded>(), hasLength(2));
      });
    });

    test('a burst of ten saves 100 ms apart is one reload (SC-006)', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads(delay: const Duration(milliseconds: 60));
        for (var i = 0; i < 10; i++) {
          h.save();
          async.elapse(const Duration(milliseconds: 100));
        }
        async.elapse(const Duration(seconds: 2));
        expect(h.restarts, hasLength(1));
      });
    });

    test('a manual reload waits for the one in flight', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads(delay: const Duration(milliseconds: 200));
        h.save();
        async.elapse(const Duration(milliseconds: 150));
        ReloadResult? manual;
        unawaited(h.session.reload().then((r) => manual = r));
        async.flushMicrotasks();
        expect(h.restarts, hasLength(1));

        async.elapse(const Duration(milliseconds: 200));
        expect(h.restarts, hasLength(2));
        expect(h.only<PlayReloading>().last.paths, isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        expect(manual!.ok, isTrue);
      });
    });

    test('a save with the same bytes still reloads; the Runtime decides', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads();
        h.changes.add(FileSystemModifyEvent(scene, false, false));
        async.elapse(const Duration(milliseconds: 150));
        expect(h.restarts, hasLength(1));
      });
    });

    test('a save while starting is one reload once the game has started', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..start()
          ..answerReloads();
        h.save();
        h.save('$projectPath/assets/scenes/other.scene.json');
        async.elapse(const Duration(milliseconds: 300));
        expect(h.restarts, isEmpty, reason: 'no reload before app.started');
        h.process.play('start.txt');
        async.flushMicrotasks();
        expect(h.restarts, hasLength(1));
        expect(h.only<PlayReloading>().single.paths, [
          'assets/scenes/level1.scene.json',
          'assets/scenes/other.scene.json',
        ]);
        async.elapse(const Duration(seconds: 1));
        expect(h.restarts, hasLength(1));
      });
    });

    test('no save while starting, no reload at the start', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        async.elapse(const Duration(seconds: 1));
        expect(h.restarts, isEmpty);
      });
    });
  });

  group('stop', () {
    test('sends app.stop and needs no signal when the game exits', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        h.process.onRequest = (request) {
          if (request['method'] != 'app.stop') return;
          h.process.play('stop.txt');
          h.process.exit(0);
        };
        var done = false;
        unawaited(h.session.stop().then((_) => done = true));
        async.elapse(const Duration(seconds: 2));

        expect(h.process.requests.single, {
          'id': 1,
          'method': 'app.stop',
          'params': {'appId': appId},
        });
        expect(h.process.signals, isEmpty);
        expect(done, isTrue);
        expect(
          h.events.last,
          isA<PlayStopped>().having((e) => e.requested, 'requested', true),
        );
      });
    });

    test('escalates to SIGTERM after 5 s and SIGKILL 2 s later', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        unawaited(h.session.stop());
        async.elapse(const Duration(milliseconds: 4999));
        expect(h.process.signals, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.process.signals, [ProcessSignal.sigterm]);
        async.elapse(const Duration(seconds: 2));
        expect(h.process.signals, [
          ProcessSignal.sigterm,
          ProcessSignal.sigkill,
        ]);
        h.process.exit(-9);
        async.elapse(const Duration(seconds: 2));
        expect(h.events.last, isA<PlayStopped>());
      });
    });

    test('stop() twice sends one app.stop; after the exit it does nothing', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        unawaited(h.session.stop());
        unawaited(h.session.stop());
        async.flushMicrotasks();
        expect(h.process.requests, hasLength(1));
        h.process.exit(0);
        async.elapse(const Duration(seconds: 2));
        unawaited(h.session.stop());
        async.elapse(const Duration(seconds: 10));
        expect(h.process.requests, hasLength(1));
        expect(h.process.signals, isEmpty);
      });
    });

    test('stopping while still building signals the tool directly', () {
      fakeAsync((async) {
        final h = Harness(async)..start();
        unawaited(h.session.stop());
        async.flushMicrotasks();
        expect(h.process.requests, isEmpty);
        expect(h.process.signals, [ProcessSignal.sigterm]);
        h.process.exit(-15);
        async.elapse(const Duration(seconds: 2));
        expect(h.events, isNot(contains(isA<PlayFailed>())));
        expect(
          h.events.last,
          isA<PlayStopped>().having((e) => e.requested, 'requested', true),
        );
      });
    });

    test('a queued reload fails, not restarts, when a stop was requested', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads(delay: const Duration(milliseconds: 200));
        h.save();
        async.elapse(const Duration(milliseconds: 160));
        expect(h.restarts, hasLength(1));

        Object? error;
        unawaited(
          h.session.reload().catchError((Object e) {
            error = e;
            return const ReloadResult(ok: false, elapsed: Duration.zero);
          }),
        );
        async.flushMicrotasks();
        expect(h.restarts, hasLength(1), reason: 'queued behind the first');

        unawaited(h.session.stop());
        async.flushMicrotasks();
        expect(h.session.state, PlayState.stopping);

        async.elapse(const Duration(milliseconds: 200));
        expect(
          h.restarts,
          hasLength(1),
          reason: 'no app.restart for an app being stopped',
        );
        expect(h.session.state, PlayState.stopping);
        expect(h.only<PlayReloading>(), hasLength(1));
        expect(
          error,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('stopped'),
          ),
        );
      });
    });

    test('a crash fails the reload in flight and closes the watcher', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame();
        Object? error;
        unawaited(
          h.session.reload().catchError((Object e) {
            error = e;
            return const ReloadResult(ok: false, elapsed: Duration.zero);
          }),
        );
        async.flushMicrotasks();
        h.process
          ..play('crash.txt')
          ..exit(1);
        async.elapse(const Duration(seconds: 2));

        expect(
          error,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(projectPath),
          ),
        );
        expect(
          h.events.last,
          isA<PlayStopped>()
              .having((e) => e.exitCode, 'exitCode', 1)
              .having((e) => e.requested, 'requested', false),
        );
        expect(h.changes.hasListener, isFalse);
      });
    });
  });

  group('with a run link (spec 007)', () {
    /// The game's DevFS folder, as `app.debugPort` reports it.
    final baseUri = RegExp(
      r'"baseUri":"([^"]*)"',
    ).firstMatch(transcript('start.txt').join('\n'))!.group(1)!;
    final assets = '${baseUri}build/flutter_assets';
    const sceneAsset = 'assets/scenes/level1.scene.json';

    test('spawns with --project-root, in the real project, with no target', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame(link: true);
        expect(h.starter.arguments, [
          'run',
          '--machine',
          '-d',
          'macos',
          '--debug',
          '--project-root',
          h.runLink!.path,
        ]);
        expect(h.starter.workingDirectory, projectPath);
        expect(h.starter.arguments, isNot(contains('--target')));
        expect(h.starter.arguments, isNot(contains('-t')));
        expect(
          (h.events.first as PlayStarting).command,
          endsWith('--project-root ${h.runLink!.path}'),
        );
      });
    });

    test(
      'without a run link the spawn is spec 005\'s and nothing repoints',
      () {
        fakeAsync((async) {
          final h = Harness(async)
            ..startGame()
            ..answerReloads();
          expect(h.starter.arguments, [
            'run',
            '--machine',
            '-d',
            'macos',
            '--debug',
          ]);
          h.save();
          async.elapse(const Duration(milliseconds: 150));
          expect(h.vm.log, ['app.restart']);
          expect(h.vm.connects, 0);
        });
      },
    );

    test('a Scene reload repoints the assets first', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame(link: true)
          ..answerReloads();
        h.save();
        async.elapse(const Duration(milliseconds: 150));
        expect(h.vm.log, [
          'listViews',
          'setAssetBundlePath $assets',
          'app.restart',
        ]);
        expect(h.only<PlayReloading>(), hasLength(1));
        expect(h.only<PlayReloaded>(), hasLength(1));
      });
    });

    test('a rejected repoint restarts, repoints again, evicts, restarts', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame(link: true)
          ..answerReloads();
        h.vm.rejectSetPath = 1;
        h.save();
        async.elapse(const Duration(milliseconds: 150));
        expect(h.vm.log, [
          'listViews',
          'setAssetBundlePath $assets',
          'app.restart',
          'listViews',
          'setAssetBundlePath $assets',
          'evict $sceneAsset',
          'app.restart',
        ]);
        expect(h.only<PlayReloading>(), hasLength(1), reason: 'one pair');
        expect(h.only<PlayReloaded>(), hasLength(1));
        expect(h.only<PlayReloadFailed>(), isEmpty);
        expect(h.session.state, PlayState.running);
      });
    });

    test('a code-only reload sends app.restart alone', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame(link: true)
          ..answerReloads();
        unawaited(h.session.reload());
        async.flushMicrotasks();
        expect(h.vm.log, ['app.restart']);
        expect(h.vm.connects, 0, reason: 'no connection for code');
      });
    });

    test('reloads run one at a time with one queued', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame(link: true)
          ..answerReloads(delay: const Duration(milliseconds: 500));
        h.save();
        async.elapse(const Duration(milliseconds: 160));
        expect(h.vm.log.where((e) => e == 'app.restart'), hasLength(1));
        // Two more saves while the first is in flight: one queued reload.
        h.save();
        async.elapse(const Duration(milliseconds: 160));
        h.save();
        async.elapse(const Duration(milliseconds: 160));
        expect(h.vm.log.where((e) => e == 'app.restart'), hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(h.vm.log, [
          'listViews',
          'setAssetBundlePath $assets',
          'app.restart',
          'listViews',
          'setAssetBundlePath $assets',
          'app.restart',
        ]);
        expect(h.only<PlayReloaded>(), hasLength(2));
      });
    });

    test('restart() is a full restart that is not repointed', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame(link: true)
          ..answerReloads();
        unawaited(h.session.restart());
        async.elapse(const Duration(milliseconds: 1));
        expect(h.restarts.single['params'], containsPair('fullRestart', true));
        expect(h.vm.log, ['app.restart']);
        expect(h.only<PlayReloading>().single.paths, isEmpty);
        expect(h.only<PlayReloaded>(), hasLength(1));
        expect(h.session.state, PlayState.running);
      });
    });

    test('device events change nothing and print nothing', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame(link: true);
        final before = h.events.length;
        for (final name in [
          'device.added',
          'device.removed',
          'device.changed',
        ]) {
          h.process.emitLine('[{"event":"$name","params":{"id":"macos"}}]');
        }
        async.flushMicrotasks();
        expect(h.events, hasLength(before));
        expect(h.session.state, PlayState.running);
      });
    });

    test('a hot restart seen from an IDE is not a stop', () {
      fakeAsync((async) {
        final h = Harness(async)..startGame(link: true);
        final before = h.events.length;
        h.process.emitLine(
          '[{"event":"app.progress","params":{"appId":"$appId",'
          '"id":"hot.restart","progressId":"hot.restart","finished":true}}]',
        );
        async.flushMicrotasks();
        expect(h.events.whereType<PlayStopped>(), isEmpty);
        expect(h.events.whereType<PlayFailed>(), isEmpty);
        expect(h.session.state, PlayState.running);
        expect(h.events.length, before);
      });
    });
  });

  group('the debugger address (FR-024, FR-028)', () {
    String debugPort(String code, {int port = 5001}) =>
        '[{"event":"app.debugPort","params":{"appId":"$appId","port":$port,'
        '"wsUri":"ws://127.0.0.1:$port/$code=/ws","baseUri":"file:///p/"}}]';

    test('is null until the game reports it, and again after the end', () {
      fakeAsync((async) {
        final h = Harness(async)..start();
        expect(h.session.debuggerAddress, isNull);
        h.process.emitLine(debugPort(authCode));
        async.flushMicrotasks();
        expect(h.session.debuggerAddress, 'http://127.0.0.1:5001/$authCode=/');
        h.process.exit(0);
        async.elapse(const Duration(seconds: 2));
        expect(h.session.debuggerAddress, isNull);
      });
    });

    test('is the run\'s own: a second session gets its own code', () {
      fakeAsync((async) {
        final first = Harness(async)..start();
        first.process.emitLine(debugPort('FirstRunCode1'));
        async.flushMicrotasks();
        first.process.exit(0);
        async.elapse(const Duration(seconds: 2));
        final second = Harness(async)..start();
        second.process.emitLine(debugPort('SecondRunCode', port: 5002));
        async.flushMicrotasks();
        expect(second.session.debuggerAddress, contains('SecondRunCode'));
        expect(
          second.session.debuggerAddress,
          isNot(contains('FirstRunCode1')),
        );
      });
    });

    test('is in no event, string, error or output (SC-005)', () {
      fakeAsync((async) {
        final h = Harness(async)..start();
        h.process
          ..emitLine(debugPort(authCode))
          ..emitLine(
            'Debug service listening on ws://127.0.0.1:5001/$authCode=/ws',
          )
          ..emitStderr('Lost ws://127.0.0.1:5001/$authCode=/ws');
        h.process.queue('start.txt');
        h.process.emitAll();
        async.flushMicrotasks();
        h
          ..answerReloads()
          ..save();
        async.elapse(const Duration(seconds: 1));
        h.process.exit(1);
        async.elapse(const Duration(seconds: 2));
        for (final event in h.events) {
          expect('$event', isNot(contains(authCode)));
          if (event is PlayOutput) {
            expect(event.line, isNot(contains(authCode)));
          }
        }
        expect('${h.session}', isNot(contains(authCode)));
      });
    });

    test('the repoint connects with the address it was given', () {
      fakeAsync((async) {
        final h = Harness(async)..start(link: true);
        h.process
          ..emitLine(debugPort(authCode))
          ..queue('start.txt')
          ..emitUntil((l) => l.contains('app.started'));
        async.flushMicrotasks();
        h
          ..answerReloads()
          ..save();
        async.elapse(const Duration(milliseconds: 150));
        expect(h.vm.connectedTo, 'ws://127.0.0.1:5001/$authCode=/ws');
        h.process.exit(0);
        async.elapse(const Duration(seconds: 2));
        expect(h.vm.closed, isTrue);
      });
    });
  });

  group('a Hot-swap that stopped working (FR-011)', () {
    const sceneAsset = 'assets/scenes/level1.scene.json';

    /// Saves [content] to the Scene and lets the reload finish.
    void save(Harness h, FakeAsync async, String content, {String? report}) {
      h.fs.file(scene).writeAsStringSync(content);
      h.save();
      async.elapse(const Duration(milliseconds: 200));
      if (report != null) {
        h.process.emitLine('flutter: [pyro] Scene $report: $sceneAsset');
      }
      async.elapse(const Duration(seconds: 4));
    }

    Harness announced(FakeAsync async) {
      final h = Harness(async)
        ..startGame()
        ..answerReloads();
      h.fs.file(scene).writeAsStringSync('v1');
      h.process.emitLine('flutter: [pyro] Scene loaded: $sceneAsset');
      async.flushMicrotasks();
      return h;
    }

    test('two unreported saves in a row stop Scene reloads', () {
      fakeAsync((async) {
        final h = announced(async);
        save(h, async, 'v2');
        expect(h.only<PlayHotSwapFailed>(), isEmpty);
        save(h, async, 'v3');
        final failed = h.only<PlayHotSwapFailed>().single;
        expect(failed.paths, {sceneAsset});
        expect(failed.misses, 2);
        final restarts = h.restarts.length;
        save(h, async, 'v4');
        expect(h.restarts, hasLength(restarts), reason: 'Scene batches stop');
        // Code reloads continue.
        unawaited(h.session.reload());
        async.flushMicrotasks();
        expect(h.restarts, hasLength(restarts + 1));
      });
    });

    test('reports keep it healthy', () {
      fakeAsync((async) {
        final h = announced(async);
        for (var i = 2; i < 8; i++) {
          save(h, async, 'v$i', report: 'reloaded');
        }
        expect(h.only<PlayHotSwapFailed>(), isEmpty);
      });
    });

    test('a save that changes nothing never fails it', () {
      fakeAsync((async) {
        final h = announced(async);
        for (var i = 0; i < 4; i++) {
          save(h, async, 'v1');
        }
        expect(h.only<PlayHotSwapFailed>(), isEmpty);
      });
    });

    test('a Scene the game never announced is noted once, never failed', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..startGame()
          ..answerReloads();
        h.fs.file(scene).writeAsStringSync('v1');
        for (var i = 2; i < 6; i++) {
          save(h, async, 'v$i');
        }
        expect(h.only<PlayHotSwapFailed>(), isEmpty);
        expect(
          h.only<PlayOutput>().where(
            (o) =>
                o.source == PlayOutputSource.tool &&
                o.line.contains(sceneAsset),
          ),
          hasLength(1),
        );
      });
    });

    test('restart() re-arms it', () {
      fakeAsync((async) {
        final h = announced(async);
        save(h, async, 'v2');
        save(h, async, 'v3');
        expect(h.only<PlayHotSwapFailed>(), hasLength(1));
        unawaited(h.session.restart());
        async.flushMicrotasks();
        h.process.emitLine('flutter: [pyro] Scene loaded: $sceneAsset');
        final restarts = h.restarts.length;
        save(h, async, 'v4', report: 'reloaded');
        expect(h.restarts.length, restarts + 1, reason: 'Scene reloads resume');
        expect(h.only<PlayHotSwapFailed>(), hasLength(1));
      });
    });
  });
}
