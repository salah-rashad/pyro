# Quickstart: Validating the Runtime

How to check that the feature works. The behavior is in [spec.md](spec.md), the shapes in
[data-model.md](data-model.md) and the formats in [contracts/](contracts/).

## Prerequisites

- Flutter 3.44.2 on `PATH` (the repository's pin, Q94), and `flutter pub get` run once at the
  repository root.
- For §4 and §5: the reference Mac (macOS, Apple M4).

## 1. Run the Runtime's tests

```bash
cd packages/pyro_runtime && flutter test
```

| Test file | Covers |
|---|---|
| `test/loader/build_test.dart` | Every Node kind and transform, sprite regions, hitbox props, Behaviors in order, the four-pass order seen from `onLoad`, references (forward, root, self, cycles), independent loads (US1, SC-001) |
| `test/loader/field_values_test.dart` | Every Field type's conversion and every mismatch from research R5 (US2 #4, #5) |
| `test/loader/errors_test.dart` | One fixture per error case in US2, each message checked for the Scene, Node, Type ID, field and asset (SC-002) |
| `test/loader/unknown_type_test.dart` | `error` and `skip` for unknown Behaviors, Custom components and Node kinds; references to skipped Nodes; the warning (US2 #1–#3, #8) |
| `test/loader/lookup_test.dart` | Names, paths, anchored paths, tags, types, ambiguity, misses, unmounted Scenes (US3, SC-005) |
| `test/loader/hot_swap_test.dart` | Changed, unchanged, animation-only and image-only reloads; failed rebuilds; overlapping reloads; the same `PyroScene` object; 100 alternating reloads (US4, SC-003) |
| `test/loader/stale_reference_test.dart` | A warning on a stale transform change and on re-adding, once per Node; no listeners on current Nodes; watchers released on the next swap (US4 #7) |
| `test/assets/asset_source_test.dart` | No prefix, `cache: false` texts, one decode per image, failed loads not cached, a caller's source used exclusively (US5) |
| `test/animation/animation_file_test.dart` | Every rule of contracts/anim-file-v1.md, frame → cell math, `stepTime` and `stepTimes` |
| `test/scene/overrides_test.dart` | `AssetRef` with and without `animation`; other shapes stay plain values; canonical round trip (FR-034) |

## 2. Run the Generator's tests after the Registry change

```bash
cd packages/pyro_generator && dart test
```

The goldens show `acceptsParent` on every Behavior and nothing else changed (research R6).

## 3. Load a Scene with a real generated Registry

```bash
cd packages/pyro_generator/fixture_game
dart run build_runner build -d
git diff --exit-code lib/pyro.g.dart lib/pyro.manifest.json   # the committed Registry is current
flutter test test/load_test.dart                                 # assets/scenes/fixture.scene.json loads through AssetSource.bundle()
```

## 4. Measure the budgets (reference Mac)

```bash
cd packages/pyro_runtime && flutter test benchmark/load_benchmark_test.dart
```

It prints the median (p95) of 20 runs on the 1,000-Node benchmark Scene for a load without image
decoding, a Hot-swap check that finds nothing changed, and a rebuild, plus the longest
synchronous pause during a load and during a rebuild. Pass: under 50 ms, 5 ms and 100 ms (SC-004).
The pause has no limit yet: record it, and set the limit from it (spec Clarifications). `flutter test` runs JIT with asserts, so passing here bounds a profile build.
Record the table in `dev-docs/ARCHITECTURE.md` under a new "Runtime" section.

## 5. Hot-swap in a running game and check release builds (reference Mac)

`fixture_game` has no platform runner, and Phase 3's `example/` (#13) is where a committed macOS
target arrives. Until then, use a throwaway app outside the repository. It isn't committed.

```bash
flutter create --platforms=macos /tmp/pyro_hot_swap && cd /tmp/pyro_hot_swap
# pubspec: depend on pyro_runtime and flame by path/version, declare assets/scenes/
# copy packages/pyro_generator/fixture_game/lib/ (Registry included) and assets/scenes/fixture.scene.json
# main.dart: a FlameGame whose onLoad does PyroScene.load(..., onReloaded: (s) => print('reloaded'))
flutter run -d macos
```

1. Edit a position in `assets/scenes/fixture.scene.json` and save, then hot reload (`r`): the Node
   moves and `reloaded` is printed (US4 #1).
2. Hot reload again without editing: nothing is rebuilt and nothing is printed (US4 #2).
3. Break the JSON, save and reload: the debug error names the Scene and the game keeps running
   (US4 #5). Fix it and reload: it rebuilds.
4. Build for release and check that the Hot-swap code is gone (SC-006):

```bash
flutter build macos --release
strings build/macos/Build/Products/Release/pyro_hot_swap.app/Contents/Frameworks/App.framework/App \
  | grep -c "couldn't Hot-swap"   # 0
```

`couldn't Hot-swap` is in the debug error that only the Hot-swap path prints (research R14).
Record the result in `dev-docs/ARCHITECTURE.md` with §4's table.

## 6. See an error the way a developer would

In `fixture_game`, rename an annotated Behavior's class, rebuild with `build_runner`, and run
`flutter test test/load_test.dart`. The failure names the Scene, the Node and the old Type ID and
suggests an explicit `id:` or `UnknownType.skip`. Undo with `git checkout lib`.
