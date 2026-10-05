/// Tests for the CLI failure rendering (`lib/src/cli/diagnostics.dart`).
library;

import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('failureLine', () {
    test('prints the message of an AsciidoctorException as is', () {
      expect(
        failureLine(const AsciidoctorException("missing converter for 'x'")),
        equals("asciidart: FAILED: missing converter for 'x'"),
      );
    });

    test('drops the type name Dart puts in front of an error', () {
      expect(
        failureLine(StateError('broken')),
        equals('asciidart: FAILED: broken'),
      );
      expect(
        failureLine(ArgumentError('bad value')),
        equals('asciidart: FAILED: bad value'),
      );
      expect(
        failureLine(UnimplementedError('not yet')),
        equals('asciidart: FAILED: not yet'),
      );
      expect(
        failureLine(const FormatException('not a number')),
        equals('asciidart: FAILED: not a number'),
      );
    });

    test('adds the path and reason of a file system failure', () {
      expect(
        failureLine(
          const io.IoException(
            'Cannot open file',
            path: '/tmp/x.adoc',
            reason: 'No such file or directory',
            errorCode: 2,
          ),
        ),
        equals(
          'asciidart: FAILED: Cannot open file: /tmp/x.adoc '
          '(No such file or directory)',
        ),
      );
      expect(
        failureLine(
          const io.IoException('failed to load /a: gone', path: '/a'),
        ),
        equals('asciidart: FAILED: failed to load /a: gone'),
      );
    });
  });

  group('isBrokenPipe', () {
    test('recognizes a closed pipe reported by the seam', () {
      expect(
        io.isBrokenPipe(const io.IoException('write failed', errorCode: 32)),
        isTrue,
      );
    });

    test(testOn: 'vm', 'recognizes a closed output pipe', () {
      expect(
        io.isBrokenPipe(
          const FileSystemException('writeFrom failed', '', OSError('', 32)),
        ),
        isTrue,
      );
      expect(
        io.isBrokenPipe(const StdoutException('write failed', OSError('', 32))),
        isTrue,
      );
    });

    test('rejects other failures', () {
      expect(
        io.isBrokenPipe(const io.IoException('Cannot open file', errorCode: 2)),
        isFalse,
      );
      expect(io.isBrokenPipe(const AsciidoctorException('nope')), isFalse);
      expect(io.isBrokenPipe(StateError('nope')), isFalse);
    });
  });
}
