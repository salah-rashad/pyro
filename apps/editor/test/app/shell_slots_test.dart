import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/app.dart';
import 'package:pyro/app/play_toolbar.dart';
import 'package:pyro/panels/panels.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

/// Pumps the editor window for `/work/example` at 1280×800 and returns its
/// container.
Future<ProviderContainer> pumpWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fs = MemoryFileSystem.test();
  final container = ProviderContainer();
  container
      .read(projectProvider.notifier)
      .open(
        const ProjectState(
          root: '/work/example',
          sdk: SdkInfo.none,
          compatibility: RuntimeCompatibility.unknown,
        ),
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: PrTheme.dark(),
      home: UncontrolledProviderScope(
        container: container,
        child: PyroEditorWindow(
          command: OpenSceneCommand(
            projectRoot: '/work/example',
            recoveryFolder: '/recovery',
            fileSystem: fs,
          ),
          settings: RecentProjectsStore(
            fs.file('/support/recent_projects.json'),
            fileSystem: fs,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Unmounts the window and disposes [container].
Future<void> unmountWindow(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  testWidgets('the bottom dock holds the Console (T010)', (tester) async {
    final container = await pumpWindow(tester);
    final shell = tester.widget<PrEditorShell>(find.byType(PrEditorShell));
    expect(shell.bottom, isA<ConsolePanel>());
    expect(shell.bottomCollapsed, isFalse);
    expect(find.text('Console'), findsOneWidget);
    expect(
      find.text('No output yet. Press Play to run the game.'),
      findsOneWidget,
    );
    await unmountWindow(tester, container);
  });

  testWidgets('the toolbar holds Play (T024)', (tester) async {
    final container = await pumpWindow(tester);
    expect(find.byType(PlayToolbar), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    // /work/example has no SDK in this harness: Play says why it waits.
    expect(find.textContaining('No Flutter SDK was found'), findsOneWidget);
    await unmountWindow(tester, container);
  });
}
