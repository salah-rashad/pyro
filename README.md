# Pyro

Pyro is a scene editor for [Flame](https://flame-engine.org) games. You place entities, sprites,
hitboxes and your own components and behaviors in a visual editor, press **Play**, and the game runs
with your scene. Save a scene in Pyro and the running game shows it a moment later, without a
restart.

This is an early preview. It runs on macOS, and Pyro itself is built from source (there is no signed
build yet).

- [`apps/editor`](apps/editor): the Pyro desktop app.
- [`packages/pyro_runtime`](packages/pyro_runtime): the package that loads a scene into a Flame game.
- [`packages/pyro_annotations`](packages/pyro_annotations) and
  [`packages/pyro_generator`](packages/pyro_generator): mark your components and behaviors, and
  generate what Pyro needs to know about them.
- [`example`](example): a small game made with Pyro. Every snippet below is copied from it.

## Add Pyro to a Flame project (early preview)

### 1. What you need

- A Mac with Flutter 3.47 or newer (stable) and Xcode.
- A Flame game, with Flame 1.36 or newer.

The steps below change only the files they name.

### 2. Add the packages

In your game's `pubspec.yaml`, add the Pyro packages from this repository. They are not on pub.dev
yet, so `pyro_annotations` also needs an override (the other two packages ask for it by version).
Replace the `ref` with the commit of this repository you built Pyro from.

```yaml
dependencies:
  pyro_annotations:
    git:
      url: https://github.com/salah-rashad/pyro.git
      ref: <commit>
      path: packages/pyro_annotations
  pyro_runtime:
    git:
      url: https://github.com/salah-rashad/pyro.git
      ref: <commit>
      path: packages/pyro_runtime

dev_dependencies:
  build_runner: ^2.15.1
  pyro_generator:
    git:
      url: https://github.com/salah-rashad/pyro.git
      ref: <commit>
      path: packages/pyro_generator

dependency_overrides:
  pyro_annotations:
    git:
      url: https://github.com/salah-rashad/pyro.git
      ref: <commit>
      path: packages/pyro_annotations
```

`build_runner` must be 2.14 or newer; Pyro runs it for you and does not work with older versions.
Then run `flutter pub get`.

### 3. Make a scenes folder

Create `assets/scenes/` in your project (and `assets/images/` if you use images) and list them
under `flutter:` in your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/images/
    - assets/scenes/
```

### 4. Generate

Mark your own components and behaviors with `@PyroComponent()` and `@PyroBehavior()` (see
[`example/lib/behaviors/spin.dart`](example/lib/behaviors/spin.dart)), then run:

```bash
dart run build_runner build
```

This writes `lib/pyro.g.dart` and `lib/pyro.manifest.json`. Commit both. Pyro reads the manifest to
know your types; the game reads the generated registry. While Pyro is open it runs
`build_runner watch` for you, so new types appear in the editor after you save.

### 5. Load the scene in your game

Load the scene through the generated registry (from
[`example/lib/example_game.dart`](example/lib/example_game.dart)):

```dart
import 'package:pyro_runtime/pyro_runtime.dart';

import 'pyro.g.dart';

const scenePath = 'assets/scenes/level1.scene.json';

// In your game's onLoad:
final scene = await PyroScene.load(scenePath, registry: pyroRegistry);
await world.add(scene);
```

Hot-swap works only for scenes loaded this way.

### 6. The macOS target

If your project has no `macos/` folder, add it:

```bash
flutter create --platforms=macos .
```

A debug build also needs permission to open the network port that Play and your IDE use to talk to
the game. A `macos/` folder made by `flutter create` already has it; if yours is older or was
edited, make sure `macos/Runner/DebugProfile.entitlements` has this, next to the keys already there:

```xml
<key>com.apple.security.network.server</key>
<true/>
```

### 7. Build and open Pyro

Pyro is built from source for now:

```bash
dart pub get
cd apps/editor
flutter run -d macos
```

### 8. Open your project, then Play

1. In Pyro, open your project's folder. The status bar shows the Flutter SDK it found, the
   `pyro_runtime` version and the generator ("Generating…", then "Up to date").
2. Add a new scene (`assets/scenes/`), place an entity, give it a sprite and a hitbox, and attach one
   of your behaviors from the inspector.
3. Press **Play** in the toolbar. The game builds and opens; the Console shows its output. If Play is
   grey, hover it or read the line in the toolbar: it says what is missing and how to fix it.
4. Change something in the scene and save (⌘S). The running game shows the change a moment later.

To debug in your IDE while Pyro keeps working, press **Attach debugger**. Pyro copies the running
game's address to the clipboard (it never shows or stores it) and opens a short guide. In VS Code:

1. Select the game's device first: macOS (desktop), in the status bar.
2. Run "Flutter: Attach to Process" from the Command Palette and paste the address.
3. After a hot restart, VS Code may still show the game as paused while it runs. That is a stale
   state in VS Code.

Stop and Play again for a new address: each run has its own.

### 9. If something goes wrong

- **"External build_runner" in the status bar.** A `build_runner` that Pyro did not start is running
  in this project (a terminal, an IDE task). Pyro leaves it alone and starts its own when it ends.
  If it is stuck, `dart run build_runner stop` stops it. "Generator stopped" with a **Start** button
  means a `build_runner stop` ended Pyro's own run; press Start.
- **"Generator: not set up".** The status bar says why: `build_runner` missing or older than 2.14,
  or no Flutter SDK. Fix the `pubspec.yaml` and run `flutter pub get`.
- **Play is grey with "pyro_runtime…".** The project's `pyro_runtime` is missing or not one this
  Pyro can run. The message names the version to use.
- **macOS build fails with a signing error.** Open `macos/Runner.xcworkspace` in Xcode once, choose
  the Runner target, then Signing & Capabilities, and pick your team (or sign to run locally).
- **"Hot-swap stopped working" notice.** Two saves in a row did not reach the game. An IDE attached
  to an older run or a game left over from before can cause this. **Restart game** restarts the
  game once, from Pyro, and Hot-swap works again.

Pyro makes no promise about Windows or Linux yet.
