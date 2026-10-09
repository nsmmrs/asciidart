part of '../flow.dart';

// Tables: their grid, columns, rows and pieces.

extension _Tables on _Pass {
  /// The rows of [table] with each cell's column, as HTML places them:
  /// each cell in the first column not taken by a cell spanning down from
  /// above.
  List<_GridRow> _gridOf(TableBox table) {
    final n = table.columns.length;
    final busy = List<int>.filled(n, 0);
    final grid = <_GridRow>[];
    for (final (i, row) in table.rows.indexed) {
      final cells = <(int, TableCell)>[];
      final placed = List<int>.filled(n, 0);
      var col = 0;
      for (final cell in row.cells) {
        while (col < n && busy[col] > 0) {
          col++;
        }
        if (col >= n) break;
        final rowSpan = math.min(cell.rowSpan, table.rows.length - i);
        cells.add((
          col,
          rowSpan == cell.rowSpan ? cell : _withRowSpan(cell, rowSpan),
        ));
        for (var k = col; k < math.min(n, col + cell.colSpan); k++) {
          placed[k] = rowSpan;
        }
        col += cell.colSpan;
      }
      for (var k = 0; k < n; k++) {
        busy[k] = placed[k] > 0 ? placed[k] - 1 : math.max(0, busy[k] - 1);
      }
      grid.add(_GridRow(cells, row.minHeight, header: i < table.headerRows));
    }
    return grid;
  }

  /// Each column's narrowest and widest useful width.
  (List<double>, List<double>) _columnRanges(
    TableBox table,
    List<_GridRow> grid,
  ) {
    final n = table.columns.length;
    final mins = List<double>.filled(n, 0);
    final maxs = List<double>.filled(n, 0);
    final spanning = <(int, int, double, double)>[];
    for (final row in grid) {
      for (final (col, cell) in row.cells) {
        final (a, b) = _intrinsic(BlockBox(cell.content));
        final least = a + cell.padding.horizontal;
        final most = b + cell.padding.horizontal;
        final span = math.min(cell.colSpan, n - col);
        if (span == 1) {
          mins[col] = math.max(mins[col], least);
          maxs[col] = math.max(maxs[col], most);
        } else {
          spanning.add((col, span, least, most));
        }
      }
    }
    for (final (col, span, least, most) in spanning) {
      final columns = [for (var c = col; c < col + span; c++) c];
      final haveMin = columns.fold<double>(0, (s, c) => s + mins[c]);
      if (least > haveMin) {
        for (final c in columns) {
          mins[c] += (least - haveMin) / span;
        }
      }
      final haveMax = columns.fold<double>(0, (s, c) => s + maxs[c]);
      if (most > haveMax) {
        for (final c in columns) {
          maxs[c] += (most - haveMax) / span;
        }
      }
    }
    for (var c = 0; c < n; c++) {
      maxs[c] = math.max(maxs[c], mins[c]);
    }
    return (mins, maxs);
  }

  /// The columns' widths in [available]: fixed columns as given, auto
  /// columns from their content (as CSS's automatic table layout shares
  /// space), fraction columns sharing what is left.
  List<double> _columnWidths(
    TableBox table,
    List<_GridRow> grid,
    double available,
  ) {
    final (mins, maxs) = _columnRanges(table, grid);
    final n = table.columns.length;
    final widths = List<double>.filled(n, 0);
    final autos = <int>[];
    final fractions = <int>[];
    var fixed = 0.0;
    final whole = table.width ?? available;
    for (final (c, column) in table.columns.indexed) {
      switch (column) {
        case FixedColumnWidth(:final points):
          widths[c] = points;
          fixed += points;
        case ComputedColumnWidth(:final width):
          widths[c] = math.max(0, width(whole));
          fixed += widths[c];
        case FractionColumnWidth():
          fractions.add(c);
        case AutoColumnWidth():
          autos.add(c);
      }
    }
    double sum(List<int> columns, List<double> values) =>
        columns.fold(0, (s, c) => s + values[c]);
    var total = whole;
    if (table.shrinkToContent && fractions.isEmpty) {
      total = math.min(total, fixed + sum(autos, maxs));
    }
    final rest = total - fixed;

    void spread(List<int> columns, double room, {required bool grow}) {
      final least = sum(columns, mins);
      final most = sum(columns, maxs);
      for (final c in columns) {
        if (most <= room) {
          widths[c] =
              maxs[c] +
              (grow
                  ? (room - most) *
                        (most > 0 ? maxs[c] / most : 1 / columns.length)
                  : 0);
        } else if (least <= room) {
          widths[c] =
              mins[c] +
              (room - least) *
                  (most > least ? (maxs[c] - mins[c]) / (most - least) : 0);
        } else {
          widths[c] = least > 0
              ? mins[c] * room / least
              : room / columns.length;
        }
      }
    }

    if (fractions.isEmpty) {
      spread(autos, rest, grow: true);
    } else {
      final room = math.max<double>(0, rest - sum(fractions, mins));
      spread(autos, math.min(room, sum(autos, maxs)), grow: false);
      final left = math.max<double>(0, rest - sum(autos, widths));
      final weights = fractions.fold<double>(
        0,
        (s, c) => s + (table.columns[c] as FractionColumnWidth).weight,
      );
      for (final c in fractions) {
        final weight = (table.columns[c] as FractionColumnWidth).weight;
        widths[c] = weights > 0 ? left * weight / weights : 0;
      }
    }
    return widths;
  }

