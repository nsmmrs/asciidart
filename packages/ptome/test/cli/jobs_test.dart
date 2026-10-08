/// Tests for CLI `-j/--jobs` parallel bulk conversion.
///
/// Covers flag parsing/validation, the conversion worker codec
/// (`lib/src/cli/parallel.dart`, driven directly without isolates) and
/// end-to-end parity between `jobs=1` and `jobs=4` (identical converted
/// output, diagnostics and exit codes).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

import '../support/paths.dart';

/// GNU make's `-j` validation message (verified against make 4.4.1), with the
/// `ptome: ` prefix the CLI reports it with.
const String jobsError =
    "ptome: the '-j' option requires a positive "
    'integer argument';

/// Parses [args] with buffer sinks and a hermetic (empty) environment.
({CliOptions options, int? exitCode, String out, String err}) parseJobs(
  List<String> args,
) {
  final out = StringBuffer();
  final err = StringBuffer();
  final (:options, :exitCode) = CliOptions.parseArgs(
    args,
    out: out,
    err: err,
    environment: <String, String>{},
  );
  return (
    options: options,
    exitCode: exitCode,
    out: out.toString(),
    err: err.toString(),
  );
}

/// Invokes the CLI asynchronously with all output buffered.
///
/// Mirrors the `invoke_cli` helper: [argv] holds the full command line
/// (options plus input files), [stdinSource] supplies stdin input, and a
/// temporary logger on the error buffer is installed around the invocation.
Future<({Invoker invoker, String out, String err})> invokeJobs(
  List<String> argv, {
  String Function()? stdinSource,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final invoker = (Invoker.fromArgs(
    argv,
    out: out,
    err: err,
    environment: <String, String>{},
  ))..redirectStreams(out, err);
  final savedLogger = LoggerManager.logger;
  LoggerManager.logger = Logger(sink: err)..level = savedLogger.level;
  try {
    await invoker.invokeAsync(stdinSource: stdinSource);
  } finally {
    LoggerManager.logger = savedLogger;
  }
  return (invoker: invoker, out: out.toString(), err: err.toString());
}

/// Creates a temp source tree with four deterministic documents:
///
/// - `a.adoc`: clean.
/// - `b.adoc`: warns (`section title out of sequence`).
/// - `c.adoc`: logs an INFO (`possible invalid reference`).
/// - `d.adoc`: clean, with list content.
///
/// Returns the source directory; the caller owns cleanup via [addTearDown].
Directory writeParityFixtures() {
  final dir = createTempDir('jobs_src_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/a.adoc').writeAsStringSync('= Doc A\n\nHello A.\n');
  File('${dir.path}/b.adoc')
      .writeAsStringSync('= Doc B\n\n=== Deep\n\nHello B.\n');
  File('${dir.path}/c.adoc')
      .writeAsStringSync('See <<undefined-target-xyz>>.\n');
  File('${dir.path}/d.adoc').writeAsStringSync('= Doc D\n\n* one\n* two\n');
  return dir;
}

/// Creates an empty temp directory owned by the test (see [addTearDown]).
Directory makeTempDir(String prefix) {
  final dir = createTempDir(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Input file paths of the [writeParityFixtures] tree, in order.
List<String> parityInputs(Directory src) {
  return [
    'a.adoc',
    'b.adoc',
    'c.adoc',
    'd.adoc',
  ].map((name) => '${src.path}/$name').toList();
}

/// Reads every file in [dir] as a name-to-bytes map.
Map<String, String> readOutputTree(Directory dir) {
  return {
    for (final entry in dir.listSync())
      if (entry is File)
        entry.path.split(Platform.pathSeparator).last: entry.readAsStringSync(),
  };
}

/// Replaces `%05.5f` timing values with `#` so timing reports compare by
/// structure instead of by nondeterministic measurement.
String normalizeTimings(String text) {
  return text.replaceAll(RegExp(r'\d+\.\d{5}'), '#');
}

void main() {
  group('jobs flag parsing', () {
    test('defaults to 1', () {
      final options = CliOptions();
      expect(options.jobs, equals(1));
    });

    test('accepts the jobs seed', () {
      expect(CliOptions(jobs: 8).jobs, equals(8));
    });

    test('parses -j N', () {
      final src = writeParityFixtures();
      final result = parseJobs(['-j', '4', '${src.path}/a.adoc']);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(4));
    });

    test('parses --jobs N', () {
      final src = writeParityFixtures();
      final result = parseJobs(['--jobs', '2', '${src.path}/a.adoc']);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(2));
    });

    test('parses attached -jN', () {
      final src = writeParityFixtures();
      final result = parseJobs(['-j4', '${src.path}/a.adoc']);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(4));
    });

    test('parses attached --jobs=N', () {
      final src = writeParityFixtures();
      final result = parseJobs(['--jobs=3', '${src.path}/a.adoc']);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(3));
    });

    test('parses unambiguous --jobs abbreviations', () {
      final src = writeParityFixtures();
      final result = parseJobs(['--job', '5', '${src.path}/a.adoc']);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(5));
    });

    test('last -j wins', () {
      final src = writeParityFixtures();
      final result = parseJobs(['-j', '2', '-j', '8', '${src.path}/a.adoc']);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(8));
    });

    test('combines with other flags', () {
      final src = writeParityFixtures();
      final result = parseJobs([
        '-j',
        '4',
        '-b',
        'docbook5',
        '-S',
        'safe',
        '${src.path}/a.adoc',
      ]);
      expect(result.exitCode, isNull);
      expect(result.options.jobs, equals(4));
      expect(result.options.attributes!['backend'], equals('docbook5'));
      expect(result.options.safe, equals(SafeMode.safe));
    });

    group('validation', () {
      for (final args in [
        ['-j', '0'],
        ['-j', '-1'],
        ['-j', 'foo'],
        ['-j', '1.5'],
        ['-j0'],
        ['--jobs', '0'],
        ['--jobs=x'],
        ['--jobs='],
        ['--jobs', '-2'],
      ]) {
        test('${args.join(' ')} is a usage error', () {
          final src = writeParityFixtures();
          final result = parseJobs([...args, '${src.path}/a.adoc']);
          expect(result.exitCode, equals(1));
          expect(result.err, equals('$jobsError\n'));
          expect(result.out, equals(usageText));
        });
      }

      test('-j without a value reports a missing argument', () {
        final result = parseJobs(['-j']);
        expect(result.exitCode, equals(1));
        expect(result.err, equals('ptome: option missing argument: -j\n'));
        expect(result.out, equals(usageText));
      });

      test('invalid -j short-circuits before later options', () {
        // In-order parsing: the -j error wins over a later -h.
        final src = writeParityFixtures();
        final result = parseJobs(['-j', '0', '-h', '${src.path}/a.adoc']);
        expect(result.exitCode, equals(1));
        expect(result.err, equals('$jobsError\n'));
      });

      test('-h short-circuits before a later invalid -j', () {
        final src = writeParityFixtures();
        final result = parseJobs(['-h', '-j', '0', '${src.path}/a.adoc']);
        expect(result.exitCode, equals(0));
        expect(result.out, equals(usageText));
      });
    });
  });

  group('conversion worker', () {
    ConversionRequest request(
      String infile, {
      String? toDir,
      bool toStdout = false,
    }) => ConversionRequest(
      infile: infile,
      options: AsciidoctorOptions(
        safe: SafeMode.unsafe,
        standalone: true,
        toDir: toDir,
        mkdirs: toDir != null,
      ),
      toStdout: toStdout,
      showTimings: false,
    );

    test('runConversionJob converts a file', () async {
      final src = writeParityFixtures();
      final dest = makeTempDir('jobs_codec_');
      final response = await runConversionJob(
        request('${src.path}/a.adoc', toDir: dest.path),
      );
      expect(response.ok, isTrue);
      expect(response.records, isEmpty);
      expect(
        File('${dest.path}/a.html').readAsStringSync(),
        contains('Hello A.'),
      );
    });

    test('runConversionJob captures log records with severities', () async {
      final src = writeParityFixtures();
      final dest = makeTempDir('jobs_codec_warn_');
      final response = await runConversionJob(
        request('${src.path}/b.adoc', toDir: dest.path),
      );
      expect(response.ok, isTrue);
      final record = response.records.single;
      expect(record.severity, equals(Severity.warn));
      expect(record.message, contains('section title out of sequence'));
    });

    test('runConversionJob captures converted text in stdout mode', () async {
      final src = writeParityFixtures();
      final response = await runConversionJob(
        request('${src.path}/a.adoc', toStdout: true),
      );
      expect(response.ok, isTrue);
      expect(response.output, contains('Hello A.'));
      // Nothing is written to disk in stdout mode.
      expect(src.listSync().whereType<File>(), hasLength(4));
    });

    test('runConversionJob reports failures as unsuccessful', () async {
      final src = writeParityFixtures();
      final response = await runConversionJob(
        request('${src.path}/no-such-file.adoc'),
      );
      expect(response.ok, isFalse);
      expect(response.error, contains('no-such-file.adoc'));
    });

    test('runConversionJob restores the logger', () async {
      final before = LoggerManager.logger;
      final src = writeParityFixtures();
      final dest = makeTempDir('jobs_codec_log_');
      await runConversionJob(request('${src.path}/a.adoc', toDir: dest.path));
      expect(identical(LoggerManager.logger, before), isTrue);
    });
  });

  group('parallel vs sequential parity', () {
    test('jobs=4 matches jobs=1: outputs, diagnostics, exit code', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src);
      final out1 = makeTempDir('jobs_seq_');
      final out4 = makeTempDir('jobs_par_');

      final seq = await invokeJobs(['-D', out1.path, ...inputs]);
      final par = await invokeJobs(['-j', '4', '-D', out4.path, ...inputs]);

      expect(par.invoker.code, equals(seq.invoker.code));
      expect(seq.invoker.code, equals(0));
      expect(par.out, equals(seq.out));
      expect(par.err, equals(seq.err));
      expect(par.err, contains('section title out of sequence'));
      expect(readOutputTree(out4), equals(readOutputTree(out1)));
      expect(
        readOutputTree(out4).keys,
        unorderedEquals(['a.html', 'b.html', 'c.html', 'd.html']),
      );
    });

    test('stdout mode stays byte-identical in input order', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src);

      final seq = await invokeJobs(['-o', '-', ...inputs]);
      final par = await invokeJobs(['-j', '4', '-o', '-', ...inputs]);

      expect(par.invoker.code, equals(seq.invoker.code));
      expect(par.out, equals(seq.out));
      expect(par.err, equals(seq.err));
      // Input order survives the fan-out: A before B before C before D.
      final order = ['Hello A.', 'Hello B.', 'undefined-target-xyz', 'one'];
      var cursor = 0;
      for (final marker in order) {
        final at = par.out.indexOf(marker, cursor);
        expect(at, greaterThanOrEqualTo(0), reason: marker);
        cursor = at;
      }
    });

    test('verbose diagnostics match', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src);
      final out1 = makeTempDir('jobs_verbose_seq_');
      final out4 = makeTempDir('jobs_verbose_par_');

      final seq = await invokeJobs(['-v', '-D', out1.path, ...inputs]);
      final par = await invokeJobs([
        '-j',
        '4',
        '-v',
        '-D',
        out4.path,
        ...inputs,
      ]);

      expect(par.invoker.code, equals(seq.invoker.code));
      expect(par.err, equals(seq.err));
      expect(par.err, contains('possible invalid reference'));
      expect(readOutputTree(out4), equals(readOutputTree(out1)));
    });

    test('failure level exit codes match', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src);

      Future<int> runWith(List<String> extra) async {
        final dest = makeTempDir('jobs_fail_');
        final result = await invokeJobs([...extra, '-D', dest.path, ...inputs]);
        return result.invoker.code;
      }

      // b.adoc warns: WARN trips --failure-level=WARN in both modes ...
      expect(await runWith(['--failure-level=WARN']), equals(1));
      expect(await runWith(['-j', '4', '--failure-level=WARN']), equals(1));
      // ... but stays below ERROR in both modes.
      expect(await runWith(['--failure-level=ERROR']), equals(0));
      expect(await runWith(['-j', '4', '--failure-level=ERROR']), equals(0));
    });

    test('quiet mode matches', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src);
      final out1 = makeTempDir('jobs_quiet_seq_');
      final out4 = makeTempDir('jobs_quiet_par_');

      final seq = await invokeJobs(['-q', '-D', out1.path, ...inputs]);
      final par = await invokeJobs([
        '-j',
        '4',
        '-q',
        '-D',
        out4.path,
        ...inputs,
      ]);

      expect(par.invoker.code, equals(seq.invoker.code));
      expect(seq.err, isEmpty);
      expect(par.err, isEmpty);
      expect(readOutputTree(out4), equals(readOutputTree(out1)));
    });

    test('timings reports keep per-file order plus an aggregate', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src);
      final out1 = makeTempDir('jobs_time_seq_');
      final out4 = makeTempDir('jobs_time_par_');

      final seq = await invokeJobs(['-t', '-D', out1.path, ...inputs]);
      final par = await invokeJobs([
        '-j',
        '4',
        '-t',
        '-D',
        out4.path,
        ...inputs,
      ]);

      expect(par.invoker.code, equals(0));
      // Per-file reports in input order in both modes.
      for (final result in [seq, par]) {
        final files = RegExp('Input file: (.*)')
            .allMatches(result.err)
            .map((m) => m.group(1))
            .toList();
        expect(files, equals(inputs));
      }
      // Same per-file structure; the parallel run appends the aggregate.
      final seqLines = normalizeTimings(seq.err).trim().split('\n');
      final parLines = normalizeTimings(par.err).trim().split('\n');
      expect(parLines.sublist(0, seqLines.length), equals(seqLines));
      expect(
        parLines.sublist(seqLines.length),
        equals([
          'Total time (all files, summed): #',
          'Total wall clock time (4 workers): #',
        ]),
      );
      expect(readOutputTree(out4), equals(readOutputTree(out1)));
    });

    test('explicit shared -o output matches', () async {
      final src = writeParityFixtures();
      final inputs = parityInputs(src).sublist(0, 2);
      final dir = makeTempDir('jobs_shared_o_');

      final seq = await invokeJobs(['-o', '${dir.path}/seq.html', ...inputs]);
      final par = await invokeJobs([
        '-j',
        '4',
        '-o',
        '${dir.path}/par.html',
        ...inputs,
      ]);

      expect(par.invoker.code, equals(seq.invoker.code));
      expect(par.err, equals(seq.err));
      expect(
        File('${dir.path}/par.html').readAsStringSync(),
        equals(File('${dir.path}/seq.html').readAsStringSync()),
      );
    });

    test('single file with -j stays on the main isolate', () async {
      final src = writeParityFixtures();
      final dest = makeTempDir('jobs_single_');
      final result = await invokeJobs([
        '-j',
        '4',
        '-D',
        dest.path,
        '${src.path}/a.adoc',
      ]);
      expect(result.invoker.code, equals(0));
      expect(result.invoker.documents, hasLength(1));
      expect(
        File('${dest.path}/a.html').readAsStringSync(),
        contains('Hello A.'),
      );
    });

    test('parallel fan-out leaves documents empty', () async {
      final src = writeParityFixtures();
      final dest = makeTempDir('jobs_docs_');
      final result = await invokeJobs([
        '-j',
        '4',
        '-D',
        dest.path,
        ...parityInputs(src),
      ]);
      expect(result.invoker.code, equals(0));
      // Documents are live, non-transferable objects (see Invoker.documents).
      expect(result.invoker.documents, isEmpty);
    });

    test('stdin with -j converts sequentially', () async {
      final result = await invokeJobs([
        '-j',
        '4',
        '-',
      ], stdinSource: () => '= Stdin Doc\n\nHello stdin.\n');
      expect(result.invoker.code, equals(0));
      expect(result.invoker.documents, hasLength(1));
      expect(result.out, contains('Hello stdin.'));
    });

    test('first hard failure wins in both modes', () async {
      final src = writeParityFixtures();
      File('${src.path}/bad.adoc').writeAsBytesSync([0xff, 0xfe, 0x00, 0x41]);
      final inputs = [
        '${src.path}/a.adoc',
        '${src.path}/bad.adoc',
        '${src.path}/c.adoc',
      ];
      final out1 = makeTempDir('jobs_err_seq_');
      final out4 = makeTempDir('jobs_err_par_');

      final seq = await invokeJobs(['-D', out1.path, ...inputs]);
      final par = await invokeJobs(['-j', '4', '-D', out4.path, ...inputs]);

      expect(seq.invoker.code, equals(1));
      expect(par.invoker.code, equals(1));
      expect(par.err, equals(seq.err));
      expect(par.err, contains('ptome: FAILED: failed to load ${inputs[1]}: '));
      expect(par.err, contains('Use --trace to show backtrace'));
      // The file before the failure converts in both modes.
      expect(File('${out1.path}/a.html').existsSync(), isTrue);
      expect(File('${out4.path}/a.html').existsSync(), isTrue);
    });

    test('--trace rethrows the worker failure message', () async {
      final src = writeParityFixtures();
      File('${src.path}/bad.adoc').writeAsBytesSync([0xff, 0xfe, 0x00, 0x41]);
      final inputs = ['${src.path}/a.adoc', '${src.path}/bad.adoc'];
      final dest = makeTempDir('jobs_trace_');

      Object? sequentialError;
      final out = StringBuffer();
      final err = StringBuffer();
      final seqInvoker = Invoker.fromArgs(
        ['--trace', '-D', dest.path, ...inputs],
        out: out,
        err: err,
        environment: <String, String>{},
      );
      try {
        seqInvoker.invoke();
        // Parity comparison must capture whatever surfaces, Errors included.
      } on Object catch (e) {
        sequentialError = e;
      }
      expect(sequentialError, isNotNull);

      final parInvoker = Invoker.fromArgs(
        ['-j', '4', '--trace', '-D', dest.path, ...inputs],
        out: StringBuffer(),
        err: StringBuffer(),
        environment: <String, String>{},
      );
      Object? parallelError;
      try {
        await parInvoker.invokeAsync();
        // Parity comparison must capture whatever surfaces, Errors included.
      } on Object catch (e) {
        parallelError = e;
      }
      expect(parallelError, isA<WorkerFailure>());
      expect(parallelError.toString(), equals(sequentialError.toString()));
    });

    test('invoke stays sequential when jobs exceeds 1', () async {
      // The synchronous entry point cannot fan out; it still converts
      // correctly (sequentially) rather than failing.
      final src = writeParityFixtures();
      final dest = makeTempDir('jobs_sync_');
      final out = StringBuffer();
      final err = StringBuffer();
      final invoker = Invoker.fromArgs(
        ['-j', '4', '-D', dest.path, ...parityInputs(src)],
        out: out,
        err: err,
        environment: <String, String>{},
      )..redirectStreams(out, err);
      final savedLogger = LoggerManager.logger;
      LoggerManager.logger = Logger(sink: err)..level = savedLogger.level;
      try {
        invoker.invoke();
      } finally {
        LoggerManager.logger = savedLogger;
      }
      expect(invoker.code, equals(0));
      expect(invoker.documents, hasLength(4));
      expect(readOutputTree(dest).keys, hasLength(4));
    });
  });
}
