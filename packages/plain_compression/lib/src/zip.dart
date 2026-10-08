/// ZIP archives (PKWARE APPNOTE 6.3.10): a reproducible writer and a
/// reader, with ZIP64 for archives past 4 GiB or 65,535 entries.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_compression/src/crc32.dart';
import 'package:plain_compression/src/flate.dart';

/// How a ZIP entry's data is stored.
enum ZipMethod {
  /// As it is (method 0).
  stored(0),

  /// Compressed with DEFLATE (method 8).
  deflated(8);

  new(this.code);

  /// The method's number in the archive.
  final int code;
}

/// A file of a ZIP archive, its data expanded.
final class ZipEntry {
  /// The entry [name] with [bytes], stored with [method].
  const new(this.name, this.bytes, {this.method = ZipMethod.deflated});

  /// The entry's path in the archive (`/`-separated).
  final String name;

  /// The file's contents.
  final Uint8List bytes;

  /// How the data was stored in the archive.
  final ZipMethod method;
}

/// Writes a ZIP archive, entries in the order they are added. Every entry
/// has the same modification time (1980-01-01 00:00, the earliest a ZIP
/// records) and permissions (`-rw-r--r--`), so the archive's bytes depend
/// only on its entries.
final class ZipWriter {
  /// A writer whose deflated entries are compressed with [deflate] (raw
  /// DEFLATE, no zlib header; this package's [deflate] when not given).
  /// With [zip64], ZIP64 records are written even when the archive doesn't
  /// need them.
  new({List<int> Function(List<int> bytes)? deflate, bool zip64 = false})
    : _deflate = deflate ?? _defaultDeflate,
      _forceZip64 = zip64;

  static List<int> _defaultDeflate(List<int> bytes) => deflate(bytes);

  final List<int> Function(List<int> bytes) _deflate;
  final bool _forceZip64;
  final BytesBuilder _out = BytesBuilder(copy: false);
  final BytesBuilder _central = BytesBuilder(copy: false);
  int _count = 0;
  bool _usedZip64 = false;

  static const int _dosTime = 0;
  static const int _dosDate = (1 << 5) | 1;
  static const int _max32 = 0xffffffff;
  static const int _max16 = 0xffff;

  /// Adds the file [name] with [bytes]: compressed (the writer's deflate,
  /// or [deflated] when the compressed bytes are at hand) or stored, by
  /// [method].
  void add(
    String name,
    List<int> bytes, {
    ZipMethod method = ZipMethod.deflated,
    List<int>? deflated,
  }) {
    final nameBytes = utf8.encode(name);
    final crc = crc32(bytes);
    final data = method == ZipMethod.stored
        ? bytes
        : (deflated ?? _deflate(bytes));
    final offset = _out.length;
    // UTF-8 names set general purpose bit 11, as rubyzip does for names
    // outside ASCII.
    final flags = nameBytes.any((b) => b > 0x7f) ? 0x0800 : 0;
    final big = _forceZip64 || bytes.length >= _max32 || data.length >= _max32;
    final farOffset = _forceZip64 || offset >= _max32;
    final version = big || farOffset ? 45 : 20;
    if (big || farOffset) _usedZip64 = true;

    final localExtra = big
        ? (_Bytes()
                ..u16(1)
                ..u16(16)
                ..u64(bytes.length)
                ..u64(data.length))
              .take()
        : Uint8List(0);
    _out.add(
      (_Bytes()
            ..u32(0x04034b50)
            ..u16(version)
            ..u16(flags)
            ..u16(method.code)
            ..u16(_dosTime)
            ..u16(_dosDate)
            ..u32(crc)
            ..u32(big ? _max32 : data.length)
            ..u32(big ? _max32 : bytes.length)
            ..u16(nameBytes.length)
            ..u16(localExtra.length)
            ..bytes(nameBytes)
            ..bytes(localExtra))
          .take(),
    );
    _out.add(data);

    final centralExtra = _Bytes();
    if (big || farOffset) {
      centralExtra
        ..u16(1)
        ..u16((big ? 16 : 0) + (farOffset ? 8 : 0));
      if (big) {
        centralExtra
          ..u64(bytes.length)
          ..u64(data.length);
      }
      if (farOffset) centralExtra.u64(offset);
    }
    final centralExtraBytes = centralExtra.take();
    _central.add(
      (_Bytes()
            ..u32(0x02014b50)
            ..u16(0x0300 | version) // made by: Unix
            ..u16(version)
            ..u16(flags)
            ..u16(method.code)
            ..u16(_dosTime)
            ..u16(_dosDate)
            ..u32(crc)
            ..u32(big ? _max32 : data.length)
            ..u32(big ? _max32 : bytes.length)
            ..u16(nameBytes.length)
            ..u16(centralExtraBytes.length)
            ..u16(0) // comment
            ..u16(0) // disk
            ..u16(0) // internal attributes
            ..u32(0x81a40000) // -rw-r--r--
            ..u32(farOffset ? _max32 : offset)
            ..bytes(nameBytes)
            ..bytes(centralExtraBytes))
          .take(),
    );
    _count++;
  }

