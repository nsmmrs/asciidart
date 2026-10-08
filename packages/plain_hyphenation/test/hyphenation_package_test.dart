// plain_hyphenation against pub.dev's hyphenation package (another Dart
// implementation of Liang's algorithm), given the same vendored patterns,
// exceptions and hyphenmins: the same breaks for every word of the
// Universal Declaration of Human Rights in 19 languages
// (test/fixtures/words).
@TestOn('vm')
library;

import 'dart:io';

import 'package:hyphenation/hyphenation.dart' as other;
import 'package:plain_hyphenation/plain_hyphenation.dart';
import 'package:plain_hyphenation/src/patterns.g.dart';
import 'package:test/test.dart';

const List<String> _languages = [
  'en-us', 'de-1996', 'fr', 'es', 'it', 'nl', 'pt', 'sv', 'pl', 'ru', //
  'fi', 'da', 'tr', 'uk', 'ca', 'hr', 'sk', 'sl', 'nb',
];

void main() {
  for (final tag in _languages) {
    test('$tag: the same breaks as package:hyphenation', () {
      const dir = 'vendor/hyph-utf8/patterns';
      final exceptions = File('$dir/$tag.hyp.txt');
      final (left, right, _, _, _, _, _) = hyphenationPatterns[tag]!;
      // The pattern table's own hyphenmins are floors under the
      // hyphenator's (TeX's English 2 and 3 by default): the language's.
      final theirs = other.Hyphenator(
        other.TexHyphenationPatterns.parse(
          '\\patterns{\n${File('$dir/$tag.pat.txt').readAsStringSync()}\n}\n'
          '${exceptions.existsSync() ? '\\hyphenation{\n'
                    '${exceptions.readAsStringSync()}\n}\n' : ''}',
          leftMin: left,
          rightMin: right,
        ),
        leftMin: left,
        rightMin: right,
        minWordLength: 1,
      );
      final ours = hyphenatorFor(tag)!;
      final differ = <String>[];
      final words = File('test/fixtures/words/$tag.txt')
          .readAsLinesSync()
          .where((w) => w.isNotEmpty);
      for (final word in words) {
        final points = ours.hyphenate(word);
        final runes = word.runes.toList();
        final mine = [
          for (var i = 0; i < runes.length; i++)
            '${points.contains(i) ? '-' : ''}${String.fromCharCode(runes[i])}',
        ].join();
        final other = theirs.split(word).join('-');
        if (mine != other) differ.add('$mine / $other');
      }
      expect(differ, isEmpty);
    });
  }
}
