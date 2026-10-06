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
}
