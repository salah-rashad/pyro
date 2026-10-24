import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

const _level = 'assets/scenes/level1.scene.json';
const _other = 'assets/scenes/level2.scene.json';

/// A monitor over in-memory file contents, recording what it reports.
final class Rig {
  Rig() {
    monitor = HotSwapMonitor(
      contentOf: (path) => contents[path],
      onFailed: (paths, misses) => failures.add((paths, misses)),
      onUnannounced: unannounced.add,
    );
  }

  final contents = <String, String>{_level: 'v1', _other: 'w1'};
  final failures = <(Set<String>, int)>[];
  final unannounced = <String>[];
  late final HotSwapMonitor monitor;

  void loaded(String path) => monitor.onLine('[pyro] Scene loaded: $path');

  /// A save of [path] with [content], reloaded; its report line arrives
  /// only if [report] says so.
  void save(String path, String content, {String? report}) {
    contents[path] = content;
    monitor
      ..onBatch({path})
      ..onReloadFinished();
    if (report != null) monitor.onLine('[pyro] Scene $report: $path');
  }
}

void main() {
  test('a changed save of an armed path expects a report within 3 s', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2');
      async.elapse(const Duration(milliseconds: 2900));
      expect(r.monitor.misses, 0);
      async.elapse(const Duration(milliseconds: 200));
      expect(r.monitor.misses, 1);
      expect(r.monitor.failed, isFalse);
    });
  });

  test('reloaded and not reloaded both count as the game reporting', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2', report: 'reloaded');
      async.elapse(const Duration(seconds: 5));
      r.save(_level, 'v3', report: 'not reloaded');
      async.elapse(const Duration(seconds: 5));
      expect(r.monitor.misses, 0);
      expect(r.failures, isEmpty);
    });
  });

  test('a report that comes before the reload finished still counts', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.contents[_level] = 'v2';
      r.monitor.onBatch({_level});
      r.monitor.onLine('[pyro] Scene reloaded: $_level: ignored');
      r.monitor.onReloadFinished();
      async.elapse(const Duration(seconds: 5));
      expect(r.monitor.misses, 0);
    });
  });

  test('a reason after the path is allowed in a not reloaded line', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.contents[_level] = 'v2';
      r.monitor
        ..onBatch({_level})
        ..onReloadFinished()
        ..onLine('[pyro] Scene not reloaded: $_level: Unexpected token');
      async.elapse(const Duration(seconds: 5));
      expect(r.monitor.misses, 0);
    });
  });

  test('one miss does not fail; two in a row fail exactly once', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.failed, isFalse);
      expect(r.failures, isEmpty);
      r.save(_level, 'v3');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.failed, isTrue);
      expect(r.failures, hasLength(1));
      expect(r.failures.single.$1, {_level});
      expect(r.failures.single.$2, 2);
      // Further saves are not watched and report nothing more.
      r.save(_level, 'v4');
      async.elapse(const Duration(seconds: 10));
      expect(r.failures, hasLength(1));
    });
  });

  test('a report resets the count', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 1);
      r.save(_level, 'v3', report: 'reloaded');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 0);
      r.save(_level, 'v4');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 1);
      expect(r.monitor.failed, isFalse);
    });
  });

  test('a save with identical bytes expects nothing', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      for (var i = 0; i < 5; i++) {
        r.save(_level, 'v1');
        async.elapse(const Duration(seconds: 4));
      }
      expect(r.monitor.misses, 0);
      expect(r.monitor.failed, isFalse);
    });
  });

  test('bytes that return to the last reported content expect nothing', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2', report: 'reloaded');
      r.save(_level, 'v2');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 0);
    });
  });

  test('a burst of saves is one batch and one miss', () {
    fakeAsync((async) {
      final r = Rig()
        ..loaded(_level)
        ..loaded(_other);
      r.contents[_level] = 'v2';
      r.contents[_other] = 'w2';
      r.monitor
        ..onBatch({_level, _other})
        ..onReloadFinished();
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 1);
    });
  });

  test('a path no loaded line announced is never expected', () {
    fakeAsync((async) {
      final r = Rig();
      r.save(_level, 'v2');
      r.save(_level, 'v3');
      r.save(_level, 'v4');
      async.elapse(const Duration(seconds: 10));
      expect(r.monitor.misses, 0);
      expect(r.monitor.failed, isFalse);
      expect(r.unannounced, [_level], reason: 'noted once, not three times');
    });
  });

  test('a failed reload is not a miss', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.contents[_level] = 'v2';
      r.monitor
        ..onBatch({_level})
        ..onReloadFailed();
      async.elapse(const Duration(seconds: 10));
      expect(r.monitor.misses, 0);
    });
  });

  test('a file that cannot be read is not a miss', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.contents.remove(_level);
      r.monitor
        ..onBatch({_level})
        ..onReloadFinished();
      async.elapse(const Duration(seconds: 10));
      expect(r.monitor.misses, 0);
    });
  });

  test('Restart game re-arms with fresh baselines', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2');
      async.elapse(const Duration(seconds: 4));
      r.save(_level, 'v3');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.failed, isTrue);

      r.monitor.rearm();
      expect(r.monitor.failed, isFalse);
      expect(r.monitor.misses, 0);
      // The restarted game announces what it loads, and v3 is its baseline.
      r.loaded(_level);
      r.save(_level, 'v3');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 0, reason: 'unchanged since the restart');
      r.save(_level, 'v4');
      async.elapse(const Duration(seconds: 4));
      expect(r.monitor.misses, 1);
      expect(r.failures, hasLength(1), reason: 'the first failure only');
    });
  });

  test('dispose cancels the deadlines', () {
    fakeAsync((async) {
      final r = Rig()..loaded(_level);
      r.save(_level, 'v2');
      r.monitor.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
