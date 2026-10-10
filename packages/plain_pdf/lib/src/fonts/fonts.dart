/// Fonts for PDF text: the 14 standard fonts (metrics only, never
/// embedded) and embedded TrueType/OpenType fonts (subset to the glyphs
/// used, as Type0 fonts with Identity-H and a ToUnicode map, or as simple
/// TrueType fonts of up to 256 glyphs each).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_pdf/src/fonts/encoding.dart';
import 'package:plain_pdf/src/fonts/standard_metrics.dart';
import 'package:plain_pdf/src/fonts/standard_metrics.g.dart';
import 'package:plain_pdf/src/objects.dart';
import 'package:plain_pdf/src/writer.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// A font of a PDF: a standard font or an embedded one, which the PDF
/// canvas sets text in.
sealed class PdfFont implements Font {
  new _();

  @override
  double widthOf(String text, double size, {bool kerning = true}) {
    var width = 0.0;
    for (final glyph in shape(text, kerning: kerning)) {
      width += glyph.advance + glyph.kerning;
    }
    return width * size / 1000;
  }

  /// The bytes that show [glyphs] in a content stream (`Tj`), recording
  /// them as used.
  List<int> encode(List<ShapedGlyph> glyphs);

  /// The reference the font is written under, reserved from [writer].
  PdfRef reference(PdfWriter writer) =>
      _references[writer] ??= writer.reserve();

  final Expando<PdfRef> _references = Expando<PdfRef>();

  /// Writes the font's objects to [writer] (after all text is encoded).
  void writeTo(PdfWriter writer);
}

/// One of the 14 standard fonts, which every PDF reader provides.
final class StandardFont extends PdfFont {
  new _(this._data) : super._();

  /// The standard font [name] (`Helvetica`, `Times-Bold`...).
  factory named(String name) => _cache[name] ??= StandardFont._(
    standardFontData[name] ??
        (throw ArgumentError.value(name, 'name', 'is not a standard font')),
  );

  static final Map<String, StandardFont> _cache = {};

  /// Helvetica.
  static final StandardFont helvetica = StandardFont.named('Helvetica');

  /// Times-Roman.
  static final StandardFont timesRoman = StandardFont.named('Times-Roman');

  /// Courier.
  static final StandardFont courier = StandardFont.named('Courier');

  final StandardFontData _data;

  @override
  String get name => _data.name;

  @override
  double get ascender => _data.ascender.toDouble();

  @override
  double get descender => _data.descender.toDouble();

  @override
  double get lineGap => 0;

  /// The font bounding box from the AFM file, in 1000ths of the em:
  /// `[left, bottom, right, top]`.
  List<int> get boundingBox => List.unmodifiable(_data.bbox);

  @override
  double get capHeight => _data.capHeight.toDouble();

  @override
  double get xHeight => _data.xHeight.toDouble();

  @override
  double get underlinePosition => _data.underlinePosition.toDouble();

  @override
  double get underlineThickness => _data.underlineThickness.toDouble();

  late final _StandardGlyphs _glyphs = _StandardGlyphs.parse(_data);

  int? _code(int codePoint) => _data.symbolic
      ? _glyphs.codeForUnicode[codePoint]
      : winAnsiCode(codePoint);

  @override
  bool covers(int codePoint) {
    final code = _code(codePoint);
    return code != null &&
        _glyphs.widthForCode(code, symbolic: _data.symbolic) != null;
  }

  /// The width of each code (0–255), or null for a code without a glyph.
  late final List<double?> _widths = [
    for (var code = 0; code < 256; code++)
      _glyphs.widthForCode(code, symbolic: _data.symbolic)?.toDouble(),
  ];

  /// The kerning between two codes, by `left << 8 | right`.
  late final Map<int, double> _kerns = () {
    final codesOf = <String, List<int>>{};
    for (var code = 0; code < 256; code++) {
      if (_glyphs.nameForCode(code, symbolic: _data.symbolic)
          case final name?) {
        (codesOf[name] ??= []).add(code);
      }
    }
    final kerns = <int, double>{};
    for (final MapEntry(key: pair, :value) in _glyphs.kerning.entries) {
      final [left, right] = pair.split(' ');
      for (final a in codesOf[left] ?? const <int>[]) {
        for (final b in codesOf[right] ?? const <int>[]) {
          kerns[a << 8 | b] = value.toDouble();
        }
      }
    }
    return kerns;
  }();

