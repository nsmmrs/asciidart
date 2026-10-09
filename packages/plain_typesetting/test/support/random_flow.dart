// Random documents for the flow layout's equivalence tests: paragraphs,
// blocks, tables, column sets, custom content, notes, floats and page
// references, laid out and painted into an exact recording (every double
// written to its last bit). Only the public API is used, so the same
// documents can be laid out by any version of the package.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

import 'exact_canvas.dart';

final OpenTypeShaper _serif = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);

const _words = [
  'the', 'of', 'and', 'in', 'beginning', 'God', 'created', 'heaven', //
  'earth', 'without', 'form', 'void', 'darkness', 'was', 'upon', 'face', //
  'deep', 'Spirit', 'moved', 'waters', 'light', 'divided', 'firmament', //
  'evening', 'morning', 'were', 'first', 'day', 'gathered', 'together', //
  'unto', 'one', 'place', 'dry', 'land', 'appear', 'grass', 'herb', //
  'yielding', 'seed', 'fruit', 'tree', 'after', 'his', 'kind', 'whose', //
  'itself', 'incomprehensibilities', 'well-known', 'co-operation', //
  'x', 'a', 'I', '—', '“quoted”', 'end.', 'twenty-one', 'Abrahamic', //
];

/// Hyphenates words of six letters or more every third letter.
final class _EveryThird implements Hyphenator {
  const new();

  @override
  List<int> hyphenate(String word) => [
    if (word.length >= 6)
      for (var i = 3; i < word.length - 2; i += 3) i,
  ];
}

/// Text laid out by the content itself: lines of the [heights]
/// given, as many as fit placed (at least one at the top of a region).
final class FakeLines implements CustomContent {
  new(this.name, this.heights, {this.from = 0, this.width = 120});

  final String name;
  final List<double> heights;
  final int from;
  final double width;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    var used = 0.0;
    var end = from;
    while (end < heights.length && used + heights[end] <= available + 1e-6) {
      used += heights[end];
      end++;
    }
    if (end == from) {
      if (!atTop) return null;
      used = heights[end];
      end++;
    }
    final placed = end;
    return CustomPlacement(
      height: used,
      paint: (page, x, top) {
        var y = top;
        for (var i = from; i < placed; i++) {
          page.canvas.rect(Rect(x, y - heights[i], width * 0.9, heights[i]));
          y -= heights[i];
        }
        page.canvas.fill();
      },
      rest: end < heights.length
          ? FakeLines(name, heights, from: end, width: this.width)
          : null,
      anchors: [if (from == 0) ('$name-start', 0, 0), ('$name-$from', 1, 2)],
    );
  }

  @override
  double minHeight(double width) => heights[from];

  @override
  (double, double) intrinsicWidths() => (width / 3, width);
}

/// A random document and the layout for it.
final class RandomFlow {
  new(this.seed) : random = math.Random(seed);

  final int seed;
  final math.Random random;

  int _anchors = 0;
  final Map<String, LayoutBox> notes = {};

  T pick<T>(List<T> values) => values[random.nextInt(values.length)];
  bool chance(int percent) => random.nextInt(100) < percent;
  double between(double low, double high) =>
      low + random.nextDouble() * (high - low);

  TextStyle style() => TextStyle(
    _serif,
    pick([8.5, 10, 11, 14.25]),
    characterSpacing: chance(10) ? 0.3 : 0,
    kerning: chance(80),
    ligatures: chance(30),
  );

  String text(int words) =>
      [for (var i = 0; i < words; i++) pick(_words)]
          .join(chance(5) ? '\n' : ' ');

  List<InlineContent> runs() {
    final base = style();
    return [
      for (var i = 0, n = 1 + random.nextInt(4); i < n; i++)
        switch (random.nextInt(12)) {
          0 => () {
            final name = 'n${seed}_${_anchors++}';
            notes[name] = paragraph(small: true);
            return TextRun('*', base, anchor: name);
          }(),
          1 => PageReference('a${random.nextInt(_anchors + 1)}', base),
          2 => TextRun(
            text(1 + random.nextInt(4)),
            style(),
            link: const UriTarget('https://example.com'),
          ),
          3 => TextRun(' ${text(2)} ', base, anchor: 'a${_anchors++}'),
          _ => TextRun('${text(3 + random.nextInt(25))} ', base),
        },
    ];
  }

