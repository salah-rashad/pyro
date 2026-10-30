# Tasks: Editor (Phase 4)

**Input**: Design documents from `specs/006-editor/` (spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md)

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Included — the spec requests them (FR-039: reconciler suite + three panel widget tests; constitution V makes the reconciler Heavy). Reconciler tests are written first and must fail.

**Organization**: Tasks are grouped by user story (the spec's seven, in §14's build order #1 → #6 → #4 → #3 → #5 → #9 → capstone) so each story lands as an independently testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US7)
- File paths are under `apps/editor/` unless stated otherwise

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Add `yaml: ^1.14.0` to `apps/editor/pubspec.yaml` dependencies (BSD-3, MIT-distribution compatible — the one new dependency flagged in plan.md's Constitution Check) and resolve the workspace from the repo root (`dart pub get`); commit the lock change alone.
- [x] T002 [P] Create `apps/editor/test/flutter_test_config.dart` loading the app's font manifest the gallery's way (copy the pattern from `packages/pyro_ui/example/test/flutter_test_config.dart`) so `Pr` widgets and `PrIcons` glyphs render in tests instead of squares.
- [x] T003 [P] Create the four feature folders with empty public barrels per plan.md's structure: `lib/app/app.dart`, `lib/project/project.dart`, `lib/viewport/viewport.dart`, `lib/panels/panels.dart` (export lists grow with the stories; nothing else lives at `lib/` top level beside `main.dart` and the existing `document/`, `process/`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️** No user story starts before this phase is green.

- [x] T004 [P] Add the app widget-test harness `pumpPyro` to `apps/editor/test/helpers/pump.dart`: `MaterialApp` + `PrTheme.dark()` + `ProviderScope` over a `surfacePanel` background, plus real-mouse gesture helpers (`hover`, `mouseDrag`), modeled on `packages/pyro_ui/test/helpers.dart`.
- [x] T005 [P] Add catalog and project fixtures to `apps/editor/test/helpers/`: loaders for `example/lib/pyro.manifest.json` (read in place, like the document tests read runtime scene fixtures), fixture `pubspec.lock`/`pubspec.yaml` texts (ok / tooOld / tooNew / no pyro_runtime / undeclared folders), and a manifest-error sample; reuse the existing scene builders in `test/document/helpers/scenes.dart` (incl. `generatedScene(1000)`).

**Checkpoint**: `flutter analyze` and `flutter test` still green; stories can start.

---

## Phase 3: User Story 1 — Open a project and edit scenes in the editor window (Priority: P1) 🎯 MVP

**Goal**: The editor window exists: project list with SDK detection and Runtime compatibility, scene tabs with new/open/save, dirty marker, close confirmation, recovery *Restore* prompt, repair report (spec FR-001–FR-011).

**Independent Test** (spec story 1): open `example/`, open `level1.scene.json` with a planted recovery copy, trigger each prompt and gate, save, reopen — per quickstart.md §2/§4.

- [x] T006 [US1] Implement SDK detection in `lib/project/sdk.dart`: per-project fvm (`.fvmrc`/`.fvm/`) → `FLUTTER_ROOT` → `flutter` on `PATH` (§9.1), returning `SdkInfo { version, source }` with `none` never blocking editing; inject environment/paths for tests; unit tests in `test/project/sdk_test.dart`.
- [x] T007 [P] [US1] Implement the Runtime compatibility check in `lib/project/runtime_compat.dart`: parse the project's `pubspec.lock` with `yaml`, resolve the `pyro_runtime` version, map it through a built-in compatibility table (version → max readable `schemaVersion`; `Scene.currentSchemaVersion` is this workspace's value) into `RuntimeCompatibility { status, foundVersion, readsUpTo }` — `ok | tooOld | tooNew | unknown`; `unknown` yields `readsUpTo: null` (save blocked, *Q98*); unit tests over the T005 fixtures in `test/project/runtime_compat_test.dart`.
- [x] T008 [P] [US1] Implement the editor-settings store in `lib/project/recent_projects.dart`: recent project paths + per-project `PrShellSizes` as one JSON in Pyro's application-support folder, atomic write (`writeAtomically` pattern), never inside a project; unit tests on a memory file system.
- [x] T009 [P] [US1] Implement asset-folder and scene discovery in `lib/project/asset_folders.dart`: parse `flutter: assets:` folder entries from the project's `pubspec.yaml` (yaml), list `*.scene.json` under them (§10, *Q53*), report undeclared target folders; unit tests in `test/project/asset_folders_test.dart`.
- [x] T010 [US1] Implement the provider layer in `lib/app/providers.dart` per research.md §2: `projectProvider` (keepAlive; open project, `SdkInfo`, `RuntimeCompatibility`), `openScenesProvider`/`activeSceneProvider` (tab model; re-opening a scene focuses its tab), `selectionProvider` (single `NodeId?`), `nodeProvider(id)` (watches `documentProvider(sceneId).select((s) => s.document)`, returns the Node object itself — `==` filtering does the narrow rebuild), and `documentProvider(sceneId)`: autoDispose family `Notifier` owning its `DocumentSession` privately (state = immutable snapshot view of `OpenDocument`; `transact`/`undo`/`redo`/`save`/`pin`/`unpin` methods; session's `changes` stream pushes; `ref.onDispose` closes the session; `KeepAliveLink` pin survives the close dialog); provider tests in `test/app/providers_test.dart` (open → transact → dirty → undo; pin/unpin across an awaited dialog).
- [x] T011 [US1] Implement the open-scene command in `lib/app/open_scene.dart`: locate scenes (T009), call `RecoveryStore.find` before opening (offer *Restore* → `DocumentSession.restore`, else `open`), surface `SceneOpenFailed` (incl. `UnsupportedSchemaVersion` naming the required version, *Q49*) and the repair report (scene opens dirty with `origin: repaired`, *Q96*; report lines from `RepairReport.describe()`); `SessionServices` built from the open project's root and the T008 recovery folder; tests in `test/app/open_scene_test.dart` with a planted recovery copy and the runtime repair fixtures.
- [x] T012 [US1] Build the editor window shell in `lib/app/shell.dart`: `PrEditorShell` with Hierarchy/Viewport/Inspector slots from the (still placeholder) panel widgets, `bottom: null`, sizes persisted through `onSizesChangeEnd` (T008), status bar showing SDK + compatibility + catalog status (placeholder until US2), title bar "<project> — <scene>"; wire the macOS runner for the hidden title bar / full-size content view in `macos/Runner` (traffic-light zone; app runner config, not package code); app-quit / window-close interception (`AppLifecycleListener.onExitRequested`, or the runner's close request) walks dirty tabs through the T014 unsaved-changes dialog before quitting (FR-007).
- [x] T013 [US1] Implement scene tabs in `lib/app/scene_tabs.dart`: `PrTabs` document style, dirty dot from the provider, `onClose` → unsaved-changes dialog (pin the provider for the dialog, then Save/`discardAndClose`/Cancel), ⌘N new scene → `createDocument()` root-only untitled tab (clarified: one root Node) + first-save path dialog defaulting to `assets/scenes/` with the undeclared-folder **warning** line (never a pubspec edit — FR-008); closing the last tab shows the window's empty state (`PrEmptyState`; the project stays open — spec Edge Cases); widget test for the close-confirmation flow in `test/app/scene_tabs_test.dart`.
- [x] T014 [P] [US1] Implement the dialogs in `lib/app/dialogs.dart` on `showFsDialog`: unsaved changes (primary Save / destructive Discard / secondary Cancel), new-scene (name, folder, warning variant), save-refused (`SceneChangedOnDisk` → "changed on disk" + Reload from disk / Overwrite (destructive) / Cancel; `RuntimeVersionUnknown`/`RuntimeTooOld`/`SaveTargetExists` → their messages, *Q95*/*Q98*), recovery *Restore* prompt (scene list + written-at, primary Restore / destructive Discard).
- [x] T015 [US1] Implement save in `lib/app/save_scene.dart`: ⌘S (and the dialogs) → `session.save(runtimeReadsUpTo: compatibility.readsUpTo)`; untitled scenes go through the path dialog (`saveAs`); every refusal from `SceneFiles`' ladder routes to its T014 dialog; `SavePathRequired` only for untitled scenes. Covered by `test/app/save_scene_test.dart`.
- [x] T016 [P] [US1] Implement shortcuts and panel focus in `lib/app/shortcuts.dart`: ⌘N/⌘O/⌘S/⌘W, ⌘Z/⇧⌘Z routed to the active scene's provider methods, panel cycling on per-panel `FocusScopeNode`s from `PrPanelFocus.createNode`.
- [x] T017 [US1] Replace `lib/main.dart`'s placeholder with the real `PyroApp`: project list / welcome window on `Pr` components (recent projects with detected SDK version, "no SDK found" state, open-by-folder), bootstrapping `projectProvider` and the T012 shell; the `widget_test.dart` smoke test is updated accordingly.

**Checkpoint**: The window opens a project, opens/saves/closes scenes with every prompt and gate correct; editing is via provider transactions only (no panels yet).

---

## Phase 4: User Story 2 — The editor knows the project's types (Priority: P1)

**Goal**: The Type catalog — Manifest parser + built-in descriptors + parenting rules — live-reloading on Manifest change (spec FR-012–FR-014; `contracts/type-catalog.md`).

**Independent Test** (spec story 2): with `example/` open, hand-edit `lib/pyro.manifest.json` (add/rename/delete a type, break the JSON, add errors) — catalog updates, holds last-good, or reports; no restart, no crash.

- [x] T018 [P] [US2] Implement the catalog models and Manifest parser in `lib/project/catalog/manifest_parse.dart`: `TypeDescriptor`, `FieldDescriptor`, `ManifestProblem` (freezed, shapes exactly per `contracts/type-catalog.md`), parsing `manifest-v1` incl. `errors`/`warnings`, ignoring unknown keys, refusing a newer `manifestVersion`; unit tests in `test/project/catalog/manifest_parse_test.dart` over the T005 fixtures (clean `example/` manifest, error manifest, newer version, broken JSON).
- [x] T019 [P] [US2] Implement the built-in descriptors in `lib/project/catalog/built_in.dart`: `entity`, `sprite`, `rectangleHitbox`, `circleHitbox` with exactly the fields of `contracts/type-catalog.md`'s table (transform excluded — never a FieldDescriptor, always written in full *Q89*); unit tests in `test/project/catalog/built_in_test.dart`.
- [x] T020 [US2] Implement the parenting rules in `lib/project/catalog/parenting.dart` as the pure functions `childOffers(catalog, parent)` and `canReparent(doc, catalog, nodeId, newParentId)` — the contract's table verbatim: root offers entities + custom components; **no hitbox under the root** (*Q115*); no Node into its own subtree; custom types via Manifest `parentType`/`supertypes` (*Q57*); Behaviors are not Nodes; unit tests in `test/project/catalog/parenting_test.dart` covering every table row and both hard rules.
- [x] T021 [US2] Implement `typeCatalogProvider` in `lib/project/catalog/provider.dart`: keepAlive `Notifier` joining parsed Manifest + built-ins into `TypeCatalog { types, problems, origin }` with `origin = manifest | builtinOnly | lastGood(reason)` (*Q105*: newer version, unreadable, or errors present → keep previous types); watch `lib/pyro.manifest.json` (reuse `watchRecursively`, debounced), never run the generator (FR-013); tests in `test/project/catalog/provider_test.dart` (reload on write, lastGood on break, builtinOnly when absent).
- [x] T022 [US2] Wire catalog status into the shell's status bar (`lib/app/shell.dart`): types up to date / needs a newer Pyro (stale, not empty) / errors with count; clicking opens a `PrDialog` listing every `ManifestProblem` with its stable code, message, `file:line` and class.field, plus the `lastGood` reason when the catalog is stale (FR-014; the Console becomes the standing surface in Phase 5). Covered by a widget test rendering the T005 error-manifest fixture's problems.

**Checkpoint**: Panels and Add lists can be built against one tested catalog source.

---

## Phase 5: User Story 3 — Build and place entities in the viewport (Priority: P1)

**Goal**: The preview world — reconciler, pan/zoom, picking, move gizmo, disk assets, overlay — never ticking user code (spec FR-015–FR-023; `contracts/reconciler.md`; research.md §4).

**Independent Test** (spec story 3): open `example/`'s scene, add/drag Nodes (via a temporary transaction or the US4 menu if it exists), edit an image on disk, watch the viewport; profile-mode budget per quickstart §5.

- [x] T023 [US3] **Write first, must fail**: the reconciler suite `test/viewport/reconciler_test.dart` — the five invariants of `contracts/reconciler.md` as named tests (identity skip; same-Node-reparent yields only `ReparentNode`; one op for a one-Node edit in `generatedScene(1000)`; `childIds` order as `Reparent` with index; no ops inside an added/removed subtree; `old == null` seeds adds).
- [x] T024 [US3] Implement the reconciler in `lib/viewport/reconciler.dart` as a pure function `(SceneDocument?, SceneDocument) → IList<PreviewOp>` (no Flame imports, no clock, no I/O) until T023 passes.
- [x] T025 [US3] Implement the disk asset source in `lib/viewport/disk_assets.dart`: pyro_runtime's `AssetSource` over the project root — `loadText` always fresh; `loadImage` decodes bytes off the UI isolate (the document feature's `Offload` seam) into a Pyro-owned refcounted `ui.Image` cache that releases an image only after nothing draws it (*Q79*); a debounced watcher rebuilds only components that recorded the changed path; unit tests in `test/viewport/disk_assets_test.dart` (memory FS, tiny PNG fixture, release-after-swap, rebuild-only-dependents).
- [x] T026 [US3] Implement the preview components in `lib/viewport/preview/`: entity → positioned group; sprite → `SpriteComponent` (`paint.filterQuality = FilterQuality.none`, optional region) from T025; rectangle/circle hitbox → outline components (also the picking shapes); custom → placeholder box + Type ID (or the Manifest `preview:` image, *Q6*); Missing/unknown → error-toned placeholder; each component records the asset paths it read; `flame_test` tests in `test/viewport/preview_test.dart`.
- [x] T027 [US3] Implement `EditorGame` in `lib/viewport/editor_game.dart`: one `FlameGame` per scene in a `GameWidget` with its own `FocusNode`; camera pan (drag) and zoom (wheel, clamped, zoom-to-cursor via before/after `globalToLocal`); picking with `world.componentsAtPoint` (topmost first) writing `selectionProvider`; `pauseEngine()` when the tab hides, `resumeEngine()` + **full reconcile from the current document** when it shows (paused-listener mitigation, research.md §2); `*Callbacks` APIs only (no legacy mixins — research §4).
- [x] T028 [US3] Implement the overlay in `lib/viewport/overlay.dart`: selection outline, hover highlight + name label, and the move gizmo as camera-**viewfinder** children (hit-tested before world children; `scale = 1/zoom` for constant size); gizmo drags use `DragCallbacks`, constrain to the axis (centre square = free), and write every update through `documentProvider.transact` with a gesture `coalesceKey` (one undo per drag); no `priority` changes during drags (frame-budget rule).
- [x] T029 [US3] Wire the viewport providers in `lib/viewport/providers.dart`: the reconciler listener provider (`ref.listen(..., fireImmediately: true)` → apply ops to the world, dispose → clear), per-scene `EditorCamera` state (outside the document, *Q25*), selection → outline sync, and image-watch rebuilds flowing through T025; integration test `test/viewport/wiring_test.dart` (seed, patch, move, remove against a fake world recorder; a run of transacts sharing one `coalesceKey` lands as one history entry — SC-009's drag half).

**Checkpoint**: The viewport renders and edits `example/`'s scene; the reconciler suite is green.

---

## Phase 6: User Story 4 — Structure the scene in the hierarchy (Priority: P1)

**Goal**: Add, delete, rename, reparent by drag on `PrTreeRow` (spec FR-024–FR-028).

**Independent Test** (spec story 4): build a dozen-Node scene with every built-in kind + the custom component; rename, reorder, reparent, delete, undo each; tree, viewport and saved JSON agree.

- [X] T030 [US4] Implement the tree view in `lib/panels/hierarchy/hierarchy_panel.dart`: flatten the visible tree from `childIds`, `ListView.builder` of `PrTreeRow`s (depth, kind icon via the app's node-kind → `PrIcons` map: `layers` root, `box` entity, `image` sprite, `hitbox` hitboxes, `circleDot` custom), selection sync (watch `nodeProvider`), keyboard nav (↑↓ expand/collapse, F2 rename), scroll-to-selected, Missing/warning `PrBadge`es.
- [X] T031 [US4] Implement the Add menu in `lib/panels/hierarchy/add_menu.dart`: entries from `childOffers` (T020) — hitbox entries **disabled** under the root with the reason in a tooltip (FR-025, *Q115*; the `PrMenuItem` disabled-reason delta from plan.md is proposed here per *Q87* if the plain tooltip isn't enough — author decides); new Node = stable `uuidNodeIds` id + default name, one transaction, appears in tree and viewport at once.
- [X] T032 [US4] Implement rename and delete in `lib/panels/hierarchy/`: inline rename via `PrTreeRow`'s `renaming` state (name only — `NodeId` never changes; duplicates allowed, unremarked, *Q51* is v0.1), delete = subtree in one named transaction (one undo restores it), root not deletable (FR-026/027).
- [X] T033 [US4] Implement drag reparenting: `PrTreeRow.canAccept` → `canReparent` (T020: own-subtree and rule refusals paint the reject state), `onAccept` → `moveNode` transaction (reorder within a parent = new index); auto-expand on hover; the hitbox-onto-root reject shows its reason (the one rule a user can't guess).
- [X] T034 [US4] **Required widget tests** in `test/panels/hierarchy/hierarchy_panel_test.dart`: drag reparenting end-to-end on the T004 harness (accept + reject + reorder paths), and the Add menu's root filtering (hitbox entries disabled, entity offered).

**Checkpoint**: Structure editing complete; every action one undoable transaction.

---

## Phase 7: User Story 5 — Edit fields in the inspector (Priority: P1)

**Goal**: Transform + field editors + Override markers and Reset (spec FR-029–FR-034).

**Independent Test** (spec story 5): select the entity, set and reset every editable field type, save, reopen, byte-compare; read-only fields round-trip untouched.

- [X] T035 [P] [US5] Create `lib/panels/inspector/inspector_panel.dart` (panel shell: transform section + field rows hosted, `PrEmptyState` with nothing selected — FR-029) and implement the transform section in `lib/panels/inspector/transform_section.dart`: position, angle (°), scale, size, anchor as plain `PrNumberProperty`/`PrVector2Property` rows over `NodeTransform` (all five — clarified); **no** Override marker, "default from code" or ↺ ever (always written in full, *Q89*); the 3×3 anchor picker is deferred to the design review.
- [X] T036 [US5] Implement the scalar, string and enum editors in `lib/panels/inspector/field_editors.dart`: int/double on `PrNumberProperty` (Manifest `min`/`max` — an out-of-range number clamps on commit and the field shows the clamp; non-numeric text is held invalid: error border, Esc reverts, FR-031), bool, string, enum as a composed `PrPropertyRow` + `PrDropdown` of the Manifest's `values` (a kept value not among them still displays); every commit = `transact` with `coalesceKey: 'field:<node>:<name>'` (FR-034). Unit tests include a save/reload round-trip for the five scalar/string/enum editors (SC-008).
- [X] T037 [P] [US5] Implement the vector2 and image-path editors in `lib/panels/inspector/field_editors.dart`: `PrVector2Property` (aspect lock available where the design allows); image path = `PrDropdown` listing matching files under the project's **declared** asset folders, read from disk so new files appear without a restart (*Q31*), storing the project-relative path; unit tests include a save/reload round-trip for both (completing SC-008's seven editable types).
- [X] T038 [US5] Implement Override display and reset in `lib/panels/inspector/`: `PrValueSource` from `Overrides` presence, the ↺ *Reset to default* → `Overrides.reset` through one transaction (ADR 0003), "default from code" showing the evaluated constant or the `defaultSource` text (§7.3); tooltip carries type · default · `@Editable(tooltip:)`.
- [X] T039 [US5] Implement the read-only rows for `Color`, entity reference, `Sprite`, `SpriteAnimation`: value display only (lock affordance), round-trip untouched — test in `test/panels/inspector/round_trip_test.dart` loads a scene with all four, edits neighbouring fields, saves, byte-compares (SC-008).
- [X] T040 [US5] Implement the Missing-node safe mode in `lib/panels/inspector/inspector_panel.dart`: no invented field rows for a Missing type; name + (for entities) transform still editable; a notice explains why (story 5 scenario 8).
- [X] T041 [US5] **Required widget test** in `test/panels/inspector/override_reset_test.dart`: set an Override (marker appears) → Reset to default (marker gone, value back to code default) → undo restores the Override (one step).

**Checkpoint**: The inspector edits every preview Field type; Overrides behave per ADR 0003.

---

## Phase 8: User Story 6 — Attach Behaviors (Priority: P2)

**Goal**: Add/remove Behaviors with compatibility filtering; Missing/incompatible states keep values (spec FR-035–FR-038).

**Independent Test** (spec story 6): attach `example/`'s `Spin`, edit fields, remove/re-add; delete the class + regenerate → Missing with values kept; restore → values back.

- [X] T042 [US6] Implement the Behavior cards in `lib/panels/behaviors.dart`: list the entity's/custom Node's `BehaviorAttachment`s as collapsible cards (`PrSectionHeader`), fields via the US5 editors; *Add Behavior* list from the catalog grouped by `category`, filtered by `parentType` through `supertypes` (*Q57*), `acceptsBehaviors: false` disables the button with the reason (*Q50*); adding starts at code defaults (no Overrides).
- [X] T043 [US6] Implement remove and the kept-value states in `lib/panels/behaviors.dart`: remove = the attachment and its Overrides in one transaction; Missing behavior / Missing component cards and badges with "no longer exists in your code. Its values are kept.", values rendered read-only and preserved verbatim on save (*Q32*); incompatible parent shows the reason, kept the same; recovery when the type returns is derived — assert it in the tests.
- [X] T044 [US6] **Required widget test** in `test/panels/behaviors/missing_behavior_test.dart`: a Behavior whose Type ID left the catalog renders as Missing with its values, survives a save/load round trip byte-identically, and returns editable when the type reappears.

**Checkpoint**: All six panel stories done; every Missing value provably kept.

---

## Phase 9: User Story 7 — The whole loop, in Pyro, in `example/` (Priority: P1)

**Goal**: The phase's Done-when, run and recorded (spec FR-040/FR-041; quickstart.md).

**Independent Test**: it *is* the test — quickstart.md §2–§5 on the reference Mac.

- [X] T045 [US7] Run quickstart.md §2 (the capstone): build a scene from scratch in `example/` with the panels only (entity, sprite, hitbox, `Spin` with edited fields), save, `git diff` shows the canonical form, close/reopen identical, second save is a no-op, the contract tests pass on the new scene, and the Phase 3 loop hot-swaps it via `bin/play.dart`.
- [X] T046 [US7] Run quickstart.md §3 (the Missing drill) and §4 (save gates + recovery drills: changed-on-disk refusal with force, recovery *Restore* after a kill, repair report on a hand-broken tree).
- [X] T047 [US7] Run quickstart.md §5 (profile mode): record ≤ 16 ms frames for gizmo drag, number scrub, hierarchy selection and inspector typing on a 1,000-Node scene, and the ≤ 200 ms image-change refresh with only dependents rebuilt.
- [X] T048 [US7] Record the results in `dev-docs/ARCHITECTURE.md` (numbers, findings, workarounds) and tick Phase 4 in `dev-docs/phases.md` (status line and counts; §14 only if scope/estimates moved) — **in the same change** (FR-040/041).

---

## Phase 10: Polish & Cross-Cutting Concerns

- [X] T049 Workspace-wide gates from the repo root: `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and `flutter test` in every member; the CI contract job green on the pushed branch.
- [X] T050 Close the two flagged items from plan.md: the `yaml` dependency note (done in T001 — verify recorded) and the `PrMenuItem` disabled-reason decision (taken or explicitly declined, with the reason, in plan.md or decisions.md if it becomes a *Q*).
- [X] T051 Self-review the whole change against the constitution (boundaries: no Flame/Riverpod in `pyro_ui`, panels never import `flame`, `document/`/`process/` untouched; integrity: every save path through `DocumentSession`; performance budgets stated and measured); open the PR from `specs/006-editor` with Conventional Commits citing the *Q* numbers implemented.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately.
- **Foundational (Phase 2)**: after Setup; blocks all stories.
- **Stories**: follow §14's build order **US1 → US2 → US3 → US4 → US5 → US6 → US7**. US1 is the hard prerequisite (window, providers, save flow); US2 feeds US3's custom placeholders and US4's Add menu; US3 feeds US4/US5's selection sync; US6 needs US5's field editors; US7 needs all of them.
- **Polish (Phase 10)**: after US7.

### Within Each Story

- Models/catalog rules before the panels that read them; pure seams (reconciler, parenting) before their callers; required widget tests last in their story (the reconciler suite first in US3 — TDD).

### Parallel Opportunities

- Phase 1: T002 ∥ T003 (after T001 only for the lock file).
- Phase 2: T004 ∥ T005.
- US1: T007 ∥ T008 ∥ T009 (independent files) once T006 exists; T014 anytime after T010.
- US2: T018 ∥ T019 before T020/T021.
- US5: T035 ∥ T037 (different sections) beside T036.
- Never parallel: two tasks writing the same file (notably `field_editors.dart` T036/T037 — run sequentially or split the file first).

---

## Implementation Strategy

### MVP First (through US1)

1. Phases 1–2 → 2. Phase 3 (US1) → **stop and validate** with quickstart §1/§4: the window, tabs, prompts and gates all work against `example/`.
2. This alone de-risks every later story: providers, save flow and dialogs are the seams everything plugs into.

### Incremental Delivery

3. US2 (catalog) → headless-testable alone; US3 (viewport) → the scene is visible and draggable; US4 (hierarchy) → structure editing; US5 (inspector) → field editing + Overrides; US6 (Behaviors) → the custom-code story; each checkpoint runs its spec story's Independent Test.
4. US7 is the acceptance run — it adds no code, only proof (and the docs updates).
5. Polish closes the gates and the PR.

### Notes

- Every save path goes through `DocumentSession` — no panel writes a scene file (constitution IV).
- The Claude Design view designs are deferred (spec Clarifications): any panel task may proceed; if a "New pattern" surfaces during implementation, propose it per *Q87* before building it into a panel.
- Commit after each task or logical group, Conventional Commits citing *Q*/*FR* where they apply.
