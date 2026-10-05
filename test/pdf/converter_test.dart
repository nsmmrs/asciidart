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

  for (final name in ['simple']) {
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
}
