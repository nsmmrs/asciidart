/// Tests for the isolate worker pool (`lib/src/job_pool.dart`).
///
/// Drives [IsolateJobPool] with a fake delay worker: jobs carry a
/// `delayMs` so completions land out of order while results must come back
/// in input order.
@TestOn('vm')
library;

import 'dart:isolate';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

/// A fake job: an `id`, a value `n` to double and a delay before replying.
typedef _Request = ({String id, int n, int delayMs});

/// A fake job's reply: the request `id` and the doubled value.
typedef _Response = ({String id, int doubled});

/// Fake worker: waits `delayMs`, then echoes the request id and doubled n.
void _delayWorker(SendPort mainPort) =>
    serveJobs<_Request, _Response>(mainPort, (request) async {
      if (request.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: request.delayMs));
      }
      return (id: request.id, doubled: request.n * 2);
    });

/// Fake worker that keeps its isolate busy for `delayMs` (one job at a
/// time).
void _busyWorker(SendPort mainPort) =>
    serveJobs<_Request, _Response>(mainPort, (request) {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < request.delayMs) {}
      return (id: request.id, doubled: request.n * 2);
    });

/// Builds a fake request with the given [id], value [n] and [delayMs].
_Request _request(String id, int n, int delayMs) =>
    (id: id, n: n, delayMs: delayMs);

/// Spawns a pool of [size] fake workers.
Future<IsolateJobPool<_Request, _Response>> _spawn(int size) =>
    IsolateJobPool.spawn<_Request, _Response>(
      size: size,
      entryPoint: _delayWorker,
    );

void main() {
  group('IsolateJobPool.spawn', () {
    test('rejects size less than 1', () {
      expect(_spawn(0), throwsArgumentError);
    });

    test('reports its size', () async {
      final pool = await _spawn(2);
      try {
        expect(pool.size, equals(2));
      } finally {
        await pool.close();
      }
    });
  });

  group('IsolateJobPool.runOrdered', () {
    test('idle workers take the next job', () async {
      final pool = await IsolateJobPool.spawn<_Request, _Response>(
        size: 2,
        entryPoint: _busyWorker,
      );
      try {
        final watch = Stopwatch()..start();
        final responses = await pool.runOrdered([
          _request('long', 0, 600),
          for (var i = 1; i <= 5; i++) _request('short$i', i, 100),
        ]);
        // Dealt in turn, the long job's worker would also get two short
        // ones (800 ms); pulled, the other worker takes all five (600 ms).
        expect(watch.elapsedMilliseconds, lessThan(750));
        expect(responses.map((r) => r.id).first, 'long');
      } finally {
        await pool.close();
      }
    });

    test('empty request list returns empty', () async {
      final pool = await _spawn(2);
      try {
        expect(await pool.runOrdered(const []), isEmpty);
      } finally {
        await pool.close();
      }
    });

    test('single job round-trips its response', () async {
      final pool = await _spawn(1);
      try {
        final results = await pool.runOrdered([_request('a', 21, 0)]);
        expect(results, hasLength(1));
        expect(results[0].id, equals('a'));
        expect(results[0].doubled, equals(42));
      } finally {
        await pool.close();
      }
    });

    test(
      'results return in input order despite out-of-order completion',
      () async {
        final pool = await _spawn(3);
        try {
          // Descending delays on three workers: job 2 finishes first, then
          // job 1, then job 0 (200ms gaps).
          final requests = [
            _request('first', 1, 600),
            _request('second', 2, 400),
            _request('third', 3, 200),
          ];
          final wallClock = Stopwatch()..start();
          final results = await pool.runOrdered(requests);
          wallClock.stop();
          expect([
            for (final r in results) r.id,
          ], equals(['first', 'second', 'third']));
          expect([for (final r in results) r.doubled], equals([2, 4, 6]));
          // Overlap proof: sequential in-order execution would take 1200ms;
          // parallel execution takes ~600ms plus scheduling jitter, which
          // leaves room for slow or busy machines.
          expect(wallClock.elapsedMilliseconds, lessThan(1000));
        } finally {
          await pool.close();
        }
      },
    );

    test('stays ordered with more jobs than workers', () async {
      final pool = await _spawn(2);
      try {
        final delays = [10, 90, 30, 70, 20, 80, 40];
        final requests = [
          for (var i = 0; i < delays.length; i++)
            _request('job$i', i, delays[i]),
        ];
        final results = await pool.runOrdered(requests);
        expect([
          for (final r in results) r.id,
        ], equals([for (var i = 0; i < delays.length; i++) 'job$i']));
        expect([
          for (final r in results) r.doubled,
        ], equals([for (var i = 0; i < delays.length; i++) i * 2]));
      } finally {
        await pool.close();
      }
    });

    test('pool is reusable across runs', () async {
      final pool = await _spawn(2);
      try {
        final first = await pool.runOrdered([_request('a', 1, 10)]);
        final second = await pool.runOrdered([
          _request('b', 2, 10),
          _request('c', 3, 10),
        ]);
        expect(first.single.id, equals('a'));
        expect([for (final r in second) r.id], equals(['b', 'c']));
      } finally {
        await pool.close();
      }
    });

    test('runOrdered after close throws StateError', () async {
      final pool = await _spawn(1);
      await pool.close();
      expect(pool.runOrdered([_request('a', 1, 0)]), throwsStateError);
    });
  });

  group('IsolateJobPool.close', () {
    test('close is idempotent', () async {
      final pool = await _spawn(1);
      await pool.close();
      await pool.close();
    });
  });
}
