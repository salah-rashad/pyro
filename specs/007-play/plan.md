# Implementation Plan: Play (Phase 5)

**Branch**: `specs/007-play` | **Date**: 2026-10-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-play/spec.md`

## Summary

Phase 5 puts **Play** in the editor window and finishes the loop Phase 3 proved from the command
line. It builds on the Play client of spec 005 (`PlayClient`, `PlaySession`, `SceneWatcher`,
`redactAuthCodes`) and the editor of spec 006 (shell, status bar, Type catalog). One work item,
§14's #11 (rest), plus the README recipe and the dry run.

The work splits into five parts, each a pure-Dart unit under `apps/editor/lib/process/` with a
thin Riverpod and `Pr` layer on top (the constitution's "features reach each other only through
providers"):

1. **Play orchestration.** A `PlayController` owns at most one `PlaySession` per project, runs it
   through the **run link** and **asset re-point** (§9.3, *Q74*) so Hot-swap survives an attached
   IDE, detects a failed Hot-swap from the Runtime's debug lines, reloads code once the generator
   is idle, and offers *Restart game* when an image in use changes.
2. **Generator supervisor.** Starts `build_runner watch` for the open project, probes build_runner's
   lock first, follows takeovers (*Q77*), and publishes one state for the status bar.
3. **Console.** One redacted, bounded, filterable log of generator, game and Pyro lines in the
   shell's `bottom` slot.
4. **Attach.** *Attach debugger* copies the current run's address; the address lives in memory
   inside the session and nowhere else (*Q81*).
5. **README recipe and dry run.** A root `README.md` with the recipe, and a written dry-run report.

One small change reaches outside `apps/editor/`: the Runtime prints a stable one-line report for
every Hot-swap outcome in debug builds (research R1), because the only "Scene reloaded" line that
exists today is printed by `example/`'s own code.

## Technical Context

**Language/Version**: Dart SDK `^3.12.0`, Flutter 3.44.2 stable (pinned by CI and *Q94*; reference
machine: macOS, Apple M4).

**Primary Dependencies**:

- Existing, unchanged: `flutter_riverpod` 3.3.2, `riverpod_annotation`, `freezed` for new immutable
  models, `file`, `clock`, `crypto`, `yaml`, `pyro_ui`, `pyro_runtime`, `fast_immutable_collections`.
- **New runtime dependency: `vm_service` ^15.4.0**, moved from `dev_dependencies` (where the
  benchmarks already use it). It carries the three VM service calls of the asset re-point
  (research R4). BSD-3, compatible with MIT distribution. It is the only dependency change; flagged
  in the Constitution Check.
- No new dependency in `packages/`.

**Storage**: none new in user projects. Pyro's application-support folder gains
`run/<project-id>/` holding the run link (a symlink, removed when the project closes).
`.dart_tool/pyro/vm_service.json`, `launch.json` and any other project file are **not** written
(FR-030).

**Testing**: `flutter test` in `apps/editor` and `dart test`-style units in `process/`
(no Flutter import). Recorded transcripts for the daemon (extend the `--record` fixtures: attached
IDE, hot restart, build failure, exit without Stop), recorded build_runner output for the generator
classifier, a real second process holding a real lock for the probe, a fake VM service for the
re-point, `fake_async` and `clock` for every timer (no wall-clock sleeps), widget tests for the
toolbar, Console and status bar, and the Runtime's loader tests for the new lines. Plus two manual
runs on the reference Mac (quickstart) and the dry run.

**Target Platform**: macOS first-class (the Play target); the Dart units and widget tests also run
on Linux and Windows in CI. The run link uses a symlink, which Windows only gets with Developer
Mode; Windows Play is v0.3.

**Project Type**: Flutter desktop app (`apps/editor`) in the pub workspace, plus one edit in
`packages/pyro_runtime`.

**Performance Goals** (constitution III, spec SC-002..SC-007):

- Save → game shows the change: median < 500 ms, worst < 1 s, with the run link and re-point, with
  and without an attached `flutter attach` client (the re-point adds one VM service round trip
  before each reload; it is measured, not assumed).
- Console: 5,000 lines in one second without a dropped frame (≤ 16 ms, profile mode). Lines enter a
  fixed-size ring buffer in O(1); the UI is told at most once per 50 ms, and the list is virtualized.
- Generator: a saved annotated file reaches the catalog in ≤ 5 s (spike #2 measured ~0.9 s, 2.8 s
  for the first save).
- Idle editor (SC-010): while the game is stopped, Play, the Console and the generator state register
  no animation ticker or per-frame callback. The generator's own child process, the Manifest watch and
  the 1 s lock re-probe while `build_runner` is external are not per-frame work and are allowed.
- Runtime loader (a hot path under constitution III): the three report lines are one `debugPrint`
  per load or Hot-swap, debug builds only, no per-frame work, absent from release builds.

**Constraints**: the app never imports user code (*Q7*); Play writes nothing into the user's
project (the existing rule, now also for `.dart_tool/`); the debugger address is never stored,
logged or shown except through *Attach debugger* (FR-024); all file I/O on the UI isolate is async;
the macOS target is the only Play target; no Settings window, so every setting is a constant in one
`PlayDefaults` class.

**Scale/Scope**: 1 work item (#11, rest, ~4 evenings in §14) + README (the "stands in for Add Pyro"
recipe) + dry run. About 10 new files in `process/`, 6 in the UI, 1 Runtime edit, 1 root README.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | How this plan complies | Verdict |
|---|---|---|
| I — Clean Code | Glossary words in UI text and code (**Play**, **Play session**, **Hot-swap**, **Attach**, **Generator**); new terms (**Console**, **Run link**, **Debugger address**, **External build_runner**, **Hot-swap report**) are added to `GLOSSARY.md` in the change that introduces them; models freezed or `final`; every error names what failed and where (a lock that cannot be probed, a link that cannot be made, a service call that failed); no `catch (_) {}` | PASS |
| II — Modular Boundaries | `process/` stays free of Flutter (so `bin/play.dart` still runs with `dart run`); Riverpod lives in `process/providers.dart`, a separate library the CLI does not import; `panels/console/` uses `Pr` components only and reaches `process/` through providers; the app still does not depend on `pyro_generator` (it only runs `build_runner` as a child process); the Runtime change is debug-only and inside its loader. **Flagged:** `vm_service` becomes a runtime dependency (R4) and `pyro_runtime` gets a small edit (R1) | PASS (flagged) |
| III — Performance by Design | Budgets above; Console ring buffer + throttled notification + virtual list; async lock probe; timers cancelled with the session; link, watchers and generator child process owned and released with the project (FR-022, SC-007); Hot-swap and the markers sit behind `kDebugMode` (release builds stay clean, checked by the existing release-build job) | PASS |
| IV — User Data Integrity | Play never edits the project; "Save and play" goes through `DocumentSession.save` (atomic, version-gated) and starts nothing if a save fails; the lock probe opens the lock file for append only when it already exists and never creates a file; a generator error never changes the catalog (last-good stays, *Q105*); a failed Hot-swap stops reloading rather than guessing | PASS |
| V — Tested Core | Daemon, generator output and redaction are tested from recorded transcripts; the probe against a real lock held by another process; the supervisor, controller and failure counter as pure state machines with `fake_async`; Runtime change covered by loader tests; contract job unchanged and must stay green; no real SDK, network or sleeps in unit tests | PASS |

**Spec 006 amendment.** Spec 006's FR-013 says Pyro never runs the generator. This phase replaces
that with "starts it only when none runs" (spec 007 FR-017). Spec 006 stays as built; the rule
change is recorded in `decisions.md` with the Phase 5 decisions.

**Re-check after design (Phase 1).** Unchanged: PASS on all five. What the design added that a
reader should see: the Riverpod layer is a separate library, so principle II holds for the CLI; the
lock probe is async and creates nothing, so III and IV hold; the one Runtime edit is debug-only and
covered by loader tests, so III and V hold; no project file is written, so IV holds. The two flagged
items are justified under Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/007-play/
├── plan.md              # This file
├── research.md          # Phase 0 output: decisions R1–R15
├── data-model.md        # Phase 1 output: states, lines, defaults, transitions
├── quickstart.md        # Phase 1 output: automated checks, reference-Mac runs, the dry run
├── contracts/
│   ├── play-orchestration.md   # PlayController, run link, re-point, failure rule
│   ├── generator-supervisor.md # lock probe, takeover table, output classes, idle rule
│   ├── hot-swap-reports.md     # the Runtime's debug lines (the one package change)
│   └── readme-recipe.md        # the recipe's contents and the dry-run report format
├── checklists/requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
README.md                          # NEW — project front page + "Add Pyro to a Flame project" recipe
apps/editor/
├── bin/play.dart                  # existing CLI; builds on the same PlayClient (kept as a developer tool)
├── lib/
│   ├── process/
│   │   ├── process.dart           # barrel — stays Flutter-free; exports the new units
│   │   ├── providers.dart         # NEW — Riverpod: playControllerProvider, generatorProvider, consoleProvider
│   │   └── src/
│   │       ├── play_client.dart   # EDIT — takes the run link; passes --project-root
│   │       ├── play_session.dart  # EDIT — keeps the address privately; re-point before reload; restart(); markers
│   │       ├── play_event.dart    # EDIT — adds PlayHotSwapFailed; no event carries the address
│   │       ├── redact.dart        # existing; covered by new transcripts
│   │       ├── play_defaults.dart # NEW — PlayDefaults: the constants of data-model.md
│   │       ├── play_block.dart    # NEW — why Play is disabled, in order
│   │       ├── generator_state.dart   # NEW — GeneratorState and its reasons
│   │       ├── run_link.dart      # NEW — <app support>/run/<project-id>/<name>-pyro symlink
│   │       ├── vm_service_link.dart   # NEW — listViews / setAssetBundlePath / evict over vm_service
│   │       ├── hot_swap_monitor.dart  # NEW — content baseline, report counting, failure rule
│   │       ├── play_controller.dart   # NEW — one session per project, Play/Stop, reload gating
│   │       ├── code_watcher.dart      # NEW — lib/**.dart saves → reload once the generator is idle
│   │       ├── image_use.dart         # NEW — images referenced by Scenes; changed-image detection
│   │       ├── build_lock.dart        # NEW — BuildLockProbe (async, no create, no .requested)
│   │       ├── generator_supervisor.dart  # NEW — state machine, takeover, Start button
│   │       ├── generator_output.dart  # NEW — table-driven classifier of build_runner lines
│   │       ├── console_line.dart      # NEW — ConsoleLine, ConsoleSource, severity
│   │       └── console_buffer.dart    # NEW — redact-on-entry ring buffer, filter, throttled changes
│   ├── project/
│   │   └── build_runner_version.dart  # NEW — resolved build_runner version from pubspec.lock (>= 2.14 gate)
│   ├── app/
│   │   ├── shell.dart             # EDIT — toolbar and bottom slots, generator status item, quit check
│   │   ├── status_bar.dart        # NEW — the shell's status bar, extracted so it can be tested
│   │   ├── play_toolbar.dart      # NEW — Play/Stop, state, Attach debugger, unsaved-changes question
│   │   ├── attach_guide.dart      # NEW — the VS Code / Android Studio guide dialog
│   │   └── play_notices.dart      # NEW — toasts: image changed, Hot-swap failed, game stopped
│   └── panels/
│       └── console/               # NEW — ConsolePanel on Pr components (filter, clear, virtual list)
├── benchmark/
│   ├── hot_swap_latency.dart      # EDIT — run link + re-point, with a `flutter attach` stand-in IDE
│   └── console_throughput.dart    # NEW — 5,000 lines/s into the buffer, frame-time check
└── test/
    ├── process/                   # NEW: run_link, vm_service_link, hot_swap_monitor, play_controller,
    │                              #      code_watcher, image_use, build_lock, generator_supervisor,
    │                              #      generator_output, console_buffer; EDIT: play_session, redact
    ├── app/                       # NEW: play_toolbar, attach_guide, play_notices, status bar item
    ├── panels/console/            # NEW: console_panel widget tests
    └── fixtures/transcripts/      # NEW: recorded daemon and build_runner output (ide-attached, restart,
                                   #      build-failure, exit-without-stop, takeover, stop)
packages/pyro_runtime/
└── lib/src/loader/pyro_scene.dart # EDIT — three debug-only report lines (loaded, reloaded, not reloaded; kDebugMode), tests in test/loader/
example/
└── lib/example_game.dart          # EDIT — drops its own "Scene reloaded" print (the Runtime prints it now);
                                   #        the benchmark and quickstart wait for the Runtime's line
docs/                              # GLOSSARY.md (root), decisions.md (Q125–), phases.md, ARCHITECTURE.md,
                                   # project-plan.md §9 note — updated in the same commits
specs/007-play/dry-run-report.md   # written during the dry run (FR-033)
```

