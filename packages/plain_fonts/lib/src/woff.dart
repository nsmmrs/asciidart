/// Web fonts: WOFF (W3C, 2012) and WOFF2 (W3C, 2024) decoded to the
/// TrueType or OpenType font they wrap.
library;

import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_fonts/src/byte_sink.dart';
import 'package:plain_fonts/src/opentype.dart';

/// Whether [bytes] are a WOFF or WOFF2 font.
bool isWebFont(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x77 && // w
    bytes[1] == 0x4f && // O
    bytes[2] == 0x46 && // F
    (bytes[3] == 0x46 || bytes[3] == 0x32); // F, 2

/// The TrueType or OpenType font in the WOFF or WOFF2 font [bytes]; throws
/// a [FontFormatException] when they are malformed (or a WOFF2 font
/// collection).
Uint8List decodeWebFont(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (!isWebFont(data)) {
    throw const FontFormatException('not a WOFF or WOFF2 font');
  }
  try {
    return data[3] == 0x32 ? _Woff2(data).decode() : _woff(data);
  } on FormatException catch (e) {
    throw FontFormatException('bad WOFF data: ${e.message}');
  }
}

/// A WOFF font: zlib-compressed tables.
Uint8List _woff(Uint8List data) {
  final header = _Reader(data, 4);
  final flavor = header.u32();
  header.u32(); // length
  final count = header.u16();
  final directory = _Reader(data, 44);
  final tables = <(int, Uint8List)>[];
  for (var i = 0; i < count; i++) {
    final tag = directory.u32();
    final offset = directory.u32();
    final compressed = directory.u32();
    final length = directory.u32();
    directory.u32(); // checksum
    final stored = _Reader(data, offset).bytes(compressed);
    final table = compressed < length ? zlibDecode(stored) : stored;
    if (table.length != length) {
      throw const FormatException('a table is not its stated length');
    }
    tables.add((tag, table));
  }
  return _sfnt(flavor, tables);
}

/// The tags a WOFF2 table directory names by index.
const List<String> _knownTags = [
  'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ', //
  'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp',
  'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea', 'vmtx', 'BASE', 'GDEF',
  'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL',
  'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc',
  'feat', 'fmtx', 'fvar', 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx',
  'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill',
];

int _tag(String tag) =>
    tag.codeUnits.fold(0, (value, unit) => value << 8 | unit);

final int _glyf = _tag('glyf');
final int _loca = _tag('loca');
final int _hmtx = _tag('hmtx');
final int _head = _tag('head');
final int _hhea = _tag('hhea');
final int _maxp = _tag('maxp');

/// Big-endian reads through a buffer.
final class _Reader {
  new(this._data, [this._at = 0, int? end])
    : _view = ByteData.sublistView(_data),
      _end = end ?? _data.length;

  final Uint8List _data;
  final ByteData _view;
  int _at;
  final int _end;

  void _need(int n) {
    if (_at + n > _end) throw const FormatException('data cut short');
  }

  int u8() {
    _need(1);
    return _data[_at++];
  }

  int u16() {
    _need(2);
    final v = _view.getUint16(_at);
    _at += 2;
    return v;
  }

  int i16() {
    _need(2);
    final v = _view.getInt16(_at);
    _at += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = _view.getUint32(_at);
    _at += 4;
    return v;
  }

  Uint8List bytes(int n) {
    _need(n);
    return Uint8List.sublistView(_data, _at, _at += n);
  }

  /// A UIntBase128.
  int base128() {
    var value = 0;
    for (var i = 0; i < 5; i++) {
      final byte = u8();
      if (i == 0 && byte == 0x80) {
        throw const FormatException('UIntBase128 with a leading zero');
      }
      if (value & 0xfe000000 != 0) {
        throw const FormatException('UIntBase128 overflow');
      }
      value = value << 7 | (byte & 0x7f);
      if (byte & 0x80 == 0) return value;
    }
    throw const FormatException('UIntBase128 too long');
  }

  /// A 255UInt16.
  int u255() {
    final code = u8();
    return switch (code) {
      253 => u16(),
      254 => u8() + 506,
      255 => u8() + 253,
      _ => code,
    };
  }
}

/// A table of a WOFF2 font's directory.
final class _Entry {
  new(this.tag, this.length, this.stored, {required this.transformed});

  final int tag;
  final int length;
  final bool transformed;

  /// Its length in the decompressed stream.
  final int stored;
  late Uint8List data;
}

final class _Woff2 {
  new(this._data);

  final Uint8List _data;

  Uint8List decode() {
    final header = _Reader(_data, 4);
    final flavor = header.u32();
    header._at = 12;
    final count = header.u16();
    header._at = 20;
    final compressedLength = header.u32();
    if (flavor == 0x74746366) {
      throw const FormatException('WOFF2 font collections are not supported');
    }
    final directory = _Reader(_data, 48);
    final entries = <_Entry>[];
    for (var i = 0; i < count; i++) {
      final flags = directory.u8();
      final index = flags & 0x3f;
      final tag = index == 63 ? directory.u32() : _tag(_knownTags[index]);
      final version = flags >> 6;
      final length = directory.base128();
      final transformed = tag == _glyf || tag == _loca
          ? version == 0
          : version != 0;
      final stored = transformed ? directory.base128() : length;
      if (transformed && tag != _glyf && tag != _loca && tag != _hmtx) {
        throw const FormatException('an unknown table transform');
      }
      entries.add(_Entry(tag, length, stored, transformed: transformed));
    }
    final stream = brotliDecode(directory.bytes(compressedLength));
    var at = 0;
    for (final entry in entries) {
      if (at + entry.stored > stream.length) {
        throw const FormatException('the tables overrun their data');
      }
      entry.data = Uint8List.sublistView(stream, at, at += entry.stored);
    }
    _Reader table(int tag, int at) => _Reader(
      entries
          .firstWhere(
            (e) => e.tag == tag,
            orElse: () => throw const FormatException('a table is missing'),
          )
          .data,
      at,
    );

    final glyf = entries.where((e) => e.tag == _glyf).firstOrNull;
    final loca = entries.where((e) => e.tag == _loca).firstOrNull;
    List<int>? xMins;
    if (glyf != null && glyf.transformed) {
      if (loca == null || !loca.transformed) {
        throw const FormatException('glyf transformed without loca');
      }
      final (glyfData, locaData, mins) = _glyfAndLoca(glyf.data);
      glyf.data = glyfData;
      loca.data = locaData;
      xMins = mins;
    }
    final hmtx = entries.where((e) => e.tag == _hmtx).firstOrNull;
    if (hmtx != null && hmtx.transformed) {
      if (xMins == null) {
        throw const FormatException('hmtx transformed without glyf');
      }
      hmtx.data = _hmtxTable(
        hmtx.data,
        table(_hhea, 34).u16(),
        table(_maxp, 4).u16(),
        xMins,
      );
    }
    return _sfnt(flavor, [for (final e in entries) (e.tag, e.data)]);
  }

  /// The glyf and loca tables from the transformed glyf table, and each
  /// glyph's xMin: every glyph written into one buffer, its points
  /// decoded into scratch arrays reused from glyph to glyph (as the
  /// reference decoder, woff2_dec.cc, does).
  (Uint8List, Uint8List, List<int>) _glyfAndLoca(Uint8List data) {
    final header = _Reader(data)..u16(); // reserved
    final options = header.u16();
    final numGlyphs = header.u16();
    final indexFormat = header.u16();
    final sizes = [for (var i = 0; i < 7; i++) header.u32()];
    final streams = <_Reader>[];
    var at = header._at;
    for (final size in sizes) {
      if (at + size > data.length) {
        throw const FormatException('glyf streams overrun the table');
      }
      streams.add(_Reader(data, at, at + size));
      at += size;
    }
    final [contours, points, flags, glyphs, composites, boxes, instructions] =
        streams;
    Uint8List? overlaps;
    if (options & 1 != 0) {
      overlaps = _Reader(data, at).bytes((numGlyphs + 7) >> 3);
    }
    final boxBitmap = boxes.bytes(((numGlyphs + 31) >> 5) * 4);

    final out = ByteSink(data.length * 2);
    final offsets = Int32List(numGlyphs + 1);
    final xMins = List.filled(numGlyphs, 0);
    final scratch = _Points();
    for (var g = 0; g < numGlyphs; g++) {
      offsets[g] = out.length;
      final hasBox = boxBitmap[g >> 3] & (0x80 >> (g & 7)) != 0;
      final n = contours.i16();
      if (n == 0) {
        if (hasBox) throw const FormatException('a bounding box for no glyph');
        continue;
      }
      if (n == -1) {
        if (!hasBox) {
          throw const FormatException('a composite glyph without its box');
        }
        final box = boxes.bytes(8);
        final start = composites._at;
        var more = true;
        var hasInstructions = false;
        while (more) {
          final componentFlags = composites.u16();
          composites
            ..u16() // glyph index
            ..bytes(componentFlags & 0x0001 != 0 ? 4 : 2);
          if (componentFlags & 0x0008 != 0) {
            composites.bytes(2);
          } else if (componentFlags & 0x0040 != 0) {
            composites.bytes(4);
          } else if (componentFlags & 0x0080 != 0) {
            composites.bytes(8);
          }
          if (componentFlags & 0x0100 != 0) hasInstructions = true;
          more = componentFlags & 0x0020 != 0;
        }
        out
          ..u16(-1)
          ..add(box)
          ..addRange(data, start, composites._at);
        if (hasInstructions) {
          final length = glyphs.u255();
          out
            ..u16(length)
            ..add(instructions.bytes(length));
        }
        xMins[g] = _signed16(box[0] << 8 | box[1]);
      } else if (n > 0) {
        final ends = scratch.ends(n);
        var total = 0;
        for (var c = 0; c < n; c++) {
          total += points.u255();
          ends[c] = total - 1;
        }
        final pointFlags = flags.bytes(total);
        scratch.decode(pointFlags, glyphs);
        final instructionLength = glyphs.u255();
        final code = instructions.bytes(instructionLength);
        out.u16(n);
        if (hasBox) {
          final box = boxes.bytes(8);
          out.add(box);
          xMins[g] = _signed16(box[0] << 8 | box[1]);
        } else {
          out
            ..u16(scratch.xMin)
            ..u16(scratch.yMin)
            ..u16(scratch.xMax)
            ..u16(scratch.yMax);
          xMins[g] = _signed16(scratch.xMin & 0xffff);
        }
        for (var c = 0; c < n; c++) {
          out.u16(ends[c]);
        }
        out
          ..u16(instructionLength)
          ..add(code);
        scratch.writeTo(
          out,
          overlap:
              overlaps != null && overlaps[g >> 3] & (0x80 >> (g & 7)) != 0,
        );
      } else {
        throw const FormatException('a glyph of a negative contour count');
      }
      out.zeros((4 - out.length % 4) % 4);
    }
    offsets[numGlyphs] = out.length;
    final loca = ByteSink((indexFormat == 0 ? 2 : 4) * (numGlyphs + 1));
    for (final offset in offsets) {
      if (indexFormat == 0) {
        loca.u16(offset >> 1);
      } else {
        loca.u32(offset);
      }
    }
    return (out.takeBytes(), loca.takeBytes(), xMins);
  }

  static int _signed16(int value) => value >= 0x8000 ? value - 0x10000 : value;

  /// The hmtx table from the transformed one: left side bearings left out
  /// are the glyphs' xMin.
  static Uint8List _hmtxTable(
    Uint8List data,
    int numberOfHMetrics,
    int numGlyphs,
    List<int> xMins,
  ) {
    final reader = _Reader(data);
    final flags = reader.u8();
    if (flags & 0xfc != 0 ||
        numberOfHMetrics > numGlyphs ||
        numGlyphs > xMins.length) {
      throw const FormatException('a bad hmtx transform');
    }
    final advances = Uint16List(numberOfHMetrics);
    for (var i = 0; i < numberOfHMetrics; i++) {
      advances[i] = reader.u16();
    }
    final out = ByteSink(2 * numberOfHMetrics + 2 * numGlyphs);
    for (var i = 0; i < numGlyphs; i++) {
      final flag = i < numberOfHMetrics ? 1 : 2;
      if (i < numberOfHMetrics) out.u16(advances[i]);
      out.u16(flags & flag != 0 ? xMins[i] : reader.i16());
    }
    return out.takeBytes();
  }
}

/// The points of a simple glyph being decoded: arrays kept from glyph to
/// glyph, grown as needed.
final class _Points {
  Int32List _ends = Int32List(64);
  Int32List _xs = Int32List(256);
  Int32List _ys = Int32List(256);
  Uint8List _onCurve = Uint8List(256);
  int _count = 0;

  /// The bounds of the points (zeros for none).
  int xMin = 0;
  int yMin = 0;
  int xMax = 0;
  int yMax = 0;

  /// An array for [n] contour ends.
  Int32List ends(int n) {
    if (n > _ends.length) _ends = Int32List(n);
    return _ends;
  }

  /// Decodes the points of [pointFlags], their coordinates from the
  /// triplets in [glyphs].
  void decode(Uint8List pointFlags, _Reader glyphs) {
    final total = pointFlags.length;
    if (total > _xs.length) {
      _xs = Int32List(total);
      _ys = Int32List(total);
      _onCurve = Uint8List(total);
    }
    final xs = _xs;
    final ys = _ys;
    final onCurve = _onCurve;
    _count = total;
    var x = 0;
    var y = 0;
    var x0 = 0;
    var y0 = 0;
    var x1 = 0;
    var y1 = 0;
    for (var p = 0; p < total; p++) {
      final flag = pointFlags[p];
      onCurve[p] = flag >> 7 == 0 ? 1 : 0;
      final triplet = flag & 0x7f;
      int dx;
      int dy;
      if (triplet < 10) {
        dx = 0;
        dy = _signed(triplet, ((triplet & 14) << 7) + glyphs.u8());
      } else if (triplet < 20) {
        dx = _signed(triplet, (((triplet - 10) & 14) << 7) + glyphs.u8());
        dy = 0;
      } else if (triplet < 84) {
        final b0 = triplet - 20;
        final b1 = glyphs.u8();
        dx = _signed(triplet, 1 + (b0 & 0x30) + (b1 >> 4));
        dy = _signed(triplet >> 1, 1 + ((b0 & 0x0c) << 2) + (b1 & 0x0f));
      } else if (triplet < 120) {
        final b0 = triplet - 84;
        final b1 = glyphs.u8();
        final b2 = glyphs.u8();
        dx = _signed(triplet, 1 + ((b0 ~/ 12) << 8) + b1);
        dy = _signed(triplet >> 1, 1 + (((b0 % 12) >> 2) << 8) + b2);
      } else if (triplet < 124) {
        final b1 = glyphs.u8();
        final b2 = glyphs.u8();
        final b3 = glyphs.u8();
        dx = _signed(triplet, (b1 << 4) + (b2 >> 4));
        dy = _signed(triplet >> 1, ((b2 & 0x0f) << 8) + b3);
      } else {
        final b1 = glyphs.u8();
        final b2 = glyphs.u8();
        final b3 = glyphs.u8();
        final b4 = glyphs.u8();
        dx = _signed(triplet, (b1 << 8) + b2);
        dy = _signed(triplet >> 1, (b3 << 8) + b4);
      }
      xs[p] = x += dx;
      ys[p] = y += dy;
      // The bounds of the coordinates as stored (32 bits).
      final px = xs[p];
      final py = ys[p];
      if (p == 0) {
        x0 = x1 = px;
        y0 = y1 = py;
      } else {
        if (px < x0) x0 = px;
        if (px > x1) x1 = px;
        if (py < y0) y0 = py;
        if (py > y1) y1 = py;
      }
    }
    xMin = x0;
    yMin = y0;
    xMax = x1;
    yMax = y1;
  }

  static int _signed(int flag, int value) => flag & 1 != 0 ? value : -value;

  /// The flags and coordinates of the points, as the reference decoder
  /// writes them.
  void writeTo(ByteSink out, {required bool overlap}) {
    final xs = _xs;
    final ys = _ys;
    final onCurve = _onCurve;
    final total = _count;
    // The flags, a run of the same flag as the flag with its repeat bit
    // and a count.
    var lastX = 0;
    var lastY = 0;
    var lastFlag = -1;
    var pending = -1;
    var repeat = 0;
    for (var p = 0; p < total; p++) {
      var flag = onCurve[p];
      if (overlap && p == 0) flag |= 0x40;
      final dx = xs[p] - lastX;
      final dy = ys[p] - lastY;
      if (dx == 0) {
        flag |= 0x10;
      } else if (dx > -256 && dx < 256) {
        flag |= 0x02 | (dx > 0 ? 0x10 : 0);
      }
      if (dy == 0) {
        flag |= 0x20;
      } else if (dy > -256 && dy < 256) {
        flag |= 0x04 | (dy > 0 ? 0x20 : 0);
      }
      if (flag == lastFlag && repeat != 255) {
        pending |= 0x08;
        repeat++;
      } else {
        if (pending >= 0) out.addByte(pending);
        if (repeat != 0) out.addByte(repeat);
        pending = flag;
        repeat = 0;
      }
      lastX = xs[p];
      lastY = ys[p];
      lastFlag = flag;
    }
    if (pending >= 0) out.addByte(pending);
    if (repeat != 0) out.addByte(repeat);
    // The x coordinates, then the y ones.
    var last = 0;
    for (var p = 0; p < total; p++) {
      final d = xs[p] - last;
      if (d != 0) {
        if (d > -256 && d < 256) {
          out.addByte(d.abs());
        } else {
          out.u16(d);
        }
      }
      last = xs[p];
    }
    last = 0;
    for (var p = 0; p < total; p++) {
      final d = ys[p] - last;
      if (d != 0) {
        if (d > -256 && d < 256) {
          out.addByte(d.abs());
        } else {
          out.u16(d);
        }
      }
      last = ys[p];
    }
  }
}

/// Big-endian writes.
final class _Writer {
  new([int capacity = 256]) : _out = ByteSink(capacity);

  final ByteSink _out;

  void u8(int v) => _out.addByte(v);

  void u16(int v) => _out.u16(v);

  void i16(int v) => _out.u16(v);

  void u32(int v) => _out.u32(v);

  void bytes(List<int> b) => _out.add(b);

  Uint8List take() => _out.takeBytes();
}

/// The checksum of an sfnt table.
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

/// A TrueType or OpenType font of [flavor] with [tables], in tag order,
/// with checksums and the head table's checksum adjustment.
Uint8List _sfnt(int flavor, List<(int, Uint8List)> tables) {
  final sorted = [...tables]..sort((a, b) => a.$1.compareTo(b.$1));
  var entrySelector = 0;
  while ((2 << entrySelector) <= sorted.length) {
    entrySelector++;
  }
  final searchRange = 16 << entrySelector;
  var size = 12 + 16 * sorted.length;
  for (final (_, table) in sorted) {
    size += (table.length + 3) & ~3;
  }
  final out = _Writer(size)
    ..u32(flavor)
    ..u16(sorted.length)
    ..u16(searchRange)
    ..u16(entrySelector)
    ..u16(sorted.length * 16 - searchRange);
  var offset = 12 + 16 * sorted.length;
  int? headAt;
  final bodies = <Uint8List>[];
  for (final (tag, table) in sorted) {
    var body = table;
    if (tag == _head) {
      if (body.length < 12) throw const FormatException('a short head table');
      body = Uint8List.fromList(body)..fillRange(8, 12, 0);
      headAt = offset;
    }
    out
      ..u32(tag)
      ..u32(_checksum(body))
      ..u32(offset)
      ..u32(body.length);
    bodies.add(body);
    offset += (body.length + 3) & ~3;
  }
  for (final body in bodies) {
    out
      ..bytes(body)
      .._out.zeros((4 - body.length % 4) % 4);
  }
  final font = out.take();
  if (headAt != null) {
    final adjustment = (0xb1b0afba - _checksum(font)) & 0xffffffff;
    ByteData.sublistView(font).setUint32(headAt + 8, adjustment);
  }
  return font;
}
