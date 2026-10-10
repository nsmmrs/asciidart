/// Subsetting TrueType fonts for embedding: the glyphs a document uses
/// (with the glyphs composite glyphs are made of) keep their outlines and
/// their glyph ids; the others are emptied, so the font program shrinks
/// while text keeps addressing glyphs by id (CID = GID).
library;

import 'dart:typed_data';

import 'package:plain_fonts/src/byte_sink.dart';
import 'package:plain_fonts/src/opentype.dart';

/// The glyphs to keep for [used]: `.notdef`, [used], and the components
/// of TrueType composite glyphs, recursively (CFF glyphs have none).
Set<int> glyphClosure(OpenTypeFont font, Iterable<int> used) {
  final keep = <int>{0};
  final queue = [...used];
  while (queue.isNotEmpty) {
    final glyph = queue.removeLast();
    if (glyph < 0 || glyph >= font.numGlyphs || !keep.add(glyph)) continue;
    if (font.isTrueType) queue.addAll(font.components(glyph));
  }
  return keep;
}

/// The tables of a subset TrueType font program.
const List<String> _keptTables = [
  'cvt ', 'fpgm', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp', 'prep', //
];

/// A TrueType font program with only [glyphs]' outlines (glyph ids kept);
/// without the `name`, `post` and layout tables, which a PDF reader
/// doesn't use, and without a `cmap` (a CID font is addressed by glyph
/// id) unless [codes] are given: one-byte codes and the glyph ids they
/// show, for a simple font (ISO 32000-2, 9.6.6.4), which a `cmap` then
/// maps in a Macintosh Roman subtable and a Windows symbol one (at
/// `0xF000` and up).
Uint8List subsetTrueType(
  OpenTypeFont font,
  Set<int> glyphs, {
  Map<int, int>? codes,
}) {
  if (!font.isTrueType) {
    throw const FontFormatException('only TrueType outlines can be subset');
  }
  final glyf = ByteSink();
  final loca = ByteData(4 * (font.numGlyphs + 1));
  for (var g = 0; g < font.numGlyphs; g++) {
    loca.setUint32(4 * g, glyf.length);
    if (glyphs.contains(g)) {
      final data = font.glyphData(g);
      glyf
        ..add(data)
        // Keep every glyph 4-byte aligned.
        ..zeros((4 - data.length % 4) % 4);
    }
  }
  loca.setUint32(4 * font.numGlyphs, glyf.length);

  final head = Uint8List.fromList(font.table('head')!);
  final headView = ByteData.sublistView(head)
    ..setUint32(8, 0) // checkSumAdjustment, set below
    ..setInt16(50, 1); // long loca offsets

  final tables = <String, Uint8List>{
    for (final tag in _keptTables) tag: ?font.table(tag),
    'glyf': glyf.takeBytes(),
    'loca': loca.buffer.asUint8List(),
    'head': head,
    if (codes != null) 'cmap': _byteCmap(codes),
  };
  final file = assembleFont(tables);
  // The checksum adjustment makes the whole file sum to 0xb1b0afba; set
  // in the file, it adds itself to the head table's checksum too.
  final adjustment = (0xb1b0afba - _checksum(file)) & 0xffffffff;
  headView.setUint32(8, adjustment);
  final view = ByteData.sublistView(file);
  final record = 12 + 16 * (tables.keys.toList()..sort()).indexOf('head');
  view
    ..setUint32(view.getUint32(record + 8) + 8, adjustment)
    ..setUint32(
      record + 4,
      (view.getUint32(record + 4) + adjustment) & 0xffffffff,
    );
  return file;
}

