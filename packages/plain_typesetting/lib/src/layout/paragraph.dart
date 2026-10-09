/// Paragraphs broken into lines: inline content becomes the boxes, glue
/// and penalties of Knuth and Plass's model, break opportunities come from
/// UAX #14, and a `LineBreaker` strategy chooses the breaks (first fit and
/// Knuth-Plass are provided). Lines are then aligned, measured and
/// painted.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/geometry.dart';
import 'package:plain_typesetting/src/layout/inline.dart';
import 'package:plain_typesetting/src/link.dart';
import 'package:plain_unicode/plain_unicode.dart'
    show LineBreakClass, lineBreakClass, lineBreakOffsets;

/// How the lines of a paragraph are spaced.
@immutable
sealed class LineHeight {
  const new _();

  /// The fonts' height (ascender to descender, plus their line gap) and
  /// [leading] more.
  const factory font({double leading}) = FontLineHeight;

  /// [factor] times the largest font size on the line, the extra split
  /// above and below the text (as CSS does).
  const factory multiple(double factor) = MultipleLineHeight;

  /// [points] per line.
  const factory exact(double points) = ExactLineHeight;
}

/// Lines as tall as their fonts, plus leading.
final class FontLineHeight extends LineHeight {
  /// The fonts' height plus [leading].
  const new({this.leading = 0}) : super._();

  /// The extra space between lines, in points.
  final double leading;
}

/// Lines a multiple of their font size tall.
final class MultipleLineHeight extends LineHeight {
  /// [factor] times the font size.
  const new(this.factor) : super._();

  /// The multiple.
  final double factor;
}

/// Lines of a fixed height.
final class ExactLineHeight extends LineHeight {
  /// [points] tall.
  const new(this.points) : super._();

  /// The height, in points.
  final double points;
}

/// How lines sit between the margins.
enum TextAlign {
  /// Against the left margin.
  left,

  /// Centered.
  center,

  /// Against the right margin.
  right,

  /// Against both margins, stretching the spaces (the last line, and
  /// lines ending in a hard break, are left aligned).
  justify,
}

/// Finds where words may be hyphenated.
abstract interface class Hyphenator {
  /// The offsets in [word] (letters only) a hyphen may go before.
  List<int> hyphenate(String word);
}

/// A paragraph: inline content, aligned and spaced.
@immutable
final class Paragraph {
  /// A paragraph of [content].
  const new(
    this.content, {
    this.align = TextAlign.left,
    this.lineHeight = const LineHeight.font(),
    this.firstLineIndent = 0,
    this.hyphenator,
    this.breakLongWords = true,
    this.hyphenRepetition = HyphenRepetition.none,
  });

  /// The inline content.
  final List<InlineContent> content;

  /// The alignment.
  final TextAlign align;

  /// The line spacing.
  final LineHeight lineHeight;

  /// The indent of the first line, in points.
  final double firstLineIndent;

  /// What hyphenates words, if anything.
  final Hyphenator? hyphenator;

  /// Whether a word wider than the line is broken between any two
  /// characters (rather than sticking out).
  final bool breakLongWords;

  /// Whether a line broken after a word's own hyphen (a compound's) starts
  /// with the hyphen again.
  final HyphenRepetition hyphenRepetition;
}

/// When a compound's hyphen is repeated at the start of the next line, as
/// the orthographies of some languages have it (for Spanish, the Real
/// Academia Española's Ortografía de la lengua española, 2010).
enum HyphenRepetition {
  /// Never.
  none,

  /// Always: Czech, Croatian, Lower Sorbian, Polish, Portuguese, Slovak.
  always,

  /// Before a word that doesn't start with a capital: Spanish.
  beforeLowercase;

  /// The repetition the typography of the language [tag] (`pt`, `es-MX`)
  /// asks for.
  static HyphenRepetition forLanguage(String? tag) =>
      switch (tag?.toLowerCase().split(RegExp('[-_]')).first) {
        'cs' || 'hr' || 'dsb' || 'pl' || 'pt' || 'sk' => always,
        'es' => beforeLowercase,
        _ => none,
      };

  /// Whether the hyphen is repeated before [following] text.
  bool repeatsBefore(String following) => switch (this) {
    none => false,
    always => true,
    beforeLowercase =>
      following.isNotEmpty &&
          !_isUppercase(String.fromCharCode(following.runes.first)),
  };

  static bool _isUppercase(String c) =>
      c != c.toLowerCase() && c == c.toUpperCase();
}

/// An item of the paragraph's line breaking model.
@immutable
sealed class LineItem {
  const new _();

  /// The item's natural width, in points.
  double get width;
}

/// Content that is never broken: a piece of a word, or an image.
final class BoxItem extends LineItem {
  /// The [text] of [content] (empty for an image), [width] wide.
  const new(this.content, this.text, this.width) : super._();

  /// The text run or image.
  final InlineContent content;

