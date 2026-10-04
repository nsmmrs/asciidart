// Adjacent-string joins here are markup/paths, not prose; joined values
// are asserted byte-identical by tests.
// ignore_for_file: missing_whitespace_between_adjacent_strings
/// Shared types for the syntax-highlighter adapters.
///
/// Dart port of the adapter-facing surface of
/// `lib/asciidoctor/syntax_highlighter.rb` (the `Base#format` wrapper and the
/// option vocabulary) plus the [SourceLexer] seam behind which the
/// server-side lexing backends (Rouge, CodeRay, Pygments) hide.
///
/// The full `SyntaxHighlighter` framework (registry, factory, `Document`
/// integration) is deliberately *not* ported here: it needs `Document` and
/// arrives with the converter wave. The adapters in this directory are pure
/// string transformers; every value they need from a node or document arrives
/// as an explicit parameter.
///
/// ## The lexer seam
///
/// The server-side adapters (`CodeRayAdapter`, `PygmentsAdapter`,
/// `RougeAdapter`) accept an optional [SourceLexer]. Constructed without
/// one, they report `canHighlight == false` and throw [UnimplementedError]
/// from `highlight`. Stylesheet queries degrade exactly like the Ruby
/// adapters do when their library is unavailable (fallback comment /
/// default style). CodeRay ships a real backend (`CodeRaySourceLexer`,
/// wired as the factory default); rouge and pygments lexers are a later
/// wave, so those adapters stay seam-gated. Tests inject fakes (see
/// `dart/test/highlight/`).
library;

import 'package:asciidoctor/src/path_resolver.dart';

/// Selects whether highlighted HTML references stylesheet classes or carries
/// inline styles.
///
/// Mirrors the Ruby `:css_mode` option. The Ruby converter passes
/// `(doc_attrs["{name}-css"] || :class).to_sym`, so only `:class` selects
/// class mode; every other value behaves as inline (conventionally `:style`).
enum CssMode {
  /// Emit `class` attributes; highlighting requires the adapter stylesheet.
  ///
  /// Ruby `:class`.
  classes,

  /// Emit inline `style` attributes; no stylesheet is required.
  ///
  /// Ruby `:style` (or any other non-`:class` value).
  inline;

  /// Resolves the `{name}-css` document attribute value to a [CssMode].
  ///
  /// Mirrors the Ruby converter expression: a missing attribute behaves as
  /// `'class'`; only the exact value `'class'` selects [classes].
  static CssMode fromAttribute(String? value) =>
      (value ?? 'class') == 'class' ? CssMode.classes : CssMode.inline;
}

/// Selects how line numbers are rendered for a source block.
///
/// Mirrors the Ruby `:number_lines` option (`:table` / `:inline` / absent).
enum LineNumbersMode {
  /// Line numbers in a side-by-side table column.
  ///
  /// Ruby `:table`.
  table,

  /// Line numbers prepended to each line.
  ///
  /// Ruby `:inline`.
  inline;

  /// Resolves the `{name}-linenums-mode` document attribute value.
  ///
  /// Mirrors the Ruby converter expression: a missing attribute behaves as
  /// `'table'`; only the exact value `'table'` selects [table], any other
  /// present value selects [inline]. A `null` result means line numbering is
  /// disabled (the `linenums` option was not set).
  static LineNumbersMode? fromAttribute(String? value, {bool linenums = true}) {
    if (!linenums) return null;
    return (value ?? 'table') == 'table'
        ? LineNumbersMode.table
        : LineNumbersMode.inline;
  }
}

/// A slot in the output document where an adapter may inject markup.
///
/// Mirrors the Ruby `:head` / `:footer` location symbols.
enum DocinfoLocation {
  /// Markup injected into the document `<head>`.
  head,

  /// Markup injected at the end of the document `<body>`.
  footer,
}

/// Immutable description of one server-side highlight operation.
///
/// This is the request object passed to [SourceLexer.highlight]. Fields mirror
/// the Ruby `highlight` options hash (`:css_mode`, `:number_lines`,
/// `:start_line_number`, `:highlight_lines`, `:style`) plus the few
/// node-derived values lexing needs (`mixed`).
class HighlightRequest {
  /// Creates an immutable highlight request.
  const new({
    required this.source,
    this.language,
    this.cssMode = CssMode.classes,
    this.numberLines,
    this.startLineNumber = 1,
    this.highlightLines = const [],
    this.style,
    this.mixed = false,
  });

