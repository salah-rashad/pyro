import 'dart:async';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/app.dart';
import 'package:pyro/app/play_toolbar.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_runtime/pyro_runtime.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../document/helpers/scenes.dart';
import '../helpers/fixtures.dart';

const scenePath = '/proj/assets/scenes/level1.scene.json';

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

/// A Play controller stand-in: counts plays and drives its phase by hand.
final class FakeStarts {
  var count = 0;
  final List<Completer<PlaySession>> _sessions = [];

  Future<PlaySession> call(String path, {RunLink? runLink}) {
    count++;
    final session = Completer<PlaySession>();
    _sessions.add(session);
    return session.future;
  }

  /// Fails every pending start, ending the controller in stopped.
  void failAll() {
    for (final session in _sessions) {
      if (!session.isCompleted) {
        session.completeError(const PlayStartException('/proj', 'test end'));
      }
    }
  }
}

void main() {
  late MemoryFileSystem fs;
  late ProviderContainer container;
  late OpenSceneCommand command;
  late FakeStarts starts;

  ProviderContainer openProject({
    SdkInfo sdk = _sdk,
    RuntimeCompatibility compatibility = _compatible,
  }) {
    final c = ProviderContainer(
      overrides: [
        playFileSystemProvider.overrideWithValue(fs),
        playStarterProvider.overrideWithValue(starts.call),
      ],
    );
    c
        .read(projectProvider.notifier)
        .open(
          ProjectState(root: '/proj', sdk: sdk, compatibility: compatibility),
        );
    return c;
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PrTheme.dark(),
        home: UncontrolledProviderScope(
          container: container,
          child: Material(
            color: PrColors.dark.surfacePanel,
            child: Align(
              alignment: Alignment.topCenter,
              child: PlayToolbar(command: command),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openDirtyScene() async {
    final session = await command.open(scenePath);
    command.register(
      container,
      sceneId: scenePath,
      session: session,
      displayName: 'level1',
      path: scenePath,
    );
    container.listen(documentProvider(scenePath), (_, _) {});
    session.transact('Add entity', (doc) {
      return doc.addNode(
        EntityNode(
          id: const NodeId('extra'),
          name: 'extra',
          transform: NodeTransform(),
        ),
        parentId: doc.rootId,
      );
    });
  }

  Future<void> closeAll() async {
    for (final session in container.read(sessionRegistryProvider).values) {
      if (!session.isClosed) await session.discardAndClose();
    }
  }

  Finder playButton() => find.widgetWithText(PrButton, 'Play');

  setUp(() {
    starts = FakeStarts();
    fs = MemoryFileSystem.test();
    fs.directory('/proj/assets/scenes').createSync(recursive: true);
    fs.directory('/proj/macos').createSync(recursive: true);
    fs.directory('/recovery').createSync(recursive: true);
    fs.file('/proj/pubspec.yaml').writeAsStringSync(pubspecDeclaredFolders);
    fs.file(scenePath).writeAsStringSync(SceneCodec.encode(smallScene()));
    command = OpenSceneCommand(
      projectRoot: '/proj',
      recoveryFolder: '/recovery',
      fileSystem: fs,
      offload: runInline,
    );
  });

  tearDown(() {
    starts.failAll();
    container.dispose();
  });

  testWidgets('Play is enabled with no block and starts the game', (
    tester,
  ) async {
    container = openProject();
    await pump(tester);
    expect(tester.widget<PrButton>(playButton()).onPressed, isNotNull);
    expect(find.text('Stopped'), findsOneWidget);
    await tester.tap(playButton());
    await tester.pump();
    expect(starts.count, 1);
    expect(find.text('Starting…'), findsOneWidget);
    expect(find.widgetWithText(PrButton, 'Stop'), findsOneWidget);
    starts.failAll();
    await tester.pump();
    await tester.pump();
    expect(find.text('Stopped'), findsOneWidget);
    // The Console's throttled notification.
    await tester.pump(PlayDefaults.consoleNotify);
  });

  group('Play is disabled with its reason and fix', () {
    testWidgets('no Flutter SDK', (tester) async {
      container = openProject(sdk: SdkInfo.none);
      await pump(tester);
      expect(tester.widget<PrButton>(playButton()).onPressed, isNull);
      expect(find.textContaining('No Flutter SDK'), findsOneWidget);
      expect(find.textContaining('FLUTTER_ROOT'), findsOneWidget);
    });

    testWidgets('an incompatible Runtime', (tester) async {
      container = openProject(compatibility: RuntimeCompatibility.unknown);
      await pump(tester);
      expect(tester.widget<PrButton>(playButton()).onPressed, isNull);
      expect(find.textContaining("Runtime can't run"), findsOneWidget);
      expect(find.textContaining('pyro_runtime was not found'), findsOne);
    });

    testWidgets('no macos/ folder', (tester) async {
      fs.directory('/proj/macos').deleteSync();
      container = openProject();
      await pump(tester);
      expect(tester.widget<PrButton>(playButton()).onPressed, isNull);
      expect(
        find.textContaining('flutter create --platforms=macos .'),
        findsOneWidget,
      );
      final button = tester.widget<PrButton>(playButton());
      expect(button.disabledReason, contains('macos/'));
    });
  });

  testWidgets('shows the four phase labels', (tester) async {
    container = openProject();
    await pump(tester);
    expect(find.text('Stopped'), findsOneWidget);
    // The controller's own transitions are tested in play_controller_test;
    // here each phase only needs its label.
    final labels = {
      PlayPhase.stopped: 'Stopped',
      PlayPhase.starting: 'Starting…',
      PlayPhase.running: 'Running',
      PlayPhase.stopping: 'Stopping…',
    };
    for (final MapEntry(key: phase, value: label) in labels.entries) {
      final c = ProviderContainer(
        parent: container,
        overrides: [playPhaseProvider.overrideWithValue(AsyncData(phase))],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: PrTheme.dark(),
          home: UncontrolledProviderScope(
            container: c,
            child: Material(child: PlayToolbar(command: command)),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget, reason: '$phase');
      expect(
        find.widgetWithText(
          PrButton,
          phase == PlayPhase.stopped ? 'Play' : 'Stop',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  group('with an unsaved Scene', () {
    testWidgets('Play asks first; dismissing starts nothing', (tester) async {
      container = openProject();
      await openDirtyScene();
      await pump(tester);
      await tester.tap(playButton());
      await tester.pumpAndSettle();
      expect(find.text('Save and play'), findsOneWidget);
      expect(find.text('Play without saving'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(starts.count, 0);
      await tester.tap(playButton());
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(starts.count, 0);
      expect(container.read(documentProvider(scenePath)).isDirty, isTrue);
      await closeAll();
    });

    testWidgets('Save and play saves, then starts', (tester) async {
      container = openProject();
      await openDirtyScene();
      await pump(tester);
      await tester.tap(playButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and play'));
      await tester.pumpAndSettle();
      expect(container.read(documentProvider(scenePath)).isDirty, isFalse);
      expect(fs.file(scenePath).readAsStringSync(), contains('"extra"'));
      expect(starts.count, 1);
      await closeAll();
    });

    testWidgets('a failing save starts nothing', (tester) async {
      container = openProject();
      await openDirtyScene();
      await pump(tester);
      // The folder goes away under the open Scene: its save fails.
      fs.directory('/proj/assets').deleteSync(recursive: true);
      await tester.tap(playButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and play'));
      await tester.pumpAndSettle();
      expect(container.read(documentProvider(scenePath)).isDirty, isTrue);
      expect(starts.count, 0);
      await closeAll();
    });

    testWidgets('Play without saving starts at once', (tester) async {
      container = openProject();
      await openDirtyScene();
      await pump(tester);
      await tester.tap(playButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play without saving'));
      await tester.pumpAndSettle();
      expect(starts.count, 1);
      expect(container.read(documentProvider(scenePath)).isDirty, isTrue);
      await closeAll();
    });
  });

  testWidgets('with no unsaved Scene, no question appears', (tester) async {
    container = openProject();
    final session = await command.open(scenePath);
    command.register(
      container,
      sceneId: scenePath,
      session: session,
      displayName: 'level1',
      path: scenePath,
    );
    container.listen(documentProvider(scenePath), (_, _) {});
    await pump(tester);
    await tester.tap(playButton());
    await tester.pumpAndSettle();
    expect(find.text('Save and play'), findsNothing);
    expect(starts.count, 1);
    await closeAll();
  });
}
