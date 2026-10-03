/// Tests for the CLI invoker port (`lib/src/cli/invoker.dart`).
///
/// Port of `test/invoker_test.rb` (the invocation halves; option-parsing
/// halves already live in `options_test.dart`). Adaptations: XPath/CSS
/// assertions become substring checks (no Nokogiri equivalent), file outputs
/// go to temp directories instead of `test/fixtures` where the behavior
/// allows it, and Ruby's `invoke_cli` / `invoke_cli_to_buffer` / global
/// `$stdout` swapping collapses into [invokeCli], which always buffers and
/// installs a temporary logger on the error buffer (cf. Ruby's
/// `redirect_streams`). Tests with no Dart analog are `skip()`ped with a
/// `PERMANENT:` reason; tests awaiting a later wave keep a `WAVE-GATED:`
/// reason with their ported bodies intact.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/cli/invoker.dart';
import 'package:asciidoctor/src/cli/options.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/version.dart';
import 'package:test/test.dart';

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/dart/pubspec.yaml').existsSync() &&
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

/// Resolves [name] under `test/fixtures`.
String fixturePath(String name) => '$repoRoot/test/fixtures/$name';

/// An existing oracle fixture used as the default input file.
String get sampleFile => fixturePath('sample.adoc');

/// Invokes the CLI like Ruby's `invoke_cli` / `invoke_cli_to_buffer`.
///
/// [argv] plus [filename] (`-` and absolute paths pass through, other names
/// resolve under `test/fixtures`, `null` passes no file) are parsed and
/// invoked with all output buffered; [stdin] supplies stdin input (cf. the
/// Ruby block form). A temporary logger on the error buffer is installed
/// around the invocation (cf. Ruby's `redirect_streams`) and restored after.
Invoker invokeCli(
  List<String> argv, [
  String? filename = 'sample.adoc',
  String Function()? stdin,
]) {
  final out = StringBuffer();
  final err = StringBuffer();
  final filepath =
      filename == null || filename == '-' || File(filename).isAbsolute
      ? filename
      : fixturePath(filename);
  final invoker = Invoker.fromArgs(
    [...argv, if (filepath != null) filepath],
    out: out,
    err: err,
    environment: <String, String>{},
  );
  invoker.redirectStreams(out, err);
  final savedLogger = LoggerManager.logger;
  LoggerManager.logger = Logger(logdev: err)..level = savedLogger.level;
  try {
    invoker.invoke(stdinSource: stdin);
  } finally {
    LoggerManager.logger = savedLogger;
  }
  return invoker;
}

/// Invokes the CLI like Ruby's `invoke_cli_to_buffer` (an alias here:
/// [invokeCli] always buffers).
Invoker invokeCliToBuffer(
  List<String> argv, [
  String? filename = 'sample.adoc',
  String Function()? stdin,
]) => invokeCli(argv, filename, stdin);

/// Invokes the CLI with several input files, like Ruby's
/// `invoke_cli_with_filenames`.
Invoker invokeCliWithFilenames(List<String> argv, List<String> filenames) {
  return invokeCli([
    ...argv,
    ...filenames.map(
      (name) => File(name).isAbsolute ? name : fixturePath(name),
    ),
  ], null);
}

/// Writes `pipe content` to the fifo at `args[0]`, then signals `args[1]`.
///
/// Top-level entry point for the writer isolate in the named-pipe test.
/// Opens [FileMode.writeOnly] (`O_WRONLY`): the default write mode opens
/// `O_RDWR`, which succeeds instantly on a fifo without rendezvous, so a
/// writer that wins the race would come and go before the reader opens and
/// leave the reader blocked forever.
void _writePipe(List<Object> args) {
  final raf = File(args[0] as String).openSync(mode: FileMode.writeOnly);
  raf.writeStringSync('pipe content');
  raf.closeSync();
  (args[1] as SendPort).send(null);
}

/// Runs the real CLI binary in a subprocess, like Ruby's `run_command`.
Future<ProcessResult> runCli(
  List<String> args, {
  Map<String, String>? environment,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    ['bin/asciidoctor.dart', ...args],
    workingDirectory: '$repoRoot/dart',
    environment: environment,
  );
}

/// Copies the fixture [name] into [dir] and returns the copy's path.
String copyFixtureTo(String name, Directory dir) {
  final copy = File('${dir.path}/$name')
    ..writeAsStringSync(File(fixturePath(name)).readAsStringSync());
  return copy.path;
}

