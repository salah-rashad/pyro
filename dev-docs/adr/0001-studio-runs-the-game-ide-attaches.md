# Pyro runs the game; the IDE attaches to it

As in Unity, Play lives in Pyro: it launches the game with `flutter run --machine` on the chosen device, owns that process, and hot-swaps Scenes into it on save. Developers who want breakpoints or code hot reload attach their IDE's debugger to the running process instead of launching the game from the IDE. We chose this so Pyro controls the whole loop (Play, Stop, device choice, Console, Hot-swap) and does not depend on which IDE the developer uses or how they start the game. The cost is that "Attach" is an extra step developers aren't used to in Flutter, so Pyro has to make it easy.

## Considered Options

- **IDE owns the run, Pyro only edits files**: hot-swap through the IDE's hot reload. Rejected: Pyro can't offer Play/Stop, a device picker or a Console, and the loop depends on each developer's IDE setup.
- **Pyro runs the game, IDE attaches** (chosen).
- **Pyro runs the game, IDE attaches, Pyro stops reloading while an IDE is attached**: the user reloads from the IDE instead. Kept as the fallback if the workarounds below stop working.

## Spike #1 result (2026-10-16)

The decision holds. Spike #1 confirmed that an IDE attached through the fixed DDS port can set breakpoints and hot-reload while Pyro's `flutter run` stays connected, on the iOS simulator and a physical Android phone. It also showed that two flutter_tools clients don't share a DevFS cleanly: the attaching IDE deletes Pyro's DevFS when their names match (breaking Pyro's hot restart on physical devices), and the engine serves assets from whichever client last pointed it at its own copy, so scene saves get ignored. Pyro therefore runs the game under a differently named project root (a symlink, via flutter's hidden `--project-root`) and points the engine back at its own DevFS before every reload (`_flutter.setAssetBundlePath`). Both are private interfaces, so Pyro re-checks them on each Flutter stable release and keeps the "stop reloading while an IDE is attached" fallback (Q74; attach URI handling in Q81; details in [`ARCHITECTURE.md`](../ARCHITECTURE.md#spike-1--play-hot-swap-and-attach)).
