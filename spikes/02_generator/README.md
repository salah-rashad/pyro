# Spike #2 — Generator shape and latency

Throwaway code for the v0.0 de-risking spike (`dev-docs/project-plan.md` §14 row 2, §7.3, §9.2,
§15.3 item 2; decisions Q38, Q48, Q68). Findings go into `dev-docs/ARCHITECTURE.md`; nothing here
ships.

| Folder | What it is |
|---|---|
| `studio_annotations/` | Stand-in for `flame_studio_annotations`: `@StudioBehavior`, `@StudioComponent`, `@Editable`. |
| `studio_generator/` | Stand-in for `flame_studio_generator`. Two builders: `studio_scan` (per library, `run_only_if_triggered`, writes `<file>.studio.json` to the build cache) and `studio_aggregate` (`$lib$`, `build_to: source`, reads every `.studio.json` and writes `lib/flame_studio.g.dart` + `lib/flame_studio.manifest.json`). |
| `example_game/` | A small Flame game (3 annotated types) with its **committed** Registry and Manifest, and a test that uses the Registry. |
| `bench/` | `gen_project.dart` (synthetic mid-size project), `measure.dart` (watch latency harness), `lock_probe.dart` (lock probe and a Studio-policy simulator). |

## What is being checked

1. A `$lib$` aggregator writes **both** the Registry and the Manifest into `lib/` (*Q68*).
2. `build_runner watch` updates them within ~3 s of a save on a mid-size project, and
   `triggers` keep unannotated files cheap.
3. A lock probe can tell that a `build_runner` is already running (*Q48*), and the Studio can
   react to one taking over.
4. `build_runner build --only-check` exists and works for CI (*Q68*); build_runner ≥ 2.14 (*Q48*).

## Quick start

Prerequisites: Flutter stable (tested with 3.44.2 / Dart 3.12.2) on your `PATH`.

### 1. The generator on a small game

```bash
cd spikes/02_generator/example_game && flutter pub get
```

```bash
dart run build_runner build
```

`lib/flame_studio.g.dart` and `lib/flame_studio.manifest.json` are committed, so a fresh clone
already has them; the build should report `wrote 0 outputs` for them. Then check the Registry
works and matches the Manifest:

```bash
flutter test
```

### 2. Watch latency on a synthetic mid-size project

From `spikes/02_generator/bench`:

```bash
dart pub get
```

```bash
dart run bin/gen_project.dart --out ../sample --files 300 --annotated 42
```

```bash
cd ../sample && flutter pub get && dart run build_runner build && cd ../bench
```

```bash
dart run bin/measure.dart --project ../sample --runs 5
```

`measure.dart` starts `build_runner watch`, runs every scenario 5 times (each edit is unique and
reverted afterwards) and prints a Markdown table. Time starts when the edit's write returns.
`gen_project.dart` options: `--files`, `--annotated`, `--no-triggers` (scanner runs on every
file), `--flavor dart` (pure Dart with Flame-shaped stubs, so the newest build_runner resolves;
see finding 1). `sample*/` folders are gitignored.

### 3. Lock probe

With and without a `dart run build_runner watch` running in `../sample` from another terminal:

```bash
dart run bin/lock_probe.dart ../sample
```

Prints `none` (build_runner ≥ 2.14 never ran there), `free` or `held`. `--poll` prints every
change. To play the Studio's part (start a watcher if the lock is free, go to "External
build_runner" if it is held, follow takeovers):

```bash
dart run bin/lock_probe.dart ../sample --studio
```

Then, from another terminal in `../sample`, try `dart run build_runner watch`, Ctrl-C,
`dart run build_runner build` and `dart run build_runner stop`, and watch what it logs.

### 4. `--only-check` (needs build_runner ≥ 2.16, so the pure-Dart flavor)

```bash
dart run bin/gen_project.dart --out ../sample_dart --flavor dart
```

```bash
cd ../sample_dart && dart pub get && dart run build_runner build
```

```bash
dart run build_runner build --only-check
```

Exit 0. Hand-edit `lib/flame_studio.manifest.json` (or an annotated file) and run it again:
exit 1.

