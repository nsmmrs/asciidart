/// Port of `test/reader_test.rb`.
///
/// Tests that assert through `Document#parse`/`Document#convert` in Ruby are
/// rewritten to equivalent reader-level assertions (the parser and converter
/// waves own those paths); each such rewrite is marked `READER-LEVEL`.
/// Tests that cannot run at reader level are skipped with a reason instead
/// of being dropped.
///
/// The [FakeDocument] test double implements the temporary [ReaderDocument]
/// interface with a faithful mini-port of the `Substitutors` entry points
/// the reader calls; it is retired when `document.dart` lands.
library;

import 'dart:convert' show Encoding;
import 'dart:io' show Directory, File, FileSystemEntity, Platform, Process;

import 'package:asciidoctor/src/attribute_list.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/version.dart';
import 'package:test/test.dart';

const List<String> sampleData = ['first line', 'second line', 'third line'];

/// Repo root, found by searching upward for the directory that holds both
/// the Dart package and the Ruby `test/` tree (fixtures stay the single
/// oracle copy under `test/`).
final String repoRoot = _findRepoRoot();

String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/dart/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test/fixtures').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate repo root from ${dir.path}');
    }
    dir = parent;
  }
}

/// Repo `test/` dir.
final String repoTestDir = '$repoRoot/test';

/// Oracle fixtures shared with the Ruby suite.
final String fixtureDir = '$repoTestDir/fixtures';

/// A recorded log entry (severity plus message).
class LogRecord {
  LogRecord(this.severity, this.message);

  final LogSeverity severity;
  final Object? message;
}

/// In-memory logger for assertions. Mirrors `Asciidoctor::MemoryLogger`,
/// which records every message regardless of level.
class MemoryLogger implements ReaderLogger {
  final List<LogRecord> messages = [];

  bool get isEmpty => messages.isEmpty;
  bool get isNotEmpty => messages.isNotEmpty;

  void clear() => messages.clear();

  Object? _resolve(Object? message) =>
      message is Function ? message() : message;

  @override
  void info(Object? message) =>
      messages.add(LogRecord(LogSeverity.info, _resolve(message)));

  @override
  void warn(Object? message) =>
      messages.add(LogRecord(LogSeverity.warn, _resolve(message)));

  @override
  void error(Object? message) =>
      messages.add(LogRecord(LogSeverity.error, _resolve(message)));
}

/// Runs [body] with a [MemoryLogger] installed as the global logger.
/// [level] is accepted for parity with Ruby's helper and ignored, exactly
/// as `MemoryLogger` ignores it there.
T usingMemoryLogger<T>(
  T Function(MemoryLogger logger) body, [
  LogSeverity? level,
]) {
  final oldLogger = LoggerManager.logger;
  final memoryLogger = MemoryLogger();
  LoggerManager.logger = memoryLogger;
  try {
    return body(memoryLogger);
  } finally {
    LoggerManager.logger = oldLogger;
  }
}

/// Asserts the (`idx`th or only) recorded message. Mirrors
/// `assert_message`: a `~` prefix on [expectedMessage] asserts containment
/// instead of equality, and [contextual] requires a [LogMessage] with a
/// source location (Ruby's `Hash` kind).
void assertMessage(
  MemoryLogger logger,
  LogSeverity severity,
  String expectedMessage, {
  bool contextual = false,
  int? index,
}) {
  if (index == null) expect(logger.messages, hasLength(1));
  final record = logger.messages[index ?? 0];
  expect(record.severity, severity);
  final String actual;
  if (contextual) {
    expect(record.message, isA<LogMessage>());
    final message = record.message as LogMessage;
    expect(message.sourceLocation, isNotNull);
    actual = message.toString();
  } else {
    expect(record.message, isA<String>());
    actual = record.message as String;
  }
  if (expectedMessage.startsWith('~')) {
    expect(actual, contains(expectedMessage.substring(1)));
  } else {
    expect(actual, equals(expectedMessage));
  }
}

/// Asserts the full recorded message list. Mirrors `assert_messages`.
void assertMessages(
  MemoryLogger logger,
  List<(LogSeverity, String, bool)> expected,
) {
  expect(logger.messages, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    assertMessage(
      logger,
      expected[i].$1,
      expected[i].$2,
      contextual: expected[i].$3,
      index: i,
    );
  }
}

/// Intrinsic attributes available to every document. Copy of
/// `Asciidoctor::INTRINSIC_ATTRIBUTES` for [FakeDocument]; retired with it.
const Map<String, String> intrinsicAttributes = {
  'startsb': '[',
  'endsb': ']',
  'vbar': '|',
  'caret': '^',
  'asterisk': '*',
  'tilde': '~',
  'plus': '&#43;',
  'backslash': '\\',
  'backtick': '`',
  'blank': '',
  'empty': '',
  'sp': ' ',
  'two-colons': '::',
  'two-semicolons': ';;',
  'nbsp': '&#160;',
  'deg': '&#176;',
  'zwsp': '&#8203;',
  'quot': '&#34;',
  'apos': '&#39;',
  'lsquo': '&#8216;',
  'rsquo': '&#8217;',
  'ldquo': '&#8220;',
  'rdquo': '&#8221;',
  'wj': '&#8288;',
  'brvbar': '&#166;',
  'pp': '&#43;&#43;',
  'cpp': 'C&#43;&#43;',
  'cxx': 'C&#43;&#43;',
  'amp': '&',
  'lt': '<',
  'gt': '>',
};

/// Test double for the document surface [PreprocessorReader] consumes.
///
/// Implements [ReaderDocument] with the attribute defaults the reader tests
/// rely on (`attribute-missing`, `asciidoctor`, `asciidoctor-version`) plus
/// a faithful mini-port of the two `Substitutors` entry points the reader
/// calls ([subAttributes], [parseAttributes]). URI transport ([readUri])
/// mirrors `using_test_webserver`: the canned JSON resource plus every file
/// under the repo `test/` dir, with `null` for anything else (the 404 path).
/// Retired when `document.dart` lands.
class FakeDocument implements ReaderDocument {
  FakeDocument({
    Map<String, Object?>? attributes,
    this.safe = SafeMode.secure,
    String? baseDir,
    this.sourcemap = false,
    this.includeProcessors,
  }) : attributes = {
         'attribute-missing': 'skip',
         'attribute-undefined': 'drop-line',
         'asciidoctor': '',
         'asciidoctor-version': Asciidoctor.version,
         ...?attributes,
       },
       baseDir = baseDir ?? Directory.current.path;

  @override
  final Map<String, Object?> attributes;

  @override
  final int safe;

  @override
  final String baseDir;

  @override
  final bool sourcemap;

  @override
  final List<ReaderIncludeProcessor>? includeProcessors;

  @override
  final Map<String, bool?> catalogIncludes = {};

  @override
  final PathResolver pathResolver = PathResolver();

  @override
  Object? attr(String name) => attributes[name];

  @override
  bool attrSet(String name) => attributes.containsKey(name);

  @override
  String normalizeSystemPath(
    String target,
    String? start, {
    String? targetName,
  }) {
    String? startPath = start;
    String? jail;
    if (safe < SafeMode.safe) {
      if (startPath != null) {
        if (!pathResolver.isRoot(startPath)) {
          startPath = '$baseDir/$startPath';
        }
      } else {
        startPath = baseDir;
      }
    } else {
      startPath ??= baseDir;
      jail = baseDir;
    }
    return pathResolver.systemPath(
      target,
      start: startPath,
      jail: jail,
      targetName: targetName ?? 'path',
    );
  }

  /// Attribute reference pattern. Port of `AttributeReferenceRx` for the
  /// reference forms the reader tests exercise (plain, escaped); `set` and
  /// `counter` forms parse but are unsupported (see [subAttributes]).
  /// Groups: 1 = leading escape, 2 = name, 3 = set/counter marker,
  /// 4 = trailing escape.
  static final RegExp attrRefRx = RegExp(
    r'(\\)?\{([\p{Alpha}\p{M}\p{Nd}\p{Pc}\u200C\u200D][\p{Alpha}\p{M}\p{Nd}\p{Pc}\u200C\u200D-]*|(set|counter2?):.+?)(\\)?\}',
    unicode: true,
  );

  static const String _can = '\u0018';
  static const String _del = '\u007f';

  /// Faithful mini-port of `Substitutors#sub_attributes` covering the
  /// reference forms and `attribute-missing` modes the reader tests use.
  /// `set`/`counter` references are unsupported (no reader test uses them;
  /// the `substitutors.dart` wave provides the real implementation).
  @override
  String subAttributes(
    String text, {
    String? attributeMissing,
    String dropLineSeverity = 'info',
  }) {
    String? attrMissing;
    var drop = false;
    var dropLine = false;
    var dropEmptyLine = false;
    final result = text.replaceAllMapped(attrRefRx, (match) {
      // escaped attribute, return unescaped
      if (match.group(1) == '\\' || match.group(4) == '\\') {
        return '{${match.group(2)}}';
      }
      if (match.group(3) != null) {
        throw UnimplementedError(
          'set/counter attribute references are not supported by FakeDocument',
        );
      }
      final key = match.group(2)!.toLowerCase();
      if (attributes.containsKey(key)) {
        // NOTE Ruby stringifies gsub block results ('1', 'false').
        return '${attributes[key]}';
      }
      final intrinsic = intrinsicAttributes[key];
      if (intrinsic != null) return intrinsic;
      attrMissing ??= _missingMode(attributeMissing);
      switch (attrMissing) {
        case 'drop':
          drop = dropEmptyLine = true;
          return _del;
        case 'drop-line':
          if (dropLineSeverity == 'info') {
            LoggerManager.logger.info(
              'dropping line containing reference to missing attribute: $key',
            );
          }
          drop = dropLine = true;
          return _can;
        case 'warn':
          LoggerManager.logger.warn(
            'skipping reference to missing attribute: $key',
          );
          return match.group(0)!;
        default: // 'skip'
          return match.group(0)!;
      }
    });

    if (!drop) return result;
    if (dropEmptyLine) {
      // NOTE squeeze runs of DEL first, as Ruby does.
      final squeezed = result.replaceAll(RegExp('$_del+'), _del);
      final lines = squeezed.split('\n');
      if (dropLine) {
        return lines
            .where(
              (line) =>
                  line != _del &&
                  line != _can &&
                  !line.startsWith(_can) &&
                  !line.contains(_can),
            )
            .join('\n')
            .replaceAll(_del, '');
      } else {
        return lines
            .where((line) => line != _del)
            .join('\n')
            .replaceAll(_del, '');
      }
    } else if (result.contains('\n')) {
      return result
          .split('\n')
          .where(
            (line) =>
                line != _can && !line.startsWith(_can) && !line.contains(_can),
          )
          .join('\n');
    } else {
      return '';
    }
  }

  String _missingMode(String? override) {
    if (override != null) return override;
    final configured = attributes['attribute-missing'];
    if (configured == null || configured == false) {
      return complianceAttributeMissing;
    }
    return configured.toString();
  }

  @override
  Map<Object, String?> parseAttributes(
    String? attrlist, {
    bool subInput = false,
  }) {
    if (attrlist == null || attrlist.isEmpty) return {};
    var text = attrlist;
    if (subInput && text.contains('{')) text = subAttributes(text);
    // NOTE no subs block: Ruby passes block=nil here (sub_result unset).
    return AttributeList(text).parse([]);
  }

