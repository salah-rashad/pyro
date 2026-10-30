# Feature Specification: Play

**Feature Branch**: `specs/007-play`

**Created**: 2026-10-24

**Status**: Draft

**Input**: User description: "Phase 5 — Play (dev-docs/phases.md): #11 Play, rest of the preview part —
build_runner watcher with the lock probe, external mode and takeover (Q48, Q77); Play/Stop on the
macOS desktop target; Console with URI redaction (§9.4, Q81); Hot-swap on save with the run link
and asset re-point that keep it working with an IDE attached (§9.3, Q74); auto code reload after
the generator goes idle (Q61); Attach debugger copying the current URI (Q81); the image-restart
toast (Q72); "Game stopped" handling (Q63). Also the README recipe for adding Pyro to a project
(git dependencies, dependency_overrides, build_runner ≥ 2.14, assets/scenes/ in pubspec.yaml,
PyroScene.load call, enabling the macOS target), and the dry run: the tester task following only
the README in a Flame project that isn't example/. Tests: daemon protocol parsing from recorded
transcripts; the lock probe. Done when the dry run passes end to end: open a Flame project, place
an entity with a sprite and a hitbox, attach a custom Behavior, tweak its fields, press Play and
see the change in the running game, then attach VS Code with the copied URI and Hot-swap again."

## Overview

Phase 4 built the editor: a Scene can be composed, saved and reopened in Pyro. Phase 3 proved, from
the command line, that saving a Scene file swaps it in a running game. Phase 5 joins the two. It
puts **Play** in the editor window, so a developer composes a Scene, presses one button, and sees
the same Scene in their own game, and keeps seeing every later save there within about a second
(project-plan §9.3, §14 item 11, *Q82*).

It delivers four things that only mean something together:

1. **Play and Stop** in the editor window: runs the project's real game on the macOS desktop
   target, shows what it prints in a **Console**, swaps the Scene on every save, reloads code after
   the generator finishes, and notices when the game stops.
2. **The generator kept running**: Pyro starts the code generator in watch mode when the project
   needs one, steps aside when the developer already runs one, takes over again when theirs
   finishes, and shows the state in the status bar.
3. **Attach**: the developer's IDE can attach to the game Pyro runs, set breakpoints and reload
   code, without breaking the Scene swap.
4. **The README recipe and the dry run.** Until the "Add Pyro" flow arrives (Phase 7), a README
   recipe is how a developer adds Pyro to their own Flame project. A tester following only that
   README, in a Flame project that is not `example/`, must reach the end of the tester task. That
   run is the check that closes the phase and unlocks the early preview.

**Who uses it**

- **A Flame developer** (the author first, then the 5–8 testers of Phase 6): opens their own
  project, composes a Scene, presses Play, and keeps their IDE next to it.
- **A tester** doing the dry run, with only the README.
- **Later work**: Phase 6 sends the README and the tester task to testers; Phase 7 adds the device
  list, the attach info file, `launch.json`, unauthenticated mode and the "Add Pyro" flow on top of
  what this phase builds.

**Out of scope** (separate items): the device list and emulator or simulator boot (Phase 7, *Q62*);
any Play target other than the macOS desktop; the attach info file, the "Add VS Code attach config"
action and unauthenticated mode (Phase 7, *Q82*); clickable `file:line` links in the Console, which
need the external-editor setting (Phase 7, *Q85*); the Settings window, so every setting this phase
reads has a fixed default; the "Add Pyro" flow and SDK management (Phase 7); Image Hot-swap without
a restart (v0.2); anything on Windows or Linux.

## Clarifications

### Session 2026-10-24

- Q: When the user presses Play while the open Scene has unsaved changes, should Pyro save it
  first, ask, or run the last saved version? → A: Ask: "Save and play" or "Play without saving".
