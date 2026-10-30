# Implementation Plan: Document Model

**Branch**: `specs/002-document-model` | **Date**: 2026-10-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-document-model/spec.md`

## Summary

Build Pyro's Document model in the app (`apps/editor/lib/document/`), headless: an immutable
`SceneDocument` (flat `IMap<NodeId, Node>` plus a parent index, over `pyro_runtime`'s Node
classes) with four tree-safe edit operations; a pure `DocumentHistory` with named transactions,
coalescing, a 200-entry cap and an identity-based dirty flag; `SceneFiles` for opening and
atomic saving, with the `schemaVersion` gate and a content-digest check against changes made on
disk; a `RecoveryStore` and 30-second `RecoveryTimer` for crash recovery outside the project;
and a `DocumentSession` that ties them together for #1 to wrap in a Riverpod provider. The app
gains freezed, Riverpod (dependencies only), `fast_immutable_collections` and small I/O helpers,
on the current Flutter 3.44.2 pin (research R1).

## Technical Context

**Language/Version**: Dart ^3.12, Flutter 3.44.2 (the repository's pin, kept by the author's
choice; R1)

**Primary Dependencies**: `pyro_runtime` (Scene format, `SceneCodec`), `freezed_annotation`
3.1.0 + `freezed` 3.2.6-dev.1, `fast_immutable_collections` 12.0.0, `uuid`, `file`, `clock`,
`crypto`; `flutter_riverpod` 3.3.2, `riverpod_annotation` 4.0.3 and
`riverpod_generator` 4.0.4 added for #1 but unused here; `build_runner` 2.15.1, `fake_async`
(dev). Versions verified to resolve in the workspace lock (R1)

**Storage**: `*.scene.json` files in the developer's project (written only on save, atomically);
recovery copies as Scene files plus a small JSON metadata file in a recovery folder outside the
project ([contracts/recovery-copies.md](contracts/recovery-copies.md))

**Testing**: `flutter test` in `apps/editor` with `MemoryFileSystem`, a forwarding file system
that fails or pauses on demand, `fake_async`, an injected clock and an inline `Offload` runner
(R9, R10); `pyro_runtime`'s fixtures for round trips; a benchmark run by hand with
`flutter test --enable-vmservice benchmark/` (JIT, so an upper bound), with SC-006 measured
from a heap snapshot taken through the VM service

**Target Platform**: Pyro desktop on macOS (first class), Windows and Linux (built and tested
in CI, best effort)

**Project Type**: desktop app module (a feature folder inside `apps/editor`)

**Performance Goals**: one-Node transaction, undo and redo < 1 ms median on a 1,000-Node Scene
(SC-005); a 200-step history holds < 2 MB on a 1,000-Node Scene (SC-006); open and save never
block a frame (decode and encode off the UI isolate through an injected `Offload`, default `Isolate.run`, R9)

**Constraints**: the Scene file is written only on save, atomically (constitution IV); in tests,
the file system, clock, timers and isolate runner are injected or faked, and Scenes under test
live in memory; real files are only the repository's fixtures and one atomic-write test in a
temporary folder (constitution V, R10); no import of `pyro_generator` or user code
(constitution II); no editor UI

**Scale/Scope**: about 1,000 Nodes and ~0.5 MB per Scene, a few Scenes open at once, 200 history
entries per Scene, one recovery copy per dirty Scene

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Pre-research | Post-design |
|---|---|---|---|
| I. Clean Code | Immutable models; mutation only through named transactions; names from `GLOSSARY.md`; errors name file, transaction, Node and version; public API documented; no speculative abstraction | ✅ | ✅ freezed and hand-written immutable values (R4); `transact` is the only way to change a `SceneDocument` held by a session (R6); every error type names its location (data-model.md); `NodeIdSource`, the file system and the clock are documented seams (test doubles); new glossary terms listed below |
| II. Modular Boundaries | App doesn't depend on the generator or run user code; feature folder `document/` with a public library; new dependencies stated | ✅ | ✅ `lib/document/document.dart` exports the API, internals under `lib/document/src/`; no change to `pyro_runtime`; every new dependency is listed in R1 and recorded as a decision |
| III. Performance by Design | Document is a hot path: budget stated and measured; structural sharing; no blocking I/O | ✅ SC-005, SC-006 | ✅ `IMap` sharing (R3), identity equality (R4), codec work off the UI isolate through `Offload` (R9); benchmark in quickstart §4 |
| IV. User Data Integrity | Atomic writes; preserve the unknown; refuse unreadable versions; Scene file written only on save; recovery file | ✅ | ✅ temp file + flush + rename (R7); Nodes are the Runtime's, unknown data passes through untouched; gate before any I/O (R14); changed-on-disk refusal (R8); recovery outside the project (R11) |
| V. Tested Core | Document and history are Heavy: every behavior has a test; deterministic | ✅ | ✅ test map in quickstart §1 covers every FR; fake file system, clock, timers and isolate runner (R9, R10); byte-for-byte round trip of every canonical fixture (R15) |

Technology constraints: Flutter stable only ✅ (3.44.2). Riverpod and freezed for the app stack
✅ (Q26). freezed 3.2.6-dev.1 is a prerelease of a code generator, not of Flutter; it is a risk
(below), not a violation.

**Result:** passes, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/002-document-model/
├── plan.md                  # This file
├── research.md              # Phase 0: decisions R1–R15
├── data-model.md            # Phase 1: types, invariants, state transitions, errors
├── quickstart.md            # Phase 1: how to validate
├── contracts/
│   ├── document-api.md      # What lib/document/document.dart exports
│   └── recovery-copies.md   # The recovery folder's files
├── checklists/
│   └── requirements.md      # Spec quality checklist
└── tasks.md                 # Phase 2 (/speckit-tasks; not created here)
```

