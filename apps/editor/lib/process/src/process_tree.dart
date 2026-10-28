import 'dart:io';

/// The pids of every process below [pid], children before their parents'
/// siblings, so signalling them in order never orphans one first.
///
/// `dart` is often a wrapper script (puro's, for one) that starts the real
/// Dart VM as a child and does not `exec` it, so signalling the wrapper alone
/// leaves `build_runner` running. Reads `pgrep -P`; empty on Windows and when
/// `pgrep` is missing or fails.
Future<List<int>> processDescendants(int pid) async {
  if (Platform.isWindows) return const [];
  final found = <int>[];
  Future<void> walk(int parent) async {
    final ProcessResult result;
    try {
      result = await Process.run('pgrep', ['-P', '$parent']);
    } on ProcessException {
      return;
    }
    if (result.exitCode != 0) return;
    for (final line in (result.stdout as String).split('\n')) {
      final child = int.tryParse(line.trim());
      if (child == null) continue;
      await walk(child);
      found.add(child);
    }
  }

  await walk(pid);
  return found;
}