- Q: How does Pyro decide that Hot-swap has stopped working while an IDE is attached? → A: Two
  saves in a row that changed a Scene's content get no "Scene reloaded" line from the game within
  3 seconds, after both workarounds were tried.
  (Amended while planning, 2026-10-24: Pyro cannot tell whether an IDE is attached, so the rule
  applies to any run; the report is a line the Runtime prints, not one from the game's own code.
  See FR-011.)
- Q: Which project does the dry run use? → A: A Flame project the author did not write and Pyro was
  not built against; a project from the Flame examples if the author has none.
- Q: How does Pyro know an external generator is idle before it reloads code? → A: The generated
  Registry and Manifest files have not changed for 2 seconds after the Dart save; if they never
  change, 2 seconds after the save.
- Q: Does the 60-minute setup time decide whether the dry run passes? → A: No. The dry run passes
  when every step is done without help; the setup time is only recorded, and Phase 6 uses it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Press Play and see the Scene in the game (Priority: P1)

A developer has a project open in Pyro with a Scene that places an entity, a sprite, a hitbox and a
custom Behavior. They press **Play** in the editor window. The project's own game starts on the
Mac, the Scene shows in it, and the Console shows the game's output. They move the entity in
Pyro's viewport, change a Behavior field in the inspector and press save. Within about a second the
running game shows the change, with no restart and without losing the game's window.

**Why this priority**: this is the product loop (*Q82*): compose, save, see it in the real game.
Without it Pyro is a Scene file editor, and nothing else in the phase has anything to act on.

**Independent Test**: open `example/` in the editor, press Play, edit a Behavior field, save, and
watch the game. Then press Stop.

**Acceptance Scenarios**:

1. **Given** a project open in the editor with a Flutter SDK detected and the macOS target
   enabled, **When** the user presses Play, **Then** the button shows that the game is starting,
   the game's window opens, the state becomes "Running", and the Play button becomes Stop.
2. **Given** a running game that loaded the Scene, **When** the user saves a changed Scene in
   Pyro, **Then** the game shows the change within the swap limit (SC-002) and shows nothing else
   different: no restart, and the game window stays where it is.
3. **Given** a running game, **When** the user saves a Scene with no change in the file, or a
   change to a Scene the game never loaded, **Then** nothing is reloaded in the game.
4. **Given** a running game, **When** the user presses Stop, **Then** the game closes, the state
   returns to "Stopped", and Play is available again.
5. **Given** unsaved changes in one or more open Scenes, **When** the user presses Play, **Then**
   Pyro asks "Save and play" or "Play without saving"; the first saves those Scenes and then
   starts the game, the second starts it with the last saved Scenes, and closing the question
   starts nothing.
6. **Given** a project with no Flutter SDK detected, no macOS target, or a Runtime older than
   Pyro needs, **When** the user looks at the Play button, **Then** it is disabled and says why
   in words, with the one action that fixes it (for a missing macOS target, the command to enable
   it).

---

### User Story 2 - The generator keeps the catalog current (Priority: P1)

The developer writes a new annotated Behavior in their IDE. They do not run any command. Pyro has
started the generator when the project was opened, so a moment after saving the Dart file the
Behavior appears in the inspector's Add list. If they already run the generator in a terminal,
Pyro does not fight it: the status bar says an external generator is running, and the catalog
still updates. If they stop theirs, Pyro takes over again, unless they asked the generator to stop.

**Why this priority**: the Behavior list is empty or stale without it, and the README recipe
cannot ask a tester to keep a terminal open for it. The lock-probing rules (*Q48*, *Q77*) are the
part most likely to misbehave in a real project.

**Independent Test**: open a project, add an annotated Behavior, and watch the Add list. Then
start a generator in a terminal, add another Behavior, stop the terminal's generator, and add a
third.

**Acceptance Scenarios**:

1. **Given** a project open in Pyro with no other generator running, **When** the project opens,
   **Then** Pyro starts the generator in watch mode and the status bar shows "Generating" and then
   "Up to date".
