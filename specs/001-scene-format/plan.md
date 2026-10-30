# Implementation Plan: Scene Format

**Branch**: `001-scene-format` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-scene-format/spec.md`

## Summary

Define `schemaVersion` 1 of the Scene file and the code on both sides of it, in `pyro_runtime`:
an immutable Node model for the early preview's Node kinds, a strict reader that refuses
duplicate keys and newer versions, a deterministic tree repair for merge damage, and a canonical
writer whose output is byte-identical on every platform. It is pure Dart with no new
dependencies; Pyro's Document model (#2) and the Runtime loader (#8) build on it.

## Technical Context

**Language/Version**: Dart ^3.12 (Flutter ≥ 3.44 for the package; the format code itself is
pure Dart, research R5)

**Primary Dependencies**: none new. Format code uses `dart:core` only; the debug warning uses
Flutter's `foundation` (`kDebugMode`, `debugPrint`), already a dependency of `pyro_runtime`

**Storage**: `*.scene.json` text files; reading and writing files on disk belongs to the
callers (#2's atomic save, #8's asset loading)

**Testing**: `flutter test` in `packages/pyro_runtime` with fixture files; a standalone
benchmark run with `dart run` (JIT) and `dart compile exe` (AOT)

**Target Platform**: everywhere a Flame game runs (Android, iOS, web, macOS, Windows, Linux),
plus Pyro on macOS

**Project Type**: library (a module inside the `pyro_runtime` package)

**Performance Goals**: decode, and separately encode, a 1,000-Node Scene in < 100 ms (median,
AOT, reference Mac; SC-006). Expected ~10–35 ms for decoding (research R1)

**Constraints**: no Flutter or Flame imports under `lib/src/scene/`; output byte-identical on
the VM and on the web (R3); reading never writes; synchronous and isolate-friendly (R9)

**Scale/Scope**: about 1,000 Nodes and ~0.5 MB per Scene; 6 Node kinds plus unknown kinds; 7
repair cases

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Pre-research | Post-design |
|---|---|---|---|
| I. Clean Code | Immutable models; names from `GLOSSARY.md`; errors name Node, key and Type ID; public API documented; no speculative abstractions | ✅ | ✅ Hand-written immutable classes (R4); every exception names its location (data-model.md); "Repair report" added to the glossary in the same change |
| II. Modular Boundaries | Format lives only in `pyro_runtime`; no new dependency; public surface through `pyro_runtime.dart` | ✅ | ✅ `lib/src/scene/` is pure Dart, enforced by a test (R5); the JSON reader and writer stay private; the `kDebugMode` warning is kept in `lib/src/loader/` |
| III. Performance by Design | Hot path has a stated budget and a measurement | ✅ SC-006: 100 ms | ✅ Benchmark in `benchmark/` (quickstart §4); synchronous, isolate-friendly API (R9); debug warning tree-shaken in release |
| IV. User Data Integrity | Preserve the unknown; refuse newer versions; never write on read | ✅ | ✅ `extra` maps and `UnknownNode` (data-model.md); version check before interpreting; duplicate keys refused (R1); repair changes only `childIds` (R8) |
| V. Tested Core | Serialization layer is Heavy: round trips per kind, fixtures per repair case | ✅ | ✅ Test map in quickstart §1: canonical fixtures act as goldens; one damaged fixture per issue with its expected output |

**Result:** passes, no violations. The custom JSON reader is extra code, but no principle
forbids it and FR-026 plus Principle IV require it (R1), so it isn't listed under Complexity
Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-scene-format/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R9
├── data-model.md        # Phase 1: types, invariants, issues and errors
├── quickstart.md        # Phase 1: how to validate
├── contracts/
│   ├── scene-file-v1.md # The file format and its canonical form
│   └── dart-api.md      # What pyro_runtime exports
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 (/speckit-tasks; not created here)
```

### Source Code (repository root)

```text
packages/pyro_runtime/
├── lib/
│   ├── pyro_runtime.dart              # exports the scene API (contracts/dart-api.md)
│   └── src/
│       ├── scene/                     # pure Dart (R5)
│       │   ├── scene.dart             # Scene, invariants, parentOf
│       │   ├── node.dart              # sealed Node and the kinds
│       │   ├── values.dart            # Vec2, NodeTransform, NodeAnchor, SpriteRegion, NodeCollisionType, ids
│       │   ├── overrides.dart         # Overrides, BehaviorAttachment, EntityRef, AssetRef
│       │   ├── scene_codec.dart       # SceneCodec, SceneReadResult, version gate
│       │   ├── node_mapping.dart      # JSON values ↔ typed Nodes, validation
│       │   ├── tree_repair.dart       # R8 passes, RepairReport, TreeIssue
│       │   ├── errors.dart            # SceneFormatException subtypes
│       │   └── json/
│       │       ├── strict_reader.dart # duplicate keys, line/column, unmodifiable values
│       │       └── canonical_writer.dart
│       └── loader/
│           └── repair_warning.dart    # warnAboutRepairs (kDebugMode)
├── test/
│   ├── scene/                         # tests listed in quickstart §1
│   ├── loader/                        # repair_warning_test.dart
│   └── fixtures/scenes/
│       ├── canonical/                 # one per Node kind, one per Field type, all_kinds
│       ├── non_canonical/             # + .expected.scene.json
│       ├── damaged/                   # one per TreeIssue + the merge story, + .expected
│       ├── version/                   # newer, missing, zero, string, float
│       └── invalid/                   # malformed, duplicate key, bad root, wrong types
└── benchmark/
    └── scene_codec_benchmark.dart     # SC-006
```

**Structure Decision**: one module inside the existing `pyro_runtime` package, where project-plan
§5 already places "model, JSON (de)serialization, migrations" (`lib/src/scene/`). There is no
`migrations/` folder yet, because only version 1 exists. The placeholder
`test/pyro_runtime_test.dart` is replaced by the real tests.

### Documentation updates in the same change

- `GLOSSARY.md`: add **Repair report** (and *canonical form* if it is used in user-facing
  docs).
- `dev-docs/project-plan.md` §7.1: replace the example with the contract's (expanded objects,
  `props` on sprites and hitboxes, `{"asset": …}`, `#AARRGGBB`), and link the contract.
- `dev-docs/decisions.md`: record the new format decisions as the next Q numbers: the version-bump
  rule (FR-020a), the tagged asset references and colour form (R6), the canonical number form
  (R3), and repair in games with a debug warning (FR-024a).
- `dev-docs/phases.md`: tick "Scene format" when done.

## Complexity Tracking

No constitution violations to justify.
