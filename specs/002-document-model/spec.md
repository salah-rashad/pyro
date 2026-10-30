# Feature Specification: Document Model

**Feature Branch**: `specs/002-document-model`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "#2 Document model (Phase 2 of dev-docs/phases.md), in the app: add
`freezed` (and Riverpod, for Phase 4); `SceneDocument` (flat `NodeId → Node` map over the shared
scene model in pyro_runtime), named transactions, undo/redo with coalescing, dirty flag, atomic
save/load, recovery file (Q55; the interval is a fixed default until Settings arrive in Phase 7,
Q85), `schemaVersion` gate (Q49). Deferred: migrations framework. See project-plan.md §8.1, §8.2.
Tests: document and history; a fixture scene round-trips through the Document model byte for
byte."

## Overview

The Document is Pyro's in-memory, undoable model of one open Scene. Every editor panel built in
Phase 4 (hierarchy, viewport, inspector, Behaviors) reads it and changes it, and nothing else may
change it. This feature defines what the Document holds, how it changes, how changes are undone,
how it knows it has unsaved work, how it reaches disk without ever leaving a half-written or
unreadable Scene, and how work survives a crash.

It is the second piece of Phase 2 (project-plan §8.1, §8.2; phases.md #2). It builds on the Scene
format (`specs/001-scene-format/`), which it reads and writes through `pyro_runtime` and doesn't
change. It has no editor UI: the window, scene tabs, close confirmation and the *Restore* prompt
are #1, which uses the operations defined here.

**Who uses it**

- **Game developer** (through the editor, from Phase 4 on): edits a Scene, undoes and redoes,
  saves, and gets their work back after a crash.
- **Editor panels** (Phase 4): change the Scene only through named transactions and read the
  current state of individual Nodes.
- **The running game**: sees only what the developer saved, never a half-finished edit or a
  half-written file (Hot-swap reads the saved Scene, §9.3).

## Clarifications

### Session 2026-10-19

- Q: If the Scene file changed on disk after Pyro opened it, what should saving do? → A: Save
  checks whether the file changed since it was opened or last saved; if it did, the save is
  refused with a "changed on disk" error, the document keeps its edits, and the caller can force
  an overwrite.
- Q: When Pyro opens a Scene it had to repair, should the document start with unsaved changes?
  → A: Yes; it starts dirty, so closing prompts the developer to save the repair. The repair is
  not an undoable step: the damaged tree never exists in the document.
- Q: If Pyro doesn't yet know which `schemaVersion` the project's Runtime reads, should saving be
  refused? → A: Yes; saving is refused until the compatibility check (#1) supplies it, and callers
  (including tests) pass it explicitly.
- Q: Where should recovery copies be kept? → A: In Pyro's application data folder, keyed by
  project and Scene path, never inside the project (so `flutter clean` and `git clean` can't
  delete them); copies older than 30 days are pruned.
- Q: SC-006's "less than 10% more memory than the Scene" can't be met by snapshot undo (*Q22*):
  each one-Node step keeps one new Node, so 200 steps on a 1,000-Node Scene cost about 20% of it
  before any map overhead (measured during implementation, 2026-10-19). What should the budget
  be? → A: An absolute budget: under 2 MB (measured 0.9 MB), keeping the collection library's
  defaults. Diff-based undo may come later as an enhancement.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Edit a Scene and undo or redo any step (Priority: P1)

A developer adds an entity, renames it, drags it across the viewport and types a new speed into
its Behavior. Each of these is one named step. They undo three times and the Scene is exactly as
it was before the drag; the drag, made of a hundred small moves, comes back as one step when they
redo. Undo and redo are labelled with what they will undo or redo ("Undo Move 3 Nodes").

**Why this priority**: every editing feature in Phase 4 is built on transactions, and undo is
what makes editing safe to try. Without it there is nothing for the panels to call.

**Independent Test**: apply sequences of transactions to a fixture document, undo and redo in
various orders, and compare every resulting state with the expected snapshot.

**Acceptance Scenarios**:

1. **Given** an open document, **When** a named transaction changes it, **Then** the document
   holds the new state and the history gains one entry carrying the transaction's name.
2. **Given** a document after several transactions, **When** the developer undoes, **Then** the
   document is exactly the state before the last transaction, and redo restores the state after
   it.
3. **Given** a run of transactions sharing one coalescing key with nothing else in between (a
   drag, a slider scrub, typing in one field), **When** they finish, **Then** they form a single
   history entry, and one undo returns to the state before the first of them.
4. **Given** two consecutive gestures with different coalescing keys, or the same key with
   another transaction in between, **When** they finish, **Then** they form separate entries.
5. **Given** an undone step, **When** a new transaction is applied, **Then** the undone steps
   can no longer be redone.
6. **Given** a transaction that changes nothing, **When** it is applied, **Then** no history
   entry is added and the dirty state doesn't change.
7. **Given** a transaction that fails or would leave the Scene invalid (a Node under its own
   descendant, a removed root), **When** it is applied, **Then** the document and history are
   unchanged and the error names the transaction and the Nodes involved.
8. **Given** a transaction that changes one Node, **When** it is applied, **Then** every Node it
   didn't change is still the very same value as before, so panels and the viewport can skip
   them.

---

### User Story 2 - Open and save a Scene without loss (Priority: P1)

A developer opens a Scene, makes no change and saves: the file is byte-for-byte the same. They
edit and save: the file holds the edit, and the game running at that moment hot-swaps either the
old file or the new one, never something in between. The editor marks the Scene as having unsaved
changes from the first edit until the save, and undoing back to the saved state clears the mark.

**Why this priority**: losing or corrupting a developer's Scene is the one failure Pyro can't
afford (constitution IV). The dirty mark drives the close confirmation in #1.

**Independent Test**: load each canonical fixture Scene into a document, save it, and compare
bytes; simulate a failure in the middle of a save and check the original file is intact.

**Acceptance Scenarios**:

1. **Given** a Scene file in canonical form, **When** it is opened as a document and saved
   without changes, **Then** the file is byte-identical to before.
2. **Given** a document with edits, **When** it is saved, **Then** the file holds exactly the
   current state in canonical form, and opening it again gives the same state.
3. **Given** a save that fails partway (disk full, permission denied, the process killed),
   **When** the file is read afterwards, **Then** it is either the complete old file or the
   complete new file, and no temporary file is left behind after a failure Pyro can observe.
4. **Given** a freshly opened or freshly saved document, **When** it is inspected, **Then** it
   is clean; after any transaction it is dirty.
5. **Given** a dirty document, **When** undo or redo reaches the state that was last saved,
   **Then** it is clean again; moving away from that state makes it dirty again.
6. **Given** a Scene file that is valid but not in canonical form, **When** it is opened,
   **Then** the document is clean, and saving it writes the canonical form.
7. **Given** a Scene file damaged by a merge, **When** it is opened, **Then** the document holds
   the repaired tree, exposes the repair report, and is dirty, so the developer is prompted to
   save the repair; the file on disk is untouched until they do.
8. **Given** a file that can't be opened (newer `schemaVersion`, malformed JSON, missing root),
   **When** opening is attempted, **Then** no document is created and the error names the file
   and the problem, as the Scene format reports it.
9. **Given** a new, unsaved Scene, **When** it is created, **Then** it holds only a root Node,
   has no file yet, and must be given a file path on its first save.
10. **Given** a document whose Scene file was changed on disk after it was opened or last saved
    (a `git pull`, another tool), **When** it is saved, **Then** nothing is written, the document
    keeps its edits and stays dirty, and the error says the file changed on disk; **When** the
    save is then repeated as a forced overwrite, **Then** it writes the document's state.

---

### User Story 3 - Get unsaved work back after a crash (Priority: P2)

A developer edits a Scene for twenty minutes without saving, and Pyro crashes (or the machine
loses power). They start Pyro again and open the project. Pyro offers to restore the Scene; they
accept, and the Scene is as it was at most a recovery interval before the crash, marked as
unsaved. The Scene file itself was never written behind their back, so the running game never saw
the half-finished edits.

**Why this priority**: required by the Data Integrity principle and *Q55*; it matters less often
than stories 1 and 2, but losing twenty minutes of work is the kind of failure users remember.

**Independent Test**: with a fake clock and file system, edit a document, advance time past the
interval, discard the document without saving (a simulated crash), and check that recovery finds
the copy and restores the expected state.

**Acceptance Scenarios**:

1. **Given** a dirty document, **When** the recovery interval passes, **Then** a recovery copy of
   the current state is written, and the Scene file is not touched.
2. **Given** a clean document, **When** the interval passes, **Then** no recovery copy is
   written.
3. **Given** a recovery copy exists, **When** the document is saved or the developer discards
   their changes and closes it, **Then** the recovery copy is removed.
4. **Given** a recovery copy left by a crash, **When** its Scene is opened again, **Then** Pyro
   can tell that a recovery copy exists and when it was written, so #1 can offer *Restore*.
5. **Given** the developer restores, **When** the document opens, **Then** it holds the recovered
   state, is dirty, has an empty history, and saving writes the Scene file as usual.
6. **Given** the developer declines to restore, **When** the document opens, **Then** it holds
   the Scene file's state and the recovery copy is removed.
7. **Given** a recovery copy that can't be read (damaged, or from a newer `schemaVersion`),
   **When** recovery is checked, **Then** the copy is kept (until pruned, FR-025a), the Scene
   opens from its file, and the problem is reported with the copy's location rather than
   silently ignored.

---

### User Story 4 - Never write a Scene the game can't read (Priority: P2)

A developer's game depends on an older `pyro_runtime` that reads only an older `schemaVersion`
than this Pyro writes. They edit a Scene and save. Instead of writing a file their game would
refuse at startup, Pyro refuses to save, keeps the edits in the document, and says which version
the Runtime reads, which version Pyro writes, and that the Runtime should be upgraded.

**Why this priority**: required by *Q49* and constitution IV. Only `schemaVersion` 1 exists
today, so no project can hit it yet, but the rule must be enforced before the first format change
ships.

**Independent Test**: save documents with the newest readable version set below, equal to and
above the version Pyro writes, and check that only the first is refused and nothing is written.

**Acceptance Scenarios**:

1. **Given** the project's Runtime reads at most version N and Pyro writes version N, **When** a
   document is saved, **Then** the save succeeds.
2. **Given** the project's Runtime reads at most a version below the one Pyro writes, **When** a
   document is saved, **Then** nothing is written, the document stays dirty with its edits, and
   the error names both versions and suggests upgrading the Runtime.
3. **Given** the newest readable version isn't known yet (the compatibility check of #1 hasn't
   run), **When** a document is saved, **Then** the save is refused in the same way rather than
   assumed safe.

---

### Edge Cases

- **Huge gestures:** a drag producing thousands of coalesced steps still costs one history entry
  and stays within the editing budget (SC-005).
- **History limit:** after more steps than the history keeps, the oldest entries are dropped; the
  current state and the saved state are never lost. If the saved state's entry is dropped, the
  document stays dirty until the next save.
- **Coalescing across a save:** a transaction with the same coalescing key as the entry before a
  save starts a new entry, so undo can always return exactly to the saved state.
- **Undo with nothing to undo / redo with nothing to redo:** does nothing, and reports that it
  can't (so the editor can disable the command).
- **Save while a gesture is in progress:** the save writes the current state; the gesture
  continues as a new entry afterwards (see coalescing across a save).
- **Saving to a new path** ("Save as", and the first save of a new Scene): the target is written
  atomically like any save; from then on the document belongs to the new path.
- **Saving onto a path whose folder doesn't exist, or a read-only file:** the save fails with an
  error naming the path; the document keeps its edits and stays dirty.
- **Data the editor doesn't understand** (unknown Node kinds, unknown keys, Overrides for fields
  that no longer exist, *Q32*): untouched by every transaction that doesn't edit it, and written
  back unchanged on save.
