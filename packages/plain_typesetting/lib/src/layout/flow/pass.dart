part of '../flow.dart';

// One layout of the content: regions filled with boxes, page by page.

/// One layout of the content.
final class _Pass {
  new(this.layout, this.previous);

  final FlowLayout layout;

  /// The anchors of the previous pass (for page references).
  final Map<String, AnchorPosition> previous;

  final List<_Page> pages = [];

  final Map<String, AnchorPosition> anchors = {};

  /// The first and last page (1-based) of each tagged box.
  final Map<String, ({int first, int last})> tagPages = {};

  /// The lines of the paragraphs with page references, by box and width
  /// (resolved for this pass).
  final Map<(ParagraphBox, double), List<Line>> _lines = {};

  bool hasReferences = false;

  final List<_Boundary> boundaries = [];

  /// The pages (0-based) of the anchors placed more than once, after the
  /// first.
  final Map<String, List<int>> repeatedAnchors = {};

  /// The layout this pass goes on from, and the pages of it that change
  /// (null: all after where it goes on).
  LayoutResult? _reuse;

  Set<int>? _changedPages;

  /// The boundaries of [_reuse] by their box.
  Map<int, (int, _Boundary)> _reuseBoundaries = const {};

  /// The pages taken from [_reuse] (their marks are in them already).
  final Set<int> _kept = {};

  /// Lays [content] out from [boundary] of [reuse] (of the same content
  /// up to it): its pages before the boundary, then the rest, taking its
  /// pages again from a later boundary on when the pass comes to it as
  /// [reuse] did and none of them is in [changedPages].
  void resume(
    List<LayoutBox> content,
    LayoutResult reuse,
    _Boundary boundary,
    Set<int>? changedPages,
  ) {
    _reuse = reuse;
    _changedPages = changedPages;
    if (changedPages != null) {
      _reuseBoundaries = {
        for (final (i, b) in reuse._boundaries.indexed) b.index: (i, b),
      };
    }
    pages.addAll(reuse._pages.take(boundary.pages));
    _kept.addAll(Iterable.generate(boundary.pages));
    _notesSet.addAll(boundary.notesSet);
    _floatsSet.addAll(boundary.floatsSet);
    hasReferences = boundary.hasReferences;
    boundaries.addAll(
      reuse._boundaries.takeWhile((b) => b.index <= boundary.index),
    );
    run(content, from: boundary);
  }

  /// A page of the template named [name], as the page after [pages].
  _Page _newPage(String? name) {
    final template = layout.templates[name] ?? layout.templates[null]!;
    return _Page(
      layout.templateForPage?.call(template, pages.length + 1) ?? template,
    );
  }

  /// Adds [page], with what [carried] holds placed at its top.
  void _add(_Page page, List<_Placed> carried) {
    if (carried.isNotEmpty) {
      final region = page.template.regions.first;
      page.placed.insertAll(0, [
        for (final placed in carried) (region, placed),
      ]);
      carried.clear();
    }
    pages.add(page);
  }

