// The PDF converter with asciidoctor-compat (asciidoctor-pdf's look,
// ADR-0015) against asciidoctor-pdf 2.3.27: each document in fixtures/
// was converted by the gem (SOURCE_DATE_EPOCH=0) into
// fixtures/<name>-gem.pdf; asciidart's conversion must have the same
// pages, outline and page labels, and look the same: no page more than
// 0.5% different (tool/pdf_look.dart).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../../tool/pdf_look.dart' show pageDifferences;
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

  /// What differs, by fixture, beyond the 0.5% a page may: the largest
  /// page difference allowed, and why.
  const allowances = {
    // A URL broken after its dots and slashes rather than inside a word,
    // and a word longer than the line broken a character later.
    'hyphens': 0.1,
  };

  /// [pdf] (asciidart's) against [gem]'s: pages, outline, labels and look.
  void expectLooksLike(String gem, String pdf, Directory dir, String name) {
    final comparison = Comparison(facts(gem, dir), facts(pdf, dir));
    expect(comparison.a.pages, comparison.b.pages);
    expect(comparison.sameOutline, isTrue, reason: '${comparison.b.outline}');
    expect(comparison.sameLabels, isTrue);
    final differences = pageDifferences(gem, pdf, '${dir.path}/look');
    final largest = differences.fold<double>(0, math.max);
    expect(
      largest,
      lessThanOrEqualTo(allowances[name] ?? 0.005),
      reason:
          'page ${differences.indexOf(largest) + 1} differs on '
          '${(largest * 100).toStringAsFixed(2)}% of its pixels',
    );
  }

  for (final name in [
    'abstract',
    'apos',
    'article-toc',
    'blocks',
    'blocks2',
    'book',
    'book1',
    'book2',
    'covers',
    'dlists',
    'dlists2',
    'footnotes',
    'footnotes-book',
    'hyphens',
    'icons',
    'images',
    'index',
    'inline-images',
    'lists',
    'media',
    'pdf-pages',
    'prepress',
    'simple',
    'split',
    'tables',
    'tables2',
    'tables3',
    'theme-keys',
    'theme-keys2',
    'toc-book-macro',
    'toc-macro',
    'toc-preamble',
  ]) {
    test('$name.adoc looks as the gem sets it', () {
      final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/$name.pdf';
      convertFile(
        'test/pdf/fixtures/$name.adoc',
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: 'pdf',
          toFile: out,
          attributes: const {'asciidoctor-compat': 'pdf'},
        ),
      );
      expectLooksLike('test/pdf/fixtures/$name-gem.pdf', out, dir, name);
    }, skip: _tools ? false : 'needs poppler and qpdf');
  }

  test('the page mode and the initial zoom come from the theme', () {
    final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = '${dir.path}/theme-keys2.pdf';
    convertFile(
      'test/pdf/fixtures/theme-keys2.adoc',
      AsciidoctorOptions(safe: SafeMode.unsafe, backend: 'pdf', toFile: out),
    );
    final qdf =
        Process.runSync('qpdf', [
              '--qdf',
              '--object-streams=disable',
              out,
              '-',
            ], stdoutEncoding: latin1).stdout
            as String;
    expect(qdf, contains('/PageMode /FullScreen'));
    // In the viewer preferences, where ISO 32000 puts it (the gem writes
    // it in the catalog).
    expect(
      qdf,
      matches(
        RegExp('/ViewerPreferences <<[^>]*/NonFullScreenPageMode /UseThumbs'),
      ),
    );
    expect(qdf, matches(RegExp(r'/OpenAction \[\s*\d+ 0 R\s*/FitH\s+841.89')));
  }, skip: _tools ? false : 'needs poppler and qpdf');

  // The gem's own examples (vendored), converted from where they are.
  for (final name in ['chronicles-example', 'edge-cases']) {
    test("the gem's $name.adoc looks as the gem sets it", () {
      final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/$name.pdf';
      convertFile(
        'vendor/asciidoctor-pdf/test/examples/$name.adoc',
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: 'pdf',
          toFile: out,
          attributes: const {'asciidoctor-compat': 'pdf'},
        ),
      );
      expectLooksLike(
        'test/pdf/fixtures/examples/$name-gem.pdf',
        out,
        dir,
        name,
      );
    }, skip: _tools ? false : 'needs poppler and qpdf');
  }
}
