/// The gzip format (RFC 1952) around DEFLATE.
library;

import 'dart:typed_data';

import 'package:plain_compression/src/crc32.dart';
import 'package:plain_compression/src/flate.dart';

/// [data] compressed in the gzip format at [level] (0-9): no file name, no
/// modification time and the OS byte "unknown", so the bytes depend only on
/// [data] and [level].
Uint8List gzipEncode(List<int> data, {int level = 6}) {
  final out = BytesBuilder(copy: false)
    ..add(const [0x1f, 0x8b, 8, 0, 0, 0, 0, 0])
    ..addByte(level >= 9 ? 2 : (level <= 1 ? 4 : 0))
    ..addByte(255)
    ..add(deflate(data, level: level));
  final crc = crc32(data);
  final size = data.length & 0xffffffff;
  for (final value in [crc, size]) {
    out
      ..addByte(value & 0xff)
      ..addByte((value >> 8) & 0xff)
      ..addByte((value >> 16) & 0xff)
      ..addByte((value >> 24) & 0xff);
  }
  return out.takeBytes();
}

/// Expands gzip [data], every member of it (concatenated members expand
/// one after another); throws a [FormatException] when it is malformed or
/// a member's CRC or size doesn't match.
Uint8List gzipDecode(List<int> data) {
  final out = BytesBuilder(copy: false);
  var at = 0;
  do {
    at = _member(data, at, out);
  } while (at < data.length && _isMember(data, at));
  return out.takeBytes();
}

bool _isMember(List<int> data, int at) =>
    at + 1 < data.length && data[at] == 0x1f && data[at + 1] == 0x8b;

/// Expands the member at [at] into [out]; the offset after it.
int _member(List<int> data, int at, BytesBuilder out) {
  if (data.length - at < 18 || !_isMember(data, at)) {
    throw const FormatException('not gzip data');
  }
  if (data[at + 2] != 8) {
    throw const FormatException('gzip data not compressed with DEFLATE');
  }
  final flags = data[at + 3];
  if (flags & 0xe0 != 0) {
    throw const FormatException('reserved gzip flags set');
  }
  var p = at + 10;
  int need(int n) {
    if (p + n > data.length) throw const FormatException('gzip data too short');
    return p;
  }

  if (flags & 4 != 0) {
    // FEXTRA: a length, then that many bytes.
    need(2);
    final length = data[p] | (data[p + 1] << 8);
    p += 2;
    need(length);
    p += length;
  }
  for (final flag in [8, 16]) {
    // FNAME, FCOMMENT: zero-terminated.
    if (flags & flag == 0) continue;
    while (data[need(1)] != 0) {
      p++;
    }
    p++;
  }
  if (flags & 2 != 0) {
    // FHCRC: the low 16 bits of the header's CRC-32.
    need(2);
    final expected = data[p] | (data[p + 1] << 8);
    if (crc32(data, start: at, end: p) & 0xffff != expected) {
      throw const FormatException('gzip header checksum mismatch');
    }
    p += 2;
  }
  final (bytes, end) = inflateAt(data, p);
  p = end;
  need(8);
  int u32(int i) =>
      data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24);
  if (u32(p) != crc32(bytes)) {
    throw const FormatException('gzip checksum mismatch');
  }
  if (u32(p + 4) != bytes.length & 0xffffffff) {
    throw const FormatException('gzip size mismatch');
  }
  out.add(bytes);
  return p + 8;
}