  /// The text.
  final String text;

  @override
  final double width;
}

/// A space: where a line may break (if a box comes before it), and what
/// stretches or shrinks to justify a line.
final class GlueItem extends LineItem {
  /// The space [text] of [run], [width] wide, which may grow by
  /// [stretch] and shrink by [shrink].
  const new(this.run, this.text, this.width, this.stretch, this.shrink)
    : super._();

  /// Glue that fills the rest of the last line.
  const new fill()
    : run = null,
      text = '',
      width = 0,
      stretch = double.infinity,
      shrink = 0,
      super._();

  /// The run the space belongs to (null for fill glue).
  final TextRun? run;

  /// The space characters.
  final String text;

  @override
  final double width;

  /// How much the space may grow.
  final double stretch;

  /// How much the space may shrink.
  final double shrink;
}

/// A place the line may break at a cost.
final class PenaltyItem extends LineItem {
  /// A break costing [penalty] (`forced` or below always breaks, `never`
  /// or above never does); [flagged] breaks add a hyphen of [width] in
  /// [run]'s style; a break with a [carry] starts the next line with a
  /// hyphen that wide (a compound's hyphen repeated, see
  /// [HyphenRepetition]).
  const new(
    this.width,
    this.penalty, {
    this.flagged = false,
    this.run,
    this.carry = 0,
  }) : super._();

  /// The cost of breaking that forces a break.
  static const double forced = -10000;

  /// The cost of breaking that forbids it.
  static const double never = 10000;

  @override
  final double width;

  /// The cost of breaking here.
  final double penalty;

  /// Whether breaking here adds a hyphen.
  final bool flagged;

  /// The width of the hyphen the next line starts with when the line
  /// breaks here (0: none).
  final double carry;

  /// The run the break is in: the hyphen's style, and the metrics of an
  /// empty line ending here.
  final TextRun? run;

  /// Whether the line must break here.
  bool get isForced => penalty <= forced;
}

/// The width available to each line (0-based) of a paragraph.
typedef LineWidths = double Function(int line);

/// Chooses where a paragraph's lines break.
abstract interface class LineBreaker {
  /// The lines of [paragraph] in [widths].
  List<Line> breakLines(Paragraph paragraph, LineWidths widths);
}

/// A line breaker over the items of [paragraphItems].
abstract base class ItemLineBreaker implements LineBreaker {
  /// A line breaker.
  const new();

  /// The indices of the items lines end at (glue or penalties), in order;
  /// the last is the final forced break.
  List<int> breakItems(List<LineItem> items, LineWidths widths);

  @override
  List<Line> breakLines(Paragraph paragraph, LineWidths widths) {
    final indent = paragraph.firstLineIndent;
    double indented(int line) => widths(line) - (line == 0 ? indent : 0);
    final items = paragraphItems(
      paragraph,
      maxWidth: paragraph.breakLongWords ? indented(0) : null,
    );
    if (items.isEmpty) return const [];
    return buildLines(paragraph, items, breakItems(items, indented), widths);
  }
}

/// The cost from which a break is a last resort for [FirstFitLineBreaker].
const double _lastResort = 500;

/// Breaks each line at the last opportunity that fits: the way most
/// word processors (and Prawn) fill lines. A break costing 500 or more
/// (between the characters of a word too long for a line) is taken only
/// when the line has no other.
final class FirstFitLineBreaker extends ItemLineBreaker {
  /// A first-fit line breaker.
  const new();

  @override
  List<int> breakItems(List<LineItem> items, LineWidths widths) {
    final breaks = <int>[];
    var start = 0;
    while (start < items.length) {
      final s = _skipDiscardable(items, start);
      if (s >= items.length) break;
      final available = widths(breaks.length) + _epsilon;
      var width = _carry(items, start - 1);
      int? candidate;
      var lastResort = false;
      int? end;
      for (var i = s; i < items.length; i++) {
        final item = items[i];
        switch (item) {
          case PenaltyItem(isForced: true):
            end = width <= available || candidate == null ? i : candidate;
          case PenaltyItem(:final penalty):
            // A costly break (between the characters of a word too long
            // for a line) only when the line has no other.
            final last = penalty >= _lastResort;
            if (penalty < PenaltyItem.never &&
                (!last || candidate == null || lastResort)) {
              if (width + item.width <= available) {
                candidate = i;
                lastResort = last;
              } else if (candidate == null) {
                end = i; // overfull, but the first chance to break
              }
            }
          case GlueItem(:final stretch):
            if (i > s && items[i - 1] is BoxItem && stretch.isFinite) {
              if (width <= available) {
                candidate = i;
                lastResort = false;
              } else {
                end = candidate ?? i;
              }
            }
            width += item.width;
          case BoxItem():
            width += item.width;
            if (width > available && candidate != null) end = candidate;
        }
        if (end != null) break;
      }
      final at = end ?? items.length - 1;
      breaks.add(at);
      start = at + 1;
    }
    return breaks;
  }
}

