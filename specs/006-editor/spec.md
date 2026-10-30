# Feature Specification: Editor

**Feature Branch**: `specs/006-editor`

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "Phase 4 — Editor (dev-docs/phases.md): #1 App shell and editor window
(preview part: Riverpod providers, project list and open project, basic SDK detection, Runtime
compatibility check from `pubspec.lock`, the editor window on `PrEditorShell` with panel slots,
scene tabs, new/open/save scene, the dirty marker, close confirmation, recovery *Restore*
prompt); #6 built-in Node kinds, editor side (Type catalog from the Manifest + hand-written
descriptors, reload when the Manifest changes, preview components, placeholders for custom
components); #4 Viewport (preview world, reconciler, pan/zoom, selection, move gizmo, disk
assets through `AssetSource`); #3 Hierarchy (add, delete, rename, reparent by drag on
`PrTreeRow`); #5 Inspector (transform, editors for `int`, `double`, `bool`, `String`, enum,
`Vector2`, asset-path dropdown, Override markers and *Reset to default*; other Field types
read-only); #9 Behaviors in the inspector (add/remove, compatibility filtering, Missing
behavior/component states with values kept). Done when: in `example/`, a scene is built from
scratch in Pyro (entity, sprite, hitbox, a custom Behavior with edited fields), saved, closed
and reopened unchanged, and deleting the Behavior's class shows it as Missing with its values
kept."

## Overview

Phases 1–3 built everything around the editor: the design system (29 `Pr` components, the
`PrEditorShell`), the Scene format, the Document model with transactions and recovery, the
Generator with its Manifest, the Runtime, and the whole loop proven end to end on the reference
Mac — with the Scene edited as JSON in a text editor. Phase 4 replaces that text editor: the
Pyro editor window itself, where a scene is built and edited visually and saved through the
Document model (project-plan §14, build order `1 → 6 → 4 → 3 → 5 → 9`; phases.md Phase 4).

Six work items, each building on the last:

1. **#1 App shell and editor window (preview part)**: the Riverpod provider layout of §8.5, the
   project list with open project, basic SDK detection (*Q39*) and the Runtime compatibility
   check from `pubspec.lock` (*Q49*); the editor window on `PrEditorShell` with panel slots,
   scene tabs, new/open/save scene, the dirty marker, close confirmation and the recovery
   *Restore* prompt. `DocumentSession` (spec 002) is wrapped in `documentProvider(sceneId)`;
   `RecoveryStore.find` runs before a Scene is opened, and the compatibility check's version is
   passed to `save`.
2. **#6 Built-in Node kinds, editor side**: the Type catalog — the Manifest parser plus
   hand-written descriptors for entity, sprite, rectangle and circle hitbox — reloaded when the
   Manifest file changes (§9.2); preview components for the built-in kinds; placeholders for
   custom components (*Q6*).
3. **#4 Viewport**: the preview world (a `FlameGame` that never ticks user logic), the
   reconciler (document diff → component operations), pan/zoom, selection, the move gizmo, and
   disk assets through `AssetSource` (*Q79*). §8.3
4. **#3 Hierarchy**: add, delete, rename and reparent by drag, on `PrTreeRow`.
5. **#5 Inspector**: the transform section; editors for `int`, `double`, `bool`, `String`,
   enum, `Vector2` and an asset-path dropdown; Override markers and *Reset to default*
   (ADR 0003). Other Field types show read-only and round-trip untouched. §8.4
6. **#9 Behaviors in the inspector**: add/remove, compatibility filtering by parent type,
   Missing behavior and Missing component states with values kept (*Q32*).

Everything the panels show and edit goes through the data contract Phase 2 built and Phase 3
guarded: the catalog comes from the committed Manifest, the document from spec 002's
`SceneDocument`, and saving produces exactly the canonical JSON the contract test loads. Data
integrity is never cut, even where breadth is (constitution IV): unknown types, missing
Behaviors and orphaned field values are preserved verbatim and shown, never dropped.

**Who uses it**

- **Pyro's author** (and, from Phase 5 on, the testers): opens `example/` (and later any Flame
  project) in Pyro, builds and edits scenes visually, and saves them through the same canonical
  format the running game hot-swaps.
- **CI**: the widget and reconciler tests this phase adds run on every push, next to the
  contract job Phase 3 turned on.
- **Later work**: Phase 5's Play button, Console and build_runner watcher plug into the same
  editor window (`processProvider`, the bottom panel slot); Phase 7's deferred parts (grid,
  snapping, more field editors, duplicate/filter) extend the panels built here.

