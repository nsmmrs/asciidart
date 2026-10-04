/// Tests for the isolate worker pool (`lib/src/job_pool.dart`).
///
/// Drives [IsolateJobPool] with a fake delay worker: jobs carry a
/// `delay_ms` so completions land out of order while results must come back
/// in input order.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:asciidoctor/src/job_pool.dart';
import 'package:test/test.dart';

/// Fake worker: waits `delay_ms`, then echoes the request id and doubled n.
void _delayWorker(SendPort mainPort) {
  final workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);
  workerPort.listen((message) async {
    final frame = message as List;
    final index = frame[0] as int;
    final request = (frame[1] as Map).cast<String, Object?>();
    final replyTo = frame[2] as SendPort;
    final delayMs = request['delay_ms']! as int;
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    replyTo.send([
      index,
      {'id': request['id'], 'double': (request['n']! as int) * 2},
    ]);
  });
}

/// Builds a fake request with the given [id], value [n] and [delayMs].
Map<String, Object?> _request(String id, int n, int delayMs) {
  return <String, Object?>{'id': id, 'n': n, 'delay_ms': delayMs};
}

void main() {
  group('IsolateJobPool.spawn', () {
    test('rejects size less than 1', () {
      expect(
        IsolateJobPool.spawn(size: 0, entryPoint: _delayWorker),
        throwsArgumentError,
      );
    });

    test('reports its size', () async {
      final pool = await IsolateJobPool.spawn(
        size: 2,
        entryPoint: _delayWorker,
      );
      try {
        expect(pool.size, equals(2));
      } finally {
        await pool.close();
      }
    });
  });

  group('IsolateJobPool.runOrdered', () {
    test('empty request list returns empty', () async {
      final pool = await IsolateJobPool.spawn(
        size: 2,
        entryPoint: _delayWorker,
      );
      try {
        expect(await pool.runOrdered([]), isEmpty);
      } finally {
        await pool.close();
      }
    });

    test('single job round-trips its response', () async {
      final pool = await IsolateJobPool.spawn(
        size: 1,
        entryPoint: _delayWorker,
      );
      try {
        final results = await pool.runOrdered([_request('a', 21, 0)]);
        expect(results, hasLength(1));
        expect(results[0]['id'], equals('a'));
        expect(results[0]['double'], equals(42));
      } finally {
        await pool.close();
      }
    });

    test(
      'results return in input order despite out-of-order completion',
      () async {
        final pool = await IsolateJobPool.spawn(
          size: 3,
          entryPoint: _delayWorker,
        );
        try {
          // Descending delays on three workers: job 2 finishes first, then
          // job 1, then job 0 (60-80ms gaps).
          final requests = [
            _request('first', 1, 200),
            _request('second', 2, 120),
            _request('third', 3, 60),
          ];
          final wallClock = Stopwatch()..start();
          final results = await pool.runOrdered(requests);
          wallClock.stop();
          expect([
            for (final r in results) r['id'],
          ], equals(['first', 'second', 'third']));
          expect([for (final r in results) r['double']], equals([2, 4, 6]));
          // Overlap proof: sequential in-order execution would take 380ms;
          // parallel execution takes ~200ms plus scheduling jitter.
          expect(wallClock.elapsedMilliseconds, lessThan(320));
        } finally {
          await pool.close();
        }
      },
    );

    test('stays ordered with more jobs than workers', () async {
      final pool = await IsolateJobPool.spawn(
        size: 2,
        entryPoint: _delayWorker,
      );
      try {
        final delays = [10, 90, 30, 70, 20, 80, 40];
        final requests = [
          for (var i = 0; i < delays.length; i++)
            _request('job$i', i, delays[i]),
        ];
        final results = await pool.runOrdered(requests);
        expect([
          for (final r in results) r['id'],
        ], equals([for (var i = 0; i < delays.length; i++) 'job$i']));
        expect([
          for (final r in results) r['double'],
        ], equals([for (var i = 0; i < delays.length; i++) i * 2]));
      } finally {
        await pool.close();
      }
    });

    test('pool is reusable across runs', () async {
      final pool = await IsolateJobPool.spawn(
        size: 2,
        entryPoint: _delayWorker,
      );
      try {
        final first = await pool.runOrdered([_request('a', 1, 10)]);
        final second = await pool.runOrdered([
          _request('b', 2, 10),
          _request('c', 3, 10),
        ]);
        expect(first.single['id'], equals('a'));
        expect([for (final r in second) r['id']], equals(['b', 'c']));
      } finally {
        await pool.close();
      }
    });

    test('runOrdered after close throws StateError', () async {
      final pool = await IsolateJobPool.spawn(
        size: 1,
        entryPoint: _delayWorker,
      );
      await pool.close();
      expect(pool.runOrdered([_request('a', 1, 0)]), throwsStateError);
    });
  });

  group('IsolateJobPool.close', () {
    test('close is idempotent', () async {
      final pool = await IsolateJobPool.spawn(
        size: 1,
        entryPoint: _delayWorker,
      );
      await pool.close();
      await pool.close();
    });
  });
}