2. **Given** a running generator, **When** the user saves a new annotated Behavior in their IDE,
   **Then** the new Behavior appears in the Add list within the generator limit (SC-004), and
   Behaviors already attached to Nodes are not disturbed.
3. **Given** a generator started by the user in a terminal before the project was opened, **When**
   the project opens, **Then** Pyro does not start its own, the status bar shows "External
   generator", and a change to the generated file still updates the catalog.
4. **Given** Pyro's own generator is running, **When** the user starts a generator or one-off
   build in a terminal, **Then** Pyro's generator exits without an error message, the status bar
   changes to "External build_runner", and when the user's run ends Pyro starts its own again.
5. **Given** Pyro's own generator is running, **When** the user asks the generator to stop, **Then**
   the status bar shows "Generator stopped" with a Start button, and Pyro does not start it again
   by itself.
6. **Given** the generator reports an error in the user's code, **When** the user looks at the
   status bar and the Console, **Then** both show the error with the file it is in, and the catalog
   keeps its last good content.

---

### User Story 3 - A tester adds Pyro to their own project from the README (Priority: P1)

A tester has a Flame project of their own and the README. They add Pyro to the project by following
the README only: add the packages as git dependencies, use a generator of version 2.14 or later, put the scenes
folder in the project's assets, load the Scene in `main`, enable the macOS target if the project lacks it.
Then they do the tester task end to end (User Story 1) and finish it.

**Why this priority**: setup friction is itself under test in the early preview, and the phase
is only done when someone other than `example/` can follow it. This is the phase's closing check.

**Independent Test**: the dry run itself: a Flame project that is not `example/`, the README, a
clean Mac with the Flutter SDK, and a timer.

**Acceptance Scenarios**:

1. **Given** a Flame project that was never touched by Pyro, **When** the tester follows only the
   README's recipe, **Then** the project resolves its packages, generates its Registry and Manifest
   with no errors, and builds and runs on macOS.
2. **Given** the project after the recipe, **When** the tester opens it in Pyro, **Then** it passes
   the Runtime compatibility check and a Scene can be created in its scenes folder.
3. **Given** the tester task (SC-001's steps), **When** the tester does it using only the README
   and Pyro's own messages, **Then** every step is completed without help from the author.
4. **Given** any step where the tester gets stuck, **When** the dry run is written up, **Then**
   the step, what they were stuck on and the fix (README text or Pyro message) are recorded, and the
   run is repeated after the fix until it passes.

---

### User Story 4 - Attach the IDE to the running game (Priority: P2)

The developer runs the game from Pyro and wants breakpoints in their own IDE. They press **Attach
debugger** and Pyro copies the current run's connection address to the clipboard, with a short guide
for VS Code and for Android Studio. They paste it into the IDE, attach, and set a breakpoint. They
edit a Scene in Pyro, save, and the game still swaps the Scene while the IDE stays attached. They
reload code from the IDE, and the Scene still swaps on the next save.

**Why this priority**: Pyro runs the game and the IDE attaches (*Q43*); that is the answer to
"where do I debug?". It is in the phase's done-when, but the loop works without it.

**Independent Test**: Play `example/`, press Attach debugger, attach VS Code with the pasted
address, set a breakpoint in a Behavior, then save a Scene change in Pyro and reload code from VS
Code, alternating.

**Acceptance Scenarios**:

1. **Given** a running game, **When** the user presses Attach debugger, **Then** the current run's
   address is on the clipboard, the guide for VS Code and Android Studio is shown, and a short
   confirmation says it was copied. The address itself is not shown on screen.
2. **Given** no running game, **When** the user looks at Attach debugger, **Then** it is disabled
   and says to press Play first.
3. **Given** an IDE attached to the running game, **When** the user saves a changed Scene in
   Pyro, **Then** the game shows the change as it does without the IDE (SC-002), including after
   the IDE has reloaded code or restarted the game.
4. **Given** an IDE attached to the running game, **When** the user reloads code from the IDE,
   **Then** the game's Scene is left as it is (a reload with no Scene change does not rebuild
   the Scene).
