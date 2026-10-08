// OpenType fonts as typesetting sees them: metrics in 1000ths of the em,
// and shaping (single substitutions of features, ligatures, kerning by
// GPOS or by one kern subtable).
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

OpenTypeShaper _font(String name, {int? kernTableSubtable}) => OpenTypeShaper(
  OpenTypeFont.parse(File('test/fonts/$name').readAsBytesSync()),
  kernTableSubtable: kernTableSubtable,
);

void main() {
  test("metrics in 1000ths of the em, from the font's tables", () {
    final font = _font('notoserif-regular-latin.ttf');
    final unit = 1000 / font.font.unitsPerEm;
    expect(font.name, font.font.postScriptName);
    expect(font.ascender, font.font.ascender * unit);
    expect(font.descender, font.font.descender * unit);
    expect(font.descender, isNegative);
    expect(font.capHeight, greaterThan(font.xHeight));
    // The underline's center: post's top less half its thickness.
    expect(
      font.underlinePosition,
      closeTo(
        font.font.underlinePosition! * unit - font.underlineThickness / 2,
        1e-9,
      ),
    );
    expect(font.covers(0x41), isTrue);
    expect(font.covers(0x3093), isFalse);
  });

  test('widths: advances and kerning at a size', () {
    final font = _font('notoserif-regular-latin.ttf');
    final glyphs = font.shape('AV');
    final kerned = glyphs[0].advance + glyphs[0].kerning + glyphs[1].advance;
    expect(font.widthOf('AV', 10), closeTo(kerned / 100, 1e-9));
    expect(
      font.widthOf('AV', 10, kerning: false),
      closeTo((glyphs[0].advance + glyphs[1].advance) / 100, 1e-9),
    );
    expect(glyphs[0].kerning, isNegative);
  });

  test('text kerned by one kern subtable alone', () {
    final first = _font('notoserif-kern-subtables.ttf', kernTableSubtable: 0);
    final second = _font('notoserif-kern-subtables.ttf', kernTableSubtable: 1);
    double kerning(OpenTypeShaper font, String text) =>
        font.shape(text).first.kerning;
    final unit = 1000 / first.font.unitsPerEm;
    // (Without a subtable, the font's GPOS pairs kern instead.)
    expect(kerning(first, 'AV'), closeTo(-80 * unit, 1e-6));
    expect(kerning(first, 'To'), 0);
    expect(kerning(second, 'AV'), closeTo(-40 * unit, 1e-6));
    expect(kerning(second, 'To'), closeTo(-60 * unit, 1e-6));
  });

  test('OpenType features substitute glyphs: old-style numerals, '
      'small capitals', () {
    final font = _font('notoserif-features.ttf');
    expect(font.font.hasFeature('onum'), isTrue);
    expect(font.font.hasFeature('zero'), isFalse);
    List<int> ids(String text, [Set<String> features = const {}]) => [
      for (final glyph in font.shape(text, features: features)) glyph.id,
    ];
    final lining = ids('2026');
    final oldstyle = ids('2026', {'onum'});
    expect(oldstyle, hasLength(4));
    expect(oldstyle, isNot(lining));
    final small = ids('Abc', {'smcp'});
    // The capital stays; the lowercase letters become small capitals.
    expect(small.first, ids('A').single);
    expect(small.sublist(1), isNot(ids('bc')));
    // The text they stand for is unchanged.
    expect(
      font.shape('2026', features: {'onum'}).map((g) => g.text).join(),
      '2026',
    );
  });

  test('small capitals by multiple substitutions of one glyph', () {
    // Libertinus's smcp is a GSUB type 2 lookup.
    final font = _font('libertinus-smcp.otf');
    List<int> ids(String text, [Set<String> features = const {}]) => [
      for (final glyph in font.shape(text, features: features)) glyph.id,
    ];
    final small = ids('Abc', {'smcp'});
    expect(small, hasLength(3));
    expect(small.sublist(1), isNot(ids('bc')));
  });

  test('ligatures replace their sequence, and stand for its text', () {
    final font = _font('notoserif-features.ttf');
    final shaped = font.shape('office', ligatures: true);
    expect(shaped.map((g) => g.text).join(), 'office');
    expect(shaped.map((g) => g.text), contains('ffi'));
    expect(font.shape('office'), hasLength(6));
  });

  test('a character without a glyph is .notdef', () {
    final font = _font('notoserif-regular-latin.ttf');
    expect(font.shape('xん').last.id, 0);
  });
}
