import 'dart:io';

/// What the probe found at `build_runner`'s lock (contracts/generator-
/// supervisor.md, "BuildLockProbe").
enum LockProbeResult {
  /// Another process holds the lock: a `build_runner` is running.
  held,

  /// The lock file exists and nobody holds it.
  free,

  /// The lock file does not exist: `build_runner` never ran here.
  absent,
}

/// Asks the operating system whether a `build_runner` runs in a project
/// (research R8), without ever starting, stopping or signalling one.
///
/// `build_runner` locks `.dart_tool/build/lock/build_runner.lock` while it
/// runs and leaves the empty file behind when it exits, so the file's
/// existence says nothing; only the lock does.
class BuildLockProbe {
  /// Creates the probe.
  const BuildLockProbe();

  /// The lock file's path inside [projectPath].
  static String lockPath(String projectPath) =>
      '$projectPath/.dart_tool/build/lock/build_runner.lock';

  /// Probes [projectPath]'s lock. Creates no file: not the lock and not the
  /// `.requested` marker `build_runner` uses to ask a run to exit.
  Future<LockProbeResult> check(String projectPath) async {
    final file = File(lockPath(projectPath));
    if (!file.existsSync()) return LockProbeResult.absent;
    RandomAccessFile? handle;
    try {
      // Append: opens for writing without truncating what a run may keep
      // there. `FileLock.exclusive` does not wait, so a held lock throws.
      handle = await file.open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      return LockProbeResult.free;
    } on FileSystemException {
      return LockProbeResult.held;
    } finally {
      if (handle != null) {
        try {
          await handle.unlock();
        } on FileSystemException {
          // Nothing was locked.
        }
        await handle.close();
      }
    }
  }
}
