/// Tests for the logging port (`lib/src/logging.dart`).
///
/// Ports `test/logger_test.rb` (27 tests). Mapping notes:
///
/// * `redirect_streams` has no Dart equivalent (stderr cannot be rebound per
///   test), so stream-capture assertions become [StringBuffer]-logdev
///   assertions, plus `identical(logger.logdev, stderr)` wiring checks for
///   the stderr-default cases.
/// * The five `:logger API option` tests need the document/load wave
///   (`load.rb` assigns `LoggerManager.logger` from the `:logger` option),
///   so they are present as skipped placeholders preserving intent.
/// * `test/logger_test.rb` barely exercises `MemoryLogger`/`NullLogger`
///   (level only) and never `max_severity`; the `extra` groups below cover
///   those contracts directly (all verified against Ruby via `ruby -Ilib`
///   probes — see the wave report).
library;

import 'dart:io';

import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/reader.dart' as reader;
import 'package:test/test.dart';

/// A [Logger] subclass, mirroring `MyLogger = Class.new Logger`.
class TestLogger extends Logger {
  /// Creates a test logger writing to [logdev].
  new([Object? logdev]) : super(logdev: logdev);
}

/// Runs [body] with the global logger (and factory) restored afterwards,
/// mirroring the `begin/ensure` blocks in `test/logger_test.rb`.
void withManagerLogger(void Function() body) {
  final oldLogger = LoggerManager.logger;
  final oldFactory = LoggerManager.loggerFactory;
  try {
    body();
  } finally {
    LoggerManager.loggerFactory = oldFactory;
    LoggerManager.logger = oldLogger;
  }
}

/// Installs a fresh default global logger for [body] (mirroring
/// `LoggerManager.logger = nil`), restoring the previous logger after.
void withFreshDefaultLogger(void Function(LoggerBase logger) body) {
  withManagerLogger(() {
    LoggerManager.logger = null;
    body(LoggerManager.logger);
  });
}

