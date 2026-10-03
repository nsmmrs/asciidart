/// Logging infrastructure for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/logging.rb` (`Asciidoctor::Logger`,
/// `Asciidoctor::MemoryLogger`, `Asciidoctor::NullLogger`,
/// `Asciidoctor::LoggerManager` and `Asciidoctor::Logging`).
///
/// Ruby's `::Logger` severity scale, manager memoization, `max_severity`
/// tracking (including messages dropped by the level filter) and the
/// `BasicFormatter` label substitutes (`WARN` → `WARNING`, `FATAL` →
/// `FAILED`) are all preserved. Deliberate divergences from `::Logger` are
/// marked `DIVERGENCE` in the member docs.
///
/// This file intentionally does not reference the temporary seams in
/// `abstract_node.dart` (`NodeLogger`) or `reader.dart` (`LogSeverity`,
/// `LogMessage`, `ReaderLogger`, `LoggerManager`); unifying them with this
/// port is a later pass (see the wave report).
library;

import 'dart:io' show File, FileMode, IOSink, pid, stderr;

/// Severity levels for log messages.
///
/// Port of `::Logger::Severity`. Integer [value]s match Ruby exactly
/// (`DEBUG` = 0 through `UNKNOWN` = 5); [label]s match Ruby's `SEV_LABEL`
/// (note: `UNKNOWN` renders as `ANY`, as in Ruby).
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

  /// Severity outside the known scale (label `ANY`, as in Ruby's
  /// `SEV_LABEL`).
  unknown(5, 'ANY');

  /// Creates a severity with integer [value] and format [label].
  const Severity(this.value, this.label);

  /// The integer severity, matching `::Logger::Severity`.
  final int value;

  /// The severity label used by formatters, matching `SEV_LABEL`.
  final String label;

  /// Returns the severity with integer [value].
  ///
  /// Throws an [ArgumentError] for values outside 0–5. DIVERGENCE: modern
  /// Ruby assigns out-of-range integer levels unchecked (e.g. `level = 99`
  /// silences every predicate); no in-repo caller relies on that (the CLI
  /// coerces level names upstream in `cli/options.rb`).
  static Severity fromValue(int value) {
    for (final severity in Severity.values) {
      if (severity.value == value) return severity;
    }
    throw ArgumentError('invalid log level: $value');
  }

  /// Returns the severity named [name] (case-insensitive).
  ///
  /// Accepts exactly the names Ruby's `Logger#level=` accepts: `DEBUG`,
  /// `INFO`, `WARN`, `ERROR`, `FATAL`, `UNKNOWN`. Anything else — including
  /// `WARNING` — throws an [ArgumentError], matching Ruby
  /// (`invalid log level: ...`).
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

  /// Coerces a user-supplied level to a [Severity].
  ///
  /// Accepts a [Severity] (returned as is), an [int] (see [fromValue]) or a
  /// [String] name (see [fromName]). Anything else, including `null`, throws
  /// an [ArgumentError]. Mirrors `::Logger#level=`.
  static Severity coerce(Object? value) {
    if (value is Severity) return value;
    if (value is int) return Severity.fromValue(value);
    if (value is String) return Severity.fromName(value);
    throw ArgumentError('invalid log level: $value');
  }
}

/// Formats a single log record.
///
/// Mirrors the `call(severity, time, progname, msg)` protocol of
/// `::Logger::Formatter` (here [severity] is a [Severity] instead of a
/// label string).
abstract interface class LoggerFormatter {
  /// Formats a record logged at [severity] with program name [progname] and
  /// resolved [message] at [time].
  String call(
    Severity severity,
    DateTime time,
    String progname,
    Object? message,
  );
}

/// Wraps a formatting function as a [LoggerFormatter].
///
/// Used when a raw function is passed as `formatter:` (Ruby accepts any
/// object responding to `call`).
final class _FunctionFormatter implements LoggerFormatter {
  /// Creates a formatter delegating to [format].
  const _FunctionFormatter(this.format);

