// LaTeX math to MathML (ADR-0014): what each construct becomes, and that
// libpdf's MathML reader takes it.
import 'package:asciidart/src/math/latex.dart';
import 'package:libpdf/libpdf.dart';
import 'package:test/test.dart';

void main() {
  String body(String tex) {
    final mathml = latexToMathml(tex);
    // Every output reads as MathML.
    parseMathML(mathml);
    return mathml
        .replaceFirst('<math xmlns="http://www.w3.org/1998/Math/MathML">', '')
        .replaceFirst(RegExp(r'</math>$'), '');
  }

  test('identifiers, numbers, operators', () {
    expect(body('x+12.5'), '<mrow><mi>x</mi><mo>+</mo><mn>12.5</mn></mrow>');
    expect(body('a-b'), '<mrow><mi>a</mi><mo>−</mo><mi>b</mi></mrow>');
    expect(body(r'\alpha \leq \Omega'), contains('<mi>α</mi>'));
    expect(body(r'\Omega'), '<mi mathvariant="normal">Ω</mi>');
  });

  test('scripts, primes and groups', () {
    expect(body('x^2'), '<msup><mi>x</mi><mn>2</mn></msup>');
    expect(body('x_i^{n+1}'), contains('<msubsup><mi>x</mi><mi>i</mi><mrow>'));
    expect(body("f''"), '<msup><mi>f</mi><mo>′′</mo></msup>');
  });

  test('large operators take limits, integrals scripts', () {
    expect(
      body(r'\sum_{i=1}^n i'),
      startsWith('<mrow><munderover><mo movablelimits="true">∑</mo>'),
    );
    expect(body(r'\int_0^1 x'), contains('<msubsup><mo>∫</mo>'));
    expect(body(r'\sum\nolimits_i'), contains('<msub>'));
    expect(
      body(r'\lim_{n\to\infty}'),
      contains('<munder><mo movablelimits="true">lim</mo>'),
    );
  });

  test('fractions, binomials, roots', () {
    expect(body(r'\frac{a}{b}'), '<mfrac><mi>a</mi><mi>b</mi></mfrac>');
    expect(
      body(r'\dfrac12'),
      contains(
        '<mstyle displaystyle="true"><mfrac><mn>1</mn><mn>2</mn></mfrac>',
      ),
    );
    expect(body(r'\binom{n}{k}'), contains('<mfrac linethickness="0">'));
    expect(body(r'\sqrt{x}'), '<msqrt><mi>x</mi></msqrt>');
    expect(body(r'\sqrt[3]{x}'), '<mroot><mi>x</mi><mn>3</mn></mroot>');
  });

  test('delimiters: stretchy with left and right, not plain', () {
    expect(body('(x)'), contains('<mo stretchy="false">(</mo>'));
    expect(
      body(r'\left( x \middle| y \right\}'),
      '<mrow><mo stretchy="true" fence="true">(</mo><mi>x</mi>'
      '<mo stretchy="true" fence="true">|</mo><mi>y</mi>'
      '<mo stretchy="true" fence="true" form="postfix">}</mo></mrow>',
    );
    expect(body(r'\left. x \right|'), startsWith('<mrow><mi>x</mi>'));
  });

  test('functions, text and alphabets', () {
    expect(body(r'\sin x'), '<mrow><mi>sin</mi><mi>x</mi></mrow>');
    expect(body(r'\operatorname{rank} A'), contains('<mi>rank</mi>'));
    expect(body(r'\text{if } x'), contains('<mtext>if </mtext>'));
    expect(
      body(r'\mathbb{R}'),
      '<mstyle mathvariant="double-struck"><mi>R</mi></mstyle>',
    );
    expect(body(r'\mathrm{d}x'), contains('<mstyle mathvariant="normal">'));
  });

  test('accents, braces, over and under', () {
    expect(
      body(r'\hat{x}'),
      '<mover accent="true"><mi>x</mi><mo>^</mo></mover>',
    );
    expect(body(r'\overline{AB}'), contains('<mo>¯</mo></mover>'));
    expect(
      body(r'\underbrace{a+b}_{n}'),
      contains('<munder><munder accentunder="true">'),
    );
    expect(body(r'\overset{def}{=}'), contains('<mover><mo>=</mo>'));
  });

  test('environments', () {
    expect(
      body(r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}'),
      '<mrow><mo fence="true" stretchy="true">(</mo><mtable>'
      '<mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr>'
      '<mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable>'
      '<mo fence="true" stretchy="true" form="postfix">)</mo></mrow>',
    );
    expect(
      body(r'\begin{cases} 1 & x > 0 \\ 0 & \text{else} \end{cases}'),
      contains('<mtable columnalign="left left">'),
    );
    expect(
      body(r'\begin{array}{lr} a & b \end{array}'),
      contains('<mtable columnalign="left right">'),
    );
    expect(
      body(r'\begin{aligned} a &= b \\ &= c \end{aligned}'),
      contains('<mstyle displaystyle="true"><mtable columnalign="right left">'),
    );
  });

  test('colors, boxes, negations, spaces', () {
    expect(
      body(r'\color{red} x'),
      '<mstyle mathcolor="red"><mi>x</mi></mstyle>',
    );
    expect(body(r'\textcolor{blue}{y}'), contains('mathcolor="blue"'));
    expect(
      body(r'\boxed{x}'),
      '<menclose notation="box"><mi>x</mi></menclose>',
    );
    expect(body(r'a \not= b'), contains('<mo>≠</mo>'));
    expect(body(r'a\,b'), contains('<mspace width="0.1667em"/>'));
  });

  test('unknown commands are shown and listed', () {
    final unknown = <String>{};
    final mathml = latexToMathml(r'\foo x', unknown: unknown);
    expect(mathml, contains(r'<mtext>\foo</mtext>'));
    expect(unknown, {r'\foo'});
  });

  test('display style', () {
    expect(latexToMathml('x', display: true), contains('display="block"'));
  });
}
