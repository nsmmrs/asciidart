part of '../flow.dart';

// Paragraphs, images, drawings and custom content placed; the widths
// boxes can usefully take.

extension _Leaves on _Pass {
  _Fit _paragraph(
    ParagraphBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    final margin = box.style.margin;
    final lines = _linesOf(box, width - margin.horizontal);
    final from = box._from;
    final top = atTop || from > 0 ? 0.0 : margin.top;
    final heights = [for (final line in lines.skip(from)) line.height];
    final count = layout.pageBreaker.linesThatFit(
      heights,
      available - top,
      orphans: box.orphans,
      widows: box.widows,
      atTop: atTop,
    );
    if (count == 0 && heights.isNotEmpty) return _Fit.moved(box);
    final placed = lines.sublist(from, from + count);
    final done = from + count >= lines.length;
    final height =
        top +
        placed.fold<double>(0, (sum, line) => sum + line.height) +
        (done ? margin.bottom : 0);
    return _Fit(
      _PlacedLines(
        placed,
        margin.left,
        top,
        height,
        from == 0 ? box.style.anchor : null,
        from == 0 ? box.style.marks : const {},
        box.style.tag,
      ),
      height,
      done ? null : ParagraphBox._rest(box, from + count),
    );
  }

  _Fit _image(
    ImageBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    final margin = box.style.margin;
    final top = atTop ? 0.0 : margin.top;
    var w = box.width;
    var h = box.height;
    final room = width - margin.horizontal;
    if (w > room) {
      h *= room / w;
      w = room;
    }
    if (top + h > available + 1e-6) {
      if (!atTop) return _Fit.moved(box);
      if (box.shrinkToFit && available.isFinite) {
        w *= (available - top) / h;
        h = available - top;
      }
    }
    final x =
        margin.left +
        switch (box.align) {
          BoxAlign.left => 0.0,
          BoxAlign.center => (room - w) / 2,
          BoxAlign.right => room - w,
        };
    final height = top + h + margin.bottom;
    return _Fit(
      _PlacedImage(box.image, x, top, w, h, height, box.style.anchor),
      height,
      null,
    );
  }

  _Fit _drawing(
    DrawingBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    final margin = box.style.margin;
    final top = atTop ? 0.0 : margin.top;
    if (top + box.height > available + 1e-6 && !atTop) {
      return _Fit.moved(box);
    }
    final room = width - margin.horizontal;
    final w = math.min(box.width ?? room, room);
    final x =
        margin.left +
        switch (box.align) {
          BoxAlign.left => 0.0,
          BoxAlign.center => (room - w) / 2,
          BoxAlign.right => room - w,
        };
    final height = top + box.height + margin.bottom;
    return _Fit(
      _PlacedDrawing(box.draw, x, top, w, box.height, height, box.style.anchor),
      height,
      null,
    );
  }

  /// The narrowest and the widest [box] can usefully be laid out.
  (double, double) _intrinsic(LayoutBox box) {
    final margin = box.style.margin.horizontal;
    switch (box) {
      case ParagraphBox(:final paragraph):
        final (least, most) = _Pass._hasReferences(paragraph)
            ? _lineExtremes(_resolve(paragraph))
            : layout._intrinsics[paragraph] ??= _lineExtremes(paragraph);
        final indent = paragraph.firstLineIndent;
        return (least + margin + indent, most + margin + indent);
      case BlockBox(:final children):
        final insets =
            margin +
            box.style.border.widths.horizontal +
            box.style.padding.horizontal;
        var least = 0.0;
        var most = 0.0;
        for (final child in children) {
          final (a, b) = _intrinsic(child);
          least = math.max(least, a);
          most = math.max(most, b);
        }
        return (least + insets, most + insets);
      case ColumnsBox(:final children, :final count, :final gap):
        var least = 0.0;
        var most = 0.0;
        for (final child in children) {
          final (a, b) = _intrinsic(child);
          least = math.max(least, a);
          most = math.max(most, b);
        }
        final gaps = gap * (count - 1);
        return (least * count + gaps + margin, most * count + gaps + margin);
      case ImageBox(:final width):
        return (width + margin, width + margin);
      case DrawingBox(:final width):
        return ((width ?? 0) + margin, (width ?? 0) + margin);
      case SpacerBox() || BreakBox():
        return (0, 0);
      case CustomBox(:final content):
        final (a, b) = content.intrinsicWidths();
        return (a + margin, b + margin);
      case TableBox():
        final grid = box._grid ?? _gridOf(box);
        final (mins, maxs) = _columnRanges(box, grid);
        double sum(List<double> values) => values.fold(0, (a, b) => a + b);
        return (sum(mins) + margin, sum(maxs) + margin);
    }
  }

  _Fit _custom(
    CustomBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    final style = box.style;
    final margin = style.margin;
    final top = atTop || box._continued ? 0.0 : margin.top;
    final content = box.content;
    final inner = width - margin.horizontal;
    final room = available - top;
    CustomPlacement? placement;
    if (content is LinedContent) {
      // As many lines as fit and the page breaker keeps; where none fits
      // at the top of a region (or there are none), the content decides.
      final total = content.lineCount(inner);
      final fit = total == 0 ? 0 : content.linesThatFit(inner, room);
      if (total > 0 && (fit > 0 || !atTop)) {
        final keep = layout.pageBreaker.linesToKeep(
          fit,
          total,
          orphans: content.orphans,
          widows: content.widows,
          atTop: atTop,
        );
        if (keep == 0) return _Fit.moved(box);
        placement = content.placeLines(inner, keep);
      }
    }
    placement ??= content.place(inner, room, atTop: atTop);
    if (placement == null) return _Fit.moved(box);
    final rest = placement.rest;
    // Its margin below no more than the room left (a region's end takes
    // what doesn't fit of it).
    final height =
        top +
        placement.height +
        (rest == null
            ? math.min(
                margin.bottom,
                math.max(0.0, available - top - placement.height),
              )
            : 0);
    return _Fit(
      _PlacedCustom(
        placement,
        margin.left,
        top,
        height,
        box._continued ? null : style.anchor,
        box._continued ? const {} : style.marks,
        width: width - margin.horizontal,
        decoration: style.decoration,
        first: !box._continued,
        last: rest == null,
        tag: style.tag,
      ),
      height,
      rest == null ? null : CustomBox._rest(rest, style),
    );
  }
}

/// The widest word and the widest line between forced breaks of
/// [paragraph].
(double, double) _lineExtremes(Paragraph paragraph) {
  var least = 0.0;
  var most = 0.0;
  var word = 0.0;
  var line = 0.0;
  for (final item in paragraphItems(paragraph)) {
    switch (item) {
      case BoxItem(:final width):
        word += width;
        line += width;
      case GlueItem(:final width):
        least = math.max(least, word);
        word = 0;
        line += width;
      case PenaltyItem(:final isForced):
        least = math.max(least, word);
        word = 0;
        if (isForced) {
          most = math.max(most, line);
          line = 0;
        }
    }
  }
  return (math.max(least, word), math.max(most, line));
}