  /// The archive.
  Uint8List finish() {
    final centralOffset = _out.length;
    final central = _central.takeBytes();
    _out.add(central);
    final zip64 =
        _usedZip64 ||
        _count >= _max16 ||
        centralOffset >= _max32 ||
        central.length >= _max32;
    if (zip64) {
      final recordOffset = _out.length;
      _out
        ..add(
          (_Bytes()
                ..u32(0x06064b50)
                ..u64(44)
                ..u16(0x032d)
                ..u16(45)
                ..u32(0)
                ..u32(0)
                ..u64(_count)
                ..u64(_count)
                ..u64(central.length)
                ..u64(centralOffset))
              .take(),
        )
        ..add(
          (_Bytes()
                ..u32(0x07064b50)
                ..u32(0)
                ..u64(recordOffset)
                ..u32(1))
              .take(),
        );
    }
    _out.add(
      (_Bytes()
            ..u32(0x06054b50)
            ..u16(0)
            ..u16(0)
            ..u16(zip64 ? _max16 : _count)
            ..u16(zip64 ? _max16 : _count)
            ..u32(zip64 ? _max32 : central.length)
            ..u32(zip64 ? _max32 : centralOffset)
            ..u16(0))
          .take(),
    );
    return _out.takeBytes();
  }
}

