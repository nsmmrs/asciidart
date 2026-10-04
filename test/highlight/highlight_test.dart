// Adjacent-string joins here are markup/paths, not prose; joined values
// are asserted byte-identical by tests.
// ignore_for_file: missing_whitespace_between_adjacent_strings
/// Tests for the shared syntax-highlighter foundation.
library;

import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:test/test.dart';

void main() {
  group('wrapSourceBlock', () {
    test('wraps content without a transform', () {
      expect(
        wrapSourceBlock(preClass: 'rouge', content: 'puts 1', language: 'ruby'),
        '<pre class="rouge highlight">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('omits data-lang when the language is absent', () {
      expect(
        wrapSourceBlock(preClass: 'rouge', content: 'x'),
        '<pre class="rouge highlight"><code>x</code></pre>',
      );
    });

    test('appends the nowrap class', () {
      expect(
        wrapSourceBlock(
          preClass: 'prettyprint',
          content: 'x',
          language: 'ruby',
          nowrap: true,
        ),
        '<pre class="prettyprint highlight nowrap">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('runs the transform and keeps data-lang last on the code tag', () {
      expect(
        wrapSourceBlock(
          preClass: 'highlightjs',
          content: 'x',
          language: 'ruby',
          transform: (pre, code) {
            code['class'] = 'language-ruby hljs';
          },
        ),
        '<pre class="highlightjs highlight">'
        '<code class="language-ruby hljs" data-lang="ruby">x</code></pre>',
      );
    });

    test('transform may add a pre style attribute', () {
      expect(
        wrapSourceBlock(
          preClass: 'rouge',
          content: 'x',
          language: 'ruby',
          transform: (pre, _) {
            pre['style'] = 'background-color: #f8f8f8';
          },
        ),
        '<pre class="rouge highlight" style="background-color: #f8f8f8">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });
  });

  group('CssMode.fromAttribute', () {
    test('missing attribute selects class mode', () {
      expect(CssMode.fromAttribute(null), CssMode.classes);
    });

    test('class selects class mode', () {
      expect(CssMode.fromAttribute('class'), CssMode.classes);
    });

    test('any other value selects inline mode', () {
      expect(CssMode.fromAttribute('style'), CssMode.inline);
      expect(CssMode.fromAttribute('bogus'), CssMode.inline);
    });
  });

  group('LineNumbersMode.fromAttribute', () {
    test('disabled linenums resolve to null', () {
      expect(LineNumbersMode.fromAttribute(null, linenums: false), isNull);
    });

    test('missing mode selects the table', () {
      expect(LineNumbersMode.fromAttribute(null), LineNumbersMode.table);
    });

    test('table selects the table', () {
      expect(LineNumbersMode.fromAttribute('table'), LineNumbersMode.table);
    });

    test('any other value selects inline numbering', () {
      expect(LineNumbersMode.fromAttribute('inline'), LineNumbersMode.inline);
    });
  });

  group('escapeSpecialChars', () {
    test('escapes ampersands, less-than, and greater-than', () {
      expect(
        escapeSpecialChars('x < 1 && y > 2'),
        'x &lt; 1 &amp;&amp; y &gt; 2',
      );
    });

    test('leaves quotes untouched', () {
      expect(escapeSpecialChars("it's \"quoted\""), "it's \"quoted\"");
    });
  });

  group('stylesheetHref', () {
    test('joins the styles directory and basename', () {
      expect(
        stylesheetHref('coderay-asciidoctor.css', 'css'),
        'css/coderay-asciidoctor.css',
      );
    });

    test('empty styles directory leaves the bare basename', () {
      expect(stylesheetHref('rouge-github.css', ''), 'rouge-github.css');
    });
  });
}
