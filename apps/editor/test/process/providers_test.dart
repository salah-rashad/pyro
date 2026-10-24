import 'dart:io' show ProcessSignal;

import 'package:file/memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/app.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';

import 'fake_generator.dart';

ProjectState project(
  String root, {
  SdkInfo sdk = SdkInfo.none,
  RuntimeCompatibility compatibility = RuntimeCompatibility.unknown,
}) => ProjectState(root: root, sdk: sdk, compatibility: compatibility);

const _sdk = SdkInfo(
  version: '3.44.2',
  source: SdkSource.flutterRoot,
  root: '/sdk',
);

const _compatible = RuntimeCompatibility(
  status: RuntimeCompatStatus.ok,
  foundVersion: '0.0.1',
  readsUpTo: 1,
);

void main() {
  group('consoleBufferProvider', () {
    test('is recreated when the project root changes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(consoleBufferProvider, (_, _) {});
      container.read(projectProvider.notifier).open(project('/a'));
      final first = container.read(consoleBufferProvider)
        ..add('from a', source: ConsoleSource.pyro);
      container.read(projectProvider.notifier).open(project('/b'));
      final second = container.read(consoleBufferProvider);
      expect(second, isNot(same(first)));
      expect(second.lines, isEmpty);
    });

    test('is disposed when the project closes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(consoleBufferProvider, (_, _) {});
      container.read(projectProvider.notifier).open(project('/a'));
      final buffer = container.read(consoleBufferProvider);
      var closed = false;
      buffer.changes.listen(null, onDone: () => closed = true);
      container.read(projectProvider.notifier).close();
      container.read(consoleBufferProvider);
      return pumpEventQueue().then((_) => expect(closed, isTrue));
    });
  });

  group('consoleSourceFilterProvider', () {
    test('shows every source by default, one, then all again', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(consoleSourceFilterProvider), {
        ...ConsoleSource.values,
      });
      container
          .read(consoleSourceFilterProvider.notifier)
          .showOnly(ConsoleSource.game);
      expect(container.read(consoleSourceFilterProvider), {ConsoleSource.game});
      container.read(consoleSourceFilterProvider.notifier).showAll();
      expect(container.read(consoleSourceFilterProvider), {
        ...ConsoleSource.values,
      });
    });
  });

  group('playControllerProvider', () {
    late MemoryFileSystem fs;
    late ProviderContainer container;
    late List<String> started;

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.directory('/a/macos').createSync(recursive: true);
      fs.directory('/b').createSync(recursive: true);
      started = [];
      container = ProviderContainer(
        overrides: [
          playFileSystemProvider.overrideWithValue(fs),
          playStarterProvider.overrideWithValue((path) async {
            started.add(path);
            throw PlayStartException(path, 'not in tests');
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(playControllerProvider, (_, _) {});
    });

    test('is null without a project', () {
      expect(container.read(playControllerProvider), isNull);
    });

    test('has no block for a playable project and plays it', () async {
      container
          .read(projectProvider.notifier)
          .open(project('/a', sdk: _sdk, compatibility: _compatible));
      final controller = container.read(playControllerProvider)!;
      expect(controller.projectPath, '/a');
      expect(controller.block, isNull);
      await controller.play();
      expect(started, ['/a']);
      expect(
        container.read(consoleBufferProvider).lines.last.text,
        "Can't play /a: not in tests",
      );
    });

    test('blocks in the data model order', () {
      final notifier = container.read(projectProvider.notifier);
      notifier.open(project('/b'));
      expect(
        container.read(playControllerProvider)!.block!.reason,
        contains('Flutter SDK'),
      );
      notifier.open(project('/b', sdk: _sdk));
      expect(
        container.read(playControllerProvider)!.block!.fix,
        contains('pyro_runtime was not found'),
      );
      notifier.open(project('/b', sdk: _sdk, compatibility: _compatible));
      expect(
        container.read(playControllerProvider)!.block!.fix,
        contains('flutter create --platforms=macos .'),
      );
    });

    test('is recreated per project and disposed on close', () async {
      final notifier = container.read(projectProvider.notifier);
      notifier.open(project('/a', sdk: _sdk, compatibility: _compatible));
      final first = container.read(playControllerProvider)!;
      var closed = false;
      first.phases.listen(null, onDone: () => closed = true);
      notifier.open(project('/b', sdk: _sdk, compatibility: _compatible));
      expect(container.read(playControllerProvider), isNot(same(first)));
      await pumpEventQueue();
      expect(closed, isTrue);
      notifier.close();
      expect(container.read(playControllerProvider), isNull);
    });
  });

  group('generatorProvider', () {
    late MemoryFileSystem fs;
    late ProviderContainer container;
    late Spawns spawns;
    late FakeProbe probe;

    String lock(String? buildRunner) =>
        'packages:\n'
        '${buildRunner == null ? '' : '  build_runner:\n    version: "$buildRunner"\n'}'
        '  pyro_runtime:\n    version: "0.0.1"\n';

    void fresh() {
      fs = MemoryFileSystem.test();
      fs.file('/proj/pubspec.lock')
        ..createSync(recursive: true)
        ..writeAsStringSync(lock('2.15.1'));
      spawns = Spawns();
      probe = FakeProbe()..fallback = LockProbeResult.free;
      container = ProviderContainer(
        overrides: [
          playFileSystemProvider.overrideWithValue(fs),
          generatorProcessStarterProvider.overrideWithValue(spawns.call),
          buildLockProbeProvider.overrideWithValue(probe),
        ],
      );
    }

    setUp(fresh);

    tearDown(() async {
      container.dispose();
      await pumpEventQueue();
    });

    void open({
      SdkInfo sdk = _sdk,
      RuntimeCompatibility compatibility = _compatible,
    }) {
      container
          .read(projectProvider.notifier)
          .open(project('/proj', sdk: sdk, compatibility: compatibility));
      container.listen(generatorProvider, (_, _) {});
      container.listen(generatorStateProvider, (_, _) {});
    }

    test('is null without a project', () {
      expect(container.read(generatorProvider), isNull);
    });

    test("starts the SDK's dart on the opened project", () async {
      open();
      await pumpEventQueue();
      expect(spawns.commands, [
        ['/sdk/bin/dart', 'run', 'build_runner', 'watch'],
      ]);
      expect(spawns.directories, ['/proj']);
      expect(
        container.read(generatorProvider)!.state.status,
        GeneratorStatus.starting,
      );
      expect(
        container.read(generatorStateProvider).value?.status,
        GeneratorStatus.starting,
      );
    });

    test('is not set up, and says why', () async {
      final reasons = <String, ({String? lock, SdkInfo sdk, bool compatible})>{
        'build_runner is not in the project': (
          lock: null,
          sdk: _sdk,
          compatible: true,
        ),
        '2.13.9': (lock: '2.13.9', sdk: _sdk, compatible: true),
        'needs the Flutter SDK': (
          lock: '2.15.1',
          sdk: SdkInfo.none,
          compatible: true,
        ),
        'pyro_runtime was not found': (
          lock: '2.15.1',
          sdk: _sdk,
          compatible: false,
        ),
      };
      for (final MapEntry(key: reason, value: setup) in reasons.entries) {
        container.dispose();
        fresh();
        fs.file('/proj/pubspec.lock').writeAsStringSync(lock(setup.lock));
        open(
          sdk: setup.sdk,
          compatibility: setup.compatible
              ? _compatible
              : RuntimeCompatibility.unknown,
        );
        await pumpEventQueue();
        final state = container.read(generatorProvider)!.state;
        expect(state.status, GeneratorStatus.notSetUp, reason: reason);
        expect(state.reason, contains(reason));
        expect(spawns.processes, isEmpty);
        expect(probe.calls, 0);
      }
    });

    test('forwards its output to the Console, errors as errors', () async {
      open();
      await pumpEventQueue();
      spawns.last
        ..emitLine('  0s pyro_generator:pyro_scan on 9 inputs; lib/a.dart')
        ..emitLine('E pyro_generator:pyro_scan on lib/a.dart:')
        ..emitLine('  11:27: Expected an identifier.')
        ..emitLine(
          '  Failed to build with build_runner/aot in 0s; wrote 2 outputs.',
        )
        ..emitLine('Starting build #2.');
      await pumpEventQueue();
      final lines = container
          .read(consoleBufferProvider)
          .lines
          .where((line) => line.source == ConsoleSource.generator)
          .toList();
      expect(lines.map((line) => line.severity), [
        ConsoleSeverity.info,
        ConsoleSeverity.error,
        ConsoleSeverity.error,
        ConsoleSeverity.error,
        ConsoleSeverity.info,
      ]);
      expect(lines[2].text, '  11:27: Expected an identifier.');
    });

    test('is recreated per project and stops its own run on close', () async {
      open();
      await pumpEventQueue();
      final first = container.read(generatorProvider);
      container.read(projectProvider.notifier).close();
      await pumpEventQueue();
      expect(spawns.processes.single.signals, [ProcessSignal.sigterm]);
      expect(container.read(generatorProvider), isNull);
      expect(first, isNotNull);
      spawns.processes.single.exit(-15);
      await pumpEventQueue();
    });

    test('an external run is never touched on close', () async {
      probe.fallback = LockProbeResult.held;
      open();
      await pumpEventQueue();
      expect(
        container.read(generatorProvider)!.state.status,
        GeneratorStatus.external,
      );
      container.read(projectProvider.notifier).close();
      await pumpEventQueue();
      expect(spawns.processes, isEmpty);
    });
  });
}
