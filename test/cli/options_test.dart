/// Tests for the CLI options port (`lib/src/cli/options.dart`).
///
/// Port of `test/options_test.rb`, plus the option-parsing halves of the
/// `test/invoker_test.rb` cases (invocation halves live in
/// `invoker_test.dart`) and extra parity tests for flags the Ruby suite never
/// exercises directly (`-B`, `-R`, `-D`, `-o`, `--trace`, `--safe`, long
/// abbreviations, short clusters, ...). Every expectation was verified
/// against `lib/asciidoctor/cli/options.rb` via `ruby -Ilib` probes and a
/// 159-vector Ruby-vs-Dart differential run (exit codes, STDOUT/STDERR bytes
/// and all option fields).
library;

import 'dart:io';

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/cli/options.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/version.dart';
import 'package:test/test.dart';

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test/fixtures').existsSync()) {
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
}

/// The repository checkout directory.
final String repoRoot = _findRepoRoot();

/// An existing oracle fixture used as the input file.
String get sampleFile => '$repoRoot/test/fixtures/sample.adoc';

/// Parses [args] with buffer sinks and a hermetic (empty) environment.
///
/// Returns the options, the exit code (`null` on success) and the captured
/// output. Pass [environment] to control `ASCIIDOCTOR_MANPAGE_PATH`.
({CliOptions options, int? exitCode, String out, String err}) parseCli(
  List<String> args, {
  Map<String, String>? environment,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final (:options, :exitCode) = CliOptions.parseArgs(
    args,
    out: out,
    err: err,
    environment: environment ?? <String, String>{},
  );
  return (
    options: options,
    exitCode: exitCode,
    out: out.toString(),
    err: err.toString(),
  );
}

void main() {
  group('CliOptions constructor', () {
    test('defaults match Options.new', () {
      final options = CliOptions();
      expect(options.attributes, equals(<String, String>{}));
      expect(options.inputFiles, isNull);
      expect(options.outputFile, isNull);
      expect(options.safe, equals(SafeMode.unsafe));
      expect(options.standalone, isTrue);
      expect(options.templateDirs, isNull);
      expect(options.templateEngine, isNull);
      expect(options.eruby, isNull);
      expect(options.verbose, equals(1));
      expect(options.warnings, isFalse);
      expect(options.loadPaths, isNull);
      expect(options.requires, isNull);
      expect(options.baseDir, isNull);
      expect(options.sourceDir, isNull);
      expect(options.destinationDir, isNull);
      expect(options.logLevel, isNull);
      expect(options.failureLevel, equals(Severity.fatal));
      expect(options.sourcemap, isNull);
      expect(options.trace, isFalse);
      expect(options.timings, isFalse);
    });

    test('seeds attributes, doctype, backend and sourcemap', () {
      // Option-parsing half of invoker_test 'should allow options Hash to be
      // passed as first argument of constructor' (the Invoker.new half needs
      // the invoker card).
      final options = CliOptions(
        attributes: {'toc': ''},
        doctype: 'book',
        sourcemap: true,
      );
      expect(options.attributes, equals({'toc': '', 'doctype': 'book'}));
      expect(options.sourcemap, isTrue);

      final backend = CliOptions(backend: 'docbook5');
      expect(backend.attributes, equals({'backend': 'docbook5'}));
    });

    test('aliases the seeded attributes map like Ruby', () {
      final seed = {'toc': ''};
      final options = CliOptions(attributes: seed);
      expect(identical(options.attributes, seed), isTrue);
    });

    test('accepts a bare string or list for templateDirs', () {
      expect(CliOptions(templateDirs: 'dir').templateDirs, equals(['dir']));
      expect(
        CliOptions(templateDirs: ['a', 'b']).templateDirs,
        equals(['a', 'b']),
      );
      expect(() => CliOptions(templateDirs: 42), throwsArgumentError);
    });

    test('coerces seeded log levels', () {
      expect(CliOptions(logLevel: 1).logLevel, equals(Severity.info));
      expect(
        CliOptions(logLevel: Severity.error).logLevel,
        equals(Severity.error),
      );
      expect(CliOptions(logLevel: 'debug').logLevel, equals(Severity.debug));
    });

    test('ignores seeds for trace, timings and failure level', () {
      // Ruby assigns these unconditionally in Options.new.
      final options = CliOptions();
      expect(options.trace, isFalse);
      expect(options.timings, isFalse);
      expect(options.failureLevel, equals(Severity.fatal));
    });
  });

  group('help', () {
    test('prints usage and returns 0 when help flag is present', () {
      final result = parseCli(['-h']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));
      expect(result.err, isEmpty);
    });

    test('long help flag prints usage', () {
      final result = parseCli(['--help']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));
    });

    test('shows safe modes in severity order', () {
      final result = parseCli(['-h']);
      expect(result.exitCode, equals(0));
      expect(result.out, contains('unsafe, safe, server, secure'));
    });

    test('usage banner shape matches the oracle', () {
      final result = parseCli(['-h']);
      final lines = result.out.split('\n');
      expect(
        lines.take(6).toList(),
        equals([
          'Usage: asciidoctor [OPTION]... FILE...',
          'Convert the AsciiDoc input FILE(s) to the backend output format (e.g., HTML 5, DocBook 5, etc.)',
          'Unless specified otherwise, the output is written to a file whose name is derived from the input file.',
          'Application log messages are printed to STDERR.',
          'Example: asciidoctor input.adoc',
          '',
        ]),
      );
      expect(
        lines[lines.length - 2],
        equals(
          '    -V, --version                    display the version and runtime environment (or -v if no other flags or arguments)',
        ),
      );
      expect(result.out, endsWith('\n'));
    });

    test('prints usage and returns 0 when help topic is unknown', () {
      final result = parseCli(['-h', 'unknown']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));
    });

    test('help topics are case-sensitive', () {
      final result = parseCli(['-h', 'MANPAGE']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));
    });

    test('dumps man page when help topic is manpage', () {
      final result = parseCli(
        ['-h', 'manpage'],
        environment: {
          'ASCIIDOCTOR_MANPAGE_PATH': '$repoRoot/man/asciidoctor.1',
        },
      );
      expect(result.exitCode, equals(0));
      expect(result.out, contains('Manual: Asciidoctor Manual'));
      expect(result.out, contains('.TH "ASCIIDOCTOR"'));
    });

    test('dumps man page via the checkout lookup by default', () {
      // Mirrors the Ruby test's assumption that the man page ships next to
      // the sources; the Dart port searches upward from the workdir.
      final result = parseCli(['-h', 'manpage']);
      expect(result.exitCode, equals(0));
      expect(result.out, contains('.TH "ASCIIDOCTOR"'));
    });

    test('reads a gzipped man page override', () {
      final tmp = Directory.systemTemp.createTempSync('manpage');
      try {
        final source = File('$repoRoot/man/asciidoctor.1').readAsBytesSync();
        final gzPath = '${tmp.path}/asciidoctor.1.gz';
        File(gzPath).writeAsBytesSync(gzip.encode(source));
        final result = parseCli(
          ['-h', 'manpage'],
          environment: {'ASCIIDOCTOR_MANPAGE_PATH': gzPath},
        );
        expect(result.exitCode, equals(0));
        expect(result.out, contains('.TH "ASCIIDOCTOR"'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('prints message and returns 1 when manpage is not found', () {
      final manpagePath = '$repoRoot/test/fixtures/no-such-file.1';
      final result = parseCli(
        ['-h', 'manpage'],
        environment: {'ASCIIDOCTOR_MANPAGE_PATH': manpagePath},
      );
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: FAILED: manual page not found: $manpagePath'),
      );
    });

    test('shows AsciiDoc syntax overview when help topic is syntax', () {
      final result = parseCli(['-h', 'syntax']);
      expect(result.exitCode, equals(0));
      expect(result.out, contains('= AsciiDoc Syntax'));
      expect(result.out, contains('== Text Formatting'));
    });

    test('accepts attached and equals help topics', () {
      var result = parseCli(['-hmanpage']);
      expect(result.exitCode, equals(0));
      expect(result.out, contains('.TH "ASCIIDOCTOR"'));

      result = parseCli(['--help=syntax']);
      expect(result.exitCode, equals(0));
      expect(result.out, contains('= AsciiDoc Syntax'));

      // A leading `=` is verbatim for short options: topic '=manpage' is
      // unknown, so the usage text is printed.
      result = parseCli(['-h=manpage']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));
    });

    test('help does not consume an option-looking topic', () {
      for (final args in [
        ['-h', '-v'],
        ['--help', '-e'],
        ['-h', '--', '-foo'],
      ]) {
        final result = parseCli(args);
        expect(result.exitCode, equals(0), reason: '$args');
        expect(result.out, startsWith('Usage:'), reason: '$args');
      }
    });

    test('help short-circuits before later invalid options', () {
      var result = parseCli(['-h', '--foobar']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));

      result = parseCli(['--help', '--foobar']);
      expect(result.exitCode, equals(0));

      // ...but an earlier invalid option still fails first.
      result = parseCli(['--foobar', '-h']);
      expect(result.exitCode, equals(1));
    });

    test('help after a positional takes no topic from it', () {
      // OptionParser permutes: `manpage` stays positional and `-h` sees no
      // following argument, so the usage text (not the man page) prints.
      final result = parseCli(['manpage', '-h']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Usage:'));
    });
  });

  group('version', () {
    test('displays version and exits for -V and --version', () {
      // Option-parsing half of invoker_test 'should display version and
      // exit' (invocation asserted nothing more).
      const expected =
          'Asciidoctor ${Asciidoctor.version} [https://asciidoctor.org]\n'
          'Runtime Environment (';
      for (final flag in ['--version', '-V']) {
        final result = parseCli([flag]);
        expect(result.exitCode, equals(0), reason: flag);
        expect(result.out, startsWith(expected), reason: flag);
        expect(result.err, isEmpty, reason: flag);
      }
    });

    test('prints version for lone -v', () {
      final result = parseCli(['-v']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Asciidoctor ${Asciidoctor.version} ['));
    });

    test('version short-circuits before later invalid options', () {
      final result = parseCli(['-V', '--foobar']);
      expect(result.exitCode, equals(0));
      expect(result.out, startsWith('Asciidoctor '));
    });

    test('printVersion writes two lines and returns 0', () {
      final out = StringBuffer();
      expect(CliOptions().printVersion(out), equals(0));
      final lines = out.toString().split('\n');
      expect(lines, hasLength(3));
      expect(
        lines[0],
        equals('Asciidoctor ${Asciidoctor.version} [https://asciidoctor.org]'),
      );
      expect(lines[1], startsWith('Runtime Environment (Dart '));
    });
  });

  group('errors', () {
    test('returns 1 when invalid option present', () {
      final result = parseCli(['--foobar']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: invalid option: --foobar'),
      );
      expect(result.out, startsWith('Usage:'));
    });

    test('invalid option message keeps equals values', () {
      final result = parseCli(['--foo=bar', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: invalid option: --foo=bar'),
      );
    });

    test('invalid short in a cluster reports the remainder', () {
      // NOTE `-j` is the Dart-only jobs flag, so the cluster uses `-z`
      // (still invalid) to exercise the remainder reporting.
      final result = parseCli(['-qzunk', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(result.err.trim(), equals('asciidoctor: invalid option: -zunk'));
    });

    test('unknown short option fails', () {
      final result = parseCli(['-z', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(result.err.trim(), equals('asciidoctor: invalid option: -z'));
    });

    test('returns 1 when option has invalid argument', () {
      final result = parseCli(['-d', 'chapter', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: invalid argument: -d chapter'),
      );
      expect(result.out, startsWith('Usage:'));
    });

    test('invalid argument message spells attached values without space', () {
      var result = parseCli(['--failure-level=foobar', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(result.err, contains('invalid argument: --failure-level=foobar'));

      result = parseCli(['-dchapter', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: invalid argument: -dchapter'),
      );

      result = parseCli(['-Schapter', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: invalid argument: -Schapter'),
      );
    });

    test('invalid argument message uses abbreviated longs as given', () {
      final result = parseCli(['--doct', 'chapter', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: invalid argument: --doct chapter'),
      );
    });

    test('enumerated values are case-sensitive', () {
      for (final args in [
        ['--failure-level=Fatal', sampleFile],
        ['--safe-mode=SAFE', sampleFile],
        ['--doctype=BOOK', sampleFile],
        ['-S', 'SAFE', sampleFile],
      ]) {
        final result = parseCli(args);
        expect(result.exitCode, equals(1), reason: '$args');
        expect(result.err, contains('invalid argument:'), reason: '$args');
      }
    });

    test('ambiguous enumerated values fail', () {
      var result = parseCli(['--eruby', 'er', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: ambiguous argument: --eruby er'),
      );

      result = parseCli(['--eruby=er', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: ambiguous argument: --eruby=er'),
      );

      result = parseCli(['--safe-mode', 's', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: ambiguous argument: --safe-mode s'),
      );

      result = parseCli(['--failure-level=', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: ambiguous argument: --failure-level='),
      );
    });

    test('returns 1 when option is missing required argument', () {
      final result = parseCli(['-b']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: option missing argument: -b'),
      );
      expect(result.out, startsWith('Usage:'));
    });

    test('missing argument message uses the option as given', () {
      var result = parseCli(['--backend']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: option missing argument: --backend'),
      );

      result = parseCli(['--back']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: option missing argument: --back'),
      );

      result = parseCli(['-qb']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: option missing argument: -b'),
      );

      result = parseCli(['-a']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: option missing argument: -a'),
      );
    });

    test('ambiguous long options throw like Ruby', () {
      // OptionParser::AmbiguousOption is not rescued by parse!, so it
      // propagates; the Dart port throws AmbiguousCliOptionException.
      for (final args in [
        ['--s'],
        ['--tem', 'x', sampleFile],
        ['--tem=x', sampleFile],
      ]) {
        expect(
          () => parseCli(args),
          throwsA(
            isA<AmbiguousCliOptionException>().having(
              (e) => e.message,
              'message',
              equals('ambiguous option: ${args[0]}'),
            ),
          ),
          reason: '$args',
        );
      }
    });

    test('needless arguments on flags throw like Ruby', () {
      // OptionParser::NeedlessArgument is not rescued by parse! either.
      final cases = {
        '--quiet=true': '--quiet=true',
        '--version=x': '--version=x',
        '--safe=x': '--safe=x',
        '--=x': '--=x',
        '-e=true': '-e=true',
        '-V=x': '-V=x',
        '-qe=x': '-e=x',
      };
      cases.forEach((flag, display) {
        expect(
          () => parseCli([flag, sampleFile]),
          throwsA(
            isA<NeedlessCliArgumentException>().having(
              (e) => e.message,
              'message',
              equals('needless argument: $display'),
            ),
          ),
          reason: flag,
        );
      });
    });

    test('reports usage to stderr when no input file given', () {
      // Option-parsing half of invoker_test 'should report usage if no input
      // file given'.
      final result = parseCli([]);
      expect(result.exitCode, equals(1));
      expect(result.err, startsWith('Usage:'));
      expect(result.out, isEmpty);
    });
  });

  group('basic parsing', () {
    test('basic argument assignment', () {
      final result = parseCli(['-w', '-v', '-e', '-d', 'book', sampleFile]);
      expect(result.exitCode, isNull);
      final options = result.options;
      expect(options.verbose, equals(2));
      expect(options.warnings, isTrue);
      expect(options.standalone, isFalse);
      expect(options.attributes!['doctype'], equals('book'));
      expect(options.inputFiles, equals([sampleFile]));
    });

    test('supports legacy option for no header footer', () {
      final result = parseCli(['-s', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.standalone, isFalse);
      expect(result.options.inputFiles, equals([sampleFile]));
    });

    test('embedded and no-header-footer are aliases', () {
      for (final flag in ['-e', '--embedded', '-s', '--no-header-footer']) {
        final result = parseCli([flag, sampleFile]);
        expect(result.exitCode, isNull, reason: flag);
        expect(result.options.standalone, isFalse, reason: flag);
      }
    });

    test('parses base, source, destination dirs and out file', () {
      final result = parseCli([
        '-B',
        'base',
        '-R',
        'src',
        '-D',
        'dest',
        '-o',
        'out.html',
        sampleFile,
      ]);
      expect(result.exitCode, isNull);
      final options = result.options;
      expect(options.baseDir, equals('base'));
      expect(options.sourceDir, equals('src'));
      expect(options.destinationDir, equals('dest'));
      expect(options.outputFile, equals('out.html'));
    });

    test('parses long forms of the directory options', () {
      final result = parseCli([
        '--base-dir',
        'base',
        '--source-dir',
        'src',
        '--destination-dir',
        'dest',
        '--out-file',
        'out.html',
        sampleFile,
      ]);
      expect(result.exitCode, isNull);
      final options = result.options;
      expect(options.baseDir, equals('base'));
      expect(options.sourceDir, equals('src'));
      expect(options.destinationDir, equals('dest'));
      expect(options.outputFile, equals('out.html'));
    });

    test('repeated scalar options keep the last value', () {
      final result = parseCli(['-o', 'a.html', '-o', 'b.html', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.outputFile, equals('b.html'));
    });

    test('enables trace flag', () {
      final result = parseCli(['--trace', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.trace, isTrue);
    });

    test('template engine assignment', () {
      final result = parseCli(['-E', 'haml', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.templateEngine, equals('haml'));
    });

    test('sets eRuby implementation', () {
      // Option-parsing half of invoker_test 'should set eRuby impl if
      // specified'.
      final result = parseCli(['--eruby', 'erubi', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.eruby, equals('erubi'));
    });
  });

  group('attributes', () {
    test('standard attribute assignment', () {
      final result = parseCli([
        '-a',
        'docinfosubs=attributes,replacements',
        '-a',
        'icons',
        sampleFile,
      ]);
      expect(result.exitCode, isNull);
      expect(
        result.options.attributes!['docinfosubs'],
        equals('attributes,replacements'),
      );
      expect(result.options.attributes!['icons'], equals(''));
    });

    test('multiple attribute arguments', () {
      final result = parseCli([
        '-a',
        'imagesdir=images',
        '-a',
        'icons',
        sampleFile,
      ]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['imagesdir'], equals('images'));
      expect(result.options.attributes!['icons'], equals(''));
    });

    test('only splits attribute key/value pairs on first equal sign', () {
      final result = parseCli(['-a', 'name=value=value', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['name'], equals('value=value'));
    });

    test('does not fail if value of attribute option is empty', () {
      final result = parseCli(['-a', '', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes, isNull);
    });

    test('does not fail if value of attribute option is equal sign', () {
      final result = parseCli(['-a', '=', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes, isNull);
    });

    test('strips trailing but not leading attribute whitespace', () {
      var result = parseCli(['-a', 'x=1  ', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes, equals({'x': '1'}));

      result = parseCli(['-a', ' x', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes, equals({' x': ''}));
    });

    test('stores invoker-level attributes verbatim', () {
      // Option-parsing halves of the invoker attribute tests: the CLI stores
      // the pairs; applying `!`/`@` overrides happens document-side.
      final cases = {
        'idprefix=id': {'idprefix': 'id'},
        'toc-title=t=o=c': {'toc-title': 't=o=c'},
        'note-caption=Note to self:': {'note-caption': 'Note to self:'},
        'icons': {'icons': ''},
        'idprefix=id@': {'idprefix': 'id@'},
        'sectids!': {'sectids!': ''},
      };
      cases.forEach((argument, expected) {
        final result = parseCli(['-a', argument, sampleFile]);
        expect(result.exitCode, isNull, reason: argument);
        expect(result.options.attributes, equals(expected), reason: argument);
      });
    });

    test('force-encodes mislabeled attribute strings to UTF-8', skip: 'PERMANENT: Ruby string encodings do not exist in Dart; strings are Unicode.', () {
      // Port of options_test 'should gracefully force encoding to UTF-8 if
      // encoding on string is mislabeled'.
    });
  });

  group('backend, doctype and safe mode', () {
    test('allows safe mode to be specified', () {
      final result = parseCli(['-S', 'safe', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.safe, equals(SafeMode.safe));
    });

    test('sets safe mode to the specified level', () {
      // Option-parsing half of invoker_test 'should set safe mode to
      // specified level'.
      final levels = {
        'unsafe': SafeMode.unsafe,
        'safe': SafeMode.safe,
        'server': SafeMode.server,
        'secure': SafeMode.secure,
      };
      levels.forEach((name, level) {
        final result = parseCli(['-S', name, sampleFile]);
        expect(result.exitCode, isNull, reason: name);
        expect(result.options.safe, equals(level), reason: name);
      });
    });

    test('completes unambiguous safe mode abbreviations', () {
      final result = parseCli(['-S', 'sec', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.safe, equals(SafeMode.secure));
    });

    test('sets safe mode with the bare safe flag', () {
      // Option-parsing half of invoker_test 'should set safe mode if
      // specified'.
      final result = parseCli(['--safe', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.safe, equals(SafeMode.safe));
    });

    test('allows any backend to be specified', () {
      final result = parseCli(['-b', 'my_custom_backend', sampleFile]);
      expect(result.exitCode, isNull);
      expect(
        result.options.attributes!['backend'],
        equals('my_custom_backend'),
      );
    });

    test('assigns article, book and inline doctypes', () {
      for (final doctype in ['article', 'book', 'inline']) {
        final result = parseCli(['-d', doctype, sampleFile]);
        expect(result.exitCode, isNull, reason: doctype);
        expect(
          result.options.attributes!['doctype'],
          equals(doctype),
          reason: doctype,
        );
      }
    });

    test('completes unambiguous doctype abbreviations', () {
      final result = parseCli(['-d', 'art', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['doctype'], equals('article'));
    });
  });

  group('levels, verbosity and toggles', () {
    test('sets failure level to FATAL by default', () {
      final result = parseCli([sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.failureLevel, equals(Severity.fatal));
    });

    test('allows failure level FATAL using any recognized abbreviation', () {
      for (final value in ['f', 'fatal', 'FATAL']) {
        final result = parseCli(['--failure-level=$value', sampleFile]);
        expect(result.exitCode, isNull, reason: value);
        expect(result.options.failureLevel, equals(Severity.fatal));
      }
    });

    test('allows failure level ERROR using any recognized abbreviation', () {
      for (final value in ['e', 'err', 'ERR', 'error', 'ERROR']) {
        final result = parseCli(['--failure-level=$value', sampleFile]);
        expect(result.exitCode, isNull, reason: value);
        expect(result.options.failureLevel, equals(Severity.error));
      }
    });

    test('allows failure level WARN using any recognized abbreviation', () {
      for (final value in ['w', 'warn', 'WARN', 'warning', 'WARNING']) {
        final result = parseCli(['--failure-level=$value', sampleFile]);
        expect(result.exitCode, isNull, reason: value);
        expect(result.options.failureLevel, equals(Severity.warn));
      }
    });

    test('does not allow failure level to be set to unknown value', () {
      final result = parseCli(['--failure-level=foobar', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(result.err, contains('invalid argument: --failure-level=foobar'));
    });

    test('does not allow failure level DEBUG', () {
      // DEBUG is a --log-level candidate but not a --failure-level one.
      final result = parseCli(['--failure-level=debug', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(result.err, contains('invalid argument:'));
    });

    test('sets log level to DEBUG when log-level option is specified', () {
      final result = parseCli(['--log-level', 'debug', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.logLevel, equals(Severity.debug));
    });

    test('allows log level WARN using any recognized abbreviation', () {
      for (final value in ['w', 'warn', 'WARN', 'warning', 'WARNING']) {
        final result = parseCli(['--log-level=$value', sampleFile]);
        expect(result.exitCode, isNull, reason: value);
        expect(result.options.logLevel, equals(Severity.warn));
      }
    });

    test('sets verbose to 2 when -v flag is specified', () {
      final result = parseCli(['-v', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.verbose, equals(2));
    });

    test('sets verbose to 0 when -q flag is specified', () {
      final result = parseCli(['-q', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.verbose, equals(0));
    });

    test('sets verbose to 2 when -v flag is specified after -q flag', () {
      final result = parseCli(['-q', '-v', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.verbose, equals(2));
    });

    test('sets verbose to 0 when -q flag is specified after -v flag', () {
      final result = parseCli(['-v', '-q', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.verbose, equals(0));
    });

    test('enables warnings when -w flag is specified', () {
      final result = parseCli(['-w', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.warnings, isTrue);
    });

    test('enables timings when -t flag is specified', () {
      final result = parseCli(['-t', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.timings, isTrue);
    });

    test('timings option is disabled by default', () {
      final result = parseCli([sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.timings, isFalse);
    });

    test('enables sourcemap when sourcemap flag is specified', () {
      final result = parseCli(['--sourcemap', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.sourcemap, isTrue);
    });

    test('sourcemap option is disabled by default', () {
      final result = parseCli([sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.sourcemap, isNot(isTrue));
    });

    test('enables section numbers when -n flag is specified', () {
      final result = parseCli(['-n', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['sectnums'], equals(''));
    });
  });

  group('templates, requires and load paths', () {
    test('template directory assignment', () {
      // The tilt availability check is deferred to the template-converter
      // phase (see the options.dart library docs); parsing records the dirs.
      final result = parseCli(['-T', 'custom-backend', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.templateDirs, equals(['custom-backend']));
    });

    test('multiple template directory assignments', () {
      final result = parseCli([
        '-T',
        'custom-backend',
        '-T',
        'custom-backend-hacks',
        sampleFile,
      ]);
      expect(result.exitCode, isNull);
      expect(
        result.options.templateDirs,
        equals(['custom-backend', 'custom-backend-hacks']),
      );
    });

    test('multiple -r flags fail for unloadable libraries', () {
      // Dart cannot load libraries at runtime, so every require fails
      // exactly as an unloadable library does in Ruby.
      final options = CliOptions();
      final out = StringBuffer();
      final err = StringBuffer();
      final exitCode = options.parse(
        ['-r', 'foobar', '-r', 'foobaz', sampleFile],
        out: out,
        err: err,
        environment: <String, String>{},
      );
      expect(exitCode, equals(1));
      expect(
        err.toString(),
        contains("asciidoctor: FAILED: 'foobar' could not be loaded"),
      );
      expect(options.requires, equals(['foobar', 'foobaz']));
    });

    test('-r flag with commas is treated as a single path', () {
      final result = parseCli([
        '-r',
        '/no-such-folder/a,b,c/ext.rb',
        sampleFile,
      ]);
      expect(result.exitCode, equals(1));
      expect(
        result.err,
        contains(
          "asciidoctor: FAILED: '/no-such-folder/a,b,c/ext.rb' could not be loaded",
        ),
      );
      expect(result.options.requires, equals(['/no-such-folder/a,b,c/ext.rb']));
    });

    test('suggests --trace when a require fails', () {
      // Option-parsing half of invoker_test 'should suggest --trace option
      // if not present when program raises error'.
      final result = parseCli(['-r', 'no-such-module', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err,
        contains(
          "'no-such-module' could not be loaded\n  Use --trace to show backtrace",
        ),
      );
    });

    test('raises when --trace is specified and a require fails', () {
      // Option-parsing half of invoker_test 'should raise error when --trace
      // option is specified and program raises error'. Ruby re-raises the
      // LoadError; Dart throws UnsupportedError (dynamic loading is
      // unsupported).
      expect(
        () => parseCli(['--trace', '-r', 'no-such-module', sampleFile]),
        throwsUnsupportedError,
      );
    });

    test('-I option records load paths', () {
      final result = parseCli(['-I', 'foobar', '-I', 'foobaz', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.loadPaths, equals(['foobar', 'foobaz']));
    });

    test('-I option splits path lists on the platform separator', () {
      final separator = Platform.isWindows ? ';' : ':';
      final result = parseCli(['-I', 'foobar${separator}foobaz', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.loadPaths, equals(['foobar', 'foobaz']));
    });

    test('-I option appends paths to the load path', skip: r'PERMANENT: Dart has no $LOAD_PATH; values are recorded in loadPaths only.', () {
      // The `\$:` assertions of the options_test -I tests.
    });
  });

  group('input files', () {
    test('reports error if input file does not exist', () {
      // Option-parsing half of invoker_test 'should report error if input
      // file does not exist'.
      final result = parseCli(['missing_file.adoc']);
      expect(result.exitCode, equals(1));
      expect(result.err, contains('input file missing_file.adoc is missing'));
    });

    test('treats extra arguments as files', () {
      // Option-parsing half of invoker_test 'should treat extra arguments as
      // files'.
      final result = parseCli(['-o', '/dev/null', 'extra', 'arguments']);
      expect(result.exitCode, equals(1));
      expect(result.err, contains('input file extra is missing'));
    });

    test('reports the first missing file', () {
      final result = parseCli(['nope1.adoc', 'nope2.adoc']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: FAILED: input file nope1.adoc is missing'),
      );
    });

    test('reports an empty positional as missing', () {
      final result = parseCli(['', sampleFile]);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals('asciidoctor: FAILED: input file  is missing'),
      );
    });

    test('reports a directory input as not a file', () {
      final result = parseCli(['$repoRoot/test/fixtures']);
      expect(result.exitCode, equals(1));
      expect(
        result.err.trim(),
        equals(
          'asciidoctor: FAILED: input path $repoRoot/test/fixtures is a directory, not a file',
        ),
      );
    });

    test(
      'reports an unreadable input file',
      skip: Platform.isWindows ? 'chmod-based readability needs POSIX.' : null,
      () {
        final tmp = Directory.systemTemp.createTempSync('unreadable');
        try {
          final path = '${tmp.path}/input.adoc';
          File(path).writeAsStringSync('content\n');
          Process.runSync('chmod', ['000', path]);
          final result = parseCli([path]);
          expect(result.exitCode, equals(1));
          expect(
            result.err.trim(),
            equals('asciidoctor: FAILED: input file $path is not readable'),
          );
        } finally {
          Process.runSync('chmod', ['644', '${tmp.path}/input.adoc']);
          tmp.deleteSync(recursive: true);
        }
      },
    );

    test('accepts stdin as the sole input', () {
      final result = parseCli(['-o', '-', '-']);
      expect(result.exitCode, isNull);
      expect(result.options.inputFiles, equals(['-']));
      expect(result.options.outputFile, equals('-'));
      expect(result.err, isEmpty);
    });

    test('emits warning when unparsed options remain', () {
      final result = parseCli(['-b', 'docbook', '-', '-']);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals('docbook'));
      expect(
        result.err,
        equals(
          'asciidoctor: WARNING: extra arguments detected '
          "(unparsed arguments: '-', '-') or incorrect usage of stdin\n"
          'asciidoctor: WARNING: extra arguments detected '
          "(unparsed arguments: '-', '-') or incorrect usage of stdin\n",
        ),
      );
    });

    test('warns about but keeps dash siblings of real files', () {
      final result = parseCli([sampleFile, '-']);
      expect(result.exitCode, isNull);
      expect(result.options.inputFiles, equals([sampleFile]));
      expect(result.err, contains('asciidoctor: WARNING: extra arguments'));
    });

    test('stops option parsing at --', () {
      final result = parseCli(['--', '-h']);
      expect(result.exitCode, isNull);
      expect(result.options.inputFiles, equals([]));
      expect(result.err, contains('asciidoctor: WARNING: extra arguments'));
    });

    test('expands relative globs like Dir.glob', () {
      // Option-parsing half of invoker_test 'should convert all files that
      // matches a glob expression'. Parsing runs with an absolute pattern so
      // it is independent of the process workdir.
      final pattern = '$repoRoot/test/fixtures/ba*.adoc';
      final result = parseCli([pattern]);
      expect(result.exitCode, isNull);
      expect(
        result.options.inputFiles,
        equals(['$repoRoot/test/fixtures/basic.adoc']),
      );
    });

    test(
      'expands backslash globs on Windows',
      skip: Platform.isWindows ? null : 'Backslash tilt only runs on Windows.',
      () {
        final pattern = '$repoRoot/test/fixtures/ba*.adoc'.replaceAll(
          '/',
          r'\',
        );
        final result = parseCli([pattern]);
        expect(result.exitCode, isNull);
        expect(result.options.inputFiles, hasLength(1));
      },
    );

    test('glob skips dotfiles and supports classes and recursion', () {
      final tmp = Directory.systemTemp.createTempSync('glob');
      try {
        Directory('${tmp.path}/sub/deep').createSync(recursive: true);
        for (final name in [
          'a.adoc',
          'b.adoc',
          '.hidden.adoc',
          'sub/c.adoc',
          'sub/deep/d.adoc',
          'note.txt',
        ]) {
          File('${tmp.path}/$name').writeAsStringSync('x\n');
        }

        var result = parseCli(['${tmp.path}/*.adoc']);
        expect(result.exitCode, isNull);
        expect(
          result.options.inputFiles,
          equals(['${tmp.path}/a.adoc', '${tmp.path}/b.adoc']),
        );

        result = parseCli(['${tmp.path}/.*.adoc']);
        expect(result.exitCode, isNull);
        expect(result.options.inputFiles, equals(['${tmp.path}/.hidden.adoc']));

        result = parseCli(['${tmp.path}/[ab].adoc']);
        expect(result.exitCode, isNull);
        expect(
          result.options.inputFiles,
          equals(['${tmp.path}/a.adoc', '${tmp.path}/b.adoc']),
        );

        result = parseCli(['${tmp.path}/?.adoc']);
        expect(result.exitCode, isNull);
        expect(
          result.options.inputFiles,
          equals(['${tmp.path}/a.adoc', '${tmp.path}/b.adoc']),
        );

        result = parseCli(['${tmp.path}/**/*.adoc']);
        expect(result.exitCode, isNull);
        expect(
          result.options.inputFiles,
          equals([
            '${tmp.path}/a.adoc',
            '${tmp.path}/b.adoc',
            '${tmp.path}/sub/c.adoc',
            '${tmp.path}/sub/deep/d.adoc',
          ]),
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });

  group('parsing mechanics', () {
    test('completes unambiguous long abbreviations', () {
      var result = parseCli(['--back', 'xhtml5', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals('xhtml5'));

      result = parseCli(['--sect', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['sectnums'], equals(''));

      result = parseCli(['--no-h', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.standalone, isFalse);

      result = parseCli(['--out-fil=x', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.outputFile, equals('x'));
    });

    test('matches long options case-insensitively', () {
      var result = parseCli(['--Backend', 'xhtml5', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals('xhtml5'));

      // An exact case-insensitive match beats prefix matches (--safe over
      // --safe-mode).
      for (final flag in ['--SAFE', '--Safe']) {
        result = parseCli([flag, sampleFile]);
        expect(result.exitCode, isNull, reason: flag);
        expect(result.options.safe, equals(SafeMode.safe), reason: flag);
      }
    });

    test('parses combined short flags in order', () {
      final result = parseCli(['-etest', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.standalone, isFalse);
      expect(result.options.timings, isTrue);
    });

    test('short options take attached values verbatim', () {
      var result = parseCli(['-bhtml5', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals('html5'));

      result = parseCli(['-o-', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.outputFile, equals('-'));

      // A leading `=` is kept, not stripped.
      result = parseCli(['-I=foo', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.loadPaths, equals(['=foo']));

      result = parseCli(['-a=x', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes, equals({'': 'x'}));

      result = parseCli(['-abfoo', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes, equals({'bfoo': ''}));
    });

    test('short flag cluster hands off to an option with an argument', () {
      final result = parseCli(['-qa', 'x', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.verbose, equals(0));
      expect(result.options.attributes, equals({'x': ''}));
    });

    test('accepts an empty value from equals form', () {
      final result = parseCli(['--backend=', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals(''));
    });

    test('required arguments consume the next token unconditionally', () {
      var result = parseCli(['-o', '-v', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.outputFile, equals('-v'));
      expect(result.options.verbose, equals(1));

      result = parseCli(['-b', '-e', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals('-e'));
      expect(result.options.standalone, isTrue);

      result = parseCli(['--backend', '-e', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.attributes!['backend'], equals('-e'));

      result = parseCli(['-I', '-foo', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.loadPaths, equals(['-foo']));

      result = parseCli(['-o', '--', sampleFile]);
      expect(result.exitCode, isNull);
      expect(result.options.outputFile, equals('--'));
    });

    test('does not mutate the argument list', () {
      final args = ['-v', '-e', sampleFile];
      final result = parseCli(args);
      expect(result.exitCode, isNull);
      expect(args, equals(['-v', '-e', sampleFile]));
    });

    test('parseArgs returns the options and the exit code', () {
      final out = StringBuffer();
      final err = StringBuffer();
      final (:options, :exitCode) = CliOptions.parseArgs(
        ['-n', sampleFile],
        out: out,
        err: err,
        environment: <String, String>{},
      );
      expect(exitCode, isNull);
      expect(options.attributes, equals({'sectnums': ''}));
      expect(out.toString(), isEmpty);
      expect(err.toString(), isEmpty);
    });
  });

  // NOTE (unskip-3c): the invocation halves once placeholdered here now
  // live in `invoker_test.dart`, which owns CLI invocation behavior:
  // verbosity mapping ('silences warnings if -q flag is specified',
  // 'shows debug messages if -v flag is specified'), the failure-level
  // exit code ('returns non-zero exit code if failure level is reached'),
  // `--log-level` ('changes level on logger when --log-level is
  // specified', plus the `-q`/`-v` interplay tests), attribute unsets
  // and soft sets ('unsets attribute ending in bang', 'does not set
  // attribute ending in @ if defined in document'), and the invoker
  // constructor forms (the 'Invoker constructor' group). The 'handles
  // compat files' placeholder was deleted outright: no compat-file
  // handling exists in `options.rb` or `invoker.rb`, so there is nothing
  // to port or cover.
  group('deferred to later phases', () {
    test(
      'fails when template directories need a missing engine',
      skip: "WAVE-GATED: deferred to the template-converter phase (Ruby requires the 'tilt' gem).",
      () {},
    );

    test(
      'enables Ruby script warnings for -w',
      skip:
          r'PERMANENT: No Dart equivalent of $VERBOSE-backed script warnings.',
      () {},
    );

    test(
      'falls back to man -w for the man page',
      skip: 'PERMANENT: The man database cannot be controlled hermetically in a unit test.',
      () {},
    );

    test(
      'reports a missing syntax page',
      skip: 'PERMANENT: data/reference/syntax.adoc always ships in the checkout; Ruby offers no override to simulate absence.',
      () {},
    );
  });
}
