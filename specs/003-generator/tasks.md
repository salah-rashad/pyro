---

description: "Task list for the Generator (#7): pyro_annotations, pyro_generator and the Registry contract in pyro_runtime"
---

# Tasks: Generator

**Input**: Design documents from `specs/003-generator/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: included. Constitution Principle V makes the generator a **Heavy** test layer
(goldens for the Registry and the Manifest, error cases), and the spec's done-when is golden
fixtures passing. Within each phase, write the tests first and see them fail before
implementing.

**Organization**: tasks are grouped by user story so each story can be built and checked on its
own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: the user story the task belongs to (US1–US4)

## Path Conventions

All paths are relative to the repository root. Shortened below:

- `ann/` = `packages/pyro_annotations/`
- `gen/` = `packages/pyro_generator/`
- `rt/` = `packages/pyro_runtime/`
- `game/` = `packages/pyro_generator/fixture_game/`

Run commands with Flutter 3.44.2 on the path. Generator tests: `cd packages/pyro_generator &&
dart test`. Regenerate goldens after an intended change: `PYRO_UPDATE_GOLDENS=1 dart test
test/golden_test.dart`, then review `git diff test/goldens`. Fixture game: `cd
packages/pyro_generator/fixture_game && dart run build_runner build -d && flutter test`.

**Golden case layout** (used throughout): `gen/test/goldens/<case>/` holds `input/` (the files
of an in-memory package named `game`, as `input/lib/**.dart`, plus an optional `input/no_runtime`
marker file meaning "pyro_runtime is not a dependency"), and the expected outputs
`pyro.g.dart.golden`, `pyro.manifest.json.golden` and `log.golden` (one line per logged
diagnostic: `SEVERE <code> <file>:<line>` or `WARNING …`). The `.golden` suffix keeps the
expected Registry out of `dart format` and the analyzer; `gen/analysis_options.yaml` excludes
`test/goldens/**` so the inputs, which import stand-in packages, aren't analyzed either.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: dependencies, the fixture game skeleton, the test harness, CI

- [X] T001 Update `gen/pubspec.yaml` per [research.md R1](research.md#r1-toolchain-and-dependencies): add dependency `glob: ^2.1.0` and dev dependency `build_test: ^3.5.0`, sorted (`sort_pub_dependencies`), keeping the wide ranges and their comment; add `gen/analysis_options.yaml` exclusions `test/goldens/**` and `fixture_game/**` (the fixture is analyzed on its own, T004); add `gen/.pubignore` with `fixture_game/`. Run `dart pub get` at the repository root and confirm the lock holds build_test 3.5.16, glob 2.2.0, analyzer 12.1.0, build 4.0.7, source_gen 4.2.4
- [X] T002 Create the fixture game skeleton: `game/pubspec.yaml` (`name: fixture_game`, `publish_to: none`, `resolution: workspace`, `environment: sdk ^3.12.0, flutter ">=3.44.0"`, dependencies `flame`, `flame_behaviors`, `flutter`, `pyro_runtime`; dev dependencies `build_runner: ^2.15.1`, `flutter_test`, `pyro_generator`; **no `build.yaml`**, FR-027); `game/analysis_options.yaml` that includes `../../../analysis_options.yaml` (lint parity; add `flutter_lints` as a dev dependency and `package:flutter_lints/flutter.yaml` as the root's Flutter members do), with a comment that the root's `**/*.g.dart` exclusion still applies because included excludes merge (verified 2026-10-20), so `lib/pyro.g.dart` is analyzed by naming it (T004, research R11); `game/lib/fixture_game.dart` (library doc comment: "A small Flame game the generator's CI builds, with every Field type (spec 003)."); add `packages/pyro_generator/fixture_game` to `workspace:` in the root `pubspec.yaml`; add to `.gitattributes`, under the comment "The generator's golden files and the fixture game's committed outputs are compared byte for byte (spec 003); git must not rewrite their line endings.", the lines `packages/pyro_generator/test/goldens/** -text` and `packages/pyro_generator/fixture_game/lib/pyro.* -text` (plan.md, Risks). Run `dart pub get`
- [X] T003 [P] Write the test harness in `gen/test/support/`: `stubs.dart` with `const Map<String, String> flameStubs`, in-memory sources at the real paths of research R3: `flame|lib/src/components/core/component.dart` (`class Component {}`), `flame|lib/src/components/position_component.dart` (`class PositionComponent extends Component {}`), `flame|lib/src/sprite.dart` (`class Sprite {}`), `flame|lib/src/sprite_animation.dart` (`class SpriteAnimation {}`), `flame|lib/components.dart` exporting those and `package:vector_math/vector_math.dart`, `vector_math|lib/vector_math.dart` → `src/vector_math/vector2.dart` (`class Vector2 {}`), `vector_math|lib/vector_math_64.dart` → `src/vector_math_64/vector2.dart` (`class Vector2 {}`), `flame_behaviors|lib/flame_behaviors.dart` → `mixin EntityMixin on Component {}`, `abstract class Behavior<Parent extends EntityMixin> extends Component {}`, `class PositionedEntity extends PositionComponent with EntityMixin {}`, and a `pyro_runtime|lib/pyro_runtime.dart` stub that re-exports `package:pyro_annotations/pyro_annotations.dart`; `harness.dart` with `Future<GeneratorRun> runGenerator(Map<String, String> gameSources, {bool withRuntime = true})` that reads every file of `ann/lib/` from disk into `pyro_annotations|lib/…`, adds `flameStubs` (and the runtime stub unless `withRuntime` is false), runs `testBuilders([pyroScan(BuilderOptions.empty), pyroAggregate(BuilderOptions.empty)], …, rootPackage: 'game')` with a flattened `TestReaderWriter`, and returns the two outputs (or null), every `.pyro.json` fragment and the log records; and `golden.dart` with `void expectGolden(File file, String actual)` that rewrites the file when `Platform.environment['PYRO_UPDATE_GOLDENS'] == '1'` and otherwise compares bytes, printing a line diff on mismatch. Note: `Color` from `dart:ui` can't be stubbed (research R12); cases that need it live in the fixture game
- [X] T004 [P] Update `.github/workflows/ci.yml` `analyze-test` job: add "Check the fixture game's generated files" on all three OSes after "Resolve the workspace" (`cd packages/pyro_generator/fixture_game && dart run build_runner build -d && git diff --exit-code -- lib/pyro.g.dart lib/pyro.manifest.json`, SC-003); add `packages/pyro_generator/fixture_game` to the "Analyze Flutter packages and the app" `flutter analyze --fatal-infos` list; add a step "Analyze the fixture game's Registry" (`flutter analyze --fatal-infos lib/pyro.g.dart` in it), commented "Excluded files are still analyzed when named; the root options exclude **/*.g.dart, so the Registry is checked this way (SC-005)."; add a "Test the fixture game" step (`flutter test` in it). In the `contract` job's TODO comment, note that `fixture_game`'s steps are the pattern #12 reuses for `example/`. Commit these steps together with T030, so CI never sees the fixture game without its committed outputs

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the annotations, the Registry contract, the diagnostic and JSON plumbing, and two builders that already write (empty) outputs

