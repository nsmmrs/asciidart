// SVG path data parsing pinned to the RegExp-based parser of commit
// 17001e86 (test/frozen/svg_path.dart), run side by side on the same
// platform: the segments of seeded random path data, well formed and not
// (numbers like `5.`, `.5`, `1e`, `-`, `1e+`, `.e1`; stray letters, flags
// and separators), and the numbers of single tokens checked against the
// number grammar's RegExp.
import 'dart:math' as math;

import 'package:plain_pdf/plain_pdf.dart';
import 'package:test/test.dart';

import 'frozen/svg_path.dart' as frozen;

String number(math.Random r) => switch (r.nextInt(14)) {
  0 => '${r.nextInt(500)}',
  1 => '-${(r.nextDouble() * 300).toStringAsFixed(3)}',
  2 => '.${r.nextInt(999)}',
  3 => '${(r.nextDouble() * 10).toStringAsFixed(2)}e${r.nextInt(3)}',
  4 => '${r.nextInt(50)}.',
  5 => '+${r.nextInt(9)}E-${r.nextInt(4)}',
  6 => '${r.nextInt(9)}e',
  7 => '-',
  8 => '.',
  9 => '1e+',
  10 => '.e1',
  11 => '0${r.nextInt(9)}.5.5',
  12 => '${r.nextInt(3)}${r.nextInt(2)}', // flags run together
  _ => (r.nextDouble() * 100).toStringAsFixed(4),
};

String pathData(math.Random r, int commands, {required bool clean}) {
  final out = StringBuffer('M${number(r)},${number(r)}');
  const separators = [' ', ',', '', '\t', '\n ', ' , '];
  for (var i = 0; i < commands; i++) {
    if (!clean && r.nextInt(40) == 0) {
      out.write('xX#é '[r.nextInt(5)]);
    }
    final command = 'MmLlHhVvCcSsQqTtAaZz'[r.nextInt(20)];
    out.write(r.nextBool() ? command : ' $command ');
    final count = switch (command.toUpperCase()) {
      'M' || 'L' || 'T' => 2,
      'H' || 'V' => 1,
      'C' => 6,
      'S' || 'Q' => 4,
      'A' => 7,
      _ => 0,
    };
    // Sometimes repeated, without the letter; sometimes short.
    final total =
        count * (r.nextInt(4) == 0 ? 2 : 1) - (clean ? 0 : r.nextInt(2));
    for (var k = 0; k < total; k++) {
      if (k > 0) out.write(separators[r.nextInt(separators.length)]);
      if (command.toUpperCase() == 'A' && (k % 7 == 3 || k % 7 == 4)) {
        out.write(clean || r.nextInt(10) > 0 ? '${r.nextInt(2)}' : '2');
      } else {
        out.write(
          clean ? '${r.nextInt(400) - 200}.${r.nextInt(99)}' : number(r),
        );
      }
    }
  }
  return out.toString();
}

String describe(SvgPath path) => [
  for (final s in path.segments)
    switch (s) {
      MoveSegment(:final x, :final y) => 'M$x,$y',
      LineSegment(:final x, :final y) => 'L$x,$y',
      CubicSegment(
        :final x1,
        :final y1,
        :final x2,
        :final y2,
        :final x,
        :final y,
      ) =>
        'C$x1,$y1,$x2,$y2,$x,$y',
      CloseSegment() => 'Z',
    },
].join(';');

String describeFrozen(frozen.SvgPath path) => [
  for (final s in path.segments)
    switch (s) {
      frozen.MoveSegment(:final x, :final y) => 'M$x,$y',
      frozen.LineSegment(:final x, :final y) => 'L$x,$y',
      frozen.CubicSegment(
        :final x1,
        :final y1,
        :final x2,
        :final y2,
        :final x,
        :final y,
      ) =>
        'C$x1,$y1,$x2,$y2,$x,$y',
      frozen.CloseSegment() => 'Z',
    },
].join(';');

/// What parsing [data] gives: its segments, or the error it throws.
String outcome(String data) {
  try {
    return describe(SvgPath.parse(data));
  } on FormatException catch (e) {
    return 'error: ${e.message}';
  }
}

String frozenOutcome(String data) {
  try {
    return describeFrozen(frozen.SvgPath.parse(data));
  } on FormatException catch (e) {
    return 'error: ${e.message}';
  }
}

void main() {
  test('random path data parses as before', () {
    final r = math.Random(5);
    for (var i = 0; i < 3000; i++) {
      final data = pathData(r, r.nextInt(30), clean: i.isEven);
      expect(outcome(data), frozenOutcome(data), reason: data);
    }
  });

  test('numbers follow the grammar', () {
    final grammar = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
    final r = math.Random(8);
    const alphabet = '0123456789+-.eE ,x';
    for (var i = 0; i < 20000; i++) {
      final token = String.fromCharCodes([
        for (var k = r.nextInt(8) + 1; k > 0; k--)
          alphabet.codeUnitAt(r.nextInt(alphabet.length)),
      ]);
      // (Separators before a number are skipped.)
      final match = grammar.matchAsPrefix(
        token,
        token.indexOf(RegExp(r'[^ ,]|$')),
      );
      final segments = SvgPath.parse('M$token 7').segments;
      if (match == null) {
        expect(segments, isEmpty, reason: token);
        continue;
      }
      // (The y may be missing: the token can hold more than a number.)
      if (segments.isEmpty) continue;
      expect(
        (segments.first as MoveSegment).x,
        double.parse(match[0]!),
        reason: token,
      );
    }
  });
}
