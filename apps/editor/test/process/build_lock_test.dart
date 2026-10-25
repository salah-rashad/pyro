import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

/// The `dart` that runs the helper: the SDK's own when `flutter test` says
/// where it is, else the one on `PATH`.
String get _dart {
  final root = Platform.environment['FLUTTER_ROOT'];
  // On Windows the SDK's launcher is `dart.bat`; `bin/dart` is a shell script.
  final name = Platform.isWindows ? 'dart.bat' : 'dart';
  return root == null ? name : '$root/bin/$name';
}

void main() {
  late Directory project;
  late File lockFile;
  const probe = BuildLockProbe();

  setUp(() {
    project = Directory.systemTemp.createTempSync('pyro_build_lock_');
    lockFile = File('${project.path}/.dart_tool/build/lock/build_runner.lock');
  });

  tearDown(() => project.deleteSync(recursive: true));

  List<String> listing() =>
      [for (final entity in project.listSync(recursive: true)) entity.path]
        ..sort();

  /// A separate process holding the lock until its stdin closes.
  Future<Process> holdLock() async {
    final process = await Process.start(_dart, [
      'run',
      'test/helpers/hold_lock.dart',
      project.path,
    ], runInShell: Platform.isWindows);
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    expect(await lines.first, 'locked');
    return process;
  }

  test('absent when the lock file does not exist, creating nothing', () async {
    final before = listing();
    expect(await probe.check(project.path), LockProbeResult.absent);
    expect(listing(), before);
    expect(listing().where((path) => path.endsWith('.requested')), isEmpty);
  });

  test('free when a lock file exists that nobody holds', () async {
    lockFile.createSync(recursive: true);
    final before = listing();
    expect(await probe.check(project.path), LockProbeResult.free);
    expect(listing(), before);
  });

  test(
    'held while another process holds it, free once that process exits',
    () async {
      final holder = await holdLock();
      expect(await probe.check(project.path), LockProbeResult.held);
      // Probing twice changes nothing: the probe let go of what it opened.
      expect(await probe.check(project.path), LockProbeResult.held);
      await holder.stdin.close();
      expect(await holder.exitCode, 0);
      expect(await probe.check(project.path), LockProbeResult.free);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('the probe never keeps the lock itself', () async {
    lockFile.createSync(recursive: true);
    for (var i = 0; i < 3; i++) {
      expect(await probe.check(project.path), LockProbeResult.free);
    }
    // Another handle takes it at once, so nothing was left locked.
    final handle = await lockFile.open(mode: FileMode.append);
    addTearDown(handle.close);
    await handle.lock(FileLock.exclusive);
    await handle.unlock();
  });
}
