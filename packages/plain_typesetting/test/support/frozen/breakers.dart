// A frozen copy of the Knuth-Plass and Typst line breakers of
// lib/src/layout/paragraph.dart as of 17001e86 (before typed arrays and
// multiplications for math.pow): the oracle the breakers' equivalence test
// compares every break with. Don't change it.
// ignore_for_file: type=lint
import 'dart:math' as math;

import 'package:plain_typesetting/plain_typesetting.dart';

/// The total-fit algorithm of Knuth and Plass ("Breaking paragraphs into
/// lines", 1981): the breaks that minimize the sum of the lines'
/// demerits, so spacing is even across the paragraph.
final class FrozenKnuthPlass {
  /// A Knuth-Plass line breaker; [tolerance] is the largest adjustment
  /// ratio accepted (retried larger when no breaks fit, then falling back
  /// to first fit).
  const new({
    this.tolerance = 2,
    this.linePenalty = 10,
    this.flaggedDemerits = 100,
    this.fitnessDemerits = 100,
  });

  /// The largest stretch ratio of a line.
  final double tolerance;

  /// The demerits of each line.
  final double linePenalty;

  /// The demerits of two hyphenated lines in a row.
  final double flaggedDemerits;

  /// The demerits of adjacent lines in very different fitness classes.
  final double fitnessDemerits;

  List<int> breakItems(List<LineItem> items, LineWidths widths) {
    for (final ratio in [tolerance, tolerance * 5, 100.0]) {
      final breaks = _total(items, widths, ratio);
      if (breaks != null) return breaks;
    }
    return const FirstFitLineBreaker().breakItems(items, widths);
  }

  List<int>? _total(List<LineItem> items, LineWidths widths, double limit) {
    // Running totals of the items before each index.
    final n = items.length;
    final totalWidth = List<double>.filled(n + 1, 0);
    final totalStretch = List<double>.filled(n + 1, 0);
    final totalShrink = List<double>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      final item = items[i];
      totalWidth[i + 1] =
          totalWidth[i] + (item is PenaltyItem ? 0 : item.width);
      totalStretch[i + 1] =
          totalStretch[i] + (item is GlueItem ? item.stretch : 0);
      totalShrink[i + 1] =
          totalShrink[i] + (item is GlueItem ? item.shrink : 0);
    }
    var active = <_Node>[_Node(-1, 0, 1, 0, null, flagged: false, start: 0)];
    for (var i = 0; i < n; i++) {
      final item = items[i];
      final penalty = switch (item) {
        PenaltyItem(:final penalty) when penalty < PenaltyItem.never => penalty,
        GlueItem(:final stretch)
            when i > 0 && items[i - 1] is BoxItem && stretch.isFinite =>
          0.0,
        _ => null,
      };
      if (penalty == null) continue;
      final flagged = item is PenaltyItem && item.flagged;
      final forced = item is PenaltyItem && item.isForced;
      final best = <(int, int), _Node>{};
      final survivors = <_Node>[];
      for (final node in active) {
        final start = node.start;
        var width =
            totalWidth[i] - totalWidth[start] + _carry(items, node.position);
        if (item is PenaltyItem) width += item.width;
        final stretch = totalStretch[i] - totalStretch[start];
        final shrink = totalShrink[i] - totalShrink[start];
        final available = widths(node.line);
        final double ratio;
        if (width < available - _epsilon) {
          ratio = stretch > 0 ? (available - width) / stretch : double.infinity;
        } else if (width > available + _epsilon) {
          ratio = shrink > 0
              ? (available - width) / shrink
              : double.negativeInfinity;
        } else {
          ratio = 0;
        }
        if (ratio >= -1 && !forced) survivors.add(node);
        if (ratio < -1 || ratio > limit) continue;
        final badness = 100 * math.pow(ratio.abs(), 3);
        var demerits = math.pow(linePenalty + badness, 2).toDouble();
        if (penalty >= 0) {
          demerits += penalty * penalty;
        } else if (penalty > PenaltyItem.forced) {
          demerits -= penalty * penalty;
        }
        if (flagged && node.flagged) demerits += flaggedDemerits;
        final fitness = ratio < -0.5
            ? 0
            : ratio <= 0.5
            ? 1
            : ratio <= 1
            ? 2
            : 3;
        if ((fitness - node.fitness).abs() > 1) demerits += fitnessDemerits;
        final total = node.demerits + demerits;
        final key = (fitness, node.line + 1);
        if (best[key] == null || total < best[key]!.demerits) {
          best[key] = _Node(
            i,
            node.line + 1,
            fitness,
            total,
            node,
            flagged: flagged,
            start: _skipDiscardable(items, i + 1),
          );
        }
      }
      active = [...survivors, ...best.values];
      if (active.isEmpty) return null;
    }
    final finals = active.where((node) => node.position == n - 1);
    if (finals.isEmpty) return null;
    var node = finals.reduce((a, b) => a.demerits <= b.demerits ? a : b);
    final breaks = <int>[];
    for (_Node? at = node; at != null && at.position >= 0; at = at.previous) {
      breaks.add(at.position);
      node = at;
    }
    return breaks.reversed.toList();
  }
}

