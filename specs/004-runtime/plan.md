# Implementation Plan: Runtime

**Branch**: `specs/004-runtime` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-runtime/spec.md`

## Summary

Build #8, the Runtime's loader, in `pyro_runtime/lib/src/loader/`, on the Scene format (spec 001)
and the Registry contract (spec 003):

- **`PyroScene.load`** decodes a Scene with `SceneCodec`, warns about repairs, and runs a four-pass
  `SceneBuilder` into a detached `BuiltScene`: construct, configure (assets loaded concurrently,
  Overrides converted), resolve references, attach. Only a complete build becomes a
  `PyroScene`'s children, so failed loads and failed Hot-swaps leave nothing behind.
- **Built-in kinds** map to a new `PyroEntity`, `SpriteComponent`, `RectangleHitbox` and
  `CircleHitbox`.
- **Lookups** scan a tree-ordered entry list.
- **Assets** go through a two-method `AssetSource`, a bundle-backed one by default, with no
  prefix and no Flame globals.
- **`.anim.json`** gets a strict reader next to the Scene format.
- **Hot-swap** (debug only) overrides `onHotReload`, compares the kept file texts exactly, rebuilds
  on change, swaps, watches removed components for stale use, and calls `onReloaded`.

Two shared contracts change in the same item:
- `AssetRef` gains an optional `animation` key for `SpriteAnimation` Overrides (FR-034).
- `RegistryType` gains `acceptsParent`, which the Generator emits for Behaviors (research R6).

## Technical Context

**Language/Version**: Dart ^3.12, Flutter 3.44.2 (the repository's pin, Q94)

**Primary Dependencies**: `pyro_runtime`: Flutter, `flame` 1.38.2 (range `>=1.36.0 <2.0.0`),
`flame_behaviors` 1.4.0, `pyro_annotations`, unchanged (FR-033, research R1); dev `flame_test`
2.3.1, `flutter_test`. `pyro_generator`: unchanged dependencies, one emitter change.
`fixture_game`: unchanged dependencies, gains an asset folder.

**Storage**: none. The Runtime reads Scene files, animation files and images through an
`AssetSource` and writes nothing

**Testing**: `flutter test` in `pyro_runtime` with `flame_test`, a memory `AssetSource` and a
hand-written Registry (research R15). Generator goldens via `dart test`. `fixture_game`'s
`flutter test` loads a Scene with the real generated Registry. A load benchmark under
`flutter test`. Manual Hot-swap and release checks on the reference Mac (quickstart §5)

**Target Platform**: inside games on every platform Flutter and Flame support. Hot-swap in debug
builds only

**Project Type**: library (the shipped runtime package) plus small changes to the Generator and
its fixture

**Performance Goals**: 1,000-Node Scene loaded in < 50 ms median excluding image decoding; a
no-op Hot-swap check < 5 ms; a rebuild < 100 ms (SC-004, constitution III); the longest
synchronous pause during a load and a rebuild measured, with its limit set after T043 (spec
Clarifications); zero per-frame work after load (FR-032)

**Constraints**: no new dependency in `pyro_runtime` (constitution II); every Hot-swap path
behind `kDebugMode` (constitution III); nothing read from `Flame.images`, `Flame.assets` or
`Flame.bundle` when a source is given (FR-030); a failed load or rebuild leaves no partial Scene
(FR-004, FR-026); the Generator still never depends on the Runtime

**Scale/Scope**: Scenes up to ~1,000 Nodes (the constitution's reference size); 6 Node kinds of
`schemaVersion` 1; 11 Field types; ~12 error cases (US2)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Pre-research | Post-design |
|---|---|---|---|
| I. Clean Code | Glossary names; public API documented; errors name Scene, Node, Type ID, field, path; immutable data; no speculative abstraction | ✅ | ✅ one `SceneLoadException` carrying every name (contracts/runtime-api.md); the builder's passes are private functions, not a framework; `AssetSource` has two real callers (bundle, Pyro's disk source in #4) plus the test double; `BuiltScene` and `AnimationFile` are immutable; new glossary terms below |
| II. Modular Boundaries | Runtime stays small; the scene model and its formats live here; boundary changes stated | ✅ | ✅ no new dependency (R1); the `.anim.json` reader lives next to the Scene format (R7); the `RegistryType` change is a stated contract change made with the Generator in one commit (R6); `pyro_generator` still doesn't import the Runtime (it emits text) |
| III. Performance by Design | Budget stated and measured; no per-frame work; debug-only Hot-swap behind `kDebugMode`; async I/O | ✅ | ✅ SC-004 budgets with a benchmark (R15, quickstart §4); the "must not block a frame" rule is measured (longest isolate pause) before a limit is set, by the author's choice (spec Clarifications), and revisited in T043; `PyroScene` overrides no `update`/`render` (R14); stale watchers only on removed components (R12); assets loaded concurrently (R4); no-op reloads compare text before decoding (R11) |
| IV. User Data Integrity | Runtime never writes user files; unknown data never silently misread | ✅ | ✅ the Runtime only reads; unknown Type IDs fail by default (Q58); unused Overrides warn, never vanish from the file (FR-012); the `AssetRef` amendment keeps every other value shape verbatim and doesn't need a `schemaVersion` bump (R13) |
| V. Tested Core | Runtime loader is Heavy: tests for every behavior; deterministic | ✅ | ✅ a test file per user story plus format tests (quickstart §1); memory asset source and in-test images, no files, network or clocks; Hot-swap driven through `game.onHotReload()`; an end-to-end load with the real Registry in `fixture_game` |

Technology constraints: Flame floor 1.36 for `onHotReload` ✅; no `dart:mirrors` ✅ (parent checks
come from generated code, R6); MIT-compatible dependencies ✅ (none added).

**Result:** passes, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/004-runtime/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R15
├── data-model.md              # Phase 1: PyroScene, BuiltScene, passes, AnimationFile, errors
├── quickstart.md              # Phase 1: how to validate
├── contracts/
│   ├── runtime-api.md         # PyroScene, PyroEntity, AssetSource, SceneLoadException; amended RegistryType and AssetRef
│   └── anim-file-v1.md        # *.anim.json reading rules
├── checklists/
│   └── requirements.md        # Spec quality checklist
└── tasks.md                   # Phase 2 (/speckit-tasks; not created here)
```

