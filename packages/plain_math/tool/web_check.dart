// Compiled to JavaScript in CI: converts AsciiMath and LaTeX (characters
// beyond the BMP among them) to MathML and reads it back, printing a
// digest; the CI job compares it with the Dart VM's, as the results must
// be the same.
import 'dart:convert';

import 'package:plain_math/plain_math.dart';

const List<String> _asciimath = [
  'sum_(i=1)^n i^3=((n(n+1))/2)^2',
  'int_0^1 f(x) dx',
  '[[a,b],[c,d]]',
  'sqrt(x) + root(3)(y)',
  'bb "bold" cc "C" fr "F"',
  'x in RR, y != 0',
];

const List<String> _latex = [
  r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}',
  r'\sum_{k=1}^\infty \frac{1}{k^2} = \frac{\pi^2}{6}',
  r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
  r'\text{if $x > 0$, then } \mathbf{F} = m\mathbf{a}',
  r'𝐀 + \not x \dots + \operatorname*{arg\,max}_\theta',
];

/// [node]'s shape: its kind and its tokens' text.
String _shape(MathNode node) => switch (node) {
  MathToken(:final kind, :final text) => '${kind.name}:$text',
  MathRow(:final children) => '(${children.map(_shape).join(' ')})',
  MathStyled(:final child) => 's${_shape(child)}',
  MathScripts(:final base, :final sub, :final sup) =>
    '^(${_shape(base)} ${sub == null ? '' : _shape(sub)} '
        '${sup == null ? '' : _shape(sup)})',
  MathUnderOver(:final base, :final under, :final over) =>
    '_(${_shape(base)} ${under == null ? '' : _shape(under)} '
        '${over == null ? '' : _shape(over)})',
  MathFraction(:final numerator, :final denominator) =>
    '/(${_shape(numerator)} ${_shape(denominator)})',
  MathRadical(:final radicand, :final index) =>
    'r(${_shape(radicand)} ${index == null ? '' : _shape(index)})',
  MathTable(:final rows) =>
    't(${rows.map((r) => r.map(_shape).join(' & ')).join(r' \\ ')})',
  MathEnclose(:final child, :final notations) =>
    'e$notations(${_shape(child)})',
  MathSpace(:final width) => 'w$width',
};

void main() {
  final parts = [
    for (final e in _asciimath) ...[
      asciimathToMathml(e),
      _shape(asciimathToMath(e)),
    ],
    for (final tex in _latex) ...[
      latexToMathml(tex, display: true),
      _shape(latexToMath(tex)),
    ],
  ];
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(parts.join('\n'))) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${parts.length} $b-$a');
}
