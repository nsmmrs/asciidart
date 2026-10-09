part of '../flow.dart';

// Notes at the bottom of a region, and side notes beside the text.

extension _Notes on _Pass {
  /// Sets the side notes beside their anchors on every page (see
  /// [FlowLayout.sideNotes]), the pages' text as it is.
  void _placeSideNotes() {
    final notes = layout.sideNotes;
    final column = layout.sideColumn;
    if (notes.isEmpty || column == null) return;
    // Each page's notes, in reading order (the left column's, then the
    // right's, as a reference Bible's center column has them).
    final byPage = <int, List<(String, double)>>{};
    for (final MapEntry(:key, :value) in anchors.entries) {
      if (notes.containsKey(key)) {
        (byPage[value.page] ??= []).add((key, value.y));
      }
    }
    // The notes waiting for room, with their names.
    var carried = <(String, LayoutBox)>[];
    unsetSideNotes.clear();
    for (var i = 0; i < pages.length || carried.isNotEmpty; i++) {
      // Notes still waiting when the text has ended go on pages of their
      // own, with only their margin (as long as a page takes one).
      final added = i == pages.length;
      if (added) pages.add(_newPage(null));
      final page = pages[i];
      page.side.clear();
      final full = column(i + 1, page.template);
      if (full == null) {
        if (added) break;
        continue;
      }
      // (Above the page's notes.)
      final area = switch (page.notesTop) {
        final top? when top + layout.sideNoteGap > full.bottom =>
          Rect.fromEdges(
            full.left,
            top + layout.sideNoteGap,
            full.right,
            full.top,
          ),
        _ => full,
      };
      final here = byPage[i] ?? const <(String, double)>[];
      final entries = [
        for (final (name, box) in carried) (name, box, area.top),
        for (final (name, y) in here) (name, notes[name]!, y),
      ];
      carried = [];
      var cursor = area.top;
      for (final (name, box, y) in entries) {
        // After one that didn't fit, the rest wait too, in order.
        if (carried.isNotEmpty) {
          carried.add((name, box));
          continue;
        }
        final top = math.min(y, cursor);
        final room = top - area.bottom;
        // A note goes on whole to the next page (but one taller than the
        // whole column, which is split).
        final whole = _measure(box, area.width);
        if (room <= 0 ||
            (whole > room + 1e-6 && whole <= area.height + 1e-6) ||
            _minHeight(box, area.width) > room + 1e-6) {
          carried.add((name, box));
          continue;
        }
        final fit = _place(box, area.width, room, atTop: true);
        if (fit.placed == null) {
          carried.add((name, box));
          continue;
        }
        page.side.add((
          Rect(area.left, top - fit.height, area.width, fit.height),
          fit.placed,
        ));
        cursor = top - fit.height - layout.sideNoteGap;
        if (fit.rest case final rest?) carried.add((name, rest));
      }
      // A page of its own that takes none of them: they never will.
      if (added && page.side.isEmpty) {
        pages.removeLast();
        break;
      }
    }
    unsetSideNotes.addAll([for (final (name, _) in carried) name]);
  }

  /// [first] (the placing of [content] in [region]) with room made for the
  /// notes its anchors refer to, and the notes placed at the bottom: the
  /// content placed again in less height until its notes fit below it.
  /// Notes that don't fit are deferred to the next region.
  (_Fit, _Fit?) _notes(
    LayoutBox content,
    Rect region,
    _Fit first, {
    List<LayoutBox> bottom = const [],
  }) {
    final width = region.width;
    var fit = first;
    final deferred = _deferredNotes;
    List<LayoutBox> pending(_Fit fit) => [
      ?deferred,
      for (final name in _Pass._anchorsOf(fit.placed))
        if (!_notesSet.contains(name)) ?layout.notes[name],
    ];
    // The bottom of the region: its floating boxes, then its notes under
    // the separator.
    List<LayoutBox> area(List<LayoutBox> notes) => [
      ...bottom,
      if (notes.isNotEmpty) ?layout.noteSeparator,
      ...notes,
    ];
    var notes = pending(fit);
    double total(_Fit fit, List<LayoutBox> notes) =>
        fit.height + _measure(BlockBox(area(notes)), width);
    if ((notes.isNotEmpty || bottom.isNotEmpty) &&
        total(fit, notes) > region.height + 1e-6) {
      // The most content whose notes fit under it: more room places more
      // content, which refers to more notes, so the room is found by
      // halving.
      var low = 0.0;
      var high = fit.height;
      (_Fit, List<LayoutBox>)? best;
      for (var step = 0; step < 12; step++) {
        final room = (low + high) / 2;
        _floatsWaiting = 0;
        final tried = _placeRegion(content, width, room);
        final tryNotes = pending(tried);
        if (total(tried, tryNotes) <= region.height + 1e-6) {
          best = (tried, tryNotes);
          low = room;
        } else {
          high = room;
        }
      }
      // Notes taller than most of the region: as many as fit under what
      // is placed first, the rest on the next region.
      if (best case (final tried, final tryNotes)
          when tried.placed != null && tried.height >= region.height / 4) {
        fit = tried;
        notes = tryNotes;
      } else {
        _floatsWaiting = 0;
        fit = _placeRegion(content, width, region.height);
        notes = pending(fit);
      }
    }
    for (final name in _Pass._anchorsOf(fit.placed)) {
      if (layout.notes.containsKey(name)) _notesSet.add(name);
    }
    _deferredNotes = null;
    if (notes.isEmpty && bottom.isEmpty) return (fit, null);
    final room = region.height - fit.height;
    final placed = _place(BlockBox(area(notes)), width, room, atTop: false);
    if (placed.placed == null || placed.height == 0) {
      // No note fits: all of them on the next region, without a
      // separator; the floating boxes stay, as they were measured to.
      _deferredNotes = notes.isEmpty ? null : BlockBox(notes);
      if (bottom.isEmpty) return (fit, null);
      return (
        fit,
        _place(BlockBox(bottom), width, double.infinity, atTop: false),
      );
    }
    _deferredNotes = placed.rest;
    return (fit, placed);
  }
}