5. **Given** the game stopped and started again, **When** the user presses Attach debugger,
   **Then** the new run's address is copied, not the previous run's.
6. **Given** the guide, **When** the user reads it, **Then** it tells them to select the game's
   device before attaching in VS Code, and that VS Code may show a stale "paused" state after a
   restart although the game is running.

---

### User Story 5 - Read what the game and the generator say, without leaking the debugger address (Priority: P2)

The developer opens the Console and sees one merged log: what the generator printed, what the game
printed (both its log messages and plain printed lines), and what Pyro itself did (started,
reloaded, stopped). They can filter by source. When the game's engine prints its debugger address
into the output, the Console shows a short "Debugger available" line in its place; the address
and its authentication code never appear in the Console, in Pyro's logs or crash reports, or in
Pyro's settings.

**Why this priority**: the debugger address grants full control of the game process, so keeping it
out of every place it could be copied from is a requirement, not polish; the Console is also where
the author and testers find out why something did not work.

**Independent Test**: run a game on macOS, whose engine prints its address, and search every
Console line and Pyro's log files for the address's authentication code.

**Acceptance Scenarios**:

1. **Given** a running game, **When** it prints text with `print` and through the Flutter log,
   **Then** both appear in the Console, in order, labeled as game output.
2. **Given** a generator running, **When** it prints build progress or an error, **Then** it
   appears in the Console labeled as generator output.
3. **Given** a line from any source that carries a debugger address, **When** it reaches the
   Console, **Then** the address and its authentication code are removed before display, and the
   rest of the line is kept.
4. **Given** a whole Play run, **When** every Console line, Pyro log and settings file written
   during it is searched for that run's authentication code, **Then** there is no match.
5. **Given** a Console with many lines, **When** the user filters by source, **Then** only that
   source's lines show, and clearing the filter shows all again, without losing lines.
6. **Given** a very chatty game, **When** it prints thousands of lines, **Then** the editor stays
   responsive (SC-006) and the Console keeps the most recent lines up to a fixed limit.

---

### User Story 6 - Stops and restarts the game cannot hide (Priority: P2)

The developer closes the game window, stops it from their IDE, or the game crashes. Pyro notices,
shows "Game stopped" in the Console, and makes Play available again. When they quit Pyro or close
the project with the game running, Pyro asks first and then stops the game. If they change an image
the running game uses, Pyro tells them the game must restart to show it and offers to restart it.

**Why this priority**: a Play button that stays on "Running" after the game is gone, or a game
process left behind when Pyro quits, would cost trust fast. The image case is the one place the
save-and-see loop does not work, and silence there would look like a bug.

**Independent Test**: start the game, close its window by hand, and check Pyro. Start it again,
quit Pyro. Start it again, replace an image the Scene uses, and use the offer.

**Acceptance Scenarios**:

1. **Given** a running game, **When** it exits by any means other than Pyro's Stop (window closed,
   IDE stop, crash), **Then** the Console shows "Game stopped", the state returns to "Stopped", and
   Play is available.
2. **Given** a running game, **When** the user closes the project or quits Pyro, **Then** Pyro asks
   for confirmation, and on yes stops the game before closing; on no, nothing changes.
3. **Given** a running game, **When** Pyro itself exits without the chance to ask (a crash), **Then**
   the next time Pyro opens the project it does not show a stale "Running", and a game left over
   from the crash is not mistaken for a new run.
4. **Given** a running game that uses an image, **When** that image file changes on disk, **Then**
   Pyro shows "Image changed" with a *Restart game* action; choosing it restarts the game and the
   new image shows; dismissing it leaves the game as it is.
5. **Given** an image the running game does not use changes, **When** it is saved, **Then** no
   message shows.
