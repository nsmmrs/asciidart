/// Fixed-size isolate worker pool for transferable jobs.
///
/// Backs the CLI `-j/--jobs` bulk-conversion path (`cli/invoker.dart` fans
/// out one input file per job). Requests and responses are plain data
/// (`Map<String, Object?>` holding only numbers, strings, booleans, nulls,
/// lists and maps) because only such values cross isolate boundaries; live
/// objects (documents, loggers, sinks) never leave their isolate.
///
/// ## Worker protocol
///
/// A worker `entryPoint` receives the main isolate's handshake [SendPort],
/// creates its own [ReceivePort], and sends that port's [SendPort] back as
/// the handshake reply. Afterwards it serves `[index, request, replyPort]`
/// frames, where `index` is the request's position in the [JobPool.runOrdered]
/// input list and `replyPort` is the [SendPort] the `[index, response]` frame
/// must be sent to. Workers must reply exactly once per request; a worker
/// that dies or never replies stalls its [JobPool.runOrdered] caller.
///
/// Jobs are dispatched round-robin over the workers and responses are
/// reordered by index, so results always come back in input order regardless
/// of completion order. The pool spawns its isolates once (amortized over the
/// CLI run) and reuses them across [JobPool.runOrdered] calls.
library;

import 'dart:async';
import 'dart:isolate';

/// Worker isolate entry-point signature.
///
/// Receives the main isolate's handshake port; the worker answers with its
/// own [SendPort] and then serves `[index, request, replyPort]` frames (see
/// the library documentation).
typedef WorkerMain = void Function(SendPort mainPort);

/// A pool that runs transferable requests and returns responses in order.
///
/// Kept deliberately small so the CLI fan-out stays testable: unit tests
/// drive [IsolateJobPool] with fake workers, and callers needing no
/// parallelism can substitute an inline implementation.
abstract interface class JobPool {
  /// Runs [requests] and returns their responses in input order.
  ///
  /// Every element of [requests] — and every value the worker puts in a
  /// response — must be transferable across isolates (numbers, strings,
  /// booleans, nulls, lists and maps of those).
  Future<List<Map<String, Object?>>> runOrdered(
    List<Map<String, Object?>> requests,
  );

  /// Releases pool resources (worker isolates). Idempotent.
  Future<void> close();
}

/// A [JobPool] of long-lived worker isolates.
///
/// Created with [IsolateJobPool.spawn], which spawns [size] isolates running
/// `entryPoint` and handshakes each one for its job port before returning.
final class IsolateJobPool implements JobPool {
  /// Creates a pool over already-handshaked [_isolates] and [_workerPorts].
  new _(this._isolates, this._workerPorts);

  /// Spawns a pool of [size] isolates running [entryPoint].
  ///
  /// Throws an [ArgumentError] when [size] is less than 1. When a spawn or
  /// handshake fails, already-spawned isolates are killed and the error is
  /// rethrown.
  static Future<IsolateJobPool> spawn({
    required int size,
    required WorkerMain entryPoint,
  }) async {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be >= 1');
    }
    final isolates = <Isolate>[];
    final workers = <SendPort>[];
    try {
      for (var i = 0; i < size; i++) {
        final handshake = ReceivePort();
        try {
          final isolate = await Isolate.spawn(entryPoint, handshake.sendPort);
          isolates.add(isolate);
          workers.add(await handshake.first as SendPort);
        } finally {
          handshake.close();
        }
      }
    } catch (_) {
      for (final isolate in isolates) {
        isolate.kill(priority: Isolate.immediate);
      }
      rethrow;
    }
    return IsolateJobPool._(isolates, workers);
  }

  final List<Isolate> _isolates;
  final List<SendPort> _workerPorts;
  var _closed = false;

  /// The number of worker isolates in this pool.
  int get size => _workerPorts.length;

  @override
  Future<List<Map<String, Object?>>> runOrdered(
    List<Map<String, Object?>> requests,
  ) async {
    if (_closed) throw StateError('IsolateJobPool is closed');
    if (requests.isEmpty) return <Map<String, Object?>>[];
    final replies = ReceivePort();
    try {
      final results = List<Map<String, Object?>?>.filled(requests.length, null);
      var remaining = requests.length;
      final done = Completer<void>();
      final subscription = replies.listen((message) {
        final frame = message as List;
        results[frame[0] as int] = (frame[1] as Map).cast<String, Object?>();
        if (--remaining == 0) done.complete();
      });
      for (var i = 0; i < requests.length; i++) {
        _workerPorts[i % _workerPorts.length].send([
          i,
          requests[i],
          replies.sendPort,
        ]);
      }
      await done.future;
      await subscription.cancel();
      return [for (final result in results) result!];
    } finally {
      replies.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
  }
}
