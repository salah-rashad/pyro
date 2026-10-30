---

description: "Task list for the Vertical Slice (Phase 3): the example/ game, the CI contract test, and the first slice of Play (a flutter run --machine client with a CLI)"
---

# Tasks: Vertical Slice

**Input**: Design documents from `specs/005-vertical-slice/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: included. Constitution Principle V makes the contract test **Heavy** and requires process
clients to be tested against recorded daemon transcripts. SC-009 asks for those tests to pass
without a real `flutter` process or device. Within each phase, write the tests first and see them fail before
implementing.

**Organization**: tasks are grouped by user story so each story can be built and checked on its
own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: the user story the task belongs to (US1–US4)
- **(needs Flutter)**: needs Flutter 3.44.2 on the path. **(reference Mac)**: needs the
  reference Mac (macOS, Apple M4, Flutter 3.44.2). If a task can't run in the implementing
  session, leave it open and say so in the PR, as specs 003 and 004 did.

## Path Conventions

All paths are relative to the repository root. Shortened below:

- `ex/` = `example/`
- `app/` = `apps/editor/`
- `proc/` = `apps/editor/lib/process/`
- `ptest/` = `apps/editor/test/process/`

Commands: client tests `cd apps/editor && flutter test test/process/`; example game
`cd example && dart run build_runner build -d && flutter test`; the CLI
`cd apps/editor && dart run bin/play.dart ../../example`.

**Messages** (used throughout): every client error names what failed and where (constitution I):
the project path, the executable, the exit code, or the daemon's message. Tests check these parts
with `contains`, not whole strings. No event, exception or printed line may contain a VM service
auth code. Tests assert this with the transcripts' known code `AbCdEf123456=` (research R5).

---

## Implementation notes

What changed from the plan while implementing (2026-10-22), each also reflected in the code's
comments or the docs:

- **Flutter in the cloud session.** The container had no Flutter at first, so 3.44.2 was installed
  for the session. Every task except the reference-Mac ones (T025, T039, T045, T046) ran here.
  T031 was CI run 35 (`workflow_dispatch` on `specs/005-vertical-slice`, 2026-10-22). All seven jobs
  were green, the contract job took 1 min 19 s, and the example's committed-files check passed on
  macOS, Windows and Linux.
- **The macOS runner (T004)** was made with `flutter create` in a scratch copy, and only `macos/`
  and `.metadata` were copied in, so nothing else in `example/` was touched.
- **Saves while starting (T032, T035):** the plan dropped Scene changes before `app.started`. A
  real `flutter run` on Linux (a throwaway runner, see ARCHITECTURE.md, "Vertical slice") showed
  the game reads its Scene ~100 ms *before* `app.started`, so such a save was lost. The client
  now watches from the spawn and sends one reload after `app.started` (*Q122*). The test for it
  lives in `ptest/play_session_test.dart`, not `scene_watcher_test.dart`. The watcher has no
  `pause`/`resume`: the session's queue already keeps one reload in flight.
- **`app.devTools` and `app.dtd`** came up in the same run and carry addresses. They are dropped
  like `app.debugPort` (*Q121*). `start.txt` now includes them, and `reload_ok.txt` has the real
  success message.
- **`SceneWatcher.close` is synchronous.** Awaiting the subscription's `cancel()` never completed
  under `fake_async`, which hung the session's exit. Nothing needs to wait for the watch to wind
  down.
- **`PlayClient.start` takes `onStdoutLine`** for the CLI's `--record` (contracts/play-client-api.md).
- **The example game logs with `debugPrint`**, not `print` (the `avoid_print` lint). On desktop it
  reaches stdout and the daemon the same way.
- **The canonical Scene (T021)** writes string lists one item per line, as `SceneCodec.encode`
  does. The file is the encoder's output.
- **`build_runner` keeps a hand-edited output** when its inputs didn't change, so a local check of
  the committed files needs `rm -rf .dart_tool/build` first, as a fresh CI checkout has
  (ARCHITECTURE.md finding 4).
- **The benchmark** waits for both `PlayStarted` and the game's first line before timing, because
  the game can print before `app.started`.
- **§14 estimates (T050)** are left as they are until the reference-Mac run closes Phase 3, per
  the plan.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: make `example/` a workspace member with its assets and runner, and protect the files
that are compared byte for byte.

- [X] T001 Add `example` to the `workspace:` list in `pubspec.yaml` (after
  `packages/pyro_generator/fixture_game`). Create `ex/pubspec.yaml` per
  [contracts/example-game.md § Package](contracts/example-game.md#package): `name: pyro_example`,
  `publish_to: none`, `version: 0.0.1`, `environment: sdk ^3.12.0, flutter ">=3.44.0"`,
  `resolution: workspace`. Dependencies are `flame: ">=1.36.0 <2.0.0"`, `flame_behaviors: ^1.4.0`,
  `flutter`, `pyro_annotations: ^0.0.1` and `pyro_runtime: ^0.0.1`. Dev dependencies are
  `build_runner: ^2.15.1`, `flame_test: ^2.0.0`, `flutter_lints: ^6.0.0`, `flutter_test` and
  `pyro_generator: ^0.0.1`. `flutter: assets: [assets/images/, assets/scenes/]`. There is no
  `build.yaml` (*Q107*). Copy `packages/pyro_generator/fixture_game/analysis_options.yaml` to
  `ex/analysis_options.yaml`, fixing its relative include. Run `dart pub get` at the root.
- [X] T002 [P] Add to `.gitattributes`, with a comment in the existing style:
  `example/lib/pyro.* -text`, `example/assets/** -text`, `example/test/goldens/** -text` and
  `apps/editor/test/fixtures/daemon/** -text` (research R6, R13)
- [X] T003 [P] Write `ex/tool/draw_ship.dart`. It encodes a 32×32 RGBA PNG (a simple ship
  silhouette on transparency) with `dart:io`'s `zlib` and a CRC-32 written in the script, with no
  image package, and writes it to `ex/assets/images/ship.png`. Run it and commit both files.
  Running it again must produce identical bytes.
- [X] T004 (needs Flutter) In `ex/`, run
  `flutter create --platforms=macos --project-name pyro_example --org dev.pyro .`. Keep `macos/`
  and `.metadata`. Delete everything else it created or changed (`lib/main.dart`, the `test/`
  folder, `README.md`, `pubspec.yaml` changes and any new `.gitignore`), so that the files from
  T001 stay as written. Check that `macos/Runner/DebugProfile.entitlements` holds
  `com.apple.security.network.server` (VM service in debug). Commit `ex/macos/` (spec FR-006).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the parts of the Play client that US3 and US4 both stand on: events, the daemon
parser, redaction, the fake process, and a session that can start and notice an exit.

**⚠️ CRITICAL**: US3 and US4 cannot start until this phase is complete. US1 and US2 don't depend
on it.

### Tests for the foundation

- [X] T005 [P] Write the hand-written transcripts in `app/test/fixtures/daemon/` per research R6,
  one stdout line per line, in Flutter 3.44.2's daemon format (spike #1's driver shows the
  shapes):
  - `start.txt`: a non-JSON `Launching lib/main.dart on macOS in debug mode...` line;
    `[{"event":"daemon.connected",…}]`; `app.start` with `appId: "app-1"`; `app.progress`
    started and finished; a raw `flutter: The Dart VM service is listening on
    http://127.0.0.1:50300/AbCdEf123456=/` line; `app.debugPort` with
    `wsUri: "ws://127.0.0.1:50300/AbCdEf123456=/ws"` and a `baseUri`;
    `[{"event":"app.started","params":{"appId":"app-1"}}]`; and the raw line
    `flutter: [pyro_example] Scene loaded: assets/scenes/level1.scene.json`.
  - `reload_ok.txt`: a `{"id":1,"result":{"code":0,"message":""}}` response, with an
    `app.progress` pair before it.
  - `reload_failed.txt`: `{"id":1,"result":{"code":1,"message":"lib/main.dart:3:1: Error: …"}}`.
  - `stop.txt`: an `{"id":2,"result":true}` response, then
    `[{"event":"app.stop","params":{"appId":"app-1"}}]`.
  - `crash.txt`: a raw `Lost connection to device.` line and nothing more (the test ends the
    process with exit code 1).
  - `no_macos_target.txt`: the tool's `No macOS desktop project configured…` lines, then nothing
    (the test exits it with code 1).

  Add `app/test/fixtures/daemon/README.md` saying they are hand-written until quickstart §5.10
  replaces them with recordings (`bin/play.dart --record`).
- [X] T006 [P] Write `ptest/redact_test.dart` for `redactAuthCodes`:
  `http://127.0.0.1:50300/AbCdEf123456=/` becomes `http://127.0.0.1:50300/<auth-code>=/`; the
  same for `ws://…/AbCdEf123456=/ws` and DTD's `ws://127.0.0.1:1235/AbCdEf123456=` at the end of a
  line; a code inside JSON quotes; a line without a URI is unchanged; a path that isn't a code (a
  URL without a trailing `=`) is unchanged.
- [X] T007 [P] Write `ptest/daemon_message_test.dart` for `parseDaemonLine`:
  - an event (`DaemonEvent(name, params)`);
  - a response with `result` and one with `error` (`DaemonResponse`);
  - a batch of two messages in one line;
  - a line that starts with `[{` and ends with `}]` but isn't JSON → one `RawLine`;
  - an unknown event → `DaemonEvent` (not an error);
  - every line of every file in `app/test/fixtures/daemon/` parses without throwing (total
    function, research R4).
- [X] T008 Write `ptest/fake_process.dart`, a `Process` for tests:
  - `FakeProcess.fromTranscript(String file)` reads lines from `app/test/fixtures/daemon/`;
  - `emitAll()` and `emitUntil(bool Function(String line))` push lines to stdout;
  - `emitStderr(String line)` pushes to stderr;
  - `requests` gives each stdin line, decoded as `{id, method, params}`;
  - `exit(int code)` completes `exitCode` and closes both streams;
  - `kill([ProcessSignal])` records signals and returns true, without exiting unless the test says
    so.

  Also write `fakeStarter(FakeProcess)`, a `ProcessStarter` that records the executable, the
  arguments and the working directory.
- [X] T009 Write the lifecycle part of `ptest/play_session_test.dart` (`group('lifecycle')`),
  using `start.txt`:
  - the events, in order: `PlayStarting` (with command
    `flutter run --machine -d macos --debug` and the project path), `PlayOutput` lines,
    `PlayDebuggerAvailable`, `PlayStarted(appId: 'app-1')`, then the game's `Scene loaded` line
    as `PlayOutput(source: game)`;
  - the raw VM service line is redacted;
  - **no** event's `toString()` or field contains `AbCdEf123456`;
  - `state` goes starting → running;
  - after `exit(0)`, `PlayStopped(exitCode: 0, requested: false)` comes and the stream closes;
  - stderr lines arrive as `PlayOutput(source: stderr)`.

  Also write `ptest/play_client_test.dart`'s spawn case on a `MemoryFileSystem` holding
  `/work/My Game ñ/pubspec.yaml` and `/work/My Game ñ/macos/`. The path has a space and a
  non-ASCII character (spec Edge Cases). Check that the starter is called with `flutter`,
  `['run', '--machine', '-d', 'macos', '--debug']` and that exact path as the working
  directory, that the `flutter` argument overrides the executable, and that the file system holds
  exactly the same entries after the session stops (nothing written, spec FR-020).

### Implementation for the foundation

- [X] T010 [P] Implement `proc/src/redact.dart`: `redactAuthCodes(String line)` with spike #1's
  pattern `((?:https?|wss?)://[^/\s"]+/)[A-Za-z0-9_\-]+=(?=[/"\s]|$)` → `${1}<auth-code>=`
  (research R5). Make T006 pass.
- [X] T011 [P] Implement `proc/src/daemon_message.dart`: a sealed `DaemonMessage` with
  `DaemonEvent(String name, Map<String, Object?> params)`, `DaemonResponse(int id, Object? result,
  Object? error)` and `RawLine(String text)`, plus `List<DaemonMessage> parseDaemonLine(String
  line)`. It is total: anything unexpected is a `RawLine` (research R4). Make T007 pass.
- [X] T012 [P] Implement `proc/src/play_event.dart` per
  [data-model.md § PlayEvent](data-model.md#playevent-sealed) and
  [contracts/play-client-api.md](contracts/play-client-api.md):
  - the sealed `PlayEvent` with `PlayStarting`, `PlayDebuggerAvailable`, `PlayStarted`,
    `PlayOutput`, `PlayReloading`, `PlayReloaded`, `PlayReloadFailed`, `PlayFailed` and
    `PlayStopped`;
  - `PlayOutputSource { game, tool, stderr }`;
  - `PlayState { starting, running, reloading, stopping, stopped }`;
  - `ReloadResult`;
  - `PlayStartException(projectPath, message)`.

  All are immutable with `final` fields and `const` constructors where possible. Each has a
  `toString` that the CLI prints. Document every public member.
- [X] T013 Implement the base of `proc/src/play_session.dart`:
  - decode stdout and stderr as UTF-8 lines;
  - dispatch each `parseDaemonLine` result: `app.start` keeps `appId`; `app.debugPort` becomes
    `PlayDebuggerAvailable` and the URI is dropped; `app.started` becomes `PlayStarted` with
    `elapsed`; `app.log` and `RawLine` become `PlayOutput(game)`; `app.progress` (unfinished, with
    a message) and `daemon.logMessage` become `PlayOutput(tool)`; unknown events become
    `PlayOutput(tool)` with the event name; `app.stop` sets a stopping flag;
  - send requests (`_send(method, params)` with increasing ids, completing from
    `DaemonResponse`);
  - pass every line through `redactAuthCodes` before it becomes an event;
  - keep `_tail`, the last 20 redacted lines;
  - on process exit, emit `PlayStopped`, then close the stream;
  - have `state` follow
    [data-model.md § States](data-model.md#states).

  Make T009's lifecycle group pass.
- [X] T014 Implement `proc/src/play_client.dart` (`PlayClient`; the constructor takes `flutter`,
  `startProcess`, `fileSystem` (`package:file`, default `const LocalFileSystem()`),
  `watchDirectory`, `quietPeriod: 150 ms` and `stopTimeout: 5 s`, research R3, R8, R10). Every
  file check goes through `fileSystem`, never `dart:io`'s `File` or `Directory`. `start` spawns `run --machine -d macos --debug` in the absolute project path and returns
  a `PlaySession`. Write `proc/process.dart`, the library that exports exactly the surface of
  [contracts/play-client-api.md § Exports](contracts/play-client-api.md#exports), with a library
  doc comment citing §9.3. Make T009's spawn case pass. No file under `proc/` may import
  `package:flutter` or Riverpod (research R2). Add a test in `ptest/play_client_test.dart` that
  reads every `proc/**.dart` file and fails on such an import, or on a `dart:io` `File(` or
  `Directory(` constructor (file access goes through `fileSystem`). This test reads the
  repository's own sources, not the client's file system.

**Checkpoint**: `flutter test test/process/` passes in `app/`, and a session replays `start.txt`
to `PlayStarted` with no auth code anywhere.

---

## Phase 3: User Story 1 - A working example game (Priority: P1) 🎯 MVP

**Goal**: `example/` generates cleanly, loads its Scene through `PyroScene.load` and the
generated Registry, and shows every Override's effect.

**Independent Test**: `cd example && dart run build_runner build -d && flutter analyze
--fatal-infos . lib/pyro.g.dart && flutter test`, then `flutter run -d macos` (quickstart §2,
§4).

### Tests for User Story 1

- [X] T015 [P] [US1] Write `ex/test/scene_canonical_test.dart`. It reads
  `assets/scenes/level1.scene.json` from disk and checks that
  `SceneCodec.encode(SceneCodec.decode(text))` equals the file byte for byte, with no repairs
  reported (spec FR-003).
- [X] T016 [P] [US1] Write `ex/test/example_game_test.dart` with `testWithGame(ExampleGame.new)`:
  - after load, `scene.find<PyroEntity>('ship')` has a `Spin` whose `turnsPerSecond` is 0.5 (the
    Override) and whose `clockwise` is true (the default);
  - it has a `SpriteComponent` `hull` and a `RectangleHitbox` `body` of size 48×48;
  - `scene.find<Banner>('title')` has `message == 'Hello from Pyro'`, `color` is white and
    `text` is the message;
  - after `game.update(1)` the ship's angle changed by `0.5 * 2π`, clockwise (positive);
  - the HUD reads `time: 1s  swaps: 0  code: v1`;
  - `game.onHotReload()` with an unchanged bundle leaves `swaps: 0` (US1 #3–#4, US3 #3).

### Implementation for User Story 1

- [X] T017 [P] [US1] Write `ex/lib/behaviors/spin.dart`: `@PyroBehavior()`,
  `class Spin extends Behavior<PyroEntity>`. It has
  `@Editable() double turnsPerSecond = 0.25;` and `@Editable() bool clockwise = true;`, and
  `update(dt)` turns `parent.angle` by `turnsPerSecond * 2π * dt`, negated when not `clockwise`.
  Write a doc comment.
- [X] T018 [P] [US1] Write `ex/lib/components/banner.dart`: `@PyroComponent()`,
  `class Banner extends TextComponent`. It has `@Editable() String message = 'Pyro';` and
  `@Editable() Color color = const Color(0xFFFFFFFF);`, and `onLoad` sets `text = message` and a
  `TextPaint` with `color` at font size 24. It accepts no Behaviors (contracts/example-game.md).
- [X] T019 [P] [US1] Write `ex/lib/code_marker.dart`: `const codeMarker = 'v1';`, with a doc
  comment saying the Dart-only reload check edits it (quickstart §5.4).
- [X] T020 [US1] Write `ex/lib/example_game.dart` and `ex/lib/main.dart` per
  [contracts/example-game.md § Game](contracts/example-game.md#game):
  - `ExampleGame extends FlameGame` with an 800×600 fixed-resolution camera;
  - `onLoad` awaits
    `PyroScene.load('assets/scenes/level1.scene.json', registry: pyroRegistry, onReloaded:
    _onReloaded)`, adds it to `world`, and prints
    `[pyro_example] Scene loaded: assets/scenes/level1.scene.json`;
  - `_onReloaded` increments `swaps` and prints
    `[pyro_example] Scene reloaded: assets/scenes/level1.scene.json`;
  - a HUD `TextComponent` in `camera.viewport` shows `time: <whole seconds>s  swaps: <n>  code:
    <codeMarker>`, updated in `update`;
  - `main` runs `runApp(GameWidget(game: ExampleGame()))`.

  The printed lines must match the contract exactly, because the benchmark matches them.
- [X] T021 [US1] Write `ex/assets/scenes/level1.scene.json` per
  [contracts/example-game.md § Scene](contracts/example-game.md#scene-assetsscenes-level1scenejson):
  Nodes `root`, `ship`, `hull`, `body` and `title` with the listed transforms, props and Overrides,
  in canonical form (sorted keys, two-space indent, trailing newline, as `SceneCodec.encode`
  writes). Make T015 pass. If the hand-written form differs, replace it with the encoder's output.
- [X] T022 [US1] (needs Flutter) Run `dart run build_runner build -d` in `ex/`. Check that
  `lib/pyro.manifest.json` has `"errors": []` and `"warnings": []` and lists `Spin` (fields `clockwise`,
  `turnsPerSecond`) and `Banner` (fields `color`, `message`), then commit `lib/pyro.g.dart` and
  `lib/pyro.manifest.json` (US1 #1). Make T016 pass.
- [X] T023 [US1] Write `ex/README.md`. It says what the game is for (the slice, the contract test
  and later the README recipe's reference) and covers: running it (`flutter run -d macos`);
  regenerating (`dart run build_runner build -d`); updating the golden (the `cp` of
  contracts/contract-job.md); that it is macOS-only; and `assets/images/ship.png`, drawn by
  `tool/draw_ship.dart` for this repository and MIT licensed (spec FR-008).
- [X] T024 [US1] (needs Flutter) Run `flutter analyze --fatal-infos example` from the root, then
  `flutter analyze --fatal-infos lib/pyro.g.dart` and `flutter test` in `ex/`, and
  `dart format --set-exit-if-changed example` (US1 #2, constitution I).
- [X] T025 [US1] (reference Mac) Run quickstart §4. Note the time from a clean clone's
  `dart pub get` to the window (SC-001) for T049.
  _Run 2026-10-22: 26 s from a warm cache (not measured cold). The window shows the clockwise
  ship, the banner and the HUD; **the hitbox is not drawn**, see ARCHITECTURE.md "Vertical slice"._

**Checkpoint**: the example generates with no errors, its tests pass, and on the Mac the window
shows the turning ship, the banner and the HUD.

---

## Phase 4: User Story 2 - The contract is checked on every push (Priority: P1)

**Goal**: CI regenerates `example/`'s files and compares them on three OSes, compares the
Manifest with its golden, and loads every Scene, each as a named step.

**Independent Test**: quickstart §2 and §3 locally, then the same breakages on a pushed branch.

### Tests for User Story 2

- [X] T026 [P] [US2] Write `ex/test/contract/scenes_test.dart` per
  [contracts/contract-job.md § scenes_test.dart](contracts/contract-job.md#testcontractscenes_testdart):
  - at test time, list `Directory('assets/scenes')` recursively for files ending in
    `.scene.json`, sorted, with paths relative to the package (`assets/scenes/…`, `/` separators
    on Windows too);
  - fail with a clear message if the list is empty;
  - for each file, a `testWithFlameGame('loads <path>')` that awaits
    `PyroScene.load(path, registry: pyroRegistry)` with the default `onUnknownType`, then
    `game.ensureAdd` and `game.ready()`;
  - while each load runs, replace `debugPrint` with a recorder, restoring it in `tearDown`. If
    the Runtime printed any warning (an unused Override, a repair, a skip; spec FR-012), fail
    with the Scene's path and the warning's text.

  Add a case that proves the warning check works: an unused Override in an inline copy of
  `level1.scene.json` (loaded through a memory `AssetSource`) must fail with the field named.

  A library doc comment says this is #12's Scene check (*Q59*).

### Implementation for User Story 2

- [X] T027 [US2] (needs Flutter) Create `ex/test/goldens/pyro.manifest.json.golden` as a
  byte-for-byte copy of `ex/lib/pyro.manifest.json` (after T022). Check with
  `diff -u test/goldens/pyro.manifest.json.golden lib/pyro.manifest.json`.
- [X] T028 [US2] In `.github/workflows/ci.yml`'s `analyze-test` job, per
  [contracts/contract-job.md § In analyze-test](contracts/contract-job.md#in-analyze-test-macos-windows-linux):
  - after the fixture game's check, add the step "Check the example game's generated files"
    (`working-directory: example`, `dart run build_runner build -d` then
    `git diff --exit-code -- lib/pyro.g.dart lib/pyro.manifest.json`);
  - add `example` to "Check formatting"'s path list and to "Analyze Flutter packages and the app";
  - add "Analyze the example game's Registry" (`flutter analyze --fatal-infos lib/pyro.g.dart`
    in `example`);
  - add "Test the example game" (`flutter test` in `example`), after the fixture game's tests.
- [X] T029 [US2] Replace the `contract` job in `.github/workflows/ci.yml` per
  [contracts/contract-job.md § The contract job](contracts/contract-job.md#the-contract-job-linux-ubuntu-2404).
  Name it `Contract test` on `ubuntu-24.04`. Its steps are checkout, `subosito/flutter-action@v2`
  with `${{ env.FLUTTER_VERSION }}` and cache, `dart pub get`, then the five named steps in order,
  each with `working-directory: example`: the four checks of the contract, plus "Analyze the
  example game", which runs `flutter analyze --fatal-infos . lib/pyro.g.dart` (spec FR-013). Replace the TODO comment with a short one citing
  *Q59* and spec 005. Keep the Flutter ≥ 3.47 `--only-check` note above step 2 and the golden
  `cp` command above step 3. Keep the job's existing triggers (FR-009, FR-015).
- [X] T030 [US2] (needs Flutter) Run quickstart §2 and each breakage of §3 locally. Each check fails
  where the table says and passes again after `git checkout -- example` (SC-002).
- [X] T031 [US2] Push, then confirm in CI that the contract job is green, that the committed-files
  step passes on macOS, Windows and Linux (FR-009a), and that the job takes under 3 minutes warm
  (SC-003). If the three-OS step is green, tick the CI part of `specs/003-generator/tasks.md` T043
  with a note pointing to this spec. Its Mac clean-cache run stays as it is.

**Checkpoint**: the contract job is green, and each deliberate breakage fails at its own named
step.

---

## Phase 5: User Story 3 - Saving the Scene swaps it in the running game (Priority: P1)

**Goal**: the client watches `assets/scenes/`, turns settled changes into one hot reload at a
time, and reports each reload. The CLI lets the author run it, and the benchmark times it.

**Independent Test**: `ptest/` passes (quickstart §1). On the Mac, quickstart §5 steps 1–6.

### Tests for User Story 3

- [X] T032 [P] [US3] Write `ptest/scene_watcher_test.dart` with `fake_async` and a
  `StreamController<FileSystemEvent>` as the watcher (research R7, R8):
  - only paths under `assets/scenes/` ending in `.scene.json` count (`level1.scene.json.tmp`,
    `.level1.scene.json.swp`, `level1.scene.json~` and `lib/main.dart` don't);
  - a `FileSystemMoveEvent` counts its destination;
  - a delete is passed on;
  - nothing fires before 150 ms of quiet;
  - a burst of 10 modify events 100 ms apart gives one reload covering the one path;
  - a change during an in-flight reload queues exactly one more, covering every path changed
    meanwhile, and more changes don't queue a third;
  - (moved to `ptest/play_session_test.dart`, see Implementation notes) saves while starting become one reload after `app.started`;
  - a missing `assets/scenes/` (absent from the test's `MemoryFileSystem`) gives one
    `PlayOutput(tool)` line and no watch.
- [X] T033 [P] [US3] Write the reload part of `ptest/play_session_test.dart` (`group('reload')`,
  starting from `start.txt`):
  - a Scene change sends exactly
    `{"method":"app.restart","params":{"appId":"app-1","fullRestart":false,"pause":false,"reason":"pyro"}}`;
  - with `reload_ok.txt` the events are `PlayReloading(paths: ['assets/scenes/level1.scene.json'])`
    then `PlayReloaded`, and state goes running → reloading → running;
  - with `reload_failed.txt` the event is `PlayReloadFailed` whose message contains
    `lib/main.dart:3:1` and whose `code` is 1;
  - an error response gives `PlayReloadFailed` with its message;
  - `reload()` while starting throws `StateError`;
  - a manual `reload()` during an in-flight one waits and then sends its own `app.restart` with
    `paths` empty;
  - a no-op change (same bytes) still sends a reload (research R7).

### Implementation for User Story 3

- [X] T034 [US3] Implement `proc/src/scene_watcher.dart`, a `SceneWatcher` that takes the project
  directory, the `DirectoryWatcher` and the quiet period. It filters, debounces with `Timer`, and
  coalesces into a `Stream<Set<String>>` of project-relative paths (`/`-separated). `pause` and
  `resume` follow the session's in-flight state, and `close()` cancels the subscription and the
  timer. It reports a missing folder through a callback. Make T032 pass.
- [X] T035 [US3] Wire reloads into `proc/src/play_session.dart`:
  - start the `SceneWatcher` on `PlayStarted`;
  - `reload()` and watcher batches go through one queue: one `app.restart` in flight, at most one
    queued with the union of paths;
  - emit `PlayReloading` / `PlayReloaded` / `PlayReloadFailed` from the response's `code` and
    `message`;
  - time `elapsed` with `clock`;
  - add `reload()` to the public surface.

  Pass `watchDirectory` and `quietPeriod` through from `PlayClient`. Make T033 pass.
- [X] T036 [US3] Write `app/bin/play.dart` per [contracts/play-cli.md](contracts/play-cli.md):
  - parse `<project>`, `--flutter` and `--record`, with no package (a small loop like spike #1's);
    bad arguments print usage to stderr and exit 64;
  - print each event as `+<s.mmm>s  <event>`;
  - `r` + Enter calls `reload()` and `q` calls `stop()`;
  - `--record <file>` tees every raw stdout line of the process to the file, after
    `redactAuthCodes`;
  - exit 1 on `PlayStartException` or `PlayFailed`, otherwise with the game's exit code.

  Signals come in US4 (T044). Document it in a file doc comment.
- [X] T037 [P] [US3] Write `app/benchmark/hot_swap_latency.dart` per research R14:
  - it takes the project path (default `../../example`), starts a `PlaySession`, and waits for
    `PlayStarted` and the `[pyro_example] Scene loaded` line;
  - **SC-004**: ten times, write a changed `level1.scene.json` atomically (temp + rename) with the
    ship's x moved, start a `Stopwatch` just before the rename, and stop it on the next
    `[pyro_example] Scene reloaded` output line (a 5 s timeout counts as a failure). Print each
    time, the median and the worst. It passes when the median < 500 ms and the worst < 1 s;
  - **SC-005**: ten times, alternately touch the Scene (same bytes, new mtime) and bump
    `codeMarker` in `lib/code_marker.dart` then `reload()`; count `Scene reloaded` lines over 2 s
    after each. It passes on 0;
  - **SC-006**: ten changed writes 100 ms apart; count `PlayReloading` events until 2 s of quiet.
    It passes on ≤ 2, provided the last `Scene reloaded` came after the last write;
  - restore both files in a `finally`, stop the session, print a Markdown table, and exit 1 on any
    failed criterion.

  Note in its doc comment that the time is to the log line, and the next frame is ≤ 16 ms later.
- [X] T038 [US3] Add "Play from the command line" to `app/README.md`. It covers what
  `bin/play.dart` does, the usage and keys from contracts/play-cli.md, that it is the slice's entry
  point until the Play button (spec FR-025), and how to run the benchmark.
- [X] T039 [US3] (reference Mac) Run quickstart §5 steps 1–6 and keep the notes and the benchmark
  table for T049. If step 2 or 4 fails, stop, record what happened, and propose a default Play
  target to the author before going on (spec FR-026).

**Checkpoint**: on the Mac, a hand save swaps the Scene within the SC-004 limits, no-op and
Dart-only reloads leave it alone, and a broken save keeps the game running.

---

## Phase 6: User Story 4 - Start, stop and clean up (Priority: P2)

**Goal**: start failures are reported, not waited on, and stopping always ends every process
the client started.

**Independent Test**: `ptest/` passes. On the Mac, quickstart §5 steps 7–8.

### Tests for User Story 4

- [X] T040 [P] [US4] Extend `ptest/play_client_test.dart` with the start failures (research R11):
  - a path with no `pubspec.yaml` throws `PlayStartException`, with a message naming the path and
    `pubspec.yaml`;
  - a path with no `macos/` names `macos/`;
  - a starter that throws `ProcessException('flutter', …, 'No such file or directory')` gives a
    `PlayStartException` naming `flutter` and the OS message;
  - `no_macos_target.txt` then `exit(1)` before `app.started` gives `PlayFailed(exitCode: 1)`,
    whose `outputTail` holds the tool's lines (at most 20, redacted), then `PlayStopped`;
  - `app.stop` with an `error` before `app.started` gives `PlayFailed` with that error.

  All of these run on a `MemoryFileSystem` (constitution V). No test touches the real disk.
- [X] T041 [P] [US4] Write the stop part of `ptest/play_session_test.dart` (`group('stop')`,
  `fake_async`):
  - `stop()` sends `app.stop` with `appId`; with `stop.txt` and an exit within 5 s no signal is
    sent and `PlayStopped(requested: true)` comes;
  - with no exit, `SIGTERM` is sent at 5 s and `SIGKILL` at 7 s;
  - `stop()` twice sends one `app.stop`;
  - `stop()` after the process exited does nothing;
  - with `crash.txt` and `exit(1)`, `PlayStopped(exitCode: 1, requested: false)` comes, the
    watcher is closed, and an in-flight `reload()` fails with a `StateError` naming the stopped session;
  - a second `PlayClient.start` after a stop works (US4 #4).

### Implementation for User Story 4

- [X] T042 [US4] In `proc/src/play_client.dart`, check `pubspec.yaml` and `macos/` through
  `fileSystem` before spawning, and map a `ProcessException` to `PlayStartException`. Make the first three cases of
  T040 pass.
- [X] T043 [US4] In `proc/src/play_session.dart`:
  - an exit or `app.stop(error)` before `app.started` emits `PlayFailed` with the exit code and
    `_tail`;
  - `stop()` is idempotent: it sends `app.stop` and escalates per research R10 with `Timer`s;
  - on exit it cancels the watcher, the timers and the pending requests (they fail with a
    `StateError` naming the stopped session), then emits `PlayStopped` and closes.

  Make T040 and T041 pass.
- [X] T044 [US4] In `app/bin/play.dart`, `SIGINT` and `SIGTERM` call `stop()` (`SIGTERM` is not
  watched on Windows), and the exit status follows the table in contracts/play-cli.md.
- [X] T045 [US4] (reference Mac) Run quickstart §5 steps 7–8 and keep the notes for T049. If an
  orphaned `pyro_example` process remains after a kill, record it and the fallback it needs (plan
  Risks).

**Checkpoint**: five start and stop cycles leave nothing running, and start errors exit 1 with
the path or compile error named.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T046 (reference Mac) Run quickstart §5.9, the release build check (FR-027), and §5.10:
  record real transcripts with `--record`, check that they hold no auth code, replace the
  hand-written files in `app/test/fixtures/daemon/` (adjusting tests only where the real format
  differs, noting each difference), update that folder's README, and rerun quickstart §1.
- [X] T047 [P] Add **Play session** and **Contract test** to `GLOSSARY.md` (plan § Documentation
  updates). This ships in the same PR as the code (constitution I).
- [X] T048 [P] Add Q117–Q124 to `dev-docs/decisions.md`, with the rows the plan lists: the CLI entry
  point, the contract job's OS split, the latency limit, no run link or re-point in the slice, the
  URI dropped, the 150 ms debounce with one reload in flight, the contract test failing on
  Runtime warnings, and the `specs/005-vertical-slice` mirror branch.
- [X] T049 Add a "Vertical slice" section to `dev-docs/ARCHITECTURE.md`, after "Runtime". It covers:
  - what was checked and on what machine;
  - the results of T025, T039, T045 and T046 (whether a save swaps on macOS, whether Dart-only
    reloads leave the Scene alone, the benchmark table, start and stop, the release check);
  - any workaround needed, as numbered findings;
  - the default Play target decision (SC-010).

  Where the same run covered spec 004's T038 and T043, update the Runtime section's open line.
  Steps that couldn't run are listed as to do.
- [X] T050 Update `dev-docs/project-plan.md` §9.3 (what the slice built: the daemon client, the
  debounce, redaction, no IDE workarounds yet), §13 ("Process clients" names the transcript
  fixtures), and §14 (the estimates of #11, #12 and #13 if they moved; plan Risks). In the same
  commit, update `dev-docs/phases.md`: tick Phase 3's items that are done; update the status line,
  the at-a-glance table and the "Left" counts; and close or carry over Phase 2's "Open" note
  (FR-028).
- [X] T051 Tick or annotate `specs/004-runtime/tasks.md` T038 and T043 and
  `specs/003-generator/tasks.md` T043 to match what T031, T039 and T046 did.
- [X] T052 Final pass. Run `dart format --set-exit-if-changed packages apps example`, both
  analyze steps of CI, `flutter test` in `apps/editor` and `example`, and quickstart §1–§3. Then
  re-read the diff against the constitution: no Flutter import in `proc/`, no auth code in any
  fixture or test output, every public member documented, glossary terms used.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T004 needs Flutter and can wait until it's available. Nothing in
  CI builds `macos/`.
- **Foundational (Phase 2)**: none on Setup (it is all in `apps/editor`). It blocks US3 and US4 only.
- **US1 (Phase 3)**: after T001–T003. T022 and T024 need Flutter, and T025 needs T004 and the Mac.
- **US2 (Phase 4)**: after US1's T022 (the golden copies the generated Manifest). T026, T028 and
  T029 can be written earlier.
- **US3 (Phase 5)**: after Foundational. T039 also needs US1 (the game it runs).
- **US4 (Phase 6)**: after Foundational. It can run alongside US3 except where both touch
  `play_session.dart` (T035 and T043): do T035 first.
- **Polish (Phase 7)**: T046 after T039 and T045. T049 after every Mac task. T050 and T051 after
  T049. T047 and T048 at any time, in the same PR.

### Within Each Story

- Tests and fixtures first, failing, then the implementation
- `daemon_message.dart`, `redact.dart` and `play_event.dart` before `play_session.dart`;
  `scene_watcher.dart` before the session's reload wiring; the session before the CLI and the
  benchmark
- Each story's checkpoint passes before its Mac task runs

### Parallel Opportunities

- Setup: T002, T003 (after T001)
- Foundational: T005–T007 together; T010–T012 together; then T013, T014
- US1 alongside Foundational: T015–T019 together
- US2: T026, T028, T029 alongside US1's T020–T021
- US3: T032 and T033 together; T037 alongside T036
- US4: T040 and T041 together, alongside US3's tests
- Polish: T047, T048

---

## Parallel Example: Foundational and User Story 1

```bash
# The client's leaf modules and the example game's classes, side by side:
Task: "Implement apps/editor/lib/process/src/redact.dart"
Task: "Implement apps/editor/lib/process/src/daemon_message.dart"
Task: "Implement apps/editor/lib/process/src/play_event.dart"
Task: "Write example/lib/behaviors/spin.dart"
Task: "Write example/lib/components/banner.dart"
```

## Parallel Example: User Stories 3 and 4

```bash
# Their tests, together:
Task: "Write apps/editor/test/process/scene_watcher_test.dart"
Task: "Write the reload group of apps/editor/test/process/play_session_test.dart"
Task: "Extend apps/editor/test/process/play_client_test.dart with start failures"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup
2. Phase 3: US1
3. **Stop and validate:** `example/` generates, its tests pass, and it runs on macOS under plain
   `flutter run`

### Incremental Delivery

1. Setup + US1 → a working sample game (MVP)
2. US2 → the contract is guarded in CI from here on (*Q88*)
3. Foundational + US3 → saves Hot-swap through Pyro's own client, timed on the Mac (the slice's
   reason to exist)
4. US4 → clean starts and stops, ready for the Play button
5. Polish → results recorded, phases.md updated, Phase 3 closed

### Without Flutter or the Mac

Foundational, US3 and US4 (except their Mac tasks), T001–T003, T015–T021, T023, T026, T028 and
T029 need no device and no running game: the client's tests replay transcripts (SC-009). Running
any test still needs Flutter, because `apps/editor` and `example/` are Flutter packages, so a
session without it can write that code but not verify it. These wait for a session with Flutter:
T004, T022, T024, T027, T030 and T031. These wait for the reference Mac: T025, T039, T045 and
T046.

---

## Notes

- [P] tasks touch different files and depend on no unfinished task
- Commit after each task or logical group, in Conventional Commits, citing the spec
  (`feat(process): … (spec 005, US3)`)
- Stop at any checkpoint to validate a story on its own
- The example's Scene and Manifest are compared byte for byte: never hand-edit generated files;
  regenerate
