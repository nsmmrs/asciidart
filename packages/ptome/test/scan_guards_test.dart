// The substitutions skip a pass when a cheap check says its pattern cannot
// match. Each check must be a necessary condition: these tests hold it to
// the pattern on random text made of the characters the pattern cares
// about, two-byte letters included.
import 'dart:math';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const List<String> _emailPieces = [
  'a', 'Z', '0', '9', '_', '-', '.', '%', '+', ';', '&amp;', '&', '@', '@', //
  '@@', ' ', '\n', '>', ':', '/', r'\', 'é', 'α', '’', '–', '‍', //
  '́', '😀', 'org', '.org', 'x.io', '.c', '#', '*', '!', '"', "'", '=',
];

const List<String> _literalPieces = [
  'a', 'k', 'l', 'n', ':', '[', ']', '(', ')', '&', ';', 'g', 't', '<', '>', //
  '+', r'$', 's', '@', '-', '.', "'", '"', ' ', '\n', '\x7f', 'é', '’', //
  '😀', 'link:', 'lt;', '&gt;', 'xref', 'ss:', 'dexterm', '((', '))', '--',
];

const List<String> _literals = [
  '((', '))', 'dexterm', '{', '://', 'link:', 'mailto:', 'ilto:', '&lt;&lt;', //
  'xref:', '[', ':', ':[', 'kbd:', 'btn:', 'menu:', '"', '&gt;', 'image:', //
  'icon:', '[[', 'or:', '&', ';&l', 'tnote', '++', r'$$', 'ss:', 'stem:', //
  'math:', '--', '...', '(', '\n', '\x7f', 'é', '’', '😀', 'a’', '’s',
];

String _text(Random random, List<String> pieces, [int max = 24]) => [
  for (var i = random.nextInt(max); i > 0; i--)
    pieces[random.nextInt(pieces.length)],
].join();

void main() {
  test('mayHoldEmail: false only where inlineEmailRx cannot match', () {
    final random = Random(549);
    var held = 0;
    for (var i = 0; i < 200000; i++) {
      final text = _text(random, _emailPieces);
      if (inlineEmailRx.hasMatch(text)) {
        held++;
        expect(
          mayHoldEmail(text),
          isTrue,
          reason: 'in ${Uri.encodeComponent(text)}',
        );
      }
    }
    // The alphabet has to produce addresses for the test to mean anything.
    expect(held, greaterThan(1000));
  });

  test('mayHoldEmail: verse lines starting with "@ " are skipped', () {
    expect(mayHoldEmail('@ In the beginning God created the heaven.'), isFalse);
    expect(mayHoldEmail('@ a’s @ b–c @'), isFalse);
    expect(mayHoldEmail('write to me@example.org'), isTrue);
    expect(mayHoldEmail('ἀ@β'), isTrue);
    for (final short in ['', '@', 'a@', '@b']) {
      expect(mayHoldEmail(short), isFalse);
    }
    expect(mayHoldEmail('a@b'), isTrue);
  });

  test('hasLiteral, literalIndexOf and hasAnyChar: as String.contains', () {
    final random = Random(96);
    final texts = [for (var i = 0; i < 300; i++) _text(random, _literalPieces)];
    for (var i = 0; i < 100000; i++) {
      // Texts asked about in turn and again (the mask is kept for the
      // last one).
      final text = texts[random.nextInt(texts.length)];
      final literal = _literals[random.nextInt(_literals.length)];
      final reason = 'for $literal in ${Uri.encodeComponent(text)}';
      expect(hasLiteral(text, literal), text.contains(literal), reason: reason);
      final start = random.nextInt(text.length + 1);
      expect(
        literalIndexOf(text, literal, start),
        text.indexOf(literal, start),
        reason: '$reason from $start',
      );
      const classChars = "*_`#^~'+&<>([";
      final chars = [
        for (var k = random.nextInt(4) + 1; k > 0; k--)
          classChars[random.nextInt(classChars.length)],
      ].join();
      expect(
        hasAnyChar(text, chars),
        chars.split('').any(text.contains),
        reason: 'for any of $chars in ${Uri.encodeComponent(text)}',
      );
    }
  });

  test('hasReplaceableText: as replaceableTextRx', () {
    const pieces = [
      'a', '-', '--', '.', '..', '(', ')', 'C', 'R', 'T', 'M', '(C)', '(TM', //
      '&', "'", ' ', 'é', '’',
    ];
    final random = Random(909);
    for (var i = 0; i < 50000; i++) {
      final text = _text(random, pieces, 8);
      expect(
        hasReplaceableText(text),
        replaceableTextRx.hasMatch(text),
        reason: 'in ${Uri.encodeComponent(text)}',
      );
    }
  });
}