  /// The wrapped formatting function.
  final String Function(
    Severity severity,
    DateTime time,
    String progname,
    Object? message,
  )
  format;

  @override
  String call(
    Severity severity,
    DateTime time,
    String progname,
    Object? message,
  ) => format(severity, time, progname, message);
}

/// Default log record formatter.
///
/// Mirrors `::Logger::Formatter#call`
/// (`D, [2026-10-03T05:25:29.294678 #pid] DEBUG -- progname: message`). Used
/// when `formatter:` is explicitly `null`, matching Ruby's
/// `opts.key? :formatter` check.
final class DefaultFormatter implements LoggerFormatter {
  /// Creates the default formatter.
  const DefaultFormatter();

  @override
  String call(
    Severity severity,
    DateTime time,
    String progname,
    Object? message,
  ) {
    final label = severity.label;
    return '${label[0]}, [${time.toIso8601String()} #$pid] ${label.padLeft(5)} -- $progname: $message\n';
  }
}

/// Traditional single-line log record formatter.
///
/// Port of `Asciidoctor::Logger::BasicFormatter`: renders
/// `progname: SEVERITY: message`, substituting `WARNING` for `WARN` and
/// `FAILED` for `FATAL`.
final class BasicFormatter implements LoggerFormatter {
  /// Creates the basic formatter.
  const BasicFormatter();

  /// Severity label substitutes. Port of `SEVERITY_LABEL_SUBSTITUTES`.
  static const Map<String, String> severityLabelSubstitutes = {
    'WARN': 'WARNING',
    'FATAL': 'FAILED',
  };

  @override
  String call(
    Severity severity,
    DateTime time,
    String progname,
    Object? message,
  ) {
    final label = severityLabelSubstitutes[severity.label] ?? severity.label;
    return '$progname: $label: $message\n';
  }
}

/// Shared `::Logger` behavior for [Logger], [MemoryLogger] and [NullLogger].
///
/// Holds the level filter, the `debug?`-style predicates (named
/// `isDebugEnabled`, etc.) and the severity convenience methods, which all
/// delegate to [add]. Subclasses implement [add] and [maxSeverity].
abstract class LoggerBase {
  /// Creates a logger with the given [level].
  LoggerBase(Severity level) : _level = level;

  Severity _level;

  /// The minimum severity emitted (messages below it are dropped, except by
  /// [MemoryLogger], which records everything like its Ruby counterpart).
  ///
  /// Assigning through this setter accepts a [Severity], an [int], or a
  /// [String] name (see [Severity.coerce]), mirroring `::Logger#level=`.
  Severity get level => _level;

  /// Sets the level from a [Severity], [int], or [String] name.
  set level(Object? value) => _level = Severity.coerce(value);

  /// The highest severity passed to [add] so far, or `null` when nothing
  /// was logged yet. Mirrors `max_severity`.
  Severity? get maxSeverity;

  /// Whether [Severity.debug] messages are emitted (`level <= DEBUG`).
  ///
  /// Mirrors `::Logger#debug?`.
  bool get isDebugEnabled => _level.value <= Severity.debug.value;

  /// Whether [Severity.info] messages are emitted (`level <= INFO`).
  ///
  /// Mirrors `::Logger#info?`.
  bool get isInfoEnabled => _level.value <= Severity.info.value;

  /// Whether [Severity.warn] messages are emitted (`level <= WARN`).
  ///
  /// Mirrors `::Logger#warn?`.
  bool get isWarnEnabled => _level.value <= Severity.warn.value;

  /// Whether [Severity.error] messages are emitted (`level <= ERROR`).
  ///
  /// Mirrors `::Logger#ERROR` predicate (`error?`).
  bool get isErrorEnabled => _level.value <= Severity.error.value;

  /// Whether [Severity.fatal] messages are emitted (`level <= FATAL`).
  ///
  /// Mirrors `::Logger#fatal?`.
  bool get isFatalEnabled => _level.value <= Severity.fatal.value;

