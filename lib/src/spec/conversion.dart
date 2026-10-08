/// One conversion of one document to one format, and its result: the unit
/// every engine (Ruby workers, asciidart in-process) runs.
library;

/// The output formats a case can name.
enum Format {
  html5('html'),
  xhtml5('xhtml'),
  docbook5('xml'),
  manpage('man'),
  pdf('pdf'),
  epub3('epub');

  const Format(this.extension);

  /// The file extension of an expected-output blob.
  final String extension;

  /// Whether the output is bytes rather than text.
  bool get binary => this == pdf || this == epub3;

  static Format parse(String name) => values.firstWhere(
    (f) => f.name == name,
    orElse: () => throw FormatException('unknown format: $name'),
  );
}

/// Asciidoctor's safe modes, least to most restrictive.
enum Safe {
  unsafe,
  safe,
  server,
  secure;

  static Safe parse(String name) => values.firstWhere(
    (s) => s.name == name,
    orElse: () => throw FormatException('unknown safe mode: $name'),
  );
}

/// A request to convert [input] to [format].
final class Conversion {
  const Conversion({
    required this.id,
    required this.input,
    required this.format,
    required this.baseDir,
    this.doctype,
    this.safe = Safe.safe,
    this.standalone = false,
    this.attributes = const {},
    this.extra = const {},
  });

  final String id;
  final String input;
  final Format format;

  /// The directory includes and images resolve against (absolute).
  final String baseDir;
  final String? doctype;
  final Safe safe;
  final bool standalone;

  /// API attributes; a name ending in `!` unsets, a value ending in `@` is
  /// soft (a document may override it).
  final Map<String, String> attributes;

  /// Other Asciidoctor API options, passed through to Ruby engines as they
  /// are (captured test inputs); asciidart ignores them.
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    'id': id,
    'input': input,
    'backend': format.name,
    'base_dir': baseDir,
    'doctype': ?doctype,
    'safe': safe.name,
    'standalone': standalone,
    'attributes': attributes,
    if (extra.isNotEmpty) 'options': extra,
  };
}

/// A message an engine logged during a conversion.
final class LogEntry {
  const LogEntry(this.severity, this.message, {this.line});

  /// `debug`, `info`, `warning`, `error` or `fatal`.
  final String severity;
  final String message;
  final int? line;

  /// `severity:line: message`, the form stored in `versions.toml`.
  @override
  String toString() => '$severity:${line ?? ''}: $message';

  static LogEntry parse(String text) {
    final first = text.indexOf(':');
    final second = text.indexOf(':', first + 1);
    final line = text.substring(first + 1, second);
    return LogEntry(
      text.substring(0, first),
      text.substring(second + 2),
      line: line.isEmpty ? null : int.parse(line),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LogEntry &&
      other.severity == severity &&
      other.message == message &&
      other.line == line;

  @override
  int get hashCode => Object.hash(severity, message, line);
}

/// What came of a [Conversion].
sealed class Outcome {
  const Outcome({required this.id, required this.micros});

  final String id;

  /// Wall time of the conversion itself.
  final int micros;
}

/// The engine produced output.
final class Converted extends Outcome {
  const Converted({
    required super.id,
    required super.micros,
    required this.output,
    this.log = const [],
    this.coverage,
    this.includes = const [],
  });

  /// Text, or bytes for binary formats.
  final Object output;
  final List<LogEntry> log;

  /// The files the document included (absolute paths), where the engine
  /// reports them.
  final List<String> includes;
  final CaseCoverage? coverage;
}

/// The engine threw.
final class Crashed extends Outcome {
  const Crashed({
    required super.id,
    required super.micros,
    required this.error,
    this.frame,
    this.coverage,
  });

  final String error;

  /// The innermost frame inside the engine's own code, if known.
  final String? frame;
  final CaseCoverage? coverage;
}

/// The engine did not finish within the time limit.
final class TimedOut extends Outcome {
  const TimedOut({required super.id, required super.micros});
}

/// The lines and branch arms one conversion reached, as indices into the
/// engine's coverage universe.
final class CaseCoverage {
  const CaseCoverage(this.lines, this.branches);

  final List<int> lines;
  final List<int> branches;
}
