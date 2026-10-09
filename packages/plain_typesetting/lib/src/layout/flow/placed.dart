part of '../flow.dart';

// What a pass placed, and how it paints.

/// What placing a box gave: the placed part, its height, and the rest
/// (null when all of it was placed).
final class _Fit {
  const new(
    this.placed,
    this.height,
    this.rest, {
    this.hit,
    this.floated = const [],
    this.pinned = const [],
    this.carried = const [],
  });

  /// Nothing placed: all of [box] goes to the next region.
  const new moved(LayoutBox box)
    : placed = null,
      height = 0,
      rest = box,
      hit = null,
      floated = const [],
      pinned = const [],
      carried = const [];

  final _Placed? placed;
  final double height;
  final LayoutBox? rest;

  /// The forced break that ended the placing.
  final BreakBox? hit;

  /// Floating boxes that didn't fit, for the top of the next region.
  final List<LayoutBox> floated;

  /// Floating boxes that fit, for the top or bottom of the region: each
  /// with its top (from the placed part's top) and height.
  final List<(LayoutBox, double, double)> pinned;

  /// What is left of blocks floating to a side ([BoxStyle.side]), for the
  /// top of the next region (each floating to its side).
  final List<LayoutBox> carried;
}

/// Where a block floating to a side is in its region: across from [left]
/// to [right] (from the region's left), down from [top] to [bottom] (from
/// its top; infinite when it goes on in the next region), the blocks
/// beside it [gap] from it.
final class _Exclusion {
  const new(
    this.side,
    this.left,
    this.right, {
    required this.gap,
    required this.top,
    required this.bottom,
  });

  final FloatSide side;
  final double left;
  final double right;
  final double gap;
  final double top;
  final double bottom;
}

final class _Page {
  new(this.template);

  final PageTemplate template;
  final List<(Rect, _Placed?)> placed = [];

  /// The side notes set on the page (see [FlowLayout.sideNotes]).
  final List<(Rect, _Placed?)> side = [];

  /// The top of the highest notes set at the bottom of a region of the
  /// page, which side notes stay above.
  double? notesTop;

  /// The marks set on the page, in order.
  final List<(String, String)> marks = [];
}

/// A placed piece of a box, positioned relative to the top left of the
/// space it was placed in.
sealed class _Placed {
  const new();

  double get height;

  /// Reports the anchors and marks of the piece at ([x], [top]).
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  );

  /// Paints the piece at ([x], [top]).
  void paint(_Painter painter, double x, double top);
}

final class _Painter {
  new(this.canvas, this.page);

  final Canvas canvas;
  final LayoutPage page;
}

final class _PlacedSpace extends _Placed {
  const new(this.height);

  @override
  final double height;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {}

  @override
  void paint(_Painter painter, double x, double top) {}
}

final class _PlacedBlock extends _Placed {
  const new(
    this.style,
    this.width,
    this.height,
    this.children, {
    required this.top,
    required this.openTop,
    required this.openBottom,
    required this.marks,
    required this.anchor,
    this.marginBottom,
  });

  final BoxStyle style;
  final double width;
  @override
  final double height;

  /// The margin below taken (of a last piece), when less than the
  /// style's.
  final double? marginBottom;

  /// The children and their offsets below the content top.
  final List<(double, _Placed)> children;

  /// The top margin taken.
  final double top;

  final bool openTop;
  final bool openBottom;
  final Map<String, String> marks;
  final String? anchor;

  /// Whether the piece has the block's top and bottom edges (padding and
  /// border): the first and last piece's, or every piece's with
  /// [BoxStyle.cloneEdges].
  bool get _topEdge => !openTop || style.cloneEdges;
  bool get _bottomEdge => !openBottom || style.cloneEdges;

  double get _contentTop =>
      top + (_topEdge ? style.border.widths.top + style.padding.top : 0);