/// The letters at the start of a text.
final RegExp _leadingLetters = RegExp(r'\p{Alphabetic}*', unicode: true);

/// Typst's line breaking (typst-layout's `inline/linebreak.rs`, as of
/// v0.14): the breaks that minimize the sum of the lines' costs, each line
/// costing (1 + badness + penalty)². A line's badness is 100·|ratio|³,
/// its ratio how far its spaces stretch or shrink (past their stretch,
/// the rest spread over its spaces in half-ems); a line too full costs a
/// million rather than being refused. Ragged lines ([justify] false) may
/// not shrink, and the last line (before a forced break) costs only what
/// it shrinks. Penalties: a hyphenation [hyphenationCost] (15% more for
/// letter closer than five to the word's edge), two lines in a
/// row ending in a dash [hyphenationCost] more, a lone word on a line
/// before a forced break (a runt) [runtCost]. A penalty item's own
/// positive cost is added to its line's.
final class FrozenTypst {
  /// A breaker for text set in [fontSize] points, justified or not.
  const new({
    this.justify = true,
    this.fontSize = 10,
    this.hyphenationCost = 135,
    this.runtCost = 100,
  });

  /// Whether the lines are justified (their spaces may shrink).
  final bool justify;

  /// The size of the text: stretch past the spaces' counts in half of it.
  final double fontSize;

  /// The cost of ending a line with a hyphenation.
  final double hyphenationCost;

  /// The cost of a lone word on the last line.
  final double runtCost;

