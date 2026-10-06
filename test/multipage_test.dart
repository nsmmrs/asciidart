// The multipage_html5 backend: a book as linked pages.
@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/multipage.dart';
import 'package:test/test.dart';

const _book = '''
= The Book
Ada Lovelace
:doctype: book
:sectnums:
:toc:

Preamble text.footnote:[Root note.]

= Part One

Part intro.

== Chapter A

See <<_chapter_b>> and the ((term)) here.footnote:[First note.]

=== Section A1

Text in A1.

== Chapter B

Back to <<_section_a1>>.(((term)))footnote:[Second note.]

[index]
== Index
''';

/// [source] converted to pages in a new directory (with [attributes]):
/// the pages by file name.
Map<String, String> _site(
  String source, {
  Map<String, String> attributes = const {},
}) {
  final dir = Directory.systemTemp.createTempSync('multipage_test.');
  addTearDown(() => dir.deleteSync(recursive: true));
  final input = File('${dir.path}/book.adoc')..writeAsStringSync(source);
  convertFile(
    input.path,
    AsciidoctorOptions(
      safe: SafeMode.safe,
      backend: 'multipage_html5',
      attributes: {'reproducible': '', ...attributes},
    ),
  );
  return {
    for (final file in dir.listSync().whereType<File>())
      if (file.path.endsWith('.html'))
        file.uri.pathSegments.last: file.readAsStringSync(),
  };
}

void main() {
  setUpAll(MultipageHtml5Converter.register);

  test('a page per part and chapter, the root as the output file', () {
    expect(_site(_book).keys.toSet(), {
      'book.html',
      '_part_one.html',
      '_chapter_a.html',
      '_chapter_b.html',
      '_index.html',
    });
  });

  test('pages link to the previous, enclosing and next pages', () {
    final page = _site(_book)['_chapter_a.html']!;
    expect(
      page,
      contains(
        '<nav class="multipage-nav">\n'
        '<a class="prev" rel="prev" href="_part_one.html">&#8592; Part One</a>\n'
        '<a class="up" rel="up" href="_part_one.html">&#8593; Part One</a>\n'
        '<a class="next" rel="next" href="_chapter_b.html">'
        '2. Chapter B &#8594;</a>\n'
        '</nav>',
      ),
    );
    expect(page, contains('<title>1. Chapter A | The Book</title>'));
  });

  test('no link is broken', () {
    final site = _site(_book);
    final ids = {
      for (final MapEntry(key: file, value: html) in site.entries)
        file: {
          for (final m in RegExp(r'\sid="([^"]+)"').allMatches(html)) m[1]!,
        },
    };
    for (final MapEntry(key: file, value: html) in site.entries) {
      for (final m in RegExp(
        '<a [^>]*?href="([^"#:]*)(?:#([^"]*))?"',
      ).allMatches(html)) {
        final target = m[1]!.isEmpty ? file : m[1]!;
        if (!target.endsWith('.html')) continue;
        expect(site, contains(target), reason: '$file links to $target');
        if (m[2] case final id?) {
          expect(ids[target], contains(id), reason: '$file links to $id');
        }
      }
    }
    // A cross reference to another page names the page.
    expect(
      site['_chapter_b.html'],
      contains('<a href="_chapter_a.html#_section_a1">'),
    );
  });

  test("code that shows a link isn't rewritten", () {
    final site = _site(
      _book.replaceFirst(
        'Text in A1.',
        'Text in A1.\n\n----\n<a href="#_chapter_b">B</a>\n----',
      ),
    );
    expect(
      site['_chapter_a.html'],
      contains('&lt;a href="#_chapter_b"&gt;B&lt;/a&gt;'),
    );
  });

  test('the index links to every use, on its page', () {
    expect(
      _site(_book)['_index.html'],
      contains(
        '<span class="index-term">term</span>: '
        '<a href="_chapter_a.html#_indexterm_1">Chapter A</a>, '
        '<a href="_chapter_b.html#_indexterm_2">Chapter B</a>',
      ),
    );
  });

  test('footnotes are listed on the page they are on', () {
    final site = _site(_book);
    expect(site['_chapter_a.html'], contains('First note.'));
    expect(site['_chapter_a.html'], isNot(contains('Second note.')));
    expect(site['book.html'], contains('Root note.'));
  });

  test('multipage-level 2 gives sections pages of their own', () {
    final site = _site(_book, attributes: {'multipage-level': '2'});
    expect(site.keys, contains('_section_a1.html'));
    expect(
      site['_chapter_a.html'],
      contains('<nav class="multipage-children">'),
    );
    expect(site['_chapter_a.html'], isNot(contains('Text in A1.')));
  });
}