  double get _contentLeft =>
      style.margin.left + style.border.widths.left + style.padding.left;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) {
      anchor(name, x + style.margin.left, top - this.top);
    }
    if (style.tag case final name?) tag(name);
    marks.entries.map((e) => (e.key, e.value)).forEach(mark);
    for (final (offset, child) in children) {
      child.visit(
        x + _contentLeft,
        top - _contentTop - offset,
        anchor,
        mark,
        tag,
      );
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final canvas = painter.canvas;
    final border = style.border;
    final left = x + style.margin.left;
    final boxWidth = width - style.margin.horizontal;
    final boxTop = top - this.top;
    final bottomMargin = openBottom ? 0 : marginBottom ?? style.margin.bottom;
    final boxHeight = height - this.top - bottomMargin;
    final rect = Rect(left, boxTop - boxHeight, boxWidth, boxHeight);
    final uniform =
        border.widths.top == border.widths.left &&
        border.widths.left == border.widths.right &&
        border.widths.right == border.widths.bottom &&
        _topEdge &&
        _bottomEdge;
    if (style.background case final background?) {
      canvas
        ..save()
        ..setFillColor(background);
      if (border.radius > 0 && uniform) {
        canvas.roundedRect(rect, border.radius);
      } else {
        canvas.rect(rect);
      }
      canvas
        ..fill()
        ..restore();
    }
    final widths = border.widths;
    if (widths != EdgeInsets.zero) {
      canvas
        ..save()
        ..setStrokeColor(border.color);
      if (uniform && widths.top > 0) {
        final w = widths.top;
        final inset = Rect(
          rect.left + w / 2,
          rect.bottom + w / 2,
          rect.width - w,
          rect.height - w,
        );
        canvas.setLineWidth(w);
        if (border.radius > 0) {
          canvas.roundedRect(inset, math.max(0, border.radius - w / 2));
        } else {
          canvas.rect(inset);
        }
        canvas.stroke();
      } else {
        void side(double w, double x1, double y1, double x2, double y2) {
          if (w <= 0) return;
          canvas
            ..setLineWidth(w)
            ..moveTo(x1, y1)
            ..lineTo(x2, y2)
            ..stroke();
        }

        final Rect(left: l, bottom: b, right: r, top: t) = rect;
        if (_topEdge) {
          side(widths.top, l, t - widths.top / 2, r, t - widths.top / 2);
        }
        if (_bottomEdge) {
          side(
            widths.bottom,
            l,
            b + widths.bottom / 2,
            r,
            b + widths.bottom / 2,
          );
        }
        side(widths.left, l + widths.left / 2, b, l + widths.left / 2, t);
        side(widths.right, r - widths.right / 2, b, r - widths.right / 2, t);
      }
      canvas.restore();
    }
    style.decoration?.call(
      painter.page,
      rect,
      first: _topEdge,
      last: _bottomEdge,
    );
    for (final (offset, child) in children) {
      child.paint(painter, x + _contentLeft, top - _contentTop - offset);
    }
  }
}

final class _PlacedLines extends _Placed {
  const new(
    this.lines,
    this.left,
    this.top,
    this.height,
    this.anchor,
    this.marks,
    this.tag,
  );

  final Map<String, String> marks;

  /// The paragraph's tag ([BoxStyle.tag]).
  final String? tag;

  final List<Line> lines;
  final double left;
  final double top;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
    if (this.tag case final name?) tag(name);
    marks.entries.map((e) => (e.key, e.value)).forEach(mark);
    var y = top - this.top;
    for (final line in lines) {
      for (final fragment in line.fragments) {
        if (fragment case TextFragment(:final run, :final style)
            when run.anchor != null) {
          anchor(
            run.anchor!,
            x + left + fragment.x,
            y - line.baseline + style.font.ascender * style.size / 1000,
          );
        }
      }
      y -= line.height;
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    var y = top - this.top;
    for (final line in lines) {
      line.paint(painter.canvas, x + left, y, link: painter.page.link);
      y -= line.height;
    }
  }
}

final class _PlacedImage extends _Placed {
  const new(
    this.image,
    this.left,
    this.top,
    this.width,
    this.imageHeight,
    this.height,
    this.anchor,
  );

  final Graphic image;
  final double left;
  final double top;
  final double width;
  final double imageHeight;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
  }

  @override
  void paint(_Painter painter, double x, double top) {
    image.paint(
      painter.canvas,
      Rect(x + left, top - this.top - imageHeight, width, imageHeight),
    );
  }
}

final class _PlacedDrawing extends _Placed {
  const new(
    this.draw,
    this.left,
    this.top,
    this.width,
    this.drawingHeight,
    this.height,
    this.anchor,
  );

  final void Function(Canvas canvas, Rect rect) draw;
  final double left;
  final double top;
  final double width;
  final double drawingHeight;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
  }

  @override
  void paint(_Painter painter, double x, double top) {
    painter.canvas.saved(
      () => draw(
        painter.canvas,
        Rect(x + left, top - this.top - drawingHeight, width, drawingHeight),
      ),
    );
  }
}

final class _PlacedCustom extends _Placed {
  const new(
    this.placement,
    this.left,
    this.top,
    this.height,
    this.anchor,
    this.marks, {
    required this.width,
    this.decoration,
    this.first = true,
    this.last = true,
    this.tag,
  });

  final double width;
  final BoxDecoration? decoration;

  /// The box's tag ([BoxStyle.tag]).
  final String? tag;
  final bool first;
  final bool last;

