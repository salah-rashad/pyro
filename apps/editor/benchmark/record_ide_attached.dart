// Records the daemon's output of a game that an IDE is attached to (spec 007,
// T039, T054): the transcript `test/fixtures/transcripts/ide-attached.txt`.
//
// Usage, from apps/editor, with the game not already running:
//   dart run benchmark/record_ide_attached.dart [project] [output]
//   (defaults: ../../example, test/fixtures/transcripts/ide-attached.txt)
//
// It plays the project through a run link, attaches `flutter attach -d macos
// --debug-uri <address>` as the stand-in IDE (it makes the same DevFS clash
// as VS Code, spike #1 finding 2), saves a Scene, hot reloads and hot
// restarts from the attach side, and saves again. Every line the daemon
// writes is recorded with VM service auth codes masked; the address itself
// is never printed or stored. The Scene is restored when it ends.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pyro/process/process.dart';

const _scene = 'assets/scenes/level1.scene.json';
const _shipPosition = '"position": [400, 300]';

Future<void> main(List<String> args) async {
  final project = Directory(
    args.isEmpty ? '../../example' : args.first,
  ).absolute.path;
  final output = File(
    args.length > 1 ? args[1] : 'test/fixtures/transcripts/ide-attached.txt',
  );
  final scene = File('$project/$_scene');
  final sceneText = scene.readAsStringSync();
  if (!sceneText.contains(_shipPosition)) {
    stderr.writeln('$_scene no longer holds $_shipPosition.');
    exit(1);
  }

  final support = Directory.systemTemp.createTempSync('pyro_attach_support_');
  final link = await RunLink.create(project, supportDir: support.path);
  if (link == null) {
    stderr.writeln('The run link could not be made.');
    exit(1);
  }
  final recorded = <String>[];
  final session = await PlayClient().start(
    project,
    runLink: link,
    onStdoutLine: recorded.add,
  );
  final events = session.events.asBroadcastStream();
  Process? attach;
  var ok = true;
  try {
    await events
        .firstWhere((e) => e is PlayStarted || e is PlayFailed)
        .timeout(const Duration(minutes: 10))
        .then((e) {
          if (e is PlayFailed) throw StateError(e.message);
        });
    await Future<void>.delayed(const Duration(seconds: 2));

    // The stand-in IDE. Its output is read for markers only.
    final address = session.debuggerAddress!;
    attach = await Process.start('flutter', [
      'attach',
      '-d',
      'macos',
      '--debug-uri',
      address,
    ]);
    final attachLines = <String>[];
    final attached = Completer<void>();
    attach.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          attachLines.add(redactAuthCodes(line));
          stdout.writeln('attach: ${redactAuthCodes(line)}');
          if ((line.contains('To hot reload') ||
                  line.contains('Flutter run key commands')) &&
              !attached.isCompleted) {
            attached.complete();
          }
        });
    attach.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => stdout.writeln('attach err: ${redactAuthCodes(line)}'),
        );
    await attached.future.timeout(const Duration(seconds: 90));
    stdout.writeln('attached');

    Future<bool> reloaded() => events
        .any((e) => e is PlayReloaded || e is PlayReloadFailed)
        .timeout(const Duration(seconds: 10), onTimeout: () => false);

    // A Scene save while attached.
    var next = reloaded();
    scene.writeAsStringSync(
      sceneText.replaceFirst(_shipPosition, '"position": [410, 300]'),
    );
    stdout.writeln('first save reloaded: ${await next}');

    // The IDE's hot reload, then its hot restart.
    attach.stdin.writeln('r');
    await Future<void>.delayed(const Duration(seconds: 4));
    attach.stdin.writeln('R');
    await Future<void>.delayed(const Duration(seconds: 6));

    // A Scene save after the restart.
    next = reloaded();
    scene.writeAsStringSync(
      sceneText.replaceFirst(_shipPosition, '"position": [420, 300]'),
    );
    final second = await next;
    stdout.writeln('second save reloaded: $second');
    ok = second;
    await Future<void>.delayed(const Duration(seconds: 1));
  } on Object catch (error) {
    ok = false;
    stderr.writeln('Recording failed: $error');
  } finally {
    scene.writeAsStringSync(sceneText);
    attach?.kill();
    await session.stop();
    await link.remove();
    support.deleteSync(recursive: true);
  }

  output.writeAsStringSync('${recorded.join('\n')}\n');
  stdout.writeln('recorded ${recorded.length} lines to ${output.path}');
  await stdout.flush();
  exit(ok ? 0 : 1);
}
