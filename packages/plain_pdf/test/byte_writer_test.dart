// The content-stream byte writer against the object layer it stands in
// for: numbers byte for byte as formatNumber writes them (a differential
// test over rounding ties, their neighbours and seeded random values),
// names as PdfName and strings as PdfString write them.
//
// PLAIN_PDF_FUZZ_SCALE=N multiplies the number of values (the research
// run checked 15.7 million, N = 50 or so).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_pdf/src/byte_writer.dart';
import 'package:test/test.dart';

final int scale =
    int.tryParse(Platform.environment['PLAIN_PDF_FUZZ_SCALE'] ?? '') ?? 1;

String written(void Function(ByteWriter out) write) {
  final out = ByteWriter();
  write(out);
  return latin1.decode(out.toBytes());
}

/// The values that differ (at most 10), as `value p=precision`.
List<String> mismatches(Iterable<double> values, int precision) {
  final failures = <String>[];
  final batch = <double>[];
  void check() {
    final out = ByteWriter();
    for (final value in batch) {
      out
        ..number(value, precision)
        ..byte(0x0a);
    }
    final lines = latin1.decode(out.toBytes()).split('\n');
    for (var i = 0; i < batch.length; i++) {
      final expected = formatNumber(batch[i], precision: precision);
      if (lines[i] != expected && failures.length < 10) {
        failures.add('${batch[i]} p=$precision: ${lines[i]}, not $expected');
      }
    }
    batch.clear();
  }

  for (final value in values) {
    batch.add(value);
    if (batch.length == 100000) check();
  }
  check();
  return failures;
}

double next(double value, int ulps) {
  final bits = ByteData(8)..setFloat64(0, value);
  bits.setInt64(0, bits.getInt64(0) + ulps);
  return bits.getFloat64(0);
}

/// Decimal ties at [precision] (k·5·10^-(p+1)) and their neighbours.
Iterable<double> ties(int precision, int count) sync* {
  final divisor = math.pow(10, precision + 1).toDouble();
  for (var k = -count; k < count; k++) {
    final x = k * 5 / divisor;
    yield x;
    if (x == 0) continue;
    for (final ulps in const [-2, -1, 1, 2]) {
      yield next(x, ulps);
    }
  }
}

/// Binary fractions: exact ties at some precisions.
Iterable<double> binaryFractions() sync* {
  for (var e = 1; e <= 40; e++) {
    for (var m = 1; m < 1000; m += 2) {
      yield m / math.pow(2, e);
      yield -m / math.pow(2, e);
    }
  }
}

/// Random values: coordinates on a page, colors and opacities, and the
/// sums and quotients layout computes.
Iterable<double> randomValues(int seed, int count) sync* {
  final random = math.Random(seed);
  for (var i = 0; i < count; i++) {
    yield (random.nextDouble() - 0.5) * 4000;
    yield random.nextDouble() * 2 - 1;
    final x = random.nextInt(842) * 0.75 + random.nextInt(1000) / 3.0;
    yield x;
    yield x * 11 / 1000;
    yield -x / 7;
    yield random.nextDouble() * math.pow(10, random.nextInt(15));
    yield random.nextDouble() * math.pow(10, -random.nextInt(12));
  }
}

void main() {
  group('number', () {
    for (final precision in const [3, 5]) {
      test('decimal ties and their neighbours, precision $precision', () {
        expect(mismatches(ties(precision, 100000 * scale), precision), isEmpty);
      });
      test('binary fractions, precision $precision', () {
        expect(mismatches(binaryFractions(), precision), isEmpty);
      });
      test('random values, precision $precision', () {
        expect(
          mismatches(randomValues(precision, 60000 * scale), precision),
          isEmpty,
        );
      });
    }

    test('every precision, fast path or not', () {
      for (var precision = 0; precision <= 12; precision++) {
        expect(mismatches(ties(precision, 2000), precision), isEmpty);
        expect(
          mismatches(randomValues(100 + precision, 2000), precision),
          isEmpty,
        );
      }
    });

    test('edges', () {
      const values = <double>[
        0,
        // Negative zero, which an int literal isn't.
        // ignore: prefer_int_literals
        -0.0,
        1,
        -1,
        0.5,
        -0.5,
        1e-320,
        -1e-320,
        0.000004,
        0.000005,
        -0.000005,
        0.999995,
        -0.999995,
        999999999999999,
        -999999999999999,
        999999999999.5,
        4503599627.370496,
        123456789.25,
        2.5,
        -2.5,
      ];
      for (final precision in const [1, 3, 5, 9]) {
        expect(mismatches(values, precision), isEmpty);
      }
    });

    test('numeric writes ints and doubles as formatNumber does', () {
      for (final value in const <num>[
        0, 1, -1, 42, -1234567, 999999999999999, 1000000000000000, //
        -1000000000000000, 0.0, -0.0, 2.25, -3.333333,
      ]) {
        expect(written((out) => out.numeric(value)), formatNumber(value));
      }
    });

    test('what formatNumber rejects throws, taking back the operator', () {
      for (final value in const [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        1e15,
        -1e16,
        1e300,
      ]) {
        expect(() => formatNumber(value), throwsArgumentError);
        final out = ByteWriter()..operator('q');
        expect(
          () => out
            ..number(1.5, 5)
            ..byte(0x20)
            ..number(value, 5),
          throwsArgumentError,
        );
        expect(latin1.decode(out.toBytes()), 'q\n');
      }
    });
  });

  test('names as PdfName writes them', () {
    final random = math.Random(7);
    const alphabet = 'Ab09 #()<>[]{}/%~!\t\u007fé中';
    for (var i = 0; i < 5000; i++) {
      final name = String.fromCharCodes([
        for (var k = random.nextInt(8); k >= 0; k--)
          if (random.nextInt(4) == 0)
            alphabet.codeUnitAt(random.nextInt(alphabet.length))
          else
            0x41 + random.nextInt(26),
      ]);
      expect(written((out) => out.name(name)), PdfName(name).toString());
    }
  });

  test('strings as PdfString writes them', () {
    final random = math.Random(9);
    for (var i = 0; i < 2000; i++) {
      final codes = [
        for (var k = random.nextInt(20); k > 0; k--) random.nextInt(300),
      ];
      final start = codes.isEmpty ? 0 : random.nextInt(codes.length);
      final end = start + random.nextInt(codes.length - start + 1);
      for (final hex in const [false, true]) {
        expect(
          written((out) => out.string(codes, start, end, hex: hex)),
          PdfString(codes.sublist(start, end), hex: hex).toString(),
        );
      }
    }
  });

  test('the buffer grows', () {
    final out = ByteWriter();
    for (var i = 0; i < 100000; i++) {
      out.integer(i);
    }
    final expected = StringBuffer();
    for (var i = 0; i < 100000; i++) {
      expected.write(i);
    }
    expect(latin1.decode(out.toBytes()), expected.toString());
  });
}