## Results

macOS 26.2, Apple M4 (10 cores, 16 GB), Flutter 3.44.2 / Dart 3.12.2, 2026-10-16.
build_runner **2.15.1** for Flutter projects (the newest that resolves with Flutter 3.44.2, see
finding 1), **2.17.1** for the pure-Dart flavor.

| Check | Result |
|---|---|
| `$lib$` aggregator writes Registry **and** Manifest into `lib/` | ✅ both, from one builder, `build_to: source` |
| Registry compiles and works (factories + setters) | ✅ `flutter analyze` clean, `flutter test` passes |
| Watch updates both files ≤ ~3 s (300 files, 42 annotated, Flame) | ✅ median **0.9 s**; first save after watch start **2.8 s** |
| Same at 1000 files, 142 annotated | ✅ median **0.9–1.0 s**; first save **2.8–2.9 s** |
| `triggers` / `run_only_if_triggered` skip unannotated files | ✅ "259 not triggered", but saves only up to ~0.1 s per save here |
| Lock probe detects a running `watch` / `build` | ✅ `held`, ~1–4 ms per probe, never disturbs the watcher |
| Studio can follow another process taking over | ✅ with one policy change (finding 6) |
| `build --only-check` for CI | ✅ on 2.17.1; ❌ not available on Flutter 3.44.2 (build_runner capped at 2.15.1) |
| Output byte-identical on a clean rebuild | ✅ |
| build_runner ≥ 2.14 (Q48) | ✅ lock and takeover behave the same on 2.15.1 and 2.17.1 |

### Watch latency (median of 5, range in brackets)

"Build done" is when build_runner prints `Built with build_runner`; "reports" is its own build
duration. Outputs are only rewritten when their content changes, so "unchanged" means the file
wasn't touched.

**Flutter + Flame, 300 files (42 annotated), triggers on, build_runner 2.15.1:**

| Scenario | Manifest updated | Registry updated | Build done | build_runner reports |
|---|---|---|---|---|
| First save after watch start (tooltip) | 2822 ms | unchanged | 2825 ms | 2.36 s |
| Annotated: tooltip edit | 948 ms (810–954) | unchanged | 951 ms | 0.45–0.50 s |
| Annotated: add an `@Editable` field | 916 ms (855–961) | 916 ms (855–961) | 919 ms | 0.44–0.49 s |
| Annotated: method body edit | unchanged | unchanged | 887 ms (791–922) | 0.41–0.45 s |
| Unannotated leaf file | unchanged | unchanged | 429 ms (383–487) | 0.02 s |
| Unannotated core file (all annotated files import it) | unchanged | unchanged | 897 ms (862–973) | 0.44–0.49 s |
| New annotated file | 903 ms (865–930) | 903 ms (865–930) | 904 ms | 0.42–0.46 s |

**All configurations** (build done, median; "first" = first save after watch start):

| Configuration | First | Annotated edit | Add field | Body edit | Leaf edit | Core edit | New file |
|---|---|---|---|---|---|---|---|
| Flutter, 300 files, triggers on | 2825 | 951 | 919 | 887 | 429 | 897 | 904 |
| Flutter, 300 files, triggers off | 2665 | 948 | 945 | 920 | 493 | 966 | 899 |
| Flutter, 1000 files, triggers on | 2818 | 1012 | 1006 | 916 | 481 | 990 | 903 |
| Flutter, 1000 files, triggers off | 2921 | 938 | 1012 | 924 | 494 | 1096 | 916 |
| Pure Dart, 300 files, triggers on (2.17.1) | 527 | 496 | 505 | 473 | 484 | 498 | 447 |
| Pure Dart, 300 files, triggers off (2.17.1) | 512 | 491 | 513 | 492 | 487 | 536 | 500 |

All times in ms.

**Other timings (Flutter, 300 files):**

| What | Time |
|---|---|
| First `build_runner build` in a fresh checkout | ~14–16 s, of which ~10 s is the AOT compile of the builders |
| Full build with a compiled build script, no cache (`studio_scan` only) | 2.4 s (triggers on) / 2.5 s (off); 1000 files: 2.7 s / 2.9 s |
| `build_runner watch` start to first "Built" with a warm cache | 0.9 s |
| Builder code changed (e.g. a generator upgrade) | Recompiles the build script, ~10 s |

