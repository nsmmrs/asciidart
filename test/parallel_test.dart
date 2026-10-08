@TestOn('vm')
library;

import 'dart:isolate';

import 'package:ptome/src/parallel.dart';
import 'package:test/test.dart';

/// The sum of the squares below [n].
final class _Squares extends Job<int> {
  const new(this.n);

  final int n;

  @override
  int run() {
    var sum = 0;
    for (var i = 0; i < n; i++) {
      sum += i * i;
    }
    return sum;
  }
}

/// Waits [millis] (busy), then gives its [name].
final class _Busy extends Job<String> {
  const new(this.name, this.millis);

  final String name;
  final int millis;

  @override
  String run() {
    final watch = Stopwatch()..start();
    while (watch.elapsedMilliseconds < millis) {}
    return name;
  }
}

final class _Throws extends Job<int> {
  const new();

  @override
  int run() => throw StateError('no luck');
}

/// Ends its worker.
final class _Dies extends Job<int> {
  const new();

  @override
  int run() {
    Isolate.current.kill(priority: Isolate.immediate);
    return 0;
  }
}

void main() {
  test('every pool gives the serial results', () async {
    final jobs = [for (var n = 0; n < 40; n++) _Squares(n * 1000)];
    final serial = await Future.wait(jobs.map(Parallel.serial.submit));
    final pool = Parallel.ofSize(3);
    expect(pool.workers, 3);
    expect(await Future.wait(jobs.map(pool.submit)), serial);
  });

  test('idle workers pull the next job', () async {
    final pool = Parallel.ofSize(2);
    final finished = <String>[];
    await Future.wait([
      for (final job in const [
        _Busy('long', 400),
        _Busy('a', 20),
        _Busy('b', 20),
        _Busy('c', 20),
      ])
        pool.submit(job).then(finished.add),
    ]);
    // The short ones on the other worker, one after another, before the
    // long one ends (dealt in turn, the third would wait for it).
    expect(finished, ['a', 'b', 'c', 'long']);
  });

  test('a job that fails fails its future', () async {
    await expectLater(
      Parallel.ofSize(2).submit(const _Throws()),
      throwsA(
        isA<JobFailure>().having(
          (failure) => failure.message,
          'message',
          contains('no luck'),
        ),
      ),
    );
    await expectLater(
      Parallel.serial.submit(const _Throws()),
      throwsA(isA<StateError>()),
    );
  });

  test('a worker that ends fails its job and is replaced', () async {
    final pool = Parallel.ofSize(4);
    await expectLater(pool.submit(const _Dies()), throwsA(isA<JobFailure>()));
    expect(await pool.submit(const _Squares(4)), 14);
  });

  test('the jobs attribute sets the workers', () {
    expect(Parallel.forAttribute('1').workers, 0);
    expect(Parallel.forAttribute('5').workers, 5);
    expect(Parallel.forAttribute(null).workers, isNot(1));
    expect(Parallel.forAttribute('many').workers, greaterThanOrEqualTo(0));
    Parallel.nested = true;
    addTearDown(() => Parallel.nested = false);
    expect(Parallel.forAttribute('5').workers, 0);
  });
}
