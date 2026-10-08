/// CRC-32 (ISO-HDLC, as ZIP, gzip and PNG compute it).
library;

import 'dart:typed_data';

/// The CRC-32 of [bytes], or of the bytes from [start] to [end], continuing
/// from [crc] (the CRC of the bytes before, 0 for none).
int crc32(List<int> bytes, {int start = 0, int? end, int crc = 0}) {
  final stop = end ?? bytes.length;
  var c = crc ^ 0xffffffff;
  var i = start;
  if (bytes is Uint8List && stop - start >= 8 && crc == crc & 0xffffffff) {
    c = _sliced(bytes, start, stop, c);
    i = stop - ((stop - start) & 7);
  }
  for (; i < stop; i++) {
    c = _tables[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

/// Slicing-by-8 (Kounavis and Berry) over the bytes from [start] while
/// eight remain before [stop]: two little-endian words per step, eight
/// lookups. Every value stays within 32 bits, so the web computes the same.
int _sliced(Uint8List bytes, int start, int stop, int crc) {
  final t = _tables;
  var c = crc;
  for (var i = start; i + 8 <= stop; i += 8) {
    final lo =
        c ^
        (bytes[i] |
            (bytes[i + 1] << 8) |
            (bytes[i + 2] << 16) |
            (bytes[i + 3] << 24));
    final hi =
        bytes[i + 4] |
        (bytes[i + 5] << 8) |
        (bytes[i + 6] << 16) |
        (bytes[i + 7] << 24);
    c =
        t[1792 + (lo & 0xff)] ^
        t[1536 + ((lo >>> 8) & 0xff)] ^
        t[1280 + ((lo >>> 16) & 0xff)] ^
        t[1024 + (lo >>> 24)] ^
        t[768 + (hi & 0xff)] ^
        t[512 + ((hi >>> 8) & 0xff)] ^
        t[256 + ((hi >>> 16) & 0xff)] ^
        t[hi >>> 24];
  }
  return c;
}

/// Eight tables of 256: the first is the byte-at-a-time table, entry `b` of
/// table `k` the CRC of byte `b` followed by `k` zero bytes.
final Uint32List _tables = () {
  final t = Uint32List(8 * 256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    t[n] = c;
  }
  for (var n = 0; n < 256; n++) {
    var c = t[n];
    for (var k = 1; k < 8; k++) {
      c = t[c & 0xff] ^ (c >>> 8);
      t[k * 256 + n] = c;
    }
  }
  return t;
}();
