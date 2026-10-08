// Paragraphs, independent of any backend: inline content broken into
// lines by first fit and Knuth-Plass, at UAX #14 opportunities and a
// hyphenator's points, aligned, and painted on a recording canvas with
// their links and anchors.
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

const String _lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do '
    'eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim '
    'ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut '
    'aliquip ex ea commodo consequat.';

List<Line> _lines(
  List<InlineContent> content, {
  double width = 150,
  LineBreaker breaker = const FirstFitLineBreaker(),
  TextAlign align = TextAlign.left,
  Hyphenator? hyphenator,
}) => breaker.breakLines(
  Paragraph(content, align: align, hyphenator: hyphenator),
  (_) => width,
);

String _text(Line line) => [
  for (final fragment in line.fragments)
    if (fragment is TextFragment) fragment.text,
].join();

/// Hyphenates every word after its third letter.
final class _AfterThree implements Hyphenator {
  const new();

  @override
  List<int> hyphenate(String word) => [if (word.length > 5) 3];
}

void main() {
  test('first fit fills each line, and keeps the words in order', () {
    final lines = _lines([TextRun(_lorem, _body)]);
    expect(lines.length, greaterThan(2));
    for (final line in lines) {
      expect(line.width, lessThanOrEqualTo(150 + 1e-6));
    }
    expect(lines.map(_text).join(' ').split(RegExp(r'\s+')), _lorem.split(' '));
    // Each line but the last couldn't take the next word.
    for (var i = 0; i + 1 < lines.length; i++) {
      final next = _text(lines[i + 1]).trim().split(' ').first;
      expect(lines[i].width + _body.measure(' $next'), greaterThan(150 - 1e-6));
    }
  });

  test('Knuth-Plass evens out the lines first fit leaves ragged', () {
    double raggedness(List<Line> lines) => [
      for (final line in lines.take(lines.length - 1))
        (150 - line.width) * (150 - line.width),
    ].fold(0, (a, b) => a + b);
    final firstFit = _lines([TextRun(_lorem, _body)]);
    final knuthPlass = _lines([
      TextRun(_lorem, _body),
    ], breaker: const KnuthPlassLineBreaker());
    expect(
      raggedness(knuthPlass),
      lessThanOrEqualTo(raggedness(firstFit) + 1e-6),
    );
  });

  test('alignment: right and center move the line, justify fills it', () {
    final left = _lines([TextRun(_lorem, _body)]).first;
    final right = _lines([
      TextRun(_lorem, _body),
    ], align: TextAlign.right).first;
    final center = _lines([
      TextRun(_lorem, _body),
    ], align: TextAlign.center).first;
    expect(right.fragments.first.x, closeTo(150 - left.width, 1e-6));
    expect(center.fragments.first.x, closeTo((150 - left.width) / 2, 1e-6));
    final justified = _lines([
      TextRun(_lorem, _body),
    ], align: TextAlign.justify).first;
    final last = justified.fragments.last;
    expect(last.x + last.width, closeTo(150, 1e-6));
  });

  test("a hyphenator's points break words that don't fit", () {
    // "an extraordinary" doesn't fit; "an ext-" does.
    final width = _body.measure('an extra');
    final lines = _lines(
      [TextRun('an extraordinary day', _body)],
      width: width,
      hyphenator: const _AfterThree(),
    );
    expect(lines.first.hyphenated, isTrue);
    expect(_text(lines.first), 'an ext-');
    final plain = _lines([
      TextRun('an extraordinary day', _body),
    ], width: width);
    expect(_text(plain.first).trim(), 'an');
  });

  test('painted: glyph runs at the baseline, colors, links and anchors', () {
    final page = RecordingPage(const Rect(0, 0, 200, 100));
    final calls = page.canvas.calls;
    final links = <(Rect, LinkTarget)>[];
    final anchors = <String>[];
    final line =
        _lines([
          TextRun('See ', _body),
          TextRun(
            'this',
            _body,
            color: const Color.rgb(1, 0, 0),
            link: const LinkTarget.uri('https://example.org'),
            anchor: 'here',
            underline: true,
          ),
        ]).single..paint(
          page.canvas,
          10,
          90,
          link: (rect, target) => links.add((rect, target)),
          anchor: (name, x, y) => anchors.add(name),
        );
    expect(page.texts, ['See ', 'this']);
    expect(calls, contains('fill color rgb 1.00 0.00 0.00'));
    // The underline: a filled rectangle.
    expect(calls.where((c) => c.startsWith('rect')), isNotEmpty);
    expect(links.single.$2, isA<UriTarget>());
    expect(links.single.$1.width, closeTo(_body.measure('this'), 1e-6));
    expect(anchors, ['here']);
    final baseline = 90 - line.baseline;
    expect(page.canvas.calls.first, 'save');
    expect(
      page.canvas.calls,
      contains(
        'glyphs "See " at 10.00 ${baseline.toStringAsFixed(2)} '
        '${_serif.name} 10.00',
      ),
    );
  });
}
