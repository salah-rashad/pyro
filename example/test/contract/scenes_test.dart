/// #12's Scene check (Q59; spec 005, FR-012): every Scene under
/// `assets/scenes/` loads with the real, generated Registry, with no error
/// and no Runtime warning. The Runtime only warns about an Override the code
/// no longer has, so a warning fails the check too.
library;

import 'dart:io';
import 'dart:ui' show Image;

import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro_example/pyro.g.dart';
import 'package:pyro_runtime/pyro_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenes =
      Directory('assets/scenes')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.uri.pathSegments.join('/'))
          .where((path) => path.endsWith('.scene.json'))
          .toList()
        ..sort();

  test('there are Scenes to check', () {
    expect(scenes, isNotEmpty, reason: 'no *.scene.json under assets/scenes/');
  });

  for (final path in scenes) {
    testWithFlameGame('loads $path', (game) async {
      final warnings = await _load(game, path);
      expect(warnings, isEmpty, reason: 'Runtime warnings for $path');
    });
  }

  testWithFlameGame('a Runtime warning is caught', (game) async {
    const path = 'assets/scenes/level1.scene.json';
    final text = await rootBundle.loadString(path);
    final unused = text.replaceFirst(
      '"turnsPerSecond": 0.5',
      '"speed": 3,\n            "turnsPerSecond": 0.5',
    );
    expect(unused, isNot(text));
    final warnings = await _load(game, path, assets: _Overlay({path: unused}));
    expect(warnings.join('\n'), contains('Spin.speed'));
  });
}

/// Loads [path] into [game] with the default `UnknownType.error`, returning
/// whatever the Runtime printed while it did, except its `[pyro] Scene …`
/// Hot-swap reports (spec 007), which are not warnings.
Future<List<String>> _load(
  FlameGame game,
  String path, {
  AssetSource? assets,
}) async {
  final printed = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    final line = message ?? '';
    if (!line.startsWith('[pyro] Scene ')) printed.add(line);
  };
  try {
    final scene = await PyroScene.load(
      path,
      registry: pyroRegistry,
      assets: assets,
    );
    await game.ensureAdd(scene);
    await game.ready();
  } finally {
    debugPrint = original;
  }
  return printed;
}

/// The bundle, with some texts replaced.
final class _Overlay implements AssetSource {
  _Overlay(this._texts);

  final Map<String, String> _texts;
  final _bundle = AssetSource.bundle();

  @override
  Future<String> loadText(AssetPath path) async =>
      _texts[path] ?? await _bundle.loadText(path);

  @override
  Future<Image> loadImage(AssetPath path) => _bundle.loadImage(path);
}
