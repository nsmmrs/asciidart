// The encoder writes the bytes the encoder frozen at 17001e86 wrote, at
// every level: plain_pdf's byte-exact output and every PDF and EPUB made
// without a native zlib depend on it. Inputs: text and source files,
// synthetic PDF content streams, images and font tables, edge sizes around
// block, window and stored-block limits, and random slices.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_compression/src/flate.dart' show huffmanLengths;
import 'package:test/test.dart';

import 'frozen/flate.dart' as frozen;

/// A page's content stream: text objects with fonts, positions and kerned
/// words, some paths, as a PDF writer makes them.
Uint8List _contentStream(Random random, List<String> words, int size) {
  final out = StringBuffer();
  var y = 760.0;
  while (out.length < size) {
    final font = '/F${1 + random.nextInt(4)} ${8 + random.nextInt(6)} Tf';
    final x = '${72 + random.nextInt(40)}.${random.nextInt(100)}';
    out.write('BT\n$font\n1 0 0 1 $x ${y.toStringAsFixed(2)} Tm\n[');
    for (var k = 3 + random.nextInt(9); k > 0; k--) {
      out.write('(${words[random.nextInt(words.length)]})');
      if (random.nextBool()) out.write('-${random.nextInt(300)}');
    }
    out.write('] TJ\nET\n');
    if (random.nextInt(8) == 0) {
      final at = y.toStringAsFixed(1);
      out.write('q 0.5 w 72 $at m 540 $at l S Q\n');
    }
    y = y < 80 ? 760 : y - 11.5;
  }
  return Uint8List.fromList(utf8.encode(out.toString()));
}

/// RGB pixels: gradients, flat areas and noise.
Uint8List _image(Random random, int width, int height) {
  final pixels = Uint8List(width * height * 3);
  var at = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final flat = (x ~/ 40 + y ~/ 30).isEven;
      for (var c = 0; c < 3; c++) {
        pixels[at++] = flat
            ? 255 - c * 20
            : (x * (c + 1) + y * 2 + random.nextInt(6)) & 0xff;
      }
    }
  }
  return pixels;
}

/// Big-endian 16-bit tables of small numbers, as fonts hold.
Uint8List _fontTables(Random random, int size) {
  final data = ByteData(size & ~1);
  for (var at = 0; at + 2 <= data.lengthInBytes; at += 2) {
    final v = random.nextInt(4) == 0
        ? random.nextInt(65536)
        : 500 + random.nextInt(200) - 100;
    data.setUint16(at, v);
  }
  return data.buffer.asUint8List();
}

