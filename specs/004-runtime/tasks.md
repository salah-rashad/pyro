---

description: "Task list for the Runtime (#8): PyroScene loading, lookups, assets and Hot-swap in pyro_runtime, plus the Registry and AssetRef amendments"
---

# Tasks: Runtime

**Input**: Design documents from `specs/004-runtime/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: included. Constitution Principle V makes the runtime loader a **Heavy** test layer, and
Phase 2's done-when is the Runtime loading fixture Scenes with a hand-written Registry in
`flame_test`. Within each phase, write the tests first and see them fail before implementing.

**Organization**: tasks are grouped by user story so each story can be built and checked on its
own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: the user story the task belongs to (US1–US5)

## Path Conventions

All paths are relative to the repository root. Shortened below:

- `rt/` = `packages/pyro_runtime/`
- `gen/` = `packages/pyro_generator/`
- `game/` = `packages/pyro_generator/fixture_game/`

Run commands with Flutter 3.44.2 on the path. Runtime tests: `cd packages/pyro_runtime && flutter
test`. Generator tests: `cd packages/pyro_generator && dart test`; regenerate goldens after an
intended change with `PYRO_UPDATE_GOLDENS=1 dart test test/golden_test.dart`, then review `git
diff test/goldens`. Fixture game: `cd packages/pyro_generator/fixture_game && dart run
build_runner build -d && flutter test`.

**Messages** (used throughout): every `SceneLoadException` and every debug warning starts with
the Scene's asset path, then names the Node as `"<name>" (<id>)` (or `(<id>)` when unnamed), then
`<TypeId>.<field>` where they apply, as in
[contracts/runtime-api.md § Errors](contracts/runtime-api.md#errors). Tests check these parts with
`contains`, not whole strings, so wording can improve without rewriting tests.

---

## Implementation notes

Deviations found while implementing, each also reflected in the code's comments:

- **Fixtures in code (T016, T024, T030):** loader fixtures are Dart builders in
  `rt/test/support/loader_fixtures.dart` written by `SceneCodec.encode`, not JSON files under
  `rt/test/fixtures/loader/`, so they are canonical by construction. Raw text appears inline only
  where a test needs malformed or damaged JSON.
- **Animation errors (T014, T018):** every broken rule of an animation file, a newer
  `schemaVersion` included, is the new `InvalidAnimationFile` (a `SceneFormatException`), because
  `UnsupportedSchemaVersion`'s message speaks of a Scene.
- **Image cache (T007, T008):** `AssetSource.bundle` keeps its own `Future<Image>` cache instead of
  Flame's `Images`: `Images.clear` on a failed load raises a second, unhandled error (spike #3
  finding 3).
- **Hitboxes need a positioned parent (T022):** Flame refuses a hitbox without a
  `PositionComponent` ancestor, so a hitbox directly under the root fails the load naming the Node
  (spec edge case added).
- **Open on the reference Mac:** only T043's timings and pause limit remain. T038's manual
  Hot-swap in a macOS app and T043's release-build check ran there in spec 005's run on
  `example/` (2026-10-22, ARCHITECTURE.md "Vertical slice / On the reference Mac"). Container
  (Linux, JIT) timings are in ARCHITECTURE.md "Runtime" as an early signal. #8's estimate is
  5 evenings, set by the author (Q116).
- **Behavior parent types (T010):** a Behavior whose parent type is private or unreachable is the
  new Generator error `unreachableParentType` (golden case `errors/unreachable_parent_type`).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: pin the Flame facts the design reads from source, and the test support every story
uses

- [X] T001 Write `rt/test/loader/flame_assumptions_test.dart`, one `testWithFlameGame` per fact research marks *read* (plan.md, Risks: "Read, not run"):
  1. a concrete subclass of `PositionedEntity` can be created and holds a `Behavior<PositionedEntity>`;
  2. `RectangleHitbox(position: Vector2(4, 2), size: Vector2(24, 30))` and `CircleHitbox(radius: 5, position: Vector2.zero())` keep their size and radius after being mounted under a 100×100 `PositionComponent` (no fill-parent);
  3. `game.onHotReload()` calls `onHotReload` on a mounted child and on a child added but not yet loaded, and not on a component that was never added;
  4. children `add`ed to a component before it is added to the game run `onLoad` only after that component is added, parents before children;
  5. after `removeFromParent` and one `game.update(0)`, a component's `mounted` future completes when it is added again;
  6. a listener on a `PositionComponent`'s `transform` is called when `position.x` changes, and isn't called by `removeFromParent` alone;
  7. `SpriteAnimation.spriteList` and `SpriteAnimation.variableSpriteList` build animations with the given step times and `loop`;
  8. `Images(prefix: '', bundle: b).load('assets/images/a.png')` asks `b` for exactly `assets/images/a.png`.

  If any fact fails, stop and update research.md (R3, R4, R7, R8, R11 or R12) and the affected tasks before going on.
- [X] T002 [P] Write the test support in `rt/test/support/`:
  - `images.dart`: `Future<Image> makeImage(int width, int height)` via `PictureRecorder` → `toImage`, filled with one colour;
  - `memory_asset_source.dart`: `MemoryAssetSource implements AssetSource`, holding `Map<String, String> texts` and `Map<String, Image> images` (both mutable, so Hot-swap tests can change them). It counts every call (`textReads`, `imageReads`, each a `Map<String, int>`) and throws `FlutterError('Unable to load asset: "<path>"')` for an unknown path, as `rootBundle` does;
  - `scene_text.dart`: `String sceneJson({...})`, small builders that write Scene JSON for tests through `SceneCodec.encode`, so tests never hand-write canonical form.

  `AssetSource` itself comes in T008. Write this file against the contract and let it compile once T008 lands.
- [X] T003 [P] Add `packages/pyro_generator/fixture_game/assets/** -text` to `.gitattributes`, under the spec 003 comment, extended with "and the fixture game's Scene and animation files (spec 004)". Create `rt/test/fixtures/loader/` with a `README.md`: one line per fixture saying which acceptance scenario it serves, filled in as fixtures are added

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the two contract amendments, the error type, the asset source, the hand-written
Registry, and a `PyroScene.load` that loads a root-only Scene

**⚠️ CRITICAL**: no user story work can begin until this phase is complete

### Tests for the foundation

- [X] T004 [P] Extend `rt/test/scene/overrides_test.dart` for T009 (FR-034, research R13):
  - `AssetRef.fromJson` accepts `{"asset": "a.png"}` (`animation` null) and `{"asset": "a.anim.json", "animation": "walk"}`;
  - it returns null for an empty `animation`, a non-string `animation`, a third key, `{"animation": "walk"}` alone, and an empty `asset`;
  - `toJson` writes `animation` only when set;
  - equality and `hashCode` include `animation`.

  Add to `rt/test/scene/round_trip_test.dart` a fixture whose Behavior holds `{"animation": "walk", "asset": "assets/anims/goblin.anim.json"}` and round-trips byte for byte, plus one whose value has a third key and stays a plain JSON value.
- [X] T005 [P] Extend `rt/test/loader/registry_test.dart` for T010 (research R6):
  - a Behavior `RegistryType` keeps its `acceptsParent` and it is called as given;
  - `PyroRegistry` throws an `ArgumentError` naming the Type ID for a Behavior without `acceptsParent`, and for a Custom component with one.
- [X] T006 [P] Write `rt/test/loader/load_exception_test.dart` for T011:
  - `toString()` starts with the Scene path and includes the Node as `"name" (id)`, the `TypeId.field`, the asset path, the message, and the cause's `toString()` on its own line;
  - it omits every part that is null.
- [X] T007 [P] Write `rt/test/assets/asset_source_test.dart` for T008 with a fake `AssetBundle` that records each key and `cache` flag:
  - `AssetSource.bundle(fake).loadText('assets/scenes/a.scene.json')` asks for that exact key with `cache: false`;
  - `loadImage('assets/images/a.png')` asks for that exact key (no `assets/images/` prefix), and returns the same `Image` on a second call without a second bundle read;
  - an image load that fails rethrows, and a second call reads the bundle again (the failure isn't cached);
  - `AssetSource.bundle()` with no argument uses `rootBundle`, checked by identity through a `@visibleForTesting` getter.

### Implementation for the foundation

- [X] T008 [P] Implement `rt/lib/src/assets/asset_source.dart` per [contracts/runtime-api.md § Assets](contracts/runtime-api.md#assets) and research R8:
  - `abstract interface class AssetSource` with `loadText` and `loadImage`;
  - `factory AssetSource.bundle([AssetBundle? bundle])` returning a private `_BundleAssetSource`. It resolves `final b = bundle ?? rootBundle;` once and uses `b` for both: text with `b.loadString(path, cache: false)` and images through its own `Images(prefix: '', bundle: b)`, never `Flame.bundle`. When `Images.load` throws, it calls `images.clear(path)` before rethrowing.

  Document that the source owns its images. Make T007 pass.
- [X] T009 Amend `AssetRef` in `rt/lib/src/scene/overrides.dart` per [contracts/runtime-api.md § Amended: AssetRef](contracts/runtime-api.md#amended-assetref-spec-001-contract):
  - add `const AssetRef(this.path, {this.animation})`;
  - `fromJson` accepts exactly the two shapes;
  - `toJson`, `==`, `hashCode` and `toString` include `animation`;
  - check that the canonical writer needs no change (keys are sorted already).

  In the same commit, update the Field type table in `specs/001-scene-format/contracts/scene-file-v1.md` (a `SpriteAnimation` row with `{"asset": path, "animation": name}`, the asset row limited to `ImagePath` and `Sprite`, and under "Reading rules" that a colour's hex digits are accepted in either case and written upper case), the written-form table in `specs/003-generator/research.md` R5 (the `spriteAnimation` row), and project-plan §7.1's "Override values" bullet, each with "(spec 004, FR-034)". Make T004 pass.
- [X] T010 Add `acceptsParent` to `RegistryType` in `rt/lib/src/loader/registry.dart` per [contracts/runtime-api.md § Amended: RegistryType](contracts/runtime-api.md#amended-registrytype-spec-003-contract), with `PyroRegistry`'s two new `ArgumentError` checks. In the same commit:
  - in `gen/lib/src/registry_emitter.dart`, emit `acceptsParent: (parent) => parent is <T>,` for every Behavior, where `<T>` is the Behavior's type argument written with the same import prefix the emitter uses for field types, or `EntityMixin` from `flame_behaviors` when the Behavior has no type argument or uses `EntityMixin`. Add `flame_behaviors` to the Registry's imports when it is needed;
  - regenerate the goldens (`PYRO_UPDATE_GOLDENS=1`) and review that the only change is the added line;
  - run `dart run build_runner build -d` in `game/` to regenerate `game/lib/pyro.g.dart`;
  - update `specs/003-generator/contracts/registry-api.md` to match.

  Make T005 pass and keep `gen/` and `game/` tests green.
- [X] T011 [P] Implement `rt/lib/src/loader/load_exception.dart`: `final class SceneLoadException implements Exception` with exactly the fields of [contracts/runtime-api.md § Errors](contracts/runtime-api.md#errors) (`scene`, `nodeId`, `nodeName`, `typeId`, `field`, `asset`, `message`, `cause`, `causeStackTrace`) and the `toString` of T006. Make T006 pass.
- [X] T012 Write `rt/test/support/test_registry.dart`, a hand-written `PyroRegistry testRegistry` (research R15) over small test classes in the same file:
  - **Behaviors:**
    - `AllFields extends Behavior<PositionedEntity>` with one Editable-style public field per Field type: `int count = 1`, `double speed = 50`, `bool active = true`, `String label = 'x'`, `Mode mode = Mode.a` (`enum Mode { a, b }`), `Vector2 direction = Vector2(1, 0)`, `Color tint = const Color(0xFFFFFFFF)`, `ImagePath icon = const ImagePath('assets/images/default.png')`, `Sprite? sprite`, `SpriteAnimation? effect`, `Component? target`, and a nullable `int? maybe`. It records `onLoad` calls and the field values seen in `onLoad` into a static log;
    - `EnemyOnly extends Behavior<Enemy>`;
    - `Throwing`, whose constructor throws `StateError('boom')`.
  - **Custom components:**
    - `Player extends PositionedEntity` with `int maxHealth = 3`, `Color tint = const Color(0xFFFF8800)`;
    - `Enemy extends PositionedEntity`;
    - `Plain extends PositionComponent` (no `EntityMixin`);
    - `BadSetter extends PositionComponent`, whose field setter throws.

  Each `RegistryType` has `accepts` and `set` written as the Generator would, and `acceptsParent` for Behaviors.
- [X] T013 Implement the loader skeleton:
  - `rt/lib/src/loader/built_scene.dart`: `BuiltScene`, `NodeEntry` and the internal `SkippedItem` and `UnusedOverride` records per [data-model.md § BuiltScene](data-model.md#builtscene-internal), with `path` for messages (names from the root joined by `/`, `#<id>` for an unnamed Node);
  - `rt/lib/src/loader/pyro_scene.dart`: `UnknownType`, `SceneReloaded` and `final class PyroScene extends Component`, with a private constructor and `static Future<PyroScene> load(String path, {required PyroRegistry registry, UnknownType onUnknownType = UnknownType.error, SceneReloaded? onReloaded, AssetSource? assets})`. `load`:
    1. reads the text through the source (`AssetSource.bundle()` when none is given);
    2. decodes it with `SceneCodec.decode`;
    3. calls `warnAboutRepairs(path, result.repairs)`;
    4. builds a root-only `BuiltScene`.

    A failure to read or decode becomes a `SceneLoadException` with `cause` set (US2 #11). `path` returns the `AssetPath`.
  - `rt/lib/pyro_runtime.dart`: export `PyroScene`, `UnknownType`, `SceneReloaded`, `AssetSource` and `SceneLoadException`, and update the library doc comment, which still says the loader "lands with v0.1 work item 8".

  Add one test to `rt/test/loader/build_test.dart`: a root-only Scene loads, has no children and mounts in a `FlameGame`.

**Checkpoint**: `flutter test` passes in `rt/`; `dart test` passes in `gen/`; `game/`'s committed
Registry is current and its tests pass

---

## Phase 3: User Story 1 - Load a Scene into a game (Priority: P1) 🎯 MVP

**Goal**: every built-in Node kind, Custom components, Behaviors and every v1 Field type load
through the four passes, so every `onLoad` sees configured fields

**Independent Test**: in a headless Flame test game, load fixture Scenes covering every Node kind
and every Field type with the hand-written Registry. Check the component tree, every built-in
property and every field value (spec US1)

### Tests for User Story 1

- [X] T014 [P] [US1] Write `rt/test/animation/animation_file_test.dart` for T018–T019, one case per rule of [contracts/anim-file-v1.md](contracts/anim-file-v1.md):
  - §7.2's example reads;
  - `offset` and `spacing` default to `[0, 0]`, and `loop` to `true`;
  - refused: a newer `schemaVersion` (`UnsupportedSchemaVersion` naming 1), duplicate keys (with line and column), missing `image`, `grid.cellSize` or `animations`, an empty `animations`, empty `frames`, a negative frame, both or neither of `stepTime` and `stepTimes`, `stepTimes` of the wrong length, a step time ≤ 0, a `cellSize` ≤ 0;
  - unknown keys are ignored;
  - frame → cell: on a 100×64 image with `cellSize [32, 32]`, `offset [2, 0]` and `spacing [1, 0]`, there are 3 columns, frame 4 is at (35, 32), and frame 6 is out of range (an error naming the file, the animation and the frame);
  - `toSpriteAnimation` gives each frame its `srcPosition`, `srcSize` and step time.
- [X] T015 [P] [US1] Write `rt/test/loader/field_values_test.dart` for T020, one group per row of [research R5](research.md#r5-converting-override-values) against `testRegistry`'s `AllFields` fields:
  - **accepted:** `80` and `80.5` for `double`; `2` and `2.0` for `int`; enum names; `[1, 0]` for `Vector2`; `"#FFFF8800"` and `"#ffff8800"` for `Color` (both → `Color(0xFFFF8800)`); `{"asset": …}` for `ImagePath` (an `ImagePath`, nothing loaded); `null` for a nullable field;
  - **mismatches:** `1.5` for `int`, `"x"` for `bool`, `"c"` for `Mode`, `[1]`, `[1, "a"]`, `"#FF8800"`, `"FFFF8800"`, `null` for `count`, `{"asset": …, "animation": …}` for `Sprite`, `{"asset": …}` for `SpriteAnimation`. Each one's mismatch names the field, the written value (cut at 80 characters with `…`) and the expected Field type.
- [X] T016 [US1] Add fixtures under `rt/test/fixtures/loader/`, written with `scene_text.dart` where possible and listed in its README:
  - `all_kinds.scene.json`: root → entity `goblin_1` (`Patrol`-like `AllFields` Behavior, tag `enemy`) → sprite with region, and a rectangle hitbox with every prop; a circle hitbox with a custom anchor `[0.25, 0.75]`; a Custom `Player` with `maxHealth` and `tint` Overrides;
  - `all_fields.scene.json`: one entity with `AllFields` and an Override for every field, including `sprite`, `effect` (`assets/anims/fx.anim.json`, `walk`) and `target` → `player`;
  - `references.scene.json`: a forward reference, a reference to the root, a self reference and an A↔B cycle;
  - `repaired.scene.json`: an orphan and a Node under two parents (copy the damage pattern from `rt/test/scene/tree_repair_test.dart`);
  - `assets/anims/fx.anim.json` with `walk` and `idle`.
- [X] T017 [US1] Write `rt/test/loader/build_test.dart` (extending T013's file) for T020–T024, with a `MemoryAssetSource` serving the fixtures and `makeImage` images. One test per US1 acceptance scenario:
  1. the tree mirrors `childIds` order with the right component classes (`PyroEntity`, `SpriteComponent`, `RectangleHitbox`, `CircleHitbox`, `Player`);
  2. every transform (named and custom anchors);
  3. sprite with and without a region (`srcPosition`, `srcSize`);
  4. every hitbox prop (position, size or radius, angle, anchor, `collisionType`, `isSolid`);
  5. Behaviors attached in order, including the same type twice;
  6. every Field type's value, and a field without an Override keeps its default;
  7. `AllFields`' `onLoad` log shows every Override, loaded asset and resolved reference already set, and parents load before children;
  8. forward, root (`PyroScene`), self and cycle references;
  9. `repaired.scene.json` loads, and in debug a single repair warning is printed (capture `debugPrint`);
  10. two loads of the same Scene give two independent `PyroScene`s.

### Implementation for User Story 1

- [X] T018 [P] [US1] Implement `rt/lib/src/animation/animation_file.dart` (`AnimationFile`, `AnimationGrid`, `AnimationClip`, all immutable with `final` fields) and `rt/lib/src/animation/animation_codec.dart` (`AnimationCodec.decode(String text, {required String path})`) per [data-model.md § AnimationFile](data-model.md#animationfile-internal-modellibsrcanimation) and [contracts/anim-file-v1.md](contracts/anim-file-v1.md):
  - reuse `rt/lib/src/scene/json/strict_reader.dart` for duplicate keys and positions;
  - reuse `UnsupportedSchemaVersion` and `InvalidSchemaVersion` from `rt/lib/src/scene/errors.dart`, adding a `SceneFormatException` subclass only if no existing one fits a broken rule, documented like its siblings;
  - the rules are: "`frames` non-empty, each ≥ 0", "exactly one of `stepTime` (> 0) or `stepTimes` (each > 0, same length as `frames`)", "`loop` defaults to `true`", "`offset`, `spacing` default to `[0, 0]`, both ≥ 0", "`cellSize` both > 0".
- [X] T019 [US1] Implement `rt/lib/src/animation/sprite_sheet.dart`: `SpriteAnimation toSpriteAnimation(AnimationFile file, String name, Image image)`. It computes columns and rows as in [contracts/anim-file-v1.md § Frames](contracts/anim-file-v1.md#frames), throws a `RangeError`-based error naming the file, the animation and the frame when a frame is out of range, and uses `SpriteAnimation.spriteList` or `.variableSpriteList` (research R7). Make T014 pass.
- [X] T020 [P] [US1] Implement `rt/lib/src/loader/field_values.dart`: a pure `FieldConversion convert(RegistryField field, Object? written)` returning a value, a deferred request (asset: `(path, animation?)`; reference: `NodeId`) or a mismatch with its message parts, per research R5. Accept colours with `RegExp(r'^#[0-9A-Fa-f]{8}$')`. Make T015 pass.
- [X] T021 [P] [US1] Implement `rt/lib/src/loader/pyro_entity.dart` (`class PyroEntity extends PositionedEntity`, constructor per [contracts/runtime-api.md](contracts/runtime-api.md#built-in-node-components), documented as the `entity` Node's component) and `rt/lib/src/loader/builtin_nodes.dart`, which maps each built-in kind to its complete component per research R3:
  - `Anchor` from `NodeAnchor` (a named anchor → the Flame constant of the same name, custom → `Anchor(x, y)`);
  - `CollisionType` from `NodeCollisionType` by name;
  - `Vector2` from `Vec2`;
  - hitboxes always get an explicit position and size or radius;
  - a sprite Node gets a `SpriteComponent` with its transform and no sprite, plus a helper that pass 2 calls with the loaded image to set `Sprite(image, srcPosition:, srcSize:)` (research R3).
- [X] T022 [US1] Implement `rt/lib/src/loader/scene_builder.dart`, the four passes of [research R4](research.md#r4-the-four-pass-build) for the success path. It takes a decoded `Scene`, a `PyroRegistry`, an `AssetSource`, an `UnknownType`, the Scene's `AssetPath` and a required `Component root` (the `PyroScene` the build is for), and returns a `BuiltScene`:
  1. **construct:** depth first in `childIds` order. Built-in kinds come from T021; `custom` Nodes and Behaviors are created through `RegistryType.create()`. Collect `AssetRequest`s deduplicated by path, noting the first Node and field that asked;
  2. **configure:** `Future.wait` over every request (images by `loadImage`; animation files by `loadText` + `AnimationCodec.decode` + `loadImage` of their `image`, each file parsed once). Record each text read in `texts`. Then set each sprite Node's `sprite` (T021's helper), Custom components' transforms and every non-reference Override via T020 and `RegistryField.set`;
  3. **resolve:** set reference Overrides from `componentsById` (the root → the `root` argument);
  4. **attach:** `add` Behaviors and children in Scene order, then build `entries` in tree order.

  Error paths stay minimal here (throw `SceneLoadException` with the message parts available); US2 completes them.
- [X] T023 [US1] Wire T022 into `PyroScene.load` in `rt/lib/src/loader/pyro_scene.dart`: build first, then create the `PyroScene` and `addAll(built.children)`. `componentsById[rootId]` must be the returned `PyroScene`, so create the instance first, pass it as `root`, and keep it private until `load` completes. Export `PyroEntity` from `rt/lib/pyro_runtime.dart`, and re-export `Behavior` and `EntityMixin` from `flame_behaviors` (contracts/runtime-api.md, Exports). Make T017 pass.

**Checkpoint**: Phase 2 of phases.md's done-when for the Runtime holds: every fixture Scene loads in
`flame_test` with the hand-written Registry (SC-001)

---

## Phase 4: User Story 2 - Clear errors when code and Scene disagree (Priority: P1)

**Goal**: every drift between code and Scene fails or warns with the Scene, Node and type, field or
path named; `UnknownType.skip` keeps a game running through a refactor

**Independent Test**: load one fixture Scene per error case with the hand-written Registry. Check
what each load does (error, skip or warning) and that each message names the Scene, the Node and
the type, field or path involved (spec US2)

### Tests for User Story 2

- [X] T024 [P] [US2] Add one fixture per US2 scenario under `rt/test/fixtures/loader/errors/` (listed in the README):
  - `unknown_behavior`, `unknown_custom` (with a child and a grandchild), `unknown_kind`, `role_mismatch` (a Behavior Type ID on a `custom` Node);
  - `bad_value_int` (`1.5`), `bad_value_bool`, `bad_value_enum`, `bad_value_color`, `null_non_nullable`, `unused_override`;
  - `missing_ref`, `wrong_ref_type` (a `Player?`-typed field pointing at a sprite), `ref_to_skipped`;
  - `missing_image`, `missing_anim_file`, `bad_anim_file`, `unknown_animation`, `anim_without_name`;
  - `behavior_on_plain` (Behaviors on `Plain`), `wrong_parent` (`EnemyOnly` on a `Player`);
  - `malformed` (bad JSON), `newer_schema` (`schemaVersion: 2`);
  - `throwing_constructor`, `throwing_setter`.
- [X] T025 [P] [US2] Write `rt/test/loader/errors_test.dart` for T027–T029. For each fixture of T024 except the `unknown_*` and `unused_override` ones, `PyroScene.load` throws a `SceneLoadException` whose fields and `toString` name:
  - the Scene path;
  - the Node (name and ID);
  - the Type ID, field and asset path where the scenario has them;
  - for `unknown_animation`, the animations the file holds;
  - for `malformed`, `newer_schema` and the throwing ones, a `cause` of the original type with a non-null `causeStackTrace`.

  Also: `missing scene file` (no text in the source) fails naming the path (US2 #11). Then lossless conversion loads silently (US2 #5).
- [X] T026 [P] [US2] Write `rt/test/loader/unknown_type_test.dart` for T027–T028, covering US2 #1–#3, #6 and #8:
  - with the default policy, `unknown_behavior`, `unknown_custom` and `unknown_kind` fail naming the Type ID or kind and mentioning `UnknownType.skip`, and `role_mismatch` fails under both policies;
  - with `UnknownType.skip`:
    - the unknown Behavior is gone and its Node stays;
    - the unknown Custom component's whole subtree is gone, and lookups don't find its children;
    - the unknown kind's subtree is gone;
    - `ref_to_skipped`'s field is `null`;
    - exactly one debug warning lists every skipped Node, Behavior and reference (capture `debugPrint`);
  - `unused_override` loads under both policies with one debug warning naming the Scene, Node, Type ID and field.

### Implementation for User Story 2

- [X] T027 [US2] Complete pass 1 in `rt/lib/src/loader/scene_builder.dart` per [research R9](research.md#r9-unknown-type-ids-and-node-kinds):
  - unknown Type IDs and `UnknownNode` kinds throw under `UnknownType.error` with the message of contracts/runtime-api.md (the first example), and under `skip` are recorded as `SkippedItem`s (a Behavior alone; a Node with its whole subtree, so pass 1 doesn't descend into it);
  - role mismatches always throw (FR-007);
  - constructor errors are caught per Node and rethrown with `typeId` and the cause (FR-018).
- [X] T028 [US2] Implement `rt/lib/src/loader/load_warnings.dart`: `void warnAboutSkipped(AssetPath scene, List<SkippedItem> items)` and `void warnAboutUnusedOverrides(AssetPath scene, List<UnusedOverride> items)`, in `rt/lib/src/loader/repair_warning.dart`'s style (`if (!kDebugMode || items.isEmpty) return;`, one `debugPrint` with a `══ … ══` header line). Record skipped references in pass 3 and unused Overrides in pass 2. Call both from `PyroScene.load` after a successful build. Make T026 pass.
- [X] T029 [US2] Complete every other error path in `rt/lib/src/loader/scene_builder.dart` so T025 passes:
  - **pass 2:** asset errors with `asset` and the first requesting Node and field; animation-file errors wrapped with the file path; an unknown or missing animation name listing the file's animations (sorted); value mismatches from T020; setter errors caught per field;
  - **pass 3:** a missing target (`missing_ref`), or a target the field's `accepts` rejects (`wrong_ref_type`), naming the target's Node ID;
  - **pass 4:** Behaviors on a component that isn't an `EntityMixin`, and `acceptsParent` rejecting the Node's component (FR-008), naming the Behavior's Type ID.

  Check that no failed load leaves a component in any game: in `errors_test.dart`, add each fixture's `PyroScene.load` future to a test game and assert `game.children` is empty afterwards (FR-004).

**Checkpoint**: every fixture under `errors/` behaves as its scenario says (SC-002)

---

## Phase 5: User Story 3 - Find Nodes from game code (Priority: P1)

**Goal**: `find` and `findAll` by name, path, tag and type, before or after mounting, with
errors that say what matched

**Independent Test**: load a fixture Scene with repeated names, tags and nested paths, then call
every lookup form and check its results and its errors (spec US3)

### Tests for User Story 3

- [X] T030 [P] [US3] Add `rt/test/fixtures/loader/lookups.scene.json`:
  - root → `arena` → `boss` (`Enemy`), and root → `cave` → `boss` (`Enemy`);
  - `player` (`Player`) at the top level;
  - three entities tagged `enemy` at different depths, one of them unnamed;
  - a Node named `a/b` (a name with `/`);
  - `arena` → `inner` → `boss` (`Enemy`), a third `boss` deeper under `arena`.

  Write `rt/test/loader/lookup_test.dart` for T031–T032, covering US3 #1–#6:
  - `find<Player>('player')`;
  - `find('boss')` throws listing all three `boss` paths and mentioning `findAll`;
  - `find('arena/boss')` returns `arena`'s direct child only, while `find('inner/boss')` returns the inner one;
  - `find('/arena/boss')` matches, and `find('/inner/boss')` doesn't;
  - `find('nobody')` names the Scene and the query;
  - `find<Player>('arena')` names `arena`'s type and `Player`;
  - `findAll(tag: 'enemy')` returns three in tree order, including the unnamed one;
  - `findAll<Enemy>(name: 'boss')` returns three;
  - `findAll(name: 'x')` returns empty;
  - `find('a/b')` doesn't find the Node named `a/b`, but `findAll` filtered by `tag` and `T` does (edge case);
  - every lookup works on the result of `load` before it is added to a game (US3 #6).

### Implementation for User Story 3

- [X] T031 [US3] Implement path matching in `rt/lib/src/loader/built_scene.dart` per [research R10](research.md#r10-lookups): `Iterable<NodeEntry> match({String? nameOrPath, String? tag})`. It splits on `/`, matches the last segment's name and then the nearest ancestors in order, and for a leading `/` requires the first segment's entry to have no `parent`. Unnamed entries never match a name.
- [X] T032 [US3] Add `find<T extends Component>(String nameOrPath)` and `findAll<T extends Component>({String? name, String? tag})` to `PyroScene` in `rt/lib/src/loader/pyro_scene.dart` per [contracts/runtime-api.md § Loading](contracts/runtime-api.md#loading). `find` throws a `StateError` for none, several (listing each match's `path`, and suggesting `findAll` or a longer path) or a type mismatch (naming the Node's runtime type and `T`). Ambiguity is decided by name alone, before `T` is checked. `findAll` returns a new `List<T>`. Make T030 pass.

**Checkpoint**: every lookup form behaves as US3 says (SC-005)

---

## Phase 6: User Story 4 - Hot-swap a saved Scene in the running game (Priority: P1)

**Goal**: in debug builds a mounted Scene rebuilds itself only when its file or animation files
changed, keeps running when the new content is broken, calls `onReloaded`, and warns about stale
references

**Independent Test**: in a headless Flame test, load a Scene, change the text its asset source
returns, trigger a hot reload and check the rebuild and the callback. Leave the text unchanged,
reload again and check that nothing was rebuilt (spec US4)

### Tests for User Story 4

- [X] T033 [P] [US4] Write `rt/test/loader/hot_swap_test.dart` for T035–T036. Each test mounts a Scene loaded from a `MemoryAssetSource`, changes `texts` (or not), calls `game.onHotReload()`, then awaits a `@visibleForTesting Future<void> get pendingCheck` on the `PyroScene` and `game.update(0)`:
  - **changed Scene** (US4 #1, #6): new components, the same `PyroScene` object in the same parent, `onReloaded` called once with it, and lookups return new components;
  - **unchanged** (US4 #2): no `onReloaded`, the same component objects, and `textReads` up by exactly one per file;
  - **changed animation file only** (US4 #3): rebuilds, and the new animation's step time is used;
  - **changed image only** (US4 #4): no rebuild;
  - **broken JSON, then an unknown Type ID, then a fixed file** (US4 #5): the first two keep the old components, print one debug error each naming the Scene and containing "couldn't Hot-swap", and don't call `onReloaded`; the third rebuilds;
  - **two `onHotReload` calls back to back with different texts:** checks don't overlap (a source whose `loadText` completes only when the test says so), and the Scene ends on the second text;
  - **a Scene loaded but never added** to the game: `game.onHotReload()` reads nothing;
  - **SC-003:** 100 reloads alternating changed and unchanged texts give exactly 50 rebuilds and 50 `onReloaded` calls.
- [X] T034 [P] [US4] Write `rt/test/loader/stale_reference_test.dart` for T037:
  - after a rebuild, changing a removed Node's `position` prints one warning naming the Scene, the Node (`"player" (9b2e)`) and `onReloaded`, and changing it again prints nothing more;
  - re-adding a removed component to the game prints one warning;
  - the swap itself, `removeFromParent` and `game.update` print nothing (plan.md, Risks: `Transform2D` listeners);
  - a component of the current version has no listener (`transform.hasListeners` is false, via a `@visibleForTesting` hook if `hasListeners` isn't public);
  - after a second rebuild, the first generation's components no longer warn, and the second generation's do;
  - removing the `PyroScene` from the game detaches every watcher.

### Implementation for User Story 4

- [X] T035 [US4] Implement the change check in `rt/lib/src/loader/hot_swap.dart` per [research R11](research.md#r11-hot-swap): `Future<bool> contentChanged(AssetSource source, Map<AssetPath, String> texts)`. It re-reads every path in `texts` through `source.loadText` and compares with `==`. A read failure counts as changed, so the rebuild reports it.
- [X] T036 [US4] Override `onHotReload` in `PyroScene` (`rt/lib/src/loader/pyro_scene.dart`):
  - call `super.onHotReload()`, then, only `if (kDebugMode)`, chain `_checkForChanges()` onto a private `Future<void> _pending` (expose it as `@visibleForTesting pendingCheck`);
  - `_checkForChanges`: if `contentChanged` (T035) finds no change, stop. Otherwise read and decode the Scene and run `SceneBuilder` with the kept Registry, policy and source and `root: this`, so root references resolve to the same instance;
  - on failure, `debugPrint` one error starting `══ Pyro couldn't Hot-swap <path> ══` with the cause and keep the current build (FR-026);
  - on success, swap synchronously: `removeAll` the old root children, `addAll` the new, replace the build (index, `texts`), warn about repairs, skips and unused Overrides as in `load`, start the stale watch (T037), then call `onReloaded?.call(this)`.

  Make T033 pass.
- [X] T037 [US4] Implement `StaleWatch` in `rt/lib/src/loader/hot_swap.dart` per [research R12](research.md#r12-stale-reference-warning) and [data-model.md § StaleWatch](data-model.md#stalewatch-internal-debug-only):
  - for each removed entry's component, once `component.removed` completes (research R12: before that, `mounted` is an already-completed future), it attaches a `transform` listener (only for `PositionComponent`s) and a `mounted.then` callback that checks the watch is still open;
  - `fire` prints `══ Pyro: <path> was Hot-swapped, but game code still uses Node "<name>" (<id>) from before ══`, followed by "Re-run lookups in onReloaded (PyroScene.load).", then detaches that Node;
  - `close()` detaches everything.

  `PyroScene` closes the previous watch before starting a new one and in `onRemove` (calling `super`). Every line of this code runs only under `kDebugMode`. Make T034 pass.
- [X] T038 [US4] On the reference Mac, run [quickstart.md](quickstart.md) §5 steps 1–3 in a throwaway macOS app (not committed) and note the results for T047. If it can't run in the implementing session, leave this task open and say so in the PR
  - *Spec 005:* folded into its reference-Mac run on `example/` (spec 005 T039, quickstart §5 steps 1–5), which closes this task when it runs.
  - Closed by that run (2026-10-22): a save swaps the Scene on macOS, a Dart-only reload leaves it alone; see ARCHITECTURE.md "Vertical slice / On the reference Mac".

**Checkpoint**: Hot-swap tests pass (SC-003); the manual run on macOS, if done, shows a saved Scene
rebuilding and a Dart-only reload leaving it alone

---

## Phase 7: User Story 5 - Same paths in Pyro and the game (Priority: P2)

**Goal**: every file a load reads goes through one asset source by project-relative path, each
image is decoded once per Scene, and a real game loads through its bundle

**Independent Test**: load the same fixture Scene with the default bundle-backed source and with a
memory source. Check that the same paths are requested and the same assets come back (spec US5)

### Tests for User Story 5

- [X] T039 [P] [US5] Add to `rt/test/loader/build_test.dart`:
  - loading `all_kinds.scene.json` through a `MemoryAssetSource` and through `AssetSource.bundle(fakeBundle)` (serving the same files) requests the same set of paths, all project-relative with no prefix (US5 #1);
  - with a caller's source, `Flame.images` and `Flame.assets` stay empty and `Flame.bundle` is never read (US5 #2; assert on their cache keys before and after);
  - a Scene with three sprites and a `Sprite` field on one image calls `loadImage` for it exactly once (US5 #3, FR-031);
  - after a Hot-swap rebuild, the image isn't loaded again (Q72).
- [X] T040 [P] [US5] Add `game/assets/scenes/fixture.scene.json`, `game/assets/images/sheet.png` (a 64×32 PNG, two 32×32 cells, generated once with a short script in the scratchpad and committed) and `game/assets/anims/sheet.anim.json`. The Scene uses `game/`'s real annotated types: an entity with one of its Behaviors and every Override that Behavior's fields allow, a sprite, a hitbox and a Custom component. Declare the three folders under `flutter: assets:` in `game/pubspec.yaml`. Write `game/test/load_test.dart`: `PyroScene.load('assets/scenes/fixture.scene.json', registry: pyroRegistry)` with the default source in a `testWithFlameGame`, checking a field value, a lookup and the sprite's image size (quickstart §3).

### Implementation for User Story 5

- [X] T041 [US5] Make T039 and T040 pass. Expected changes are small: request deduplication in pass 1 is T022's, and image ownership is T008's. Fix whatever T039 exposes in `rt/lib/src/loader/scene_builder.dart` or `rt/lib/src/assets/asset_source.dart`, and document on `PyroScene.load` that one bundle source is created per Scene and kept across Hot-swaps (research R8)

**Checkpoint**: all Runtime tests pass; `game/`'s load test passes with the real generated
Registry and `rootBundle`

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: the budgets measured, documentation in sync, final checks

- [X] T042 [P] Write `rt/benchmark/load_benchmark_test.dart` (SC-004, quickstart §4). Reuse the 1,000-Node Scene generator from `rt/benchmark/scene_codec_benchmark.dart`: move it to `rt/benchmark/support/benchmark_scene.dart` and import it from both, with entities, sprites on 10 distinct images, hitboxes, and Custom components and Behaviors from a small benchmark Registry. Use a `MemoryAssetSource` with pre-made images (so image decoding is excluded). Report the median and p95 of 20 runs each for `PyroScene.load`, a no-op Hot-swap check (`contentChanged` on unchanged texts), and a full rebuild (load into a mounted Scene + swap). `expect` each median under 50 ms, 5 ms and 100 ms. Also record the longest synchronous pause of the isolate during a load and during a rebuild: run a `Timer.periodic(Duration.zero)` probe alongside and report the longest gap between its ticks. No `expect` on it yet (spec Clarifications).
- [ ] T043 On the reference Mac, run T042 and quickstart §5 step 4 (the release build checked with `strings … | grep -c "couldn't Hot-swap"` → 0, SC-006). Record the table (including the longest pauses, and noting that the no-op figure times `contentChanged` alone, not the whole `onHotReload` call), the configuration (macOS, Apple M4, Flutter 3.44.2, `flutter test` JIT) and the release result. Then propose a pause limit to the author. Once they set it, add it to SC-004 and plan.md, add the `expect` to T042's benchmark, and if the limit needs it, make `scene_builder.dart` yield between passes (and every ~200 Nodes in pass 1), recording the limit as a decision in `dev-docs/decisions.md`. Record all of this in a new "Runtime" section of `dev-docs/ARCHITECTURE.md`, after the Generator section. If this can't run on the reference Mac in the implementing session, leave the task open and say so in the PR
  - *Spec 005:* the release check runs there on `example/` (spec 005 T046, quickstart §5.9). The timings and the pause limit stay this task's.
- [X] T044 [P] Update `GLOSSARY.md` (plan.md, Documentation updates):
  - add **Asset source**, **Animation file** and **Stale reference**, each one line in the file's style;
  - add to **Entity** that its component in games is `PyroEntity`;
  - add to **Hot-swap** that it rebuilds only when the Scene's content changed.
- [X] T045 [P] Add decisions from Q109 to `dev-docs/decisions.md`, each citing "Runtime spec, 2026-10-20":
  - `SpriteAnimation` Overrides are `{"asset", "animation"}` with no `schemaVersion` bump (FR-034);
  - the stale-reference warning detects transform changes, re-adding and `PyroScene` API calls (amends Q71's ◇);
  - Hot-swap compares the kept file texts, with no hash (refines Q67);
  - `RegistryType.acceptsParent` checks Behavior parents at load (extends Q57);
  - under `UnknownType.skip` an unknown Custom component or kind is dropped with its subtree (details Q58);
  - missing assets fail a game's load.
- [X] T046 Update `dev-docs/project-plan.md` and `dev-docs/phases.md` in one commit (phases.md sync rule):
  - §6.2: the API as built (`PyroScene.load`'s parameters, `find` and `findAll` path rules, `UnknownType`), the loading order no longer ◇ proposed, that `onReloaded` runs before the new Nodes' `onLoad`s, and the stale-reference mechanism of T045;
  - §10: `AssetSource` as built (two methods, bundle default, no prefix);
  - §14 and phases.md: #8's estimate **as the author sets it** (plan.md suggests 4 → ~5; ask before writing numbers);
  - tick #8 in phases.md with a link to `specs/004-runtime/spec.md` and the Q numbers of T045;
  - update phases.md's status line and "Left" figures, and mark Phase 2 ✅ if its done-when holds.
- [X] T047 [P] Update `rt/README.md` (create it if absent): `PyroScene.load` with §6.2's example, lookups, `UnknownType.skip`, `onReloaded`, what Hot-swap needs (a debug build, Flame ≥ 1.36, a reload through `flutter run`), the asset source, and that Scenes load without Pyro (Q64). Add a `rt/CHANGELOG.md` entry for the loader, the `AssetRef` amendment and `acceptsParent`, saying that a `pyro.g.dart` generated before this version fails at startup with an `ArgumentError` naming the Behavior until `dart run build_runner build` regenerates it, and a `gen/CHANGELOG.md` entry for `acceptsParent`.
- [X] T048 Run the repository's checks:
  - `dart format --output=none --set-exit-if-changed packages apps`;
  - `dart analyze --fatal-infos packages/pyro_annotations packages/pyro_generator`;
  - `flutter analyze --fatal-infos packages/pyro_runtime packages/pyro_ui apps/editor packages/pyro_generator/fixture_game`;
  - `flutter analyze --fatal-infos lib/pyro.g.dart` in `game/`;
  - `dart test` in `gen/`, and `flutter test` in `rt/`, `game/` and `apps/editor`;
  - in `game/`, `dart run build_runner build -d && git diff --exit-code -- lib/pyro.g.dart lib/pyro.manifest.json`;
  - walk through [quickstart.md](quickstart.md) §1–§3 and §6.
- [X] T049 Self-review the change against the constitution (plan.md, Constitution Check):
  - `pyro_runtime`'s `pubspec.yaml` dependencies are unchanged;
  - every public member is documented;
  - every `SceneLoadException` and warning names the Scene and the Node;
  - every Hot-swap and stale-watch line is under `kDebugMode`;
  - `PyroScene` overrides no `update` or `render`;
  - `pyro_generator` still doesn't depend on `pyro_runtime`.

  Note in `dev-docs/ARCHITECTURE.md`'s Runtime section what was verified (data contract change, constitution workflow rule).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T001 first: a failing assumption changes the design
- **Foundational (Phase 2)**: after Setup; blocks every story. T010 is one commit across `rt/`,
  `gen/` and `game/`
- **US1 (Phase 3)**: after Foundational
- **US2 (Phase 4)**: after US1 (its error paths live in `scene_builder.dart`)
- **US3 (Phase 5)**: after US1. It can run alongside US2: it touches `built_scene.dart` and the
  lookup methods only
- **US4 (Phase 6)**: after US1. T036 reuses US2's warnings, so finish T028 first
- **US5 (Phase 7)**: after US1. T040 needs T010's regenerated Registry
- **Polish (Phase 8)**: after all stories; T042 after US4. T044 (glossary) ships in the same PR as
  the code that introduces its terms (constitution I), never in a later one

### Within Each Story

- Tests and fixtures first, failing, then the implementation
- `field_values.dart`, `builtin_nodes.dart` and the animation reader before `scene_builder.dart`;
  `scene_builder.dart` before `pyro_scene.dart`'s wiring
- Each story's checkpoint passes before the next story starts

### Parallel Opportunities

- Setup: T002 and T003 (after T001)
- Foundational: tests T004–T007 together; T008 and T011 together; T009 alongside them; then T010,
  T012, T013
- US1: tests T014 and T015 together; T018, T020 and T021 together
- US2: T024–T026 together
- US3 alongside US2 (T030–T032)
- US4: T033 and T034 together
- US5: T039 and T040 together, alongside US3
- Polish: T042, T044, T045 and T047

---

## Parallel Example: User Story 1

```bash
# Tests for the leaf modules, together:
Task: "Write rt/test/animation/animation_file_test.dart"
Task: "Write rt/test/loader/field_values_test.dart"

# Then the three leaf modules, side by side:
Task: "Implement rt/lib/src/animation/animation_file.dart and animation_codec.dart"
Task: "Implement rt/lib/src/loader/field_values.dart"
Task: "Implement rt/lib/src/loader/pyro_entity.dart and builtin_nodes.dart"
```

## Parallel Example: User Stories 2 and 3

```bash
# US2's fixtures and tests, and US3's whole phase, together:
Task: "Add error fixtures under rt/test/fixtures/loader/errors/"
Task: "Write rt/test/loader/errors_test.dart"
Task: "Write rt/test/loader/unknown_type_test.dart"
Task: "Add lookups.scene.json and write rt/test/loader/lookup_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup (T001 pins the Flame facts)
2. Phase 2: Foundational
3. Phase 3: US1
4. **Stop and validate:** every fixture Scene loads in `flame_test` with the hand-written
   Registry, every `onLoad` sees configured fields

### Incremental Delivery

1. Setup + Foundational → contracts amended, `PyroScene.load` for a root-only Scene
2. US1 → Scenes load (MVP; Phase 2's Runtime done-when)
3. US2 → every drift reported; `UnknownType.skip`
4. US3 → lookups
5. US4 → Hot-swap and the stale-reference warning
6. US5 → one asset seam, checked end to end in `fixture_game`
7. Polish → budgets measured, docs and decisions in sync, #8 ticked

Phase 3 (the vertical slice) needs US1, US3 and US4; US2 is what makes the slice debuggable, and
US5's `fixture_game` load is the pattern #12's contract test reuses for `example/`.

---

## Notes

- [P] tasks = different files, no dependencies on unfinished tasks
- Commit after each task or logical group (Conventional Commits, citing Q numbers or ADRs where
  one applies), on `specs/004-runtime`
- Tests that print in debug capture `debugPrint` by swapping it in `setUp` and restoring it in
  `tearDown`; no test sleeps or reads the wall clock
- Stop at any checkpoint to validate a story on its own
