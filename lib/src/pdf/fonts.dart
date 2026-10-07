/// Fonts: line metrics as Prawn 2.4 gives them (so a theme's line heights
/// set lines as asciidoctor-pdf does), from TrueType's `OS/2` typographic
/// values (else `hhea`) or from AFM files; text shaped with OpenType
/// (GPOS kerning, ligatures); and the font catalog of a theme, with the
/// standard families and the icon fonts.
library;

import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/path_resolver.dart';
import 'package:asciidart/src/pdf/assets.g.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:libpdf/libpdf.dart';

/// A font face with Prawn's line metrics; [pdf] draws it.
sealed class FontFace {
  const new _(this.family, this.style);

  /// The family name (as the theme names it).
  final String family;

  /// The style: `normal`, `bold`, `italic` or `bold_italic`.
  final String style;

  /// The font that draws the text.
  PdfFont get pdf;

  /// [text] as the font can draw it (the same, but for a built-in font).
  String normalize(String text) => text;

  /// The ascender, in 1000ths of the em.
  num get ascender;

  /// The descender (negative), in 1000ths of the em.
  num get descender;

  /// The line gap, in 1000ths of the em.
  num get lineGap;

  /// The ascender at [size] points.
  double ascenderAt(double size) => ascender / 1000 * size;

  /// The descender at [size] points, as Prawn gives it (positive).
  double descenderAt(double size) => -descender / 1000 * size;

  /// The line gap at [size] points.
  double lineGapAt(double size) => lineGap / 1000 * size;

  /// The height of capital letters at [size] points.
  double capHeightAt(double size) => pdf.capHeight / 1000 * size;

  /// The line height at [size] points: ascender, descender and line gap.
  double heightAt(double size) =>
      (ascender - descender + lineGap) / 1000 * size;

  /// The width of [text] at [size] points, with the OpenType [features]
  /// (an embedded font's that it has).
  double widthOf(
    String text,
    double size, {
    bool kerning = true,
    Set<String> features = const {},
  });

  /// Whether the font has a glyph for [codePoint].
  bool hasGlyph(int codePoint);

  /// Whether the font's characters are all as wide (it isn't ligated).
  bool get fixedPitch;

  /// How text in the font becomes glyphs.
  Shaping get shaping;

  /// Whether text in the font is ligated (never in a fixed-pitch font).
  bool get ligates => shaping.ligates && !fixedPitch;

  /// Whether the face is slanted when drawn (an italic made from an
  /// upright face the family has).
  bool get slanted => false;

  /// Whether the face is stroked when drawn (a bold made from a regular
  /// face the family has).
  bool get emboldened => false;
}

/// How text becomes glyphs, for measuring and drawing it.
enum Shaping {
  /// As libpdf shapes it: kerned by the font's GPOS pairs (or its kern
  /// table).
  opentype,

  /// As libpdf shapes it, with the font's standard ligatures (`liga`).
  ligatures;

  /// Whether the font's standard ligatures are used.
  bool get ligates => this == ligatures;
}

/// A TrueType (or OpenType) font.
final class TrueTypeFont extends FontFace {
  /// The font of [pdf] in [family] and [style].
  new(super.family, super.style, this.pdf, [this.shaping = Shaping.opentype])
    : slanted = false,
      emboldened = false,
      super._() {
    _metrics();
  }

  /// [style] made from [base], a face of the same family: slanted for an
  /// italic, stroked for a bold.
  new synthetic(TrueTypeFont base, String style)
    : pdf = base.pdf,
      shaping = base.shaping,
      slanted = style.contains('italic') && !base.style.contains('italic'),
      emboldened = style.contains('bold') && !base.style.contains('bold'),
      super._(base.family, style) {
    _metrics();
  }

  @override
  final bool slanted;

  @override
  final bool emboldened;

  void _metrics() {
    final font = pdf.font;
    _scale = 1000 / font.unitsPerEm;
    int pick(int? typo, int hhea) => typo != null && typo != 0 ? typo : hhea;
    ascender = (pick(font.typoAscender, font.ascender) * _scale).truncate();
    descender = (pick(font.typoDescender, font.descender) * _scale).truncate();
    lineGap = (pick(font.typoLineGap, font.lineGap) * _scale).truncate();
  }

  @override
  final EmbeddedFont pdf;

  @override
  final Shaping shaping;

  late final double _scale;

  @override
  late final int ascender;

  @override
  late final int descender;

  @override
  late final int lineGap;

  final Map<int, int> _widths = {};

  /// The width of [codePoint]'s glyph, in 1000ths of the em (truncated,
  /// as Prawn keeps it); NUL and line feeds are 0 wide.
  int widthOfCode(int codePoint) {
    if (codePoint == 0 || codePoint == 10) return 0;
    return _widths[codePoint] ??=
        (pdf.font.advance(pdf.font.glyphFor(codePoint)) * _scale).truncate();
  }

