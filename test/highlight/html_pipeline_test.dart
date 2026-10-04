/// Tests for the html-pipeline adapter.
library;

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

void main() {
  const adapter = HtmlPipelineAdapter();
  const content = "puts 'Hello, World!'\nputs 1 + 2";

  group('format', () {
    test('emits the lang hook', () {
      expect(
        adapter.format(content: content, language: 'ruby'),
        '<pre lang="ruby"><code>$content</code></pre>',
      );
    });

    test('omits the lang attribute when the language is absent', () {
      expect(
        adapter.format(content: content),
        '<pre><code>$content</code></pre>',
      );
    });
  });

  group('hasDocinfo', () {
    test('is false for both locations', () {
      expect(adapter.hasDocinfo(DocinfoLocation.head), isFalse);
      expect(adapter.hasDocinfo(DocinfoLocation.footer), isFalse);
    });
  });
}