### Source Code (repository root)

```text
packages/pyro_runtime/
├── lib/pyro_runtime.dart                    # + exports (contracts/runtime-api.md "Exports")
├── lib/src/
│   ├── scene/overrides.dart                 # AssetRef.animation (R13)
│   ├── animation/
│   │   ├── animation_file.dart              # AnimationFile, AnimationGrid, AnimationClip
│   │   ├── animation_codec.dart             # strict reader (reuses scene/json/strict_reader.dart)
│   │   └── sprite_sheet.dart                # frame → cell math, SpriteAnimation factory
│   ├── assets/asset_source.dart             # AssetSource, the bundle source (R8)
│   └── loader/
│       ├── registry.dart                    # + RegistryType.acceptsParent (R6)
│       ├── repair_warning.dart              # unchanged
│       ├── pyro_scene.dart                  # PyroScene, UnknownType, SceneReloaded, load, lookups
│       ├── pyro_entity.dart                 # PyroEntity
│       ├── scene_builder.dart               # the four passes → BuiltScene (R4)
│       ├── built_scene.dart                 # BuiltScene, NodeEntry, path matching (R10)
│       ├── builtin_nodes.dart               # built-in kind → component (R3)
│       ├── field_values.dart                # Override conversion (R5)
│       ├── load_exception.dart              # SceneLoadException
│       ├── load_warnings.dart               # skip and unused-Override warnings
│       └── hot_swap.dart                    # change check, StaleWatch (R11, R12)
├── test/
│   ├── support/                             # memory_asset_source.dart, test_registry.dart, images.dart
│   ├── fixtures/loader/                     # *.scene.json, *.anim.json per scenario (already -text)
│   ├── loader/                              # quickstart §1 files
│   ├── animation/animation_file_test.dart
│   ├── assets/asset_source_test.dart
│   └── scene/overrides_test.dart            # + AssetRef.animation cases
└── benchmark/load_benchmark_test.dart       # SC-004

packages/pyro_generator/
├── lib/src/registry_emitter.dart            # emit acceptsParent for Behaviors
├── test/goldens/*/pyro.g.dart.golden        # regenerated: + acceptsParent
└── fixture_game/
    ├── pubspec.yaml                         # + flutter: assets: [assets/scenes/, assets/images/, assets/anims/]
    ├── assets/                              # fixture.scene.json, a small spritesheet, one .anim.json
    ├── lib/pyro.g.dart                      # regenerated: + acceptsParent
    └── test/load_test.dart                  # loads the Scene with the real Registry (quickstart §3)
```