  void run(List<LayoutBox> content, {_Boundary? from}) {
    LayoutBox? rest = from == null
        ? BlockBox(content)
        : from.index < content.length
        ? BlockBox._rest(content.sublist(from.index), const BoxStyle())
        : null;
    var template = from == null ? layout.startTemplate : from.template;
    var guard = 0;
    // What was placed on a page that was replaced (anchors, marks: it had
    // no height), carried to the page replacing it.
    final carried = <_Placed>[];
    // Notes deferred past the end of the content go on on pages of their
    // own.
    // Floating boxes that didn't fit, for the top of the next region.
    final floats = <LayoutBox>[];
    // What is left of blocks floating to a side, for the top of the next
    // region.
    var carriedFloats = <LayoutBox>[];
    while (rest != null ||
        _deferredNotes != null ||
        floats.isNotEmpty ||
        carriedFloats.isNotEmpty) {
      final page = _newPage(template);
      if (!layout.keepTemplate) template = null;
      var discard = false;
      PageSide? side;
      for (final (i, region) in page.template.regions.indexed) {
        _regionHeight = region.height;
        // Floating boxes that waited: at the top of the region, those for
        // the bottom at its bottom.
        final waitingBottom = [
          for (final float in floats)
            if (float.style.float == FloatPlacement.bottom)
              ..._cleared(float, top: false),
        ];
        // (The others at the top, the content starting below them as at
        // the region's top.)
        var waitingTop = [
          for (final float in floats)
            if (float.style.float != FloatPlacement.bottom)
              ..._cleared(float, top: true),
        ];
        final restBox = rest ?? const BlockBox([]);
        // A break the floating boxes waited before: after them, in the
        // flow.
        bool startsWithBreak(LayoutBox box) => switch (box) {
          BreakBox() => true,
          BlockBox(:final children) when children.isNotEmpty => startsWithBreak(
            children.first,
          ),
          _ => false,
        };
        final breakFirst = waitingTop.isNotEmpty && startsWithBreak(restBox);
        final content = breakFirst
            ? BlockBox([...waitingTop, restBox])
            : restBox;
        if (breakFirst) waitingTop = const [];
        floats.clear();
        _floatsWaiting = 0;
        _floatsNotHere.clear();
        final reserved =
            (waitingBottom.isEmpty
                ? 0.0
                : _measure(BlockBox(waitingBottom), region.width)) +
            (waitingTop.isEmpty
                ? 0.0
                : _place(
                    BlockBox(waitingTop),
                    region.width,
                    double.infinity,
                    atTop: true,
                  ).height);
        // What is left of blocks floating to a side: at the top of the
        // region first, the content going around them.
        _seedExclusions = [];
        final carriedHere = carriedFloats;
        carriedFloats = [];
        for (final float in carriedHere) {
          final side = float.style.side!;
          final width = math.min(float.style.sideWidth, region.width);
          var floatTop = 0.0;
          for (final other in _seedExclusions) {
            if (other.side == side) {
              floatTop = math.max(floatTop, other.bottom);
            }
          }
          final floatFit = floatTop.isInfinite
              ? null
              : _withoutExclusions(
                  () => _place(
                    _unsided(float),
                    width,
                    region.height - reserved - floatTop,
                    atTop: true,
                  ),
                );
          if (floatFit?.placed case final piece?) {
            final x = side == FloatSide.right ? region.width - width : 0.0;
            page.placed.add((
              Rect(
                region.left + x,
                region.bottom,
                width,
                region.height - floatTop,
              ),
              piece,
            ));
            _seedExclusions.add(
              _Exclusion(
                side,
                x,
                x + width,
                gap: float.style.sideGap,
                top: floatTop,
                bottom: floatFit!.rest == null
                    ? floatTop + floatFit.height
                    : double.infinity,
              ),
            );
            if (floatFit.rest case final more?) {
              carriedFloats.add(_sided(more, float.style));
            }
          } else {
            carriedFloats.add(float);
          }
        }
        var fit = _placeRegion(content, region.width, region.height - reserved);
        // Floating boxes that fit, at the top or the bottom of the region:
        // the content in what the top ones leave.
        final top = <LayoutBox>[...waitingTop];
        final bottom = <LayoutBox>[...waitingBottom];
        if (fit.pinned.isNotEmpty) {
          fit = _pinFloats(content, region, fit, top, bottom);
        }
        final topFit = top.isEmpty
            ? null
            : _place(BlockBox(top), region.width, region.height, atTop: true);
        final topHeight = topFit?.height ?? 0.0;
        final area = topHeight == 0
            ? region
            : Rect(
                region.left,
                region.bottom,
                region.width,
                region.height - topHeight,
              );
        if (topFit != null) {
          page.placed.add((
            Rect(
              region.left,
              region.bottom + area.height,
              region.width,
              topHeight,
            ),
            topFit.placed,
          ));
        }
        if (layout.notes.isNotEmpty ||
            _deferredNotes != null ||
            bottom.isNotEmpty) {
          final (withNotes, notes) = _notes(content, area, fit, bottom: bottom);
          fit = withNotes;
          page.placed.add((area, fit.placed));
          if (notes != null) {
            page.placed.add((
              Rect(area.left, area.bottom, area.width, notes.height),
              notes.placed,
            ));
            if (notes.height > 0) {
              final top = area.bottom + notes.height;
              page.notesTop = math.max(page.notesTop ?? top, top);
            }
          }
        } else {
          page.placed.add((area, fit.placed));
        }
        rest = fit.rest;
        floats.addAll(fit.floated);
        carriedFloats.addAll(fit.carried);
        if (rest == null &&
            _deferredNotes == null &&
            floats.isEmpty &&
            carriedFloats.isEmpty) {
          break;
        }
        if (fit.hit case BreakBox(
          kind: BreakKind.page,
          template: final name,
          side: final wanted,
        )) {
          side = wanted;
          if (name != null || !layout.keepTemplate) template = name;
          // A break to another template on a page still empty replaces it.
          discard =
              layout.keepTemplate &&
              name != null &&
              i == 0 &&
              (fit.placed?.height ?? 0) == 0;
          break;
        }
      }
      if (discard) {
        carried.addAll([for (final (_, placed) in page.placed) ?placed]);
      } else {
        _add(page, carried);
      }
      // A break to a side: a blank page first when the next page is on
      // the other side.
      if (side != null && PageSide.of(pages.length + 1) != side) {
        _add(_newPage(template), carried);
      }
      // A clean boundary: the rest is the top-level boxes from one on,
      // nothing pending.
      if (carried.isEmpty && floats.isEmpty && _deferredNotes == null) {
        if (rest case BlockBox(:final children, _continued: true)
            when children.isNotEmpty &&
                children.length < content.length &&
                identical(
                  children.first,
                  content[content.length - children.length],
                )) {
          var boundary = _Boundary(
            index: content.length - children.length,
            pages: pages.length,
            template: template,
            notesSet: {..._notesSet},
            floatsSet: Set.identity()..addAll(_floatsSet),
            hasReferences: hasReferences,
          );
          boundaries.add(boundary);
          // The pages of the layout gone on from, up to its next
          // boundary, when this one is the same as its and none of them
          // changes.
          while (true) {
            final (i, old) = _reuseBoundaries[boundary.index] ?? (-1, null);
            if (old == null || !old.sameAs(boundary)) break;
            final reuse = _reuse!;
            final next = i + 1 < reuse._boundaries.length
                ? reuse._boundaries[i + 1]
                : null;
            final end = next?.pages ?? reuse._pages.length;
            if (_changedPages!.any((p) => p >= old.pages && p < end)) break;
            for (final page in reuse._pages.sublist(old.pages, end)) {
              _kept.add(pages.length);
              pages.add(page);
            }
            if (next == null) {
              rest = null;
              break;
            }
            rest = BlockBox._rest(
              content.sublist(next.index),
              const BoxStyle(),
            );
            template = next.template;
            _notesSet
              ..clear()
              ..addAll(next.notesSet);
            _floatsSet
              ..clear()
              ..addAll(next.floatsSet);
            boundaries.add(boundary = next);
          }
        }
      }
      if (++guard > 100000) throw StateError('layout does not progress');
    }
    // A last page with nothing on it (after a trailing page break) is left
    // out.
    if (pages.length > 1 &&
        pages.last.placed.every((p) => (p.$2?.height ?? 0) == 0)) {
      pages.removeLast();
    }
    for (final (i, page) in pages.indexed) {
      final kept = _kept.contains(i);
      for (final (region, placed) in page.placed) {
        placed?.visit(
          region.left,
          region.top,
          (anchor, x, y) {
            if (anchors.containsKey(anchor)) {
              (repeatedAnchors[anchor] ??= []).add(i);
            } else {
              anchors[anchor] = AnchorPosition(i, x, y);
            }
          },
          // (Pages kept from another pass have their marks.)
          kept ? (_) {} : page.marks.add,
          (tag) {
            final first = tagPages[tag]?.first ?? i + 1;
            tagPages[tag] = (first: first, last: i + 1);
          },
        );
      }
    }
    _placeSideNotes();
  }

