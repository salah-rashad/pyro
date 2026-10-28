# Pyro (desktop app)

The Pyro editor: a Flutter desktop app (macOS first-class; Windows and
Linux built in CI). Released as binaries on GitHub Releases, not on pub.dev.

```bash
flutter run -d macos
```

Run `dart pub get` once at the repository root first: the app is a member of
the root pub workspace.

> **Status:** early preview, in progress. See
> [`docs/phases.md`](../../docs/phases.md) for what is built.

## Play

Open a project, then press **Play** in the toolbar (the project needs a Flutter
SDK, a compatible `pyro_runtime` and a `macos/` folder; when Play is grey, the
toolbar says what to fix). Pyro runs the project's own game with
`flutter run --machine` and:

- **Hot-swaps** a Scene when you save it, and reloads the game's Dart code when
  you save a file under `lib/` (after `build_runner` is done with it);
- offers **Restart game** when an image a Scene uses changes, or when Hot-swap
  stops reaching the game;
- shows **Game stopped** when the game exits by itself, and asks before
  stopping a running game when you quit;
- copies the game's debugger address with **Attach debugger**, for VS Code or
  Android Studio (a short guide opens; the address is never shown or logged).

The **Console** at the bottom holds the generator's, the game's and Pyro's own
lines (the last 10,000), with debugger auth codes masked. Pyro also runs
`build_runner watch` for the project (or leaves yours alone and shows
"External build_runner"). Play writes nothing inside your project.

## Play from the command line

`bin/play.dart` is a developer tool kept from the vertical slice (spec 005): it
runs a game through the same Play client (`lib/process/`) without the editor.
It starts the game with
`flutter run --machine` on macOS, and hot-reloads it when a Scene under
`assets/scenes/` is saved, so the Scene Hot-swaps in the running game:

```bash
dart run bin/play.dart ../../example
```

| Option | Meaning |
|---|---|
| `--flutter <path>` | the `flutter` executable (default: `flutter` on `PATH`) |
| `--record <file>` | also write `flutter run`'s raw output to `<file>`, auth codes masked |

While it runs, type `r` + Enter to hot-reload, or `q` + Enter (or Ctrl-C) to
stop. It exits with 1 if the game couldn't start, otherwise with the game's
exit code. The VM service address never appears in its output.

To measure the save-to-screen loop on the `example/` game (spec 005,
SC-004–SC-006), with the game not already running:

```bash
dart run benchmark/hot_swap_latency.dart ../../example
```

The same benchmark, with a `flutter attach` stand-in for an IDE kept attached
(spec 007, SC-002), and the Console's throughput check:

```bash
dart run benchmark/hot_swap_latency.dart ../../example --with-attach
dart run benchmark/console_throughput.dart
```
