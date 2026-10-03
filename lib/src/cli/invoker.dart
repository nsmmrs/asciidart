/// Command-line invocation for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/cli/invoker.rb` (`Asciidoctor::Cli::Invoker`).
///
/// ## Deliberate divergences from `invoker.rb`
///
/// - Construction is split into named constructors ([Invoker.fromOptions],
///   [Invoker.fromMap], [Invoker.fromArgs]) because Dart has no splat
///   arguments; Ruby's `*options` flattening has no analog.
/// - Ruby's `invoke!` block (which supplies stdin, used by tests) becomes the
///   [Invoker.invoke] `stdinSource` callback. Without it, stdin is read fully
///   as UTF-8 (`stdin.readAsStringSync(encoding: utf8)`), matching Ruby's
///   forced UTF-8 stdio encoding.
/// - `Invoker.fromMap` ignores the `failure_level`, `trace` and `timings`
///   seeds, exactly as Ruby's `Options#initialize` does, and drops unknown
///   keys (Ruby only reads known keys out of the hash).
/// - A missing `input_files` entry (only possible via [Invoker.fromMap] or a
///   hand-built [CliOptions], never via parsing) converts zero files and
///   succeeds; Ruby crashes with a `NoMethodError` on `nil.size` there.
/// - `-r/--require` libraries are already resolved (and rejected) during
///   [CliOptions.parse], as documented in `cli/options.dart`; there is
///   nothing left for the invoker to require.
/// - Dart has no `$VERBOSE`, so `-w` is only forwarded to the processor in
///   the `warnings` option; there is no script-warning flag to set and
///   restore, and no `refute`-style `$VERBOSE` round-trip to preserve.
/// - `SOURCE_DATE_EPOCH` handling is a no-op: Ruby only deletes the variable
///   to neutralize RubyGems' Ruby 2.7 behavior, and Dart has no RubyGems. The
///   process environment is read-only in Dart anyway.
/// - Signal delivery differs: Ruby raises `SignalException` inside `invoke!`
///   (exit code = signal number, plus a newline for `Interrupt`). Dart
///   delivers no signals as exceptions, so that branch has no port; an
///   interactive SIGINT terminates the VM with its default exit code.
/// - Ruby reports `e.status` as the exit code when the raised error responds
///   to it (e.g. `SystemExit`); Dart errors carry no status, so processor
///   failures always yield exit code 1.
/// - The failure message is the error's `toString()` (Dart exceptions expose
///   no uniform `message` getter); Ruby's `RuntimeError`-only
///   `"#{message} (#{class})"` suffix has no Dart analog.
/// - `File.expand_path` lexical normalization of `.`/`..` segments is
///   approximated with `Uri.normalizePath`; symlinks are not resolved, as in
///   Ruby. Backslash folding applies on Windows only, as in Ruby.
/// - The `to_dir`/`to_file`/`mkdirs`/`timings`/`failure_level` option keys
///   passed to the processor are snake_case strings, mirroring the Ruby
///   symbol keys; the `port/load` merge owns that contract.
library;

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' show min;

import '../abstract_node.dart';
import '../document.dart';
import '../job_pool.dart';
import '../load.dart';
import '../logging.dart';
import '../timings.dart';
import 'options.dart';
import 'parallel.dart';

/// Runs the Asciidoctor processor from parsed command-line options.
///
/// Port of `Asciidoctor::Cli::Invoker`. Construct from parsed options
/// ([Invoker.fromOptions]), an options map ([Invoker.fromMap], the `Hash`
/// form) or raw arguments ([Invoker.fromArgs], which parses via
/// [CliOptions]), then call [invoke] and read [code].
final class Invoker with Logging {
  /// Creates an invoker for already-parsed [options].
  Invoker.fromOptions(CliOptions options) : _options = options;

  /// Creates an invoker from an options [map] (the Ruby `Hash` form).
  ///
  /// Known snake_case keys (camelCase aliases accepted) seed a [CliOptions]
  /// exactly as Ruby's `Options#initialize` reads them: `attributes`,
  /// `input_files`, `output_file`, `safe` (an [int] level or a level name),
  /// `standalone`, `template_dirs`, `template_engine`, `doctype`, `backend`,
  /// `eruby`, `verbose`, `warnings`, `load_paths`, `requires`, `base_dir`,
  /// `source_dir`, `destination_dir`, `log_level`, `sourcemap`. The
  /// `failure_level`, `trace` and `timings` seeds are ignored (as in Ruby)
  /// and unknown keys are dropped.
  Invoker.fromMap(Map<String, Object?> map) : _options = _optionsFromMap(map);