void main() {
  group('Invoker constructor', () {
    test('allows CliOptions to be passed as first argument of constructor', () {
      final opts = CliOptions(
        attributes: {'toc': ''},
        doctype: 'book',
        sourcemap: true,
      );
      final invoker = Invoker.fromOptions(opts);
      expect(identical(invoker.options, opts), isTrue);
    });

    test(
      'allows options map to be passed as first argument of constructor',
      () {
        final map = <String, Object?>{
          'attributes': {'toc': ''},
          'doctype': 'book',
          'sourcemap': true,
        };
        final invoker = Invoker.fromMap(map);
        final resolvedOpts = invoker.options!;
        expect(resolvedOpts.attributes!['toc'], equals(''));
        expect(resolvedOpts.attributes!['doctype'], equals('book'));
        expect(resolvedOpts.sourcemap, isTrue);
      },
    );

    test(
      'parses options from list passed as first argument of constructor',
      () {
        final invoker = Invoker.fromArgs([
          '-s',
          sampleFile,
        ], environment: <String, String>{});
        final resolvedOptions = invoker.options!;
        expect(resolvedOptions.standalone, isFalse);
        expect(resolvedOptions.inputFiles, equals([sampleFile]));
      },
    );

    test('parses options from multiple arguments passed to constructor', () {
      // Dart has a single list form (no splat); the whole argv travels as
      // one list, matching Ruby's flattened `*options`.
      final invoker = Invoker.fromArgs([
        '-s',
        sampleFile,
      ], environment: <String, String>{});
      final resolvedOptions = invoker.options!;
      expect(resolvedOptions.standalone, isFalse);
      expect(resolvedOptions.inputFiles, equals([sampleFile]));
    });
  });

  group('version and usage', () {
    test('displays version and exits', () {
      final expected =
          'Asciidoctor ${Asciidoctor.version} [https://asciidoctor.org]\n'
          'Runtime Environment (Dart ';
      for (final flag in ['--version', '-V']) {
        final invoker = invokeCliToBuffer([flag]);
        expect(invoker.code, equals(0));
        expect(invoker.readOutput(), startsWith(expected));
      }
    });

    test('reports usage if no input file given', () {
      final invoker = invokeCli([], null);
      expect(invoker.readError(), contains('Usage:'));
      expect(invoker.code, equals(1));
    });

    test('reports error if input file does not exist', () {
      final invoker = invokeCli([], 'missing_file.adoc');
      expect(invoker.readError(), matches(RegExp(r'input file .* is missing')));
      expect(invoker.code, equals(1));
    });

    test('treats extra arguments as files', () {
      final invoker = invokeCli([
        '-o',
        '/dev/null',
        'extra',
        'arguments',
        'sample.adoc',
      ], null);
      expect(invoker.readError(), matches(RegExp(r'input file .* is missing')));
      expect(invoker.code, equals(1));
    });
  });

  group('require failures', () {
    test(
      'suggests --trace option if not present when program raises error',
      () {
        final invoker = invokeCli(['-r', 'no-such-module']);
        expect(
          invoker.readError(),
          contains(
            "'no-such-module' could not be loaded\n  Use --trace to show backtrace",
          ),
        );
        expect(invoker.code, equals(1));
      },
    );

    test(
      'raises error when --trace option is specified and program raises error',
      () {
        // Ruby re-raises LoadError; Dart cannot load libraries at runtime, so
        // options.dart throws UnsupportedError instead (see its docs).
        expect(
          () => Invoker.fromArgs(
            ['--trace', '-r', 'no-such-module', sampleFile],
            out: StringBuffer(),
            err: StringBuffer(),
            environment: <String, String>{},
          ),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });

  group('stream redirection', () {
    test('reads empty output and error by default', () {
      final invoker = Invoker.fromOptions(CliOptions());
      expect(invoker.readOutput(), isEmpty);
      expect(invoker.readError(), isEmpty);
    });

    test('redirects and resets streams', () {
      final invoker = Invoker.fromOptions(CliOptions());
      invoker.redirectStreams(StringBuffer('out'), StringBuffer('err'));
      expect(invoker.readOutput(), equals('out'));
      expect(invoker.readError(), equals('err'));
      invoker.resetStreams();
      expect(invoker.readOutput(), isEmpty);
      expect(invoker.readError(), isEmpty);
    });

    test('does nothing when options is null', () {
      final invoker = Invoker.fromArgs(
        [],
        out: StringBuffer(),
        err: StringBuffer(),
        environment: <String, String>{},
      );
      expect(invoker.options, isNull);
      expect(invoker.code, equals(1));
      invoker.invoke();
      expect(invoker.documents, isEmpty);
      expect(invoker.document, isNull);
      expect(invoker.code, equals(1));
    });
  });

  group('command binary', () {
    test('--help exits 0 and prints usage to stdout', () async {
      final result = await runCli(['--help']);
      expect(result.exitCode, equals(0));
      expect(result.stdout as String, contains('Usage: asciidoctor'));
      expect(result.stderr as String, isEmpty);
    });

    test('--version exits 0', () async {
      final result = await runCli(['--version']);
      expect(result.exitCode, equals(0));
      expect(
        result.stdout as String,
        contains('Asciidoctor ${Asciidoctor.version}'),
      );
    });

    test('missing input file exits 1', () async {
      final result = await runCli(['missing_file.adoc']);
      expect(result.exitCode, equals(1));
      expect(result.stderr as String, contains('is missing'));
    });

    test('shows backtrace when --trace option is specified and program raises error', () async {
      final result = await runCli([
        '-r',
        'no-such-module',
        '--trace',
        sampleFile,
      ]);
      expect(result.exitCode, equals(1));
      final err = result.stderr as String;
      expect(err, contains("'no-such-module' could not be loaded"));
      expect(err, contains('#0 '));
    });
  });

  group('conversion', () {
    test('parses source and converts to html5 article by default', () {
      final invoker = invokeCli(['-o', '-']);
      final doc = invoker.document!;
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('author'), equals('Doc Writer'));
      expect(doc.attr('backend'), equals('html5'));
      expect(doc.attr('outfilesuffix'), equals('.html'));
      expect(doc.attr('doctype'), equals('article'));
      expect(doc.hasBlocks, isTrue);
      expect(doc.blocks.first.context, equals('preamble'));
      final output = invoker.readOutput();
      expect(output, isNotEmpty);
      expect(output, contains('<html'));
      expect(output, contains('<title>Document Title</title>'));
    });

    test('sets implicit doc info attributes', () {
      final invoker = invokeCliToBuffer([
        '-o',
        '/dev/null',
      ], fixturePath('sample.adoc'));
      final doc = invoker.document!;
      expect(doc.attr('docname'), equals('sample'));
      expect(doc.attr('docfile'), equals(fixturePath('sample.adoc')));
      expect(doc.attr('docdir'), equals('$repoRoot/test/fixtures'));
      expect(doc.hasAttr('docdate'), isTrue);
      expect(doc.hasAttr('docyear'), isTrue);
      expect(doc.hasAttr('doctime'), isTrue);
      expect(doc.hasAttr('docdatetime'), isTrue);
      expect(invoker.readOutput(), isEmpty);
    });

    test('allows docdate and doctime to be overridden', () {
      final invoker = invokeCliToBuffer([
        '-o',
        '/dev/null',
        '-a',
        'docdate=2015-01-01',
        '-a',
        'doctime=10:00:00-0700',
      ], fixturePath('sample.adoc'));
      final doc = invoker.document!;
      expect(doc.hasAttr('docdate', '2015-01-01'), isTrue);
      expect(doc.hasAttr('docyear', '2015'), isTrue);
      expect(doc.hasAttr('doctime', '10:00:00-0700'), isTrue);
      expect(doc.hasAttr('docdatetime', '2015-01-01 10:00:00-0700'), isTrue);
    });

    test('accepts document from stdin and writes to stdout', () {
      final invoker = invokeCliToBuffer(['-e'], '-', () => 'content');
      final doc = invoker.document!;
      expect(doc.hasAttr('docname'), isFalse);
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(Directory.current.path));
      expect(doc.attr('docdate'), equals(doc.attr('localdate')));
      expect(doc.attr('docyear'), equals(doc.attr('localyear')));
      expect(doc.attr('doctime'), equals(doc.attr('localtime')));
      expect(doc.attr('docdatetime'), equals(doc.attr('localdatetime')));
      expect(doc.hasAttr('outfile'), isFalse);
      expect(invoker.readOutput(), contains('<p>content</p>'));
    });

    test('does not fail to rewind input when reading document from stdin', () {
      // No Dart analog for swapping `$stdin`; the stdin callback covers
      // string input.
      final invoker = invokeCliToBuffer(['-e'], '-', () => 'paragraph');
      expect(invoker.code, equals(0));
      expect(invoker.document!.blocks.length, equals(1));
    });

    test('accepts document from stdin and writes to output file', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final outPath = '${tempDir.path}/sample-output.html';
        final invoker = invokeCli(['-e', '-o', outPath], '-', () => 'content');
        final doc = invoker.document!;
        expect(doc.hasAttr('docname'), isFalse);
        expect(doc.hasAttr('docfile'), isFalse);
        expect(doc.attr('docdir'), equals(Directory.current.path));
        expect(doc.attr('docdate'), equals(doc.attr('localdate')));
        expect(doc.attr('docyear'), equals(doc.attr('localyear')));
        expect(doc.attr('doctime'), equals(doc.attr('localtime')));
        expect(doc.attr('docdatetime'), equals(doc.attr('localdatetime')));
        expect(doc.hasAttr('outfile'), isTrue);
        expect(doc.attr('outfile'), equals(outPath));
        expect(File(outPath).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails if input file matches resolved output file', () {
      final invoker = invokeCliToBuffer([
        '-a',
        'outfilesuffix=.adoc',
      ], 'sample.adoc');
      expect(
        invoker.readError(),
        contains('input file and output file cannot be the same'),
      );
    });

    test('fails if input file matches specified output file', () {
      final invoker = invokeCliToBuffer(['-o', sampleFile], 'sample.adoc');
      expect(
        invoker.readError(),
        contains('input file and output file cannot be the same'),
      );
    });

    test('accepts input from named pipe and outputs to stdout', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final pipePath = '${tempDir.path}/sample-pipe.adoc';
        final mkfifo = Process.runSync('mkfifo', [pipePath]);
        expect(mkfifo.exitCode, equals(0));
        // Ruby uses a writer thread; Dart uses a writer isolate (a
        // top-level entry point: closures cannot cross isolates).
        final writerDone = ReceivePort();
        await Isolate.spawn(_writePipe, [pipePath, writerDone.sendPort]);
        final invoker = invokeCliToBuffer(['-a', 'stylesheet!'], pipePath);
        expect(invoker.readOutput(), contains('pipe content'));
        await writerDone.first;
        writerDone.close();
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('allows docdir to be specified when input is a string', () {
      // Ruby passes a root-relative `--base-dir`; the Dart suite runs
      // from `dart/`, so the path is absolute here.
      final expectedDocdir = '$repoRoot/test/fixtures';
      final invoker = invokeCliToBuffer(
        ['-e', '--base-dir', expectedDocdir, '-o', '/dev/null'],
        '-',
        () => 'content',
      );
      final doc = invoker.document!;
      expect(doc.attr('docdir'), equals(expectedDocdir));
      expect(doc.baseDir, equals(expectedDocdir));
    });

    test('prints warnings to stderr by default', () {
      final invoker = invokeCliToBuffer(
        ['-o', '/dev/null'],
        '-',
        () => '1. first\n3. third\n',
      );
      expect(invoker.readError(), contains('WARNING'));
    });

    test('emits no unexpected warnings', () async {
      final result = await runCli(['-o', '/dev/null', '-w', sampleFile]);
      expect(result.stdout as String, isEmpty);
      expect(result.stderr as String, isEmpty);
    });

    test('changes level on logger when --log-level is specified', () {
      final invoker = invokeCli(
        ['--log-level', 'info'],
        '-',
        () =>
            'skip to <<install>>\n\n. download\n. install[[install]]\n. run\n',
      );
      expect(
        invoker.readError(),
        equals('asciidoctor: INFO: possible invalid reference: install\n'),
      );
    });

    test('does not log when --log-level and -q are both specified', () {
      final invoker = invokeCli(
        ['--log-level', 'info', '-q'],
        '-',
        () =>
            'skip to <<install>>\n\n. download\n. install[[install]]\n. run\n',
      );
      expect(invoker.readError(), isEmpty);
    });

    test('uses specified log level when --log-level and -v are both specified', () {
      final invoker = invokeCli(
        ['--log-level', 'warn', '-v'],
        '-',
        () =>
            'skip to <<install>>\n\n. download\n. install[[install]]\n. run\n',
      );
      expect(invoker.readError(), isEmpty);
    });

    test(
      'enables script warnings if -w flag is specified',
      skip:
          'PERMANENT: No Dart equivalent of \$VERBOSE-backed script warnings '
          '(Ruby-only behavior); -w parsing is covered in options_test.dart.',
      () {},
    );

    test('silences warnings if -q flag is specified', () {
      final invoker = invokeCliToBuffer(
        ['-q', '-o', '/dev/null'],
        '-',
        () => '2. second\n3. third\n',
      );
      expect(invoker.readError(), isEmpty);
    });

    test('shows debug messages if -v flag is specified', () {
      // verbose 2 sets the logger level to DEBUG around conversion
      // (`lib/asciidoctor/cli/invoker.rb`); the debug message is the one
      // from blocks_test.rb 'should log debug message if block style is
      // unknown and debug level is enabled'.
      const input = '[foo]\n--\nbar\n--\n';
      final invoker = invokeCli(['-v', '-o', '/dev/null'], '-', () => input);
      expect(invoker.readError(), contains('DEBUG'));
      expect(
        invoker.readError(),
        contains('unknown style for open block: foo'),
      );
      final quiet = invokeCli(['-o', '/dev/null'], '-', () => input);
      expect(quiet.readError(), isNot(contains('unknown style')));
    });

    test('does not fail to check log level when -q flag is specified', () {
      final invoker = invokeCli(
        ['-q'],
        '-',
        () =>
            'skip to <<install>>\n\n. download\n. install[[install]]\n. run\n',
      );
      expect(invoker.code, equals(0));
    });

    test('returns non-zero exit code if failure level is reached', () {
      final invoker = invokeCli(
        ['-q', '--failure-level=WARN', '-o', '/dev/null'],
        '-',
        () => '1. first\n3. third\n',
      );
      expect(invoker.code, equals(1));
      expect(invoker.readError(), isEmpty);
    });

    test('outputs to file name based on input file name', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final input = copyFixtureTo('sample.adoc', tempDir);
        final expectedOut = '${tempDir.path}/sample.html';
        final invoker = invokeCli([], input);
        expect(invoker.document!.attr('outfile'), equals(expectedOut));
        expect(File(expectedOut).existsSync(), isTrue);
        final output = File(expectedOut).readAsStringSync();
        expect(output, contains('<html'));
        expect(output, contains('<title>Document Title</title>'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('outputs to file in destination directory if set', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final expectedOut = '${tempDir.path}/sample.html';
        final invoker = invokeCli(['-D', tempDir.path]);
        expect(invoker.document!.attr('outfile'), equals(expectedOut));
        expect(File(expectedOut).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('preserves directory structure in destination directory if source directory is set', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        invokeCli([
          '-D',
          tempDir.path,
          '-R',
          '$repoRoot/test/fixtures',
        ], 'subdir/index.adoc');
        expect(Directory('${tempDir.path}/subdir').existsSync(), isTrue);
        expect(File('${tempDir.path}/subdir/index.html').existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('outputs to file specified', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final outPath = '${tempDir.path}/sample-output.html';
        final invoker = invokeCli(['-o', outPath]);
        expect(invoker.document!.attr('outfile'), equals(outPath));
        expect(File(outPath).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'copies default stylesheet to target directory if linkcss is specified',
      skip:
          'WAVE-GATED: needs the syntax-highlighter wave (no SourceLexer '
          'backends exist, so no source block is ever highlighted and the '
          'coderay stylesheet is never required).',
      () {
        final tempDir = Directory.systemTemp.createTempSync(
          'asciidoctor-invoker-',
        );
        try {
          final outPath = '${tempDir.path}/sample-output.html';
          invokeCli([
            '-o',
            outPath,
            '-a',
            'linkcss',
            '-a',
            'source-highlighter=coderay',
          ], 'source-block.adoc');
          final siblings = [
            outPath,
            '${tempDir.path}/asciidoctor.css',
            '${tempDir.path}/coderay-asciidoctor.css',
          ];
          for (final path in siblings) {
            expect(File(path).existsSync(), isTrue, reason: path);
            final contents = File(path).readAsStringSync();
            expect(contents, contains('\n'));
            expect(contents, isNot(contains('\r')));
            expect(contents.endsWith('\n'), isFalse);
          }
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test(
      'does not copy coderay stylesheet when no source blocks were highlighted',
      () {
        final tempDir = Directory.systemTemp.createTempSync(
          'asciidoctor-invoker-',
        );
        try {
          final outPath = '${tempDir.path}/sample-output.html';
          invokeCli([
            '-o',
            outPath,
            '-a',
            'linkcss',
            '-a',
            'source-highlighter=coderay',
          ]);
          expect(File(outPath).existsSync(), isTrue);
          expect(File('${tempDir.path}/asciidoctor.css').existsSync(), isTrue);
          expect(
            File('${tempDir.path}/coderay-asciidoctor.css').existsSync(),
            isFalse,
          );
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test(
      'does not copy default stylesheet if linkcss is set and copycss is unset',
      () {
        final tempDir = Directory.systemTemp.createTempSync(
          'asciidoctor-invoker-',
        );
        try {
          final outPath = '${tempDir.path}/sample-output.html';
          invokeCli(['-o', outPath, '-a', 'linkcss', '-a', 'copycss!']);
          expect(File(outPath).existsSync(), isTrue);
          expect(File('${tempDir.path}/asciidoctor.css').existsSync(), isFalse);
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test(
      'copies custom stylesheet if stylesheet and linkcss are specified',
      () {
        final tempDir = Directory.systemTemp.createTempSync(
          'asciidoctor-invoker-',
        );
        try {
          final outPath = '${tempDir.path}/sample-output.html';
          invokeCli([
            '-o',
            outPath,
            '-a',
            'linkcss',
            '-a',
            'copycss=stylesheets/custom.css',
            '-a',
            'stylesdir=./styles',
            '-a',
            'stylesheet=custom.css',
          ]);
          expect(File(outPath).existsSync(), isTrue);
          expect(
            File('${tempDir.path}/styles/custom.css').existsSync(),
            isTrue,
          );
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test('does not copy custom stylesheet if copycss is unset', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final outPath = '${tempDir.path}/sample-output.html';
        invokeCli([
          '-o',
          outPath,
          '-a',
          'linkcss',
          '-a',
          'stylesdir=./styles',
          '-a',
          'stylesheet=custom.css',
          '-a',
          'copycss!',
        ]);
        expect(File(outPath).existsSync(), isTrue);
        expect(File('${tempDir.path}/styles/custom.css').existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('does not copy custom stylesheet if stylesdir is a URI', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final outPath = '${tempDir.path}/sample-output.html';
        invokeCli([
          '-o',
          outPath,
          '-a',
          'linkcss',
          '-a',
          'stylesdir=http://example.org/styles',
          '-a',
          'stylesheet=custom.css',
        ]);
        expect(File(outPath).existsSync(), isTrue);
        expect(Directory('${tempDir.path}/http:').existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('converts all passed files', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final basic = copyFixtureTo('basic.adoc', tempDir);
        final sample = copyFixtureTo('sample.adoc', tempDir);
        invokeCliWithFilenames([], [basic, sample]);
        expect(File('${tempDir.path}/basic.html').existsSync(), isTrue);
        expect(File('${tempDir.path}/sample.html').existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('does not modify options when processing multiple files', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        invokeCliWithFilenames(
          ['-D', tempDir.path, '-a', 'outfilesuffix=.htm'],
          ['basic.adoc', 'sample.adoc'],
        );
        expect(File('${tempDir.path}/basic.htm').existsSync(), isTrue);
        expect(File('${tempDir.path}/sample.htm').existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('converts all files matching a glob expression', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        copyFixtureTo('basic.adoc', tempDir);
        invokeCli(['${tempDir.path}/ba*.adoc'], null);
        expect(File('${tempDir.path}/basic.html').existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('converts all files matching an absolute path glob expression', () {
      // Ruby additionally tries a backslash-style pattern on Windows;
      // tempDir.path already uses native separators there.
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        copyFixtureTo('basic.adoc', tempDir);
        invokeCliToBuffer(['${tempDir.path}/ba*.adoc'], null);
        expect(File('${tempDir.path}/basic.html').existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('suppresses header footer if specified', () {
      // NOTE the second flag set verifies the legacy alias -s.
      for (final flags in [
        ['-e', '-o', '-'],
        ['-s', '-o', '-'],
      ]) {
        final invoker = invokeCliToBuffer(flags);
        final output = invoker.readOutput();
        expect(output, isNot(contains('<html')));
        expect(output, contains('preamble'));
      }
    });

    test('writes page for each alternate manname', () {
      const input = '''
= eve(1)
Andrew Stanton
v1.0.0
:doctype: manpage
:manmanual: EVE
:mansource: EVE

== NAME

eve, islifeform - analyzes an image to determine if it's a picture of a life form

== SYNOPSIS

*eve* ['OPTION']... 'FILE'...
''';
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final outPath = '${tempDir.path}/eve.1';
        invokeCli(['-b', 'manpage', '-o', outPath], '-', () => input);
        expect(File(outPath).existsSync(), isTrue);
        final sibling = '${tempDir.path}/islifeform.1';
        expect(File(sibling).existsSync(), isTrue);
        expect(File(sibling).readAsStringSync().trim(), equals('.so eve.1'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('outputs a trailing newline to stdout', () {
      final invoker = invokeCli(['-o', '-']);
      expect(invoker.readOutput().endsWith('\n'), isTrue);
    });

    test('sets backend to html5 if specified', () {
      final invoker = invokeCliToBuffer(['-b', 'html5', '-o', '-']);
      final doc = invoker.document!;
      expect(doc.attr('backend'), equals('html5'));
      expect(doc.attr('outfilesuffix'), equals('.html'));
      expect(invoker.readOutput(), contains('<html'));
    });

    test('sets backend to docbook5 if specified', () {
      final invoker = invokeCliToBuffer([
        '-b',
        'docbook5',
        '-a',
        'xmlns',
        '-o',
        '-',
      ]);
      final doc = invoker.document!;
      expect(doc.attr('backend'), equals('docbook5'));
      expect(doc.attr('outfilesuffix'), equals('.xml'));
      expect(invoker.readOutput(), contains('<article'));
    });

    test('sets doctype to article if specified', () {
      final invoker = invokeCliToBuffer(['-d', 'article', '-o', '-']);
      expect(invoker.document!.attr('doctype'), equals('article'));
      expect(invoker.readOutput(), contains('class="article"'));
    });

    test('sets doctype to book if specified', () {
      final invoker = invokeCliToBuffer(['-d', 'book', '-o', '-']);
      expect(invoker.document!.attr('doctype'), equals('book'));
      expect(invoker.readOutput(), contains('class="book"'));
    });

    test('warns if doctype is inline and the first block is not an inline candidate', () {
      for (final input in ['== Section Title', 'image::tiger.png[]']) {
        final invoker = invokeCliToBuffer(['-d', 'inline'], '-', () => input);
        expect(invoker.readError(), contains('no inline candidate'));
      }
    });

    test(
      'does not warn if doctype is inline and the document has no blocks',
      () {
        final invoker = invokeCliToBuffer(
          ['-d', 'inline'],
          '-',
          () => '// comment',
        );
        expect(invoker.readError(), isNot(contains('WARNING')));
      },
    );

    test(
      'does not warn if doctype is inline and the document has multiple blocks',
      () {
        final invoker = invokeCliToBuffer(
          ['-d', 'inline'],
          '-',
          () => 'paragraph one\n\nparagraph two\n\nparagraph three',
        );
        expect(invoker.readError(), isNot(contains('WARNING')));
      },
    );

    test(
      'adds source location to blocks when sourcemap option is specified',
      () {
        final invoker = invokeCliToBuffer(['--sourcemap', '-o', '-']);
        final doc = invoker.document!;
        final allBlocks = doc.findBy();
        expect(allBlocks, isNotEmpty);
        for (final block in allBlocks) {
          expect(block.sourceLocation, isNotNull);
        }
        expect(doc.blocks[0].sourceLocation!.file, equals(sampleFile));
        expect(doc.blocks[0].sourceLocation!.lineno, equals(6));
      },
    );

    test(
      'locates custom templates based on template dir, engine and backend',
      skip:
          'WAVE-GATED: No Tilt/Haml template-engine analog exists in Dart; '
          'deferred to the template-converter phase.',
      () {},
    );

    test(
      'loads custom templates from multiple template directories',
      skip:
          'WAVE-GATED: No Tilt/Haml template-engine analog exists in Dart; '
          'deferred to the template-converter phase.',
      () {},
    );

    test('sets attribute with value', () {
      final invoker = invokeCliToBuffer([
        '--trace',
        '-a',
        'idprefix=id',
        '-e',
        '-o',
        '-',
      ]);
      expect(invoker.document!.attr('idprefix'), equals('id'));
      expect(invoker.readOutput(), contains('id="idsection_a"'));
    });

    test('sets attribute with value containing equal sign', () {
      final invoker = invokeCliToBuffer([
        '--trace',
        '-a',
        'toc',
        '-a',
        'toc-title=t=o=c',
        '-o',
        '-',
      ]);
      expect(invoker.document!.attr('toc-title'), equals('t=o=c'));
      expect(invoker.readOutput(), contains('>t=o=c<'));
    });

    test('sets attribute with quoted value containing a space', () {
      // Emulates: --trace -a toc -a note-caption="Note to self:" -o -
      final invoker = invokeCliToBuffer([
        '--trace',
        '-a',
        'toc',
        '-a',
        'note-caption=Note to self:',
        '-o',
        '-',
      ]);
      expect(invoker.document!.attr('note-caption'), equals('Note to self:'));
      expect(invoker.readOutput(), contains('>Note to self:<'));
    });

    test('does not set attribute ending in @ if defined in document', () {
      final invoker = invokeCliToBuffer([
        '--trace',
        '-a',
        'idprefix=id@',
        '-e',
        '-o',
        '-',
      ]);
      expect(invoker.document!.attr('idprefix'), equals('id_'));
      expect(invoker.readOutput(), contains('id="id_section_a"'));
    });

    test('sets attribute with no value', () {
      final invoker = invokeCliToBuffer(['-a', 'icons', '-e', '-o', '-']);
      expect(invoker.document!.attr('icons'), equals(''));
      expect(invoker.readOutput(), contains('alt="Note"'));
    });

    test('unsets attribute ending in bang', () {
      final invoker = invokeCliToBuffer(['-a', 'sectids!', '-e', '-o', '-']);
      expect(invoker.document!.hasAttr('sectids'), isFalse);
      expect(invoker.readOutput(), contains('<h2>'));
    });

    test('defaults to unsafe safe mode for cli', () {
      final invoker = invokeCliToBuffer(['-o', '/dev/null']);
      expect(invoker.document!.safe, equals(SafeMode.unsafe));
    });

    test('sets safe mode if specified', () {
      final invoker = invokeCliToBuffer(['--safe', '-o', '/dev/null']);
      expect(invoker.document!.safe, equals(SafeMode.safe));
    });

    test('sets safe mode to specified level', () {
      const levels = {
        'unsafe': SafeMode.unsafe,
        'safe': SafeMode.safe,
        'server': SafeMode.server,
        'secure': SafeMode.secure,
      };
      levels.forEach((name, level) {
        final invoker = invokeCliToBuffer(['-S', name, '-o', '/dev/null']);
        expect(invoker.document!.safe, equals(level));
      });
    });

    test('sets eRuby impl if specified', () {
      final invoker = invokeCliToBuffer([
        '--eruby',
        'erubi',
        '-o',
        '/dev/null',
      ]);
      expect(invoker.document!.options['eruby'], equals('erubi'));
    });

    test(
      'forces default external encoding to UTF-8',
      skip:
          'PERMANENT: No Dart analog: Dart strings are Unicode and the invoker '
          'forces UTF-8 stdio; Ruby`s Encoding.default_external does not exist.',
      () {},
    );

    test(
      'forces stdio encoding to UTF-8',
      skip:
          'PERMANENT: No Dart analog: Dart strings are Unicode and the invoker '
          'forces UTF-8 stdio; Ruby IO encodings do not exist.',
      () {},
    );

    test('does not fail to load if call to Dir.home fails', () {
      // Ruby injects a Dir.home failure via `-r undef-dir-home.rb`; Dart
      // has no home-directory lookup on the load path (and `-r` only
      // accepts known libraries), so the port just verifies plain
      // conversion of the same fixture.
      final invoker = invokeCli(['-e', '-o', '-'], 'basic.adoc');
      expect(invoker.readOutput(), contains('Body content'));
    });

    test('prints timings when -t flag is specified', () {
      final invoker = invokeCli(
        ['-t', '-o', '/dev/null'],
        '-',
        () => 'Sample *AsciiDoc*',
      );
      expect(invoker.readError(), contains('Total time'));
    });

    test('shows timezone as UTC if system TZ is set to UTC', () async {
      final environment = Map<String, String>.of(Platform.environment)
        ..['TZ'] = 'UTC'
        ..remove('SOURCE_DATE_EPOCH')
        ..remove('IGNORE_SOURCE_DATE_EPOCH');
      final result = await runCli([
        '-d',
        'inline',
        '-o',
        '-',
        '-e',
        fixturePath('doctime-localtime.adoc'),
      ], environment: environment);
      final lines = (result.stdout as String).split('\n');
      final lastTwo = lines.sublist(lines.length - 3, lines.length - 1);
      for (final line in lastTwo) {
        expect(line, endsWith(' UTC'));
      }
    });

    test('shows timezone as offset if system TZ is not set to UTC', () async {
      final environment = Map<String, String>.of(Platform.environment)
        ..['TZ'] = 'EST+5'
        ..remove('SOURCE_DATE_EPOCH')
        ..remove('IGNORE_SOURCE_DATE_EPOCH');
      final result = await runCli([
        '-d',
        'inline',
        '-o',
        '-',
        '-e',
        fixturePath('doctime-localtime.adoc'),
      ], environment: environment);
      final lines = (result.stdout as String).split('\n');
      final lastTwo = lines.sublist(lines.length - 3, lines.length - 1);
      for (final line in lastTwo) {
        expect(line, endsWith(' -0500'));
      }
    });

    test(
      'uses SOURCE_DATE_EPOCH as modified time of input file and local time',
      () async {
        // Port of invoker_test.rb 'should use SOURCE_DATE_EPOCH as modified
        // time of input file and local time'. The process environment is
        // read-only in-process, so the CLI runs in a subprocess (cf. the
        // timezone tests above) and the datetime attributes are asserted
        // through attribute references in the converted output.
        final tempDir = Directory.systemTemp.createTempSync(
          'asciidoctor-invoker-',
        );
        try {
          final inputPath = '${tempDir.path}/epoch.adoc';
          File(inputPath).writeAsStringSync(
            '{docdate} {docyear} {docdatetime} {localdate} {localyear} '
            '{localdatetime}\n',
          );
          final environment = Map<String, String>.of(Platform.environment)
            ..['SOURCE_DATE_EPOCH'] = '1234123412';
          final result = await runCli([
            '-o',
            '-',
            inputPath,
          ], environment: environment);
          expect(result.exitCode, equals(0));
          final output = result.stdout as String;
          expect(output, contains('2009-02-08'));
          expect(output, contains('2009-02-08 20:03:32 UTC'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test('ignores SOURCE_DATE_EPOCH if value is empty', () async {
      // Port of invoker_test.rb 'should ignore SOURCE_DATE_EPOCH is value
      // is empty', via a subprocess (see the test above).
      final tempDir = Directory.systemTemp.createTempSync(
        'asciidoctor-invoker-',
      );
      try {
        final inputPath = '${tempDir.path}/epoch.adoc';
        File(inputPath).writeAsStringSync('{localyear}\n');
        final environment = Map<String, String>.of(Platform.environment)
          ..['SOURCE_DATE_EPOCH'] = '';
        final result = await runCli([
          '-o',
          '-',
          inputPath,
        ], environment: environment);
        expect(result.exitCode, equals(0));
        final match = RegExp(r'<p>(\d{4})</p>')
            .firstMatch(result.stdout as String);
        expect(match, isNotNull);
        expect(
          int.parse(match![1]!),
          greaterThanOrEqualTo(DateTime.now().year - 1),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails if SOURCE_DATE_EPOCH is malformed', () async {
      // Port of invoker_test.rb 'should fail if SOURCE_DATE_EPOCH is
      // malformed', via a subprocess (see the tests above).
      final environment = Map<String, String>.of(Platform.environment)
        ..['SOURCE_DATE_EPOCH'] = 'aaaaaaaa';
      final result = await runCli([
        '-o',
        '/dev/null',
        sampleFile,
      ], environment: environment);
      expect(result.exitCode, equals(1));
    });
  });
}
