# Quickstart: validating Play (Phase 5)

Three layers, cheapest first. Layers 1 and 2 run in CI (macOS, Windows, Linux) with no device,
game or window. Layer 3 needs the reference Mac. Success criteria come from
[spec.md](spec.md); contracts are in [contracts/](contracts/).

**Prerequisites:** the repository at its root, `dart pub get` done once, Flutter 3.44.2 on `PATH`
(`export PATH="$PATH:/Users/salah/Library/flutter/bin"`), Xcode on the Mac.

## 1. Automated, no device

From `apps/editor`:

```bash
flutter test test/process test/app test/panels/console
```

| Group | Proves | Spec |
|---|---|---|
| `test/process/play_session_test.dart` (extended) | recorded daemon transcripts: attached-IDE run, hot restart, build failure, exit without Stop; the re-point order and its fallback against a fake VM service | FR-007..010, FR-035 |
| `hot_swap_monitor_test.dart` | no false failure on unchanged bytes or unannounced Scenes; two misses fail; a report resets; *Restart game* re-arms | FR-011 |
| `play_controller_test.dart` | one session per project, the four phases, the disabled reasons in order, "Game stopped", stop always ends Stopped | FR-001..005, FR-014, FR-016 |
| `build_lock_test.dart` | held / free / absent against a real lock held by a `dart` helper process; no file created | FR-017, FR-036 |
| `generator_supervisor_test.dart` | start, external, both rows of the takeover table, stop with *Start*, error keeps the catalog, dispose leaves an external run alone | FR-017..022 |
| `code_watcher_test.dart` | reload waits while generating; external settle rule (2 s after the last generated-file change, or 2 s after the save) | FR-012 |
| `image_use_test.dart` | only images a Scene names raise the notice | FR-013 |
| `console_buffer_test.dart`, `redact_test.dart` | redaction on entry from every source and shape in the transcripts; ring bound; filter; throttle | FR-023..025, FR-037 |
| `play_toolbar_test.dart`, `attach_guide_test.dart`, `play_notices_test.dart` | Play/Stop states, "Save and play" / "Play without saving" / dismiss, Attach copies and never shows the address, the guide's three facts | FR-006, FR-027..029 |
| `console_panel_test.dart` | filter, clear, follow-the-tail | FR-023 |

From `packages/pyro_runtime`:

```bash
flutter test test/loader
```

Proves the three report lines of [hot-swap-reports.md](contracts/hot-swap-reports.md). That nothing
prints in release mode is checked on the release build (tasks T080).

From the repository root, the contract job's commands (unchanged) must still pass with `example/`
no longer printing its own reload line.

## 2. Benchmarks (reference Mac)

From `apps/editor`:

```bash
dart run benchmark/hot_swap_latency.dart ../../example
dart run benchmark/hot_swap_latency.dart ../../example --with-attach
dart run benchmark/console_throughput.dart
```

| Run | Pass | Spec |
|---|---|---|
| `hot_swap_latency` | median < 500 ms, worst < 1 s over ten saves, with the run link and re-point | SC-002 |
| `--with-attach` (a `flutter attach` process stands in for the IDE and reproduces the DevFS clash) | the same limits; ten no-change saves and ten code-only reloads rebuild the Scene 0 times | SC-002, SC-003 |
| `console_throughput` | 5,000 lines/s for 10 s stay inside the buffer bound; cost per line reported | SC-006 (the frame check is in step 3.6) |

## 3. Manual run on the reference Mac

### 3.1 Play and Hot-swap in `example/`

1. `cd apps/editor && flutter run -d macos`, open `example/`, open `assets/scenes/level1.scene.json`.
2. Status bar shows the SDK, the Runtime result and **Generating…** then **Up to date**.
3. Press **Play**. The state goes Starting → Running; the game opens; the Console shows the build and
   `[pyro] Scene loaded: assets/scenes/level1.scene.json`.
