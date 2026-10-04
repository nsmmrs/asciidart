/// Parallel bulk-conversion worker for the CLI `-j/--jobs` path.
///
/// The invoker (`cli/invoker.dart`) converts one input file per job on worker
/// isolates and replays the results on the main isolate in input order, so
/// `asciidoctor -j 4 a b c` emits byte-identical converted output,
/// diagnostics and exit codes to the sequential run (except timing values,
/// which are inherently nondeterministic; see below).
///
/// ## Requests and responses
///
/// A [ConversionRequest] carries the input file and the processor options
/// (plain data only: never live documents, loggers or sinks). The worker
/// answers with a [ConversionResponse]: whether the conversion succeeded,
/// the error text of a failure, the captured log records (replayed through
/// the main isolate's logger, which reproduces the sequential stderr bytes
/// and folds the worst worker severity into `maxSeverity`, so
/// `--failure-level` exit codes match the sequential run), the phase
/// timings, and in STDOUT mode the converted text (STDOUT cannot be shared
/// across isolates).
///
/// ## Timings aggregation
///
/// Each worker measures its own read/parse/convert phases; the main isolate
/// prints the per-file reports in input order (same format as sequential)
/// and then one aggregate: the summed per-file read+parse+convert times plus
/// the wall-clock time of the parallel phase. Summing attributes the true
/// CPU cost to the conversion while the wall clock shows the `-j` win.
library;

import 'package:asciidoctor/src/cli/diagnostics.dart';
import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/options.dart';
import 'package:asciidoctor/src/timings.dart';

/// A conversion job: one input file and its processor options.
final class ConversionRequest {
  /// Creates a request to convert [infile] with [options].
  const new({
    required this.infile,
    required this.options,
    required this.toStdout,
    required this.showTimings,
  });

  /// The input file.
  final String infile;

  /// The processor options (without a logger or timings, which the worker
  /// creates).
  final AsciidoctorOptions options;

  /// Whether the output goes to STDOUT (captured by the worker).
  final bool toStdout;

  /// Whether to measure the processing phases.
  final bool showTimings;
}

/// A log record captured by a worker: its severity and rendered message.
final class CapturedRecord {
  /// Creates a record.
  const new(this.severity, this.message);

  /// The severity the message was logged at.
  final Severity severity;

  /// The rendered message (location prefix included).
  final String message;
}

/// The outcome of a [ConversionRequest].
final class ConversionResponse {
  /// Creates a response.
  const new({
    required this.ok,
    required this.records,
    this.error,
    this.timings,
    this.output,
  });

  /// Whether the conversion succeeded.
  final bool ok;

  /// The error text of a failed conversion.
  final String? error;

  /// The log records, in logging order.
  final List<CapturedRecord> records;

  /// The phase timings in seconds, when requested.
  final Map<String, double>? timings;

  /// The converted text, in STDOUT mode.
  final String? output;
}

/// Converts the single input file described by [request].
///
/// Runs [convertFileAsync] (with a capture buffer in STDOUT mode and a
/// [Timings] when requested) under a [MemoryLogger] that records every log
/// record regardless of level; level filtering happens on the main isolate
/// during replay, exactly as in the sequential run. Failures are reported as
/// unsuccessful responses carrying the records logged before the failure;
/// the worker isolate's logger is always restored.
///
/// Unit tests drive it directly, without spawning isolates.
Future<ConversionResponse> runConversionJob(ConversionRequest request) async {
  final savedLogger = LoggerManager.logger;
  final memory = MemoryLogger();
  LoggerManager.logger = memory;
  try {
    final timings = request.showTimings ? Timings() : null;
    final options = request.options.copyWith(timings: timings);
    final capture = request.toStdout ? StringBuffer() : null;
    await convertFileAsync(request.infile, options, capture);
    return ConversionResponse(
      ok: true,
      records: _capture(memory),
      timings: timings == null ? null : Map<String, double>.of(timings.log),
      output: capture?.toString(),
    );
    // Worker boundary: every failure (including Errors) must become an
    // error response instead of killing the isolate silently.
  } on Object catch (e) {
    return ConversionResponse(
      ok: false,
      error: describe(e),
      records: _capture(memory),
    );
  } finally {
    LoggerManager.logger = savedLogger;
  }
}

/// Replays worker-captured [records] through [logger].
///
/// Each record is logged exactly as the sequential run logged it, so
/// filtered output bytes and [LoggerBase.maxSeverity] match the sequential
/// run.
void replayRecords(LoggerBase logger, List<CapturedRecord> records) {
  for (final record in records) {
    logger.add(record.severity, LogMessage(record.message));
  }
}

/// The records [memory] captured, with their messages rendered.
List<CapturedRecord> _capture(MemoryLogger memory) => [
  for (final record in memory.messages)
    CapturedRecord(record.severity, '${record.message}'),
];

/// A worker-side conversion failure, rethrown on the main isolate.
///
/// Carries the worker's error text verbatim (the original error object
/// cannot cross isolates), so `--trace` output matches the sequential run's
/// message; only the backtrace differs (it starts on the main isolate).
final class WorkerFailure extends AsciidoctorException {
  /// Creates a failure carrying the worker-side error [message] (see
  /// [describe]).
  const new(super.message);
}
