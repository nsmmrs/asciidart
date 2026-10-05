/// Tests for the embedded `-h` topic files in [HelpTopics].
///
/// The byte-for-byte tests guard the `help_topics.g.dart` contract: each
/// embedded constant must round-trip to the exact bytes of its source file
/// (`man/asciidoctor.1`, `vendor/asciidoctor/data/reference/syntax.adoc`). The fallback tests
/// prove `-h manpage`/`-h syntax` succeed with no checkout files visible.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

/// Finds the repository checkout by walking up to the `man` directory.
///
/// Tests run with the package root (`dart/`) as the working directory.
String findRepoRoot() {
  var dir = Directory.current;
  for (var depth = 0; depth <= 6; depth++) {
    if (Directory('${dir.path}/man').existsSync() &&
        Directory('${dir.path}/vendor/asciidoctor/data').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'repository checkout not found above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
  throw StateError(
    'repository checkout not found above ${Directory.current.path}',
  );
}

/// The repository checkout directory.
final String repoRoot = findRepoRoot();

/// Parses [args] with buffer sinks and a hermetic (empty) environment.
({int? exitCode, String out, String err}) parseCli(List<String> args) {
  final out = StringBuffer();
  final err = StringBuffer();
  final parsed = CliOptions.parseArgs(
    args,
    out: out,
    err: err,
    environment: <String, String>{},
  );
  return (exitCode: parsed.exitCode, out: out.toString(), err: err.toString());
}

void main() {
  group('HelpTopics', () {
    test('embedded manpage equals man/asciidoctor.1 byte-for-byte', () {
      expect(
        utf8.encode(HelpTopics.manpage),
        orderedEquals(File('$repoRoot/man/asciidoctor.1').readAsBytesSync()),
      );
    });

    test('embedded syntax equals syntax.adoc byte-for-byte', () {
      expect(
        utf8.encode(HelpTopics.syntax),
        orderedEquals(
          File('$repoRoot/vendor/asciidoctor/data/reference/syntax.adoc')
              .readAsBytesSync(),
        ),
      );
    });

    test('-h manpage falls back to embedded data outside a checkout', () {
      // No checkout lookup can succeed from the system temp dir, and no
      // override is set, so the embedded copy must be served. The cwd is
      // overridden zone-locally: assigning `Directory.current` would race
      // suites running concurrently in this process.
      final tmp = Directory.systemTemp.createTempSync('help-topics');
      try {
        final result = IOOverrides.runZoned(
          () => parseCli(['-h', 'manpage']),
          getCurrentDirectory: () => tmp,
        );
        expect(result.exitCode, equals(0));
        expect(result.out, contains('.TH "ASCIIDOCTOR"'));
        expect(result.out, contains('Manual: Asciidoctor Manual'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('-h syntax falls back to embedded data outside a checkout', () {
      final tmp = Directory.systemTemp.createTempSync('help-topics');
      try {
        final result = IOOverrides.runZoned(
          () => parseCli(['-h', 'syntax']),
          getCurrentDirectory: () => tmp,
        );
        expect(result.exitCode, equals(0));
        expect(result.out, contains('= AsciiDoc Syntax'));
        expect(result.out, contains('== Text Formatting'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
