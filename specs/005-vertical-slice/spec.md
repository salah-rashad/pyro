# Feature Specification: Vertical Slice

**Feature Branch**: `specs/005-vertical-slice`

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "Phase 3 — Vertical slice (dev-docs/phases.md): an `example/` Flame game
in the workspace (one annotated Behavior, one custom component, one hand-written Scene JSON,
loaded through PyroScene and the generated Registry, macOS target enabled); #12 CI contract test
(run the generator on example/, check committed Registry and Manifest via git diff on Flutter
3.44, check Manifest against golden, load every example/ scene with flame_test against the real
Registry); first slice of #11 (Pyro's `flutter run --machine` client starts example/ on macOS,
saving the Scene JSON triggers app.restart and the scene hot-swaps, Dart-only reload leaves it
alone). Done when editing example/'s Scene JSON by hand and saving swaps the scene on macOS,
Dart-only reloads don't rebuild it, and the contract job passes."

## Overview

Phase 2 built both sides of the data contract: the Scene format, the Document model, the
Generator and the Runtime. Each was tested alone, with fixtures and hand-written Registries. The
vertical slice joins them for the first time, with no editor UI: a hand-written Scene JSON goes
through the real Generator, the real Runtime and a real Play on the macOS desktop target, and a
save swaps the scene in the running game (project-plan §14, *Q88*; phases.md Phase 3).

It delivers three things that only mean something together:

1. **`example/`**, a minimal Flame game in the workspace that uses Pyro the way a developer's
   game would: one annotated Behavior, one Custom component, one Scene file, the generated
   Registry and Manifest, and the macOS target.
