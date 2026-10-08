/// highlight.js in ptome: highlighting at conversion with plain_highlighting
/// (the default), and the browser markup of Asciidoctor with
/// `highlightjs-mode=client`.
library;

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

String convertWith(
  String source, [
  Map<String, String?> attributes = const {},
]) => convert(
  source,
  AsciidoctorOptions(
    safe: SafeMode.safe,
    standalone: true,
    attributes: {'source-highlighter': 'highlight.js', ...attributes},
  ),
);

const ruby = '[source,ruby]\n----\nputs "hi" # greet\n----\n';

void main() {
  group('server-side (default)', () {
    test('highlights source blocks at conversion', () {
      final html = convertWith(ruby);
      expect(
        html,
        contains(
          '<pre class="highlightjs highlight">'
          '<code class="language-ruby hljs" data-lang="ruby">'
          'puts <span class="hljs-string">&quot;hi&quot;</span> '
          '<span class="hljs-comment"># greet</span></code></pre>',
        ),
      );
    });

    test("links only the theme stylesheet of plain_highlighting's version", () {
      final html = convertWith(ruby, {'highlightjs-theme': 'monokai'});
      expect(
        html,
        contains(
          '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/'
          'highlight.js/11.12.0/styles/monokai.min.css">',
        ),
      );
      expect(html, isNot(contains('<script')));
    });

    test('honors highlightjsdir', () {
      final html = convertWith(ruby, {'highlightjsdir': 'hl'});
      expect(
        html,
        contains('<link rel="stylesheet" href="hl/styles/github.min.css">'),
      );
    });

    test('leaves blocks without a language, or with an unknown one, alone', () {
      final html = convertWith(
        '[source]\n----\na < b\n----\n\n'
        '[source,nosuchlang]\n----\na < b\n----\n',
      );
      expect(
        html,
        contains('<code class="language-none hljs">a &lt; b</code>'),
      );
      expect(
        html,
        contains(
          '<code class="language-nosuchlang hljs" data-lang="nosuchlang">'
          'a &lt; b</code>',
        ),
      );
    });

    test('puts callouts at line ends, outside the spans', () {
      final html = convertWith(
        '[source,js]\n----\n/* a\nb */ x(); // <1>\ny(); // <2>\n----\n'
        '<1> one\n<2> two\n',
      );
      expect(
        html,
        contains(
          '<span class="hljs-comment">/* a</span>\n'
          '<span class="hljs-comment">b */</span> ',
        ),
      );
      expect(html, contains('<b class="conum">(1)</b>'));
      expect(html, contains('<b class="conum">(2)</b>'));
    });
  });

  group('client-side (highlightjs-mode=client)', () {
    test('marks up blocks for the browser and loads highlight.js', () {
      final html = convertWith(ruby, {'highlightjs-mode': 'client'});
      expect(
        html,
        contains(
          '<code class="language-ruby hljs" data-lang="ruby">'
          'puts "hi" # greet</code>',
        ),
      );
      expect(html, contains('highlight.js/9.18.3/styles/github.min.css'));
      expect(html, contains('highlight.js/9.18.3/highlight.min.js'));
    });
  });

  test('splitSpansAtLines closes and reopens spans around newlines', () {
    expect(
      splitSpansAtLines(
        '<span class="a">x\n<span class="b">y\nz</span></span>\nw',
      ),
      '<span class="a">x</span>\n'
      '<span class="a"><span class="b">y</span></span>\n'
      '<span class="a"><span class="b">z</span></span>\nw',
    );
  });
}
