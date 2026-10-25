import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:pyro/process/process.dart';

/// The project every Play test plays.
const projectPath = '/work/example';

/// A `MemoryFileSystem` holding a playable project at [path]: a
/// `pubspec.yaml`, a `macos/` folder and, unless [scenes] is false, an
/// `assets/scenes/` folder.
MemoryFileSystem projectFileSystem({
  String path = projectPath,
  bool scenes = true,
}) {
  final fs = MemoryFileSystem();
  fs.file('$path/pubspec.yaml').createSync(recursive: true);
  fs.directory('$path/macos').createSync(recursive: true);
  if (scenes) fs.directory('$path/assets/scenes').createSync(recursive: true);
  return fs;
}

/// Reads a daemon transcript from `test/fixtures/daemon/` (research R6).
List<String> transcript(String name) =>
    File('test/fixtures/daemon/$name').readAsLinesSync();

/// Reads a spec 007 recording from `test/fixtures/transcripts/`.
List<String> recorded(String name) =>
    File('test/fixtures/transcripts/$name').readAsLinesSync();

/// A `flutter run --machine` stand-in: its stdout replays transcript lines
/// when the test says so, its stdin records the client's requests, and it
/// exits only when told to.
final class FakeProcess implements Process {
  /// Creates a process with nothing queued.
  FakeProcess();

  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  final _queued = Queue<String>();

  /// The requests the client wrote to stdin, decoded, in order.
  final requests = <Map<String, Object?>>[];

  /// The signals sent with [kill], in order.
  final signals = <ProcessSignal>[];

  /// Called with each request as it arrives, to answer it.
  void Function(Map<String, Object?> request)? onRequest;

  @override
  // The client writes to it; the session's end makes closing it moot.
  // ignore: close_sinks
  late final IOSink stdin = IOSink(_StdinRecorder(this));

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  /// Whether [exit] was called.
  bool get exited => _exit.isCompleted;

  /// Queues [name]'s lines after whatever is queued.
  void queue(String name) => _queued.addAll(transcript(name));

  /// Queues [lines] after whatever is queued.
  void queueLines(Iterable<String> lines) => _queued.addAll(lines);

  /// Writes every queued line to stdout.
  void emitAll() {
    while (_queued.isNotEmpty) {
      emitLine(_queued.removeFirst());
    }
  }

  /// Writes queued lines up to and including the first that [test] accepts.
  void emitUntil(bool Function(String line) test) {
    while (_queued.isNotEmpty) {
      final line = _queued.removeFirst();
      emitLine(line);
      if (test(line)) return;
    }
  }

  /// Queues [name] and writes all of it.
  void play(String name) {
    queue(name);
    emitAll();
  }

  /// Writes one line to stdout.
  void emitLine(String line) => _stdout.add(utf8.encode('$line\n'));

  /// Writes one line to stderr.
  void emitStderr(String line) => _stderr.add(utf8.encode('$line\n'));

  /// Ends the process with [code], closing its output.
  void exit(int code) {
    if (_exit.isCompleted) return;
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    return true;
  }
}

final class _StdinRecorder implements StreamConsumer<List<int>> {
  _StdinRecorder(this._process);

  final FakeProcess _process;
  final _buffer = StringBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.transform(utf8.decoder).forEach(_add);

  void _add(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final lines = text.split('\n');
    _buffer
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines) {
      final batch = jsonDecode(line) as List<Object?>;
      for (final request in batch.cast<Map<String, Object?>>()) {
        _process.requests.add(request);
        _process.onRequest?.call(request);
      }
    }
  }

  @override
  Future<void> close() async {}
}

/// A [ProcessStarter] that returns [process] and records how it was called.
final class FakeStarter {
  /// Creates a starter for [process], or one that throws [error].
  FakeStarter(this.process, {this.error});

  /// The process every call returns.
  final FakeProcess process;

  /// Thrown instead, when set.
  final Exception? error;

  /// The executable of the last call.
  String? executable;

  /// The arguments of the last call.
  List<String>? arguments;

  /// The working directory of the last call.
  String? workingDirectory;

  /// The [ProcessStarter] to give `PlayClient`.
  Future<Process> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.workingDirectory = workingDirectory;
    final error = this.error;
    if (error != null) throw error;
    return process;
  }
}
