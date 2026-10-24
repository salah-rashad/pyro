/// The Riverpod layer over Play, the generator and the Console (spec 007).
///
/// A library of its own: `process.dart` stays free of Flutter so
/// `bin/play.dart` still runs with `dart run`; the editor window reaches
/// the process units only through these providers.
library;

import 'dart:async';
import 'dart:io' show Process;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app.dart';
import '../project/project.dart';
import 'process.dart';

/// The file system Play reads the project through; tests inject a memory
/// one.
final playFileSystemProvider = Provider<FileSystem>(
  (ref) => const LocalFileSystem(),
);

/// Starts Play sessions; the app's is `PlayClient.start` with the open
/// project's `flutter`. Tests inject a fake.
final playStarterProvider = Provider<PlayStarter>((ref) {
  final sdk = ref.watch(projectProvider.select((project) => project?.sdk));
  final client = PlayClient(
    flutter: flutterExecutable(sdk ?? SdkInfo.none),
    fileSystem: ref.watch(playFileSystemProvider),
  );
  return client.start;
});

/// The open project's Play: one `PlayController` per project, disposed
/// (which stops the game) when the project closes; null with no project.
final playControllerProvider = Provider<PlayController?>((ref) {
  final project = ref.watch(projectProvider);
  if (project == null) return null;
  final fs = ref.watch(playFileSystemProvider);
  final controller = PlayController(
    projectPath: project.root,
    console: ref.watch(consoleBufferProvider),
    start: ref.watch(playStarterProvider),
    block: PlayBlock.of(
      // A project that failed to open never reaches the editor window,
      // which shows its error instead.
      projectError: null,
      hasSdk: project.sdk.source != SdkSource.none,
      runtimeProblem: runtimeProblem(project.compatibility),
      hasMacosFolder: fs
          .directory(fs.path.join(project.root, 'macos'))
          .existsSync(),
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Spawns the generator's `build_runner`; tests inject a fake.
final generatorProcessStarterProvider = Provider<ProcessStarter>(
  (ref) => Process.start,
);

/// Looks at the project's `build_runner` lock; tests inject a fake.
final buildLockProbeProvider = Provider<BuildLockProbe>(
  (ref) => const BuildLockProbe(),
);

/// Why the generator cannot run in [project], or null (FR-017, FR-020):
/// no Flutter SDK, no `build_runner` or one older than 2.14, or an
/// incompatible Runtime, in that order.
String? generatorSetUpProblem(ProjectState project, FileSystem fileSystem) {
  if (project.sdk.source == SdkSource.none) {
    return 'build_runner needs the Flutter SDK, which was not found.';
  }
  return BuildRunnerVersion.of(project.root, fileSystem: fileSystem).reason ??
      runtimeProblem(project.compatibility);
}

/// The open project's generator: one `GeneratorSupervisor` per project,
/// started when the project opens, its output forwarded to the Console, and
/// disposed (which stops Pyro's own `build_runner`, never an external one)
/// when the project closes; null with no project.
final generatorProvider = Provider<GeneratorSupervisor?>((ref) {
  final project = ref.watch(projectProvider);
  if (project == null) return null;
  final console = ref.watch(consoleBufferProvider);
  final supervisor = GeneratorSupervisor(
    projectPath: project.root,
    dart: dartExecutable(project.sdk),
    setUpProblem: generatorSetUpProblem(
      project,
      ref.watch(playFileSystemProvider),
    ),
    startProcess: ref.watch(generatorProcessStarterProvider),
    probe: ref.watch(buildLockProbeProvider),
  );
  var continuesSevere = false;
  final lines = supervisor.lines.listen((line) {
    final kind = classifyGeneratorLine(line);
    // A severe line is followed by its message, indented.
    final isError =
        kind == GeneratorLine.severe ||
        kind == GeneratorLine.failed ||
        (continuesSevere && line.startsWith(' '));
    continuesSevere = kind == GeneratorLine.severe;
    console.add(
      line,
      source: ConsoleSource.generator,
      severity: isError ? ConsoleSeverity.error : ConsoleSeverity.info,
    );
  });
  ref.onDispose(() {
    unawaited(lines.cancel());
    unawaited(supervisor.dispose());
  });
  unawaited(supervisor.start());
  return supervisor;
});

/// The open project's generator state, for the status bar; "stopped" with
/// no project.
final generatorStateProvider = StreamProvider<GeneratorState>((ref) async* {
  final supervisor = ref.watch(generatorProvider);
  if (supervisor == null) {
    yield GeneratorState.initial;
    return;
  }
  yield supervisor.state;
  yield* supervisor.states;
});

/// The open project's Play phase, for the toolbar; stopped with no
/// project.
final playPhaseProvider = StreamProvider<PlayPhase>((ref) {
  final controller = ref.watch(playControllerProvider);
  if (controller == null) return Stream.value(PlayPhase.stopped);
  return controller.phases;
});

/// The Runtime compatibility check's message when it blocks Play, in the
/// status bar's words; null when the Runtime is compatible.
String? runtimeProblem(RuntimeCompatibility compatibility) =>
    switch (compatibility.status) {
      RuntimeCompatStatus.ok => null,
      RuntimeCompatStatus.tooOld =>
        'pyro_runtime ${compatibility.foundVersion} is too old for this Pyro; '
            'update pyro_runtime in the project.',
      RuntimeCompatStatus.tooNew =>
        'pyro_runtime ${compatibility.foundVersion} needs a newer Pyro; '
            'update Pyro.',
      RuntimeCompatStatus.unknown =>
        'pyro_runtime was not found in pubspec.lock; add it to the project '
            'and run `flutter pub get`.',
    };

/// The open project's Console: a new, empty buffer per project root,
/// disposed when the project closes or another one opens.
final consoleBufferProvider = Provider<ConsoleBuffer>((ref) {
  ref.watch(projectProvider.select((project) => project?.root));
  final buffer = ConsoleBuffer();
  ref.onDispose(buffer.dispose);
  return buffer;
});

/// The Console's sources shown; all of them by default, never none.
final consoleSourceFilterProvider =
    NotifierProvider<ConsoleSourceFilter, Set<ConsoleSource>>(
      ConsoleSourceFilter.new,
    );

/// [consoleSourceFilterProvider]'s notifier.
class ConsoleSourceFilter extends Notifier<Set<ConsoleSource>> {
  @override
  Set<ConsoleSource> build() => ConsoleSource.values.toSet();

  /// Shows only [source]'s lines.
  void showOnly(ConsoleSource source) => state = {source};

  /// Shows every source.
  void showAll() => state = ConsoleSource.values.toSet();
}
