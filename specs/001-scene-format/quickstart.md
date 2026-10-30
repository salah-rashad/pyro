# Quickstart: Validating the Scene Format

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

How to check that the feature works once it's built. The rules are in
[contracts/scene-file-v1.md](contracts/scene-file-v1.md); this guide doesn't repeat them.

## Prerequisites

- Flutter 3.44 or later on the path: `export PATH="$PATH:/Users/salah/Library/flutter/bin"`
- From the repository root: `dart pub get`

## 1. Run the tests

```bash
cd packages/pyro_runtime && flutter test
```

Expected: everything passes. The suite covers each part of the spec (files are in `test/scene/`
unless a path is given):

| Spec | Test file | Fixtures |
|---|---|---|
| Story 1, FR-014–FR-017, SC-001 | `round_trip_test.dart` | `test/fixtures/scenes/canonical/*.scene.json`, `non_canonical/*` |
| Story 2, FR-009–FR-012 | `overrides_test.dart` | `canonical/overrides.scene.json` |
| Story 3, FR-018–FR-020a, SC-004 | `schema_version_test.dart` | `version/*.scene.json` |
| Story 4, FR-021–FR-025, SC-005 | `tree_repair_test.dart` | `damaged/*.scene.json` + `damaged/*.expected.scene.json` |
| FR-024a | `test/loader/repair_warning_test.dart` | none |
| Edge cases, FR-026 | `errors_test.dart` | `invalid/*.scene.json` |
| Research R5 (pure Dart) | `scene_imports_test.dart` | none |

## 2. Check a round trip by hand

1. Copy `test/fixtures/scenes/canonical/all_kinds.scene.json` to a scratch folder and commit it
   to a scratch git repository.
2. From a scratch script, overwrite the file with
   `SceneCodec.encode(SceneCodec.decode(text).scene)`.
3. `git diff` shows nothing (SC-002).
4. Change one Node's `position` in the decoded Scene, encode, and diff: only that Node's
   `position` line changes (SC-003).

## 3. Reproduce a damaged merge

1. Open `test/fixtures/scenes/damaged/merge_moved_and_deleted.scene.json`. It lists one Node
   under two parents, lists a child that doesn't exist, and has an orphan, the situation from
   Story 4.
2. Decode it. Expected: no exception, `repairs.describe()` prints three lines (one per issue,
   with Node IDs), and the encoded result equals
   `merge_moved_and_deleted.expected.scene.json`.
3. `test/loader/repair_warning_test.dart` covers the debug output: one warning block listing the
   three repairs and telling you to open and save the Scene in Pyro. The release check (nothing
   printed) needs a running game and is done in Phase 3 with `example/`.

## 4. Measure the performance budget (SC-006)

```bash
cd packages/pyro_runtime
dart run benchmark/scene_codec_benchmark.dart
dart compile exe benchmark/scene_codec_benchmark.dart -o /tmp/scene_bench && /tmp/scene_bench
```

The benchmark builds a deterministic 1,000-Node Scene (entities with Behaviors, sprites,
hitboxes), then times `decode` and `encode` over 50 runs after warm-up. Expected for the AOT
binary on the reference Mac: median decode and median encode each under 100 ms. Record the
numbers in `dev-docs/ARCHITECTURE.md` alongside the spike measurements.

## 5. Refuse a newer file

Decode `test/fixtures/scenes/version/newer.scene.json` (`"schemaVersion": 2`). Expected:
`UnsupportedSchemaVersion`, with a message naming version 2 and supported version 1; the file's
modification time is unchanged.