/// The total-fit algorithm of Knuth and Plass ("Breaking paragraphs into
/// lines", Software: Practice and Experience 11, 1981), with TeX's
/// parameters (The TeXbook, chapter 14): the breaks that minimize the sum
/// of the lines' demerits, so spacing is even across the paragraph.
///
/// A line's badness is 100·r³, r how far its spaces stretch or shrink
/// (at most their shrink: never tighter); its demerits (l + b)² plus the
/// square of its break's penalty (less it, for a negative one), more for
/// two hyphenated lines in a row, a hyphenated next-to-last line, and
/// lines next to each other in fitness classes more than one apart
/// (tight, decent, loose, very loose). Breaks are tried within
/// [tolerance], then with [emergencyStretch] more on every line (TeX's
/// third pass), then at any looseness, and last one line at a time.
/// Every line knows its number, so lines of different widths (an indent,
/// a drop's lines, a runaround) are broken as well as the rest.
///
/// [raggedStretch] sets ragged lines as TeX's `\rightskip` does: each
/// line may fall short of the measure by that much at no more than a
/// badness of 100, its spaces keep their width, and the breaks that
/// even the lines' ends out the most are taken.
final class KnuthPlassLineBreaker extends ItemLineBreaker {
  /// A Knuth-Plass line breaker with TeX's default costs: [tolerance] a
  /// badness of 200, a [linePenalty] of 10, 10000 demerits for two
  /// hyphenated lines in a row ([flaggedDemerits]) or adjacent lines far
  /// apart in fitness ([fitnessDemerits]), and 5000 for a hyphenated
  /// next-to-last line ([finalHyphenDemerits]).
  const new({
    this.tolerance = 1.26,
    this.linePenalty = 10,
    this.flaggedDemerits = 10000,
    this.fitnessDemerits = 10000,
    this.finalHyphenDemerits = 5000,
    this.emergencyStretch = 0,
    this.raggedStretch,
  });

  /// The largest stretch ratio of a line in the first pass (1.26: a
  /// badness of 200, TeX's `\tolerance`).
  final double tolerance;

  /// The demerits of each line (TeX's `\linepenalty`).
  final double linePenalty;

  /// The demerits of two hyphenated lines in a row (TeX's
  /// `\doublehyphendemerits`).
  final double flaggedDemerits;

  /// The demerits of adjacent lines in very different fitness classes
  /// (TeX's `\adjdemerits`).
  final double fitnessDemerits;

  /// The demerits of a hyphenated next-to-last line (TeX's
  /// `\finalhyphendemerits`).
  final double finalHyphenDemerits;

  /// The stretch added to every line in the second pass, when the first
  /// found no breaks (TeX's `\emergencystretch`); 0 skips the pass.
  final double emergencyStretch;

  /// For ragged lines: how far short of the measure a line may fall (TeX's
  /// `\rightskip` stretch); `null` for justified lines.
  final double? raggedStretch;

  @override
  List<int> breakItems(List<LineItem> items, LineWidths widths) {
    // Running totals of the items before each index, the first item of
    // the line after a break at each index, and each line's width: the
    // same for every tolerance tried.
    final n = items.length;
    final totalWidth = Float64List(n + 1);
    final totalStretch = Float64List(n + 1);
    final totalShrink = Float64List(n + 1);
    // Fills (infinite stretch) counted apart, so their totals subtract.
    final totalFills = Int32List(n + 1);
    for (var i = 0; i < n; i++) {
      final item = items[i];
      totalWidth[i + 1] =
          totalWidth[i] + (item is PenaltyItem ? 0 : item.width);
      final fill = item is GlueItem && item.stretch.isInfinite;
      totalStretch[i + 1] =
          totalStretch[i] + (item is GlueItem && !fill ? item.stretch : 0);
      totalShrink[i + 1] =
          totalShrink[i] + (item is GlueItem ? item.shrink : 0);
      totalFills[i + 1] = totalFills[i] + (fill ? 1 : 0);
    }
    final next = Int32List(n + 1)..[n] = n;
    for (var i = n - 1; i >= 0; i--) {
      final discarded = switch (items[i]) {
        GlueItem() => true,
        PenaltyItem(:final isForced) => !isForced,
        BoxItem() => false,
      };
      next[i] = discarded ? next[i + 1] : i;
    }
    final lineWidths = <double>[];
    double widthOf(int line) {
      while (lineWidths.length <= line) {
        lineWidths.add(widths(lineWidths.length));
      }
      return lineWidths[line];
    }

    final sums = (totalWidth, totalStretch, totalShrink, totalFills, next);
    final passes = [
      (tolerance, 0.0),
      if (emergencyStretch > 0) (tolerance, emergencyStretch),
      (100.0, emergencyStretch),
    ];
    for (final (ratio, extra) in passes) {
      final breaks = _total(items, sums, widthOf, ratio, extra);
      if (breaks != null) return breaks;
    }
    return const FirstFitLineBreaker().breakItems(items, widths);
  }

