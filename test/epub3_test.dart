/// The EPUB3 backend: the package (OPF, manifest properties, ids), the zip
/// layout, dates, and a conversion end to end. Byte-for-byte parity with
/// asciidoctor-epub3 is checked by `tool/epub_parity.dart` against the gem.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidart/src/epub3/assets.g.dart';
import 'package:asciidart/src/epub3/book.dart';
import 'package:asciidart/src/epub3/dates.dart';
import 'package:asciidart/src/epub3/epub3.dart';
import 'package:asciidart/src/epub3/zip.dart';
import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

Map<String, String> unzipText(List<int> epub) => {
  for (final entry in readZip(epub, (b) => ZLibCodec(raw: true).decode(b)))
    entry.name: utf8.decode(entry.bytes, allowMalformed: true),
};

void main() {
  setUpAll(registerEpub3);

  test('the embedded assets are the vendored files', () {
    for (final dir in ['styles', 'fonts', 'images']) {
      for (final file in Directory(
        'vendor/asciidoctor-epub3/$dir',
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path.substring('vendor/asciidoctor-epub3/'.length);
        expect(
          Epub3Assets.bytes(path),
          file.readAsBytesSync(),
          reason: '$path (run dart run tool/embed_epub3.dart)',
        );
      }
    }
  });

  test('the zip stores mimetype first and reads back', () {
    final book = EpubBook()
      ..language('en', id: 'pub-language')
      ..primaryIdentifier('x', 'pub-identifier', 'uuid')
      ..addTitle('T', id: 'pub-title')
      ..lastModified('1970-01-01T00:00:00Z');
    book.addItem('nav.xhtml', id: 'nav')
      ..addProperty('nav')
      ..setText('<html/>');
    final epub = book.zip(deflate: (b) => ZLibCodec(raw: true).encode(b));
    final entries = readZip(epub, (b) => ZLibCodec(raw: true).decode(b));
    expect(entries.first.name, 'mimetype');
    expect(entries.first.method, 0);
    expect(utf8.decode(entries.first.bytes), 'application/epub+zip');
    expect(
      [for (final e in entries) e.name],
      [
        'mimetype',
        'EPUB/nav.xhtml',
        'EPUB/package.opf',
        'META-INF/container.xml',
      ],
    );
    expect(crc32(utf8.encode('123456789')), 0xcbf43926);
  });

  test('item ids and properties follow gepub', () {
    final book = EpubBook();
    final a = book.addItem('styles/epub3.css');
    final b = book.addItem('other/epub3.css');
    final c = book.addOrderedItem('ch.xhtml')
      ..setText(
        '<?xml version="1.0"?>\n<!DOCTYPE html>\n<html><head>'
        '<script>x</script></head><body><img src="http://x/a.png"/>'
        '<mml:math/></body></html>',
      )
      ..addProperty('svg');
    expect(a.id, 'item_epub3');
    expect(b.id, 'item_epub31');
    expect(a.mediaType, 'text/css');
    expect(c.properties, ['remote-resources', 'mathml', 'scripted', 'svg']);
    expect(
      book.packageXml(),
      contains(
        'properties="remote-resources mathml '
        'scripted svg"',
      ),
    );
  });

  test('dates are read as Ruby reads them and written in UTC', () {
    expect(rubyTimeParseUtc('2026-01-31'), startsWith('2026-01-'));
    expect(
      rubyTimeParseUtc('2026-01-31 12:00:00 +0100'),
      '2026-01-31T11:00:00Z',
    );
    expect(rubyTimeParseUtc('2026-01-31T12:00:00Z'), '2026-01-31T12:00:00Z');
    expect(rubyTimeParseUtc('31 January 2026'), isNotNull);
    expect(rubyTimeParseUtc('January 31, 2026'), isNotNull);
    expect(rubyTimeParseUtc('v1.0'), isNull);
  });

  test('a book converts to chapters, navigation and a package', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync('''
= The Book: A Subtitle
Ada Lovelace
:doctype: book
:toc:
:uuid: 0000

[preface]
== Preface

Some *bold* text.footnote:[A note.]

== Chapter One

See <<_chapter_two>>.

== Chapter Two

NOTE: Watch out.
''');
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'reproducible': ''},
      ),
    );
    final files = unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    expect(files.keys.first, 'mimetype');
    expect(
      files.keys,
      containsAll(<String>[
        'EPUB/_preface.xhtml',
        'EPUB/_chapter_one.xhtml',
        'EPUB/_chapter_two.xhtml',
        'EPUB/nav.xhtml',
        'EPUB/toc.xhtml',
        'EPUB/toc.ncx',
        'EPUB/package.opf',
        'EPUB/styles/epub3.css',
        'EPUB/fonts/notoserif-regular-latin.ttf',
        'META-INF/container.xml',
      ]),
    );
    final opf = files['EPUB/package.opf']!;
    expect(
      opf,
      contains('<dc:identifier id="pub-identifier">0000</dc:identifier>'),
    );
    expect(
      opf,
      contains('<dc:creator id="creator1">Ada Lovelace</dc:creator>'),
    );
    expect(
      opf,
      contains('<meta property="dcterms:modified">1970-01-01T00:00:00Z</meta>'),
    );
    expect(
      files['EPUB/_chapter_one.xhtml'],
      contains(
        '<a id="xref--_chapter_two" href="_chapter_two.xhtml" class="xref">Chapter Two</a>',
      ),
    );
    expect(
      files['EPUB/_preface.xhtml'],
      contains('<aside id="note-1" epub:type="footnote">'),
    );
  });

  test('epub3 cannot write to standard output', () async {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/doc.adoc')..writeAsStringSync('= T\n\nx\n');
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCliCode(
      ['-b', 'epub3', '-o', '-', input.path],
      out: out,
      err: err,
    );
    expect(code, 1);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'the epub3 backend writes a file of its own and cannot write '
        'to standard output; give an output file (-o FILE)',
      ),
    );
  });
}
