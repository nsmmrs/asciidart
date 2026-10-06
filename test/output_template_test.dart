import 'package:asciidart/asciidart.dart';
import 'package:asciidart/src/output_template.dart';
import 'package:test/test.dart';

void main() {
  test('optional parts and links around the number', () {
    expect(
      renderTemplate('{{#n}}{{n}}. {{/n}}{{t}}', {'n': '3', 't': 'Title'}),
      '3. Title',
    );
    expect(
      renderTemplate('{{#n}}{{n}}. {{/n}}{{t}}', {'n': '', 't': 'T'}),
      'T',
    );
    expect(
      renderNumbered('[{{number}}]', '2', (n) => '<a>$n</a>'),
      '[<a>2</a>]',
    );
  });

  group('footnote markers in HTML', () {
    const source = 'Text.footnote:[A note.]';

    test('are the default without templates', () {
      final html = asciidoc.convert(source);
      expect(html, contains('[<a id="_footnoteref_1" class="footnote"'));
      expect(html, contains('<a href="#_footnoteref_1">1</a>. A note.'));
    });

    test('come from the templates', () {
      final html = asciidoc.convert(
        ':footnote-reference-template: {{number}}\n'
        ':footnote-label-template: ({{number}}){sp}\n\n$source',
      );
      expect(html, contains('<sup class="footnote"><a id="_footnoteref_1"'));
      expect(html, contains('(<a href="#_footnoteref_1">1</a>) A note.'));
    });
  });

  group('caption numbers', () {
    test('come from <kind>-caption-template', () {
      final html = asciidoc.convert(
        ':listing-caption: Listing\n'
        ':listing-caption-template: pass:[{{caption}} {{number}}: ]\n'
        ':figure-caption-template: {{caption}} {{number}} —{sp}\n\n'
        '.A route\n----\ncode\n----\n\n.A picture\nimage::pic.png[]\n',
      );
      expect(html, contains('<div class="title">Listing 1: A route</div>'));
      expect(html, contains('<div class="title">Figure 1 — A picture</div>'));
    });

    test('leave cross references their word and number', () {
      final html = asciidoc.convert(
        ':xrefstyle: short\n'
        ':figure-caption-template: pass:[{{caption}} {{number}}: ]\n\n'
        'See <<pic>> and xref:pic[xrefstyle=full].\n\n'
        '[#pic]\n.A picture\nimage::pic.png[]\n',
      );
      expect(html, contains('<a href="#pic">Figure 1</a>'));
      expect(
        html,
        contains('<a href="#pic">Figure 1, &#8220;A picture&#8221;</a>'),
      );
    });

    test("are Asciidoctor's without a template", () {
      final html = asciidoc.convert(
        ':listing-caption: Listing\n\n.A route\n----\ncode\n----\n',
      );
      expect(html, contains('<div class="title">Listing 1. A route</div>'));
    });

    test('of appendices too', () {
      final html = asciidoc.convert(
        '= Book\n:doctype: book\n'
        ':appendix-caption-template: pass:[{{caption}} {{number}} — ]\n\n'
        '[appendix]\n== Extra\n\nText.\n',
      );
      expect(html, contains('Appendix A — Extra'));
    });
  });
}
