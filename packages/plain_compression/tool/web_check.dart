// Compiled to JavaScript in CI: compresses and expands data with every
// level, and expands the Brotli fixtures' first stream, printing a digest
// of the bytes; the CI job compares it with the Dart VM's, as the output
// must be the same bytes on both. It also checks the checksums, encoder,
// inflater and Brotli decoder against the code frozen at 17001e86 (the
// bit-level code must compute the same with dart2js's 32-bit operators)
// and throws on a difference.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_compression/src/flate.dart' show huffmanLengths;

import '../test/frozen/brotli.dart' as frozen;
import '../test/frozen/crc32.dart' as frozen;
import '../test/frozen/flate.dart' as frozen;

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
  parts
    ..add(utf8.decode(brotli))
    ..add(_frozenEquivalence());
  // The digest is the program's output.
  // ignore: avoid_print
  print(adler32(utf8.encode(parts.join(' '))));
}

/// Compares with the frozen code; the number of checks.
String _frozenEquivalence() {
  final random = Random(8);
  var checks = 0;
  void same(Object a, Object b, String what) {
    checks++;
    if (a.toString() != b.toString()) throw StateError('differs: $what');
  }

  int byte(int spread) => random.nextInt(4) == 0
      ? random.nextInt(256)
      : 32 + random.nextInt(spread);
  Uint8List bytes(int n, int spread) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) byte(spread)]);

  // Checksums over every byte value, all 255s and odd lengths.
  for (final n in [0, 7, 8, 9, 5552, 5553, 30001]) {
    final data = bytes(n, 200);
    same(crc32(data), frozen.crc32(data), 'crc32 $n');
    same(adler32(data), frozen.adler32(data), 'adler32 $n');
  }
  final ones = Uint8List(70000)..fillRange(0, 70000, 255);
  same(crc32(ones), frozen.crc32(ones), 'crc32 255s');
  same(adler32(ones), frozen.adler32(ones), 'adler32 255s');
  same(
    crc32(ones, start: 3, end: 6003, crc: 0xdeadbeef),
    frozen.crc32(ones, start: 3, end: 6003, crc: 0xdeadbeef),
    'crc32 range',
  );

  // The encoder's bytes at every level, and the inflater's reading of
  // them and of damaged copies.
  final inputs = [
    bytes(20000, 12),
    bytes(70000, 90),
    Uint8List.fromList([for (var i = 0; i < 50000; i++) (i % 300) * 7 & 0xff]),
  ];
  for (final data in inputs) {
    for (var level = 0; level <= 9; level++) {
      final compressed = deflate(data, level: level);
      same(compressed, frozen.deflate(data, level: level), 'deflate $level');
      same(inflate(compressed), data, 'inflate $level');
    }
  }
  final stream = deflate(inputs[0]);
  for (var k = 0; k < 300; k++) {
    final damaged = Uint8List.fromList(stream);
    damaged[random.nextInt(min(60, damaged.length))] = random.nextInt(256);
    final cut = Uint8List.sublistView(
      damaged,
      0,
      k.isEven ? damaged.length : random.nextInt(damaged.length),
    );
    same(
      _outcome(() => inflate(cut)),
      _outcome(() => frozen.inflate(cut)),
      '$k',
    );
  }
  for (var k = 0; k < 200; k++) {
    int frequency() => random.nextInt(3) == 0 ? 0 : 1 << random.nextInt(14);
    final frequencies = [for (var s = 0; s < 286; s++) frequency()];
    same(
      huffmanLengths(frequencies, 15),
      frozen.huffmanLengths(frequencies, 15),
      'huffmanLengths',
    );
  }

  // Brotli: test/brotli's words.txt.br (dictionary words, transformed)
  // and words-x40-q1.br, and damaged copies.
  final streams = [
    base64.decode(
      'AiUAlOPAjqHHG5G3O51bp6RLiZZMKN9EC5NNg2qxuGQREpq6reSHVj/F7oNFEHyIZmE+'
      'WY3azl6PSLGTunbG3Ha4Q0U0e16E0DYcbMH/0HIAHyuyYXEzuJJ0SPa6R0FM9Uy75XNk'
      '2uE0VRix5BwV+rBWcJK+otKHOseXzGPkA+1cjvZnSuoliI11XuM2zBo8D2Sk0GlD2kQt',
    ),
    base64.decode(
      'jzMXAICqqqrq/26XE4edDdzvARYGEAcH8LjEIcIB7CyuKmam4aIiFqriZmEBNby/gdNj'
      'GOAAcwwwHAZmg81hzyHhYvu3hfH7TOGBe7FdMdkffp55rbCNC3xhCP0fiDafMC6smM5T'
      'ZgTLXDtGXdlW4cYmwsZuRSL2JIKH2g5fyHG7XvD++T1evrBT7WpaGCQCEtP5Fe2VRazD'
      'KNDwpW0+dLKSyZNph6TORQEzkg6RNxZbM6uDNGLeKys6LhuIWK+oQ3XyFJqYgktJ5RjF'
      'rR2otnnrF88ydOhj2hCEan1rg6mzejvoqf35bvEYTs2z/j0JQAY=',
    ),
  ];
  for (var k = 0; k < 400; k++) {
    final damaged = Uint8List.fromList(streams[k & 1]);
    if (k < 2) {
      same(brotliDecode(damaged), frozen.brotliDecode(damaged), 'brotli');
      continue;
    }
    damaged[random.nextInt(damaged.length)] = random.nextInt(256);
    same(
      _outcome(() => brotliDecode(damaged)),
      _outcome(() => frozen.brotliDecode(damaged)),
      'brotli $k',
    );
  }
  return '$checks checks';
}

String _outcome(Uint8List Function() expand) {
  try {
    final bytes = expand();
    return 'ok ${bytes.length} ${adler32(bytes)}';
  } on FormatException catch (e) {
    return e.message;
  }
}