  /// Creates an invoker by parsing [args] via [CliOptions].
  ///
  /// On success [options] holds the parsed options and [code] is 0. When
  /// parsing ends early (help, version, or an error) [options] is `null`
  /// and [code] holds the exit code, mirroring Ruby's
  /// `Integer === Options.parse!(options)` branch.
  ///
  /// [out] and [err] receive parse-time output (defaulting to the process
  /// streams); [environment] supplies environment variables (defaulting to
  /// [Platform.environment]).
  Invoker.fromArgs(
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
  /// (mirroring the Ruby block form, used by tests), otherwise stdin is
  /// read fully as UTF-8. Processor failures set [code] to 1 (or rethrow
  /// when `--trace` was given) and report to the error stream; a logger
  /// severity at or above the failure level also yields exit code 1.
  ///
  /// Always converts sequentially on the current isolate, even when
  /// [CliOptions.jobs] exceeds 1; use [invokeAsync] for parallel fan-out.
  void invoke({String Function()? stdinSource}) {
    final options = _options;
    if (options == null) return;

    final err = _err ?? stderr;
    final opts = <String, Object?>{};
    final infiles = options.inputFiles ?? <String>[];
    String? outfile = options.outputFile;
    final sourceDir = options.sourceDir;
    final absSrcdirPosix = sourceDir == null ? null : _expandPath(sourceDir);
    final destinationDir = options.destinationDir;
    if (destinationDir != null) opts['to_dir'] = destinationDir;
    final attributes = options.attributes;
    if (attributes != null) opts['attributes'] = attributes;
    final showTimings = options.timings;
    // NOTE :trace is consumed here (no assignment to processor options).
    LoggerBase? savedLogger;
    Severity? savedLevel;
    if (options.verbose == 0) {
      savedLogger = LoggerManager.logger;
      LoggerManager.logger = NullLogger();
    } else if (options.verbose == 2) {
      savedLevel = LoggerManager.logger.level;
      LoggerManager.logger.level = Severity.debug;
    }
    // Every other option passes through unless null (Ruby's `else` branch).
    opts['safe'] = options.safe;
    opts['standalone'] = options.standalone;
    opts['warnings'] = options.warnings;
    opts['failure_level'] = options.failureLevel;
    _putIfPresent(opts, 'template_dirs', options.templateDirs);
    _putIfPresent(opts, 'template_engine', options.templateEngine);
    _putIfPresent(opts, 'eruby', options.eruby);
    _putIfPresent(opts, 'base_dir', options.baseDir);
    _putIfPresent(opts, 'sourcemap', options.sourcemap);
    _putIfPresent(opts, 'log_level', options.logLevel);
    _putIfPresent(opts, 'load_paths', options.loadPaths);
    _putIfPresent(opts, 'requires', options.requires);

    final logLevel = opts.remove('log_level') as Severity?;
    if (logLevel != null && savedLogger == null) {
      savedLevel ??= LoggerManager.logger.level;
      LoggerManager.logger.level = logLevel;
    }

    try {
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

      Object? tofile;
      if (outfile == '-') {
        final out = _out;
        if (out == null) {
          // Mirrors `$stdout.set_encoding UTF_8`.
          stdout.encoding = utf8;
          tofile = stdout;
        } else {
          tofile = out;
        }
      } else if (outfile != null) {
        opts['mkdirs'] = true;
        tofile = outfile;
      } else {
        opts['mkdirs'] = true;
        // tofile stays null: the outfile is derived from the infile.
      }

      if (stdinInput) {
        final input = stdinSource != null ? stdinSource() : _readStdin();
        final inputOpts = Map<String, Object?>.of(opts)..['to_file'] = tofile;
        if (showTimings) {
          final timings = Timings();
          inputOpts['timings'] = timings;
          documents.add(convert(input, inputOpts) as Document);
          timings.printReport(err, '-');
        } else {
          documents.add(convert(input, inputOpts) as Document);
        }
      } else {
        for (final infile in infiles) {
          // Fresh merge per file so the `to_dir` adjustment below never
          // accumulates across files.
          final inputOpts = Map<String, Object?>.of(opts)..['to_file'] = tofile;
          final srcdir = absSrcdirPosix;
          if (srcdir != null && inputOpts.containsKey('to_dir')) {
            final absIndir = _dirname(_expandPath(infile));
            if (absIndir.startsWith('$srcdir/')) {
              inputOpts['to_dir'] =
                  '${inputOpts['to_dir']}${absIndir.substring(srcdir.length)}';
            }
          }
          if (showTimings) {
            final timings = Timings();
            inputOpts['timings'] = timings;
            documents.add(convertFile(infile, inputOpts) as Document);
            timings.printReport(err, infile);
          } else {
            documents.add(convertFile(infile, inputOpts) as Document);
          }
        }
      }
      final maxSeverity = logger.maxSeverity;
      if (maxSeverity != null &&
          maxSeverity.value >= options.failureLevel.value) {
        _code = 1;
      }
    } catch (e) {
      _code = 1;
      if (options.trace) rethrow;
      err.writeln(e.toString());
      err.writeln('  Use --trace to show backtrace');
    } finally {
      if (savedLogger != null) {
        LoggerManager.logger = savedLogger;
      } else if (savedLevel != null) {
        LoggerManager.logger.level = savedLevel;
      }
    }
  }

  /// Converts the input files, fanning out to worker isolates when `-j` asks.
  ///
  /// Dart-only extension (no Ruby analog): when [CliOptions.jobs] exceeds 1
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
    } else {
      invoke(stdinSource: stdinSource);
    }
  }

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
    final err = _err ?? stderr;
    final opts = <String, Object?>{};
    final infiles = options.inputFiles ?? <String>[];
    final outfile = options.outputFile;
    final sourceDir = options.sourceDir;
    final absSrcdirPosix = sourceDir == null ? null : _expandPath(sourceDir);
    final destinationDir = options.destinationDir;
    if (destinationDir != null) opts['to_dir'] = destinationDir;
    final attributes = options.attributes;
    if (attributes != null) opts['attributes'] = attributes;
    final showTimings = options.timings;
    LoggerBase? savedLogger;
    Severity? savedLevel;
    if (options.verbose == 0) {
      savedLogger = LoggerManager.logger;
      LoggerManager.logger = NullLogger();
    } else if (options.verbose == 2) {
      savedLevel = LoggerManager.logger.level;
      LoggerManager.logger.level = Severity.debug;
    }
    // Every other option passes through unless null (Ruby's `else` branch).
    opts['safe'] = options.safe;
    opts['standalone'] = options.standalone;
    opts['warnings'] = options.warnings;
    opts['failure_level'] = options.failureLevel;
    _putIfPresent(opts, 'template_dirs', options.templateDirs);
    _putIfPresent(opts, 'template_engine', options.templateEngine);
    _putIfPresent(opts, 'eruby', options.eruby);
    _putIfPresent(opts, 'base_dir', options.baseDir);
    _putIfPresent(opts, 'sourcemap', options.sourcemap);
    _putIfPresent(opts, 'log_level', options.logLevel);
    _putIfPresent(opts, 'load_paths', options.loadPaths);
    _putIfPresent(opts, 'requires', options.requires);

    final logLevel = opts.remove('log_level') as Severity?;
    if (logLevel != null && savedLogger == null) {
      savedLevel ??= LoggerManager.logger.level;
      LoggerManager.logger.level = logLevel;
    }

    try {
      // The caller excluded stdin input and shared explicit `-o` targets, so
      // `tofile` is either the STDOUT sink or per-input derived outputs.
      final toStdout = outfile == '-';
      Object? tofile;
      if (toStdout) {
        final out = _out;
        if (out == null) {
          stdout.encoding = utf8;
          tofile = stdout;
        } else {
          tofile = out;
        }
      } else {
        opts['mkdirs'] = true;
        tofile = null;
      }

      final requests = <Map<String, Object?>>[];
      for (final infile in infiles) {
        // Fresh merge per file so the `to_dir` adjustment below never
        // accumulates across files (same computation as [invoke]).
        final inputOpts = Map<String, Object?>.of(opts)..['to_file'] = tofile;
        final srcdir = absSrcdirPosix;
        if (srcdir != null && inputOpts.containsKey('to_dir')) {
          final absIndir = _dirname(_expandPath(infile));
          if (absIndir.startsWith('$srcdir/')) {
            inputOpts['to_dir'] =
                '${inputOpts['to_dir']}${absIndir.substring(srcdir.length)}';
          }
        }
        requests.add(
          buildConversionRequest(
            infile: infile,
            processorOptions: inputOpts,
            toStdout: toStdout,
            showTimings: showTimings,
          ),
        );
      }

      final workerCount = min(options.jobs, infiles.length);
      final pool = await IsolateJobPool.spawn(
        size: workerCount,
        entryPoint: conversionWorkerMain,
      );
      final wallClock = Stopwatch()..start();
      List<Map<String, Object?>> responses;
      try {
        responses = await pool.runOrdered(requests);
      } finally {
        wallClock.stop();
        await pool.close();
      }

      // Replay in input order. The first hard failure stops the replay like
      // the sequential loop's exception (later jobs' logs, output and
      // timings are dropped).
      String? workerError;
      var summedSeconds = 0.0;
      for (var i = 0; i < responses.length; i++) {
        final response = responses[i];
        replayRecords(logger, response['records']);
        if (response['ok'] != true) {
          workerError = response['error'] as String?;
          break;
        }
        if (toStdout) (tofile as StringSink).write(response['output']);
        if (showTimings) {
          final workerTimings = Timings()
            ..log.addAll((response['timings'] as Map).cast<String, double>());
          workerTimings.printReport(err, infiles[i]);
          summedSeconds += workerTimings.readParseConvert ?? 0;
        }
      }
      if (workerError != null) {
        _code = 1;
        if (options.trace) throw WorkerFailure(workerError);
        err.writeln(workerError);
        err.writeln('  Use --trace to show backtrace');
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
      _code = 1;
      if (options.trace) rethrow;
      err.writeln(e.toString());
      err.writeln('  Use --trace to show backtrace');
    } finally {
      if (savedLogger != null) {
        LoggerManager.logger = savedLogger;
      } else if (savedLevel != null) {
        LoggerManager.logger.level = savedLevel;
      }
    }
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

  /// Builds a [CliOptions] from a Ruby-style options [map].
  static CliOptions _optionsFromMap(Map<String, Object?> map) {
    Object? get(String snake, [String? camel]) {
      if (map.containsKey(snake)) return map[snake];
      if (camel != null && map.containsKey(camel)) return map[camel];
      return null;
    }

    List<String>? stringList(Object? value) {
      if (value == null) return null;
      if (value is List<String>) return value;
      if (value is Iterable) {
        return value.map((element) => element.toString()).toList();
      }
      throw ArgumentError.value(value, 'options map entry', 'expected a List');
    }

    final attributes = get('attributes');
    return CliOptions(
      attributes: attributes == null
          ? null
          : (attributes as Map).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
      inputFiles: stringList(get('input_files', 'inputFiles')),
      outputFile: get('output_file', 'outputFile') as String?,
      safe: _coerceSafe(get('safe')),
      standalone: (get('standalone') as bool?) ?? true,
      templateDirs: get('template_dirs', 'templateDirs'),
      templateEngine: get('template_engine', 'templateEngine') as String?,
      doctype: get('doctype') as String?,
      backend: get('backend') as String?,
      eruby: get('eruby') as String?,
      verbose: (get('verbose') as int?) ?? 1,
      warnings: (get('warnings') as bool?) ?? false,
      loadPaths: stringList(get('load_paths', 'loadPaths')),
      requires: stringList(get('requires')),
      baseDir: get('base_dir', 'baseDir') as String?,
      sourceDir: get('source_dir', 'sourceDir') as String?,
      destinationDir: get('destination_dir', 'destinationDir') as String?,
      logLevel: get('log_level', 'logLevel'),
      sourcemap: get('sourcemap') as bool?,
    );
  }

  /// Coerces a `safe` seed to a level, accepting names for convenience.
  static int? _coerceSafe(Object? value) {
    if (value == null || value is int) return value as int?;
    if (value is String) {
      switch (value) {
        case 'unsafe':
          return SafeMode.unsafe;
        case 'safe':
          return SafeMode.safe;
        case 'server':
          return SafeMode.server;
        case 'secure':
          return SafeMode.secure;
      }
    }
    throw ArgumentError.value(value, 'safe', 'expected a level or its name');
  }
}