**Structure Decision**: the loader goes where project-plan §5 puts it
(`pyro_runtime/lib/src/loader/`), split so each research decision has its own file and test.
`AssetSource` gets `lib/src/assets/` because Pyro's disk source (#4) implements it without
touching the loader. The animation reader sits beside `lib/src/scene/` because it is a file
format the Runtime owns (constitution II). The end-to-end check reuses spec 003's `fixture_game`
rather than starting `example/`, which is #13's job in Phase 3.

### Documentation updates in the same change

- `GLOSSARY.md`:
  - add **Asset source** (where the Runtime and Pyro read files, by project-relative path);
  - add **Animation file** (`.anim.json`);
  - add **Stale reference** (a component of a Node a Hot-swap removed);
  - mention `PyroEntity` under **Entity**;
  - say under **Hot-swap** that it rebuilds only on changed content.
- `dev-docs/decisions.md`, from Q109:
  - `SpriteAnimation` Overrides are `{"asset", "animation"}`, with no `schemaVersion` bump;
  - the stale-reference warning's detection scope (amends Q71's ◇);
  - Hot-swap compares the kept file texts, no hash (refines Q67);
  - `RegistryType.acceptsParent` (extends Q57);
  - unknown Custom components and Node kinds are skipped with their subtree (details Q58);
  - missing assets fail the load.
- `dev-docs/project-plan.md`:
  - §6.2: the API as built; the loading order is no longer ◇ proposed; the stale-reference
    mechanism;
  - §7.1: the `SpriteAnimation` written form;
  - §10: `AssetSource` as built;
  - §14: #8's estimate, if it moved (Risks).
- `dev-docs/phases.md`: the same §14 change in the same commit (sync rule); tick #8 when done. Phase
  2's done-when is then met.
- `specs/001-scene-format/contracts/scene-file-v1.md` and `specs/003-generator/research.md` R5:
  the amended written-form table (R13).
- `dev-docs/ARCHITECTURE.md`: a "Runtime" section with the SC-004 table, the manual Hot-swap run and
  the release check (quickstart §4, §5).

## Risks

- **Estimate.** §14 gives #8 four evenings. The animation reader, the two contract amendments and
  the stale watch weren't priced in. Expect ~5. Note it in §14 and phases.md when #8 is done, not
  before.
- **Read, not run.** The Flame facts in research (abstract `PositionedEntity`, hitbox fill rule,
  the `onHotReload` path, `mounted` futures) come from reading the sources, with no SDK in the
  planning session. The first task is a small `flame_test` that pins each one, so a wrong
  assumption fails on day one instead of mid-build.
- **`Transform2D` listeners.** `PositionComponent` may notify its own transform listeners during
  removal, or when a parent changes. A warning fired by Flame itself, not game code, would be a
  false alarm. `stale_reference_test.dart` checks that removal and the swap alone fire nothing.
- **Unmounted queued children.** Building whole subtrees with `add` on unmounted parents relies on
  Flame's lifecycle queue (R4). If a deep tree mounts children in an unexpected order, `onLoad`
  could see a parent not yet loaded. `build_test.dart` asserts the `onLoad` order on a three-level
  tree.
- **Line endings.** New Scene and animation fixtures go under `test/fixtures/`, which
  `.gitattributes` already marks `-text`. `fixture_game/assets/**` needs the same line.

## Complexity Tracking

No constitution violations to justify.
