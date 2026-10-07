/// Phase timings for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/timings.rb` (`Asciidoctor::Timings`). Measures the
/// wall-clock time spent in each document processing phase (`read`, `parse`,
/// `convert`, `write`).
library;

import 'package:asciidart/src/io.dart' as io;

/// Measures the wall-clock time spent in each document processing phase.
///
/// Mirrors `Asciidoctor::Timings`: [start] arms the timer for a phase key,
/// [record] stores the elapsed seconds, and the getters ([read], [parse],
/// [convert], [write], [total], ...) read back recorded totals. Times are
/// `double` seconds from a monotonic clock ([Stopwatch], mirroring
/// `Process.clock_gettime(Process::CLOCK_MONOTONIC)`).
class Timings {
  /// Creates timings with no recorded phases; [onRecord] hears of each
  /// phase as it finishes (asciidart's `--progress`).
  new({this.onRecord}) {
    _stopwatch.start();
  }

  /// Called with each phase and its seconds as the phase is recorded.
  final void Function(String phase, double seconds)? onRecord;

  final Stopwatch _stopwatch = Stopwatch();
  final Map<String, double> _log = {};
  final Map<String, double> _timers = {};

  /// Recorded phase durations in seconds, keyed by phase name.
  ///
  /// Exposed so tests can seed exact values; production code must use
  /// [start]/[record].
  Map<String, double> get log => _log;

  double get _now =>
      _stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;

  /// Starts the timer for [key], replacing any running timer for it.
  ///
  /// Returns the start time in seconds. Mirrors `Timings#start`.
  double start(String key) => _timers[key] = _now;

  /// Records the elapsed seconds for [key] since the matching [start].
  ///
  /// Returns the recorded duration. Throws a [StateError] when no timer was
  /// started for [key]. Mirrors `Timings#record`.
  double record(String key) {
    final startTime = _timers.remove(key);
    if (startTime == null) {
      throw StateError('cannot record timing for "$key": no timer was started');
    }
    final seconds = _log[key] = _now - startTime;
    onRecord?.call(key, seconds);
    return seconds;
  }

  /// Returns the total recorded seconds for [key1]..[key4], or `null` when
  /// the total is zero (no phase recorded). Unknown keys count as zero.
  ///
  /// Mirrors `Timings#time`.
  double? time([String? key1, String? key2, String? key3, String? key4]) {
    var total = 0.0;
    for (final key in [key1, key2, key3, key4]) {
      if (key != null) total += _log[key] ?? 0;
    }
    return total > 0 ? total : null;
  }

  /// Recorded seconds spent reading the source, or `null` when unrecorded.
  double? get read => time('read');

  /// Recorded seconds spent parsing the source, or `null` when unrecorded.
  double? get parse => time('parse');

  /// Recorded seconds spent reading and parsing, or `null` when unrecorded.
  double? get readParse => time('read', 'parse');

  /// Recorded seconds spent converting the document, or `null` when
  /// unrecorded.
  double? get convert => time('convert');

  /// Recorded seconds spent reading, parsing and converting, or `null` when
  /// unrecorded.
  double? get readParseConvert => time('read', 'parse', 'convert');

  /// Recorded seconds spent writing the output, or `null` when unrecorded.
  double? get write => time('write');

  /// Recorded seconds spent reading, parsing, converting and writing, or
  /// `null` when unrecorded.
  double? get total => time('read', 'parse', 'convert', 'write');

  /// Prints the timing report to [to] (default standard output), headed by
  /// `Input file: [subject]` when [subject] is given.
  ///
  /// Mirrors `Timings#print_report`, including the `%05.5f` rendering (always
  /// at least 7 characters wide, so plain 5-decimal fixed notation matches
  /// exactly) and the `0.00000` fallback for unrecorded phases.
  void printReport([StringSink? to, String? subject]) {
    final out = to ?? io.standardOutput;
    if (subject != null) out.writeln('Input file: $subject');
    out
      ..writeln(
        '  Time to read and parse source: '
        '${(readParse ?? 0).toStringAsFixed(5)}',
      )
      ..writeln(
        '  Time to convert document: ${(convert ?? 0).toStringAsFixed(5)}',
      )
      ..writeln(
        '  Total time (read, parse and convert): '
        '${(readParseConvert ?? 0).toStringAsFixed(5)}',
      );
  }
}
