/// Parallel bulk-conversion worker for the CLI `-j/--jobs` path.
///
/// The invoker (`cli/invoker.dart`) converts one input file per job on worker
/// isolates and replays the results on the main isolate in input order, so
/// `asciidoctor -j 4 a b c` emits byte-identical converted output,
/// diagnostics and exit codes to the sequential run (except timing values,
/// which are inherently nondeterministic; see below).
///
/// ## Request/response codec
///
/// Jobs cross the isolate boundary as plain transferable data: `buildRequest`
/// freezes the per-file processor options (paths plus option maps — never
/// live objects such as documents, loggers or sinks) into a
/// `Map<String, Object?>`, and [runConversionJob] answers with another one:
///
/// - `'ok'` ([bool]): whether the conversion succeeded.
/// - `'error'` ([String], failures only): the worker-side `toString()` of
///   the thrown error, reported verbatim on the main isolate.
/// - `'records'` (`List<List<Object?>>`): captured log records as
///   `[severityValue, message]` pairs, in logging order. Messages are
///   resolved strings (lazy blocks are evaluated worker-side); the main
///   isolate replays each pair through its own logger, which reproduces the
///   sequential stderr bytes exactly (same severity, same default progname,
///   same formatter) and folds the worst worker severity into
///   `maxSeverity`, so `--failure-level` exit codes match the sequential
///   run. MemoryLogger drops the record progname, but no in-repo caller
///   passes an explicit one (all logging goes through the severity
///   convenience methods), so nothing is lost.
/// - `'max_severity'` ([int], nullable): the worst captured severity value,
///   for callers that need it without replaying.
/// - `'timings'` (`Map<String, double>`, successes with timings enabled
///   only): the worker-side phase log, reseeded into a main-isolate
///   [Timings] so per-file reports keep the sequential format.
/// - `'output'` ([String], stdout-mode successes only): the converted text
///   the worker captured instead of writing to the unshareable STDOUT sink;
///   the main isolate writes these in input order.
///
/// ## Timings aggregation
///
/// Each worker measures its own read/parse/convert phases; the main isolate
/// prints the per-file reports in input order (same format as sequential)
/// and then one aggregate: the summed per-file read+parse+convert times plus
/// the wall-clock time of the parallel phase. Summing attributes the true
/// CPU cost to the conversion while the wall clock shows the `-j` win.
library;

import 'dart:isolate';

import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/timings.dart';

/// Worker isolate entry point for conversion jobs (see `WorkerMain`).
///
/// Handshakes its job port back to [mainPort] and then serves
/// `[index, request, replyPort]` frames with [runConversionJob], wrapping
/// unexpected failures (including malformed frames) in an `'ok': false`
/// response so the main isolate never stalls waiting for a reply.
void conversionWorkerMain(SendPort mainPort) {
  final workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);
  workerPort.listen((message) {
    final frame = message as List;
    final index = frame[0] as int;
    final request = (frame[1] as Map).cast<String, Object?>();
    final replyTo = frame[2] as SendPort;
    Map<String, Object?> response;
    try {
      response = runConversionJob(request);
      // Worker boundary: every failure (including Errors) must serialize
      // into an error response instead of killing the isolate silently.
    } on Object catch (e) {
      response = <String, Object?>{
        'ok': false,
        'error': e.toString(),
        'records': <List<Object?>>[],
        'max_severity': null,
      };
    }
    replyTo.send([index, response]);
  });
}

/// Builds the transferable conversion request for [infile].
///
/// [processorOptions] holds the per-file processor options exactly as the
/// sequential path would pass them to [convertFile] (with `to_file` already
/// resolved to `null` or an explicit path and `to_dir` already adjusted),
/// except that a STDOUT sink is passed as [toStdout] instead: sinks cannot
/// cross isolates, so the worker captures the converted text and returns it
/// in the response `'output'`. [showTimings] enables worker-side phase
/// measurement. Only transferable values may appear in [processorOptions]
/// (no live loggers, sinks, or custom objects); enums must be pre-converted
/// to plain values (see `'failure_level'` below). In STDOUT mode the
/// caller's `to_file` sink is dropped here (the worker captures into its own
/// buffer instead), so the request stays transferable.
Map<String, Object?> buildConversionRequest({
  required String infile,
  required Map<String, Object?> processorOptions,
  required bool toStdout,
  required bool showTimings,
}) {
  return <String, Object?>{
    'infile': infile,
    'attributes': processorOptions['attributes'],
    'safe': processorOptions['safe'],
    'standalone': processorOptions['standalone'],
    'warnings': processorOptions['warnings'],
    'failure_level': (processorOptions['failure_level']! as Severity).value,
    'template_dirs': processorOptions['template_dirs'],
    'template_engine': processorOptions['template_engine'],
    'eruby': processorOptions['eruby'],
    'base_dir': processorOptions['base_dir'],
    'load_paths': processorOptions['load_paths'],
    'requires': processorOptions['requires'],
    'to_dir': processorOptions['to_dir'],
    'to_file': toStdout ? null : processorOptions['to_file'],
    'mkdirs': processorOptions['mkdirs'] ?? false,
    'to_stdout': toStdout,
    'timings': showTimings,
  };
}

