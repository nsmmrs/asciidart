// The index in HTML: an `[index]` section lists the document's index terms,
// linked to their uses (Asciidoctor renders the section empty).

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

const _book = '''
= Book
:doctype: book

== Cats

The ((Tiger)) is big.(((Big cats, Lions)))
indexterm:[Sheep, see=Ewe]
indexterm:[Felines, see-also="Tiger"]

== Dogs

Wolves are ((wild)).(((Big cats, Tigers, Siberian)))
A ((Tiger)) again.(((Tiger)))

|===
a|In a cell: ((Ocelot)).
|===

[index]
== Index
''';

String _html(String source, {Map<String, String> attributes = const {}}) =>
    convert(
      source,
      AsciidoctorOptions(safe: SafeMode.safe, attributes: attributes),
    );

void main() {
  test('index-sort: code-point and index-category-headings!', () {
    const source =
        '= Book\n:doctype: book\n\n== One\n\n((htmx)) ((HTTP)) ((Alpine))\n\n'
        '[index]\n== Index\n';
    List<String> terms(String html) => [
      for (final m in RegExp(
        '<span class="index-term">([^<]*)</span>',
      ).allMatches(html))
        m[1]!,
    ];
    // The index's order: case-insensitive, by letter.
    final letter = _html(source);
    expect(terms(letter), ['Alpine', 'htmx', 'HTTP']);
    expect(letter, contains('<h3>A</h3>'));
    // Code point order, one list.
    final codePoint = _html(
      source,
      attributes: {'index-sort': 'code-point', 'index-category-headings!': ''},
    );
    expect(terms(codePoint), ['Alpine', 'HTTP', 'htmx']);
    expect(codePoint, isNot(contains('<h3>')));
  });

  test('a term indexed in a section title is in the index', () {
    final html = _html(
      '= Book\n:doctype: book\n\n== Chapter ((Gadget))\n\nText.\n\n'
      '[index]\n== Index\n',
    );
    final index = html.substring(html.indexOf('<div class="index">'));
    expect(index, contains('<span class="index-term">Gadget</span>'));
    expect(index, contains('href="#_indexterm_1"'));
    expect(html, contains('Chapter <a id="_indexterm_1"></a>Gadget'));
  });

  test('each use gets an anchor and the index links to it', () {
    final html = _html(_book);
    expect(html, contains('The <a id="_indexterm_1"></a>Tiger is big.'));
    final index = html.substring(html.indexOf('<div class="index">'));
    // Letters in order, terms under them.
    expect(RegExp('<h3>(.)</h3>').allMatches(index).map((m) => m[1]), [
      'B',
      'F',
      'O',
      'S',
      'T',
      'W',
    ]);
    // A use links to the anchor, labeled by its section (once per
    // section).
    expect(
      index,
      contains(
        '<span class="index-term">Tiger</span>: '
        '<a href="#_indexterm_1">Cats</a>, <a href="#_indexterm_7">Dogs</a>',
      ),
    );
    // Subterms nest.
    expect(
      index,
      contains(
        '<li id="_index_entry_3"><span class="index-term">Tigers</span>\n'
        '<ul class="index-terms">\n'
        '<li id="_index_entry_4"><span class="index-term">Siberian</span>: '
        '<a href="#_indexterm_6">Dogs</a></li>',
      ),
    );
    expect(index, contains('Sheep</span>, <em>see</em> Ewe</li>'));
    expect(
      index,
      matches(
        RegExp(
          'Felines</span>: <a href="#_indexterm_4">Cats</a>; '
          r'<em>see also</em> <a href="#_index_entry_\d+">Tiger</a>',
        ),
      ),
    );
    // A term in an AsciiDoc table cell.
    expect(index, contains('Ocelot</span>: <a href="#'));
    expect(
      RegExp(r'<a id="(_indexterm_\d+)"></a>Ocelot').hasMatch(html),
      isTrue,
    );
  });

  test('a term with markup cut open is listed as text', () {
    final html = _html(
      'Some text.(((pass:[<em>]Kept)))\n\n[index]\n== Index\n',
    );
    expect(html, contains('<span class="index-term">Kept</span>'));
  });

  test('emphasis around a term stays whole', () {
    final html = _html('_Some (((emph_ term))) text._\n\n[index]\n== Index\n');
    expect(html, contains('<span class="index-term">emph_ term</span>'));
    expect(html, contains('<em>Some <a id="_indexterm_1"></a> text.</em>'));
  });

  test('is unchanged from Asciidoctor without an index section', () {
    final source = _book.substring(0, _book.indexOf('[index]'));
    final html = _html(source);
    expect(html, isNot(contains('_indexterm')));
    expect(html, contains('The Tiger is big.'));
  });

  test('is left out with index-html unset', () {
    final html = _html(_book, attributes: {'index-html!': ''});
    expect(html, isNot(contains('_indexterm')));
    expect(html, isNot(contains('class="index"')));
    expect(
      html,
      contains(
        '<h2 id="_index">Index</h2>\n<div class="sectionbody">\n\n</div>',
      ),
    );
  });

  test('converting twice gives the same HTML', () {
    final document = load(
      _book,
      options: const AsciidoctorOptions(safe: SafeMode.safe),
    );
    expect(document.convert(), document.convert());
  });
}
