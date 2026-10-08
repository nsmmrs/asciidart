/// Shared types for the syntax highlighters: the option vocabulary, the
/// result of highlighting, and the `Base#format` wrapper of
/// `lib/asciidoctor/syntax_highlighter.rb`.
///
/// The framework (registry, factory, `Document` integration) lives in
/// `syntax_highlighter.dart`.
library;

import 'package:ptome/src/path_resolver.dart';

/// Selects whether highlighted HTML references stylesheet classes or carries
/// inline styles.
///
/// Selected by the `{name}-css` document attribute: only `class` (the
/// default) selects class mode; every other value behaves as inline
/// (conventionally `style`).
enum CssMode {
  /// Emit `class` attributes; highlighting requires the adapter stylesheet.
  classes,

  /// Emit inline `style` attributes; no stylesheet is required.
  inline;

  /// Resolves the `{name}-css` document attribute value to a [CssMode].
  ///
  /// A missing attribute behaves as `'class'`; only the exact value
  /// `'class'` selects [classes].
  static CssMode fromAttribute(String? value) =>
      (value ?? 'class') == 'class' ? CssMode.classes : CssMode.inline;
}

/// Selects how line numbers are rendered for a source block.
///
/// Selected by the `{name}-linenums-mode` document attribute when the block
/// has line numbers.
enum LineNumbersMode {
  /// Line numbers in a side-by-side table column.
  table,

  /// Line numbers prepended to each line.
  inline;

  /// Resolves the `{name}-linenums-mode` document attribute value.
  ///
  /// A missing attribute behaves as `'table'`; only the exact value `'table'`
  /// selects [table], any other present value selects [inline]. A `null` result
  /// means line numbering is disabled (the `linenums` option was not set).
  static LineNumbersMode? fromAttribute(String? value, {bool linenums = true}) {
    if (!linenums) return null;
    return (value ?? 'table') == 'table'
        ? LineNumbersMode.table
        : LineNumbersMode.inline;
  }
}

/// A slot in the output document where an adapter may inject markup.
///
/// The `head` and `footer` docinfo locations.
enum DocinfoLocation {
  /// Markup injected into the document `<head>`.
  head,

  /// Markup injected at the end of the document `<body>`.
  footer,
}

/// The result of one server-side highlight operation.
///
/// [sourceOffset] is the index into [html] where
/// extracted callout marks must be restored, or `null` when callout
/// restoration needs no offset (no callouts, or the backend emitted no code
/// cell to anchor to).
class HighlightResult {
  /// Creates a highlight result.
  const new(this.html, [this.sourceOffset]);

  /// The highlighted HTML fragment.
  final String html;

  /// The callout-restoration offset, or `null` when not applicable.
  final int? sourceOffset;
}

/// Wraps converted source in `<pre>` / `<code>` tags.
///
/// Direct port of `SyntaxHighlighter::Base#format`:
/// `<pre class="{preClass} highlight[ nowrap]">` plus an optional `transform`
/// that mutates the `pre` and `code` attribute maps before emission. When a
/// transform runs, `data-lang` is re-inserted last on the `<code>` tag to stay
/// consistent with Asciidoctor 1.5.x attribute order.
String wrapSourceBlock({
  required String preClass,
  required String content,
  String? language,
  bool nowrap = false,
  void Function(Map<String, String> pre, Map<String, String> code)? transform,
}) {
  String renderAttrs(Map<String, String> attrs) =>
      attrs.entries.map((entry) => ' ${entry.key}="${entry.value}"').join();
  final classAttrVal = nowrap
      ? '$preClass highlight nowrap'
      : '$preClass highlight';
  if (transform != null) {
    final pre = <String, String>{'class': classAttrVal};
    final code = <String, String>{'data-lang': ?language};
    transform(pre, code);
    // NOTE make sure data-lang is the last attribute on the code tag to
    // remain consistent with 1.5.x
    final dataLang = code.remove('data-lang');
    if (dataLang != null) code['data-lang'] = dataLang;
    return '<pre${renderAttrs(pre)}><code${renderAttrs(code)}>$content</code></pre>';
  }
  return '<pre class="$classAttrVal">'
      '<code${language != null ? ' data-lang="$language"' : ''}>'
      '$content</code></pre>';
}

/// Joins a stylesheet [basename] onto [stylesDir] for `linkcss` docinfo.
///
/// Mirrors `doc.normalize_web_path basename, stylesdir, false`, which
/// delegates to `PathResolver.webPath` (the target is a plain file name, so
/// the URI-target branch never applies).
String stylesheetHref(String basename, String stylesDir) =>
    _pathResolver.webPath(basename, stylesDir);

final PathResolver _pathResolver = PathResolver();

/// Escapes `&`, `<`, and `>` for verbatim HTML inclusion.
///
/// Mirrors `Substitutors#sub_specialchars` (and thus `sub_source source,
/// false`, the fallback the Pygments adapter uses when its backend returns
/// no output).
String escapeSpecialChars(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
