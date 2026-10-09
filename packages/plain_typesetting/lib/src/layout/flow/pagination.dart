part of '../flow.dart';

// Pagination rules and templates, and the layout itself.

/// Decides where content breaks across regions.
abstract interface class PageBreaker {
  /// How many of the lines of [heights] go in [available] height (0 moves
  /// them all to the next region), keeping [orphans] lines before the
  /// break and [widows] after it; [atTop] when nothing is above them in
  /// the region (they can't move to a fresher one).
  int linesThatFit(
    List<double> heights,
    double available, {
    required int orphans,
    required int widows,
    required bool atTop,
  });

  /// How many lines of [total] go in a region where the first [fit] of
  /// them fit (0 moves them all to the next region), keeping [orphans]
  /// lines before the break and [widows] after it; [atTop] when nothing
  /// is above them in the region.
  int linesToKeep(
    int fit,
    int total, {
    required int orphans,
    required int widows,
    required bool atTop,
  });

  /// Whether a box kept together, [height] tall, moves to the next
  /// region rather than split, with [available] left of a region
  /// [regionHeight] tall.
  bool moveKeptBox(double height, double available, double regionHeight);
}

/// The usual rules: as many lines as fit, unless that leaves fewer than
/// the orphans before the break or the widows after it; kept boxes move
/// when they fit in a whole region.
final class DefaultPageBreaker implements PageBreaker {
  /// The default page breaker.
  const new();

  @override
  int linesThatFit(
    List<double> heights,
    double available, {
    required int orphans,
    required int widows,
    required bool atTop,
  }) {
    var fit = 0;
    var used = 0.0;
    while (fit < heights.length && used + heights[fit] <= available + 1e-6) {
      used += heights[fit];
      fit++;
    }
    return linesToKeep(
      fit,
      heights.length,
      orphans: orphans,
      widows: widows,
      atTop: atTop,
    );
  }

  @override
  int linesToKeep(
    int fit,
    int total, {
    required int orphans,
    required int widows,
    required bool atTop,
  }) {
    if (fit >= total) return total;
    // A line must go somewhere: at the top of a region, at least one.
    final least = atTop ? math.max(1, fit) : 0;
    if (fit < orphans) return least;
    if (total - fit < widows) {
      final kept = total - widows;
      return kept >= orphans ? kept : least;
    }
    return fit;
  }

  @override
  bool moveKeptBox(double height, double available, double regionHeight) =>
      height > available + 1e-6 && height <= regionHeight + 1e-6;
}

/// What a running header or footer knows about its page.
final class PageInfo {
  new _(
    this.number,
    this.count,
    this.label,
    this._marks,
    this.template,
    this._topMarks, {
    this.isEmpty = false,
  });

  /// The template of the page.
  final PageTemplate template;

  /// The page number (1-based).
  final int number;

  /// The number of pages.
  final int count;

  /// The page's label (its number as the layout writes it).
  final String label;

  final Map<String, String> _marks;

  /// Whether nothing was laid out on the page (a blank page before a
  /// recto or verso start, say).
  final bool isEmpty;

  /// The value of the running mark [name] on this page: the first one set
  /// on the page, or else the last one set before it.
  String? mark(String name) => _marks[name];

  final Map<String, String> _topMarks;

  /// The value of the running mark [name] at the top of this page: the last
  /// one set before it (what a header set at the page's top sees, as
  /// Typst's headers do).
  String? topMark(String name) => _topMarks[name];
}

/// The pages content is laid out on.
@immutable
final class PageTemplate {
  /// Pages of [size] whose content area is inside [margins], in
  /// [columns] columns [columnGap] apart; [header] and [footer] give the
  /// boxes of the top and bottom margins, [background] paints under the
  /// content and [foreground] over everything.
  const new(
    this.size, {
    this.margins = const EdgeInsets.all(72),
    this.columns = 1,
    this.columnGap = 12,
    this.header,
    this.footer,
    this.background,
    this.foreground,
    this.bleed,
  });

