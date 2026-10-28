import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemEvent, FileSystemModifyEvent;

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/app.dart';
import 'package:pyro/app/play_notices.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../process/fake_game.dart';
import '../process/fake_process.dart';

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
  late MemoryFileSystem fs;
  late ProviderContainer container;
  late LiveGame game;
  late StreamController<FileSystemEvent> changes;
  late StreamController<FileSystemEvent> files;

  /// Opens the project over a fake game. Inside the test body, not
  /// `setUp`: the fake process's streams must live in the test's fake-async
  /// zone.
  void arrange() {
    fs = projectFileSystem();
    changes = StreamController<FileSystemEvent>.broadcast();
    files = StreamController<FileSystemEvent>.broadcast();
    game = LiveGame(fs, changes: () => changes.stream);
    container = ProviderContainer(
      overrides: [
        playFileSystemProvider.overrideWithValue(fs),
        playDirectoryWatcherProvider.overrideWithValue((_) => files.stream),
        playStarterProvider.overrideWithValue(game.start),
      ],
    );
    container
        .read(projectProvider.notifier)
        .open(
          const ProjectState(
            root: projectPath,
            sdk: _sdk,
            compatibility: _compatible,
          ),
        );
  }

  tearDown(() {
    unawaited(changes.close());
    unawaited(files.close());
    container.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PrTheme.dark(),
        home: UncontrolledProviderScope(
          container: container,
          child: const PlayNotices(child: Material(child: SizedBox.expand())),
        ),
      ),
    );
    await tester.pump();
  }

  /// Plays and lets the game start.
  Future<PlayController> run(WidgetTester tester) async {
    final controller = container.read(playControllerProvider)!;
    unawaited(controller.play());
    await tester.pump();
    game.started('AbCdEf123456');
    await tester.pump();
    await tester.pump();
    expect(controller.phase, PlayPhase.running);
    return controller;
  }

  testWidgets('a game that exits by itself is a Game stopped toast', (
    tester,
  ) async {
    arrange();
    await pump(tester);
    await run(tester);
    game.process.exit(0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Game stopped'), findsOneWidget);
    expect(find.text('The game was closed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Game stopped'), findsNothing, reason: 'it goes away');
    await tester.pump(PlayDefaults.consoleNotify);
  });

  testWidgets('a crash names its exit code', (tester) async {
    arrange();
    await pump(tester);
    await run(tester);
    game.process.exit(137);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('The game exited with code 137.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(PlayDefaults.consoleNotify);
  });

  testWidgets('a requested stop shows nothing', (tester) async {
    arrange();
    await pump(tester);
    final controller = await run(tester);
    unawaited(controller.stop());
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Game stopped'), findsNothing);
    await tester.pump(PlayDefaults.consoleNotify);
  });

  testWidgets('a Hot-swap that stopped offers Restart game', (tester) async {
    arrange();
    await pump(tester);
    final controller = await run(tester);
    const scene = 'assets/scenes/level1.scene.json';
    final file = fs.file('$projectPath/$scene')..writeAsStringSync('v1');
    game.process.emitLine('flutter: [pyro] Scene loaded: $scene');
    await tester.pump();
    for (final content in ['v2', 'v3']) {
      file.writeAsStringSync(content);
      changes.add(FileSystemModifyEvent(file.path, false, true));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 4));
    }
    expect(find.text('Hot-swap stopped working'), findsOneWidget);
    expect(find.text('Restart game'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Restart game'));
    await tester.pump(const Duration(seconds: 1));
    final restart = game.process.requests.last;
    expect(restart['method'], 'app.restart');
    expect(restart['params'], containsPair('fullRestart', true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Hot-swap stopped working'), findsNothing);

    unawaited(controller.stop());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(PlayDefaults.consoleNotify);
  });

  testWidgets('a second notice of a kind replaces the first', (tester) async {
    arrange();
    await pump(tester);
    await run(tester);
    game.process.exit(1);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('The game exited with code 1.'), findsOneWidget);
    // Play again and have it exit differently.
    game = LiveGame(fs, changes: () => changes.stream);
    container.updateOverrides([
      playFileSystemProvider.overrideWithValue(fs),
      playDirectoryWatcherProvider.overrideWithValue((_) => files.stream),
      playStarterProvider.overrideWithValue(game.start),
    ]);
    await tester.pump();
    await run(tester);
    game.process.exit(2);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Game stopped'), findsOneWidget);
    expect(find.text('The game exited with code 2.'), findsOneWidget);
    expect(find.text('The game exited with code 1.'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(PlayDefaults.consoleNotify);
  });

  group('a changed image the game uses (FR-013)', () {
    const ship = 'assets/images/ship.png';

    /// A project whose Scene names [ship], and a running game.
    Future<PlayController> arrangeWithImages(WidgetTester tester) async {
      arrange();
      fs
          .file('$projectPath/pubspec.yaml')
          .writeAsStringSync(
            'name: game\nflutter:\n  assets:\n    - assets/images/\n'
            '    - assets/scenes/\n',
          );
      fs.file('$projectPath/assets/images/ship.png')
        ..createSync(recursive: true)
        ..writeAsStringSync('png');
      fs.file('$projectPath/assets/images/unused.png').writeAsStringSync('png');
      fs
          .file('$projectPath/assets/scenes/level1.scene.json')
          .writeAsStringSync(
            jsonEncode({
              'schemaVersion': 1,
              'rootId': 'root',
              'nodes': {
                'root': {
                  'kind': 'root',
                  'childIds': ['hull'],
                },
                'hull': {
                  'kind': 'sprite',
                  'name': 'hull',
                  'props': {'image': ship},
                  'transform': {
                    'anchor': 'center',
                    'angle': 0,
                    'position': [0, 0],
                    'scale': [1, 1],
                    'size': [64, 64],
                  },
                },
              },
            }),
          );
      await pump(tester);
      final controller = await run(tester);
      await tester.pump();
      return controller;
    }

    void change(String relative) =>
        files.add(FileSystemModifyEvent('$projectPath/$relative', false, true));

    testWidgets('offers Restart game, which restarts and clears the toast', (
      tester,
    ) async {
      final controller = await arrangeWithImages(tester);
      change(ship);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Image changed'), findsOneWidget);
      expect(find.textContaining(ship), findsOneWidget);
      expect(find.text('Restart game'), findsOneWidget);
      // Nothing restarted by itself.
      expect(
        game.process.requests.where((r) => r['method'] == 'app.restart'),
        isEmpty,
      );

      await tester.tap(find.text('Restart game'));
      await tester.pump(const Duration(seconds: 1));
      final restart = game.process.requests.last;
      expect(restart['method'], 'app.restart');
      expect(restart['params'], containsPair('fullRestart', true));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Image changed'), findsNothing);

      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(PlayDefaults.consoleNotify);
    });

    testWidgets('left alone, the game is left as it is', (tester) async {
      final controller = await arrangeWithImages(tester);
      change(ship);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 30));
      expect(controller.phase, PlayPhase.running);
      expect(
        game.process.requests.where((r) => r['method'] == 'app.restart'),
        isEmpty,
      );
      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(PlayDefaults.consoleNotify);
    });

    testWidgets('an image no Scene names shows nothing', (tester) async {
      final controller = await arrangeWithImages(tester);
      change('assets/images/unused.png');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Image changed'), findsNothing);
      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(PlayDefaults.consoleNotify);
    });

    testWidgets('the offer leaves with the game', (tester) async {
      final controller = await arrangeWithImages(tester);
      change(ship);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Restart game'), findsOneWidget);
      game.process.exit(0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Game stopped'), findsOneWidget);
      expect(find.text('Image changed'), findsNothing);
      expect(find.text('Restart game'), findsNothing);
      expect(controller.phase, PlayPhase.stopped);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(PlayDefaults.consoleNotify);
    });

    testWidgets('a second change replaces the toast', (tester) async {
      final controller = await arrangeWithImages(tester);
      fs.file('$projectPath/assets/images/glow.png').writeAsStringSync('png');
      change(ship);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Image changed'), findsOneWidget);
      // The Scene now names a second image.
      final scene = fs.file('$projectPath/assets/scenes/level1.scene.json');
      final json = jsonDecode(scene.readAsStringSync()) as Map<String, Object?>;
      final nodes = json['nodes']! as Map<String, Object?>;
      (nodes['root']! as Map<String, Object?>)['childIds'] = ['hull', 'glow'];
      nodes['glow'] = {
        ...(nodes['hull']! as Map<String, Object?>),
        'name': 'glow',
        'props': {'image': 'assets/images/glow.png'},
      };
      scene.writeAsStringSync(jsonEncode(json));
      files.add(FileSystemModifyEvent(scene.path, false, true));
      await tester.pump(const Duration(milliseconds: 200));
      change('assets/images/glow.png');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Image changed'), findsOneWidget);
      expect(
        find.text(
          '2 images changed. '
          'The game shows the old ones until it restarts.',
        ),
        findsOneWidget,
      );
      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(PlayDefaults.consoleNotify);
    });
  });
}