  /// The side notes that could not be set: the column of a page was too
  /// small for them, or no page has one.
  final List<String> unsetSideNotes = [];

  /// The notes whose anchors were placed (each set once).
  final Set<String> _notesSet = {};

  /// The notes that didn't fit in the region before.
  LayoutBox? _deferredNotes;

  /// The anchors [placed] reports, in order.
  static List<String> _anchorsOf(_Placed? placed) {
    final names = <String>[];
    placed?.visit(0, 0, (name, _, _) => names.add(name), (_) {}, (_) {});
    return names;
  }

  /// The label of the page of [anchor] from the previous pass.
  String? _pageOf(String anchor) => switch (previous[anchor]) {
    AnchorPosition(:final page) => layout.pageLabel(page + 1),
    null => null,
  };

  List<Line> _linesOf(ParagraphBox box, double width) {
    final source = box._source ?? box;
    List<Line> lines() => (source.lineBreaker ?? layout.lineBreaker).breakLines(
      _resolve(source.paragraph),
      (_) => width,
    );
    if (_hasReferences(source.paragraph)) {
      return _lines[(source, width)] ??= lines();
    }
    return (layout._lines[source] ??= {})[width] ??= lines();
  }

  static bool _hasReferences(Paragraph paragraph) =>
      paragraph.content.any((c) => c is PageReference);

  /// [paragraph] with its page references filled in.
  Paragraph _resolve(Paragraph paragraph) {
    if (!_hasReferences(paragraph)) return paragraph;
    hasReferences = true;
    return Paragraph(
      [
        for (final c in paragraph.content)
          if (c case PageReference(:final anchor, :final placeholder))
            c.resolve(_pageOf(anchor) ?? placeholder)
          else
            c,
      ],
      align: paragraph.align,
      lineHeight: paragraph.lineHeight,
      firstLineIndent: paragraph.firstLineIndent,
      hyphenator: paragraph.hyphenator,
      breakLongWords: paragraph.breakLongWords,
    );
  }

