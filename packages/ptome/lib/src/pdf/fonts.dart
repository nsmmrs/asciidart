/// Fonts: line metrics as Prawn 2.4 gives them (so a theme's line heights
/// set lines as asciidoctor-pdf does), from TrueType's `OS/2` typographic
/// values (else `hhea`) or from AFM files; text shaped with OpenType
/// (GPOS kerning, ligatures); and the font catalog of a theme, with the
/// standard families and the icon fonts.
library;

import 'package:plain_pdf/plain_pdf.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/path_resolver.dart';
import 'package:ptome/src/pdf/theme.dart';

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
  /// As plain_pdf shapes it: kerned by the font's GPOS pairs (or its kern
  /// table).
  opentype,

  /// As plain_pdf shapes it, with the font's standard ligatures (`liga`).
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

  /// The height of capital letters, where lines are set on it (lines set
  /// from their cap heights): the font's `OS/2` cap height, else its
  /// typographic ascender (the PDF's font descriptor keeps its own).
  @override
  double capHeightAt(double size) {
    final font = pdf.font;
    final units = switch (font.capHeight) {
      final cap? when cap > 0 => cap,
      _ => font.typoAscender ?? font.ascender,
    };
    return units / font.unitsPerEm * size;
  }

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
    // and again), in 1000ths of the em; by the text alone for the usual
    // kerning without features.
    final Map<String, double> widths;
    if (features.isEmpty && kerning) {
      widths = _unitWidths;
    } else {
      final names = _featureKeys[features] ??= features.join(',');
      widths = (kerning ? _featureWidths : _unkernedWidths)[names] ??= {};
    }
    final units = widths[text] ??= () {
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

  /// The widths with features, by their names, kerned and not.
  final Map<String, Map<String, double>> _featureWidths = {};
  final Map<String, Map<String, double>> _unkernedWidths = {};

  /// The names of a set of features, joined once for each set.
  static final Expando<String> _featureKeys = Expando();

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

/// The icon font families (prawn-icon's sets): their files' names (the
/// gem's, then the project's own) and the family the font names itself,
/// bold for Font Awesome's solid style.
const Map<String, ({List<String> files, String family, bool bold})> iconFonts =
    {
      'fas': (
        files: ['fa-solid.ttf', 'fa-solid-900.ttf'],
        family: 'Font Awesome 5 Free',
        bold: true,
      ),
      'far': (
        files: ['fa-regular.ttf', 'fa-regular-400.ttf'],
        family: 'Font Awesome 5 Free',
        bold: false,
      ),
      'fab': (
        files: ['fa-brands.ttf', 'fa-brands-400.ttf'],
        family: 'Font Awesome 5 Brands',
        bold: false,
      ),
      'fi': (
        files: ['foundation-icons.ttf'],
        family: 'fontcustom',
        bold: false,
      ),
      'pf': (
        files: ['paymentfont-webfont.ttf'],
        family: 'paymentfont-webfont',
        bold: false,
      ),
    };

/// Families the default themes name whose fonts are published today under
/// another name (M+ 1mn's successor is M PLUS 1 Code).
const Map<String, List<String>> _familyAliases = {
  'm+ 1mn': ['M PLUS 1 Code'],
  'm+ 1p': ['M PLUS 1p'],
  'm+ 1p fallback': ['M+ 1p', 'M PLUS 1p'],
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
  /// list separated by `;` or `,`, `GEM_FONTS_DIR` naming the default
  /// fonts wherever they are installed; by default the theme's directory,
  /// then the installed fonts), text in them shaped by [shaping]. A font
  /// that can't be found is looked up among the [installed] fonts by its
  /// file's name, then by its family; one that isn't installed either is
  /// replaced by a built-in PDF font (Times, Helvetica or Courier), with a
  /// message to [warn].
  new(
    Theme theme, {
    String? fontsDir,
    this.shaping = Shaping.opentype,
    this.synthesizeFaces = false,
    FontIndex? installed,
    void Function(String message)? warn,
  }) : _installed = installed ?? Fonts.current,
       _warn = warn ?? _ignore,
       _catalog = theme.fontCatalog?.families ?? const {},
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
  final FontIndex _installed;
  final void Function(String message) _warn;
  final Set<String> _warned = {};

  static void _ignore(String message) {}
  final Map<(String, String), FontFace> _fonts = {};
  static final Map<String, List<int>> _files = {};

  /// Whether [family] is known (in the catalog, built in, an icon set or
  /// installed).
  bool hasFamily(String family) =>
      _catalog.containsKey(family) ||
      _builtInFamilies.containsKey(family) ||
      iconFonts.containsKey(family) ||
      _installed.hasFamily(family);

  /// Whether the font of icon set [set] (`fas`, `fi`...) is installed.
  bool hasIcons(String set) => _iconFile(set) != null;

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
    if (iconFonts.containsKey(family)) {
      final path =
          _iconFile(family) ??
          (throw FontException('the $family icon font is not installed'));
      return TrueTypeFont(family, 'normal', _parse(path), shaping);
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
      if (_file(path) case final file?) {
        return TrueTypeFont(family, style, _parse(file), shaping);
      }
      return _installedFace(family, style) ??
          _fallback(
            family,
            style,
            path.startsWith('GEM_FONTS_DIR/')
                ? 'font family $family is not installed'
                : '$path not found',
          );
    }
    if (_builtInFamilies[family] case final styles?) {
      final name = styles[style] ?? styles['normal']!;
      return AfmFont(family, style, StandardFont.named(name), shaping);
    }
    return _installedFace(family, style) ??
        _fallback(family, style, 'font family $family is not installed');
  }

  /// The face of [family] in [style] among the installed fonts (by the
  /// family or one of its aliases), made from the nearest style the
  /// family has when the catalog allows it.
  FontFace? _installedFace(String family, String style) {
    final bold = style == 'bold' || style == 'bold_italic';
    final italic = style == 'italic' || style == 'bold_italic';
    for (final name in [family, ...?_familyAliases[family.toLowerCase()]]) {
      final found = _installed.find(name, bold: bold, italic: italic);
      if (found == null) continue;
      final face = TrueTypeFont(
        family,
        found.bold == bold && found.italic == italic ? style : _styleOf(found),
        _parse(found.path, index: found.index),
        shaping,
      );
      if (face.style == style || !synthesizeFaces) return face;
      return TrueTypeFont.synthetic(face, style);
    }
    return null;
  }

  static String _styleOf(InstalledFont font) =>
      switch ((font.bold, font.italic)) {
        (true, true) => 'bold_italic',
        (true, false) => 'bold',
        (false, true) => 'italic',
        (false, false) => 'normal',
      };

  /// A built-in PDF font in place of [family] (Courier for a monospace
  /// family, Times for a serif one, else Helvetica), said once per family
  /// and style.
  FontFace _fallback(String family, String style, String why) {
    final lower = family.toLowerCase();
    final builtIn = RegExp('mono|code|1mn|courier|consol').hasMatch(lower)
        ? 'Courier'
        : RegExp('serif|times').hasMatch(lower) && !lower.contains('sans')
        ? 'Times-Roman'
        : 'Helvetica';
    final styles = _builtInFamilies[builtIn]!;
    final name = styles[style] ?? styles['normal']!;
    if (_warned.add('$family/$style')) {
      _warn(
        '$why: using $name for $family ($style); `ptome doctor` installs '
        "the default themes' fonts",
      );
    }
    return AfmFont(family, style, StandardFont.named(name), shaping);
  }

  /// The installed file of icon set [set], by its names, then its family.
  String? _iconFile(String set) {
    final icons = iconFonts[set];
    if (icons == null) return null;
    for (final name in icons.files) {
      if (_installed.fileNamed(name) case final path?) return path;
    }
    return _installed.find(icons.family, bold: icons.bold)?.path;
  }

  /// The font in the file at [path] ([index] in a collection).
  EmbeddedFont _parse(String path, {int index = 0}) =>
      EmbeddedFont.parse(_bytes(path), index: index);

  /// (Files are read once per process; fonts given as bytes belong to
  /// their conversion.)
  List<int> _bytes(String path) => _installed.isInMemory(path)
      ? _installed.bytes(path)
      : _files[path] ??= _installed.bytes(path);

  /// The file a catalog [path] names: in the font folders given (the
  /// theme's), else installed under the same name; null when there is
  /// none. `GEM_FONTS_DIR/` names the default fonts, wherever installed.
  String? _file(String path) {
    final gem = path.startsWith('GEM_FONTS_DIR/');
    final name = _baseName(gem ? path.substring(14) : path);
    if (!gem) {
      for (final dir in _dirs) {
        if (dir == 'GEM_FONTS_DIR') continue;
        final resolved = PathResolver().systemPath(path, start: dir);
        if (io.isFile(resolved)) return resolved;
      }
    }
    return _installed.fileNamed(name);
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
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
