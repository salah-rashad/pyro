# Implementation Plan: Vertical Slice

**Branch**: `specs/005-vertical-slice` (mirrored from this session's
`claude/gallant-galileo-0xv2k7`, see Risks) | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-vertical-slice/spec.md`

## Summary

Phase 3 joins the data contract end to end, with no editor UI:

- **`example/`** (item 13's skeleton), a workspace member and minimal Flame game. It has one
  Behavior (`Spin`: `double`, `bool`), one Custom component (`Banner`: `String`, `Color`), one
  canonical Scene, the committed Registry and Manifest, a macOS runner, and a HUD that makes
  Hot-swaps visible (research R12).
- **The contract test** (#12). The `contract` job replaces its TODO with five named steps on
  Linux: generate, `git diff` the committed files, `diff` the Manifest against its golden, load
  every discovered Scene with `flame_test` (failing on Runtime warnings too), and analyse
  `example/`. The committed-files check also joins the
  three-OS matrix, which closes spec 003's cross-system check (R13).
- **The first slice of Play** (#11). The app's `process/` feature gets a Flutter-free
  `PlayClient`. It spawns `flutter run --machine -d macos`, parses the daemon's messages, masks
  auth codes, watches `assets/scenes/`, and turns settled changes into one `app.restart` at a
  time. A thin CLI, `apps/editor/bin/play.dart`, drives it (R2–R11). A benchmark script measures
  SC-004–SC-006 on the Mac (R14).

It ends with a manual run on the reference Mac (quickstart §5), recorded in
`dev-docs/ARCHITECTURE.md`. That run decides whether macOS stays the preview's default Play target.

## Technical Context

**Language/Version**: Dart ^3.12, Flutter 3.44.2 (the repository's pin, Q94)

**Primary Dependencies**: `example/`: `flame` (>=1.36 <2), `flame_behaviors` ^1.4.0,
`pyro_runtime`, `pyro_annotations`; dev `pyro_generator`, `build_runner` ^2.15.1, `flame_test`,
`flutter_lints`, the same as `fixture_game`. `apps/editor`: **no new dependency**. The client uses
`dart:io` plus the existing `clock` and `file` (a `FileSystem` seam), and, in tests,
`fake_async` and `MemoryFileSystem` (R1, R3).

**Storage**: none new. The client writes nothing in the project (FR-020). `example/` reads its
Scene and image through the bundle.

**Testing**: `flutter test` in `apps/editor/test/process/` against transcript files and a fake
process and watcher (constitution V, R6). `flutter test` in `example/`, including
`test/contract/`. CI steps per contracts/contract-job.md. A latency benchmark script and a manual
end-to-end check on the reference Mac (quickstart §5).

**Target Platform**: the client and CLI run on macOS (Pyro's v0.1 platform). Their tests run on
all three CI OSes. `example/` targets macOS only. The contract job runs on Linux.

**Project Type**: a sample app plus a CI job plus one app feature (a process client) with a CLI

**Performance Goals**: save to visible change, median < 500 ms and worst < 1 s over ten saves
(SC-004); zero rebuilds on no-op and Dart-only reloads (SC-005); ≤ 2 reloads for a 10-save burst
(SC-006); contract job < 3 min warm (SC-003)

**Constraints**: the client imports no Flutter or Riverpod (so it runs from `dart run`); no VM
service URI in any event, log or exception (FR-021, R5); no files written in the user's project
(FR-020); no IDE workarounds (R9); `example/` runs under plain `flutter run` (FR-007)

**Scale/Scope**: one sample game (2 annotated types, 4 Nodes, 1 image); 9 daemon messages; 4 CI
steps plus 2 matrix steps; ~6 transcripts

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Pre-research | Post-design |
|---|---|---|---|
| I. Clean Code | Glossary names; documented public API; errors name what and where; immutable values; no dead or speculative code | ✅ | ✅ events and results are immutable (data-model.md); `PlayStartException`, `PlayFailed` and `PlayReloadFailed` name the path, executable, exit code and output tail; the seams (`ProcessStarter`, `DirectoryWatcher`) each have a test double and a real implementation; the CLI's future (kept or removed) is set by FR-025; new glossary terms below |
| II. Modular Boundaries | App never imports or runs user code; feature folders; no new dependency without saying so | ✅ | ✅ the client starts `flutter run` as a child process and reads only its protocol (*Q7*); it lives in `lib/process/` behind `process.dart`; no dependency added (R1); `example/` depends only on the published packages' public APIs, as a developer's game would |
| III. Performance by Design | Budget stated and measured; feedback latency; no blocking I/O on the UI isolate; resources released | ✅ | ✅ SC-004 budget with the benchmark (R14); a 150 ms debounce chosen against it (R8); all I/O async; the watcher, timers and process are released on stop (R10); process-output parsing is per line and cheap, and moves off the UI isolate in Phase 4 if profiling asks |
| IV. User Data Integrity | Pyro never rewrites user data; atomic writes | ✅ | ✅ the client writes nothing in the project (FR-020); the benchmark rewrites `example/`'s own Scene atomically and restores it, and it never runs on a user project by default; `example/`'s Scene is canonical (FR-003) |
| V. Tested Core | Contract test green; process clients tested against recorded transcripts, never a real SDK; deterministic | ✅ | ✅ the contract job is this feature (R13); client tests replay transcripts through a fake process, with `fake_async` for timers, a `MemoryFileSystem` for every file check, and a pushed event stream for file changes (R3, R6–R8), so no client test touches the real disk or clock; real recordings replace the hand-written transcripts on the Mac (quickstart §5.10) |

Technology constraints: Flutter stable 3.44.2 ✅; no `dart:mirrors` ✅; uses the user's installed
SDK, `flutter` on `PATH` or `--flutter` (*Q39*) ✅; MIT-compatible ✅ (nothing added; the image is
drawn for the repository).

Workflow: the spec-branch rule is met. The work is on `specs/005-vertical-slice`, which mirrors
this session's assigned branch commit for commit (see Risks).

**Result:** passes, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/005-vertical-slice/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R15
├── data-model.md              # Phase 1: PlayClient, PlaySession states, PlayEvent, example state
├── quickstart.md              # Phase 1: how to validate (§1–§3 anywhere, §4–§5 on the Mac)
├── contracts/
│   ├── play-client-api.md     # process.dart's public surface
│   ├── play-cli.md            # bin/play.dart usage, output, exit codes
│   ├── example-game.md        # example/'s types, Scene, log lines, HUD
│   └── contract-job.md        # the CI steps and their local commands
├── checklists/
│   └── requirements.md        # Spec quality checklist
└── tasks.md                   # Phase 2 (/speckit-tasks; not created here)
```