  LineHeight lineHeight() => switch (random.nextInt(4)) {
    0 => const LineHeight.multiple(1.4),
    1 => const LineHeight.exact(13),
    2 => const LineHeight.font(leading: 2),
    _ => const LineHeight.font(),
  };

  ParagraphBox paragraph({bool small = false}) => ParagraphBox(
    Paragraph(
      small ? [TextRun(text(4 + random.nextInt(20)), style())] : runs(),
      align: pick(TextAlign.values),
      lineHeight: lineHeight(),
      firstLineIndent: chance(30) ? 12 : 0,
      hyphenator: chance(50) ? const _EveryThird() : null,
      breakLongWords: chance(80),
      hyphenRepetition: chance(20)
          ? HyphenRepetition.always
          : HyphenRepetition.none,
    ),
    style: BoxStyle(
      margin: EdgeInsets(top: pick([0, 3, 6]), bottom: pick([0, 4, 8])),
      anchor: chance(20) ? 'a${_anchors++}' : null,
      keepWithNext: chance(10),
    ),
    orphans: pick([1, 2, 3]),
    widows: pick([1, 2, 3]),
    lineBreaker: switch (random.nextInt(5)) {
      0 => const FirstFitLineBreaker(),
      1 => const KnuthPlassLineBreaker(),
      2 => TypstLineBreaker(fontSize: 9, justify: chance(50)),
      _ => null,
    },
  );

  BoxStyle blockStyle() => BoxStyle(
    margin: EdgeInsets(
      top: pick([0, 6, 12]),
      bottom: pick([0, 6]),
      left: pick([0, 0, 10]),
    ),
    padding: chance(40) ? EdgeInsets.all(pick([2, 6])) : EdgeInsets.zero,
    border: chance(30)
        ? const Border(widths: EdgeInsets.all(1), radius: 2)
        : Border.none,
    background: chance(20) ? const GrayColor(0.9) : null,
    keepTogether: chance(15),
    keepWithNext: chance(10),
    anchor: chance(20) ? 'a${_anchors++}' : null,
    marks: chance(20) ? {'section': 'S${random.nextInt(9)}'} : const {},
    tag: chance(10) ? 'T${random.nextInt(4)}' : null,
    float: chance(8) ? pick(FloatPlacement.values) : null,
    verticalAlign: chance(5) ? VerticalAlign.middle : null,
    cloneEdges: chance(10),
    side: chance(4) ? pick(FloatSide.values) : null,
    sideWidth: 80,
    sideGap: 6,
  );

  TableBox table(int depth) {
    final columns = 1 + random.nextInt(4);
    final rows = 1 + random.nextInt(8);
    // (Header rows short: a header taller than a region repeats forever.)
    final headerRows = random.nextInt(math.min(2, rows - 1) + 1);
    return TableBox(
      [
        for (var r = 0; r < rows; r++)
          TableRow([
            for (var c = 0; c < columns;)
              () {
                final span = chance(15) ? 2 : 1;
                c += span;
                return TableCell(
                  r < headerRows
                      ? [
                          ParagraphBox(Paragraph([TextRun(text(2), style())])),
                        ]
                      : [
                          // (Leaves: tables in narrow cells of tables don't
                          // end.)
                          for (var k = 0, n = 1 + random.nextInt(2); k < n; k++)
                            box(3),
                        ],
                  colSpan: span,
                  rowSpan: r >= headerRows && chance(10) ? 2 : 1,
                  padding: EdgeInsets.all(pick([2, 4])),
                  background: chance(20) ? const GrayColor(0.8) : null,
                  border: const Border(widths: EdgeInsets.all(0.5)),
                  verticalAlign: pick(VerticalAlign.values),
                );
              }(),
          ], minHeight: chance(20) ? 20 : 0),
      ],
      columns: [
        for (var c = 0; c < columns; c++)
          switch (random.nextInt(4)) {
            0 => const ColumnWidth.fixed(60),
            1 => const ColumnWidth.fraction(1),
            2 => const ColumnWidth.fraction(2),
            _ => const ColumnWidth.auto(),
          },
      ],
      headerRows: headerRows,
      shrinkToContent: chance(30),
      align: pick(BoxAlign.values),
      stripes: chance(30) ? const [GrayColor(0.95), null] : const [],
      style: BoxStyle(
        margin: const EdgeInsets(top: 6, bottom: 6),
        keepTogether: chance(10),
        anchor: chance(20) ? 'a${_anchors++}' : null,
      ),
    );
  }

