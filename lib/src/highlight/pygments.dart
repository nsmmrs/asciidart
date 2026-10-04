/// Pygments adapter: server-side highlighting with generated stylesheets.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter/pygments.rb`.
///
/// The HTML format/wrap/docinfo logic and the backend-output post-processing
/// (wrapper stripping, lineno-span normalization, callout offsets) are fully
/// ported. Token lexing and stylesheet generation sit behind the
/// [SourceLexer] seam: the backend must return the raw Pygments wrapper
/// output (the `<div class="lineno">...` envelope), or `null` when it fails,
/// in which case the adapter falls back to escaped source.
library;

import 'dart:io';

import 'package:asciidoctor/src/highlight/highlight.dart';

/// Syntax-highlighter adapter for Pygments.
///
/// Server-side adapter: [highlight] resolves the style, delegates lexing to
/// the injected [SourceLexer], then strips and normalizes the backend's
/// wrapper output. [format] attaches the style's base rule to the `<pre>`
/// tag in inline-CSS mode.
class PygmentsAdapter {
  /// Creates a Pygments adapter, optionally with a [lexer] backend.
  new({this.lexer});

  /// Names this adapter registers for (`register_for 'pygments'`).
  static const List<String> registeredNames = ['pygments'];

  /// The adapter name.
  static const String name = 'pygments';

  /// The `<pre>` CSS class.
  static const String preClass = 'pygments';

  /// The default style name (`DEFAULT_STYLE`).
  static const String defaultStyle = 'default';

  /// Stylesheet comment used when no lexer backend is available.
  static const String unavailableStylesheet =
      '/* Pygments CSS disabled because Pygments is not available. */';

  /// Stylesheet comment used when the backend fails to generate CSS.
  static const String failedStylesheet = '/* Failed to load Pygments CSS. */';

  /// Class prefix applied to token spans (`classprefix` backend option).
  static const String tokenClassPrefix = 'tok-';

  /// The backend wrapper `<div>` class (`cssclass` backend option).
  ///
  /// The value never appears in final output; Pygments appends `table` to it
  /// for the nested table class.
  static const String wrapperClass = 'lineno';

  /// Matches the backend wrapper envelope (`WrapperTagRx`).
  ///
  /// NOTE `<pre>` carries a style attribute when `pygments-css=style`.
  /// NOTE `<div>` carries a trailing newline when
  /// `pygments-linenums-mode=table`.
  /// NOTE the initial `<span></span>` preserves leading blank lines.
  static final RegExp wrapperTagRx = RegExp(
    '<div class="$wrapperClass"><pre\\b[^>]*?>(.*)</pre></div>\\n*',
    dotAll: true,
  );

  /// Opening tag of the code cell in table-numbered output, anchoring the
  /// callout-restoration offset.
  static const String _codeCellStartTag = '<td class="code">';

  /// Legacy inline lineno span opener (emitted by older Pygments releases).
  static const String _legacyLinenoSpanStartTag = '<span class="lineno">';

  /// Matches a legacy inline lineno span (`LegacyLinenoSpanTagRx`).
  ///
  /// The opener carries no regex metacharacters, so it interpolates verbatim.
  static final RegExp _legacyLinenoSpanTagRx = RegExp(
    '$_legacyLinenoSpanStartTag( *\\d+) ?</span>',
  );

  /// Rewrites a legacy or styled inline lineno span match to the normalized
  /// `<span class="linenos">` form (`LinenoSpanTagCs`).
  static String _normalizeLinenoSpan(Match match) =>
      '<span class="linenos">${match[1]}</span>';

  /// Matches a styled inline lineno span (`StyledLinenoSpanTagRx`).
  static final RegExp _styledLinenoSpanTagRx = RegExp(
    r'(?<=^|<span></span>)<span style="[^"]+">( *\d+) ?</span>',
  );

  /// Matches the styled lineno column opener (`StyledLinenoColumnStartTagsRx`).
  static final RegExp _styledLinenoColumnStartTagsRx = RegExp(
    '<td><div class="linenodiv" style="[^"]+?"><pre style="[^"]+?">',
  );

