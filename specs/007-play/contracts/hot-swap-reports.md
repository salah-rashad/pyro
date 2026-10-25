# Contract: Hot-swap reports (the Runtime's debug lines)

The one change this phase makes to a package. `PyroScene` in `pyro_runtime` prints these lines to
the game's output in debug builds, so Pyro can tell what a Hot-swap did in **any** game
(research R1, FR-011).

## Lines

```text
[pyro] Scene loaded: <path>
[pyro] Scene reloaded: <path>
[pyro] Scene not reloaded: <path>: <first line of the error>
```

- `<path>` is the Scene's asset path as `PyroScene.load` received it, for example
  `assets/scenes/level1.scene.json`.
- One line per event. No other text on the line. Pyro matches the prefix `[pyro] Scene ` followed by
  `loaded`, `reloaded` or `not reloaded`, then `: `, then the path up to the next `: ` or end of line.
- `loaded`: printed once when a `PyroScene` finishes building its first tree.
- `reloaded`: printed after a Hot-swap rebuilt the tree because the content changed (the place
  `onReloaded` is called). Not printed when the content is unchanged.
- `not reloaded`: printed when a Hot-swap tried to rebuild and failed; the game keeps the Scene it
  had. The existing multi-line "Pyro couldn't Hot-swap" block stays as it is.

## Rules

1. Printed only under `kDebugMode`, from code already behind that guard. Release builds contain none
   of it (the existing release-build job checks this).
2. Printed with `debugPrint`, which is what the daemon reports as game output.
3. The format is stable: a change to it is a contract change, noted in `ARCHITECTURE.md` and covered
   by the loader tests.
4. `example/` stops printing its own `Scene reloaded` line; its `Scene loaded` and HUD stay.
   `benchmark/hot_swap_latency.dart` and the quickstart wait for `[pyro] Scene reloaded`.

## Pyro's use

| Line | `HotSwapMonitor` |
|---|---|
| `loaded` | arms the path |
| `reloaded` / `not reloaded` | counts as the game's report: clears the expectation, `misses = 0`, updates the content baseline |

A Scene the game never announced is never expected to report (no false failure).

## Tests (`packages/pyro_runtime/test/`)

- A first load prints `loaded` once.
- A changed file prints `reloaded` once; an unchanged one prints nothing.
- A file that cannot be rebuilt prints `not reloaded` with the error's first line and keeps the old
  tree.
- The helper that builds each line is pure and tested for all three formats. The `kDebugMode` guard
  cannot be switched off in `flutter test`, so it is checked on the release build (tasks T080).