**⚠️ CRITICAL**: no user story work can begin until this phase is complete

### Tests for the foundation

- [X] T005 [P] Replace `ann/test/pyro_annotations_test.dart` with tests for T008: every annotation and `ImagePath` can be created in a `const` context with and without arguments; `ImagePath('a') == ImagePath('a')`, different paths differ, `hashCode` follows `path`, `toString()` is `ImagePath(a)`
- [X] T006 [P] Write `rt/test/loader/registry_test.dart` for T009: `PyroRegistry` looks types up by `TypeId` (null for unknown), lists `types` in Type ID order regardless of input order, and throws `ArgumentError` naming the Type ID when two types share one; `RegistryField`'s `accepts` and `set` are called as given (a hand-written `RegistryType` for a small test `Component` subclass with an `int` field)
- [X] T007 [P] Write `gen/test/manifest_json_test.dart` for T012: keys sorted at every level; two-space indentation, LF, trailing newline; empty arrays as `[]`; `50.0` written `50`, `0.1` as `0.1`, `-3.0` as `-3`, ints unchanged; strings escaped as `dart:convert` does; and `gen/test/diagnostics_test.dart` for T011: sort by `file`, `line`, `code`, `typeId`, `field`; `toJson` omits absent optional keys; every `DiagnosticCode` has a `kind` (23 errors, 2 warnings, [contracts/manifest-v1.md § Codes](contracts/manifest-v1.md#codes))

### Implementation for the foundation

- [X] T008 [P] Implement the annotations per [contracts/annotations-api.md](contracts/annotations-api.md): `ann/lib/src/annotations.dart` (`final class PyroBehavior({label, category, id})`, `final class PyroComponent({label, category, id, preview})`, `final class Editable({min, max, tooltip, label})`, all `const`, documented) and `ann/lib/src/image_path.dart` (`final class ImagePath`, `const ImagePath(this.path)`, `==`, `hashCode`, `toString`); export both from `ann/lib/pyro_annotations.dart`, replacing the "land with v0.1 work item 7" doc text
- [X] T009 [P] Implement the Registry contract in `rt/lib/src/loader/registry.dart` per [contracts/registry-api.md](contracts/registry-api.md): `enum TypeRole { behavior, component }`, `enum FieldType { int_, double_, bool_, string, enum_, vector2, color, imagePath, sprite, spriteAnimation, entityRef }` (each value documented with the Dart value its setter receives, [research.md R5](research.md#r5-field-types-their-checks-and-their-values)), `final class RegistryField({required name, required type, required nullable, required accepts, required set, values})`, `final class RegistryType({required id, required role, required create, required fields})` with `create` typed `Component Function()`, and `final class PyroRegistry(Iterable<RegistryType>)` with `operator [](TypeId)` and `types`; export it from `rt/lib/pyro_runtime.dart` and update that library's doc comment (the Registry contract is here; the loader still lands with #8)
- [X] T010 [P] Implement `gen/lib/src/checkers.dart`: the `TypeChecker`s of [research.md R3](research.md#r3-recognising-pyros-and-flames-types-without-depending-on-flame) as top-level constants, plus `bool isFlameVector2(DartType)`, `isColor`, `isSprite`, `isSpriteAnimation`, `isComponent`, `isBehavior`, `isEntityMixin`, `isPositionComponent` helpers that accept a `DartType` or `InterfaceElement` and handle aliases
- [X] T011 [P] Implement `gen/lib/src/diagnostics.dart`: `enum DiagnosticKind { error, warning }`, `enum DiagnosticCode` with every code of [contracts/manifest-v1.md § Codes](contracts/manifest-v1.md#codes) and its kind, `final class Diagnostic` (`code`, `message`, `file`, `line`, `typeId?`, `className?`, `field?`, `related`), `toJson`/`fromJson`, `compareTo` in the contract's sort order, and one message builder per code that names the file, class and field and says how to fix it (e.g. `duplicateTypeId`: "Type ID "Patrol" is used by Patrol (lib/a.dart:3) and Patrol (lib/b.dart:7). Give one of them an explicit id: in its annotation.")
- [X] T012 [P] Implement `gen/lib/src/manifest_json.dart`: a canonical JSON writer (sorted keys, two-space indent, LF, trailing newline; numbers per Q92: a `double` with no fractional part written as an integer, others with Dart's shortest `toString()`); `gen/lib/src/fragment.dart`: `ScanFragment`, `TypeRecord`, `RegistryEntry`, `RegistryFieldEntry`, `ClassKey` of [data-model.md § Intermediate](data-model.md#intermediate-scan-fragment-libpyrojson-build-cache-only) with `toJson`/`fromJson` (`ClassKey` serialized as `"<library uri>#<class name>"`)
- [X] T013 Implement the builder skeletons (depends on T010–T012): `gen/lib/src/scan_builder.dart` (`PyroScanBuilder`, `buildExtensions {'.dart': ['.pyro.json']}`, returns early for non-libraries and libraries outside `lib/`, writes a fragment only when it has types, holders or diagnostics); `gen/lib/src/aggregate_builder.dart` (`PyroAggregateBuilder`, `buildExtensions {r'$lib$': ['pyro.g.dart', 'pyro.manifest.json']}`, reads `findAssets(Glob('lib/**.pyro.json'))` sorted by path, writes both outputs, then logs errors with `log.severe` and warnings with `log.warning`, one record per diagnostic); `gen/lib/src/registry_emitter.dart` stub that emits the empty Registry of [contracts/registry-api.md](contracts/registry-api.md) (header, `import 'package:pyro_runtime/pyro_runtime.dart' as i0;`, `final pyroRegistry = i0.PyroRegistry(const []);`, formatted with `DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)`); `gen/lib/builder.dart` with documented factories `Builder pyroScan(BuilderOptions)` and `Builder pyroAggregate(BuilderOptions)` replacing the placeholder; `gen/build.yaml` per [research.md R2](research.md#r2-builder-shape-a-per-library-scan-and-a-lib-aggregator) (`pyro_scan`: `build_to: cache`, `auto_apply: dependents`, `runs_before: [pyro_generator:pyro_aggregate]`, `defaults: options: run_only_if_triggered: true`; `pyro_aggregate`: `build_to: source`, `auto_apply: dependents`, `required_inputs: [".pyro.json"]`; `triggers:` `annotation PyroBehavior`, `annotation PyroComponent`, `annotation Editable`). Delete the placeholder `gen/test/builder_test.dart`
- [X] T014 Write `gen/test/golden_test.dart` (depends on T003, T013): one test per directory under `gen/test/goldens/`, running `runGenerator` on its `input/` and calling `expectGolden` for the three expected files (a missing output compares as an absent file); add the first case `gen/test/goldens/empty/` (a `lib/game.dart` with no annotations) and generate its goldens: the empty Registry, `{"errors": [], "manifestVersion": 1, "types": [], "warnings": []}`, an empty log (US1 #9)

**Checkpoint**: `dart test` passes in `ann/`, `rt/test/loader/` and `gen/`; the `empty` golden passes

---

## Phase 3: User Story 1 - Annotate a Behavior and see it described (Priority: P1) 🎯 MVP

**Goal**: valid annotated classes of both roles, with every v1 Field type, inherited and mixin fields, defaults, supertypes and parent types, described in the Manifest and buildable through the Registry

**Independent Test**: run the Generator on an annotated fixture package and compare the Registry and the Manifest with their golden files (spec US1)

### Tests for User Story 1

- [X] T015 [P] [US1] Write `gen/test/classify_test.dart` for T020: run the scan (through `runGenerator`) on small classes and assert the fragment's Field types for `int`, `double`, `bool`, `String`, an enum, Flame's `Vector2`, `ImagePath`, `Sprite?`, `SpriteAnimation?`, `Component?`, a `PositionComponent` subclass, a `PositionedEntity` subclass, nullable variants, and a `typedef` alias of `double`; and that `num`, `dynamic`, `Object`, `List<int>`, `Map<String, int>`, a record, a function type, `vector_math_64`'s `Vector2`, a `Behavior` subclass, an enum with no values and a type-parameter-typed field are classified unsupported (the error itself is US2's)
- [X] T016 [P] [US1] Write `gen/test/defaults_test.dart` for T021: every row of [research.md R6](research.md#r6-defaults): no initializer on a nullable field → `default: null`, no `defaultSource`; `null`; `50` and `50.0` → `50`; `-3`; `-0.5`; `true`; `'text'`; `PatrolMode.loop` (and with an import prefix) → `"loop"`; `const ImagePath('assets/images/a.png')` and `ImagePath('…')` → `{"asset": "assets/images/a.png"}`; `Vector2(1, 0)` → `default: null, defaultSource: "Vector2(1, 0)"`; `'a' 'b'`, `'$x'`, `kSpeed`, `1 + 2` → source text
- [X] T017 [P] [US1] Write `gen/test/linearization_test.dart` for T022: fields of an unannotated superclass, of an annotated superclass (each type lists them), of a mixin applied to a superclass and of a mixin applied to the class itself, in the order "top of the chain down, each in declaration order" (FR-013); a field redeclared in the subclass appears once, at the superclass's position, with the subclass's declaration; `declaredIn` names the declaring class or mixin; a superclass in another library is read through its own library
- [X] T018 [P] [US1] Write `gen/test/imports_test.dart` for T023: a `Vector2` field in a file importing `package:flame/components.dart` gets that import (not `vector_math/src/…`), an enum declared in the same file uses the class's library, a `Sprite` field imported through `package:flame/components.dart`, two user types named `Player` in two libraries get distinct import prefixes and qualified references in the Registry (the compile check is in the fixture game, T027), an inherited field's type is searched in the superclass's library; the Registry imports are sorted and prefixed `i0`, `i1`, … (FR-025, research R10)
- [X] T019 [P] [US1] Add golden case `gen/test/goldens/full/` (written before T024 so it fails first): `input/lib/behaviors/patrol.dart` (the §6.1 `Patrol`: `@PyroBehavior(label: 'Patrol', category: 'Movement')`, doc comment, `Behavior<PositionedEntity>`, `@Editable(min: 0, max: 400, tooltip: 'Pixels per second') double speed = 50`, `Vector2 direction = Vector2(1, 0)`, `PatrolMode mode = PatrolMode.pingPong`, `Player? target`, `SpriteAnimation? hitEffect`, `ImagePath trail = const ImagePath('assets/images/trail.png')`), `input/lib/behaviors/blink.dart` (bare `Behavior`, so no `parentType`; `@Editable(label: 'Visible') bool visible = true`), `input/lib/components/player.dart` (`@PyroComponent(preview: 'assets/images/player.png') class Player extends PositionedEntity` with `int lives = 3`, `String nickname = 'p1'`, `Sprite? icon`), `input/lib/components/enemy.dart` (`@PyroComponent(id: 'enemy.base') class Enemy extends Hurtable with Glows`, where `abstract class Hurtable extends PositionComponent` (unannotated) declares `@Editable() int health = 10` and `mixin Glows on PositionComponent` declares `@Editable() double glow = 0.5`), `input/lib/components/boss.dart` (`@PyroComponent class Boss extends Enemy`, so `supertypes` starts `["enemy.base", …]`, plus `Enemy? minion`), `input/lib/components/coin.dart` (`part 'coin_part.dart';`) with `input/lib/components/coin_part.dart` holding `@PyroComponent class Coin extends PositionComponent`, so the golden pins `"source": "lib/components/coin_part.dart"` (spec Edge Cases). Expected Manifest and Registry follow [contracts/manifest-v1.md](contracts/manifest-v1.md) and [contracts/registry-api.md](contracts/registry-api.md); review the generated goldens by hand against both contracts before committing them

### Implementation for User Story 1

- [X] T020 [P] [US1] Implement Field type classification in `gen/lib/src/fields.dart`: `FieldClass? classify(DartType type)` returning the Manifest name, the `FieldType` value name, nullability, the enum's value names (for `enum`) and the referenced class (for `entityRef`), per [research.md R5](research.md#r5-field-types-their-checks-and-their-values); type aliases resolved; null for unsupported types
- [X] T021 [P] [US1] Implement `gen/lib/src/defaults.dart`: `DefaultValue readDefault(VariableDeclaration? declaration, FieldClass field)` returning `(Object? value, String? source)` per research R6, using the AST from `resolver.astNodeFor(field.firstFragment)`; numbers kept as `int` or `double` for T012's writer
- [X] T022 [US1] Implement `gen/lib/src/introspect.dart` (depends on T010, T020, T021): for an annotated `ClassElement`, the Type ID (`id` or class name), role, label (annotation `label` or class name), category, doc (`///` stripped, joined with `\n`, trimmed), `source` (the package-relative path of the file holding the class declaration, from the class's first fragment's source, so a class in a `part` file reports the part file, spec Edge Cases), supertypes per [research.md R4](research.md#r4-class-level-rules-and-what-each-records) (superclass chain nearest first, stopping after `Component` or `Behavior`, mixin applications skipped; annotated classes named by their Type ID, read from their annotation), `parentType` (omitted for `EntityMixin`), `acceptsBehaviors`, `preview`; the linearization (`ClassKey`s, top-down, superclasses then their mixins) and the merged `@Editable` field list of FR-013 with `declaredIn`
- [X] T023 [US1] Implement `gen/lib/src/imports.dart` (depends on T022): `String? importFor(InterfaceElement type, LibraryElement from)` searching `from.firstFragment.libraryImports` in source order for an imported library whose `exportNamespace` holds `type` and whose URI has no `/src/` segment in another package, `dart:ui` accepted directly, the declaring library used for the package's own types; null when nothing matches (the error is US2's)
- [X] T024 [US1] Wire the scan in `gen/lib/src/scan_builder.dart` (depends on T022, T023): for each annotated class, build a `TypeRecord` with its Manifest entry (keys of [contracts/manifest-v1.md § Type](contracts/manifest-v1.md#type) and [§ Field](contracts/manifest-v1.md#field): `name`, `type`, `nullable`, `default`, `defaultSource`, `label`, `tooltip`, `min`, `max`, `values`, `refType`, `declaredIn`) and its `RegistryEntry` (class import, field type imports from T023)
- [X] T025 [US1] Implement the Manifest side of `gen/lib/src/aggregate_builder.dart` and `gen/lib/src/manifest_emitter.dart` (depends on T024): merge valid records, sort types by Type ID, write `lib/pyro.manifest.json` through T012's writer
- [X] T026 [US1] Implement `gen/lib/src/registry_emitter.dart` in full (depends on T024): imports `pyro_runtime`, each class library and each field type library, deduplicated, sorted by URI, prefixed `i0…`; one `RegistryType` per type in Type ID order with `id: const iN.TypeId('…')`, `role`, `create: iN.Class.new`, and a `fields` map in Manifest order, each `RegistryField` with `type`, `nullable`, `values: iN.Enum.values` for enums, `accepts: (v) => v is T` (or `v == null || v is T` when nullable) and `set: (t, v) => (t as iN.Class).field = v as T` (`T?` when nullable); `// ignore_for_file: type=lint`; formatted with `dart_style`. Make `full` and `empty` goldens pass (T014, T019)
- [X] T027 [US1] Fill `game/lib/`: `behaviors/patrol.dart`, `behaviors/blink.dart`, `components/player.dart`, `components/enemy.dart`, `components/boss.dart` like T019's case but against real Flame, plus `components/lamp.dart` (`@PyroComponent class Lamp extends PositionComponent` with `@Editable() Color tint = const Color(0xFFFFFFFF)` and `Color? glow`), so every v1 Field type appears at least once (FR-011); and `components/legacy/player.dart` with `@PyroComponent(id: 'legacy.player') class Player extends PositionComponent` beside `components/player.dart`, plus an `@Editable() Player? buddy` field typed with each in a Behavior, so the committed Registry has to compile with both (FR-025); import annotations through `package:pyro_runtime/pyro_runtime.dart` in at least one file and directly from `pyro_annotations` in another (Q44, FR-005; add `pyro_annotations` as a dependency of `game/`)
- [X] T028 [P] [US1] Write `game/test/registry_test.dart`: for every type in `pyroRegistry.types`, `create()` returns an instance of the class; for every field, `accepts` takes a valid value of its type (and `null` exactly when `nullable`) and rejects a wrong-typed one, and `set` assigns it (read back from the instance); enum fields' `values` equal the enum's `values`; the Manifest (`File('lib/pyro.manifest.json')`) and the Registry list the same Type IDs in the same order and the same field names per type (SC-005, SC-006)
- [X] T029 [US1] Run `dart run build_runner build -d` in `game/` (no `build.yaml` there, FR-027, US3 #6), check `lib/pyro.manifest.json` against [contracts/manifest-v1.md](contracts/manifest-v1.md) and `lib/pyro.g.dart` against [contracts/registry-api.md](contracts/registry-api.md) by hand, then `flutter analyze --fatal-infos`, `flutter analyze --fatal-infos lib/pyro.g.dart` and `flutter test` in `game/` (SC-005). Prove the Registry step checks the file: add `int _probe = 'x';` to `lib/pyro.g.dart`, see `flutter analyze lib/pyro.g.dart` fail, then revert. Run `dart format --output=none --set-exit-if-changed game/lib/pyro.g.dart`: if the SDK formatter disagrees with the package `dart_style` output, exclude `**/pyro.g.dart` from the CI format step and say why in a comment (plan.md, Risks)
- [X] T030 [US1] Commit `game/lib/pyro.g.dart` and `game/lib/pyro.manifest.json`; confirm T004's CI steps pass locally (regenerate, `git diff --exit-code`, analyze, test)

**Checkpoint**: the `full` and `empty` goldens pass; the fixture game builds, analyzes clean and its Registry test passes

---

## Phase 4: User Story 2 - Get a clear error for every broken rule (Priority: P1)

**Goal**: every build-time rule reports an error or warning naming file, line, class and field; erroneous and colliding classes leave both outputs; both files are written before the build fails

**Independent Test**: run the Generator on one fixture per rule and compare its Manifest (with the errors), its Registry and its log with golden files; check that the build reports failure (spec US2)

### Tests for User Story 2

- [X] T031 [P] [US2] Add one golden case per class-level error under `gen/test/goldens/errors/`, each with one offending class and one valid class (which must stay in both outputs, US2 #7): `both_annotations`, `private_class` (`_Patrol`), `abstract_class`, `sealed_class` (code `abstractClass`), `generic_class` (`Patrol<T>`), `bad_constructor_required` (`Patrol(this.speed)`), `bad_constructor_named_only` (only `Patrol.make()`), `not_position_component` (`@PyroComponent class X extends Component`), `not_behavior` (`@PyroBehavior class X extends PositionComponent`), `bad_type_id_empty` (`id: ''`), `bad_type_id_space` (`id: 'enemy base'`), `parent_type_not_class` (`Behavior<SomeMixin>` where `mixin SomeMixin on EntityMixin`), `missing_runtime` (`input/no_runtime`). Also `optional_constructor_ok` (`Patrol({this.speed = 1})`, no error)
- [X] T032 [P] [US2] Add one golden case per field-level error and warning under `gen/test/goldens/errors/`: `unsupported_map` (`Map<String, int> loot = {}`), `unsupported_list`, `unsupported_vector64`, `unsupported_behavior_ref` (`Patrol? other`), `unsupported_empty_enum`, `unreachable_field_type` (a type only reachable through an import that doesn't export it, e.g. a `part`-declared alias; adjust to the case `imports_test.dart` found), `field_private`, `field_final`, `field_const`, `field_static`, `field_no_default` (`double speed;` and `late double speed;`), `field_must_be_nullable` (`Player target = Player();`, `Sprite icon`, `SpriteAnimation fx`), `editable_on_getter`, `editable_on_setter`, `editable_abstract` (in an abstract unannotated superclass), `range_on_string` (`@Editable(min: 0) String s = ''`), `min_above_max` (`min: 10, max: 1`), `default_out_of_range` (warning; `@Editable(min: 0, max: 10) double d = -1`; the type stays in both outputs and the log has only a `WARNING` line), `unused_editable` (warning; an unannotated class with an `@Editable` field that no annotated class extends; plus a mixin used by an annotated class, which produces nothing), `two_errors_one_class` (both errors reported, class left out once)
- [X] T033 [P] [US2] Add collision golden cases under `gen/test/goldens/collisions/`: `same_class_name` (`Patrol` in `lib/a.dart` and `lib/b.dart`), `same_explicit_id` (`id: 'enemy'` on two classes), `three_way`, `erroneous_and_valid` (one `Patrol` with a bad constructor, one valid: both left out, both the `badConstructor` and the `duplicateTypeId` error reported, research R8). Each error lists every class in `related`; neither class appears in the Registry or `types` (US2 #1, FR-009)
- [X] T034 [P] [US2] Write `gen/test/failure_test.dart`: for a failing case, the build result reports failure, both outputs are still written (US2 #7, FR-020), and re-running the builders on the same inputs logs the same errors again (US2 #9); fixing the input on a second run (replace the bad source) gives the `full`-style outputs with no errors

### Implementation for User Story 2

- [X] T035 [US2] Add the class-level rules to `gen/lib/src/introspect.dart` per [data-model.md § Annotated class](data-model.md#annotated-class): `bothAnnotations`, `privateClass`, `abstractClass` (abstract or sealed), `genericClass`, `badConstructor` (no unnamed constructor, or any required parameter), `notPositionComponent`, `notBehavior`, `badTypeId` ("non-empty, no whitespace"), `parentTypeNotClass`; each a `Diagnostic` with `file`, the 1-based `line` of the class name (`library.lineInfo`), `className` and `typeId`; a record with any error gets `valid: false` but keeps its Type ID and linearization (research R8)
- [X] T036 [US2] Add the field-level rules to `gen/lib/src/fields.dart` and `gen/lib/src/introspect.dart` per [data-model.md § Editable field](data-model.md#editable-field): `unsupportedFieldType` (message names the declared type, and for `vector_math_64` suggests Flame's `Vector2`), `fieldNotPublic`, `fieldFinal`, `fieldStatic`, `fieldNoDefault` ("any non-nullable field needs an initializer", `late` included), `fieldMustBeNullable` ("entity reference, `Sprite`, `SpriteAnimation` must be nullable"), `editableOnAccessor`, `editableNotConcrete`, `rangeOnNonNumeric` ("`min`/`max` only on `int`/`double`"), `minAboveMax` ("`min ≤ max`"), `defaultOutOfRange` (warning, "evaluated default within range"), and `unreachableFieldType` from T023's null; errors on inherited fields name the subclass in `className`/`typeId` and the declaring file and line
- [X] T037 [US2] Record `@Editable` holders in the scan (`gen/lib/src/scan_builder.dart`): every unannotated class or mixin in the library with at least one `@Editable` field, as a `ClassKey` plus its file, line and first field name
- [X] T038 [US2] Add the cross-library rules to `gen/lib/src/aggregate_builder.dart` per [data-model.md § Aggregation](data-model.md#aggregation): group every record (valid or not) by Type ID, emit one `duplicateTypeId` per group of two or more with all classes in `related` (sorted by file, line) and drop them all; drop `valid: false` records; `unusedEditable` for holders in no record's linearization; `missingRuntime` when `buildStep.canRead(AssetId('pyro_runtime', 'lib/pyro_runtime.dart'))` is false (`file: pubspec.yaml`, `line: 1`; `canRead` rather than `packageConfig`, so the in-memory stub of T003 counts); merge with the fragments' diagnostics, sort (T011), write `errors` and `warnings`, then log. Make every golden of T031–T034 pass and review each generated message by hand: it names the file, the class (and field) and says how to fix it (SC-002)
- [X] T039 [US2] Run quickstart §3 in `game/` by hand: an unsupported `Map` field fails the build with the error in the log and in `errors`, `Patrol` leaves both files, the other types stay, and reverting restores both files byte for byte; `git checkout` afterwards

**Checkpoint**: every golden under `errors/` and `collisions/` passes; each code of the contract has at least one case (SC-002)

---

## Phase 5: User Story 3 - Committed output that never drifts (Priority: P1)

**Goal**: byte-identical outputs across runs, file orders and OSes; untouched files when nothing a reader sees changes

**Independent Test**: build the fixture package twice from a clean cache, and on two operating systems, and compare bytes; make each kind of edit and check which file changes (spec US3)

### Tests for User Story 3

- [X] T040 [P] [US3] Write `gen/test/stability_test.dart`: the `full` case's inputs with files renamed so they sort in a different order, and with classes reordered within a file, give byte-identical outputs (US3 #3); a method-body edit and an edit to an unannotated file give byte-identical outputs to before (US3 #4); a tooltip-only, label-only, category-only and doc-only edit change the Manifest and leave the Registry byte-identical (US3 #5); removing the last annotation from a library removes its fragment and its type from both outputs (plan.md, Risks); neither output contains the absolute path of the temp or package directory, a timestamp, or `\r` (US3 #2)
- [X] T041 [P] [US3] Write `gen/test/triggers_test.dart`: `gen/build.yaml` parses (with `package:build_config`, already in the lock) to the two builders, `auto_apply: dependents`, `run_only_if_triggered: true` for `pyro_scan`, and the three triggers (FR-027, FR-028); a library with no Pyro annotation produces no fragment

### Implementation for User Story 3

- [X] T042 [US3] Fix whatever T040 and T041 find in `gen/lib/src/`: sort every list the contract orders (types, fields kept in linearization order, enum values in declaration order, diagnostics, imports), never iterate a `Map` or `Set` built from build_runner's input order without sorting, write paths with `/` only, and emit no content that depends on the run (research R7)
- [ ] T043 [US3] Clean-cache check in `game/`: `rm -rf .dart_tool/build && dart run build_runner build -d && git diff --exit-code -- lib/pyro.g.dart lib/pyro.manifest.json` twice (US3 #1); after the branch is pushed, confirm T004's regenerate-and-diff step passes on the macOS, Windows and Linux CI runners (SC-003)
  - *Spec 005 (Q118):* CI also regenerates `example/`'s files on all three OSes; that confirms the CI part there. The clean-cache run here stays open.
  - *CI half confirmed (2026-10-22):* T004's fixture-game regenerate-and-diff was green on the macOS, Windows and Linux runners in the `CI` run on `main` after PR #14 merged (run 39771649079; first seen in run 39743736278, spec 005 T031). Only the local clean-cache run above stays open.

**Checkpoint**: stability and trigger tests pass; CI's regenerate-and-diff step is green on three OSes

---

## Phase 6: User Story 4 - Fast feedback while Pyro watches (Priority: P2)

**Goal**: the Generator stays within the watch budget on a mid-size Flame project

**Independent Test**: on a synthetic mid-size project, measure the time from a save to the Manifest update in `build_runner watch`, as spike #2 did (spec US4)

- [X] T044 [US4] Adapt spike #2's harness (spikes are exempt from the constitution) in `spikes/02_generator/bench/bin/gen_project.dart`: a `--pyro` flag that depends on the workspace's `pyro_annotations` and `pyro_generator` by path, emits `@PyroBehavior`/`@PyroComponent`/`@Editable` with `ImagePath` and the other preview Field types, and watches `lib/pyro.manifest.json` and `lib/pyro.g.dart` in `bench/bin/measure.dart` instead of the `flame_studio.*` files (research R13)
- [ ] T045 [US4] On the reference Mac (macOS, Apple M4, Flutter 3.44.2), generate 300 files / 42 annotated with `--pyro`, build once, and run `measure.dart --runs 5` (quickstart §4); pass if the median "Manifest updated" time for an annotated save is under 3 s (SC-004). Record the table, the configuration and the first-save time in `dev-docs/ARCHITECTURE.md` under a new "Generator" section next to spike #2's results. If this can't run on the reference Mac in the implementing session, leave the task open and say so in the PR

**Checkpoint**: SC-004 measured and recorded

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: documentation in sync, package docs, final checks

- [X] T046 [P] Update `GLOSSARY.md` (plan.md, Documentation updates): add **Image path**, **Generator error**, **Generator warning** and **Parent type**, each one line in the file's style
- [X] T047 [P] Add decisions from Q100 to `dev-docs/decisions.md`, each citing "Generator spec, 2026-10-20": every v1 Field type in #7 now; `ImagePath` from `pyro_annotations`; entity reference, `Sprite` and `SpriteAnimation` fields must be nullable; `@Editable` on plain fields only; unused `@Editable` is a warning; the `manifestVersion` rule (FR-015a); `min > max` is an error and an out-of-range default a warning; games need no `build.yaml` (FR-027); collisions drop every class sharing the ID, erroneous ones included (research R8)
- [X] T048 Update `dev-docs/project-plan.md` and `dev-docs/phases.md` in one commit (phases.md sync rule): §6.1 (annotations and `ImagePath` as built, the added rules of spec FR-013a, FR-011, FR-025a); §7.3 (Manifest as in [contracts/manifest-v1.md](contracts/manifest-v1.md): sorted keys, `warnings`, `nullable`, `declaredIn`, codes; `build.yaml` no longer required); §14 and phases.md: the remaining Field types move into the preview's #7, with the new estimates **as the author sets them** (plan.md suggests 4.5 → ~6.5 and Phase 7's "#7 Generator (2)" → removed; ask before writing numbers), the README recipe and "Add Pyro" no longer add `build.yaml`; tick #7 in phases.md with a link to `specs/003-generator/spec.md` and the Q numbers of T047
- [X] T049 [P] Write `gen/README.md` and `ann/README.md`: what each package does, the `pubspec.yaml` lines a game needs (`pyro_runtime`, dev `pyro_generator` and `build_runner ≥ 2.14`), that no `build.yaml` is needed, the two output files and that they are committed, and the CI check of §7.3 (Q76); add a 0.0.1 entry to both `CHANGELOG.md` files and to `rt/CHANGELOG.md` for the Registry contract
- [X] T050 Check FR-031's upper end: in a throwaway pure-Dart project in the scratchpad (outside the workspace), depend on `pyro_generator` and `pyro_annotations` by path, `dart pub upgrade` so it resolves the newest `analyzer`, `build`, `source_gen` and `dart_style` the ranges allow, copy `gen/test/` in and run `dart test` against that resolution. Record both ends' versions in `dev-docs/ARCHITECTURE.md`'s Generator section; if an API differs, use the form that works at both ends, or narrow the range and record why (spike #2 finding 1)
- [X] T051 Run the repository's checks: `dart format --output=none --set-exit-if-changed packages apps`, `dart analyze --fatal-infos packages/pyro_annotations packages/pyro_generator`, `flutter analyze --fatal-infos packages/pyro_runtime packages/pyro_ui apps/editor packages/pyro_generator/fixture_game`, `dart test` in `ann/` and `gen/`, `flutter test` in `rt/` and `game/`; walk through [quickstart.md](quickstart.md) §1–§3
- [X] T052 Self-review the change against the constitution (plan.md, Constitution Check): `pyro_generator`'s `pubspec.yaml` has no `pyro_runtime`, `flame` or `flutter`; every public member is documented; every diagnostic names file, class and field; the generated Registry has no `src/` import of another package; and note in `dev-docs/ARCHITECTURE.md`'s Generator section what was verified (data contract change, constitution workflow rule)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none; T002 before T004's fixture steps can pass
- **Foundational (Phase 2)**: after Setup; blocks every story
- **US1 (Phase 3)**: after Foundational
- **US2 (Phase 4)**: after US1 (its rules live in the files US1 creates, and its goldens need a working valid path for the "one valid class" in each case)
- **US3 (Phase 5)**: after US1; can run alongside US2 (T040/T041 touch only new test files), but T042 should land after US2 so the sort covers diagnostics
- **US4 (Phase 6)**: after US1; independent of US2 and US3
- **Polish (Phase 7)**: after all stories

### Within Each Story

- Tests (and golden inputs) first, failing, then the implementation
- `fields.dart` and `defaults.dart` before `introspect.dart`; `introspect.dart` before `imports.dart` and the scan; the scan before both emitters
- Each story's checkpoint passes before the next story starts

### Parallel Opportunities

- Setup: T003, T004 (after T001, T002)
- Foundational: tests T005–T007 together; T008–T012 together; then T013, T014
- US1: tests T015–T019 together; T020 and T021 together; T028 alongside T026
- US2: T031–T034 together
- US3: T040, T041 together; US3 alongside US2 up to T042
- US4 alongside US2 and US3
- Polish: T046, T047, T049

---

## Parallel Example: User Story 1

```bash
# Tests and golden inputs for User Story 1, together:
Task: "Write gen/test/classify_test.dart"
Task: "Write gen/test/defaults_test.dart"
Task: "Write gen/test/linearization_test.dart"
Task: "Write gen/test/imports_test.dart"
Task: "Add golden case gen/test/goldens/full/"

# Then the two leaf modules, side by side:
Task: "Implement Field type classification in gen/lib/src/fields.dart"
Task: "Implement gen/lib/src/defaults.dart"
```

## Parallel Example: User Story 2

```bash
# All golden cases and the failure test, together:
Task: "Add class-level error golden cases under gen/test/goldens/errors/"
Task: "Add field-level error and warning golden cases under gen/test/goldens/errors/"
Task: "Add collision golden cases under gen/test/goldens/collisions/"
Task: "Write gen/test/failure_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup
2. Phase 2: Foundational
3. Phase 3: US1
4. **Stop and validate:** the `full` golden passes and the fixture game's Registry builds every type and sets every field

### Incremental Delivery

1. Setup + Foundational → annotations, Registry contract, two builders writing empty outputs
2. US1 → valid types described and buildable (MVP)
3. US2 → every rule reported; collisions safe
4. US3 → deterministic, CI-checked on three OSes
5. US4 → watch latency measured
6. Polish → docs and decisions in sync, #7 ticked

Phase 2's "Done when" needs the goldens including the error cases, so US1 and US2 are both
required before #7 counts as done; US3 is what lets #12's contract test rely on the committed
files.

---

## Notes

- [P] tasks = different files, no dependencies on unfinished tasks
- Commit after each task or logical group (Conventional Commits, citing Q numbers where one
  applies), on `specs/003-generator`
- Review every generated golden by hand before committing it: a golden only pins what it holds
- Stop at any checkpoint to validate a story on its own