  List<int> breakItems(List<LineItem> items, LineWidths widths) {
    final n = items.length;
    if (n == 0) return const [];
    // Running totals of the items before each index; infinite stretch (a
    // fill) counted apart.
    final width = List<double>.filled(n + 1, 0);
    final stretch = List<double>.filled(n + 1, 0);
    final shrink = List<double>.filled(n + 1, 0);
    final fills = List<int>.filled(n + 1, 0);
    final spaces = List<int>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      final item = items[i];
      width[i + 1] = width[i] + (item is PenaltyItem ? 0 : item.width);
      final infinite = item is GlueItem && !item.stretch.isFinite;
      stretch[i + 1] =
          stretch[i] + (item is GlueItem && !infinite ? item.stretch : 0);
      shrink[i + 1] = shrink[i] + (item is GlueItem ? item.shrink : 0);
      fills[i + 1] = fills[i] + (infinite ? 1 : 0);
      // (Justifiable spaces: not a fixed space, which never stretches.)
      spaces[i + 1] =
          spaces[i] +
          (item is GlueItem && !infinite && item.stretch > 0 ? 1 : 0);
    }
    bool candidate(int i) => switch (items[i]) {
      PenaltyItem(:final penalty) => penalty < PenaltyItem.never,
      GlueItem(stretch: final s) =>
        i > 0 && items[i - 1] is BoxItem && s.isFinite,
      BoxItem() => false,
    };
    final minRatio = justify ? -1.0 : 0.0;
    final entries = <_TypstEntry>[_TypstEntry(-1, 0, 0, 0, null, dash: false)];
    var active = 0;
    var previous = -1;
    for (var i = 0; i < n; i++) {
      if (!candidate(i)) continue;
      final item = items[i];
      final forced = item is PenaltyItem && item.isForced;
      final hyphen = item is PenaltyItem && item.flagged;
      // The line's end without the spaces before the break.
      var end = i;
      while (end > 0 && items[end - 1] is GlueItem) {
        end--;
      }
      var lastBox = end - 1;
      while (lastBox >= 0 && items[lastBox] is! BoxItem) {
        lastBox--;
      }
      final dash =
          hyphen ||
          (lastBox >= 0 && (items[lastBox] as BoxItem).text.endsWith('-'));
      // The letters of the word on each side of a hyphenation (not the
      // punctuation around it: Typst hyphenates "beyond" in “beyond”).
      double hyphenPenalty() {
        final before = StringBuffer();
        for (var k = i - 1; k >= 0 && items[k] is! GlueItem; k--) {
          if (items[k] case BoxItem(:final text)) {
            before.write(String.fromCharCodes(text.runes.toList().reversed));
          }
        }
        final after = StringBuffer();
        for (var k = i + 1; k < n && items[k] is! GlueItem; k++) {
          if (items[k] case BoxItem(:final text)) after.write(text);
        }
        int letters(String text) =>
            _leadingLetters.matchAsPrefix(text)?[0]?.runes.length ?? 0;
        // (Counted in code points.)
        final left = letters(before.toString());
        final right = letters(after.toString());
        final steps = math.max(0, 5 - left) + math.max(0, 5 - right);
        return (1 + 0.15 * steps) * hyphenationCost;
      }

      // (The same for every line ending here: computed once.)
      double? hyphenCost;
      _TypstEntry? best;
      for (var k = active; k < entries.length; k++) {
        final pred = entries[k];
        final start = pred.start;
        if (start > end) continue;
        var w = width[end] - width[start] + _carry(items, pred.position);
        if (item is PenaltyItem) w += item.width;
        final available = widths(pred.line);
        final infinite = fills[end] - fills[start] > 0;
        final ratio = _ratio(
          available - w,
          infinite ? double.infinity : stretch[end] - stretch[start],
          shrink[end] - shrink[start],
          spaces[end] - spaces[start],
        );
        final double badness;
        if (ratio < minRatio) {
          badness = 1000000;
        } else if (!forced || ratio < 0) {
          badness = 100 * math.pow(ratio.abs(), 3).toDouble();
        } else {
          badness = 0;
        }
        var penalty = 0.0;
        // A lone word: no break opportunity between the line's start and
        // its end.
        if (forced && pred.position == previous) penalty += runtCost;
        if (hyphen) penalty += hyphenCost ??= hyphenPenalty();
        if (dash && pred.dash) penalty += hyphenationCost;
        // A break's own cost (none of Typst's: a break between the
        // characters of a word too long for a line, say).
        if (item case PenaltyItem(penalty: final p)
            when !forced && !hyphen && p > 0) {
          penalty += p;
        }
        final cost = math.pow(1 + badness + penalty, 2).toDouble();
        if (ratio < minRatio && active == k) active++;
        final total = pred.total + cost;
        if (best == null || best.total >= total) {
          best = _TypstEntry(
            i,
            _skipDiscardable(items, i + 1),
            pred.line + 1,
            total,
            pred,
            dash: dash,
          );
        }
      }
      if (best != null) {
        entries.add(best);
        // Nothing breaks across a forced break.
        if (forced) active = entries.length - 1;
      }
      previous = i;
    }
    final breaks = <int>[];
    for (
      _TypstEntry? at = entries.last;
      at != null && at.position >= 0;
      at = at.previous
    ) {
      breaks.add(at.position);
    }
    return breaks.reversed.toList();
  }

  /// How far a line's spaces stretch (positive) or shrink (negative) to
  /// fill [rawDelta], Typst's `raw_ratio`.
  double _ratio(double rawDelta, double stretch, double shrink, int spaces) {
    final delta = rawDelta.abs() < 1e-9 ? 0.0 : rawDelta;
    final adjustability = math.max<double>(0, delta >= 0 ? stretch : shrink);
    var ratio = delta / adjustability;
    if (ratio.isNaN) ratio = 0;
    if (ratio > 1) {
      final extra = (delta - adjustability) / math.max(spaces, 1);
      ratio = 1 + extra / (fontSize / 2);
    }
    return ratio.clamp(-2.0, 10.0);
  }
}

final class _TypstEntry {
  new(
    this.position,
    this.start,
    this.line,
    this.total,
    this.previous, {
    required this.dash,
  });

  /// The item the line breaks at (-1 for the paragraph's start).
  final int position;

  /// The item the next line starts at.
  final int start;

  /// The number of lines up to this break.
  final int line;

  /// The cost of the lines up to this break.
  final double total;

  /// The break before.
  final _TypstEntry? previous;

  /// Whether the line ends with a dash (a hyphen).
  final bool dash;
}

final class _Node {
  new(
    this.position,
    this.line,
    this.fitness,
    this.demerits,
    this.previous, {
    required this.flagged,
    required this.start,
  });

  /// The item the break is at (-1 for the start of the paragraph).
  final int position;

  /// The number of lines before the break.
  final int line;

  final int fitness;
  final double demerits;
  final _Node? previous;
  final bool flagged;

  /// The first item of the line after the break.
  final int start;
}

const double _epsilon = 1e-6;

/// The width of the hyphen a line starts with after a break at [at] (see
/// [PenaltyItem.carry]); 0 at the paragraph's start.
double _carry(List<LineItem> items, int at) =>
    switch (at >= 0 ? items[at] : null) {
      PenaltyItem(:final carry) => carry,
      _ => 0,
    };

/// The first index from [start] that isn't glue or a penalty that
/// doesn't force a break (what a line break discards).
int _skipDiscardable(List<LineItem> items, int start) {
  var i = start;
  while (i < items.length &&
      (items[i] is GlueItem ||
          (items[i] is PenaltyItem && !(items[i] as PenaltyItem).isForced))) {
    i++;
  }
  return i;
}
