---

description: "Task list for the Document model (#2) in apps/editor"
---

# Tasks: Document Model

**Input**: Design documents from `specs/002-document-model/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: included. Constitution Principle V makes document and history a **Heavy** test
layer, and the spec asks for document, history and byte-for-byte round-trip tests. Within each
phase, write the tests first and see them fail before implementing.

**Organization**: tasks are grouped by user story so each story can be built and checked on its
own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: the user story the task belongs to (US1–US4)

## Path Conventions

All paths are relative to the repository root. The app is `apps/editor/`, shortened below as
`app/`, so `app/lib/document/src/history.dart` means `apps/editor/lib/document/src/history.dart`.
The Runtime's fixtures are `packages/pyro_runtime/test/fixtures/scenes/`, shortened as
`fixtures/`.

Run commands with Flutter on the path: `export PATH="$PATH:/Users/salah/Library/flutter/bin"`.
Tests: `cd apps/editor && flutter test test/document`. After changing a freezed class:
`cd apps/editor && dart run build_runner build -d`, and commit the generated `*.freezed.dart`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: dependencies, folders, code generation in CI, test helpers

- [X] T001 Add the dependencies of [research.md R1](research.md#r1-toolchain-stay-on-flutter-3442-analyzer-12-prerelease-freezed) to `app/pubspec.yaml`, sorted (`sort_pub_dependencies`): dependencies `clock: ^1.1.2`, `crypto: ^3.0.6`, `fast_immutable_collections: ^12.0.0`, `file: ^7.0.1`, `flutter_riverpod: ^3.3.2`, `freezed_annotation: ^3.1.0`, `path: ^1.9.1`, `riverpod_annotation: 4.0.3`, `uuid: ^4.6.0`; dev dependencies `build_runner: ^2.15.1`, `fake_async: ^1.3.3`, `freezed: 3.2.6-dev.1`, `riverpod_generator: 4.0.4`. Replace the pubspec comment "Riverpod, freezed and flame_tiled join when the first code uses them" with one saying Riverpod is added for #1's providers and freezed for the document's models. Run `dart pub get` at the repository root and confirm the lock holds analyzer 12.1.0, freezed 3.2.6-dev.1, riverpod_generator 4.0.4, flutter_riverpod 3.3.2 and build_runner 2.15.1
- [X] T002 Create `app/lib/document/document.dart` (library doc comment: "Pyro's Document model: one open Scene's state, history, saving and crash recovery (spec 002)."; exports added as each story lands) and the folders `app/lib/document/src/`, `app/test/document/helpers/` and `app/benchmark/`
- [X] T003 [P] Add a "Check generated code" step to the `analyze-test` job in `.github/workflows/ci.yml`, on Linux only (`if: runner.os == 'Linux'`), after "Resolve the workspace": `cd apps/editor && dart run build_runner build -d && git diff --exit-code -- lib`, so committed `*.freezed.dart` files can't go stale (plan.md, Structure Decision). If T011 finds that generated files fail `dart format --set-exit-if-changed`, also change the "Check formatting" step to skip `*.g.dart` and `*.freezed.dart` (for example by formatting the output of `git ls-files 'packages/**.dart' 'apps/**.dart' | grep -vE '\.(g|freezed)\.dart$'`)
- [X] T004 [P] Write test helpers in `app/test/document/helpers/fixtures.dart`: `String fixturesRoot` = `'../../packages/pyro_runtime/test/fixtures/scenes'` (research R15), `Uint8List readFixtureBytes(String relative)` reading raw bytes with `dart:io`, and `List<String> fixtureNames(String folder)` listing `*.scene.json` files that don't end in `.expected.scene.json`, sorted; fail with a message naming the path if the folder is missing
- [X] T005 [P] Write `app/test/document/helpers/scenes.dart`: `NodeIdSource counterIds([String prefix = 'n'])` returning `n1`, `n2`, …; `Scene smallScene()` (root `root` with entities `a` and `b`, `a` with sprite child `a1`); `Scene generatedScene(int nodes)` (root → entities, each with one sprite and one rectangle hitbox child, deterministic IDs) for the session tests and the benchmark; and `Future<R> runInline<R>(FutureOr<R> Function() work) async => work();`, the inline `Offload` that every `fakeAsync` test passes (research R9)
- [X] T006 [P] Write `app/test/document/helpers/failing_file_system.dart`: a `ForwardingFileSystem` (from `package:file`) over a `MemoryFileSystem` that counts every operation (open, write, flush, close, rename, delete, stat, read) and throws a `FileSystemException` at the operation numbered `failAt` (null: never); exposes `operationCount` and `operations` (a log of names and paths) so tests can assert "nothing was read or written"; and `Completer<void>? holdWrites`: while set, every write to a path matching `holdPattern` waits on it, so a test can edit while a save is in flight and then complete it

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the error types, Node ID source, `childIds` helper and the `SceneDocument` value that every story uses

**⚠️ CRITICAL**: no user story work can begin until this phase is complete

### Tests for the foundation

- [X] T007 [P] Write `app/test/document/node_children_test.dart` for T010: `withChildIds` returns a Node of the same class with the new list and every other field identical (same `extra`, `name`, `tags`, `transform`, `behaviors`, `fields`, `propsExtra`, `kind`) for each of `RootNode`, `EntityNode`, `SpriteNode`, `RectangleHitboxNode`, `CircleHitboxNode`, `CustomNode` and `UnknownNode`
- [X] T008 [P] Write `app/test/document/scene_document_test.dart` (conversion group) for T011: `fromScene` of `smallScene()` and of every `fixtures/canonical/` Scene gives `parents` matching `Scene.parentOf` for every Node, `nodes` holding the very same Node objects, and `sceneExtra` equal to `Scene.extra`; `toScene()` of that document encodes (`SceneCodec.encode`) to the same text as the original Scene; `node`, `parentOf`, `childrenOf`, `contains` and `isAncestor` answer correctly, including for the root and unknown IDs

### Implementation for the foundation

- [X] T009 [P] Implement the error types in `app/lib/document/src/errors.dart` per [data-model.md § Errors](data-model.md#errors): `sealed class DocumentEditError implements Exception` with `DuplicateNodeId(id)`, `NodeNotFound(id)`, `RootNotAllowed(id, operation)`, `NodeHasChildren(id)`, `IndexOutOfRange(parentId, index, length)`, `MoveIntoOwnSubtree(id, targetParentId)`, `ChildrenChanged(id)`, each also carrying `String? nodeName`; `TransactionFailed(label, cause)`; `SceneOpenFailed(path, cause)`; `sealed class SaveRefused implements Exception` with `RuntimeVersionUnknown(path)`, `RuntimeTooOld(path, reads, writes)`, `SceneChangedOnDisk(path)`, `SaveTargetExists(path)`, `SavePathRequired()`; `SaveFailed(path, cause)`; `RecoveryWriteFailed(location, cause)`. Every `toString()` names what failed and where (FR-030); `RuntimeTooOld`'s says the Runtime reads up to `reads`, Pyro writes `writes`, and suggests upgrading `pyro_runtime`
- [X] T010 [P] Implement `app/lib/document/src/node_children.dart`: `Node withChildIds(Node node, List<NodeId> childIds)` as an exhaustive `switch` over the sealed Node kinds, each calling that kind's `copyWith(childIds:)` (research R6); and `app/lib/document/src/node_ids.dart`: `typedef NodeIdSource = NodeId Function();` and `NodeId uuidNodeIds()` (UUID v4 from `package:uuid`, *Q14*); and `app/lib/document/src/offload.dart`: `typedef Offload = Future<R> Function<R>(FutureOr<R> Function() work);` with a doc comment saying the default is `Isolate.run` and tests pass an inline runner (research R9)
- [X] T011 Implement `SceneDocument` in `app/lib/document/src/scene_document.dart` per [data-model.md § SceneDocument](data-model.md#scenedocument): `@Freezed(equal: false)` with `rootId`, `IMap<NodeId, Node> nodes`, `IMap<NodeId, NodeId> parents` ("The parent of every Node except the root"), `Map<String, Object?> sceneExtra` (unmodifiable); `factory SceneDocument.fromScene(Scene)`, `Scene toScene()` (lets `Scene`'s constructor re-check the invariants, research R2), and the derived getters of T008. Run `build_runner`, then `dart format --output=none --set-exit-if-changed lib/document/src/scene_document.freezed.dart`; if it fails, apply T003's format-step exclusion; commit `scene_document.freezed.dart` (depends on T010)

**Checkpoint**: `flutter test test/document` passes T007 and T008

---

## Phase 3: User Story 1 - Edit a Scene and undo or redo any step (Priority: P1) 🎯 MVP

**Goal**: named transactions over the four edits, with undo, redo, coalescing and the dirty flag, on a session created in memory

**Independent Test**: apply sequences of transactions to a document, undo and redo in various orders, and compare every state with the expected snapshot (spec US1)

### Tests for User Story 1

- [X] T012 [P] [US1] Add the edits group to `app/test/document/scene_document_test.dart`: for each of `addNode`, `removeNode`, `moveNode`, `replaceNode`, the success case and every refusal in [data-model.md § Edits](data-model.md#edits) (`DuplicateNodeId`, `NodeNotFound`, `RootNotAllowed`, `NodeHasChildren`, `IndexOutOfRange`, `MoveIntoOwnSubtree`, `ChildrenChanged`); `addNode`/`moveNode` default `index` appends; `removeNode` removes the whole subtree from `nodes` and `parents`; moving within one parent reorders; the no-ops (move to the current parent and index, replace with the identical Node) return the identical document; after any edit, every Node it didn't touch is `identical` to before (FR-003, US1 #8); a seeded random sequence of 1,000 valid and invalid edits keeps the five invariants (check with `toScene()` and `parents` against `childIds` after each step)
- [X] T013 [P] [US1] Write `app/test/document/history_test.dart` for T015: opening state labelled `'Open'` and not undoable; apply adds one entry with its label (US1 #1); undo restores the exact earlier `SceneDocument` (`identical`) and redo the later one (US1 #2); a run with one coalescing key is one entry with the **first** label, and one undo returns before its first step (US1 #3); a different key, an unkeyed transaction, an undo, a redo or `markSaved` ends the run (US1 #4, FR-011); applying after undo drops the redo tail (US1 #5); an identical `next` adds nothing and leaves `isDirty` unchanged (US1 #6, FR-009); `canUndo`/`canRedo`/`undoLabel`/`redoLabel` (FR-013); the cap: "At most 201 (the opening state plus 200 steps, FR-014)", oldest dropped first, and a document whose saved entry was dropped stays dirty; dirty by identity, clean again on undo or redo back to the saved state (US2 #5); `saved` null keeps a document dirty through any undo (FR-016)
- [X] T014 [P] [US1] Write `app/test/document/document_session_test.dart` (editing group) for T017: `DocumentSession.create` holds only a root Node, is clean and has no path (US2 #9); `transact` publishes the new `OpenDocument` on `changes` synchronously, one event per step and in order; a `DocumentEditError` inside `edit` throws `TransactionFailed` naming the label and leaves `state` identical (US1 #7); a non-`DocumentEditError` propagates unchanged and leaves `state` identical; undo and redo publish; `close` on a dirty session throws `StateError`; `discardAndClose` on it succeeds; two sessions created side by side keep separate histories: a transaction, undo or redo in one never changes or publishes the other (spec edge case "Two documents open at once")

### Implementation for User Story 1

- [X] T015 [US1] Add the four edits to `app/lib/document/src/scene_document.dart` per [data-model.md § Edits](data-model.md#edits) and research R6, using `withChildIds` for every `childIds` change and keeping `parents` in step (depends on T011)
- [X] T016 [P] [US1] Implement `HistoryEntry` and `DocumentHistory` in `app/lib/document/src/history.dart` per [data-model.md § DocumentHistory](data-model.md#documenthistory) and research R5: `IList<HistoryEntry> entries`, `index`, `SceneDocument? saved`, `Object? openCoalesceKey`; `DocumentHistory.opened(state, {required bool clean})`; `apply`, `undo`, `redo`, `markSaved(state)`; no `==` override
- [X] T017 [US1] Implement `OpenDocument` and `OpenedFrom` in `app/lib/document/src/open_document.dart` per [data-model.md § OpenDocument](data-model.md#opendocument) (fields `history`, `path`, `baseline` (`Digest?`), `repairs`, `origin`; `transact`, `undo`, `redo`, `markSaved(SaveResult)`, where `transact` wraps a `DocumentEditError` in `TransactionFailed(label, cause)`), `createDocument({NodeIdSource newId})` (a root-only Scene whose root ID comes from `newId`; clean), and `SaveResult` (freezed value: `state`, `path`, `digest`) in the same file; run `build_runner` (depends on T015, T016)
- [X] T018 [US1] Implement the editing part of `DocumentSession` and `SessionServices` in `app/lib/document/src/document_session.dart` per [contracts/document-api.md](contracts/document-api.md#one-open-scene): `create`, `state`, `changes` (a synchronous broadcast `StreamController`), `errors`, `transact`, `undo`, `redo`, `close` (throws `StateError` when dirty), `discardAndClose`; close the stream controllers on close (depends on T017)
- [X] T019 [US1] Export `SceneDocument`, `DocumentHistory` (type only), `OpenDocument`, `OpenedFrom`, `DocumentSession`, `SessionServices`, `NodeIdSource`, `uuidNodeIds`, `createDocument` and the `DocumentEditError` cases and `TransactionFailed` from `app/lib/document/document.dart`; keep the constructors listed under "Not exported" in the contract private (depends on T018)

**Checkpoint**: US1's tests pass; a document can be edited, undone and redone in memory

---

## Phase 4: User Story 2 - Open and save a Scene without loss (Priority: P1)

**Goal**: open a Scene file into a document and save it back byte for byte, atomically, refusing to overwrite changes made on disk

**Independent Test**: open each canonical fixture, save it unchanged, compare bytes; fail a save part-way and check the original is intact (spec US2)

### Tests for User Story 2

- [X] T020 [P] [US2] Write `app/test/document/round_trip_test.dart`: for every Scene in `fixtures/canonical/` (via `fixtureNames`), copy its bytes into a `MemoryFileSystem`, `SceneFiles.open`, `save` with `runtimeReadsUpTo: 1`, and expect identical bytes (US2 #1, SC-001); on a mismatch print a line diff; for every `fixtures/non_canonical/` Scene, open is clean (`isDirty == false`) and saving writes the matching `.expected.scene.json` bytes (US2 #6); edit then undo to the saved state then save is byte-identical
- [X] T021 [P] [US2] Write `app/test/document/scene_files_test.dart` (open and save groups): open errors for a missing file, non-UTF-8 bytes and each `fixtures/invalid/` and `fixtures/version/` file throw `SceneOpenFailed` naming the path, with the `SceneFormatException` as `cause` (US2 #8); a `fixtures/damaged/` Scene opens dirty, `origin == OpenedFrom.repaired`, with a non-empty `repairs`, and its file's bytes unchanged (US2 #7, FR-016); after an edit, save writes the new state and reopening gives the same text (US2 #2); a new document without a path throws `SavePathRequired` (US2 #9); the file replaced with different bytes, or deleted, throws `SceneChangedOnDisk` and writes nothing, and `overwrite: true` then writes (US2 #10, FR-019a); replaced with identical bytes saves normally; `saveAs` onto an existing other file throws `SaveTargetExists` unless `overwrite`; a target folder that doesn't exist throws `SaveFailed` naming the path, and the document keeps its edits; every test here passes `offload: runInline` except one open-edit-save test that keeps the default `Isolate.run`, so the real isolate path is covered (research R9)
- [X] T022 [P] [US2] Write `app/test/document/atomic_write_test.dart` for T024: with `FailingFileSystem`, run one save to learn its operation count, then for every `failAt` from 1 to that count run it again on a fresh copy and assert the target reads back as exactly the old or exactly the new bytes, and no `*.pyro-tmp` file is left in the folder (US2 #3, SC-003); one test on `LocalFileSystem` in a `Directory.systemTemp.createTemp` folder (deleted in `tearDown`) checks that rename replaces an existing target, so CI covers Windows (research R7)
- [X] T023 [P] [US2] Add the saving group to `app/test/document/document_session_test.dart`: `DocumentSession.open` of a fixture; with `FailingFileSystem.holdWrites` set, start a save, `transact` while it waits, then complete the completer: the session stays dirty and its saved entry is the state at the start of the save (FR-020); two `save` calls run one after the other, never interleaved (check the file system's operation log); after `saveAs`, `state.path` is the new path and later saves go there

### Implementation for User Story 2

- [X] T024 [P] [US2] Implement `Future<void> writeAtomically(FileSystem fs, String path, List<int> bytes)` in `app/lib/document/src/atomic_write.dart` per research R7: temporary file `.<target name>.<random hex>.pyro-tmp` in the target's folder, `writeAsBytes(bytes, flush: true)`, `rename` onto the target; on any failure delete the temporary file (log, don't throw, if that fails too) and rethrow; never create the folder
- [X] T025 [US2] Implement `SceneFiles.open` in `app/lib/document/src/scene_files.dart`: read the bytes, then in one call to the injected `Offload` (default `Isolate.run`) decode UTF-8, `SceneCodec.decode`, `SceneDocument.fromScene` and SHA-256 the bytes (research R8, R9); `SceneFiles` takes `FileSystem` and `Offload` in its constructor; build an `OpenDocument` with `origin` `file` (clean) or `repaired` (non-empty repair report: `saved` null, FR-016); wrap every failure in `SceneOpenFailed(path, cause)` (depends on T017)
- [X] T026 [US2] Implement `SceneFiles.save` in `app/lib/document/src/scene_files.dart` per [contracts/document-api.md](contracts/document-api.md#opening-creating-and-restoring): keep a `runtimeReadsUpTo` parameter (checked in US4); `SavePathRequired`; for the document's own path, read and hash the current file and throw `SceneChangedOnDisk` if it differs from `baseline` or is gone, unless `overwrite`; for `saveAs` onto an existing different file throw `SaveTargetExists` unless `overwrite`; then `toScene()`, encode and hash in one `Offload` call, `writeAtomically`, and return `SaveResult(state, path, digest)`; wrap write failures in `SaveFailed(path, cause)` (depends on T024, T025)
- [X] T027 [US2] Add `open` and `save` to `DocumentSession` in `app/lib/document/src/document_session.dart`: `open` uses `SceneFiles.open`; `save` captures `state` at the start, queues behind any running save (a `Future` chain), calls `SceneFiles.save` and applies `markSaved(result)` to the **current** `OpenDocument`, then publishes (depends on T018, T026)
- [X] T028 [US2] Export `SceneFiles`, `SaveResult`, `SceneOpenFailed`, `SaveRefused` and its cases and `SaveFailed` from `app/lib/document/document.dart` (depends on T027)

**Checkpoint**: US1 and US2 tests pass; every canonical fixture round-trips byte for byte through a document

---

## Phase 5: User Story 3 - Get unsaved work back after a crash (Priority: P2)

**Goal**: recovery copies every 30 s while dirty, outside the project, found and restored on the next launch

**Independent Test**: with a fake clock and file system, edit, advance past the interval, drop the session, then find and restore the copy (spec US3)

### Tests for User Story 3

- [X] T029 [P] [US3] Write `app/test/document/recovery_store_test.dart` per [contracts/recovery-copies.md](contracts/recovery-copies.md): `<key>` is the lowercase hex SHA-256 of `<projectRoot>\n<scenePath>` after `normalize`; the copy is two files, `<key>.scene.json` (decodes with `SceneCodec`) and `<key>.recovery.json` (`formatVersion` 1, both paths, `writtenAt` UTC ISO 8601 from the injected clock); `find` returns `NoRecovery`, `RecoveryAvailable` (with `sceneFileModifiedAt`, null when the Scene is gone) or `RecoveryUnreadable` for each case in the contract's "Reading" list, deleting nothing for unreadable ones (FR-029); copies older than 30 days are pruned on `find`, including unreadable ones by file time (FR-025a); `discard` removes both files and tolerates missing ones (declining *Restore*, US3 #6, is #1's call to `discard`; this test covers the store's half)
- [X] T030 [P] [US3] Add the recovery group to `app/test/document/document_session_test.dart`, using `fakeAsync`, `withClock` and `offload: runInline` in every `SessionServices`, `SceneFiles` and `RecoveryStore`: no copy while clean (US3 #2); no copy for a `create`d Scene that has never been saved, however long it stays dirty, and copies once it has been saved to a path (FR-024); one copy after 30 s of being dirty, and none rewritten while the state is unchanged (US3 #1, research R12); the Scene file's bytes never change without `save` (FR-026); a save, and `discardAndClose`, remove the copy (US3 #3); after `saveAs`, the copy under the old path is removed; a crash (drop the session without closing) then `find` → `RecoveryAvailable`, and `DocumentSession.restore` gives the last copied state, dirty, `canUndo == false`, `origin == OpenedFrom.restored`, saving to the Scene's own path (US3 #4, #5, FR-028); the edits lost are at most 30 s (SC-004); a restored document whose Scene file changed afterwards is refused with `SceneChangedOnDisk` on save; a failing recovery write appears on `errors` as `RecoveryWriteFailed` and editing continues

### Implementation for User Story 3

- [X] T031 [P] [US3] Implement `RecoveryStore`, `RecoveryInfo` (freezed value: `projectRoot`, `scenePath`, `writtenAt`, `sceneFileModifiedAt`, `key`) and `RecoveryCheck` (sealed: `NoRecovery`, `RecoveryAvailable(info)`, `RecoveryUnreadable(location, problem)`) in `app/lib/document/src/recovery_store.dart` per [contracts/recovery-copies.md](contracts/recovery-copies.md): `find` (prune, then look up), `discard`, and the internal `write(projectRoot, scenePath, SceneDocument)` (Scene file first, then metadata, both through `writeAtomically`, encoding through the injected `Offload`; the constructor takes `folder`, `FileSystem` and `Offload`) and `readCopy(info)` returning an `OpenDocument` with `origin` `restored`, `saved` null and `baseline` = the digest of the Scene file as it is now (FR-028); run `build_runner` (depends on T024)
- [X] T032 [P] [US3] Implement `RecoveryTimer` in `app/lib/document/src/recovery_timer.dart`: `Timer.periodic(interval)` that, on each tick, reads the session's current `OpenDocument` through a callback and writes a copy only if it is dirty and its `state` isn't identical to the last one written; reports failures through a callback; `cancel()` (research R12)
- [X] T033 [US3] Wire recovery into `DocumentSession` in `app/lib/document/src/document_session.dart`: start the timer on `open` and `restore`, and for a `create`d Scene after its first save (an untitled Scene has no path to key a copy by, research R12); after a successful save `discard` the copy (both the old and the new path after `saveAs`); `discardAndClose` discards; `close` cancels the timer; add `static Future<DocumentSession> restore(RecoveryInfo copy, ...)` using `readCopy`; forward `RecoveryWriteFailed` to `errors`; `SessionServices` needs no `Offload` of its own, since `SceneFiles` and `RecoveryStore` each take one (depends on T027, T031, T032)
- [X] T034 [US3] Export `RecoveryStore`, `RecoveryInfo`, `RecoveryCheck` and its cases and `RecoveryWriteFailed` from `app/lib/document/document.dart` (depends on T033)

**Checkpoint**: US1–US3 tests pass; a simulated crash loses at most one interval of edits

---

## Phase 6: User Story 4 - Never write a Scene the game can't read (Priority: P2)

**Goal**: saving refuses unless the project's Runtime is known to read the version Pyro writes

**Independent Test**: save with `runtimeReadsUpTo` below, equal to and unknown (null), and check only the equal case writes (spec US4)

### Tests for User Story 4

- [X] T035 [P] [US4] Add the gate group to `app/test/document/scene_files_test.dart`, on `FailingFileSystem`: `runtimeReadsUpTo: 1` writes (US4 #1); `0` throws `RuntimeTooOld(reads: 0, writes: 1)` whose message suggests upgrading the Runtime (US4 #2); `null` throws `RuntimeVersionUnknown` (US4 #3); in both refusals `operationCount` doesn't change (nothing read or written, FR-022), the document keeps its edits and stays dirty; the gate is checked before `SavePathRequired` and the changed-on-disk check (SC-007)

### Implementation for User Story 4

- [X] T036 [US4] Implement the gate at the top of `SceneFiles.save` in `app/lib/document/src/scene_files.dart` per research R14: `null` → `RuntimeVersionUnknown(path)`; `< Scene.currentSchemaVersion` → `RuntimeTooOld(path, reads, writes: Scene.currentSchemaVersion)`; before any file access. Recovery writes (T031) are not gated (depends on T026)

**Checkpoint**: all four stories' tests pass

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: the performance budgets, and the documentation the constitution requires in the same change

- [X] T037 [P] Write `app/benchmark/document_benchmark_test.dart` (SC-005, SC-006), untagged (it lives outside `test/`, so CI's `flutter test` never runs it): a 1,000-Node `generatedScene`; after 100 warm-up steps, time 1,000 one-Node `transact` calls (a `replaceNode` changing one transform), 200 undos and 200 redos on a `DocumentSession` with a `MemoryFileSystem`, and print median and p95 in microseconds; time `open` and `save`; for SC-006, take a heap snapshot through the VM service (`HeapSnapshotGraph`, run with `--enable-vmservice`) and print the bytes a 200-step history reaches that neither the Scene nor its opening state reaches, next to the Scene's own bytes (adds `vm_service` as a dev dependency; it is already in the lock through `flutter_test`)
- [X] T038 Run `cd apps/editor && flutter test --enable-vmservice benchmark/document_benchmark_test.dart`; if the median transaction, undo or redo is ≥ 1 ms (SC-005) or the history holds ≥ 2 MB (SC-006), profile and fix before continuing. Record the numbers, machine and date in a "Document model" section of `dev-docs/ARCHITECTURE.md`, saying they are JIT and that memory comes from a heap snapshot, and why SC-006 changed from 10% to 2 MB (depends on T037)
- [X] T039 [P] Add to `GLOSSARY.md` under "Editing and running": **Transaction** ("A named change to a Document, such as *Move 3 Nodes*; the only way a Document changes, and one step of undo."), **Coalescing key** ("The identifier that merges the transactions of one continuous gesture (a drag, a slider scrub, typing in one field) into one undo step."), **Unsaved changes** ("A Document whose state differs from its Scene file on disk; shown with a marker and confirmed before closing.", `_Avoid_: dirty (in user-facing text)`), **Recovery copy** ("A copy of a Document with unsaved changes, kept outside the project so the work survives a crash; Pyro offers to restore it on the next launch.", `_Avoid_: autosave, backup`)
- [X] T040 [P] Record this spec's decisions in `dev-docs/decisions.md` as Q94–Q99 (and add "Q94–Q99 from the Document model spec (`specs/002-document-model/`, 2026-10-19)" to the opening paragraph): Q94 the toolchain stays on Flutter 3.44.2 with freezed 3.2.6-dev.1 and riverpod_generator 4.0.4 until the pin moves (R1); Q95 saving refuses when the Scene file changed on disk since it was opened or saved, with a forced overwrite (FR-019a); Q96 a Scene repaired on open has unsaved changes, and the repair isn't an undo step (FR-016); Q97 recovery copies live in Pyro's application support folder, keyed by project and Scene path, pruned after 30 days (FR-025, FR-025a; amends Q55); Q98 saving refuses while the Runtime's readable `schemaVersion` is unknown (FR-022; details Q49); Q99 the history's memory budget is absolute (SC-006, under 2 MB) and diff-based undo may come later (see Q22)
- [X] T041 [P] Update `dev-docs/project-plan.md` §8.1 and §8.2: the parent index beside the Node map and the Runtime's Node classes reused (R2), identity equality for the document and history (R4), the coalescing, cap and dirty rules (R5), the changed-on-disk check (R8), and the recovery location and 30-second default interval (R11, R12); mark the `IMap` bullet as decided; link `specs/002-document-model/`
- [X] T042 [P] Add the resolution finding to `dev-docs/ARCHITECTURE.md` (near the spike #2 build_runner notes): in this workspace on Flutter 3.44.2, `test` (needed by the pure-Dart packages) caps analyzer at 12, so spike #4's freezed 4.0.0-dev.3 and riverpod_generator 4.0.9 don't resolve; the working set is R1's; Flutter 3.47.x would allow stable freezed 4.x
- [X] T043 Tick "#2 Document model" in `dev-docs/phases.md` Phase 2, update its Status line and the "Left" column, and add to the #1 bullet there: "wrap `DocumentSession` in `documentProvider(sceneId)`; call `RecoveryStore.find` before opening a Scene and pass the compatibility check's version to `save`" (depends on T038–T042)
- [X] T044 Run the full gate from the repository root: `dart format --output=none --set-exit-if-changed packages apps`, `flutter analyze --fatal-infos apps/editor`, `cd apps/editor && dart run build_runner build -d && git diff --exit-code -- lib`, and `cd apps/editor && flutter test`; then walk through [quickstart.md](quickstart.md) §1–§6 and confirm each expected outcome

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup; blocks every story
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on US1's `OpenDocument` and `DocumentSession` (T017, T018)
- **US3 (Phase 5)**: depends on US2's `writeAtomically` and session saving (T024, T027)
- **US4 (Phase 6)**: depends on US2's `SceneFiles.save` (T026); independent of US3
- **Polish (Phase 7)**: T037 needs US1 and US2; T043 and T044 need everything

```text
Setup → Foundational → US1 → US2 ─┬─ US3 ─┐
                                  └─ US4 ─┴─ Polish
