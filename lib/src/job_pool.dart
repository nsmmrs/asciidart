/// Fixed-size isolate worker pool.
///
/// Backs the CLI `-j/--jobs` bulk-conversion path (`cli/invoker.dart` fans
/// out one input file per job). Requests and responses are objects that can
/// cross isolate boundaries (no live documents, loggers or sinks).
///
/// ## Worker protocol
///
/// A worker `entryPoint` receives the main isolate's handshake [SendPort]
/// and serves jobs with [serveJobs], which sends its own [SendPort] back as
/// the handshake reply and then answers each job exactly once. A worker that
/// dies or never replies stalls its [JobPool.runOrdered] caller.
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
/// Receives the main isolate's handshake port (see the library
/// documentation).
typedef WorkerMain = void Function(SendPort mainPort);

/// A job sent to a worker: the request, its position and the reply port.
final class _JobFrame<Req> {
  const new(this.index, this.request, this.replyTo);

  final int index;
  final Req request;
  final SendPort replyTo;
}

/// A worker's reply to the job at [index].
final class _ReplyFrame<Res> {
  const new(this.index, this.response);

  final int index;
  final Res response;
}

/// Serves jobs for a pool on a worker isolate: handshakes with [mainPort],
/// then answers each request with [handle].
void serveJobs<Req, Res>(
  SendPort mainPort,
  FutureOr<Res> Function(Req request) handle,
) {
  final workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);
  workerPort.listen((message) async {
    if (message case _JobFrame<Req>(
      :final index,
      :final request,
      :final replyTo,
    )) {
      replyTo.send(_ReplyFrame<Res>(index, await handle(request)));
    }
  });
}

/// A pool that runs requests and returns responses in order.
///
/// Kept deliberately small so the CLI fan-out stays testable: unit tests
/// drive [IsolateJobPool] with fake workers, and callers needing no
/// parallelism can substitute an inline implementation.
abstract interface class JobPool<Req, Res> {
  /// Runs [requests] and returns their responses in input order.
  Future<List<Res>> runOrdered(List<Req> requests);

  /// Releases pool resources (worker isolates). Idempotent.
  Future<void> close();
}

/// A [JobPool] of long-lived worker isolates.
///
/// Created with [IsolateJobPool.spawn], which spawns [size] isolates running
/// `entryPoint` and handshakes each one for its job port before returning.
final class IsolateJobPool<Req, Res> implements JobPool<Req, Res> {
  /// Creates a pool over already-handshaked [_isolates] and [_workerPorts].
  new _(this._isolates, this._workerPorts);

  /// Spawns a pool of [size] isolates running [entryPoint], which must
  /// serve jobs with [serveJobs].
  ///
  /// Throws an [ArgumentError] when [size] is less than 1. When a spawn or
  /// handshake fails, already-spawned isolates are killed and the error is
  /// rethrown.
  static Future<IsolateJobPool<Req, Res>> spawn<Req, Res>({
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
          final reply = await handshake.first;
          if (reply is! SendPort) {
            throw StateError('worker handshake failed: $reply');
          }
          workers.add(reply);
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
    return IsolateJobPool<Req, Res>._(isolates, workers);
  }

  final List<Isolate> _isolates;
  final List<SendPort> _workerPorts;
  var _closed = false;

  /// The number of worker isolates in this pool.
  int get size => _workerPorts.length;

  @override
  Future<List<Res>> runOrdered(List<Req> requests) async {
    if (_closed) throw StateError('IsolateJobPool is closed');
    if (requests.isEmpty) return <Res>[];
    final replies = ReceivePort();
    try {
      final results = List<Res?>.filled(requests.length, null);
      var remaining = requests.length;
      final done = Completer<void>();
      final subscription = replies.listen((message) {
        if (message case _ReplyFrame<Res>(:final index, :final response)) {
          results[index] = response;
          if (--remaining == 0) done.complete();
        }
      });
      for (var i = 0; i < requests.length; i++) {
        _workerPorts[i % _workerPorts.length].send(
          _JobFrame<Req>(i, requests[i], replies.sendPort),
        );
      }
      await done.future;
      await subscription.cancel();
      return [for (final result in results) result as Res];
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