**Out of scope** (deferred items, per §14's preview column): Play, the Console, the
build_runner watcher, auto code reload, Attach (all #11, rest — Phase 5); the asset browser and
pubspec sync (#10 — Phase 7), so no asset import UI and no pubspec editing beyond the warning in
FR-008; grid, snapping, rotate/scale gizmos and the reference rectangle (*Q85*) (#4, v0.1);
duplicate, filter and the duplicate-name warning (*Q51*) (#3, v0.1); editors for `Color`, entity
reference, `Sprite` and `SpriteAnimation` (#5, v0.1 — read-only here); multi-select "mixed"
values (*Q65*, v0.1.1); the third hitbox kind, behavior reorder and Missing behavior polish
(#6/#9, v0.1); the "Add Pyro" flow, SDK management and settings (#1, v0.1 — the README recipe
stands in); anything on Windows or Linux beyond CI's widget tests.

## Clarifications

### Session 2026-10-22

- Q: Which fields does the inspector's Transform section edit in this phase? → A: All five —
  position, angle, scale, size and anchor — as plain number/Vector2 rows on the existing
  components. §14's "numeric editing in the inspector covers them" for rotate/scale is then
  honored without gizmos; the 3×3 anchor picker of the design prompts waits for the design
  review (a new pattern, proposed only if the plain row proves insufficient).
- Q: What does a brand-new scene contain when it is created? → A: One root Node; entities are
  added from there, and the file is named at first save.
- Q: What happens when a typed or scrubbed number lands outside the field's `min`/`max`? → A:
  The committed value is clamped to the range and the field shows the clamped result —
  scrubbing already stops at the limits, and rejecting the entry would fight typing and
  scrubbing alike.
- Q: When are the Claude Design view designs generated, given the tool is unavailable now? →
  A: Later. The prompts are synced, so the views can be generated at any time; the spec, plan
  and tasks proceed now, and each panel's implementation waits for its view design (the
  "New patterns" rule of `claude-design-prompts.md`) — not the other way around.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Open a project and edit scenes in the editor window (Priority: P1)

The author launches Pyro. The project list shows their recent projects with the detected
Flutter version for each; `example/` is there. They open it: Pyro checks the project's
`pyro_runtime` version from `pubspec.lock` against its built-in compatibility range and reports
the result. The editor window appears — `PrEditorShell` with the Hierarchy on the left, the
Viewport in the centre, the Inspector on the right — and they open `level1.scene.json`: Pyro
finds it under the project's declared asset folders, finds no recovery copy, and the scene
appears in a tab. They edit something (story 5), and the tab gains the dirty marker. They close
the tab: Pyro asks whether to save, discard or cancel. They save: the file is written
atomically in the canonical format, the dirty marker clears, and `git diff` on the scene file
shows only the intended change.

**Why this priority**: nothing else in Phase 4 runs without a window, an open project, the Type
catalog's host and scene files to work in (§14's build order puts item 1 first for exactly
that). It is also where the two safety prompts live (close confirmation, recovery *Restore*).

**Independent Test**: open `example/` in Pyro with a recovery copy planted for one scene, open
that scene, edit, close without saving, cancel, save, and reopen. Every prompt and marker
appears at the right moment; the saved file is byte-identical to what the Document model's
writer produces (spec 002).

**Acceptance Scenarios**:

1. **Given** Pyro launched with no project open, **When** the project list appears, **Then** it
   lists recent projects with each one's detected Flutter version (per-project fvm config →
   `FLUTTER_ROOT` → `flutter` on `PATH`, §9.1), and a project with no detectable SDK says so
   instead of showing a version.
2. **Given** a project is opened, **When** Pyro reads its `pubspec.lock`, **Then** the resolved
   `pyro_runtime` version is checked against Pyro's built-in range: in range → nothing to do;
   too old or too new → a clear message naming the version and the required range (*Q49*), and
   saving is gated until it is in range (FR-004, FR-010).
3. **Given** the editor window, **When** the user opens a Scene, **Then** Pyro looks for
   `*.scene.json` under the project's declared asset folders (§10), calls
   `RecoveryStore.find` first, and if a recovery copy exists for that Scene offers *Restore*
   (restoring it leaves the tab dirty with no saved snapshot, §8.2; *Q55*).
4. **Given** a Scene with a newer `schemaVersion` than the Runtime reads, **When** the user
   opens it, **Then** it is refused with a message naming the required version, not mangled
   (*Q49*; the gate built in spec 002).
5. **Given** a Scene whose tree needed repair (orphans, double parents), **When** it opens,
   **Then** the repairs are reported to the user, the repaired document is dirty with no saved
   snapshot until saved (§8.2, *Q96*).
6. **Given** a dirty scene tab, **When** the user closes it, **Then** Pyro asks save, discard or
   cancel; discard loses the changes on purpose, cancel keeps the tab open.
7. **Given** a clean scene tab, **When** the user closes it, **Then** it closes with no prompt.
8. **Given** the user asks for a new Scene, **When** it is created, **Then** it is an untitled
   tab holding one root Node, and the first save asks for its path, defaulting to the project's
   scene folder (`assets/scenes/`, *Q53*).
9. **Given** the user saves a new Scene into a folder that is not declared in `pubspec.yaml`,
   **When** the save happens, **Then** Pyro warns that the game cannot load from that folder;
   it does not edit the pubspec itself (the sync flow is #10, Phase 7).

---

### User Story 2 - The editor knows the project's types (Priority: P1)

With `example/` open, the Type catalog holds the project's annotated types — the Behavior and
the custom component from the committed `pyro.manifest.json` — plus Pyro's hand-written
descriptors for entity, sprite and the two hitboxes. The Add lists, the Inspector's field rows
and the viewport's placeholders all draw from this one catalog. While Pyro is open, the author
runs `build_runner` themselves (or git-checks out a branch), the Manifest file changes on disk,
and Pyro re-parses it: new types appear in the Add lists, renamed fields show their new names,
and a type whose class was deleted turns its scene Nodes into Missing states — without a
restart. If the Manifest carries generator errors or warnings, they are shown with their code,
file and line (§7.3), and the last good catalog stays in use.

**Why this priority**: the catalog is what every panel reads; items 4–9 build on it, which is
why §14 builds item 6 second. It is also the first time the Manifest has a live consumer, so
its contract is exercised as written (spec 003).

**Independent Test**: with `example/` open, hand-edit `lib/pyro.manifest.json` (add a type,
rename a field, delete a type, break the JSON, add to `errors`) and watch the catalog update,
hold, or report in each case — no restart, no crash.

**Acceptance Scenarios**:

1. **Given** a project with a committed Manifest, **When** it is opened, **Then** the catalog
   parses `lib/pyro.manifest.json` and contains every listed type with its role, label,
   category, parent type, supertypes, accepts-behaviors flag and Editable fields with defaults,
   min/max, enum values and tooltips, exactly as the Manifest carries them (§7.3, *Q57*,
   *Q50*).
2. **Given** the open project, **When** the Manifest file changes on disk, **Then** the catalog
   is re-parsed and every panel that reads it updates: Add lists, field rows, compatibility
   filtering and Missing states re-evaluate (§9.2). Pyro itself runs no generator in this
   phase.
3. **Given** a Manifest whose `errors` array is non-empty, **When** it is parsed, **Then** the
   errors and warnings are shown with their stable code, file, line, class and field, where the
   type would have appeared, and the previous good catalog stays active.
4. **Given** a Manifest that is broken JSON or a version Pyro cannot read, **When** the reload
   happens, **Then** the last good catalog stays active with a clear error, and nothing crashes
   or blanks out.
5. **Given** the built-in Node kinds (entity, sprite, rectangle hitbox, circle hitbox),
   **When** the catalog is built, **Then** their hand-written descriptors declare the same
   shape Manifest types have — fields, parenting rules and supertypes — so panels treat built-in
   and custom types identically.
6. **Given** a type ID that appears in the scene but not in the catalog, **When** the scene is
   shown, **Then** it is a Missing state with its values kept (story 6), never dropped or
   silently renamed.

---

### User Story 3 - Build and place entities in the viewport (Priority: P1)

The scene from story 1 is now empty of interest; the author builds it up. They add Nodes
(story 4), and each appears in the viewport at its position: sprites render from the project's
image files on disk, hitboxes draw as their outlines, custom components draw as placeholders
(box + Type ID, or the `preview:` image, *Q6*). They pan with a drag, zoom with the wheel,
click a Node to select it — the hierarchy row and the inspector follow — and drag the move
gizmo to reposition it, smooth and live. Every document change runs through the reconciler,
which touches only what changed. They replace a sprite's image file on disk with an edit of
their own; within a moment the viewport shows the new pixels, and only the Nodes that read that
file rebuilt. Nothing in the viewport ticks game logic, and Pyro never imports or executes the
project's code (*Q7*).

**Why this priority**: the viewport is the biggest item (6.5 evenings) and the visual half of
the product loop — the thing a text editor cannot do. The reconciler it needs is also the
heaviest-tested seam of the phase (§13).

**Independent Test**: open `example/`'s scene, add and drag Nodes, edit an image file on disk,
and watch the viewport follow. In profile mode on the reference Mac, dragging and scrubbing
hold 60 fps with a 1,000-Node scene.

**Acceptance Scenarios**:

1. **Given** an open Scene, **When** the document changes, **Then** the reconciler walks old
   and new document by `NodeId`: Nodes that are the same object are skipped, changed Nodes
   patch their preview component, added Nodes create components and removed Nodes drop them
   (§8.3) — and nothing else rebuilds.
2. **Given** the viewport, **When** the user pans and zooms, **Then** the camera moves and
   scales smoothly; the camera is editor state, not document state (*Q25*), so it survives
   edits and undo.
3. **Given** Nodes on screen, **When** the user clicks one, **Then** the topmost Node under the
   cursor is selected (outlined by the overlay layer), the hierarchy selects its row and the
   inspector shows it; clicking empty space deselects. Single selection only this phase
   (*Q65*).
4. **Given** a selected Node, **When** the user drags the move gizmo, **Then** the Node's
   position follows the pointer live; the whole gesture is one coalesced transaction named for
   it, so one undo reverts the drag (§8.2).
5. **Given** a sprite's image file edited on disk, **When** the change lands, **Then** only the
   Nodes that read that file rebuild and the new image shows within ~200 ms (spike #3's budget,
   *Q79*); an image is freed only after it is no longer drawn.
6. **Given** an image file missing from disk, **When** a sprite references it, **Then** the
   viewport shows a clear error state for that Node (not a crash), and adding the file makes it
   render.
7. **Given** a custom component, **When** it renders, **Then** it is a placeholder: a labelled
   box with the Type ID, or the `preview:` image when the Manifest carries one (*Q6*).
8. **Given** interactive editing (gizmo drag, scrubbing a number, selecting, typing), **When**
   measured in profile mode on the reference Mac with a 1,000-Node scene, **Then** frames stay
   at or under 16 ms (constitution III).
9. **Given** file or image work the viewport must do, **When** it is large, **Then** it happens
   off the UI isolate or in chunks; no frame is blocked (constitution III).

---

### User Story 4 - Structure the scene in the hierarchy (Priority: P1)

The left panel shows the scene as a tree: the root, its children in order, their children —
one `PrTreeRow` per Node, with the Node's kind and name. The author right-clicks or uses the
Add button to add a child (offered only what the selected parent accepts: an entity under the
root, a sprite under an entity, a hitbox under an entity…), deletes a Node with its subtree,
renames one, and drags a Node onto another to reparent it, or between rows to reorder it. A
drop the parenting rules forbid is refused with the reason. Every action is a named
transaction: undo restores a deleted subtree in one step.

**Why this priority**: the hierarchy is the structural editor and the primary selection surface;
the inspector and viewport are only useful against a scene worth structuring. It is P1 with the
other panels because the phase's Done-when scene is built through all three together.

**Independent Test**: build a scene of a dozen Nodes with every built-in kind and the custom
component, then rename, reorder, reparent, delete and undo each in turn, watching the tree, the
viewport and the saved JSON agree.

**Acceptance Scenarios**:

1. **Given** an open Scene, **When** the hierarchy renders, **Then** it shows the Node tree
   from `childIds` order, one `PrTreeRow` per Node with kind and name, expandable and
   collapsible, its selection the same selection the viewport and inspector use.
2. **Given** a selected Node, **When** the user adds a child, **Then** the Add list comes from
   the catalog, filtered to what the selected parent accepts (parenting rules: hand-written for
   the built-ins, the Manifest's parent-type and supertype rules for custom types, *Q57*);
   the new Node gets a stable unique `NodeId` and a default name, and appears in tree and
   viewport at once.
3. **Given** a Node, **When** the user deletes it, **Then** it and its subtree are removed in
   one named transaction; one undo restores the whole subtree. The root Node cannot be deleted.
4. **Given** a Node, **When** the user renames it, **Then** only its name changes — the
   `NodeId` never changes; a name equal to a sibling's is allowed (the duplicate-name warning
   is v0.1, *Q51*).
5. **Given** a Node dragged onto another, **When** the drop lands, **Then** it is reparented
   there through a transaction; dragged between rows of the same parent, it is reordered.
6. **Given** a drop that would put a Node inside its own subtree, or onto a parent whose rules
   refuse it, **When** the drop lands, **Then** the reparent is refused with a clear reason and
   the tree is unchanged.
7. **Given** a Node of an unknown Type ID, **When** the tree renders, **Then** its row shows a
   Missing state and its children and name are intact (constitution IV).

---

### User Story 5 - Edit fields in the inspector (Priority: P1)

With an entity selected, the right panel shows its transform and its fields, one row per
Editable field from the catalog. `int` and `double` are number fields honouring the Manifest's
`min`/`max` and tooltip; `bool` is a toggle; `String` is text; enums are dropdowns of the
Manifest's values; `Vector2` is the two-number field; an asset path is a dropdown of matching
files on disk. Setting a value marks the field as an Override with a visible marker, and *Reset
to default* removes the Override and shows the code default again — evaluated constants as
values, non-constant defaults as their source text ("default from code", §7.3). Fields of the
types this phase doesn't edit (`Color`, entity reference, `Sprite`, `SpriteAnimation`) show
read-only and round-trip untouched. Typing, scrubbing and dragging merge into one undo step
each; undo and redo work across panels.

**Why this priority**: the inspector is where the scene's content is actually set — the phase's
Done-when scene needs a custom Behavior's fields edited here, and the Override model (ADR 0003)
is the product's core editing concept.

**Independent Test**: select `example/`'s entity, set and reset every editable field type once,
save, reopen, and byte-compare; then check a read-only field's value survives a save untouched
even while its neighbours are edited.

**Acceptance Scenarios**:

1. **Given** a selected Node, **When** the inspector renders, **Then** it shows a transform
   section (position, angle, scale, size, anchor) and one row per Editable field of the Node's
   type from the catalog, in the Manifest's order, on `PrPropertyRow` / `PrNumberProperty` /
   `PrVector2Property`.
2. **Given** a `double` field with `min`/`max` in the Manifest, **When** a value is typed,
   dragged or scrubbed past the range, **Then** the committed value is clamped to the range
   (and the widget shows the clamp; §6.1's `min` above `max` never reaches here — the
   generator rejects it).
3. **Given** an enum field, **When** the dropdown opens, **Then** it offers exactly the
   Manifest's `values`; the current value shows even when it is not among them (a
   kept value from code that changed).
4. **Given** an asset-path field, **When** the dropdown opens, **Then** it lists the matching
   files under the project's declared asset folders, read from disk (new files appear without a
   restart, *Q31*); choosing one stores the project-relative path.
5. **Given** a field with an Override, **When** the inspector renders, **Then** the row carries
   the Override marker and *Reset to default*; resetting removes the Override (ADR 0003) and
   the row shows the code default again — the evaluated constant, or the source text for a
   non-constant default.
6. **Given** a field of `Color`, entity-reference, `Sprite` or `SpriteAnimation` type holding a
   value, **When** the inspector renders and the scene is saved, **Then** the row is read-only
   and the value round-trips byte-identically, untouched by any other edit (§14 item 5).
7. **Given** typing in one field, scrubbing a number, or dragging in the viewport, **When** the
   input continues, **Then** consecutive transactions coalesce with one label; the next
   different action, an undo, a redo or a save ends the run (§8.2).
8. **Given** a Node whose type is Missing from the catalog, **When** the inspector renders,
   **Then** no field rows are invented: the Node is shown as Missing with its values kept, and
   editing is limited to what is safe (name, transform of the entity itself) until the type
   returns (story 6).

---

### User Story 6 - Attach Behaviors (Priority: P2)

On the entity, the inspector lists its Behaviors by label. *Add Behavior* opens the catalog's
behaviors grouped by category, filtered to the ones whose required parent type this entity
satisfies (`Behavior<Enemy>` needs an `Enemy` or subclass; entities that don't accept Behaviors
offer none — *Q50*, *Q57*). Adding one sets its fields from the code defaults; the author edits
them (story 5) and the changes mark Overrides. Removing a Behavior drops it and its Overrides,
as one transaction. When a Behavior's class disappears from the project, its entity shows it as
**Missing behavior** — greyed, its values kept and preserved on save — and if the class comes
back (a git checkout, say), the Behavior and its values return intact.

**Why this priority**: Behaviors are the point of Pyro — the custom code a scene attaches — and
the compatibility filtering and Missing states are what make editing safe against code/data
drift. It is last in the build order (#9) because it needs every panel before it, and P2 only
because the other panels are prerequisites for it rather than lesser.

**Independent Test**: attach `example/`'s Behavior to an entity, edit fields, remove and re-add
it, then delete the class from the project (regenerate the Manifest) and watch it go Missing
with values kept; restore the class and watch it return.

**Acceptance Scenarios**:

1. **Given** a selected entity that accepts Behaviors, **When** *Add Behavior* opens, **Then**
   the list shows the catalog's behaviors grouped by category, offering only those whose
   required parent type the entity's type satisfies, through the Manifest's supertypes
   (*Q57*); an entity that does not accept Behaviors offers none (*Q50*).
2. **Given** a Behavior added, **When** it appears, **Then** its fields start at the code
   defaults (no Overrides), and the author edits them into Overrides as in story 5.
3. **Given** a Behavior on an entity, **When** the user removes it, **Then** it and its
   Overrides are removed in one named transaction, undoable in one step.
4. **Given** a Behavior whose Type ID is no longer in the catalog, **When** the entity is
   shown, **Then** it appears as a Missing behavior with its field values kept: shown, editable
   nowhere except preserved, saved verbatim, and never dropped (*Q32*, constitution IV).
5. **Given** a Behavior whose required parent type no longer matches its entity (the class
   changed), **When** the entity is shown, **Then** the Behavior is marked incompatible with
   the reason, and remains with its values kept.
6. **Given** a custom component Node whose type is Missing, **When** it is shown, **Then** it is
   a Missing component state in hierarchy, viewport (placeholder) and inspector, with its
   values kept (*Q32*).
7. **Given** a Missing behavior or component, **When** its type returns to the Manifest, **Then**
   it renders and edits normally again, with every kept value still there.

---

### User Story 7 - The whole loop, in Pyro, in `example/` (Priority: P1)

The capstone the phase is Done when: starting from a new empty scene in `example/`, the author
builds a scene entirely in Pyro — an entity with a sprite and a hitbox, and the project's
custom Behavior attached with edited fields — saves it, closes it, reopens it, and finds it
unchanged; then deletes the Behavior's class from the project and watches the Behavior show as
Missing with its values kept. The scene loads and hot-swaps in the running game exactly as the
hand-written scenes of Phase 3 did, because it is the same canonical format.

**Why this priority**: this is the phase's acceptance test (phases.md, Phase 4 "Done when") —
the first scenes whose every byte Pyro authored. It is listed last because it is the sum of
stories 1–6, but it is the reason for them.

**Independent Test**: run the scenario start to finish on the reference Mac, then verify the
saved scene loads in CI's contract check (or locally as it does), byte-compares after the
close/reopen cycle, and hot-swaps in the running game.

**Acceptance Scenarios**:

1. **Given** `example/` open and a new empty scene, **When** the author builds the scene
   (entity, sprite, hitbox, custom Behavior with edited fields) using only Pyro's panels,
   **Then** every step is undoable and the viewport shows the scene as it is built.
2. **Given** the built scene, **When** it is saved and the file inspected, **Then** it is the
   canonical form (sorted keys, Overrides only) — saving it again changes nothing, and the
   contract job's Scene-loading check passes on it.
3. **Given** the saved scene, **When** the tab is closed and the scene reopened, **Then** the
   document is identical — names, order, Overrides, values — and the tab is clean.
4. **Given** the Behavior's class deleted and the Manifest regenerated, **When** the scene is
   opened (or already open), **Then** the Behavior shows as Missing with its values kept, and
   saving preserves those values verbatim.
5. **Given** the saved scene, **When** the game runs (as in Phase 3), **Then** the scene loads
   and hot-swaps exactly as a hand-written one — Pyro's output needs nothing the hand-written
   format didn't.

---

### Edge Cases

- **The Manifest changes under an open scene** (types added, renamed, removed): the catalog
  updates live (story 2); Nodes of removed types become Missing with values kept; renamed
  fields keep their Override values under the new names; nothing is dropped on save.
- **The Manifest is temporarily unreadable** (a failed build wrote errors, or a checkout left
  broken JSON): the last good catalog stays, errors are shown, and saving still round-trips
  every kept value.
- **The scene file changes on disk while open in Pyro**: the next save is refused with the
  digest mismatch (*Q95*, spec 002) and the editor offers to force the save or re-open the
  file; Pyro never silently overwrites.
- **A recovery copy is newer than the file being opened**: the *Restore* prompt (story 1) offers
  restore or discard; restoring leaves the scene dirty until saved (*Q55*, §8.2).
- **The same scene opened twice**: the second open focuses the existing tab; there is one
  `documentProvider(sceneId)` per scene, never two documents for one file.
- **Undo pressed mid-gesture** (during a drag or scrub): the coalesced run ends and the undo
  applies cleanly (§8.2's rules, already built in spec 002; the panels must honor them).
- **The last scene tab closed**: the window shows an empty state, not a blank shell; the
  project stays open.
- **A very large scene** (1,000 Nodes): the tree, the reconciler and the inspector stay within
  the frame budget (story 3, scenario 8); panels watch the narrowest provider (`nodeProvider`,
  `select`), never the whole document.
- **A Node deep in the tree, collapsed**: renaming or reparenting it works without expanding
  its ancestors; the tree scrolls to a Node selected in the viewport.
- **Values kept for fields the catalog no longer lists** (a field removed from the class):
  they round-trip untouched — the editor never writes a scene from the catalog alone, only
  from the document (constitution IV; the Runtime's unused-Override warning covers the game
  side).
- **Non-constant defaults** (`Vector2(1, 0)`): shown as source text, not evaluated; *Reset to
  default* restores them the same way (§7.3 `defaultSource`).
- **A project whose `pyro_runtime` is out of range**: scenes open and edit, but save is gated
  with the version named (story 1, scenario 2); Pyro never writes a `schemaVersion` the
  Runtime can't read (*Q49*).
- **A project whose `pubspec.lock` has no `pyro_runtime` at all**: compatibility is
  `unknown` — scenes open and edit, and save is gated until a Runtime is resolved (*Q98*).
- **A project with no detectable SDK**: it opens and scenes edit and save — the SDK is needed
  for Play (Phase 5), not for editing; the project list and status say no SDK was found.
- **Deleting a Behavior that is the only writer of an Override**: removing the Behavior removes
  its Overrides with it (one transaction, undoable); kept values of *missing* Behaviors are a
  different state and are preserved (story 6).

## Requirements *(mandatory)*

### Functional Requirements

**App shell and editor window (#1)**

- **FR-001**: The app MUST provide the provider layout of §8.5 for this phase's scope:
  `projectProvider` (open project, SDK info, Runtime compatibility), `documentProvider(sceneId)`
  (`SceneDocument` + history; exposes `transact`), `selectionProvider`, `typeCatalogProvider`
  and the derived `nodeProvider(id)`; `processProvider` arrives with Phase 5. Panels MUST watch
  the narrowest provider for what they show (`nodeProvider(id)`, `select`), never the whole
  document (constitution III).
- **FR-002**: `documentProvider(sceneId)` MUST wrap the `DocumentSession` built in spec 002
  (one per open scene), and every document change from any panel MUST go through its named
  transactions (§8.2; constitution I: no other mutation path exists).
- **FR-003**: The app MUST keep a project list of recently opened projects, each shown with its
  detected Flutter SDK version following §9.1's order (per-project fvm config →
  `FLUTTER_ROOT` → `flutter` on `PATH`); a project with none found MUST say so. The list is
  Pyro's own data, stored outside any user project. The manual override (Settings) is out of
  scope.
- **FR-004**: On opening a project, the app MUST read the resolved `pyro_runtime` version from
  the project's `pubspec.lock` and check it against a compatibility range built into Pyro
  (*Q49*): in range, editing and saving are normal; out of range, a message names the found and
  required versions and saving is gated (FR-010) until the project's Runtime is in range. Pyro
  never edits the pubspec in this phase.
- **FR-005**: The editor window MUST be the `PrEditorShell` from `pyro_ui` with its panel slots
  (§8.6): Hierarchy left, Viewport centre, Inspector right; the bottom slot stays empty until
  Phase 5's Console. Every panel MUST be built from `Pr` components — a missing one is proposed
  and the author decides whether it is built (*Q87*, constitution II); panels never style raw
  Material widgets around the design system.
- **FR-006**: The window MUST offer scene tabs, one per open scene, each showing the scene's
  name and the dirty marker from the Document model (spec 002); the dirty state MUST reflect
  "current snapshot ≠ last saved snapshot", by identity, exactly as the Document model defines
  it (§8.2).
- **FR-007**: Closing a dirty scene tab MUST ask save, discard or cancel; closing a clean tab
  asks nothing. Quitting the app with dirty tabs asks the same for each. Undo history is not
  persisted across sessions (§8.2).
- **FR-008**: *New scene* MUST create an untitled scene holding exactly one root Node, whose
  first save asks for a file path defaulting to the project's scene folder (`assets/scenes/`,
  *Q53*). If the chosen folder is not declared in `pubspec.yaml`, the app MUST warn that the
  game cannot load from it and MUST NOT edit the pubspec (item 10, Phase 7).
- **FR-009**: *Open scene* MUST offer the `*.scene.json` files under the project's declared
  asset folders (§10), MUST call `RecoveryStore.find` before opening and offer *Restore* when a
  recovery copy exists (restored scenes are dirty with no saved snapshot, §8.2, *Q55*), and
  MUST surface the Document model's gates: a newer `schemaVersion` is refused with the required
  version, and load-time repairs are reported (spec 002; *Q49*).
- **FR-010**: *Save* MUST go through the Document model's atomic save, passing the
  compatibility check's version so the written `schemaVersion` is always one the project's
  Runtime reads (*Q49*, spec 002). A save refused because the file changed on disk (digest,
  *Q95*) MUST be surfaced with the choice to force the save or reopen the file — never a
  silent overwrite.
- **FR-011**: Selection (and camera and panel state) MUST live outside the document (*Q25*):
  `selectionProvider` holds the selected `NodeId`s; this phase is single-selection (multi-select
  is v0.1.1, *Q65*). Selecting anywhere (viewport, hierarchy) MUST update every selection-aware
  surface.

**Type catalog and preview components (#6)**

- **FR-012**: The app MUST build its Type catalog from the project's committed
  `lib/pyro.manifest.json` (spec 003's format): every type with role, label, category, parent
  type, supertypes, accepts-behaviors flag and Editable fields (name, type, evaluated default
  or `defaultSource`, `min`/`max`, enum `values`, tooltip), plus hand-written descriptors for
  the built-in Node kinds (entity, sprite, rectangle hitbox, circle hitbox) declaring the same
  shape, so built-in and custom types are indistinguishable to the panels.
- **FR-013**: The app MUST watch the Manifest file and re-parse it on change (§9.2): the
  catalog, Add lists, inspector rows, compatibility filtering and Missing states MUST
  re-evaluate without a restart. Pyro MUST NOT run the generator itself in this phase (the
  watcher is #11, rest).
- **FR-014**: Manifest `errors` and `warnings` MUST be shown with their stable code, file,
  line, class and field where the type would have appeared (§7.3) — in a problems list
  opened from the catalog status (a `PrDialog`; the Console takes over as the standing
  surface in Phase 5); while a Manifest is unreadable or carries errors, the last good
  catalog MUST stay active with a clear error, and no crash or blank catalog.
- **FR-015**: Preview components MUST render built-in Node kinds for real with Pyro's own Flame
  (sprites from disk images via `AssetSource`, hitboxes as their outlines), and custom
  components as placeholders — a labelled box with the Type ID, or the `preview:` image when
  the Manifest carries one (*Q6*). A custom component whose supertypes include `TextComponent`
  shows its text instead: its first `String` Field's value and its first `Color` Field's colour
  (the Override, else the Manifest default), at Flame's default `TextPaint` size, since the
  editor can't run the component's code to know more.
- **FR-016**: The viewport MUST be a `FlameGame` embedded in the app that never ticks user
  logic, and the app MUST NOT import or execute the project's code (*Q7*, §8.3, constitution
  II); everything it draws comes from the document, the catalog and files on disk.

**Viewport (#4)**

- **FR-017**: The reconciler MUST turn each document change into component operations by
  walking old and new document by `NodeId`: skip Nodes that are the same object (`identical`),
  patch changed Nodes' components, create and remove components for added and removed Nodes
  (§8.3). Its diff-to-operations mapping MUST be unit-tested as a pure function (§13,
  constitution V: Heavy).
- **FR-018**: The viewport MUST support pan (drag) and zoom (wheel), with the camera held as
  editor state outside the document (*Q25*); a change to the camera MUST NOT dirty the scene.
- **FR-019**: Clicking the viewport MUST select the topmost Node under the cursor (outline via
  the overlay layer); clicking empty space deselects. Selected state MUST sync to the hierarchy
  and inspector (FR-011).
- **FR-020**: A move gizmo MUST drag the selected Node's position live; the whole gesture MUST
  be one coalesced transaction with a gesture label, so one undo reverts it (§8.2). Grid,
  snapping, and rotate/scale gizmos are out of scope (§14: numeric editing in the inspector
  covers them).
- **FR-021**: The viewport MUST load images from disk through the `AssetSource` interface
  (*Q31*, *Q79*, spike #3): a file change rebuilds only the Nodes that read that file
  (per-Node file records), a changed image reaches the screen within ~200 ms, and an image is
  freed only after it is no longer drawn. A missing image file MUST show an error state for
  that Node, not a crash.
- **FR-022**: Gizmos, selection outlines and hover feedback MUST draw in an overlay layer above
  the preview world (§8.3), never as Nodes in the document.
- **FR-023**: Interactive editing (gizmo drag, number scrub, hierarchy selection, inspector
  typing) MUST hold 60 fps (≤ 16 ms frames in profile mode) on the reference Mac with a
  1,000-Node scene (constitution III); file and image work large enough to block a frame MUST
  run off the UI isolate or in chunks. A regression past the budget blocks the change unless
  justified in Complexity Tracking.

**Hierarchy (#3)**

- **FR-024**: The hierarchy MUST render the Node tree from `childIds` order on `PrTreeRow`
  (kind and name per row, expand/collapse), sharing the selection with the viewport and
  inspector, and MUST scroll to a Node selected elsewhere.
- **FR-025**: *Add* MUST offer Node kinds from the catalog filtered by the selected parent's
  parenting rules (hand-written for built-ins; the Manifest's parent type and supertypes for
  custom types, *Q57*), give the new Node a stable unique `NodeId` and a default name, and add
  it through a named transaction.
- **FR-026**: *Delete* MUST remove a Node with its subtree in one named transaction (one undo
  restores it); the root Node MUST NOT be deletable.
- **FR-027**: *Rename* MUST change only the Node's name; the `NodeId` never changes. Duplicate
  names are allowed and unremarked (the warning is v0.1, *Q51*).
- **FR-028**: Drag on `PrTreeRow` MUST reorder within a parent and reparent across parents
  through a named transaction; a drop into the Node's own subtree or onto a parent whose rules
  refuse it MUST be refused with the reason, leaving the tree unchanged.

**Inspector (#5)**

- **FR-029**: With a Node selected, the inspector MUST show a transform section (position,
  angle, scale, size and anchor — plain number/Vector2 rows; the anchor's 3×3 picker is a later
  design decision) and one row per Editable field of the Node's type from the catalog, in the
  Manifest's order, on the design system's property-row components; with nothing selected it
  shows an empty state.
- **FR-030**: The inspector MUST provide working editors for `int`, `double` (honouring the
  Manifest's `min`/`max` and tooltip), `bool`, `String`, enum (the Manifest's `values`),
  `Vector2` and asset paths (a dropdown of matching files under the project's declared asset
  folders, read from disk so new files appear without a restart, *Q31*; the value stored is
  the project-relative path).
- **FR-031**: The field's `min`/`max` from the Manifest MUST be enforced so that no
  out-of-range Override is ever written: a typed, dragged or scrubbed number outside the
  range is clamped on commit and the field shows the clamped result (Clarification
  2026-10-22 — scrubbing already stops at the limits, and rejecting the entry would fight
  typing and scrubbing alike); text that is not a number at all is held invalid (error
  border, Esc reverts) — the `PrNumberProperty` behavior (*Q84*). An enum value not among
  the Manifest's `values` (a kept value) MUST still display.
- **FR-032**: Fields with an Override MUST carry a visible Override marker and *Reset to
  default*, which removes the Override (ADR 0003); un-overridden fields MUST show the code
  default — the evaluated constant, or the source text for a non-constant default (§7.3).
- **FR-033**: Fields of the types this phase does not edit (`Color`, entity reference,
  `Sprite`, `SpriteAnimation`) MUST render read-only and MUST round-trip byte-identically on
  save, untouched by any other edit (§14 item 5).
- **FR-034**: Every inspector edit MUST go through named transactions with coalescing (typing
  in one field, scrubbing, a drag): consecutive same-key transactions merge, and any other
  action, undo, redo or save ends the run (§8.2). Undo and redo MUST work across panels (a
  viewport drag, a hierarchy rename, an inspector edit each revert in one step).

**Behaviors in the inspector (#9)**

- **FR-035**: The inspector MUST list an entity's Behaviors and offer *Add Behavior* from the
  catalog grouped by category, filtered to the Behaviors whose required parent type the
  entity's type satisfies through the Manifest's supertypes (*Q57*); entities that do not
  accept Behaviors offer none (*Q50*). Adding creates the Behavior at its code defaults; its
  fields then edit as FR-030–FR-032.
- **FR-036**: *Remove Behavior* MUST remove the Behavior and its Overrides in one named
  transaction, undoable in one step.
- **FR-037**: A Behavior whose Type ID is not in the catalog MUST show as a **Missing
  behavior** state — visibly marked, its field values kept and preserved verbatim on save,
  never dropped (*Q32*, constitution IV); a Behavior whose required parent type no longer
  matches its entity MUST show as incompatible with the reason, likewise kept. A custom
  component Node in the same situation MUST show as a **Missing component** state in hierarchy,
  viewport and inspector.
- **FR-038**: When a Missing type returns to the catalog, the Node or Behavior MUST render and
  edit normally again with every kept value intact — the round trip loses nothing.

**Cross-cutting and verification**

- **FR-039**: The reconciler MUST be tested as a pure function (document diff → expected
  component operations), including identity skips, patches, adds, removes and subtree moves
  (§13, constitution V); panel behaviour MUST be covered by widget tests for at least
  reparenting by drag, *Reset to default* (Override removal) and the Missing behavior state
  (phases.md, Phase 4 Tests). Tests MUST be deterministic: no real network, no wall-clock
  sleeps, no real SDK or device (constitution V).
- **FR-040**: The phase MUST end with the manual run of story 7 on the reference Mac (macOS,
  Apple M4, Flutter 3.44.2), recorded in `dev-docs/ARCHITECTURE.md`: the built-from-scratch scene
  saved, closed, reopened unchanged; the Behavior's class deleted → Missing with values kept;
  the scene loads and hot-swaps in the running game as a hand-written one does; the frame
  budget check of FR-023 with its numbers; any workaround needed.
- **FR-041**: `dev-docs/phases.md` MUST be updated in the same change that closes the phase:
  Phase 4's items ticked, the status line and counts updated (constitution, "Development
  Workflow"; §14 changes only if scope or estimates changed).

### Key Entities

- **Project**: an opened Flame project folder; holds the detected SDK version, the Runtime
  compatibility result, its declared asset folders and its Manifest. One is open at a time.
- **Type catalog**: the parsed Manifest plus the hand-written built-in descriptors; the single
  source every panel reads for types, fields and parenting rules. Reloads when the Manifest
  file changes.
- **Type descriptor**: one entry of the catalog (built-in or from the Manifest): role, label,
  category, fields with defaults and ranges, parenting rules, supertypes.
- **Scene tab / `DocumentSession`**: one open scene: its document, history and dirty state
  (spec 002), wrapped in `documentProvider(sceneId)`.
- **Selection**: the selected `NodeId` (single this phase), shared by viewport, hierarchy and
  inspector; editor state, not document state (*Q25*).
- **Reconciler**: the pure old-document → new-document → component-operations step behind the
  viewport (§8.3).
- **Preview component**: the viewport's rendering of one Node — real for built-in kinds,
  placeholder for custom (*Q6*).
- **Overlay**: the layer above the preview world drawing gizmos, selection outlines and hover
  (§8.3).
- **Missing state**: the shown-but-kept rendering of a Behavior or component whose type the
  catalog no longer holds (*Q32*).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the reference Mac, the author builds story 7's scene in `example/` from an
  empty scene using only Pyro's panels, saves it, closes the tab, reopens it, and the document
  is identical (names, order, Overrides, values); the file is in canonical form and a second
  save is a no-op (byte-identical).
- **SC-002**: After the Behavior's class is deleted and the Manifest regenerated, the scene
  shows the Behavior as Missing with its values kept; saving preserves those values verbatim;
  restoring the class brings the Behavior and its values back intact (one round trip, nothing
  lost).
- **SC-003**: The scene built in SC-001 loads in the contract job's Scene-loading check (or
  the local equivalent) and hot-swaps in the running game on macOS exactly as a hand-written
  scene of Phase 3 did — no editor-only bytes, no special handling.
- **SC-004**: In profile mode on the reference Mac with a 1,000-Node scene, gizmo dragging,
  number scrubbing, hierarchy selection and inspector typing each hold ≤ 16 ms frames
  (constitution III's editor budget); the numbers are recorded with the phase's results.
- **SC-005**: An image file edited on disk appears in the viewport within 200 ms (spike #3's
  budget, *Q79*), and only the Nodes that read the file rebuild — verified by the reconciler
  tests' operation counts, not by timing alone.
- **SC-006**: The reconciler tests pass as a pure function: identity skip, patch, add, remove
  and subtree-move each produce exactly the expected operations; a one-Node change to a
  1,000-Node document produces exactly one patch.
- **SC-007**: The three required widget tests — reparenting by drag, *Reset to default*
  (Override removal) and the Missing behavior state — pass, and every recovery-flow prompt
  (Restore on open, close confirmation, save refusal with force) is exercised by a test or the
  recorded manual run.
- **SC-008**: Every field type of §6.1 round-trips through the editor: the seven editable
  types edit and save; `Color`, entity reference, `Sprite` and `SpriteAnimation` round-trip
  byte-identically while their neighbours are edited.
- **SC-009**: One undo reverts each gesture as one step — a viewport drag, a hierarchy rename
  and a field-typing run each undo in a single action, across panels.

## Assumptions

- The reference environment is the reference Mac (macOS, Apple M4, Flutter 3.44.2); `example/`
  from Phase 3 is the project every scenario runs in (it already declares `assets/scenes/`, has
  a committed Manifest, and hot-swaps on macOS).
- All 29 `Pr` components and the `PrEditorShell` exist ahead of this phase (Phase 1, *Q84*);
  the panels only compose them. A component the panels need that doesn't fit is proposed and
  the author decides (*Q87*) — none is currently expected to be missing
  (`PrTreeRow`, `PrPropertyRow`, `PrNumberProperty`, `PrVector2Property` all exist).
- The Claude Design **view designs are deferred, not a dependency**: the panels compose
  components whose APIs are fixed, so the spec, plan and tasks proceed without them. Each
  panel's implementation task waits for its view design (Prompts 2, 1, 4, 3, 5 and 11C of
  `claude-design-prompts.md`, in Phase 4's build order), so missing "New patterns" surface
  before code, not during it.
- **Transform** means all five `PositionComponent` fields — position, angle, scale, size and
  anchor — as plain number/Vector2 rows (confirmed in clarify). Rotate and scale have no gizmo
  this phase (§14: numeric editing covers them), and the anchor's 3×3 picker waits for the
  design review.
- **Number clamping**: on commit, an entered value outside the Manifest's `min`/`max` is
  clamped (the generator guarantees `min ≤ max`, §6.1). The alternative — refusing the entry —
  was not chosen because the Manifest's range is authoritative either way and clamping matches
  the scrubbing interaction.
- A **new scene** starts as one root Node (the Scene format requires a root; the author adds
  entities beneath it). Its name is the file name on first save.
- A project **without a detectable SDK** still opens and edits — the SDK gates Play (Phase 5),
  not editing; §9.1's block applies when Play exists.
- **Opening an already-open scene** focuses its existing tab (one document per scene file);
  two tabs on one file would need merge handling this phase doesn't have.
- The **Runtime compatibility result gates saving**, not editing (the write is what must never
  be unreadable, *Q49*); the upgrade flow itself is the README recipe's job until "Add Pyro"
  arrives (Phase 7).
- The bottom panel slot stays **empty** in this phase: the Console is Phase 5 and the asset
  browser Phase 7; the shell hides the slot rather than showing a placeholder panel.
- The asset-path dropdown reads the **declared** asset folders from disk (§10) — undeclared
  folders' files are not offered (the "Not in pubspec.yaml" marking is #10, Phase 7; the
  new-scene warning in FR-008 covers the save side).
- Estimate: phases.md gives Phase 4 **18 evenings** (3 + 2 + 6.5 + 2 + 2.5 + 2) before the
  1.3–1.5× solo overrun §14 warns about; §14 and phases.md change when the phase closes, only
  if scope or estimates moved.
- Behaviors are shown **in the inspector** on their entity (as §14 item 9 names it), not as
  rows in the hierarchy tree; the hierarchy lists Nodes only.
- The scene's undo history, camera and selection are per-session and never persisted (§8.1,
  §8.2); the recovery file is the only cross-session safety net (*Q55*).