```

US3 and US4 touch different files except `document_session_test.dart` (US3 only) and
`scene_files.dart`/`scene_files_test.dart` (US4 only), so they can be built side by side.

### Within Each Story

- Tests first, run and seen failing
- Values before services, services before the session, the session before the exports
- Run `build_runner` after any freezed change and commit the output in the same commit
- The story's checkpoint passes before the next story starts

### Parallel Opportunities

- Setup: T003, T004, T005, T006
- Foundational: tests T007, T008; then T009 and T010 together; then T011
- US1: tests T012, T013, T014 together; T016 alongside T015
- US2: tests T020–T023 together; T024 alongside T025
- US3: tests T029, T030; T031 and T032 together
- US3 and US4 as a whole, once US2 is done
- Polish: T037, T039–T042

---

## Parallel Example: User Story 1

```bash
# Tests for User Story 1, together:
Task: "Add the edits group to app/test/document/scene_document_test.dart"
Task: "Write app/test/document/history_test.dart"
Task: "Write app/test/document/document_session_test.dart (editing group)"
```

## Parallel Example: User Story 3

```bash
# Store and timer, side by side:
Task: "Implement RecoveryStore in app/lib/document/src/recovery_store.dart"
Task: "Implement RecoveryTimer in app/lib/document/src/recovery_timer.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup
2. Phase 2: Foundational
3. Phase 3: US1
4. **Stop and validate:** edits, undo, redo and coalescing behave as the spec says, in memory

### Incremental Delivery

1. Setup + Foundational → the document value exists
2. US1 → editing with undo (MVP)
3. US2 → open and save, byte for byte, atomically
4. US3 → crash recovery
5. US4 → the `schemaVersion` gate
6. Polish → budgets measured, docs in sync, Phase 2's #2 ticked

Nothing here reaches users before #1 puts a window around it, and Phase 2's "Done when" needs
the round trip, so all four stories are needed before the work counts as done. The order above
is for checking progress, not for releasing.

---

## Notes

- [P] tasks = different files, no dependencies on unfinished tasks
- Commit after each task or logical group (Conventional Commits, citing Q numbers where one
  applies), on `specs/002-document-model`
- Stop at any checkpoint to validate a story on its own
