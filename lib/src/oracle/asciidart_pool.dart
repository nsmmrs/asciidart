/// asciidart in worker isolates, so a conversion that hangs can be stopped
/// (the isolate is killed and replaced) and conversions run in parallel.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import '../spec/conversion.dart';
import 'asciidart_runner.dart';

final class _Worker {
  _Worker._(this._isolate, this._requests, this._responses);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  final Queue<(Conversion, Completer<Outcome>, Stopwatch)> pending = Queue();
  bool dead = false;

  static Future<_Worker> spawn() async {
    final responses = ReceivePort();
    final isolate = await Isolate.spawn(_serve, responses.sendPort);
    final stream = responses.asBroadcastStream();
    final requests = await stream.first as SendPort;
    final worker = _Worker._(isolate, requests, responses);
    stream.listen((message) {
      if (worker.pending.isEmpty) return;
      final (_, completer, _) = worker.pending.removeFirst();
      if (!completer.isCompleted) completer.complete(message as Outcome);
    });
    return worker;
  }

  Future<Outcome> convert(Conversion conversion, Duration timeout) {
    final completer = Completer<Outcome>();
    final watch = Stopwatch()..start();
    pending.add((conversion, completer, watch));
    _requests.send(conversion);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        kill();
        return TimedOut(id: conversion.id, micros: watch.elapsedMicroseconds);
      },
    );
  }

  void kill() {
    if (dead) return;
    dead = true;
    _isolate.kill(priority: Isolate.immediate);
    _responses.close();
    // Everything queued behind the hung conversion is lost with it.
    for (final (conversion, completer, watch) in pending) {
      if (!completer.isCompleted) {
        completer.complete(
          TimedOut(id: conversion.id, micros: watch.elapsedMicroseconds),
        );
      }
    }
    pending.clear();
  }
}

void _serve(SendPort responses) {
  final requests = ReceivePort();
  responses.send(requests.sendPort);
  requests.listen((message) {
    responses.send(convertWithAsciidart(message as Conversion));
  });
}

final class AsciidartPool {
  AsciidartPool._(this._workers);

  final List<_Worker> _workers;

  static Future<AsciidartPool> start({int size = 1}) async => AsciidartPool._(
    await Future.wait([for (var i = 0; i < size; i++) _Worker.spawn()]),
  );

  /// Converts [conversion] in the least busy isolate.
  ///
  /// Conversions queued behind one that times out are reported as timed
  /// out too; callers that need exact attribution submit one conversion per
  /// worker at a time.
  Future<Outcome> convert(
    Conversion conversion, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    for (var i = 0; i < _workers.length; i++) {
      if (_workers[i].dead) _workers[i] = await _Worker.spawn();
    }
    var best = _workers.first;
    for (final worker in _workers) {
      if (worker.pending.length < best.pending.length) best = worker;
    }
    return best.convert(conversion, timeout);
  }

  /// Converts every conversion, one at a time per isolate (so each time
  /// limit covers only its own conversion), in completion order.
  Stream<Outcome> convertAll(
    Iterable<Conversion> conversions, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final next = conversions.iterator;
    final out = StreamController<Outcome>();
    Future<void> lane(int i) async {
      while (next.moveNext()) {
        final conversion = next.current;
        if (_workers[i].dead) _workers[i] = await _Worker.spawn();
        out.add(await _workers[i].convert(conversion, timeout));
      }
    }

    Future.wait([for (var i = 0; i < _workers.length; i++) lane(i)])
        .whenComplete(out.close);
    return out.stream;
  }

  void close() {
    for (final worker in _workers) {
      worker.kill();
    }
  }
}