  /// The line of [items] from [start] (after the break at [position]) to
  /// the break at [at], numbered [line]: how far its spaces stretch, its
  /// demerits after a line of [fitnessBefore] (hyphenated: [flaggedBefore]),
  /// and its fitness class.
  ({double ratio, double demerits, int fitness}) _line(
    List<LineItem> items,
    (Float64List, Float64List, Float64List, Int32List, Int32List) sums,
    LineWidths widths,
    int position,
    int start,
    int line,
    int at,
    double extraStretch, {
    required double penalty,
    required bool forced,
    required bool flagged,
    required bool flaggedBefore,
    required int fitnessBefore,
  }) {
    final (totalWidth, totalStretch, totalShrink, totalFills, _) = sums;
    final item = items[at];
    var width = totalWidth[at] - totalWidth[start] + _carry(items, position);
    if (item is PenaltyItem) width += item.width;
    // Ragged lines: their spaces as they are, and the line's end may
    // stretch by [raggedStretch].
    final ragged = raggedStretch;
    final stretch = totalFills[at] > totalFills[start]
        ? double.infinity
        : (ragged ?? totalStretch[at] - totalStretch[start]) + extraStretch;
    final shrink = ragged == null ? totalShrink[at] - totalShrink[start] : 0.0;
    final available = widths(line);
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
    // (math.pow's cube and square, multiplied as the VM's pow does.)
    final r = ratio.abs();
    final badness = 100 * (r * r * r);
    final base = linePenalty + badness;
    var demerits = base * base;
    if (penalty >= 0) {
      demerits += penalty * penalty;
    } else if (penalty > PenaltyItem.forced) {
      demerits -= penalty * penalty;
    }
    if (flagged && flaggedBefore) demerits += flaggedDemerits;
    // The paragraph's last line after a hyphenated one.
    if (forced && at == items.length - 1 && flaggedBefore) {
      demerits += finalHyphenDemerits;
    }
    final fitness = ratio < -0.5
        ? 0
        : ratio <= 0.5
        ? 1
        : ratio <= 1
        ? 2
        : 3;
    if ((fitness - fitnessBefore).abs() > 1) demerits += fitnessDemerits;
    return (ratio: ratio, demerits: demerits, fitness: fitness);
  }

  /// The total demerits of breaking [items] at [breaks] (the indices of
  /// the items broken at, the last the paragraph's end), as the first pass
  /// counts them; infinite when a line is overfull or past [tolerance]. For
  /// checking that the breaker finds the least there is.
  @visibleForTesting
  double demeritsOf(List<LineItem> items, LineWidths widths, List<int> breaks) {
    final n = items.length;
    final totalWidth = Float64List(n + 1);
    final totalStretch = Float64List(n + 1);
    final totalShrink = Float64List(n + 1);
    final totalFills = Int32List(n + 1);
    for (var i = 0; i < n; i++) {
      final item = items[i];
      totalWidth[i + 1] =
          totalWidth[i] + (item is PenaltyItem ? 0 : item.width);
      final fill = item is GlueItem && item.stretch.isInfinite;
      totalStretch[i + 1] =
          totalStretch[i] + (item is GlueItem && !fill ? item.stretch : 0);
      totalShrink[i + 1] =
          totalShrink[i] + (item is GlueItem ? item.shrink : 0);
      totalFills[i + 1] = totalFills[i] + (fill ? 1 : 0);
    }
    final next = Int32List(n + 1)..[n] = n;
    for (var i = n - 1; i >= 0; i--) {
      final discarded = switch (items[i]) {
        GlueItem() => true,
        PenaltyItem(:final isForced) => !isForced,
        BoxItem() => false,
      };
      next[i] = discarded ? next[i + 1] : i;
    }
    final sums = (totalWidth, totalStretch, totalShrink, totalFills, next);
    var total = 0.0;
    var position = -1;
    var flagged = false;
    var fitness = 1;
    for (final (line, at) in breaks.indexed) {
      final item = items[at];
      final (:ratio, :demerits, fitness: lineFitness) = _line(
        items,
        sums,
        widths,
        position,
        position < 0 ? 0 : next[position + 1],
        line,
        at,
        0,
        penalty: item is PenaltyItem ? item.penalty : 0,
        forced: item is PenaltyItem && item.isForced,
        flagged: item is PenaltyItem && item.flagged,
        flaggedBefore: flagged,
        fitnessBefore: fitness,
      );
      if (ratio < -1 || ratio > tolerance) return double.infinity;
      total += demerits;
      position = at;
      flagged = item is PenaltyItem && item.flagged;
      fitness = lineFitness;
    }
    return total;
  }

