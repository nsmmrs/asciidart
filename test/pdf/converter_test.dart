// The PDF converter against asciidoctor-pdf 2.3.27: each document in
// fixtures/ was converted by the gem (SOURCE_DATE_EPOCH=0) into
// fixtures/<name>-gem.pdf; asciidart's conversion must put the same words
// in the same places, with the same outline, links and page labels.
@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../../tool/pdf_parity.dart';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

final bool _tools = [
  'pdftotext',
  'pdftohtml',
  'pdfinfo',
  'pdftoppm',
  'qpdf',
].every(_has);

void main() {
  setUpAll(registerPdf);

  for (final name in [
    'abstract',
    'apos',
    'article-toc',
    'blocks',
    'blocks2',
    'book',
    'book1',
    'book2',
    'dlists',
    'dlists2',
    'footnotes',
    'footnotes-book',
    'icons',
    'images',
    'index',
    'inline-images',
    'lists',
    'simple',
    'split',
    'tables',
    'tables2',
    'tables3',
    'toc-book-macro',
    'toc-macro',
    'toc-preamble',
  ]) {
    test('$name.adoc converts as the gem converts it', () {
      final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/$name.pdf';
      convertFile(
        'test/pdf/fixtures/$name.adoc',
        AsciidoctorOptions(safe: SafeMode.unsafe, backend: 'pdf', toFile: out),
      );
      final comparison = Comparison(
        facts('test/pdf/fixtures/$name-gem.pdf', dir),
        facts(out, dir),
      );
      expect(comparison.a.pages, comparison.b.pages);
      expect(comparison.text, 1, reason: comparison.wordDiff());
      expect(comparison.geometry.$1, 1, reason: comparison.wordDiff());
      expect(comparison.sameOutline, isTrue, reason: '${comparison.b.outline}');
      expect(comparison.sameLinks, isTrue);
      expect(comparison.sameLabels, isTrue);
      expect(comparison.pixels, lessThan(1));
    }, skip: _tools ? false : 'needs poppler and qpdf');
  }

  // The gem's own examples (vendored), converted from where they are. In
  // the chronicles a footnote reference after a floated image is drawn in
  // the same place but extracts in another order (the gem's content
  // stream has it earlier), so the words need only be 99.9% in order.
  for (final name in ['chronicles-example', 'edge-cases']) {
    test('the gem\'s $name.adoc converts as the gem converts it', () {
      final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/$name.pdf';
      convertFile(
        'vendor/asciidoctor-pdf/test/examples/$name.adoc',
        AsciidoctorOptions(safe: SafeMode.unsafe, backend: 'pdf', toFile: out),
      );
      final comparison = Comparison(
        facts('test/pdf/fixtures/examples/$name-gem.pdf', dir),
        facts(out, dir),
      );
      expect(comparison.a.pages, comparison.b.pages);
      expect(
        comparison.text,
        greaterThanOrEqualTo(0.999),
        reason: comparison.wordDiff(),
      );
      expect(comparison.geometry.$1, 1, reason: comparison.wordDiff());
      expect(comparison.sameOutline, isTrue);
      expect(comparison.sameLinks, isTrue);
      expect(comparison.sameLabels, isTrue);
      expect(comparison.pixels, lessThan(1));
    }, skip: _tools ? false : 'needs poppler and qpdf');
  }
}