  /// The space the last of [children] leaves below the content: its
  /// margin below (and, through a block with nothing closing it, its own
  /// last child's), or a spacer's height.
  double _trailingSpace(List<LayoutBox> children) {
    if (children.isEmpty) return 0;
    final last = children.last;
    return switch (last) {
      SpacerBox(:final height) =>
        height + _trailingSpace(children.sublist(0, children.length - 1)),
      BlockBox(:final children, :final style)
          when style.padding.bottom == 0 && style.border.widths.bottom == 0 =>
        style.margin.bottom + _trailingSpace(children),
      _ => last.style.margin.bottom,
    };
  }

  /// The height of [box] laid out with no limit (beside no block floating
  /// to a side).
  double _measure(LayoutBox box, double width, {bool atTop = false}) =>
      _withoutExclusions(
        () => _place(box, width, double.infinity, atTop: atTop),
      ).height;

  /// The least height [box] needs where it starts (to keep a box with
  /// it).
  double _minHeight(LayoutBox box, double width) {
    final margin = box.style.margin;
    // A block kept together starts whole, when a region holds it.
    if (box is BlockBox && box.style.keepTogether) {
      final whole = _measure(box, width);
      if (whole <= _regionHeight + 1e-6) return whole;
    }
    switch (box) {
      case ParagraphBox(:final orphans):
        final lines = _linesOf(box, width - margin.horizontal);
        return margin.top +
            lines.take(orphans).fold(0, (sum, line) => sum + line.height);
      case BlockBox(:final children) || ColumnsBox(:final children):
        final style = box.style;
        final inner =
            width -
            margin.horizontal -
            style.border.widths.horizontal -
            style.padding.horizontal;
        return margin.top +
            style.border.widths.top +
            style.padding.top +
            (children.isEmpty ? 0 : _minHeight(children.first, inner));
      // A table splits after its first row (its header repeated): that
      // much of it, unless it is kept together.
      case TableBox(:final rows, :final headerRows)
          when box._grid == null &&
              !box.style.keepTogether &&
              rows.length > headerRows + 1:
        return _measure(
          TableBox(
            rows.sublist(0, headerRows + 1),
            columns: box.columns,
            headerRows: headerRows,
            width: box.width,
            shrinkToContent: box.shrinkToContent,
            align: box.align,
            stripes: box.stripes,
            cellsContainMargins: box.cellsContainMargins,
            style: box.style,
          ),
          width,
        );
      case ImageBox() || DrawingBox() || TableBox():
        return _measure(box, width);
      case CustomBox(:final content):
        return margin.top + content.minHeight(width - margin.horizontal);
      case SpacerBox() || BreakBox():
        return 0;
    }
  }

  _Fit _place(
    LayoutBox box,
    double width,
    double available, {
    required bool atTop,
  }) => switch (box) {
    // Nothing floats out of a framed block (padded, bordered, filled or
    // decorated): it stays in its frame.
    BlockBox(:final style)
        when style.padding != EdgeInsets.zero ||
            style.border != Border.none ||
            style.background != null ||
            style.decoration != null =>
      _withoutFloats(() => _block(box, width, available, atTop: atTop)),
    BlockBox() => _block(box, width, available, atTop: atTop),
    ParagraphBox() => _paragraph(box, width, available, atTop: atTop),
    ImageBox() => _image(box, width, available, atTop: atTop),
    DrawingBox() => _drawing(box, width, available, atTop: atTop),
    SpacerBox(:final height) =>
      atTop
          ? const _Fit(_PlacedSpace(0), 0, null)
          : _Fit(
              _PlacedSpace(math.min(height, available)),
              math.min(height, available),
              null,
            ),
    BreakBox() => _Fit(const _PlacedSpace(0), 0, null, hit: box),
    ColumnsBox() => _withoutFloats(() {
      _columnsDepth++;
      try {
        return _columns(box, width, available, atTop: atTop);
      } finally {
        _columnsDepth--;
      }
    }),
    TableBox() => _withoutFloats(
      () => _table(box, width, available, atTop: atTop),
    ),
    CustomBox() => _custom(box, width, available, atTop: atTop),
  };