- **Removing a Node:** removes its whole subtree in one step; undo brings back every removed Node
  with its data, position among its siblings and IDs.
- **Moving a Node:** under itself or one of its descendants, or moving or removing the root, is
  refused as an invalid transaction (User Story 1, scenario 7).
- **Two documents open at once:** each has its own history, dirty flag and recovery copy; a
  transaction in one never affects another.
- **Recovery copy older than the Scene file** (the file was saved by another tool after the
  crash): the copy is still offered, with both times available so #1 can say which is newer.
- **Project moved or renamed between the crash and the next launch:** the copy is keyed by the
  old paths, so it isn't offered; it stays on disk until pruned (FR-025a).
- **Scene file deleted or renamed while open:** treated as changed on disk (FR-019a): the save is
  refused until it is forced, which writes the file again at the document's path.
- **External change that leaves the bytes identical** (a checkout of the same content, a touch):
  not a change; the save goes ahead.

## Requirements *(mandatory)*

### Functional Requirements

**Document**

- **FR-001**: A document MUST hold one Scene as a flat map of Nodes by Node ID, with each Node's
  parent and ordered children available in memory; only the ordered children are written to
  disk (*Q23, Q47*).
- **FR-002**: A document MUST be immutable: each change produces a new document state, and a
  state once produced never changes.
