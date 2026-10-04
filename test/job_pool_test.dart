/// Tests for the isolate worker pool (`lib/src/job_pool.dart`).
///
/// Drives [IsolateJobPool] with a fake delay worker: jobs carry a
/// `delayMs` so completions land out of order while results must come back
/// in input order.
library;

import 'dart:isolate';

import 'package:asciidoctor/src/internal.dart';
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
            for (final r in results) r.id,
          ], equals(['first', 'second', 'third']));
          expect([for (final r in results) r.doubled], equals([2, 4, 6]));
          // Overlap proof: sequential in-order execution would take 380ms;
          // parallel execution takes ~200ms plus scheduling jitter.
          expect(wallClock.elapsedMilliseconds, lessThan(320));
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