/// The entries of the ZIP archive [archive], in central-directory order,
/// their data expanded and checked against their CRC-32. Throws a
/// [FormatException] for anything malformed: offsets or sizes outside the
/// archive, an unsupported method, encryption, a CRC mismatch.
List<ZipEntry> readZip(List<int> archive) {
  final data = archive is Uint8List ? archive : Uint8List.fromList(archive);
  final r = _Reader(data);
  // The end of central directory record: the last signature that fits.
  var end = data.length - 22;
  final stop = end - 0xffff;
  while (end >= 0 && end >= stop && r.u32(end) != 0x06054b50) {
    end--;
  }
  if (end < 0 || end < stop) throw const FormatException('not a ZIP archive');
  var count = r.u16(end + 10);
  var size = r.u32(end + 12);
  var offset = r.u32(end + 16);
  if (count == 0xffff || size == 0xffffffff || offset == 0xffffffff) {
    // ZIP64: the locator just before, pointing at the ZIP64 record.
    final locator = end - 20;
    if (locator < 0 || r.u32(locator) != 0x07064b50) {
      throw const FormatException('ZIP64 locator missing');
    }
    final record = r.u64(locator + 8);
    if (r.u32(record) != 0x06064b50) {
      throw const FormatException('ZIP64 end of central directory missing');
    }
    count = r.u64(record + 32);
    size = r.u64(record + 40);
    offset = r.u64(record + 48);
  }
  r.check(offset, size);
  if (count > size ~/ 46 + 1) throw const FormatException('bad entry count');

  final entries = <ZipEntry>[];
  var at = offset;
  for (var i = 0; i < count; i++) {
    if (r.u32(at) != 0x02014b50) {
      throw const FormatException('bad central directory entry');
    }
    final flags = r.u16(at + 8);
    final methodCode = r.u16(at + 10);
    final crc = r.u32(at + 16);
    var compressedSize = r.u32(at + 20);
    var uncompressedSize = r.u32(at + 24);
    final nameLength = r.u16(at + 28);
    final extraLength = r.u16(at + 30);
    final commentLength = r.u16(at + 32);
    var local = r.u32(at + 42);
    final nameBytes = r.bytes(at + 46, nameLength);
    // ZIP64 extended information: the fields that overflowed, in order.
    final extra = at + 46 + nameLength;
    r.check(extra, extraLength);
    for (var e = extra; e + 4 <= extra + extraLength;) {
      final id = r.u16(e);
      final length = r.u16(e + 2);
      if (e + 4 + length > extra + extraLength) {
        throw const FormatException('bad extra field');
      }
      if (id == 1) {
        var f = e + 4;
        int next() {
          if (f + 8 > e + 4 + length) {
            throw const FormatException('bad ZIP64 extra field');
          }
          final v = r.u64(f);
          f += 8;
          return v;
        }

        if (uncompressedSize == 0xffffffff) uncompressedSize = next();
        if (compressedSize == 0xffffffff) compressedSize = next();
        if (local == 0xffffffff) local = next();
      }
      e += 4 + length;
    }
    if (flags & 1 != 0) {
      throw const FormatException('encrypted ZIP entries are not supported');
    }
    final method = switch (methodCode) {
      0 => ZipMethod.stored,
      8 => ZipMethod.deflated,
      _ => throw FormatException('unsupported ZIP method $methodCode'),
    };
    final name = flags & 0x0800 != 0
        ? utf8.decode(nameBytes, allowMalformed: true)
        : _cp437(nameBytes);
    if (r.u32(local) != 0x04034b50) {
      throw FormatException('bad local header for $name');
    }
    final start = local + 30 + r.u16(local + 26) + r.u16(local + 28);
    final raw = r.bytes(start, compressedSize);
    final Uint8List bytes;
    if (method == ZipMethod.stored) {
      bytes = raw;
    } else {
      final (inflated, _) = inflateAt(raw, 0);
      bytes = inflated;
    }
    if (bytes.length != uncompressedSize) {
      throw FormatException('size mismatch in $name');
    }
    if (crc32(bytes) != crc) throw FormatException('CRC mismatch in $name');
    entries.add(ZipEntry(name, bytes, method: method));
    at = extra + extraLength + commentLength;
  }
  return entries;
}

/// Little-endian writes.
final class _Bytes {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u16(int v) => _b
    ..addByte(v & 0xff)
    ..addByte((v >> 8) & 0xff);

  void u32(int v) {
    u16(v & 0xffff);
    u16((v >> 16) & 0xffff);
  }

  void u64(int v) {
    u32(v % 0x100000000);
    u32(v ~/ 0x100000000);
  }

  void bytes(List<int> b) => _b.add(b);

  Uint8List take() => _b.takeBytes();
}

/// Bounds-checked little-endian reads.
final class _Reader {
  new(this._data);

  final Uint8List _data;

  void check(int at, int length) {
    if (at < 0 || length < 0 || at + length > _data.length) {
      throw const FormatException('ZIP structure outside the archive');
    }
  }

  int u16(int at) {
    check(at, 2);
    return _data[at] | (_data[at + 1] << 8);
  }

  int u32(int at) {
    check(at, 4);
    return u16(at) + u16(at + 2) * 0x10000;
  }

  int u64(int at) {
    final low = u32(at);
    final high = u32(at + 4);
    if (high >= 0x200000) throw const FormatException('ZIP64 value too large');
    return high * 0x100000000 + low;
  }

  Uint8List bytes(int at, int length) {
    check(at, length);
    return Uint8List.sublistView(_data, at, at + length);
  }
}

/// [bytes] decoded as code page 437, as ZIP names without the UTF-8 flag
/// are.
String _cp437(List<int> bytes) => String.fromCharCodes([
  for (final b in bytes)
    if (b < 0x80) b else _cp437High.codeUnitAt(b - 0x80),
]);

const String _cp437High =
    'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼'
    '╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';