6. **Given** a running game, **When** the user saves Dart code in `lib/` and the generator is
   idle, **Then** the game reloads the code once, automatically, and a code change that the generator
   is still processing is not reloaded until it finishes.

---

### Edge Cases

- **Play pressed twice, or while starting.** There is at most one game per project; a second press
  does nothing and does not start another.
- **The game fails to build.** The Console shows the compiler's messages, the state returns to
  "Stopped", and Play is available. No "Running" state ever shows for a game that did not start.
- **Saving during startup.** A save made while the game is still starting reaches the game once it
  has started (as in the vertical slice), and is not lost.
- **Saving in a burst.** Several saves within a fraction of a second produce one reload
  (spec 005 behavior carries over).
- **A Scene save that fails.** The game does not reload, and the editor's own save error is the
  only message. If it fails during "Save and play", the game does not start.
- **The macOS target is missing.** Play is disabled with the exact command to enable it; Pyro does
  not change the project (*Q29*).
- **The project is not a Pyro project** (no Runtime dependency). The existing compatibility check
  blocks Play with its message; no process is started.
- **The generator's lock is held by an editor plugin or another Pyro window.** It is treated as an
  external generator; Pyro never fails to open the project because of it.
- **The user quits their external generator and starts it again quickly.** Pyro starts its own when
  the lock is free and gives up the lock again when the user's run starts; no error is shown for
  this ordinary hand-off.
- **A Console line that looks like an address but is not one.** Only text that matches the shape
  of a debugger address, in full, is redacted; ordinary lines are never altered.
- **The game prints a line with an address of its own.** It is redacted by the same rule; Pyro
  cannot tell the origin, and over-redacting is preferred to leaking.
- **An IDE hot-restarts the game.** The Scene still swaps on the next Pyro save, and the Console
  does not report "Game stopped".
- **Flutter reports a device mid-run that is not the macOS desktop.** It is ignored.
- **The Mac has no network, or ports are busy.** Play works; the game picks free ports itself, and no
  fixed port is ever required.

## Requirements *(mandatory)*

### Functional Requirements

**Play and Stop**

- **FR-001**: The editor window MUST have a Play control in the toolbar that starts the project's
  own game on the macOS desktop target in debug mode, and turns into Stop while a game runs or
  starts. It MUST show exactly one of these states: Stopped, Starting, Running, Stopping.
- **FR-002**: There MUST be at most one game running per project, and pressing Play while one
  runs or starts MUST do nothing.
- **FR-003**: Play MUST be disabled, with a plain-language reason and the single action that fixes
  it, when no Flutter SDK is detected, when the project has no macOS target, when the Runtime is
  incompatible, or when the project failed to open. Pyro MUST NOT edit the project to enable it.
- **FR-004**: Stop MUST ask the game to stop, and if it does not exit within a short time, force
  it to exit, and always end in the Stopped state. Stopping MUST leave no game process behind.
- **FR-005**: Play MUST run the project's real entry point; it MUST NOT substitute its own.
- **FR-006**: When any open Scene has unsaved changes, pressing Play MUST ask the user to choose
  "Save and play" or "Play without saving" before anything starts. "Save and play" MUST save every
  such Scene through the normal save (atomic, with the same error handling) and start the game only
  if all saves succeed. Dismissing the question MUST start nothing. Pyro MUST NOT save a Scene
  without this choice. When no Scene is unsaved, Play starts at once with no question.

**Hot-swap on save**

- **FR-007**: While a game runs, a save of a Scene file in the project's scenes folder MUST cause
  the game to show the new Scene, using the existing Hot-swap, within the limit of SC-002.
- **FR-008**: Saves MUST be coalesced as in the vertical slice: a burst becomes one reload, one
  reload is in flight at a time, at most one is queued, and a save made while the game starts is
  applied once it has started.
- **FR-009**: A save that leaves the file's content unchanged, a code-only reload, and a
  reload triggered by an IDE MUST NOT rebuild the Scene in the game.