/// A `cmap` table mapping one-byte [codes] to glyph ids: a Macintosh
/// Roman subtable (format 6) and a Windows symbol one (format 4, the codes
/// at `0xF000` and up, one segment a code).
Uint8List _byteCmap(Map<int, int> codes) {
  final sorted = codes.keys.toList()..sort();
  if (sorted.isEmpty || sorted.first < 0 || sorted.last > 0xff) {
    throw ArgumentError.value(codes, 'codes', 'must be one-byte codes');
  }
  // Format 6: the glyph ids from the first code to the last.
  final first = sorted.first;
  final count = sorted.last - first + 1;
  final mac = ByteData(10 + 2 * count)
    ..setUint16(0, 6)
    ..setUint16(2, 10 + 2 * count)
    ..setUint16(4, 0) // language
    ..setUint16(6, first)
    ..setUint16(8, count);
  for (final code in sorted) {
    mac.setUint16(10 + 2 * (code - first), codes[code]!);
  }
  // Format 4: a segment a code, and the closing 0xFFFF one.
  final segments = sorted.length + 1;
  var power = 1;
  while (power * 2 <= segments) {
    power *= 2;
  }
  final windows = ByteData(16 + 8 * segments)
    ..setUint16(0, 4)
    ..setUint16(2, 16 + 8 * segments)
    ..setUint16(4, 0) // language
    ..setUint16(6, 2 * segments)
    ..setUint16(8, 2 * power)
    ..setUint16(10, power.bitLength - 1)
    ..setUint16(12, 2 * segments - 2 * power);
  const ends = 14;
  final starts = ends + 2 * segments + 2;
  final deltas = starts + 2 * segments;
  final offsets = deltas + 2 * segments; // all 0
  for (final (i, code) in sorted.indexed) {
    final unicode = 0xf000 + code;
    windows
      ..setUint16(ends + 2 * i, unicode)
      ..setUint16(starts + 2 * i, unicode)
      ..setUint16(deltas + 2 * i, (codes[code]! - unicode) & 0xffff);
  }
  windows
    ..setUint16(ends + 2 * sorted.length, 0xffff)
    ..setUint16(starts + 2 * sorted.length, 0xffff)
    ..setUint16(deltas + 2 * sorted.length, 1)
    ..setUint16(offsets + 2 * sorted.length, 0);
  final header = ByteData(4 + 8 * 2)
    ..setUint16(0, 0) // version
    ..setUint16(2, 2)
    // Macintosh Roman.
    ..setUint16(4, 1)
    ..setUint16(6, 0)
    ..setUint32(8, 4 + 8 * 2)
    // Windows symbol.
    ..setUint16(12, 3)
    ..setUint16(14, 0)
    ..setUint32(16, 4 + 8 * 2 + mac.lengthInBytes);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...mac.buffer.asUint8List(),
    ...windows.buffer.asUint8List(),
  ]);
}

/// A font file with [tables] (sorted by tag) and a table directory, of
/// [sfntVersion] (TrueType outlines, or `OTTO` for CFF).
Uint8List assembleFont(
  Map<String, Uint8List> tables, {
  int sfntVersion = 0x00010000,
}) {
  final tags = tables.keys.toList()..sort();
  final count = tags.length;
  var entrySelector = 0;
  while (1 << (entrySelector + 1) <= count) {
    entrySelector += 1;
  }
  final searchRange = (1 << entrySelector) * 16;
  final header = ByteData(12 + 16 * count)
    ..setUint32(0, sfntVersion)
    ..setUint16(4, count)
    ..setUint16(6, searchRange)
    ..setUint16(8, entrySelector)
    ..setUint16(10, count * 16 - searchRange);
  var offset = 12 + 16 * count;
  for (var i = 0; i < count; i++) {
    final data = tables[tags[i]]!;
    final record = 12 + 16 * i;
    for (var k = 0; k < 4; k++) {
      header.setUint8(record + k, tags[i].codeUnitAt(k));
    }
    header
      ..setUint32(record + 4, _checksum(data))
      ..setUint32(record + 8, offset)
      ..setUint32(record + 12, data.length);
    offset += (data.length + 3) & ~3;
  }
  final out = ByteSink(offset)..add(header.buffer.asUint8List());
  for (final tag in tags) {
    final data = tables[tag]!;
    out
      ..add(data)
      ..zeros((4 - data.length % 4) % 4);
  }
  return out.takeBytes();
}

/// The sum of [data]'s 32-bit words, the last one padded with zeros.
int _checksum(Uint8List data) {
  var sum = 0;
  final full = data.length & ~3;
  final view = ByteData.sublistView(data);
  for (var i = 0; i < full; i += 4) {
    sum = (sum + view.getUint32(i)) & 0xffffffff;
  }
  if (full < data.length) {
    var last = 0;
    for (var i = full; i < full + 4; i++) {
      last = last << 8 | (i < data.length ? data[i] : 0);
    }
    sum = (sum + last) & 0xffffffff;
  }
  return sum;
}