2. **The contract test in CI** (#12, *Q59*), which from now on regenerates `example/`'s Registry
   and Manifest, checks them, and loads every `example/` Scene against the real Registry. A
   change to the Generator, the Runtime or the Scene format that breaks the contract fails CI.
3. **The first slice of Play** (#11): Pyro's own client for `flutter run --machine` starts
   `example/` on macOS and, when the Scene file is saved, asks the running game to hot-reload
   so the Scene swaps. It is the "verify Hot-swap on macOS" check that §9.3 and *Q82* left open:
   spike #1 proved the mechanism on macOS, iOS and Android with a throwaway driver (macOS reload
   ~58 ms), but Pyro's own client has not run it yet.

The slice also makes the author the first user of the whole loop, before any editor panel exists.
If macOS Hot-swap turns out not to work, the slice's result is the evidence for choosing the
preview's default Play target before Phase 4 starts.

**Who uses it**

- **Pyro's author** (and later, testers): runs `example/` through Pyro's client, edits the Scene
  JSON by hand, and watches the running game change.
- **CI**: runs the contract job on every push and pull request.
- **Later work**: the editor (Phase 4) builds its Play button and Console on the client this slice
  starts (#11, rest); the README recipe and the testers' dry run (Phase 5) reuse `example/` as the
  reference for what a working project looks like.

**Out of scope** (separate items): any editor UI, the Console panel, URI redaction and Attach
(#11, rest); the build_runner watcher, the lock probe and automatic code reload (#11, rest); the
run link and asset re-point that keep Hot-swap working with an IDE attached (§9.3, *Q74*); the
device list and emulator boot; the full sample game (item 13, v0.1); anything on Windows or Linux.

## Clarifications

### Session 2026-10-22

- Q: How does a user start Pyro's client for `example/` before the editor window exists? →
  A: With a small command-line entry point in the app package (`apps/editor/bin/`), run from the
  workspace with the project path as its argument. It prints the client's lifecycle events and the
  game's output lines, and stops the game on Ctrl-C. It exists so the slice can be run and timed
  by hand on the Mac; the Play button of Phase 4 reuses the same client, and the entry point is
  then either kept as a documented developer tool or removed (FR-025).
- Q: Does the contract job run on Linux only, or on all three desktop systems? → A: It runs on
  Linux. Its committed-files check (regenerate `example/`'s Registry and Manifest, then compare
  with the committed copies) also runs on macOS and Windows, because that is the output that
  could differ by system. The Manifest golden and Scene-loading checks run on Linux only. This
  also closes spec 003's open cross-system check (T043, SC-003).
- Q: What is the pass limit for the delay from saving a changed Scene to seeing it in the running
  game? → A: Over ten saves on the reference Mac, the median is under 500 ms and the worst is
  under 1 s.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A working example game (Priority: P1)

The author opens the workspace and finds `example/`. It is a small Flame game that uses every
part of Pyro's contract once. It has one Behavior with a few Editable fields, one Custom component
with a few Editable fields and a Scene file, `level1.scene.json`, that places an entity, a sprite
and a hitbox, attaches the Behavior and the Custom component, and sets some Overrides. The game
loads the Scene through `PyroScene.load` with the generated Registry. Running it on macOS shows
the entity where the Scene put it, and the Behavior's Override values are visible in the game (a
speed that moves the entity, a colour on the hitbox, or text on screen), so a change to the
Scene is visible at a glance.

**Why this priority**: every other part of the slice needs a project to run on. It is also the
first test that a real game (not a fixture) can follow the §6 workflow: annotate, generate, load.

**Independent Test**: run `dart pub get` in the workspace, generate the Registry and Manifest in
`example/`, and run the game's tests. Then start the game on macOS by hand with `flutter run`
and see the Scene.

**Acceptance Scenarios**:

1. **Given** a fresh clone of the repository, **When** the workspace is resolved and the
   generator is run in `example/`, **Then** it produces the Registry and the Manifest with no
   errors and no warnings, and the Manifest lists the Behavior and the Custom component with
   their Editable fields.
2. **Given** `example/`, **When** the game's analysis runs with the workspace's shared rules,
   **Then** it passes with no issues, including on the generated Registry (it is committed, so
   it is analysed like the rest).
3. **Given** `example/`'s Scene file, **When** the game starts on macOS, **Then** the Scene loads
   through `PyroScene.load` and the generated Registry and the entity, the sprite, the hitbox,
   the Behavior and the Custom component all appear and act as the Scene says.
4. **Given** a Behavior Override in the Scene, **When** the game runs, **Then** the effect of the
   Override is visible to a person watching the window, and a field without an Override shows its
   default from code (ADR 0003).
5. **Given** the game running on macOS, **When** a developer attaches an IDE or runs
   `flutter run` themselves, **Then** it behaves as any Flutter game does. `example/` needs
   nothing from the Pyro app to start.

---

### User Story 2 - The contract is checked on every push (Priority: P1)

A contributor changes the Generator's output, the Scene format or the Runtime's loader. CI's
contract job regenerates `example/`'s Registry and Manifest, compares them with the committed
copies, compares the Manifest with its golden file, and loads every Scene under `example/`
against the real Registry. If the change altered what the Generator writes, or made a Scene stop
loading, the job fails and says which of the four checks broke. If nothing changed, the job
passes.

**Why this priority**: the point of the vertical slice in CI is that the data contract between
the two halves of Pyro is guarded from now on (*Q59*, *Q88*). Without it the first change to
either half can break the other unnoticed, as the three spikes' hand-run checks would.

**Independent Test**: on a clean checkout run the four checks locally (as CI does) and see them
pass. Then break each one on purpose (edit the committed Registry, edit the Manifest golden,
rename a Behavior field a Scene overrides) and see the matching check fail with a clear message.

**Acceptance Scenarios**:

1. **Given** the repository as committed, **When** the contract job runs on a clean checkout,
   **Then** it passes.
2. **Given** a change to the Generator that alters the Registry or the Manifest `example/`
   produces, **When** the job runs, **Then** it fails at the check of the committed files, and
   the failure shows the difference.
3. **Given** a change to the annotated Behavior's field list that is not matched by a new
   golden Manifest, **When** the job runs, **Then** it fails at the Manifest golden check.
4. **Given** a Scene in `example/` that overrides a field the code no longer has, or names a
   Type ID the Registry doesn't hold, **When** the job runs, **Then** it fails at the Scene check
   with the Runtime's own error or warning (naming the Scene, the Node and the Type ID or field).
   The Runtime loads a Scene with an unused Override and only warns (spec 004 FR-012), so the
   Scene check treats any Runtime warning as a failure.
5. **Given** a second Scene file added to `example/`, **When** the job runs, **Then** that Scene
   is checked too, with no change to the job.
6. **Given** the committed-files check running on macOS, Windows and Linux, **When** each
   regenerates the Registry and Manifest, **Then** all three match the committed files byte for
   byte (SC-003 of spec 003: the same output on every system).
7. **Given** a repository whose Flutter version has moved to a release where `build_runner`
   offers its own "is the generated output up to date" check, **When** the project owner
   follows the note in the job, **Then** they can switch the check of the committed files to it
   without changing the other three (§7.3, *Q76*).

---

### User Story 3 - Saving the Scene swaps it in the running game (Priority: P1)

The author starts `example/` on macOS with Pyro's client. The game window opens and shows the
Scene. They open `level1.scene.json` in a text editor, change the entity's position and a
Behavior Override, and save. Within about a second the entity moves and the Behavior behaves
differently, in the same running game, without a restart: the game's own state outside the Scene
(a score on screen, say) is unchanged. They then change a line of Dart in the game (a log
message, say), save, and ask the client for a hot reload (automatic code reload is #11, rest). The Scene is not rebuilt: whatever the game
did to the Scene's components since the swap (an entity it moved, a counter it kept) is still
there.

**Why this priority**: this is the product loop (*Q82*), the thing the whole slice exists to
prove on the preview's default target. If it doesn't work on macOS, Phase 4's Play button has
nothing to stand on and the default Play target has to change.

**Independent Test**: start `example/` through the client on a Mac, edit and save the Scene file,
and time how long the window takes to show the change. Then edit a Dart file, save, and check
that the Scene's runtime state survives.

**Acceptance Scenarios**:

1. **Given** the client has started `example/` on macOS and the game is running, **When** the
   client reports the game as started, **Then** it also holds what it needs to reload the game
   (the app's identifier and the running game's state) and reports that to its caller.
2. **Given** the running game, **When** the Scene file is saved with different content, **Then**
   the client asks the game to hot-reload, the Scene is rebuilt from the new file and the change
   appears in the window. The game's `onReloaded` hook runs once.
3. **Given** the running game, **When** the Scene file is saved with the same content (a save with
   no change, or a touch), **Then** the client may reload the game but the Scene is not
   rebuilt: components keep their state and `onReloaded` does not run (§6.2, *Q67*).
4. **Given** the running game, **When** a Dart file under `lib/` is changed and the game is
   hot-reloaded, **Then** the Scene is not rebuilt.
5. **Given** the running game, **When** the Scene file is saved several times in quick
   succession (an editor that writes twice, or a burst of saves), **Then** the client sends one
   reload per settled change, not one per file-system event, and the game ends up showing the
   last saved content.
6. **Given** a Scene file that is saved with a mistake (invalid JSON, an unknown Type ID, a value
   of the wrong type), **When** the client reloads the game, **Then** the game keeps running with
   the previous Scene, the Runtime's error (naming the Scene, Node and Type ID or field) reaches
   the client's output, and the next valid save recovers.
7. **Given** a Scene saved by a tool that writes atomically (write a temp file, rename over the
   target, as Pyro's own save will), **When** the rename happens, **Then** the client notices
   the change as it would a plain write.
8. **Given** the reference Mac, **When** a save is made, **Then** the change is on screen in
   under a second, with a median under 500 ms over ten saves (SC-004; the constitution's
   feedback-latency budget; spike #1 measured 58–250 ms for the reload itself).

---

### User Story 4 - Start, stop and clean up (Priority: P2)

The author starts the client, watches the game window open, closes the game window by hand and
sees the client report that the game stopped. They start it again and stop it from the client.
No `flutter` process is left behind in either case, and a second start works.

**Why this priority**: the slice's value is the reload loop (story 3), but a client that leaks
processes or hangs on a closed window is not something Phase 4 can build on. It is P2 because
the Play button's full lifetime rules (*Q63*, confirmation on quit) belong to #11, rest.

**Independent Test**: start and stop the client five times on a Mac and check the process list
after each run. Close the window by hand once and check the client's report.

**Acceptance Scenarios**:

1. **Given** the client has started a game, **When** the caller stops it, **Then** the game exits
   and no process the client started is still running; if the game does not exit in a short time
   the client kills it.
2. **Given** a running game, **When** it exits for any other reason (window closed, crash, an
   IDE's stop), **Then** the client reports that the game stopped, with the exit status.
3. **Given** a project that cannot be started (no macOS target, `flutter` not found, a Dart
   compile error), **When** the client is asked to start it, **Then** it reports a clear error
   with what failed and where (the command, the project path, the tool's own output), rather
   than waiting forever.
4. **Given** the client has started and stopped a game, **When** it is asked to start again,
   **Then** it works the same way.

---

### Edge Cases

- The Scene file is saved before the game has finished starting (no running app yet): the save
  is not lost. The client sends no reload to an app it has not seen start. Once the app has
  started, it sends one reload for every save made meanwhile, because the game may have read the
  Scene before the save. That reload is harmless if the game read the new file.
- The Scene file is deleted or renamed while the game runs: the client does not crash; a reload
  that follows gets the Runtime's missing-file error and the game keeps the previous Scene.
- A new Scene file appears under `assets/scenes/` that the game does not load: the client still
  reloads for it (it can't tell which Scenes the game loaded, see Assumptions). That reload is
  harmless, because the Runtime rebuilds only Scenes whose content changed. The contract job
  checks the new Scene too.
- `flutter run --machine` writes lines that are not messages for the client (build progress,
  warnings, the engine's own log): the client ignores what it does not understand, keeps the lines
  for later display, and never mistakes them for a reply.
- A reload is sent while a previous one has not finished: the client queues at most one more and
  sends it when the first finishes, so reloads never overlap.
- The working directory or project path contains spaces or non-ASCII characters: starting and
  reloading still work.
- The generator is stale when the game starts (an annotated class changed, the Registry has not
  been regenerated): not this slice's job to fix (the build_runner watcher is #11, rest). The
  contract job's committed-files check is what catches it in CI.
- Two clients started for the same project: the second one is not specified (*Q63*: one running
  game per project, owned by #11, rest).

## Requirements *(mandatory)*

### Functional Requirements

**`example/`**

- **FR-001**: The workspace MUST contain a Flame game `example/` that is a member of the pub
  workspace, depends on the Pyro packages from the workspace and on the generator for its
  development, and is analysed, formatted and tested under the same rules as the other members
  (constitution I).
- **FR-002**: `example/` MUST contain exactly one annotated Behavior with Editable fields of at
  least two different Field types, and exactly one annotated Custom component with at least one
  Editable field. Nothing else in it is annotated.
- **FR-003**: `example/` MUST contain one hand-written Scene file that places an entity with a
  sprite and a hitbox, attaches the Behavior, includes the Custom component, sets some Overrides
  and leaves some fields at their code defaults. It MUST be in the canonical form the Scene
  writer produces, so a save by Pyro later produces no spurious diff.
- **FR-004**: The game MUST load the Scene with `PyroScene.load` and the generated Registry,
  add it to its world, and make the effect of at least one Override visible in the window.
- **FR-005**: The generated Registry and Manifest MUST be committed in `example/lib/` (*Q68*),
  as for any Pyro game, and `example/` MUST need no `build.yaml` (*Q107*).
- **FR-006**: The macOS target MUST be enabled in `example/`. Other desktop and mobile targets
  are out of scope for this slice and need not be present.
- **FR-007**: `example/` MUST start and run under plain `flutter run`, with no Pyro app, so it
  stays a faithful sample of what a developer's project looks like.
- **FR-008**: The assets `example/` needs (an image for the sprite) MUST be small, licensed for
  the repository and listed with their source and licence.

**Contract test**

- **FR-009**: The CI contract job MUST replace the placeholder job and run on every push and pull
  request that CI already covers.
- **FR-009a**: The committed-files check of FR-010 MUST also run on macOS and Windows. The
  Manifest golden check and the Scene-loading check (FR-011, FR-012) run on Linux only.
- **FR-010**: The job MUST resolve the workspace, run the generator on `example/`, and fail if
  the Registry or the Manifest it writes differs from the committed copy. The failure MUST show
  the difference. The check used MUST be the one that works on the pinned Flutter version
  (3.44, `build_runner` up to 2.15.1; §7.3, *Q76*).
- **FR-011**: The job MUST compare the generated Manifest with a golden Manifest kept next to
  the contract tests, and fail on any difference. Updating the golden MUST be a deliberate,
  documented step (not a side effect of running the job).
- **FR-012**: The job MUST discover every `*.scene.json` under `example/` (not a hard-coded list)
  and load each one with `flame_test` against the real generated Registry, using the Runtime's
  default setting for unknown types (so an unknown Type ID fails). A load that prints any Runtime
  warning (an unused Override, a repaired tree, a skipped type) MUST also fail the check, naming
  the Scene and quoting the warning: `example/`'s Scenes are meant to be clean.
- **FR-013**: Each of the three checks MUST report on its own, so a failing run says which check
  failed without reading logs for the other two. The job MUST also analyse `example/`, including
  its generated Registry, with the workspace's rules, as a fourth step of its own.
- **FR-014**: The checks MUST be runnable locally with commands the contributor can copy from the
  job, and MUST give the same result as in CI.
- **FR-015**: The job MUST pin the same Flutter version as the rest of CI and MUST finish in under
  three minutes on a warm cache.

**Pyro's client (first slice of #11)**

- **FR-016**: Pyro MUST contain a client for `flutter run --machine` that starts a project on the
  macOS desktop target and speaks the daemon's JSON messages: it recognises the app's start, its
  identifier, its debug connection and its stop, and sends it commands.
- **FR-017**: The client MUST start the project in debug mode, with the project's own `main.dart`
  (§9.3, "Play uses the real `main.dart`"), and MUST NOT require changes to the project beyond
  those the README recipe will describe.
- **FR-018**: The client MUST watch the project's Scene files and, when one the game has loaded
  changes on disk, trigger a hot-reload of the running game through the daemon (`app.restart`
  without a full restart), not through the VM service directly, so that changed assets are
  synced first (§9.3, *Q66*).
- **FR-019**: The client MUST coalesce bursts of changes into one reload per settled change,
  MUST NOT run two reloads at the same time, and MUST NOT send a reload before the app has
  started. Changes that arrive before `app.started` MUST be held and sent as one reload once the
  app has started.
- **FR-020**: The client MUST write nothing to the project (no info file, no `launch.json`, no
  run link) in this slice (those belong to #11, rest and v0.1).
- **FR-021**: The client MUST report the game's lifecycle to its caller as typed events (starting,
  started, reloaded, reload failed, stopped with status, error), and MUST pass the game's output
  lines through for later display, unchanged except that any VM service auth code in them is
  masked. The VM service address MUST NOT appear in anything the client logs or reports (§9.3,
  "The URI stays out of logs"; *Q81*): on desktop the engine prints it to stdout as a raw line.
- **FR-022**: Stopping MUST send the daemon's stop command first and kill the process if the game
  does not exit within a short, fixed time. No child process may outlive the client.
- **FR-023**: Errors MUST name what failed and where (the command, the project path, the tool's
  own output), per constitution I. Every start that cannot proceed reports an error event rather
  than waiting.
- **FR-024**: The client MUST depend on nothing in the game: it does not import, build or execute
  the user's code (*Q7*, constitution II). It lives in the app's `process/` feature, behind a
  small public surface, with the daemon-message parsing separable and testable from recorded
  transcripts (§13, "Process clients").
- **FR-025**: The command-line entry point (see Clarifications) MUST take the project path, print
  each lifecycle event and output line, stop the game on interrupt, and exit with a non-zero
  status if the game could not start. It MUST stay a thin caller of the client, be documented in
  the app's README, and be either kept as a documented developer tool or removed when the Play
  button replaces it (constitution I: no dead code).

**Verification**

- **FR-026**: The slice MUST end with a manual end-to-end check on the reference Mac (macOS,
  Apple M4, Flutter 3.44.2) that records, in `dev-docs/ARCHITECTURE.md`: whether a Scene save swaps
  the Scene, whether a Dart-only reload leaves it alone, the time from save to visible change
  over at least ten saves (median and worst), and any workaround needed. If macOS Hot-swap does
  not work, it MUST record the failure and a proposed default Play target for the author to
  decide before Phase 4 (phases.md, Phase 3).
- **FR-027**: The result MUST also state whether the macOS release build of `example/` contains
  none of the Hot-swap code path (the check of spec 004 T043, run here on `example/`), since it is
  the first real game to run it.
- **FR-028**: Phases.md MUST be updated in the same change: Phase 3's items ticked as done, the
  status line and counts updated, and the "Open" notes of Phase 2 (spec 004 T038, T043) closed
  or carried over with the reason.

### Key Entities

- **`example/` game**: the sample Flame game. Holds one Behavior, one Custom component, one
  Scene, the generated Registry and Manifest, and a macOS runner.
- **Scene file**: `example/`'s hand-written `*.scene.json`, in the canonical form of spec 001.
- **Golden Manifest**: the expected Manifest of `example/`, kept in the repository, compared with
  the generated one.
- **Contract check**: one of the three CI checks (committed files, Manifest golden, Scene
  loading).
- **Play session**: one run of a project through the client, from start to stop (*Play* in the
  glossary). Has a state (starting, running, reloading, stopping, stopped), an app identifier and
  a stream of events and output.
- **Reload trigger**: a settled change to a Scene file that causes one hot-reload request.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a clean checkout, a developer can go from `dart pub get` to the example game
  showing its Scene on a Mac in under five minutes, following only the commands in
  `example/`'s README.
- **SC-002**: The contract job passes on the repository as committed, and each of three
  deliberate breakages (a hand-edited Registry, a hand-edited Manifest golden, a Scene with a
  removed Type ID) makes it fail at exactly the matching check, with a message that names the
  file or Scene involved.
- **SC-003**: The contract job finishes in under three minutes on a warm cache on Linux, and
  the committed-files check passes on macOS, Windows and Linux with identical files.
- **SC-004**: Over ten consecutive saves of a changed Scene file on the reference Mac, the
  change is visible in the running game with a median delay under 500 ms and a worst delay under
  1 s. It is measured from the save to the game's "Scene reloaded" log line, printed once the swap
  is done. The frame that shows it follows within 16 ms, which is noted with the results
  (constitution III; spike #1 measured 58–250 ms for the reload itself).
- **SC-005**: Over ten consecutive reloads that follow a Dart-only change or a save with the same
  content, the Scene is rebuilt zero times (components keep their state, `onReloaded` does not
  run).
- **SC-006**: A burst of ten saves 100 ms apart causes at most two reloads and ends with the last
  content on screen.
- **SC-007**: After five start/stop cycles, including one where the game window is closed by
  hand and one where the game is stopped by the client, no process started by the client is still
  running.
- **SC-008**: A Scene with a mistake never takes the running game down: in nine trials (three each
  of invalid JSON, an unknown Type ID and a wrong-typed Override), the game keeps running with the previous
  Scene and the error reaches the client's caller with the Scene, Node and Type ID or field named.
- **SC-009**: The recorded transcripts of a start, a reload, a failed reload and a stop make the
  client's parsing tests pass without starting a real `flutter` process or any device.
- **SC-010**: The result of the manual check (FR-026) is recorded, and the author can say, from
  it alone, whether macOS is the preview's default Play target or not.

## Assumptions

- The slice runs on the macOS desktop target on the author's Mac (Apple M4, Flutter 3.44.2).
  Linux and Windows desktops are not exercised (the preview defaults Play to macOS, *Q82*).
  CI cannot run the macOS manual check; the contract job runs on Linux, where the generator and
  `flame_test` need no display.
- The Hot-swap mechanism is the one spike #1 verified (§9.3): a hot reload issued through the
  daemon syncs changed assets and evicts them from `rootBundle` before reassemble, and Flame
  calls `onHotReload` on mounted components. This slice does not need the run link or the asset
  re-point, which exist to keep Hot-swap working while an IDE is attached; with only the Pyro
  client attached, spike #1's macOS runs did not need them. If the manual check shows otherwise,
  that is a finding to record (FR-026), not a scope increase.
- The client does not build the project itself or run `build_runner`. The committed Registry and
  Manifest are the starting point, kept current by hand (or the contributor's own
  `build_runner` run) in this slice. The watcher with the lock probe and auto code reload are
  #11, rest.
- Which Scene files the game "has loaded" is approximated in this slice by the Scene files under
  the project's `assets/scenes/` directory (the layout the README recipe will prescribe).
  Reloading for a Scene the game never loaded is harmless (the Runtime ignores it); it only
  costs a reload.
- The client reports events to its caller as a stream and prints nothing itself. The command-line
  entry point (Clarifications) is the caller that prints them in this slice.
- `example/` is a skeleton (item 13 of the preview, 0.5 evening). The fuller sample game of
  v0.1 builds on it later and may rename or add Scenes; the contract job's discovery of every
  Scene (FR-012) means that costs nothing.
- The golden Manifest lives under `example/test/`, next to the contract tests, where the
  Generator never writes (it writes only `lib/`), so a stray regeneration cannot silently update
  the file it is compared with.
- Estimated effort: phases.md gives ~1.5 evenings (0.5 for item 13, 1 for item 12, with #11's
  slice inside #11's 4). The plan's estimate is ~2.5–3 before the 1.3–1.5× solo overrun, because
  the client, its transcript tests (SC-009), the CLI and the benchmark weren't priced in
  (plan Risks). §14 and phases.md change when the slice is done.