  _Fit _block(
    BlockBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    // (Where it starts, as measuring below may move it.)
    final (y, left, right) = (_y, _left, _right);
    final style = box.style;
    final continued = box._continued;
    final clone = style.cloneEdges;
    final top =
        (atTop || continued ? 0.0 : style.margin.top) +
        (continued && !clone ? 0 : style.border.widths.top + style.padding.top);
    final bottom = style.padding.bottom + style.border.widths.bottom;
    final inner =
        width -
        style.margin.horizontal -
        style.border.widths.horizontal -
        style.padding.horizontal;
    if (style.keepTogether && !atTop && !continued && available.isFinite) {
      final whole = _measure(box, width);
      final region = _regionHeight;
      if (layout.pageBreaker.moveKeptBox(whole, available, region)) {
        return _Fit.moved(box);
      }
    }
    // A block aligned in the room of its region: the room above it as its
    // top margin, when it fits whole.
    if (style.verticalAlign case final align?
        when align != VerticalAlign.top &&
            atTop &&
            !continued &&
            available.isFinite) {
      // (Its margin below is outside it, and the space its last child
      // leaves below, as CSS's margins collapse through a container's
      // end.)
      final whole =
          _measure(BlockBox(box.children, style: style._lowered(0)), width) -
          style.margin.bottom -
          _trailingSpace(box.children);
      if (whole < available) {
        final room =
            (available - whole) * (align == VerticalAlign.middle ? .5 : 1);
        return _block(
          BlockBox(box.children, style: style._lowered(room)),
          width,
          available,
          atTop: false,
        );
      }
    }
    // The bottom padding and border close the block: a page break inside
    // it reserves no room for them, they need room only below its last
    // child (if they don't fit there, the block is placed again with room
    // for them throughout).
    // (A block whose pieces each close reserves the room throughout.)
    final full = available - top - (clone ? bottom : 0);
    final mark = _exclusions.length;
    _y = y;
    _left = left;
    _right = right;
    final fit = _blockChildren(
      box,
      width,
      inner,
      full,
      top,
      atTop: atTop,
      reserved: clone,
    );
    // (The margin below as placed: no more than the room left.)
    final marginPlaced = switch (fit.placed) {
      _PlacedBlock(:final marginBottom?) => marginBottom,
      _ => style.margin.bottom,
    };
    if (!clone &&
        fit.rest == null &&
        fit.hit == null &&
        bottom > 0 &&
        fit.height - marginPlaced > available + 1e-6) {
      _exclusions.length = mark;
      _y = y;
      _left = left;
      _right = right;
      return _blockChildren(
        box,
        width,
        inner,
        full - bottom,
        top,
        atTop: atTop,
        reserved: true,
      );
    }
    return fit;
  }