  final CustomPlacement placement;
  final double left;
  final double top;
  @override
  final double height;
  final String? anchor;
  final Map<String, String> marks;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.tag case final name?) tag(name);
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
    marks.entries.map((e) => (e.key, e.value)).forEach(mark);
    for (final (name, dx, dy) in placement.anchors) {
      anchor(name, x + left + dx, top - this.top - dy);
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    decoration?.call(
      painter.page,
      Rect(
        x + left,
        top - this.top - placement.height,
        width,
        placement.height,
      ),
      first: first,
      last: last,
    );
    placement.paint(painter.page, x + left, top - this.top);
  }
}

final class _PlacedColumns extends _Placed {
  const new(this.columns, this.top, this.height);

  final List<(double, _Placed)> columns;
  final double top;
  @override
  final double height;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    for (final (left, column) in columns) {
      column.visit(x + left, top - this.top, anchor, mark, tag);
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    for (final (left, column) in columns) {
      column.paint(painter, x + left, top - this.top);
    }
  }
}

final class _PlacedCell {
  const new(
    this.cell,
    this.x,
    this.y,
    this.width,
    this.height,
    this.content,
    this.contentHeight, {
    required this.openBottom,
    this.stripe,
  });

  final TableCell cell;

  /// The background of the cell's row, for a cell without its own.
  final Color? stripe;

  /// The left edge, from the table's region's left.
  final double x;

  /// The top edge, below the table's top.
  final double y;
  final double width;
  final double height;
  final _Placed? content;
  final double contentHeight;
  final bool openBottom;

  double get _contentTop {
    final padding = cell.padding;
    final room = height - padding.vertical;
    if (cell.verticalOffset case final offset?) {
      return y + padding.top + offset(room, contentHeight);
    }
    return y +
        padding.top +
        switch (cell.verticalAlign) {
          VerticalAlign.top => 0,
          VerticalAlign.middle => (room - contentHeight) / 2,
          VerticalAlign.bottom => room - contentHeight,
        };
  }
}

final class _PlacedTable extends _Placed {
  const new(this.cells, this.height, this.anchor, this.tag, this.borders);

  final List<_PlacedCell> cells;

  /// When the cells' borders are painted.
  final TableBorders borders;

  /// The table's tag ([BoxStyle.tag]).
  final String? tag;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x, top);
    if (this.tag case final name?) tag(name);
    for (final cell in cells) {
      cell.content?.visit(
        x + cell.x + cell.cell.padding.left,
        top - cell._contentTop,
        anchor,
        mark,
        tag,
      );
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final canvas = painter.canvas;
    for (final placed in cells) {
      if (placed.cell.background ?? placed.stripe case final background?) {
        canvas
          ..save()
          ..setFillColor(background)
          ..rect(
            Rect(
              x + placed.x,
              top - placed.y - placed.height,
              placed.width,
              placed.height,
            ),
          )
          ..fill()
          ..restore();
      }
    }
    void content(_PlacedCell placed) => placed.content?.paint(
      painter,
      x + placed.x + placed.cell.padding.left,
      top - placed._contentTop,
    );
    if (borders == TableBorders.withCells) {
      for (final placed in cells) {
        _paintBorder(painter, placed, x, top);
        content(placed);
      }
      return;
    }
    cells.forEach(content);
    for (final placed in cells) {
      _paintBorder(painter, placed, x, top);
    }
  }

  /// Paints the border of [placed] (its decoration, if it has one).
  void _paintBorder(
    _Painter painter,
    _PlacedCell placed,
    double x,
    double top,
  ) {
    final canvas = painter.canvas;
    {
      if (placed.cell.decoration case final decoration?) {
        decoration(
          painter.page,
          Rect(
            x + placed.x,
            top - placed.y - placed.height,
            placed.width,
            placed.height,
          ),
          first: !placed.cell._openTop,
          last: !placed.openBottom,
        );
        return;
      }
      final border = placed.cell.border;
      final widths = border.widths;
      if (widths == EdgeInsets.zero) return;
      final l = x + placed.x;
      final r = l + placed.width;
      final t = top - placed.y;
      final b = t - placed.height;
      canvas
        ..save()
        ..setStrokeColor(border.color);
      void side(double w, double x1, double y1, double x2, double y2) {
        if (w <= 0) return;
        canvas
          ..setLineWidth(w)
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..stroke();
      }

      // Borders are centered on the cell's edges, and the horizontal ones
      // reach over the vertical ones' halves at the corners.
      if (!placed.cell._openTop) {
        side(widths.top, l - widths.left / 2, t, r + widths.right / 2, t);
      }
      if (!placed.openBottom) {
        side(widths.bottom, l - widths.left / 2, b, r + widths.right / 2, b);
      }
      side(widths.left, l, b, l, t);
      side(widths.right, r, b, r, t);
      canvas.restore();
    }
  }
}
