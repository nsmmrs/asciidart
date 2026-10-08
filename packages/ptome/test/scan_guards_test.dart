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
}
