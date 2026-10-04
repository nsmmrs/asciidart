/// Logging infrastructure for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/logging.rb` (`Asciidoctor::Logger`,
/// `Asciidoctor::MemoryLogger`, `Asciidoctor::NullLogger`,
/// `Asciidoctor::LoggerManager` and `Asciidoctor::Logging`).
///
/// The severity scale, `maxSeverity` tracking (including messages dropped by
/// the level filter) and the [BasicFormatter] label substitutes (`WARN` →
/// `WARNING`, `FATAL` → `FAILED`) behave as in Asciidoctor.
library;

import 'dart:io' show File, FileMode, IOSink, pid, stderr;

import 'package:asciidoctor/src/cursor.dart';

/// Severity levels for log messages.
///
/// Integer [value]s run from `DEBUG` = 0 through `UNKNOWN` = 5; [label]s
/// are the standard level names, except that `UNKNOWN` renders as `ANY`.
enum Severity {
  /// Debugging detail.
  debug(0, 'DEBUG'),

  /// Informational message.
  info(1, 'INFO'),

  /// Recoverable problem.
  warn(2, 'WARN'),

  /// Failure that still allows processing to continue.
  error(3, 'ERROR'),

  /// Unrecoverable failure.
  fatal(4, 'FATAL'),

  /// Severity outside the known scale (label `ANY`).
  unknown(5, 'ANY');

  /// Creates a severity with integer [value] and format [label].
  new(this.value, this.label);

  /// The integer severity.
  final int value;

  /// The severity label used by formatters.
  final String label;

  /// Returns the severity with integer [value].
  ///
  /// Throws an [ArgumentError] for values outside 0–5.
  static Severity fromValue(int value) {
    for (final severity in Severity.values) {
      if (severity.value == value) return severity;
    }
    throw ArgumentError('invalid log level: $value');
  }

  /// Returns the severity named [name] (case-insensitive).
  ///
  /// Accepts exactly these names: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`,
  /// `UNKNOWN`. Anything else throws an [ArgumentError].
  static Severity fromName(String name) {
    switch (name.toUpperCase()) {
      case 'DEBUG':
        return Severity.debug;
      case 'INFO':
        return Severity.info;
      case 'WARN':
        return Severity.warn;
      case 'ERROR':
        return Severity.error;
      case 'FATAL':
        return Severity.fatal;
      case 'UNKNOWN':
        return Severity.unknown;
      default:
        throw ArgumentError('invalid log level: $name');
    }
  }
}

/// A log message: its [text] plus the source position it refers to.
///
/// Port of the hash built by `Logging#message_with_context`. [toString]
/// renders `sourceLocation: text` when a location is present, else [text].
class LogMessage {
  /// Creates a message with [text] and optional source locations.
  const new(this.text, {this.sourceLocation, this.includeLocation});

  /// The message text, without location prefix.
  final String text;

  /// The source position the message refers to, if any.
  final Cursor? sourceLocation;

  /// The position inside an include file the message refers to, if any.
  final Cursor? includeLocation;

  @override
  String toString() {
    final location = sourceLocation;
    return location == null ? text : '$location: $text';
  }
}

/// Formats a single log record.
abstract interface class LoggerFormatter {
  /// Formats [message], logged at [severity] by [progname] at [time].
  String call(
    Severity severity,
    DateTime time,
    String progname,
    LogMessage message,
  );
}

/// Detailed log record formatter.
///
/// Renders `D, [2026-10-03T05:25:29.294678 #pid] DEBUG -- progname: message`.
final class DefaultFormatter implements LoggerFormatter {
  /// Creates the default formatter.
  const new();

  @override
  String call(
    Severity severity,
    DateTime time,
    String progname,
    LogMessage message,
  ) {
    final label = severity.label;
    return '${label[0]}, [${time.toIso8601String()} #$pid] '
        '${label.padLeft(5)} -- $progname: $message\n';
  }
}

/// Single-line log record formatter.
///
/// Port of `Asciidoctor::Logger::BasicFormatter`: renders
/// `progname: SEVERITY: message`, substituting `WARNING` for `WARN` and
/// `FAILED` for `FATAL`.
final class BasicFormatter implements LoggerFormatter {
  /// Creates the basic formatter.
  const new();

  /// Severity label substitutes.
  static const Map<String, String> severityLabelSubstitutes = {
    'WARN': 'WARNING',
    'FATAL': 'FAILED',
  };

  @override
  String call(
    Severity severity,
    DateTime time,
    String progname,
    LogMessage message,
  ) {
    final label = severityLabelSubstitutes[severity.label] ?? severity.label;
    return '$progname: $label: $message\n';
  }
}

/// Shared behavior for [Logger], [MemoryLogger] and [NullLogger].
///
/// Holds the level filter, the `isDebugEnabled`-style predicates and the
/// severity convenience methods, which all delegate to [add].
abstract class LoggerBase {
  /// Creates a logger with the given [level].
  new(this.level);

  /// The minimum severity emitted (messages below it are dropped, except by
  /// [MemoryLogger], which records everything).
  Severity level;

  /// The highest severity passed to [add] so far, or `null` when nothing
  /// was logged yet.
  Severity? get maxSeverity;

  /// Whether [Severity.debug] messages are emitted.
  bool get isDebugEnabled => level.value <= Severity.debug.value;

  /// Whether [Severity.info] messages are emitted.
  bool get isInfoEnabled => level.value <= Severity.info.value;

