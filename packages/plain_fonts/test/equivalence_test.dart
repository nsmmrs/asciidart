// The reader, the subsetters and the web font decoder against frozen
// copies of their code from before the performance work (test/frozen):
// the same values, the same bytes, the same rejections, on the fixtures,
// on damaged copies of them and, when the machine has it, on a CJK CFF
// font. More fonts (files or folders) can be named in
// PLAIN_FONTS_EQUIVALENCE_FONTS, separated by colons.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

import 'frozen/cff.dart' as frozen;
import 'frozen/opentype.dart' as frozen;
import 'frozen/subset.dart' as frozen;
import 'frozen/woff.dart' as frozen;

const _cjk = '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc';

List<String> _fontFiles() {
  final extra = Platform.environment['PLAIN_FONTS_EQUIVALENCE_FONTS'];
  final roots = [
    'test/fonts',
    if (File(_cjk).existsSync()) _cjk,
    ...?extra?.split(':').where((path) => path.isNotEmpty),
  ];
  final files = <String>[];
  for (final root in roots) {
    if (FileSystemEntity.isDirectorySync(root)) {
      files.addAll(
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path)
            .where(
              (path) => RegExp(r'\.(ttf|otf|ttc|otc|woff2?)$').hasMatch(path),
            )
            .toList()
          ..sort(),
      );
    } else {
      files.add(root);
    }
  }
  return files;
}

/// What [body] gives, or the type of what it throws (messages may differ).
Object? _outcome(Object? Function() body) {
  try {
    return body();
  } on FontFormatException {
    return 'FontFormatException';
  } on frozen.FontFormatException {
    return 'FontFormatException';
  } on Object catch (e) {
    return e is RangeError ? 'RangeError' : '${e.runtimeType}';
  }
}

/// Expects [actual] to be [expected], byte arrays compared quickly.
void _expectSame(Object? actual, Object? expected, {String? reason}) {
  if (actual is Uint8List && expected is Uint8List) {
    var same = actual.length == expected.length;
    for (var i = 0; same && i < actual.length; i++) {
      same = actual[i] == expected[i];
    }
    if (!same) {
      fail(
        'bytes differ (${actual.length} against ${expected.length})'
        '${reason == null ? '' : ': $reason'}',
      );
    }
  } else if (actual is Set<int> && expected is Set<int>) {
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      fail('sets differ${reason == null ? '' : ': $reason'}');
    }
  } else if (actual is Map<int, int> && expected is Map<int, int>) {
    if (actual.length != expected.length ||
        actual.entries.any((e) => expected[e.key] != e.value)) {
      fail('maps differ${reason == null ? '' : ': $reason'}');
    }
  } else {
    expect(actual, expected, reason: reason);
  }
}

