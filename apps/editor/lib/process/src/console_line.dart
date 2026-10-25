/// Where a Console line came from (spec 007, data model "ConsoleLine").
enum ConsoleSource {
  /// The `build_runner` run Pyro follows.
  generator,

  /// The running game and the build of it.
  game,

  /// Pyro's own notes about Play and the generator.
  pyro,
}

/// How serious a Console line is, from its source's own level.
enum ConsoleSeverity { info, warning, error }

/// One line of the Console. Immutable; [text] is already redacted.
final class ConsoleLine {
  /// Creates a line; only `ConsoleBuffer` makes them.
  const ConsoleLine({
    required this.text,
    required this.source,
    required this.severity,
    required this.time,
    required this.sequence,
  });

  /// The line, auth codes masked, without a line break.
  final String text;

  /// Where it came from.
  final ConsoleSource source;

  /// How serious it is.
  final ConsoleSeverity severity;

  /// When it entered the Console.
  final DateTime time;

  /// The order it entered in: strictly increasing per buffer.
  final int sequence;

  @override
  String toString() => '${source.name}: $text';
}