  @override
  String? readUri(Uri uri, Encoding encoding) {
    // Mirrors using_test_webserver: canned JSON plus every file under the
    // repo test dir; anything else is the 404 path (null).
    if (uri.path == '/name/asciidoctor') return '{"name": "asciidoctor"}\n';
    final file = File('$repoTestDir${uri.path}');
    if (!file.existsSync() || FileSystemEntity.isDirectorySync(file.path)) {
      return null;
    }
    try {
      return encoding.decode(file.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }
}

/// Whether the current user is root (via `id -u`); best effort, `false`
/// when the check itself fails.
bool _isRoot() {
  try {
    return Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
  } catch (_) {
    return false;
  }
}

/// Formats [mode] (as from [FileSystemEntity.statSync]) for `chmod`.
String _modeString(int mode) => (mode & 0xfff).toRadixString(8);

/// Builds a [PreprocessorReader] over [input] with a [FakeDocument], mirroring
/// `Document.new input, ...` at reader level (unparsed).
PreprocessorReader preprocessorReader(
  Object? input, {
  Map<String, Object?>? attributes,
  int safe = SafeMode.secure,
  String? baseDir,
  Object? cursor,
  bool sourcemap = false,
}) {
  final doc = FakeDocument(
    attributes: attributes,
    safe: safe,
    baseDir: baseDir,
    sourcemap: sourcemap,
  );
  return PreprocessorReader(doc, input, cursor, true);
}

/// Reads all lines for [input] in safe mode against the fixtures dir.
List<String?> _includeLines(String input) {
  final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
  return PreprocessorReader(doc, input, null, true).readLines();
}

/// Expanded lines between the block delimiters of a delimited [input]
/// (the `----`/`++++` lines the parser would consume).
List<String?> _delimitedLines(String input) {
  final lines = _includeLines(input);
  return lines.sublist(1, lines.length - 1);
}

/// Expanded lines between the `----` delimiters of a listing-block [input].
List<String?> _listingLines(String input) => _delimitedLines(input);

/// Reads all lines from a [PreprocessorReader] over [input], mirroring the
/// `while reader.has_more_lines?` loops in the Ruby tests.
List<String?> readAll(
  Object? input, {
  Map<String, Object?>? attributes,
  int safe = SafeMode.secure,
  String? baseDir,
  Object? cursor,
  bool sourcemap = false,
}) {
  final reader = preprocessorReader(
    input,
    attributes: attributes,
    safe: safe,
    baseDir: baseDir,
    cursor: cursor,
    sourcemap: sourcemap,
  );
  final lines = <String?>[];
  while (reader.hasMoreLines()) {
    lines.add(reader.readLine());
  }
  return lines;
}

void main() {
  group('Reader', () {
    group('Prepare lines', () {
      test('should prepare lines from Array data', () {
        final reader = Reader(sampleData);
        expect(reader.lines, equals(sampleData));
      });

      test('should prepare lines from String data', () {
        final reader = Reader(sampleData.join('\n'));
        expect(reader.lines, equals(sampleData));
      });

      test('should prepare lines from String data with trailing newline', () {
        final reader = Reader('${sampleData.join('\n')}\n');
        expect(reader.lines, equals(sampleData));
      });

      test('should remove UTF-8 BOM from first line of String data', () {
        // NOTE Dart strings have no encoding; only BOM removal is portable.
        final data = '\uFEFF${sampleData.join('\n')}';
        final reader = Reader(data, null, true);
        expect(reader.lines[0]![0], equals('f'));
        expect(reader.lines, equals(sampleData));
      });

      test('should remove UTF-8 BOM from first line of Array data', () {
        final data = [...sampleData];
        data[0] = '\uFEFF${data[0]}';
        final reader = Reader(data, null, true);
        expect(reader.lines[0]![0], equals('f'));
        expect(reader.lines, equals(sampleData));
      });

      test(
        'should encode UTF-16LE string to UTF-8 when BOM is found',
        skip:
            'Ruby encoding coercion has no Dart equivalent (strings are '
            'always Unicode)',
        () {},
      );

      test(
        'should encode UTF-16LE string array to UTF-8 when BOM is found',
        skip:
            'Ruby encoding coercion has no Dart equivalent (strings are '
            'always Unicode)',
        () {},
      );

      test(
        'should encode UTF-16BE string to UTF-8 when BOM is found',
        skip:
            'Ruby encoding coercion has no Dart equivalent (strings are '
            'always Unicode)',
        () {},
      );

      test(
        'should encode UTF-16BE string array to UTF-8 when BOM is found',
        skip:
            'Ruby encoding coercion has no Dart equivalent (strings are '
            'always Unicode)',
        () {},
      );
    });

    group('With empty data', () {
      test('hasMoreLines should return false with empty data', () {
        expect(Reader().hasMoreLines(), isFalse);
      });

      test('isEmpty should return true with empty data', () {
        expect(Reader().isEmpty, isTrue);
        expect(Reader().isEof, isTrue);
      });

      test('isNextLineEmpty should return true with empty data', () {
        expect(Reader().isNextLineEmpty(), isTrue);
      });

      test('peekLine should return null with empty data', () {
        expect(Reader().peekLine(), isNull);
      });

      test('peekLines should return empty Array with empty data', () {
        expect(Reader().peekLines(1), isEmpty);
      });

      test('readLine should return null with empty data', () {
        expect(Reader().readLine(), isNull);
      });

      test('readLines should return empty Array with empty data', () {
        expect(Reader().readLines(), isEmpty);
      });
    });

    group('With data', () {
      test('hasMoreLines should return true if there are lines remaining', () {
        final reader = Reader(sampleData);
        expect(reader.hasMoreLines(), isTrue);
      });

      test('isEmpty should return false if there are lines remaining', () {
        final reader = Reader(sampleData);
        expect(reader.isEmpty, isFalse);
        expect(reader.isEof, isFalse);
      });

      test('isNextLineEmpty should return false if next line is not blank', () {
        final reader = Reader(sampleData);
        expect(reader.isNextLineEmpty(), isFalse);
      });

      test('isNextLineEmpty should return true if next line is blank', () {
        final reader = Reader(['', 'second line']);
        expect(reader.isNextLineEmpty(), isTrue);
      });

      test('peekLine should return null if next entry is null', () {
        expect(Reader(<String?>[null]).peekLine(), isNull);
      });

      test('peekLine should return next line if there are lines remaining', () {
        final reader = Reader(sampleData);
        expect(reader.peekLine(), equals(sampleData.first));
      });

      test('peekLine should not consume line or increment line number', () {
        final reader = Reader(sampleData);
        expect(reader.peekLine(), equals(sampleData.first));
        expect(reader.peekLine(), equals(sampleData.first));
        expect(reader.lineno, equals(1));
      });

      test(
        'peekLines should return next lines if there are lines remaining',
        () {
          final reader = Reader(sampleData);
          expect(reader.peekLines(2), equals(sampleData.sublist(0, 2)));
        },
      );

      test('peekLines should not consume lines or increment line number', () {
        final reader = Reader(sampleData);
        expect(reader.peekLines(2), equals(sampleData.sublist(0, 2)));
        expect(reader.peekLines(2), equals(sampleData.sublist(0, 2)));
        expect(reader.lineno, equals(1));
      });

      test(
        'peekLines should not increment line number if reader overruns buffer',
        () {
          final reader = Reader(sampleData);
          expect(reader.peekLines(sampleData.length * 2), equals(sampleData));
          expect(reader.lineno, equals(1));
        },
      );

      test('peekLines should peek all lines if no arguments are given', () {
        final reader = Reader(sampleData);
        expect(reader.peekLines(), equals(sampleData));
        expect(reader.lineno, equals(1));
      });

      test('peekLines should not invert order of lines', () {
        final reader = Reader(sampleData);
        expect(reader.lines, equals(sampleData));
        reader.peekLines(3);
        expect(reader.lines, equals(sampleData));
      });

      test('readLine should return next line if there are lines remaining', () {
        final reader = Reader(sampleData);
        expect(reader.readLine(), equals(sampleData.first));
      });

      test('readLine should consume next line and increment line number', () {
        final reader = Reader(sampleData);
        expect(reader.readLine(), equals(sampleData[0]));
        expect(reader.readLine(), equals(sampleData[1]));
        expect(reader.lineno, equals(3));
      });

      test('advance should consume next line and return a Boolean indicating if a line was consumed', () {
        final reader = Reader(sampleData);
        expect(reader.advance(), isTrue);
        expect(reader.advance(), isTrue);
        expect(reader.advance(), isTrue);
        expect(reader.advance(), isFalse);
      });

      test('readLines should return all lines', () {
        final reader = Reader(sampleData);
        expect(reader.readLines(), equals(sampleData));
      });

      test('read should return all lines joined as String', () {
        final reader = Reader(sampleData);
        expect(reader.read(), equals(sampleData.join('\n')));
      });

      test('hasMoreLines should return false after readLines is invoked', () {
        final reader = Reader(sampleData);
        reader.readLines();
        expect(reader.hasMoreLines(), isFalse);
      });

      test('unshift puts line onto Reader as next line to read', () {
        final reader = Reader(sampleData, null, true);
        reader.unshift('line zero');
        expect(reader.peekLine(), equals('line zero'));
        expect(reader.readLine(), equals('line zero'));
        expect(reader.lineno, equals(1));
      });

      test('terminate should consume all lines and update line number', () {
        final reader = Reader(sampleData);
        reader.terminate();
        expect(reader.isEof, isTrue);
        expect(reader.lineno, equals(4));
      });

      test('skipBlankLines should skip blank lines', () {
        final reader = Reader(['', '', ...sampleData]);
        reader.skipBlankLines();
        expect(reader.peekLine(), equals(sampleData.first));
      });

      test('lines should return remaining lines', () {
        final reader = Reader(sampleData);
        reader.readLine();
        expect(reader.lines, equals(sampleData.sublist(1)));
      });

      test('sourceLines should return copy of original data Array', () {
        final reader = Reader(sampleData);
        reader.readLines();
        expect(reader.sourceLines, equals(sampleData));
      });

      test('source should return original data Array joined as String', () {
        final reader = Reader(sampleData);
        reader.readLines();
        expect(reader.source, equals(sampleData.join('\n')));
      });
    });

    group('Line context', () {
      test('cursor.toString should return file name and line number of current line', () {
        final reader = Reader(sampleData, 'sample.adoc');
        reader.readLine();
        expect(reader.cursor().toString(), equals('sample.adoc: line 2'));
      });

      test(
        'lineInfo should return file name and line number of current line',
        () {
          final reader = Reader(sampleData, 'sample.adoc');
          reader.readLine();
          expect(reader.lineInfo, equals('sample.adoc: line 2'));
        },
      );

      test('cursorAtPrevLine should return file name and line number of previous line read', () {
        final reader = Reader(sampleData, 'sample.adoc');
        reader.readLine();
        expect(
          reader.cursorAtPrevLine().toString(),
          equals('sample.adoc: line 1'),
        );
      });

      // NOTE the following save/restore/mark tests have no Ruby counterpart
      // in reader_test.rb; they pin ported behavior the parser wave calls.
      test('mark and cursorAtMark track the marked position', () {
        final reader = Reader(['a', 'b', 'c', 'd']);
        reader.readLine();
        expect(reader.mark(), isTrue);
        expect(reader.cursorAtMark().toString(), equals('<stdin>: line 2'));
        expect(reader.cursorBeforeMark().toString(), equals('<stdin>: line 1'));
        reader.readLine();
        expect(reader.cursorAtMark().toString(), equals('<stdin>: line 2'));
      });

      test('save and restoreSave round-trip reader state', () {
        final reader = Reader(['a', 'b', 'c', 'd']);
        reader.readLine();
        reader.mark();
        reader.save();
        expect(reader.readLine(), equals('b'));
        reader.restoreSave();
        expect(reader.readLine(), equals('b'));
        expect(reader.lineno, equals(3));
        expect(reader.cursorAtMark().toString(), equals('<stdin>: line 2'));
        // restoreSave is a no-op once the saved state is consumed
        reader.restoreSave();
        expect(reader.readLine(), equals('c'));
        // discardSave drops the saved state
        reader.save();
        reader.readLine();
        reader.discardSave();
        reader.restoreSave();
        expect(reader.readLine(), isNull);
      });
    });

    group('Read lines until', () {
      test('Read lines until until end', () {
        final lines = [
          'This is one paragraph.\n',
          '\n',
          'This is another paragraph.\n',
        ];

        final reader = Reader(lines, null, true);
        final result = reader.readLinesUntil();
        expect(result, hasLength(3));
        expect(result, equals(lines.map((line) => line.chomp()).toList()));
        expect(reader.hasMoreLines(), isFalse);
        expect(reader.isEof, isTrue);
      });

      test('Read lines until until blank line', () {
        final lines = [
          'This is one paragraph.\n',
          '\n',
          'This is another paragraph.\n',
        ];

        final reader = Reader(lines, null, true);
        final result = reader.readLinesUntil(breakOnBlankLines: true);
        expect(result, hasLength(1));
        expect(result.first, equals(lines.first.chomp()));
        expect(reader.peekLine(), equals(lines.last.chomp()));
      });

      test('Read lines until until blank line preserving last line', () {
        final lines = [
          'This is one paragraph.',
          '',
          'This is another paragraph.',
        ];

        final reader = Reader(lines);
        final result = reader.readLinesUntil(
          breakOnBlankLines: true,
          preserveLastLine: true,
        );
        expect(result, hasLength(1));
        expect(result.first, equals(lines.first.chomp()));
        expect(reader.isNextLineEmpty(), isTrue);
      });

      test('Read lines until until condition is true', () {
        final lines = [
          '--',
          'This is one paragraph inside the block.',
          '',
          'This is another paragraph inside the block.',
          '--',
          '',
          'This is a paragraph outside the block.',
        ];

        final reader = Reader(lines);
        reader.readLine();
        final result = reader.readLinesUntil(test: (line) => line == '--');
        expect(result, hasLength(3));
        expect(result, equals(lines.sublist(1, 4)));
        expect(reader.isNextLineEmpty(), isTrue);
      });

      test('Read lines until until condition is true, taking last line', () {
        final lines = [
          '--',
          'This is one paragraph inside the block.',
          '',
          'This is another paragraph inside the block.',
          '--',
          '',
          'This is a paragraph outside the block.',
        ];

        final reader = Reader(lines);
        reader.readLine();
        final result = reader.readLinesUntil(
          readLastLine: true,
          test: (line) => line == '--',
        );
        expect(result, hasLength(4));
        expect(result, equals(lines.sublist(1, 5)));
        expect(reader.isNextLineEmpty(), isTrue);
      });

      test('Read lines until until condition is true, taking and preserving last line', () {
        final lines = [
          '--',
          'This is one paragraph inside the block.',
          '',
          'This is another paragraph inside the block.',
          '--',
          '',
          'This is a paragraph outside the block.',
        ];

        final reader = Reader(lines);
        reader.readLine();
        final result = reader.readLinesUntil(
          readLastLine: true,
          preserveLastLine: true,
          test: (line) => line == '--',
        );
        expect(result, hasLength(4));
        expect(result, equals(lines.sublist(1, 5)));
        expect(reader.peekLine(), equals('--'));
      });

      test('read lines until terminator', () {
        final lines = [
          '****\n',
          'captured\n',
          '\n',
          'also captured\n',
          '****\n',
          '\n',
          'not captured\n',
        ];

        const expected = ['captured', '', 'also captured'];

        final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
        final reader = PreprocessorReader(doc, lines, null, true);
        final terminator = reader.readLine();
        final result = reader.readLinesUntil(
          terminator: terminator,
          skipProcessing: true,
        );
        expect(result, equals(expected));
        expect(reader.unterminated, isFalse);
      });

      test('should flag reader as unterminated if reader reaches end of source without finding terminator', () {
        final lines = [
          '****\n',
          'captured\n',
          '\n',
          'also captured\n',
          '\n',
          'captured yet again\n',
        ];

        final expected = lines.sublist(1).map((line) => line.chomp()).toList();

        usingMemoryLogger((logger) {
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, lines, null, true);
          final terminator = reader.peekLine();
          final result = reader.readLinesUntil(
            terminator: terminator,
            skipFirstLine: true,
            skipProcessing: true,
          );
          expect(result, equals(expected));
          expect(reader.unterminated, isTrue);
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: unterminated **** block',
            contextual: true,
          );
        });
      });
    });
  });