- **FR-003**: A change MUST keep every Node it doesn't touch as the same value (structural
  sharing), so consumers can detect unchanged Nodes without comparing their contents.
- **FR-004**: A document MUST hold only Scene data. Selection, camera, panel sizes and hover are
  not part of it and are not undoable (*Q25*).
- **FR-005**: A document MUST preserve every piece of Scene data it doesn't understand, as the
  Scene format does (constitution IV, *Q32*).

**Transactions**

- **FR-006**: The only way to change a document MUST be a named transaction: a label shown to the
  developer (for example "Move 3 Nodes") plus a change to the current state (*Q22*).
- **FR-007**: The document MUST offer these basic changes for transactions to combine: add a Node
  under a parent at a position among its siblings, remove a Node with its whole subtree, move a
  Node to another parent or position, and replace a Node's data. Each keeps the Scene a valid
  tree, and new Nodes get a new unique Node ID (a UUID, *Q14*).
- **FR-008**: A transaction MUST be all-or-nothing: if it fails or would produce an invalid
  Scene, the document and history are unchanged and the error names the transaction label and
  the Nodes involved.
- **FR-009**: A transaction that results in no change MUST NOT add a history entry or change the
  dirty state.

**History**

- **FR-010**: History MUST be a sequence of document states, each labelled with the transaction
  that produced it; undo and redo move between them, so every undo restores an exact earlier
  state (*Q22*).
