/// PDFs and EPUBs through the API: `convertToBytes`, the `fonts` option,
/// `convertFile` with a file format.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidart/asciidart.dart';
import 'package:asciidart/io.dart';
import 'package:asciidart/src/font_index.dart';
import 'package:test/test.dart';

/// The fonts vendored with asciidoctor-pdf, given as bytes.
List<FontFile> _vendoredFonts() => [
  for (final dir in [
    'vendor/asciidoctor-pdf/data/fonts',
    'vendor/asciidoctor-pdf/icons',
  ])
    for (final file in Directory(dir).listSync(recursive: true))
      if (file is File && file.path.endsWith('.ttf'))
        FontFile(file.uri.pathSegments.last, file.readAsBytesSync()),
];

const _source = '= Doc\n:icons: font\n\nHello *bold* `code` icon:heart[]\n';

/// The same date in every conversion, so that their bytes compare.
const _date = {'localdatetime': '2020-01-01 00:00:00 +0000', 'jobs': '1'};

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('asciidart-bytes.');
    // A machine without fonts: what the conversions find, they were given.
    FontIndex.installed = FontIndex([
      '${tmp.path}/no-fonts',
    ], cacheFile: '${tmp.path}/cache.tsv');
  });
  tearDown(() {
    FontIndex.installed = null;
    tmp.deleteSync(recursive: true);
  });

  test('a PDF, in the fonts given', () {
    final diagnostics = <Diagnostic>[];
    final pdf = Asciidart(
      fonts: _vendoredFonts(),
      onDiagnostic: diagnostics.add,
    ).convertToBytes(_source, backend: Backend.pdf, attributes: _date);
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(
      diagnostics.where((d) => d.message.contains('not installed')),
      isEmpty,
    );
  });

  test('without the fonts, built-in ones stand in, with warnings', () {
    final diagnostics = <Diagnostic>[];
    final pdf = Asciidart(onDiagnostic: diagnostics.add)
        .convertToBytes(_source, backend: Backend.pdf, attributes: _date);
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(
      diagnostics.map((d) => d.message),
      contains(contains('font family Noto Serif is not installed')),
    );
  });

  test('fonts given as WOFF and WOFF2', () {
    final diagnostics = <Diagnostic>[];
    final pdf = Asciidart(
      fonts: [
        for (final name in [
          'notoserif-regular-ascii.woff2',
          'notoserif-bold-ascii.woff',
        ])
          FontFile(name, File('test/fixtures/fonts/$name').readAsBytesSync()),
      ],
      onDiagnostic: diagnostics.add,
    ).convertToBytes('Hello *bold*\n', backend: Backend.pdf, attributes: _date);
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    final messages = [for (final d in diagnostics) d.message];
    expect(messages, isNot(contains(contains('not installed'))));
  });

  test('the asynchronous conversion makes the same bytes', () async {
    final ad = Asciidart(fonts: _vendoredFonts());
    final sync = ad.convertToBytes(
      _source,
      backend: Backend.pdf,
      attributes: _date,
    );
    final async = await ad.convertToBytesAsync(
      _source,
      backend: Backend.pdf,
      attributes: _date,
    );
    expect(async, sync);
  });

  test('an EPUB', () {
    final epub = asciidoc.convertToBytes(
      '= Book\n:doctype: book\n\n== One\n\nText.\n',
      backend: Backend.epub3,
    );
    expect(latin1.decode(epub.sublist(0, 2)), 'PK');
    expect(latin1.decode(epub), contains('application/epub+zip'));
  });

  test('convertFile writes a PDF', () async {
    final input = File('${tmp.path}/doc.adoc')..writeAsStringSync(_source);
    await Asciidart(
      safe: SafeMode.unsafe,
      fonts: _vendoredFonts(),
    ).convertFile(input.path, backend: Backend.pdf);
    final pdf = File('${tmp.path}/doc.pdf').readAsBytesSync();
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
  });

  test('text and file formats each have their method', () {
    expect(
      () => asciidoc.convert(_source, backend: Backend.pdf),
      throwsArgumentError,
    );
    expect(
      () => asciidoc.convertToBytes(_source, backend: Backend.html5),
      throwsArgumentError,
    );
    expect(Backend.epub3.makesFile, isTrue);
    expect(Backend.docbook5.makesFile, isFalse);
  });
}
