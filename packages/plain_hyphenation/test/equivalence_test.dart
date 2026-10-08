// The trie hyphenates every word as the algorithm it replaced does
// (test/reference_liang.dart), in all 72 languages: the hyphenator the
// package loads from its compiled patterns and the one built from the
// vendored text, on words made from the patterns (each pattern's letters,
// two patterns joined), random words over the language's letters with
// some characters that aren't, the exceptions, the UDHR's words where
// there are some, all in mixed case too.
//
// The words are random but seeded, so a run is repeatable. Setting
// PLAIN_HYPHENATION_EQUIVALENCE_SCALE to a number multiplies how many
// there are of each kind (and changes the seed), for longer runs than CI's.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:plain_hyphenation/plain_hyphenation.dart';
import 'package:test/test.dart';

import 'reference_liang.dart';

/// Characters that are no language's letters, or change as words are
/// lowercased: a capital I with a dot (two characters in lower case), a
/// capital sharp s, sigma, a titlecase digraph, a ligature, astral and
/// lone surrogate characters, dots, hyphens and digits.
const List<String> _strangers = [
  '.', '-', '1', '9', ' ', 'İ', 'ẞ', 'Σ', 'ς', 'ǅ', 'ﬁ', '\u{1F600}', //
  '\u{1D400}', '\uD800', '\uDC00', '́', '‍', 'ı', 'K', 'Å',
];

final int _scale =
    int.tryParse(
      Platform.environment['PLAIN_HYPHENATION_EQUIVALENCE_SCALE'] ?? '',
    ) ??
    1;

void main() {
  for (final tag in hyphenationLanguages) {
    test('$tag: the same breaks as the reference', () {
      final random = math.Random(tag.hashCode ^ _scale);
      final patterns = File('vendor/hyph-utf8/patterns/$tag.pat.txt')
          .readAsStringSync();
      final exceptionsFile = File('vendor/hyph-utf8/patterns/$tag.hyp.txt');
      final exceptions = exceptionsFile.existsSync()
          ? exceptionsFile.readAsStringSync()
          : '';
      final compiled = hyphenatorFor(tag)!;
      final (left, right) = (compiled.left, compiled.right);
      final reference = ReferenceHyphenator(
        patterns,
        exceptions: exceptions,
        left: left,
        right: right,
      );
      final parsed = PatternHyphenator(
        patterns,
        exceptions: exceptions,
        left: left,
        right: right,
      );

      final tokens = patterns.split(RegExp(r'\s+'))
        ..removeWhere((t) => t.isEmpty);
      final pieces = [
        for (final t in tokens) t.replaceAll(RegExp('[0-9]'), ''),
      ];
      final letters = {for (final p in pieces) ...p.replaceAll('.', '').runes}
          .map(String.fromCharCode)
          .toList();
      String any(List<String> list) => list[random.nextInt(list.length)];
      final count = 300 * _scale;
      final words = <String>[
        for (var i = 0; i < count; i++) any(pieces).replaceAll('.', ''),
        for (var i = 0; i < count; i++)
          (any(pieces) + any(pieces)).replaceAll('.', ''),
        // Patterns with their dots, where a word has them only as letters.
        for (var i = 0; i < count ~/ 10; i++) any(pieces) + any(pieces),
        for (var i = 0; i < count; i++)
          [
            for (var k = 1 + random.nextInt(16); k > 0; k--)
              if (random.nextInt(12) == 0) any(_strangers) else any(letters),
          ].join(),
        for (final e in exceptions.split(RegExp(r'\s+')))
          if (e.isNotEmpty) e.replaceAll('-', ''),
        // Longer than the scratch buffers start.
        for (var i = 0; i < 3; i++)
          [for (var k = 0; k < 70 + i * 50; k++) any(letters)].join(),
        if (File('test/fixtures/words/$tag.txt') case final udhr
            when udhr.existsSync())
          ...udhr.readAsLinesSync().take(count),
      ];
      String mixed(String word) {
        if (word.isEmpty) return word;
        return switch (random.nextInt(3)) {
          0 => word.toUpperCase(),
          1 => word[0].toUpperCase() + word.substring(1),
          _ => [
            for (final rune in word.runes)
              if (random.nextBool())
                String.fromCharCode(rune).toUpperCase()
              else
                String.fromCharCode(rune),
          ].join(),
        };
      }

      final differ = <String>[];
      for (final word in [...words, ...words.map(mixed)]) {
        final expected = reference.hyphenate(word).toString();
        for (final (name, hyphenator) in [
          ('compiled', compiled),
          ('parsed', parsed),
        ]) {
          final actual = hyphenator.hyphenate(word).toString();
          if (actual != expected && differ.length < 20) {
            differ.add('$name "$word": $actual, not $expected');
          }
        }
      }
      expect(differ, isEmpty);
      expect(compiled.isEmpty, reference.isEmpty);
    });
  }

  test('patterns of any shape, as the reference has them', () {
    for (final (patterns, exceptions) in [
      ('', ''),
      ('1', ''), // a pattern without letters
      ('a', ''), // and one without digits
      ('', 'ex-cep-tion'),
      ('a1b a3b 2b1 % comment', ''), // the last of the same letters wins
      ('.a1b b1c. 1.1', ''),
      ('\u{1F600}1\u{1F600} 1\uD800', ''),
    ]) {
      final reference = ReferenceHyphenator(
        patterns,
        exceptions: exceptions,
        left: 1,
        right: 1,
      );
      final ours = PatternHyphenator(
        patterns,
        exceptions: exceptions,
        left: 1,
        right: 1,
      );
      expect(ours.isEmpty, reference.isEmpty, reason: patterns);
      for (final word in [
        'ab', 'abc', 'abab', 'a.b', 'exception', 'Exception', //
        '\u{1F600}\u{1F600}\u{1F600}', 'x\uD800y', 'aaaa',
      ]) {
        expect(
          ours.hyphenate(word),
          reference.hyphenate(word),
          reason: '$patterns: $word',
        );
      }
    }
  });
}