- **FR-011**: Consecutive transactions with the same coalescing key MUST merge into one history
  entry labelled with the first transaction's label. Any other transaction, an undo, a redo or a
  save ends the run.
- **FR-012**: A new transaction after one or more undos MUST discard the steps that could have
  been redone.
- **FR-013**: The document MUST report whether undo and redo are possible and the labels they
  would apply.
- **FR-014**: History MUST keep at least the 200 most recent entries; older entries are dropped
  first. History MUST NOT be saved across sessions (*Q55*).

**Dirty state**

- **FR-015**: A document MUST be dirty exactly when its current state isn't its saved state (the
  state last saved, or opened unchanged from its file), as reached through history; undoing or
  redoing back to the saved state makes it clean. A repaired or restored document has no saved
  state until its first save; a new document's root-only state counts as saved, so an untouched
  new Scene closes without a prompt.
- **FR-016**: A document opened from a file the reader repaired MUST start dirty, with the repair
  report available, and MUST NOT write the repair to disk until the developer saves (spec 001,
  FR-025). The repaired tree is the document's first state, with no history entry to undo back
  to the damaged tree; it has no saved state (FR-015).

**Open and save**

- **FR-017**: Opening MUST read the Scene file without blocking the editor, through the shared
  Scene format, and MUST create no document when reading fails; the error names the file path and
  the problem.
