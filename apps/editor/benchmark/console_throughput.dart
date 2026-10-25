// Measures the Console's buffer under a flood (spec 007, SC-006, research
// R12): 5,000 lines per second for 10 seconds, from all three sources, a
// share of them carrying a debugger address, into one `ConsoleBuffer` with a
// listener on its `changes`.
//
// Usage, from apps/editor:
//   dart run benchmark/console_throughput.dart
//
// Prints the cost per line (redaction included), the notifications per second
// and the lines kept, and exits 1 if the buffer notifies more than 20 times a
// second or does not keep exactly its capacity. The frame check of the panel
// itself (quickstart §3.6) needs a profile build and is done by hand.
import 'dart:async';
import 'dart:io';

import 'package:pyro/process/process.dart';

const _linesPerSecond = 5000;
const _seconds = 10;
const _tick = Duration(milliseconds: 10);
const _maxNotificationsPerSecond = 20;

Future<void> main() async {
  final buffer = ConsoleBuffer();
  var notifications = 0;
  final subscription = buffer.changes.listen((_) => notifications++);

  final perTick = _linesPerSecond * _tick.inMilliseconds ~/ 1000;
  final ticks = _seconds * 1000 ~/ _tick.inMilliseconds;
  final cost = Stopwatch();
  var added = 0;
  final done = Completer<void>();
  var tick = 0;
  Timer.periodic(_tick, (timer) {
    cost.start();
    for (var i = 0; i < perTick; i++, added++) {
      buffer.add(
        _line(added),
        source: ConsoleSource.values[added % ConsoleSource.values.length],
        severity: added % 50 == 0
            ? ConsoleSeverity.error
            : ConsoleSeverity.info,
      );
    }
    cost.stop();
    if (++tick == ticks) {
      timer.cancel();
      done.complete();
    }
  });
  final wall = Stopwatch()..start();
  await done.future;
  // Let the last throttled notification fire.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  wall.stop();
  await subscription.cancel();

  final perSecond = notifications / (wall.elapsedMilliseconds / 1000);
  final microsPerLine = cost.elapsedMicroseconds / added;
  final kept = buffer.lines.length;
  final leaked = buffer.lines.any((line) => line.text.contains('AbCdEf'));
  buffer.dispose();

  final failures = [
    if (perSecond > _maxNotificationsPerSecond)
      '${perSecond.toStringAsFixed(1)} notifications a second, '
          'more than $_maxNotificationsPerSecond',
    if (kept != buffer.capacity) 'kept $kept lines, not ${buffer.capacity}',
    if (leaked) 'an auth code reached the buffer',
  ];

  stdout
    ..writeln('| Measure | Value |')
    ..writeln('|---|---|')
    ..writeln('| Lines added | $added in $_seconds s |')
    ..writeln('| Cost per line | ${microsPerLine.toStringAsFixed(2)} µs |')
    ..writeln(
      '| Notifications | $notifications '
      '(${perSecond.toStringAsFixed(1)} a second, limit '
      '$_maxNotificationsPerSecond) |',
    )
    ..writeln('| Lines kept | $kept of ${buffer.capacity} |');
  if (failures.isNotEmpty) {
    stderr.writeln('FAILED: ${failures.join('; ')}');
    exit(1);
  }
  stdout.writeln('OK');
}

/// A game line, every third carrying an address the buffer must mask.
String _line(int n) => n % 3 == 0
    ? 'The Dart VM service is listening on http://127.0.0.1:50300/AbCdEf$n=/'
    : 'flutter: frame $n, entities: ${n % 200}, position: (${n % 800}, ${n % 600})';