### Source Code (repository root)

```text
apps/editor/
├── pubspec.yaml                       # + the dependencies in research R1
├── lib/
│   ├── main.dart                      # unchanged (the shell is #1)
│   └── document/
│       ├── document.dart              # public library (contracts/document-api.md)
│       └── src/
│           ├── scene_document.dart    # SceneDocument (freezed, identity), the four edits
│           ├── node_children.dart     # childIds on any Node kind (exhaustive switch)
│           ├── node_ids.dart          # NodeIdSource, UUID v4 default
│           ├── offload.dart           # Offload (runs codec work off the UI isolate)
│           ├── history.dart           # DocumentHistory, HistoryEntry
│           ├── open_document.dart     # OpenDocument, OpenedFrom
│           ├── scene_files.dart       # SceneFiles: open, save, save as, gate, change check
│           ├── atomic_write.dart      # temp file + flush + rename
│           ├── recovery_store.dart    # RecoveryStore, RecoveryCheck, RecoveryInfo
│           ├── recovery_timer.dart    # RecoveryTimer
│           ├── document_session.dart  # DocumentSession
│           └── errors.dart            # DocumentEditError, TransactionFailed, SaveRefused, …
├── test/
│   └── document/                      # tests listed in quickstart §1
│       └── fixtures/                  # repaired Scene, recovery folders
└── benchmark/
    └── document_benchmark_test.dart   # SC-005, SC-006 (run by hand; CI's flutter test runs test/ only)
```

**Structure Decision**: one feature folder, `document/`, in the app, as constitution II names
it; nothing in `packages/` changes. Round-trip tests read `pyro_runtime`'s canonical fixtures in
place (R15). The generated `*.freezed.dart` files are committed, like the generator's output
elsewhere in the repo, so a checkout analyzes without running `build_runner`; CI regenerates and
diffs them, and they must pass the repo's format check like any file (tasks.md T003, T011).

### Documentation updates in the same change

- `GLOSSARY.md`: add **Transaction**, **Coalescing key**, **Recovery copy** and **Unsaved
  changes** (the dirty state; avoid "dirty" in user-facing text).
- `dev-docs/decisions.md`: the next Q numbers (from Q94) for this spec's decisions: the toolchain
  and prerelease freezed (R1); save refused when the file changed on disk (FR-019a); repaired
  Scenes open with unsaved changes (FR-016); recovery copies outside the project with a 30-day
  prune (FR-025, FR-025a); saving refused while the Runtime's version is unknown (FR-022).
- `dev-docs/project-plan.md` §8.1, §8.2: the parent index beside the Node map (R2), identity
  equality (R4), the coalescing and dirty rules (R5), the change check on save (R8) and the
  recovery location (R11). §8.5 stays for #1.
- `dev-docs/ARCHITECTURE.md`: the verified resolution finding (R1: `test` caps analyzer at 12 on
  Flutter 3.44.2, so spike #4's versions don't resolve in the workspace).
- `dev-docs/phases.md`: tick #2 when done.

## Risks

- **Prerelease freezed.** 3.2.6-dev.1 is the newest freezed that resolves on Flutter 3.44.2
  (R1). The generated code is committed and reviewed like any code; moving to Flutter 3.47.x
  (stable freezed 4.0.3, riverpod_lint, `build_runner --only-check`) is a follow-up chore,
  best done before Phase 3's contract job.
- **Older Riverpod than spike #4 tested.** 3.3.2 instead of 3.4.3. Nothing here uses it; #1
  re-checks the spike's findings on it.
- **Windows rename.** Replacement on rename is relied on (R7); CI's Windows job runs the atomic
  write tests against the real file system once.
- **Fixture path.** The app's tests read `pyro_runtime`'s fixtures through a relative path; a
  move of either breaks the tests loudly, not silently.

## Complexity Tracking

No constitution violations to justify.
