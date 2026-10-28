import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/app.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_ui/pyro_ui.dart';

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
  // SC-010: while the game is stopped, Play, the Console and the generator
  // state ask for no frame at all.
  testWidgets('a stopped game and an idle generator schedule no frames', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fs = projectFileSystem(path: '/proj');
    final container = ProviderContainer(
      overrides: [
        playFileSystemProvider.overrideWithValue(fs),
        generatorStateProvider.overrideWith(
          (ref) => Stream.value(const GeneratorState(GeneratorStatus.upToDate)),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(projectProvider.notifier)
        .open(
          const ProjectState(
            root: '/proj',
            sdk: _sdk,
            compatibility: _compatible,
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: PrTheme.dark(),
        home: UncontrolledProviderScope(
          container: container,
          child: PyroEditorWindow(
            command: OpenSceneCommand(
              projectRoot: '/proj',
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
    // Let the first frames, the status bar's stream and the Console settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Console'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

    // And it stays so: time passing asks for nothing.
    await tester.pump(const Duration(minutes: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  test('Play\'s code registers no ticker and no per-frame callback', () {
    final offenders = [
      for (final entity in Directory('lib/process').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          for (final banned in [
            'Ticker',
            'addPostFrameCallback',
            'addPersistentFrameCallback',
            'scheduleFrameCallback',
            'SchedulerBinding',
            'WidgetsBinding',
          ])
            if (entity.readAsStringSync().contains(banned))
              '${entity.path}: $banned',
    ];
    expect(offenders, isEmpty);
  });
}
