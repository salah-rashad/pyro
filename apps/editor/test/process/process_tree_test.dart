import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/src/process_tree.dart';

void main() {
  test('finds every process below a pid, deepest first', () async {
    // A shell with two children, one of which has a child of its own.
    final shell = await Process.start('sh', [
      '-c',
      'sleep 60 & sh -c "sleep 60 & wait" & wait',
    ]);
    addTearDown(() => shell.kill(ProcessSignal.sigkill));
    List<int> below = const [];
    for (var i = 0; i < 50 && below.length < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      below = await processDescendants(shell.pid);
    }
    try {
      expect(below, hasLength(3));
      expect(below, isNot(contains(shell.pid)));
      // A parent never comes before its own child.
      for (final pid in below) {
        final parent = (await Process.run('ps', [
          '-o',
          'ppid=',
          '-p',
          '$pid',
        ])).stdout.toString().trim();
        final at = below.indexOf(int.parse(parent));
        if (at != -1) expect(at, greaterThan(below.indexOf(pid)));
      }
    } finally {
      for (final pid in below) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    }
  }, skip: Platform.isWindows ? 'pgrep is not on Windows' : null);

  test('a pid with no children, or none at all, has no descendants', () async {
    final idle = await Process.start('sleep', ['60']);
    addTearDown(() => idle.kill(ProcessSignal.sigkill));
    expect(await processDescendants(idle.pid), isEmpty);
    expect(await processDescendants(2147483646), isEmpty);
  }, skip: Platform.isWindows ? 'pgrep is not on Windows' : null);
}
