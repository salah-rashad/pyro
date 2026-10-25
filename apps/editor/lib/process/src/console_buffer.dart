import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';

import 'console_line.dart';
import 'play_defaults.dart';
import 'redact.dart';

/// The Console's lines: a fixed-size ring that masks auth codes on entry
/// and tells its listeners at most once per [notifyEvery] (spec 007, R12).
///
/// [add] is the only way in, so no line can skip the redaction (FR-025).
final class ConsoleBuffer {
  /// Creates an empty buffer holding at most [capacity] lines.
  ConsoleBuffer({
    this.capacity = PlayDefaults.consoleCapacity,
    this.notifyEvery = PlayDefaults.consoleNotify,
  }) : _ring = List<ConsoleLine?>.filled(capacity, null);

  /// How many lines it keeps; the oldest drops first.
  final int capacity;

  /// The shortest gap between two [changes] events.
  final Duration notifyEvery;

  final List<ConsoleLine?> _ring;
  final _changes = StreamController<void>.broadcast();
  late final _view = _RingView(this);
  var _start = 0;
  var _length = 0;
  var _sequence = 0;
  Timer? _notify;
  var _disposed = false;

  /// Fires, throttled, after lines were added or the buffer was cleared.
  Stream<void> get changes => _changes.stream;

  /// Every line, oldest first; an unmodifiable view, not a copy.
  List<ConsoleLine> get lines => _view;

  /// The lines whose source is in [sources], oldest first. All sources
  /// return [lines] itself.
  List<ConsoleLine> filtered(Set<ConsoleSource> sources) {
    if (sources.length == ConsoleSource.values.length) return _view;
    return List.unmodifiable(
      _view.where((line) => sources.contains(line.source)),
    );
  }

  /// Adds [text], one line per line break in it, auth codes masked.
  void add(
    String text, {
    required ConsoleSource source,
    ConsoleSeverity severity = ConsoleSeverity.info,
  }) {
    if (_disposed) return;
    final now = clock.now();
    for (final part in text.trimRight().split(_lineBreak)) {
      final line = ConsoleLine(
        text: redactAuthCodes(part),
        source: source,
        severity: severity,
        time: now,
        sequence: _sequence++,
      );
      if (_length < capacity) {
        _ring[(_start + _length) % capacity] = line;
        _length++;
      } else {
        _ring[_start] = line;
        _start = (_start + 1) % capacity;
      }
    }
    _scheduleNotify();
  }

  /// Removes every line.
  void clear() {
    if (_disposed) return;
    _ring.fillRange(0, capacity, null);
    _start = 0;
    _length = 0;
    _scheduleNotify();
  }

  /// Cancels the pending notification and closes [changes].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notify?.cancel();
    _notify = null;
    unawaited(_changes.close());
  }

  void _scheduleNotify() {
    _notify ??= Timer(notifyEvery, () {
      _notify = null;
      if (!_disposed) _changes.add(null);
    });
  }
}

final _lineBreak = RegExp(r'\r?\n');

/// [ConsoleBuffer.lines]: indexes the ring in place; every write throws.
final class _RingView extends ListBase<ConsoleLine> {
  _RingView(this._buffer);

  final ConsoleBuffer _buffer;

  @override
  int get length => _buffer._length;

  @override
  set length(int value) => throw UnsupportedError('The Console is read-only.');

  @override
  void operator []=(int index, ConsoleLine value) =>
      throw UnsupportedError('The Console is read-only.');

  @override
  ConsoleLine operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _buffer._ring[(_buffer._start + index) % _buffer.capacity]!;
  }
}
