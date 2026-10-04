/// Tests for the CLI failure rendering (`lib/src/cli/diagnostics.dart`).
library;

import 'dart:io';

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

void main() {
  group('failureLine', () {
    test('prints the message of an AsciidoctorException as is', () {
      expect(
        failureLine(const AsciidoctorException("missing converter for 'x'")),
        equals("asciidoctor: FAILED: missing converter for 'x'"),
      );
    });

    test('drops the type name Dart puts in front of an error', () {
      expect(
        failureLine(StateError('broken')),
        equals('asciidoctor: FAILED: broken'),
      );
      expect(
        failureLine(ArgumentError('bad value')),
        equals('asciidoctor: FAILED: bad value'),
      );
      expect(
        failureLine(UnimplementedError('not yet')),
        equals('asciidoctor: FAILED: not yet'),
      );
      expect(
        failureLine(const FormatException('not a number')),
        equals('asciidoctor: FAILED: not a number'),
      );
    });

    test('adds the path and reason of a file system failure', () {
      expect(
        failureLine(
          const FileSystemException(
            'Cannot open file',
            '/tmp/x.adoc',
            OSError('No such file or directory', 2),
          ),
        ),
        equals(
          'asciidoctor: FAILED: Cannot open file: /tmp/x.adoc '
          '(No such file or directory)',
        ),
      );
      expect(
        failureLine(const FileSystemException('failed to load /a: gone', '/a')),
        equals('asciidoctor: FAILED: failed to load /a: gone'),
      );
    });
  });

  group('isBrokenPipe', () {
    test('recognizes a closed output pipe', () {
      expect(
        isBrokenPipe(
          const FileSystemException('writeFrom failed', '', OSError('', 32)),
        ),
        isTrue,
      );
      expect(
        isBrokenPipe(const StdoutException('write failed', OSError('', 32))),
        isTrue,
      );
    });

    test('rejects other failures', () {
      expect(
        isBrokenPipe(
          const FileSystemException('Cannot open file', '', OSError('', 2)),
        ),
        isFalse,
      );
      expect(isBrokenPipe(const AsciidoctorException('nope')), isFalse);
      expect(isBrokenPipe(StateError('nope')), isFalse);
    });
  });
}
