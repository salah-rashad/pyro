import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro_runtime/pyro_runtime.dart';
import 'package:pyro_runtime/src/loader/pyro_scene.dart'
    show HotSwapReport, hotSwapReportLine;

import '../support/loader_fixtures.dart';
import '../support/memory_asset_source.dart';
import '../support/scene_text.dart';
import '../support/test_registry.dart';

/// Root → `player` at ([x], 0).
String _scene(double x) => sceneJson([
  RootNode(id: const NodeId('root'), childIds: const [NodeId('p')]),
  CustomNode(
    id: const NodeId('p'),
    name: 'player',
    type: const TypeId('Player'),
    transform: at(x, 0),
  ),
]);

/// The Runtime's Hot-swap report lines (spec 007, contracts/hot-swap-reports.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> printed;
  late DebugPrintCallback original;
  late MemoryAssetSource source;

  setUp(() async {
    printed = [];
    original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    source = await sourceFor(_scene(0));
  });

  tearDown(() => debugPrint = original);

  List<String> reports() =>
      printed.where((line) => line.startsWith('[pyro] Scene ')).toList();

  Future<PyroScene> mount(FlameGame game) async {
    final scene = await PyroScene.load(
      scenePath,
      registry: testRegistry,
      assets: source,
    );
    await game.ensureAdd(scene);
    await game.ready();
    return scene;
  }

  Future<void> hotReload(FlameGame game, PyroScene scene) async {
    game.onHotReload();
    await scene.pendingCheck;
    await game.ready();
  }

  group('hotSwapReportLine', () {
    test('formats the three reports', () {
      expect(
        hotSwapReportLine(HotSwapReport.loaded, 'assets/scenes/a.scene.json'),
        '[pyro] Scene loaded: assets/scenes/a.scene.json',
      );
      expect(
        hotSwapReportLine(HotSwapReport.reloaded, 'assets/scenes/a.scene.json'),
        '[pyro] Scene reloaded: assets/scenes/a.scene.json',
      );
      expect(
        hotSwapReportLine(
          HotSwapReport.notReloaded,
          'assets/scenes/a.scene.json',
          'FormatException: Unexpected end of input\n  at line 1',
        ),
        '[pyro] Scene not reloaded: assets/scenes/a.scene.json: '
        'FormatException: Unexpected end of input',
      );
    });
  });

  testWithFlameGame('a first load prints "loaded" once', (game) async {
    await mount(game);
    expect(reports(), ['[pyro] Scene loaded: $scenePath']);
  });

  testWithFlameGame('a changed Scene prints "reloaded" once, an unchanged '
      'one nothing', (game) async {
    final scene = await mount(game);
    printed.clear();

    await hotReload(game, scene);
    expect(reports(), isEmpty);

    source.texts[scenePath] = _scene(10);
    await hotReload(game, scene);
    expect(reports(), ['[pyro] Scene reloaded: $scenePath']);
  });

  testWithFlameGame('a Scene that cannot be rebuilt prints "not reloaded" '
      'and keeps the old tree', (game) async {
    final scene = await mount(game);
    final before = scene.find<Player>('player');
    printed.clear();

    source.texts[scenePath] = '{"schemaVersion": 1,';
    await hotReload(game, scene);

    final lines = reports();
    expect(lines, hasLength(1));
    expect(lines.single, startsWith('[pyro] Scene not reloaded: $scenePath: '));
    expect(lines.single, isNot(contains('\n')));
    expect(scene.find<Player>('player'), same(before));
    expect(
      printed.where((line) => line.contains("couldn't Hot-swap")),
      hasLength(1),
      reason: 'the multi-line block stays',
    );
  });
}