### Source Code (repository root)

```text
pubspec.yaml                                 # workspace: + example
.gitattributes                               # + example/lib/pyro.*, example/assets/**, example/test/goldens/** -text
.github/workflows/ci.yml                     # analyze-test: + example steps; contract: the five steps

example/
├── pubspec.yaml                             # pyro_example (contracts/example-game.md)
├── analysis_options.yaml                    # includes the root options, like fixture_game
├── README.md                                # run it, regenerate, update the golden, image licence
├── macos/                                   # flutter create --platforms=macos (on a machine with Flutter)
├── assets/
│   ├── images/ship.png                      # 32×32, drawn by tool/draw_ship.dart
│   └── scenes/level1.scene.json             # canonical, hand-written
├── lib/
│   ├── main.dart                            # GameWidget(game: ExampleGame())
│   ├── example_game.dart                    # loads the Scene, HUD, onReloaded log line
│   ├── code_marker.dart                     # const codeMarker = 'v1'
│   ├── behaviors/spin.dart                  # @PyroBehavior Spin
│   ├── components/banner.dart               # @PyroComponent Banner
│   ├── pyro.g.dart                          # generated, committed
│   └── pyro.manifest.json                   # generated, committed
├── test/
│   ├── contract/scenes_test.dart            # every assets/scenes/**/*.scene.json with pyroRegistry
│   ├── goldens/pyro.manifest.json.golden
│   └── example_game_test.dart               # the game loads; HUD counts a reload (onHotReload driven)
└── tool/draw_ship.dart                      # writes assets/images/ship.png

apps/editor/
├── README.md                                # + "Play from the command line" (FR-025)
├── bin/play.dart                            # the CLI (contracts/play-cli.md)
├── benchmark/hot_swap_latency.dart          # SC-004–SC-006 on the Mac (R14)
├── lib/process/
│   ├── process.dart                         # public library (contracts/play-client-api.md)
│   └── src/
│       ├── play_client.dart                 # PlayClient, start checks, spawn (R3, R11)
│       ├── play_session.dart                # state machine, requests, stop escalation (R8, R10)
│       ├── play_event.dart                  # PlayEvent hierarchy, ReloadResult, PlayState
│       ├── daemon_message.dart              # line → DaemonEvent | DaemonResponse | RawLine (R4)
│       ├── redact.dart                      # redactAuthCodes (R5)
│       └── scene_watcher.dart               # filter, debounce, coalesce (R7, R8)
└── test/
    ├── fixtures/daemon/*.txt                # transcripts (R6); -text in .gitattributes
    └── process/
        ├── fake_process.dart                # replays a transcript, records stdin, controllable exit
        ├── daemon_message_test.dart
        ├── redact_test.dart
        ├── play_session_test.dart           # lifecycle, reload ok/failed, stop, crash
        ├── scene_watcher_test.dart          # debounce, one in flight, atomic rename, pre-start drop
        └── play_client_test.dart            # start checks, ProcessException, early exit
```

