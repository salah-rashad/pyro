# Quickstart: validating Phase 4 end to end

This is the manual validation guide for the editor phase — the spec's story 7 capstone plus
the checks CI cannot run. Preconditions: the workspace resolved (`dart pub get` at the root),
Flutter 3.44.2 on macOS, `example/`'s generated files committed (they are).

## 1. Automated checks (every change)

```sh
cd apps/editor && flutter analyze && flutter test    # document, process, app, project, viewport, panels
cd ../../packages/pyro_ui && flutter test          # untouched, but the panels lean on it
cd ../../../example && flutter test                # contract side, incl. scene_canonical_test
```

The reconciler suite (`test/viewport/reconciler_test.dart`) must show the named invariants:
identity skip, one-op-for-one-edit on a 1,000-Node document, subtree atomicity, order. The
three panel widget tests (reparent by drag, Reset to default, Missing behavior) run with the
font-loading config so `Pr` glyphs render.

## 2. The capstone run (spec story 7, FR-040)

1. `cd apps/editor && flutter run -d macos` — the project list appears with `example/` (add it
   by folder if not listed) and its detected Flutter version.
2. Open the project; the status area shows the Runtime compatibility result (in range).
3. New scene (⌘N): an untitled tab with one root Node. Save it as
   `example/assets/scenes/built.scene.json` (default folder offered; no pubspec warning since
   `assets/scenes/` is declared).
4. Build with the panels only: an entity under the root (position it by dragging the gizmo),
   a sprite under it (pick `assets/images/ship.png` from the dropdown), a rectangle hitbox,
   and the `Spin` Behavior with `turnsPerSecond` edited (Override marker appears; reset it
   once and re-set it). Check: every step undoable; ⌘Z reverts a whole gizmo drag in one step.
5. Save. `git diff example/assets/scenes/built.scene.json` shows a canonical file (sorted
   keys, Overrides only, whole numbers without `.0`).
6. Close the tab (clean — no prompt), reopen it: identical document, tab clean, `git diff`
   empty after a second save (SC-001).
7. Contract side: `cd example && flutter test test/contract` — the new scene loads against
   the real Registry with no warnings; `dart run build_runner build && git diff --exit-code`
   stays clean.
8. Hot-swap (the Phase 3 loop): run the game (`dart run bin/play.dart ../..` from `apps/editor`
   or the example's own runner) and save the scene from Pyro — the running game swaps it.

## 3. The Missing drill (SC-002)

1. With the scene from §2 open, delete `Spin` from `example/lib/` and regenerate:
   `cd example && dart run build_runner build`.
2. In Pyro: the Behavior card turns Missing ("no longer exists in your code. Its values are
   kept"), the hierarchy shows the warning badge, the viewport still shows the entity.
3. Save → the JSON still carries the Behavior with its field values verbatim.
4. `git checkout` the class, regenerate: the card returns editable with every value intact.

## 4. Save gates and recovery

- Edit the scene file on disk behind Pyro (append a space, save) → save from Pyro is refused
  with the changed-on-disk dialog; *Overwrite* (destructive) and *Reload from disk* both work.
- With unsaved edits, wait 30 s, `kill -9` the app, relaunch, open the scene → the *Restore*
  prompt offers the recovery copy; restoring leaves the tab dirty.
- Open `example/assets/scenes/level1.scene.json`, break its tree by hand (move a Node's id
  out of its parent's `childIds`), reopen → repair banner with the per-Node report, tab dirty.

## 5. Frame budget (SC-004, profile mode)

```sh
cd apps/editor && flutter run --profile -d macos
```

Open a generated 1,000-Node scene (the test helpers' `generatedScene(1000)` writer, or paste
one produced by a tiny `dart run` helper from `test/document/helpers`). In DevTools' timeline,
record while: dragging the move gizmo, scrubbing a number, arrowing through the hierarchy,
typing in a field. Frames must stay ≤ 16 ms; record the numbers (FR-040 puts them in
`ARCHITECTURE.md`). Also: edit `example/assets/images/ship.png` on disk and time the
viewport refresh (≤ 200 ms, only the reading Nodes rebuild — visible with a one-sprite scene).

## 6. Done when

phases.md Phase 4 is ticked, the numbers and findings from §2–§5 are recorded in
`dev-docs/ARCHITECTURE.md`, and §14/phases.md counts are updated in the same commit (FR-041).
