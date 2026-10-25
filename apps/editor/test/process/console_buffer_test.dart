import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

void main() {
  group('ConsoleBuffer', () {
    test('keeps lines in order with a strictly increasing sequence', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      buffer
        ..add('one', source: ConsoleSource.pyro)
        ..add('two', source: ConsoleSource.game)
        ..add('three', source: ConsoleSource.generator);
      expect(buffer.lines.map((line) => line.text), ['one', 'two', 'three']);
      final sequences = buffer.lines.map((line) => line.sequence).toList();
      for (var i = 1; i < sequences.length; i++) {
        expect(sequences[i], greaterThan(sequences[i - 1]));
      }
    });

    test('holds exactly its capacity and drops the oldest first', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      expect(PlayDefaults.consoleCapacity, 10000);
      for (var i = 0; i < 10005; i++) {
        buffer.add('line $i', source: ConsoleSource.game);
      }
      expect(buffer.lines, hasLength(10000));
      expect(buffer.lines.first.text, 'line 5');
      expect(buffer.lines.last.text, 'line 10004');
    });

    test('redacts every line on entry, for every source', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      for (final source in ConsoleSource.values) {
        buffer.add('at ws://127.0.0.1:1234/AbC=/ws', source: source);
      }
      expect(buffer.lines, hasLength(3));
      for (final line in buffer.lines) {
        expect(line.text, 'at ws://127.0.0.1:1234/<auth-code>=/ws');
      }
    });

    test('splits multi-line text into one line each', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      buffer.add('a\nb\r\nc\n', source: ConsoleSource.game);
      expect(buffer.lines.map((line) => line.text), ['a', 'b', 'c']);
    });

    test('a filter hides other sources without losing lines', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      buffer
        ..add('g', source: ConsoleSource.generator)
        ..add('a', source: ConsoleSource.game)
        ..add('p', source: ConsoleSource.pyro);
      expect(buffer.filtered({ConsoleSource.game}).map((line) => line.text), [
        'a',
      ]);
      expect(
        buffer.filtered(ConsoleSource.values.toSet()).map((line) => line.text),
        ['g', 'a', 'p'],
      );
      expect(buffer.lines, hasLength(3));
    });

    test('keeps the severity it was given', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      buffer.add(
        'boom',
        source: ConsoleSource.generator,
        severity: ConsoleSeverity.error,
      );
      expect(buffer.lines.single.severity, ConsoleSeverity.error);
      buffer.add('fine', source: ConsoleSource.game);
      expect(buffer.lines.last.severity, ConsoleSeverity.info);
    });

    test('clear() empties it', () {
      final buffer = ConsoleBuffer();
      addTearDown(buffer.dispose);
      buffer.add('x', source: ConsoleSource.game);
      buffer.clear();
      expect(buffer.lines, isEmpty);
      buffer.add('y', source: ConsoleSource.game);
      expect(buffer.lines.single.text, 'y');
    });

    test('tells listeners at most once per 50 ms under a burst', () {
      fakeAsync((async) {
        final buffer = ConsoleBuffer();
        var notified = 0;
        buffer.changes.listen((_) => notified++);
        for (var i = 0; i < 5000; i++) {
          buffer.add('line $i', source: ConsoleSource.game);
          if (i % 100 == 0) async.elapse(const Duration(milliseconds: 1));
        }
        // 50 ms of adds (one per 100 lines), then the trailing notification.
        async.elapse(const Duration(milliseconds: 100));
        expect(notified, lessThanOrEqualTo(2));
        expect(notified, greaterThanOrEqualTo(1));
        notified = 0;
        async.elapse(const Duration(seconds: 1));
        expect(notified, 0, reason: 'no change, no notification');
        buffer.dispose();
      });
    });

    test('a burst spread over a second notifies at most 20 times', () {
      fakeAsync((async) {
        final buffer = ConsoleBuffer();
        var notified = 0;
        buffer.changes.listen((_) => notified++);
        for (var ms = 0; ms < 1000; ms++) {
          for (var i = 0; i < 5; i++) {
            buffer.add('line', source: ConsoleSource.game);
          }
          async.elapse(const Duration(milliseconds: 1));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(notified, lessThanOrEqualTo(21));
        buffer.dispose();
      });
    });

    test('dispose() cancels the pending notification', () {
      fakeAsync((async) {
        final buffer = ConsoleBuffer();
        var notified = 0;
        buffer.changes.listen((_) => notified++);
        buffer.add('x', source: ConsoleSource.game);
        buffer.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(notified, 0);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