**Structure Decision**: all orchestration lives in `process/` as pure Dart so it is testable with
fakes and usable by the CLI; the Riverpod layer is one extra library beside it; the Console is a
panel in `panels/` next to the hierarchy and inspector; the toolbar, guide and notices belong to the
editor window and go in `app/`. The constitution's six folders are unchanged. `example/` loses its
own report print because the Runtime now owns the marker, which also keeps the contract test
meaningful (R1).

## Complexity Tracking

No violations. Two items are called out per constitution II ("a change that adds a package
dependency or crosses a boundary MUST say so"):

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| `vm_service` as a runtime dependency of the app | The asset re-point calls `_flutter.listViews`, `_flutter.setAssetBundlePath` and `ext.flutter.evict` over the VM service before every reload, and a `flutter attach` stand-in test needs the same client | A hand-written WebSocket JSON-RPC client was rejected: it repeats request ids, error mapping, stream shutdown and reconnect rules that `vm_service` already tests, for the cost of a package the repository already resolves |
| `pyro_runtime` prints three debug-only report lines | FR-011 needs a signal that exists in every game; today the only such line is printed by `example/`'s code, so a tester's game would never show it | Reading the line from each game's own code was rejected: it cannot work in a tester's game. Asking the VM service for a rebuild count was rejected: it needs a Runtime service extension (*Q66* chose none) for the same effect as one line |
