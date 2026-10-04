/// Tests for the highlight.js adapter.
library;

import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:asciidoctor/src/highlight/highlightjs.dart';
import 'package:test/test.dart';

void main() {
  const adapter = HighlightJsAdapter();
  const content = "puts 'Hello, World!'\nputs 1 + 2";

  group('format', () {
    test('emits the language and hljs hooks', () {
      expect(
        adapter.format(content: content, language: 'ruby'),
        '<pre class="highlightjs highlight">'
        '<code class="language-ruby hljs" data-lang="ruby">'
        '$content</code></pre>',
      );
    });

    test('appends the nowrap class', () {
      expect(
        adapter.format(content: content, language: 'ruby', nowrap: true),
        '<pre class="highlightjs highlight nowrap">'
        '<code class="language-ruby hljs" data-lang="ruby">'
        '$content</code></pre>',
      );
    });

    test('missing language maps to language-none without data-lang', () {
      expect(
        adapter.format(content: content),
        '<pre class="highlightjs highlight">'
        '<code class="language-none hljs">$content</code></pre>',
      );
    });

    test('nohighlight strips the highlight marker from the pre class', () {
      expect(
        adapter.format(content: 'puts 1', language: 'ruby', nohighlight: true),
        '<pre class="highlightjs">'
        '<code class="language-ruby hljs" data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('nohighlight keeps the nowrap class', () {
      expect(
        adapter.format(
          content: 'puts 1',
          language: 'ruby',
          nowrap: true,
          nohighlight: true,
        ),
        '<pre class="highlightjs nowrap">'
        '<code class="language-ruby hljs" data-lang="ruby">puts 1</code></pre>',
      );
    });
  });

  group('hasDocinfo', () {
    test('is true for both locations', () {
      expect(adapter.hasDocinfo(DocinfoLocation.head), isTrue);
      expect(adapter.hasDocinfo(DocinfoLocation.footer), isTrue);
    });
  });

  group('docinfoHead', () {
    test('links the default theme from the CDN', () {
      expect(
        adapter.docinfoHead(
          cdnBaseUrl: 'https://cdnjs.cloudflare.com/ajax/libs',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/'
        'highlight.js/9.18.3/styles/github.min.css"/>',
      );
    });

    test('honors a custom directory and theme', () {
      expect(
        adapter.docinfoHead(
          highlightjsDir: 'https://x.test/hj',
          theme: 'monokai',
          cdnBaseUrl: 'https://cdnjs.cloudflare.com/ajax/libs',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" '
        'href="https://x.test/hj/styles/monokai.min.css"/>',
      );
    });

    test('omits the slash by default', () {
      expect(
        adapter.docinfoHead(
          cdnBaseUrl: 'https://cdnjs.cloudflare.com/ajax/libs',
        ),
        endsWith('.min.css">'),
      );
    });
  });

  group('docinfoFooter', () {
    const cdn = 'https://cdnjs.cloudflare.com/ajax/libs';
    const bootstrap =
        '<script>\n'
        'if (!hljs.initHighlighting.called) {\n'
        '  hljs.initHighlighting.called = true\n'
        "  ;[].slice.call(document.querySelectorAll('pre.highlight > "
        "code[data-lang]')).forEach(function (el) { hljs.highlightBlock(el) })\n"
        '}\n'
        '</script>';

    test('loads the bundle and bootstraps highlighting', () {
      expect(
        adapter.docinfoFooter(cdnBaseUrl: cdn),
        '<script src="$cdn/highlight.js/9.18.3/highlight.min.js"></script>\n'
        '$bootstrap',
      );
    });

    test('loads extra languages, left-stripping each entry', () {
      expect(
        adapter.docinfoFooter(cdnBaseUrl: cdn, languagesAttr: 'ruby, python'),
        '<script src="$cdn/highlight.js/9.18.3/highlight.min.js"></script>\n'
        '<script src="$cdn/highlight.js/9.18.3/languages/ruby.min.js">'
        '</script>\n'
        '<script src="$cdn/highlight.js/9.18.3/languages/python.min.js">'
        '</script>\n'
        '$bootstrap',
      );
    });

    test('empty languages attribute loads no extra languages', () {
      expect(
        adapter.docinfoFooter(cdnBaseUrl: cdn, languagesAttr: ''),
        '<script src="$cdn/highlight.js/9.18.3/highlight.min.js"></script>\n'
        '$bootstrap',
      );
    });

    test('trailing empty entries are dropped like Ruby split', () {
      expect(
        adapter.docinfoFooter(cdnBaseUrl: cdn, languagesAttr: 'ruby,'),
        contains('languages/ruby.min.js'),
      );
      expect(
        adapter.docinfoFooter(cdnBaseUrl: cdn, languagesAttr: 'ruby,'),
        isNot(contains('languages/.min.js')),
      );
    });
  });
}
