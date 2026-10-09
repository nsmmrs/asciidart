/// Tests for the CLI invoker port (`lib/src/cli/invoker.dart`).
///
/// Port of `test/invoker_test.rb` (the invocation halves; option-parsing
/// halves already live in `options_test.dart`). Adaptations: XPath/CSS
/// assertions become substring checks (no Nokogiri equivalent), file outputs
/// go to temp directories instead of `vendor/asciidoctor/test/fixtures` where the behavior
/// allows it, and Ruby's `invoke_cli` / `invoke_cli_to_buffer` / global
/// `$stdout` swapping collapses into [invokeCli], which always buffers and
/// installs a temporary logger on the error buffer (cf. Ruby's
/// `redirect_streams`). Tests with no Dart analog are `skip()`ped with a
/// `PERMANENT:` reason; tests awaiting a later wave keep a `WAVE-GATED:`
/// reason with their ported bodies intact.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

import '../support/cli.dart';
import '../support/paths.dart';

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/vendor/asciidoctor/test/fixtures')
            .existsSync()) {
      return posixPath(dir.path);
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repository checkout not found above $currentPath');
    }
    dir = parent;
  }
}

/// The repository checkout directory.
final String repoRoot = _findRepoRoot();

/// Resolves [name] under `vendor/asciidoctor/test/fixtures`.
String fixturePath(String name) =>
    '$repoRoot/vendor/asciidoctor/test/fixtures/$name';

/// An existing oracle fixture used as the default input file.
String get sampleFile => fixturePath('sample.adoc');

/// Invokes the CLI like Ruby's `invoke_cli` / `invoke_cli_to_buffer`.
///
/// [argv] plus [filename] (`-` and absolute paths pass through, other names
/// resolve under `vendor/asciidoctor/test/fixtures`, `null` passes no file) are parsed and
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
    [...argv, ?filepath],
    out: out,
    err: err,
    environment: <String, String>{},
  )..redirectStreams(out, err);
  final savedLogger = LoggerManager.logger;
  LoggerManager.logger = Logger(sink: err)..level = savedLogger.level;
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
  (File(args[0] as String).openSync(mode: FileMode.writeOnly))
    ..writeStringSync('pipe content')
    ..closeSync();
  (args[1] as SendPort).send(null);
}

/// Runs the real CLI binary in a subprocess, like Ruby's `run_command`.
Future<ProcessResult> runCli(
  List<String> args, {
  Map<String, String>? environment,
}) => runPtome(args, workingDirectory: repoRoot, environment: environment);

/// Copies the fixture [name] into [dir] and returns the copy's path.
String copyFixtureTo(String name, Directory dir) {
  final copy = File('${dir.path}/$name')
    ..writeAsStringSync(File(fixturePath(name)).readAsStringSync());
  return copy.path;
}

