// Compiled to JavaScript in CI: compresses and expands data with every
// level, and expands the Brotli fixtures' first stream, printing a digest
// of the bytes; the CI job compares it with the Dart VM's, as the output
// must be the same bytes on both.
import 'dart:convert';

import 'package:plain_compression/plain_compression.dart';

void main() {
  final text = utf8.encode(
    'web check, the same bytes on the VM and the web. ' * 400,
  );
  final binary = [
    for (var i = 0; i < 40000; i++) (i * i ~/ 7 + (i >> 8)) & 0xff,
  ];
  final parts = <String>[];
  for (final data in [text, binary]) {
    for (var level = 0; level <= 9; level++) {
      final compressed = zlibEncode(data, level: level);
      if (zlibDecode(compressed).length != data.length) {
        throw StateError('zlib round trip, level $level');
      }
      parts.add('${compressed.length}:${adler32(compressed)}');
    }
  }
  // gzip, CRC-32 and a ZIP archive round trip to the same bytes.
  final gz = gzipEncode(text, level: 9);
  final zip =
      (ZipWriter()
            ..add('a.txt', text)
            ..add('b.bin', binary, method: ZipMethod.stored))
          .finish();
  if (gzipDecode(gz).length != text.length ||
      readZip(zip).map((e) => e.bytes.length).join(',') !=
          '${text.length},${binary.length}') {
    throw StateError('gzip or ZIP round trip');
  }
  parts.add('${crc32(binary)} ${adler32(gz)} ${adler32(zip)}');
  // "Hello, Brotli!" at quality 11.
  final brotli = brotliDecode(base64.decode('jwaASGVsbG8sIEJyb3RsaSED'));
  parts.add(utf8.decode(brotli));
  // The digest is the program's output.
  // ignore: avoid_print
  print(adler32(utf8.encode(parts.join(' '))));
}
