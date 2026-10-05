/// The scenarios of `doc/api.md`, written only against the public
/// libraries: if one of these needs `package:asciidart/src/...`, the public
/// API has a gap. These run on the VM and on Node.js (the library has no
/// file system access); the file scenarios are in `files_test.dart`.
library;

import 'dart:async';

import 'package:asciidart/asciidart.dart';
import 'package:test/test.dart';

const card = '''
= Fix the parser
:status: doing
:priority: 2
:labels: parser, bug

The parser drops *bold* text.
''';

const guide = '''
= Guide

== Install

Run the installer.

[source,java]
----
class Main {}
----

== Use

[source,ruby]
----
puts 1
----

NOTE: Read the docs.

* one
* two
''';

void main() {
  group('1. render AsciiDoc to HTML', () {
    test('convert returns the body', () {
      expect(
        asciidoc.convert('Hello, *World*!'),
        '<div class="paragraph">\n'
        '<p>Hello, <strong>World</strong>!</p>\n'
        '</div>',
      );
    });

    test('standalone returns a page, with attributes applied', () {
      final page = asciidoc.convert(
        '= Title\n\nNOTE: x',
        standalone: true,
        attributes: {'icons': 'font'},
      );
      expect(page, startsWith('<!DOCTYPE html>'));
      expect(page, contains('<i class="fa icon-note"'));
      expect(page, contains('<meta name="generator" content="Asciidart '));
    });

    test('other backends', () {
      expect(
        asciidoc.convert('text', backend: Backend.docbook5),
        '<simpara>text</simpara>',
      );
    });
  });

  group('2. read metadata, then render', () {
    test('typed attributes and the title', () {
      final doc = asciidoc.parse(card);
      expect(doc.title, 'Fix the parser');
      expect(doc.attributes['status'], 'doing');
      expect(doc.attributes.intValue('priority'), 2);
      expect(doc.attributes.listValue('labels'), ['parser', 'bug']);
      expect(doc.attributes.listValue('missing'), isEmpty);
      expect(doc.toHtml(), contains('<strong>bold</strong>'));
    });

    test('the header as written', () {
      final doc = asciidoc.parseHeader(
        "= Don't -- (C) *stop*\n:status: doing\n:draft!:\n\nbody",
      );
      expect(doc.sourceTitle, "Don't -- (C) *stop*");
      expect(doc.title, contains('&#8217;'));
      expect(doc.headerAttributes, {'status': 'doing', 'draft': null});
    });

    test('parseHeader reads the header only', () {
      final doc = asciidoc.parseHeader(card);
      expect(doc.attributes['status'], 'doing');
      expect(doc.blocks, isEmpty);
    });

    test('authors', () {
      final doc = asciidoc.parse('= T\nAda Lovelace <ada@example.org>\n\nx');
      expect(doc.authors.single.name, 'Ada Lovelace');
      expect(doc.authors.single.email, 'ada@example.org');
    });
  });

  group('3. walk and query the tree', () {
    final doc = asciidoc.parse(guide);

    test('sections with their text', () {
      final sections = doc.descendants<Section>().toList();
      expect([for (final s in sections) s.title], ['Install', 'Use']);
      expect(sections.first.id, '_install');
      expect(sections.first.level, 1);
      expect(sections.first.plainText, startsWith('Run the installer.'));
    });

    test('typed queries', () {
      final java = doc.descendants<Listing>().where(
        (l) => l.language == 'java',
      );
      expect(java.single.source, 'class Main {}');
      expect(doc.descendants<Admonition>().single.kind, AdmonitionKind.note);
      expect(
        [for (final i in doc.descendants<ListItem>()) i.plainText],
        ['one', 'two'],
      );
    });

    test('parents, documents and locations', () {
      final listing = doc.descendants<Listing>().first;
      expect(listing.parent, isA<Section>());
      expect(listing.document, same(doc));
      expect(listing.location?.line, 8);
    });

    test('diagnostics with codes', () {
      final broken = asciidoc.parse('See <<nowhere>>.')..convert();
      expect(
        broken.diagnostics.map((d) => d.code),
        contains(DiagnosticCode.unknownReference),
      );
    });
  });

  group('4. your own renderer', () {
    String render(Block block) => switch (block) {
      final Section s => '# ${s.title}\n${s.blocks.map(render).join()}',
      final Paragraph p => '${p.plainText}\n',
      final Listing l => '```${l.language ?? ''}\n${l.source}\n```\n',
      final Admonition a => '> ${a.kind.name}: ${a.plainText}\n',
      final UnorderedList u => [
        for (final i in u.items) '- ${i.plainText}\n',
      ].join(),
      _ => '',
    };

    test('inline content as a tree', () {
      String md(InlineContent content) => switch (content) {
        InlineText(:final text) => text,
        Formatted(kind: FormattedKind.strong, :final children) =>
          '**${children.map(md).join()}**',
        Formatted(kind: FormattedKind.emphasis, :final children) =>
          '_${children.map(md).join()}_',
        Link(:final target, :final children) =>
          '[${children.map(md).join()}]($target)',
        final Inline other => other.plainText,
      };
      final doc = asciidoc.parse(
        '= The *Guide*\n\n'
        'Read *the https://example.org[_fine_ manual]* -- now.\n\n'
        '* an *item*',
      );
      final paragraph = doc.blocks.first as Paragraph;
      expect(
        paragraph.inlines.map(md).join(),
        'Read **the [_fine_ manual](https://example.org)**\u2009—\u2009now.',
      );
      final item = doc.descendants<ListItem>().single;
      expect(item.inlines.map(md).join(), 'an **item**');
      expect(doc.titleInlines.map(md).join(), 'The **Guide**');
      // The converted text is the same as before.
      expect(paragraph.content, contains('<strong>the <a href'));
    });

    test('an exhaustive switch over blocks', () {
      final doc = asciidoc.parse(guide);
      expect(doc.blocks.map(render).join(), '''
# Install
Run the installer.
```java
class Main {}
```
# Use
```ruby
puts 1
```
> note: Read the docs.
- one
- two
''');
    });
  });

  group('5. customize the HTML', () {
    test('override some nodes, keep the rest', () {
      final ad = Asciidart(
        html: (node, defaults) => switch (node) {
          final Admonition a =>
            '<aside class="${a.kind.name}">${defaults.content(a)}</aside>',
          final InlineImage i =>
            defaults.render(i).replaceFirst('<img', '<img loading="lazy"'),
          _ => defaults.render(node),
        },
      );
      final html = ad.convert('NOTE: *Hi*\n\nimage:a.png[] text');
      expect(html, contains('<aside class="note"><strong>Hi</strong></aside>'));
      expect(html, contains('<img loading="lazy" src="a.png"'));
    });

    test('the override sees the document', () {
      final ad = Asciidart(
        html: (node, defaults) =>
            node is Document ? 'DOC' : defaults.render(node),
      );
      expect(ad.convert('x'), 'DOC');
    });
  });

  group('6. extensions', () {
    test('every kind', () {
      final ad = Asciidart(
        extensions: [
          InlineMacro(
            'issue',
            (m) =>
                m.link('https://example.org/${m.target}', text: '#${m.target}'),
          ),
          BlockMacro('hello', (m) => m.html('<p>hello ${m.target}</p>')),
          CustomBlock(
            'shout',
            (b) => b.paragraph(b.source.toUpperCase()),
            on: {BlockKind.paragraph},
          ),
          IncludeResolver(
            (r) => r.target == 'db:intro' ? 'Included *text*.' : null,
          ),
          TreeProcessor((doc) {
            for (final image in doc.descendants<Image>()) {
              image.target = 'https://cdn.example.org/${image.target}';
            }
          }),
          Preprocessor(
            (lines, doc) => [
              for (final l in lines) l.replaceAll('TODO', 'done'),
            ],
          ),
          Postprocessor((output, doc) => '$output\n<!-- end -->'),
          const Docinfo(_meta),
        ],
      );
      final html = ad.convert('''
issue:7[]

hello::world[]

[shout]
quiet please

include::db:intro[]

image::a.png[]

TODO
''');
      expect(html, contains('<a href="https://example.org/7">#7</a>'));
      expect(html, contains('<p>hello world</p>'));
      expect(html, contains('QUIET PLEASE'));
      expect(html, contains('Included <strong>text</strong>.'));
      expect(html, contains('src="https://cdn.example.org/a.png"'));
      expect(html, contains('<p>done</p>'));
      expect(html, endsWith('<!-- end -->'));
      expect(
        ad.convert('x', standalone: true),
        contains('<meta name="x-test">'),
      );
    });

    test('an asynchronous include resolver', () async {
      final ad = Asciidart(
        extensions: [
          IncludeResolver((r) async {
            await Future<void>.delayed(Duration.zero);
            return r.target == 'remote' ? 'From *far*.' : null;
          }),
        ],
      );
      final doc = await ad.parseAsync('include::remote[]');
      expect(doc.toHtml(), contains('From <strong>far</strong>.'));
      expect(
        () => ad.parse('include::remote[]'),
        throwsA(isA<AsciidartException>()),
      );
    });
  });

  group('7. fail on warnings', () {
    test('diagnostics have severities and locations', () {
      final reported = <Diagnostic>[];
      final ad = Asciidart(onDiagnostic: reported.add);
      final doc = ad.parse('== A\n\n==== B\n', path: 'docs/index.adoc');
      final warnings = doc.diagnostics.where(
        (d) => d.severity >= Severity.warning,
      );
      expect(warnings.single.code, DiagnosticCode.sectionOutOfSequence);
      expect(warnings.single.location?.line, 3);
      // Below the server safe mode, relative to the document's directory.
      expect(warnings.single.location?.path, 'index.adoc');
      expect(reported, doc.diagnostics);
    });
  });

  group('also supported', () {
    test('a custom highlighter', () {
      final ad = Asciidart(
        highlighters: {'upper': _Upper()},
        attributes: {'source-highlighter': 'upper'},
      );
      final html = ad.convert(
        '[source,txt]\n----\nabc\n----',
        standalone: true,
      );
      expect(html, contains('ABC'));
      expect(html, contains('<style>.upper{}</style>'));
    });

    test('versions', () {
      expect(asciidoctorVersion, '2.1.0.alpha.0');
      expect(asciidartVersion, isNotEmpty);
    });
  });
}

String _meta(Document doc) => '<meta name="x-test">';

final class _Upper extends Highlighter {
  @override
  String highlight(SourceCode code) => code.source.toUpperCase();

  @override
  String? get head => '<style>.upper{}</style>';
}
