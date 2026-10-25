/// Why Play is disabled, and the one thing that fixes it (spec 007,
/// FR-003, data model "PlayBlock").
final class PlayBlock {
  /// Creates a reason with its fix.
  const PlayBlock(this.reason, this.fix);

  /// The first reason that applies, in the data model's order, or null
  /// when Play is available.
  ///
  /// The inputs are plain values so this file stays free of Flutter:
  /// [projectError] is the open project's own error, [runtimeProblem] the
  /// Runtime compatibility check's message when it failed.
  static PlayBlock? of({
    required String? projectError,
    required bool hasSdk,
    required String? runtimeProblem,
    required bool hasMacosFolder,
  }) {
    if (projectError != null) {
      return PlayBlock("The project couldn't be opened.", projectError);
    }
    if (!hasSdk) {
      return const PlayBlock(
        'No Flutter SDK was found for this project.',
        "Pyro looks for the project's .fvmrc, then FLUTTER_ROOT, then "
            'flutter on PATH; set one up (for an fvm project, run '
            '`fvm install`) and reopen the project.',
      );
    }
    if (runtimeProblem != null) {
      return PlayBlock(
        "The project's Runtime can't run with this Pyro.",
        runtimeProblem,
      );
    }
    if (!hasMacosFolder) {
      return const PlayBlock(
        'The project has no macos/ folder, so it cannot run on macOS.',
        'Run `flutter create --platforms=macos .` in the project, then '
            'reopen it.',
      );
    }
    return null;
  }

  /// Why Play is disabled, in plain language.
  final String reason;

  /// The single action that makes Play available.
  final String fix;

  @override
  String toString() => '$reason $fix';
}