- **FR-018**: Saving MUST write the current state in canonical form, so a document opened from a
  canonical file and saved unchanged reproduces it byte for byte.
- **FR-019**: Saving MUST be atomic: the new contents are written in full next to the target and
  then replace it in one step, so any reader (the running game, git, another tool) sees either the
  complete old file or the complete new file. A failed save MUST leave the target as it was,
  remove the partial file when possible, and keep the document's edits and dirty state.
- **FR-019a**: Before writing, saving MUST check that the Scene file's contents are still the
  ones the document last opened or saved. If the file was changed, deleted or replaced on disk,
  the save MUST be refused with an error naming the path and saying it changed on disk, leaving
  the file and the document untouched; the caller MAY then repeat the save as a forced overwrite.
  A first save or "Save as" onto an existing file is refused the same way unless forced.
- **FR-020**: Saving MUST NOT block the editor, and edits made while a save is running MUST NOT be
  lost or written half-way.
- **FR-021**: A new document MUST hold only a root Node and no file path; its first save, and any
  "Save as", MUST name the target path.

**`schemaVersion` gate (*Q49*)**

- **FR-022**: Saving MUST be given the newest `schemaVersion` the project's Runtime reads, and
  MUST refuse to write when the version Pyro writes is newer, or when that newest readable version
  isn't known. The refusal MUST name both versions and suggest upgrading the Runtime, and MUST
  leave the file and the document untouched.
- **FR-023**: Opening a file with a newer `schemaVersion` than Pyro reads MUST be refused, as the
  Scene format already does. Migrating older files is deferred (see Assumptions).

**Recovery (*Q55, Q85*)**

- **FR-024**: While a document that has a file path is dirty, Pyro MUST write a recovery copy of its current state at
  a fixed interval of 30 seconds, until Settings make the interval configurable (Phase 7, *Q85*).
  A clean document MUST NOT be written.
