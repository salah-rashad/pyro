// Measures the vertical slice's Hot-swap loop on a real game (spec 005,
// research R14): SC-004 (save to Scene reloaded), SC-005 (no rebuild on a
// no-op save or a Dart-only reload) and SC-006 (a burst of saves is at most
// two reloads). Rerun on each Flutter release (project plan §13).
//
// Usage, from apps/editor, with the game not already running:
//   dart run benchmark/hot_swap_latency.dart [project] [--with-attach]
//   (default project ../../example)
//
// The game always runs through a run link and every Scene save re-points the
// engine's assets first (spec 007, research R2, R5). With --with-attach a
// `flutter attach -d macos --debug-uri <address>` stand-in IDE stays attached
// the whole time (it makes the same DevFS clash as VS Code, spike #1
// finding 2); the address is read from the session and never printed.
//
// It drives `example/`: it rewrites assets/scenes/level1.scene.json and
// lib/code_marker.dart, restores both when it ends, and waits for the
// Runtime's "[pyro] Scene reloaded" Hot-swap report (spec 007,
// contracts/hot-swap-reports.md). Times run to that line, which the Runtime
// prints once the swap is done; the frame that shows it follows within
// 16 ms. Prints a Markdown table and exits 1 if a criterion fails.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pyro/process/process.dart';

const _scene = 'assets/scenes/level1.scene.json';
const _marker = 'lib/code_marker.dart';
const _reloaded = '[pyro] Scene reloaded';
const _loaded = '[pyro_example] Scene loaded';
const _shipPosition = '"position": [400, 300]';

Future<void> main(List<String> args) async {
  final withAttach = args.contains('--with-attach');
  final paths = args.where((a) => !a.startsWith('--')).toList();
  final project = Directory(
    paths.isEmpty ? '../../example' : paths.first,
  ).absolute.path;
  final scene = File('$project/$_scene');
  final marker = File('$project/$_marker');
  final sceneText = scene.readAsStringSync();
  final markerText = marker.readAsStringSync();
  if (!sceneText.contains(_shipPosition)) {
    stderr.writeln(
      '$_scene no longer holds $_shipPosition; update the benchmark.',
    );
    exit(1);
  }

  final support = Directory.systemTemp.createTempSync('pyro_latency_support_');
  final link = await RunLink.create(project, supportDir: support.path);
  if (link == null) {
    stderr.writeln('The run link could not be made.');
    exit(1);
  }
  final session = await PlayClient().start(project, runLink: link);
  final events = session.events.asBroadcastStream();
  Process? attach;
  final rows = <List<String>>[];
  var ok = true;
  try {
    // Both: the game can print its first line before the daemon reports
    // app.started.
    final started = events.any((e) => e is PlayStarted);
    final loaded = events.any(
      (e) => e is PlayOutput && e.line.contains(_loaded),
    );
    final ready = await Future.wait([
      started,
      loaded,
    ]).timeout(const Duration(minutes: 10));
    if (ready.contains(false)) {
      throw StateError('the game stopped before loading its Scene');
    }

    if (withAttach) {
      attach = await Process.start('flutter', [
        'attach',
        '-d',
        'macos',
        '--debug-uri',
        session.debuggerAddress!,
      ], workingDirectory: project);
      final attached = Completer<void>();
      attach.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.contains('Flutter run key commands') &&
                !attached.isCompleted) {
              attached.complete();
            }
          });
      unawaited(attach.stderr.drain<void>());
      await attached.future.timeout(const Duration(minutes: 2));
      rows.add(['An IDE stand-in is attached', 'yes', '', '']);
    }

    // SC-004: ten changed saves, each timed to the game's reload line.
    final times = <int>[];
    for (var i = 1; i <= 10; i++) {
      final reloaded = _nextLine(events, _reloaded, const Duration(seconds: 5));
      final watch = Stopwatch()..start();
      _writeAtomically(
        scene,
        sceneText.replaceFirst(
          _shipPosition,
          '"position": [${400 + i * 10}, 300]',
        ),
      );
      times.add(await reloaded ? watch.elapsedMilliseconds : 5000);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    times.sort();
    final median = (times[4] + times[5]) ~/ 2;
    final worst = times.last;
    final latencyOk = median < 500 && worst < 1000;
    ok &= latencyOk;
    rows
      ..add([
        'SC-004 save → Scene reloaded, median',
        '$median ms',
        '< 500 ms',
        _mark(median < 500),
      ])
      ..add([
        'SC-004 worst of ten',
        '$worst ms',
        '< 1000 ms',
        _mark(worst < 1000),
      ])
      ..add(['SC-004 all ten', times.join(', '), '', '']);

    // SC-005: no-op saves and Dart-only reloads rebuild nothing.
    var rebuilds = 0;
    for (var i = 1; i <= 10; i++) {
      final reloaded = _nextLine(events, _reloaded, const Duration(seconds: 2));
      if (i.isOdd) {
        _writeAtomically(scene, scene.readAsStringSync());
      } else {
        marker.writeAsStringSync(markerText.replaceFirst("'v1'", "'bench-$i'"));
        await session.reload();
      }
      if (await reloaded) rebuilds++;
    }
    ok &= rebuilds == 0;
    rows.add([
      'SC-005 rebuilds after 10 no-op reloads',
      '$rebuilds',
      '0',
      _mark(rebuilds == 0),
    ]);

    // SC-006: ten changed saves 100 ms apart.
    var reloads = 0;
    final counting = events.listen((e) {
      if (e is PlayReloading) reloads++;
    });
    var lastLine = DateTime(0);
    final lines = events.listen((e) {
      if (e is PlayOutput && e.line.contains(_reloaded)) {
        lastLine = DateTime.now();
      }
    });
    late DateTime lastWrite;
    for (var i = 1; i <= 10; i++) {
      _writeAtomically(
        scene,
        sceneText.replaceFirst(
          _shipPosition,
          '"position": [${200 + i * 10}, 300]',
        ),
      );
      lastWrite = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await counting.cancel();
    await lines.cancel();
    final burstOk = reloads <= 2 && lastLine.isAfter(lastWrite);
    ok &= burstOk;
    rows.add([
      'SC-006 reloads for 10 saves 100 ms apart',
      '$reloads',
      '≤ 2, last content shown',
      _mark(burstOk),
    ]);
  } on Object catch (error) {
    ok = false;
    stderr.writeln('Benchmark failed: $error');
  } finally {
    _writeAtomically(scene, sceneText);
    marker.writeAsStringSync(markerText);
    attach?.kill();
    await session.stop();
    await link.remove();
    support.deleteSync(recursive: true);
  }

  stdout
    ..writeln('| Check | Result | Limit | |')
    ..writeln('|---|---|---|---|');
  for (final row in rows) {
    stdout.writeln('| ${row.join(' | ')} |');
  }
  exit(ok ? 0 : 1);
}

/// Completes with true when a game line containing [text] arrives within
/// [timeout], false otherwise.
Future<bool> _nextLine(
  Stream<PlayEvent> events,
  String text,
  Duration timeout,
) => events
    .any((e) => e is PlayOutput && e.line.contains(text))
    .timeout(timeout, onTimeout: () => false);

/// Writes like Pyro will: a temp file, then a rename over the target.
void _writeAtomically(File file, String text) {
  final temp = File('${file.path}.tmp')..writeAsStringSync(text, flush: true);
  temp.renameSync(file.path);
}

String _mark(bool passed) => passed ? '✅' : '❌';
