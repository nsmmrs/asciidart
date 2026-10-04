/// Tests for the writer port (`lib/src/writer.dart`).
///
/// Ruby ships no dedicated writer tests, so these are direct behavioral
/// tests; every expectation was verified against `lib/asciidoctor/writer.rb`
/// via `ruby -Ilib -e` probes (see the wave report).
library;

import 'dart:io';

import 'package:asciidoctor/src/writer.dart';
import 'package:test/test.dart';

/// A converter mixing in [Writer].
class TestConverter with Writer;

/// A converter mixing in [VoidWriter].
class VoidConverter with VoidWriter;

void main() {
  group('Writer', () {
    test('writes chomped output plus a newline to a stream', () {
      final buffer = StringBuffer();
      TestConverter().write('hello', buffer);
      expect(buffer.toString(), equals('hello\n'));
    });

    test('chomps exactly one trailing line break before writing', () {
      String write(String output) {
        final buffer = StringBuffer();
        TestConverter().write(output, buffer);
        return buffer.toString();
      }

      expect(write('a\n'), equals('a\n'));
      expect(write('a\n\n'), equals('a\n\n'));
      expect(write('a\r\n'), equals('a\n'));
      expect(write('a\r'), equals('a\n'));
      expect(write('a'), equals('a\n'));
      expect(write(''), equals('\n'));
    });

    test('writes output verbatim to a file path', () {
      final dir = Directory.systemTemp.createTempSync(
        'asciidoctor-writer-test',
      );
      try {
        final path = '${dir.path}${Platform.pathSeparator}out.html';
        TestConverter().write('file-out', path);
        expect(File(path).readAsStringSync(), equals('file-out'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('writes output verbatim to a File', () {
      final dir = Directory.systemTemp.createTempSync(
        'asciidoctor-writer-test',
      );
      try {
        final file = File('${dir.path}${Platform.pathSeparator}out.html');
        TestConverter().write('no-newline', file);
        expect(file.readAsStringSync(), equals('no-newline'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('rejects targets that are neither sinks nor files', () {
      expect(() => TestConverter().write('x', 42), throwsArgumentError);
    });
  });

  group('VoidWriter', () {
    test('leaves streams untouched', () {
      final buffer = StringBuffer();
      VoidConverter().write('x', buffer);
      expect(buffer.toString(), isEmpty);
    });

    test('leaves existing files untouched', () {
      final dir = Directory.systemTemp.createTempSync(
        'asciidoctor-writer-test',
      );
      try {
        final path = '${dir.path}${Platform.pathSeparator}out.html';
        File(path).writeAsStringSync('');
        VoidConverter().write('x', path);
        expect(File(path).readAsStringSync(), isEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('creates no file for a missing path', () {
      final dir = Directory.systemTemp.createTempSync(
        'asciidoctor-writer-test',
      );
      try {
        final path = '${dir.path}${Platform.pathSeparator}missing.html';
        VoidConverter().write('x', path);
        expect(File(path).existsSync(), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
