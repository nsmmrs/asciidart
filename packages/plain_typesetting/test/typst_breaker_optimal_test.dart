// The Typst line breaker finds the best breaks there are where line
// widths vary (an indent, a drop's lines, a runaround; BUG-1cks79): on
// small random paragraphs that can be set without an overfull line, the
// cost of its breaks is the least of every way to break them, found by
// trying them all.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

void main() {
  test('the least cost of every way to break the paragraph', () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
      ),
    );
    final run = TextRun('', TextStyle(font, 10));
    var checked = 0;
    for (var seed = 0; seed < 400; seed++) {
      final random = math.Random(seed);
      final items = <LineItem>[];
      for (var i = 0, n = 4 + random.nextInt(11); i < n; i++) {
        items.add(BoxItem(run, 'word', 8 + random.nextDouble() * 30));
        if (random.nextInt(5) == 0) {
          items
            ..add(BoxItem(run, 'ing', 5 + random.nextDouble() * 10))
            // (A hyphen of no width: Typst stops trying a way to the
            // breaks once a line from it is overfull, which a hyphen's
            // width can make it at one break and not at the next.)
            ..add(PenaltyItem(0, 50, flagged: true, run: run));
        }
        items.add(GlueItem(run, ' ', 3, 1.5, 1));
      }
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
      // Narrow first lines (a drop), then the column's width.
      final width = 40 + random.nextDouble() * 80;
      final narrow = 1 + random.nextInt(3);
      final cut = 10 + random.nextDouble() * 30;
      double widths(int line) => line < narrow ? width - cut : width;
      for (final justify in [true, false]) {
        final breaker = TypstLineBreaker(justify: justify);
        final found = breaker.breakItems(items, widths);
        // Every way: each subset of the break opportunities, with the
        // paragraph's end.
        final opportunities = [
          for (var i = 0; i < items.length - 1; i++)
            if (switch (items[i]) {
              GlueItem() => i > 0 && items[i - 1] is BoxItem,
              PenaltyItem(:final penalty) => penalty < PenaltyItem.never,
              BoxItem() => false,
            })
              i,
        ];
        var best = double.infinity;
        for (var mask = 0; mask < 1 << opportunities.length; mask++) {
          final breaks = [
            for (var b = 0; b < opportunities.length; b++)
              if (mask & (1 << b) != 0) opportunities[b],
            items.length - 1,
          ];
          best = math.min(best, breaker.costOf(items, widths, breaks));
        }
        // (Where a line can't help being overfull, the breaker gives up
        // on the ways through it, as Typst does: no promise there.)
        if (best >= _overfull) continue;
        checked++;
        expect(
          breaker.costOf(items, widths, found),
          closeTo(best, best * 1e-9),
          reason: 'seed $seed, justify $justify',
        );
      }
    }
    expect(checked, greaterThan(300));
  });
}

/// The cost of a paragraph with an overfull line (badness 1000000,
/// squared).
const double _overfull = 1000000000000;
