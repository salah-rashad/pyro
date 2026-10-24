import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:pyro/process/process.dart';

import 'fake_process.dart';
import 'fake_vm.dart';

/// A game on a fake `flutter run` for widget tests: it answers every request
/// the way the daemon does and ends when told to stop.
final class LiveGame {
  /// Creates the game, to run in the project of [fileSystem].
  LiveGame(this.fileSystem, {this._changes}) {
    process.onRequest = (request) {
      process.emitLine(
        jsonEncode([
          {
            'id': request['id'],
            'result': request['method'] == 'app.restart'
                ? {'code': 0, 'message': ''}
                : true,
          },
        ]),
      );
      if (request['method'] == 'app.stop') {
        process.emitLine('Application finished.');
        process.exit(0);
      }
    };
  }

  /// The project's file system.
  final FileSystem fileSystem;
  final Stream<FileSystemEvent> Function()? _changes;

  /// The fake process.
  final process = FakeProcess();

  /// The fake VM service every re-point talks to.
  final vm = FakeVm();

  /// A [PlayStarter] for the game.
  Future<PlaySession> start(String path, {RunLink? runLink}) => PlayClient(
    startProcess: FakeStarter(process).call,
    fileSystem: fileSystem,
    watchDirectory: (_) => _changes?.call() ?? const Stream.empty(),
    vmConnect: vm.connect,
  ).start(path, runLink: runLink);

  /// The game reports its address (carrying [code]) and has started.
  void started(String code) {
    process.emitLine(
      '[{"event":"app.debugPort","params":{"appId":"a1","port":5001,'
      '"wsUri":"ws://127.0.0.1:5001/$code=/ws","baseUri":"file:///p/"}}]',
    );
    process
      ..queue('start.txt')
      ..emitUntil((line) => line.contains('app.started'));
  }
}
