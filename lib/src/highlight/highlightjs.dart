/// highlight.js adapter: marks up source blocks for client-side highlighting.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter/highlightjs.rb`.
///
/// Full port: highlighting itself runs in the browser, so everything here is
/// pure string transformation (the `<pre>`/`<code>` hooks plus the head and
/// footer loader tags). No [SourceLexer] is involved.
library;

import 'package:asciidoctor/src/highlight/highlight.dart';

/// Syntax-highlighter adapter for highlight.js.
///
/// Highlighting is performed by the highlight.js script in the browser; this
/// adapter only emits the markup hooks ([format]) and the loader tags
/// ([docinfoHead], [docinfoFooter]).
class HighlightJsAdapter {
  /// Creates a highlight.js adapter.
  const new();

  /// Names this adapter registers for (`register_for 'highlightjs',
  /// `'highlight.js'`).
  static const List<String> registeredNames = ['highlightjs', 'highlight.js'];

  /// The adapter name.
  static const String name = 'highlightjs';

  /// The `<pre>` CSS class.
  static const String preClass = 'highlightjs';

  /// The pinned highlight.js version (`HIGHLIGHT_JS_VERSION`).
  static const String highlightJsVersion = '9.18.3';

  /// The default CDN base URL.
  ///
  /// Mirrors the converter expression
  /// `{asset-uri-scheme}://cdnjs.cloudflare.com/ajax/libs` with the default
  /// `asset-uri-scheme` of `https`.
  static const String defaultCdnBaseUrl =
      'https://cdnjs.cloudflare.com/ajax/libs';

  /// Formats converted [content] for client-side highlighting.
  ///
  /// The `<code>` tag carries `language-{language} hljs` (`language-none`
  /// when [language] is absent). When [nohighlight] is set (the
  /// `nohighlight` option on the block), the ` highlight` marker is removed
  /// from the `<pre>` class so the client skips the block. [nowrap] appends
  /// the `nowrap` class.
  String format({
    required String content,
    String? language,
    bool nowrap = false,
    bool nohighlight = false,
  }) => wrapSourceBlock(
    preClass: preClass,
    content: content,
    language: language,
    nowrap: nowrap,
    transform: (pre, code) {
      if (nohighlight) {
        pre['class'] = pre['class']!.replaceFirst(' highlight', '');
      }
      code['class'] = 'language-${language ?? 'none'} hljs';
    },
  );

  /// Whether this adapter injects markup at [location].
  ///
  /// Always true: highlight.js needs both the head stylesheet link and the
  /// footer scripts.
  bool hasDocinfo(DocinfoLocation location) => true;

  /// Returns the `<link>` tag for the highlight.js theme stylesheet.
  ///
  /// [highlightjsDir] mirrors the `highlightjsdir` document attribute
  /// (default: `{cdnBaseUrl}/highlight.js/{highlightJsVersion}`); [theme]
  /// mirrors `highlightjs-theme` (default: `github`). [selfClosingSlash]
  /// mirrors the converter's void-element slash (default `''` for HTML,
  /// `'/'` for XML).
  String docinfoHead({
    String? highlightjsDir,
    String theme = 'github',
    String cdnBaseUrl = defaultCdnBaseUrl,
    String selfClosingSlash = '',
  }) {
    final baseUrl =
        highlightjsDir ?? '$cdnBaseUrl/highlight.js/$highlightJsVersion';
    return '<link rel="stylesheet" href="$baseUrl/styles/$theme.min.css"'
        '$selfClosingSlash>';
  }

  /// Returns the footer `<script>` tags that load and bootstrap highlight.js.
  ///
  /// [languagesAttr] mirrors the raw `highlightjs-languages` document
  /// attribute (comma-separated); each entry is left-stripped and loaded from
  /// `{baseUrl}/languages/{lang}.min.js`. A missing or empty value loads no
  /// extra languages. Splitting mirrors Ruby's `String#split`, which drops
  /// trailing empty entries.
  String docinfoFooter({
    String? highlightjsDir,
    String? languagesAttr,
    String cdnBaseUrl = defaultCdnBaseUrl,
  }) {
    final baseUrl =
        highlightjsDir ?? '$cdnBaseUrl/highlight.js/$highlightJsVersion';
    final languageScripts = _splitLanguages(languagesAttr)
        .map(
          (lang) =>
              '<script src="$baseUrl/languages/$lang.min.js">'
              '</script>\n',
        )
        .join();
    return '<script src="$baseUrl/highlight.min.js"></script>\n'
        '$languageScripts<script>\n'
        'if (!hljs.initHighlighting.called) {\n'
        '  hljs.initHighlighting.called = true\n'
        "  ;[].slice.call(document.querySelectorAll('pre.highlight > "
        "code[data-lang]')).forEach(function (el) { hljs.highlightBlock(el) })\n"
        '}\n'
        '</script>';
  }

  /// Splits the raw `highlightjs-languages` attribute like Ruby's
  /// `String#split(',')` (trailing empty entries dropped) and left-strips
  /// each entry (Ruby `String#lstrip`).
  static List<String> _splitLanguages(String? value) {
    if (value == null || value.isEmpty) return const [];
    final parts = value.split(',');
    while (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    return [for (final part in parts) part.trimLeft()];
  }
}