  /// [_kerns] as a table by `left << 8 | right`, NaN for no pair (the
  /// values are whole numbers, exact in single precision).
  late final Float32List _kernTable = () {
    final table = Float32List(0x10000)..fillRange(0, 0x10000, double.nan);
    for (final MapEntry(:key, :value) in _kerns.entries) {
      table[key] = value;
    }
    return table;
  }();

  /// The one-character strings of U+0000 to U+00FF, made once.
  static final List<String> _latin1 = List.generate(
    0x100,
    String.fromCharCode,
    growable: false,
  );

  @override
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
  }) {
    final glyphs = <ShapedGlyph>[];
    final widths = _widths;
    final kerns = kerning ? _kernTable : null;
    final missing = _data.symbolic ? 0x20 : 0x3f; // '?'
    var previous = -1;
    for (final rune in text.runes) {
      final code = _code(rune) ?? missing;
      final codeWidth = code < 256 ? widths[code] : null;
      if (kerns != null && previous >= 0 && code < 256) {
        final kern = kerns[previous << 8 | code];
        if (!kern.isNaN) {
          final last = glyphs.length - 1;
          final glyph = glyphs[last];
          glyphs[last] = ShapedGlyph(glyph.id, glyph.text, glyph.advance, kern);
        }
      }
      glyphs.add(
        ShapedGlyph(
          code,
          rune < 0x100 ? _latin1[rune] : String.fromCharCode(rune),
          codeWidth ?? 0,
        ),
      );
      previous = codeWidth != null ? code : -1;
    }
    return glyphs;
  }

  @override
  List<int> encode(List<ShapedGlyph> glyphs) => [for (final g in glyphs) g.id];

  @override
  void writeTo(PdfWriter writer) {
    writer.write(
      PdfDict({
        'Type': const PdfName('Font'),
        'Subtype': const PdfName('Type1'),
        'BaseFont': PdfName(name),
        if (!_data.symbolic) 'Encoding': const PdfName('WinAnsiEncoding'),
      }),
      reference(writer),
    );
  }
}

final class _StandardGlyphs {
  new(this._byCode, this._byName, this.codeForUnicode, this.kerning);

  factory parse(StandardFontData data) {
    final byCode = <int, (String, int)>{};
    final byName = <String, int>{};
    final codeForUnicode = <int, int>{};
    for (final entry in data.glyphs.split(';')) {
      final [code, name, width, unicode] = entry.split(' ');
      final c = int.parse(code);
      final w = int.parse(width);
      byName[name] = w;
      if (c >= 0) {
        byCode[c] = (name, w);
        if (unicode != '-') codeForUnicode[int.parse(unicode, radix: 16)] = c;
      }
    }
    final kerning = <String, int>{};
    if (data.kerning.isNotEmpty) {
      for (final pair in data.kerning.split(';')) {
        final [left, right, value] = pair.split(' ');
        kerning['$left $right'] = int.parse(value);
      }
    }
    // Latin fonts are used through WinAnsiEncoding: their glyphs by name
    // (the AFM codes are StandardEncoding's).
    final unicodeNames = <int, String>{};
    for (final entry in data.glyphs.split(';')) {
      final [_, name, _, unicode] = entry.split(' ');
      if (unicode != '-') {
        unicodeNames.putIfAbsent(int.parse(unicode, radix: 16), () => name);
      }
    }
    // WinAnsiEncoding also encodes the space as 240 (the no-break space)
    // and the hyphen as 255 (the soft hyphen): ISO 32000-2, Annex D.2.
    if (unicodeNames[0x20] case final space?) {
      unicodeNames.putIfAbsent(0xa0, () => space);
    }
    if (unicodeNames[0x2d] case final hyphen?) {
      unicodeNames.putIfAbsent(0xad, () => hyphen);
    }
    return _StandardGlyphs(byCode, byName, codeForUnicode, kerning)
      .._unicodeNames = unicodeNames;
  }

  final Map<int, (String, int)> _byCode;
  final Map<String, int> _byName;
  final Map<int, int> codeForUnicode;
  final Map<String, int> kerning;
  Map<int, String> _unicodeNames = const {};

