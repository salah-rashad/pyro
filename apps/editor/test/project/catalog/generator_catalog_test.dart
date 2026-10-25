import 'dart:async';
import 'dart:io' show FileSystemEvent, FileSystemModifyEvent;

import 'package:fake_async/fake_async.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/app/providers.dart';
import 'package:pyro/panels/hierarchy/hierarchy_model.dart';
import 'package:pyro/process/process.dart';
import 'package:pyro/process/providers.dart';
import 'package:pyro/project/project.dart';
import 'package:pyro_runtime/pyro_runtime.dart';

import '../../helpers/fixtures.dart';
import '../../process/fake_generator.dart';

/// The generator and the Type catalog together (spec 007, FR-018, FR-020,
/// FR-021): a failing or external `build_runner` changes nothing about the
/// catalog's rules.
void main() {
  // A broadcast stream the test drives; nothing to release.
  // ignore: close_sinks
  late StreamController<FileSystemEvent> events;
  late FileSystem fs;
  late Spawns spawns;
  late FakeProbe probe;

  const manifestPath = '/proj/lib/pyro.manifest.json';

  setUp(() {
    events = StreamController<FileSystemEvent>.broadcast();
    fs = MemoryFileSystem.test();
    fs.directory('/proj/lib').createSync(recursive: true);
    fs
        .file('/proj/pubspec.lock')
        .writeAsStringSync(
          'packages:\n'
          '  build_runner:\n    version: "2.15.1"\n'
          '  pyro_runtime:\n    version: "0.0.1"\n',
        );
    spawns = Spawns();
    probe = FakeProbe()..fallback = LockProbeResult.free;
  });

  ProviderContainer open() {
    final c = ProviderContainer(
      overrides: [
        catalogFileSystemProvider.overrideWithValue(fs),
        manifestWatchProvider.overrideWithValue((_) => events.stream),
        playFileSystemProvider.overrideWithValue(fs),
        generatorProcessStarterProvider.overrideWithValue(spawns.call),
        generatorDescendantsProvider.overrideWithValue((_) async => const []),
        buildLockProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(projectProvider.notifier)
        .open(
          const ProjectState(
            root: '/proj',
            sdk: SdkInfo(
              version: '3.44.2',
              source: SdkSource.flutterRoot,
              root: '/sdk',
            ),
            compatibility: RuntimeCompatibility(
              status: RuntimeCompatStatus.ok,
              foundVersion: '0.0.1',
              readsUpTo: 1,
            ),
          ),
        );
    c.listen(generatorProvider, (_, _) {});
    return c;
  }

  void manifestChanged() =>
      events.add(FileSystemModifyEvent(manifestPath, false, true));

  final entity = EntityNode(
    id: const NodeId('e'),
    name: 'e',
    transform: NodeTransform(),
    behaviors: [BehaviorAttachment(type: const TypeId('Spin'))],
  );

  test('a generator error keeps the last good types and no Behavior goes '
      'Missing (FR-020, FR-021, Q105)', () {
    fakeAsync((async) {
      fs.file(manifestPath).writeAsStringSync(readExampleManifest());
      final c = open();
      async.flushMicrotasks();
      expect(c.read(typeCatalogProvider).origin, isA<ManifestUpToDate>());
      expect(c.read(typeCatalogProvider)[const TypeId('Spin')], isNotNull);

      // The build fails; the generator writes the Manifest with its errors.
      spawns.last
        ..emitLine('Starting build #2.')
        ..emitLine('E pyro_generator:pyro_scan on lib/behaviors/spin.dart:')
        ..emitLine('  11:27: Expected an identifier.')
        ..emitLine(
          '  Failed to build with build_runner/aot in 0s; wrote 2 outputs.',
        );
      fs.file(manifestPath).writeAsStringSync(manifestWithProblems);
      manifestChanged();
      async.elapse(manifestQuietPeriod);

      expect(c.read(generatorProvider)!.state.status, GeneratorStatus.error);
      final catalog = c.read(typeCatalogProvider);
      expect(catalog.origin, isA<ManifestStale>());
      expect(catalog.problems, isNotEmpty);
      expect(
        catalog[const TypeId('Spin')],
        isNotNull,
        reason: 'stale, not empty',
      );
      expect(hasMissingBehavior(entity, catalog), isFalse);
      expect(isMissing(entity, catalog), isFalse);

      // The fix builds: the Manifest is clean and the catalog current.
      spawns.last
        ..emitLine('Starting build #3.')
        ..emitLine('  Built with build_runner/aot in 0s; wrote 3 outputs.');
      fs.file(manifestPath).writeAsStringSync(readExampleManifest());
      manifestChanged();
      async.elapse(manifestQuietPeriod);
      expect(c.read(generatorProvider)!.state.status, GeneratorStatus.upToDate);
      expect(c.read(typeCatalogProvider).origin, isA<ManifestUpToDate>());
      expect(hasMissingBehavior(entity, c.read(typeCatalogProvider)), isFalse);
    });
  });

  test('with an external build_runner, a Manifest change still updates the '
      'catalog (FR-018)', () {
    fakeAsync((async) {
      probe.fallback = LockProbeResult.held;
      fs.file(manifestPath).writeAsStringSync(manifestWithShip);
      final c = open();
      async.flushMicrotasks();
      expect(c.read(generatorProvider)!.state.status, GeneratorStatus.external);
      expect(spawns.processes, isEmpty);
      expect(c.read(typeCatalogProvider)[const TypeId('Ship')], isNotNull);

      // The user's own generator writes a new Manifest.
      fs.file(manifestPath).writeAsStringSync(readExampleManifest());
      manifestChanged();
      async.elapse(manifestQuietPeriod);

      final catalog = c.read(typeCatalogProvider);
      expect(catalog.origin, isA<ManifestUpToDate>());
      expect(catalog[const TypeId('Ship')], isNull);
      expect(catalog[const TypeId('Spin')], isNotNull);
      expect(c.read(generatorProvider)!.state.status, GeneratorStatus.external);
    });
  });
}

/// A Manifest with one custom component, `Ship`.
const String manifestWithShip = '''
{
  "manifestVersion": 1,
  "types": [
    {
      "id": "Ship",
      "role": "component",
      "label": "Ship",
      "supertypes": ["PositionComponent"],
      "fields": []
    }
  ],
  "errors": [],
  "warnings": []
}
''';