  List<int>? _total(
    List<LineItem> items,
    (Float64List, Float64List, Float64List, Int32List, Int32List) sums,
    LineWidths widths,
    double limit,
    double extraStretch,
  ) {
    final (totalWidth, totalStretch, totalShrink, totalFills, next) = sums;
    final n = items.length;
    var active = <_Node>[_Node(-1, 0, 1, 0, null, flagged: false, start: 0)];
    var survivors = <_Node>[];
    // The best break at this index for each fitness class and line count,
    // in the order they were first found.
    final bestFitness = <int>[];
    final bestLine = <int>[];
    final best = <_Node>[];
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
      bestFitness.clear();
      bestLine.clear();
      best.clear();
      survivors.clear();
      for (final node in active) {
        final (:ratio, :demerits, :fitness) = _line(
          items,
          sums,
          widths,
          node.position,
          node.start,
          node.line,
          i,
          extraStretch,
          penalty: penalty,
          forced: forced,
          flagged: flagged,
          flaggedBefore: node.flagged,
          fitnessBefore: node.fitness,
        );
        if (ratio >= -1 && !forced) survivors.add(node);
        if (ratio < -1 || ratio > limit) continue;
        final total = node.demerits + demerits;
        final line = node.line + 1;
        var at = 0;
        while (at < best.length &&
            (bestFitness[at] != fitness || bestLine[at] != line)) {
          at++;
        }
        if (at == best.length || total < best[at].demerits) {
          final found = _Node(
            i,
            line,
            fitness,
            total,
            node,
            flagged: flagged,
            start: next[i + 1],
          );
          if (at == best.length) {
            bestFitness.add(fitness);
            bestLine.add(line);
            best.add(found);
          } else {
            best[at] = found;
          }
        }
      }
      // The survivors, then the new breaks, are the active ones.
      final kept = survivors..addAll(best);
      survivors = active;
      active = kept;
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

/// The items of [paragraph]: its words as boxes, its spaces as glue, its
/// other break opportunities (UAX #14) as penalties, its hard breaks as
/// forced penalties. Soft hyphens, and the hyphenator's points, give
/// flagged penalties. With [maxWidth], a box wider than it is split into
/// characters with costly breaks between them.
List<LineItem> paragraphItems(Paragraph paragraph, {double? maxWidth}) {
  final contents = [
    for (final content in paragraph.content)
      ...switch (content) {
        PageReference(:final placeholder) => [content.resolve(placeholder)],
        TextRun(fallbackFonts: [_, ...]) => _withFallbacks(content),
        _ => [content],
      },
  ];
  final text = StringBuffer();
  for (final content in contents) {
    text.write(switch (content) {
      TextRun(:final text) => text,
      // U+FFFC OBJECT REPLACEMENT CHARACTER.
      InlineImage() => '\u{fffc}',
      PageReference(:final placeholder) => placeholder,
    });
  }
  final whole = text.toString();
  final breaks = lineBreakOffsets(whole);
  // The first break opportunity not before the offset last asked about
  // (breakBefore is asked about offsets in order).
  var nextBreak = 0;
  final items = <LineItem>[];
  final word = StringBuffer();
  TextRun? wordRun;
  TextRun? lastRun;
  var softHyphen = false;

  void flush() {
    final run = wordRun;
    if (run == null || word.isEmpty) return;
    final piece = word.toString();
    word.clear();
    final hyphenator = paragraph.hyphenator;
    final points = hyphenator == null || !_isWord(piece)
        ? const <int>[]
        : hyphenator.hyphenate(piece);
    var from = 0;
    for (final point in [
      ...points.where((p) => p > 0 && p < piece.length),
    ]..sort()) {
      final part = piece.substring(from, point);
      items
        ..add(BoxItem(run, part, run.style.measure(part)))
        ..add(PenaltyItem(run.style.measure('-'), 50, flagged: true, run: run));
      from = point;
    }
    final rest = piece.substring(from);
    items.add(BoxItem(run, rest, run.style.measure(rest)));
  }

  var offset = 0;
  void breakBefore(int at) {
    if (at == 0) return;
    while (nextBreak < breaks.length && breaks.offsetAt(nextBreak) < at) {
      nextBreak++;
    }
    final opportunity =
        nextBreak < breaks.length && breaks.offsetAt(nextBreak) == at;
    if (opportunity && breaks.isMandatoryAt(nextBreak)) {
      flush();
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: lastRun));
    } else if (opportunity) {
      flush();
      if (lastRun case final run? when softHyphen) {
        items.add(
          PenaltyItem(run.style.measure('-'), 50, flagged: true, run: run),
        );
      } else if (items.lastOrNull is! GlueItem) {
        // After a compound's hyphen, repeated on the next line where the
        // language has it so.
        final run = lastRun;
        final repeat =
            run != null &&
            whole.codeUnitAt(at - 1) == 0x2d &&
            paragraph.hyphenRepetition.repeatsBefore(whole.substring(at));
        items.add(
          PenaltyItem(
            0,
            0,
            run: run,
            carry: repeat ? run.style.measure('-') : 0,
          ),
        );
      }
    }
    softHyphen = false;
  }