**Structure Decision**: `example/` sits at the root, where project-plan §5 draws it, as a pub
workspace member like `fixture_game`. The client goes in the app's `process/` feature
(constitution II's feature list, §9.3). It is split so that each research decision has one file
and one test file. Parsing (`daemon_message.dart`) and redaction (`redact.dart`) are pure
functions. Only `play_session.dart` holds state. The CLI and the benchmark are the feature's two
callers in this slice. The Play button's provider is the third, in Phase 4.

### Documentation updates in the same change

- `GLOSSARY.md`: add **Play session** (one run of the game from Play to stop; *Avoid*: run,
  launch) and **Contract test** (the CI check that `example/`'s generated files and Scenes still
  agree with the Generator and the Runtime).
- `dev-docs/decisions.md`, from Q117:
  - the client's entry point is a CLI in `apps/editor/bin/` until the Play button (spec
    Clarifications);
  - the contract job's committed-files check runs on all three OSes, and the golden and Scene
    checks on Linux (spec Clarifications);
  - the Hot-swap latency limit: median < 500 ms and worst < 1 s over ten saves (spec
    Clarifications);
  - the slice runs without the run link and asset re-point (R9);
  - the client drops the VM service URI rather than keeping it (R5);
  - the debounce is 150 ms with one reload in flight (R8);
  - the contract test fails on any Runtime warning as well as on errors (R13; spec analysis
    finding I1);
  - spec 005 runs on a `specs/005-vertical-slice` mirror of the session branch (Risks).
- `dev-docs/project-plan.md`: §9.3 notes what the slice built (daemon client, debounce, redaction);
  §13 "Process clients" names the transcript fixtures; §14 updates the estimates of #11, #12
  and #13 if they moved.
- `dev-docs/phases.md`: tick Phase 3's items, update the status line and counts, and close or carry
  over Phase 2's "Open" notes (FR-028), in the same commit as any §14 change (sync rule).
- `dev-docs/ARCHITECTURE.md`: a new "Vertical slice" section with the manual results, the benchmark
  table and the release check (FR-026, FR-027), plus whichever of spec 004's T038 and T043 the
  same run closes.
- `specs/003-generator/tasks.md` T043 and `specs/004-runtime/tasks.md` T038 and T043: tick them, or
  note what this slice did for them.

## Risks

- **No Flutter in the planning session.** The daemon message shapes come from spike #1's driver
  and findings, not a run here. Hand-written transcripts may differ from 3.44.2's real output in
  detail, such as field order or extra events. The client treats unknown messages as output
  (R4), and quickstart §5.10 swaps in real recordings, so a difference fails a test rather than
  the slice.
- **`macos/` needs Flutter.** `flutter create --platforms=macos` must run in a session that has
  Flutter (an earlier container had it, and the Mac does). If the implementing session lacks it,
  that task waits for the Mac, and CI is unaffected (the contract job doesn't build macOS).
- **macOS Hot-swap through Pyro's own client is unproven.** That is the point of the slice.
  If it fails, record the failure, propose a default Play target, and stop before Phase 4
  (spec FR-026).
- **Orphaned macOS app.** If `flutter run` is killed after the timeout, the `.app` may keep
  running (R10). The manual check looks for it. The fallback, killing the process group or finding the
  app by its bundle path, is decided then from what the check sees.
- **FSEvents latency and coalescing.** FSEvents batches events, by default with up to ~100 ms of
  latency in `dart:io`'s use. Added to the 150 ms debounce, that still fits SC-004's median, and
  the benchmark measures it. If the median fails, shorten the debounce before anything else.
- **Branch rule.** The constitution asks for `specs/005-vertical-slice`. This session was told to
  push to `claude/gallant-galileo-0xv2k7`, so every push goes to both branches with the same
  commits, and the PR opens from `specs/005-vertical-slice`. Delete the session branch after the
  merge.
- **Estimate.** Phases.md gives the slice ~1.5 evenings (0.5 + 1, with #11's slice inside #11's
  4). The client with its tests, the benchmark and the CLI are closer to 1.5 on their own, which
  makes ~2.5–3 for Phase 3. Update §14 and phases.md when the slice is done, not before.

## Complexity Tracking

No constitution violations to justify.
