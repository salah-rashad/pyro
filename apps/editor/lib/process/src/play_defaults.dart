/// The timings and sizes of Play, the generator and the Console (spec 007,
/// data model "PlayDefaults"). Constants until a Settings window exists
/// (Phase 7); every other file reads them from here.
abstract final class PlayDefaults {
  /// How long Scene or Dart files must stay unchanged before a reload
  /// (spec 005, *Q122*).
  static const sceneQuiet = Duration(milliseconds: 150);

  /// How long a stop waits after `app.stop` before SIGTERM (spec 005).
  static const stopTimeout = Duration(seconds: 5);

  /// How long, after a Scene Hot-swap, the game has to print its
  /// Hot-swap report before the save counts as a miss (FR-011).
  static const hotSwapReportWait = Duration(seconds: 3);

  /// Consecutive misses after which Hot-swap is reported failed (FR-011).
  static const hotSwapMissLimit = 2;

  /// How long the generated files must stay unchanged, with an external
  /// `build_runner`, before a code reload (FR-012).
  static const codeReloadSettle = Duration(seconds: 2);

  /// How often the `build_runner` lock is probed while an external run
  /// holds it (research R8).
  static const lockReprobe = Duration(seconds: 1);

  /// How long, after Pyro's own `build_runner` exits because another run
  /// asked it to, the lock is watched for that run before the exit counts
  /// as `build_runner stop` (research R8). Measured: a `build` takes the
  /// lock about 100 ms after the exit and holds it for the build; a `stop`
  /// never does.
  static const takeoverWindow = Duration(seconds: 2);

  /// How often the lock is looked at during [takeoverWindow].
  static const takeoverPoll = Duration(milliseconds: 100);

  /// How many lines the Console keeps; the oldest drops first (R12).
  static const consoleCapacity = 10000;

  /// The shortest gap between two Console change notifications (R12).
  static const consoleNotify = Duration(milliseconds: 50);
}
