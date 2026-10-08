/// Work on other cores (ADR-0016): a [Job] is plain data and what to
/// compute from it; a [Parallel] runs jobs on workers, the idle ones
/// pulling the next, and gives each result back as its future.
///
/// The output never depends on the workers: callers decide where each
/// result goes before submitting, and await the results in their own
/// order. The serial pool runs a job when it is submitted (the reference,
/// and the only pool on JavaScript); the isolate pool keeps its isolates
/// for the life of the process. With `PTOME_JOBS_SHUFFLE=1` in the
/// environment, every pool hands its results back after a random delay,
/// so a caller depending on the order they finish in shows it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/parallel/pool_serial.dart'
    if (dart.library.io) 'package:ptome/src/parallel/pool_isolate.dart'
    as backend;

/// A job for a worker: plain data (numbers, strings, bytes, records and
/// lists of them; never closures or objects with identity-keyed state),
/// and the computation [run] makes from it there.
abstract base class Job<R> {
  /// A job.
  const new();

  /// The result, computed on a worker (or here, serially).
  R run();
}

/// Runs [Job]s.
abstract interface class Parallel {
  /// The serial pool: each job runs when it is submitted.
  static const Parallel serial = _Serial();

  /// Whether this isolate is a worker of an outer pool (`-j`), where
  /// conversions run serially (nested pools oversubscribe the cores).
  static bool nested = false;

  /// The pool of [jobs] workers ([serial] for 1 or less, when [nested] and
  /// where isolates aren't available).
  static Parallel ofSize(int jobs) =>
      jobs <= 1 || nested ? serial : backend.pool(jobs);

  /// The pool the `jobs` attribute's [value] asks for: a number of workers
  /// (`1`: none); the physical cores when unset or not a number.
  static Parallel forAttribute(String? value) =>
      ofSize(switch (int.tryParse(value?.trim() ?? '')) {
        final jobs? => jobs,
        null => backend.physicalCores,
      });

  /// The number of workers (0: serial).
  int get workers;

  /// Runs [job] on the next idle worker; its result.
  Future<R> submit<R>(Job<R> job);
}

/// Runs [body] as a conversion whose caller awaits its work on other
/// cores before writing (`Document.finish`): only there do converters
/// submit jobs (the synchronous path would only do the work twice).
T awaitingWorkers<T>(T Function() body) =>
    runZoned(body, zoneValues: {_awaiting: true});

/// Whether the conversion under way is awaited (see [awaitingWorkers]).
bool get workersAwaited => Zone.current[_awaiting] == true;

final Object _awaiting = Object();

/// A job that failed on a worker: its error and stack trace, as text.
final class JobFailure implements Exception {
  /// A failure with [message], thrown at [stack].
  const new(this.message, this.stack);

  /// The error, as text.
  final String message;

  /// Where it was thrown, as text.
  final String stack;

  @override
  String toString() => message;
}

/// Whether results are handed back in a random order
/// (`PTOME_JOBS_SHUFFLE=1`).
final bool _shuffle = io.environment['PTOME_JOBS_SHUFFLE'] == '1';
final math.Random _random = math.Random();

/// Completes [completer] with what [result] returns (or throws), after a
/// random delay when results are shuffled.
void deliver<R>(
  Completer<R> completer,
  R Function() result, {
  bool shuffle = true,
}) {
  void complete() {
    try {
      completer.complete(result());
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
  }

  if (_shuffle && shuffle) {
    Timer(Duration(microseconds: _random.nextInt(3000)), complete);
  } else {
    complete();
  }
}

final class _Serial implements Parallel {
  const new();

  @override
  int get workers => 0;

  @override
  Future<R> submit<R>(Job<R> job) {
    // (Run now; handed back as the shuffle says.)
    R Function() outcome;
    try {
      final result = job.run();
      outcome = () => result;
    } catch (error, stack) {
      outcome = () => Error.throwWithStackTrace(error, stack);
    }
    final completer = Completer<R>();
    deliver(completer, outcome);
    return completer.future;
  }
}
