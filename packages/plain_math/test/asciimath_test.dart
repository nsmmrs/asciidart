/// AsciiMath to MathML (ADR-0014) against the `asciimath` gem 2.0.6:
/// `test/fixtures/asciimath/expected.json` is the gem's MathML for each
/// expression of `expressions.txt` (`AsciiMath.parse(e).to_mathml('mml:')`,
/// written by `tool/asciimath_corpus.rb`; see the fixture's README).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_math/plain_math.dart';
import 'package:test/test.dart';

void main() {
  final expected = jsonDecode(
    File('test/fixtures/asciimath/expected.json').readAsStringSync(),
  ) as Map<String, Object?>;
  for (final MapEntry(key: expression, :value) in expected.entries) {
    final mathml = value! as String;
    if (mathml.startsWith('ERROR')) {
      // The gem fails on it (an unclosed quote...); here it converts.
      test('does not fail on $expression', () {
        expect(asciimathToMathml(expression, prefix: 'mml:'), isNotEmpty);
      });
    } else {
      test(expression, () {
        expect(asciimathToMathml(expression, prefix: 'mml:'), mathml);
      });
    }
  }

  test('attributes on the math element', () {
    expect(
      asciimathToMathml(
        'x',
        prefix: 'mml:',
        attributes: const {'xmlns:mml': 'http://www.w3.org/1998/Math/MathML'},
      ),
      '<mml:math xmlns:mml="http://www.w3.org/1998/Math/MathML">'
      '<mml:mi>x</mml:mi></mml:math>',
    );
  });
}