  double _cellWidth(int col, TableCell cell, List<double> widths) {
    var width = 0.0;
    for (var c = col; c < math.min(widths.length, col + cell.colSpan); c++) {
      width += widths[c];
    }
    return width;
  }

  /// The heights of [rows] (cells spanning down add to the last row they
  /// span).
  List<double> _rowHeights(List<_GridRow> rows, List<double> widths) {
    final heights = [for (final row in rows) row.minHeight];
    final spans = <(int, int, double)>[];
    for (final (i, row) in rows.indexed) {
      for (final (col, cell) in row.cells) {
        final width = _cellWidth(col, cell, widths) - cell.padding.horizontal;
        final needs =
            _measure(BlockBox(cell.content), width) + cell.padding.vertical;
        final span = math.min(cell.rowSpan, rows.length - i);
        if (span == 1) {
          heights[i] = math.max(heights[i], needs);
        } else {
          spans.add((i, span, needs));
        }
      }
    }
    for (final (i, span, needs) in spans) {
      final have = heights
          .sublist(i, i + span)
          .fold<double>(0, (a, b) => a + b);
      if (needs > have) heights[i + span - 1] += needs - have;
    }
    return heights;
  }

  /// The last row of the group starting at [start]: rows joined by cells
  /// spanning down.
  int _groupEnd(List<_GridRow> rows, int start) {
    var end = start;
    for (var i = start; i <= end && i < rows.length; i++) {
      for (final (_, cell) in rows[i].cells) {
        end = math.max(end, math.min(rows.length - 1, i + cell.rowSpan - 1));
      }
    }
    return end;
  }