  group('PreprocessorReader', () {
    group('Type hierarchy', () {
      test('PreprocessorReader should extend from Reader', () {
        final reader = preprocessorReader([]);
        expect(reader, isA<Reader>());
      });

      test(
        'PreprocessorReader should invoke or emulate Reader initializer',
        () {
          final reader = preprocessorReader([...sampleData]);
          expect(reader.lines, equals(sampleData));
          expect(reader.lineno, equals(1));
        },
      );
    });

    group('Prepare lines', () {
      test('should prepare and normalize lines from Array data', () {
        final data = ['', ...sampleData, ''];
        final reader = preprocessorReader(data);
        expect(reader.lines, equals(['', ...sampleData]));
      });

      test('should prepare and normalize lines from String data', () {
        final data = [' ', ...sampleData, ' '];
        final reader = preprocessorReader(data.join('\n'));
        expect(reader.lines, equals(['', ...sampleData]));
      });

      test('should drop all lines if all lines are empty', () {
        final reader = preprocessorReader(['', ' ', '', ' ']);
        expect(reader.lines, isEmpty);
      });

      test('should clean CRLF from end of lines', () {
        const input = 'source\r\nwith\r\nCRLF\r\nline endings\r\n';
        final variants = <Object>[
          input,
          ['source\r\n', 'with\r\n', 'CRLF\r\n', 'line endings\r\n'],
          input.split('\n'),
          input.split('\n').join('\n'),
        ];
        for (final lines in variants) {
          final reader = preprocessorReader(lines);
          for (final line in reader.lines) {
            expect(line, isNot(endsWith('\r')));
            expect(line, isNot(endsWith('\r\n')));
            expect(line, isNot(endsWith('\n')));
          }
        }
      });

      test('should not skip front matter by default', () {
        const input =
            '---\n'
            'layout: post\n'
            'title: Document Title\n'
            'author: username\n'
            'tags: [ first, second ]\n'
            '---\n'
            '= Document Title\n'
            'Author Name\n'
            '\n'
            'preamble\n';

        final doc = FakeDocument();
        final reader = PreprocessorReader(doc, input, null, true);
        expect(doc.attributes.containsKey('front-matter'), isFalse);
        expect(reader.peekLine(), equals('---'));
        expect(reader.lineno, equals(1));
      });

      test('should not skip front matter if ending delimiter is not found', () {
        const input =
            '---\n'
            'title: Document Title\n'
            'tags: [ first, second ]\n'
            '= Document Title\n'
            'Author Name\n'
            '\n'
            'preamble\n';

        final doc = FakeDocument(attributes: {'skip-front-matter': ''});
        final reader = PreprocessorReader(doc, input, null, true);
        expect(reader.peekLine(), equals('---'));
        expect(doc.attributes.containsKey('front-matter'), isFalse);
        expect(reader.lineno, equals(1));
      });

      test(
        'should skip front matter if specified by skip-front-matter attribute',
        () {
          const frontMatter =
              'layout: post\n'
              'title: Document Title\n'
              'author: username\n'
              'tags: [ first, second ]';

          const input =
              '---\n'
              '$frontMatter\n'
              '---\n'
              '= Document Title\n'
              'Author Name\n'
              '\n'
              'preamble\n';

          final doc = FakeDocument(attributes: {'skip-front-matter': ''});
          final reader = PreprocessorReader(doc, input, null, true);
          expect(reader.peekLine(), equals('= Document Title'));
          expect(doc.attributes['front-matter'], equals(frontMatter));
          expect(reader.lineno, equals(7));
        },
      );

      test('should skip TOML front matter if specified by skip-front-matter attribute', () {
        const frontMatter =
            "layout = 'post'\n"
            "title = 'Document Title'\n"
            "author = 'username'\n"
            "tags = ['first', 'second']";

        const input =
            '+++\n'
            '$frontMatter\n'
            '+++\n'
            '= Document Title\n'
            'Author Name\n'
            '\n'
            'preamble\n';

        final doc = FakeDocument(attributes: {'skip-front-matter': ''});
        final reader = PreprocessorReader(doc, input, null, true);
        expect(reader.peekLine(), equals('= Document Title'));
        expect(doc.attributes['front-matter'], equals(frontMatter));
        expect(reader.lineno, equals(7));
      });

      test('should not skip front matter in include file if skip-front-matter attribute is set', () {
        const input =
            '....\n'
            'include::fixtures/with-front-matter.adoc[]\n'
            '....\n';
        final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
        final reader = PreprocessorReader(doc, input, null, true);
        const expected = [
          '....',
          '---',
          'name: value',
          '---',
          'content',
          '....',
        ];
        expect(reader.readlines(), equals(expected));
        expect(doc.attrSet('front-matter'), isFalse);
      });

      test('should skip front matter in include file if skip-front-matter option is set on include directiv', () {
        const input =
            '....\n'
            'include::fixtures/with-front-matter.adoc[opts=skip-front-matter]\n'
            '....\n';
        final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
        final reader = PreprocessorReader(doc, input, null, true);
        const expected = ['....', 'content', '....'];
        expect(reader.readlines(), equals(expected));
        expect(doc.attrSet('front-matter'), isFalse);
      });
    });

    group('Include Stack', () {
      test('PreprocessorReader#push_include method should return reader', () {
        final reader = preprocessorReader([]);
        final result = reader.pushInclude(
          ['one', 'two', 'three'],
          '<stdin>',
          '<stdin>',
        );
        expect(result, same(reader));
      });

      test('PreprocessorReader#push_include method should put lines on top of stack', () {
        final reader = preprocessorReader(['a', 'b', 'c']);
        reader.pushInclude(['one', 'two', 'three'], '', '<stdin>');
        expect(reader.includeStack, hasLength(1));
        expect(reader.readLine()!.rstrip(), equals('one'));
      });

      test('PreprocessorReader#push_include method should gracefully handle file and path', () {
        final reader = preprocessorReader(['a', 'b', 'c']);
        reader.pushInclude(['one', 'two', 'three']);
        expect(reader.includeStack, hasLength(1));
        expect(reader.readLine()!.rstrip(), equals('one'));
        expect(reader.file, isNull);
        expect(reader.path, equals('<stdin>'));
      });

      test('PreprocessorReader#push_include method should set path from file automatically if not specified', () {
        final doc = FakeDocument();
        final reader = PreprocessorReader(doc, ['a', 'b', 'c'], null, true);
        reader.pushInclude(['one', 'two', 'three'], '/tmp/lines.adoc');
        expect(reader.file, equals('/tmp/lines.adoc'));
        expect(reader.path, equals('lines.adoc'));
        expect(doc.catalogIncludes['lines'], isTrue);
      });

      test('PreprocessorReader#push_include method should accept file as a URI and compute dir and path', () {
        final fileUri = Uri.parse('http://example.com/docs/file.adoc');
        final dirUri = Uri.parse('http://example.com/docs');
        final reader = preprocessorReader([]);
        reader.pushInclude(['one', 'two', 'three'], fileUri);
        expect(reader.file, same(fileUri));
        expect(reader.dir, equals(dirUri));
        expect(reader.path, equals('file.adoc'));
      });

      test('PreprocessorReader#push_include method should accept file as a top-level URI and compute dir and path', () {
        final fileUri = Uri.parse('http://example.com/index.adoc');
        final dirUri = Uri.parse('http://example.com');
        final reader = preprocessorReader([]);
        reader.pushInclude(['one', 'two', 'three'], fileUri);
        expect(reader.file, same(fileUri));
        expect(reader.dir, equals(dirUri));
        expect(reader.path, equals('index.adoc'));
      });

      test('PreprocessorReader#push_include method should not fail if data is null', () {
        final reader = preprocessorReader(['a', 'b', 'c']);
        reader.pushInclude(null, '', '<stdin>');
        expect(reader.includeStack, isEmpty);
        expect(reader.readLine()!.rstrip(), equals('a'));
      });

      test('PreprocessorReader#push_include method should ignore dot in directory name when computing include path', () {
        final doc = FakeDocument();
        final reader = PreprocessorReader(doc, ['a', 'b', 'c'], null, true);
        reader.pushInclude(['one', 'two', 'three'], null, 'include.d/data');
        expect(reader.file, isNull);
        expect(reader.path, equals('include.d/data'));
        expect(doc.catalogIncludes['include.d/data'], isTrue);
      });
    });

    group('Include Directive', () {
      test(
        'should replace include directive with link macro in default safe mode',
        () {
          const input = 'include::include-file.adoc[]';
          final reader = preprocessorReader(input);
          expect(
            reader.readLine(),
            equals('link:include-file.adoc[role=include]'),
          );
        },
      );

      test('should not add role to link macro used to replace include directive in compat mode', () {
        const input = 'include::include-file.adoc[]';
        final reader = preprocessorReader(
          input,
          attributes: {'compat-mode': ''},
        );
        expect(reader.readLine(), equals('link:include-file.adoc[]'));
      });

      test('should escape spaces in target when generating link from include directive', () {
        const input = 'include::foo bar baz.adoc[]';
        final reader = preprocessorReader(input);
        expect(
          reader.readLine(),
          equals('link:pass:c[foo bar baz.adoc][role=include]'),
        );
      });

      test('should preserve attrlist when replacing include directive with link macro', () {
        const input = 'include::include-file.adoc[leveloffset=+1]';
        final reader = preprocessorReader(input);
        expect(
          reader.readLine(),
          equals('link:include-file.adoc[role=include,leveloffset=+1]'),
        );
      });

      test('should replace include directive with link macro if safe mode allows it, but allow-uri-read is not set', () {
        usingMemoryLogger((logger) {
          const input = 'include::https://example.org/dist/info.adoc[]';
          final reader = preprocessorReader(input, safe: SafeMode.safe);
          expect(
            reader.readLine(),
            equals('link:https://example.org/dist/info.adoc[role=include]'),
          );
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: cannot include contents of URI: https://example.org/dist/info.adoc (allow-uri-read attribute not enabled)',
            contextual: true,
          );
        });
      });

      test('should not add role to link macro that replaces include directive with remote target in compat mode', () {
        const input = 'include::https://example.org/dist/info.adoc[]';
        usingMemoryLogger((logger) {
          final reader = preprocessorReader(
            input,
            safe: SafeMode.safe,
            attributes: {'compat-mode': ''},
          );
          expect(
            reader.readLine(),
            equals('link:https://example.org/dist/info.adoc[]'),
          );
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: cannot include contents of URI: https://example.org/dist/info.adoc (allow-uri-read attribute not enabled)',
            contextual: true,
          );
        });
      });

      test('should escape spaces in target when generating link from remote include directive', () {
        usingMemoryLogger((logger) {
          const input = 'include::https://example.org/no such file.adoc[]';
          final reader = preprocessorReader(input, safe: SafeMode.safe);
          expect(
            reader.readLine(),
            equals(
              'link:pass:c[https://example.org/no such file.adoc][role=include]',
            ),
          );
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: cannot include contents of URI: https://example.org/no such file.adoc (allow-uri-read attribute not enabled)',
            contextual: true,
          );
        });
      });

      test('should preserve attrlist when replacing remove include directive with link macro', () {
        usingMemoryLogger((logger) {
          const input =
              'include::https://example.org/dist/info.adoc[leveloffset=+1]';
          final reader = preprocessorReader(input, safe: SafeMode.safe);
          expect(
            reader.readLine(),
            equals(
              'link:https://example.org/dist/info.adoc[role=include,leveloffset=+1]',
            ),
          );
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: cannot include contents of URI: https://example.org/dist/info.adoc (allow-uri-read attribute not enabled)',
            contextual: true,
          );
        });
      });