/// Converts the single input file described by [request].
///
/// Runs [convertFile] with the frozen options (plus a capture buffer in
/// STDOUT mode and a [Timings] when requested) under a [MemoryLogger] that
/// records every log record regardless of level; level filtering happens on
/// the main isolate during replay, exactly as in the sequential run. Returns
/// the transferable response described in the library documentation. Failures
/// are caught and reported as `'ok': false` with the records logged before
/// the throw; the worker isolate's logger is always restored.
///
/// This is a plain synchronous function so unit tests can drive the codec
/// without spawning isolates.
Map<String, Object?> runConversionJob(Map<String, Object?> request) {
  final savedLogger = LoggerManager.logger;
  final memory = MemoryLogger();
  LoggerManager.logger = memory;
  try {
    final opts = <String, Object?>{};
    final attributes = request['attributes'];
    if (attributes != null) opts['attributes'] = attributes;
    opts['safe'] = request['safe']! as int;
    opts['standalone'] = request['standalone']! as bool;
    opts['warnings'] = request['warnings']! as bool;
    opts['failure_level'] = Severity.fromValue(
      request['failure_level']! as int,
    );
    for (final key in [
      'template_dirs',
      'template_engine',
      'eruby',
      'base_dir',
      'load_paths',
      'requires',
      'to_dir',
    ]) {
      final value = request[key];
      if (value != null) opts[key] = value;
    }
    StringBuffer? capture;
    if (request['to_stdout'] == true) {
      capture = StringBuffer();
      opts['to_file'] = capture;
    } else {
      final toFile = request['to_file'];
      if (toFile != null) opts['to_file'] = toFile as String;
    }
    if (request['mkdirs'] == true) opts['mkdirs'] = true;
    Timings? timings;
    if (request['timings'] == true) {
      timings = Timings();
      opts['timings'] = timings;
    }
    convertFile(request['infile']! as String, opts);
    return <String, Object?>{
      'ok': true,
      'records': _transferRecords(memory),
      'max_severity': memory.maxSeverity?.value,
      'timings': timings == null ? null : Map<String, double>.of(timings.log),
      'output': capture?.toString(),
    };
    // Worker boundary: every failure (including Errors) must serialize
    // into an error response instead of killing the isolate silently.
  } on Object catch (e) {
    return <String, Object?>{
      'ok': false,
      'error': e.toString(),
      'records': _transferRecords(memory),
      'max_severity': memory.maxSeverity?.value,
    };
  } finally {
    LoggerManager.logger = savedLogger;
  }
}

/// Replays worker-captured [records] through [logger].
///
/// Each `[severityValue, message]` pair is logged exactly as the sequential
/// run logged it, so filtered output bytes and [LoggerBase.maxSeverity]
/// match the sequential run. [records] comes from a job response verbatim.
void replayRecords(LoggerBase logger, Object? records) {
  for (final record in records! as List) {
    final pair = record as List;
    logger.add(Severity.fromValue(pair[0] as int), pair[1] as String);
  }
}

/// Freezes [memory]'s records as transferable `[severityValue, message]`
/// pairs. Messages are resolved to strings worker-side (matching what the
/// sequential formatter would interpolate).
List<List<Object?>> _transferRecords(MemoryLogger memory) {
  return [
    for (final record in memory.messages)
      <Object?>[record.severity.value, '${record.message}'],
  ];
}

/// A worker-side conversion failure, rethrown on the main isolate.
///
/// Carries the worker's error text verbatim (the original error object cannot
/// cross isolates), so `--trace` output matches the sequential run's message;
/// only the backtrace differs (it starts on the main isolate).
final class WorkerFailure implements Exception {
  /// Creates a failure carrying the worker-side error [message].
  const new(this.message);

  /// The worker-side `toString()` of the thrown error.
  final String message;

  @override
  String toString() => message;
}
