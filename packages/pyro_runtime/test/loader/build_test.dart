import 'dart:convert';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro_runtime/pyro_runtime.dart';

import '../support/images.dart';
import '../support/loader_fixtures.dart';
import '../support/scene_text.dart';
import '../support/test_registry.dart';

Future<PyroScene> _load(String scene) async => PyroScene.load(
  scenePath,
  registry: testRegistry,
  assets: await sourceFor(scene),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> printed;
  late DebugPrintCallback original;

  setUp(() {
    allFieldsLoads.clear();
    printed = [];
    original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
  });

  tearDown(() => debugPrint = original);

  testWithFlameGame('a root-only Scene loads with no children', (game) async {
    final scene = await _load(sceneJson([RootNode(id: const NodeId('root'))]));
    await game.ensureAdd(scene);
    expect(scene.children, isEmpty);
    expect(scene.path, scenePath);
  });

  group('US1', () {
    testWithFlameGame('#1 the tree mirrors childIds with the right '
        'components', (game) async {
      final scene = await _load(allKindsScene());
      await game.ensureAdd(scene);
      await game.ready();

      expect(
        [for (final c in scene.children) c.runtimeType],
        [PyroEntity, Player],
      );
      final goblin = scene.children.first;
      expect(
        [for (final c in goblin.children) c.runtimeType],
        [AllFields, AllFields, SpriteComponent, RectangleHitbox],
      );
      expect(scene.children.last.children.single, isA<CircleHitbox>());
    });

    testWithFlameGame('#2 transforms, named and custom anchors', (game) async {
      final scene = await _load(allKindsScene());
      final goblin = scene.find<PyroEntity>('goblin_1');
      expect(goblin.position, Vector2(320, 128));
      expect(goblin.size, Vector2(32, 32));
      expect(goblin.scale, Vector2(2, 1));
      expect(goblin.angle, 0.5);
      expect(goblin.anchor, Anchor.center);
      final player = scene.find<Player>('player');
      expect(player.position, Vector2(64, 128));
      expect(player.size, Vector2(32, 48));
      expect(
        scene.find<CircleHitbox>('sensor').anchor,
        const Anchor(0.25, 0.75),
      );
    });

    testWithFlameGame('#3 a sprite shows its region', (game) async {
      final scene = await _load(allKindsScene());
      final sprite = scene.find<SpriteComponent>('sprite').sprite!;
      expect(sprite.image.width, 64);
      expect(sprite.srcPosition, Vector2(32, 0));
      expect(sprite.srcSize, Vector2(32, 32));
    });

    testWithFlameGame('#3 a sprite without a region shows the whole image', (
      game,
    ) async {
      final scene = await _load(
        sceneJson([
          RootNode(id: const NodeId('root'), childIds: const [NodeId('s')]),
          SpriteNode(
            id: const NodeId('s'),
            name: 's',
            transform: at(0, 0, w: 64, h: 32),
            image: const AssetPath(sheet),
          ),
        ]),
      );
      final sprite = scene.find<SpriteComponent>('s');
      expect(sprite.sprite!.srcSize, Vector2(64, 32));
      expect(sprite.size, Vector2(64, 32));
    });

    testWithFlameGame('#4 hitbox props', (game) async {
      final scene = await _load(allKindsScene());
      await game.ensureAdd(scene);
      final rect = scene.find<RectangleHitbox>('body');
      expect(rect.position, Vector2(4, 2));
      expect(rect.size, Vector2(24, 30));
      expect(rect.angle, 0.25);
      expect(rect.anchor, Anchor.bottomCenter);
      expect(rect.collisionType, CollisionType.passive);
      expect(rect.isSolid, isTrue);
      final circle = scene.find<CircleHitbox>('sensor');
      expect(circle.radius, 40.5);
      expect(circle.position, Vector2(10, 20));
      expect(circle.collisionType, CollisionType.inactive);
      expect(circle.isSolid, isFalse);
    });

    testWithFlameGame('#5 Behaviors in Scene order, the same type twice', (
      game,
    ) async {
      final scene = await _load(allKindsScene());
      await game.ensureAdd(scene);
      final behaviors = scene
          .find<PyroEntity>('goblin_1')
          .findBehaviors<AllFields>()
          .toList();
      expect([for (final b in behaviors) b.count], [1, 2]);
    });

    testWithFlameGame('#6 every Field type, and defaults without an Override', (
      game,
    ) async {
      final scene = await _load(allFieldsScene());
      final holder = scene.find<PyroEntity>('holder');
      await game.ensureAdd(scene);
      final fields = holder.findBehavior<AllFields>();
      expect(fields.count, 4);
      expect(fields.speed, 80.0);
      expect(fields.active, isFalse);
      expect(fields.label, 'hello');
      expect(fields.mode, Mode.b);
      expect(fields.direction, Vector2(0, -1));
      expect(fields.tint, const Color(0xFF8800AA));
      expect(fields.icon, const ImagePath('assets/images/icon.png'));
      expect(fields.sprite!.srcSize, Vector2(64, 32));
      expect(fields.effect!.frames, hasLength(2));
      expect([for (final f in fields.effect!.frames) f.stepTime], [0.4, 0.2]);
      expect(fields.effect!.loop, isFalse);
      expect(fields.effect!.frames[1].sprite.srcPosition, Vector2(32, 0));
      expect(fields.target, same(scene.find<Player>('player')));
      expect(fields.maybe, isNull);

      final defaults = await _load(allFieldsScene(fields: const {}));
      final plain = defaults.find<PyroEntity>('holder');
      await game.ensureAdd(defaults);
      final untouched = plain.findBehavior<AllFields>();
      expect(untouched.count, 1);
      expect(untouched.direction, Vector2(1, 0));
      expect(untouched.maybe, 7);
      expect(defaults.find<Player>('player').maxHealth, 3);
    });

    testWithFlameGame('#7 onLoad sees every Override, asset and reference, '
        'parents first', (game) async {
      final scene = await _load(allFieldsScene());
      expect(allFieldsLoads, isEmpty, reason: 'nothing loads before mounting');
      await game.ensureAdd(scene);
      await game.ready();
      final seen = allFieldsLoads.single;
      expect(seen['count'], 4);
      expect(seen['sprite'], isA<Sprite>());
      expect(seen['effect'], isA<SpriteAnimation>());
      expect(seen['target'], isA<Player>());
      expect(seen['parentLoaded'], isTrue);
    });

    testWithFlameGame('#8 forward, root and self references', (game) async {
      final forward = await _load(referenceScene('b'));
      expect(
        forward.find<PyroEntity>('a').findBehavior<AllFields>().target,
        same(forward.find<PyroEntity>('b')),
      );
      final root = await _load(referenceScene('root'));
      expect(
        root.find<PyroEntity>('a').findBehavior<AllFields>().target,
        same(root),
      );
      final self = await _load(referenceScene('a'));
      final a = self.find<PyroEntity>('a');
      expect(a.findBehavior<AllFields>().target, same(a));
    });

    testWithFlameGame('#8 a reference cycle', (game) async {
      final scene = await _load(
        sceneJson([
          RootNode(
            id: const NodeId('root'),
            childIds: const [NodeId('a'), NodeId('b')],
          ),
          for (final (id, other) in [('a', 'b'), ('b', 'a')])
            EntityNode(
              id: NodeId(id),
              name: id,
              transform: at(0, 0),
              behaviors: [
                BehaviorAttachment(
                  type: const TypeId('AllFields'),
                  fields: Overrides({
                    'target': {'ref': other},
                  }),
                ),
              ],
            ),
        ]),
      );
      final a = scene.find<PyroEntity>('a');
      final b = scene.find<PyroEntity>('b');
      expect(a.findBehavior<AllFields>().target, same(b));
      expect(b.findBehavior<AllFields>().target, same(a));
    });

    testWithFlameGame('#9 a repaired Scene loads, with one repair warning', (
      game,
    ) async {
      // "b" is listed under both "root" and "a"; the reader keeps the first.
      const damaged = '''
{"schemaVersion": 1, "rootId": "root", "nodes": {
  "root": {"kind": "root", "childIds": ["a", "b"]},
  "a": {"kind": "entity", "name": "a", "childIds": ["b"], "transform":
    {"anchor": "topLeft", "angle": 0, "position": [0, 0], "scale": [1, 1], "size": [0, 0]}},
  "b": {"kind": "entity", "name": "b", "transform":
    {"anchor": "topLeft", "angle": 0, "position": [0, 0], "scale": [1, 1], "size": [0, 0]}}
}}''';
      final scene = await _load(damaged);
      expect(scene.findAll<PyroEntity>(), hasLength(2));
      // The Runtime's own `[pyro] Scene loaded` report aside (spec 007).
      final warnings = printed.where((p) => !p.startsWith('[pyro] Scene '));
      expect(warnings, hasLength(1));
      expect(warnings.single, contains(scenePath));
      expect(warnings.single, contains('repaired'));
    });

    testWithFlameGame('#10 two loads are independent', (game) async {
      final first = await _load(allKindsScene());
      final second = await _load(allKindsScene());
      expect(
        first.find<Player>('player'),
        isNot(same(second.find<Player>('player'))),
      );
      await game.ensureAddAll([first, second]);
      expect(game.children.whereType<PyroScene>(), hasLength(2));
    });
  });

  group('US5', () {
    test('#1 the bundle and a memory source get the same project-relative '
        'paths', () async {
      final memory = await sourceFor(allFieldsScene());
      await PyroScene.load(scenePath, registry: testRegistry, assets: memory);
      final bundle = _RecordingBundle(memory.texts, await makePng(64, 32));
      await PyroScene.load(
        scenePath,
        registry: testRegistry,
        assets: AssetSource.bundle(bundle),
      );
      expect(bundle.keys.toSet(), {
        ...memory.textReads.keys,
        ...memory.imageReads.keys,
      });
      expect(bundle.keys, everyElement(startsWith('assets/')));
    });

    test("#2 a caller's source is the only thing read", () async {
      final source = await sourceFor(allKindsScene());
      await PyroScene.load(scenePath, registry: testRegistry, assets: source);
      expect(Flame.images.containsKey(sheet), isFalse);
    });

    test('#3 an image used by several Nodes and fields is read once', () async {
      final source = await sourceFor(
        sceneJson([
          RootNode(id: const NodeId('root'), childIds: const [NodeId('e')]),
          EntityNode(
            id: const NodeId('e'),
            name: 'e',
            transform: at(0, 0),
            childIds: const [NodeId('s1'), NodeId('s2'), NodeId('s3')],
            behaviors: [
              BehaviorAttachment(
                type: const TypeId('AllFields'),
                fields: Overrides(const {
                  'sprite': {'asset': sheet},
                  'effect': {'asset': fxAnim, 'animation': 'walk'},
                }),
              ),
            ],
          ),
          for (final id in ['s1', 's2', 's3'])
            SpriteNode(
              id: NodeId(id),
              name: id,
              transform: at(0, 0),
              image: const AssetPath(sheet),
            ),
        ]),
      );
      await PyroScene.load(scenePath, registry: testRegistry, assets: source);
      expect(source.imageReads, {sheet: 1});
    });

    testWithFlameGame('a Hot-swap decodes no image again (Q72)', (game) async {
      final memory = await sourceFor(allKindsScene());
      final bundle = _RecordingBundle(memory.texts, await makePng(64, 32));
      final scene = await PyroScene.load(
        scenePath,
        registry: testRegistry,
        assets: AssetSource.bundle(bundle),
      );
      await game.ensureAdd(scene);
      memory.texts[scenePath] = allKindsScene().replaceFirst('320', '321');
      game.onHotReload();
      await scene.pendingCheck;
      expect(scene.find<PyroEntity>('goblin_1').position.x, 321);
      expect(bundle.keys.where((k) => k == sheet), hasLength(1));
    });
  });
}

/// A bundle serving [texts] and one PNG for every other key, recording
/// each key read.
final class _RecordingBundle extends CachingAssetBundle {
  _RecordingBundle(this.texts, this.png);

  final Map<String, String> texts;
  final Uint8List png;
  final List<String> keys = [];

  @override
  Future<ByteData> load(String key) async {
    keys.add(key);
    final text = texts[key];
    return text == null
        ? ByteData.sublistView(png)
        : ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}
