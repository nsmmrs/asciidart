// The pair tables of the line breaker against its rules: every decision
// the tables give must be the one the rules give in context. The tables
// hold the decisions of class pairs believed to depend on nothing else
// (`_needsRules` in lib/src/line_break.dart lists the others); this test
// keeps that list honest, now and on every update of UAX #14.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:plain_unicode/src/line_break.dart' show lineBreaksByRules;
import 'package:test/test.dart';

import 'oracle/line_break_data_v0.dart' as data_v0;

String _signature(List<LineBreak> breaks) =>
    [for (final b in breaks) '${b.offset}${b.mandatory ? '!' : ''}'].join(',');

/// The texts of [texts] where the tables and the rules differ, at most 20.
List<String> _differences(Iterable<String> texts) {
  final failures = <String>[];
  for (final text in texts) {
    final rules = _signature(lineBreaksByRules(text));
    final tables = _signature(lineBreaks(text));
    if (rules != tables && failures.length < 20) {
      failures.add(
        '${text.runes.map((r) => r.toRadixString(16)).join(' ')}\n'
        '  rules  $rules\n  tables $tables',
      );
    }
  }
  return failures;
}

/// One code point for each distinct set of line breaking properties (the
/// class and the flags the rules read), and those the rules single out.
List<int> _pool() {
  final representatives = <int, int>{};
  for (var r = 0; r < data_v0.rangeStarts.length; r++) {
    representatives.putIfAbsent(
      data_v0.rangeValues[r],
      () => data_v0.rangeStarts[r],
    );
  }
  return [
    ...representatives.values,
    ...[0x25cc, 0x200d, 0x300, 0x20, 0x31, 0x22, 0x201c, 0x201d, 0xab, 0xbb],
    ...[0x1f1e6, 0x1f466, 0x1f3fb, 0x1b05, 0x1b44, 0x1bf2, 0x3002, 0x300c],
  ];
}

void main() {
  test('the rules pass the conformance test on their own', () {
    final lines = const LineSplitter().convert(
      utf8.decode(
        gzip.decode(
          File('test/unicode/LineBreakTest.txt.gz').readAsBytesSync(),
        ),
      ),
    );
    var failures = 0;
    var cases = 0;
    for (final line in lines) {
      final data = line.split('#').first.trim();
      if (data.isEmpty) continue;
      final text = StringBuffer();
      final expected = <int>[];
      for (final token in data.split(RegExp(r'\s+'))) {
        switch (token) {
          case '÷':
            if (text.isNotEmpty) expected.add(text.length);
          case '×':
            break;
          default:
            text.writeCharCode(int.parse(token, radix: 16));
        }
      }
      cases++;
      final actual = [for (final b in lineBreaksByRules('$text')) b.offset];
      if (actual.join(',') != expected.join(',')) failures++;
    }
    expect(cases, greaterThan(15000));
    expect(failures, 0);
  });

  test('every sequence of three code points: tables and rules agree', () {
    final pool = _pool();
    final texts = <String>[];
    for (final x in pool) {
      for (final y in pool) {
        for (final z in pool) {
          texts.add(String.fromCharCodes([x, y, z]));
        }
      }
    }
    expect(_differences(texts), isEmpty);
  });

  test('random strings: tables and rules agree', () {
    final pool = [..._pool(), 0x20, 0x20, 0x20, 0x200d, 0x300];
    final random = Random(18);
    Iterable<String> strings(int count) sync* {
      for (var n = 0; n < count; n++) {
        yield String.fromCharCodes([
          for (var k = random.nextInt(12); k >= 0; k--)
            pool[random.nextInt(pool.length)],
        ]);
      }
    }

    expect(_differences(strings(300000)), isEmpty);
  });
}