## Notes

**1. Flutter 3.44.2 caps build_runner at 2.15.1 (dead end, then workaround).** Flutter 3.44.2
pins `meta: 1.18.0`; `analyzer` ≥ 13.1.0 needs `meta ^1.18.3`, and build_runner ≥ 2.15.2 needs
`analyzer ≥ 13.3.0`. So in any Flutter project on 3.44.2, `build_runner: ^2.17.1` fails to
resolve, and an unconstrained one resolves to **2.15.1** (with `analyzer 13.0.0`,
`build 4.0.7`, `source_gen 4.2.4`, `dart_style 3.1.9`). The generator first required
`analyzer ^14`/`build ^5` and didn't resolve at all; it now accepts `analyzer >=12 <15`,
`build >=4 <6`, `source_gen >=4 <5`, `dart_style >=3 <4`, and the same code builds against both
ends. Flutter 3.47.0 changed the pin to `meta: ^1.18.3` (checked in `packages/flutter/pubspec.yaml`
at the 3.47.0 and 3.47.7 tags), so Flutter ≥ 3.47 should get build_runner 2.17; not tested here
(only 3.44.2 is installed). Consequence: **`--only-check` (2.16.0+) isn't available to Flutter
3.44 projects.** On 2.15.1 it fails with `Could not find an option named "--only-check".`

**2. Where the time goes.** In watch mode every save pays a fixed ~0.4–0.5 s: build_runner
debounces file events for 250 ms (`lib/src/commands/watch/watcher.dart`) plus FSEvents delivery.
The pure-Dart flavor shows only that: builds take 0.01–0.06 s, saves finish at ~0.5 s. In the
Flutter flavor, each changed library that must be re-resolved costs another ~0.4 s
("spent 0.41s resolving"): re-resolving against Flutter + Flame, independent of project size
(300 → 1000 files changed almost nothing). The first build after a watch starts costs ~2.4 s,
the analyzer building its element model for the Flutter SDK (a one-off `build` pays it too). That first save after the Studio starts its watcher is the only one
near the 3 s budget.

**3. Triggers work but matter little here.** With `run_only_if_triggered: true` the scanner
logs "259 not triggered" and skips unannotated files: build_runner's own time for a core edit is
0.47 s vs 0.49 s (300 files) and 0.52 s vs 0.60 s (1000 files), a leaf edit 0.02–0.03 s vs
0.02–0.04 s, a full build 2.4 s vs 2.5 s (2.7 s vs 2.9 s at 1000 files). The
analyzer cost of resolving annotated files is the same either way, and with triggers on, an
edit to a file that every annotated file imports still re-runs the scanner on all of them
("40 same"). Keep triggers (free, and the gap grows with heavier unannotated code), but they are
not what keeps latency low. Annotation triggers match by name (`annotation StudioBehavior`), so
a user re-exporting the annotations under another name would need their own trigger.

**4. Outputs only change when their content does.** build_runner (≥ 2.14) doesn't rewrite
unchanged outputs, and the aggregator's output depends only on the fragments, so a body edit,
an unannotated edit or a revert leaves both files untouched. A tooltip edit changes only the
Manifest; the Registry (factories + setters) changes only when types or fields do. The Studio
can watch the Manifest file and re-parse on every change without filtering no-op writes.

**5. Generator errors.** The aggregator writes both outputs, then calls `log.severe`. The build
fails (exit 1, `Failed to build`), but the Manifest on disk already has `errors` filled in, so
the Studio can show them inline (§7.3). The watch keeps running and recovers on the next good
save, and a no-change rebuild repeats the failure, so the error doesn't silently disappear.
Types with errors are left out of both outputs. A first version kept one of two classes with
the same Type ID (whichever path sorted first); the Registry then built the wrong class for
`Player`. Now every class sharing an ID is dropped and the error names all sources.

