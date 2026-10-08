// Compiled to JavaScript in CI: lays out paragraphs and pages in a font of
// made-up metrics, recording what is drawn, and prints a digest; the CI
// job compares it with the Dart VM's, as the results must be the same.
import 'dart:convert';

import 'package:plain_typesetting/plain_typesetting.dart';

/// A font whose advances come from the character codes.
final class _Font implements Font {
  @override
  String get name => 'Made-Up';
  @override
  double get ascender => 800;
  @override
  double get descender => -200;
  @override
  double get lineGap => 90;
  @override
  double get capHeight => 700;
  @override
  double get xHeight => 480;
  @override
  double get underlinePosition => -110;
  @override
  double get underlineThickness => 50;
  @override
  bool covers(int codePoint) => codePoint < 0x250;

  @override
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
  }) => [
    for (final rune in text.runes)
      ShapedGlyph(
        rune,
        String.fromCharCode(rune),
        rune == 0x20 ? 250 : 400 + (rune * 37) % 300,
        kerning && rune == 0x41 ? -30.5 : 0,
      ),
  ];

  @override
  double widthOf(String text, double size, {bool kerning = true}) =>
      [for (final g in shape(text, kerning: kerning)) g.advance + g.kerning]
          .fold<double>(0, (a, b) => a + b) *
      size /
      1000;
}

/// [v] the same on every platform (the VM writes `15.0`, JavaScript `15`).
String _n(double v) => v.toStringAsFixed(4);

/// A page recording the text drawn on it and its positions.
final class _Page implements LayoutPage, Canvas {
  final List<String> out = [];

  @override
  Canvas get canvas => this;
  @override
  void link(Rect rect, LinkTarget target) => out.add('link ${_n(rect.left)}');
  @override
  double glyphs(List<ShapedGlyph> glyphs, double x, double y, TextStyle s) {
    out.add('${glyphs.map((g) => g.text).join()}@${_n(x)},${_n(y)}');
    return s.widthOf(glyphs);
  }

  @override
  double text(String text, double x, double y, TextStyle style) =>
      glyphs(style.shape(text), x, y, style);
  @override
  void noSuchMethod(Invocation invocation) {}
}

final class _Document implements LayoutDocument<_Page> {
  final List<_Page> pages = [];
  final List<String> anchors = [];

  @override
  _Page addPage(Rect mediaBox, {Rect? bleedBox, Rect? trimBox}) {
    final page = _Page();
    pages.add(page);
    return page;
  }

  @override
  void addAnchor(String name, _Page page, double left, double top) =>
      anchors.add('$name ${pages.indexOf(page)} ${_n(left)} ${_n(top)}');
}

const String _text =
    'All human beings are born free and equal in dignity and rights. They '
    'are endowed with reason and conscience and should act towards one '
    'another in a spirit of brotherhood. AVA AVA AVA.';

void main() {
  final style = TextStyle(_Font(), 10.5);
  final document = _Document();
  FlowLayout(
        template: const PageTemplate(
          Rect(0, 0, 200, 120),
          margins: EdgeInsets.all(15),
        ),
      )
      .layout([
        for (final (name, breaker) in [
          ('first-fit', const FirstFitLineBreaker()),
          ('knuth-plass', const KnuthPlassLineBreaker()),
        ])
          for (final align in TextAlign.values)
            BlockBox([
              ParagraphBox(
                Paragraph([TextRun(_text, style)], align: align),
                lineBreaker: breaker,
              ),
            ], style: BoxStyle(anchor: '$name-${align.name}')),
      ])
      .render(document);
  final parts = [
    for (final page in document.pages) ...page.out,
    ...document.anchors,
  ];
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(parts.join('\n'))) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${document.pages.length} pages ${parts.length} $b-$a');
}
