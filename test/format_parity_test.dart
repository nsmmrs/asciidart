/// A book's features in every format (ADR-0012, doc/formats.md): each
/// test converts the same source with the backends that should agree.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidart/src/epub3/epub3.dart';
import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/multipage.dart';
import 'package:asciidart/src/pdf/pdf.dart';
import 'package:test/test.dart';

import 'epub3_test.dart' show unzipText;

void main() {
  setUpAll(registerEpub3);
  setUpAll(MultipageHtml5Converter.register);
  setUpAll(registerPdf);
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('format_parity_test.');
    File('${dir.path}/art.txt').writeAsStringSync('+--+\n|<>|\n+--+\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String convertWith(String backend, String source) {
    final input = File('${dir.path}/doc.adoc')..writeAsStringSync(source);
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: backend,
        attributes: const {'reproducible': ''},
      ),
    );
    final extension = switch (backend) {
      'html5' => 'html',
      'docbook5' => 'xml',
      _ => 'epub',
    };
    return '${dir.path}/doc.$extension';
  }

  group('a text file shown as an image', () {
    const source = '= Doc\n\n.Art\nimage::art.txt[Art]\n';

    test('HTML: its text, preformatted, in the image block', () {
      final html = File(convertWith('html5', source)).readAsStringSync();
      expect(
        html,
        contains(
          '<div class="imageblock text">\n<div class="content">\n'
          '<pre>+--+\n|&lt;&gt;|\n+--+</pre>\n</div>',
        ),
      );
      expect(html, isNot(contains('src="art.txt"')));
    });

    test('EPUB: its text, preformatted, the file not packed', () {
      final files = unzipText(
        File(convertWith('epub3', source)).readAsBytesSync(),
      );
      final content = files.entries
          .where((e) => e.key.endsWith('.xhtml') && e.value.contains('Art'))
          .map((e) => e.value)
          .join();
      expect(content, contains('<pre>+--+\n|&lt;&gt;|\n+--+</pre>'));
      expect(files.keys.where((k) => k.endsWith('.txt')), isEmpty);
    });

    test('DocBook: its text in the media object', () {
      final xml = File(convertWith('docbook5', source)).readAsStringSync();
      expect(
        xml,
        contains(
          '<textobject><literallayout class="monospaced">+--+\n|&lt;&gt;|\n'
          '+--+</literallayout></textobject>',
        ),
      );
      expect(xml, isNot(contains('fileref="art.txt"')));
    });
  });

  test("DocBook: a chapter of a toc macro alone is the book's toc", () {
    final xml = File(
      convertWith(
        'docbook5',
        '= Book\n:doctype: book\n\n[#contents]\n== Contents\n\ntoc::[]\n\n'
            '== One\n\nText.\n',
      ),
    ).readAsStringSync();
    expect(
      xml,
      contains(
        '<toc xml:id="contents">\n<title>Contents</title>\n'
        '</toc>',
      ),
    );
  });

  test("DocBook: an image's placement as floatstyle", () {
    final xml = File(
      convertWith(
        'docbook5',
        '= Doc\n\n.Top\nimage::a.png[placement=top]\n\n'
            'image::b.png[placement=none]\n',
      ),
    ).readAsStringSync();
    expect(xml, contains('<figure floatstyle="before">'));
    expect(xml, contains('<informalfigure floatstyle="none">'));
  });

  group('%unbreakable', () {
    const source =
        '= Doc\n\n[%unbreakable]\n----\ncode\n----\n\n'
        '[%unbreakable]\n.Side\n****\nText.\n****\n';

    test('HTML: the class unbreakable', () {
      final html = File(convertWith('html5', source)).readAsStringSync();
      expect(html, contains('<div class="listingblock unbreakable">'));
      expect(html, contains('<div class="sidebarblock unbreakable">'));
    });

    test('EPUB: the class unbreakable', () {
      final files = unzipText(
        File(convertWith('epub3', source)).readAsBytesSync(),
      );
      expect(files.values.join(), contains('unbreakable'));
    });

    test('DocBook: the keep-together instruction', () {
      final xml = File(convertWith('docbook5', source)).readAsStringSync();
      expect(
        RegExp(r'<\?dbfo keep-together="always"\?>').allMatches(xml),
        hasLength(2),
      );
    });
  });

  test(':hyphens: hyphenates the text in HTML and EPUB', () {
    const source = '= Doc\n:hyphens:\n\nText.\n';
    expect(
      File(convertWith('html5', source)).readAsStringSync(),
      contains('hyphens:auto'),
    );
    final files = unzipText(
      File(convertWith('epub3', source)).readAsBytesSync(),
    );
    expect(
      files.entries
          .where((e) => e.key.endsWith('.xhtml') && e.value.contains('Text.'))
          .single
          .value,
      contains('hyphens: auto'),
    );
    // Without it, the stylesheets' own.
    expect(
      File(convertWith('html5', '= Doc\n\nText.\n')).readAsStringSync(),
      isNot(contains('hyphens:auto')),
    );
  });

  test('DocBook: the ISBN and editors in the info', () {
    final xml = File(
      convertWith(
        'docbook5',
        '= Book\nAnn Author\n:isbn: 978-0-00-000000-0\n'
            ':editor: Ed One; Ed Two\n\nText.\n',
      ),
    ).readAsStringSync();
    expect(
      xml,
      contains('<biblioid class="isbn">978-0-00-000000-0</biblioid>'),
    );
    expect(xml, contains('<editor><personname>Ed One</personname></editor>'));
    expect(xml, contains('<editor><personname>Ed Two</personname></editor>'));
  });

  test("the cover on the HTML page and the website's home page only", () {
    const source =
        '= Book\n:doctype: book\n'
        ':front-cover-image: image:cover.png[A cover]\n\n== One\n\nText.\n';
    final html = File(convertWith('html5', source)).readAsStringSync();
    expect(
      html,
      contains(
        '<div id="cover" class="imageblock cover">\n<div class="content">\n'
        '<img src="cover.png" alt="A cover">',
      ),
    );
    expect(html.indexOf('id="cover"'), lessThan(html.indexOf('id="header"')));
    final input = File('${dir.path}/site.adoc')..writeAsStringSync(source);
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'multipage_html5',
        attributes: {'reproducible': ''},
      ),
    );
    expect(
      File('${dir.path}/site.html').readAsStringSync(),
      contains('id="cover"'),
    );
    final pages = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.html') &&
              !f.path.endsWith('site.html') &&
              !f.path.endsWith('doc.html'),
        )
        .toList();
    expect(pages, isNotEmpty);
    for (final page in pages) {
      expect(page.readAsStringSync(), isNot(contains('id="cover"')));
    }
  });

  test("HTML: the house stylesheet by default, Asciidoctor's by name", () {
    const house = 'asciidart house style';
    expect(
      File(convertWith('html5', '= Doc\n\nText.\n')).readAsStringSync(),
      contains(house),
    );
    final classic = File(
      convertWith('html5', '= Doc\n:stylesheet: asciidoctor\n\nText.\n'),
    ).readAsStringSync();
    expect(classic, contains('Asciidoctor default stylesheet'));
    expect(classic, isNot(contains(house)));
  });

  test("EPUB: the house rules after asciidoctor-epub3's, or its alone", () {
    String css(String source) => unzipText(
      File(convertWith('epub3', source)).readAsBytesSync(),
    )['EPUB/styles/epub3.css']!;
    expect(css('= Doc\n\nText.\n'), contains('asciidart house style'));
    expect(
      css('= Doc\n:epub3-stylesheet: asciidoctor-epub3\n\nText.\n'),
      isNot(contains('asciidart house style')),
    );
  });

  test("EPUB: the print edition's pages from the PDF's page map", () {
    final source = StringBuffer('= Book\n:doctype: book\n\n== One\n\n');
    for (var i = 0; i < 40; i++) {
      source
        ..write('Paragraph $i, long enough to take a few lines. ' * 4)
        ..write('\n\n');
    }
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync(source.toString());
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'pdf',
        attributes: {'pdf-page-map': 'book.pages.json'},
      ),
    );
    final map = jsonDecode(
      File('${dir.path}/book.pages.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect((map['labels']! as List).length, greaterThan(2));
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'epub3',
        attributes: {'epub-page-map': 'book.pages.json', 'reproducible': ''},
      ),
    );
    final files = unzipText(File('${dir.path}/book.epub').readAsBytesSync());
    final chapter = files['EPUB/_one.xhtml']!;
    expect(
      chapter,
      contains('<span epub:type="pagebreak" role="doc-pagebreak" id="page-2"'),
    );
    expect(
      files['EPUB/nav.xhtml'],
      contains('<nav epub:type="page-list" id="page-list" hidden="hidden">'),
    );
    expect(files['EPUB/nav.xhtml'], contains('href="_one.xhtml#page-2">2</a>'));
  });
}