  /// [box]'s children placed in [room] below [top]: the block split where
  /// they don't fit, else the whole block.
  _Fit _blockChildren(
    BlockBox box,
    double width,
    double inner,
    double room,
    double top, {
    required bool atTop,
    bool reserved = false,
  }) {
    final style = box.style;
    final continued = box._continued;
    final bottom = style.padding.bottom + style.border.widths.bottom;
    final children = <(double, _Placed)>[];
    final floated = <LayoutBox>[];
    final pinned = <(LayoutBox, double, double)>[];
    final carried = <LayoutBox>[];
    var cursor = 0.0;
    var trailing = 0.0;
    final atTopInside = atTop && top == 0 && !box._containsMargins;
    // Where the content starts in the region, for blocks floating to a
    // side; the blocks floating there before the children.
    final contentY = _y + top;
    final innerLeft =
        _left +
        style.margin.left +
        style.border.widths.left +
        style.padding.left;
    final innerRight =
        _right +
        style.margin.right +
        style.border.widths.right +
        style.padding.right;
    final entryMark = _exclusions.length;
    // [rest] from child [from] on (placed in part when [partial]): the
    // repeated head first when a child after it was placed.
    _Fit split(
      List<LayoutBox> rest, {
      BreakBox? hit,
      int? from,
      bool partial = false,
      bool headOnly = false,
    }) {
      if (children.isEmpty &&
          floated.isEmpty &&
          rest.length == box.children.length &&
          !atTop) {
        _exclusions.length = entryMark;
        return _Fit.moved(box);
      }
      final head = box.repeatedHead;
      final repeat =
          head > 0 &&
          (rest.isNotEmpty || headOnly) &&
          from != null &&
          (partial ? from >= head : from > head);
      // (The space below the last piece placed doesn't carry to the
      // region's end: a piece with its own bottom edge closes right
      // under it.)
      // (A piece the region's end cuts off reaches it when the style
      // says so.)
      final toEnd =
          style.splitToRegionEnd &&
          (rest.isNotEmpty || repeat) &&
          room.isFinite;
      final placed = _PlacedBlock(
        style,
        width,
        // ([room] has the bottom edge's room taken out when [reserved].)
        toEnd
            ? top + room + (reserved ? bottom : 0)
            : top +
                  cursor -
                  (style.cloneEdges ? trailing : 0) +
                  (style.cloneEdges ? bottom : 0),
        children,
        top: atTop || continued ? 0 : style.margin.top,
        openTop: continued,
        openBottom: true,
        marks: continued ? const {} : style.marks,
        anchor: continued ? null : style.anchor,
      );
      return _Fit(
        placed,
        placed.height,
        // A box that ends with a break ends there: nothing of it (not
        // its bottom margin) is carried past the break.
        rest.isEmpty && !repeat
            ? null
            : BlockBox._rest(
                [if (repeat) ...box.children.take(head), ...rest],
                style,
                repeatedHead: head,
                containsMargins: box._containsMargins,
              ),
        hit: hit,
        floated: floated,
        pinned: pinned,
        carried: carried,
      );
    }

    for (var i = 0; i < box.children.length; i++) {
      final child = box.children[i];
      // A floating box set at the top or bottom of a region already.
      if (_floatsSet.contains(child)) {
        _floatsReached.add(child);
        continue;
      }
      final childAtTop = atTopInside && cursor == 0;
      if (child is BreakBox) {
        // With floating boxes waiting (or the rest of one floating to a
        // side), the break comes after them: the region ends here, the
        // break left for after them.
        if (floated.isNotEmpty || _floatsWaiting > 0 || carried.isNotEmpty) {
          return split(box.children.sublist(i), from: i);
        }
        // A break at the top of a region: none, unless forced (or a break
        // to a template, which replaces an empty page).
        if (childAtTop &&
            !child.force &&
            (child.template == null || !layout.keepTemplate) &&
            (child.side == null ||
                PageSide.of(pages.length + 1) == child.side)) {
          continue;
        }
        final rest = box.children.sublist(i + 1);
        return split(rest, hit: child, from: i + 1);
      }
      // A box no floating box may pass: after them, in the next region.
      if (child.style.floatBarrier &&
          !childAtTop &&
          (floated.isNotEmpty || _floatsWaiting > 0)) {
        return split(box.children.sublist(i), from: i);
      }
      // A floating box this region's text no longer reaches (see
      // [_pinFloats]): for the next region.
      if (_floatsNotHere.contains(child) && _floats(child)) {
        floated.add(child);
        _floatsWaiting++;
        continue;
      }
      // A floating box that spans the columns it's in: for the region's
      // top or bottom, measured there (not placed in its column).
      if (child.style.floatSpan &&
          _floatDepth > 0 &&
          _floats(child) &&
          child.style.float != null &&
          child.style.float != FloatPlacement.next) {
        pinned.add((child, top + cursor, 0));
        continue;
      }
      final mark = _exclusions.length;
      final y = contentY + cursor;
      _y = y;
      _left = innerLeft;
      _right = innerRight;
      // A block floating to a side: set there, the blocks after it beside
      // it; what doesn't fit, at the top of the next region.
      if (child.style.side case final side? when _excluding) {
        final left = innerLeft;
        final right = _regionWidth - innerRight;
        final width = math.min(child.style.sideWidth, right - left);
        // (Under one already floating to that side.)
        var floatTop = y;
        for (var moved = true; moved;) {
          moved = false;
          for (final other in _exclusions) {
            if (other.side == side &&
                other.top <= floatTop + 1e-6 &&
                other.bottom > floatTop + 1e-6) {
              floatTop = other.bottom;
              moved = true;
            }
          }
        }
        final floatRoom = room - cursor - (floatTop - y);
        final x = side == FloatSide.right ? right - width : left;
        final floatFit = floatTop.isInfinite || floatRoom <= 0
            ? null
            : _withoutExclusions(
                () => _place(_unsided(child), width, floatRoom, atTop: false),
              );
        if (floatFit?.placed case final piece?) {
          children.add((
            cursor + floatTop - y,
            _PlacedBlock(
              BoxStyle(margin: EdgeInsets(left: x - left)),
              inner,
              floatFit!.height,
              [(0, piece)],
              top: 0,
              openTop: false,
              openBottom: false,
              marks: const {},
              anchor: null,
            ),
          ));
          _exclusions.add(
            _Exclusion(
              side,
              x,
              x + width,
              gap: child.style.sideGap,
              top: floatTop,
              bottom: floatFit.rest == null
                  ? floatTop + floatFit.height
                  : double.infinity,
            ),
          );
          if (floatFit.rest case final rest?) {
            carried.add(_sided(rest, child.style));
          }
        } else {
          carried.add(child);
        }
        continue;
      }
      // Beside blocks floating to a side: a block that fits beside them
      // whole is set there, narrowed; one that doesn't, below them (a
      // block without a frame, its children each so).
      var fit = _Fit.moved(child);
      var placed = false;
      if (_excluding && _exclusions.isNotEmpty && !_transparent(child)) {
        final left = innerLeft;
        final right = _regionWidth - innerRight;
        var narrowLeft = left;
        var narrowRight = right;
        var until = double.infinity;
        for (final other in _exclusions) {
          if (other.top > y + 1e-6 || other.bottom <= y + 1e-6) continue;
          final before = (narrowLeft, narrowRight);
          if (other.side == FloatSide.right) {
            narrowRight = math.min(narrowRight, other.left - other.gap);
          } else {
            narrowLeft = math.max(narrowLeft, other.right + other.gap);
          }
          if ((narrowLeft, narrowRight) != before) {
            until = math.min(until, other.bottom);
          }
        }
        if (narrowLeft > left + 1e-6 || narrowRight < right - 1e-6) {
          // (A block reaching out past its edges with negative margins
          // reaches no nearer the floating block than the gap.)
          final margin = child.style.margin;
          final narrowed = BlockBox(
            [child],
            style: BoxStyle(
              margin: EdgeInsets(
                left:
                    narrowLeft -
                    left +
                    (narrowLeft > left + 1e-6
                        ? math.max(0.0, -margin.left)
                        : 0.0),
                right:
                    right -
                    narrowRight +
                    (narrowRight < right - 1e-6
                        ? math.max(0.0, -margin.right)
                        : 0.0),
              ),
            ),
          );
          final tried = _place(
            narrowed,
            inner,
            room - cursor,
            atTop: childAtTop,
          );
          final beside =
              tried.placed != null &&
              (until.isInfinite ||
                  (tried.rest == null &&
                      tried.hit == null &&
                      tried.height - child.style.margin.bottom <=
                          until - y + 1e-6));
          if (beside) {
            fit = tried;
            placed = true;
          } else {
            _exclusions.length = mark;
            // Below them, if the region goes on that far.
            final skip = until - y;
            if (cursor + skip >= room - 1e-6) {
              return split(box.children.sublist(i), from: i);
            }
            children.add((cursor, _PlacedSpace(skip)));
            cursor += skip;
            trailing = 0;
            i--;
            continue;
          }
        }
      }
      if (!placed) {
        fit = _place(child, inner, room - cursor, atTop: childAtTop);
      }
      if (fit.placed == null &&
          child.style.floating &&
          !childAtTop &&
          _floats(child)) {
        _exclusions.length = mark;
        floated.add(child);
        _floatsWaiting++;
        continue;
      }
      if (fit.placed == null) {
        _exclusions.length = mark;
        return split(box.children.sublist(i), from: i);
      }
      carried.addAll(fit.carried);
      floated.addAll(fit.floated);
      for (final (pin, y, height) in fit.pinned) {
        pinned.add((pin, top + cursor + y, height));
      }
      // A floating box that fits: for the top or bottom of the region.
      if (child.style.float case final float?
          when float != FloatPlacement.next &&
              fit.rest == null &&
              !childAtTop &&
              _floats(child) &&
              (child is BlockBox || child is CustomBox)) {
        pinned.add((child, top + cursor, fit.height));
      }
      if (fit.rest == null &&
          fit.hit == null &&
          child.style.keepWithNext &&
          i + 1 < box.children.length &&
          !childAtTop) {
        final next = _minHeight(box.children[i + 1], inner);
        if (cursor + fit.height + next > room + 1e-6) {
          _exclusions.length = mark;
          carried.removeRange(
            carried.length - fit.carried.length,
            carried.length,
          );
          return split(box.children.sublist(i), from: i);
        }
      }
      children.add((cursor, fit.placed!));
      cursor += fit.height;
      // The space below what was just placed (a spacer, a box's margin).
      trailing = switch (child) {
        SpacerBox() => fit.height,
        _ when fit.rest == null => math.min(
          child.style.margin.bottom,
          fit.height,
        ),
        _ => 0.0,
      };
      if (fit.rest != null || fit.hit != null) {
        return split(
          [?fit.rest, ...box.children.sublist(i + 1)],
          hit: fit.hit,
          from: fit.rest != null ? i : i + 1,
          partial: fit.rest != null,
        );
      }
    }
    // A block with a repeated head whose block floating to a side goes on
    // in the next region: the head goes on there too, beside it.
    if (carried.isNotEmpty && box.repeatedHead > 0 && _excluding) {
      return split(const [], from: box.children.length, headOnly: true);
    }
    // Its margin below no more than the room left (a region's end takes
    // what doesn't fit of it).
    final marginBottom = math.min<double>(
      style.margin.bottom,
      // ([room] has the bottom edge's room taken out when [reserved].)
      math.max<double>(0, room + (reserved ? bottom : 0) - cursor - bottom),
    );
    // Content run past the room it was given with its bottom edge's
    // room reserved (a text box's last line may run its gap below past
    // it): with [BoxStyle.splitToRegionEnd], the region's end cuts the
    // bottom edge off, the block reaching that end.
    final cut =
        reserved && style.splitToRegionEnd && room.isFinite && cursor > room;
    final placed = _PlacedBlock(
      style,
      width,
      cut ? top + room + bottom : top + cursor + bottom + marginBottom,
      children,
      top: atTop || continued ? 0 : style.margin.top,
      openTop: continued,
      openBottom: false,
      marks: continued ? const {} : style.marks,
      anchor: continued ? null : style.anchor,
      marginBottom: cut ? 0 : marginBottom,
    );
    return _Fit(
      placed,
      placed.height,
      null,
      floated: floated,
      pinned: pinned,
      carried: carried,
    );
  }