  @override
  double widthOf(
    String text,
    double size, {
    bool kerning = true,
    Set<String> features = const {},
  }) {
    // Shaped once per text (line breaking measures the same words again
    // and again), in 1000ths of the em.
    final key = features.isEmpty
        ? (kerning ? text : '\u0000$text')
        : '${kerning ? '' : '\u0000'}${features.join(',')}\u0001$text';
    final units = _unitWidths[key] ??= () {
      var width = 0.0;
      final glyphs = pdf.shape(
        text,
        kerning: kerning,
        ligatures: ligates,
        features: features,
      );
      for (final (i, glyph) in glyphs.indexed) {
        width += glyph.advance;
        if (i < glyphs.length - 1) width += glyph.kerning;
      }
      return width;
    }();
    return units * size / 1000;
  }

  final Map<String, double> _unitWidths = {};

  @override
  bool hasGlyph(int codePoint) => pdf.font.glyphFor(codePoint) > 0;

  @override
  bool get fixedPitch => pdf.font.isFixedPitch;
}

/// One of the 14 standard fonts, from its AFM file.
final class AfmFont extends FontFace {
  /// The standard font [pdf] in [family] and [style].
  new(super.family, super.style, this.pdf, [this.shaping = Shaping.opentype])
    : super._();

  @override
  final StandardFont pdf;

  @override
  final Shaping shaping;

  @override
  double get ascender => pdf.ascender;

  @override
  double get descender => pdf.descender;

  @override
  double get lineGap {
    final box = pdf.boundingBox;
    return (box[3] - box[1]) - (ascender - descender);
  }

  @override
  double widthOf(
    String text,
    double size, {
    bool kerning = true,
    Set<String> features = const {},
  }) => pdf.widthOf(text, size, kerning: kerning);

  @override
  bool hasGlyph(int codePoint) => pdf.covers(codePoint);

  @override
  bool get fixedPitch => pdf.name.startsWith('Courier');

  /// The characters Windows-1252 lacks that become others.
  static const Map<int, String> _fallbackChars = {
    0x200b: '',
    0x202f: '\u00a0',
    0x2009: ' ',
    0x2063: '\u00ad',
    0x25e6: '-',
    0x25aa: '\u00b7',
  };

  /// [text] in the characters of Windows-1252: some others replaced by
  /// look-alikes, and when any other is left, each character Windows-1252
  /// lacks replaced by `¬` (asciidoctor-pdf's AFM font
  /// `normalize_encoding`).
  @override
  String normalize(String text) {
    if (pdf.name == 'Symbol' || pdf.name == 'ZapfDingbats') return text;
    final out = StringBuffer();
    for (final rune in text.runes) {
      if (rune < 0x80 || pdf.covers(rune)) {
        out.writeCharCode(rune);
      } else if (_fallbackChars[rune] case final replacement?) {
        out.write(replacement);
      } else {
        return String.fromCharCodes([
          for (final rune in text.runes)
            if (rune < 0x80 || pdf.covers(rune)) rune else 0xac,
        ]);
      }
    }
    return out.toString();
  }
}

/// Prawn's built-in families, by style.
const Map<String, Map<String, String>> _builtInFamilies = {
  'Courier': {
    'normal': 'Courier',
    'bold': 'Courier-Bold',
    'italic': 'Courier-Oblique',
    'bold_italic': 'Courier-BoldOblique',
  },
  'Times-Roman': {
    'normal': 'Times-Roman',
    'bold': 'Times-Bold',
    'italic': 'Times-Italic',
    'bold_italic': 'Times-BoldItalic',
  },
  'Helvetica': {
    'normal': 'Helvetica',
    'bold': 'Helvetica-Bold',
    'italic': 'Helvetica-Oblique',
    'bold_italic': 'Helvetica-BoldOblique',
  },
  'Symbol': {'normal': 'Symbol'},
  'ZapfDingbats': {'normal': 'ZapfDingbats'},
};

/// The icon font families (prawn-icon's sets) and their files.
const Map<String, String> iconFontFiles = {
  'fas': 'icons/fas/fa-solid.ttf',
  'far': 'icons/far/fa-regular.ttf',
  'fab': 'icons/fab/fa-brands.ttf',
  'fi': 'icons/fi/foundation-icons.ttf',
  'pf': 'icons/pf/paymentfont-webfont.ttf',
};

/// A font file that couldn't be found or read.
final class FontException implements Exception {
  /// An exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// The fonts of one conversion: the theme's catalog, Prawn's built-in
/// families and the icon fonts, loaded (and subset) once each.
final class FontCatalog {
  /// The catalog of [theme], its font files looked up in [fontsDir] (a
  /// list separated by `;` or `,`, `GEM_FONTS_DIR` naming the bundled
  /// fonts; by default the theme's directory, then the bundled fonts),
  /// text in them shaped by [shaping].
  new(
    Theme theme, {
    String? fontsDir,
    this.shaping = Shaping.opentype,
    this.synthesizeFaces = false,
  }) : _catalog = theme.fontCatalog?.families ?? const {},
       _dirs = [
         for (final dir
             in (fontsDir ??
                     (theme.directory == null
                         ? 'GEM_FONTS_DIR'
                         : '${theme.directory};GEM_FONTS_DIR'))
                 .split(RegExp('[;,]')))
           if (dir.isEmpty) 'GEM_FONTS_DIR' else dir,
       ];

