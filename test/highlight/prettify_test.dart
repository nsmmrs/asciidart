/// Tests for the prettify adapter.
library;

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

void main() {
  const adapter = PrettifyAdapter();
  const content = "puts 'Hello, World!'\nputs 1 + 2";

  group('format', () {
    test('emits the plain prettyprint envelope', () {
      expect(
        adapter.format(content: content, language: 'ruby'),
        '<pre class="prettyprint highlight">'
        '<code data-lang="ruby">$content</code></pre>',
      );
    });

    test('linenums appends the linenums class', () {
      expect(
        adapter.format(content: 'puts 1', language: 'ruby', linenums: true),
        '<pre class="prettyprint highlight linenums">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('linenums with a start appends linenums:N', () {
      expect(
        adapter.format(
          content: 'puts 1',
          language: 'ruby',
          linenums: true,
          start: '7',
        ),
        '<pre class="prettyprint highlight linenums:7">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('a start without linenums is ignored', () {
      expect(
        adapter.format(content: 'puts 1', language: 'ruby', start: '7'),
        '<pre class="prettyprint highlight">'
        '<code data-lang="ruby">puts 1</code></pre>',
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
    const cdn = 'https://cdnjs.cloudflare.com/ajax/libs';

    test('links the default theme from the CDN', () {
      expect(
        adapter.docinfoHead(selfClosingSlash: '/'),
        '<link rel="stylesheet" href="$cdn/prettify/r298/prettify.min.css"/>',
      );
    });

    test('uses an absolute theme URL verbatim', () {
      expect(
        adapter.docinfoHead(
          theme: 'https://x.test/t.min.css',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" href="https://x.test/t.min.css"/>',
      );
    });

    test('honors a custom directory and theme', () {
      expect(
        adapter.docinfoHead(
          prettifyDir: 'https://x.test/pr',
          theme: 'doxy',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" href="https://x.test/pr/doxy.min.css"/>',
      );
    });
  });

  group('docinfoFooter', () {
    test('loads run_prettify.js from the CDN', () {
      expect(
        adapter.docinfoFooter(),
        '<script src="https://cdnjs.cloudflare.com/ajax/libs/prettify/r298/'
        'run_prettify.min.js"></script>',
      );
    });
  });
}
