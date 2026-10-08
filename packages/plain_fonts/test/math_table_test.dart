// The OpenType MATH table, read from a subset of Noto Sans Math (its
// values checked against fontTools').
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

void main() {
  final font = OpenTypeFont.parse(
    File('test/fonts/notosansmath-subset.ttf').readAsBytesSync(),
  );
  final table = OpenTypeMathTable.parse(font.table('MATH')!)!;

  group('MATH table', () {
    test('constants', () {
      expect(table[MathConstant.scriptPercentScaleDown], 60);
      expect(table[MathConstant.scriptScriptPercentScaleDown], 50);
      expect(table[MathConstant.displayOperatorMinHeight], 2300);
      expect(table[MathConstant.axisHeight], 278);
      expect(table[MathConstant.fractionRuleThickness], 71);
      expect(table[MathConstant.superscriptShiftUp], 390);
      expect(table[MathConstant.subscriptShiftDown], 210);
      expect(table[MathConstant.radicalKernAfterDegree], -450);
      expect(table[MathConstant.radicalDegreeBottomRaisePercent], 56);
    });

    test('variants and assemblies, italic corrections', () {
      final paren = table.vertical(font.glyphFor(0x28))!;
      expect(paren.variants.first.advance, 942);
      expect(
        paren.variants.map((v) => v.advance),
        orderedEquals([...paren.variants.map((v) => v.advance)]..sort()),
      );
      expect(paren.parts, hasLength(3));
      expect(paren.parts.where((p) => p.extender), hasLength(1));
      expect(table.minConnectorOverlap, 100);
      // Mathematical italic small f.
      expect(table.italicsCorrections[font.glyphFor(0x1d453)], 145);
    });
  });
}
