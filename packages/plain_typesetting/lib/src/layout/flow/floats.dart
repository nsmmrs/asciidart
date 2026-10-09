part of '../flow.dart';

// Floating boxes pinned to a region's top or bottom.

extension _Floats on _Pass {
  /// [first] (the placing of [content] in [region]) with the floating
  /// boxes it placed that fit taken out of the flow, for the top of the
  /// region ([top]) or its bottom ([bottom]): the content placed again in
  /// the height they leave.
  _Fit _pinFloats(
    LayoutBox content,
    Rect region,
    _Fit first,
    List<LayoutBox> top,
    List<LayoutBox> bottom,
  ) {
    var fit = first;
    // The floating boxes pinned here, with what each added to its edge.
    final pinned = <LayoutBox, List<LayoutBox>>{};
    double measured(List<LayoutBox> boxes) =>
        boxes.isEmpty ? 0 : _measure(BlockBox(boxes), region.width);
    void place() {
      _floatsWaiting = 0;
      _floatsReached.clear();
      fit = _placeRegion(
        content,
        region.width,
        region.height - measured(top) - measured(bottom),
      );
    }

    for (var attempt = 0; attempt < 4 && fit.pinned.isNotEmpty; attempt++) {
      var added = false;
      for (final (box, y, height) in fit.pinned) {
        if (!_floatsSet.add(box)) continue;
        added = true;
        // (Auto: at the top if its middle, placed in the flow, would be
        // in the region's upper half, the floats placed already taking
        // their room; at the bottom otherwise.)
        final atTop = switch (box.style.float) {
          FloatPlacement.top => true,
          FloatPlacement.bottom => false,
          _ =>
            measured(top) + measured(bottom) + y + height / 2 <=
                region.height / 2,
        };
        final cleared = _Pass._cleared(box, top: atTop);
        // (Too tall for the room the floats already pinned leave: the next
        // region's.)
        if (measured([...top, ...bottom, ...cleared]) > region.height) {
          _floatsSet.remove(box);
          _floatsNotHere.add(box);
          continue;
        }
        (atTop ? top : bottom).addAll(cleared);
        pinned[box] = cleared;
      }
      if (!added) break;
      place();
      // A box the content no longer reaches in the room left (the text
      // before it now goes on in the next region): it waits for the next
      // region: a float never comes before the text it belongs to (as
      // LaTeX's floats, which never precede their reference point).
      final unreached = [
        for (final box in pinned.keys)
          if (!_floatsReached.contains(box)) box,
      ];
      if (unreached.isNotEmpty) {
        for (final box in unreached) {
          for (final piece in pinned.remove(box)!) {
            top.remove(piece);
            bottom.remove(piece);
          }
          _floatsSet.remove(box);
          _floatsNotHere.add(box);
        }
        place();
      }
    }
    return fit;
  }
}
