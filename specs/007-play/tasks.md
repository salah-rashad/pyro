# Tasks: Play (Phase 5)

**Input**: Design documents from `specs/007-play/` (spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md)

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Included — the spec requests them (FR-035 daemon transcripts, FR-036 the lock probe, FR-037 redaction) and constitution V makes process clients, the Runtime loader and the contract test Heavy. Within each story the tests come first and must fail before the code that satisfies them.

**Organization**: Tasks are grouped by user story, in the spec's priority order: US1 Play and Hot-swap on save (P1), US2 generator (P1), US3 README and dry run (P1), US4 Attach and IDE (P2), US5 Console (P2), US6 stops and restarts (P2). US3 is listed third because the spec ranks it P1, but it is the last story to *finish*: its dry run needs US1, US2 and US4 (see Dependencies).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US6)
- File paths are under `apps/editor/` unless stated otherwise
- **(reference Mac)** marks a task that needs the macOS machine, a game window and Xcode; every other task needs the Flutter SDK (3.47.7) but no device
- Run Flutter and Dart with `export PATH="$PATH:/Users/salah/Library/flutter/bin"` first

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Move `vm_service: ^15.4.0` from `dev_dependencies` to `dependencies` in `apps/editor/pubspec.yaml` (BSD-3, MIT-distribution compatible; the one dependency change, flagged in plan.md's Complexity Tracking), run `dart pub get` from the repository root, and commit the lock change alone.
- [X] T002 [P] Create `lib/process/src/play_defaults.dart` with `abstract final class PlayDefaults` holding exactly the constants of data-model.md: `sceneQuiet` 150 ms, `stopTimeout` 5 s, `hotSwapReportWait` 3 s, `hotSwapMissLimit` 2, `codeReloadSettle` 2 s, `lockReprobe` 1 s, `consoleCapacity` 10000, `consoleNotify` 50 ms; documented; export it from `lib/process/process.dart`. Point `PlayClient`'s defaults at `sceneQuiet` and `stopTimeout` (same values, one source).
- [X] T003 [P] Create `test/fixtures/transcripts/README.md` listing each recorded transcript (name, command that recorded it, Flutter version, date, which test reads it) with the rule that auth codes are masked by `--record` and that `grep -rE '[A-Za-z0-9_-]{6,}=(/|$)' test/fixtures/transcripts` must find nothing before committing.

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️** No user story starts before this phase is green. It holds the pieces every story shares: the Console's data and panel (every story writes lines, and a build failure must be visible from US1) and the Runtime's report lines (the Hot-swap monitor, the benchmark and the quickstart read them).

### Console data (pure Dart)

- [X] T004 [P] Write `test/process/console_buffer_test.dart` first (must fail): lines enter in order with a strictly increasing `sequence`; the ring holds exactly 10,000 lines and the oldest drops first; every line is passed through `redactAuthCodes` on entry for all three sources (`ws://127.0.0.1:1234/AbC=/ws` becomes `ws://127.0.0.1:1234/<auth-code>=/ws`); a filter set hides other sources without losing lines and restoring it shows them all; `clear()` empties it; listeners are told at most once per 50 ms under a burst of 5,000 `add` calls (use `fake_async` and `clock`, no real sleeps).
- [X] T005 [P] Extend `test/process/redact_test.dart` with the shapes of FR-037 and SC-005: the `app.debugPort` `wsUri`, a raw stdout line carrying `http://127.0.0.1:50300/AbC=/`, the Dart Tooling Daemon `ws://…/AbC=` at the end of a line, a daemon error message, and lines that must stay byte-for-byte unchanged (a URL without an auth code, `key=value` text, a path ending in `=`). Add the same cases through `ConsoleBuffer.add` once T006 exists.
- [X] T006 Implement `lib/process/src/console_line.dart` (`ConsoleSource` {generator, game, pyro}, `ConsoleSeverity` {info, warning, error}, immutable `ConsoleLine` with `text`, `source`, `severity`, `time`, `sequence` per data-model.md) and `lib/process/src/console_buffer.dart` (`ConsoleBuffer`: fixed-capacity ring from `PlayDefaults.consoleCapacity`, redaction on entry, `Stream<void> changes` throttled by `consoleNotify` using `clock`, `lines` as an unmodifiable view filtered by an enabled-source set, `clear()`, `dispose()` cancelling its timer). Export both from `lib/process/process.dart`. Add the glossary entry **Console** to `GLOSSARY.md` in this change. T004 and T005 pass.
- [X] T007 Add `lib/process/providers.dart` (a separate library; `process.dart` stays free of Flutter so `bin/play.dart` still runs with `dart run`) with `consoleBufferProvider` — one `ConsoleBuffer` per open project, disposed with the project — and a `consoleSourceFilterProvider` (`Set<ConsoleSource>`, all enabled). Provider test in `test/process/providers_test.dart`: the buffer is recreated when the project root changes and disposed on close.

### Console panel (moved up from the Console story: Play's output and build failures must be visible from US1)

- [X] T008 [P] Write `test/panels/console/console_panel_test.dart` on `pumpPyro`: lines appear in order with their source label; filtering by each source hides the others and clearing the filter shows all again; *Clear* empties the list; the list follows the tail until the user scrolls up and resumes on request; severity colors a line (`error` distinguishable from `info`); 5,000 lines inserted at once render only the visible rows (virtualized) and the buffer stays at its bound.
- [X] T009 Implement `lib/panels/console/console_panel.dart` on `Pr` components (`PrPanel` header, `PrSegmentedControl` or `PrToggleButton`s for the three sources, a `PrIconButton` for *Clear*, a virtualized `ListView.builder` with a fixed row extent, `PrEmptyState` when empty): reads `consoleBufferProvider`, filters through `consoleSourceFilterProvider`, rebuilds only on the buffer's throttled `changes`, follows the tail unless scrolled up. Export `ConsolePanel` from `lib/panels/panels.dart`. T008 passes.
- [X] T010 Mount the Console in the shell's bottom dock: set `bottom: ConsolePanel()` in `lib/app/shell.dart` (the `PrShellSizes.bottom` height, 220 by default, and its persistence already exist); keep it collapsible through the shell's own dock behavior. Update `test/widget_test.dart` for the new slot.

### Runtime report lines (the one package change, `contracts/hot-swap-reports.md`)

- [X] T011 [P] Write `packages/pyro_runtime/test/loader/hot_swap_reports_test.dart` first (must fail, `flame_test` style of the existing loader tests): a first `PyroScene.load` prints exactly `[pyro] Scene loaded: <path>` once; a Hot-swap that rebuilt after a content change prints exactly `[pyro] Scene reloaded: <path>` once, and an unchanged re-read prints nothing; a Hot-swap whose file cannot be rebuilt prints `[pyro] Scene not reloaded: <path>: <first line of the error>` and the old tree stays; the existing multi-line "Pyro couldn't Hot-swap" block is still printed. Capture output with `debugPrint` overridden. Also test the pure helper of T012 for the three formats.
- [X] T012 Implement the three lines in `packages/pyro_runtime/lib/src/loader/pyro_scene.dart` via one pure helper (`String hotSwapReportLine(HotSwapReport kind, String path, [String? reason])`, `@visibleForTesting`), printed with `debugPrint`: `loaded` once, after the first build only (`_adopt` also runs on a Hot-swap and must not print it), `reloaded` right before `onReloaded?.call(this)` in `_checkForChanges`, `not reloaded` in its failure branch. Every call site stays inside the existing `kDebugMode` guard of `onHotReload` or an equivalent one; the first-load line is also guarded by `kDebugMode`. Add the glossary entry **Hot-swap report** to `GLOSSARY.md` in this change. T011 passes.
- [X] T013 [P] Update `example/lib/example_game.dart`: remove the `debugPrint('[pyro_example] Scene reloaded: …')` in `_onReloaded` (keep `swaps++` and the HUD, and the `Scene loaded` line the benchmark already waits for); update `example/README.md` to say the Runtime prints the report lines. Update `benchmark/hot_swap_latency.dart`: `_reloaded` becomes `'[pyro] Scene reloaded'` and its header comment says where the line now comes from.
- [X] T014 Run the workspace checks from the repository root — `flutter analyze --fatal-infos`, `dart format --set-exit-if-changed .`, `flutter test` in `packages/pyro_runtime`, `example/` and `apps/editor` — and the contract job's local commands (regenerate `example/`, compare the committed Registry and Manifest and the golden, load every `example/` Scene with the real Registry, fail on any warning). All green before any story starts.

**Checkpoint**: Console (data and panel) and the Runtime's report lines exist, tests green, contract job green; stories can start.

---

## Phase 3: User Story 1 — Press Play and see the scene in the game (Priority: P1) 🎯 MVP

**Goal**: A Play control in the editor window starts the project's own game on macOS, shows Starting → Running → Stopped, asks "Save and play" / "Play without saving" when scenes have unsaved changes, explains in words why Play is disabled, stops cleanly, and Hot-swaps a saved scene (FR-001–FR-009, FR-014, FR-016).

**Independent Test** (spec story 1): open `example/`, press Play, edit a Behavior field, save, watch the game change in under a second, then press Stop (quickstart §3.1).

### Tests for User Story 1 (write first, must fail)

- [X] T015 [US1] (reference Mac) Record the daemon transcripts that US1's tests read, with `dart run bin/play.dart ../../example --record test/fixtures/transcripts/<name>.txt`: `run-scene-save.txt` (start, one scene save, stop), `build-failure.txt` (run it on a scratch copy of `example/` with a deliberate compile error in `lib/`), `exit-without-stop.txt` (start, then close the game's window by hand). Mask check per T003, then commit them.
- [X] T016 [P] [US1] Write `test/process/play_block_test.dart`: `PlayBlock.of(...)` returns the first reason in the order of data-model.md — project failed to open, no Flutter SDK, Runtime incompatible or missing, no `macos/` folder — each with its fix text (the `macos/` one contains `flutter create --platforms=macos .`), and `null` when none applies.
- [X] T017 [P] [US1] Write `test/process/play_controller_test.dart` over a fake `PlayStarter` and fake sessions (reuse `test/process/fake_process.dart`, `fake_async`): `phase` goes stopped → starting → running → stopping → stopped; `play()` while starting/running/stopping does nothing and starts one session (FR-002); a transcript that ends before `app.started` (T015's `build-failure.txt`) ends Stopped and never shows running (FR-016); `exit-without-stop.txt` ends Stopped with a `GameStopped` notice within the same turn (FR-014); `stop()` ends Stopped even when `app.stop` is ignored (SIGTERM then SIGKILL, FR-004); a `block` makes `play()` start nothing; lifecycle events become Console lines of source `pyro` and game output becomes source `game`.
- [X] T018 [P] [US1] Write `test/app/play_toolbar_test.dart` on `pumpPyro`: Play enabled with no block; Play disabled with the reason and fix visible for each `PlayBlock`; the control becomes Stop while starting/running and shows the four phase labels; with an unsaved scene, pressing Play shows "Save and play" / "Play without saving"; "Save and play" saves every unsaved scene then starts, and a failing save starts nothing; "Play without saving" starts at once; dismissing starts nothing; with no unsaved scene no question appears (FR-006).

### Implementation for User Story 1

- [X] T019 [P] [US1] Implement `lib/process/src/play_block.dart` (`PlayBlock` with `reason` and `fix`, plus `PlayBlock.of({project, sdk, compatibility, hasMacosFolder})` in the data-model.md order). T016 passes.
- [X] T020 [US1] Implement `lib/process/src/play_controller.dart` per `contracts/play-orchestration.md`: `PlayPhase` {stopped, starting, running, stopping}, `phase`/`phases`, `block`, `notices` (`PlayNotice` sealed class with `GameStopped` for now), `play()`, `stop()`; an injected `PlayStarter` (defaults to `PlayClient.start`) so tests need no process; maps `PlayState.reloading` to running; writes Pyro lifecycle events and game output into the `ConsoleBuffer` (sources per data-model.md; a `PlayFailed` event puts its `outputTail` lines in the Console); `play()` is a no-op unless the phase is stopped and `block == null`. Export from `process.dart`. T017 passes.
- [X] T021 [US1] In `lib/process/providers.dart` add `playControllerProvider` — one `PlayController` per open project, built from `projectProvider` (root, SDK, compatibility, `macos/` folder check), its `ConsoleBuffer`, a `PlayClient` using the detected Flutter executable, disposed on project close (disposal stops the game; the confirmation lives in US6). Test the wiring in `test/process/providers_test.dart`.
- [X] T022 [US1] Add the "Save and play" question to `lib/app/dialogs.dart` as `showSaveAndPlayDialog(...)` returning `SaveAndPlayAnswer` {saveAndPlay, playWithoutSaving, cancel}, on the existing dialog component and button order of the other dialogs there.
- [X] T023 [US1] Implement `lib/app/play_toolbar.dart`: a `PrToolbar` content with the Play/Stop `PrButton`, the phase label, and the disabled reason + fix (tooltip and a one-line inline text) from `PlayController.block`; pressing Play with unsaved scenes runs T022's question, saves through the existing `saveScene` for each unsaved scene (stop at the first failure and start nothing), then calls `play()`. Panels and the toolbar import `Pr` components only. T018 passes.
- [X] T024 [US1] Wire the toolbar into `lib/app/shell.dart`: replace `toolbar: const SizedBox(height: PrSizes.toolbar)` with the `PlayToolbar`; keep every existing slot as is. Update the shell smoke test in `test/widget_test.dart` if it asserts the empty toolbar.
- [ ] T025 [US1] (reference Mac) Run `dart run benchmark/hot_swap_latency.dart ../../example` (no run link yet: this is spec 005's baseline, and SC-002 with the run link is re-measured in T053/T054) and check median < 500 ms, worst < 1 s over ten saves, and SC-003 (zero scene rebuilds for ten no-change saves and ten code-only reloads) against the Runtime's new report line, then run quickstart §3.1 by hand. Record the numbers in the commit message.

**Checkpoint**: Play, Stop, the unsaved question, the disabled reasons and Hot-swap on save work from the editor window; everything else in the spec builds on this.

---

## Phase 4: User Story 2 — The generator keeps the catalog current (Priority: P1)

**Goal**: Pyro starts `build_runner watch` for the open project only when none runs, steps aside for an external one, takes over again after one ends, honours `build_runner stop`, and shows one state in the status bar (FR-017–FR-022).

**Independent Test** (spec story 2): open a project, add an annotated Behavior and watch the Add list; start a generator in a terminal, add another, stop it, add a third (quickstart §3.3).

### Tests for User Story 2 (write first, must fail)

- [X] T026 [US2] (reference Mac) Record real `build_runner` output into `test/fixtures/transcripts/` from `example/` on Flutter 3.47.7 (stdout and stderr merged, in order): `build-runner-watch.txt` (start, one successful build, one build after saving an annotated file), `build-runner-takeover.txt` (a second `dart run build_runner build` while the watcher runs), `build-runner-stop.txt` (`dart run build_runner stop` while it runs), `build-runner-error.txt` (a syntax error in an annotated class, then the fix). Write the exact build-start, build-success and severe-level lines you saw at the top of `contracts/generator-supervisor.md` (research R9 left them open) and commit.
- [X] T027 [P] [US2] Write `test/helpers/hold_lock.dart` (a standalone `dart` program: opens `<arg>/.dart_tool/build/lock/build_runner.lock`, takes `FileLock.exclusive`, prints `locked`, waits for stdin to close) and `test/process/build_lock_test.dart`: `check` returns `held` while the helper process holds the lock, `free` after it exits, `absent` when the file does not exist and **creates no file** (assert the directory listing is unchanged, and that no `.requested` appears); the probe unlocks and closes in a `finally`. Real operating-system locks, no Flutter SDK.
- [X] T028 [P] [US2] Write `test/process/generator_output_test.dart` over the T026 transcripts: each line maps to `building`, `succeeded`, `failed`, `takeover`, `waiting` or `other` as in `contracts/generator-supervisor.md`; unmatched lines are `other`; `Exiting as requested by another build_runner process.` and `Waiting for already-running build_runner.` are recognized.
- [X] T029 [P] [US2] Write `test/project/build_runner_version_test.dart` first (must fail): `BuildRunnerVersion.of` reads `packages: build_runner: version` from `pubspec.lock` texts — `2.15.1` ok, `2.14.0` ok (the boundary), `2.13.9` too old, no `build_runner` entry → absent, a malformed lock → unknown with the parse reason; it never throws (FR-017).
- [X] T030 [US2] Write `test/process/generator_supervisor_test.dart` over a fake process starter and a fake `BuildLockProbe`, with `fake_async`: no `build_runner` in the pubspec, a `build_runner` below 2.14 (the reason names the version found and 2.14) or an incompatible Runtime → `notSetUp`, nothing spawned (FR-017, FR-020); lock `free`/`absent` → spawns `<flutter root>/bin/dart run build_runner watch` without `--delete-conflicting-outputs` and goes starting → generating → upToDate; lock `held` → `external`, nothing spawned, re-probes every 1 s and starts its own when free; both rows of the Q77 table on the takeover transcript (held → external then restart on release; free → `stopped` and no restart; *Start* restarts); a non-zero exit → `error` with the last severe line and no automatic restart; the waiting case → own process stopped, `external`; an `error` build carries file and message; `dispose()` stops Pyro's own child and cancels the timer but never touches an external run, and no timer or child remains (FR-022).

### Implementation for User Story 2

- [X] T031 [P] [US2] Implement `lib/process/src/build_lock.dart` per `contracts/generator-supervisor.md` and research R8: `LockProbeResult` {held, free, absent} and `BuildLockProbe.check(projectPath)` using `File.exists`, `RandomAccessFile.lock(FileLock.exclusive)` (async, non-blocking so a held lock throws), `unlock` and `close` in a `finally`; never creates a file. T027 passes.
- [X] T032 [P] [US2] Implement `lib/process/src/generator_output.dart`: a table-driven classifier (a const list of pattern → `GeneratorLine` kind) whose rows are the strings recorded in T026. T028 passes.
- [X] T033 [P] [US2] Implement `lib/project/build_runner_version.dart`: `BuildRunnerVersion.of(projectPath)` parsing the project's `pubspec.lock` with `yaml`, the way `lib/project/runtime_compat.dart` reads `pyro_runtime`; result `ok(version)`, `tooOld(found, required: 2.14.0)`, `absent` or `unknown(reason)`. T029 passes.
- [X] T034 [US2] Implement `lib/process/src/generator_state.dart` (`GeneratorState` {notSetUp, starting, generating, upToDate, error, external, stopped} with `ownedByPyro`, `generation`, and for `error` the `file`, `message`) and `lib/process/src/generator_supervisor.dart` per the contract: the start rules, the takeover table, re-probing every `PlayDefaults.lockReprobe`, `Stream<GeneratorState> states`, `Stream<String> lines`, `start()` for the *Start* button, `dispose()`. The `dart` executable is `<flutter root>/bin/dart` from the detected SDK. Export both from `process.dart`. Add the glossary entry **External build_runner** to `GLOSSARY.md` in this change. T030 passes.
- [X] T035 [US2] In `lib/process/providers.dart` add `generatorProvider`: builds a `GeneratorSupervisor` when a project opens (precondition: `build_runner` in the pubspec, `BuildRunnerVersion` ≥ 2.14, and the Runtime compatibility result), starts it, forwards its `lines` into the `ConsoleBuffer` with source `generator` (severity `error` for severe lines), and disposes it when the project closes. Provider test in `test/process/providers_test.dart`.
- [X] T036 [US2] Add the generator item to the status bar in `lib/app/shell.dart` (`_StatusBar`): text per the state table in data-model.md ("Generating…", "Up to date", "External build_runner", "Generator: not set up", "Generator stopped"), an error state that opens the Console's error line or the catalog dialog with the file and message, and a *Start* button only in `stopped`. Keep the existing SDK, compatibility and catalog items. `_StatusBar` is private today: extract it to `lib/app/status_bar.dart` (still used only by the shell) so the widget test can pump it; the "Generator: not set up" text includes the reason. Widget test in `test/app/status_bar_test.dart` for each state, including that `stopped` shows *Start* and calls `start()`.
- [X] T037 [US2] Add a catalog regression test in `test/project/catalog/` : when the supervisor reports `error` and the Manifest on disk carries `errors`, `typeCatalogProvider` keeps the last good types (stale, not empty, *Q105*) and attached Behaviors do not become Missing (FR-020, FR-021); and with the supervisor `external`, a change to `lib/pyro.manifest.json` still updates the catalog through the existing Manifest watch (FR-018).
- [X] T038 [US2] (reference Mac) Run quickstart §3.3 by hand, including SC-008 (ten attempts: the user's own generator always finishes its build) and SC-004 (a new annotated Behavior reaches the Add list in ≤ 5 s). Record the numbers in the commit message. **Headless numbers (2026-10-25, `apps/editor/benchmark/generator_takeover.dart`): SC-004 save → Manifest on disk median 1054 ms, worst 2990 ms; SC-008 10 of 10 user builds finished and Pyro's run came back by itself 10 times; Q77 `stop` stayed stopped; FR-019 names `lib/behaviors/spin.dart`. Still by hand: how the status bar looks and the Add list in the window.** **Also by computer use (2026-10-25): the status bar shows "Generator: starting", then "Up to date", with the generator's lines in the Console, once the workspace-lock fix was in; with another `build_runner` holding the lock it shows "External build_runner". **The Add list, by computer use (2026-10-25): a new annotated Behavior (`PulseProbe`) was in the generated Manifest 3.5 s after the file was written and showed in the inspector's Behaviors list (SC-004, limit 5 s); deleting it removed it again and left `example/` with no diff. Finding: the only way to open an existing Scene is ⌘O, which has no menu entry or button, and the empty state says "Open a Scene from the project" with only a *New scene* button; the README does not mention ⌘O either.**

**Checkpoint**: the Behavior list stays current without a terminal, and Pyro and a user's own generator coexist.

---

## Phase 5: User Story 4 — Attach the IDE to the running game (Priority: P2)

> Listed before US3 because US3's dry run needs it. Depends on US1.

**Goal**: *Attach debugger* copies the current run's address, with the VS Code and Android Studio guides, and Hot-swap keeps working while an IDE is attached, through the run link and the asset re-point; a failed Hot-swap is detected and recoverable (FR-007–FR-011, FR-027–FR-030, FR-024 for the address).

**Independent Test** (spec story 4): Play `example/`, press Attach debugger, attach VS Code with the pasted address, set a breakpoint, then alternate saving a scene change in Pyro and reloading code from VS Code (quickstart §3.2).

### Tests for User Story 4 (write first, must fail)

- [X] T039 [US4] (reference Mac) Record `test/fixtures/transcripts/ide-attached.txt`: Play `example/` with `bin/play.dart --record`, then in another terminal run `flutter attach -d macos --debug-uri <the run's address>` as the stand-in IDE (it makes the same DevFS clash as VS Code, spike #1 finding 2), save a scene change, hot reload and hot restart from the attach side, save again. Mask check per T003. This transcript is recorded with the spec 005 client, so it has no run link: it is used for parsing only, and T054 re-records it with the link.
- [X] T040 [P] [US4] Write `test/process/run_link_test.dart` on a memory/temp file system: `create` makes `<support>/run/<12 hex>/<name>-pyro` pointing at the project, the name never equals the project folder's name, the id is the first 12 hex digits of the SHA-1 of the canonical path; it returns `null` (not an exception) when the support folder is read-only; `remove` and `sweep` delete only the link and **never follow it** (the project folder and its files survive).
- [X] T041 [P] [US4] Write `test/process/vm_service_link_test.dart`: the real wrapper against a loopback-only (127.0.0.1) fake WebSocket JSON-RPC server, no other network — `listViews`, `setAssetBundlePath`, `evict` send the exact methods `_flutter.listViews`, `_flutter.setAssetBundlePath` (`viewId`, `isolateId`, `assetDirectory`) and `ext.flutter.evict` (`isolateId`, `value`); a rejected call throws `VmServiceCallFailed` naming the method and the engine message and the exception text and `toString` never contain the address.
- [X] T042 [US4] Extend `test/process/play_session_test.dart` and `test/process/play_client_test.dart`: with `runLink` set the spawn arguments are the spec 005 arguments plus `--project-root <link>` and the working directory is the real project; before a scene reload the order is `listViews` → `setAssetBundlePath(<baseUri>/build/flutter_assets)` → `app.restart`; when `setAssetBundlePath` is rejected the order is `app.restart` → re-point → `evict` of each changed scene → `app.restart` once more, still one `PlayReloading`/`PlayReloaded` pair; code-only batches send `app.restart` alone; reloads still run one at a time with one queued (*Q122*); `restart()` sends `fullRestart: true`; the hot restart in `ide-attached.txt` produces no `PlayStopped` and no "Game stopped" Console line; the spawn arguments contain no `--target`/`-t` (the project's own entry point, FR-005); `device.added`/`device.removed`/`device.changed` events produce no state change and no Console line; `debuggerAddress` is set from `app.debugPort`, null after the session ends, and **no** event, `toString`, exception or Console line from the `ide-attached.txt` transcript contains the auth code (SC-005, FR-024).
- [X] T043 [P] [US4] Write `test/process/hot_swap_monitor_test.dart`: a changed-content save for an armed path expects a report within 3 s of the reload; `reloaded` and `not reloaded` both count as the game's report; one miss does not fail; two misses in a row fail exactly once and emit `PlayHotSwapFailed`; a report resets the count; a save with identical bytes, a burst of saves (one batch) and a path no `loaded` line announced never count as a miss; `Restart game` re-arms with fresh baselines (FR-011, research R6).
- [X] T044 [P] [US4] Write `test/app/attach_guide_test.dart` and extend `test/app/play_toolbar_test.dart`: *Attach debugger* is disabled with "Press Play first" when no game runs; pressing it while running puts `copyDebuggerAddress()` on the (fake) clipboard, shows a toast without the address and opens the guide; the guide text states the three facts of FR-029 (select the game's device first; paste into "Flutter: Attach to Process"; VS Code may show a stale "paused" state after a restart) and, for Android Studio, its attach steps; the address appears nowhere in the widget tree (SC-005).
- [X] T045 [US4] Extend `test/process/play_controller_test.dart` (FR-030, constitution IV): a full simulated run — Play, scene saves, Attach, Stop — against a memory file system leaves the project tree byte-identical, writes nothing under `.dart_tool/pyro/` or `.vscode/`, passes no `--disable-service-auth-codes` and no fixed DDS port to the spawn, and the only new path anywhere is the run link under the support folder.

### Implementation for User Story 4

- [X] T046 [P] [US4] Implement `lib/process/src/run_link.dart` per `contracts/play-orchestration.md` (`RunLink.create`, `path`, `remove`, `sweep`). Add the glossary entry **Run link** to `GLOSSARY.md` in this change. T040 passes.
- [X] T047 [P] [US4] Implement `lib/process/src/vm_service_link.dart`: the `VmServiceLink` interface and a `VmServiceLink.connect(address)` implementation over `package:vm_service`, `VmServiceCallFailed`, `close()`; every type holding the address overrides `toString` to hide it. T041 passes.
- [X] T048 [US4] Implement `lib/process/src/hot_swap_monitor.dart` per data-model.md and research R6 (baseline SHA-256 per path via `crypto`, `armed`, `expected`, `misses`, `failed`; timers through `clock`). Add `PlayHotSwapFailed(paths, misses)` to `lib/process/src/play_event.dart` and export it. T043 passes.
- [X] T049 [US4] Edit `lib/process/src/play_client.dart` and `lib/process/src/play_session.dart`: `PlayClient.start(…, {RunLink? runLink})` adds `--project-root` when set (spec 005's behavior when null); `PlaySession` stores `wsUri`/`baseUri` privately from `app.debugPort` while still emitting only `PlayDebuggerAvailable`, exposes `debuggerAddress` (documented "for Attach debugger only", cleared when the session ends), opens a `VmServiceLink` lazily for the re-point, runs the re-point/fallback sequence of the contract before scene batches (not before code-only batches), adds `restart()`, feeds output lines and reload results to the `HotSwapMonitor`, and stops sending scene reloads once the monitor has failed. Ignore `device.*` daemon events instead of printing them as tool output. Add the glossary entry **Debugger address** to `GLOSSARY.md` in this change. T042 passes.
- [X] T050 [US4] Extend `lib/process/src/play_controller.dart`: create the `RunLink` before `start` and remove it after the session ends (a failed `create` is a Console line and Play still starts, research R2), `copyDebuggerAddress()` (the only reader of the address, null unless running), `restartGame()` (a full restart that re-arms the monitor), a `HotSwapFailed` notice, and `canAttach`. Extend `test/process/play_controller_test.dart` with these.
- [X] T051 [P] [US4] Implement `lib/app/attach_guide.dart` (`showAttachGuide` on the existing dialog component: numbered VS Code steps and Android Studio steps, no address) and `lib/app/play_notices.dart` with the notice rendering for `GameStopped` and `HotSwapFailed` (toast with *Restart game*); each notice replaces the previous of its kind. T044 passes.
- [X] T052 [US4] Add the *Attach debugger* control to `lib/app/play_toolbar.dart`: disabled with "Press Play first" unless `canAttach`; on press copy through `Clipboard.setData(copyDebuggerAddress())`, show the toast "Debugger address copied" and open the guide. Mount `play_notices.dart` in `lib/app/shell.dart`. T044 passes.
- [X] T053 [US4] Extend `benchmark/hot_swap_latency.dart`: both modes now create a `RunLink` (temp support folder) and pass it to `PlayClient.start`, so SC-002 is measured with the run link and re-point; add `--with-attach`: after the game starts, spawn `flutter attach -d macos --debug-uri <address>` as the stand-in IDE (read the address through the session's `debuggerAddress`, never print it), keep it attached while measuring, and report the same medians, worst case and rebuild counts.
- [ ] T054 [US4] (reference Mac) Run `dart run benchmark/hot_swap_latency.dart ../../example --with-attach` (SC-002 with an attached client, SC-003) and quickstart §3.2 with real VS Code (Dart-Code): attach, breakpoint hit, alternate Pyro saves with IDE reloads and hot restarts, then Stop/Play/Attach again and check the new address is copied (FR-028). Re-record `test/fixtures/transcripts/ide-attached.txt` with the run link and commit it (T039's copy had none). Record the numbers in the commit message. **Done headless (2026-10-25, Flutter 3.47.7): `benchmark/hot_swap_latency.dart ../../example --with-attach`: SC-002 median 268 ms, worst 334 ms; SC-003 0 rebuilds for no-op reloads, a burst of ten saves = 1 reload, with `flutter attach` attached; without it median 258 ms, worst 332 ms. `ide-attached.txt` re-recorded with the run link. Not done: real VS Code (Dart-Code) attach, breakpoint, IDE reloads, and the new-address check (FR-028). Finding: `_flutter.setAssetBundlePath` takes a file path, not a URI (fixed). After the IDE's hot restart the game's output stops reaching Pyro (whether the swap itself still lands was not established), so the session now notices the view's isolate changed outside Pyro, disarms the Hot-swap monitor and says so in the Console once; checked on the real game: three saves after an `R` from `flutter attach`, 0 false failures.** **Still not done: real VS Code. The computer-use tier for VS Code lets me click but not type, and the attach needs "Flutter: Attach to Process" typed into the command palette.**

**Checkpoint**: Hot-swap survives an attached IDE, a broken Hot-swap is reported and recoverable, and the address is copied only by the explicit action.

---

## Phase 6: User Story 3 — A tester adds Pyro to their own project from the README (Priority: P1)

> The README can be drafted any time after Phase 2; the dry run needs US1, US2 and US4 done (the tester task includes Attach). Depends on them.

**Goal**: A root README recipe that takes a Flame project that is not `example/` from nothing to a running scene, and a written dry-run report whose last attempt passes without help (FR-031–FR-034, SC-001, SC-009).

**Independent Test** (spec story 3): the dry run itself — a Flame project the author did not write, the README only, a clean Mac with Flutter and Xcode (quickstart §4).

- [X] T055 [US3] Write the root `README.md`: a short description of Pyro and the section "Add Pyro to a Flame project (early preview)" with the nine items of `contracts/readme-recipe.md`, in order. Every snippet is copied from `example/pubspec.yaml`, `example/lib/main.dart`, `example/lib/example_game.dart` and `example/macos/Runner/DebugProfile.entitlements` as they are today (the git dependencies with `path: packages/<name>`, the `dependency_overrides` they need, `build_runner` ≥ 2.14, `assets/scenes/`, the generate step, the `PyroScene.load` call, `flutter create --platforms=macos .`, the debug network entitlement); building and opening Pyro from source (`dart pub get`, then `flutter run -d macos` in `apps/editor`); the three Attach facts of FR-029; and the "If something goes wrong" list (lock or External build_runner and `dart run build_runner stop`, incompatible Runtime, macOS debug signing, Hot-swap stopped and *Restart game*). No promise about Windows or Linux.
- [X] T056 [US3] Verify the README text against the repository before the dry run: for each pubspec/Dart/entitlement snippet, diff it against its `example/` source (`git diff --no-index`), run every command of the recipe in a scratch folder (`/tmp/pyro-readme-check`, a copy of `example/` without its `pubspec.lock`) and confirm `dart pub get`, `dart run build_runner build` and `flutter build macos --debug` succeed, and fix any drift in the README. **Done (2026-10-25, Flutter 3.47.7): the README's YAML block was applied to a copy of `example/` (git dependencies pointed at a local checkout of HEAD): `flutter pub get` resolves, `dart run build_runner build` regenerates the committed Registry and Manifest (only a blank line differs, formatting), `flutter build macos --debug` succeeds. Without the `pyro_annotations` override `pub get` fails, so the README is right to ask for it. The entitlement and Dart snippets match `example/`. Finding: `flutter create --platforms=macos .` already writes `com.apple.security.network.server`, so step 6 now says so.**
> **Deferred (2026-10-25):** T057–T059 (the dry run) are planned as the last task of the early preview, once the other work is done. The dry-run project is not chosen yet.

- [ ] T057 [US3] (reference Mac) Choose the dry-run project per FR-034 (a Flame project the author did not write and Pyro was not built against; a project from the Flame examples if the author has none) and create `specs/007-play/dry-run-report.md` with the header and table format of `contracts/readme-recipe.md`.
- [ ] T058 [US3] (reference Mac) Dry run, attempt 1: follow only the README in that project, then do the tester task (open in Pyro, place an entity with a sprite and a hitbox, attach a custom Behavior and tweak its fields, press Play, see the change, attach VS Code with the copied address, Hot-swap again). Record start time, first-running-scene time, every stuck point and every unclear sentence in the report, with the verdict.
- [ ] T059 [US3] (reference Mac) For each stuck point from the latest attempt, fix the cause — README text, a Pyro message (a disabled-Play reason, a status-bar text, a Console line) or code — commit each fix separately, note it under "Fixes made" in the report, and run the next attempt. Repeat until an attempt's verdict is "passed without help" (SC-001, SC-009: no "why is Play grey?" question). The elapsed time is recorded and does not decide the verdict.

**Checkpoint**: the README alone gets a stranger's project to a Hot-swapped scene with an attached IDE.

---

## Phase 7: User Story 5 — Console and redaction (Priority: P2)

**Goal**: Prove the Console (panel and buffer, built in Phase 2) never leaks a debugger address and stays smooth under a flood (FR-024–FR-026, SC-005, SC-006).

**Independent Test** (spec story 5): run a game on macOS, whose engine prints its address, and search every Console line and Pyro's files for the auth code (quickstart §3.2 step 1, §3.6). The panel itself (filter, clear, follow the tail) is tested in Phase 2, T008.

### Tests for User Story 5 (write first, must fail)

- [X] T060 [P] [US5] Write `benchmark/console_throughput.dart`: pushes 5,000 lines per second for 10 seconds into a `ConsoleBuffer` with a mix of sources and lines containing addresses, then prints the cost per line, the number of notifications (≤ 20 per second) and the retained line count (= capacity).
- [X] T061 [US5] Add a run-level redaction test in `test/process/play_controller_test.dart` using `ide-attached.txt` and `run-scene-save.txt`: after a whole simulated run, no Console line, notice, `toString` of any event or controller state contains the run's auth code (SC-005); only `copyDebuggerAddress()` returns it.

### Implementation for User Story 5

- [X] T062 [US5] Make sure the buffer has a single entry point: the controller (T020), the generator (T035) and the game output already do; add a test in `test/process/providers_test.dart` that a line written by each of the three paths with an address in it reaches `ConsoleBuffer.lines` redacted, and that no code path adds to the buffer without `add`. T061 passes.
- [X] T063 [US5] (reference Mac) Run `dart run benchmark/console_throughput.dart` and the profile-mode frame check of quickstart §3.6 (`flutter run -d macos --profile`, a game printing 5,000 lines in one second): no frame over 16 ms while the Console follows the tail (SC-006). If a frame exceeds the budget, fix the Console (row cost, notification rate) before closing the story and record the final numbers. **Partly done (2026-10-25, Flutter 3.47.7, headless): `dart run benchmark/console_throughput.dart`: 50,000 lines in 10 s, 8.9 µs per line with redaction, 16.5 notifications a second (limit 20), 10,000 of 10,000 lines kept, no auth code kept. Not done: the profile-mode frame check of quickstart §3.6 (a game printing 5,000 lines in one second, DevTools timeline).** **Frame check done (2026-10-25, Pyro built with `flutter run -d macos --profile`, M4):** the example game, temporarily patched to print 5,000 lines in one second three times (reverted), ran from Play while `benchmark/frame_recorder.dart` read the `Flutter.Frame` events for 45 s with the Console following the tail: 68 frames, build p50 3.1 ms, p99 5.6 ms, max 5.8 ms, raster max 3.6 ms, **0 frames over 16 ms** (SC-006). Pyro's build_runner was gone after quitting (the quit fix).

**Checkpoint**: one log shows everything, nothing in it can leak an address, and it holds 60 fps under a flood.

---

## Phase 8: User Story 6 — Stops and restarts the game cannot hide (Priority: P2)

> Depends on US1 (controller), US2 (generator state for code reload) and US4 (`restartGame`, notices).

**Goal**: "Game stopped" always shown, quitting or closing the project asks before stopping a running game, an image the game uses changing offers *Restart game*, and Dart changes reload code once the generator is idle (FR-012–FR-016, FR-022; edge case of a crashed Pyro).

**Independent Test** (spec story 6): close the game's window by hand; quit Pyro with the game running; replace an image a Scene uses and use the offer; save Dart code (quickstart §3.4).

### Tests for User Story 6 (write first, must fail)

- [X] T064 [P] [US6] Write `test/process/code_watcher_test.dart` with a fake directory watcher, a fake generator state stream and `fake_async`: a batch of `lib/**.dart` saves (150 ms of quiet) asks for one code reload; with the generator `generating` the reload waits for the next `upToDate` or `error`; with `upToDate`, `stopped`, `notSetUp` or `error` it reloads at once; with `external` it reloads when `lib/pyro.g.dart` and `lib/pyro.manifest.json` have been unchanged for 2 s after the save, and 2 s after the save if they never change (FR-012); a code save and a scene save close together share one reload; nothing runs while no game is running. **Note:** a code save and a scene save close together share one reload only through the session's existing one-in-flight, one-queued rule; `CodeWatcher` itself knows nothing of Scene saves.
- [X] T065 [P] [US6] Write `test/process/image_use_test.dart` on a memory file system: image paths named by Sprite Nodes and Image-path Overrides in every `assets/scenes/**/*.scene.json` are collected with the Runtime's `SceneCodec`; a change to a collected path raises `ImageChanged(path)`; a change to an unreferenced image raises nothing; the set is rebuilt when a scene file changes; `restartGame` clears the changed set.
- [X] T066 [P] [US6] Extend `test/process/play_controller_test.dart` and write `test/app/play_notices_test.dart`: an `ImageChanged` notice shows "Image changed" with *Restart game* which calls `restartGame()` and then clears; dismissing leaves the game as it is; a second change replaces the first notice; `GameStopped` after an unrequested exit; the controller's code reloads go through `CodeWatcher` with the generator state; `stop()` is called when the project closes.
- [X] T067 [P] [US6] Write `test/app/quit_and_close_test.dart`: with a game running, an exit request asks "A game is running. Stop it and quit?" — yes stops the game first and then exits, no cancels the exit and leaves the game running; the same helper guards closing the project; with no game running there is no question; the unsaved-scenes dialogs still come first.
- [X] T068 [P] [US6] Write `test/app/idle_frames_test.dart` for SC-010: with the game stopped and the generator `upToDate`, pumping the shell with the toolbar, status bar and Console leaves `tester.binding.hasScheduledFrame` false and `SchedulerBinding.instance.transientCallbackCount` at 0 (no ticker, no per-frame callback); the controller registers no `Ticker` or `addPostFrameCallback` loop.

### Implementation for User Story 6

- [X] T069 [P] [US6] Implement `lib/process/src/code_watcher.dart` per research R10: a recursive watch on the project's `lib/` (the `DirectoryWatcher` of `scene_watcher.dart`), batching by `PlayDefaults.sceneQuiet`, emitting code-reload requests gated by the `GeneratorState` stream and, for `external`, the 2 s settle rule on the two generated files. T064 passes.
- [X] T070 [P] [US6] Implement `lib/process/src/image_use.dart` per research R11 (reads scenes with `SceneCodec`, watches the project's declared image asset folders from `lib/project/asset_folders.dart`). T065 passes.
- [X] T071 [US6] Wire both into `lib/process/src/play_controller.dart`: while the phase is running start the `CodeWatcher` (its requests call the session's code-only reload, which skips the re-point) and `ImageUse` (its changes raise `ImageChanged`); stop and dispose them with the session; `GameStopped` and `HotSwapFailed` keep working. T066 passes. **Done:** the controller takes `CodeWatcherMaker` and `ImageWatcherMaker` factories and starts both on `app.started`; `ImageUse` reads Scenes with the Runtime, which imports Flutter, so it is built in `providers.dart` and reached through the `ImageWatching` interface, keeping `process.dart` (and `bin/play.dart`) free of Flutter. Added `playDirectoryWatcherProvider` so tests drive the watchers.
- [X] T072 [US6] Add the `ImageChanged` rendering to `lib/app/play_notices.dart` (toast "Image changed" with *Restart game*). T066 passes.
- [X] T073 [US6] Implement `confirmStopGame(BuildContext, ProviderContainer)` in `lib/app/dialogs.dart` (a confirmation, then `PlayController.stop()`), call it from `_exitWhenScenesClean` in `lib/app/shell.dart` after the unsaved-scenes loop, and from the project-close flow (find the callers of `ProjectNotifier.close`). T067 passes. **Done:** `confirmStopGame` + `StopGameFor` in `dialogs.dart`; `_exitWhenScenesClean` calls it last. `ProjectNotifier.close` has no caller yet (no *Close project* command exists), so `closeProject(context, container)` in `shell.dart` is the guarded entry point for one, tested in `quit_and_close_test.dart`.
- [X] T074 [US6] On project open, call `RunLink.sweep(projectPath, supportDir)` (in the `playControllerProvider` build) so a link left by a crashed Pyro is removed; nothing about a run is persisted, so no stale "Running" can show (research R13). Add a test to `test/process/providers_test.dart` that a leftover link is gone after open and the project it pointed at is untouched.
- [X] T075 [US6] (reference Mac) Run quickstart §3.4 by hand (window closed by hand, image changed and unchanged, ⌘Q with a game running, force-quit and reopen) and SC-007 (Play available again within 1 s of any exit; no game or `flutter` process after Stop or project close). Record the results in the commit message. **Done by computer use on the reference Mac (2026-10-25, Flutter 3.47.7), with these results:** a Dart save reloaded the game's code with `swaps` still 0 (generator up to date); replacing `ship.png` raised the "Image changed" notice and *Restart game* showed the new image ("Restarted in 290 ms"); a change to an image no Scene names raised nothing; closing the game window by hand gave "Lost connection to device", "Game stopped" and a Play button again; ⌘Q with a game running asked "A game is running. Stop it and quit?", Cancel kept both running, "Stop and quit" left no game, no `flutter run` and no run link; after `kill -9` of Pyro the game kept running (as specified) and the link stayed, and on reopening the link was swept, the project was untouched, no "Running" was shown and Play started a new game; Stop left no game process, no `flutter run` and no link. **Found and fixed:** (1) `example/` is a pub-workspace member, so its lock is the root's and the generator showed "not set up" (`findPubspecLock`); (2) the "Image changed" toast stayed after the game closed, offering *Restart game* to nothing; (3) quitting Pyro never stopped its own `build_runner`, so the next run saw "External build_runner". **Not measured:** SC-007's 1 s (the tool round trip is longer than that; the controller tests cover it). **Confirmed afterwards and fixed:** under puro `dart` is a wrapper that does not `exec` (bash, puro2, dartvm), so a SIGTERM to it left `build_runner` running after project close too; the supervisor now signals everything below the process first (`processDescendants`), covered by unit tests with a fake process tree and a real one. **Checked end to end (2026-10-25):** a real `build_runner watch` under puro reached "Up to date", and after `dispose` no `build_runner` process was left.

**Checkpoint**: nothing about a run's end is silent, and a Dart save reaches the running game once generation is done.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [X] T076 [P] Check that the terms added by T006, T012, T034, T046 and T049 are in `GLOSSARY.md` (each is added in the task that introduces it, constitution I) and nothing is missing: **Console**, **Run link**, **Debugger address**, **External build_runner**, **Hot-swap report**; update **Play session** and **Attach** if their wording no longer fits. **Done (2026-10-25):** all five terms were already in `GLOSSARY.md`; **Play session** and **Attach** reworded (code reload and image notice; the copied address).
- [X] T077 [P] Record the Phase 5 decisions in `docs/decisions.md` as Q125 onward (one row each): the Runtime's report lines (R1); the run link always used (R2); the address held privately (R3); `vm_service` as a runtime dependency (R4); the re-point sequence (R5); the Hot-swap failure rule on any run (R6); the supervisor and "Not set up" (R7, R8, R9); code reload idle rule (R10); images in use are those a Scene names (R11); Console capacity and throttle (R12); "Save and play" question (clarification); the setup time is recorded, not a pass limit (clarification); spec 006 FR-013 superseded (Pyro now starts the generator when none runs); the status-bar wording "External build_runner" is unchanged from `project-plan.md` §9.2 and Q48/Q77. **Done:** Q125–Q138 in `docs/decisions.md` (R1–R12 and the four clarification/supersession rows), and the header names the spec.
- [X] T078 [P] Update `docs/phases.md` (tick Phase 5 items as they finish, the status line, the table row), `docs/project-plan.md` §9.3 and §14 item 11 ("Built in Phase 5" notes, same style as the vertical slice's), and `apps/editor/README.md` (the Play button, the Console, `bin/play.dart` kept as a developer tool). **Done:** `docs/phases.md` marks Phase 5 🔶 (the code, tests and README are done; the dry run and the by-hand checks are open, so it is not ✅), `docs/project-plan.md` §9.3 and §14 item 11 say what was built and what was left out on purpose (the info file and `launch.json`, FR-030), `apps/editor/README.md` describes Play, the Console and `bin/play.dart` as a developer tool.
- [X] T079 Add a "Play" section to `docs/ARCHITECTURE.md` with what was verified: the numbers from T025, T038, T054, T063, T075, the Flutter version, the private interfaces re-checked (`--project-root`, `_flutter.setAssetBundlePath`, `ext.flutter.evict`), and the dry run's outcome. **Done:** the "Play" section of `docs/ARCHITECTURE.md` holds the numbers from T038, T054, T063 and T080, the Flutter version, the private interfaces, what is still unverified, and says the dry run has not been done. T025 was not re-run (no baseline mode is left since T053).
- [X] T080 Release-build check, same method as spec 005's (FR-027): build `example/` in release mode and search `App.framework/App` for `[pyro] Scene` and `couldn't Hot-swap`: zero matches; confirm the same strings are present in the debug build so the search is valid. Record both counts in `docs/ARCHITECTURE.md`. **Done (2026-10-25, Flutter 3.47.7):** release `App.framework/App`: `[pyro] Scene` 0, `couldn't Hot-swap` 0; debug kernel: 7 and 2; `Scene loaded` is in the release binary (2), so the search is valid. Recorded in `docs/ARCHITECTURE.md`.
- [X] T081 Run the full gates from the repository root and fix anything red: `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos`, `flutter test` in every workspace member, the contract job's commands, and a release build of the app. Re-run quickstart §1 and §2 end to end and tick Phase 5 in `docs/phases.md`. **Done (2026-10-25, Flutter 3.47.7):** every CI command passes locally (contract regeneration with no diff, format, analyze, tests in all eight members, the editor's release build); quickstart §1 is that test run and §2 was re-run after Phase 8: latency median 294 ms / worst 377 ms, with `flutter attach` 264 / 339 ms, 0 rebuilds, a burst = 1 reload, Console 8.1 µs a line. Phase 5 stays 🔶 in `docs/phases.md`: the dry run and the by-hand checks (T025, T038, T054, T063, T075) are open.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: none.
- **Phase 2 (Foundational)**: after Phase 1; blocks every story. T004–T007 (Console data), T008/T009/T010 (Console panel, after T007) and T011–T013 (Runtime) are independent groups; T014 closes the phase.
- **US1 (Phase 3)**: after Phase 2. The MVP.
- **US2 (Phase 4)**: after Phase 2; independent of US1 (its status-bar item only needs the shell, which exists).
- **US4 (Phase 5)**: after US1 (needs the controller and the toolbar).
- **US3 (Phase 6)**: README (T055, T056) after Phase 2 with its Attach facts; **the dry run (T057–T059) after US1, US2 and US4**.
- **US5 (Phase 7)**: the redaction proofs and the flood benchmark; after Phase 2; T061 needs US4's transcript; best after US1.
- **US6 (Phase 8)**: after US1, US2 and US4.
- **Polish (Phase 9)**: after all stories; T076–T078 can start as each story lands.

### Within a story

Tests first and failing, then pure Dart units, then the controller/session wiring, then providers, then UI, then the reference-Mac run. Recording transcripts (T015, T026, T039) comes before the tests that read them.

### Parallel opportunities

- Phase 2: T004, T005 and T011 in parallel, then T006 and T012 in parallel, then T013 in parallel with T007; the Console panel (T008, T009, T010) follows T007 while T011–T013 proceed.
- US1: T016, T017, T018 (after T015) in parallel; T019 beside T020's tests; T022 beside T019.
- US2: T027, T028 and T029 in parallel; T031, T032 and T033 in parallel; US2 as a whole in parallel with US1 if two people work.
- US4: T040, T041, T043, T044 in parallel; T046 and T047 in parallel.
- US5's benchmark (T060) and the README draft (T055) in parallel with US2/US4.
- US6: T064–T067 and T068 in parallel; T069 and T070 in parallel.
- Polish: T076, T077, T078 in parallel.

### Parallel example: User Story 4 tests

```text
T040 run_link_test.dart        T041 vm_service_link_test.dart
T043 hot_swap_monitor_test.dart  T044 attach_guide_test.dart (+ toolbar test)
```

All touch different test files and need only the transcript of T039.

---

## Implementation Strategy

### MVP first (User Story 1)

1. Phase 1 and Phase 2 (Console data and panel, Runtime report lines, contract job green).
2. Phase 3 (US1). **Stop and validate**: open `example/`, Play, edit, save, see it, Stop (quickstart §3.1). That is the product loop; everything after makes it robust and shippable to testers.

### Incremental delivery

1. US1 → the loop works.
2. US2 → the Behavior list stays current; no terminal needed.
3. US4 → the IDE can attach without breaking Hot-swap.
4. US5 → the Console is visible and proven leak-free.
5. US6 → every end of a run is handled; code reloads.
6. US3 → the dry run closes the phase and unlocks the early preview.
7. Polish → docs, decisions, release-build check, full gates.

### Notes

- The tasks marked (reference Mac) are the only ones needing the Mac; a Linux/CI run covers everything else.
- `lib/app/shell.dart` is edited by T024, T036, T052, T010, T073 and `lib/process/play_controller.dart` by T020, T050, T071: do those tasks one at a time, in order, never as parallel work.
- Commit after each task or small group with Conventional Commits citing the decision (`Qnn`) where one applies; all commits on `specs/007-play`.
- Nothing in this phase writes into a user project: the only thing outside memory is the run link in Pyro's application-support folder.
