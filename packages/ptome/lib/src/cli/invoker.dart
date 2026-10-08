/// Command-line invocation for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/cli/invoker.rb` (`Asciidoctor::Cli::Invoker`).
///
/// ## Differences from Asciidoctor 2.1.0.alpha.0
///
/// - Construction uses named constructors ([Invoker.fromOptions],
///   [Invoker.fromArgs]).
/// - Tests supply stdin through the [Invoker.invoke] `stdinSource` callback.
///   Without it, stdin is read fully as UTF-8.
/// - Missing input files (only possible with hand-built [CliOptions],
///   never via parsing) convert zero files and succeed, where Asciidoctor
///   crashes.
/// - `SOURCE_DATE_EPOCH` is left untouched (Asciidoctor clears it only to
///   work around a RubyGems issue).
/// - Signals are not delivered as exceptions, so an interactive SIGINT
///   terminates the VM with its default exit code instead of exiting with
///   the signal number.
/// - Processor failures always yield exit code 1.
/// - The failure message is the error's `toString()`.
/// - `.`/`..` segments are normalized lexically with `Uri.normalizePath`;
///   symlinks are not resolved. Backslash folding applies on Windows only.
library;

import 'dart:math' show min;

import 'package:ptome/src/cli/diagnostics.dart';
import 'package:ptome/src/cli/options.dart';
import 'package:ptome/src/cli/parallel.dart';
import 'package:ptome/src/cli/workers.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/load.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/options.dart';
import 'package:ptome/src/path_resolver.dart';
import 'package:ptome/src/remote.dart';
import 'package:ptome/src/timings.dart';

/// Runs the Asciidoctor processor from parsed command-line options.
///
/// Port of `Asciidoctor::Cli::Invoker`. Construct from parsed options
/// ([Invoker.fromOptions]) or raw arguments ([Invoker.fromArgs], which
/// parses via [CliOptions]), then call [invoke] and read [code].
final class Invoker {
  /// Creates an invoker for already-parsed [options].
  new fromOptions(CliOptions options) : _options = options;