  for (final content in contents) {
    switch (content) {
      case PageReference():
        break; // resolved above
      case InlineImage(:final width):
        breakBefore(offset);
        flush();
        items.add(BoxItem(content, '', width));
        offset += 1;
      case TextRun(:final text, :final style):
        final shrink = paragraph.align == TextAlign.justify
            ? style.measure(' ') / 3
            : 0.0;
        if (wordRun != content) flush();
        wordRun = content;
        lastRun = content;
        for (final rune in text.runes) {
          breakBefore(offset);
          wordRun = content;
          final length = rune > 0xffff ? 2 : 1;
          switch (rune) {
            case 0x0a || 0x0b || 0x0c || 0x0d || 0x85 || 0x2028 || 0x2029:
              break; // a hard break, already a forced penalty
            case 0x20 || 0x09:
              flush();
              final space = style.measure(' ');
              // Spaces only shrink in justified text: elsewhere nothing
              // would shrink them when the line is drawn.
              items.add(GlueItem(content, ' ', space, space / 2, shrink));
            case 0xad:
              softHyphen = true;
            case 0x200b || 0x2060 || 0xfeff:
              break; // zero width, not drawn
            default:
              word.writeCharCode(rune);
          }
          offset += length;
        }
        flush();
    }
  }
  flush();
  if (items.isEmpty) return items;
  items
    ..add(const GlueItem.fill())
    ..add(PenaltyItem(0, PenaltyItem.forced, run: lastRun));
  return maxWidth == null ? items : _splitWide(items, maxWidth);
}

/// [run] split where its font lacks characters a fallback font has.
List<TextRun> _withFallbacks(TextRun run) {
  final primary = run.style.font;
  Font fontFor(int rune) {
    if (primary.covers(rune) || rune <= 0x20) return primary;
    for (final font in run.fallbackFonts) {
      if (font.covers(rune)) return font;
    }
    return primary;
  }

  final runs = <TextRun>[];
  final text = StringBuffer();
  Font? current;
  void flush() {
    if (text.isEmpty) return;
    final piece = run.withText(text.toString());
    runs.add(
      identical(current, primary)
          ? piece
          : piece.withStyle(run.style.copyWith(font: current)),
    );
    text.clear();
  }

  for (final rune in run.text.runes) {
    // Spaces and controls stay with the font around them.
    final font = rune <= 0x20 && current != null ? current : fontFor(rune);
    if (!identical(font, current)) {
      flush();
      current = font;
    }
    text.writeCharCode(rune);
  }
  flush();
  return runs;
}

bool _isWord(String text) => text.runes.every(
  (c) =>
      lineBreakClass(c) == LineBreakClass.al ||
      lineBreakClass(c) == LineBreakClass.hl,
);

/// [items] with each box wider than [maxWidth] split into characters,
/// with costly breaks between them.
List<LineItem> _splitWide(List<LineItem> items, double maxWidth) {
  if (!items.any((item) => item is BoxItem && item.width > maxWidth)) {
    return items;
  }
  return [
    for (final item in items)
      if (item case BoxItem(content: final TextRun run, :final text)
          when item.width > maxWidth)
        for (final (i, char) in [
          for (final rune in text.runes) String.fromCharCode(rune),
        ].indexed) ...[
          if (i > 0) PenaltyItem(0, 1000, run: run),
          BoxItem(run, char, run.style.measure(char)),
        ]
      else
        item,
  ];
}

/// A piece of a line.
@immutable
sealed class LineFragment {
  const new _(this.x, this.width);

  /// The offset from the line's start, in points.
  final double x;

  /// The width, in points.
  final double width;
}

/// Text of one run on a line.
final class TextFragment extends LineFragment {
  /// [glyphs] of [run] set in [style] at [x].
  const new(super.x, super.width, this.run, this.text, this.glyphs, this.style)
    : super._();

  /// The run the text comes from.
  final TextRun run;

  /// The text (with its spaces).
  final String text;

  /// The shaped glyphs.
  final List<ShapedGlyph> glyphs;

  /// The style it is drawn in: the run's, with the word spacing that
  /// justifies the line.
  final TextStyle style;
}

/// An inline image on a line.
final class ImageFragment extends LineFragment {
  /// [image] at [x], its bottom [bottom] points above the baseline.
  const new(super.x, super.width, this.image, this.bottom) : super._();

  /// The image.
  final InlineImage image;

  /// The offset of its bottom from the baseline (negative: below it).
  final double bottom;
}

