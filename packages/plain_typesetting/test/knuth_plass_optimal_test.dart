// The Knuth-Plass line breaker finds the least demerits there are: on
// small random paragraphs, justified or ragged, with lines of one width or
// narrow first lines (an indent, a drop), the demerits of its breaks are
// the least of every way to break them within its tolerance, found by
// trying them all.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

void main() {
  test('the least demerits of every way to break the paragraph', () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
      ),
    );
    final run = TextRun('', TextStyle(font, 10));
    var checked = 0;
    for (var seed = 0; seed < 500; seed++) {
      final random = math.Random(seed);
      final items = <LineItem>[];
      for (var i = 0, n = 4 + random.nextInt(11); i < n; i++) {
        items.add(BoxItem(run, 'word', 8 + random.nextDouble() * 30));
        if (random.nextInt(5) == 0) {
          items
            ..add(BoxItem(run, 'ing', 5 + random.nextDouble() * 10))
            // (A hyphen of no width: a way to the breaks is given up once
            // a line from it is overfull, which a hyphen's width can make
            // it at one break and not at the next.)
            ..add(PenaltyItem(0, 50, flagged: true, run: run));
        }
        items.add(GlueItem(run, ' ', 3, 1.5, 1));
      }
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
      final width = 40 + random.nextDouble() * 80;
      final narrow = random.nextInt(4);
      final cut = 10 + random.nextDouble() * 30;
      double widths(int line) => line < narrow ? width - cut : width;
      final opportunities = [
        for (var i = 0; i < items.length - 1; i++)
          if (switch (items[i]) {
            GlueItem() => i > 0 && items[i - 1] is BoxItem,
            PenaltyItem(:final penalty) => penalty < PenaltyItem.never,
            BoxItem() => false,
          })
            i,
      ];
      for (final breaker in const [
        KnuthPlassLineBreaker(),
        KnuthPlassLineBreaker(raggedStretch: 20),
      ]) {
        var best = double.infinity;
        for (var mask = 0; mask < 1 << opportunities.length; mask++) {
          final breaks = [
            for (var b = 0; b < opportunities.length; b++)
              if (mask & (1 << b) != 0) opportunities[b],
            items.length - 1,
          ];
          best = math.min(best, breaker.demeritsOf(items, widths, breaks));
        }
        // (No way within the tolerance: the later passes, which the
        // demerits here don't count.)
        if (best.isInfinite) continue;
        checked++;
        final found = breaker.breakItems(items, widths);
        expect(
          breaker.demeritsOf(items, widths, found),
          closeTo(best, best * 1e-9),
          reason: 'seed $seed, ragged ${breaker.raggedStretch}',
        );
      }
    }
    expect(checked, greaterThan(200));
  });
}
