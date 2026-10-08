part of 'api.dart';

/// How serious a [Diagnostic] is.
enum Severity implements Comparable<Severity> {
  /// Detail useful when debugging a document.
  debug,

  /// Information about the conversion.
  info,

  /// A problem in the document; the output may not be what was intended.
  warning,

  /// A problem that drops or breaks part of the output.
  error,

  /// A problem that stops the conversion.
  fatal;

  @override
  int compareTo(Severity other) => index - other.index;

  /// Whether this is more serious than [other].
  bool operator >(Severity other) => index > other.index;

  /// Whether this is at least as serious as [other].
  bool operator >=(Severity other) => index >= other.index;

  /// Whether this is less serious than [other].
  bool operator <(Severity other) => index < other.index;

  /// Whether this is at most as serious as [other].
  bool operator <=(Severity other) => index <= other.index;

  static Severity _of(impl.Severity severity) => switch (severity) {
    impl.Severity.debug => Severity.debug,
    impl.Severity.info => Severity.info,
    impl.Severity.warn => Severity.warning,
    impl.Severity.error => Severity.error,
    impl.Severity.fatal || impl.Severity.unknown => Severity.fatal,
  };
}

/// What a [Diagnostic] is about, for the messages that are worth telling
/// apart in code; [other] for the rest.
enum DiagnosticCode {
  /// A cross reference to an ID that is not defined.
  unknownReference,

  /// An ID that is already used by another element.
  duplicateId,

  /// An include whose target cannot be found or read.
  includeNotFound,

  /// A reference to an attribute that is not set.
  missingAttribute,

  /// A section whose level skips one (for example `===` right after `=`).
  sectionOutOfSequence,

  /// A delimited block without its closing delimiter.
  unterminatedBlock,

  /// List items numbered out of sequence.
  listNumbering,

  /// A table row or cell that does not fit the table's columns.
  tableStructure,

  /// An image or other asset that cannot be found or read.
  missingAsset,

  /// Any other message.
  other;

  static final List<(RegExp, DiagnosticCode)> _patterns = [
    (RegExp('^possible invalid reference'), unknownReference),
    (RegExp('^id assigned to .* already in use'), duplicateId),
    (RegExp('^include (file|uri) (not found|not readable)'), includeNotFound),
    (
      RegExp(
        '^(dropping line containing|skipping) reference to missing attribute',
      ),
      missingAttribute,
    ),
    (RegExp('^section title out of sequence'), sectionOutOfSequence),
    (RegExp('^unterminated '), unterminatedBlock),
    (RegExp('^(callout )?list item index'), listNumbering),
    (RegExp('^(dropping cells|dropping cell|table missing)'), tableStructure),
    (RegExp('^(image to embed not found|could not retrieve)'), missingAsset),
  ];

  static DiagnosticCode _of(String message) {
    for (final (pattern, code) in _patterns) {
      if (pattern.hasMatch(message)) return code;
    }
    return other;
  }
}

/// Where in the source something is.
@immutable
final class SourceLocation {
  const new _(this.path, this.line);

  static SourceLocation? _of(impl.Cursor? cursor) =>
      cursor == null ? null : SourceLocation._(cursor.path, cursor.lineno);

  /// The file (or `<stdin>` for source given as a string), when known.
  final String? path;

  /// The 1-based line number.
  final int line;

  @override
  bool operator ==(Object other) =>
      other is SourceLocation && other.path == path && other.line == line;

  @override
  int get hashCode => Object.hash(path, line);

  @override
  String toString() => '${path ?? '<stdin>'}: line $line';
}

/// A message about a document, reported while parsing or converting it.
final class Diagnostic {
  const new _(this.severity, this.message, this.code, this.location);

  /// How serious it is.
  final Severity severity;

  /// The message, without the location.
  final String message;

  /// What it is about.
  final DiagnosticCode code;

  /// Where in the source it is, when known (for a problem inside an
  /// included file, the line in that file).
  final SourceLocation? location;

  @override
  String toString() =>
      '${severity.name.toUpperCase()}: '
      '${location == null ? '' : '$location: '}$message';
}

/// Collects the messages logged while a document is parsed or converted.
final class _Collector extends impl.LoggerBase {
  new([this.onDiagnostic]) : super(impl.Severity.debug);

  final void Function(Diagnostic diagnostic)? onDiagnostic;

  final List<Diagnostic> diagnostics = [];

  impl.Severity? _max;

  @override
  impl.Severity? get maxSeverity => _max;

  @override
  Future<void> close() async {}

  @override
  void add(impl.Severity severity, impl.LogMessage message) {
    final max = _max;
    if (max == null || severity.value > max.value) _max = severity;
    final location = message.includeLocation ?? message.sourceLocation;
    final diagnostic = Diagnostic._(
      Severity._of(severity),
      message.text,
      DiagnosticCode._of(message.text),
      SourceLocation._of(location),
    );
    diagnostics.add(diagnostic);
    onDiagnostic?.call(diagnostic);
  }

  /// Runs [body] with this collector receiving the messages.
  R run<R>(R Function() body) => impl.LoggerManager.scoped(this, body);
}

/// A problem that stops a document from being parsed or converted.
final class PtomeException implements Exception {
  new _(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'PtomeException: $message';
}

/// Runs [body], turning the implementation's exceptions into
/// [PtomeException]s.
R _guard<R>(R Function() body) {
  try {
    return body();
  } on impl.AsciidoctorException catch (e, st) {
    Error.throwWithStackTrace(PtomeException._(e.message), st);
  }
}

/// Like [_guard], for asynchronous work.
Future<R> _guardAsync<R>(Future<R> Function() body) async {
  try {
    return await body();
  } on impl.AsciidoctorException catch (e, st) {
    Error.throwWithStackTrace(PtomeException._(e.message), st);
  }
}
