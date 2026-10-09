part of '../flow.dart';

// The pages laid out, rendered into a document.

/// Content laid out on pages, ready to render.
final class LayoutResult {
  new _(
    this._layout,
    this._pages,
    this.anchors,
    this.tagPages,
    this._boundaries,
    this._repeatedAnchors,
    this.unsetSideNotes,
  );

  final FlowLayout _layout;
  final List<_Page> _pages;
  final List<_Boundary> _boundaries;
  final Map<String, List<int>> _repeatedAnchors;

  /// The pages (0-based) [anchor] is placed on, in order: the page of
  /// [anchors]'s position, then those of its repetitions.
  List<int> anchorPages(String anchor) => [
    ?anchors[anchor]?.page,
    ...?_repeatedAnchors[anchor],
  ];

  /// The top-level boxes after which a later layout of the same content
  /// may go on from this one's pages (each the start of a run of pages
  /// nothing before it reaches into).
  List<int> get boundaries => [for (final b in _boundaries) b.index];

  /// The last of [boundaries] with only pages before [page] (0-based)
  /// before it, or 0: a later layout that changes nothing on the pages
  /// before [page] may go on from it.
  int boundaryBefore(int page) {
    var index = 0;
    for (final boundary in _boundaries) {
      if (boundary.pages > page) break;
      index = boundary.index;
    }
    return index;
  }

  /// Where each anchor is.
  final Map<String, AnchorPosition> anchors;

  /// The side notes (see [FlowLayout.sideNotes]) that could not be set
  /// anywhere, by name: the side column was too small for them. Notes
  /// still waiting when the text ends go on pages of their own.
  final List<String> unsetSideNotes;

  /// The first and last page (1-based) of each box with a tag
  /// ([BoxStyle.tag]): a box that breaks across pages has two.
  final Map<String, ({int first, int last})> tagPages;

  /// The number of pages.
  int get pageCount => _pages.length;

  /// The page number of [anchor] (1-based), if it is anchored.
  int? pageOf(String anchor) => switch (anchors[anchor]) {
    AnchorPosition(:final page) => page + 1,
    null => null,
  };

  /// Adds the pages to [document]; anchors become its destinations, named
  /// by [destinationName] (the anchor's name when null).
  List<P> render<P extends LayoutPage>(
    LayoutDocument<P> document, {
    String Function(String anchor)? destinationName,
  }) {
    final rendered = <P>[];
    final carried = <String, String>{};
    for (final (i, page) in _pages.indexed) {
      // A mark's value on a page: the first set on it, else the last
      // carried over.
      final marks = {...carried};
      final top = {...carried};
      final firsts = <String>{};
      for (final (name, value) in page.marks) {
        if (firsts.add(name)) marks[name] = value;
        carried[name] = value;
      }
      final info = PageInfo._(
        i + 1,
        _pages.length,
        _layout.pageLabel(i + 1),
        marks,
        page.template,
        top,
        isEmpty: page.placed.every((p) => (p.$2?.height ?? 0) == 0),
      );
      final template = page.template;
      final size = template.size;
      final P target;
      if (template.bleed case final bleed?) {
        final sheet = Rect(
          size.left - bleed,
          size.bottom - bleed,
          size.width + 2 * bleed,
          size.height + 2 * bleed,
        );
        target = document.addPage(sheet, trimBox: size, bleedBox: sheet);
      } else {
        target = document.addPage(size);
      }
      final painter = _Painter(target.canvas, target);
      template.background?.call(target.canvas, info);
      _running(template.header?.call(info), template, painter, header: true);
      for (final (region, placed) in [...page.placed, ...page.side]) {
        placed?.paint(painter, region.left, region.top);
      }
      _running(template.footer?.call(info), template, painter, header: false);
      template.foreground?.call(target.canvas, info);
      rendered.add(target);
    }
    for (final MapEntry(key: name, value: position) in anchors.entries) {
      document.addAnchor(
        destinationName?.call(name) ?? name,
        rendered[position.page],
        position.x,
        position.y,
      );
    }
    return rendered;
  }

  /// Lays out and paints running content in the top or bottom margin.
  void _running(
    List<LayoutBox>? boxes,
    PageTemplate template,
    _Painter painter, {
    required bool header,
  }) {
    if (boxes == null || boxes.isEmpty) return;
    final size = template.size;
    final margins = template.margins;
    final width = size.width - margins.horizontal;
    final height = header ? margins.top : margins.bottom;
    final pass = _Pass(_layout, anchors).._regionHeight = height;
    // Space in running content is meant: nothing is dropped at its top.
    final fit = pass._place(BlockBox(boxes), width, height, atTop: false);
    final top = header ? size.top : size.bottom + margins.bottom;
    fit.placed?.paint(painter, size.left + margins.left, top);
  }
}
