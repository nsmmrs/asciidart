/// html-pipeline adapter: marks up source blocks for later filtering.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter/html_pipeline.rb`.
///
/// Full port: the adapter emits `<pre lang="..."><code>` hooks for the
/// html-pipeline `SyntaxHighlightFilter` to highlight downstream. It carries
/// no options, no docinfo, and no [SourceLexer].
library;

import 'highlight.dart';

/// Syntax-highlighter adapter for html-pipeline.
///
/// Emits `<pre[ lang]>` hooks only; highlighting happens downstream in the
/// html-pipeline filter chain.
class HtmlPipelineAdapter {
  /// Creates an html-pipeline adapter.
  const HtmlPipelineAdapter();

  /// Names this adapter registers for (`register_for 'html-pipeline'`).
  static const List<String> registeredNames = ['html-pipeline'];

  /// The adapter name.
  static const String name = 'html-pipeline';

  /// Wraps converted [content] in `<pre lang>` / `<code>` hooks.
  ///
  /// Unlike the other adapters this bypasses [wrapSourceBlock] entirely: no
  /// `highlight` class, no `data-lang`, no `nowrap` handling.
  String format({required String content, String? language}) =>
      '<pre${language != null ? ' lang="$language"' : ''}>'
      '<code>$content</code></pre>';

  /// Whether this adapter injects markup at [location].
  ///
  /// Always false: the Ruby adapter defines no docinfo methods.
  bool hasDocinfo(DocinfoLocation location) => false;
}
