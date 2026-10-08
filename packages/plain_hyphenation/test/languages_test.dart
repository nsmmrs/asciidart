// The embedded patterns: every language decodes to the vendored hyph-utf8
// files exactly, tags and aliases find their patterns, and known words
// hyphenate as TeX hyphenates them.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart' show brotliDecode;
import 'package:plain_hyphenation/plain_hyphenation.dart';
import 'package:plain_hyphenation/src/patterns.g.dart';
import 'package:test/test.dart';

String _hyphenated(String language, String word) {
  final points = hyphenatorFor(language)!.hyphenate(word);
  final runes = word.runes.toList();
  return [
    for (var i = 0; i < runes.length; i++)
      '${points.contains(i) ? '-' : ''}${String.fromCharCode(runes[i])}',
  ].join();
}

void main() {
  test('72 languages, each decoding to its vendored files', () {
    expect(hyphenationLanguages, hasLength(72));
    final families = <String, Uint8List>{};
    for (final MapEntry(key: tag, value: entry)
        in hyphenationPatterns.entries) {
      final (_, _, family, at, length, exceptionsAt, exceptionsLength) = entry;
      final text = families.putIfAbsent(
        family,
        () => brotliDecode(base64Decode(patternFamilies[family]!)),
      );
      List<int> slice(int start, int length) =>
          Uint8List.sublistView(text, start, start + length);
      final patterns = File('vendor/hyph-utf8/patterns/$tag.pat.txt');
      final exceptions = File('vendor/hyph-utf8/patterns/$tag.hyp.txt');
      expect(slice(at, length), patterns.readAsBytesSync(), reason: tag);
      expect(
        slice(exceptionsAt, exceptionsLength),
        exceptions.existsSync() ? exceptions.readAsBytesSync() : <int>[],
        reason: tag,
      );
    }
  });

  test('tags, aliases and primary languages', () {
    expect(patternTag('en'), 'en-us');
    expect(patternTag('en_US'), 'en-us');
    expect(patternTag('EN-gb'), 'en-gb');
    expect(patternTag('de'), 'de-1996');
    expect(patternTag('de-AT'), 'de-1996');
    expect(patternTag('pt-BR'), 'pt');
    expect(patternTag('sr'), 'sh-cyrl');
    expect(patternTag('xx'), isNull);
    expect(hyphenatorFor('xx'), isNull);
    expect(identical(hyphenatorFor('en'), hyphenatorFor('en-us')), isTrue);
  });

  test('known words hyphenate as TeX hyphenates them', () {
    expect(_hyphenated('en', 'hyphenation'), 'hy-phen-ation');
    expect(_hyphenated('en', 'algorithm'), 'al-go-rithm');
    expect(_hyphenated('en', 'associate'), 'as-so-ciate'); // an exception
    expect(_hyphenated('de', 'Silbentrennung'), 'Sil-ben-tren-nung');
    expect(
      _hyphenated('fr', 'anticonstitutionnellement'),
      'an-ti-cons-ti-tu-tion-nel-le-ment',
    );
  });
}