/// A line of a paragraph, ready to paint.
@immutable
final class Line {
  /// A line of [fragments].
  const new(
    this.fragments, {
    required this.width,
    required this.height,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.hyphenated,
  });

  /// The fragments, left to right, positioned for the alignment.
  final List<LineFragment> fragments;

  /// The width of the content, in points.
  final double width;

  /// The height the line takes, in points.
  final double height;

  /// The baseline's distance from the top of the line.
  final double baseline;

  /// The height of the content above the baseline.
  final double ascent;

  /// The depth of the content below the baseline (negative).
  final double descent;

  /// Whether the line ends with a hyphen the break added.
  final bool hyphenated;

  /// Paints the line with its top-left corner at ([x], [top]), reporting
  /// the rectangles of links to [link] and the positions of anchors to
  /// [anchor].
  void paint(
    Canvas canvas,
    double x,
    double top, {
    void Function(Rect rect, LinkTarget target)? link,
    void Function(String name, double x, double y)? anchor,
  }) {
    final y = top - baseline;
    for (final fragment in fragments) {
      final left = x + fragment.x;
      switch (fragment) {
        case TextFragment(:final run, :final glyphs, :final style):
          final font = style.font;
          final size = style.size;
          if (run.decoration case final decoration?) {
            _decorate(
              canvas,
              decoration,
              Rect(
                left - decoration.padding,
                y + font.descender * size / 1000,
                fragment.width + 2 * decoration.padding,
                (font.ascender - font.descender) * size / 1000,
              ),
            );
          }
          canvas.save();
          if (run.color case final color?) canvas.setFillColor(color);
          canvas.glyphs(glyphs, left, y, style);
          final thickness = font.underlineThickness * size / 1000;
          if (run.underline) {
            canvas
              ..rect(
                Rect(
                  left,
                  y + font.underlinePosition * size / 1000 - thickness / 2,
                  fragment.width,
                  thickness,
                ),
              )
              ..fill();
          }
          if (run.strikethrough) {
            canvas
              ..rect(
                Rect(
                  left,
                  y + font.xHeight * size / 2000 - thickness / 2,
                  fragment.width,
                  thickness,
                ),
              )
              ..fill();
          }
          canvas.restore();
          if (run.link case final target? when link != null) {
            link(
              Rect(
                left,
                y + font.descender * size / 1000,
                fragment.width,
                (font.ascender - font.descender) * size / 1000,
              ),
              target,
            );
          }
          if (run.anchor case final name? when anchor != null) {
            anchor(name, left, y + font.ascender * size / 1000);
          }
        case ImageFragment(:final image, :final bottom):
          image.image.paint(
            canvas,
            Rect(left, y + bottom, image.width, image.height),
          );
          if (image.link case final target? when link != null) {
            link(Rect(left, y + bottom, image.width, image.height), target);
          }
      }
    }
  }
}

void _decorate(Canvas canvas, InlineDecoration decoration, Rect rect) {
  void shape(Rect r) => decoration.radius > 0
      ? canvas.roundedRect(r, decoration.radius)
      : canvas.rect(r);
  canvas.save();
  if (decoration.background case final background?) {
    canvas.setFillColor(background);
    shape(rect);
    canvas.fill();
  }
  final w = decoration.borderWidth;
  if (decoration.borderColor case final color? when w > 0) {
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(w);
    shape(
      Rect(
        rect.left + w / 2,
        rect.bottom + w / 2,
        rect.width - w,
        rect.height - w,
      ),
    );
    canvas.stroke();
  }
  canvas.restore();
}

/// The lines of [paragraph] from its [items] broken at [breaks], in
/// [widths].
List<Line> buildLines(
  Paragraph paragraph,
  List<LineItem> items,
  List<int> breaks,
  LineWidths widths,
) {
  final lines = <Line>[];
  var start = 0;
  for (final (number, end) in breaks.indexed) {
    final s = _skipDiscardable(items, start);
    final content = s < end ? items.sublist(s, end) : <LineItem>[];
    while (content.isNotEmpty && content.last is GlueItem) {
      content.removeLast();
    }
    final breakItem = items[end];
    final hyphen = breakItem is PenaltyItem && breakItem.flagged
        ? breakItem.run
        : null;
    final last =
        number == breaks.length - 1 ||
        (breakItem is PenaltyItem && breakItem.isForced);
    final indent = number == 0 ? paragraph.firstLineIndent : 0.0;
    final emptyRun = breakItem is PenaltyItem ? breakItem.run : null;
    // The hyphen repeated from the line before (see PenaltyItem.carry).
    final leading = switch (start > 0 ? items[start - 1] : null) {
      PenaltyItem(:final carry, :final run?) when carry > 0 => run,
      _ => null,
    };
    lines.add(
      _line(
        paragraph,
        content,
        hyphen,
        leading,
        widths(number) - indent,
        indent,
        justify: paragraph.align == TextAlign.justify && !last,
        emptyRun: emptyRun,
      ),
    );
    start = end + 1;
  }
  return lines;
}

