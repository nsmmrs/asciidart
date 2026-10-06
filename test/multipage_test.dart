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
    for (final file in dir.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.html'))
        file.path.substring(dir.path.length + 1): file.readAsStringSync(),
  };
}

/// The page of the site a link [href] on page [from] goes to, with its
/// fragment: the link resolved against the page's directory (a directory
/// is its `index.html`).
(String, String?) _resolve(String from, String href) {
  final hash = href.indexOf('#');
  final path = hash < 0 ? href : href.substring(0, hash);
  final fragment = hash < 0 ? null : href.substring(hash + 1);
  if (path.isEmpty) return (from, fragment);
  final segments = from.split('/')..removeLast();
  for (final segment in path.split('/')) {
    if (segment == '..') {
      segments.removeLast();
    } else if (segment.isNotEmpty && segment != '.') {
      segments.add(segment);
    }
  }
  final file = path.endsWith('/')
      ? [...segments, 'index.html'].join('/')
      : segments.join('/');
  return (file, fragment);
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

  group('page-path', () {
    final source = _book
        .replaceFirst(
          '== Chapter A',
          '[#_chapter_a,page-path=chapters/a/]\n== Chapter A',
        )
        .replaceFirst('= Part One', '[page-path=part/one.html]\n= Part One')
        .replaceFirst(
          'Text in A1.',
          'Text in A1.\n\nimage::pic.png[A picture]',
        );

    test('names the page and its directory', () {
      final site = _site(source);
      expect(
        site.keys,
        containsAll(['chapters/a/index.html', 'part/one.html']),
      );
      expect(site['book.html'], contains('<a href="chapters/a/">'));
      expect(site['book.html'], contains('<a href="part/one.html">'));
    });

    test('every link resolves from the page it is on', () {
      final site = _site(source);
      var links = 0;
      for (final MapEntry(key: file, value: html) in site.entries) {
        for (final m in RegExp('<a [^>]*?href="([^"]*)"').allMatches(html)) {
          final href = m[1]!;
          if (href.contains(':')) continue;
          final (target, id) = _resolve(file, href);
          links++;
          expect(site, contains(target), reason: '$file links to $href');
          if (id != null) {
            expect(
              site[target],
              contains('id="$id"'),
              reason: '$file links to $href',
            );
          }
        }
      }
      expect(links, greaterThan(10));
      // Resources too.
      expect(
        site['chapters/a/index.html'],
        contains('<img src="../../pic.png" alt="A picture">'),
      );
      expect(
        site['chapters/a/index.html'],
        contains('href="../../_chapter_b.html"'),
      );
    });

    test('stays in the site', () {
      final site = _site(
        _book.replaceFirst('== Chapter A', '[page-path=../a/]\n== Chapter A'),
      );
      expect(site.keys, contains('_chapter_a.html'));
    });
  });

  test('multipage-toclevels lists the sections of each page', () {
    final root = _site(
      _book,
      attributes: {'multipage-toclevels': '2'},
    )['book.html']!;
    expect(root, contains('<a href="_chapter_a.html#_section_a1">'));
    expect(_site(_book)['book.html'], isNot(contains('#_section_a1')));
  });

  test('docinfo is on every page', () {
    final dir = Directory.systemTemp.createTempSync('multipage_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/docinfo-footer.html')
        .writeAsStringSync('<script src="customizer.js"></script>\n');
    final input = File('${dir.path}/book.adoc')
      ..writeAsStringSync(
        _book.replaceFirst('== Chapter A', '[page-path=a/]\n== Chapter A'),
      );
    convertFile(
      input.path,
      const AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'multipage_html5',
        attributes: {'docinfo': 'shared-footer'},
      ),
    );
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.html') || file.path.contains('docinfo')) {
        continue;
      }
      final html = file.readAsStringSync();
      expect(
        html,
        contains(
          file.path.endsWith('a/index.html')
              ? '<script src="../customizer.js">'
              : '<script src="customizer.js">',
        ),
        reason: file.path,
      );
    }
  });

  test('a toc macro on a page of its own takes the list of pages', () {
    final site = _site(
      _book
          .replaceFirst(':toc:', ':toc: macro')
          .replaceFirst(
            '= Part One',
            '[#contents,page-path=contents/]\n== Contents\n\ntoc::[]\n\n= Part One',
          ),
    );
    // The home page: the header and preamble alone.
    expect(site['book.html'], isNot(contains('multipage-toc')));
    expect(
      site['contents/index.html'],
      contains('<nav class="multipage-toc">'),
    );
    expect(site['contents/index.html'], contains('href="../_chapter_a.html"'));
  });

  test('navigation labels from templates', () {
    final site = _site(
      _book,
      attributes: {
        'multipage-nav-previous-template': 'Previous: {{title}}',
        'multipage-nav-next-template': 'Next: {{title}}',
        'multipage-nav-up-template': 'Up: {{basic-title}}',
      },
    );
    expect(site['_chapter_b.html'], contains('>Up: Part One</a>'));
    expect(site['_chapter_b.html'], contains('>Previous: 1. Chapter A</a>'));
    expect(site['_chapter_a.html'], contains('>Next: 2. Chapter B</a>'));
  });

  test('navigation from a multipage_nav template', () {
    final dir = Directory.systemTemp.createTempSync('multipage_test.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final templates = Directory('${dir.path}/templates')..createSync();
    File('${templates.path}/multipage_nav.mustache').writeAsStringSync(
      '<footer>{{#next}}<a href="{{href}}">Next: {{title}}</a>{{/next}}'
      '</footer>',
    );
    final input = File('${dir.path}/book.adoc')..writeAsStringSync(_book);
    convertFile(
      input.path,
      AsciidoctorOptions(
        safe: SafeMode.safe,
        backend: 'multipage_html5',
        templateDirs: [templates.path],
        attributes: const {'reproducible': ''},
      ),
    );
    final page = File('${dir.path}/_chapter_a.html').readAsStringSync();
    expect(
      page,
      contains('<footer><a href="_chapter_b.html">Next: 2. Chapter B</a>'),
    );
  });
}