void _expectSameFont(
  OpenTypeFont font,
  frozen.OpenTypeFont old,
  Random r, {
  bool thorough = true,
}) {
  expect(
    [
      font.unitsPerEm, font.bbox, font.indexToLocFormat, font.ascender, //
      font.descender, font.lineGap, font.numGlyphs, font.capHeight,
      font.typoAscender, font.typoDescender, font.typoLineGap, font.xHeight,
      font.weightClass, font.fsType, font.italicAngle, font.isFixedPitch,
      font.underlinePosition, font.underlineThickness, font.postScriptName,
      font.familyName, font.isTrueType, font.tableTags.toList(),
    ],
    [
      old.unitsPerEm, old.bbox, old.indexToLocFormat, old.ascender, //
      old.descender, old.lineGap, old.numGlyphs, old.capHeight,
      old.typoAscender, old.typoDescender, old.typoLineGap, old.xHeight,
      old.weightClass, old.fsType, old.italicAngle, old.isFixedPitch,
      old.underlinePosition, old.underlineThickness, old.postScriptName,
      old.familyName, old.isTrueType, old.tableTags.toList(),
    ],
  );
  final cmap = _outcome(() => font.characterMap);
  _expectSame(cmap, _outcome(() => old.characterMap));
  if (cmap is! Map<int, int>) return;
  final probes = [
    ...cmap.keys,
    for (var i = 0; i < 2000; i++) r.nextInt(0x110000),
    for (var c = 0; c < 0x300; c++) c,
    -1,
    0xffff,
    0x10000,
    0x10ffff,
  ];
  for (final c in probes) {
    if (font.glyphFor(c) != old.glyphFor(c)) {
      fail('glyphFor($c): ${font.glyphFor(c)} != ${old.glyphFor(c)}');
    }
  }
  for (var g = -1; g <= font.numGlyphs; g++) {
    if (font.advance(g) != old.advance(g)) fail('advance($g)');
  }
  // Kerning: the mapped glyphs' pairs (all of them for a small font, a
  // sample otherwise) and random pairs, out of range ones too.
  final mapped = {...cmap.values}.toList()..sort();
  final pairs = <(int, int)>[
    if (mapped.isEmpty)
      ...const <(int, int)>[]
    else if (!thorough)
      for (var i = 0; i < 2000; i++)
        (mapped[r.nextInt(mapped.length)], mapped[r.nextInt(mapped.length)])
    else if (mapped.length <= 400)
      for (final a in mapped)
        for (final b in mapped) (a, b)
    else
      for (var i = 0; i < 160000; i++)
        (mapped[r.nextInt(mapped.length)], mapped[r.nextInt(mapped.length)]),
    for (var i = 0; i < (thorough ? 20000 : 1000); i++)
      (r.nextInt(font.numGlyphs + 2), r.nextInt(font.numGlyphs + 2)),
  ];
  for (final (a, b) in pairs) {
    final value = _outcome(() => font.kerning(a, b));
    final expected = _outcome(() => old.kerning(a, b));
    if (value != expected) fail('kerning($a, $b): $value != $expected');
    if (font.kernTablePair(a, b) != old.kernTablePair(a, b)) {
      fail('kernTablePair($a, $b)');
    }
    if (font.kernTablePair(a, b, subtable: 0) !=
        old.kernTablePair(a, b, subtable: 0)) {
      fail('kernTablePair($a, $b, subtable: 0)');
    }
  }
  expect(font.hasKernTable, old.hasKernTable);
  for (final feature in ['smcp', 'onum', 'c2sc', 'liga', 'kern', 'zero']) {
    expect(
      _outcome(() => font.hasFeature(feature)),
      _outcome(() => old.hasFeature(feature)),
    );
    _expectSame(
      _outcome(() => font.singleSubstitutions(feature)),
      _outcome(() => old.singleSubstitutions(feature)),
    );
  }
  expect(
    _outcome(() => font.ligatures.map((k, v) => MapEntry(k, v.toString()))),
    _outcome(() => old.ligatures.map((k, v) => MapEntry(k, v.toString()))),
  );
  if (font.isTrueType) {
    for (var i = 0; i < 300; i++) {
      final g = i < 100 ? i : r.nextInt(font.numGlyphs);
      expect(
        _outcome(() => font.glyphBounds(g)),
        _outcome(() => old.glyphBounds(g)),
      );
      expect(
        _outcome(() => font.components(g)),
        _outcome(() => old.components(g)),
      );
    }
  }
}

/// Glyph sets to subset to: a few glyphs, some hundreds, every one.
List<Set<int>> _glyphSets(int numGlyphs, Random r) => [
  {0},
  {for (var i = 0; i < 12; i++) r.nextInt(numGlyphs)},
  {for (var i = 0; i < min(numGlyphs, 400); i++) r.nextInt(numGlyphs)},
  {for (var g = 0; g < numGlyphs; g++) g},
];

void _expectSameSubsets(OpenTypeFont font, frozen.OpenTypeFont old, Random r) {
  for (final glyphs in _glyphSets(font.numGlyphs, r)) {
    final closure = glyphClosure(font, glyphs);
    _expectSame(closure, frozen.glyphClosure(old, glyphs));
    if (font.isTrueType) {
      final bytes = _outcome(() => subsetTrueType(font, closure));
      final expected = _outcome(() => frozen.subsetTrueType(old, closure));
      _expectSame(bytes, expected);
    } else if (font.table('CFF ') case final cff?) {
      _expectSame(subsetCff(cff, closure), frozen.subsetCff(cff, closure));
    }
  }
  if (font.table('CFF ') case final cff?) {
    _expectSame(subsetCff(cff, null), frozen.subsetCff(cff, null));
  }
}

/// [data] as a Brotli stream of uncompressed meta-blocks (RFC 7932,
/// 9.2), which any decoder reads back as it is.
Uint8List _brotliStored(Uint8List data) {
  final out = <int>[];
  var bits = 0;
  var count = 0;
  void write(int value, int width) {
    bits |= value << count;
    count += width;
    while (count >= 8) {
      out.add(bits & 0xff);
      bits >>= 8;
      count -= 8;
    }
  }

  void align() {
    if (count > 0) write(0, 8 - count);
  }

  write(0, 1); // WBITS 16
  for (var at = 0; at < data.length; at += 0x10000) {
    final length = min(0x10000, data.length - at);
    write(0, 1); // ISLAST
    write(0, 2); // MNIBBLES 4
    write(length - 1, 16);
    write(1, 1); // ISUNCOMPRESSED
    align();
    out.addAll(Uint8List.sublistView(data, at, at + length));
  }
  write(1, 1); // ISLAST
  write(1, 1); // ISLASTEMPTY
  align();
  return Uint8List.fromList(out);
}