  /// The floating boxes set at the top or bottom of a region (their place
  /// in the flow is skipped).
  final Set<LayoutBox> _floatsSet = Set.identity();

  /// [box] set at the [top] or bottom of a region: not floating, its
  /// clearance ([BoxStyle.floatClearance]) on the content's side.
  static List<LayoutBox> _cleared(LayoutBox box, {required bool top}) {
    final clearance = box.style.floatClearance;
    if (clearance <= 0) return [_unfloated(box)];
    return top
        ? [_unfloated(box), SpacerBox(clearance)]
        : [SpacerBox(clearance), _unfloated(box)];
  }

  /// [box] (a floating block or custom box) as it is set at the top or
  /// bottom of a region: not floating.
  static LayoutBox _unfloated(LayoutBox box) => switch (box) {
    BlockBox(:final children, :final style) => BlockBox(
      children,
      style: style._unfloated,
    ),
    CustomBox(:final content, :final style) => CustomBox(
      content,
      style: style._unfloated,
    ),
    _ => box,
  };

  /// How many floating boxes wait for the next region in the placing
  /// under way (for float barriers).
  int _floatsWaiting = 0;

  /// The floating boxes set at a region's edge that the last placing of
  /// the content came to (passed over in the flow).
  final Set<LayoutBox> _floatsReached = Set.identity();

