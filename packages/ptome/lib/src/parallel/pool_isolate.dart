/// A pool of worker isolates (see `parallel.dart`), spawned as jobs come
/// and kept for the life of the process.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/parallel.dart';

final Map<int, _IsolatePool> _pools = {};

/// The pool of [size] isolates (one for each size, shared).
Parallel pool(int size) => _pools[size] ??= _IsolatePool(size);

/// The physical cores of the machine.
int get physicalCores => io.physicalCores;

/// A job submitted and not yet answered, whatever its result's type.
abstract interface class _Waiting {
  int get id;
  abstract _Worker? worker;
  _Asked request();
  void answer(_Answer reply);
  void fail(String error);
}

/// A job submitted and not yet answered.
final class _Pending<R> implements _Waiting {
  new(this.id, this.job);

  @override
  final int id;
  final Job<R> job;
  final Completer<R> completer = Completer<R>();

  @override
  _Worker? worker;

  @override
  _Request<R> request() => _Request<R>(id, job);

  @override
  void answer(_Answer reply) => deliver(completer, () {
    if (reply case _Reply<R>(:final R value, error: null)) return value;
    throw JobFailure(reply.error ?? 'no result', reply.stack ?? '');
  });

  @override
  void fail(String error) =>
      deliver(completer, () => throw JobFailure(error, ''));
}

/// A request, whatever its result's type.
abstract interface class _Asked {
  /// Runs the job (on the worker); the reply, or its future.
  FutureOr<_Answer> answer();
}

/// A reply, whatever its result's type.
abstract interface class _Answer {
  int get id;
  String? get error;
  String? get stack;
}

final class _Request<R> implements _Asked {
  const new(this.id, this.job);

  final int id;
  final Job<R> job;

  @override
  FutureOr<_Reply<R>> answer() {
    _Reply<R> failed(Object error, StackTrace stack) =>
        _Reply<R>(id, null, error: '$error', stack: '$stack');
    try {
      return switch (job.run()) {
        final Future<R> later => later.then(
          (value) => _Reply<R>(id, value),
          onError: failed,
        ),
        final R value => _Reply<R>(id, value),
      };
      // A job's failure goes back to its future.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      return failed(error, stack);
    }
  }
}

final class _Reply<R> implements _Answer {
  const new(this.id, this.value, {this.error, this.stack});

  @override
  final int id;
  final R? value;
  @override
  final String? error;
  @override
  final String? stack;
}

/// A worker isolate: the port it takes jobs on, once it said hello.
final class _Worker {
  new(this.index);

  final int index;
  SendPort? port;

  /// Its uncaught error, if it had one.
  String? error;

  /// The ports that hear of its error and its end.
  RawReceivePort? errors;
  RawReceivePort? exit;
}

/// The hello of worker [index]: the port it takes jobs on.
final class _Hello {
  const new(this.index, this.port);

  final int index;
  final SendPort port;
}

/// A worker's main: says hello with its port, then answers each request.
void _work((SendPort, int) start) {
  final (main, index) = start;
  final port = RawReceivePort((Object message) {
    if (message case final _Asked request) {
      switch (request.answer()) {
        case final Future<_Answer> later:
          unawaited(later.then(main.send));
        case final _Answer now:
          main.send(now);
      }
    }
  });
  main.send(_Hello(index, port.sendPort));
}

final class _IsolatePool implements Parallel {
  new(this.workers);

  @override
  final int workers;

  final Queue<_Waiting> _queue = Queue();
  final List<_Worker> _idle = [];
  final Map<int, _Worker> _all = {};
  final Map<int, _Waiting> _running = {};
  var _nextId = 0;
  var _nextWorker = 0;
  var _starting = 0;

  /// The hellos and replies (keeping the isolate alive only while jobs are
  /// out).
  late final RawReceivePort _port = RawReceivePort(_receive)
    ..keepIsolateAlive = false;

  @override
  Future<R> submit<R>(Job<R> job) {
    final pending = _Pending<R>(_nextId++, job);
    _queue.add(pending);
    _dispatch();
    return pending.completer.future;
  }

  void _dispatch() {
    while (_queue.isNotEmpty && _idle.isNotEmpty) {
      final worker = _idle.removeLast();
      final pending = _queue.removeFirst()..worker = worker;
      _running[pending.id] = pending;
      worker.port!.send(pending.request());
    }
    // More workers for the jobs waiting, up to the size.
    var wanted = _queue.length - _starting;
    while (wanted > 0 && _all.length < workers) {
      _spawn();
      wanted--;
    }
    _port.keepIsolateAlive = _running.isNotEmpty || _queue.isNotEmpty;
  }

  void _spawn() {
    final worker = _Worker(_nextWorker++);
    _all[worker.index] = worker;
    _starting++;
    final errors = worker.errors = RawReceivePort((Object message) {
      if (message case [final error, _]) worker.error = '$error';
    })..keepIsolateAlive = false;
    final exit = worker.exit = RawReceivePort((void _) => _ended(worker))
      ..keepIsolateAlive = false;
    unawaited(
      Isolate.spawn(
        _work,
        (_port.sendPort, worker.index),
        onError: errors.sendPort,
        onExit: exit.sendPort,
      ).then<void>(
        (_) {},
        onError: (Object error) {
          worker.error = 'a worker could not start: $error';
          _ended(worker);
        },
      ),
    );
  }

  void _receive(Object message) {
    switch (message) {
      case _Hello(:final index, :final port):
        final worker = _all[index];
        if (worker == null) return;
        _starting--;
        worker.port = port;
        _idle.add(worker);
      case _Answer(:final id):
        final pending = _running.remove(id);
        if (pending == null) return;
        if (pending.worker case final worker?) _idle.add(worker);
        pending.answer(message);
    }
    _dispatch();
  }

  /// [worker] ended: its job fails (and the jobs waiting, when no worker
  /// is left to start); it's replaced as jobs come.
  void _ended(_Worker worker) {
    if (_all.remove(worker.index) == null) return;
    worker.errors?.close();
    worker.exit?.close();
    if (worker.port == null) _starting--;
    _idle.remove(worker);
    final error = worker.error ?? 'a worker ended';
    for (final pending in [..._running.values]) {
      if (pending.worker == worker) {
        _running.remove(pending.id);
        pending.fail(error);
      }
    }
    if (worker.port == null && _all.isEmpty) {
      // It never started: nothing will run the jobs waiting.
      for (final pending in _queue) {
        pending.fail(error);
      }
      _queue.clear();
    }
    _dispatch();
  }
}
