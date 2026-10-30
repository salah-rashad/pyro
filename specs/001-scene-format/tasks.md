---

description: "Task list for the Scene format (schemaVersion 1) in pyro_runtime"
---

# Tasks: Scene Format

**Input**: Design documents from `specs/001-scene-format/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: included. Constitution Principle V makes serialization a **Heavy** test layer: every
behavior change ships with tests in the same change. Within each phase, write the tests first
and see them fail before implementing.

**Organization**: tasks are grouped by user story so each story can be built and checked on its
own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: the user story the task belongs to (US1–US4)

## Path Conventions

All paths are relative to the repository root. The package is `packages/pyro_runtime/`,
shortened below as `pkg/`, so `pkg/lib/src/scene/node.dart` means
`packages/pyro_runtime/lib/src/scene/node.dart`.

Run commands with Flutter on the path: `export PATH="$PATH:/Users/salah/Library/flutter/bin"`.
Tests: `cd packages/pyro_runtime && flutter test`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: folders, test helpers and the pure-Dart guard

- [X] T001 Create the folders from plan.md's Source Code tree: `pkg/lib/src/scene/json/`, `pkg/lib/src/loader/`, `pkg/test/scene/`, `pkg/test/loader/`, `pkg/test/fixtures/scenes/{canonical,non_canonical,damaged,version,invalid}/` and `pkg/benchmark/`; delete the placeholder test `pkg/test/pyro_runtime_test.dart`
- [X] T002 [P] Add a fixture helper in `pkg/test/scene/fixtures.dart`: `String readFixture(String relativePath)` reads `test/fixtures/scenes/<relativePath>` as UTF-8 bytes **without** normalising line endings, and `List<String> fixtureNames(String folder, {String suffix = '.scene.json'})` lists files, excluding `*.expected.scene.json`, sorted
- [X] T003 [P] Write the pure-Dart guard in `pkg/test/scene/scene_imports_test.dart` (research R5): read every `.dart` file under `pkg/lib/src/scene/` and fail, naming file and line, if any `import`/`export` starts with `package:flutter`, `package:flame` or `dart:ui`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the model types, errors, strict reader and canonical writer that every story uses

**⚠️ CRITICAL**: no user story work can begin until this phase is complete

### Tests for the foundation

- [X] T004 [P] Write `pkg/test/scene/strict_reader_test.dart` for the reader of T010: duplicate keys raise `DuplicateKey` with `key`, a dotted `path` (for example `nodes.a1.transform`) and 1-based `line`/`column`; malformed input (trailing comma, unterminated string, bare word, trailing garbage after the value) raises `MalformedJson` with `offset`, `line`, `column`; a leading U+FEFF byte-order mark and CRLF line endings are accepted; `80` reads as an `int` and `80.0` as a `double` on the VM; string escapes `\" \\ \/ \b \f \n \r \t \uXXXX` (including surrogate pairs) decode; returned maps and lists are unmodifiable (mutation throws `UnsupportedError`); 500-deep nesting parses without overflowing the stack
- [X] T005 [P] Write `pkg/test/scene/canonical_writer_test.dart` for the writer of T011, one test per rule in [contracts/scene-file-v1.md § Canonical form](contracts/scene-file-v1.md#canonical-form): LF, two spaces, one trailing newline; the given top-level key order first, then sorted keys; every other object's keys sorted by `String.compareTo`; `{}` and `[]` for empty; number-only arrays inline as `[320, 128]`; other arrays one element per line; numbers `80.0 → 80`, `-3.0 → -3`, `1e20 → 100000000000000000000`, `1e21 → 1e+21`, `0.1 → 0.1`, `1e-7 → 1e-7`, `1.23e-18 → 1.23e-18`, `-0.0 → 0`; NaN and infinities throw `ArgumentError`; strings escape only `"`, `\` and characters below U+0020 (`\b \f \n \r \t`, others as lower-case `\u00XX`), leaving `é`, `😀` and `/` as they are
- [X] T006 [P] Write `pkg/test/scene/scene_test.dart` for T012: the `Scene` constructor throws `ArgumentError` when there isn't exactly one `RootNode`, when `nodes[rootId]` isn't it, when a `childIds` entry names no Node, when a Node appears in two lists or twice in one, when the root appears in a list, or when some Node isn't reachable from the root; `parentOf` returns each Node's parent and `null` for the root; every Node class's `copyWith` changes only the given fields; value types (`Vec2`, `NodeTransform`, `NodeAnchor`, `SpriteRegion`) have value equality and `Node`s compare by identity

### Implementation for the foundation

- [X] T007 [P] Implement the error types in `pkg/lib/src/scene/errors.dart` per [data-model.md § SceneFormatException](data-model.md#sceneformatexception-sealed-implements-exception): `sealed class SceneFormatException implements Exception` with `MalformedJson(message, offset, line, column)`, `DuplicateKey(key, path, line, column)`, `UnsupportedSchemaVersion(found, supported)`, `InvalidSchemaVersion(found)`, `InvalidRoot(reason)`, `InvalidNode(nodeId, nodeName?, typeId?, key?, message)`, `UnwritableValue(nodeId, key, value)`; each `toString()` names what failed and where (FR-026); public members documented
- [X] T008 [P] Implement the value types in `pkg/lib/src/scene/values.dart` per [data-model.md § Value types](data-model.md#value-types): extension types `NodeId`, `TypeId`, `AssetPath` over `String`; `Vec2(x, y)` with `double` fields; `NodeTransform(position, size, scale, angle, anchor, extra)` with "angle: double (radians)" and `extra` holding unknown keys inside `transform` (FR-017), included in equality through a private deep-equality helper for JSON values in the same file (no `collection` dependency); `NodeAnchor` as either one of the nine names `topLeft, topCenter, topRight, centerLeft, center, centerRight, bottomLeft, bottomCenter, bottomRight` or a custom `Vec2`; `SpriteRegion(position, size)`; `enum CollisionType { active, passive, inactive }`; value equality and `hashCode` on all of them; no Flutter or Flame imports
- [X] T009 [P] Implement `Overrides` and `BehaviorAttachment` in `pkg/lib/src/scene/overrides.dart`: `Overrides` wraps an unmodifiable `Map<String, Object?>` of JSON values keyed by field name; `BehaviorAttachment(type: TypeId, fields: Overrides, extra)`; both immutable with `copyWith`
- [X] T010 Implement the strict reader in `pkg/lib/src/scene/json/strict_reader.dart` (research R1) so T004 passes: a recursive-descent parser over code units that skips a leading U+FEFF, treats `\r` as whitespace, builds `Map.unmodifiable`/`List.unmodifiable` values, reads integers as `int` and other numbers as `double`, tracks the key path for `DuplicateKey`, and converts offsets to 1-based line and column for errors; library-private API `Object? readStrictJson(String text)`
- [X] T011 Implement the canonical writer in `pkg/lib/src/scene/json/canonical_writer.dart` (research R2, R3) so T005 passes: `String writeCanonicalJson(Object? value, {List<String> topLevelOrder = const []})` using a `StringBuffer`; the number rule is "a finite integral value with magnitude below 10²¹ is written as digits only; any other finite value uses `double.toString()`; `-0.0` is written `0`"
- [X] T012 Implement the Node model in `pkg/lib/src/scene/node.dart` per [data-model.md § Node kinds](data-model.md#node-kinds): `sealed class Node` (`id`, `childIds`, `extra`) and `RootNode`, `EntityNode` (`transform`, `behaviors`), `SpriteNode` (`transform`, `image: AssetPath`, `region: SpriteRegion?`, `propsExtra`), `RectangleHitboxNode` (`position`, `size`, `angle`, `anchor`, `collisionType`, `isSolid`, `propsExtra`), `CircleHitboxNode` (`position`, `radius`, `anchor`, `collisionType`, `isSolid`, `propsExtra`), where `propsExtra` holds unknown keys inside `props` (FR-017), `CustomNode` (`type: TypeId`, `transform`, `fields: Overrides`, `behaviors`), `UnknownNode` (`kind: String`); every non-root kind has `String? name` and `List<String> tags`; all collections unmodifiable; `copyWith` on each class (depends on T008, T009)
- [X] T013 Implement `Scene` in `pkg/lib/src/scene/scene.dart` so T006 passes: `static const int currentSchemaVersion = 1`, fields `rootId`, `nodes` (unmodifiable), `extra`; the constructor checks the invariants in [data-model.md § Scene](data-model.md#scene) and throws `ArgumentError` naming the offending Node IDs; `root`; `parentOf` from a map built lazily once; `copyWith` (depends on T012)
- [X] T014 Add the report types to `pkg/lib/src/scene/tree_repair.dart` (no repair logic yet; US4 adds it): `final class RepairReport` (`issues` unmodifiable, `isEmpty`, `describe()` one line per issue) and `sealed class TreeIssue` with `MissingChild(parentId, childId)`, `SelfChild(nodeId)`, `RootAsChild(parentId)`, `DuplicateChild(parentId, childId)`, `MultipleParents(nodeId, keptParentId, removedFromParentId)`, `OrphanAttached(nodeId)`, `CycleBroken(nodeIds, attachedNodeId, removedFromParentId)`; `RepairReport.empty`

**Checkpoint**: `flutter test` passes T003–T006; the model, reader and writer exist and story work can start

---

## Phase 3: User Story 1 - Save and reopen a Scene without any change (Priority: P1) 🎯 MVP

**Goal**: read and write every early-preview Node kind's built-in data losslessly and in
canonical form (FR-001–FR-008, FR-013–FR-017, FR-026)

**Independent Test**: every fixture in `canonical/` is byte-identical after decode → encode;
every `non_canonical/` fixture encodes to its `.expected` file and is then stable (quickstart §1
and §2)

### Tests for User Story 1

- [X] T015 [P] [US1] Write canonical fixtures in `pkg/test/fixtures/scenes/canonical/`, in exact canonical form per the contract (no `behaviors` or `fields` yet; those come in US2): `root_only.scene.json`; `entity.scene.json` (name, tags, nested children); `sprite.scene.json` (one sprite with `srcPosition`/`srcSize`, one without); `rectangle_hitbox.scene.json`; `circle_hitbox.scene.json`; `custom.scene.json` (`type`, `transform`, no fields); `anchors.scene.json` (all nine named anchors and one custom `[0.25, 0.75]`); `unknown_kind.scene.json` (a `"kind": "prefabInstance"` Node with nested data plus an unknown key on an entity, its transform, a rectangle hitbox's `props` and the top level); `text.scene.json` (names with quotes, backslash, emoji, Arabic text and a line break); `numbers.scene.json` (decimal, negative, `1e-7`, large integral values)
- [X] T016 [P] [US1] Write non-canonical fixtures in `pkg/test/fixtures/scenes/non_canonical/`, each with an `<name>.expected.scene.json`: `unsorted_keys`, `four_space_indent`, `crlf_line_endings`, `byte_order_mark`, `no_trailing_newline`, `float_integers` (`80.0`, `1.0` scale), `empty_collections` (`"childIds": []`, `"tags": []`, `"behaviors": []`, `"fields": {}`), `expanded_number_arrays` (`[\n 320,\n 128\n]`), `compact` (all on one line); `behaviors`/`fields` empties are covered by US2's `empty_behaviors_and_fields`, since US1 doesn't map them yet
- [X] T017 [P] [US1] Write invalid fixtures in `pkg/test/fixtures/scenes/invalid/` for the reading errors in the contract: `malformed.scene.json`, `duplicate_node_id.scene.json`, `duplicate_key_in_transform.scene.json`, `missing_root_id.scene.json`, `root_id_unknown.scene.json`, `root_wrong_kind.scene.json`, `two_roots.scene.json`, `custom_without_type.scene.json`, `vector_one_number.scene.json`, `vector_string.scene.json`, `negative_radius.scene.json`, `bad_collision_type.scene.json`, `bad_anchor_name.scene.json`, `src_position_without_size.scene.json`, `kind_not_string.scene.json`, `nodes_not_object.scene.json`, `empty_node_id.scene.json`, `child_ids_not_list.scene.json`, `child_id_not_string.scene.json`, `tags_not_strings.scene.json` (the last four expect `InvalidNode`, per data-model.md "Node IDs (the keys of `nodes`) are non-empty; `childIds` is a list of strings; `name` is a string; `tags` is a list of strings")
- [X] T018 [US1] Write `pkg/test/scene/round_trip_test.dart`: for every `canonical/` fixture, `SceneCodec.encode(SceneCodec.decode(text).scene)` equals `text` byte for byte (SC-001); for every `non_canonical/` fixture, the output equals its `.expected` file and encoding again changes nothing (FR-016); moving one Node with `copyWith` changes only lines inside that Node's block, checked with a line diff (SC-003); unknown kinds and keys come back unchanged (FR-017) (depends on T015, T016)
- [X] T019 [US1] Write `pkg/test/scene/errors_test.dart`: each `invalid/` fixture throws the expected `SceneFormatException` subtype, and its `toString()` contains the Node ID and, where relevant, the Node name, Type ID or key (FR-026); `UnwritableValue` is thrown when encoding a transform with `double.nan` (depends on T017)

### Implementation for User Story 1

- [X] T020 [US1] Implement JSON ↔ Node mapping for built-in data in `pkg/lib/src/scene/node_mapping.dart`: `Node nodeFromJson(NodeId id, Object? json)` and `Map<String, Object?> nodeToJson(Node node)` for all seven classes; reading validates per [data-model.md § Validation on read](data-model.md#node-sealed) ("vectors are two finite numbers, `radius` and `size` components are ≥ 0, `collisionType` is one of its three names, `anchor` is a known name or a vector", "`srcPosition` and `srcSize` are both present or both absent", "`custom` requires a non-empty `type`") and throws `InvalidNode`; keys it doesn't recognise go to `Node.extra`, `NodeTransform.extra` or `propsExtra`, depending on where they appear; writing omits empty `childIds`/`tags` and a `null` `name`, and always writes all five transform keys (FR-013); `UnknownNode` keeps its whole object (behaviors and fields are mapped in US2)
- [X] T021 [US1] Implement `SceneCodec` and `SceneReadResult` in `pkg/lib/src/scene/scene_codec.dart` per [contracts/dart-api.md](contracts/dart-api.md#reading-and-writing): `decode` runs `readStrictJson`, requires a top-level object, requires `schemaVersion == 1` for now (US3 adds the full gate), validates `rootId` and `nodes` (throwing `InvalidRoot`), maps Nodes with T020, constructs `Scene`, and returns `SceneReadResult(scene, RepairReport.empty)`; `encode` writes with `topLevelOrder: ['schemaVersion', 'rootId', 'nodes']` and turns writer `ArgumentError`s into `UnwritableValue` naming the Node and key (depends on T020)
- [X] T022 [US1] Export the public scene API from `pkg/lib/pyro_runtime.dart` (`SceneCodec`, `SceneReadResult`, `Scene`, the Node classes, value types, `Overrides`, `BehaviorAttachment`, `RepairReport`, `TreeIssue` subtypes, `SceneFormatException` subtypes), keeping `json/` private, and update the library doc comment

**Checkpoint**: T018 and T019 pass; Scenes with every built-in Node kind round-trip

---

## Phase 4: User Story 2 - Code defaults reach every Node without an Override (Priority: P1)

**Goal**: Behaviors and Custom component fields store Overrides only, in the Field type written
forms (FR-007, FR-009–FR-012)

**Independent Test**: `overrides.scene.json` round-trips byte for byte, holds exactly the set
fields, and an Override equal to its default survives (quickstart §1)

### Tests for User Story 2

- [X] T023 [P] [US2] Write `pkg/test/fixtures/scenes/canonical/overrides.scene.json`: an entity with two Behaviors in a deliberate non-alphabetical order (`Patrol` then `Attack`), a custom Node with `fields` covering every row of the contract's Field types table (`80`, `0.25`, `true`, a string, an enum name, `[1, 0]`, `"#FFFF8800"`, `{"asset": "assets/images/fx.png"}`, `{"ref": "<a Node ID in the file>"}`), one Override equal to its code default, one field name no code knows, a `{"ref": …}` to a Node ID that doesn't exist, and an unknown key inside a Behavior object
- [X] T024 [US2] Write `pkg/test/scene/overrides_test.dart`: the fixture round-trips byte for byte; decoding exposes exactly the written fields; removing a field from `Overrides` with `copyWith` removes its key from the output (FR-010); Behavior order is preserved; an empty `fields` map is omitted; `EntityRef.fromJson`/`toJson` and `AssetRef.fromJson`/`toJson` convert the tagged forms and return `null` for anything else; a dangling `{"ref": …}` is kept as written; a Behavior without `type` throws `InvalidNode` naming the Node (depends on T023)

### Implementation for User Story 2

- [X] T025 [P] [US2] Add `EntityRef` (`{"ref": "<NodeId>"}`) and `AssetRef` (`{"asset": "<AssetPath>"}`) to `pkg/lib/src/scene/overrides.dart`, each with `static X? fromJson(Object? value)` and `Map<String, Object?> toJson()`, value equality, and doc comments giving the contract's written forms
- [X] T026 [US2] Extend `pkg/lib/src/scene/node_mapping.dart` to map `behaviors` (on `entity` and `custom`) and `fields` (on `custom` and inside each Behavior): read Override values as JSON values without interpreting them (FR-011), keep unknown Behavior keys in `BehaviorAttachment.extra`, require "each with a non-empty `type`", and omit empty `behaviors` and `fields` on write (depends on T025)
- [X] T027 [US2] Export `EntityRef` and `AssetRef` from `pkg/lib/pyro_runtime.dart`

**Checkpoint**: US1 and US2 tests pass; Overrides follow ADR 0003

---

## Phase 5: User Story 3 - Refuse a Scene from a newer Pyro (Priority: P2)

**Goal**: the `schemaVersion` gate (FR-018–FR-020a)

**Independent Test**: each `version/` fixture gives the expected outcome, and a newer file is
refused before any Node is looked at (quickstart §5)

### Tests for User Story 3

- [X] T028 [P] [US3] Write fixtures in `pkg/test/fixtures/scenes/version/`: `current.scene.json` (`1`), `current_as_float.scene.json` (`1.0`, accepted), `newer.scene.json` (`2`, with Nodes this version couldn't read, for example an unknown required shape), `missing.scene.json`, `zero.scene.json`, `negative.scene.json`, `string.scene.json` (`"1"`), `fraction.scene.json` (`1.5`), `null.scene.json`
- [X] T029 [US3] Write `pkg/test/scene/schema_version_test.dart`: `newer` throws `UnsupportedSchemaVersion` with `found == 2`, `supported == 1`, and both numbers in `toString()`, even though its Nodes are invalid (the gate runs first); `missing`, `zero`, `negative`, `string`, `fraction` and `null` throw `InvalidSchemaVersion`; `current` and `current_as_float` decode; `encode` always writes `"schemaVersion": 1` as the first key (FR-018) (depends on T028)

### Implementation for User Story 3

- [X] T030 [US3] Replace the temporary version check in `pkg/lib/src/scene/scene_codec.dart` with the gate: it runs straight after `readStrictJson`, before `rootId` or `nodes` are read; it accepts an `int` ≥ 1 or an integral `double` ≥ 1; it throws `InvalidSchemaVersion(found)` for anything else and `UnsupportedSchemaVersion(found, Scene.currentSchemaVersion)` when the value is greater than `Scene.currentSchemaVersion`; add a doc comment on `Scene.currentSchemaVersion` stating the bump rule of FR-020a ("any new Node kind, Field type or required key, or a change in meaning, increases it")

**Checkpoint**: US1–US3 tests pass; newer files are refused

---

## Phase 6: User Story 4 - Open a Scene damaged by a git merge (Priority: P2)

**Goal**: deterministic repair of `childIds` damage, reported, never losing data (FR-021–FR-025),
and the debug warning in games (FR-024a)

**Independent Test**: each `damaged/` fixture decodes to its `.expected` file with the expected
issues; the merge-story fixture behaves as quickstart §3 describes

### Tests for User Story 4

- [X] T031 [P] [US4] Write damaged fixtures in `pkg/test/fixtures/scenes/damaged/`, each with `<name>.expected.scene.json` (the repaired canonical output): `missing_child`, `self_child`, `root_as_child`, `duplicate_child`, `multiple_parents` (kept with the first parent in a depth-first walk), `orphans` (two orphan heads whose IDs sort opposite to file order, one with its own child, so the subtree moves together), `cycle_unreachable` (A lists B, B lists A, neither under the root), `cycle_with_tail` (a cycle whose smallest ID isn't the smallest remaining ID), `cycle_reachable` (a descendant lists its ancestor), `merge_moved_and_deleted` (Story 4's narrative: one Node under two parents, a missing child and an orphan), and `healthy` (no `.expected`; must report nothing)
- [X] T032 [US4] Write `pkg/test/scene/tree_repair_test.dart`: each damaged fixture's output equals its `.expected` file; `repairs.issues` matches an expected list of `TreeIssue`s (type and IDs, in discovery order) per fixture; Node count and every Node's encoded data except `childIds` are unchanged (FR-023); decoding the same fixture twice gives identical bytes (FR-022); `healthy` gives an empty report; a generated 10,000-deep chain decodes without a stack overflow; `describe()` has one line per issue, each containing its Node IDs (depends on T031)
- [X] T033 [P] [US4] Write `pkg/test/loader/repair_warning_test.dart`: with `debugPrint` overridden to capture output, `warnAboutRepairs('assets/scenes/level1.scene.json', report)` prints one block naming the scene key, every issue and the advice to open the Scene in Pyro and save it; an empty report prints nothing (release behavior relies on the `kDebugMode` guard and is checked in quickstart §3)

### Implementation for User Story 4

- [X] T034 [US4] Implement the four repair passes of [research.md R8](research.md#r8-deterministic-tree-repair) in `pkg/lib/src/scene/tree_repair.dart` as `({Map<NodeId, List<NodeId>> childIds, RepairReport report}) repairTree(NodeId rootId, Map<NodeId, List<NodeId>> childIds)`: (1) clean each list in file order; (2) iterative pre-order walk from the root, removing already-visited children (`MultipleParents`); (3) append unvisited heads under the root in ascending `NodeId` order (`OrphanAttached`) and walk each; (4) while Nodes remain unvisited, follow listing parents up from the smallest remaining ID to a cycle and attach that cycle's smallest ID (`CycleBroken` listing the Nodes reached, sorted); it changes only `childIds` lists
- [X] T035 [US4] Wire repair into `SceneCodec.decode` in `pkg/lib/src/scene/scene_codec.dart`: after mapping Nodes and before constructing `Scene`, run `repairTree`, apply the repaired lists with each Node's `copyWith(childIds: …)`, and return the report in `SceneReadResult`; decoding never writes a file (FR-025) (depends on T034)
- [X] T036 [P] [US4] Implement `warnAboutRepairs(String sceneKey, RepairReport repairs)` in `pkg/lib/src/loader/repair_warning.dart`: returns at once if `!kDebugMode` or the report is empty; otherwise one `debugPrint` block: a header naming the scene, `repairs.describe()`, and "Open this Scene in Pyro and save it to keep the repair."; export it from `pkg/lib/pyro_runtime.dart`

**Checkpoint**: all four stories pass their tests independently

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: the full example, the performance budget, and the documentation the constitution
requires in the same change

- [X] T037 [P] Add `pkg/test/fixtures/scenes/canonical/all_kinds.scene.json`, the example from [contracts/scene-file-v1.md](contracts/scene-file-v1.md#example) with every Node kind, Behaviors and fields; T018's round-trip loop picks it up automatically
- [X] T038 [P] Write `pkg/benchmark/scene_codec_benchmark.dart` (SC-006): build a deterministic 1,000-Node Scene (root → 250 entities, each with one Behavior with three fields, one sprite and one hitbox child), encode it once, then after 10 warm-up runs time 50 `decode` and 50 `encode` calls and print the median and p95 in milliseconds and the size in KB; import only `pkg/lib/src/scene/` so it runs with `dart run`
- [X] T039 Run the benchmark with `dart run` and as an AOT binary (`dart compile exe`) per quickstart §4; if the AOT median decode or encode is ≥ 100 ms, profile and optimise `strict_reader.dart`/`canonical_writer.dart` before continuing; record the numbers, machine and date in a "Scene format" section of `dev-docs/ARCHITECTURE.md`, naming this machine as the reference machine for SC-006. If `dart run` can't resolve the package, run the benchmark as a `flutter test` file tagged `benchmark` (CI excludes it with `--exclude-tags benchmark`) and record that its numbers are JIT only (depends on T038)
- [X] T040 [P] Add **Repair report** to `GLOSSARY.md` under "Scenes": "The list of inconsistencies in a Scene's tree that reading found and fixed (an orphan, a Node under two parents, a missing child…), each naming the Nodes involved." with `_Avoid_: Fix log, migration`; also add **Node ID** ("The stable identifier of a Node within its Scene; it never changes when the Node is renamed, moved or edited.", `_Avoid_: UUID (as a term)`) and **Canonical form** ("The one exact way Pyro writes a Scene file, so saving an unchanged Scene changes no bytes."), and change the "Node kind" entry to "a built-in sort (root, entity, sprite, hitbox, prefab instance) or a Custom component"
- [X] T041 [P] Replace the example in `dev-docs/project-plan.md` §7.1 with the contract's example, update the bullets to mention `props`, tagged `{"asset": …}` references and the `#AARRGGBB` colour form, and link `specs/001-scene-format/contracts/scene-file-v1.md`
- [X] T042 [P] Record the format decisions in `dev-docs/decisions.md` as Q89–Q93 (and add them to the opening paragraph's list of sources): Q89 built-in Node properties are always written in full; Q90 any new Node kind, Field type or required key bumps `schemaVersion`; Q91 Field type written forms (`#AARRGGBB`, `{"asset": …}`, `{"ref": …}`); Q92 the canonical form (top-level order, sorted keys, inline number arrays, the number rule); Q93 games repair damaged trees in every build with a debug warning, and orphans go under the root in Node ID order
- [X] T043 [P] Add an "Unreleased" entry to `pkg/CHANGELOG.md` describing the Scene format API
- [X] T044 Tick "Scene format" in `dev-docs/phases.md` Phase 2, and add to the #8 bullet there: "call `warnAboutRepairs` after `SceneCodec.decode` in `PyroScene.load` (FR-024a)" (depends on T039–T043)
- [X] T045 Run the full gate from the repository root: `dart format --output=none --set-exit-if-changed packages apps`, `flutter analyze --fatal-infos packages/pyro_runtime`, and `cd packages/pyro_runtime && flutter test`; then walk through [quickstart.md](quickstart.md) §2, §3 and §5 and confirm each expected outcome

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup; blocks every story
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on US1's `node_mapping.dart` and `scene_codec.dart` (T020, T021), because it extends the same mapping
- **US3 (Phase 5)**: depends on US1's `scene_codec.dart` (T021); independent of US2
- **US4 (Phase 6)**: depends on US1's `scene_codec.dart` (T021); independent of US2 and US3
- **Polish (Phase 7)**: T037 needs US1 and US2; T039 needs all stories; the documentation tasks can start once their story is done

```text
Setup → Foundational → US1 ─┬─ US2 ─┐
                            ├─ US3 ─┼─ Polish
                            └─ US4 ─┘
```

US2, US3 and US4 touch different parts of the same two files (`node_mapping.dart` for US2,
`scene_codec.dart` for US3 and US4), so if they are built at the same time, finish one story's
change to a shared file before starting the next.

### Within Each Story

- Fixtures and tests first, run and seen failing
- Model and helper changes before mapping, mapping before the codec
- The story's checkpoint passes before the next story starts

### Parallel Opportunities

- Setup: T002 and T003
- Foundational tests: T004, T005, T006; implementation: T007, T008, T009 together, then T010 and T011 side by side (different files), then T012 → T013 → T014
- US1: fixtures T015, T016, T017 together
- US2: T023 alongside T025
- US3 and US4 fixtures (T028, T031) can be written while US2 is in progress
- US4: T033 and T036 (the warning) alongside T031–T035 (the repair)
- Polish: T037, T038, T040–T043

---

## Parallel Example: User Story 1

```bash
# Fixtures for User Story 1, together:
Task: "Write canonical fixtures in pkg/test/fixtures/scenes/canonical/"
Task: "Write non-canonical fixtures in pkg/test/fixtures/scenes/non_canonical/"
Task: "Write invalid fixtures in pkg/test/fixtures/scenes/invalid/"
```

## Parallel Example: User Story 4

```bash
# The repair and the debug warning, side by side:
Task: "Write damaged fixtures in pkg/test/fixtures/scenes/damaged/"
Task: "Write pkg/test/loader/repair_warning_test.dart"
Task: "Implement warnAboutRepairs in pkg/lib/src/loader/repair_warning.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup
2. Phase 2: Foundational
3. Phase 3: US1
4. **Stop and validate:** every built-in Node kind round-trips byte for byte

### Incremental Delivery

1. Setup + Foundational → the reader and writer exist
2. US1 → built-in Scenes round-trip (MVP)
3. US2 → Behaviors and Overrides
4. US3 → newer files refused
5. US4 → merge damage repaired
6. Polish → performance measured, docs in sync, Phase 2's "Scene format" ticked

Nothing in this feature ships to users before the Document model (#2) and the Runtime loader
(#8) use it, so all four stories are needed before the work counts as done. The order above is
for checking progress, not for releasing.

---

## Notes

- [P] tasks = different files, no dependencies on unfinished tasks
- Commit after each task or logical group (Conventional Commits, citing Q numbers where one
  applies)
- Stop at any checkpoint to validate a story on its own