- **FR-010**: Pyro MUST keep Hot-swap working while an IDE is attached to the same game (the
  run link and asset re-point of §9.3, *Q74*): it MUST run its game so that its asset copy does not
  share a name with the IDE's, and before every reload point the game at its own asset copy again,
  with the second-reload fallback when that fails. Both are private interfaces of the Flutter
  tools, so FR-011 covers the case where they break.
- **FR-011**: Pyro cannot tell whether an IDE is attached, so it MUST treat Hot-swap as failed, on
  any run, when two saves in a row that changed a Scene's content each get no report from the game
  within 3 seconds of that reload finishing, after both workarounds of FR-010 were tried for each. The game reports every
  Hot-swap outcome with a line in its output (a successful swap as "Scene reloaded", a Scene it
  could not rebuild as "Scene not reloaded"; see Assumptions), and either line counts as a report.
  Pyro MUST then stop sending Hot-swaps, say so in the Console and in the editor, and tell the
  user to reload from the IDE if one is attached, or to restart the game. A *Restart game* action
  MUST restart the game and start Hot-swap again. A single slow or missing report MUST NOT trigger
  the failure, and a successful report MUST reset the count.

**Code reload, images, and stops**

- **FR-012**: While a game runs, a save to Dart code in the project's `lib/` MUST reload the code in
  the game once the generator has gone idle, never while it is generating. When Pyro runs the
  generator, idle means its state is Up to date. When the generator is external, Pyro cannot read
  its output, so idle means the generated Registry and Manifest files have not changed for 2
  seconds after the save, and if they never change, the reload happens 2 seconds after the save.
  This behavior is on by default, and has no switch until Settings arrive (Phase 7).
- **FR-013**: When an image file the running game uses changes on disk, Pyro MUST show an "Image
  changed" message with a *Restart game* action that restarts the game (a full restart, not a
  reload). Images the game does not use MUST NOT trigger it.
- **FR-014**: When the game exits any way other than Pyro's Stop, Pyro MUST show "Game stopped" in
  the Console, return to Stopped and re-enable Play within a second.
- **FR-015**: Closing the project or quitting Pyro while a game runs MUST ask for confirmation, and
  on yes MUST stop the game first.
- **FR-016**: A run that did not start (build failure) MUST end in Stopped with the compiler output
  in the Console and MUST NOT show Running.

**Generator**

