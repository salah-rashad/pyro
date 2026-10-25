# Research: Play (Phase 5)

Each entry is a decision the plan rests on. Sources are the project's own documents and code read
on 2026-10-24: `docs/project-plan.md` §9, `docs/ARCHITECTURE.md` (spikes #1 and #2 and the vertical
slice), `docs/decisions.md`, the Play client in `apps/editor/lib/process/`, the Type catalog
provider, `packages/pyro_runtime`'s `PyroScene`, and `example/`. Nothing here was run against a
Flutter SDK; the items that need a run on the reference Mac are listed at the end (**To confirm
while building**). When the work is built, the decisions are recorded in `docs/decisions.md` as
Q125 onward.

## R1 — The game's Hot-swap report is a Runtime line, not a game line

**Finding.** Clarification Q2 (FR-011) counts a missing "Scene reloaded" line. That line is printed
by `example/lib/example_game.dart` from its own `onReloaded` callback
(`debugPrint('[pyro_example] Scene reloaded: …')`). `PyroScene` in `pyro_runtime` prints nothing on
success, and prints a multi-line "Pyro couldn't Hot-swap" block on failure. A tester's game has no
such callback, so the rule as clarified could never observe a success.

**Decision.** `PyroScene` prints one stable line when it loads a Scene and one per Hot-swap outcome, in debug
builds only (inside
`kDebugMode`, already the guard of `onHotReload`):

```text
[pyro] Scene loaded: assets/scenes/level1.scene.json
[pyro] Scene reloaded: assets/scenes/level1.scene.json
[pyro] Scene not reloaded: assets/scenes/level1.scene.json: <first line of the error>
```

Pyro counts either line as the game's report (a Scene that cannot be rebuilt is a user error, not a
broken mechanism). `example/` drops its own print; the benchmark and the quickstart wait for the
Runtime's line. Format and rules: [contracts/hot-swap-reports.md](contracts/hot-swap-reports.md).

**Why.** One line per outcome is the smallest signal that works in every game, costs nothing in
release (tree-shaken with the rest of Hot-swap), and needs no service extension (*Q66*).

**Alternatives.** Ask the VM service for the scene's content hash: needs a Runtime service
extension and a connection per check. Count rebuilds through `onReloaded` in the tester's code:
cannot be required. Infer success from the daemon's reload result: the daemon succeeds even when
the engine still reads the IDE's stale copy, which is exactly the failure to catch.

## R2 — The run link is always used; it lives in Pyro's application support