  /// Creates an invoker by parsing [args] via [CliOptions].
  ///
  /// On success [options] holds the parsed options and [code] is 0. When
  /// parsing ends early (help, version, or an error) [options] is `null`
  /// and [code] holds the exit code.
  ///
  /// [out] and [err] receive parse-time output (defaulting to the process
  /// streams); [environment] supplies environment variables (defaulting to
  /// the process environment).
  new fromArgs(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    Map<String, String>? environment,
  }) {
    final (:options, :exitCode) = CliOptions.parseArgs(
      args,
      out: out,
      err: err,
      environment: environment,
    );
    if (exitCode != null) {
      _code = exitCode;
      _options = null;
    } else {
      _options = options;
    }
  }

  CliOptions? _options;
  int _code = 0;
  StringSink? _out;
  StringSink? _err;

  /// The parsed options, or `null` when argument parsing ended early
  /// ([code] then holds the exit code).
  CliOptions? get options => _options;

  /// The converted documents, in input order.
  ///
  /// Only populated by the sequential path ([invoke] and [invokeAsync]
  /// without fan-out). The parallel path leaves this empty: documents are
  /// live, non-transferable objects, and re-parsing them on the main isolate
  /// would erase the parallel speedup.
  final List<Document> documents = [];

  /// The process exit code for this invocation.
  int get code => _code;

  /// The first converted document, or `null` when nothing was converted.
  Document? get document => documents.isEmpty ? null : documents.first;

  /// Converts the input files described by [options].
  ///
  /// Port of `Invoker#invoke!`: a `null` [options] is a no-op (the exit
  /// [code] was already set by parsing). When the single input is `-`,
  /// stdin supplies the source: [stdinSource] is called when given
  /// (as tests do), otherwise stdin is
  /// read fully as UTF-8. Processor failures set [code] to 1 (or rethrow
  /// when `--trace` was given) and report to the error stream; a logger
  /// severity at or above the failure level also yields exit code 1.
  ///
  /// Always converts sequentially on the current isolate, even when
  /// [CliOptions.jobs] exceeds 1; use [invokeAsync] for parallel fan-out.
  void invoke({String Function()? stdinSource}) {
    final options = _options;
    if (options == null) return;
    final err = _err ?? io.standardError;
    // NOTE trace is consumed here (it is not a processor option).
    final restoreLogger = _applyVerbosity(options);
    final conversions = _conversions(options, err, stdinSource);
    try {
      for (final conversion in conversions) {
        conversion.done(conversion.convert());
      }
      _checkSeverity(options);
    } catch (e) {
      if (io.isBrokenPipe(e)) rethrow;
      _code = 1;
      if (options.trace) rethrow;
      _reportFailure(err, e);
    } finally {
      restoreLogger();
    }
  }

  /// Like [invoke], awaiting the work each conversion runs on other cores
  /// (ADR-0016) before writing its output.
  Future<void> _invokeFinishing({String Function()? stdinSource}) async {
    final options = _options;
    if (options == null) return;
    final err = _err ?? io.standardError;
    final restoreLogger = _applyVerbosity(options);
    final conversions = _conversions(options, err, stdinSource);
    try {
      for (final conversion in conversions) {
        conversion.done(await conversion.finishing());
      }
      _checkSeverity(options);
    } catch (e) {
      if (io.isBrokenPipe(e)) rethrow;
      _code = 1;
      if (options.trace) rethrow;
      _reportFailure(err, e);
    } finally {
      restoreLogger();
    }
  }

  /// The conversions [invoke] runs, in order (set up as they are reached):
  /// each converts (or converts awaiting its work on other cores), and is
  /// done with its document.
  Iterable<_Conversion> _conversions(
    CliOptions options,
    StringSink err,
    String Function()? stdinSource,
  ) sync* {
    final infiles = options.inputFiles ?? <String>[];
    var outfile = options.outputFile;
    final sourceDir = options.sourceDir;
    final absSrcdirPosix = sourceDir == null ? null : _expandPath(sourceDir);
    final showTimings = options.timings;
    final baseOptions = _processorOptions(options)
        .copyWith(uriReader: _uriReader);

    var stdinInput = false;
    if (infiles.length == 1) {
      final infile0 = infiles[0];
      if (infile0 == '-') {
        outfile ??= infile0;
        stdinInput = true;
      } else if (_isPipe(infile0)) {
        outfile ??= '-';
      }
    }

    StringSink? sink;
    var opts = baseOptions;
    if (outfile == '-') {
      final out = _out;
      if (out == null) {
        sink = io.standardOutput;
      } else {
        sink = out;
      }
    } else {
      // An explicit output file, or one derived from the input file.
      opts = opts.copyWith(mkdirs: true, toFile: outfile);
    }

    void Function(Document) done(Timings? timings, String subject) =>
        (document) {
          documents.add(document);
          if (showTimings) timings?.printReport(err, subject);
        };

    if (stdinInput) {
      final input = stdinSource != null ? stdinSource() : _readStdin();
      final timings = _timings(options, '-', err);
      final targetOptions = opts.copyWith(timings: timings);
      yield (
        convert: () => convertToTarget(input, targetOptions, sink),
        finishing: () => convertToTargetFinishing(input, targetOptions, sink),
        done: done(timings, '-'),
      );
    } else {
      for (final infile in infiles) {
        final timings = _timings(options, infile, err);
        final fileOptions = _withSourceDir(
          opts,
          infile,
          absSrcdirPosix,
        ).copyWith(timings: timings);
        yield (
          convert: () => convertFile(infile, fileOptions, sink),
          finishing: () => convertFileFinishing(infile, fileOptions, sink),
          done: done(timings, infile),
        );
      }
    }
  }

  /// Sets the exit [code] to 1 when the worst message logged reaches the
  /// failure level.
  void _checkSeverity(CliOptions options) {
    final maxSeverity = LoggerManager.logger.maxSeverity;
    if (maxSeverity != null &&
        maxSeverity.value >= options.failureLevel.value) {
      _code = 1;
    }
  }

  static void _reportFailure(StringSink err, Object error) => err
    ..writeln(failureLine(error))
    ..writeln('  Use --trace to show backtrace');

  /// Converts the input files, fanning out to worker isolates when `-j` asks.
  ///
  /// Specific to this port: when [CliOptions.jobs] exceeds 1
  /// and several input files are given, each file converts on a pooled
  /// worker isolate and the per-file results are replayed in input order,
  /// so converted output, diagnostics and the exit [code] match the
  /// sequential run (see [_invokeParallel]). Otherwise — single input file,
  /// stdin conversion, an explicit shared `-o` target (whose concurrent
  /// writes could not stay ordered), or `jobs <= 1` — this simply runs the
  /// sequential [invoke] on the current isolate.
  Future<void> invokeAsync({String Function()? stdinSource}) async {
    final options = _options;
    if (options == null) return;
    final infiles = options.inputFiles ?? <String>[];
    final multiFile = infiles.length > 1;
    final stdinInput = infiles.length == 1 && infiles[0] == '-';
    final outfile = options.outputFile;
    final sharedOutfile = outfile != null && outfile != '-' && multiFile;
    if (options.jobs > 1 && multiFile && !stdinInput && !sharedOutfile) {
      await _invokeParallel();
      return;
    }
    var source = stdinSource;
    if (_allowsUriRead(options)) {
      // Fetch the remote content the inputs read before converting them.
      final cache = <String, RemoteResource?>{};
      final base = _processorOptions(options);
      if (stdinInput) {
        final input = stdinSource != null ? stdinSource() : _readStdin();
        source = () => input;
        await prefetchRemoteContent(base, cache, source: input);
      } else {
        for (final infile in infiles) {
          // A named pipe can be read only once.
          if (_isPipe(infile)) continue;
          try {
            await prefetchRemoteContent(base, cache, path: infile);
            // The conversion reports any failure, so prefetching ignores it.
            // ignore: avoid_catches_without_on_clauses
          } catch (_) {}
        }
      }
      _uriReader = cachedUriReader(cache);
    }
    await _invokeFinishing(stdinSource: source);
  }

  /// The reader for remote content fetched by [invokeAsync].
  UriReader? _uriReader;

  /// Whether the `allow-uri-read` attribute is set on the command line.
  static bool _allowsUriRead(CliOptions options) =>
      options.attributes?['allow-uri-read'] != null;

  /// Converts several input files on a pool of worker isolates.
  ///
  /// The option setup mirrors [invoke] (keep the two in sync); only the
  /// conversion loop differs. One job per input file runs on a fixed pool of
  /// `min(jobs, fileCount)` long-lived isolates spawned once for this call.
  /// Each worker converts with the same options, attributes, safe mode and
  /// failure level as the sequential path, captures its log records and
  /// phase timings, and (in `-o -` mode) its converted text; the main
  /// isolate then replays logs, STDOUT text and per-file timing reports in
  /// input order and derives [code] from the replayed worst severity
  /// exactly like [invoke].
  ///
  /// Two deliberate divergences from a sequential run: with `-t`, one
  /// aggregate (summed per-file times plus wall clock) follows the per-file
  /// reports (see `cli/parallel.dart`); and when a file fails hard, files
  /// already dispatched to other workers may still be converted on disk
  /// (their logs, output and timings are dropped, and the error report and
  /// exit code match the sequential stop-at-first-failure exactly).
  Future<void> _invokeParallel() async {
    final options = _options!;
    final err = _err ?? io.standardError;
    final infiles = options.inputFiles ?? <String>[];
    final outfile = options.outputFile;
    final sourceDir = options.sourceDir;
    final absSrcdirPosix = sourceDir == null ? null : _expandPath(sourceDir);
    final showTimings = options.timings;
    final restoreLogger = _applyVerbosity(options);
    final baseOptions = _processorOptions(options);

    try {
      // The caller excluded stdin input and shared explicit `-o` targets, so
      // the output is either STDOUT or per-input derived files.
      final toStdout = outfile == '-';
      StringSink? sink;
      var opts = baseOptions;
      if (toStdout) {
        final out = _out;
        if (out == null) {
          sink = io.standardOutput;
        } else {
          sink = out;
        }
      } else {
        opts = opts.copyWith(mkdirs: true);
      }

      final requests = <ConversionRequest>[
        for (final infile in infiles)
          ConversionRequest(
            infile: infile,
            options: _withSourceDir(opts, infile, absSrcdirPosix),
            toStdout: toStdout,
            showTimings: showTimings,
          ),
      ];

      final workerCount = min(options.jobs, infiles.length);
      final wallClock = Stopwatch()..start();
      final responses = await convertOnWorkers(requests, workerCount);
      wallClock.stop();

      // Replay in input order. The first hard failure stops the replay like
      // the sequential loop's exception (later jobs' logs, output and
      // timings are dropped).
      final logger = LoggerManager.logger;
      String? workerError;
      var summedSeconds = 0.0;
      for (var i = 0; i < responses.length; i++) {
        final response = responses[i];
        replayRecords(logger, response.records);
        if (!response.ok) {
          workerError = response.error;
          break;
        }
        if (sink != null) sink.write(response.output);
        final timingsLog = response.timings;
        if (showTimings && timingsLog != null) {
          final workerTimings = Timings()
            ..log.addAll(timingsLog)
            ..printReport(err, infiles[i]);
          summedSeconds += workerTimings.readParseConvert ?? 0;
        }
      }
      if (workerError != null) {
        _code = 1;
        final failure = WorkerFailure(workerError);
        if (options.trace) throw failure;
        err
          ..writeln(failureLine(failure))
          ..writeln('  Use --trace to show backtrace');
        return;
      }
      if (showTimings) {
        err.writeln(
          'Total time (all files, summed): ${summedSeconds.toStringAsFixed(5)}',
        );
        final wallSeconds =
            wallClock.elapsedMicroseconds / Duration.microsecondsPerSecond;
        err.writeln(
          'Total wall clock time ($workerCount workers): '
          '${wallSeconds.toStringAsFixed(5)}',
        );
      }
      final maxSeverity = logger.maxSeverity;
      if (maxSeverity != null &&
          maxSeverity.value >= options.failureLevel.value) {
        _code = 1;
      }
    } catch (e) {
      if (io.isBrokenPipe(e)) rethrow;
      _code = 1;
      if (options.trace) rethrow;
      err
        ..writeln(failureLine(e))
        ..writeln('  Use --trace to show backtrace');
    } finally {
      restoreLogger();
    }
  }

  /// The timings of converting [subject], when `-t` or `--progress` asks
  /// for them; with `--progress`, each phase is reported to [err] as it
  /// finishes.
  static Timings? _timings(CliOptions options, String subject, StringSink err) {
    if (!options.timings && !options.progress) return null;
    return Timings(
      onRecord: options.progress
          ? (phase, seconds) => err.writeln(
              'ptome: $subject: $phase done in '
              '${(seconds * 1000).round()} ms',
            )
          : null,
    );
  }

  /// Applies the verbosity of [options] to the global logger (silenced for
  /// `-q`, else the `--log-level`, or debug level for `-v`) and returns a
  /// callback restoring it.
  static void Function() _applyVerbosity(CliOptions options) {
    if (options.verbose == 0) {
      final savedLogger = LoggerManager.logger;
      LoggerManager.logger = NullLogger();
      return () => LoggerManager.logger = savedLogger;
    }
    // `--log-level` wins over `-v` (lib/asciidoctor/cli/invoker.rb).
    final level =
        options.logLevel ?? (options.verbose == 2 ? Severity.debug : null);
    if (level == null) return () {};
    final logger = LoggerManager.logger;
    final savedLevel = logger.level;
    logger.level = level;
    return () => logger.level = savedLevel;
  }

  /// Adjusts the processor options before each conversion: a custom
  /// command's configuration (extensions, output overrides, highlighters).
  AsciidoctorOptions Function(AsciidoctorOptions options)? configure;

  /// The processor options for [options], before output targets.
  AsciidoctorOptions _processorOptions(CliOptions options) {
    final processorOptions = AsciidoctorOptions(
      safe: options.safe,
      standalone: options.standalone,
      attributes: options.attributes ?? const <String, String?>{},
      templateDirs: options.templateDirs ?? const <String>[],
      templateEngine: options.templateEngine,
      baseDir: options.baseDir,
      toDir: options.destinationDir,
      sourcemap: options.sourcemap ?? false,
    );
    return configure?.call(processorOptions) ?? processorOptions;
  }

  /// Mirrors the input file's position below the `-R` source directory
  /// ([absSrcdir]) in the destination directory.
  static AsciidoctorOptions _withSourceDir(
    AsciidoctorOptions opts,
    String infile,
    String? absSrcdir,
  ) {
    final toDir = opts.toDir;
    if (absSrcdir == null || toDir == null) return opts;
    final absIndir = _dirname(_expandPath(infile));
    if (!absIndir.startsWith('$absSrcdir/')) return opts;
    return opts.copyWith(
      toDir: '$toDir${absIndir.substring(absSrcdir.length)}',
    );
  }

  /// Redirects converted output ([out]) and reports ([err]) to buffers.
  ///
  /// Port of `Invoker#redirect_streams`. When [err] is omitted, reports
  /// keep going to stderr.
  void redirectStreams(StringSink out, [StringSink? err]) {
    _out = out;
    _err = err;
  }

  /// Returns the redirected output buffer, or `''` when [redirectStreams]
  /// was not called (or the target is not a [StringBuffer]).
  String readOutput() {
    final out = _out;
    return out is StringBuffer ? out.toString() : '';
  }

  /// Returns the redirected error buffer, or `''` when [redirectStreams]
  /// was not called with an error target (or it is not a [StringBuffer]).
  String readError() {
    final err = _err;
    return err is StringBuffer ? err.toString() : '';
  }

  /// Clears the [redirectStreams] targets.
  void resetStreams() {
    _out = null;
    _err = null;
  }
}

/// Whether [path] is a named pipe.
bool _isPipe(String path) => io.isPipe(path);

/// The absolute, lexically normalized form of [path] with forward slashes
/// on Windows.
String _expandPath(String path) {
  final resolver = PathResolver();
  final absolute = resolver.isRoot(path)
      ? path
      : resolver.joinPath([io.currentDirectory, path]);
  return resolver.expandPath(absolute);
}

/// Reads stdin fully and decodes it as UTF-8.
String _readStdin() => io.readStdin();

/// The parent directory of an (expanded) absolute [path].
String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  if (slash <= 0) return path;
  return path.substring(0, slash);
}

/// A conversion [Invoker.invoke] runs: how to convert (or convert awaiting
/// the work on other cores), and what to do with the document.
typedef _Conversion = ({
  Document Function() convert,
  Future<Document> Function() finishing,
  void Function(Document document) done,
});
