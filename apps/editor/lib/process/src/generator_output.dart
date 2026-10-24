/// What one line of `build_runner`'s output means to the supervisor
/// (contracts/generator-supervisor.md, "Output classes").
enum GeneratorLine {
  /// A build has started.
  building,

  /// A build finished without errors.
  succeeded,

  /// A build finished with errors.
  failed,

  /// A severe-level message, such as an error in an annotated class.
  severe,

  /// The run is being asked to exit by another `build_runner` run.
  takeover,

  /// This run found another one holding the lock and waits for it.
  waiting,

  /// Anything else: it goes to the Console only.
  other,
}

/// The recorded lines of `build_runner` 2.15 (transcripts
/// `build-runner-*.txt`, research R9), first match wins. Earlier versions'
/// lines are not recognized: they are `notSetUp` (FR-017).
final _rows = <(RegExp, GeneratorLine)>[
  (RegExp(r'^Starting build #\d+\.$'), GeneratorLine.building),
  // `  0s builder:name on 9 inputs; lib/a.dart`: the semicolon marks an
  // action that has started; its finishing line has a colon.
  (RegExp(r'^\s+\d+s \S+ on \d+ inputs?;'), GeneratorLine.building),
  (
    RegExp(r'^\s*Built with build_runner.* wrote \d+ outputs?\.$'),
    GeneratorLine.succeeded,
  ),
  (RegExp(r'^\s*Failed to build with build_runner'), GeneratorLine.failed),
  (RegExp(r'^E \S'), GeneratorLine.severe),
  (
    RegExp(r'^Exiting as requested by another build_runner process\.$'),
    GeneratorLine.takeover,
  ),
  (
    RegExp(r'^Waiting for already-running build_runner\.$'),
    GeneratorLine.waiting,
  ),
];

/// Classifies one line of `build_runner`'s output.
GeneratorLine classifyGeneratorLine(String line) {
  for (final (pattern, kind) in _rows) {
    if (pattern.hasMatch(line)) return kind;
  }
  return GeneratorLine.other;
}

final _severeFile = RegExp(r'^E \S+ on (\S+?):$');

/// The file a severe line names (`E builder on lib/a.dart:`), or null.
String? severeFile(String line) => _severeFile.firstMatch(line)?.group(1);