**Decision.** Every Play creates `<app support>/run/<project-id>/<name>-pyro`, a symlink to the
project, and runs `flutter run --machine -d macos --debug --project-root <link>` with the real
project as working directory (spike #1 finding 4, *Q74*). `<project-id>` is the first 12 hex digits
of the SHA-1 of the project's canonical path (`crypto` is already a dependency). The link is removed
when the game stops; any link left under that project's folder is removed when the project opens
(a crash leaves one, FR-015 and the crash edge case).

**Why always.** Pyro cannot know in advance that an IDE will attach, and a DevFS name clash can
only be avoided before the run starts. The name differs from the project's folder name, which is
all the fix needs.

**If the link cannot be made** (read-only support folder, a filesystem without symlinks): Play still
starts without it, the Console says that attaching an IDE may stop Hot-swap, and a failed Hot-swap
then follows R6. Play does not refuse.

**Alternatives.** Create the link only when Attach is pressed: too late, the run already has its
DevFS name. Copy the project: loses live edits. A link inside the project: writes to the user's
tree (constitution IV).

## R3 — The debugger address is held privately and read only by Attach

**Finding.** Spec 005 (*Q121*) drops the address from every event so nothing downstream can leak it.
The re-point (R4, R5) needs the address in memory, and Attach needs to copy it.

**Decision.** `PlaySession` stores `wsUri` and the DevFS `baseUri` from `app.debugPort` in private
fields, still emits only `PlayDebuggerAvailable`, and exposes one accessor, `debuggerAddress`,
documented as "for *Attach debugger* only". The address is cleared when the session ends, so a
second run can never return the first run's address (FR-028). The VM service link receives the
address in its constructor and never logs it; `toString` of every type holding it is overridden.
Redaction stays at the entry of the Console buffer (R12) and in the session (existing), so a raw
stdout line with the address is masked wherever it appears.

**Tests.** A transcript with the address in `app.debugPort`, in a raw stdout line and in an error
message; assert no event, Console line, `toString` or exception message contains the auth code
(SC-005, FR-037).

## R4 — `vm_service` is the client for the three calls

**Decision.** Move `vm_service` ^15.4.0 from `dev_dependencies` to `dependencies`. Wrap it in a
small `VmServiceLink` interface (`listViews()`, `setAssetBundlePath(viewId, isolateId, dir)`,
`evict(isolateId, asset)`) with a real implementation and a fake for tests. The three methods are the
ones the spike driver calls (`_flutter.listViews`, `_flutter.setAssetBundlePath`,
`ext.flutter.evict`); the first and second are private engine extensions, so the wrapper is also the
single place to re-check on each Flutter stable release (§15.1).

**Alternatives.** A raw WebSocket as in the spike driver: rejected in Complexity Tracking.

## R5 — Re-point before every reload, with the spike's fallback

**Decision.** Before each Hot-swap the controller calls `repointAssets()`:

1. `listViews`; take the first view.
2. `setAssetBundlePath(assetDirectory = <baseUri>/build/flutter_assets)`.
3. If that succeeds, send `app.restart {fullRestart: false}`.
4. If the engine rejects it (the folder does not exist yet, or an IDE recreated the DevFS), send
   `app.restart`, re-point again, `evict` the changed scene files, and send `app.restart` once more.

This is the spike driver's `reload()` verbatim in behavior (spike #1, `studio_driver.dart`). The
extra reload on the first save after a run starts is a known cost (spike #1 open item, a proposed
optimization that is not taken here).

**Where.** Inside `PlaySession`'s reload path, so every caller (scene watcher, code watcher, manual)
gets it and the one-at-a-time queue of *Q122* still applies. Code-only reloads skip the re-point:
they change no asset.

**Measured.** SC-002 repeats the spec 005 benchmark with the link and re-point, with and without a
`flutter attach` client as the stand-in IDE (it makes the same DevFS clash as VS Code, spike #1
finding 2). The budget is in the plan.

## R6 — How a failed Hot-swap is recognized

**Decision.** `HotSwapMonitor` keeps, per Scene path, the SHA-256 of the file as of the last report
(baseline: the file's content when the session starts). For each batch from the scene watcher it
hashes the changed files; if a file's hash differs from its baseline, a report is *expected* within
3 seconds of the reload finishing (the daemon's `PlayReloaded`). A report line (R1) for that path
clears the expectation and updates the baseline. If the 3 seconds pass, the miss counter goes up; two
misses in a row set the state to failed. A report resets the counter. Misses count only after the
full R5 sequence ran for that save.

**On failure.** The controller stops sending *scene* reloads, shows the "Hot-swap stopped working"
notice and the Console line, and offers **Restart game** (a full restart, which also re-arms the
monitor with fresh baselines). Code reloads continue.

**Why this differs from the clarified wording.** The spec said "while an IDE is attached". Pyro has no
reliable way to know that (the IDE talks to the VM service, not to Pyro), so the rule applies to any
run, and the message names both causes. The spec's FR-011 was amended to match.

**Edge cases handled by design.** A save that leaves the bytes unchanged has the same hash, expects
nothing, and cannot count as a miss (the spike's "testing pitfall"). A burst of saves is one batch
(*Q122*). A Scene the game never loaded would count as a miss, so the monitor expects a report only
for a path the game has announced: the Runtime also prints `[pyro] Scene loaded: <path>` when
`PyroScene.load` builds a Scene (R1, the contract's third line), and that line arms the path. A
changed path with no such line is ignored and noted once in the Console.

**Alternatives.** Compare file hashes in the game through a service call: a Runtime service extension
(*Q66*). Time the daemon's reload: succeeds in the failure case.

## R7 — The generator supervisor and the command it runs

**Decision.** `GeneratorSupervisor` runs `dart run build_runner watch` in the project, with the
`dart` next to the detected Flutter SDK (`<flutter root>/bin/dart`), because `dart run` resolves a
Flutter project's packages correctly from there (spike #2 ran it this way). No
`--delete-conflicting-outputs`: Pyro does not delete files in the user's project. It starts only when
the project has `build_runner` in its pubspec and the Runtime compatibility check passed; otherwise
the state is **Not set up** (amended into FR-020) and nothing starts. The `build_runner` version
comes from the project's `pubspec.lock` (`packages: build_runner: version:`), read the way
`runtime_compat.dart` reads `pyro_runtime`'s; below 2.14 the reason names the version found and the
version required. Spec 006's compatibility check does not look at `build_runner`, so this is new.

**States** and transitions are in [contracts/generator-supervisor.md](contracts/generator-supervisor.md).
It publishes a stream of states plus the lines it reads (for the Console), and it is the only thing
that spawns `build_runner`.

**Alternatives.** Use `build_runner` as a library inside the app: the app must not run user code or
depend on the generator (constitution II). Run `build` on each save: slower than the watcher (spike
#2, ~0.9 s versus a cold start of 14–16 s).

## R8 — The lock probe

**Decision.** `BuildLockProbe.check(projectPath)` returns `held`, `free` or `absent`:

- `absent` when `.dart_tool/build/lock/build_runner.lock` does not exist (no build_runner ever ran
  there). The probe never creates it, so it cannot leave a trace (FR-017).
- Otherwise open it with `FileMode.append`, try `lock(FileLock.exclusive)` (the non-blocking form, so
  it throws at once when held), unlock and close in a `finally`. A lock error means `held`.

It uses the **async** `lock`, not `lockSync`, so the UI isolate does not block (constitution III);
the probe took 1–4 ms in spike #2. It never creates `.requested`. After a takeover exit the
supervisor re-probes (*Q77*). While the state is External, it re-probes every 1 s until `free`.

**Testing.** POSIX file locks are per process, so a lock held by the test's own isolate would not
conflict. The test spawns a tiny `dart` helper that takes the lock and waits for its stdin to close,
and asserts held, then free after the helper exits, then absent for a missing file. This uses the
real operating system and no Flutter SDK.

## R9 — Classifying build_runner output

**Decision.** `generator_output.dart` is a table of line patterns to events (`building`, `succeeded`,
`failed`, `takeover`, `waiting-for-lock`, `info`), unit-tested on recorded real output saved under
`test/fixtures/transcripts/`. Lines that match nothing go to the Console as generator output and
change nothing. The patterns that matter, from spike #2 and the spec: the takeover line
`Exiting as requested by another build_runner process.`, the wait line `Waiting for already-running
build_runner.`, severe-level lines, and the build start and success lines. **The exact strings of the
last two are not quoted here**; they are captured from a real `build_runner watch` on the reference
Mac before the table is written (see below), and the fallback when the strings change is the one in
the spike: an exit code 0 that Pyro did not request means takeover.

**Errors.** A failed build leaves the Manifest's `errors` filled in (spike #2 finding 4), and the
Type catalog already keeps the last good types. The supervisor adds the state **Error** with the
first severe line and, when the Manifest names a file and message, those. It never edits the catalog.

## R10 — Code reload waits for the generator to be idle

**Decision.** `CodeWatcher` watches `lib/**.dart` of the open project (generated files included, so
a regenerated Registry reloads too). A batch of saves (150 ms of quiet, as for scenes) asks the
controller for a code reload. The controller:

- sends it at once when the generator state is **Up to date**, **Stopped** or **Not set up** (nothing
  is going to change the files);
- waits when the state is **Generating** (Pyro's own watcher), and reloads on the next **Up to date**;
- **holds** it while the state is **Error**, with a Console note naming the file and message, and
  reloads once when the generator recovers. The generator reads every file under `lib/`, so an error
  usually means Dart the game cannot run. Found by hand (2026-10-25): such a reload reached the game as
  compile-error stubs that throw in `update`, the Flame game loop's ticker died, and the game stayed
  frozen after the error was undone until a hot restart. (A reload that races ahead of the generator is
  still rejected by `flutter run` with "DevFS synchronization failed", which is safe.);
- with **External build_runner** (Pyro cannot read its output), waits until `lib/pyro.g.dart` and
  `lib/pyro.manifest.json` have not changed for 2 seconds after the last save, and reloads
  2 seconds after the save if they never change (the clarified rule, FR-012).

A code reload is `app.restart {fullRestart: false}`, the same call as a Hot-swap, so a code save
and a scene save close together share one reload (the one-in-flight, one-queued rule). The re-point
is skipped when the batch has no scene file.

## R11 — Which images the game uses

**Decision.** `ImageUse` reads every `assets/scenes/**/*.scene.json` of the project with the Runtime's
`SceneCodec` at Play and again when scene files change, and collects the project-relative image paths
that Sprite Nodes and Image-path Overrides name. A watcher on the project's asset image folders
(from `asset_folders.dart`, which Phase 4 already reads) reports a change to a collected path as
`ImageChanged(path)`. The controller shows the "Image changed" notice with **Restart game**; the
notice replaces itself for further changes to the same set and clears on a restart. A path no Scene
names is ignored (the spec's added assumption).

**Alternatives.** Any change in `assets/images/`: shows the notice for unused images (FR-013 forbids).
Ask the game which images it loaded: needs a service extension.

## R12 — The Console buffer and throughput

**Decision.** `ConsoleBuffer` is a fixed-capacity ring (10,000 lines) of immutable `ConsoleLine`
values. Every line is redacted on entry (`redactAuthCodes`), so a filter, a copy of Console text or a
crash cannot expose an address (FR-025). The buffer notifies listeners at most once per 50 ms
(a `clock` timer, so tests use `fake_async`). The panel is a virtualized list with a fixed row
extent; it follows the tail unless the user scrolled up. Filters are by source (generator, game,
Pyro) and clear without losing lines. Severity is carried but only colors a line (no search in this
phase).

**Why 10,000.** The spec asks for 5,000 lines in a second without a dropped frame and a bounded
buffer; 10,000 keeps two seconds of that burst for a user to read, costs about a megabyte of
strings, and is one constant in `PlayDefaults`.

**Measured.** `benchmark/console_throughput.dart` pushes 5,000 lines per second for 10 seconds and
reports buffer cost; the profile-mode frame check is in the quickstart (SC-006).

**Not in this phase.** `file:line` links: they need the external-editor setting (Phase 7).

## R13 — Play, Stop, quit and close

**Decision.** The controller exposes `play()`, `stop()` and a state stream with the four spec states
(the session's `reloading` shows as Running). `play()` first checks the disabled reasons
(FR-003) in a fixed order and reports the first one: no SDK, no `pubspec.yaml`, Runtime incompatible,
no `macos/` folder (with the command `flutter create --platforms=macos .`, from the existing
`PlayStartException` text). If any open scene has unsaved changes, the toolbar asks "Save and play" /
"Play without saving" first and the controller is only called after the answer; "Save and play" calls
the existing `saveScene` for each and aborts on the first failure.

Quitting uses the shell's existing `AppExitResponse` hook, extended: after the unsaved-changes loop it
asks "A game is running. Stop it and quit?" and stops the session first on yes. Closing a project
does the same through one `confirmStopGame` helper both call. Game exits that Pyro did not request are
already `PlayStopped(requested: false)` events; the controller turns those into "Game stopped" and
the Stopped state within the same turn (FR-014, SC-007).

**Stale state after a crash.** Nothing about a run is persisted, so a new Pyro cannot show "Running"
for an old game. The leftover run link is removed on project open (R2). A game process left behind by
a crashed Pyro is not adopted (spec assumption); Play starts a new one.

## R14 — Attach

**Decision.** *Attach debugger* is enabled while the state is Running. It writes
`session.debuggerAddress` to the clipboard, shows a toast "Debugger address copied" (no address), and
opens `attach_guide.dart`, a `PrDialog` with the two guides. The VS Code guide has the three facts of
FR-029: select the game's device first, paste the address in "Flutter: Attach to Process", and the
stale "paused" state after a restart. Nothing is written into the project and no port or flag
changes (FR-030, *Q81*).

## R15 — The README recipe and the dry run

**Finding.** The repository has no root `README.md` (only `example/README.md` and
`apps/editor/README.md`). Phase 8 owns the Getting Started README (#16).

**Decision.** Add a root `README.md` now with a short description and one section, "Add Pyro to a
Flame project (early preview)". Its contents are listed in [contracts/readme-recipe.md](contracts/readme-recipe.md);
every snippet is taken from `example/pubspec.yaml` and `example/lib/main.dart` as they are, so the
recipe cannot drift from a project the contract test already builds. The dry run follows it in a
project the author did not write (FR-034) and writes
`specs/007-play/dry-run-report.md`; each README or message fix is a commit on this branch and the run
repeats until it passes without help.

## Constants (no Settings window yet, *Q85*)

One `PlayDefaults` class holds: scene quiet period 150 ms (existing), stop timeout 5 s (existing),
Hot-swap report wait 3 s, miss limit 2, code-reload settle 2 s, lock re-probe interval 1 s, Console
capacity 10,000 lines, Console notify interval 50 ms. Phase 7 turns the user-facing ones into
settings.

## To confirm while building

| Item | How | If it differs |
|---|---|---|
| The build and success lines of `build_runner watch` on Flutter 3.47.7 (R9) | Run it in `example/`, save `test/fixtures/transcripts/` | Adjust the table; the classifier is data |
| `flutter attach` as a stand-in IDE reproduces the DevFS clash (R5) | The latency benchmark with and without it | Use VS Code by hand for SC-002 |
| `--project-root` with a symlink works with the current Flutter pin (§15.1) | The quickstart's run 1 | Re-check the private options; fall back as in §9.3 |
| Platform channel for the macOS debug build needs no network-client entitlement beyond `example/`'s | The dry run in a third-party project | README recipe lists the entitlement if needed |
| The first-run extra reload is acceptable (R5) | Latency benchmark, first save | Take spike #1's proposed optimization |
