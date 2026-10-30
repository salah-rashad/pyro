# Implementation Plan: Generator

**Branch**: `specs/003-generator` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-generator/spec.md`

## Summary

Build #7, the Generator, on the shape spike #2 proved: `pyro_annotations` gains
`@PyroBehavior`, `@PyroComponent`, `@Editable` and `ImagePath`; `pyro_generator` gains a
per-library scan builder (analyzer work: recognition by type, the build-time rules, Field type
classification for every v1 Field type, inherited and mixin fields, defaults, import search) that
writes a JSON fragment to the build cache, and a `$lib$` aggregator that merges the fragments,
applies the cross-library rules (Type ID collisions, unused `@Editable` holders, the runtime
dependency), and writes the committed `lib/pyro.manifest.json` and `lib/pyro.g.dart`. Both
builders auto-apply to dependents, so a game needs no `build.yaml`. `pyro_runtime` gains the
small Registry contract the generated code implements and #8 builds on. Tests are golden files
from `build_test` runs on in-memory packages with stand-in Flame libraries, plus a Flutter
`fixture_game` with real Flame that CI regenerates, analyzes and tests on three OSes.

## Technical Context

**Language/Version**: Dart ^3.12, Flutter 3.44.2 (the repository's pin, Q94)

**Primary Dependencies**: `pyro_generator`: `analyzer` 12.1.0, `build` 4.0.7, `source_gen`
4.2.4, `dart_style` 3.1.8 (wide ranges kept, spike #2 finding 1), `glob` ^2.1.0 (made direct),
`pyro_annotations`; `build_test` ^3.5.0 (dev, resolves 3.5.16). `pyro_annotations`: none.
`pyro_runtime`: unchanged dependencies. `fixture_game`: `pyro_runtime`, `flame`,
`flame_behaviors`; dev `pyro_generator`, `build_runner` ^2.15.1, `flutter_test`. All verified to
resolve in the workspace lock (research R1)

**Storage**: two committed files in the game's `lib/`; one JSON fragment per relevant library in
build_runner's cache

**Testing**: `dart test` in `pyro_generator` (`build_test` `testBuilders` on in-memory packages,
byte-for-byte goldens, research R12) and `pyro_annotations`; `fixture_game`: `build_runner build`
+ `git diff --exit-code`, `flutter analyze --fatal-infos`, `flutter test`; watch latency measured
by hand with spike #2's harness (R13)

**Target Platform**: the build runs on the developer's machine and in CI (macOS, Windows,
Linux) on the plain Dart VM; the generated Registry runs in the game on every platform Flutter
supports

**Project Type**: build_runner code generator (library packages) plus a shared runtime contract

**Performance Goals**: annotated save → Manifest updated in < 3 s median in `build_runner watch`
on 300 files / 42 annotated (SC-004; spike #2: ~0.9 s); unannotated libraries skipped by
triggers; outputs rewritten only when their bytes change

**Constraints**: `pyro_generator` never depends on `pyro_runtime`, Flame or Flutter
(constitution II); outputs byte-identical across runs and OSes (FR-029); no implementation
imports in the Registry (FR-025); errors written into the Manifest before the build fails
(FR-020)

**Scale/Scope**: games of up to ~1,000 libraries with ~150 annotated types (spike #2's largest
run); 11 Field types; 23 error codes and 2 warning codes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Pre-research | Post-design |
|---|---|---|---|
| I. Clean Code | Names from `GLOSSARY.md`; public API documented; errors name file, class, field and Type ID; immutable data; no speculative abstraction | ✅ | ✅ annotations and Registry types are `final` classes with `const` constructors (contracts); every diagnostic names its file, line, class and field (research R8); the scan/aggregate split is spike #2's proven seam, not a new layer; new glossary terms listed below |
| II. Modular Boundaries | `pyro_annotations` has no dependencies; `pyro_generator` depends only on annotations, `source_gen`, `build`, `analyzer` (+ `dart_style`, `glob`, already transitive), never the Runtime or Flutter; Runtime stays small; boundary changes stated | ✅ | ✅ Flame types matched by package and name (R3); the Registry contract lives in `pyro_runtime` and uses only `Object`, `Component` and core types (R9); `fixture_game` depends on the generator, not the reverse; `glob` made direct (R1) |
| III. Performance by Design | Generator watch output ≤ ~3 s on a mid-size project | ✅ SC-004 | ✅ spike #2 shape kept (R2), triggers include `Editable` only; measured by hand (R13, quickstart §4) |
| IV. User Data Integrity | Nothing in the user's project is lost or silently rewritten; the generated files are deterministic | ✅ | ✅ only Pyro's two generated files are written; collisions drop every class sharing an ID so a Scene can never get the wrong class (R8); unknown keys ignored by readers (FR-015a); no `build.yaml` or pubspec change needed in the game (FR-027) |
| V. Tested Core | Generator is Heavy: golden tests for Registry and Manifest, error cases; deterministic | ✅ | ✅ one golden case per error and warning code plus the success fixture (R12); `fixture_game` regenerated and diffed on three OSes; in-memory sources, no network, no clocks |

Technology constraints: no `dart:mirrors` or `reflectable` ✅ (Q12, Q38); `build_runner ≥ 2.14`
✅ (2.15.1); MIT-compatible dependencies ✅ (`glob`, `build_test`: BSD-3).

**Result:** passes, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/003-generator/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R14
├── data-model.md              # Phase 1: inputs, scan fragment, aggregation, outputs
├── quickstart.md              # Phase 1: how to validate
├── contracts/
│   ├── annotations-api.md     # What pyro_annotations exports
│   ├── manifest-v1.md         # lib/pyro.manifest.json, diagnostics and codes
│   └── registry-api.md        # pyro_runtime's Registry types and the generated pyro.g.dart
├── checklists/
│   └── requirements.md        # Spec quality checklist
└── tasks.md                   # Phase 2 (/speckit-tasks; not created here)
```

