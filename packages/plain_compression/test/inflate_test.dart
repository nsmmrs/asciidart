// The table-driven inflater against zlib (dart:io) and against the
// bit-at-a-time inflater frozen at 17001e86: the same bytes and the same
// end offset for every stream, and for damaged streams the same
// FormatException, never another error.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_compression/src/flate.dart' show inflateAt;
import 'package:test/test.dart';

import 'frozen/flate.dart' as frozen;

/// What inflating gives: the bytes and end offset, or the error message.
String _outcome((Uint8List, int) Function() inflate) {
  try {
    final (bytes, end) = inflate();
    return 'ok ${bytes.length} ${_digest(bytes)} end $end';
  } on FormatException catch (e) {
    return 'FormatException: ${e.message}';
  }
}

String _digest(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

void main() {
  final random = Random(11);
  final text = utf8.encode(File('LICENSE').readAsStringSync());
  final words = File('test/brotli/words.txt').readAsBytesSync();
  final samples = <String, Uint8List>{
    'empty': Uint8List(0),
    'one byte': Uint8List.fromList([42]),
    'text': Uint8List.fromList(text),
    'words x8': Uint8List.fromList([for (var i = 0; i < 8; i++) ...words]),
    'random': Uint8List.fromList(
      List.generate(100000, (_) => random.nextInt(256)),
    ),
    'zeros': Uint8List(300000),
    'runs': Uint8List.fromList([
      for (var i = 0; i < 200000; i++)
        if (i % 7 == 0) random.nextInt(4) else 0,
    ]),
    'period 300': Uint8List.fromList(
      List.generate(150000, (i) => (i % 300) * 7 & 0xff),
    ),
    'low entropy': Uint8List.fromList(
      List.generate(120000, (_) => 65 + random.nextInt(5)),
    ),
  };

  group('inflate reads what zlib writes', () {
    for (final MapEntry(key: name, value: data) in samples.entries) {
      test(name, () {
        for (final level in [0, 1, 6, 9]) {
          final raw = ZLibCodec(raw: true, level: level).encode(data);
          expect(inflate(raw), data, reason: 'raw, level $level');
          expect(zlibDecode(ZLibCodec(level: level).encode(data)), data);
          expect(gzipDecode(GZipCodec(level: level).encode(data)), data);
        }
        // Small memory levels and windows make more, smaller blocks.
        final small = ZLibCodec(raw: true, memLevel: 1, windowBits: 9);
        expect(inflate(small.encode(data)), data);
        for (final strategy in [
          ZLibOption.strategyFiltered,
          ZLibOption.strategyHuffmanOnly,
          ZLibOption.strategyRle,
          ZLibOption.strategyFixed,
        ]) {
          final codec = ZLibCodec(raw: true, strategy: strategy);
          expect(inflate(codec.encode(data)), data, reason: '$strategy');
        }
      });
    }
  });

  test('zlib reads what deflate writes, inflate too', () {
    for (final data in samples.values) {
      for (final level in [0, 1, 4, 6, 9]) {
        final compressed = deflate(data, level: level);
        expect(ZLibCodec(raw: true).decode(compressed), data);
        expect(inflate(compressed), data);
      }
    }
  });

  test('the end offset is where the stream ends', () {
    for (final data in samples.values) {
      final raw = ZLibCodec(raw: true).encode(data);
      final framed = Uint8List.fromList([9, 9, 9, ...raw, 1, 2, 3, 4, 5]);
      final (bytes, end) = inflateAt(framed, 3);
      expect(bytes, data);
      expect(end, 3 + raw.length);
      expect(end, frozen.inflateAt(framed, 3).$2);
    }
  });

  // Damaged streams: bits flipped, bytes changed, cut short, bytes
  // inserted; whatever the bit-at-a-time decoder made of them, the new one
  // makes too, down to the exception's message.
  test('damaged streams read as the frozen inflater read them', () {
    final sources = <Uint8List>[
      for (final data in [
        samples['text']!,
        samples['words x8']!,
        Uint8List.sublistView(samples['runs']!, 0, 4000),
        Uint8List.sublistView(samples['random']!, 0, 500),
        Uint8List.fromList(utf8.encode('Hello, Hello, Hello!')),
      ]) ...[
        deflate(data),
        ZLibCodec(raw: true, level: 9).encode(data) as Uint8List,
        ZLibCodec(raw: true, strategy: ZLibOption.strategyFixed).encode(data)
            as Uint8List,
        ZLibCodec(
          raw: true,
          strategy: ZLibOption.strategyHuffmanOnly,
        ).encode(data) as Uint8List,
        deflate(data, level: 0),
      ],
    ];
    final outcomes = <String, int>{};
    for (var k = 0; k < 10000; k++) {
      final source = sources[random.nextInt(sources.length)];
      final damaged = Uint8List.fromList(source);
      List<int> stream = damaged;
      switch (random.nextInt(5)) {
        case 0:
          for (var n = 1 + random.nextInt(3); n > 0; n--) {
            final bit = random.nextInt(damaged.length * 8);
            damaged[bit >> 3] ^= 1 << (bit & 7);
          }
        case 1:
          // Damage near the start, where the code lengths are.
          final at = random.nextInt(min(40, damaged.length));
          damaged[at] = random.nextInt(256);
        case 2:
          stream = Uint8List.sublistView(
            damaged,
            0,
            random.nextInt(damaged.length),
          );
        case 3:
          final at = random.nextInt(damaged.length);
          stream = [
            ...damaged.take(at),
            for (var n = 1 + random.nextInt(4); n > 0; n--) random.nextInt(256),
            ...damaged.skip(at),
          ];
        default:
          stream = List.generate(
            1 + random.nextInt(64),
            (_) => random.nextInt(256),
          );
      }
      final bytes = Uint8List.fromList(stream);
      final expected = _outcome(() => frozen.inflateAt(bytes, 0));
      final actual = _outcome(() => inflateAt(bytes, 0));
      expect(actual, expected, reason: 'stream $k: $bytes');
      final kind = expected.startsWith('ok') ? 'ok' : expected;
      outcomes[kind] = (outcomes[kind] ?? 0) + 1;
    }
    // The damage reaches every kind of error.
    expect(
      outcomes.keys,
      containsAll([
        'ok',
        'FormatException: deflate data ended early',
        'FormatException: invalid deflate code',
        'FormatException: distance too far back',
        'FormatException: invalid stored block length',
        'FormatException: invalid deflate block type',
        'FormatException: too many code lengths',
        'FormatException: invalid repeat',
        'FormatException: invalid length code',
      ]),
      reason: '$outcomes',
    );
  });

  test('a long overlapping match and a stored block across the window', () {
    // abc repeated, then 70000 stored bytes, then matches 32768 back.
    final data = Uint8List.fromList([
      for (var i = 0; i < 1000; i++) ...[97, 98, 99],
      for (var i = 0; i < 70000; i++) random.nextInt(256),
      for (var i = 0; i < 5; i++) ...List.generate(40000, (j) => j % 251),
    ]);
    for (final level in [0, 1, 9]) {
      final raw = ZLibCodec(raw: true, level: level).encode(data);
      expect(inflate(raw), data);
    }
  });
}
