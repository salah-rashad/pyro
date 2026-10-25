import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'play_defaults.dart';

/// Recognizes a Hot-swap that stopped working (spec 007, FR-011, research
/// R6), from the game's own report lines (contracts/hot-swap-reports.md).
///
/// Per Scene path it keeps the SHA-256 of the content as of the game's last
/// report. After a Scene save whose content differs from that, the game has
/// [reportWait] after the reload to say `reloaded` or `not reloaded`. A
/// save that gets no report is a miss; [missLimit] misses in a row make the
/// Hot-swap [failed]. Any report resets the count.
///
/// A save with the same bytes, a path the game never announced, a failed
/// reload and an unreadable file are never misses.
final class HotSwapMonitor {
  /// Creates the monitor. [contentOf] reads a project-relative Scene path
  /// (null when it can't be read). [onFailed] is called once, with the paths
  /// of the last missed save and the miss count; [onUnannounced] once for
  /// each path the game did not announce.
  HotSwapMonitor({
    required this.contentOf,
    required this.onFailed,
    this.onUnannounced,
    this.reportWait = PlayDefaults.hotSwapReportWait,
    this.missLimit = PlayDefaults.hotSwapMissLimit,
  });

  /// Reads a Scene's current content.
  final String? Function(String path) contentOf;

  /// Called when the Hot-swap is declared failed.
  final void Function(Set<String> paths, int misses) onFailed;

  /// Called once for a changed path the game never announced.
  final void Function(String path)? onUnannounced;

  /// How long after the reload the game has to report.
  final Duration reportWait;

  /// Consecutive misses that fail the Hot-swap.
  final int missLimit;

  static final _report = RegExp(
    r'^(?:flutter: )?\[pyro\] Scene (loaded|reloaded|not reloaded): '
    r'(.*?)(?:: .*)?$',
  );

  final _baseline = <String, String>{};
  final _armed = <String>{};
  final _expected = <String>{};
  final _noted = <String>{};
  final _timers = <Timer>{};
  var _batch = <String>{};
  var _misses = 0;
  var _failed = false;

  /// Consecutive saves that got no report.
  int get misses => _misses;

  /// Whether Hot-swaps are declared failed, until [rearm].
  bool get failed => _failed;

  /// Reads one line of the game's output.
  void onLine(String line) {
    final match = _report.firstMatch(line);
    if (match == null) return;
    final kind = match.group(1)!;
    final path = match.group(2)!;
    _armed.add(path);
    final hash = _hash(path);
    if (hash != null) _baseline[path] = hash;
    if (kind != 'loaded') {
      _expected.remove(path);
      _misses = 0;
    }
  }

  /// A batch of Scene saves is about to be reloaded: expects a report for
  /// each announced path whose content changed.
  void onBatch(Set<String> paths) {
    _batch = {};
    if (_failed) return;
    for (final path in paths) {
      if (!_armed.contains(path)) {
        if (_noted.add(path)) onUnannounced?.call(path);
        continue;
      }
      final hash = _hash(path);
      if (hash == null || hash == _baseline[path]) continue;
      _expected.add(path);
      _batch.add(path);
    }
  }

  /// The reload of the last batch is done: its reports are due within
  /// [reportWait].
  void onReloadFinished() {
    final batch = _batch;
    _batch = {};
    if (batch.isEmpty) return;
    late final Timer timer;
    timer = Timer(reportWait, () {
      _timers.remove(timer);
      _expire(batch);
    });
    _timers.add(timer);
  }

  /// The reload of the last batch failed; the daemon says so itself, and
  /// the game could not have reported.
  void onReloadFailed() {
    _expected.removeAll(_batch);
    _batch = {};
  }

  /// *Restart game*: the new game announces its Scenes again, and what it
  /// loads is the new baseline.
  void rearm() {
    cancel();
    _failed = false;
    _misses = 0;
    _baseline.clear();
    _armed.clear();
    _expected.clear();
    _noted.clear();
    _batch = {};
  }

  /// Cancels the deadlines.
  void dispose() => cancel();

  /// Cancels the deadlines.
  void cancel() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _expire(Set<String> batch) {
    final missed = batch.intersection(_expected);
    if (missed.isEmpty || _failed) return;
    _expected.removeAll(missed);
    _misses++;
    if (_misses >= missLimit) {
      _failed = true;
      onFailed(missed, _misses);
    }
  }

  String? _hash(String path) {
    final content = contentOf(path);
    return content == null
        ? null
        : sha256.convert(utf8.encode(content)).toString();
  }
}
