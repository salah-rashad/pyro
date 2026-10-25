import 'dart:async';
import 'dart:io' show FileSystemEvent, FileSystemMoveEvent;

import 'package:file/file.dart';

import 'generator_state.dart';
import 'play_defaults.dart';
import 'scene_watcher.dart';

/// Turns saves of a project's `lib/**.dart` files into requests for a code
/// reload, once the generator is done with them (spec 007, FR-012, research
/// R10).
///
/// A batch of saves (one [quietPeriod] without a change) asks for one reload,
/// when the generator is:
/// - **up to date, stopped, not set up or in error**: nothing is going to
///   change the generated files, so at once;
/// - **starting or generating**: on the next state that is none of these;
/// - **External build_runner**: Pyro can't read its output, so [settle]
///   after the save, and again [settle] after each change of
///   `lib/pyro.manifest.json` or `lib/pyro.g.dart` (a regenerated Registry
///   is a save of its own).
///
/// The generated files are inside `lib/`, so a regenerated Registry reloads
/// too. Saves while a reload waits share it.
final class CodeWatcher {
  /// Watches [projectPath]'s `lib/` with [watch] and calls [onReload] for
  /// each reload to make. [generatorState] and [generatorStates] are the
  /// generator's current state and its changes. [onNote] explains, once, why
  /// nothing is watched (no folder) or watching stopped (an error from
  /// [watch]).
  CodeWatcher({
    required FileSystem fileSystem,
    required this._projectPath,
    required this._watch,
    required this._generatorState,
    required this._generatorStates,
    required this._onReload,
    this._onNote,
    this._quietPeriod = PlayDefaults.sceneQuiet,
    this._settle = PlayDefaults.codeReloadSettle,
  }) : _fs = fileSystem;

  final FileSystem _fs;
  final String _projectPath;
  final DirectoryWatcher _watch;
  final GeneratorState Function() _generatorState;
  final Stream<GeneratorState> _generatorStates;
  final void Function() _onReload;
  final void Function(String note)? _onNote;
  final Duration _quietPeriod;
  final Duration _settle;
  StreamSubscription<FileSystemEvent>? _files;
  StreamSubscription<GeneratorState>? _states;
  Timer? _quiet;
  Timer? _settling;
  var _needsReload = false;

  /// Starts watching, or notes that the project has no `lib/`.
  void start() {
    final lib = _fs.directory(_fs.path.join(_projectPath, 'lib'));
    if (!lib.existsSync()) {
      _onNote?.call(
        'No lib/ folder in $_projectPath, so saving Dart code '
        "won't reload the game.",
      );
      return;
    }
    try {
      _files = _watch(lib).listen(
        _onEvent,
        onError: (Object error) => _onNote?.call(
          'Stopped watching ${lib.path} for code changes: $error',
        ),
      );
    } on Object catch (error) {
      _onNote?.call("Can't watch ${lib.path} for code changes: $error");
      return;
    }
    _states = _generatorStates.listen(_onGeneratorState);
  }

  /// Stops watching; a reload still waiting is dropped. No event is handled
  /// after this.
  void close() {
    _quiet?.cancel();
    _settling?.cancel();
    _quiet = null;
    _settling = null;
    _needsReload = false;
    unawaited(_files?.cancel());
    unawaited(_states?.cancel());
    _files = null;
    _states = null;
  }

  void _onEvent(FileSystemEvent event) {
    if (event.isDirectory) return;
    final path = event is FileSystemMoveEvent
        ? event.destination ?? event.path
        : event.path;
    final context = _fs.path;
    final relative = context
        .split(context.relative(path, from: _projectPath))
        .join('/');
    if (relative == 'lib/pyro.manifest.json') {
      // Not a save of code, but an External build_runner writing: wait for
      // it to finish before reloading the save that came before.
      if (_settling?.isActive ?? false) _settleFor(_settle);
      return;
    }
    if (!relative.startsWith('lib/') || !relative.endsWith('.dart')) return;
    _needsReload = true;
    _settling?.cancel();
    _quiet?.cancel();
    _quiet = Timer(_quietPeriod, () {
      _quiet = null;
      _gate();
    });
  }

  void _onGeneratorState(GeneratorState state) {
    // A save still being batched is judged when its batch ends.
    if (_needsReload && _quiet == null) _gate();
  }

  void _gate() {
    if (!_needsReload) return;
    switch (_generatorState().status) {
      case GeneratorStatus.starting || GeneratorStatus.generating:
        break; // Waits for the next state.
      case GeneratorStatus.external:
        _settleFor(_settle - _quietPeriod);
      case GeneratorStatus.notSetUp ||
          GeneratorStatus.upToDate ||
          GeneratorStatus.error ||
          GeneratorStatus.stopped:
        _settling?.cancel();
        _fire();
    }
  }

  void _settleFor(Duration wait) {
    _settling?.cancel();
    _settling = Timer(wait, _fire);
  }

  void _fire() {
    if (!_needsReload) return;
    _needsReload = false;
    _settling = null;
    _onReload();
  }
}
