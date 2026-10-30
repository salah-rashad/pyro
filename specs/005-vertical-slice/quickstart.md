# Quickstart: validating the Vertical Slice

How to check that spec 005 works. §1–§3 run anywhere Flutter 3.44.2 runs, including CI. §4–§5
need the reference Mac (macOS, Apple M4, Flutter 3.44.2). Commands assume the repository root
unless a directory is given. The details live in the contracts: see
[example-game.md](contracts/example-game.md), [contract-job.md](contracts/contract-job.md),
[play-client-api.md](contracts/play-client-api.md) and [play-cli.md](contracts/play-cli.md).

## Prerequisites

```bash
dart pub get
```

## §1. Play client tests (no device, no real `flutter run`)

```bash
cd apps/editor && flutter test test/process/
```

Expected: all pass. They cover:
- the daemon line parser on every transcript in `test/fixtures/daemon/`;
- auth code redaction, including the raw desktop VM service line;
- the state machine: start, start failures, reload ok and failed, stop, an unrequested exit and a
  crash with no `app.stop`;
- the debounce and the one-in-flight rule under `fake_async`: a burst of 10 changes gives ≤ 2
  reloads, saves while starting become one reload after `app.started`, and an atomic-rename event counts as a change;
- the stop escalation: `app.stop`, then SIGTERM, then SIGKILL;
- no event ever contains `wsUri` (SC-009, US3 #5–#7, US4).

## §2. Example game, as CI checks it

```bash
cd example
dart run build_runner build -d
git diff --exit-code -- lib/pyro.g.dart lib/pyro.manifest.json
diff -u test/goldens/pyro.manifest.json.golden lib/pyro.manifest.json
flutter analyze --fatal-infos . lib/pyro.g.dart
flutter test
```

Expected: no diff, no analysis issues, all tests pass, including `test/contract/` (US1 #1–#2,
US2 #1).

## §3. Each contract check fails where it should (SC-002)

On a scratch branch, one at a time, run §2 again and reset afterwards
(`git checkout -- example`):

| Break | Expected failure |
|---|---|
| Add a blank line to `lib/pyro.g.dart` | `git diff` step shows it |
| Change `"default": 0.25` in `test/goldens/pyro.manifest.json.golden` | `diff -u` step shows it |
| Rename `"type": "Spin"` to `"Spinner"` in `assets/scenes/level1.scene.json` | `test/contract/` fails naming `level1.scene.json`, Node `ship` and Type ID `Spinner` |
| Add `"speed": 3` to `ship`'s `Spin` Overrides (a field the code doesn't have) | `test/contract/` fails quoting the Runtime's unused-Override warning for `Spin.speed` (US2 #4) |
| Copy `level1.scene.json` to `assets/scenes/extra/level2.scene.json` (then declare `assets/scenes/extra/`) | `test/contract/` runs two Scene tests, with no test edit (US2 #5) |

Then push the branch and confirm the CI run shows the same failures in the step of the same
name, and the committed-files step passing on macOS, Windows and Linux (SC-003, FR-009a).

## §4. Run the example by hand (reference Mac)

```bash
cd example && flutter run -d macos
```

Expected: a window with the ship turning clockwise (the default from code) at half a turn per
second (the Override), its hitbox, the banner "Hello from Pyro" in white, and the HUD
`time: …s  swaps: 0  code: v1` (US1 #3–#5). Quit with `q`. Time from `dart pub get` on a clean
clone to the window is under 5 minutes (SC-001).

## §5. The slice end to end (reference Mac)

Record every result in `dev-docs/ARCHITECTURE.md`, section "Vertical slice" (FR-026).

1. **Play through the client.** Run
   `cd apps/editor && dart run bin/play.dart ../../example --record /tmp/start.txt`. The window
   opens. The CLI prints `started` and the game's `Scene loaded` line, and no line shows an auth
   code.
2. **Save by hand.** Open `example/assets/scenes/level1.scene.json`, change `turnsPerSecond` to
   `2` and the banner's `message`, and save. Within a second the ship spins faster and the banner
   changes. `swaps` goes to 1 and `time` keeps counting (US3 #2).
3. **Save with no change** (save again in the editor without edits, or `touch` the file). The CLI
   shows a reload, `swaps` stays the same, and the ship keeps its angle (US3 #3).
4. **Dart-only reload.** Change `codeMarker` to `'v2'` and type `r` in the CLI. The HUD shows
   `code: v2` and `swaps` doesn't change (US3 #4).
5. **A broken save.** Three times each: save invalid JSON, an unknown Type ID, and
   `"turnsPerSecond": "fast"`.
   Each time the game keeps the previous Scene and the CLI shows the Runtime's
   `couldn't Hot-swap` message naming the Scene, Node and type or field. A valid save recovers
   (US3 #6, SC-008).
6. **Timings.** Stop the CLI (`q`) and run
   `cd apps/editor && dart run benchmark/hot_swap_latency.dart ../../example`. Expected: SC-004
   median < 500 ms and worst < 1 s; SC-005 zero rebuilds; SC-006 ≤ 2 reloads with the last content
   shown. Paste its table into ARCHITECTURE.md.
7. **Start and stop.** Five times: start with `bin/play.dart`, then stop with `q` (three times),
   Ctrl-C (once) and by closing the window (once). After each, `pgrep -fl "flutter|pyro_example"`
   shows nothing from the run (US4, SC-007).
8. **Start errors.** Run `bin/play.dart` on `packages/pyro_generator/fixture_game` (no `macos/`)
   and on a copy of `example/` with a syntax error in `lib/main.dart`. Each exits 1 with a message
   naming the path or the compile error (US4 #3).
9. **Release build** (FR-027, spec 004 T043's release part):
   ```bash
   cd example && flutter build macos --release
   strings build/macos/Build/Products/Release/pyro_example.app/Contents/Frameworks/App.framework/App | grep -c "couldn't Hot-swap"
   ```
   Expected: `0`.
10. **Transcripts.** Replace the hand-written files in `apps/editor/test/fixtures/daemon/` with the
    recordings from steps 1, 5 and 7 (`--record`), check that no auth code is in them
    (`grep -E "/[A-Za-z0-9_-]+=/" …` finds only `<auth-code>`), and rerun §1.

If step 2 or 4 fails, record what happened and propose a default Play target for the author to
decide before Phase 4 (spec FR-026, SC-010).

The same session can close spec 004's T038 (its quickstart §5 steps 1–3 run here on
`example/`) and T043 (the benchmark on this Mac). Record which.
