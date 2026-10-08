// The MathML tree: the elements read, with or without a namespace
// prefix, styles, tables and enclosures.
import 'package:plain_math/plain_math.dart';
import 'package:test/test.dart';

void main() {
  String math(String inner) =>
      '<math xmlns="http://www.w3.org/1998/Math/MathML">$inner</math>';

  group('MathML', () {
    test('elements, with or without a prefix', () {
      final node = parseMathML(
        '<mml:math><mml:msubsup><mml:mi>a</mml:mi><mml:mn>1</mml:mn>'
        '<mml:mn>2</mml:mn></mml:msubsup></mml:math>',
      );
      expect(node, isA<MathScripts>());
      final scripts = node as MathScripts;
      expect((scripts.base as MathToken).text, 'a');
      expect((scripts.sub! as MathToken).kind, MathTokenKind.number);
      expect((scripts.sup! as MathToken).text, '2');
    });

    test('styles, tables and enclosures', () {
      final styled = parseMathML(
        math(
          '<mstyle mathcolor="#ff0000" mathvariant="bold"> <mi>x</mi> '
          '</mstyle>',
        ),
      );
      expect(styled, isA<MathStyled>());
      // The tree keeps the attribute; the layout reads it as a color.
      expect((styled as MathStyled).color, '#ff0000');
      expect(styled.variant, 'bold');
      final table = parseMathML(
        math(
          '<mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr>'
          '<mtr><mtd><mi>c</mi></mtd></mtr></mtable>',
        ),
      );
      expect((table as MathTable).rows.map((r) => r.length), [2, 1]);
      final enclose = parseMathML(
        math(
          '<menclose notation="box updiagonalstrike"> <mi>x</mi> '
          '</menclose>',
        ),
      );
      expect((enclose as MathEnclose).notations, ['box', 'updiagonalstrike']);
    });

    test('not MathML', () {
      expect(() => parseMathML('<math>'), throwsA(isA<MathMLException>()));
    });
  });
}
