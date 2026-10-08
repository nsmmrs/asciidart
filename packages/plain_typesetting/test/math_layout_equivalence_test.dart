// The math layout against a frozen copy of it (test/support/frozen): the
// same formulas, random trees among them, must come out the same to the
// last bit of every double (items are moved in place and glyph metrics
// cached now; neither may change a coordinate).
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_math/plain_math.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/exact_canvas.dart';
import 'support/frozen/math_layout.dart';

const _asciimath = [
  'x^2 + y^2 = z^2',
  'sum_(i=1)^n i^3=((n(n+1))/2)^2',
  'int_0^1 f(x) dx',
  'sqrt(1 + sqrt(1 + sqrt(x)))',
  'root(3)(x+1)',
  'lim_(x->oo) (1 + 1/x)^x = e',
  '[[a,b],[c,d]]',
  '((a,b),(c,d))',
  '{(x, x >= 0), (-x, x < 0):}',
  'hat(x) + bar(y) + vec(v) + dot(a) + ddot(b) + ul(c)',
  'obrace(1+2+3)^"six" + ubrace(a+b)_"sum"',
  "f'(x) = lim_(h->0) (f(x+h)-f(x))/h",
  '|x| + ||v|| + |__x__| + |~x~|',
  'bb(A) + cc(B) + fr(C) + sf(D) + tt(E) + bbb(R)',
  'alpha beta gamma Delta Omega',
  'a/b/c/d',
  '(((((x)))))',
  'x_1^2 x_(i,j)^(k+1)',
  'prod_(k=1)^oo (1 - x^k)',
  'color(red)(x) + color(blue)(y)',
  'cancel(x) + overset(def)(=) + underset(n)(max)',
  'oint_C F * dr',
  'dim ker f + dim im f = n',
];

const _latex = [
  r'\frac{a}{b} + \dfrac{1}{2} + \tfrac{3}{4}',
  r'\sqrt[n]{x^n + y^n}',
  r'\sum_{k=0}^{\infty} \frac{x^k}{k!}',
  r'\int_{-\infty}^{\infty} e^{-x^2} \, dx = \sqrt{\pi}',
  r'\left( \frac{a}{b} \right) \left[ x \right] \left\{ y \right\}',
  r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
  r'\begin{cases} 1 & x > 0 \\ 0 & \text{otherwise} \end{cases}',
  r'\overline{AB} + \underline{CD} + \widehat{xyz} + \overbrace{a+b}^{n}',
  r'\binom{n}{k} = \frac{n!}{k!(n-k)!}',
  r'\mathbf{F} = m\mathbf{a}, \mathcal{L}, \mathbb{R}, \mathfrak{g}',
  r'\lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n',
  r'\boxed{E = mc^2}',
  r'x \xrightarrow{f} y \xleftarrow[g]{} z',
  r'\left\| \sum_i v_i \right\|^2 \le \sum_i \|v_i\|^2',
  '{a}^{b^{c^{d}}}',
  r'\frac{\frac{\frac{1}{2}}{3}}{4}',
  r'\iint_D \iiint_V \oint_C',
  r'\color{red}{x} + \textcolor{blue}{y}',
  r'\mathop{\mathrm{arg\,max}}_{\theta} L(\theta)',
  r'\hat{a} \tilde{b} \vec{c} \dot{d} \ddot{e} \bar{f} \check{g} \breve{h}',
];

void main() {
  final font = OpenTypeShaper(
    OpenTypeFont.parse(
      File('test/fonts/notosansmath-subset.ttf').readAsBytesSync(),
    ),
  );
  final serif = OpenTypeShaper(
    OpenTypeFont.parse(
      File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
    ),
  );
  final layout = MathLayout(font, fallbacks: [serif]);
  final frozen = FrozenMathLayout(font, fallbacks: [serif]);

  List<String> painted(
    void Function(Canvas canvas, double x, double y) paintAt,
    double w,
    double h,
    double d,
  ) {
    final canvas = ExactCanvas();
    paintAt(canvas, 0, 0);
    return ['${exact(w)} ${exact(h)} ${exact(d)}', ...canvas.calls];
  }

  void same(MathNode tree, String label) {
    for (final display in [false, true]) {
      for (final size in [10.0, 10.5, 7.3, 13.75]) {
        final a = layout.layout(tree, size: size, display: display);
        final b = frozen.layout(tree, size: size, display: display);
        expect(
          painted(a.paintAt, a.width, a.height, a.depth),
          painted(b.paintAt, b.width, b.height, b.depth),
          reason: '$label at $size${display ? ', display' : ''}',
        );
      }
    }
  }

  test('AsciiMath formulas set as before, bit for bit', () {
    for (final source in _asciimath) {
      same(asciimathToMath(source), source);
    }
  });

  test('LaTeX formulas set as before, bit for bit', () {
    for (final source in _latex) {
      same(latexToMath(source, unknown: {}), source);
    }
  });

  test('deep nesting set as before, bit for bit', () {
    same(asciimathToMath('${'(' * 60}x${')' * 60}'), 'nested parentheses');
    same(
      latexToMath('${r'\frac{' * 30}x${'}{y}' * 30}', unknown: {}),
      'nested fractions',
    );
  });

  test('random trees set as before, bit for bit', () {
    for (var seed = 0; seed < 400; seed++) {
      same(_RandomTree(math.Random(seed)).node(5), 'seed $seed');
    }
  });
}

