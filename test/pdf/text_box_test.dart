// The Prawn-compatible text box against Prawn itself: the paragraphs of
// fixtures/prawn_text.rb, laid out by Prawn 2.4 with asciidoctor-pdf
// 2.3.27's extensions (fixtures/prawn_text.pdf), and by asciidart, must
// have the same words in the same places.
@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/pdf/fonts.dart';
import 'package:asciidart/src/pdf/markup.dart';
import 'package:asciidart/src/pdf/text_box.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:libpdf/libpdf.dart';
import 'package:test/test.dart';

import '../../tool/pdf_parity.dart';

const String lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do '
    'eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad '
    'minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip '
    'ex ea commodo consequat. Duis aute irure dolor in reprehenderit in '
    'voluptate velit esse cillum dolore eu fugiat nulla pariatur.';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

/// The document of fixtures/prawn_text.rb, laid out by asciidart.
List<int> asciidartPdf() {
  final catalog = FontCatalog(ThemeLoader().load());
  final context = TextContext(fonts: catalog, rootSize: 10.5);
  const size = 10.5;
  const leading = 1.15 * size - size;
  final layout = TextLayout(
    leading: leading,
    initialGap: leading / 2 + catalog.font('Noto Serif').lineGapAt(size),
    paddingBottom: leading / 2,
  );
  const state = TextState(family: 'Noto Serif', size: size);
  final transform = MarkupTransform();
  LayoutBox box(String text, String align) => CustomBox(
    PrawnTextBox(
      transform.apply(parseMarkup(text)!),
      state,
      TextLayout(
        align: align,
        leading: layout.leading,
        initialGap: layout.initialGap,
        paddingBottom: layout.paddingBottom,
      ),
      context,
    ),
    style: const BoxStyle(margin: EdgeInsets(bottom: 12)),
  );
  final result =
      FlowLayout(
        template: const PageTemplate(
          PdfRect(0, 0, 595.28, 841.89),
          margins: EdgeInsets(top: 36, right: 48, bottom: 48, left: 48),
        ),
      ).layout([
        box(lorem, 'justify'),
        box(lorem, 'left'),
        box(
          'Some <strong>bold</strong> and <em>italic</em> text with '
              '<code>code</code> in it, and <a href="https://example.org">a '
              'link</a>.',
          'left',
        ),
        box(
          'Centered text over a couple of lines, to see where each line '
              'starts when it is centered.',
          'center',
        ),
        box('line one<br>line two', 'left'),
        for (var i = 0; i < 30; i++) box(lorem, 'justify'),
      ]);
  final document = PdfDocument();
  result.render(document);
  return document.save();
}

void main() {
  test(
    'paragraphs land where Prawn puts them',
    () {
      final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ours = File('${dir.path}/ours.pdf')
        ..writeAsBytesSync(asciidartPdf());
      final comparison = Comparison(
        facts('test/pdf/fixtures/prawn_text.pdf', dir),
        facts(ours.path, dir),
      );
      expect(comparison.a.pages, comparison.b.pages);
      expect(comparison.text, 1, reason: comparison.wordDiff());
      expect(comparison.geometry.$1, 1, reason: comparison.wordDiff());
      expect(comparison.sameLinks, isTrue);
    },
    skip: ['pdftotext', 'pdftohtml', 'pdfinfo', 'pdftoppm', 'qpdf'].every(_has)
        ? false
        : 'needs poppler and qpdf',
  );
}