  /// Logs [message] at [Severity.debug]. Returns `true`, as in Ruby.
  bool debug(Object? message) => add(Severity.debug, message);

  /// Logs [message] at [Severity.info]. Returns `true`, as in Ruby.
  bool info(Object? message) => add(Severity.info, message);

  /// Logs [message] at [Severity.warn]. Returns `true`, as in Ruby.
  bool warn(Object? message) => add(Severity.warn, message);

  /// Logs [message] at [Severity.error]. Returns `true`, as in Ruby.
  bool error(Object? message) => add(Severity.error, message);

  /// Logs [message] at [Severity.fatal]. Returns `true`, as in Ruby.
  bool fatal(Object? message) => add(Severity.fatal, message);

  /// Logs [message] at [Severity.unknown]. Returns `true`, as in Ruby.
  bool unknown(Object? message) => add(Severity.unknown, message);

  /// Logs [message] at [severity], resolving a `null` [message] from
  /// [progname] (mirroring `::Logger#add`, where the convenience methods
  /// pass their argument as `progname`).
  ///
  /// A `null` [severity] means [Severity.unknown]. A zero-argument function
  /// passed as [message] plays the role of Ruby's block form (`logger.info
  /// { ... }`): it is only invoked when the record is actually emitted (or
  /// recorded, for [MemoryLogger]), never for level-filtered records.
  /// Always returns `true`, as in Ruby.
  bool add(Severity? severity, [Object? message, Object? progname]);

  /// Releases resources held by this logger.
  ///
  /// [Logger] closes file sinks it opened itself; [MemoryLogger] and
  /// [NullLogger] do nothing. DIVERGENCE: Ruby's `Logger#close` closes
  /// whatever log device it was given; the Dart port never closes a
  /// caller-supplied sink (in particular never stderr).
  Future<void> close();
}

/// The application logger.
///
/// Port of `Asciidoctor::Logger`: writes formatted records to a log device,
/// defaults to stderr, program name `asciidoctor`, level `WARN` and the
/// [BasicFormatter].
class Logger extends LoggerBase {
  /// Creates a logger writing to [logdev].
  ///
  /// [logdev] may be a [StringSink] (e.g. a [StringBuffer] or [IOSink]), a
  /// [File], or a [String] file path (opened for appending, as Ruby's
  /// `Logger` does). When omitted it defaults to stderr; an explicit `null`
  /// discards all output (mirroring `::Logger.new(nil)`). Anything else
  /// throws an [ArgumentError].
  ///
  /// [level] defaults to [Severity.warn] when omitted and accepts a
  /// [Severity], [int], or [String] name (see [Severity.coerce]); an
  /// explicit `null` throws an [ArgumentError], as in Ruby.
  ///
  /// [formatter] defaults to the [BasicFormatter] when omitted; an explicit
  /// `null` selects the [DefaultFormatter] (mirroring Ruby's
  /// `opts.key? :formatter` check); a [LoggerFormatter] — or a raw
  /// formatting function — is used as is.
  Logger({
    Object? logdev = _unspecified,
    Object? level = _unspecified,
    Object? formatter = _unspecified,
  }) : this._(_resolveLogdev(logdev), _resolveLevel(level), formatter);

  /// Creates a logger from an already-resolved log device.
  Logger._(_ResolvedLogdev resolved, super.level, Object? formatter)
    : _sink = resolved.sink,
      _ownsSink = resolved.owned {
    this.formatter = _resolveFormatter(formatter);
  }

  /// Sentinel distinguishing an omitted optional argument from an explicit
  /// `null` (which Ruby's `opts.key?` checks can tell apart).
  static const Object _unspecified = Object();

  final StringSink _sink;
  final bool _ownsSink;

  /// The program name stamped on every record. Always starts as
  /// `asciidoctor` (Ruby assigns it unconditionally in the constructor).
  String progname = 'asciidoctor';

  /// The record formatter. Mirrors `::Logger#formatter`.
  late LoggerFormatter formatter;

  Severity? _maxSeverity;

