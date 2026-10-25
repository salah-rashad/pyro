import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/app.dart';
import 'package:pyro/app/shell.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_runtime/pyro_runtime.dart';
import 'package:pyro_ui/pyro_ui.dart';

import '../document/helpers/scenes.dart';
import '../helpers/fixtures.dart';
import '../process/fake_game.dart';

const _scenePath = '/proj/assets/scenes/level1.scene.json';
const _question = 'A game is running. Stop it and quit?';

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
  late OpenSceneCommand command;
  late LiveGame game;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/proj/assets/scenes').createSync(recursive: true);
    fs.directory('/proj/macos').createSync(recursive: true);
    fs.directory('/recovery').createSync(recursive: true);
    fs.file('/proj/pubspec.yaml').writeAsStringSync(pubspecDeclaredFolders);
    fs.file(_scenePath).writeAsStringSync(SceneCodec.encode(smallScene()));
    command = OpenSceneCommand(
      projectRoot: '/proj',
      recoveryFolder: '/recovery',
      fileSystem: fs,
      offload: runInline,
    );
  });

  /// The editor window over a fake game. Inside the test body: the fake
  /// process's streams must live in the test's zone.
  Future<PlayController> pumpWindow(WidgetTester tester) async {
    game = LiveGame(fs);
    container = ProviderContainer(
      overrides: [
        playFileSystemProvider.overrideWithValue(fs),
        playStarterProvider.overrideWithValue(game.start),
        playDirectoryWatcherProvider.overrideWithValue(
          (_) => const Stream.empty(),
        ),
      ],
    );
    container
        .read(projectProvider.notifier)
        .open(
          const ProjectState(
            root: '/proj',
            sdk: _sdk,
            compatibility: _compatible,
          ),
        );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PrTheme.dark(),
        home: UncontrolledProviderScope(
          container: container,
          child: PyroEditorWindow(
            command: command,
            settings: RecentProjectsStore(
              fs.file('/support/recent_projects.json'),
              fileSystem: fs,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final controller = container.listen(playControllerProvider, (_, _) {});
    return controller.read()!;
  }

  Future<void> play(WidgetTester tester, PlayController controller) async {
    unawaited(controller.play());
    await tester.pump();
    game.started('AbCdEf123456');
    await tester.pump();
    await tester.pump();
    expect(controller.phase, PlayPhase.running);
  }

  Future<void> openDirtyScene() async {
    final session = await command.open(_scenePath);
    command.register(
      container,
      sceneId: _scenePath,
      session: session,
      displayName: 'level1',
      path: _scenePath,
    );
    container.listen(documentProvider(_scenePath), (_, _) {});
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

  Future<void> finish(WidgetTester tester) async {
    for (final session in container.read(sessionRegistryProvider).values) {
      if (!session.isClosed) await session.discardAndClose();
    }
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(minutes: 1));
  }

  List<String> sent() => [
    for (final request in game.process.requests) request['method']! as String,
  ];

  group('quitting', () {
    testWidgets('with no game there is no question', (tester) async {
      await pumpWindow(tester);
      final response = tester.binding.handleRequestAppExit();
      await tester.pump();
      expect(find.text(_question), findsNothing);
      expect(await response, AppExitResponse.exit);
      await finish(tester);
    });

    testWidgets('yes stops the game first, then exits', (tester) async {
      final controller = await pumpWindow(tester);
      await play(tester, controller);
      final response = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text(_question), findsOneWidget);
      expect(controller.phase, PlayPhase.running, reason: 'not before yes');

      await tester.tap(find.text('Stop and quit'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(await response, AppExitResponse.exit);
      expect(sent(), contains('app.stop'));
      expect(controller.phase, PlayPhase.stopped);
      expect(game.process.exited, isTrue);
      await finish(tester);
    });

    testWidgets('no cancels the exit and leaves the game running', (
      tester,
    ) async {
      final controller = await pumpWindow(tester);
      await play(tester, controller);
      final response = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await response, AppExitResponse.cancel);
      expect(controller.phase, PlayPhase.running);
      expect(sent(), isNot(contains('app.stop')));

      // The close × and Esc say no as well.
      final again = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(await again, AppExitResponse.cancel);
      expect(controller.phase, PlayPhase.running);

      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await finish(tester);
    });

    testWidgets('unsaved Scenes are asked about before the game', (
      tester,
    ) async {
      final controller = await pumpWindow(tester);
      await openDirtyScene();
      await play(tester, controller);
      final response = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('Save changes to "level1"?'), findsOneWidget);
      expect(find.text(_question), findsNothing);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text(_question), findsOneWidget);
      await tester.tap(find.text('Stop and quit'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(await response, AppExitResponse.exit);
      expect(controller.phase, PlayPhase.stopped);
      await finish(tester);
    });

    testWidgets('cancelling the unsaved question never asks about the game', (
      tester,
    ) async {
      final controller = await pumpWindow(tester);
      await openDirtyScene();
      await play(tester, controller);
      final response = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await response, AppExitResponse.cancel);
      expect(find.text(_question), findsNothing);
      expect(controller.phase, PlayPhase.running);
      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await finish(tester);
    });
  });

  group('closing the project (the same helper)', () {
    Future<bool> close(WidgetTester tester, Completer<bool> result) async {
      final context = tester.element(find.byType(PyroEditorWindow));
      unawaited(closeProject(context, container).then(result.complete));
      await tester.pumpAndSettle();
      return result.isCompleted;
    }

    testWidgets('with no game it closes at once', (tester) async {
      await pumpWindow(tester);
      final result = Completer<bool>();
      expect(await close(tester, result), isTrue);
      expect(await result.future, isTrue);
      expect(container.read(projectProvider), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('asks first, and no keeps the project and the game', (
      tester,
    ) async {
      final controller = await pumpWindow(tester);
      await play(tester, controller);
      final result = Completer<bool>();
      expect(await close(tester, result), isFalse);
      expect(
        find.text('A game is running. Stop it and close the project?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result.future, isFalse);
      expect(container.read(projectProvider), isNotNull);
      expect(controller.phase, PlayPhase.running);
      unawaited(controller.stop());
      await tester.pump(const Duration(seconds: 2));
      await finish(tester);
    });

    testWidgets('yes stops the game, then closes the project', (tester) async {
      final controller = await pumpWindow(tester);
      await play(tester, controller);
      final result = Completer<bool>();
      await close(tester, result);
      await tester.tap(find.text('Stop and close'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(await result.future, isTrue);
      expect(sent(), contains('app.stop'));
      expect(controller.phase, PlayPhase.stopped);
      expect(container.read(projectProvider), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(minutes: 1));
    });
  });
}
