# Contract: README recipe and dry-run report

## The recipe (root `README.md`, section "Add Pyro to a Flame project (early preview)")

It is the stand-in for the "Add Pyro" flow (*Q82*). Every snippet is copied from `example/`, which
the contract job already builds, so it cannot drift. Order and content:

1. **What you need**: Flutter 3.47 or newer stable and Xcode (macOS); a Flame project with
   Flame ≥ 1.36; a Mac. What the recipe changes in the project: only the files it names.
2. **Packages**: `pyro_annotations` and `pyro_runtime` as git dependencies on this repository
   (`git:` with `path: packages/<name>`), `pyro_generator` in `dev_dependencies`,
   `build_runner` ≥ 2.14 (the ^2.15.1 that `example/` uses); plus the `dependency_overrides`
   they need while they are not on pub.dev (they depend on each other by version, found in spike
   #2's `gen_project.dart --pyro`). Exact text copied from `example/pubspec.yaml` and checked by
   the dry run.
3. **Scenes folder**: `assets/scenes/` (and `assets/images/` if used) listed under `flutter: assets:`.
4. **Generate**: `dart run build_runner build`, which writes `lib/pyro.g.dart` and
   `lib/pyro.manifest.json`; commit them.
5. **Load the Scene** in the game: the `PyroScene.load(...)` call from `example/lib/example_game.dart`
   with the generated Registry, and a note that Hot-swap works only for Scenes loaded this way.
6. **macOS target**: `flutter create --platforms=macos .` if there is no `macos/` folder; the debug
   entitlement `com.apple.security.network.server` that a debug build needs (checked against
   `example/macos/Runner/DebugProfile.entitlements`).
7. **Build and open Pyro** from source: `dart pub get`, `flutter run -d macos` from `apps/editor`
   (the early preview has no signed build).
8. **Open your project, then Play**: where to click; what the status bar says; how to Attach VS Code
   (the three facts of FR-029).
9. **If something goes wrong**: the generator reports a lock or "External build_runner" (what that
   means and how to stop it with `dart run build_runner stop`); the Runtime is incompatible (the
   message and the version to use); macOS debug signing failure; Hot-swap stopped working (what
   *Restart game* does).

It makes no promise about Windows or Linux.

## The dry-run report (`specs/007-play/dry-run-report.md`, FR-033)

Written during the run, one section per attempt:

```text
## Attempt N — <date>
Project: <name, URL, commit>          Flutter: <version>      Mac: <model, macOS version>
Started: <time>   First running scene: <time>   Elapsed: <h:mm>   Helped: yes/no
| Step | Result | Notes (where stuck, what was unclear) |
|---|---|---|
| 1 Add the packages | pass/fail | |
| 2 …through the tester task of SC-001 | | |
Fixes made before the next attempt: <README text / Pyro message / code> — <commit>
Verdict: passed without help / needs another attempt
```

The phase closes when the last attempt's verdict is "passed without help" (SC-001); the elapsed
time is recorded and does not decide the verdict (clarification).