  /// The page size.
  final Rect size;

  /// How far the sheet runs past [size] on every side, for content that
  /// is trimmed off in print: with a bleed (0 included), [size] is the
  /// `TrimBox` and the sheet (`MediaBox`, `BleedBox`) is [size] grown by
  /// it; without one (null), the page has no print boxes. Layout is on
  /// [size].
  final double? bleed;

  /// The margins around the content area.
  final EdgeInsets margins;

  /// The number of columns of the content area.
  final int columns;

  /// The space between columns.
  final double columnGap;

  /// The boxes of the top margin for a page.
  final List<LayoutBox> Function(PageInfo page)? header;

  /// The boxes of the bottom margin for a page.
  final List<LayoutBox> Function(PageInfo page)? footer;

  /// Paints under a page's content.
  final void Function(Canvas canvas, PageInfo page)? background;

  /// Paints over a page's content and its header and footer.
  final void Function(Canvas canvas, PageInfo page)? foreground;

  /// The regions content flows through, in order.
  List<Rect> get regions {
    final width = size.width - margins.horizontal;
    final columnWidth = (width - columnGap * (columns - 1)) / columns;
    return [
      for (var i = 0; i < columns; i++)
        Rect(
          size.left + margins.left + i * (columnWidth + columnGap),
          size.bottom + margins.bottom,
          columnWidth,
          size.height - margins.vertical,
        ),
    ];
  }
}

/// Where an anchor ended up.
@immutable
final class AnchorPosition {
  /// [page] (0-based) at ([x], [y]).
  const new(this.page, this.x, this.y);

  /// The page index.
  final int page;

  /// The x coordinate.
  final double x;

  /// The y coordinate (the top of what is anchored).
  final double y;
}

/// Lays boxes out on pages.
final class FlowLayout {
  /// A layout of pages from [template] (or, by name, from [templates],
  /// whose `null` entry is the default), breaking lines with
  /// [lineBreaker] and pages with [pageBreaker]; [pageLabel] writes page
  /// numbers (for references and headers).
  new({
    PageTemplate? template,
    Map<String?, PageTemplate>? templates,
    this.pageBreaker = const DefaultPageBreaker(),
    this.lineBreaker = const FirstFitLineBreaker(),
    String Function(int number)? pageLabel,
    this.maxPasses = 5,
    this.startTemplate,
    this.keepTemplate = false,
    this.templateForPage,
    this.notes = const {},
    this.noteSeparator,
    this.sideNotes = const {},
    this.sideColumn,
    this.sideNoteGap = 2,
  }) : templates = {null: ?template, ...?templates},
       pageLabel = pageLabel ?? _decimal {
    if (this.templates[null] == null) {
      throw ArgumentError('a default page template is needed');
    }
  }

  /// The page templates by name (`null` is the default).
  final Map<String?, PageTemplate> templates;

  /// Decides where content breaks across regions.
  final PageBreaker pageBreaker;

  /// Breaks paragraphs into lines (unless a paragraph has its own).
  final LineBreaker lineBreaker;

  /// Writes a page number.
  final String Function(int number) pageLabel;

  /// The most layouts tried to resolve page references.
  final int maxPasses;

  /// The name of the first page's template (the default when null).
  final String? startTemplate;

  /// Whether a page break's template stays in effect for the pages after
  /// it (until another break names one), rather than for the next page
  /// alone. A break naming another template at the top of a page that's
  /// still empty then replaces that page.
  final bool keepTemplate;

  /// The template of each page, from the page number (1-based) and the
  /// template the content calls for (for margins that differ between recto
  /// and verso pages, say); the one the content calls for when null.
  final PageTemplate Function(PageTemplate template, int number)?
  templateForPage;

  /// Notes by the anchor that refers to them (footnotes): a note is set
  /// at the bottom of the region its anchor is placed in, the region's
  /// content making room for it; what doesn't fit there goes on at the
  /// bottom of the next region.
  final Map<String, LayoutBox> notes;

