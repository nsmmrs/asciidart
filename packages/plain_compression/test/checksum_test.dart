// CRC-32 and Adler-32 compute what the byte-at-a-time versions frozen at
// 17001e86 computed: typed and untyped lists, views, ranges and running
// CRCs.
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:test/test.dart';

import 'frozen/crc32.dart' as frozen;
import 'frozen/flate.dart' as frozen;

void main() {
  final random = Random(7);
  Uint8List bytes(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) random.nextInt(256)]);

  final sizes = [0, 1, 7, 8, 9, 15, 16, 17, 63, 5551, 5552, 5553, 20000];

  test('CRC-32 matches the byte-at-a-time CRC', () {
    for (final n in sizes) {
      final data = bytes(n);
      expect(crc32(data), frozen.crc32(data), reason: '$n bytes');
      expect(crc32(data.toList()), frozen.crc32(data), reason: 'List $n');
    }
    expect(crc32(Uint8List(100000)), frozen.crc32(Uint8List(100000)));
    final ones = Uint8List(4099)..fillRange(0, 4099, 255);
    expect(crc32(ones), frozen.crc32(ones));
  });

  test('CRC-32 over ranges, views and running CRCs', () {
    final data = bytes(3000);
    for (var k = 0; k < 300; k++) {
      final start = random.nextInt(data.length);
      final end = start + random.nextInt(data.length - start + 1);
      final crc = random.nextBool() ? 0 : random.nextInt(0x100000000);
      expect(
        crc32(data, start: start, end: end, crc: crc),
        frozen.crc32(data, start: start, end: end, crc: crc),
        reason: '$start-$end from $crc',
      );
      final view = Uint8List.sublistView(data, start, end);
      expect(crc32(view, crc: crc), frozen.crc32(view, crc: crc));
    }
    // An empty or reversed range is the CRC so far.
    expect(
      crc32(data, start: 100, end: 50),
      frozen.crc32(data, start: 100, end: 50),
    );
    expect(crc32(data, start: 100, end: 100, crc: 5), 5);
    // Continuing a CRC is the same as one CRC over both parts.
    final whole = crc32(data);
    expect(crc32(data, start: 1234, crc: crc32(data, end: 1234)), whole);
  });

  test('Adler-32 matches the byte-at-a-time sum', () {
    for (final n in [...sizes, 5552 * 3 + 5, 70000]) {
      final data = bytes(n);
      expect(adler32(data), frozen.adler32(data), reason: '$n bytes');
      expect(adler32(data.toList()), frozen.adler32(data), reason: 'List $n');
    }
    // All 255s: the largest sums the reduction has to keep in range.
    final ones = Uint8List(100000)..fillRange(0, 100000, 255);
    expect(adler32(ones), frozen.adler32(ones));
    final data = bytes(9000);
    for (var k = 0; k < 100; k++) {
      final start = random.nextInt(data.length);
      final view = Uint8List.sublistView(data, start);
      expect(adler32(view), frozen.adler32(view));
    }
  });
}
