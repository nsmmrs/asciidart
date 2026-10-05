/// highlight.js: the syntax highlighter of asciidart.
///
/// By default asciidart highlights source blocks itself, at conversion, with
/// hilite (highlight.js 11.12.0 in Dart): the output is what highlight.js
/// would produce in the browser, and the page only links the theme's
/// stylesheet. With the `highlightjs-mode` attribute set to `client`, it
/// behaves as Asciidoctor does instead: source blocks get the markup hooks
/// and the page loads highlight.js, which highlights them in the browser
/// (port of `lib/asciidoctor/syntax_highlighter/highlightjs.rb`).
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/highlight/highlight.dart';
import 'package:asciidart/src/highlight/syntax_highlighter.dart';
import 'package:hilite/hilite.dart' show hilite;

/// The highlight.js release whose themes match hilite's output (its CSS
/// classes): the version hilite ports.
const String hiliteHighlightJsVersion = '11.12.0';

/// highlight.js, highlighting at conversion (the default) or in the browser
/// (`highlightjs-mode=client`).
final class HighlightJsHighlighter extends SyntaxHighlighterBase {
  /// The highlighter for [document] (its `highlightjs-mode` decides).
  new({Document? document})
    : client = document?.attr('highlightjs-mode') == 'client';

  /// Whether highlighting runs in the browser.
  final bool client;

  final HighlightJsAdapter _adapter = const HighlightJsAdapter();

  @override
  String get name => HighlightJsAdapter.name;

  @override
  bool get canHighlight => !client;

  @override
  HighlightResult highlight(
    AbstractBlock node,
    String source,
    String? language, {
    Map<int, String>? callouts,
    CssMode cssMode = CssMode.classes,
    List<int> highlightLines = const <int>[],
    LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    String? style,
  }) {
    // As in the browser: a block without a language, or with one
    // highlight.js does not know, is not highlighted.
    if (language == null || !hilite.hasLanguage(language)) {
      return HighlightResult(escapeSpecialChars(source));
    }
    final html = hilite.highlight(source, language: language).html;
    // Callouts go at line ends: close the spans a line leaves open.
    return HighlightResult(
      callouts == null || callouts.isEmpty ? html : splitSpansAtLines(html),
    );
  }

  @override
  String format(AbstractBlock node, String? language, FormatOptions opts) =>
      _adapter.format(
        content: node.content() ?? '',
        language: language,
        nowrap: opts.nowrap,
      );

  @override
  bool hasDocinfo(String location) => client || location == 'head';

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) {
    final highlightjsDir = node.attr('highlightjsdir');
    final theme = node.attr('highlightjs-theme', 'github')!;
    if (!client) {
      final baseUrl =
          highlightjsDir ??
          '$cdnBaseUrl/highlight.js/$hiliteHighlightJsVersion';
      return '<link rel="stylesheet" href="$baseUrl/styles/$theme.min.css"'
          '$selfClosingTagSlash>';
    }
    if (location == 'head') {
      return _adapter.docinfoHead(
        highlightjsDir: highlightjsDir,
        theme: theme,
        cdnBaseUrl: cdnBaseUrl,
        selfClosingSlash: selfClosingTagSlash,
      );
    }
    return _adapter.docinfoFooter(
      highlightjsDir: highlightjsDir,
      languagesAttr: node.attr('highlightjs-languages'),
      cdnBaseUrl: cdnBaseUrl,
    );
  }
}

final RegExp _spanTag = RegExp(r'<span class="[^"]*">|</span>|\n');

/// [html] with every span that crosses a line closed at the line's end and
/// reopened on the next line, so each line stands alone (as Rouge's output
/// does), and markup appended to a line lands outside the spans.
String splitSpansAtLines(String html) {
  final out = StringBuffer();
  final open = <String>[];
  var last = 0;
  for (final m in _spanTag.allMatches(html)) {
    out.write(html.substring(last, m.start));
    last = m.end;
    final tag = m[0]!;
    if (tag == '\n') {
      out
        ..write('</span>' * open.length)
        ..write('\n')
        ..writeAll(open);
    } else if (tag == '</span>') {
      open.removeLast();
      out.write(tag);
    } else {
      open.add(tag);
      out.write(tag);
    }
  }
  out.write(html.substring(last));
  return out.toString();
}

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
  /// when [language] is absent). [nowrap] appends the `nowrap` class.
  String format({
    required String content,
    String? language,
    bool nowrap = false,
  }) => wrapSourceBlock(
    preClass: preClass,
    content: content,
    language: language,
    nowrap: nowrap,
    transform: (pre, code) {
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
  /// extra languages. Trailing empty entries are dropped.
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
        "code[data-lang]')).forEach(function (el) { "
        'hljs.highlightBlock(el) })\n'
        '}\n'
        '</script>';
  }

  /// Splits the raw `highlightjs-languages` attribute on commas (trailing
  /// empty entries dropped) and left-trims each entry.
  static List<String> _splitLanguages(String? value) {
    if (value == null || value.isEmpty) return const [];
    final parts = value.split(',');
    while (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    return [for (final part in parts) part.trimLeft()];
  }
}