  String? nameForCode(int code, {required bool symbolic}) {
    if (symbolic) return _byCode[code]?.$1;
    final character = winAnsiCharacter(code);
    return character == null ? null : _unicodeNames[character];
  }

  int? widthForCode(int code, {required bool symbolic}) {
    final name = nameForCode(code, symbolic: symbolic);
    return name == null ? null : _byName[name];
  }
}

/// A TrueType or OpenType font embedded in the document: subset to the
/// glyphs used (TrueType outlines) and written as a Type0 font with
/// Identity-H encoding and a ToUnicode map, so text extracts and searches.
final class EmbeddedFont extends PdfFont implements OpenTypeTextFont {
  new _(
    this.font, {
    required this.subset,
    required this.truncateWidths,
    required bool singleByte,
    this.kernTableSubtable,
  }) : _shaper = OpenTypeShaper(font, kernTableSubtable: kernTableSubtable),
       singleByte = singleByte && font.isTrueType,
       super._();

  /// The font in [bytes] (the font at [index] of a collection); with
  /// [subset] (the default), only the glyphs used are embedded. The
  /// glyph widths written are rounded to whole 1000ths of the em, or
  /// truncated with [truncateWidths] (as some engines do; text then lines
  /// up with theirs). Text is kerned by the font's GPOS pair adjustments,
  /// else its `kern` table, or by the `kern` table's subtable
  /// [kernTableSubtable] alone (Prawn kerns with the first). With
  /// [singleByte], a font with TrueType outlines is written as simple
  /// fonts, see [singleByte].
  factory parse(
    List<int> bytes, {
    int index = 0,
    bool subset = true,
    bool truncateWidths = false,
    bool singleByte = false,
    int? kernTableSubtable,
  }) => EmbeddedFont._(
    OpenTypeFont.parse(bytes, index: index),
    subset: subset,
    truncateWidths: truncateWidths,
    singleByte: singleByte,
    kernTableSubtable: kernTableSubtable,
  );

  @override
  final OpenTypeFont font;

  /// Shapes text, and gives the metrics.
  final OpenTypeShaper _shaper;

  /// Whether only the glyphs used are embedded.
  final bool subset;

  /// Whether the widths written are truncated rather than rounded.
  final bool truncateWidths;

  /// The `kern` subtable text is kerned by alone, if any.
  final int? kernTableSubtable;

  /// Whether the font is written as simple TrueType fonts rather than a
  /// Type0 font: subsets of up to 256 glyphs, a byte a glyph, the space
  /// code 32 in each (so word spacing is the `Tw` operator's, which
  /// applies to that code alone), each with its own `cmap` and ToUnicode
  /// map. Text in it is shown in runs of one subset ([encodeRuns]). Only
  /// fonts with TrueType outlines are.
  final bool singleByte;

  /// The simple fonts of a [singleByte] font, in order of first use.
  final List<_ByteSubset> _subsets = [];

  /// The space's glyph, code 32 in every simple font.
  late final int _space = font.glyphFor(0x20);

  /// The glyphs used so far, with the text each stands for.
  final Map<int, String> _used = {};

  /// Whether text used a character the font has no glyph for.
  bool _usedNotdef = false;

  /// Whether text has used characters the font has no glyph for (shown as
  /// `.notdef`).
  bool get missedGlyphs => _usedNotdef;

  double _scale(num units) => _shaper.scale(units);

  @override
  String get name => font.postScriptName;

  @override
  double get ascender => _shaper.ascender;

  @override
  double get descender => _shaper.descender;

  @override
  double get lineGap => _shaper.lineGap;

  @override
  double get capHeight => _shaper.capHeight;

  @override
  double get xHeight => _shaper.xHeight;

  @override
  double get underlinePosition => _shaper.underlinePosition;

  @override
  double get underlineThickness => _shaper.underlineThickness;

  @override
  bool covers(int codePoint) => _shaper.covers(codePoint);