  /// Replacement for the styled lineno column opener
  /// (`LinenoColumnStartTagsCs`).
  static const String _linenoColumnStartTags =
      '<td class="linenos"><div class="linenodiv"><pre>';

  /// The lexing backend, or `null` when no backend is available.
  ///
  /// The library counts as available exactly when a backend is present.
  final SourceLexer? lexer;

  bool _requiresStylesheet = false;
  String? _style;

  /// Whether server-side highlighting can run (`highlight?`).
  ///
  /// True exactly when a [lexer] backend was provided.
  bool get canHighlight => lexer != null;

  /// Whether any highlighted output so far requires the adapter stylesheet.
  ///
  /// Set by the first [highlight] call in [CssMode.classes] mode.
  bool get requiresStylesheet => _requiresStylesheet;

  /// The currently resolved style name, if [highlight] or [format] resolved
  /// one yet.
  String? get currentStyle => _style;

  /// Highlights [source] using the [lexer] backend plus post-processing.
  ///
  /// The style resolves from [style] (falling back to [defaultStyle] when
  /// absent or unknown) and sticks for later [docinfoHead] calls. [language]
  /// passes through to the backend untouched; alias resolution and the
  /// `text/plain` fallback are the backend's job, as are the `startinline`
  /// computation (fed by [mixed]) and the space-joined `hl_lines` rendering
  /// of [highlightLines].
  ///
  /// The backend's wrapper envelope is then stripped: table-numbered output
  /// keeps a bare `<pre>` envelope, all other output keeps only the wrapper
  /// contents. Inline line numbers are normalized to
  /// `<span class="linenos">`, and styled table columns are normalized to the
  /// class-based opener. When [numberLines] is [LineNumbersMode.table] and
  /// [hasCallouts] is set, the result carries the offset just past the code
  /// cell's opening tag (`null` when the tag is absent).
  ///
  /// A `null` [startLineNumber] takes the non-table path even when
  /// [numberLines] is [LineNumbersMode.table] (in practice the converter always
  /// supplies a start line when `linenums` is set). A `null` backend response
  /// falls back to escaped [source].
  ///
  /// Throws [UnimplementedError] when no [lexer] backend was provided.
  HighlightResult highlight({
    required String source,
    String? language,
    CssMode cssMode = CssMode.classes,
    LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    List<int> highlightLines = const [],
    bool hasCallouts = false,
    String? style,
    bool mixed = false,
  }) {
    final backend = lexer;
    if (backend == null) {
      throw UnimplementedError(
        'Pygments highlighting needs a SourceLexer backend; '
        'no Pygments lexer is built in.',
      );
    }
    final noclasses = cssMode != CssMode.classes;
    if (!noclasses) _requiresStylesheet = true;
    _style ??= resolveStyle(style);
    final raw = backend.highlight(
      HighlightRequest(
        source: source,
        language: language,
        cssMode: cssMode,
        numberLines: numberLines,
        startLineNumber: startLineNumber,
        highlightLines: highlightLines,
        style: _style,
        mixed: mixed,
      ),
    );
    if (numberLines == LineNumbersMode.table && startLineNumber != null) {
      if (raw == null) return HighlightResult(escapeSpecialChars(source));
      var html = raw;
      if (noclasses) {
        html = html.replaceFirst(
          _styledLinenoColumnStartTagsRx,
          _linenoColumnStartTags,
        );
      }
      html = html.replaceFirstMapped(
        wrapperTagRx,
        (match) => '<pre>${match[1]}</pre>',
      );
      if (hasCallouts) {
        final index = html.indexOf(_codeCellStartTag);
        return HighlightResult(
          html,
          index < 0 ? null : index + _codeCellStartTag.length,
        );
      }
      return HighlightResult(html);
    }
    if (raw == null) return HighlightResult(escapeSpecialChars(source));
    var html = raw;
    if (numberLines != null) {
      if (noclasses) {
        html = html.replaceAllMapped(
          _styledLinenoSpanTagRx,
          _normalizeLinenoSpan,
        );
      } else if (html.contains(_legacyLinenoSpanStartTag)) {
        html = html.replaceAllMapped(
          _legacyLinenoSpanTagRx,
          _normalizeLinenoSpan,
        );
      }
    }
    html = html.replaceFirstMapped(wrapperTagRx, (match) => match[1]!);
    return HighlightResult(html);
  }