4. Move the ship and change the Spin Behavior's turns per second. Save. The game shows the change
   in under a second and the Console shows `[pyro] Scene reloaded: …`. (SC-002)
5. Press **Stop**. With the game stopped, change something and leave it unsaved, then press **Play**:
   the question "Save and play" / "Play without saving" appears; check both answers and that
   dismissing it starts nothing. (FR-006)
6. Press **Stop** again. The game closes, Play returns, `ps` shows no `flutter` or game process. (SC-007)

### 3.2 Attach VS Code and keep Hot-swapping

1. Play. Press **Attach debugger**; a toast says it was copied and the guide opens. Search the screen,
   the Console and `~/Library/Application Support/<Pyro>/` for the pasted address's auth code:
   nothing (SC-005).
2. In VS Code (Dart-Code): select the macOS device in the status bar, "Flutter: Attach to Process",
   paste. Set a breakpoint in the Behavior; it hits.
3. Reload code from VS Code, then save a Scene change in Pyro: the game shows the change. Hot-restart
   from VS Code, save another change: same. Ten saves, median < 500 ms. (SC-002, FR-010)
4. Stop and Play again, press **Attach debugger**: the new address is copied, not the old one. (FR-028)

### 3.3 The generator

1. Add an annotated Behavior to `example/lib/` in the IDE and save: it appears in the inspector's
   Add list within 5 s (SC-004); existing Behaviors are undisturbed.
2. Run `dart run build_runner watch` in a terminal: Pyro's status bar changes to **External
   generator** with no error. Stop it: Pyro starts its own again.
3. Run `dart run build_runner stop`: **Generator stopped** with a *Start* button; nothing restarts.
4. Run `dart run build_runner build` while Pyro's own run is active: External, then Pyro's own again
   when it ends. (FR-019; SC-008 ten attempts, the user's run always finishes.)
5. Introduce a Dart syntax error in an annotated class: status bar and Console name the file; the
   catalog keeps its last types.

### 3.4 Stops, images, quit

1. Play, close the game's window by hand: Console "Game stopped", Play available in under a second.
2. Play, replace an image a Scene uses: the *Image changed* notice with **Restart game**; use it, see
   the new image. Replace an image no Scene uses: no notice.
3. Play, then ⌘Q: Pyro asks to stop the game first; on yes the game closes; on no nothing changes.
4. Play, force-quit Pyro (`kill -9`), reopen: no "Running" is shown; the leftover run link is gone;
   Play starts a new game. (The old game window is closed by hand.)

### 3.5 A failed Hot-swap

No manual run: the failure rule is covered by `hot_swap_monitor_test.dart` and the fake VM service
(FR-011). On each new Flutter stable, run 3.2 again; if saves stop reaching the game, this notice is
what the user must see.

### 3.6 Frame check

Profile build (`flutter run -d macos --profile`), a game that prints 5,000 lines in one second:
the DevTools timeline shows no frame over 16 ms while the Console follows the tail. (SC-006)

## 4. The dry run (closes the phase)

Follow [contracts/readme-recipe.md](contracts/readme-recipe.md) in a Flame project the author did
not write and Pyro was not built against (a project from the Flame examples if none). Use only the
README. Do the tester task:

1. Open the project in Pyro.
2. Place an entity with a sprite and a hitbox.
3. Attach a custom Behavior and tweak its fields.
4. Press Play and see the change in the running game.
5. Attach VS Code with the copied address and Hot-swap again.

Write `dry-run-report.md` as the contract describes. Repeat after each fix until an attempt passes
without help. The time from the first README step to the first running scene is recorded and does
not decide the verdict.

## 5. After it passes

- Tick Phase 5 in `docs/phases.md` and the status line; add the verified behavior and the
  measurements to `docs/ARCHITECTURE.md` ("Play"); record decisions Q125– in `docs/decisions.md`;
  add the new terms to `GLOSSARY.md`.
- Re-run the vertical slice's checks (`benchmark/hot_swap_latency.dart` limits from spec 005) and
  the contract job: they must still pass.