Line _line(
  Paragraph paragraph,
  List<LineItem> items,
  TextRun? hyphen,
  TextRun? leadingHyphen,
  double available,
  double indent, {
  required bool justify,
  required TextRun? emptyRun,
}) {
  // Runs of items of the same content, in order.
  final pieces = <(InlineContent, StringBuffer)>[
    if (leadingHyphen != null) (leadingHyphen, StringBuffer('-')),
  ];
  for (final item in items) {
    final (InlineContent? content, String text) = switch (item) {
      BoxItem(:final content, :final text) => (content, text),
      GlueItem(:final run?, :final text) => (run, text),
      _ => (null, ''),
    };
    if (content == null) continue;
    if (content is TextRun &&
        pieces.isNotEmpty &&
        identical(pieces.last.$1, content)) {
      pieces.last.$2.write(text);
    } else {
      pieces.add((content, StringBuffer(text)));
    }
  }
  if (hyphen != null) {
    if (pieces.isNotEmpty && identical(pieces.last.$1, hyphen)) {
      pieces.last.$2.write('-');
    } else {
      pieces.add((hyphen, StringBuffer('-')));
    }
  }

  // Natural widths, and the spaces justification stretches.
  var natural = 0.0;
  var spaces = 0;
  final shaped = <(InlineContent, String, List<ShapedGlyph>, double)>[];
  for (final (content, buffer) in pieces) {
    final text = buffer.toString();
    switch (content) {
      case TextRun(:final style):
        final glyphs = style.shape(text);
        final width = style.widthOf(glyphs);
        shaped.add((content, text, glyphs, width));
        natural += width;
        spaces += ' '.allMatches(text).length;
      case InlineImage(:final width):
        shaped.add((content, text, const [], width));
        natural += width;
      case PageReference():
        throw StateError('page references are resolved before breaking');
    }
  }
  final extra = justify && spaces > 0 ? (available - natural) / spaces : 0.0;
  final width = natural + extra * spaces;
  var x =
      indent +
      switch (paragraph.align) {
        TextAlign.left || TextAlign.justify => 0.0,
        TextAlign.center => (available - width) / 2,
        TextAlign.right => available - width,
      };

  // Vertical metrics.
  var ascent = 0.0;
  var descent = 0.0;
  var gap = 0.0;
  var size = 0.0;
  var xHeight = 0.0;
  void text(TextStyle style) {
    final scale = style.size / 1000;
    ascent = math.max(
      ascent,
      style.font.ascender * scale + math.max(0, style.rise),
    );
    descent = math.min(
      descent,
      style.font.descender * scale + math.min(0, style.rise),
    );
    gap = math.max(gap, style.font.lineGap * scale);
    size = math.max(size, style.size);
    xHeight = math.max(xHeight, style.font.xHeight * scale);
  }

  for (final (content, _, _, _) in shaped) {
    if (content is TextRun) text(content.style);
  }
  if (shaped.isEmpty && emptyRun != null) text(emptyRun.style);
  final textAscent = ascent;
  final fragments = <LineFragment>[];
  for (final (content, string, glyphs, natural) in shaped) {
    switch (content) {
      case TextRun(:final style):
        final count = ' '.allMatches(string).length;
        final adjusted = extra == 0
            ? style
            : style.copyWith(wordSpacing: style.wordSpacing + extra);
        final w = natural + extra * count;
        fragments.add(TextFragment(x, w, content, string, glyphs, adjusted));
        x += w;
      case InlineImage(:final height, :final alignment):
        final bottom = switch (alignment) {
          InlineAlignment.baseline => 0.0,
          InlineAlignment.middle => xHeight / 2 - height / 2,
          InlineAlignment.top => textAscent - height,
        };
        ascent = math.max(ascent, bottom + height);
        descent = math.min(descent, bottom);
        if (size == 0) size = height;
        fragments.add(ImageFragment(x, content.width, content, bottom));
        x += content.width;
      case PageReference():
        throw StateError('page references are resolved before breaking');
    }
  }
  final (height, baseline) = switch (paragraph.lineHeight) {
    FontLineHeight(:final leading) => (
      ascent - descent + gap + leading,
      ascent,
    ),
    MultipleLineHeight(:final factor) => _centered(
      factor * size,
      ascent,
      descent,
    ),
    ExactLineHeight(:final points) => _centered(points, ascent, descent),
  };
  return Line(
    fragments,
    width: width,
    height: height,
    baseline: baseline,
    ascent: ascent,
    descent: descent,
    hyphenated: hyphen != null,
  );
}

/// A line [height] tall with its content centered (the extra split above
/// and below, as CSS does).
(double, double) _centered(double height, double ascent, double descent) =>
    (height, (height - (ascent - descent)) / 2 + ascent);