  /// Wraps converted [content] in the `<pre>`/`<code>` envelope.
  ///
  /// In inline-CSS mode the style's base rule is resolved (which also records
  /// the style for later [docinfoHead] calls) and attached as the `<pre>`
  /// `style` attribute; without a backend, or when the style contributes no
  /// base rule, no `style` attribute is emitted.
  String format({
    required String content,
    String? language,
    bool nowrap = false,
    CssMode cssMode = CssMode.classes,
    String? style,
  }) {
    String? preStyle;
    if (cssMode != CssMode.classes) {
      _style = resolveStyle(style);
      preStyle = baseStyle(_style!);
    }
    return wrapSourceBlock(
      preClass: preClass,
      content: content,
      language: language,
      nowrap: nowrap,
      transform: preStyle == null
          ? null
          : (pre, _) {
              pre['style'] = preStyle!;
            },
    );
  }

  /// Whether this adapter injects markup at [location].
  ///
  /// True only for [DocinfoLocation.head] once [requiresStylesheet] is set.
  bool hasDocinfo(DocinfoLocation location) =>
      _requiresStylesheet && location == DocinfoLocation.head;

  /// Returns the head markup for the Pygments stylesheet.
  ///
  /// When [linkCss] is set, links `{stylesDir}/pygments-{style}.css`
  /// (mirroring `doc.normalize_web_path`); otherwise embeds the stylesheet in
  /// a `<style>` tag. [selfClosingSlash] mirrors the converter's
  /// void-element slash (default `''` for HTML, `'/'` for XML).
  String docinfoHead({
    required bool linkCss,
    String stylesDir = '',
    String selfClosingSlash = '',
  }) {
    if (linkCss) {
      return '<link rel="stylesheet" '
          'href="${stylesheetHref(stylesheetBasename(_style), stylesDir)}"'
          '$selfClosingSlash>';
    }
    return '<style>\n${readStylesheet(_style)}\n</style>';
  }

  /// Whether the adapter wants its stylesheet written to disk
  /// (`write_stylesheet?`).
  bool get wantsStylesheetFile => _requiresStylesheet;

  /// Writes the Pygments stylesheet for the resolved style to [toDir]
  /// (`write_stylesheet`).
  void writeStylesheet(String toDir) {
    File('$toDir/${stylesheetBasename(_style)}')
        .writeAsStringSync(readStylesheet(_style));
  }

  /// Resolves a requested style name to a usable one.
  ///
  /// Returns [style] when the backend offers it, else [defaultStyle].
  /// Without a backend every style is unknown, so this always returns
  /// [defaultStyle].
  String resolveStyle(String? style) =>
      style != null && styleAvailable(style) ? style : defaultStyle;

  /// Whether [style] names a style the backend offers (`style_available?`).
  ///
  /// Always false without a backend.
  bool styleAvailable(String style) => lexer?.styleAvailable(style) ?? false;

  /// The `pre.pygments { ... }` rule body for [style] (`base_style`), or
  /// `null` when the style contributes none or no backend is available.
  String? baseStyle(String style) => lexer?.baseStyle(style);

  /// The rendered stylesheet for [style] (`read_stylesheet`).
  ///
  /// Falls back to [failedStylesheet] when the backend fails to generate CSS
  /// and to [unavailableStylesheet] when no backend is available.
  String readStylesheet(String? style) {
    final backend = lexer;
    if (backend == null) return unavailableStylesheet;
    return backend.stylesheet(style ?? defaultStyle) ?? failedStylesheet;
  }

  /// The stylesheet file name for [style] (`stylesheet_basename`).
  String stylesheetBasename(String? style) =>
      'pygments-${style ?? defaultStyle}.css';
}