  /// The floating boxes that wait for the next region: the text before
  /// them goes on there.
  final Set<LayoutBox> _floatsNotHere = Set.identity();

  /// How deep the placing is in columns or tables, where boxes don't
  /// float.
  int _floatDepth = 0;

  /// Whether [child] may float here: at the top level, or out of columns
  /// when it spans them ([BoxStyle.floatSpan]).
  bool _floats(LayoutBox child) =>
      _floatDepth == 0 ||
      (child.style.floatSpan && _floatDepth == _columnsDepth);

  /// How many of the levels [_floatDepth] counts are columns.
  int _columnsDepth = 0;

  /// [place] with boxes not floating.
  _Fit _withoutFloats(_Fit Function() place) {
    _floatDepth++;
    try {
      return _withoutExclusions(place);
    } finally {
      _floatDepth--;
    }
  }

  // Blocks floating to a side ([BoxStyle.side]).

  /// Whether the blocks being placed go around blocks floating to a side
  /// (in a region's flow, not while measuring or in a framed block).
  bool _excluding = false;

  /// The blocks floating to a side in the region being filled.
  List<_Exclusion> _exclusions = [];

  /// Those carried over from the region before, set at its top.
  List<_Exclusion> _seedExclusions = [];

  /// The width of the region being filled.
  double _regionWidth = 0;

  /// Where the box being placed starts: its top from the region's top,
  /// its edges from the region's.
  double _y = 0;

  double _left = 0;

  double _right = 0;

  /// [place] with no block floating to a side.
  _Fit _withoutExclusions(_Fit Function() place) {
    final saved = _excluding;
    _excluding = false;
    try {
      return place();
    } finally {
      _excluding = saved;
    }
  }

  /// [content] placed in a region [width] wide and [room] high, beside
  /// the blocks floating to a side carried there.
  _Fit _placeRegion(LayoutBox content, double width, double room) {
    _exclusions = [..._seedExclusions];
    _regionWidth = width;
    _y = _left = _right = 0;
    _excluding = true;
    try {
      return _place(content, width, room, atTop: true);
    } finally {
      _excluding = false;
    }
  }

  /// Whether [box] is a block whose children go around blocks floating to
  /// a side each on its own (one without a frame or a keep).
  static bool _transparent(LayoutBox box) =>
      box is BlockBox &&
      box.style.padding == EdgeInsets.zero &&
      box.style.border == Border.none &&
      box.style.background == null &&
      box.style.decoration == null &&
      !box.style.keepTogether &&
      box.style.side == null;

  /// [box] (a block floating to a side) not floating.
  static BlockBox _unsided(LayoutBox box) => switch (box) {
    BlockBox(:final children, :final style) => BlockBox(
      children,
      style: style._unsided,
    ),
    _ => BlockBox([box]),
  };

  /// [rest] (of a block floating to a side as [style] says) floating
  /// again, for the next region.
  static BlockBox _sided(LayoutBox rest, BoxStyle style) => BlockBox(
    [rest],
    style: BoxStyle(
      side: style.side,
      sideWidth: style.sideWidth,
      sideGap: style.sideGap,
    ),
  );

  /// The height of the region being filled (for keep rules).
  double _regionHeight = double.infinity;
}
