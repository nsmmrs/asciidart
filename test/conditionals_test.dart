// Single-source conditionals: each backend sets backend-<name> and
// basebackend-<name>, so print-only and web-only content needs no
// separate source.
@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/epub3/epub3.dart';
import 'package:asciidart/src/epub3/zip.dart';
import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/multipage.dart';
import 'package:asciidart/src/pdf/pdf.dart';
import 'package:test/test.dart';

import 'vendored_fonts.dart';

const _source = '''
= Cond
:doctype: book

== One

ifdef::backend-pdf[PDF-ONLY]
ifdef::backend-html5[HTML5-ONLY]
ifdef::backend-epub3[EPUB3-ONLY]
ifdef::backend-multipage_html5[MULTIPAGE-ONLY]
ifdef::backend-docbook5[DOCBOOK-ONLY]
ifdef::basebackend-html[BASE-HTML]
ifdef::basebackend-docbook[BASE-DOCBOOK]
ifndef::backend-pdf[NOT-PDF]
''';

final bool _pdftotext = Process.runSync('which', ['pdftotext']).exitCode == 0;

/// The markers [backend] keeps, from its output's text.
Set<String> _markers(String backend) {
  final dir = Directory.systemTemp.createTempSync('conditionals_test.');
  addTearDown(() => dir.deleteSync(recursive: true));
  final input = File('${dir.path}/c.adoc')..writeAsStringSync(_source);
  final suffix = switch (backend) {
    'pdf' => '.pdf',
    'epub3' => '.epub',
    'docbook5' => '.xml',
    _ => '.html',
  };
  final out = '${dir.path}/c$suffix';
  convertFile(
    input.path,
    AsciidoctorOptions(safe: SafeMode.unsafe, backend: backend, toFile: out),
  );
  final text = switch (backend) {
    'pdf' => Process.runSync('pdftotext', [out, '-']).stdout as String,
    'epub3' => [
      for (final entry in readZip(
        File(out).readAsBytesSync(),
        (bytes) => ZLibCodec(raw: true).decode(bytes),
      ))
        if (entry.name.endsWith('.xhtml')) String.fromCharCodes(entry.bytes),
    ].join(),
    'multipage_html5' => File('${dir.path}/_one.html').readAsStringSync(),
    _ => File(out).readAsStringSync(),
  };
  return {
    for (final m in RegExp(
      '[A-Z0-9]+-ONLY|BASE-[A-Z]+|NOT-PDF',
    ).allMatches(text))
      m[0]!,
  };
}

void main() {
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    registerEpub3();
    MultipageHtml5Converter.register();
  });

  test('html5', () {
    expect(_markers('html5'), {'HTML5-ONLY', 'BASE-HTML', 'NOT-PDF'});
  });

  test('multipage_html5', () {
    expect(_markers('multipage_html5'), {
      'MULTIPAGE-ONLY',
      'BASE-HTML',
      'NOT-PDF',
    });
  });

  test('epub3', () {
    expect(_markers('epub3'), {'EPUB3-ONLY', 'BASE-HTML', 'NOT-PDF'});
  });

  test('docbook5', () {
    expect(_markers('docbook5'), {'DOCBOOK-ONLY', 'BASE-DOCBOOK', 'NOT-PDF'});
  });

  // As asciidoctor-pdf sets it, the PDF's base backend is html.
  test('pdf', () {
    expect(_markers('pdf'), {'PDF-ONLY', 'BASE-HTML'});
  }, skip: _pdftotext ? false : 'needs pdftotext');
}