  @override
  Severity? get maxSeverity => _maxSeverity;

  /// The sink records are written to (stderr, a caller-supplied sink, or a
  /// file sink opened from a path).
  StringSink get logdev => _sink;

  @override
  bool add(Severity? severity, [Object? message, Object? progname]) {
    final resolved = severity ?? Severity.unknown;
    final currentMax = _maxSeverity;
    if (currentMax == null || resolved.value > currentMax.value) {
      _maxSeverity = resolved;
    }
    if (resolved.value < level.value) return true;
    var text = message;
    if (text is Object? Function()) text = text();
    final String effectiveProgname;
    if (text == null) {
      text = progname;
      effectiveProgname = this.progname;
    } else {
      effectiveProgname = progname?.toString() ?? this.progname;
    }
    _sink.write(formatter(resolved, DateTime.now(), effectiveProgname, text));
    return true;
  }

  @override
  Future<void> close() async {
    final sink = _sink;
    if (_ownsSink && sink is IOSink) await sink.close();
  }

  static Severity _resolveLevel(Object? level) =>
      identical(level, _unspecified) ? Severity.warn : Severity.coerce(level);

  static LoggerFormatter _resolveFormatter(Object? formatter) {
    if (identical(formatter, _unspecified)) return const BasicFormatter();
    if (formatter == null) return const DefaultFormatter();
    if (formatter is LoggerFormatter) return formatter;
    if (formatter is String Function(Severity, DateTime, String, Object?)) {
      return _FunctionFormatter(formatter);
    }
    throw ArgumentError.value(
      formatter,
      'formatter',
      'expected a LoggerFormatter, a formatting function, or null',
    );
  }

  static _ResolvedLogdev _resolveLogdev(Object? logdev) {
    if (identical(logdev, _unspecified)) return _ResolvedLogdev(stderr, false);
    if (logdev == null) return _ResolvedLogdev(_NullSink(), false);
    if (logdev is StringSink) return _ResolvedLogdev(logdev, false);
    if (logdev is File) {
      return _ResolvedLogdev(logdev.openWrite(mode: FileMode.append), true);
    }
    if (logdev is String) {
      return _ResolvedLogdev(
        File(logdev).openWrite(mode: FileMode.append),
        true,
      );
    }
    throw ArgumentError.value(
      logdev,
      'logdev',
      'expected a StringSink, File, file path, or null',
    );
  }
}

/// A log device plus whether the logger owns (and must close) it.
class _ResolvedLogdev {
  /// Creates a resolved log device.
  const _ResolvedLogdev(this.sink, this.owned);

  /// The sink records are written to.
  final StringSink sink;

  /// Whether the logger opened [sink] itself.
  final bool owned;
}

/// A sink discarding everything written to it (a `null` log device).
class _NullSink implements StringSink {
  /// Creates the discarding sink.
  const _NullSink();

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
}

/// A log record kept in memory.
///
/// Port of the `{severity:, message:}` hashes stored in
/// `Asciidoctor::MemoryLogger#messages` ([severity] is a [Severity] instead
/// of a symbol).
class MemoryLogMessage {
  /// Creates a record of [message] logged at [severity].
  const MemoryLogMessage(this.severity, this.message);

  /// The severity the message was logged at.
  final Severity severity;

  /// The resolved message (never a lazy function).
  final Object? message;
}

/// A logger recording every record in [messages].
///
/// Port of `Asciidoctor::MemoryLogger`: level `UNKNOWN`, no level filtering
/// ([add] records everything, exactly like Ruby, which overrides `add`
/// without a level check).
class MemoryLogger extends LoggerBase {
  /// Creates an empty memory logger.
  MemoryLogger() : super(Severity.unknown);

  /// The recorded records, in logging order.
  final List<MemoryLogMessage> messages = [];

  @override
  bool add(Severity? severity, [Object? message, Object? progname]) {
    var text = message;
    if (text is Object? Function()) text = text();
    text ??= progname;
    messages.add(MemoryLogMessage(severity ?? Severity.unknown, text));
    return true;
  }