  /// Whether [Severity.warn] messages are emitted.
  bool get isWarnEnabled => level.value <= Severity.warn.value;

  /// Whether [Severity.error] messages are emitted.
  bool get isErrorEnabled => level.value <= Severity.error.value;

  /// Whether [Severity.fatal] messages are emitted.
  bool get isFatalEnabled => level.value <= Severity.fatal.value;

  /// Logs [text] at [Severity.debug], optionally located [at] a position.
  void debug(String text, {Cursor? at}) =>
      add(Severity.debug, LogMessage(text, sourceLocation: at));

  /// Logs [text] at [Severity.info], optionally located [at] a position.
  void info(String text, {Cursor? at}) =>
      add(Severity.info, LogMessage(text, sourceLocation: at));

  /// Logs [text] at [Severity.warn], optionally located [at] a position.
  void warn(String text, {Cursor? at}) =>
      add(Severity.warn, LogMessage(text, sourceLocation: at));

  /// Logs [text] at [Severity.error], optionally located [at] a position.
  void error(String text, {Cursor? at}) =>
      add(Severity.error, LogMessage(text, sourceLocation: at));

  /// Logs [text] at [Severity.fatal], optionally located [at] a position.
  void fatal(String text, {Cursor? at}) =>
      add(Severity.fatal, LogMessage(text, sourceLocation: at));

  /// Logs [message] at [severity].
  void add(Severity severity, LogMessage message);

  /// Releases resources held by this logger.
  ///
  /// [Logger] closes file sinks it opened itself; a caller-supplied sink (in
  /// particular stderr) is never closed.
  Future<void> close();
}

/// The application logger.
///
/// Port of `Asciidoctor::Logger`: writes formatted records to a sink,
/// defaulting to stderr, program name `asciidoctor`, level `WARN` and the
/// [BasicFormatter].
class Logger extends LoggerBase {
  /// Creates a logger writing to [sink] (default stderr).
  new({
    StringSink? sink,
    Severity level = Severity.warn,
    this.formatter = const BasicFormatter(),
  }) : _sink = sink ?? stderr,
       _ownsSink = false,
       super(level);

  /// Creates a logger appending to the file at [path], which it closes in
  /// [close].
  new toFile(
    String path, {
    Severity level = Severity.warn,
    this.formatter = const BasicFormatter(),
  }) : _sink = File(path).openWrite(mode: FileMode.append),
       _ownsSink = true,
       super(level);

  final StringSink _sink;
  final bool _ownsSink;

  /// The program name stamped on every record.
  String progname = 'asciidoctor';

  /// The record formatter.
  LoggerFormatter formatter;

  Severity? _maxSeverity;

  @override
  Severity? get maxSeverity => _maxSeverity;

  /// The sink records are written to.
  StringSink get sink => _sink;

  @override
  void add(Severity severity, LogMessage message) {
    final currentMax = _maxSeverity;
    if (currentMax == null || severity.value > currentMax.value) {
      _maxSeverity = severity;
    }
    if (severity.value < level.value) return;
    _sink.write(formatter(severity, DateTime.now(), progname, message));
  }

  @override
  Future<void> close() async {
    final sink = _sink;
    if (_ownsSink && sink is IOSink) await sink.close();
  }
}

/// A log record kept in memory.
class MemoryLogMessage {
  /// Creates a record of [message] logged at [severity].
  const new(this.severity, this.message);

  /// The severity the message was logged at.
  final Severity severity;

  /// The logged message.
  final LogMessage message;
}

/// A logger recording every record in [messages].
///
/// Port of `Asciidoctor::MemoryLogger`: level `WARN`, no level filtering
/// ([add] records everything regardless of [level]).
class MemoryLogger extends LoggerBase {
  /// Creates an empty memory logger.
  new() : super(Severity.warn);

  /// The recorded records, in logging order.
  final List<MemoryLogMessage> messages = [];

  @override
  void add(Severity severity, LogMessage message) {
    messages.add(MemoryLogMessage(severity, message));
  }

  /// The highest recorded severity, or `null` when [messages] is empty.
  @override
  Severity? get maxSeverity {
    Severity? max;
    for (final record in messages) {
      if (max == null || record.severity.value > max.value) {
        max = record.severity;
      }
    }
    return max;
  }

  /// Drops all recorded records.
  void clear() => messages.clear();

  /// Whether no records were recorded.
  bool get isEmpty => messages.isEmpty;

  @override
  Future<void> close() async {}
}

/// A logger discarding every record while tracking [maxSeverity].
///
/// Port of `Asciidoctor::NullLogger` (level `WARN`).
class NullLogger extends LoggerBase {
  /// Creates a null logger.
  new() : super(Severity.warn);

  Severity? _maxSeverity;

  @override
  Severity? get maxSeverity => _maxSeverity;

  @override
  void add(Severity severity, LogMessage message) {
    final currentMax = _maxSeverity;
    if (currentMax == null || severity.value > currentMax.value) {
      _maxSeverity = severity;
    }
  }

  @override
  Future<void> close() async {}
}

/// Global logger registry.
///
/// Port of `Asciidoctor::LoggerManager`.
abstract final class LoggerManager {
  static LoggerBase? _logger;

  /// The global logger, created on first access (a [Logger] on stderr).
  static LoggerBase get logger => _logger ??= Logger();

  /// Replaces the global logger, or resets it to a default stderr [Logger]
  /// when [newLogger] is `null`.
  static set logger(LoggerBase? newLogger) => _logger = newLogger ?? Logger();
}
