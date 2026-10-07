/// A small ZIP writer for EPUB containers: entries stored or compressed
/// with a raw DEFLATE function the caller provides (`dart:io`'s zlib on
/// the VM), in the order they are added.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Writes a ZIP archive.
final class ZipWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);
  final BytesBuilder _central = BytesBuilder(copy: false);
  int _count = 0;

  /// The DOS date and time of every entry: 1980-01-01 00:00:00, the
  /// earliest a ZIP can record, so the archive is reproducible.
  static const int _dosTime = 0;
  static const int _dosDate = (1 << 5) | 1;

  /// Adds the file [name] with [bytes], compressed with [deflate] (raw
  /// DEFLATE, no zlib header) when given (or already, as [deflated]) and
  /// stored otherwise.
  void add(
    String name,
    List<int> bytes, {
    List<int> Function(List<int> bytes)? deflate,
    List<int>? deflated,
  }) {
    final nameBytes = utf8.encode(name);
    final crc = crc32(bytes);
    final compress = deflate != null || deflated != null;
    final compressed = deflated ?? deflate?.call(bytes) ?? bytes;
    final method = compress ? 8 : 0;
    final offset = _out.length;
    // UTF-8 names (general purpose flag bit 11), as the gem's rubyzip with
    // unicode_names does for names outside ASCII.
    final flags = nameBytes.any((b) => b > 0x7f) ? 0x0800 : 0;

    _out
      ..add(_u32(0x04034b50))
      ..add(_u16(20))
      ..add(_u16(flags))
      ..add(_u16(method))
      ..add(_u16(_dosTime))
      ..add(_u16(_dosDate))
      ..add(_u32(crc))
      ..add(_u32(compressed.length))
      ..add(_u32(bytes.length))
      ..add(_u16(nameBytes.length))
      ..add(_u16(0))
      ..add(nameBytes)
      ..add(compressed);

    _central
      ..add(_u32(0x02014b50))
      ..add(_u16(0x0314)) // made by: Unix, 2.0
      ..add(_u16(20))
      ..add(_u16(flags))
      ..add(_u16(method))
      ..add(_u16(_dosTime))
      ..add(_u16(_dosDate))
      ..add(_u32(crc))
      ..add(_u32(compressed.length))
      ..add(_u32(bytes.length))
      ..add(_u16(nameBytes.length))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0x81a40000)) // -rw-r--r--
      ..add(_u32(offset))
      ..add(nameBytes);
    _count += 1;
  }

  /// The archive.
  Uint8List finish() {
    final centralOffset = _out.length;
    final central = _central.takeBytes();
    _out
      ..add(central)
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(_count))
      ..add(_u16(_count))
      ..add(_u32(central.length))
      ..add(_u32(centralOffset))
      ..add(_u16(0));
    return _out.takeBytes();
  }

  static List<int> _u16(int value) => [value & 0xff, (value >> 8) & 0xff];

  static List<int> _u32(int value) => [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}

/// Reads the entries of a ZIP archive written by [ZipWriter] or another
/// writer: name, compression method and the (possibly compressed) bytes,
/// in archive order. [inflate] expands raw DEFLATE data.
List<({String name, int method, List<int> bytes})> readZip(
  List<int> archive,
  List<int> Function(List<int> bytes) inflate,
) {
  final data = archive is Uint8List ? archive : Uint8List.fromList(archive);
  final view = ByteData.sublistView(data);
  var end = data.length - 22;
  while (end >= 0 && view.getUint32(end, Endian.little) != 0x06054b50) {
    end -= 1;
  }
  if (end < 0) throw const FormatException('not a ZIP archive');
  final count = view.getUint16(end + 10, Endian.little);
  var at = view.getUint32(end + 16, Endian.little);
  final entries = <({String name, int method, List<int> bytes})>[];
  for (var i = 0; i < count; i++) {
    final method = view.getUint16(at + 10, Endian.little);
    final size = view.getUint32(at + 20, Endian.little);
    final nameLength = view.getUint16(at + 28, Endian.little);
    final extraLength = view.getUint16(at + 30, Endian.little);
    final commentLength = view.getUint16(at + 32, Endian.little);
    final local = view.getUint32(at + 42, Endian.little);
    final name = utf8.decode(data.sublist(at + 46, at + 46 + nameLength));
    final localName = view.getUint16(local + 26, Endian.little);
    final localExtra = view.getUint16(local + 28, Endian.little);
    final start = local + 30 + localName + localExtra;
    final raw = data.sublist(start, start + size);
    entries.add((
      name: name,
      method: method,
      bytes: method == 8 ? inflate(raw) : raw,
    ));
    at += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

/// The CRC-32 of [bytes] (as ZIP computes it).
int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});