/// The WOFF2 font [woff2] split into its header and table directory, and
/// its decompressed table data, with where each table's data starts.
(Uint8List, Uint8List, List<(String, int, int)>) _woff2Parts(Uint8List woff2) {
  const known = [
    'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', //
    'cvt ', 'fpgm', 'glyf', 'loca', 'prep', 'CFF ',
  ];
  final view = ByteData.sublistView(woff2);
  final count = view.getUint16(12);
  final compressed = view.getUint32(20);
  var at = 48;
  int base128() {
    var value = 0;
    while (true) {
      final byte = woff2[at++];
      value = value << 7 | (byte & 0x7f);
      if (byte & 0x80 == 0) return value;
    }
  }

  final tables = <(String, int, int)>[];
  var offset = 0;
  for (var i = 0; i < count; i++) {
    final flags = woff2[at++];
    final index = flags & 0x3f;
    final String tag;
    if (index == 63) {
      tag = String.fromCharCodes(woff2, at, at + 4);
      at += 4;
    } else {
      tag = index < known.length ? known[index] : '#$index';
    }
    final length = base128();
    final version = flags >> 6;
    final transformed = tag == 'glyf' || tag == 'loca'
        ? version == 0
        : version != 0;
    final stored = transformed ? base128() : length;
    tables.add((tag, offset, stored));
    offset += stored;
  }
  final stream = brotliDecode(
    Uint8List.sublistView(woff2, at, at + compressed),
  );
  return (Uint8List.sublistView(woff2, 0, at), stream, tables);
}

/// A WOFF2 font of [directory] (its header and table directory) and the
/// table data [stream], stored uncompressed.
Uint8List _woff2Of(Uint8List directory, Uint8List stream) {
  final compressed = _brotliStored(stream);
  final font = Uint8List(directory.length + compressed.length)
    ..setAll(0, directory)
    ..setAll(directory.length, compressed);
  ByteData.sublistView(font)
    ..setUint32(8, font.length)
    ..setUint32(20, compressed.length);
  return font;
}

