// The Typst and Knuth-Plass line breakers against frozen copies of them
// (test/support/frozen/breakers.dart): typed arrays, cached line widths
// and multiplications for math.pow may not move a single break, on real
// paragraphs and on random item lists.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/frozen/breakers.dart';

const _genesis =
    'In the beginning God created the heaven and the earth. And the earth was '
    'without form, and void; and darkness was upon the face of the deep.';
const _long =
    'Incomprehensibilities notwithstanding, the well-known co-operation of '
    'twenty-one “quoted” extraordinarily long-winded words—with dashes—ends.';
const List<String> _texts = [
  _genesis,
  _long,
  'a b c d e f g h i j k l m n o p q r s t u v w x y z',
  'Supercalifragilisticexpialidocious antidisestablishmentarianism.',
  'Short.\nLines\nwith\nbreaks and then a longer one that has to wrap.',
];

/// Hyphenates words of five letters or more every second letter.
final class _EverySecond implements Hyphenator {
  const new();

  @override
  List<int> hyphenate(String word) => [
    if (word.length >= 5)
      for (var i = 2; i < word.length - 1; i += 2) i,
  ];
}

/// A random paragraph's items: words and spaces, now and then a
/// hyphenation or a hard break.
List<LineItem> _randomText(math.Random random, TextRun run) {
  final items = <LineItem>[];
  for (var i = 0, n = 5 + random.nextInt(150); i < n; i++) {
    items.add(BoxItem(run, 'w', 5 + random.nextDouble() * 30));
    if (random.nextInt(6) == 0) {
      items
        ..add(BoxItem(run, 'ord', 5 + random.nextDouble() * 10))
        ..add(PenaltyItem(3, 50, flagged: true, run: run));
    }
    if (random.nextInt(40) == 0) {
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
    } else {
      items.add(GlueItem(run, ' ', 3, 1.5, 1));
    }
  }
  return items
    ..add(const GlueItem.fill())
    ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
}

/// Random items: boxes of words (some ending in a hyphen or punctuation),
/// spaces, fixed spaces and fills, and penalties of every kind.
List<LineItem> _randomItems(math.Random random, TextRun run) {
  const words = ['word', 'a', 'end.', 'co-', 'beyond', '“it”', 'x1', 'éé'];
  final items = <LineItem>[];
  for (var i = 0, n = 1 + random.nextInt(120); i < n; i++) {
    final w = 2 + random.nextDouble() * 40;
    switch (random.nextInt(12)) {
      case 0 || 1 || 2 || 3 || 4:
        items.add(BoxItem(run, words[random.nextInt(words.length)], w));
      case 5 || 6:
        items.add(GlueItem(run, ' ', 3, random.nextBool() ? 1.5 : 0, 1));
      case 7:
        items.add(PenaltyItem(4, 50, flagged: true, run: run));
      case 8:
        items.add(PenaltyItem(0, random.nextBool() ? 0 : 1000, run: run));
      case 9:
        items.add(PenaltyItem(0, -random.nextInt(200).toDouble(), run: run));
      case 10:
        items.add(PenaltyItem(0, 0, run: run, carry: 4));
      default:
        items
          ..add(const GlueItem.fill())
          ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
    }
  }
  return items
    ..add(const GlueItem.fill())
    ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
}

void main() {
  final font = OpenTypeShaper(
    OpenTypeFont.parse(
      File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
    ),
  );
  final run = TextRun('', TextStyle(font, 10));

  void same(List<LineItem> items, LineWidths widths, String label) {
    for (final justify in [true, false]) {
      for (final size in [9.0, 10.5]) {
        expect(
          TypstLineBreaker(
            justify: justify,
            fontSize: size,
          ).breakItems(items, widths),
          FrozenTypst(
            justify: justify,
            fontSize: size,
          ).breakItems(items, widths),
          reason: 'Typst, $label',
        );
      }
    }
    for (final tolerance in [1.0, 2.0, 5.0]) {
      expect(
        KnuthPlassLineBreaker(tolerance: tolerance).breakItems(items, widths),
        FrozenKnuthPlass(tolerance: tolerance).breakItems(items, widths),
        reason: 'Knuth-Plass, $label',
      );
    }
  }

  test('paragraphs broken as before', () {
    for (final (k, text) in _texts.indexed) {
      for (final align in [TextAlign.justify, TextAlign.left]) {
        final paragraph = Paragraph(
          [TextRun(text, TextStyle(font, 10))],
          align: align,
          hyphenator: const _EverySecond(),
        );
        for (final width in [40.0, 90.0, 150.0, 300.0]) {
          final items = paragraphItems(paragraph, maxWidth: width);
          same(items, (_) => width, 'text $k at $width');
          same(
            items,
            (line) => line.isEven ? width : width * 0.7,
            'text $k at $width, alternating',
          );
        }
      }
    }
  });

  test('random items broken as before', () {
    for (var seed = 0; seed < 1500; seed++) {
      final random = math.Random(seed);
      final items = seed % 3 == 0
          ? _randomItems(random, run)
          : _randomText(random, run);
      final width = 20 + random.nextDouble() * 200;
      same(
        items,
        seed.isEven ? (_) => width : (line) => width + 7 * (line % 3),
        'seed $seed',
      );
    }
  });
}