  _Fit _table(
    TableBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    final style = box.style;
    final continued = box._grid != null;
    if (style.keepTogether && !atTop && !continued && available.isFinite) {
      final whole = _measure(box, width);
      if (layout.pageBreaker.moveKeptBox(whole, available, _regionHeight)) {
        return _Fit.moved(box);
      }
    }
    final margin = style.margin;
    final top = atTop || continued ? 0.0 : margin.top;
    final room = width - margin.horizontal;
    final grid = box._grid ?? _gridOf(box);
    final widths = box._widths ?? _columnWidths(box, grid, room);
    final tableWidth = widths.fold<double>(0, (a, b) => a + b);
    final left =
        margin.left +
        switch (box.align) {
          BoxAlign.left => 0.0,
          BoxAlign.center => (room - tableWidth) / 2,
          BoxAlign.right => room - tableWidth,
        };
    final columnLeft = [
      for (var c = 0, x = left; c < widths.length; x += widths[c], c++) x,
    ];
    final cells = <_PlacedCell>[];
    final space = available - top;
    var used = 0.0;

    /// Places [cell] (at [col]) [height] tall at [y]; returns the rest of
    /// its content if it didn't all fit.
    LayoutBox? cellAt(
      int col,
      TableCell cell,
      double y,
      double height, {
      required bool openBottom,
      Color? stripe,
    }) {
      final width = _cellWidth(col, cell, widths);
      final padding = cell.padding;
      final fit = _place(
        BlockBox(cell.content),
        width - padding.horizontal,
        height - padding.vertical,
        atTop: true,
      );
      cells.add(
        _PlacedCell(
          cell,
          columnLeft[col],
          y,
          width,
          height,
          fit.placed,
          fit.height,
          openBottom: openBottom || fit.rest != null,
          stripe: stripe,
        ),
      );
      return fit.rest;
    }

    // The body rows placed in this region, for the stripes.
    var stripeIndex = 0;
    Color? nextStripe({required bool body}) {
      if (!body || box.stripes.isEmpty) return null;
      return box.stripes[stripeIndex++ % box.stripes.length];
    }

    void placeRows(
      List<_GridRow> rows,
      List<double> heights, {
      bool body = true,
    }) {
      var y = top + used;
      for (final (i, row) in rows.indexed) {
        final stripe = nextStripe(body: body);
        for (final (col, cell) in row.cells) {
          final span = math.min(cell.rowSpan, rows.length - i);
          final height = heights
              .sublist(i, i + span)
              .fold<double>(0, (a, b) => a + b);
          cellAt(col, cell, y, height, openBottom: false, stripe: stripe);
        }
        y += heights[i];
      }
      used += heights.fold<double>(0, (a, b) => a + b);
    }

    final headers = [
      for (final row in grid)
        if (row.header) row,
    ];
    final body = [
      for (final row in grid)
        if (!row.header) row,
    ];
    final headerHeights = _rowHeights(headers, widths);
    final headerHeight = headerHeights.fold<double>(0, (a, b) => a + b);
    if (headerHeight > space + 1e-6 && !atTop) return _Fit.moved(box);
    placeRows(headers, headerHeights, body: false);

    List<_GridRow>? rest;
    var placedBody = 0;
    var i = 0;
    while (i < body.length) {
      final end = _groupEnd(body, i);
      final group = body.sublist(i, end + 1);
      final heights = _rowHeights(group, widths);
      final groupHeight = heights.fold<double>(0, (a, b) => a + b);
      if (used + groupHeight <= space + 1e-6) {
        placeRows(group, heights);
        placedBody += group.length;
        i = end + 1;
        continue;
      }
      if (placedBody > 0) {
        rest = body.sublist(i);
        break;
      }
      if (!atTop) return _Fit.moved(box);
      // At the top of a region and still too tall: split the group.
      final room = space - used;
      var fitting = 0;
      var fittingHeight = 0.0;
      while (fitting < group.length &&
          fittingHeight + heights[fitting] <= room + 1e-6) {
        fittingHeight += heights[fitting];
        fitting++;
      }
      final restRows = <_GridRow>[];
      if (fitting > 0) {
        final carried = <(int, TableCell)>[];
        var y = top + used;
        for (var r = 0; r < fitting; r++) {
          final stripe = nextStripe(body: true);
          for (final (col, cell) in group[r].cells) {
            final span = math.min(cell.rowSpan, group.length - r);
            if (r + span <= fitting) {
              final height = heights
                  .sublist(r, r + span)
                  .fold<double>(0, (a, b) => a + b);
              cellAt(col, cell, y, height, openBottom: false, stripe: stripe);
            } else {
              final height = heights
                  .sublist(r, fitting)
                  .fold<double>(0, (a, b) => a + b);
              final left = cellAt(
                col,
                cell,
                y,
                height,
                openBottom: true,
                stripe: stripe,
              );
              carried.add((
                col,
                TableCell._rest(cell, [?left], r + span - fitting),
              ));
            }
          }
          y += heights[r];
        }
        used += fittingHeight;
        final next = group[fitting];
        restRows
          ..add(
            _GridRow(
              [...next.cells, ...carried]..sort((a, b) => a.$1 - b.$1),
              next.minHeight,
            ),
          )
          ..addAll(group.sublist(fitting + 1));
      } else {
        // Not even one row fits: split the first row's cells.
        final row = group.first;
        final carried = <(int, TableCell)>[];
        final stripe = nextStripe(body: true);
        for (final (col, cell) in row.cells) {
          final span = math.min(cell.rowSpan, group.length);
          final left = cellAt(
            col,
            cell,
            top + used,
            room,
            openBottom: true,
            stripe: stripe,
          );
          carried.add((col, TableCell._rest(cell, [?left], span)));
        }
        used += room;
        restRows
          ..add(_GridRow(carried, 0))
          ..addAll(group.sublist(1));
      }
      rest = [...restRows, ...body.sublist(end + 1)];
      break;
    }
    final height = top + used + (rest == null ? margin.bottom : 0);
    return _Fit(
      _PlacedTable(
        cells,
        height,
        rest == null ? style.anchor : null,
        style.tag,
      ),
      height,
      rest == null ? null : TableBox._rest(box, [...headers, ...rest], widths),
    );
  }
}

TableCell _withRowSpan(TableCell cell, int rowSpan) => TableCell(
  cell.content,
  colSpan: cell.colSpan,
  rowSpan: rowSpan,
  padding: cell.padding,
  background: cell.background,
  border: cell.border,
  verticalAlign: cell.verticalAlign,
);