### Source Code (repository root)

```text
pubspec.yaml                                 # + packages/pyro_generator/fixture_game in workspace:

packages/pyro_annotations/
├── lib/pyro_annotations.dart                # exports the four types
├── lib/src/
│   ├── annotations.dart                     # PyroBehavior, PyroComponent, Editable
│   └── image_path.dart                      # ImagePath
└── test/pyro_annotations_test.dart          # const-ness, ImagePath equality

packages/pyro_runtime/
├── lib/pyro_runtime.dart                    # + export src/loader/registry.dart
├── lib/src/loader/registry.dart             # PyroRegistry, RegistryType, RegistryField, TypeRole, FieldType
└── test/loader/registry_test.dart           # lookup, order, duplicate IDs refused

packages/pyro_generator/
├── build.yaml                               # pyro_scan + pyro_aggregate, auto_apply: dependents, triggers
├── pubspec.yaml                             # + glob; dev + build_test
├── .pubignore                               # fixture_game/
├── lib/builder.dart                         # pyroScan(), pyroAggregate() factories
├── lib/src/
│   ├── checkers.dart                        # TypeCheckers (research R3)
│   ├── scan_builder.dart                    # per-library builder: writes .pyro.json
│   ├── introspect.dart                      # class rules, supertypes, parent type, linearization
│   ├── fields.dart                          # field rules, Field type classification
│   ├── defaults.dart                        # initializer → default / defaultSource
│   ├── imports.dart                         # import search for field types (research R10)
│   ├── diagnostics.dart                     # Diagnostic, codes, messages, sort order
│   ├── fragment.dart                        # ScanFragment JSON (de)serialization
│   ├── aggregate_builder.dart               # $lib$ builder: merge, cross-library rules, write
│   ├── manifest_json.dart                   # canonical JSON writer (sorted keys, number form)
│   ├── manifest_emitter.dart                # Manifest object from the merged records
│   └── registry_emitter.dart                # pyro.g.dart text + dart_style
├── test/
│   ├── support/                             # stand-in flame / flame_behaviors / vector_math sources, harness
│   ├── goldens/<case>/                      # input/lib/ + pyro.g.dart.golden, pyro.manifest.json.golden, log.golden
│   └── *_test.dart                          # quickstart §1
└── fixture_game/                            # Flutter workspace member, publish_to: none
    ├── pubspec.yaml
    ├── analysis_options.yaml                # root rules; pyro.g.dart analyzed by naming it in CI
    ├── lib/                                 # annotated components and Behaviors, every Field type
    │   ├── pyro.g.dart                      # committed output
    │   └── pyro.manifest.json               # committed output
    └── test/registry_test.dart              # SC-005, SC-006

.github/workflows/ci.yml                     # analyze + test pyro_generator/fixture_game; regenerate + diff on 3 OSes
```

