// The math layout: plain_math trees set by the rules of the OpenType
// MATH table, with a subset of Noto Sans Math.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_math/plain_math.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

void main() {
  final font = OpenTypeShaper(
    OpenTypeFont.parse(
      File('test/fonts/notosansmath-subset.ttf').readAsBytesSync(),
    ),
  );
  final layout = MathLayout(font);
  MathBox box(String mathml, {bool display = false}) =>
      layout.layout(parseMathML(mathml), size: 10, display: display);
  String math(String inner) =>
      '<math xmlns="http://www.w3.org/1998/Math/MathML">$inner</math>';

  group('layout', () {
    test('a superscript is raised, a subscript lowered', () {
      final base = box(math('<mi>x</mi>'));
      final sup = box(math('<msup><mi>x</mi><mn>2</mn></msup>'));
      final sub = box(math('<msub><mi>x</mi><mn>2</mn></msub>'));
      expect(sup.width, greaterThan(base.width));
      // At least SuperscriptShiftUp (3.9 points at 10) over the baseline.
      expect(sup.height, greaterThan(3.9));
      expect(sub.depth, greaterThanOrEqualTo(2.1));
      expect(sub.height, closeTo(base.height, 0.01));
    });

    test('a fraction about the math axis', () {
      final frac = box(math('<mfrac><mi>a</mi><mi>b</mi></mfrac>'));
      final display = box(
        math('<mfrac><mi>a</mi><mi>b</mi></mfrac>'),
        display: true,
      );
      expect(frac.height, greaterThan(2.78));
      expect(frac.depth, greaterThan(0));
      // Display style: larger shifts, full-size parts.
      expect(
        display.height + display.depth,
        greaterThan(frac.height + frac.depth),
      );
    });

    test('a radical over its radicand, an index before it', () {
      final x = box(math('<mi>x</mi>'));
      final root = box(math('<msqrt><mi>x</mi></msqrt>'));
      final cube = box(math('<mroot><mi>x</mi><mn>3</mn></mroot>'));
      expect(root.height, greaterThan(x.height));
      expect(root.width, greaterThan(x.width));
      // The index over the sign's left (its kern after the degree is
      // negative), the root no narrower.
      expect(cube.width, greaterThanOrEqualTo(root.width));
      expect(cube.height, greaterThanOrEqualTo(root.height));
    });

    test('delimiters stretch to what they enclose', () {
      final plain = box(math('<mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow>'));
      final tall = box(
        math(
          '<mrow><mo>(</mo><mtable>'
          '<mtr><mtd><mi>a</mi></mtd></mtr>'
          '<mtr><mtd><mi>b</mi></mtd></mtr>'
          '<mtr><mtd><mi>c</mi></mtd></mtr>'
          '</mtable><mo>)</mo></mrow>',
        ),
      );
      expect(
        tall.height + tall.depth,
        greaterThan(2 * (plain.height + plain.depth)),
      );
    });

    test('a large operator is larger in display style, with limits', () {
      const sum =
          '<munderover><mo>\u2211</mo><mi>i</mi><mi>n</mi></munderover>';
      final inline = box(math(sum));
      final display = box(math(sum), display: true);
      // DisplayOperatorMinHeight: 2.3 em at least.
      expect(display.height + display.depth, greaterThan(23));
      expect(
        display.height + display.depth,
        greaterThan(inline.height + inline.depth),
      );
      // Inline, the limits are scripts: beside, so wider than the sign.
      final sign = box(math('<mo>\u2211</mo>'));
      expect(inline.width, greaterThan(sign.width));
    });

    test('an accent over its base', () {
      final v = box(math('<mi>v</mi>'));
      final vec = box(
        math('<mover accent="true"><mi>v</mi><mo>\u2192</mo></mover>'),
      );
      expect(vec.height, greaterThan(v.height + 1));
    });

    test('spacing: thick around relations, none in scripts', () {
      final rel = box(math('<mi>a</mi><mo>=</mo><mi>b</mi>'));
      final tight = box(
        math(
          '<msup><mi>x</mi><mrow><mi>a</mi><mo>=</mo><mi>b</mi></mrow>'
          '</msup>',
        ),
      );
      final a = box(math('<mi>a</mi>'));
      final b = box(math('<mi>b</mi>'));
      final equals = box(math('<mo>=</mo>'));
      // Two thick spaces (5/18 em each).
      expect(
        rel.width,
        closeTo(a.width + equals.width + b.width + 2 * 5 / 18 * 10, 0.01),
      );
      expect(tight.width, lessThan(rel.width));
    });

    test("drawn: identifiers in math italic, in the font's glyphs", () {
      final page = RecordingPage(const Rect(0, 0, 200, 100));
      box(math('<mi>x</mi><mo>+</mo><mn>1</mn>')).paintAt(page.canvas, 10, 50);
      expect(page.texts.join(), '\u{1d465}+1');
      expect(
        page.canvas.calls.where((c) => c.startsWith('glyphs')),
        everyElement(contains('NotoSansMath-Regular')),
      );
    });
  });
}
