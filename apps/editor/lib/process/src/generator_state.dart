/// Where the generator is (spec 007, data model "GeneratorState").
enum GeneratorStatus {
  /// The project cannot run Pyro's generator; nothing runs. The state's
  /// `reason` says why (FR-017).
  notSetUp,

  /// Pyro spawned `build_runner watch`; no build line yet.
  starting,

  /// A build is running.
  generating,

  /// The last build succeeded.
  upToDate,

  /// The last build failed, or `build_runner` could not run; `file` and
  /// `message` say what went wrong.
  error,

  /// A `build_runner` Pyro did not start holds the lock (FR-018, FR-022).
  external,

  /// The user stopped `build_runner` with `build_runner stop`; *Start* runs
  /// it again.
  stopped,
}

/// The generator's state, for the status bar and the code watcher.
final class GeneratorState {
  /// Creates a state.
  const GeneratorState(
    this.status, {
    this.generation = 0,
    this.reason,
    this.file,
    this.message,
  });

  /// The state before anything was probed.
  static const initial = GeneratorState(GeneratorStatus.stopped);

  /// Where the generator is.
  final GeneratorStatus status;

  /// How many builds Pyro's run has finished, counting failed ones: the code
  /// watcher sees "went idle after my save" as this number growing. It
  /// survives restarts of the run.
  final int generation;

  /// For [GeneratorStatus.notSetUp]: why, with the fix.
  final String? reason;

  /// For [GeneratorStatus.error]: the file of the first severe message, when
  /// `build_runner` named one.
  final String? file;

  /// For [GeneratorStatus.error]: what went wrong.
  final String? message;

  /// False only for [GeneratorStatus.external]: Pyro does not own that run
  /// and never stops it.
  bool get ownedByPyro => status != GeneratorStatus.external;

  /// This state with [status] replaced and the error fields cleared, unless
  /// they are given.
  GeneratorState to(
    GeneratorStatus status, {
    int? generation,
    String? reason,
    String? file,
    String? message,
  }) => GeneratorState(
    status,
    generation: generation ?? this.generation,
    reason: reason,
    file: file,
    message: message,
  );

  @override
  bool operator ==(Object other) =>
      other is GeneratorState &&
      other.status == status &&
      other.generation == generation &&
      other.reason == reason &&
      other.file == file &&
      other.message == message;

  @override
  int get hashCode => Object.hash(status, generation, reason, file, message);

  @override
  String toString() =>
      'GeneratorState($status, generation $generation'
      '${reason == null ? '' : ', $reason'}'
      '${message == null ? '' : ', ${file ?? 'no file'}: $message'})';
}