  @override
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
  }) => _shaper.shape(
    text,
    kerning: kerning,
    ligatures: ligatures,
    features: features,
  );

  @override
  List<int> encode(List<ShapedGlyph> glyphs) {
    final bytes = Uint8List(glyphs.length * 2);
    var at = 0;
    for (final glyph in glyphs) {
      final id = glyph.id;
      // `.notdef` stands for no character: it stays out of the ToUnicode
      // map (and still goes into the subset).
      if (id == 0) {
        _usedNotdef = true;
      } else {
        _used[id] ??= glyph.text; // the first text stays
      }
      bytes[at++] = id >> 8;
      bytes[at++] = id;
    }
    return bytes;
  }

  /// [glyphs] as runs of codes of one simple font each (a [singleByte]
  /// font): the font's index (its reference: [subsetReference]), the
  /// glyphs' range and the codes that show them; recording the glyphs as
  /// used.
  List<({int subset, int start, int end, Uint8List codes})> encodeRuns(
    List<ShapedGlyph> glyphs,
  ) {
    if (!singleByte) throw StateError('$name is not written single-byte');
    final runs = <({int subset, int start, int end, Uint8List codes})>[];
    var current = -1;
    var start = 0;
    final codes = <int>[];
    void close(int end) {
      if (end > start) {
        runs.add((
          subset: current,
          start: start,
          end: end,
          codes: Uint8List.fromList(codes),
        ));
      }
      codes.clear();
      start = end;
    }

    for (final (i, glyph) in glyphs.indexed) {
      final id = glyph.id;
      if (id == 0) _usedNotdef = true;
      // The subset showing it: the current one, else the first that has
      // it, else the last with room, else a new one. (Every subset has
      // the space.)
      var subset = current;
      if (current < 0 || !_subsets[current].has(id)) {
        subset = _subsets.indexWhere((s) => s.has(id));
        if (subset < 0) {
          if (_subsets.isEmpty || _subsets.last.full) {
            _subsets.add(_ByteSubset(_space));
          }
          subset = _subsets.length - 1;
        }
      }
      if (subset != current) {
        close(i);
        current = subset;
      }
      codes.add(_subsets[subset].code(id, glyph.text));
    }
    if (_subsets.isEmpty) _subsets.add(_ByteSubset(_space));
    if (current < 0) current = 0;
    close(glyphs.length);
    return runs;
  }

  /// The reference simple font [subset] of a [singleByte] font is written
  /// under, reserved from [writer].
  PdfRef subsetReference(PdfWriter writer, int subset) {
    if (subset == 0) return reference(writer);
    final refs = _subsetReferences[writer] ??= {};
    return refs[subset] ??= writer.reserve();
  }

  final Expando<Map<int, PdfRef>> _subsetReferences = Expando();

  /// The six-letter tag of a subset of [glyphs] (ISO 32000-2, 9.9.2),
  /// derived from them so the same use gives the same tag.
  static String _tagOf(Iterable<int> glyphs) {
    final digest = md5
        .convert(utf8.encode((glyphs.toList()..sort()).join(',')))
        .bytes;
    return String.fromCharCodes([
      for (final b in digest.take(6)) 0x41 + b % 26,
    ]);
  }

  /// The six-letter tag of the subset.
  String get _subsetTag => _tagOf(_used.keys);

  @override
  void writeTo(PdfWriter writer) {
    if (singleByte) {
      for (final (i, subset) in _subsets.indexed) {
        _writeSimple(writer, subset, subsetReference(writer, i));
      }
      return;
    }
    final glyphs = glyphClosure(font, _used.keys);
    final trueType = font.isTrueType;
    // CFF outlines are rewritten (subset, with an identity charset for a
    // CID font) when they can be, else embedded as they are.
    final cff = trueType
        ? null
        : switch (font.table('CFF ')) {
            final table? => subsetCff(table, subset ? glyphs : null),
            null => null,
          };
    // A rewritten CFF is embedded bare (CIDFontType0C), the CFF of a font
    // that couldn't be rewritten inside its OpenType file.
    final program = trueType
        ? (subset ? subsetTrueType(font, glyphs) : font.bytes)
        : (cff ?? font.bytes);
    final baseName = subset && (trueType || cff != null)
        ? '$_subsetTag+$name'
        : name;
    final fontFile = writer.write(
      PdfStream(
        program,
        dict: PdfDict({
          if (trueType)
            'Length1': PdfInt(program.length)
          else
            'Subtype': PdfName(cff != null ? 'CIDFontType0C' : 'OpenType'),
        }),
      ),
    );
    final descriptor = _descriptor(
      writer,
      baseName,
      fontFile,
      trueType: trueType,
    );
    final descendant = writer.write(
      PdfDict({
        'Type': const PdfName('Font'),
        'Subtype': PdfName(trueType ? 'CIDFontType2' : 'CIDFontType0'),
        'BaseFont': PdfName(baseName),
        'CIDSystemInfo': PdfDict({
          'Registry': PdfString(ascii.encode('Adobe')),
          'Ordering': PdfString(ascii.encode('Identity')),
          'Supplement': const PdfInt(0),
        }),
        'FontDescriptor': descriptor,
        'DW': PdfInt(_scale(font.advance(0)).round()),
        'W': _widths(),
        if (trueType) 'CIDToGIDMap': const PdfName('Identity'),
      }),
    );
    final toUnicode = writer.write(PdfStream(utf8.encode(_toUnicodeCMap())));
    writer.write(
      PdfDict({
        'Type': const PdfName('Font'),
        'Subtype': const PdfName('Type0'),
        'BaseFont': PdfName(baseName),
        'Encoding': const PdfName('Identity-H'),
        'DescendantFonts': PdfArray([descendant]),
        'ToUnicode': toUnicode,
      }),
      reference(writer),
    );
  }

  /// Writes [subset] as a simple TrueType font under [reference]: its
  /// glyphs (and `.notdef`) with a `cmap` from its codes, no encoding
  /// (the font is symbolic), its codes' widths and a ToUnicode map.
  void _writeSimple(PdfWriter writer, _ByteSubset subset, PdfRef reference) {
    final program = subsetTrueType(
      font,
      glyphClosure(font, subset.glyphs.values),
      codes: subset.glyphs,
    );
    final baseName = '${_tagOf(subset.glyphs.values)}+$name';
    final codes = subset.glyphs.keys.toList()..sort();
    writer.write(
      PdfDict({
        'Type': const PdfName('Font'),
        'Subtype': const PdfName('TrueType'),
        'BaseFont': PdfName(baseName),
        'FirstChar': PdfInt(codes.first),
        'LastChar': PdfInt(codes.last),
        'Widths': PdfArray([
          for (var code = codes.first; code <= codes.last; code++)
            switch (subset.glyphs[code]) {
              final glyph? => _width(glyph),
              null => const PdfInt(0),
            },
        ]),
        'FontDescriptor': _descriptor(
          writer,
          baseName,
          writer.write(
            PdfStream(
              program,
              dict: PdfDict({'Length1': PdfInt(program.length)}),
            ),
          ),
          trueType: true,
        ),
        'ToUnicode': writer.write(
          PdfStream(utf8.encode(_byteToUnicodeCMap(subset.texts))),
        ),
      }),
      reference,
    );
  }

  /// The font descriptor of [baseName], its program in [fontFile].
  PdfRef _descriptor(
    PdfWriter writer,
    String baseName,
    PdfRef fontFile, {
    required bool trueType,
  }) {
    final flags =
        4 | // symbolic: glyphs addressed by id or by the font's own codes
        (font.isFixedPitch ? 1 : 0) |
        (font.italicAngle != 0 ? 64 : 0);
    return writer.write(
      PdfDict({
        'Type': const PdfName('FontDescriptor'),
        'FontName': PdfName(baseName),
        'Flags': PdfInt(flags),
        'FontBBox': PdfArray.numbers([
          for (final v in font.bbox) _scale(v).round(),
        ]),
        'ItalicAngle': PdfReal(font.italicAngle),
        // The typographic metrics when the font sets them (as readers and
        // other engines take them), else the horizontal header's.
        'Ascent': PdfInt(
          _scale(_typo(font.typoAscender, font.ascender)).round(),
        ),
        'Descent': PdfInt(
          _scale(_typo(font.typoDescender, font.descender)).round(),
        ),
        'CapHeight': PdfInt(capHeight.round()),
        'StemV': PdfInt(font.weightClass >= 600 ? 120 : 80),
        if (trueType) 'FontFile2': fontFile else 'FontFile3': fontFile,
      }),
    );
  }

  /// The width written for [glyph]: in 1000ths of the em, truncated with
  /// [truncateWidths], else exact (a font of 2000 units to the em has
  /// half thousandths), so viewers set the glyphs where the layout
  /// measured them.
  PdfObject _width(int glyph) {
    final width = _scale(font.advance(glyph));
    return truncateWidths
        ? PdfInt(width.truncate())
        : width == width.roundToDouble()
        ? PdfInt(width.round())
        : PdfReal(width, precision: 3);
  }

  /// A ToUnicode CMap for one-byte codes: each code's text.
  static String _byteToUnicodeCMap(Map<int, String> texts) {
    String hex(int v, int digits) =>
        v.toRadixString(16).padLeft(digits, '0').toUpperCase();
    final codes = texts.keys.toList()..sort();
    final out = StringBuffer()
      ..write('/CIDInit /ProcSet findresource begin\n')
      ..write('12 dict begin\nbegincmap\n')
      ..write(
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n',
      )
      ..write('/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n')
      ..write('1 begincodespacerange\n<00> <FF>\nendcodespacerange\n');
    for (var start = 0; start < codes.length; start += 100) {
      final chunk = codes.sublist(start, (start + 100).clamp(0, codes.length));
      out.write('${chunk.length} beginbfchar\n');
      for (final code in chunk) {
        final text = [for (final unit in texts[code]!.codeUnits) hex(unit, 4)]
            .join();
        out.write('<${hex(code, 2)}> <$text>\n');
      }
      out.write('endbfchar\n');
    }
    out.write(
      'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n',
    );
    return out.toString();
  }

  static int _typo(int? typo, int hhea) =>
      typo != null && typo != 0 ? typo : hhea;

  /// The widths of the glyphs used (`/W`): runs of consecutive glyph ids.
  PdfArray _widths() {
    final ids = _used.keys.toList()..sort();
    final items = <PdfObject>[];
    var i = 0;
    while (i < ids.length) {
      final start = ids[i];
      final run = <PdfObject>[];
      while (i < ids.length && ids[i] == start + run.length) {
        run.add(_width(ids[i]));
        i += 1;
      }
      items
        ..add(PdfInt(start))
        ..add(PdfArray(run));
    }
    return PdfArray(items);
  }

  /// A ToUnicode CMap (ISO 32000-2, 9.10.3) mapping each glyph used to its
  /// text.
  String _toUnicodeCMap() {
    String hex4(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
    String utf16(String text) =>
        [for (final unit in text.codeUnits) hex4(unit)].join();
    final ids = _used.keys.toList()..sort();
    final out = StringBuffer()
      ..write('/CIDInit /ProcSet findresource begin\n')
      ..write('12 dict begin\nbegincmap\n')
      ..write(
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n',
      )
      ..write('/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n')
      ..write('1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n');
    for (var start = 0; start < ids.length; start += 100) {
      final chunk = ids.sublist(start, (start + 100).clamp(0, ids.length));
      out.write('${chunk.length} beginbfchar\n');
      for (final id in chunk) {
        out.write('<${hex4(id)}> <${utf16(_used[id]!)}>\n');
      }
      out.write('endbfchar\n');
    }
    out.write(
      'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n',
    );
    return out.toString();
  }
}

/// One simple font of a single-byte [EmbeddedFont]: up to 256 codes, the
/// space code 32 (codes from 33 on in order of first use; `.notdef` 0).
final class _ByteSubset {
  new(int space) {
    glyphs[0x20] = space;
    texts[0x20] = ' ';
    _codes[space] = 0x20;
  }

  /// The glyph each code shows.
  final Map<int, int> glyphs = {};

  /// The text each code stands for (`.notdef` none).
  final Map<int, String> texts = {};

  final Map<int, int> _codes = {};
  var _next = 0x21;

  /// Whether no code is left.
  bool get full => _next > 0xff;

  /// Whether [glyph] has a code here.
  bool has(int glyph) => _codes.containsKey(glyph) || glyph == 0;

  /// The code of [glyph] (standing for [text]), given it if it has none.
  int code(int glyph, String text) {
    if (glyph == 0) {
      glyphs[0] = 0;
      return 0;
    }
    return _codes[glyph] ??= () {
      final code = _next++;
      glyphs[code] = glyph;
      texts[code] = text;
      return code;
    }();
  }
}