  /// How text in the fonts becomes glyphs.
  final Shaping shaping;

  /// Whether a style the catalog lacks for a family is made from one it
  /// has (an italic slanted, a bold stroked), rather than an error.
  final bool synthesizeFaces;

  final Map<String, Map<String, String>> _catalog;
  final List<String> _dirs;
  final Map<(String, String), FontFace> _fonts = {};
  static final Map<String, List<int>> _files = {};

  /// Whether [family] is known.
  bool hasFamily(String family) =>
      _catalog.containsKey(family) ||
      _builtInFamilies.containsKey(family) ||
      iconFontFiles.containsKey(family);

  /// The font of [family] in [style]; throws [FontException] for a family
  /// or style the catalog lacks.
  FontFace font(String family, [String style = 'normal']) =>
      _fonts[(family, style)] ??= _load(family, style);

  /// The font SVG text of [family] (a name, any case, or a generic
  /// family) gets, in the style nearest to [bold] and [italic]; null when
  /// the catalog has no such family (prawn-svg's font registry).
  PdfFont? svgFont(String family, {required bool bold, required bool italic}) {
    String? named(String name) {
      final lower = name.toLowerCase();
      for (final key in [..._catalog.keys, ..._builtInFamilies.keys]) {
        if (key.toLowerCase() == lower) return key;
      }
      return null;
    }

    final name = family.replaceAll(RegExp(r'\s{2,}'), ' ');
    final found =
        named(name) ??
        switch (name.toLowerCase()) {
          'serif' || 'cursive' || 'fantasy' => 'Times-Roman',
          'sans-serif' => 'Helvetica',
          'monospace' => 'Courier',
          _ => null,
        };
    if (found == null) return null;
    final styles = (_catalog[found] ?? _builtInFamilies[found])!;
    final wanted = bold && italic
        ? 'bold_italic'
        : bold
        ? 'bold'
        : italic
        ? 'italic'
        : 'normal';
    final style = styles.containsKey(wanted)
        ? wanted
        : styles.containsKey('normal')
        ? 'normal'
        : styles.keys.first;
    try {
      return font(found, style).pdf;
    } on FontException {
      return null;
    }
  }

  /// Every font loaded, to write them into the document.
  Iterable<FontFace> get loaded => _fonts.values;

  FontFace _load(String family, String style) {
    if (iconFontFiles[family] case final path?) {
      return TrueTypeFont(family, 'normal', _embedded(_bundled(path)), shaping);
    }
    if (_catalog[family] case final styles?) {
      final path = styles[style];
      if (path == null && synthesizeFaces && styles.isNotEmpty) {
        // The nearest face the family has: of a bold italic, the bold,
        // then the italic; else the normal one.
        final base = [
          if (style == 'bold_italic') ...['bold', 'italic'],
          'normal',
          ...styles.keys,
        ].firstWhere(styles.containsKey);
        if (font(family, base) case final TrueTypeFont face) {
          return TrueTypeFont.synthetic(face, style);
        }
      }
      if (path == null) {
        throw FontException(
          'font style $style not found for font family $family',
        );
      }
      return TrueTypeFont(family, style, _embedded(_file(path)), shaping);
    }
    if (_builtInFamilies[family] case final styles?) {
      final name = styles[style] ?? styles['normal']!;
      return AfmFont(family, style, StandardFont.named(name), shaping);
    }
    throw FontException('font family $family not found');
  }

  /// The font in [bytes].
  EmbeddedFont _embedded(List<int> bytes) => EmbeddedFont.parse(bytes);

  List<int> _bundled(String path) => _files[path] ??=
      PdfAssets.bytes(path) ?? (throw FontException('$path not found'));

  List<int> _file(String path) {
    if (path.startsWith('GEM_FONTS_DIR/')) {
      return _bundled('data/fonts/${path.substring(14)}');
    }
    for (final dir in _dirs) {
      if (dir == 'GEM_FONTS_DIR') {
        final bundled = PdfAssets.bytes('data/fonts/$path');
        if (bundled != null) return _files[path] ??= bundled;
        continue;
      }
      final resolved = PathResolver().systemPath(path, start: dir);
      if (io.isFile(resolved)) {
        return _files[resolved] ??= io.readBytes(resolved);
      }
    }
    throw FontException(
      PathResolver().isAbsolutePath(path)
          ? '$path not found'
          : '$path not found in ${_dirs.join(' or ')}',
    );
  }
}

/// [size] (points, or relative: `1.2em`, `80%`, `1.5rem`) in points, for
/// a current size of [current] and a root size of [root].
double resolveFontSize(String size, double current, double root) {
  final number =
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)').stringMatch(size) ?? '',
      ) ??
      0;
  if (size.endsWith('rem')) return root * number;
  if (size.endsWith('em')) return current * number;
  if (size.endsWith('%')) return current * number / 100;
  return number;
}