  /// The highest recorded severity, or `null` when [messages] is empty.
  ///
  /// Mirrors `MemoryLogger#max_severity`.
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

  /// Drops all recorded records. Mirrors `MemoryLogger#clear`.
  void clear() => messages.clear();

  /// Whether no records were recorded. Mirrors `MemoryLogger#empty?`.
  bool get isEmpty => messages.isEmpty;

  @override
  Future<void> close() async {}
}

/// A logger discarding every record while tracking [maxSeverity].
///
/// Port of `Asciidoctor::NullLogger` (level `UNKNOWN`).
class NullLogger extends LoggerBase {
  /// Creates a null logger.
  NullLogger() : super(Severity.unknown);

  Severity? _maxSeverity;

  @override
  Severity? get maxSeverity => _maxSeverity;

  @override
  bool add(Severity? severity, [Object? message, Object? progname]) {
    final resolved = severity ?? Severity.unknown;
    final currentMax = _maxSeverity;
    if (currentMax == null || resolved.value > currentMax.value) {
      _maxSeverity = resolved;
    }
    return true;
  }

  @override
  Future<void> close() async {}
}

/// Global logger registry.
///
/// Port of `Asciidoctor::LoggerManager`. [loggerFactory] plays the role of
/// the `logger_class` property (a factory rather than a class object, since
/// Dart cannot instantiate a `Type`).
abstract final class LoggerManager {
  /// Creates loggers from a log device. Mirrors the `logger_class`
  /// property; tests replace it to observe instantiation.
  static LoggerBase Function([Object? logdev]) loggerFactory = ([
    Object? logdev,
  ]) => Logger(logdev: logdev ?? stderr);

  static LoggerBase? _logger;

  /// The global logger, memoized on first access (mirroring the
  /// `memoize_logger` redefinition of `LoggerManager.logger`).
  static LoggerBase get logger => _logger ??= loggerFactory(stderr);

  /// Replaces the global logger, or resets it to a default instance when
  /// [newLogger] is `null`. Mirrors `LoggerManager.logger=`.
  static set logger(LoggerBase? newLogger) =>
      _logger = newLogger ?? loggerFactory(stderr);

  /// Returns the memoized global logger, creating it with [logdev] on first
  /// access. Mirrors the optional `pipe` argument of
  /// `LoggerManager.logger`, which is only honored before memoization.
  static LoggerBase loggerWithLogdev([Object? logdev]) =>
      _logger ??= loggerFactory(logdev ?? stderr);
}

/// A log message carrying source context.
///
/// Port of the `{text:, ...}` hash built by `Logging#message_with_context`
/// (extended with `Logger::AutoFormattingMessage`): [toString] renders
/// `sourceLocation: text` when a location is present, else [text].
class ContextMessage {
  /// Creates a message with [text] and optional [sourceLocation].
  const ContextMessage(this.text, {this.sourceLocation});

  /// The message text, without location prefix. Mirrors `message[:text]`.
  final String text;

  /// The source location (e.g. a reader cursor) the message refers to, if
  /// any. Mirrors `message[:source_location]`.
  final Object? sourceLocation;

  @override
  String toString() {
    final location = sourceLocation;
    return location == null ? text : '$location: $text';
  }
}

/// Mixes the logging surface into a class.
///
/// Port of `Asciidoctor::Logging`: [logger] reaches the global logger and
/// [messageWithContext] builds auto-formatting [ContextMessage]s.
mixin Logging {
  /// The global logger. Mirrors `Logging#logger`.
  LoggerBase get logger => LoggerManager.logger;

  /// Builds a [ContextMessage] with [text] plus [sourceLocation] context.
  ///
  /// Mirrors `Logging#message_with_context` (whose arbitrary `context` hash
  /// is only ever given `source_location` by in-repo callers).
  ContextMessage messageWithContext(String text, {Object? sourceLocation}) =>
      ContextMessage(text, sourceLocation: sourceLocation);
}