/// Random formula trees: every kind of node, with the operators, fences,
/// accents and large operators the layout treats apart.
final class _RandomTree {
  new(this.random);

  final math.Random random;

  T pick<T>(List<T> values) => values[random.nextInt(values.length)];

  static const _identifiers = ['x', 'y', 'f', 'sin', 'α', 'Ω', 'ℏ', 'é', 'Ж'];
  static const _numbers = ['1', '2', '3.14', '42'];
  static const _operators = [
    '+', '-', '=', '<', '≤', ',', ';', '(', ')', '[', ']', '{', '}', '|', //
    '‖', '∑', '∏', '∫', '∮', '⋃', 'lim', 'max', '→', '⇒', '⟨', '⟩', '¯', //
    '^', '~', '→', '⏞', '⏟', '.', "'", '∂', '∇', '×', '±', '∘', '…',
  ];
  static const List<String?> _variants = [
    null, 'bold', 'italic', 'double-struck', 'script', 'fraktur', //
    'sans-serif', 'monospace', 'bold-italic', 'normal',
  ];
  static const _lengths = [
    '1em',
    '0.5ex',
    '3pt',
    '2px',
    '4mu',
    'thinmathspace',
  ];
  static const _notations = [
    'box', 'roundedbox', 'circle', 'top', 'bottom', 'left', 'right', //
    'updiagonalstrike', 'downdiagonalstrike', 'horizontalstrike', //
    'verticalstrike', 'longdiv', 'actuarial',
  ];

  MathNode token() => switch (random.nextInt(4)) {
    0 => MathToken(
      MathTokenKind.identifier,
      pick(_identifiers),
      variant: pick(_variants),
    ),
    1 => MathToken(MathTokenKind.number, pick(_numbers)),
    2 => MathToken(MathTokenKind.text, pick(['if', 'otherwise', ' a b '])),
    _ => MathToken(
      MathTokenKind.operator,
      pick(_operators),
      stretchy: pick([null, true, false]),
      largeOperator: pick([null, null, true]),
      movableLimits: pick([null, true, false]),
      fence: pick([null, true]),
      form: pick([null, 'prefix', 'postfix', 'infix']),
    ),
  };

  MathNode node(int depth) {
    if (depth <= 0 || random.nextInt(5) == 0) return token();
    MathNode child() => node(depth - 1);
    MathNode? maybe() => random.nextBool() ? child() : null;
    return switch (random.nextInt(10)) {
      0 || 1 => MathRow([
        for (var i = 0, n = random.nextInt(5); i < n; i++) child(),
      ]),
      2 => MathStyled(
        child(),
        display: pick([null, true, false]),
        scriptLevel: pick([null, '0', '+1', '-1', '2']),
        color: pick([null, 'red', '#00f', 'nonsense']),
        variant: pick(_variants),
      ),
      3 => MathScripts(child(), sub: maybe(), sup: maybe()),
      4 => MathUnderOver(
        child(),
        under: maybe(),
        over: maybe(),
        accent: random.nextBool(),
        accentUnder: random.nextBool(),
      ),
      5 => MathFraction(
        child(),
        child(),
        lineThickness: pick([null, 'thin', 'thick', '0', '2', '1pt']),
      ),
      6 => MathRadical(child(), index: maybe()),
      7 => MathTable([
        for (var r = 0, n = 1 + random.nextInt(3); r < n; r++)
          [for (var c = 0, m = random.nextInt(4); c < m; c++) child()],
      ], columnAlign: pick([null, 'left', 'right center', 'center  left'])),
      8 => MathEnclose(child(), [
        for (var i = 0, n = random.nextInt(3); i < n; i++) pick(_notations),
      ]),
      _ => MathRow([
        MathSpace(pick([null, ..._lengths])),
        child(),
      ]),
    };
  }
}