  /// The raw source text to highlight (callouts already extracted).
  final String source;

  /// The source language as written on the block, or `null` when absent.
  ///
  /// May carry cgi-style options (e.g., `ruby?foo=bar`); resolving those is
  /// the lexer's job (Ruby `Rouge::Lexer.find_fancy`). Implementations must
  /// fall back to plain text for unknown or absent languages, mirroring the
  /// Ruby adapters (`Rouge::Lexers::PlainText`, CodeRay `:text`,
  /// `text/plain`).
  final String? language;

  /// Whether to emit classes ([CssMode.classes]) or inline styles.
  final CssMode cssMode;

  /// How to number lines, or `null` to omit line numbers.
  final LineNumbersMode? numberLines;

  /// The 1-based number of the first line, or `null` for the backend default.
  ///
  /// The Pygments adapter passes this through untouched (a `null` value
  /// takes the non-table path, mirroring the Ruby condition chain); the
  /// Rouge and CodeRay adapters coerce `null` to `1`.
  final int? startLineNumber;

  /// The 1-based line numbers to emphasize. Empty means none.
  ///
  /// Ruby passes this array through to the backend (`highlight_lines` /
  /// `hl_lines`, space-joined for Pygments); the Rouge adapter additionally
  /// applies its own `<span class="hll">` wrapping.
  final List<int> highlightLines;

  /// The resolved style (theme) name, if the adapter resolves one.
  ///
  /// The Rouge and Pygments adapters resolve the requested style (falling
  /// back to their default) before lexing; CodeRay ignores styles.
  final String? style;

  /// Whether the block carries the `mixed` option (PHP start-inline hint).
  ///
  /// Ruby computes `start_inline` as `lexer.name == 'PHP' && !mixed`; the
  /// lexer owns the name half of that test, the adapter supplies this flag.
  final bool mixed;
}

/// The result of one server-side highlight operation.
///
/// Ruby returns either a bare string or a `[highlighted, offset]` tuple; this
/// class carries both shapes. [sourceOffset] is the index into [html] where
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

/// Lexing backend behind the server-side adapters.
///
/// Implementations wrap a real lexing library (Rouge, CodeRay, Pygments).
/// Each server-side adapter documents which members it uses:
///
/// * CodeRay uses only [highlight]; its stylesheet is a static asset, so the
///   style members are never called and may throw [UnimplementedError].
/// * Pygments uses every member. [highlight] must return the backend's raw
///   wrapper output (the `<div class="lineno">...` envelope), or `null` when
///   the backend fails; the adapter applies its post-processing regexes.
/// * Rouge uses every member. [highlight] must return the delegate-formatted
///   inner HTML with `\n` line separators and no line decorations; spans must
///   not cross line boundaries (upstream, `RougeExt` guarantees this via
///   `token_lines`). The adapter applies line highlighting and numbering.
///   A `null` response is a backend failure and surfaces as [StateError].
///
/// Returning `null` from [stylesheet] mirrors a backend CSS-generation
/// failure (Pygments reports `/* Failed to load Pygments CSS. */`); returning
/// `null` from [baseStyle] means the style contributes no `<pre>` inline
/// style (the adapter then emits no `style` attribute).
abstract interface class SourceLexer {
  /// The backend name (`rouge`, `coderay`, or `pygments`).
  String get name;

  /// Highlights `request.source` and returns the raw backend HTML.
  ///
  /// See the interface documentation for the per-adapter output contract.
  /// Returns `null` when the backend fails (handled per adapter).
  String? highlight(HighlightRequest request);

  /// Whether [style] names a theme the backend can render.
  bool styleAvailable(String style);

  /// The inline `<pre>` style for [style], or `null` when there is none.
  ///
  /// Rouge derives this from the theme foreground/background
  /// (e.g., `color: #f8f8f2;background-color: #49483e`); Pygments extracts the
  /// `pre.pygments { ... }` rule body (e.g., `background: #f8f8f8;`).
  String? baseStyle(String style);

  /// The full rendered stylesheet for [style], or `null` on failure.
  String? stylesheet(String style);
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
