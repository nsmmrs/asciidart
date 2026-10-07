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
import 'package:asciidart/src/font_index.dart';
import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

import 'vendored_fonts.dart';

Map<String, String> unzipText(List<int> epub) => {
  for (final entry in readZip(epub, (b) => ZLibCodec(raw: true).decode(b)))
    entry.name: utf8.decode(entry.bytes, allowMalformed: true),
};

void main() {
  setUpAll(registerEpub3);

  group('fonts', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('epub3_fonts.'));
    tearDown(() {
      FontIndex.installed = null;
      FontIndex.extraDirectories = const [];
      dir.deleteSync(recursive: true);
    });

    Map<String, String> epub({Map<String, String> attributes = const {}}) {
      final input = File('${dir.path}/book.adoc')
        ..writeAsStringSync(
          '= Book\n:doctype: book\n:icons: font\n\n== One\n\n'
          'NOTE: icon:heart[] and `code`.\n',
        );
      convertFile(
        input.path,
        AsciidoctorOptions(
          safe: SafeMode.safe,
          backend: 'epub3',
          attributes: {'reproducible': '', ...attributes},
        ),
      );
      return unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    }

    test("none embedded unless asked for: the reader's apply", () {
      useVendoredFonts();
      final files = epub();
      expect(files.keys.where((k) => k.contains('/fonts/')), isEmpty);
      expect(files['EPUB/styles/epub3-fonts.css'], isNot(contains('@font')));
      expect(
        files.keys,
        isNot(contains('META-INF/com.apple.ibooks.display-options.xml')),
      );
      // Icons in the text's font: no glyph that would show as a box.
      expect(
        files['EPUB/styles/epub3.css'],
        contains('aside.admonition::before,p.last::after{content:none}'),
      );
      expect(
        files['EPUB/_one.xhtml'],
        contains('.i-heart::before { content: "[heart]"; }'),
      );
    });

    test('with epub-embed-fonts, the installed fonts the stylesheet names', () {
      useVendoredFonts();
      final files = epub(attributes: {'epub-embed-fonts': ''});
      expect(
        files.keys,
        containsAll([
          'EPUB/fonts/notoserif-regular-latin.ttf',
          'EPUB/fonts/mplus1mn-regular-ascii-conums.ttf',
          'EPUB/fonts/awesome/fa-solid-900.ttf',
          'EPUB/fonts/assorted-icons.ttf',
          'META-INF/com.apple.ibooks.display-options.xml',
        ]),
      );
      expect(
        RegExp('@font-face').allMatches(files['EPUB/styles/epub3-fonts.css']!),
        hasLength(13),
      );
      expect(files['EPUB/_one.xhtml'], contains(r'content: "\f004"'));
    });

    test("a font asked for that isn't installed is left out, said once", () {
      FontIndex.installed = FontIndex([
        '${dir.path}/none',
      ], cacheFile: '${dir.path}/cache.tsv');
      final logger = MemoryLogger();
      final saved = LoggerManager.logger;
      LoggerManager.logger = logger;
      addTearDown(() => LoggerManager.logger = saved);
      final files = epub(attributes: {'epub-embed-fonts': ''});
      expect(files.keys.where((k) => k.contains('/fonts/')), isEmpty);
      expect(files['EPUB/styles/epub3-fonts.css'], isEmpty);
      final warnings = [for (final m in logger.messages) '${m.message}'];
      expect(
        warnings.where((m) => m.contains('font Noto Serif is not installed')),
        hasLength(1),
      );
    });
  });

  test('the embedded assets are the vendored files, but not the fonts', () {
    for (final dir in ['styles', 'fonts', 'images']) {
      for (final file in Directory(
        'vendor/asciidoctor-epub3/$dir',
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path
            .substring('vendor/asciidoctor-epub3/'.length)
            .replaceAll(r'\', '/');
        // The fonts aren't embedded (the installed ones are, when asked).
        if (RegExp(r'\.(ttf|otf)$|LICENSE').hasMatch(path)) {
          expect(Epub3Assets.bytes(path), isNull, reason: path);
          continue;
        }
        // A Windows checkout may give text files CRLF line endings.
        List<int> normalized(List<int>? bytes) => [
          for (final b in bytes ?? const <int>[])
            if (b != 0x0d || !RegExp(r'\.(css|tsv|svg)$').hasMatch(path)) b,
        ];
        expect(
          normalized(Epub3Assets.bytes(path)),
          normalized(file.readAsBytesSync()),
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

  test('a term indexed in a chapter title: indexed, its anchor in the '
      'heading only', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync('''
= The Book
:doctype: book
:uuid: 0000

== Chapter ((Gadget))

Text.

[index]
== Index
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
    final chapter = files['EPUB/_chapter_gadget.xhtml']!;
    expect(chapter, contains('<title>Chapter Gadget</title>'));
    expect(chapter, contains('title="Chapter Gadget"'));
    expect(RegExp('id="_indexterm_1"').allMatches(chapter), hasLength(1));
    expect(
      files['EPUB/_index.xhtml'],
      contains('_chapter_gadget.xhtml#_indexterm_1'),
    );
  });

  test('a toc macro lists the contents where it is', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync('''
= The Book
:doctype: book
:uuid: 0000

[#contents]
== Contents

toc::[]

== Cats

Text.
''');
    final logger = MemoryLogger();
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: const {'reproducible': ''},
        logger: logger,
      ),
    );
    expect(logger.messages, isEmpty);
    final files = unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    expect(
      files['EPUB/contents.xhtml'],
      contains(
        '<nav class="toc">\n<ol>\n<li><a href="contents.xhtml">'
        'Contents</a></li>\n<li><a href="_cats.xhtml">Cats</a></li>\n'
        '</ol>\n</nav>',
      ),
    );
  });

  test('an index section links to the chapters that use each term', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync('''
= The Book
:doctype: book
:uuid: 0000

== Cats

The ((Tiger)) is big.

== Dogs

A ((Tiger)) again.(((Wolves)))

[index]
== Index
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
    expect(
      files['EPUB/_cats.xhtml'],
      contains('<a id="_indexterm_1"></a>Tiger'),
    );
    final index = files['EPUB/_index.xhtml']!;
    // Marked up as an EPUB index, and a landmark.
    expect(index, contains('<div class="index" epub:type="index">'));
    expect(
      files['EPUB/nav.xhtml'],
      contains('<a epub:type="index" href="_index.xhtml">Index</a>'),
    );
    expect(
      index,
      contains(
        '<span class="index-term" epub:type="index-term">Tiger</span>: '
        '<a epub:type="index-locator" href="_cats.xhtml#_indexterm_1">Cats'
        '</a>, '
        '<a epub:type="index-locator" href="_dogs.xhtml#_indexterm_2">Dogs'
        '</a>',
      ),
    );
    expect(
      index,
      contains(
        'Wolves</span>: '
        '<a epub:type="index-locator" href="_dogs.xhtml#_indexterm_3">',
      ),
    );
  });

  test('callout-links links callouts and their items both ways', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/doc.adoc')
      ..writeAsStringSync('= Doc\n\n----\na <1>\n----\n<1> One.\n');
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'reproducible': '', 'callout-links': ''},
      ),
    );
    final chapter = unzipText(
      File('${dir.path}/doc.epub').readAsBytesSync(),
    )['EPUB/_doc.xhtml']!;
    expect(
      chapter,
      contains(
        '<a id="CO1-1" class="conum-link" href="#CO1-1-item" '
        'style="user-select:none"><i class="conum" data-value="1">',
      ),
    );
    expect(
      chapter,
      contains(
        '<li><a href="#CO1-1"><i class="conum" data-value="1">\u2460</i></a> '
        '<a id="CO1-1-item"></a>One.',
      ),
    );
  });

  group("valid where the gem's EPUB is not", () {
    /// The chapter of a one-chapter book of [body] (with [attributes]).
    String chapter(String body, {Map<String, String> attributes = const {}}) {
      final dir = Directory.systemTemp.createTempSync('epub3_test.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final input = File('${dir.path}/doc.adoc')
        ..writeAsStringSync('= Doc\n:toc-title:\n\n$body\n');
      convertFile(
        input.path,
        AsciidoctorOptions(
          safe: SafeMode.safe,
          backend: 'epub3',
          attributes: {'reproducible': '', ...attributes},
        ),
      );
      final files = unzipText(File('${dir.path}/doc.epub').readAsBytesSync());
      return '${files['EPUB/_doc.xhtml']}\n${files['EPUB/nav.xhtml']}';
    }

    test('an image width is a number of pixels or a style', () {
      final xhtml = chapter(
        'image::a.png[A, server responds]\n\nimage::b.png[B, 40%]\n\n'
        'image::c.png[C, 120]',
      );
      expect(xhtml, isNot(contains('width="server responds"')));
      expect(xhtml, contains('style="width: 40%"'));
      expect(xhtml, contains('width="120"'));
    });

    test('an empty toc-title gives the navigation a title', () {
      expect(
        chapter('Text.'),
        contains('<small class="subtitle">Table of Contents</small>'),
      );
    });

    test('a path from a website root goes to its id, or is text', () {
      final xhtml = chapter(
        '[[here]]\nTarget.\n\n'
        'See link:/a/#here[the target] and link:/b/#gone[elsewhere].',
      );
      expect(xhtml, contains('<a href="_doc.xhtml#here" class="link">'));
      expect(xhtml, contains(' and elsewhere.'));
    });

    test('emphasis around an index term stays whole', () {
      final xhtml = chapter(
        '((("_hyperscript", "event filter")))\n'
        'We can use an _event filter_ syntax in +_hyperscript+ here.',
      );
      expect(xhtml, contains('We can use an <em>event filter</em> syntax'));
    });

    test('code may scroll instead of wrapping', () {
      expect(
        chapter(
          '----\ncode\n----',
          attributes: {'ebook-code-overflow': 'scroll'},
        ),
        contains('pre { white-space: pre;'),
      );
    });
  });

  test('the ISBN as the unique identifier', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync(
        '= Book\n:uuid: 0000\n:isbn: 979-8-9909918-0-4\n'
        ':epub-unique-identifier: isbn\n\n== One\n\nText.\n',
      );
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'reproducible': ''},
      ),
    );
    final files = unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    final opf = files['EPUB/package.opf']!;
    expect(opf, contains('unique-identifier="pub-identifier"'));
    expect(
      opf,
      contains(
        '<dc:identifier id="pub-identifier">urn:isbn:9798990991804</dc:identifier>',
      ),
    );
    expect(opf, contains('<dc:identifier id="pub-uuid">0000</dc:identifier>'));
    expect(
      files['EPUB/toc.ncx'],
      contains('<meta name="dtb:uid" content="urn:isbn:9798990991804"/>'),
    );
  });

  test('a section with notoc is left out of the navigation', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync(
        '= Book\n:doctype: book\n\n[colophon%notoc]\n== Copyright\n\nText.\n\n'
        '== Chapter\n\nText.\n',
      );
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'reproducible': ''},
      ),
    );
    final files = unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    expect(files['EPUB/nav.xhtml'], contains('Chapter'));
    expect(files['EPUB/nav.xhtml'], isNot(contains('Copyright')));
    expect(files.keys, contains('EPUB/_copyright.xhtml'));
  });

  test('an ISBN and editors in the metadata', () {
    final dir = Directory.systemTemp.createTempSync('epub3_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync(
        '= Book\nAda Lovelace\n:uuid: 0000\n:isbn: 979-8-9909918-0-4\n'
        ':editor: William Talcott; Jane Doe\n\n== One\n\nText.\n',
      );
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'reproducible': ''},
      ),
    );
    final opf = unzipText(
      File('${dir.path}/book.epub').readAsBytesSync(),
    )['EPUB/package.opf']!;
    expect(
      opf,
      contains(
        '<dc:identifier id="pub-isbn">urn:isbn:9798990991804</dc:identifier>\n'
        '    <meta property="identifier-type" refines="#pub-isbn">isbn</meta>',
      ),
    );
    // The uuid stays the unique identifier.
    expect(opf, contains('unique-identifier="pub-identifier"'));
    expect(
      opf,
      contains(
        '<dc:contributor id="contributor1">William Talcott</dc:contributor>',
      ),
    );
    expect(
      opf,
      contains('<meta property="role" refines="#contributor1">edt</meta>'),
    );
    expect(opf, contains('Jane Doe</dc:contributor>'));
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