      test('include directive with remote target is converted to a link when allow-uri-read is not set', () {
        usingMemoryLogger((logger) {
          const input = 'include::http://example.org/team.adoc[]';
          final reader = preprocessorReader(input, safe: SafeMode.safe);
          expect(
            reader.readLine(),
            equals('link:http://example.org/team.adoc[role=include]'),
          );
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: cannot include contents of URI: http://example.org/team.adoc (allow-uri-read attribute not enabled)',
            contextual: true,
          );
        });
      });

      test('include directive with remote target is converted to a link when safe mode is secure', () {
        usingMemoryLogger((logger) {
          const input = 'include::http://example.org/team.adoc[]';
          final reader = preprocessorReader(input, safe: SafeMode.secure);
          expect(
            reader.readLine(),
            equals('link:http://example.org/team.adoc[role=include]'),
          );
          expect(logger.messages, isEmpty);
        });
      });

      test(
        'include directive is enabled when safe mode is less than SECURE',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input = 'include::fixtures/include-file.adoc[]';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          final lines = reader.readLines();
          expect(
            lines.any(
              (line) => line != null && line.contains('included content'),
            ),
            isTrue,
          );
          expect(doc.catalogIncludes['fixtures/include-file'], isTrue);
        },
      );

      test(
        'should strip BOM from include file',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              ':showtitle:\ninclude::fixtures/file-with-utf8-bom.adoc[]';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          expect(reader.readLines(), equals([':showtitle:', '= 人']));
        },
      );

      test(
        'should include content from a file on the classloader',
        skip: 'JRuby-only (classloader: URI)',
        () {},
      );

      test(
        'should not track include in catalog for non-AsciiDoc include files',
        // READER-LEVEL: catalog assertion only (no parsing).
        () {
          const input = '----\ninclude::fixtures/circle.svg[]\n----\n';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          reader.readLines();
          expect(doc.catalogIncludes, isEmpty);
        },
      );

      test(
        'include directive should resolve file with spaces in name',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input = 'include::fixtures/include file.adoc[]';
          final includeFile = '$fixtureDir/include-file.adoc';
          final includeFileWithSp = '$fixtureDir/include file.adoc';
          File(includeFile).copySync(includeFileWithSp);
          try {
            final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
            final reader = PreprocessorReader(doc, input, null, true);
            final source = reader.readLines().join('\n');
            expect(source, contains('included content'));
          } finally {
            File(includeFileWithSp).deleteSync();
          }
        },
      );

      test(
        'include directive should resolve file with {sp} in name',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input = 'include::fixtures/include{sp}file.adoc[]';
          final includeFile = '$fixtureDir/include-file.adoc';
          final includeFileWithSp = '$fixtureDir/include file.adoc';
          File(includeFile).copySync(includeFileWithSp);
          try {
            final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
            final reader = PreprocessorReader(doc, input, null, true);
            final source = reader.readLines().join('\n');
            expect(source, contains('included content'));
          } finally {
            File(includeFileWithSp).deleteSync();
          }
        },
      );

      test('include directive should not match if target is empty or starts or ends with space', () {
        const inputs = [
          'include::[]',
          'include:: []',
          'include:: not-include[]',
          'include::not-include []',
        ];
        for (final input in inputs) {
          final reader = preprocessorReader(input);
          expect(reader.readLine(), equals(input));
        }
      });

      test(
        'include directive should not attempt to resolve target as remote if allow-uri-read is set and URL is not on first line',
        // READER-LEVEL: the `target` attribute is preset (attribute-entry
        // parsing belongs to the document wave); line shape and log
        // message are unchanged.
        () {
          usingMemoryLogger((logger) {
            const input =
                ':target: not-a-file.adoc + \\\n'
                'http://example.org/team.adoc\n'
                '\n'
                'include::{target}[]\n';
            final doc = FakeDocument(
              safe: SafeMode.safe,
              baseDir: fixtureDir,
              attributes: {
                'allow-uri-read': '',
                'target': 'not-a-file.adoc +\nhttp://example.org/team.adoc',
              },
            );
            final reader = PreprocessorReader(doc, input, null, true);
            // skip the attribute entry lines the parser would have consumed
            reader.readLine();
            reader.readLine();
            reader.readLine();
            expect(
              reader.readLine(),
              equals(
                'Unresolved directive in <stdin> - include::not-a-file.adoc +\nhttp://example.org/team.adoc[]',
              ),
            );
            assertMessage(
              logger,
              LogSeverity.error,
              '<stdin>: line 4: include file not found: $fixtureDir/not-a-file.adoc +\nhttp://example.org/team.adoc',
              contextual: true,
            );
          });
        },
      );

      test(
        'include directive should resolve file relative to current include',
        () {
          const input = 'include::fixtures/parent-include.adoc[]';
          final pseudoDocfile = '$repoTestDir/main.adoc';
          final parentIncludeDocfile = '$fixtureDir/parent-include.adoc';
          final childIncludeDocfile = '$fixtureDir/child-include.adoc';
          final grandchildIncludeDocfile =
              '$fixtureDir/grandchild-include.adoc';

          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, pseudoDocfile, true);

          expect(reader.file, equals(pseudoDocfile));
          expect(reader.dir, equals(repoTestDir));
          expect(reader.path, equals('main.adoc'));

          expect(reader.readLine(), equals('first line of parent'));

          expect(
            reader.cursorAtPrevLine().toString(),
            equals('fixtures/parent-include.adoc: line 1'),
          );
          expect(reader.file, equals(parentIncludeDocfile));
          expect(reader.dir, equals(fixtureDir));
          expect(reader.path, equals('fixtures/parent-include.adoc'));

          reader.skipBlankLines();

          expect(reader.readLine(), equals('first line of child'));

          expect(
            reader.cursorAtPrevLine().toString(),
            equals('fixtures/child-include.adoc: line 1'),
          );
          expect(reader.file, equals(childIncludeDocfile));
          expect(reader.dir, equals(fixtureDir));
          expect(reader.path, equals('fixtures/child-include.adoc'));

          reader.skipBlankLines();

          expect(reader.readLine(), equals('first line of grandchild'));

          expect(
            reader.cursorAtPrevLine().toString(),
            equals('fixtures/grandchild-include.adoc: line 1'),
          );
          expect(reader.file, equals(grandchildIncludeDocfile));
          expect(reader.dir, equals(fixtureDir));
          expect(reader.path, equals('fixtures/grandchild-include.adoc'));

          reader.skipBlankLines();

          expect(reader.readLine(), equals('last line of grandchild'));

          reader.skipBlankLines();

          expect(reader.readLine(), equals('last line of child'));

          reader.skipBlankLines();

          expect(reader.readLine(), equals('last line of parent'));

          expect(
            reader.cursorAtPrevLine().toString(),
            equals('fixtures/parent-include.adoc: line 5'),
          );
          expect(reader.file, equals(parentIncludeDocfile));
          expect(reader.dir, equals(fixtureDir));
          expect(reader.path, equals('fixtures/parent-include.adoc'));
        },
      );

      test(
        'include directive should process lines when file extension of target is .asciidoc',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input = 'include::fixtures/include-alt-extension.asciidoc[]';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          expect(
            reader.readLines(),
            equals(['first line', '', 'Asciidoctor!', '', 'last line']),
          );
        },
      );

      test(
        'should only strip trailing newlines, not trailing whitespace, if include file is not AsciiDoc',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input = '....\ninclude::fixtures/data.tsv[]\n....\n';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          final lines = reader.readLines();
          expect(lines, hasLength(6));
          expect(lines[3], endsWith('\t'));
        },
      );

      test(
        'should fail to read include file if not UTF-8 encoded and encoding is not specified',
        // READER-LEVEL: Ruby raises ArgumentError from push_include at
        // reader level (verified via oracle probe); convert is not needed.
        () {
          const input = '....\ninclude::fixtures/iso-8859-1.txt[]\n....\n';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          expect(
            reader.readLines,
            throwsA(
              isA<ArgumentError>().having(
                (error) => error.message,
                'message',
                'source is either binary or contains invalid Unicode data',
              ),
            ),
          );
        },
      );

      test(
        'should ignore encoding attribute if value is not a valid encoding',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input =
              '....\ninclude::fixtures/encoding.adoc[tag=romé,encoding=iso-1000-1]\n....\n';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          expect(
            reader.readLines(),
            equals([
              '....',
              'Gregory Romé has written an AsciiDoc plugin for the Redmine project management application.',
              '....',
            ]),
          );
        },
      );

      test(
        'should use encoding specified by encoding attribute when reading include file',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input =
              '....\ninclude::fixtures/iso-8859-1.txt[encoding=iso-8859-1]\n....\n';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          expect(
            reader.readLines(),
            equals(['....', "Où est l'hôpital ?", '....']),
          );
        },
      );

      test(
        'unresolved target referenced by include directive is skipped when optional option is set',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input =
              'include::fixtures/{no-such-file}[opts=optional]\n\ntrailing content\n';
          usingMemoryLogger((logger) {
            final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
            final reader = PreprocessorReader(doc, input, null, true);
            expect(reader.readLines(), equals(['', 'trailing content']));
            assertMessage(
              logger,
              LogSeverity.info,
              '~<stdin>: line 1: optional include dropped because include file not found',
              contextual: true,
            );
          });
        },
      );

      test(
        'should skip include directive that references missing file if optional option is set',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input =
              'include::fixtures/no-such-file.adoc[opts=optional]\n\ntrailing content\n';
          usingMemoryLogger((logger) {
            final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
            final reader = PreprocessorReader(doc, input, null, true);
            expect(reader.readLines(), equals(['', 'trailing content']));
            assertMessage(
              logger,
              LogSeverity.info,
              '~<stdin>: line 1: optional include dropped because include file not found',
              contextual: true,
            );
          });
        },
      );

      test(
        'should replace include directive that references missing file with message',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          const input =
              'include::fixtures/no-such-file.adoc[]\n\ntrailing content\n';
          usingMemoryLogger((logger) {
            final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
            final reader = PreprocessorReader(doc, input, null, true);
            expect(
              reader.readLines(),
              equals([
                'Unresolved directive in <stdin> - include::fixtures/no-such-file.adoc[]',
                '',
                'trailing content',
              ]),
            );
            assertMessage(
              logger,
              LogSeverity.error,
              '~<stdin>: line 1: include file not found',
              contextual: true,
            );
          });
        },
      );

      test(
        'should replace include directive that references unreadable file with message',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          if (Platform.isWindows || _isRoot()) {
            markTestSkipped('requires POSIX permissions and a non-root user');
          }
          final includeFile = '$fixtureDir/chapter-a.adoc';
          final oldMode = File(includeFile).statSync().mode;
          Process.runSync('chmod', ['000', includeFile]);
          const input =
              'include::fixtures/chapter-a.adoc[]\n\ntrailing content\n';
          try {
            usingMemoryLogger((logger) {
              final doc = FakeDocument(
                safe: SafeMode.safe,
                baseDir: repoTestDir,
              );
              final reader = PreprocessorReader(doc, input, null, true);
              expect(
                reader.readLines(),
                equals([
                  'Unresolved directive in <stdin> - include::fixtures/chapter-a.adoc[]',
                  '',
                  'trailing content',
                ]),
              );
              assertMessage(
                logger,
                LogSeverity.error,
                '~<stdin>: line 1: include file not readable',
                contextual: true,
              );
            });
          } finally {
            Process.runSync('chmod', [_modeString(oldMode), includeFile]);
          }
        },
      );

      test(
        'can resolve include directive with absolute path',
        // READER-LEVEL: asserts the expanded doctitle line instead of the
        // parsed doctitle. IMPORTANT: this test needs to be run on Windows
        // to verify proper behavior in Windows.
        () {
          final includePath = '$fixtureDir/chapter-a.adoc';
          final input = 'include::$includePath[]';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: fixtureDir);
          expect(
            PreprocessorReader(doc, input, null, true).readLine(),
            equals('= Chapter A'),
          );

          final unsafeDoc = FakeDocument(
            safe: SafeMode.unsafe,
            baseDir: Directory.systemTemp.path,
          );
          expect(
            PreprocessorReader(unsafeDoc, input, null, true).readLine(),
            equals('= Chapter A'),
          );
        },
      );

      test(
        'include directive can retrieve data from uri',
        // READER-LEVEL: asserts expanded lines instead of converted
        // output; URI transport is the FakeDocument test double (see its
        // docs), keyed on the request path.
        () {
          const url = 'http://localhost:9876/name/asciidoctor';
          final input = '....\ninclude::$url[]\n....\n';
          final doc = FakeDocument(
            safe: SafeMode.safe,
            attributes: {'allow-uri-read': ''},
          );
          final reader = PreprocessorReader(doc, input, null, true);
          final lines = reader.readLines();
          expect(lines, hasLength(3));
          expect(lines[1], contains('{"name": "asciidoctor"}'));
        },
      );

      test(
        'nested include directives are resolved relative to current file',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input = '....\ninclude::fixtures/outer-include.adoc[]\n....\n';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          const expected =
              'first line of outer\n'
              '\n'
              'first line of middle\n'
              '\n'
              'first line of inner\n'
              '\n'
              'last line of inner\n'
              '\n'
              'last line of middle\n'
              '\n'
              'last line of outer';
          expect(reader.readLines().join('\n'), contains(expected));
        },
      );

      test(
        'nested remote include directive is resolved relative to uri of current file',
        // READER-LEVEL: asserts expanded lines instead of converted
        // output; URI transport is the FakeDocument test double.
        () {
          const url = 'http://localhost:9876/fixtures/outer-include.adoc';
          final input = '....\ninclude::$url[]\n....\n';
          final doc = FakeDocument(
            safe: SafeMode.safe,
            attributes: {'allow-uri-read': ''},
          );
          final reader = PreprocessorReader(doc, input, null, true);
          const expected =
              'first line of outer\n'
              '\n'
              'first line of middle\n'
              '\n'
              'first line of inner\n'
              '\n'
              'last line of inner\n'
              '\n'
              'last line of middle\n'
              '\n'
              'last line of outer';
          expect(reader.readLines().join('\n'), contains(expected));
        },
      );

      test(
        'nested remote include directive that cannot be resolved does not crash processor',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const includeUrl =
              'http://localhost:9876/fixtures/file-with-missing-include.adoc';
          const nestedIncludeUrl = 'no-such-file.adoc';
          final input = '....\ninclude::$includeUrl[]\n....\n';
          usingMemoryLogger((logger) {
            final doc = FakeDocument(
              safe: SafeMode.safe,
              attributes: {'allow-uri-read': ''},
            );
            final reader = PreprocessorReader(doc, input, null, true);
            final lines = reader.readLines();
            expect(
              lines,
              contains(
                'Unresolved directive in $includeUrl - include::$nestedIncludeUrl[]',
              ),
            );
            assertMessage(
              logger,
              LogSeverity.error,
              '$includeUrl: line 1: include uri not readable: http://localhost:9876/fixtures/$nestedIncludeUrl',
              contextual: true,
            );
          });
        },
      );

      test(
        'should support tag filtering for remote includes',
        skip: 'needs Parser.adjustIndentation (parser wave)',
        () {},
      );

      test(
        'should not crash if include directive references inaccessible uri',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const url = 'http://localhost:9876/no_such_file';
          final input = '....\ninclude::$url[]\n....\n';
          usingMemoryLogger((logger) {
            final doc = FakeDocument(
              safe: SafeMode.safe,
              attributes: {'allow-uri-read': ''},
            );
            final reader = PreprocessorReader(doc, input, null, true);
            final lines = reader.readLines();
            expect(lines, isNotEmpty);
            expect(
              lines.any(
                (line) => line != null && line.contains('Unresolved directive'),
              ),
              isTrue,
            );
            assertMessage(
              logger,
              LogSeverity.error,
              '<stdin>: line 2: include uri not readable: $url',
              contextual: true,
            );
          });
        },
      );

      test(
        'include directive supports selecting lines by line number',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              'include::fixtures/include-file.adoc[lines=1;3..4;6..-1]';
          final lines = _includeLines(input);
          final source = lines.join('\n');
          expect(source, contains('first line'));
          expect(source, isNot(contains('second line')));
          expect(source, contains('third line'));
          expect(source, contains('fourth line'));
          expect(source, isNot(contains('fifth line')));
          expect(source, contains('sixth line'));
          expect(source, contains('seventh line'));
          expect(source, contains('eighth line'));
          expect(source, contains('last line of included content'));
        },
      );

      test(
        'include directive supports line ranges separated by commas in quoted attribute value',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              'include::fixtures/include-file.adoc[lines="1,3..4,6..-1"]';
          final source = _includeLines(input).join('\n');
          expect(source, contains('first line'));
          expect(source, isNot(contains('second line')));
          expect(source, contains('third line'));
          expect(source, contains('fourth line'));
          expect(source, isNot(contains('fifth line')));
          expect(source, contains('sixth line'));
          expect(source, contains('seventh line'));
          expect(source, contains('eighth line'));
          expect(source, contains('last line of included content'));
        },
      );

      test(
        'include directive ignores spaces between line ranges in quoted attribute value',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              'include::fixtures/include-file.adoc[lines="1, 3..4 , 6 .. -1"]';
          final source = _includeLines(input).join('\n');
          expect(source, contains('first line'));
          expect(source, isNot(contains('second line')));
          expect(source, contains('third line'));
          expect(source, contains('fourth line'));
          expect(source, isNot(contains('fifth line')));
          expect(source, contains('sixth line'));
          expect(source, contains('seventh line'));
          expect(source, contains('eighth line'));
          expect(source, contains('last line of included content'));
        },
      );

      test(
        'include directive supports implicit endless range',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input = 'include::fixtures/include-file.adoc[lines=6..]';
          final source = _includeLines(input).join('\n');
          expect(source, isNot(contains('first line')));
          expect(source, isNot(contains('second line')));
          expect(source, isNot(contains('third line')));
          expect(source, isNot(contains('fourth line')));
          expect(source, isNot(contains('fifth line')));
          expect(source, contains('sixth line'));
          expect(source, contains('seventh line'));
          expect(source, contains('eighth line'));
          expect(source, contains('last line of included content'));
        },
      );

      test(
        'include directive ignores lines attribute if empty',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              '++++\ninclude::fixtures/include-file.adoc[lines=]\n++++\n';
          final source = _includeLines(input).join('\n');
          expect(source, contains('first line of included content'));
          expect(source, contains('last line of included content'));
        },
      );

      test(
        'include directive ignores lines attribute with invalid range',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              '++++\ninclude::fixtures/include-file.adoc[lines=10..5]\n++++\n';
          final source = _includeLines(input).join('\n');
          expect(source, contains('first line of included content'));
          expect(source, contains('last line of included content'));
        },
      );

      test(
        'include directive supports selecting lines by tag',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input = 'include::fixtures/include-file.adoc[tag=snippetA]';
          final source = _includeLines(input).join('\n');
          expect(source, contains('snippetA content'));
          expect(source, isNot(contains('snippetB content')));
          expect(source, isNot(contains('non-tagged content')));
          expect(source, isNot(contains('included content')));
        },
      );

      test(
        'include directive supports selecting lines by tags',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              'include::fixtures/include-file.adoc[tags=snippetA;snippetB]';
          final source = _includeLines(input).join('\n');
          expect(source, contains('snippetA content'));
          expect(source, contains('snippetB content'));
          expect(source, isNot(contains('non-tagged content')));
          expect(source, isNot(contains('included content')));
        },
      );

      test(
        'include directive supports selecting lines by tag in language that uses circumfix comments',
        skip: 'needs Parser.adjustIndentation (parser wave)',
        () {},
      );

      test(
        'include directive supports selecting lines by tag in file that has CRLF line endings',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          final tmpDir = Directory.systemTemp.createTempSync(
            'asciidoctor-reader-test',
          );
          try {
            final tmpFile = File('${tmpDir.path}/include.adoc');
            tmpFile.writeAsStringSync(
              'do not include\r\ntag::include-me[]\r\nincluded line\r\nend::include-me[]\r\ndo not include\r\n',
            );
            final input = 'include::include.adoc[tag=include-me]';
            final doc = FakeDocument(safe: SafeMode.safe, baseDir: tmpDir.path);
            final reader = PreprocessorReader(doc, input, null, true);
            final source = reader.readLines().join('\n');
            expect(source, contains('included line'));
            expect(source, isNot(contains('do not include')));
          } finally {
            tmpDir.deleteSync(recursive: true);
          }
        },
      );

      test(
        'include directive finds closing tag on last line of file without a trailing newline',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          final tmpDir = Directory.systemTemp.createTempSync(
            'asciidoctor-reader-test',
          );
          try {
            final tmpFile = File('${tmpDir.path}/include.adoc');
            tmpFile.writeAsStringSync(
              'line not included\ntag::include-me[]\nline included\nend::include-me[]',
            );
            final input = 'include::include.adoc[tag=include-me]';
            usingMemoryLogger((logger) {
              final doc = FakeDocument(
                safe: SafeMode.safe,
                baseDir: tmpDir.path,
              );
              final reader = PreprocessorReader(doc, input, null, true);
              final source = reader.readLines().join('\n');
              expect(logger.messages, isEmpty);
              expect(source, contains('line included'));
              expect(source, isNot(contains('line not included')));
            });
          } finally {
            tmpDir.deleteSync(recursive: true);
          }
        },
      );

      test(
        'include directive does not select lines containing tag directives within selected tag region',
        // READER-LEVEL: asserts expanded lines instead of converted output
        // (expectation verified against the oracle at reader level).
        () {
          const input =
              '++++\ninclude::fixtures/include-file.adoc[tags=snippet]\n++++\n';
          const expected =
              'snippetA content\n'
              '\n'
              'non-tagged content\n'
              '\n'
              'snippetB content';
          expect(_delimitedLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive skips lines inside tag which is negated',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class-enclosed.rb[tags=all;!bark]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines without a tag directive when value is double asterisk',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=**]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines except lines inside tag which is negated when value starts with double asterisk',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=**;!bark]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines, including lines inside nested tags, except lines inside tag which is negated when value starts with double asterisk',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=**;!init]\n----\n';
          const expected =
              'class Dog\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines outside of tags when value is double asterisk followed by negated wildcard',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=**;!*]\n----\n';
          expect(_listingLines(input).join('\n'), equals('class Dog\nend'));
        },
      );

      test(
        'include directive skips all tagged regions when value of tags attribute is negated wildcard',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=!*]\n----\n';
          expect(_listingLines(input).join('\n'), equals('class Dog\nend'));
        },
      );

      // FIXME this is a weird one since we'd expect it to only select the
      // specified tags; but it's always been this way
      test(
        'include directive selects all lines except for lines containing tag directive if value is double asterisk followed by nested tag names',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=**;bark-beagle;bark-all]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      // FIXME this is a weird one since we'd expect it to only select the
      // specified tags; but it's always been this way
      test(
        'include directive selects all lines except for lines containing tag directive when value is double asterisk followed by outer tag name',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=**;bark]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines inside unspecified tags when value is negated double asterisk followed by negated tags',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe; the leading
        // blank line the converter drops is preserved here).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=!**;!init]\n----\n';
          const expected =
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines except tag which is negated when value only contains negated tag',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tag=!bark]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects all lines except tags which are negated when value only contains negated tags',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=!bark;!init]\n----\n';
          expect(_listingLines(input).join('\n'), equals('class Dog\nend'));
        },
      );

      test(
        'should recognize tag wildcard if not at start of tags list',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=init;**;*;!bark-other]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects lines between tags when value of tags attribute is wildcard',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=*]\n----\n';
          const expected =
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects lines inside tags when value of tags attribute is wildcard and tag surrounds content',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class-enclosed.rb[tags=*]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive selects lines inside all tags except tag which is negated when value of tags attribute is wildcard followed by negated tag',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class-enclosed.rb[tags=*;!init]\n----\n';
          const expected =
              'class Dog\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive skips all tagged regions except ones re-enabled when value of tags attribute is negated wildcard followed by tag name',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          for (final pattern in ['!*;init', '**;!*;init']) {
            final input =
                '----\ninclude::fixtures/tagged-class.rb[tags=$pattern]\n----\n';
            const expected =
                'class Dog\n'
                '  def initialize breed\n'
                '    @breed = breed\n'
                '  end\n'
                'end';
            expect(
              _listingLines(input).join('\n'),
              equals(expected),
              reason: pattern,
            );
          }
        },
      );

      test(
        'include directive includes regions outside tags and inside specified tags when value begins with negated wildcard',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=!*;bark]\n----\n';
          const expected =
              'class Dog\n'
              '\n'
              '  def bark\n'
              '  end\n'
              'end';
          expect(_listingLines(input).join('\n'), equals(expected));
        },
      );

      test(
        'include directive includes lines inside tag except for lines inside nested tags when tag is followed by negated wildcard',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe; the leading
        // blank line the converter drops is preserved here).
        () {
          for (final pattern in ['bark;!*', '!**;bark;!*', '!**;!*;bark']) {
            final input =
                '----\ninclude::fixtures/tagged-class.rb[tags=$pattern]\n----\n';
            expect(
              _listingLines(input).join('\n'),
              equals('\n  def bark\n  end'),
              reason: pattern,
            );
          }
        },
      );

      test(
        'include directive selects lines inside tag except for lines inside nested tags when tag is preceded by negated double asterisk and negated wildcard',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe; the leading
        // blank line the converter drops is preserved here).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=!**;!*;bark]\n----\n';
          expect(
            _listingLines(input).join('\n'),
            equals('\n  def bark\n  end'),
          );
        },
      );

      test(
        'include directive does not select lines inside tag that has been included then excluded',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class.rb[tags=!*;init;!init]\n----\n';
          expect(_listingLines(input).join('\n'), equals('class Dog\nend'));
        },
      );

      test(
        'include directive only selects lines inside specified tag, even if proceeded by negated double asterisk',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe; the leading
        // blank line the converter drops is preserved here).
        () {
          for (final pattern in ['bark', '!**;bark']) {
            final input =
                '----\ninclude::fixtures/tagged-class.rb[tags=$pattern]\n----\n';
            const expected =
                '\n'
                '  def bark\n'
                "    if @breed == 'beagle'\n"
                "      'woof woof woof woof woof'\n"
                '    else\n'
                "      'woof woof'\n"
                '    end\n'
                '  end';
            expect(
              _listingLines(input).join('\n'),
              equals(expected),
              reason: pattern,
            );
          }
        },
      );

      test(
        'include directive selects lines inside specified tag and ignores lines inside a negated tag',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe; the
        // [indent=0] block attribute only takes effect at conversion, so
        // original indentation and the leading blank line are preserved).
        () {
          const input =
              '[indent=0]\n'
              '----\n'
              'include::fixtures/tagged-class.rb[tags=bark;!bark-other]\n'
              '----\n';
          const expected =
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    end\n'
              '  end';
          final lines = _includeLines(input);
          expect(
            lines.sublist(2, lines.length - 1).join('\n'),
            equals(expected),
          );
        },
      );

      test(
        'should warn if specified tag is not found in include file',
        // READER-LEVEL: log assertion only (no conversion).
        () {
          const input = 'include::fixtures/include-file.adoc[tag=no-such-tag]';
          usingMemoryLogger((logger) {
            _includeLines(input);
            assertMessage(
              logger,
              LogSeverity.warn,
              "~<stdin>: line 1: tag 'no-such-tag' not found in include file",
              contextual: true,
            );
          });
        },
      );

      test(
        'should not warn if specified negated tag is not found in include file',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class-enclosed.rb[tag=!no-such-tag]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          usingMemoryLogger((logger) {
            expect(_listingLines(input).join('\n'), equals(expected));
            expect(logger.messages, isEmpty);
          });
        },
      );

      test(
        'should warn if specified tags are not found in include file',
        // READER-LEVEL: log assertion only (no conversion).
        () {
          const input =
              '++++\ninclude::fixtures/include-file.adoc[tags=no-such-tag-b;no-such-tag-a]\n++++\n';
          usingMemoryLogger((logger) {
            _includeLines(input);
            const expectedTags = 'no-such-tag-b, no-such-tag-a';
            assertMessage(
              logger,
              LogSeverity.warn,
              "~<stdin>: line 2: tags '$expectedTags' not found in include file",
              contextual: true,
            );
          });
        },
      );

      test(
        'should not warn if specified negated tags are not found in include file',
        // READER-LEVEL: asserts expanded lines instead of the converted
        // <pre> block (expectation verified via oracle probe).
        () {
          const input =
              '----\ninclude::fixtures/tagged-class-enclosed.rb[tags=all;!no-such-tag;!unknown-tag]\n----\n';
          const expected =
              'class Dog\n'
              '  def initialize breed\n'
              '    @breed = breed\n'
              '  end\n'
              '\n'
              '  def bark\n'
              "    if @breed == 'beagle'\n"
              "      'woof woof woof woof woof'\n"
              '    else\n'
              "      'woof woof'\n"
              '    end\n'
              '  end\n'
              'end';
          usingMemoryLogger((logger) {
            expect(_listingLines(input).join('\n'), equals(expected));
            expect(logger.messages, isEmpty);
          });
        },
      );

      test(
        'should warn if specified tag in include file is not closed',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              '++++\ninclude::fixtures/unclosed-tag.adoc[tag=a]\n++++\n';
          usingMemoryLogger((logger) {
            expect(_delimitedLines(input), equals(['a']));
            assertMessage(
              logger,
              LogSeverity.warn,
              "~<stdin>: line 2: detected unclosed tag 'a' starting at line 2 of include file",
              contextual: true,
            );
            final message = logger.messages[0].message as LogMessage;
            expect(message.includeLocation, isNotNull);
          });
        },
      );

      test(
        'should warn if end tag in included file is mismatched',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              '++++\ninclude::fixtures/mismatched-end-tag.adoc[tags=a;b]\n++++\n';
          final incPath = '$fixtureDir/mismatched-end-tag.adoc';
          usingMemoryLogger((logger) {
            expect(_delimitedLines(input).join('\n'), equals('a\nb'));
            assertMessage(
              logger,
              LogSeverity.warn,
              "<stdin>: line 2: mismatched end tag (expected 'b' but found 'a') at line 5 of include file: $incPath",
              contextual: true,
            );
            final message = logger.messages[0].message as LogMessage;
            expect(message.includeLocation, isNotNull);
          });
        },
      );

      test(
        'should warn if unexpected end tag is found in included file',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              '++++\ninclude::fixtures/unexpected-end-tag.adoc[tags=a]\n++++\n';
          final incPath = '$fixtureDir/unexpected-end-tag.adoc';
          usingMemoryLogger((logger) {
            expect(_delimitedLines(input), equals(['a']));
            assertMessage(
              logger,
              LogSeverity.warn,
              "<stdin>: line 2: unexpected end tag 'a' at line 4 of include file: $incPath",
              contextual: true,
            );
            final message = logger.messages[0].message as LogMessage;
            expect(message.includeLocation, isNotNull);
          });
        },
      );

      test(
        'include directive ignores tags attribute when empty',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          for (final attrName in ['tag', 'tags']) {
            final input =
                '++++\ninclude::fixtures/include-file.xml[$attrName=]\n++++\n';
            final matches = RegExp('(?:tag|end)::')
                .allMatches(_includeLines(input).join('\n'));
            expect(matches, hasLength(2));
          }
        },
      );

      test(
        'lines attribute takes precedence over tags attribute in include directive',
        // READER-LEVEL: asserts expanded lines instead of converted output.
        () {
          const input =
              'include::fixtures/include-file.adoc[lines=1, tags=snippetA;snippetB]';
          final source = _includeLines(input).join('\n');
          expect(source, contains('first line of included content'));
          expect(source, isNot(contains('snippetA content')));
          expect(source, isNot(contains('snippetB content')));
        },
      );

      test(
        'indent of included file can be reset to size of indent attribute',
        skip: 'needs Parser.adjustIndentation (parser wave)',
        () {},
      );

      test(
        'should substitute attribute references in attrlist',
        // READER-LEVEL: the attribute is preset (attribute-entry parsing
        // belongs to the document wave); asserts expanded lines instead of
        // converted output.
        () {
          const input =
              'include::fixtures/include-file.adoc[tag={name-of-tag}]';
          final doc = FakeDocument(
            safe: SafeMode.safe,
            baseDir: repoTestDir,
            attributes: {'name-of-tag': 'snippetA'},
          );
          final reader = PreprocessorReader(doc, input, null, true);
          final source = reader.readLines().join('\n');
          expect(source, contains('snippetA content'));
          expect(source, isNot(contains('snippetB content')));
          expect(source, isNot(contains('non-tagged content')));
          expect(source, isNot(contains('included content')));
        },
      );

      test(
        'should fall back to built-in include directive behavior when not handled by include processor',
        // NOTE the Ruby test sets the dead @include_processors ivar (the
        // implementation reads @include_processor_extensions), so it
        // exercises the built-in path; the port does the same directly.
        () {
          const input = 'include::fixtures/include-file.adoc[]';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          final source = reader.readLines().join('\n');
          expect(source, contains('included content'));
        },
      );

      test('leveloffset attribute entries should be added to content if leveloffset attribute is specified', () {
        const input = 'include::fixtures/main.adoc[]';
        const expected = [
          '= Main Document',
          '',
          'preamble',
          '',
          ':leveloffset: +1',
          '',
          '= Chapter A',
          '',
          'content',
          '',
          ':leveloffset!:',
        ];

        final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
        final reader = PreprocessorReader(doc, input, null, true);
        expect(reader.readLines(), equals(expected));
      });

      test(
        'attributes are substituted in target of include directive',
        // READER-LEVEL: attributes are preset (attribute-entry parsing
        // belongs to the document wave); asserts expanded lines instead of
        // converted output.
        () {
          const input = 'include::{fixturesdir}/include-file.{ext}[]';
          final doc = FakeDocument(
            safe: SafeMode.safe,
            baseDir: repoTestDir,
            attributes: {'fixturesdir': 'fixtures', 'ext': 'adoc'},
          );
          final reader = PreprocessorReader(doc, input, null, true);
          expect(reader.readLines().join('\n'), contains('included content'));
        },
      );

      test('line is skipped by default if target of include directive resolves to empty', () {
        const input = 'include::{blank}[]';
        usingMemoryLogger((logger) {
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, input, null, true);
          expect(
            reader.readLine(),
            equals('Unresolved directive in <stdin> - include::{blank}[]'),
          );
          assertMessage(
            logger,
            LogSeverity.warn,
            '<stdin>: line 1: include dropped because resolved target is blank: include::{blank}[]',
            contextual: true,
          );
        });
      });

      test('include is dropped if target contains missing attribute and attribute-missing is drop-line', () {
        const input = 'include::{foodir}/include-file.adoc[]';
        usingMemoryLogger((logger) {
          final doc = FakeDocument(
            safe: SafeMode.safe,
            baseDir: repoTestDir,
            attributes: {'attribute-missing': 'drop-line'},
          );
          final reader = PreprocessorReader(doc, input, null, true);
          expect(reader.readLine(), isNull);
          assertMessages(logger, [
            (
              LogSeverity.info,
              'dropping line containing reference to missing attribute: foodir',
              false,
            ),
            (
              LogSeverity.info,
              '<stdin>: line 1: include dropped due to missing attribute: include::{foodir}/include-file.adoc[]',
              true,
            ),
          ]);
        }, LogSeverity.info);
      });

      test('line following dropped include is not dropped', () {
        const input = 'include::{foodir}/include-file.adoc[]\nyo\n';
        usingMemoryLogger((logger) {
          final doc = FakeDocument(
            safe: SafeMode.safe,
            baseDir: repoTestDir,
            attributes: {'attribute-missing': 'warn'},
          );
          final reader = PreprocessorReader(doc, input, null, true);
          expect(
            reader.readLine(),
            equals(
              'Unresolved directive in <stdin> - include::{foodir}/include-file.adoc[]',
            ),
          );
          expect(reader.readLine(), equals('yo'));
          assertMessages(logger, [
            (
              LogSeverity.info,
              'dropping line containing reference to missing attribute: foodir',
              false,
            ),
            (
              LogSeverity.warn,
              '<stdin>: line 1: include dropped due to missing attribute: include::{foodir}/include-file.adoc[]',
              true,
            ),
          ]);
        });
      });

      test('escaped include directive is left unprocessed', () {
        const input =
            '\\include::fixtures/include-file.adoc[]\n\\escape preserved here\n';
        final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
        final reader = PreprocessorReader(doc, input, null, true);
        // we should be able to peek it multiple times and still have the
        // backslash preserved; this is the test for unescapeNextLine
        expect(
          reader.peekLine(),
          equals('include::fixtures/include-file.adoc[]'),
        );
        expect(
          reader.peekLine(),
          equals('include::fixtures/include-file.adoc[]'),
        );
        expect(
          reader.readLine(),
          equals('include::fixtures/include-file.adoc[]'),
        );
        expect(reader.readLine(), equals('\\escape preserved here'));
      });

      test(
        'include directive not at start of line is ignored',
        // READER-LEVEL: asserts the line passes through the reader
        // untouched (literal-block detection belongs to the parser wave).
        () {
          const input = ' include::include-file.adoc[]';
          final reader = preprocessorReader(input);
          expect(reader.readLine(), equals(input));
        },
      );

      test(
        'include directive is disabled when max-include-depth attribute is 0',
        // READER-LEVEL: asserts the line passes through the reader
        // untouched (block parsing belongs to the parser wave).
        () {
          const input = 'include::include-file.adoc[]';
          final reader = preprocessorReader(
            input,
            safe: SafeMode.safe,
            attributes: {'max-include-depth': 0},
          );
          expect(reader.readLine(), equals(input));
        },
      );

      test(
        'max-include-depth cannot be set by document',
        // READER-LEVEL: the reader snapshots max depth at construction, so
        // the include still passes through (attribute-entry parsing
        // belongs to the document wave).
        () {
          const input =
              ':max-include-depth: 1\n\ninclude::include-file.adoc[]\n';
          final reader = preprocessorReader(
            input,
            safe: SafeMode.safe,
            attributes: {'max-include-depth': 0},
          );
          expect(reader.readLines(), equals(input.trimRight().split('\n')));
        },
      );

      test('include directive should be disabled if max include depth has been exceeded', () {
        const input = 'include::fixtures/parent-include.adoc[depth=1]';
        usingMemoryLogger((logger) {
          final pseudoDocfile = '$repoTestDir/main.adoc';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(
            doc,
            input,
            Cursor(pseudoDocfile),
            true,
          );
          final lines = reader.readlines();
          expect(lines, contains('include::grandchild-include.adoc[]'));
          assertMessage(
            logger,
            LogSeverity.error,
            'fixtures/child-include.adoc: line 3: maximum include depth of 1 exceeded',
            contextual: true,
          );
        });
      });

      test('include directive should be disabled if max include depth set in nested context has been exceeded', () {
        const input =
            'include::fixtures/parent-include-restricted.adoc[depth=3]';
        usingMemoryLogger((logger) {
          final pseudoDocfile = '$repoTestDir/main.adoc';
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(
            doc,
            input,
            Cursor(pseudoDocfile),
            true,
          );
          final lines = reader.readlines();
          expect(lines, contains('first line of child'));
          expect(lines, contains('include::grandchild-include.adoc[]'));
          assertMessage(
            logger,
            LogSeverity.error,
            'fixtures/child-include.adoc: line 3: maximum include depth of 0 exceeded',
            contextual: true,
          );
        });
      });

      test(
        'readLinesUntil should not process lines if process option is false',
        () {
          final lines = [
            '////\n',
            'include::fixtures/no-such-file.adoc[]\n',
            '////\n',
          ];

          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, lines, null, true);
          reader.readLine();
          final result = reader.readLinesUntil(
            terminator: '////',
            skipProcessing: true,
          );
          expect(
            result,
            equals(lines.map((line) => line.chomp()).toList().sublist(1, 2)),
          );
        },
      );

      test(
        'save and restoreSave round-trip preprocessor state including includes',
        // NOTE no Ruby counterpart in reader_test.rb; pins ported behavior
        // the parser wave calls (verified against the oracle).
        () {
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(
            doc,
            ['a', 'include::fixtures/include-file.adoc[tag=snippetA]', 'z'],
            null,
            true,
          );
          expect(reader.readLine(), equals('a'));
          reader.save();
          expect(reader.readLine(), equals('snippetA content'));
          expect(reader.includeStack, hasLength(1));
          reader.restoreSave();
          expect(reader.includeStack, isEmpty);
          expect(reader.readLines(), equals(['snippetA content', 'z']));
        },
      );

      test('skip_comment_lines should not process lines read', () {
        final lines = [
          '////\n',
          'include::fixtures/no-such-file.adoc[]\n',
          '////\n',
        ];

        usingMemoryLogger((logger) {
          final doc = FakeDocument(safe: SafeMode.safe, baseDir: repoTestDir);
          final reader = PreprocessorReader(doc, lines, null, true);
          reader.skipCommentLines();
          expect(reader.isEmpty, isTrue);
          expect(logger.messages, isEmpty);
        });
      });
    });

    group('Conditional Inclusions', () {
      test('processLine returns null if cursor advanced', () {
        const input =
            'ifdef::asciidoctor[]\nAsciidoctor!\nendif::asciidoctor[]\n';

        final reader = preprocessorReader(input);
        expect(reader.processLine(reader.lines.first!), isNull);
      });

      test('peekLine advances cursor to next conditional line of content', () {
        const input =
            'ifdef::asciidoctor[]\nAsciidoctor!\nendif::asciidoctor[]\n';

        final reader = preprocessorReader(input);
        expect(reader.lineno, equals(1));
        expect(reader.peekLine(), equals('Asciidoctor!'));
        expect(reader.lineno, equals(2));
      });

      test('peekLines should preprocess lines if direct is false', () {
        const input = 'The Asciidoctor\nifdef::asciidoctor[is in.]\n';
        final reader = preprocessorReader(input);
        expect(
          reader.peekLines(2, false),
          equals(['The Asciidoctor', 'is in.']),
        );
      });

      test('peekLines should not preprocess lines if direct is true', () {
        const input = 'The Asciidoctor\nifdef::asciidoctor[is in.]\n';
        final reader = preprocessorReader(input);
        expect(
          reader.peekLines(2, true),
          equals(['The Asciidoctor', 'ifdef::asciidoctor[is in.]']),
        );
      });

      test(
        'peekLines should not prevent subsequent preprocessing of peeked lines',
        () {
          const input = 'The Asciidoctor\nifdef::asciidoctor[is in.]\n';
          final reader = preprocessorReader(input);
          reader.peekLines(2, true);
          expect(
            reader.peekLines(2, false),
            equals(['The Asciidoctor', 'is in.']),
          );
        },
      );

      test('processLine returns line if cursor not advanced', () {
        const input =
            'content\nifdef::asciidoctor[]\nAsciidoctor!\nendif::asciidoctor[]\n';

        final reader = preprocessorReader(input);
        expect(reader.processLine(reader.lines.first!), isNotNull);
      });

      test('peekLine does not advance cursor when on a regular content line', () {
        const input =
            'content\nifdef::asciidoctor[]\nAsciidoctor!\nendif::asciidoctor[]\n';

        final reader = preprocessorReader(input);
        expect(reader.lineno, equals(1));
        expect(reader.peekLine(), equals('content'));
        expect(reader.lineno, equals(1));
      });

      test('peekLine returns null if cursor advances past end of source', () {
        const input = 'ifdef::foobar[]\nswallowed content\nendif::foobar[]\n';

        final reader = preprocessorReader(input);
        expect(reader.lineno, equals(1));
        expect(reader.peekLine(), isNull);
        expect(reader.lineno, equals(4));
      });

      test('peekLine returns null if contents of skipped conditional is empty line', () {
        const input = 'ifdef::foobar[]\n\nendif::foobar[]\n';

        final reader = preprocessorReader(input);
        expect(reader.lineno, equals(1));
        expect(reader.peekLine(), isNull);
      });

      test('ifdef with defined attribute includes content', () {
        const input =
            'ifdef::holygrail[]\nThere is a holy grail!\nendif::holygrail[]\n';

        final lines = readAll(input, attributes: {'holygrail': ''});
        expect(lines.join('\n'), equals('There is a holy grail!'));
      });

      test('ifdef with defined attribute includes text in brackets', () {
        const input =
            'On our quest we go...\n'
            'ifdef::holygrail[There is a holy grail!]\n'
            'There was much rejoicing.\n';

        final lines = readAll(input, attributes: {'holygrail': ''});
        expect(
          lines.join('\n'),
          equals(
            'On our quest we go...\nThere is a holy grail!\nThere was much rejoicing.',
          ),
        );
      });

      test('ifdef with defined attribute processes include directive in brackets', () {
        const input =
            'ifdef::asciidoctor-version[include::fixtures/include-file.adoc[tag=snippetA]]';
        final lines = readAll(input, safe: SafeMode.safe, baseDir: repoTestDir);
        expect(lines[0], equals('snippetA content'));
      });

      test('ifdef attribute name is not case sensitive', () {
        const input =
            'ifdef::showScript[]\n'
            'The script is shown!\n'
            'endif::showScript[]\n';

        final reader = preprocessorReader(
          input,
          attributes: {'showscript': ''},
        );
        expect(reader.read(), equals('The script is shown!'));
      });

      test(
        'ifndef with defined attribute does not include text in brackets',
        () {
          const input =
              'On our quest we go...\n'
              'ifndef::hardships[There is a holy grail!]\n'
              'There was no rejoicing.\n';

          final lines = readAll(input, attributes: {'hardships': ''});
          expect(
            lines.join('\n'),
            equals('On our quest we go...\nThere was no rejoicing.'),
          );
        },
      );

      test('include with non-matching nested exclude', () {
        const input =
            'ifdef::grail[]\n'
            'holy\n'
            'ifdef::swallow[]\n'
            'swallow\n'
            'endif::swallow[]\n'
            'grail\n'
            'endif::grail[]\n';

        final lines = readAll(input, attributes: {'grail': ''});
        expect(lines.join('\n'), equals('holy\ngrail'));
      });

      test('nested excludes with same condition', () {
        const input =
            'ifndef::grail[]\n'
            'ifndef::grail[]\n'
            'not here\n'
            'endif::grail[]\n'
            'endif::grail[]\n';

        final lines = readAll(input, attributes: {'grail': ''});
        expect(lines.join('\n'), equals(''));
      });

      test('include with nested exclude of inverted condition', () {
        const input =
            'ifdef::grail[]\n'
            'holy\n'
            'ifndef::grail[]\n'
            'not here\n'
            'endif::grail[]\n'
            'grail\n'
            'endif::grail[]\n';

        final lines = readAll(input, attributes: {'grail': ''});
        expect(lines.join('\n'), equals('holy\ngrail'));
      });

      test('exclude with matching nested exclude', () {
        const input =
            'poof\n'
            'ifdef::swallow[]\n'
            'no\n'
            'ifdef::swallow[]\n'
            'swallow\n'
            'endif::swallow[]\n'
            'here\n'
            'endif::swallow[]\n'
            'gone\n';

        final lines = readAll(input, attributes: {'grail': ''});
        expect(lines.join('\n'), equals('poof\ngone'));
      });

      test('exclude with nested include using shorthand end', () {
        const input =
            'poof\n'
            'ifndef::grail[]\n'
            'no grail\n'
            'ifndef::swallow[]\n'
            'or swallow\n'
            'endif::[]\n'
            'in here\n'
            'endif::[]\n'
            'gone\n';

        final lines = readAll(input, attributes: {'grail': ''});
        expect(lines.join('\n'), equals('poof\ngone'));
      });

      test('ifdef with one alternative attribute set includes content', () {
        const input =
            'ifdef::holygrail,swallow[]\n'
            'Our quest is complete!\n'
            'endif::holygrail,swallow[]\n';

        final lines = readAll(input, attributes: {'swallow': ''});
        expect(lines.join('\n'), equals('Our quest is complete!'));
      });

      test(
        'ifdef with no alternative attributes set does not include content',
        () {
          const input =
              'ifdef::holygrail,swallow[]\n'
              'Our quest is complete!\n'
              'endif::holygrail,swallow[]\n';

          final lines = readAll(input);
          expect(lines.join('\n'), equals(''));
        },
      );

      test('ifdef with all required attributes set includes content', () {
        const input =
            'ifdef::holygrail+swallow[]\n'
            'Our quest is complete!\n'
            'endif::holygrail+swallow[]\n';

        final lines = readAll(
          input,
          attributes: {'holygrail': '', 'swallow': ''},
        );
        expect(lines.join('\n'), equals('Our quest is complete!'));
      });

      test(
        'ifdef with missing required attributes does not include content',
        () {
          const input =
              'ifdef::holygrail+swallow[]\n'
              'Our quest is complete!\n'
              'endif::holygrail+swallow[]\n';

          final lines = readAll(input, attributes: {'holygrail': ''});
          expect(lines.join('\n'), equals(''));
        },
      );

      test('ifdef should permit leading, trailing, and repeat operators', () {
        const cases = {
          'asciidoctor,': 'content',
          ',asciidoctor': 'content',
          'asciidoctor+': '',
          '+asciidoctor': '',
          'asciidoctor,,asciidoctor-version': 'content',
          'asciidoctor++asciidoctor-version': '',
        };
        cases.forEach((condition, expected) {
          final input = 'ifdef::$condition[]\ncontent\nendif::[]\n';
          expect(preprocessorReader(input).read(), equals(expected));
        });
      });

      test('ifndef with undefined attribute includes block', () {
        const input =
            'ifndef::holygrail[]\n'
            'Our quest continues to find the holy grail!\n'
            'endif::holygrail[]\n';

        final lines = readAll(input);
        expect(
          lines.join('\n'),
          equals('Our quest continues to find the holy grail!'),
        );
      });

      test(
        'ifndef with one alternative attribute set does not include content',
        () {
          const input =
              'ifndef::holygrail,swallow[]\n'
              'Our quest is complete!\n'
              'endif::holygrail,swallow[]\n';

          final result = preprocessorReader(
            input,
            attributes: {'swallow': ''},
          ).read();
          expect(result, isEmpty);
        },
      );

      test(
        'ifndef with both alternative attributes set does not include content',
        () {
          const input =
              'ifndef::holygrail,swallow[]\n'
              'Our quest is complete!\n'
              'endif::holygrail,swallow[]\n';

          final result = preprocessorReader(
            input,
            attributes: {'swallow': '', 'holygrail': ''},
          ).read();
          expect(result, isEmpty);
        },
      );

      test('ifndef with no alternative attributes set includes content', () {
        const input =
            'ifndef::holygrail,swallow[]\n'
            'Our quest is complete!\n'
            'endif::holygrail,swallow[]\n';

        expect(
          preprocessorReader(input).read(),
          equals('Our quest is complete!'),
        );
      });

      test('ifndef with no required attributes set includes content', () {
        const input =
            'ifndef::holygrail+swallow[]\n'
            'Our quest is complete!\n'
            'endif::holygrail+swallow[]\n';

        expect(
          preprocessorReader(input).read(),
          equals('Our quest is complete!'),
        );
      });

      test(
        'ifndef with all required attributes set does not include content',
        () {
          const input =
              'ifndef::holygrail+swallow[]\n'
              'Our quest is complete!\n'
              'endif::holygrail+swallow[]\n';

          final result = preprocessorReader(
            input,
            attributes: {'swallow': '', 'holygrail': ''},
          ).read();
          expect(result, isEmpty);
        },
      );

      test('ifndef with at least one required attributes set does not include content', () {
        const input =
            'ifndef::holygrail+swallow[]\n'
            'Our quest is complete!\n'
            'endif::holygrail+swallow[]\n';

        // NOTE despite the name, the Ruby test asserts content IS included
        // (all required attributes must be set to skip).
        expect(
          preprocessorReader(input, attributes: {'swallow': ''}).read(),
          equals('Our quest is complete!'),
        );
      });

      test('ifdef around empty line does not introduce extra line', () {
        const input =
            'before\n'
            'ifdef::no-such-attribute[]\n'
            '\n'
            'endif::[]\n'
            'after\n';

        expect(preprocessorReader(input).read(), equals('before\nafter'));
      });

      test('should log warning if endif is unmatched', () {
        const input = 'Our quest is complete!\nendif::on-quest[]\n';

        usingMemoryLogger((logger) {
          final result = preprocessorReader(
            input,
            attributes: {'on-quest': ''},
          ).read();
          expect(result, equals('Our quest is complete!'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 2: unmatched preprocessor directive: endif::on-quest[]',
            contextual: true,
          );
        });
      });

      test('should log warning if endif is mismatched', () {
        const input =
            'ifdef::on-quest[]\n'
            'Our quest is complete!\n'
            'endif::on-journey[]\n';

        usingMemoryLogger((logger) {
          final result = preprocessorReader(
            input,
            attributes: {'on-quest': ''},
            sourcemap: true,
          ).read();
          expect(result, equals('Our quest is complete!'));
          assertMessages(logger, [
            (
              LogSeverity.error,
              '~<stdin>: line 3: mismatched preprocessor directive: endif::on-journey[]',
              true,
            ),
            (
              LogSeverity.error,
              '~<stdin>: line 1: detected unterminated preprocessor conditional directive: ifdef::on-quest[]',
              true,
            ),
          ]);
        });
      });

      test('should log warning if endif contains text', () {
        const input =
            'ifdef::on-quest[]\n'
            'Our quest is complete!\n'
            'endif::on-quest[complete!]\n'
            'fin\n';

        usingMemoryLogger((logger) {
          final result = preprocessorReader(
            input,
            attributes: {'on-quest': ''},
            sourcemap: true,
          ).read();
          expect(result, equals('Our quest is complete!\nfin'));
          assertMessages(logger, [
            (
              LogSeverity.error,
              '~<stdin>: line 3: malformed preprocessor directive - text not permitted: endif::on-quest[complete!]',
              true,
            ),
            (
              LogSeverity.error,
              '~<stdin>: line 1: detected unterminated preprocessor conditional directive: ifdef::on-quest[]',
              true,
            ),
          ]);
        });
      });

      test('escaped ifdef is unescaped and ignored', () {
        const input = '\\ifdef::holygrail[]\ncontent\n\\endif::holygrail[]\n';

        final lines = readAll(input);
        expect(
          lines.join('\n'),
          equals('ifdef::holygrail[]\ncontent\nendif::holygrail[]'),
        );
      });

      test('ifeval comparing missing attribute to nil includes content', () {
        const input = "ifeval::['{foo}' == '']\nNo foo for you!\nendif::[]\n";

        final lines = readAll(input);
        expect(lines.join('\n'), equals('No foo for you!'));
      });

      test('ifeval comparing missing attribute to 0 drops content', () {
        const input =
            "ifeval::[{leveloffset} == 0]\nI didn't make the cut!\nendif::[]\n";

        final lines = readAll(input);
        expect(lines.join('\n'), equals(''));
      });

      test('ifeval running unsupported operation on missing attribute drops content', () {
        const input =
            "ifeval::[{leveloffset} >= 3]\nI didn't make the cut!\nendif::[]\n";

        final lines = readAll(input);
        expect(lines.join('\n'), equals(''));
      });

      test('ifeval running invalid operation drops content', () {
        const input =
            "ifeval::[{asciidoctor-version} > true]\nI didn't make the cut!\nendif::[]\n";

        final lines = readAll(input);
        expect(lines.join('\n'), equals(''));
      });

      test('ifeval comparing double-quoted attribute to matching string includes content', () {
        const input =
            'ifeval::["{gem}" == "asciidoctor"]\n'
            'Asciidoctor it is!\n'
            'endif::[]\n';

        final lines = readAll(input, attributes: {'gem': 'asciidoctor'});
        expect(lines.join('\n'), equals('Asciidoctor it is!'));
      });

      test('ifeval comparing single-quoted attribute to matching string includes content', () {
        const input =
            "ifeval::['{gem}' == 'asciidoctor']\n"
            'Asciidoctor it is!\n'
            'endif::[]\n';

        final lines = readAll(input, attributes: {'gem': 'asciidoctor'});
        expect(lines.join('\n'), equals('Asciidoctor it is!'));
      });

      test('ifeval comparing quoted attribute to non-matching string drops content', () {
        const input =
            "ifeval::['{gem}' == 'asciidoctor']\n"
            'Asciidoctor it is!\n'
            'endif::[]\n';

        final lines = readAll(input, attributes: {'gem': 'tilt'});
        expect(lines.join('\n'), equals(''));
      });

      test(
        'ifeval comparing attribute to lower version number includes content',
        () {
          const input =
              "ifeval::['{asciidoctor-version}' >= '0.1.0']\n"
              'That version will do!\n'
              'endif::[]\n';

          final lines = readAll(input);
          expect(lines.join('\n'), equals('That version will do!'));
        },
      );

      test('ifeval comparing attribute to self includes content', () {
        const input =
            "ifeval::['{asciidoctor-version}' == '{asciidoctor-version}']\n"
            "Of course it's the same!\n"
            'endif::[]\n';

        final lines = readAll(input);
        expect(lines.join('\n'), equals("Of course it's the same!"));
      });

      test('ifeval arguments can be transposed', () {
        const input =
            "ifeval::['0.1.0' <= '{asciidoctor-version}']\n"
            'That version will do!\n'
            'endif::[]\n';

        final lines = readAll(input);
        expect(lines.join('\n'), equals('That version will do!'));
      });

      test('ifeval matching numeric equality includes content', () {
        const input =
            'ifeval::[{rings} == 1]\n'
            'One ring to rule them all!\n'
            'endif::[]\n';

        final lines = readAll(input, attributes: {'rings': '1'});
        expect(lines.join('\n'), equals('One ring to rule them all!'));
      });

      test('ifeval matching numeric inequality includes content', () {
        const input =
            'ifeval::[{rings} != 0]\n'
            'One ring to rule them all!\n'
            'endif::[]\n';

        final lines = readAll(input, attributes: {'rings': '1'});
        expect(lines.join('\n'), equals('One ring to rule them all!'));
      });

      test('should log error if ifeval has target', () {
        const input = 'ifeval::target[1 == 1]\ncontent\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input);
          expect(lines.join('\n'), equals('content'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 1: malformed preprocessor directive - target not permitted: ifeval::target[1 == 1]',
            contextual: true,
          );
        });
      });

      test('should log error if ifeval has invalid expression', () {
        const input = 'ifeval::[1 | 2]\ncontent\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input);
          expect(lines.join('\n'), equals('content'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 1: malformed preprocessor directive - invalid expression: ifeval::[1 | 2]',
            contextual: true,
          );
        });
      });

      test('should log error if ifeval is missing expression', () {
        const input = 'ifeval::[]\ncontent\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input);
          expect(lines.join('\n'), equals('content'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 1: malformed preprocessor directive - missing expression: ifeval::[]',
            contextual: true,
          );
        });
      });

      test('ifdef with no target is ignored', () {
        const input = 'ifdef::[]\ncontent\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input);
          expect(lines.join('\n'), equals('content'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 1: malformed preprocessor directive - missing target: ifdef::[]',
            contextual: true,
          );
        });
      });

      test('should not warn about invalid ifdef preprocessor directive if already skipping', () {
        const input =
            'ifdef::attribute-not-set[]\n'
            'foo\n'
            'ifdef::[]\n'
            'bar\n'
            'endif::[]\n'
            'baz\n';

        usingMemoryLogger((logger) {
          expect(preprocessorReader(input).read(), equals('baz'));
          expect(logger.messages, isEmpty);
        });
      });

      test('should not warn about invalid ifeval preprocessor directive if already skipping', () {
        const input =
            'ifdef::attribute-not-set[]\n'
            'foo\n'
            'ifeval::[]\n'
            'bar\n'
            'endif::[]\n'
            'baz\n';

        usingMemoryLogger((logger) {
          expect(preprocessorReader(input).read(), equals('baz'));
          expect(logger.messages, isEmpty);
        });
      });

      test('should log error with end position if preprocessor conditional directive is unterminated', () {
        const input =
            'before\n'
            'ifdef::not-set[]\n'
            'skip\n'
            'these\n'
            'lines\n'
            'fin\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input);
          expect(lines.join('\n'), equals('before'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 6: detected unterminated preprocessor conditional directive: ifdef::not-set[]',
            contextual: true,
          );
        });
      });

      test('should log error with start location if preprocessor conditional directive is unterminated and sourcemap is set', () {
        const input =
            'before\n'
            'ifdef::not-set[]\n'
            'skip\n'
            'these\n'
            'lines\n'
            'fin\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input, sourcemap: true);
          expect(lines.join('\n'), equals('before'));
          assertMessage(
            logger,
            LogSeverity.error,
            '~<stdin>: line 2: detected unterminated preprocessor conditional directive: ifdef::not-set[]',
            contextual: true,
          );
        });
      });

      test('should log error if multiple preprocessor conditional directives are unterminated', () {
        const input =
            'before\n'
            'ifdef::not-set[]\n'
            'skip\n'
            'these\n'
            'lines\n'
            'ifeval::[1 == 2]\n'
            '{asciidoctor-version}\n'
            'fin\n';

        usingMemoryLogger((logger) {
          final lines = readAll(input, sourcemap: true);
          expect(lines.join('\n'), equals('before'));
          assertMessages(logger, [
            (
              LogSeverity.error,
              '~<stdin>: line 2: detected unterminated preprocessor conditional directive: ifdef::not-set[]',
              true,
            ),
            (
              LogSeverity.error,
              '~<stdin>: line 6: detected unterminated preprocessor conditional directive: ifeval::[1 == 2]',
              true,
            ),
          ]);
        });
      });

      test(
        'should not fail to process preprocessor directive that evaluates to false and has a large number of lines',
        // READER-LEVEL: asserts expanded lines instead of parsed blocks.
        () {
          final bulk = List.filled(5000, 'data').join('\n');
          final input =
              'before\n\nifdef::attribute-not-set[]\n$bulk\nendif::attribute-not-set[]\n\nafter\n';
          expect(
            preprocessorReader(input).readLines(),
            equals(['before', '', '', 'after']),
          );
        },
      );

      test(
        'should not fail to process lines if reader contains a null entry',
        // READER-LEVEL: sets sourceLines[2] directly (the extension hook
        // belongs to the extensions wave); asserts expanded lines instead
        // of parsed blocks.
        () {
          final reader = preprocessorReader(['before', '', '', '', 'after']);
          reader.sourceLines[2] = null;
          expect(reader.readLines(), equals(['before', '', '', '', 'after']));
        },
      );
    });
  });
}
