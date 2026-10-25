# Contract: Play orchestration

The Dart surface the editor window uses to run the game (`apps/editor/lib/process/`, no Flutter
import). Shapes are the contract; method bodies are tasks. Builds on spec 005's
`contracts/play-cli.md` (`PlayClient`, `PlaySession`, `PlayEvent`), which keeps working unchanged
for `bin/play.dart`.

## `PlayController`

One per open project. Created when the project opens, disposed when it closes.

```dart
final class PlayController {
  PlayPhase get phase;                       // stopped | starting | running | stopping
  PlayBlock? get block;                      // why Play is disabled, or null (data-model)
  Stream<PlayPhase> get phases;
  Stream<PlayNotice> get notices;            // image changed, hot-swap failed, game stopped
  bool get canAttach;                        // phase == running

  Future<void> play();                       // no-op unless phase == stopped and block == null
  Future<void> stop();                       // safe to call at any phase
  Future<void> restartGame();                // full restart; re-arms the Hot-swap monitor
  String? copyDebuggerAddress();             // the only reader of the address; null if not running
}
```

Rules:

1. `play()` never starts a second session (FR-002). It creates the run link, then calls
   `PlayClient.start(project, runLink: link)`.
2. Every `PlayEvent` becomes at most one Console line (source `pyro` for lifecycle events, `game`
   for output) and, for `PlayStopped(requested: false)`, a `GameStopped` notice.
3. `stop()` ends in `stopped` even if `app.stop` and SIGTERM fail (SIGKILL after the existing
   delay) and always removes the run link and clears the address.
4. `copyDebuggerAddress()` is the **only** public way to read the address. The Console, events,
   notices, logs and `toString` never contain it (FR-024).

## `PlayClient.start` change

```dart
Future<PlaySession> start(
  String projectPath, {
  RunLink? runLink,                          // NEW: null keeps spec 005's behavior
  void Function(String line)? onStdoutLine,
});
```

When `runLink` is set, the arguments are the spec 005 arguments plus `--project-root <link path>`;
the working directory stays the real project. `PlayStartException` keeps its messages (the
`macos/` text is part of the disabled reason).

## `RunLink`

```dart
final class RunLink {
  static Future<RunLink?> create(String projectPath, {required String supportDir});
  String get path;                           // <support>/run/<project-id>/<name>-pyro
  Future<void> remove();                     // removes only the link, never its target
  static Future<void> sweep(String projectPath, {required String supportDir});
}
```

- `<project-id>` = first 12 hex digits of SHA-1 of the canonical project path.
- `<name>` = the project folder's basename; the link name is `<name>-pyro`, never equal to `<name>`.
- `create` returns null (with the reason sent to the Console by the caller) when the link cannot be
  made; Play then runs without it (research R2).
- `remove` and `sweep` delete the link entry only. They must never follow it (a test with a project
  folder inside the link's reach asserts the project survives).

## Reload sequence (inside `PlaySession`)

For a batch that contains at least one Scene path:

```text
repoint = vm.listViews() -> vm.setAssetBundlePath(view, <baseUri>/build/flutter_assets)
if repoint ok:        app.restart(fullRestart: false)
else:                 app.restart(fullRestart: false)
                      vm.setAssetBundlePath(...)            # again, now that the sync made the folder
                      vm.evict(view isolate, each scene path)
                      app.restart(fullRestart: false)       # once more
```

Code-only batches send `app.restart(fullRestart: false)` alone. All three paths go through the
existing one-in-flight, one-queued rule (*Q122*). `PlayReloading`, `PlayReloaded` and
`PlayReloadFailed` events keep their meaning; the second reload of the fallback is not a second
event.

## `VmServiceLink`

```dart
abstract interface class VmServiceLink {
  Future<List<ViewInfo>> listViews();                       // _flutter.listViews
  Future<void> setAssetBundlePath({required String viewId, String? isolateId,
                                   required String assetDirectory});  // _flutter.setAssetBundlePath
  Future<void> evict({required String isolateId, required String asset});  // ext.flutter.evict
  Future<void> close();
}
```

The real implementation wraps `vm_service`'s `VmService` over the address it was given. It throws
`VmServiceCallFailed` naming the method and the engine's message. The message never contains the
address. Tests use a fake that records the calls in order.

## Failure rule (`HotSwapMonitor`)

Inputs: the batch (paths, content hashes), `PlayReloaded` events and the game's report lines
([hot-swap-reports.md](hot-swap-reports.md)). Output: `PlayHotSwapFailed(paths, misses)` once, when
two saves in a row that changed a Scene's content got no report within 3 s of their reload. After
it, scene batches are dropped (code batches still reload) until `restartGame()`.

## Notices

| Notice | Raised when | Action offered |
|---|---|---|
| `GameStopped` | the game exits and Pyro did not ask | none; Play is already available |
| `ImageChanged(paths)` | a path in `ImageUse` changes on disk while Running | *Restart game* (`restartGame()`) |
| `HotSwapFailed` | the failure rule fires | *Restart game* |
| `GeneratorError` | the supervisor reports an error | none; details in the Console and status bar |

Each notice is replaced by the next of its kind rather than stacking.