/// Assigns `opts[key] = value` unless [value] is `null`.
void _putIfPresent(Map<String, Object?> opts, String key, Object? value) {
  if (value != null) opts[key] = value;
}

/// Whether [path] is a named pipe (cf. Ruby `File.pipe?`).
bool _isPipe(String path) {
  try {
    return FileSystemEntity.typeSync(path) == FileSystemEntityType.pipe;
  } catch (_) {
    return false;
  }
}

/// The absolute, lexically normalized form of [path] with forward slashes
/// on Windows (cf. Ruby `File.expand_path` plus the `RS`/`FS` tilt).
String _expandPath(String path) {
  var expanded = File(path).absolute.uri.normalizePath().toFilePath();
  if (Platform.isWindows) expanded = expanded.replaceAll('\\', '/');
  if (expanded.length > 1 && expanded.endsWith('/')) {
    expanded = expanded.substring(0, expanded.length - 1);
  }
  return expanded;
}

/// Reads stdin fully and decodes it as UTF-8 (cf. Ruby's forced UTF-8
/// stdio encoding).
String _readStdin() {
  final bytes = <int>[];
  while (true) {
    final byte = stdin.readByteSync();
    if (byte < 0) break;
    bytes.add(byte);
  }
  return utf8.decode(bytes);
}

/// The parent directory of an (expanded) absolute [path].
String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  if (slash <= 0) return path;
  return path.substring(0, slash);
}