void main() {
  tearDownAll(deletePtomeCommand);

  group('Invoker constructor', () {
    test('allows CliOptions to be passed as first argument of constructor', () {
      final opts = CliOptions(attributes: {'toc': ''}, doctype: 'book');
      final invoker = Invoker.fromOptions(opts);
      expect(identical(invoker.options, opts), isTrue);
    });

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
      const expected =
          'Ptome ${Asciidoctor.packageVersion} '
          '(compatible with Asciidoctor ${Asciidoctor.version}) '
          '[https://github.com/nsmmrs/ptome]\n'
          'Runtime Environment (';
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
      expect(invoker.readError(), matches(RegExp('input file .* is missing')));
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
      expect(invoker.readError(), matches(RegExp('input file .* is missing')));
      expect(invoker.code, equals(1));
    });
  });

  group('conversion failures', () {
    test(
      'suggests --trace option if not present when program raises error',
      () {
        final invoker = invokeCli(['-E', 'bogus', '-T', 'templates']);
        expect(
          invoker.readError(),
          contains(
            "unknown template engine 'bogus' (supported: mustache, dart)\n"
            '  Use --trace to show backtrace',
          ),
        );
        expect(invoker.code, equals(1));
      },
    );

    test(
      'raises error when --trace option is specified and program raises error',
      () {
        final invoker = Invoker.fromArgs(
          ['--trace', '-E', 'bogus', '-T', 'templates', sampleFile],
          out: StringBuffer(),
          err: StringBuffer(),
          environment: <String, String>{},
        );
        expect(invoker.invoke, throwsA(isA<AsciidoctorException>()));
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
      final invoker = (Invoker.fromOptions(CliOptions()))
        ..redirectStreams(StringBuffer('out'), StringBuffer('err'));
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
      expect(result.stdout as String, contains('Usage: ptome'));
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

    test('shows backtrace when --trace option is specified and program '
        'raises error', () async {
      final result = await runCli([
        '-E',
        'bogus',
        '-T',
        'templates',
        '--trace',
        sampleFile,
      ]);
      expect(result.exitCode, equals(1));
      final err = result.stderr as String;
      expect(err, contains("unknown template engine 'bogus'"));
      expect(err, contains('#0 '));
    });

    test('stops quietly when the reader of stdout goes away', () async {
      final dir = createTempDir('invoker_pipe_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Enough output to overflow the pipe buffer after `head` exits.
      final input = File('${dir.path}/big.adoc')
        ..writeAsStringSync('paragraph text\n\n' * 20000);
      const pipeline =
          r'set -o pipefail; "$@" -o - "$0" | head -c 1 >/dev/null';
      final result = await Process.run('bash', [
        '-c',
        pipeline,
        input.path,
        ...await ptomeCommand(),
      ], workingDirectory: repoRoot);
      expect(result.exitCode, equals(0), reason: '${result.stderr}');
      expect(result.stderr as String, isEmpty);
    }, skip: Platform.isWindows ? 'needs a POSIX shell pipeline' : null);
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
      expect(doc.blocks.first.contextName, equals('preamble'));
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
      expect(
        doc.attr('docdir'),
        equals('$repoRoot/vendor/asciidoctor/test/fixtures'),
      );
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
      expect(doc.attr('docdir'), equals(currentPath));
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
      final tempDir = createTempDir('asciidoctor-invoker-');
      try {
        final outPath = '${tempDir.path}/sample-output.html';
        final invoker = invokeCli(['-e', '-o', outPath], '-', () => 'content');
        final doc = invoker.document!;
        expect(doc.hasAttr('docname'), isFalse);
        expect(doc.hasAttr('docfile'), isFalse);
        expect(doc.attr('docdir'), equals(currentPath));
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
      final invoker = invokeCliToBuffer(['-a', 'outfilesuffix=.adoc']);
      expect(
        invoker.readError(),
        contains('input file and output file cannot be the same'),
      );
    });

    test('fails if input file matches specified output file', () {
      final invoker = invokeCliToBuffer(['-o', sampleFile]);
      expect(
        invoker.readError(),
        contains('input file and output file cannot be the same'),
      );
    });

    test(
      'accepts input from named pipe and outputs to stdout',
      skip: Platform.isWindows ? 'named pipes need a POSIX system' : null,
      () async {
        final tempDir = createTempDir('asciidoctor-invoker-');
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
      },
    );

    test('allows docdir to be specified when input is a string', () {
      // Ruby passes a root-relative `--base-dir`; the Dart suite runs
      // from `dart/`, so the path is absolute here.
      final expectedDocdir = '$repoRoot/vendor/asciidoctor/test/fixtures';
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
      final result = await runCli(['-o', '/dev/null', sampleFile]);
      expect(result.stdout as String, isEmpty);
      expect(result.stderr as String, isEmpty);
    });

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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
      try {
        final expectedOut = '${tempDir.path}/sample.html';
        final invoker = invokeCli(['-D', tempDir.path]);
        expect(invoker.document!.attr('outfile'), equals(expectedOut));
        expect(File(expectedOut).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('preserves directory structure in destination directory if '
        'source directory is set', () {
      final tempDir = createTempDir('asciidoctor-invoker-');
      try {
        invokeCli([
          '-D',
          tempDir.path,
          '-R',
          '$repoRoot/vendor/asciidoctor/test/fixtures',
        ], 'subdir/index.adoc');
        expect(Directory('${tempDir.path}/subdir').existsSync(), isTrue);
        expect(File('${tempDir.path}/subdir/index.html').existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('outputs to file specified', () {
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      () {
        final tempDir = createTempDir('asciidoctor-invoker-');
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
          final siblings = [outPath, '${tempDir.path}/asciidoctor.css'];
          for (final path in siblings) {
            expect(File(path).existsSync(), isTrue, reason: path);
            final contents = File(path).readAsStringSync();
            expect(contents, contains('\n'));
            expect(contents, isNot(contains('\r')));
            expect(contents.endsWith('\n'), isFalse);
          }
          // CodeRay is not available (as without its gem): no stylesheet.
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
      'does not copy coderay stylesheet when no source blocks were highlighted',
      () {
        final tempDir = createTempDir('asciidoctor-invoker-');
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
        final tempDir = createTempDir('asciidoctor-invoker-');
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
        final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
        // No directory named after the URI scheme (an invalid name on
        // Windows, so look at the listing rather than the path).
        expect([
          for (final entry in tempDir.listSync()) entry.uri.pathSegments,
        ], everyElement(isNot(contains('http:'))));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('converts all passed files', () {
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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

    test('warns if doctype is inline and the first block is not an '
        'inline candidate', () {
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
      'locates custom templates based on template dir, engine and backend',
      () {
        // Port of test/invoker_test.rb: 'should locate custom templates
        // based on template dir, template engine and backend' (adapted:
        // `-E mustache` — `-E haml` errors in the Dart port, see
        // template_loader_test.dart).
        final dir = createTempDir('invoker-template-test');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/paragraph.mustache')
            .writeAsStringSync('<p>{{content}}</p>');
        final invoker = invokeCliToBuffer([
          '-E',
          'mustache',
          '-T',
          dir.path,
          '-o',
          '-',
        ]);
        expect(invoker.code, equals(0));
        final doc = invoker.document!;
        expect(doc.converter, isA<CompositeConverter>());
        final selected = (doc.converter as CompositeConverter).findConverter(
          'paragraph',
        );
        expect(selected, isA<TemplateConverter>());
        expect(
          (selected as TemplateConverter).templates['paragraph'],
          equals('<p>{{content}}</p>'),
        );
      },
    );

    test('loads custom templates from multiple template directories', () {
      // Port of test/invoker_test.rb: 'should load custom templates from
      // multiple template directories' (adapted: Mustache files; the last
      // `-T` wins per template and the built-in wrapper is gone).
      Directory makeDir(String name, String source) {
        final dir = createTempDir('invoker-template-test');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/$name').writeAsStringSync(source);
        return dir;
      }

      final dir1 = makeDir(
        'paragraph.mustache',
        '<p class="one">{{content}}</p>',
      );
      final dir2 = makeDir(
        'paragraph.mustache',
        '<p class="two">{{content}}</p>',
      );
      final invoker = invokeCliToBuffer(
        ['-T', dir1.path, '-T', dir2.path, '-o', '-', '-e'],
        '-',
        () => 'content',
      );
      expect(invoker.code, equals(0));
      final output = invoker.readOutput();
      expect(output, contains('<p class="two">content</p>'));
      expect(output, isNot(contains('class="one"')));
      expect(output, isNot(contains('class="paragraph"')));
    });

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

    test(
      'forces default external encoding to UTF-8',
      skip:
          'PERMANENT: No Dart analog: Dart strings are Unicode and the invoker '
          'forces UTF-8 stdio; Ruby`s Encoding.default_external does '
          'not exist.',
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
        final tempDir = createTempDir('asciidoctor-invoker-');
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
      final tempDir = createTempDir('asciidoctor-invoker-');
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