**6. The lock.** The lock file is `.dart_tool/build/lock/build_runner.lock`, created by the
first build_runner ≥ 2.14 command and left behind. The `dart run build_runner` process (the
`dartvm`, not the AOT builder child) holds an exclusive lock on it while any command runs:
`watch`, `serve` **or a one-off `build`**. The probe opens it with `FileMode.append` (no
truncate, no create), tries `lockSync(FileLock.exclusive)` and unlocks at once: ~1–4 ms. 50
probes against a running watch left it running and created no `.requested` file. `kill -9` of
the `dart run` process frees the lock, and the AOT child doesn't outlive it. Behavior on 2.15.1
and 2.17.1 is identical:

| Another process runs… | The running `watch`… |
|---|---|
| `build_runner watch` | finishes its build, prints `Exiting as requested by another build_runner process.`, exits **0** after ~0.3 s; the new one takes the lock |
| `build_runner build` | exits the same way; the build runs, exits, and **nobody is watching** |
| `build_runner stop` | exits the same way; the `stop` process exits at once |
| the probe | nothing |

Run under the `--studio` simulator, the §9.2 policy ("if its watcher later exits because
another process took over, it switches to external mode") handles a second `watch`. After a
one-off `build`, though, the external holder finishes within seconds and nobody is watching.
The simulator therefore re-probes after its watcher exits: held → "External build_runner", and
when that lock is released it restarts its own watcher (it did, 1 s after the build). After a
`build_runner stop`, the lock is already free at the re-probe, and restarting would undo what
the user asked for. Since the exit message and code are identical in all three cases, the
proposed rule is: **after a takeover exit, if the lock is held → external mode and restart own
watcher when it's released; if it's already free → treat it as `stop` and show "Generator
stopped" with a Start button.** ◇ proposed

In a pub workspace, a package build also takes a *shared* lock on
`<workspace root>/.dart_tool/build/lock/build_runner.workspace.lock`, and `--workspace` builds
take it exclusively. The probe checks the package lock exclusively and (with
`--workspace-root`) the workspace lock with a *shared* attempt, which fails only for a
whole-workspace build. Not exercised here; no workspace project was built.

**7. `--only-check` (2.17.1).** Passes (exit 0) when the committed files match; fails (exit 1)
for a hand-edited Manifest (`I lib/flame_studio.manifest.json`), an annotated source changed
without regenerating (`I`), or a deleted output (`M`), and leaves the files as they were. It
works with no build cache at all (fresh clone in CI: `rm -rf .dart_tool/build`, exit 0 in 14 s
including the builder compile). It lists the files but prints no diff. Clean rebuilds were
byte-identical (`shasum`). Note it is a build_runner command like any other: run while the
Studio's watcher is up, it takes the lock and stops that watcher (finding 6).

**8. Generated code.** Registry setters cast scene values (`(v as num).toDouble()`,
`Enum.values.byName`, `v as Vector2`); converting JSON to `Vector2`/`Color`/assets/references is
left to the Runtime. The Registry imports each field type's *declaring* library, which gives
`package:flame/src/sprite_animation.dart` (implementation import) and
`package:vector_math/vector_math.dart` (a package the game doesn't depend on directly). It
compiles; the lints are silenced with `ignore_for_file: type=lint, implementation_imports`. The
real generator should import types through the libraries the user's file imports. Defaults:
literals are evaluated; anything else (including `const Color(0xFFFFFFFF)`) is stored as
`defaultSource`. The analyzer can evaluate const initializers of non-const fields if needed.
`supertypes` lists all interfaces and mixins (for `Player`, 14 entries including
`ReadOnlyScaleProvider`); the Studio probably wants class names plus `EntityMixin` only.

**9. The aggregator pattern.** `studio_scan` writes one JSON fragment per annotated library to
the build cache (nothing for other libraries). `studio_aggregate` is a `$lib$` builder with
`required_inputs: [".studio.json"]` that reads them with `findAssets(Glob('lib/**.studio.json'))`.
This is not quite the pattern source_gen's own `CombiningBuilder` uses: that one combines
`.g.part` fragments **per library** into `<file>.g.dart`. Same idea (cache fragments, then
combine), different scope.