void main() {
  final random = Random(2017);
  final words = File('test/brotli/words.txt')
      .readAsStringSync()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final wordList = [...words, 'the', 'of', 'and', 'Hypermedia', 'htmx'];
  Uint8List file(String path) => File(path).readAsBytesSync();
  final samples = <String, Uint8List>{
    for (var n = 0; n <= 9; n++)
      'size $n': Uint8List.fromList(List.generate(n, (i) => 65 + i % 3)),
    'source': Uint8List.fromList([
      ...file('test/frozen/flate.dart'),
      ...file('test/frozen/brotli.dart'),
    ]),
    'generated data': file('lib/src/brotli_data.g.dart'),
    'license': file('LICENSE'),
    'brotli streams': Uint8List.fromList([
      for (final name in ['words.txt.br', 'words-x40-q1.br'])
        ...file('test/brotli/$name'),
    ]),
    'content stream': _contentStream(random, wordList, 120000),
    'small content stream': _contentStream(random, wordList, 3000),
    'image': _image(random, 300, 120),
    'font tables': _fontTables(random, 60000),
    'random': Uint8List.fromList(
      List.generate(80000, (_) => random.nextInt(256)),
    ),
    'zeros': Uint8List(70000),
    'runs of 258 and 259': Uint8List.fromList([
      for (final run in [258, 259, 516, 3, 2, 1, 260]) ...[
        ...List.filled(run, 120),
        ...List.filled(run, 121),
      ],
    ]),
    'low entropy': Uint8List.fromList(
      List.generate(60000, (_) => 97 + random.nextInt(3)),
    ),
    'period 7': Uint8List.fromList(List.generate(50000, (i) => i % 7)),
    // More than 16383 symbols: several blocks, some stored.
    'mixed blocks': Uint8List.fromList([
      ...List.generate(20000, (_) => random.nextInt(256)),
      ...List.generate(40000, (i) => 32 + (i * 7) % 60),
      ...List.generate(30000, (_) => random.nextInt(256)),
    ]),
    // Matches reaching back to the edge of the 32 KiB window.
    'window edge': Uint8List.fromList([
      for (var k = 0; k < 3; k++) ...[
        ...List.generate(32768 - 5 + k, (i) => (i * 31 + k) & 0xff),
      ],
    ]),
  };

  test("every level writes the frozen encoder's bytes", () {
    for (final MapEntry(key: name, value: data) in samples.entries) {
      for (var level = 0; level <= 9; level++) {
        expect(
          deflate(data, level: level),
          frozen.deflate(data, level: level),
          reason: '$name, level $level',
        );
      }
      expect(zlibEncode(data), frozen.zlibEncode(data), reason: name);
      expect(gzipEncode(data), _frozenGzip(data), reason: name);
    }
  });

  test("random slices write the frozen encoder's bytes", () {
    final pool = Uint8List.fromList([
      ...samples['content stream']!,
      ...samples['image']!,
      ...samples['source']!,
      ...samples['font tables']!,
    ]);
    for (var k = 0; k < 60; k++) {
      final length = 1 + random.nextInt(k < 50 ? 20000 : 90000);
      final start = random.nextInt(pool.length - length);
      final slice = Uint8List.sublistView(pool, start, start + length);
      final level = random.nextInt(10);
      expect(
        deflate(slice, level: level),
        frozen.deflate(slice, level: level),
        reason: 'slice $start+$length, level $level',
      );
    }
  });

  test('large inputs at levels 1, 6 and 9', () {
    final large = <Uint8List>[
      _contentStream(random, wordList, 600000),
      _image(random, 640, 400),
    ];
    for (final data in large) {
      for (final level in [1, 6, 9]) {
        expect(
          deflate(data, level: level),
          frozen.deflate(data, level: level),
          reason: '${data.length} bytes, level $level',
        );
      }
    }
  });

  test('a List<int> compresses as its bytes do', () {
    final data = samples['small content stream']!;
    expect(deflate(data.toList()), frozen.deflate(data));
    expect(zlibEncode(data.toList()), frozen.zlibEncode(data));
  });

  test('Huffman code lengths are the frozen ones', () {
    for (var k = 0; k < 3000; k++) {
      final maxBits = [7, 9, 15][random.nextInt(3)];
      // As many symbols as the code length (19) and literal/length (286)
      // alphabets have, at most.
      final n = 2 + random.nextInt(maxBits == 7 ? 18 : 285);
      final zeros = random.nextInt(4);
      final spread = [3, 50, 1000, 16384][random.nextInt(4)];
      final frequencies = List.generate(
        n,
        (_) => random.nextInt(4) < zeros ? 0 : random.nextInt(spread),
      );
      // Skewed frequencies make deep trees, which have to be clipped.
      if (random.nextBool()) {
        for (var s = 0; s < n; s += 1 + random.nextInt(5)) {
          frequencies[s] = 1 << random.nextInt(14);
        }
      }
      expect(
        huffmanLengths(frequencies, maxBits),
        frozen.huffmanLengths(frequencies, maxBits),
        reason: '$frequencies, $maxBits bits',
      );
    }
  });
}

/// gzipEncode as it was at 17001e86: the header, the frozen encoder's
/// stream, the CRC and the size.
Uint8List _frozenGzip(Uint8List data) {
  final crc = crc32(data);
  return Uint8List.fromList([
    0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255, //
    ...frozen.deflate(data),
    for (final value in [crc, data.length])
      for (var shift = 0; shift < 32; shift += 8) (value >> shift) & 0xff,
  ]);
}