- **FR-017**: When a project opens, Pyro MUST check whether a generator already runs for it, without
  disturbing it and without leaving any trace in the project, and start its own in watch mode only if
  none does. Where `build_runner` is older than 2.14 (read from the project's `pubspec.lock`), the
  generator is "Not set up" (FR-020) and nothing starts.
- **FR-018**: When another generator holds the project, Pyro MUST show "External build_runner", not
  start its own, and keep the catalog current by watching the generated Manifest file.
- **FR-019**: When Pyro's generator exits because another one started, Pyro MUST NOT show an error.
  It MUST check again whether another one holds the project: if so, show "External build_runner" and
  start its own when that one ends; if not, the user asked it to stop, so show "Generator stopped"
  with a Start button and not restart it (*Q77*).
- **FR-020**: The status bar MUST show the generator's state: Up to date, Generating, Error,
  External build_runner, or Stopped, and an error MUST name the file and the message the generator
  reported. A project with no `build_runner` or Generator dependency, or whose resolved `build_runner` is older
  than 2.14, MUST show "Not set up", with a pointer to the README recipe (and, for an old version,
  the version found and the version required), and Pyro MUST start nothing for it. A generator error MUST NOT change the catalog or any attached Behavior.
- **FR-021**: When the generated Manifest changes, the Type catalog, the inspector and the Add lists
  MUST update, and Missing behavior and Missing component states MUST be re-evaluated (this reuses
  the Manifest reload of Phase 4).
- **FR-022**: Closing the project MUST stop Pyro's own generator and MUST NOT stop an external one.

**Console and redaction**

- **FR-023**: The Console MUST be a panel of the editor window showing one merged, ordered log of
  generator output, game output (both log messages and plain printed lines) and Pyro's own events,
  each line labeled with its source, filterable by source, clearable, and bounded to a fixed
  number of most recent lines.
- **FR-024**: The debugger address (the game's debug connection address, with its authentication
  code) MUST NOT appear in the Console, in any file Pyro writes (logs, crash reports, settings,
  recovery copies) or in anything Pyro puts on screen or on the clipboard other than through the
  explicit Attach debugger action. Where the address would appear, the Console MUST show
  "Debugger available" or the rest of the line with the address removed.
- **FR-025**: Redaction MUST apply to every line from every source before it is stored, so a
  filter, a copy of Console text or a crash cannot expose it.
- **FR-026**: The Console MUST NOT make the editor drop frames while many lines arrive.

**Attach**

- **FR-027**: While a game runs, an Attach debugger control MUST copy the current run's debugger
  address to the clipboard, show a confirmation without the address, and show the guides for VS Code
  and Android Studio. It MUST be disabled with an explanation when no game runs.
- **FR-028**: Each run MUST have its own address; Attach debugger MUST never copy an address from
  an earlier run.
- **FR-029**: The VS Code guide MUST say to select the game's device first, MUST say that VS Code
  may show a stale "paused" state after a restart, and MUST say where to paste the address
  ("Flutter: Attach to Process").
- **FR-030**: Pyro MUST NOT turn off debugger authentication, add a fixed debug port, write an
  address file, or write `.vscode/launch.json` in this phase.

**README and dry run**

- **FR-031**: The repository's README MUST contain a recipe for adding Pyro to an existing Flame
  project that covers: the Pyro packages as git dependencies on this repository, with the version
  overrides they need while they are not on pub.dev; the generator at version 2.14 or later; the
  scenes folder in the project's assets; loading the Scene in the game's code; the generated file
  step; enabling the macOS target if the project lacks it; and how to build and open Pyro itself
  from source.
- **FR-032**: The recipe MUST list what Pyro needs installed (Flutter version, Xcode) and what it
  changes in the project (nothing beyond the recipe's steps), and MUST say what to do when the
  most likely failures happen (the generator reports a lock, the Runtime is incompatible, macOS
  signing for debug builds).
- **FR-033**: A written dry-run report MUST be kept in the repository, recording the project used,
  the Flutter version, each step, the time from first README step to the first running Scene, every
  point where the tester stopped or needed help, and what was changed in response.
- **FR-034**: The dry run MUST use a Flame project that is not `example/`, that the author did not
  write, and that Pyro was not built against (a project from the Flame examples if the author has
  none), and MUST be repeated until it passes without help; its final run MUST be in the report.

**Tests**

- **FR-035**: The parsing of the Flutter tools' machine output MUST be tested from recorded
  transcripts, including a run with an IDE attached, a hot restart, a build failure and an exit
  without Stop.
- **FR-036**: The generator-lock check MUST be tested against a real lock held by another process,
  covering held, free, released while waiting, and the takeover cases of FR-019.
- **FR-037**: The redaction MUST be tested against every address shape seen in a recorded
  transcript, plus lines that must not change.

### Key Entities

- **Play session**: one run of the game by Pyro: its state (Stopped, Starting, Running, Stopping),
  its device, the current debugger address (held in memory only), and the Scenes and images the
  game has loaded. At most one per project.
- **Generator state**: what the generator is doing for the project: Up to date, Generating, Error,
  External, or Stopped, with the last error and who runs it (Pyro or someone else).
- **Console line**: one line of output with its source (generator, game, Pyro), a time, a severity,
  and its text after redaction.
- **Debugger address**: the per-run connection address and authentication code that grants full
  control of the game process. Never stored, logged or shown; copied only by Attach debugger.
- **Dry-run report**: the written record of the tester task done from the README, with timings,
  stuck points and fixes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A tester who follows only the README completes the tester task in a Flame project
  that is not `example/`: open the project, place an entity with a sprite and a hitbox, attach a
  custom Behavior, tweak its fields, press Play, see the change in the running game, attach VS Code
  with the copied address, and Hot-swap again. They need no help from the author, and the time from
  the first README step to the first running Scene is recorded in the dry-run report. The time
  does not decide whether the run passes.
- **SC-002**: Over ten saves on the reference Mac, the delay from saving a changed Scene in Pyro to
  seeing it in the running game has a median under 500 ms and a worst case under 1 s, with and
  without an IDE attached (the limit of spec 005, *Q119*, now measured from Pyro's own save).
- **SC-003**: Ten saves with no change, and ten code-only reloads, rebuild the Scene zero times.
- **SC-004**: A new annotated Behavior saved in the IDE appears in Pyro's Add list within 5 seconds
  on a mid-size project (the spike #2 figure is about 3 s).
- **SC-005**: Across a full run (Play, saves, an attach, an IDE reload, a stop), searching every
  Console line and every file Pyro wrote for the run's authentication code finds nothing.
- **SC-006**: While the game prints 5,000 lines in a second, the editor keeps scrolling and editing
  at 60 fps (profile mode, reference Mac).
- **SC-007**: After the game exits by any means, Play is available again within 1 second, and no game
  process remains after Stop or after closing the project.
- **SC-008**: Starting the generator check on an open project does not interrupt a generator the
  user already runs: in ten attempts the user's generator keeps running and finishes its build.
- **SC-009**: Every Play-disabled reason in FR-003 shows its fix in the window, so a tester never
  has to read source to learn why Play is off (verified in the dry run, with zero "why is Play
  grey?" questions).
- **SC-010**: While the game is stopped, Play, the Console and the generator state register no
  animation ticker or per-frame callback in the editor, and the game's release build still
  contains no Hot-swap or Play code (spec 005 SC carries over).

## Assumptions

- The macOS desktop target is the only Play target in this phase (*Q82*); the device list is
  Phase 7. Hot-swap there was verified in the vertical slice.
- The Flutter version is the one the repository pins for CI; the private Flutter interfaces the run
  link and asset re-point rely on are re-checked against it as part of this phase (project-plan
  §15.1).
- The game's run link (a folder with a different name than the project) lives in Pyro's own
  application-support area, not in the user's project, and is removed when the project closes.
- The preview has no Settings window, so code reload on save is always on, the Console's line limit
  and the generator's idle wait are fixed values, and no setting is written to the project (*Q85*).
- Console `file:line` links are not part of this phase because the external editor is configured in
  Settings (Phase 7).
- The game's reports of FR-011 come from the Runtime in debug builds, not from the game's own code.
  Today only `example/` prints a "Scene reloaded" line, from its own code, so the Runtime gains
  the two lines (the one change this phase makes to a package). They are debug-only and absent
  from release builds.
- Pyro knows an image is in use when a Scene in the project refers to it (a Sprite or an Image
  path field). An image the game loads from its own code, with no Scene referring to it, is not
  tracked and does not show the FR-013 message.
- The tester has Flutter and Xcode installed; installing them is outside the README recipe, which
  only lists what is needed.
- The dry run is done by the author, standing in for the Phase 6 testers. The project it uses is
  chosen as FR-034 says, and its name and Flutter version go in the report (FR-033).
- The README recipe is the stand-in for the "Add Pyro" flow (*Q82*); keeping its snippets correct is
  part of this phase, and the dry run is how they are checked.
- A game already running when Pyro crashes is not adopted by the next Pyro run; Play simply starts
  a new one, and a stale run is not shown as Running.
- The existing vertical slice client and its command-line entry point are the base this phase builds
  on; whether the command-line entry point stays as a developer tool is decided in the plan.
