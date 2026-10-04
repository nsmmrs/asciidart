/// Tests for the logging infrastructure: loggers, formatters, severities
/// and the global logger.
///
/// Port of `test/logger_test.rb`, adapted to the typed Dart API.
library;

import 'dart:io';

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

import 'support/doc_helpers.dart';

/// Runs [body] with the global logger restored afterwards.
void withManagerLogger(void Function() body) {
  final saved = LoggerManager.logger;
  try {
    body();
  } finally {
    LoggerManager.logger = saved;
  }
}

/// Logs to a buffer at [level] and returns what was written.
String logTo(void Function(Logger logger) body, {Severity? level}) {
  final sink = StringBuffer();
  final logger = Logger(sink: sink, level: level ?? Severity.warn);
  body(logger);
  return sink.toString();
}

void main() {
  group('LoggerManager', () {
    test('provides access to a default logger', () {
      withManagerLogger(() {
        LoggerManager.logger = null;
        final logger = LoggerManager.logger;
        expect(logger, isA<Logger>());
        expect(LoggerManager.logger, same(logger));
      });
    });

    test('allows the logger instance to be changed', () {
      withManagerLogger(() {
        final memory = MemoryLogger();
        LoggerManager.logger = memory;
        expect(LoggerManager.logger, same(memory));
      });
    });

    test(
      testOn: 'vm',
      'resetting the logger restores a default stderr logger',
      () {
        withManagerLogger(() {
          LoggerManager.logger = MemoryLogger();
          LoggerManager.logger = null;
          final logger = LoggerManager.logger as Logger;
          expect(logger.sink, same(stderr));
        });
      },
    );
  });

  group('Logger', () {
    test(testOn: 'vm', 'writes to stderr by default', () {
      expect(Logger().sink, same(stderr));
    });

    test(testOn: 'vm', 'appends to the file given to Logger.toFile', () async {
      final dir = Directory.systemTemp.createTempSync('logger_test_');
      try {
        final path = '${dir.path}/log.txt';
        File(path).writeAsStringSync('existing\n');
        final logger = Logger.toFile(path)..warn('appended');
        await logger.close();
        expect(
          File(path).readAsStringSync(),
          equals('existing\nasciidoctor: WARNING: appended\n'),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('sets level to the value given', () {
      expect(Logger(level: Severity.debug).level, equals(Severity.debug));
    });

    test('defaults to the asciidoctor progname and the WARN level', () {
      final logger = Logger();
      expect(logger.progname, equals('asciidoctor'));
      expect(logger.level, equals(Severity.warn));
      expect(logger.formatter, isA<BasicFormatter>());
    });

    test('formats messages with the program name and severity label', () {
      final output = logTo((logger) {
        logger
          ..warn('this is a call')
          ..error('an error')
          ..fatal('fatal');
      });
      expect(
        output,
        equals(
          'asciidoctor: WARNING: this is a call\n'
          'asciidoctor: ERROR: an error\n'
          'asciidoctor: FAILED: fatal\n',
        ),
      );
    });

    test('prefixes messages with the source location', () {
      final output = logTo((logger) {
        logger.warn(
          'Asciidoctor was here',
          at: Cursor('file.adoc', 'fixturedir', 'file.adoc', 5),
        );
      });
      expect(
        output,
        equals(
          'asciidoctor: WARNING: file.adoc: line 5: Asciidoctor was here\n',
        ),
      );
    });

    test('drops messages below the level but tracks maxSeverity', () {
      final sink = StringBuffer();
      final logger = Logger(sink: sink);
      expect(logger.maxSeverity, isNull);
      logger.info('dropped');
      expect(sink.toString(), isEmpty);
      expect(logger.maxSeverity, equals(Severity.info));
      logger
        ..error('kept')
        ..warn('kept too');
      expect(logger.maxSeverity, equals(Severity.error));
      expect(sink.toString(), contains('kept'));
    });

    test('predicates compare against the level', () {
      final logger = Logger();
      expect(logger.isDebugEnabled, isFalse);
      expect(logger.isInfoEnabled, isFalse);
      expect(logger.isWarnEnabled, isTrue);
      expect(logger.isErrorEnabled, isTrue);
      expect(logger.isFatalEnabled, isTrue);
    });

    test('add logs a message at the given severity', () {
      final output = logTo(
        (logger) => logger.add(Severity.unknown, const LogMessage('any')),
      );
      expect(output, equals('asciidoctor: ANY: any\n'));
    });

    test(
      testOn: 'vm',
      'close on a stderr logger does not close stderr',
      () async {
        await Logger().close();
        stderr.write('');
      },
    );

    test('the default formatter renders the traditional tagged line', () {
      final line = const DefaultFormatter()(
        Severity.warn,
        DateTime.utc(2026, 1, 2, 3, 4, 5),
        'asciidoctor',
        const LogMessage('text'),
      );
      expect(
        line,
        matches(
          RegExp(
            r'^W, \[2026-01-02T03:04:05\.000Z #\d+\]  WARN -- '
            r'asciidoctor: text\n$',
          ),
        ),
      );
    });

    test('uses a custom formatter', () {
      final sink = StringBuffer();
      Logger(sink: sink, formatter: const _UpperFormatter()).warn('loud');
      expect(sink.toString(), equals('WARN LOUD\n'));
    });
  });

  group('Severity', () {
    test('integer values follow the standard scale', () {
      expect(
        Severity.values.map((severity) => severity.value),
        equals([0, 1, 2, 3, 4, 5]),
      );
    });

    test('labels are the standard names, with ANY for unknown', () {
      expect(
        Severity.values.map((severity) => severity.label),
        equals(['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'ANY']),
      );
    });

    test('fromName accepts the six names case-insensitively', () {
      expect(Severity.fromName('debug'), equals(Severity.debug));
      expect(Severity.fromName('Info'), equals(Severity.info));
      expect(Severity.fromName('WARN'), equals(Severity.warn));
      expect(Severity.fromName('error'), equals(Severity.error));
      expect(Severity.fromName('fatal'), equals(Severity.fatal));
      expect(Severity.fromName('unknown'), equals(Severity.unknown));
    });

    test('fromName rejects other names', () {
      expect(() => Severity.fromName('WARNING'), throwsArgumentError);
    });

    test('fromValue maps integers and rejects others', () {
      expect(Severity.fromValue(3), equals(Severity.error));
      expect(() => Severity.fromValue(6), throwsArgumentError);
    });
  });

  group('MemoryLogger', () {
    test('records every severity without level filtering', () {
      final logger = MemoryLogger()
        ..debug('d')
        ..info('i')
        ..warn('w');
      expect(
        logger.messages.map((record) => record.severity),
        equals([Severity.debug, Severity.info, Severity.warn]),
      );
      expect(logger.messages.last.message.text, equals('w'));
    });

    test('keeps the source location of each message', () {
      final cursor = Cursor('file.adoc', null, 'file.adoc', 3);
      final logger = MemoryLogger()..warn('located', at: cursor);
      expect(logger.messages.single.message.sourceLocation, same(cursor));
      expect(
        '${logger.messages.single.message}',
        equals('file.adoc: line 3: located'),
      );
    });

    test('maxSeverity is null when empty, else the highest severity', () {
      final logger = MemoryLogger();
      expect(logger.maxSeverity, isNull);
      logger
        ..error('e')
        ..info('i');
      expect(logger.maxSeverity, equals(Severity.error));
    });

    test('clear empties the records', () {
      final logger = MemoryLogger()..warn('w');
      expect(logger.isEmpty, isFalse);
      logger.clear();
      expect(logger.isEmpty, isTrue);
    });

    test('defaults to the WARN level', () {
      expect(MemoryLogger().level, equals(Severity.warn));
    });
  });

  group('NullLogger', () {
    test('discards output while tracking maxSeverity', () {
      final logger = NullLogger();
      expect(logger.maxSeverity, isNull);
      logger
        ..warn('w')
        ..info('i');
      expect(logger.maxSeverity, equals(Severity.warn));
    });

    test('defaults to the WARN level', () {
      expect(NullLogger().level, equals(Severity.warn));
    });
  });

  group('LogMessage', () {
    test('renders bare text without a location', () {
      expect('${const LogMessage('text')}', equals('text'));
    });

    test('renders the location before the text', () {
      final message = LogMessage(
        'text',
        sourceLocation: Cursor('a.adoc', null, 'a.adoc', 2),
      );
      expect('$message', equals('a.adoc: line 2: text'));
    });
  });

  group('logger option', () {
    test('load assigns the given logger', () {
      withManagerLogger(() {
        final memory = MemoryLogger();
        load('contents', options: AsciidoctorOptions(logger: memory));
        expect(LoggerManager.logger, same(memory));
      });
    });

    test('loadFile assigns the given logger', () {
      withManagerLogger(() {
        final memory = MemoryLogger();
        loadFile(
          'test/fixtures/basic.adoc',
          options: AsciidoctorOptions(logger: memory),
        );
        expect(LoggerManager.logger, same(memory));
      });
    });

    test('convert assigns the given logger', () {
      withManagerLogger(() {
        final memory = MemoryLogger();
        convert('contents', AsciidoctorOptions(logger: memory));
        expect(LoggerManager.logger, same(memory));
      });
    });

    test('convertFile assigns the given logger', () {
      withManagerLogger(() {
        final memory = MemoryLogger();
        convertFile(
          'test/fixtures/basic.adoc',
          AsciidoctorOptions(toFile: '/dev/null', logger: memory),
        );
        expect(LoggerManager.logger, same(memory));
      });
    });

    test('a NullLogger silences the conversion', () {
      withManagerLogger(() {
        convert(
          '. first\n\n3. third',
          AsciidoctorOptions(logger: NullLogger()),
        );
        expect(LoggerManager.logger, isA<NullLogger>());
      });
    });
  });

  group('conversion messages', () {
    test('writes messages prefixed with the program name and location', () {
      withManagerLogger(() {
        final sink = StringBuffer();
        LoggerManager.logger = Logger(sink: sink);
        convertStringToEmbedded(
          '2. second\n3. third',
          const AsciidoctorOptions(attributes: {'docfile': 'doc.adoc'}),
        );
        expect(
          sink.toString(),
          contains('asciidoctor: WARNING: <stdin>: line 1: list item index'),
        );
      });
    });
  });
}

/// A formatter rendering the severity and the message in upper case.
final class _UpperFormatter implements LoggerFormatter {
  const new();

  @override
  String call(
    Severity severity,
    DateTime time,
    String progname,
    LogMessage message,
  ) => '${severity.label} ${message.text.toUpperCase()}\n';
}
