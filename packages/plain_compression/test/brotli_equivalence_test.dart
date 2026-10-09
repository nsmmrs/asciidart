// The Brotli decoder against the decoder frozen at 17001e86: the same
// bytes for every stream, and for damaged streams the same
// FormatException, never another error. Streams: the fixtures, and where
// the brotli tool is installed, larger ones it makes at several qualities
// and windows.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:test/test.dart';

import 'frozen/brotli.dart' as frozen;

bool _has(String tool) =>
    Process.runSync('which', [tool]).exitCode == 0 ||
    Process.runSync('where', [tool], runInShell: true).exitCode == 0;

/// What decoding gives: the bytes, or the error message.
String _outcome(Uint8List Function() decode) {
  try {
    final bytes = decode();
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return 'ok ${bytes.length} ${h.toRadixString(16)}';
  } on FormatException catch (e) {
    return 'FormatException: ${e.message}';
  }
}

/// [streams] and damaged copies of them decode as the frozen decoder
/// decodes them.
void _compare(List<Uint8List> streams, Random random, int damaged) {
  for (final stream in streams) {
    expect(brotliDecode(stream), frozen.brotliDecode(stream));
  }
  final errors = <String>{};
  for (var k = 0; k < damaged; k++) {
    final source = streams[random.nextInt(streams.length)];
    final copy = Uint8List.fromList(source);
    var input = copy;
    switch (random.nextInt(4)) {
      case 0:
        for (var n = 1 + random.nextInt(3); n > 0; n--) {
          final bit = random.nextInt(copy.length * 8);
          copy[bit >> 3] ^= 1 << (bit & 7);
        }
      case 1:
        // The header, where the prefix codes are.
        copy[random.nextInt(min(48, copy.length))] = random.nextInt(256);
      case 2:
        input = Uint8List.sublistView(copy, 0, random.nextInt(copy.length));
      default:
        copy[random.nextInt(copy.length)] = random.nextInt(256);
        input = Uint8List.sublistView(copy, 0, random.nextInt(copy.length));
    }
    final expected = _outcome(() => frozen.brotliDecode(input));
    expect(
      _outcome(() => brotliDecode(input)),
      expected,
      reason: 'stream $k: $input',
    );
    errors.add(expected);
  }
  expect(errors.length, greaterThan(5), reason: '$errors');
}

void main() {
  test('the fixtures and damaged copies', () {
    final streams = [
      for (final file in Directory('test/brotli').listSync().whereType<File>())
        if (file.path.endsWith('.br')) file.readAsBytesSync(),
      // "Hello, Brotli!" at quality 11, an empty and a one-byte stream.
      Uint8List.fromList([
        0x8f, 0x06, 0x80, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x42, //
        0x72, 0x6f, 0x74, 0x6c, 0x69, 0x21, 0x03,
      ]),
      Uint8List.fromList([0x3f]),
      Uint8List.fromList([0x0f, 0x00, 0x80, 0x78, 0x03]),
    ];
    _compare(streams, Random(5), 4000);
  });

  test(
    'what the brotli tool makes, and damaged copies',
    () {
      final tmp = Directory.systemTemp.createTempSync('brotli_eq.');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final random = Random(6);
      final source = [
        ...File('lib/src/brotli_data.g.dart').readAsBytesSync().take(40000),
        ...File('test/frozen/flate.dart').readAsBytesSync(),
        for (var i = 0; i < 20000; i++) (i * i ~/ 7 + (i >> 8)) & 0xff,
        for (var i = 0; i < 5000; i++) random.nextInt(256),
        // Bytes as rare as 2^-k: prefix codes up to 15 bits long.
        for (var i = 0; i < 60000; i++)
          random.nextInt(1 << 20).bitLength * 7 + random.nextInt(2),
      ];
      final input = File('${tmp.path}/input')..writeAsBytesSync(source);
      final streams = <Uint8List>[];
      for (final (quality, window) in [
        (0, 16),
        (1, 10),
        (4, 18),
        (6, 12),
        (9, 22),
        (11, 24),
      ]) {
        final output = '${input.path}.$quality.br';
        final run = Process.runSync('brotli', [
          '-f',
          '-q',
          '$quality',
          '-w',
          '$window',
          '-o',
          output,
          input.path,
        ]);
        expect(run.exitCode, 0, reason: '${run.stderr}');
        final stream = File(output).readAsBytesSync();
        expect(brotliDecode(stream), source, reason: 'quality $quality');
        streams.add(stream);
      }
      _compare(streams, random, 300);
    },
    skip: _has('brotli') ? false : 'brotli is not installed',
    tags: ['tools'],
  );
}
