/// Fonts as typesetting sees them: metrics, coverage and shaping, in
/// 1000ths of the em. A backend's fonts implement [Font] (plain_pdf's
/// standard and embedded fonts); [OpenTypeShaper] shapes text with an
/// OpenType font's cmap, single substitutions, ligatures and kerning.
library;

import 'package:plain_fonts/plain_fonts.dart';

/// A glyph of shaped text: what to draw and how far it moves.
final class ShapedGlyph {
  /// A glyph [id] standing for [text], advancing [advance] plus [kerning]
  /// (in 1000ths of the em).
  const new(this.id, this.text, this.advance, [this.kerning = 0]);

  /// The glyph: its id in an embedded font, its code in a standard font.
  final int id;

  /// The characters the glyph stands for (several for a ligature).
  final String text;

  /// The glyph's advance width, in 1000ths of the em.
  final double advance;

  /// The kerning before the next glyph, in 1000ths of the em (negative
  /// brings it closer).
  final double kerning;
}

/// A font text can be set in.
abstract interface class Font {
  /// The PostScript name.
  String get name;

  /// The ascender, in 1000ths of the em.
  double get ascender;

  /// The descender (negative), in 1000ths of the em.
  double get descender;

  /// The line gap, in 1000ths of the em.
  double get lineGap;

  /// The height of capital letters, in 1000ths of the em.
  double get capHeight;

  /// The height of lowercase letters, in 1000ths of the em.
  double get xHeight;

  /// The position of the underline's center, in 1000ths of the em
  /// (negative: below the baseline).
  double get underlinePosition;

  /// The underline's thickness, in 1000ths of the em.
  double get underlineThickness;

  /// Whether the font has a glyph for [codePoint].
  bool covers(int codePoint);

  /// [text] as glyphs, with kerning (and ligatures, where the font has
  /// them) when asked, and the single substitutions of the OpenType
  /// [features] the font has (`onum`, `smcp`...).
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
  });

  /// The width of [text] at [size] points.
  double widthOf(String text, double size, {bool kerning = true});
}

/// A [Font] whose glyphs are an OpenType font's: its glyph ids are the
/// font's (math layout reads the font's MATH table and draws its glyphs).
abstract interface class OpenTypeTextFont implements Font {
  /// The font program.
  OpenTypeFont get font;
}

/// An OpenType [font] as a [Font]: its metrics in 1000ths of the em, and
/// text shaped with each character's glyph from the cmap, the single
/// substitutions of the features asked for, the ligatures (`liga`), and
/// kerning by the GPOS pair adjustments, else the `kern` table, or by the
/// `kern` table's subtable [kernTableSubtable] alone.
///
/// A layout can set text in it as it is; a backend's fonts delegate to it
/// (plain_pdf's embedded fonts, which also subset and embed the font).
final class OpenTypeShaper implements OpenTypeTextFont {
  /// A shaper for [font].
  new(this.font, {this.kernTableSubtable});

  @override
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

  @override
  String get name => font.postScriptName;

  @override
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
  @override
  double get ascender => scale(font.ascender);

  /// The descender (negative).
  @override
  double get descender => scale(font.descender);

  /// The line gap.
  @override
  double get lineGap => scale(font.lineGap);

  /// The height of capital letters (the ascender if the font doesn't say).
  @override
  double get capHeight => scale(font.capHeight ?? font.ascender);

  /// The height of lowercase letters (half the ascender if the font
  /// doesn't say).
  @override
  double get xHeight => scale(font.xHeight ?? (font.ascender ~/ 2));

  /// The position of the underline's center (`post` gives its top).
  @override
  double get underlinePosition =>
      scale(font.underlinePosition ?? -font.unitsPerEm ~/ 10) -
      underlineThickness / 2;

  /// The underline's thickness.
  @override
  double get underlineThickness =>
      scale(font.underlineThickness ?? font.unitsPerEm ~/ 20);

  /// Whether the font has a glyph for [codePoint].
  @override
  bool covers(int codePoint) => font.glyphFor(codePoint) != 0;

  /// [text] as glyphs: the features' single substitutions, then the
  /// ligatures (with [ligatures]), then kerning (with [kerning]).
  @override
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
