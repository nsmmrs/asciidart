part of '../flow.dart';

// Column sets, balanced or not.

extension _Columns on _Pass {
  _Fit _columns(
    ColumnsBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    final style = box.style;
    final top = atTop || box._continued ? 0.0 : style.margin.top;
    final inner = width - style.margin.horizontal;
    final columnWidth = (inner - box.gap * (box.count - 1)) / box.count;
    // Too little room for the first box: the set goes on in the next
    // region.
    if (!atTop &&
        !box._continued &&
        box.children.isNotEmpty &&
        _minHeight(box.children.first, columnWidth) > available - top + 1e-6) {
      return _Fit.moved(box);
    }
    // The columns placed in [room]: the tallest's height, what's left, the
    // page break that ended them, and the floating boxes that leave them
    // (spanning them): those for the next region, and those for this
    // one's top or bottom. (Each try counts the floating boxes waiting
    // from where the set started.)
    final waiting = _floatsWaiting;
    _Filled? fill(double room) {
      _floatsWaiting = waiting;
      final columns = <(double, _Placed)>[];
      var height = 0.0;
      LayoutBox? rest = BlockBox(box.children);
      BreakBox? hit;
      final floated = <LayoutBox>[];
      final pinned = <(LayoutBox, double, double)>[];
      for (var c = 0; c < box.count && rest != null; c++) {
        // Each column starts at the top of a region (a break or a margin
        // at the top of the first one counts for nothing too).
        final fit = _place(rest, columnWidth, room, atTop: true);
        if (fit.placed == null) {
          if (c == 0) return null;
          break;
        }
        columns.add((
          style.margin.left + c * (columnWidth + box.gap),
          fit.placed!,
        ));
        height = math.max(height, fit.height);
        rest = fit.rest;
        floated.addAll(fit.floated);
        for (final (pin, y, h) in fit.pinned) {
          pinned.add((pin, top + y, h));
        }
        if (fit.hit case BreakBox(kind: BreakKind.page) && final page) {
          hit = page;
          break;
        }
      }
      return (
        columns: columns,
        height: height,
        rest: rest,
        hit: hit,
        floated: floated,
        pinned: pinned,
      );
    }

    var filled = fill(available - top);
    if (filled == null) return _Fit.moved(box);
    // The set ends here: its columns as short as they can be with all of
    // it in them (found by halving the room; a forced break keeps them, and
    // no try may send a floating box to the next region).
    if (box.balance &&
        filled.rest == null &&
        filled.hit == null &&
        box.count > 1) {
      final kept = filled;
      var low = kept.height / box.count;
      var high = kept.height;
      for (var step = 0; step < 16 && high - low > 0.01; step++) {
        final room = (low + high) / 2;
        final tried = fill(room);
        if (tried != null &&
            tried.rest == null &&
            tried.hit == null &&
            tried.floated.length == kept.floated.length) {
          filled = tried;
          high = room;
        } else {
          low = room;
        }
      }
      // (The counter of floating boxes waiting as the chosen try left it.)
      _floatsWaiting = waiting + filled!.floated.length;
    }
    final (:columns, :height, :rest, :hit, :floated, :pinned) = filled;
    final done = rest == null;
    final total = top + height + (done ? style.margin.bottom : 0);
    return _Fit(
      _PlacedColumns(columns, top, total),
      total,
      done
          ? null
          : ColumnsBox._rest(
              switch (rest) {
                BlockBox(:final children) => children,
                final other => [other],
              },
              box.count,
              box.gap,
              box.balance,
              style,
            ),
      hit: hit,
      floated: floated,
      pinned: pinned,
    );
  }
}

/// A column set's columns placed in some room (see `_Pass._columns`).
typedef _Filled = ({
  List<(double, _Placed)> columns,
  double height,
  LayoutBox? rest,
  BreakBox? hit,
  List<LayoutBox> floated,
  List<(LayoutBox, double, double)> pinned,
});