  /// What is set above the notes of a region (a short rule, say).
  final LayoutBox? noteSeparator;

  /// Notes set beside the text by the anchor that refers to them (a
  /// reference Bible's cross-references in its center column): each in
  /// the page's [sideColumn], in the order their anchors are read, each
  /// level with its anchor (or under the note before it, [sideNoteGap]
  /// apart), above the page's [notes]; what doesn't fit goes on at the top
  /// of the next page's (and is left out after the last page). They take
  /// no room from the text.
  final Map<String, LayoutBox> sideNotes;

  /// The column [sideNotes] are set in on a page, from its number
  /// (1-based) and its template, or null for none there.
  final Rect? Function(int number, PageTemplate template)? sideColumn;

  /// The space between two side notes.
  final double sideNoteGap;

  static String _decimal(int number) => '$number';

  /// The lines of the paragraphs without page references, by paragraph
  /// box and width: kept from one [layout] to the next (the boxes and
  /// breakers are immutable, so the lines are too).
  final Expando<Map<double, List<Line>>> _lines = Expando();

  /// The narrowest and widest lines of the paragraphs without page
  /// references (without their margins and indent).
  final Expando<(double, double)> _intrinsics = Expando();

  /// [content] laid out on pages.
  LayoutResult layout(
    List<LayoutBox> content, {
    LayoutResult? reuse,
    int unchangedBefore = 0,
    Set<int>? changedPages,
  }) {
    var anchors = <String, AnchorPosition>{};
    // Laid out again after a change at or after [unchangedBefore]: the
    // pages before the last clean boundary before it are kept, and the
    // first pass goes on from there.
    _Boundary? resumeAt;
    if (reuse != null && identical(reuse._layout, this)) {
      anchors = reuse.anchors;
      for (final boundary in reuse._boundaries) {
        if (boundary.index > unchangedBefore) break;
        if (boundary.index <= content.length && !boundary.hasReferences) {
          resumeAt = boundary;
        }
      }
    }
    late _Pass pass;
    for (var i = 0; i < maxPasses; i++) {
      pass = _Pass(this, anchors);
      if (i == 0 && resumeAt != null) {
        pass.resume(content, reuse!, resumeAt, changedPages);
      } else {
        pass.run(content);
      }
      final found = pass.anchors;
      final stable =
          found.length == anchors.length &&
          found.entries.every((e) => anchors[e.key]?.page == e.value.page);
      anchors = found;
      if (stable || !pass.hasReferences) break;
    }
    return LayoutResult._(
      this,
      pass.pages,
      anchors,
      pass.tagPages,
      pass.boundaries,
      pass.repeatedAnchors,
    );
  }
}

/// A point between two pages of a pass where nothing is pending (no
/// floating box, deferred note or carried piece) and the rest of the
/// content is the top-level boxes from [index] on: a pass may go on from
/// here as from the start.
final class _Boundary {
  const new({
    required this.index,
    required this.pages,
    required this.template,
    required this.notesSet,
    required this.floatsSet,
    required this.hasReferences,
  });

  /// The first top-level box after the boundary.
  final int index;

  /// The pages before it.
  final int pages;

  /// The template the next page takes.
  final String? template;

  /// The notes placed before it.
  final Set<String> notesSet;

  /// The floating boxes set at a region's edge before it.
  final Set<LayoutBox> floatsSet;

  /// Whether the content before it refers to pages.
  final bool hasReferences;

  /// Whether a pass at [other] goes on as one at this boundary does
  /// (neither referring to pages, whose numbers may have moved).
  bool sameAs(_Boundary other) =>
      index == other.index &&
      pages == other.pages &&
      template == other.template &&
      !hasReferences &&
      !other.hasReferences &&
      notesSet.length == other.notesSet.length &&
      notesSet.containsAll(other.notesSet) &&
      floatsSet.length == other.floatsSet.length &&
      floatsSet.containsAll(other.floatsSet);
}
