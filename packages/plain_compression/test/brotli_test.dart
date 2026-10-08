// Brotli streams the brotli tool made (fixtures, made as test/brotli's
// README says), and, where the tool is installed, round trips through it
// at every quality; damaged streams are rejected.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:test/test.dart';

bool _has(String tool) =>
    Process.runSync('which', [tool]).exitCode == 0 ||
    Process.runSync('where', [tool], runInShell: true).exitCode == 0;

Uint8List _read(String path) => File(path).readAsBytesSync();

void main() {
  group('Brotli', () {
    final words = _read('test/brotli/words.txt');
    test('static dictionary words and their transforms', () {
      expect(brotliDecode(_read('test/brotli/words.txt.br')), words);
    });

    test('a small window, and a fast quality', () {
      final repeated = [for (var i = 0; i < 40; i++) ...words];
      expect(brotliDecode(_read('test/brotli/words-x40-w10.br')), repeated);
      expect(brotliDecode(_read('test/brotli/words-x40-q1.br')), repeated);
    });

    test('empty and one-byte streams', () {
      expect(brotliDecode([0x3f]), isEmpty);
      expect(brotliDecode([0x0f, 0x00, 0x80, 0x78, 0x03]), [0x78]);
    });

    test('malformed streams throw FormatExceptions', () {
      final stream = _read('test/brotli/words.txt.br');
      expect(
        () => brotliDecode(stream.sublist(0, stream.length ~/ 2)),
        throwsFormatException,
      );
      final random = Random(1);
      for (var i = 0; i < 300; i++) {
        final bytes = [...stream];
        bytes[random.nextInt(bytes.length)] ^= 1 << random.nextInt(8);
        try {
          brotliDecode(bytes);
        } on FormatException {
          // Expected (unless the flip still makes a stream).
        }
      }
    });

    test(
      'decodes what the brotli tool makes, at every quality',
      () {
        final tmp = Directory.systemTemp.createTempSync('brotli_test.');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final random = Random(2);
        final inputs = {
          'words': utf8.encode(
            [
              for (var i = 0; i < 3000; i++)
                const ['the', 'The', 'time', 'world', 'Hello', '"', '.'][random
                    .nextInt(7)],
            ].join(' '),
          ),
          'random': [for (var i = 0; i < 70000; i++) random.nextInt(256)],
          // Structured binary data.
          'binary': [
            for (var i = 0; i < 60000; i++) (i * i ~/ 7 + (i >> 8)) & 0xff,
          ],
        };
        for (final MapEntry(key: name, value: data) in inputs.entries) {
          final input = File('${tmp.path}/$name')..writeAsBytesSync(data);
          for (final (quality, window) in [
            (0, 16),
            (2, 10),
            (5, 18),
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
            expect(
              brotliDecode(_read(output)),
              data,
              reason: '$name at quality $quality',
            );
          }
        }
      },
      skip: _has('brotli') ? false : 'brotli is not installed',
      tags: ['tools'],
    );
  });

  test('damaged streams are decoded or rejected with FormatExceptions', () {
    final random = Random(20261006);
    for (final file in Directory('test/brotli').listSync().whereType<File>()) {
      if (!file.path.endsWith('.br')) continue;
      final bytes = file.readAsBytesSync();
      for (var i = 0; i < 400; i++) {
        final copy = Uint8List.fromList(bytes);
        for (var k = 0; k < 1 + random.nextInt(8); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        final input = i.isEven
            ? copy
            : Uint8List.sublistView(copy, 0, random.nextInt(copy.length));
        try {
          brotliDecode(input);
        } on FormatException {
          // Rejected, as it should be (or decoded: a flip can still make a
          // stream).
        }
      }
    }
  });
}
