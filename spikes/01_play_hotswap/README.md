# Spike #1 — Play, Hot-swap and Attach

Throwaway code for the v0.0 de-risking spike (`dev-docs/project-plan.md` §14, §9.3, §15.3).
Findings go into `ARCHITECTURE.md`; nothing here ships.

| Folder | What it is |
|---|---|
| `game/` | A Flame game with a minimal `StudioScene` (`lib/studio_scene.dart`) that loads `assets/scenes/level1.scene.json` and, on Flame's `onHotReload()`, rebuilds the scene only if the file's content hash changed. The HUD shows the rebuild count, the hash and a Dart-code marker. |
| `driver/` | A Dart CLI that plays the Studio's part: spawns `flutter run --machine` (VM service auth codes on), writes each run's VM service URI to `game/.dart_tool/flame_studio/vm_service.json` for the IDE, edits files, hot-reloads through the daemon (`app.restart`), and reads the game's `[studio_scene]` log lines to decide pass/fail. |

## What is being checked

- **(a)** Scene edit → `app.restart` (hot reload) → `StudioScene.onHotReload` rebuilds the scene.
- **(b)** A Dart-only hot reload does **not** rebuild the scene.
- **(c)** VS Code attaches: breakpoints hit, and IDE hot reload works while the driver's
  `flutter run` is still connected (the deciding test for ADR 0001).
- **(d)** VS Code attaches with auth codes on through the `vmServiceInfoFile` entry
  (`dev-docs/decisions.md` Q81), whether it is started after the game or before it.

Run (a) and (b) on the iOS simulator, an Android emulator **and one physical phone**.

## Quick start

Prerequisites: Flutter stable (tested with 3.44.2) on your `PATH`, Xcode and/or Android SDK.

```bash
cd spikes/01_play_hotswap/game && flutter pub get && cd ../driver && dart pub get
```

Find a device id:

```bash
flutter devices
```

### 1. Automatic checks (a) + (b)

From `spikes/01_play_hotswap/driver`:

```bash
dart run bin/studio_driver.dart -d <device-id> --ci
```

It launches the game, runs both checks, prints `AUTO CHECKS (a)+(b): PASS` or `FAIL`, stops
the game, restores the files it edited and exits with code 0 (pass) or 1 (fail). Repeat for the
iOS simulator, an Android emulator and a physical phone.

### 2. Interactive run and check (c)

```bash
dart run bin/studio_driver.dart -d <device-id> --auto
```

For check (c), run it once without `--repoint-assets` (to see the problem) and once with it
(to confirm the workaround):

```bash
dart run bin/studio_driver.dart -d <device-id> --auto --repoint-assets
```

On a **physical device**, also run the game under a differently named project root so the IDE
doesn't delete the driver's DevFS (see "DevFS name clash" below):

```bash
ln -sfn "$(cd ../game && pwd)" /tmp/game-studio
```

```bash
dart run bin/studio_driver.dart -d <device-id> --auto --repoint-assets --project-root /tmp/game-studio
```

Same checks, but the game keeps running afterwards. Type a command and press Enter:

| Key | Action |
|---|---|
| `s` | Edit the scene (moves the player, recolors the coin, retitles) and hot reload. The scene should rebuild. |
| `d` | Bump `dartMarker` in `lib/dart_marker.dart` and hot reload. The HUD's `code:` changes; the scene must not rebuild. |
| `t` | Touch the scene file (same bytes) and hot reload. The scene must not rebuild. |
| `r` / `R` | Hot reload / hot restart |
| `u` | Print the VM service URI (with its auth code; it isn't printed otherwise) |
| `q` | Stop the game and restore the edited files |

Always quit with `q` (or Ctrl-C) so the driver restores `level1.scene.json` and
`dart_marker.dart`. If a run is killed hard, restore them with
`git checkout -- spikes/01_play_hotswap/game`.

On each `app.debugPort` the driver writes `{"uri": "<ws URI>"}` to
`game/.dart_tool/flame_studio/vm_service.json` (temp file + rename, owner-only), and deletes it
when the game stops or the driver quits. It deletes only the file: the debug adapter watches
the folder, so the folder must already exist when an attach entry starts before the game.

Then, with the driver still running:

1. Open `spikes/01_play_hotswap/game` in VS Code (Dart + Flutter extensions installed).
2. Run and Debug → **Attach to Studio game (info file)** (from `game/.vscode/launch.json`). It
   holds no URI; the adapter reads it from the info file. If that fails, try **Attach to Studio
   game (pick URI)** and paste the URI from `u`.
3. Set a breakpoint in `SpikeGame.update` (`lib/spike_game.dart`). It should hit; continue.
4. Edit the `dartMarker` string in VS Code and save (or press the hot reload button). The HUD
   should update, from the IDE's reload.
5. Back in the driver, type `s`, then `t`. `s` should rebuild the scene; `t` must log
   "scene unchanged". Without `--repoint-assets`, expect them to go wrong once VS Code has
   attached and reloaded (see "Asset shadowing" below). With it, they should stay correct; the
   first `s` after attaching logs one extra reload.
6. Type `q`. VS Code's debug session should end with "Application finished" or similar.

Check (d), attach before the game runs:

1. Stop the driver (`q`) and make sure `game/.dart_tool/flame_studio/vm_service.json` is gone
   (the folder stays).
2. In VS Code, start **Attach to Studio game (info file)**. It should sit at "Attaching…".
3. Start the driver (`--auto`). VS Code should attach on its own once the game is up; repeat
   steps 3–4 above, then `q`.

No VS Code? `flutter attach` exercises the same coexistence path from a second terminal (`u`
prints the URI):

```bash
flutter attach -d <device-id> --debug-url <URI from u>
```

Press `r` in that terminal for an IDE-style reload, then `s` in the driver.

### Options

| Flag | Default | Meaning |
|---|---|---|
| `-d <id>` | (required) | Device to run on |
| `--auto` | off | Run checks (a)+(b), then stay interactive |
| `--ci` | off | Run checks (a)+(b), then quit with an exit code |
| `--dds-port <n>` | (none; flutter picks a free port) | Fixed DDS port. 8181 when `--disable-auth-codes` is on |
| `--disable-auth-codes` | off | Dev-only escape hatch (Q81): pass `--disable-service-auth-codes` for a stable, unauthenticated URL (`ws://127.0.0.1:8181/ws`). Use only with local devices; pair with the "unauthenticated, DDS 8181" attach entry |
| `--repoint-assets` | off | Before each reload, point the engine back at the driver's DevFS assets (`_flutter.setAssetBundlePath`); if that folder is gone, reload, re-point, evict the scene and reload again. Workaround for asset shadowing by an attached IDE |
| `--project-root <dir>` | (none) | Pass flutter's hidden `--project-root`. Its folder name names the DevFS; use a symlink to the game with another name to avoid clashing with an attached IDE |
| `-v` | off | Pass `-v` to `flutter run` (shows DevFS sync and asset eviction) |
| `--project <dir>` | `../game` | Game project to run |

## Results

Fill in as you go. Record the Flutter version and device for each row.

| Check | macOS desktop | iOS simulator (iPhone 17) | Android emulator (Pixel 9 Pro XL) | Physical phone (Android CPH2737) |
|---|---|---|---|---|
| (a) scene edit rebuilds | ✅ ~58 ms | ✅ ~70 ms | ✅ ~250 ms | ✅ ~156 ms (USB) |
| (b) Dart-only reload doesn't rebuild | ✅ | ✅ | ✅ | ✅ ~217 ms |
| (c) second client (`flutter attach`) reloads while driver connected | ✅ | ✅ | | |
| (c) VS Code attach | | ✅ | | ✅ |
| (c) VS Code breakpoint hits | | ✅ (`SpikeGame.update`) | | |
| (c) VS Code hot reload while driver connected | | ✅ | | ✅ |
| (c) driver hot restart while an IDE is attached | ✅ (`flutter attach`, `--project-root`) | | | ❌ without / ✅ with `--project-root` (VS Code shows a stale "paused" afterwards, see notes) |
| (c) driver scene edits still apply after an IDE attaches/reloads | ❌ without / ✅ with `--repoint-assets` (✅ cleaner with `--project-root` too) | ❌ without / ✅ with `--repoint-assets` (VS Code) | | ❌ with `--repoint-assets` alone (driver hot restart breaks) / ✅ with `--repoint-assets --project-root` (VS Code) |
| (c) `--disable-service-auth-codes` needed for a stable URL? | Yes: with auth codes the URL changes every run (`/EMWbRKFTAe4=/ws`, `/rY9Oy8-nQ1I=/ws`) | | | |
| (a)+(b) with auth codes on, no fixed DDS port (Q81 default) | ✅ (2026-10-17) | | | |
| (d) Flutter debug adapter attaches via `vmServiceInfoFile`, auth codes on | ✅ scripted DAP client on `flutter debug-adapter`: game first; adapter first, folder present; adapter first, folder missing. Hot reload through the adapter ✅ | | | |
| (d) VS Code attaches via the "info file" entry | ✅ game first and entry first; no URI prompt, breakpoint hits, hot reload works (Dart-Code 3.144.0) | | | |

Flutter 3.44.2 / Flame 1.38.2, macOS 26.2. macOS desktop isn't a v0.1 Play target, but it's
the quickest loop for iterating on the spike.

## Notes so far

- **Attach through the info file (Q81), 2026-10-17, macOS desktop.** A scripted DAP client
  drove `flutter debug-adapter` (the adapter Dart-Code runs for Flutter) with
  `{"vmServiceInfoFile": ".../.dart_tool/flame_studio/vm_service.json", "toolArgs": ["-d", "macos"]}`.
  It attached with auth codes on in all three orders: game already running; adapter started
  first with the folder present but no file; adapter started first with
  `.dart_tool/flame_studio/` missing. When started first, it connected within ~0.3 s of the
  driver writing the file. A hot reload through the adapter worked while the driver stayed
  connected. Dart-Code 3.144.0 passes `vmServiceInfoFile` through without prompting for a URI
  (read from its bundled `extension.js`).
  - The adapter runs `flutter attach --debug-uri <uri>`, which still picks a device: with more
    than one connected ("macOS" plus "Mac Designed for iPad" here) and no `-d`, it exits with
    "More than one device connected". VS Code adds the device selected in its status bar, so
    that has to be the game's device.
  - The IDE's Debug Console prints the full URI ("Connecting to VM Service at ws://…/<code>=/ws").
    That's the IDE's own log, outside the Studio.
  - The driver now masks auth codes in everything it echoes (the engine's "listening on" line
    on desktop, `app.devTools`, `app.dtd`); `u` prints the URI on request.
- On desktop targets, `flutter run --machine` passes the game's `print` output through as
  raw stdout lines, not `app.log` events. The Studio's Console must handle both.
- With `--dds-port 8181 --disable-service-auth-codes`, `app.debugPort` reports
  `ws://127.0.0.1:8181/ws`, a stable URL across runs.
- Hot reload already syncs changed assets and evicts them from `rootBundle` before `reassemble`,
  so `rootBundle.loadString` with its default cache sees the new scene. No custom service
  extension is needed, as Q66 assumed.
- Two flutter_tools clients coexist for **code**. With the driver's `flutter run` connected,
  `flutter attach --debug-url http://127.0.0.1:8181/` (or VS Code) can hot-reload, and both
  clients keep working. Each client has its own compiler, so both recompile the changed library;
  harmless. Stopping the game from the driver ends the attach session ("Lost connection to
  device").
- **Asset shadowing (breaks Hot-swap while an IDE is attached).** Two flutter_tools behaviors
  combine (reproduced on macOS with `flutter attach`; seen on the iOS simulator with VS Code):
  1. The DevFS is named after the project folder (`game`). When the IDE attaches, its
     flutter_tools finds that name taken and **destroys the driver's DevFS** before creating
     its own (`DevFS: Creating failed. Destroying and trying again`). The engine is still
     pointed at the deleted folder, so the driver's next scene edit reads the **original**
     scene from the app bundle. The driver's next sync recreates its folder.
  2. Each client calls `_flutter.setAssetBundlePath` only once, on its first reload that syncs
     an asset. After the IDE's first such reload, the engine serves the scene from the IDE's
     copy, which only updates when the IDE reloads. Driver edits are then ignored ("scene
     unchanged" though the file changed) until the IDE reloads again.

  Either way the game reads a different copy than the one the driver just wrote, and a `t`
  (same bytes) can log "REBUILT" when the game switches back to the up-to-date copy.

  ```
  after s: disk=425f75a1  game: scene REBUILT #2 …->425f75a1
  after A (attach reload): game: scene unchanged hash=425f75a1
  after s: disk=f1a41103  game: scene unchanged hash=425f75a1   ← ignored
  after s: disk=34fe81c1  game: scene unchanged hash=425f75a1   ← ignored
  after A (attach reload): game: scene REBUILT #3 …->34fe81c1   ← jumps to latest
  ```

  **Workaround (`--repoint-assets`):** before each reload, the driver calls
  `_flutter.setAssetBundlePath` itself over the VM service, pointing the engine back at
  `<its DevFS base>/build/flutter_assets`. If that fails because the folder was deleted (or
  doesn't exist yet), it reloads (which recreates the folder), re-points, evicts the scene
  (`ext.flutter.evict`) and reloads again. With it, the game matched the file on disk after
  every step of `s ATTACH s t A s t A t s`, and on the iOS simulator with VS Code attached and
  hot-reloading between driver edits. Remaining wart: on the first edit after an IDE attaches,
  the first of the two reloads reads a stale copy (the original scene from the app bundle, or
  the IDE's copy if the IDE has already reloaded), so the scene can flash for ~50 ms and
  `onReloaded` can fire twice.

  **On physical devices the re-point isn't enough.** Simulators and desktop use a local DevFS
  writer that recreates the driver's folder on its next sync. Physical Android and iOS devices
  write through the VM service under the DevFS *name*, which the IDE now owns, so the driver's
  folder never comes back. Every re-point then fails, and the driver's hot restart breaks
  because it launches from its old `baseUri` (seen on Android CPH2737 with VS Code):

  ```
  E/flutter: [ERROR:flutter/runtime/dart_isolate.cc(146)] Could not prepare isolate.
  hot restart → code=1 "hot restart failed to complete: _flutter.runInView: (-32000) Could not run configuration in engine."
  ```

  **DevFS name clash fix (`--project-root`):** flutter_tools names the DevFS after
  `basename(projectRootPath)`, and `flutter run` has a hidden `--project-root` option. Running
  with `--project-root` pointing at a symlink to the game named `game-studio` gives the driver
  its own DevFS name, so the attaching IDE creates `game…` without destroying anything. On
  macOS with `flutter attach`, `--project-root` plus `--repoint-assets` was correct at every
  step of `s ATTACH s t A s t R s d A s t`: hot restart worked, and no fallback reload was
  needed after attaching. Verified on the Android phone (CPH2737) with VS Code: every re-point
  after attaching succeeded, every `s` rebuilt, `t` and VS Code reloads stayed unchanged
  (apart from one `t` after a manual scene edit, which correctly rebuilt), and both driver hot
  restarts returned `code=0`. For the Studio, the symlink
  would live in its own support folder, e.g. `<app support>/run/<project>-studio`. `--project-root`
  is hidden and undocumented, so this is a second private-API dependency.

  Caveats for the Studio: `_flutter.setAssetBundlePath` is a private engine extension (the
  one flutter_tools uses), so it may change between Flutter releases. The DevFS name clash is
  handled separately with `--project-root` (above). **Decided (Q74):** the Studio adopts
  `--project-root` plus the re-point, keeping "stop reloading while an IDE is attached" as the
  fallback. See `dev-docs/ARCHITECTURE.md`.
- **VS Code shows "paused" after any hot restart while both are connected** (driver `R` or
  VS Code's own restart), with no breakpoints set and a nonsense top frame (`List.add`,
  `int.&`, `rotl32` called from `List.add`). The game keeps running and `s`/`t` still work.
  Mechanism, reproduced on macOS with a stand-in client: a debug adapter turns on
  `pause_isolates_on_start` and asks DDS for `requirePermissionToResume(onPauseStart)`. Hot
  restart replaces the isolate (`IsolateExit` → `IsolateStart` → `PauseStart`), and the new
  isolate waits until that client resumes it. A stand-in client that never resumed left the
  game stuck at startup; VS Code does resume, but its UI keeps the "paused" state and fetches
  the stack of the running isolate, hence the random frames. Without an IDE-style client, the
  driver's restart emits no pause events at all. For the Studio: after its own hot restart
  with an IDE attached, the game depends on the IDE resuming the new isolate. Pressing
  Continue in VS Code clears the stale state. Worth re-checking against the Dart-Code issue
  tracker before relying on it.
- `flutter run --machine` emits `device.added` / `device.removed` for paired but unreachable
  devices (here two wireless iPhones with `"isConnected": false`) while it runs. The Studio's
  device dropdown should ignore devices that aren't connected.
- Testing pitfall: if an edit writes the same bytes the file already has, the hash doesn't
  change and nothing rebuilds. That's correct behavior, but it looks like a failed Hot-swap.
  The driver now makes every edit unique.