void main() {
  final files = _fontFiles();
  for (final path in files) {
    test('$path: the same reading, subsets and decoding', () {
      final bytes = File(path).readAsBytesSync();
      final r = Random(path.hashCode);
      if (isWebFont(bytes)) {
        _expectSame(
          _outcome(() => decodeWebFont(bytes)),
          _outcome(() => frozen.decodeWebFont(bytes)),
        );
      }
      final count = OpenTypeFont.fontCount(bytes);
      for (var index = 0; index < min(count, 2); index++) {
        final font = OpenTypeFont.parse(bytes, index: index);
        final old = frozen.OpenTypeFont.parse(bytes, index: index);
        _expectSameFont(font, old, r);
        _expectSameSubsets(font, old, r);
      }
    }, timeout: const Timeout.factor(10));
  }

  test('damaged fonts: the same values, subsets and rejections', () {
    final random = Random(20261008);
    for (final name in [
      'notoserif-regular-latin.ttf',
      'notoserif-kern-subtables.ttf',
      'notoserif-features.ttf',
      'notoserif-cff.otf',
      'notoserif-cid.otf',
      'libertinus-smcp.otf',
      'notoserif-features.woff2',
      'notoserif-features-hmtx.woff2',
      'notoserif-features.woff',
    ]) {
      final bytes = File('test/fonts/$name').readAsBytesSync();
      for (var i = 0; i < 120; i++) {
        final copy = Uint8List.fromList(bytes);
        for (var k = 0; k < 1 + random.nextInt(8); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        final input = i % 3 == 2
            ? Uint8List.sublistView(copy, 0, random.nextInt(copy.length))
            : copy;
        if (isWebFont(input)) {
          _expectSame(
            _outcome(() => decodeWebFont(input)),
            _outcome(() => frozen.decodeWebFont(input)),
          );
        }
        final font = _outcome(() => OpenTypeFont.parse(input));
        final old = _outcome(() => frozen.OpenTypeFont.parse(input));
        if (font is! OpenTypeFont || old is! frozen.OpenTypeFont) {
          expect(font is OpenTypeFont, old is frozen.OpenTypeFont);
          continue;
        }
        final r = Random(i);
        _expectSameFont(font, old, r, thorough: false);
        for (final glyphs in _glyphSets(font.numGlyphs, r).take(3)) {
          final closure = _outcome(() => glyphClosure(font, glyphs));
          _expectSame(
            closure,
            _outcome(() => frozen.glyphClosure(old, glyphs)),
          );
          if (closure is! Set<int>) continue;
          if (font.isTrueType) {
            _expectSame(
              _outcome(() => subsetTrueType(font, closure)),
              _outcome(() => frozen.subsetTrueType(old, closure)),
            );
          }
        }
      }
    }
  });

  test('damaged GPOS tables: the same kerning, or the same rejection', () {
    final random = Random(2026);
    for (final name in [
      'notoserif-features.ttf',
      'notoserif-regular-latin.ttf',
      'notoserif-kern-subtables.ttf',
      'mplus1p-regular-multilingual.ttf',
    ]) {
      final bytes = File('test/fonts/$name').readAsBytesSync();
      final view = ByteData.sublistView(bytes);
      var (gpos, length) = (0, 0);
      for (var i = 0; i < view.getUint16(4); i++) {
        final record = 12 + 16 * i;
        if (String.fromCharCodes(bytes, record, record + 4) == 'GPOS') {
          gpos = view.getUint32(record + 8);
          length = view.getUint32(record + 12);
        }
      }
      for (var i = 0; i < 120; i++) {
        final copy = Uint8List.fromList(bytes);
        for (var k = 0; k < 1 + random.nextInt(4); k++) {
          // Mostly the headers, lookup lists, coverage and class tables.
          final at = random.nextInt(3) == 0
              ? random.nextInt(length)
              : random.nextInt(min(length, 600));
          copy[gpos + at] = random.nextBool()
              ? random.nextInt(256)
              : copy[gpos + at] ^ (1 << random.nextInt(8));
        }
        final font = OpenTypeFont.parse(copy);
        final old = frozen.OpenTypeFont.parse(copy);
        final glyphs = [
          for (var c = 0x21; c < 0x7f; c += 2) font.glyphFor(c),
          for (var k = 0; k < 20; k++) random.nextInt(font.numGlyphs + 5),
        ];
        for (final a in glyphs) {
          for (final b in glyphs) {
            final value = _outcome(() => font.kerning(a, b));
            final expected = _outcome(() => old.kerning(a, b));
            if (value != expected) {
              fail('$name #$i kerning($a, $b): $value != $expected');
            }
          }
        }
      }
    }
  });

  test('damaged WOFF2 table data: the same fonts, or the same rejection', () {
    final random = Random(77);
    for (final name in [
      'notoserif-features.woff2',
      'notoserif-features-hmtx.woff2',
      'libertinus-smcp.woff2',
    ]) {
      final (directory, stream, tables) = _woff2Parts(
        File('test/fonts/$name').readAsBytesSync(),
      );
      // Stored uncompressed, the font is the same font.
      final whole = _woff2Of(directory, stream);
      _expectSame(decodeWebFont(whole), frozen.decodeWebFont(whole));
      final targets = [
        for (final (tag, offset, length) in tables)
          if (tag == 'glyf' || tag == 'hmtx' || tag == 'loca') (offset, length),
      ];
      for (var i = 0; i < 400; i++) {
        final copy = Uint8List.fromList(stream);
        for (var k = 0; k < 1 + random.nextInt(3); k++) {
          final (offset, length) = targets.isEmpty || random.nextInt(5) == 0
              ? (0, copy.length)
              : targets[random.nextInt(targets.length)];
          if (length == 0) continue;
          // Mostly the stream headers and the first glyphs.
          final at =
              offset +
              (random.nextBool()
                  ? random.nextInt(min(length, 200))
                  : random.nextInt(length));
          copy[at] = random.nextBool()
              ? random.nextInt(256)
              : copy[at] ^ (1 << random.nextInt(8));
        }
        final font = _woff2Of(
          directory,
          i % 7 == 6
              ? Uint8List.sublistView(copy, 0, random.nextInt(copy.length))
              : copy,
        );
        _expectSame(
          _outcome(() => decodeWebFont(font)),
          _outcome(() => frozen.decodeWebFont(font)),
          reason: '$name #$i',
        );
      }
    }
  });

  test('damaged CFF tables: the same subsets, or null', () {
    final random = Random(1008);
    for (final name in ['notoserif-cff.otf', 'notoserif-cid.otf']) {
      final cff = OpenTypeFont.parse(File('test/fonts/$name').readAsBytesSync())
          .table('CFF ')!;
      for (var i = 0; i < 1500; i++) {
        final copy = Uint8List.fromList(cff);
        for (var k = 0; k < 1 + random.nextInt(4); k++) {
          // Mostly the header, INDEXes and DICTs at the start.
          final at = random.nextBool()
              ? random.nextInt(min(copy.length, 2000))
              : random.nextInt(copy.length);
          copy[at] = random.nextInt(256);
        }
        final input = i % 5 == 4
            ? Uint8List.sublistView(copy, 0, random.nextInt(copy.length))
            : copy;
        final glyphs = {for (var k = 0; k < 30; k++) random.nextInt(400)};
        _expectSame(
          _outcome(() => subsetCff(input, glyphs)),
          _outcome(() => frozen.subsetCff(input, glyphs)),
          reason: '$name #$i',
        );
      }
    }
  });
}