- **FR-025**: Recovery copies MUST be written atomically, in the Scene format, in Pyro's own
  application data folder (never inside the developer's project), keyed by the project's and the
  Scene file's paths, and MUST record which project and Scene file they belong to and when they
  were written.
- **FR-025a**: When Pyro checks for recovery copies, it MUST delete copies older than 30 days, so
  copies of deleted or moved projects don't accumulate.
- **FR-026**: Pyro MUST NEVER write the Scene file itself except when the developer saves; the
  recovery copy is the only automatic write.
- **FR-027**: Saving a document, or closing it after the developer chose to discard its changes,
  MUST remove its recovery copy.
- **FR-028**: Pyro MUST be able to tell, for a Scene, whether a recovery copy exists and when it
  and the Scene file were last written, and MUST be able to open a document from the copy
  (dirty, with empty history, saving to the Scene's own path) or discard the copy. A restored
  document's changed-on-disk check (FR-019a) compares against the Scene file as it was when the
  copy was restored.
- **FR-029**: A recovery copy that can't be read MUST be kept until the 30-day prune removes it
  (FR-025a), and the problem reported with its location; the Scene then opens from its file.

**Errors**

- **FR-030**: Every error MUST name what failed and where: the file path, and when known the
  transaction label, Node ID, Node name or `schemaVersion` involved (constitution I).

### Key Entities

- **Document**: one open Scene in Pyro: its current state, its history, its file path (none for
  a new Scene), its dirty state and, after opening, the repair report.
- **Document state**: one immutable version of the Scene's Nodes, with each Node's parent and
  ordered children.
- **Transaction**: a named change to the document state, with an optional coalescing key.
- **History entry**: a document state plus the label of the transaction (or run of coalesced
  transactions) that produced it.
- **Coalescing key**: an identifier shared by the transactions of one continuous gesture.
- **Saved state**: the history entry last saved, or opened unchanged from its file; the document
  is clean when it is the current one. Repaired and restored documents have none until saved; a
  new document's root-only state counts as saved.
- **Recovery copy**: a copy of a dirty document's state, kept outside the project, with the Scene
  path and project it belongs to and the time it was written.
- **Readable `schemaVersion`**: the newest Scene version the project's Runtime can read, given to
  the document by the Runtime compatibility check (#1).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the canonical fixture Scenes from the Scene format are byte-identical after
  being opened as a document and saved.
- **SC-002**: For every tested sequence of transactions, undos and redos, each state reached by
  undo or redo equals the state recorded at that point, and the document is clean exactly at the
  saved state.
- **SC-003**: In repeated interrupted-save tests, the Scene file is never found partially
  written: it is always the complete old or the complete new file.
- **SC-004**: After a simulated crash, restoring loses at most one recovery interval (30 s) of
  edits, and the Scene file is unchanged since the last save in 100% of cases.
- **SC-005**: On a 1,000-Node Scene on the reference Mac, the median time to apply a
  one-Node transaction, an undo or a redo is under 1 ms, so a drag or a number scrub keeps the
  editor's 60 fps budget with room for panels and the viewport (constitution III).
- **SC-006**: On the same Scene, a full history of 200 one-Node steps holds less than 2 MB
  beyond the Scene and its opening state, because steps share unchanged Nodes.
- **SC-007**: No save that would write a `schemaVersion` the project's Runtime can't read
  succeeds, in 100% of tested cases.

## Assumptions

- **Only `schemaVersion` 1 exists.** The migrations framework is deferred (phases.md, #2) until
  the first format change after the preview; this feature only refuses newer files and refuses to
  write versions the Runtime can't read.
- **The newest readable version comes from #1.** The Runtime compatibility check reads
  `pubspec.lock` (*Q49*) and is built with the app shell; this feature takes its result as an
  input and refuses to save without one.
- **UI is out of scope.** The scene tabs, dirty marker, close confirmation, *Restore* prompt and
  error presentation are #1; the panels that issue transactions are Phase 4. This feature is
  tested headless.
- **Edit operations beyond the basics** (rename, set or reset an Override, add or remove a
  Behavior, duplicate) are built by the panels in Phase 4 on top of FR-007's basic changes.
- **Recovery copies live in Pyro's own application data folder** (FR-025), so they never appear
  in the developer's git status, asset bundle or Hot-swap, and survive `flutter clean`. The cost:
  a copy is found only at the paths it was written for.
- **A new Scene gets recovery copies from its first save on** (FR-024): before that it has no
  path to key a copy by or to open again.
- **Interval and history limit are fixed defaults:** recovery every 30 seconds while dirty, and at
  least 200 history entries. Settings for the interval arrive in Phase 7 (*Q85*).
- **A Scene file changed on disk while open** is caught only at save time (FR-019a). Watching
  files as they change and §11's *Reload* / *Keep mine* banner belong with the editor window (#1)
  or later; that banner's *Keep mine* is the forced overwrite.
- **Deleting a Node that an entity reference points to** keeps the reference as written; the
  warning before deletion (§11, proposed) is the hierarchy's job (#3).
- **Dependencies:** the app gains its model and state-management libraries here (freezed, and
  Riverpod ready for Phase 4, *Q26*) and keeps using `pyro_runtime` for the Scene format; it gains
  no dependency on the generator (constitution II). Any immutable-collection library for
  structural sharing (§8.1, proposed) is chosen in the plan.
