// LinedContent: custom content whose lines the layout counts, the page
// breaker keeping orphans and widows, the content setting the lines kept.
import 'dart:io';

import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/random_flow.dart';

/// Lines of the given [heights], laid out once (whatever the width): what
/// fits is a prefix of them.
final class Lined implements LinedContent {
  new(
    this.name,
    this.heights, {
    this.from = 0,
    this.orphans = 2,
    this.widows = 2,
    Calls? calls,
  }) : calls = calls ?? Calls();

  final String name;
  final List<double> heights;
  final int from;
  final Calls calls;

  @override
  final int orphans;

  @override
  final int widows;

  @override
  int lineCount(double width) => heights.length - from;

  @override
  int linesThatFit(double width, double available) {
    calls.fit++;
    var used = 0.0;
    var fit = 0;
    while (from + fit < heights.length &&
        used + heights[from + fit] <= available + 1e-6) {
      used += heights[from + fit];
      fit++;
    }
    return fit;
  }

  @override
  CustomPlacement placeLines(double width, int count) {
    calls.lines++;
    final end = from + count;
    var height = 0.0;
    for (var i = from; i < end; i++) {
      height += heights[i];
    }
    return CustomPlacement(
      height: height,
      paint: (page, x, top) {
        var y = top;
        for (var i = from; i < end; i++) {
          page.canvas.rect(Rect(x, y - heights[i], 50 + i.toDouble(), 1));
          y -= heights[i];
        }
      },
      rest: end < heights.length
          ? Lined(
              name,
              heights,
              from: end,
              orphans: orphans,
              widows: widows,
              calls: calls,
            )
          : null,
      anchors: [('$name-$from', 0, 0)],
    );
  }

  /// What a plain [CustomContent] does: the default page breaker's rules
  /// applied by the content itself.
  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    calls.place++;
    final count = const DefaultPageBreaker().linesThatFit(
      heights.sublist(from),
      available,
      orphans: orphans,
      widows: widows,
      atTop: atTop,
    );
    return count == 0 ? null : placeLines(width, count);
  }

  @override
  double minHeight(double width) => heights[from];

  @override
  (double, double) intrinsicWidths() => (40, 80);
}

final class Calls {
  int fit = 0;
  int lines = 0;
  int place = 0;
}

/// [inner] as plain custom content (the layout can't see its lines).
final class Plain implements CustomContent {
  new(this.inner);

  final CustomContent inner;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => switch (inner.place(width, available, atTop: atTop)) {
    null => null,
    final p => CustomPlacement(
      height: p.height,
      paint: p.paint,
      rest: switch (p.rest) {
        null => null,
        final rest => Plain(rest),
      },
      anchors: p.anchors,
    ),
  };

  @override
  double minHeight(double width) => inner.minHeight(width);

  @override
  (double, double) intrinsicWidths() => inner.intrinsicWidths();
}

void main() {
  // (The random documents quick to lay out: those the flow test runs.)
  final seeds = [
    for (final line in File('test/fixtures/flow_digests.txt').readAsLinesSync())
      if (!line.startsWith('#') && !line.endsWith(' skip'))
        int.parse(line.split(' ').first),
  ].take(40);
  FlowLayout pages(double height, {int columns = 1}) => FlowLayout(
    template: PageTemplate(
      Rect(0, 0, 200, height + 20),
      margins: const EdgeInsets.all(10),
      columns: columns,
    ),
  );
  List<int> starts(LayoutResult result, String name) => [
    for (final MapEntry(:key, :value) in result.anchors.entries)
      if (key.startsWith('$name-')) value.page,
  ];

  test('as many lines as fit, the rest on the next page', () {
    final calls = Calls();
    final result = pages(100)
        .layout([CustomBox(Lined('t', List.filled(25, 10), calls: calls))]);
    expect(result.pageCount, 3);
    expect(result.anchors['t-0']!.page, 0);
    expect(result.anchors['t-10']!.page, 1);
    expect(result.anchors['t-20']!.page, 2);
    expect(calls.place, 0);
  });

  test('widows: lines move so that two follow the break', () {
    final result = pages(100)
        .layout([CustomBox(Lined('t', List.filled(11, 10)))]);
    expect(result.anchors['t-9']!.page, 1);
  });

  test('orphans: too few lines at the bottom move on whole', () {
    final result = pages(100).layout([
      CustomBox(Lined('a', List.filled(9, 10), widows: 1)),
      CustomBox(Lined('t', List.filled(5, 10))),
    ]);
    expect(starts(result, 't'), [1]);
  });

  test('no line fits even at the top: the content places itself', () {
    final calls = Calls();
    final result = pages(20).layout([
      CustomBox(Lined('t', [30, 10], calls: calls)),
    ]);
    expect(calls.place, 1);
    expect(result.anchors['t-0']!.page, 0);
    expect(result.anchors['t-1']!.page, 1);
  });

  test('a page breaker of its own decides', () {
    final layout = FlowLayout(
      template: const PageTemplate(
        Rect(0, 0, 200, 120),
        margins: EdgeInsets.all(10),
      ),
      pageBreaker: const _Halves(),
    );
    final result = layout.layout([CustomBox(Lined('t', List.filled(30, 10)))]);
    // Half of the ten lines that fit, each page.
    expect(result.anchors['t-5']!.page, 1);
  });

  test('random documents set as plain custom content would be', () {
    final calls = Calls();
    for (final seed in seeds) {
      final (content, layout) = RandomFlow(
        seed,
        custom: (name, heights) => Lined(name, heights, calls: calls),
      ).build();
      final (plainContent, plainLayout) = RandomFlow(
        seed,
        custom: (name, heights) => Plain(Lined(name, heights)),
      ).build();
      expect(
        renderExactly(layout, content),
        renderExactly(plainLayout, plainContent),
        reason: 'seed $seed',
      );
    }
    // (The lines were counted, not placed by the content.)
    expect(calls.fit, greaterThan(100));
    expect(calls.lines, greaterThan(calls.place));
  });
}

/// Keeps half the lines that fit (all of them when they all fit).
final class _Halves implements PageBreaker {
  const new();

  @override
  int linesThatFit(
    List<double> heights,
    double available, {
    required int orphans,
    required int widows,
    required bool atTop,
  }) => const DefaultPageBreaker().linesThatFit(
    heights,
    available,
    orphans: orphans,
    widows: widows,
    atTop: atTop,
  );

  @override
  int linesToKeep(
    int fit,
    int total, {
    required int orphans,
    required int widows,
    required bool atTop,
  }) => fit >= total ? total : (fit / 2).ceil();

  @override
  bool moveKeptBox(double height, double available, double regionHeight) =>
      const DefaultPageBreaker().moveKeptBox(height, available, regionHeight);
}
