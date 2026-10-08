/// The converters against a frozen copy of themselves (test/frozen, the
/// code at 17001e86): over the fixtures and tens of thousands of fuzzed
/// inputs, every output must be the frozen one's, byte for byte (the
/// MathML, the unknown commands in order, the `MathNode` tree field by
/// field, the reader's errors). This is the gate for changing how they
/// work (faster, typed) without changing what they write.
///
/// The fuzzed inputs come from a fixed seed, and a digest of the frozen
/// copy's outputs over them guards the copy itself. To fuzz further, set
/// `PLAIN_MATH_FUZZ_SEED` (and `PLAIN_MATH_FUZZ_COUNT`, 20,000 by
/// default); the digest isn't checked then.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_math/plain_math.dart';
import 'package:test/test.dart';

import 'frozen/convert.dart';

void main() {
  final seedOverride = int.tryParse(
    Platform.environment['PLAIN_MATH_FUZZ_SEED'] ?? '',
  );
  final count =
      int.tryParse(Platform.environment['PLAIN_MATH_FUZZ_COUNT'] ?? '') ??
      20000;
  final fixed = seedOverride == null && count == 20000;

  /// That [output] (the frozen copy's when [frozen]) is the frozen copy's
  /// for every one of [inputs] (and, over the fixed inputs, that the
  /// frozen copy's outputs digest to [digest]).
  void expectSame(
    List<String> inputs,
    String Function(int i, String input, {required bool frozen}) output,
    int digest,
  ) {
    final frozenDigest = _Digest();
    final mismatches = <String>[];
    for (final (i, e) in inputs.indexed) {
      final want = output(i, e, frozen: true);
      frozenDigest.add(want);
      final got = output(i, e, frozen: false);
      if (got != want) {
        mismatches.add('input ${jsonEncode(e)}\n  want $want\n  got  $got');
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
    if (fixed) expect(frozenDigest.value, digest, reason: 'the frozen copy');
  }

  group('AsciiMath', () {
    final inputs = [
      ...File('test/fixtures/asciimath/expressions.txt')
          .readAsLinesSync()
          .where((l) => l.isNotEmpty),
      ..._asciimathEdges,
      ..._fuzz(_asciimathPieces, seedOverride ?? 42, count),
      ..._long,
    ];

    test('MathML as the frozen copy writes it, over ${inputs.length} '
        'inputs', () {
      expectSame(inputs, (i, e, {required frozen}) {
        // Every few, with a prefix and attributes.
        final prefix = i % 7 == 3 ? 'mml:' : '';
        final attributes = i % 11 == 5
            ? const {'display': 'block', 'title': '<&>"é'}
            : const <String, String>{};
        return (frozen ? frozenAsciimathToMathml : asciimathToMathml)(
          e,
          prefix: prefix,
          attributes: attributes,
        );
      }, _asciimathDigest);
    });

    test('trees as the frozen copy reads them', () {
      expectSame(
        inputs,
        (i, e, {required frozen}) => _outcome(
          () => (frozen ? frozenAsciimathToMath : asciimathToMath)(e),
        ),
        _asciimathTreeDigest,
      );
    });
  });

  group('LaTeX', () {
    final inputs = [
      for (final e in jsonDecode(
        File('test/fixtures/temml/expressions.json').readAsStringSync(),
      ) as List<Object?>)
        (e! as Map<String, Object?>)['tex']! as String,
      ..._latexEdges,
      ..._fuzz(_latexPieces, seedOverride ?? 7, count),
      ..._latexLong,
    ];

    test('MathML and unknown commands as the frozen copy writes them, over '
        '${inputs.length} inputs', () {
      expectSame(inputs, (i, e, {required frozen}) {
        final unknown = <String>{};
        final mathml = (frozen ? frozenLatexToMathml : latexToMathml)(
          e,
          display: i.isOdd,
          unknown: unknown,
        );
        return '$mathml ${unknown.join(' ')}';
      }, _latexDigest);
    });

    test('trees (or the reader error) as the frozen copy reads them', () {
      expectSame(inputs, (i, e, {required frozen}) {
        final unknown = <String>{};
        final tree = _outcome(
          () => (frozen ? frozenLatexToMath : latexToMath)(
            e,
            display: i.isOdd,
            unknown: unknown,
          ),
        );
        return '$tree ${unknown.join(' ')}';
      }, _latexTreeDigest);
    });
  });
}

// The digests of the frozen copy's outputs over the fixed inputs.
const int _asciimathDigest = 1549736355;
const int _asciimathTreeDigest = 1446294107;
const int _latexDigest = 1809389773;
const int _latexTreeDigest = 1018375130;

/// [convert]'s tree as text, or the error it throws.
String _outcome(MathNode Function() convert) {
  try {
    return _dump(convert());
  } on MathMLException catch (e) {
    return 'MathMLException(${e.message})';
  }
}

/// [node], every field of it, as text.
String _dump(MathNode node) => switch (node) {
  MathToken(
    :final kind,
    :final text,
    :final variant,
    :final stretchy,
    :final largeOperator,
    :final movableLimits,
    :final fence,
    :final form,
  ) =>
    '${kind.name}(${jsonEncode(text)} $variant $stretchy $largeOperator '
        '$movableLimits $fence $form)',
  MathRow(:final children) => 'row[${children.map(_dump).join(', ')}]',
  MathStyled(
    :final child,
    :final display,
    :final scriptLevel,
    :final color,
    :final variant,
  ) =>
    'styled($display $scriptLevel ${jsonEncode(color)} $variant '
        '${_dump(child)})',
  MathScripts(:final base, :final sub, :final sup) =>
    'scripts(${_dump(base)} ${_maybe(sub)} ${_maybe(sup)})',
  MathUnderOver(
    :final base,
    :final under,
    :final over,
    :final accent,
    :final accentUnder,
  ) =>
    'underover($accent $accentUnder ${_dump(base)} ${_maybe(under)} '
        '${_maybe(over)})',
  MathFraction(:final numerator, :final denominator, :final lineThickness) =>
    'frac($lineThickness ${_dump(numerator)} ${_dump(denominator)})',
  MathRadical(:final radicand, :final index) =>
    'root(${_dump(radicand)} ${_maybe(index)})',
  MathTable(:final rows, :final columnAlign) =>
    'table($columnAlign '
        '${rows.map((r) => '[${r.map(_dump).join(', ')}]').join(' ')})',
  MathEnclose(:final child, :final notations) =>
    'enclose(${notations.join(' ')} ${_dump(child)})',
  MathSpace(:final width) => 'space($width)',
};

String _maybe(MathNode? node) => node == null ? '-' : _dump(node);

/// FNV-1a over the UTF-16 code units of texts, 32 bits.
final class _Digest {
  int value = 0x811c9dc5;

  void add(String text) {
    for (var i = 0; i < text.length; i++) {
      value = ((value ^ text.codeUnitAt(i)) * 0x01000193) & 0xffffffff;
    }
    value = ((value ^ 0x0a) * 0x01000193) & 0xffffffff;
  }
}

/// A small PRNG of its own (splitmix-like, 32 bits), so the inputs don't
/// depend on `dart:math`'s.
final class _Random {
  new(int seed) : _state = seed & 0xffffffff;

  int _state;

  int next(int max) {
    _state = (_state + 0x9e3779b9) & 0xffffffff;
    var z = _state;
    z = ((z ^ (z >> 16)) * 0x85ebca6b) & 0xffffffff;
    z = ((z ^ (z >> 13)) * 0xc2b2ae35) & 0xffffffff;
    z ^= z >> 16;
    return z % max;
  }
}

/// [count] inputs of up to 25 of [pieces] (or, one time in eight, a
/// random printable ASCII character).
List<String> _fuzz(List<String> pieces, int seed, int count) {
  final random = _Random(seed);
  String piece() => random.next(8) == 0
      ? String.fromCharCode(0x20 + random.next(0x5f))
      : pieces[random.next(pieces.length)];
  return [
    for (var i = 0; i < count; i++)
      [for (var j = random.next(25); j >= 0; j--) piece()].join(),
  ];
}

// dart format off
const List<String> _asciimathPieces = [
  'a', 'b', 'x', 'y', 'f', 'g', 'd', 'dx', '1', '2.5', '0', '12', '1.',
  '.5', '-1', '-', '+', '*', '**', '***', '/', '//', '_', '^', '^^',
  '(', ')', '[', ']', '{', '}', '(:', ':)', '{:', ':}', '|', '||', '|:',
  ':|', ':|:', '<<', '>>', ',', ';', ':', '.', '...', ' ', '  ', '\t', '\n',
  '\r', '\f', '\v', '"t x"', '"', '"<&>"', 'text(ab)', 'text(', 'text()',
  'sqrt', 'root', 'frac', 'color', 'red', 'Blue', '#f00', '#00FF7f', 'sum',
  'prod', 'int', 'oint', 'oo', 'lim', 'alpha', 'Gamma', 'bb', 'bbb', 'cc',
  'sfbi', 'hat', 'bar', 'vec', 'ul', 'abs', 'Abs', 'norm', 'floor', 'ceil',
  r'\ ', r'\\', r'\', r'\5', r'\x', r'\t', 'α', '𝟎', '∑', '\u{1d400}',
  '\ud800', '\udc00', 'é', 'twoheadrightarrowtail', 'twoheadrightarrow',
  'twoheadrightarro', '>->>', '->>', '->', '|->', '<=>', '<=', '!=', '!in',
  'stackrel', 'overset', 'underset', 'ubrace', 'obrace', 'cancel', 'tilde',
  'O/', '/_', r'/_\', 'ii', 'iii', 'bii', 'left(', 'right)', 'left[',
  'right]', '|__', '__|', '|~', '~|', 'CC', 'RR', 'sin', 'Sin', 'log', 'mod',
  'and', 'or', 'not', 'if', 'AA', 'EE', 'xx', '-:', '@', 'o+', 'ox', 'o.',
  '((a,b),(c,d))', '[[1,2],[3,4]]', '(a,b)', '[a,b]', '<', '>', '&', "'",
];

const List<String> _asciimathEdges = [
  '', ' ', r'\', r'\\', r'\ ', r'\  x', '"', '""', 'text(', 'text()',
  'twoheadrightarrowtail', 'twoheadrightarrowtailx', r'\ \ \ \ \ \ \ \ \ ',
  'abcdefghijklmnopqrstuvwxyz', '\ud800', '\udc00', '\ud800\ud800',
  '\udc00\ud800', '𝟎𝟎', 'x\ud835', 'a\vb', '-', '--1', '1.2.3', '1..2',
  '_', '^', '_^', 'x_', 'x^', 'x_1^', 'x__', '()', '(', ')', '|x|', '||',
  'color(red)(x)', 'color(#abc)(x)', 'color(#AbCdEf)(x)', 'color(x_1)(y)',
  'color', 'frac', 'frac a', 'root', 'sqrt', '((a,b),(c,d))',
  '((a),(b),(c))', '[(a,b),(c,d)]', '((a,b),(c))', '(a,b),(c,d)',
  '{(1,2),(3,4)}', 'sum_(i=0)^n', 'lim_(x->0)', 'hat x^2', 'ubrace(a)_b',
  'obrace(a)^b', 'stackrel(a)(b)', 'overset(a)(b)', 'underset(a)(b)',
  'a//b', 'a/b/c', '(a)/(b)', '1/', '/1', 'a / / b', 'x x x x x x x',
];

final List<String> _long = [
  for (final k in [50, 200, 400]) List.filled(k, 'a+b').join('+'),
  List.filled(100, '((a,b),(c,d))').join(' '),
  List.filled(100, 'x_1^2 sum_(i=0)^n').join(' '),
  '${'(' * 60}x${')' * 60}',
  '${'sqrt ' * 60}x',
  List.filled(80, 'a/b').join(' '),
  List.filled(80, '"t" text(u) 1.5').join(' '),
];

const List<String> _latexPieces = [
  'a', 'x', 'X', '1', '23', '4.5', '.5', '+', '-', '=', '<', '>', '*', '/',
  '^', '_', "'", "''", '{', '}', '[', ']', '(', ')', '|', ' ', '\t', '\n',
  '%c\n', '%', '~', '&', r'$', ',', ';', '!', '?', r'\frac', r'\dfrac',
  r'\tfrac', r'\cfrac', r'\binom', r'\sqrt', r'\sqrt[3]', r'\left',
  r'\right', r'\middle', r'\left(', r'\right)', r'\left.', r'\right.',
  r'\left\{', r'\right\}', r'\middle|', r'\alpha', r'\Omega', r'\infty',
  r'\sum', r'\int', r'\oint', r'\lim', r'\liminf', r'\max', r'\sin',
  r'\limits', r'\nolimits', r'\text{a -- b}', r'\text{\"o $x^2$}',
  r"\text{``q'' --- \i\j \^{\i} \ss~\ x}", r'\text{<&>}', r'\textbf{b}',
  r'\mathbf', r'\mathbb', r'\boldsymbol', r'\hat', r'\vec', r'\underline',
  r'\overbrace', r'\underbrace', r'\overset', r'\underset', r'\stackrel',
  r'\color{red}', r'\color{"x"}', r'\textcolor{blue}', r'\boxed', r'\fbox',
  r'\cancel', r'\bcancel', r'\xcancel', r'\sout', r'\begin{pmatrix}',
  r'\end{pmatrix}', r'\begin{bmatrix*}[r]', r'\end{bmatrix*}',
  r'\begin{cases}', r'\end{cases}', r'\begin{array}{lcr}', r'\end{array}',
  r'\begin{aligned}', r'\end{aligned}', r'\begin{alignat}{2}',
  r'\begin{foo}', r'\end{foo}', r'\\', r'\\[2pt]', r'\cr', r'\not',
  r'\not=', r'\not\in', r'\not<', r'\not{a<b}', r'\dots', r'\ldots',
  r'\cdots', r'\operatorname{lcm}', r'\operatorname*{arg\,max}',
  r'\operatorname{a\alpha b}', r'\mathop{x}', r'\foo', r'\9', r'\,', r'\:',
  r'\;', r'\!', r'\ ', r'\quad', r'\{', r'\}', r'\|', r'\_', r'\#', r'\&',
  r'\$', r'\%', r'\', 'α', 'é', '𝟎', '\u{1d400}', '\ud800', '\udc00',
  r'\big(', r'\Bigl\langle', r'\bigr\rangle', r'\big\{', r'\big\backslash',
  r'\big/', r'\big\foo', r'\displaystyle', r'\textstyle', r'\scriptstyle',
  r'\label{x}', r'\tag{1}', r'\notag', r'\mbox{m}', r'\hbox{h}',
  r'\mathrm{d}', r'\imath', r'\backslash', r'\text{a\x b}', r'\text{\9}',
];

const List<String> _latexEdges = [
  '', ' ', r'\', '{', '}', '}}', '{{', '^', '_', 'x^', 'x_', "x'''^2_1",
  r'x^\9', r'x^\alpha', r'\not', r'\not x', r'\not\alpha', r'\not{a<b}',
  r'\not{=}', r'\not\leq', r'\not\mid', r'\not{}', r'\not\text{<}',
  '\\not\n=', r'\frac', r'\frac{a}', r'\sqrt[', r'\sqrt[3', r'\left(',
  r'\left( x \middle| y', r'\right)', r'\color{red}', r'\color{"}x',
  r'\color{a"b}{x}', r'\textcolor{"}{x}', r'\text{', r'\text{$x',
  r'\text{\', r'\text{\"}', r'\text{\"{', r'\text{\^\i}', r'\begin{matrix}',
  r'\begin{matrix}a&b\\c&d\end{matrix}', r'\begin{matrix}a\\\end{matrix}',
  r'\begin{matrix}a\\ \end{matrix}', r'\begin{matrix}a\\{}\end{matrix}',
  r'\begin{array}{l|c}a&b\end{array}', r'\begin{pmatrix*}[l]a\end{pmatrix*}',
  r'\operatorname*', r'\operatorname{\foo x}', r'\mathop', '%', '% x',
  r'\dots+', r'\dots\int', r'\dots\alpha', r'\dots\leq', r'\dots',
  "x'", r'\sum\limits_{i}^{n}', r'\int\limits_0^1', r'\lim\nolimits_x',
  r'\not\not=', r'\not{\mathbf{<}}', r'\not{x<}', '\\not{\n<}',
  r'\not\left<', r'\not\sqrt{<}', r'\not{\text{a}<}', r'\not{<<}',
  r"\text{---``--''}", r"\text{'''}", r'\text{x  y\ \ z~~w}',
];

final List<String> _latexLong = [
  '${r'\frac{' * 100}x${'}{y}' * 100}',
  List.filled(200, 'a+b').join('+'),
  List.filled(60, r'\sum_{i=0}^n x_i^2').join(' '),
  '\\begin{pmatrix}${List.filled(40, 'a&b&c').join(r'\\')}\\end{pmatrix}',
  '\\text{${List.filled(80, '``a\'\' -- b \\"o ').join()}}',
  '${r'\left(' * 40}x${r'\right)' * 40}',
];
// dart format on