/// Creates a scratch directory for [body], deleting it afterwards.
Future<void> withTempDir(Future<void> Function(Directory dir) body) async {
  final dir = Directory.systemTemp.createTempSync('asciidoctor-logger-test');
  try {
    await body(dir);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// A [Logging] carrier for the instance-access tests.
class SampleClassC with Logging {
  /// Returns the mixed-in logger.
  LoggerBase retrieveLogger() => logger;
}

/// A [Logging] carrier with a static accessor, mirroring a Ruby class
/// extended with `Logging` (whose Dart equivalent reaches [LoggerManager]
/// directly, since mixins contribute no statics).
class SampleClassD with Logging {
  /// Returns the global logger.
  static LoggerBase retrieveLogger() => LoggerManager.logger;
}

/// A mixin layered on [Logging], mirroring a Ruby module including
/// `Asciidoctor::Logging` and consumed by a class.
mixin SampleMixinA on Logging {
  /// Returns the mixed-in logger.
  LoggerBase retrieveLogger() => logger;
}

/// Consumes [SampleMixinA].
class SampleClassA with Logging, SampleMixinA;

/// A mixin with a static accessor, mirroring a Ruby module extended with
/// `Logging`.
mixin SampleMixinB {
  /// Returns the global logger.
  static LoggerBase retrieveLogger() => LoggerManager.logger;
}

/// A [Logging] carrier for the message-context tests.
class SampleClassE with Logging {
  /// Builds a message carrying [sourceLocation] context.
  ContextMessage createMessage(Object? sourceLocation) => messageWithContext(
    'Asciidoctor was here',
    sourceLocation: sourceLocation,
  );
}

void main() {
  group('LoggerManager', () {
    test('provides access to logger via static logger method', () {
      final logger = LoggerManager.logger;
      expect(logger, isNotNull);
      expect(logger, isA<LoggerBase>());
    });

    test('allows logger instance to be changed', () {
      withManagerLogger(() {
        final newLogger = TestLogger(stdout);
        LoggerManager.logger = newLogger;
        expect(LoggerManager.logger, same(newLogger));
      });
    });

    test(
      'setting logger instance to null resets instance to default logger',
      () {
        // Ruby: falsy values (`nil`, `false`); Dart only has `null`.
        withManagerLogger(() {
          LoggerManager.logger = TestLogger(stdout);
          LoggerManager.logger = null;
          expect(LoggerManager.logger, isNotNull);
          expect(LoggerManager.logger, isA<LoggerBase>());
        });
      },
    );

    test('creates logger instance from static loggerFactory property', () {
      // Ruby: `logger_class` property; Dart: [LoggerManager.loggerFactory].
      withManagerLogger(() {
        LoggerManager.loggerFactory = TestLogger.new;
        LoggerManager.logger = null;
        expect(LoggerManager.logger, isNotNull);
        expect(LoggerManager.logger, isA<TestLogger>());
      });
    });
  });

  group('Logger', () {
    test('should set logdev to stderr by default', () {
      // Ruby captures $stderr; Dart asserts the wiring plus routed output.
      expect(Logger().logdev, same(stderr));
      final buffer = StringBuffer();
      Logger(logdev: buffer).warn('this is a call');
      expect(buffer.toString(), contains('this is a call'));
    });

    test('should set logdev to specified file', () async {
      await withTempDir((dir) async {
        final path = '${dir.path}${Platform.pathSeparator}out.log';
        final logger = (Logger(logdev: path))..warn('this is a call');
        await logger.close();
        expect(
          File(path).readAsStringSync().trim().split('\n').last,
          equals('asciidoctor: WARNING: this is a call'),
        );
      });
    });

    test(
      'should set logdev to specified file with additional options',
      () async {
        await withTempDir((dir) async {
          final path = '${dir.path}${Platform.pathSeparator}out.log';
          final logger = (Logger(
            logdev: path,
            formatter: null,
            level: Severity.debug,
          ))..debug('this is a sign of life');
          await logger.close();
          expect(
            File(path).readAsStringSync().trim().split('\n').last,
            contains('DEBUG -- asciidoctor: this is a sign of life'),
          );
        });
      },
    );

    test('should set level to value specified by level kwarg', () {
      final buffer = StringBuffer();
      final logger = (Logger(logdev: buffer, level: 'fatal'))
        ..warn('this is a call');
      expect(buffer.toString(), isEmpty);
      expect(logger.level, equals(Severity.fatal));
    });

    test('should configure logger with progname set to asciidoctor', () {
      expect(Logger().progname, equals('asciidoctor'));
    });

    test('should configure logger with level set to WARN by default', () {
      expect(Logger().level, equals(Severity.warn));
    });

    test('configures default logger with progname set to asciidoctor', () {
      withFreshDefaultLogger((logger) {
        expect((logger as Logger).progname, equals('asciidoctor'));
      });
    });

    test('configures default logger with level set to WARN', () {
      withFreshDefaultLogger((logger) {
        expect(logger.level, equals(Severity.warn));
      });
    });

    test('configures default logger to write messages to stderr', () {
      withFreshDefaultLogger((logger) {
        expect((logger as Logger).logdev, same(stderr));
      });
    });

    test('configures default logger to use a formatter that matches traditional format', () {
      withManagerLogger(() {
        final buffer = StringBuffer();
        LoggerManager.logger = Logger(logdev: buffer);
        LoggerManager.logger.warn('this is a call');
        LoggerManager.logger.fatal('it cannot be done');
        expect(
          buffer.toString(),
          contains('asciidoctor: WARNING: this is a call'),
        );
        expect(
          buffer.toString(),
          contains('asciidoctor: FAILED: it cannot be done'),
        );
      });
    });

    test('NullLogger level is not null', () {
      final logger = NullLogger();
      expect(logger.level, isNotNull);
      expect(logger.level, equals(Severity.unknown));
    });

    test('MemoryLogger level is not null', () {
      final logger = MemoryLogger();
      expect(logger.level, isNotNull);
      expect(logger.level, equals(Severity.unknown));
    });
  });

  group(
    'logger option (document wave)',
    () {
      test('load API assigns the given logger', () {
        withManagerLogger(() {
          final newLogger = TestLogger(stdout);
          load('contents', {'logger': newLogger});
          expect(LoggerManager.logger, same(newLogger));
        });
      });
      test('load_file API assigns the given logger', () {
        withManagerLogger(() {
          final newLogger = TestLogger(stdout);
          loadFile('test/fixtures/basic.adoc', {'logger': newLogger});
          expect(LoggerManager.logger, same(newLogger));
        });
      });
      test('convert API assigns the given logger', () {
        withManagerLogger(() {
          final newLogger = TestLogger(stdout);
          convert('contents', {'logger': newLogger});
          expect(LoggerManager.logger, same(newLogger));
        });
      });
      test('convert_file API assigns the given logger', () {
        withManagerLogger(() {
          final newLogger = TestLogger(stdout);
          convertFile('test/fixtures/basic.adoc', {
            'to_file': false,
            'logger': newLogger,
          });
          expect(LoggerManager.logger, same(newLogger));
        });
      });
      test('falsy logger option installs a NullLogger', () {
        for (final falsyValue in [null, false]) {
          withManagerLogger(() {
            load('contents', {'logger': falsyValue});
            expect(LoggerManager.logger, isA<NullLogger>());
          });
        }
      });
    },
    // Ruby group name is ':logger API option'.
  );

  group('Logging', () {
    test('including Logging gives instance methods on mixin access to logging infrastructure', () {
      expect(SampleClassA().retrieveLogger(), same(LoggerManager.logger));
    });

    test('including Logging gives static methods on mixin access to logging infrastructure', () {
      expect(SampleMixinB.retrieveLogger(), same(LoggerManager.logger));
    });

    test('including Logging gives instance methods on class access to logging infrastructure', () {
      expect(SampleClassC().retrieveLogger(), same(LoggerManager.logger));
    });

    test('including Logging gives static methods on class access to logging infrastructure', () {
      expect(SampleClassD.retrieveLogger(), same(LoggerManager.logger));
    });

    test('can create an auto-formatting message with context', () {
      final cursor = reader.Cursor('file.adoc', 'fixturedir', 'file.adoc', 5);
      final message = SampleClassE().createMessage(cursor);
      expect(message.text, equals('Asciidoctor was here'));
      expect(message.sourceLocation, same(cursor));
      expect(
        message.toString(),
        equals('file.adoc: line 5: Asciidoctor was here'),
      );
    });

    test('writes message prefixed with program name and source location', () {
      // Pipeline equivalent of the convert_string_to_embedded assertion in
      // Ruby (the tree converter is document-wave work): the same message
      // through the real logger and formatter must render the exact line.
      final buffer = StringBuffer();
      Logger(logdev: buffer).warn(
        ContextMessage(
          'id assigned to block already in use: first',
          sourceLocation: _FakeCursor(),
        ),
      );
      expect(
        buffer.toString().trim(),
        equals(
          'asciidoctor: WARNING: <stdin>: line 5: id assigned to block already in use: first',
        ),
      );
    });
  });

  group('Severity (extra)', () {
    test('integer values match ::Logger::Severity', () {
      expect(Severity.debug.value, equals(0));
      expect(Severity.info.value, equals(1));
      expect(Severity.warn.value, equals(2));
      expect(Severity.error.value, equals(3));
      expect(Severity.fatal.value, equals(4));
      expect(Severity.unknown.value, equals(5));
    });

    test('labels match SEV_LABEL, including ANY for unknown', () {
      expect(Severity.debug.label, equals('DEBUG'));
      expect(Severity.info.label, equals('INFO'));
      expect(Severity.warn.label, equals('WARN'));
      expect(Severity.error.label, equals('ERROR'));
      expect(Severity.fatal.label, equals('FATAL'));
      expect(Severity.unknown.label, equals('ANY'));
    });

    test('fromName accepts the six canonical names case-insensitively', () {
      expect(Severity.fromName('debug'), equals(Severity.debug));
      expect(Severity.fromName('INFO'), equals(Severity.info));
      expect(Severity.fromName('Warn'), equals(Severity.warn));
      expect(Severity.fromName('ERROR'), equals(Severity.error));
      expect(Severity.fromName('fatal'), equals(Severity.fatal));
      expect(Severity.fromName('Unknown'), equals(Severity.unknown));
    });

    test('fromName rejects WARNING like Ruby', () {
      expect(() => Severity.fromName('WARNING'), throwsArgumentError);
      expect(() => Severity.fromName('bogus'), throwsArgumentError);
    });

    test('coerce accepts Severity, int, and String, rejecting the rest', () {
      expect(Severity.coerce(Severity.error), equals(Severity.error));
      expect(Severity.coerce(3), equals(Severity.error));
      expect(Severity.coerce('fatal'), equals(Severity.fatal));
      expect(() => Severity.coerce(99), throwsArgumentError);
      expect(() => Severity.coerce(null), throwsArgumentError);
      expect(() => Severity.coerce(true), throwsArgumentError);
    });
  });

  group('Logger behavior (extra)', () {
    test('level setter accepts Severity, int, and String', () {
      final logger = (Logger(logdev: StringBuffer()))..level = Severity.debug;
      expect(logger.level, equals(Severity.debug));
      logger.level = 3;
      expect(logger.level, equals(Severity.error));
      logger.level = 'fatal';
      expect(logger.level, equals(Severity.fatal));
      expect(() => logger.level = 'bogus', throwsArgumentError);
    });

    test('predicates compare against the level', () {
      final logger = Logger(logdev: StringBuffer());
      expect(logger.isDebugEnabled, isFalse);
      expect(logger.isInfoEnabled, isFalse);
      expect(logger.isWarnEnabled, isTrue);
      expect(logger.isErrorEnabled, isTrue);
      expect(logger.isFatalEnabled, isTrue);
      logger.level = Severity.debug;
      expect(logger.isDebugEnabled, isTrue);
    });

    test('severity methods return true', () {
      final logger = Logger(logdev: StringBuffer(), level: Severity.debug);
      expect(logger.debug('d'), isTrue);
      expect(logger.info('i'), isTrue);
      expect(logger.warn('w'), isTrue);
      expect(logger.error('e'), isTrue);
      expect(logger.fatal('f'), isTrue);
      expect(logger.unknown('u'), isTrue);
    });

    test('max_severity starts null and tracks even filtered messages', () {
      final logger = Logger(logdev: StringBuffer());
      expect(logger.maxSeverity, isNull);
      logger.debug('filtered');
      expect(logger.maxSeverity, equals(Severity.debug));
      logger.error('kept');
      expect(logger.maxSeverity, equals(Severity.error));
      logger.warn('lower');
      expect(logger.maxSeverity, equals(Severity.error));
    });

    test('add with null severity logs at UNKNOWN with the ANY label', () {
      final buffer = StringBuffer();
      final logger = Logger(logdev: buffer);
      expect(logger.add(null, 'mystery'), isTrue);
      expect(logger.maxSeverity, equals(Severity.unknown));
      expect(buffer.toString(), equals('asciidoctor: ANY: mystery\n'));
    });

    test('add resolves a null message from progname', () {
      final buffer = StringBuffer();
      Logger(
        logdev: buffer,
        level: Severity.debug,
      ).add(Severity.error, null, 'progmsg');
      expect(buffer.toString(), equals('asciidoctor: ERROR: progmsg\n'));
    });

    test('lazy message functions run only when the record is emitted', () {
      var evaluated = 0;
      Object? produce() {
        evaluated++;
        return 'lazy $evaluated';
      }

      final kept = StringBuffer();
      Logger(logdev: kept, level: Severity.debug).info(produce);
      expect(evaluated, equals(1));
      expect(kept.toString(), equals('asciidoctor: INFO: lazy 1\n'));

      final dropped = StringBuffer();
      Logger(logdev: dropped).debug(produce);
      expect(evaluated, equals(1));
      expect(dropped.toString(), isEmpty);
    });

    test('non-string messages render via toString', () {
      final buffer = StringBuffer();
      (Logger(logdev: buffer))
        ..warn(42)
        ..warn({'a': 1});
      expect(
        buffer.toString(),
        equals('asciidoctor: WARNING: 42\nasciidoctor: WARNING: {a: 1}\n'),
      );
    });

    test('explicit null logdev discards output', () {
      final logger = Logger(logdev: null, level: Severity.debug);
      expect(logger.warn('lost'), isTrue);
      expect(logger.maxSeverity, equals(Severity.warn));
    });

    test('invalid logdev and formatter types throw ArgumentError', () {
      expect(() => Logger(logdev: 42), throwsArgumentError);
      expect(
        () => Logger(logdev: StringBuffer(), formatter: 42),
        throwsArgumentError,
      );
    });

    test('explicit null level throws ArgumentError like Ruby', () {
      expect(
        () => Logger(logdev: StringBuffer(), level: null),
        throwsArgumentError,
      );
    });

    test('constructor forces progname to asciidoctor', () {
      final buffer = StringBuffer();
      Logger(logdev: buffer).warn('x');
      expect(buffer.toString(), startsWith('asciidoctor: '));
    });

    test('file logdev appends like Ruby', () async {
      await withTempDir((dir) async {
        final path = '${dir.path}${Platform.pathSeparator}app.log';
        File(path).writeAsStringSync('old');
        final logger = (Logger(logdev: path))..warn('new');
        await logger.close();
        expect(
          File(path).readAsStringSync(),
          equals('oldasciidoctor: WARNING: new\n'),
        );
      });
    });

    test('close on a stderr logger does not close stderr', () async {
      await Logger().close();
      stderr.writeln('stderr still open');
    });

    test('default formatter renders the traditional tagged line', () {
      final message = const DefaultFormatter().call(
        Severity.debug,
        DateTime(2026, 1, 2, 3, 4, 5),
        'asciidoctor',
        'hi',
      );
      expect(message, startsWith('D, ['));
      expect(message, contains('] DEBUG -- asciidoctor: hi\n'));
      expect(message, contains('#$pid'));
    });

    test('custom formatter function is used as is', () {
      final buffer = StringBuffer();
      Logger(
        logdev: buffer,
        formatter: (
          Severity severity,
          DateTime time,
          String progname,
          Object? message,
        ) => '$progname=${severity.label}=$message\n',
      ).warn('x');
      expect(buffer.toString(), equals('asciidoctor=WARN=x\n'));
    });

    test('loggerWithLogdev returns the memoized logger once set', () {
      // The logdev argument is only honored before memoization (mirroring
      // Ruby's `memoize_logger` redefinition); there is no public reset to
      // the unmemoized state, so this asserts the post-memoization path.
      withManagerLogger(() {
        final buffer = StringBuffer();
        LoggerManager.logger = Logger(logdev: buffer);
        final logger = LoggerManager.loggerWithLogdev(StringBuffer());
        expect(logger, same(LoggerManager.logger));
        expect((logger as Logger).logdev, same(buffer));
      });
    });

    test('resetting the manager logger uses the factory', () {
      withManagerLogger(() {
        LoggerManager.logger = TestLogger(stdout);
        LoggerManager.logger = null;
        expect(LoggerManager.logger, isA<Logger>());
      });
    });
  });

  group('MemoryLogger (extra)', () {
    test('records every severity without level filtering', () {
      final logger = (MemoryLogger())
        ..add(Severity.warn, 'w1')
        ..warn('w2')
        ..debug('d');
      expect(logger.messages, hasLength(3));
      expect(logger.messages[0].severity, equals(Severity.warn));
      expect(logger.messages[0].message, equals('w1'));
      expect(logger.messages[1].message, equals('w2'));
      expect(logger.messages[2].severity, equals(Severity.debug));
    });

    test(
      'add resolves message from block or progname, defaulting severity',
      () {
        final logger = (MemoryLogger())
          ..add(null, null, 'progonly')
          ..add(Severity.error, () => 'from-block');
        expect(logger.messages[0].severity, equals(Severity.unknown));
        expect(logger.messages[0].message, equals('progonly'));
        expect(logger.messages[1].severity, equals(Severity.error));
        expect(logger.messages[1].message, equals('from-block'));
      },
    );

    test('maxSeverity is null when empty, else the highest severity', () {
      final logger = MemoryLogger();
      expect(logger.isEmpty, isTrue);
      expect(logger.maxSeverity, isNull);
      logger
        ..debug('d')
        ..warn('w');
      expect(logger.isEmpty, isFalse);
      expect(logger.maxSeverity, equals(Severity.warn));
      logger.clear();
      expect(logger.isEmpty, isTrue);
      expect(logger.maxSeverity, isNull);
    });

    test('predicates are all false at UNKNOWN, level stays settable', () {
      final logger = MemoryLogger();
      expect(logger.isDebugEnabled, isFalse);
      expect(logger.isFatalEnabled, isFalse);
      logger.level = Severity.debug;
      expect(logger.isDebugEnabled, isTrue);
      logger.debug('still recorded');
      expect(logger.messages, hasLength(1));
    });
  });

  group('NullLogger (extra)', () {
    test('discards output while tracking maxSeverity', () {
      final logger = NullLogger();
      expect(logger.maxSeverity, isNull);
      expect(logger.warn('x'), isTrue);
      expect(logger.maxSeverity, equals(Severity.warn));
      logger.error('y');
      expect(logger.maxSeverity, equals(Severity.error));
    });

    test('predicates are all false', () {
      final logger = NullLogger();
      expect(logger.isDebugEnabled, isFalse);
      expect(logger.isWarnEnabled, isFalse);
    });
  });

  group('ContextMessage (extra)', () {
    test('renders bare text without a location', () {
      expect(const ContextMessage('hi').toString(), equals('hi'));
      expect(const ContextMessage('hi').sourceLocation, isNull);
    });
  });
}

/// Stands in for a reader cursor at `<stdin>: line 5`.
class _FakeCursor {
  @override
  String toString() => '<stdin>: line 5';
}
