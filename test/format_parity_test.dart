/// A book's features in every format (ADR-0012, doc/formats.md): each
/// test converts the same source with the backends that should agree.
@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/epub3/epub3.dart';
import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

import 'epub3_test.dart' show unzipText;

void main() {
  setUpAll(registerEpub3);
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
}
