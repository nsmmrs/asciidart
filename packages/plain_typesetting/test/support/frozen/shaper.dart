// A frozen copy of OpenTypeShaper as of 17001e86 (before shaped texts
// were cached): the oracle the shaping equivalence test compares every
// glyph with. Don't change it.
// ignore_for_file: type=lint
import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

final class FrozenShaper {
  /// A shaper for [font].
  new(this.font, {this.kernTableSubtable});

  final OpenTypeFont font;

  /// The `kern` subtable text is kerned by alone, if any.
  final int? kernTableSubtable;

  int _kerning(int left, int right) =>
      _kerns[(left << 16) | right] ??= switch (kernTableSubtable) {
        final subtable? =>
          font.kernTablePair(left, right, subtable: subtable) ?? 0,
        null => font.kerning(left, right),
      };

  /// The kerning of the pairs looked up, by `left << 16 | right`.
  final Map<int, int> _kerns = {};

  String get name => font.postScriptName;

  double widthOf(String text, double size, {bool kerning = true}) {
    var width = 0.0;
    for (final glyph in shape(text, kerning: kerning)) {
      width += glyph.advance + glyph.kerning;
    }
    return width * size / 1000;
  }

  /// [units] of the font's em in 1000ths of the em.
  double scale(num units) => units * 1000 / font.unitsPerEm;

  /// The ascender.
  double get ascender => scale(font.ascender);

  /// The descender (negative).
  double get descender => scale(font.descender);

  /// The line gap.
  double get lineGap => scale(font.lineGap);

  /// The height of capital letters (the ascender if the font doesn't say).
  double get capHeight => scale(font.capHeight ?? font.ascender);

  /// The height of lowercase letters (half the ascender if the font
  /// doesn't say).
  double get xHeight => scale(font.xHeight ?? (font.ascender ~/ 2));

  /// The position of the underline's center (`post` gives its top).
  double get underlinePosition =>
      scale(font.underlinePosition ?? -font.unitsPerEm ~/ 10) -
      underlineThickness / 2;

  /// The underline's thickness.
  double get underlineThickness =>
      scale(font.underlineThickness ?? font.unitsPerEm ~/ 20);

  /// Whether the font has a glyph for [codePoint].
  bool covers(int codePoint) => font.glyphFor(codePoint) != 0;

  /// [text] as glyphs: the features' single substitutions, then the
  /// ligatures (with [ligatures]), then kerning (with [kerning]).
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
  }) {
    final runes = text.runes.toList();
    // The features' single substitutions come first (as `smcp` comes
    // before `liga`): a substituted glyph doesn't ligate.
    final singles = [
      for (final feature in features) font.singleSubstitutions(feature),
    ];
    int glyphOf(int rune) {
      var glyph = font.glyphFor(rune);
      for (final substitutions in singles) {
        glyph = substitutions[glyph] ?? glyph;
      }
      return glyph;
    }

    final ids = <int>[];
    final texts = <String>[];
    var i = 0;
    while (i < runes.length) {
      final glyph = glyphOf(runes[i]);
      var matched = false;
      if (ligatures) {
        for (final (rest, ligature)
            in font.ligatures[glyph] ?? const <(List<int>, int)>[]) {
          if (i + rest.length >= runes.length) continue;
          var all = true;
          for (var k = 0; all && k < rest.length; k++) {
            all = glyphOf(runes[i + 1 + k]) == rest[k];
          }
          if (!all) continue;
          ids.add(ligature);
          texts.add(
            String.fromCharCodes(runes.sublist(i, i + 1 + rest.length)),
          );
          i += 1 + rest.length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        ids.add(glyph);
        texts.add(String.fromCharCode(runes[i]));
        i += 1;
      }
    }
    return [
      for (var k = 0; k < ids.length; k++)
        ShapedGlyph(
          ids[k],
          texts[k],
          scale(font.advance(ids[k])),
          kerning && k + 1 < ids.length
              ? scale(_kerning(ids[k], ids[k + 1]))
              : 0,
        ),
    ];
  }
}