  LayoutBox box(int depth) {
    final leaf = depth >= 3 || chance(45);
    // (Tables and column sets only near the top.)
    final nested = depth >= 2;
    if (leaf) {
      return switch (random.nextInt(20)) {
        0 => SpacerBox(pick([6, 20])),
        1 => DrawingBox(
          pick([1, 30]),
          (canvas, rect) => canvas
            ..rect(rect)
            ..stroke(),
          width: chance(50) ? 100 : null,
          align: pick(BoxAlign.values),
        ),
        2 when depth == 0 => BreakBox.page(force: chance(20)),
        3 when depth == 0 => const BreakBox.column(),
        4 || 5 => CustomBox(
          FakeLines('c${_anchors++}', [
            for (var i = 0, n = 1 + random.nextInt(30); i < n; i++)
              pick([12.0, 12.0, 14.5, 30.0]),
          ]),
          style: BoxStyle(
            margin: EdgeInsets(top: pick([0, 6]), bottom: pick([0, 6])),
            anchor: chance(20) ? 'a${_anchors++}' : null,
          ),
        ),
        _ => paragraph(),
      };
    }
    return switch (random.nextInt(8)) {
      0 when !nested => table(depth),
      1 when !nested => ColumnsBox(
        [for (var i = 0, n = 1 + random.nextInt(6); i < n; i++) box(2)],
        count: pick([2, 3]),
        gap: 10,
        balance: chance(50),
        style: blockStyle(),
      ),
      _ => BlockBox(
        [for (var i = 0, n = 1 + random.nextInt(5); i < n; i++) box(depth + 1)],
        style: blockStyle(),
        repeatedHead: chance(10) ? 1 : 0,
      ),
    };
  }

  /// The document: its content and the layout for it.
  (List<LayoutBox>, FlowLayout) build() {
    final content = [
      for (var i = 0, n = 3 + random.nextInt(10); i < n; i++) box(0),
    ];
    final columns = pick([1, 1, 2]);
    final height = pick(const [300.0, 420.0, 612.0]);
    final layout = FlowLayout(
      template: PageTemplate(
        Rect(0, 0, pick(const [300.0, 396.0, 460.0]), height),
        margins: EdgeInsets.all(pick([24, 36])),
        columns: columns,
        header: chance(50)
            ? (page) => [
                ParagraphBox(
                  Paragraph([
                    TextRun(
                      '${page.label} ${page.mark('section') ?? ''}',
                      TextStyle(_serif, 8),
                    ),
                  ]),
                ),
              ]
            : null,
      ),
      lineBreaker: switch (random.nextInt(3)) {
        0 => const FirstFitLineBreaker(),
        1 => const KnuthPlassLineBreaker(),
        _ => const TypstLineBreaker(),
      },
      notes: notes,
      noteSeparator: chance(50) ? DrawingBox(0.5, (c, r) {}) : null,
      maxPasses: 3,
    );
    return (content, layout);
  }
}

/// [content] laid out by [layout] and painted, exactly, a line a call.
List<String> renderExactly(FlowLayout layout, List<LayoutBox> content) {
  final LayoutResult result;
  try {
    result = layout.layout(content);
    // The layout's own refusal is the outcome compared.
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    // (Content the layout gives up on: that it does is the outcome.)
    return ['error ${error.message}'];
  }
  final document = ExactDocument();
  result.render(document);
  return [
    'pages ${result.pageCount}',
    for (final MapEntry(:key, :value) in result.anchors.entries)
      'anchor $key ${value.page} ${exact(value.x)} ${exact(value.y)}',
    for (final (i, page) in document.pages.indexed) ...[
      'page $i ${exact(page.box)}',
      ...page.canvas.calls,
      ...page.links,
    ],
    ...document.anchors,
  ];
}

/// A 32-bit FNV-1a digest of [lines] (stable across runs and platforms).
String digest(List<String> lines) {
  var hash = 0x811c9dc5;
  for (final line in lines) {
    for (final unit in line.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    hash = ((hash ^ 10) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
