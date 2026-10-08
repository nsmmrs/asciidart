// Page layout, independent of any backend: a box tree laid out on pages
// and rendered into a recording document, whose own page type the
// layout hands back, with anchors, links, decorations and page templates.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

final OpenTypeShaper _serif = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);
final TextStyle _body = TextStyle(_serif, 10);

/// The height of a line of body text.
final double _lineHeight = (_serif.ascender - _serif.descender) / 100;

ParagraphBox _para(String text, {LinkTarget? link}) => ParagraphBox(
  Paragraph([TextRun(text, _body, link: link)]),
  orphans: 1,
  widows: 1,
);

/// A page whose region holds [rows] lines of body text.
PageTemplate _rows(
  double rows, {
  void Function(Canvas canvas, PageInfo page)? background,
  void Function(Canvas canvas, PageInfo page)? foreground,
}) => PageTemplate(
  Rect(0, 0, 300, 40 + rows * _lineHeight),
  margins: const EdgeInsets.all(20),
  background: background,
  foreground: foreground,
);

void main() {
  test('lines go on to the next page, in order', () {
    final document = RecordingDocument();
    final words = [for (var i = 1; i <= 10; i++) 'line$i'];
    final pages = FlowLayout(template: _rows(4))
        .layout([_para(words.join('\n'))])
        .render(document);
    expect(pages, hasLength(3));
    expect(pages, document.pages);
    expect(
      [for (final page in pages) page.texts.map((t) => t.trim()).join(' ')],
      ['line1 line2 line3 line4', 'line5 line6 line7 line8', 'line9 line10'],
    );
  });

  test("anchors become the document's, at their page and point", () {
    final document = RecordingDocument();
    final result = FlowLayout(template: _rows(4)).layout([
      _para('a\nb\nc\nd'),
      BlockBox([_para('e')], style: const BoxStyle(anchor: 'second')),
    ])..render(document, destinationName: (anchor) => 'x-$anchor');
    expect(result.pageOf('second'), 2);
    final (page, left, top) = document.anchors['x-second']!;
    expect(page, 1);
    expect(left, 20);
    expect(top, closeTo(document.pages[1].box.top - 20, 1e-6));
  });

  test('as much content as fits with its notes under it', () {
    // Eight rows a page; seven one-line items, each with a one-line note:
    // four items and their notes fill the first page (not seven items with
    // their notes all on the next).
    final document = RecordingDocument();
    final pages =
        FlowLayout(
              template: _rows(8),
              notes: {for (var i = 1; i <= 7; i++) 'n$i': _para('note$i')},
            )
            .layout([
              for (var i = 1; i <= 7; i++)
                BlockBox([_para('item$i')], style: BoxStyle(anchor: 'n$i')),
            ])
            .render(document);
    expect(
      [for (final page in pages) page.texts.map((t) => t.trim()).join(' ')],
      [
        'item1 item2 item3 item4 note1 note2 note3 note4',
        'item5 item6 item7 note5 note6 note7',
      ],
    );
  });

  test('balanced columns: the last region of a set as even as can be', () {
    // Where each line is drawn: its text, x and y.
    Map<String, (double, double)> placed({required bool balance}) {
      final document = RecordingDocument();
      FlowLayout(template: _rows(8))
          .layout([
            ColumnsBox([
              for (var i = 1; i <= 6; i++) _para('l$i'),
            ], balance: balance),
            _para('after'),
          ])
          .render(document);
      return {
        for (final call in document.pages.single.canvas.calls)
          if (RegExp(r'^glyphs "\s*(\S+)\s*" at (\S+) (\S+)').firstMatch(call)
              case final m?)
            m[1]!: (double.parse(m[2]!), double.parse(m[3]!)),
      };
    }

    // Unbalanced, all six lines fit in the first column; balanced, three
    // and three, the paragraph after them right under the third line.
    final plain = placed(balance: false);
    expect(plain['l4']!.$1, plain['l1']!.$1);
    final even = placed(balance: true);
    expect(even['l4']!.$1, greaterThan(even['l1']!.$1));
    expect(even['l4']!.$2, closeTo(even['l1']!.$2, 1e-6));
    expect(even['l6']!.$2, closeTo(even['l3']!.$2, 1e-6));
    expect(even['after']!.$1, even['l1']!.$1);
    expect(even['after']!.$2, lessThan(even['l3']!.$2));
    expect(even['after']!.$2, greaterThan(plain['after']!.$2));
  });

  test('links are made on the page the text is on', () {
    final document = RecordingDocument();
    FlowLayout(template: _rows(4))
        .layout([_para('see', link: const LinkTarget.named('there'))])
        .render(document);
    expect(document.pages.single.links.single, endsWith('-> #there'));
  });

  test('templates and decorations paint on the pages the layout made', () {
    final document = RecordingDocument();
    final order = <String>[];
    final decorated = <LayoutPage>[];
    FlowLayout(
          template: _rows(
            4,
            background: (canvas, page) =>
                order.add('background ${page.number}'),
            foreground: (canvas, page) =>
                order.add('foreground ${page.number}'),
          ),
        )
        .layout([
          BlockBox(
            [_para('a\nb\nc\nd\ne')],
            style: BoxStyle(
              decoration: (page, rect, {required first, required last}) =>
                  decorated.add(page),
            ),
          ),
        ])
        .render(document);
    expect(order, [
      'background 1',
      'foreground 1',
      'background 2',
      'foreground 2',
    ]);
    // The block is split: a piece on each page, decorated there.
    expect(decorated, document.pages);
  });
}