**Structure Decision**: the code goes where project-plan §5 puts it (`introspect`,
`registry_emitter`, `manifest_emitter` under `pyro_generator/lib/src/`), split a little further
so each rule set has its own test file. The Registry contract goes in `pyro_runtime/lib/src/loader/`,
where §5 places the Registry interface. `fixture_game` sits inside `pyro_generator` (like
`pyro_ui/example`), is a workspace member so the root `pub get` resolves it, and is excluded from
the published package by `.pubignore`; it is not Phase 3's `example/` game, which #13 builds.

### Documentation updates in the same change

- `GLOSSARY.md`: add **Image path** (the `ImagePath` Field type), **Generator error** /
  **Generator warning**, and **Parent type** (the Node type a Behavior requires).
- `dev-docs/decisions.md`: the next Q numbers (from Q100) for this spec's decisions: every v1 Field
  type in #7 now (spec Clarifications); `ImagePath`; nullable reference and sprite fields;
  `@Editable` on fields only; unused `@Editable` is a warning; the `manifestVersion` rule;
  `min`/`max` checks; no `build.yaml` in games (FR-027).
- `dev-docs/project-plan.md`: §6.1 (annotations as built, `ImagePath`, the added rules), §7.3 (the
  Manifest as in contracts/manifest-v1.md, `warnings`, codes), §14 (the remaining Field types move
  from v0.1's #7 into the preview's #7; estimates 4.5 → ~6.5 and 2 → 0, per the author's review),
  the README recipe and "Add Pyro" items no longer add `build.yaml`.
- `dev-docs/phases.md`: same §14 changes in the same commit (sync rule); tick #7 when done.
- `dev-docs/ARCHITECTURE.md`: a "Generator" section with what was verified (R1, R12 probe, the watch
  latency of R13).
- `.github/workflows/ci.yml`: the `contract` job's TODO comment points at `fixture_game` as the
  pattern #12 reuses for `example/`.

## Risks

- **`dart_style` drift.** The Registry's formatting depends on the `dart_style` version resolved
  in the user's project; two machines with different lock files could format it differently.
  Within one project's committed lock the output is stable, which is what CI checks. If it
  bites, emit preformatted text and drop `dart_style`.
- **Import search edge cases.** A type reachable only through a chain the export namespace walk
  doesn't see would hit `unreachableFieldType` rather than compile; the error says which import to
  add. Covered by `imports_test.dart`.
- **Stale fragments.** Deleting the last annotation from a library must remove its fragment so
  the aggregator re-runs; spike #2 checked additions, not removals. `stability_test.dart` and
  quickstart §3 cover it.
- **Line endings.** The goldens and `fixture_game`'s committed outputs are compared byte for byte;
  Windows checkouts must not alter them, so `.gitattributes` marks both `-text` like the Scene
  fixtures.

## Complexity Tracking

No constitution violations to justify.
