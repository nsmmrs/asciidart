/// Rouge adapter: server-side highlighting with theme stylesheets.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter/rouge.rb` (including the
/// `RougeExt::Formatters` line decorators from `lib/asciidoctor/rouge_ext.rb`).
///
/// The HTML format/wrap/docinfo logic and the line-decoration pipeline
/// (line emphasis, inline/table line numbers, callout offsets) are fully
/// ported. Token lexing and theme stylesheets sit behind the [SourceLexer]
/// seam: the backend must return delegate-formatted inner HTML with `\n`
/// line separators and no line decorations, with spans never crossing line
/// boundaries (upstream, `RougeExt` guarantees this via `token_lines`).
library;

import 'dart:io';

import 'highlight.dart';

/// Syntax-highlighter adapter for Rouge.
///
/// Server-side adapter: [highlight] resolves the style, delegates token
/// formatting to the injected [SourceLexer], then applies the line
/// decorations itself. [format] additionally strips cgi-style language
/// options and, in inline-CSS mode, attaches the theme's base style to the
/// `<pre>` tag.
class RougeAdapter {
  /// Creates a Rouge adapter, optionally with a [lexer] backend.
  RougeAdapter({this.lexer});

  /// Names this adapter registers for (`register_for 'rouge'`).
  static const List<String> registeredNames = ['rouge'];

  /// The adapter name.
  static const String name = 'rouge';

  /// The `<pre>` CSS class.
  static const String preClass = 'rouge';

  /// The default style (theme) name (`DEFAULT_STYLE`).
  static const String defaultStyle = 'github';

  /// Stylesheet comment used when no lexer backend is available.
  static const String unavailableStylesheet =
      '/* Rouge CSS disabled because Rouge is not available. */';

  /// Opening tag of the code cell in table-numbered output, anchoring the
  /// callout-restoration offset.
  ///
  /// NOTE: unlike CodeRay's anchor this excludes the `<pre>` tag.
  static const String _codeCellStartTag = '<td class="code">';

  /// The lexing backend, or `null` when no backend is available.
  ///
  /// Mirrors the Ruby loader: the library counts as available exactly when a
  /// backend is present.
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

  /// Highlights [source] using the [lexer] backend plus line decorations.
  ///
  /// The style resolves from [style] (falling back to [defaultStyle] when
  /// absent or unknown) and sticks for later [docinfoHead] calls. [language]
  /// passes through to the backend untouched, including any cgi-style
  /// options (Ruby `Lexer.find_fancy`); [mixed] feeds the PHP `start_inline`
  /// computation, which is otherwise the backend's job.
  ///
  /// Line emphasis and numbering mirror `create_formatter`:
  /// [highlightLines] wraps lines in `<span class="hll">`, [numberLines]
  /// selects the inline or table numberer, and [startLineNumber] offsets the
  /// numbering. When line numbers and [hasCallouts] are both set, the result
  /// carries the offset just past the first code cell's opening tag (`null`
  /// when the output has no such tag, e.g., inline numbering).
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
        'Rouge highlighting needs a SourceLexer backend; '
        'real lexers are a later wave.',
      );
    }
    _style ??= resolveStyle(style);
    if (cssMode == CssMode.classes) _requiresStylesheet = true;
    final startLine = startLineNumber ?? 1;
    final inner = backend.highlight(
      HighlightRequest(
        source: source,
        language: language,
        cssMode: cssMode,
        numberLines: numberLines,
        startLineNumber: startLine,
        highlightLines: highlightLines,
        style: _style,
        mixed: mixed,
      ),
    );
    if (inner == null) {
      throw StateError('Rouge backend returned no output.');
    }
    final String html;
    if (numberLines != null) {
      final decorated = highlightHtmlLines(
        splitHtmlLines(inner),
        highlightLines,
      );
      html = numberLines == LineNumbersMode.table
          ? numberHtmlLinesAsTable(decorated, startLine: startLine)
          : numberHtmlLinesInline(decorated, startLine: startLine);
      if (hasCallouts) {
        final index = html.indexOf(_codeCellStartTag);
        return HighlightResult(
          html,
          index < 0 ? null : index + _codeCellStartTag.length,
        );
      }
      return HighlightResult(html);
    }
    if (highlightLines.isNotEmpty) {
      html = highlightHtmlLines(splitHtmlLines(inner), highlightLines).join();
    } else {
      html = inner;
    }
    return HighlightResult(html);
  }

  /// Wraps converted [content] in the `<pre>`/`<code>` envelope.
  ///
  /// Any cgi-style options are stripped from [language] for the `data-lang`
  /// attribute. In inline-CSS mode the theme's base style is resolved (which
  /// also records the style for later [docinfoHead] calls, mirroring the
  /// Ruby `@style` assignment) and attached as the `<pre>` `style`
  /// attribute; without a backend no `style` attribute is emitted.
  String format({
    required String content,
    String? language,
    bool nowrap = false,
    CssMode cssMode = CssMode.classes,
    String? style,
  }) {
    var lang = language;
    final queryIndex = lang?.indexOf('?');
    if (queryIndex != null && queryIndex >= 0) {
      lang = lang!.substring(0, queryIndex);
    }
    String? preStyle;
    if (cssMode != CssMode.classes) {
      _style = resolveStyle(style);
      preStyle = baseStyle(_style!);
    }
    return wrapSourceBlock(
      preClass: preClass,
      content: content,
      language: lang,
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

  /// Returns the head markup for the Rouge stylesheet.
  ///
  /// When [linkCss] is set, links `{stylesDir}/rouge-{style}.css`
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

  /// Writes the Rouge stylesheet for the resolved style to [toDir]
  /// (`write_stylesheet`).
  void writeStylesheet(String toDir) {
    File('$toDir/${stylesheetBasename(_style)}')
        .writeAsStringSync(readStylesheet(_style));
  }

  /// Resolves a requested style name to a usable one.
  ///
  /// Returns [style] when the backend offers it, else [defaultStyle].
  /// Without a backend every style is unknown, so this always returns
  /// [defaultStyle]. (The Ruby adapter would crash resolving a style with no
  /// library loaded; returning the default is the graceful equivalent.)
  String resolveStyle(String? style) =>
      style != null && styleAvailable(style) ? style : defaultStyle;

  /// Whether [style] names a theme the backend can render
  /// (`style_available?`).
  ///
  /// Always false without a backend.
  bool styleAvailable(String style) => lexer?.styleAvailable(style) ?? false;

  /// The inline `<pre>` style for [style] (`base_style`), or `null` when the
  /// style contributes none or no backend is available.
  String? baseStyle(String style) => lexer?.baseStyle(style);

  /// The rendered stylesheet for [style] (`read_stylesheet`).
  ///
  /// Falls back to [unavailableStylesheet] when no backend is available.
  String readStylesheet(String? style) =>
      lexer?.stylesheet(style ?? defaultStyle) ?? unavailableStylesheet;

  /// The stylesheet file name for [style] (`stylesheet_basename`).
  String stylesheetBasename(String? style) =>
      'rouge-${style ?? defaultStyle}.css';
}

/// Splits delegate-formatted [innerHtml] into per-line fragments.
///
/// Mirrors the `token_lines` walk feeding the `RougeExt` formatters: lines
/// are separated by `\n`, and a trailing newline terminates the last line
/// rather than starting an empty one.
List<String> splitHtmlLines(String innerHtml) {
  if (innerHtml.isEmpty) return const [];
  final parts = innerHtml.split('\n');
  if (parts.last == '') parts.removeLast();
  return parts;
}

/// Emphasizes the 1-based [lines] in pre-split [htmlLines].
///
/// Port of `RougeExt::Formatters::HTMLLineHighlighter#stream`: every line is
/// re-emitted with a terminating newline, and emphasized lines are wrapped in
/// `<span class="hll">` (the newline sits inside the span). Returns one
/// newline-terminated fragment per input line.
List<String> highlightHtmlLines(
  List<String> htmlLines, [
  List<int> lines = const [],
]) {
  if (lines.isEmpty) return [for (final line in htmlLines) '$line\n'];
  final wanted = lines.toSet();
  final result = <String>[];
  for (var index = 0; index < htmlLines.length; index++) {
    final line = '${htmlLines[index]}\n';
    result.add(
      wanted.contains(index + 1) ? '<span class="hll">$line</span>' : line,
    );
  }
  return result;
}

/// Prepends right-justified line numbers to newline-terminated [htmlLines].
///
/// Port of `RougeExt::Formatters::HTMLLineNumberer#stream`: each line gains a
/// `<span class="linenos">` prefix, padded with spaces to the width of the
/// last line number. Numbering starts at [startLine].
String numberHtmlLinesInline(List<String> htmlLines, {int startLine = 1}) {
  if (htmlLines.isEmpty) return '';
  final width = (startLine + htmlLines.length - 1).toString().length;
  final result = StringBuffer();
  for (var index = 0; index < htmlLines.length; index++) {
    result.write(
      '<span class="linenos">'
      '${(startLine + index).toString().padLeft(width)}'
      '</span>${htmlLines[index]}',
    );
  }
  return result.toString();
}

/// Lays newline-terminated [htmlLines] out as a line-number table.
///
/// Port of `RougeExt::Formatters::HTMLTableLineNumberer#stream`: one table
/// row per line with `linenos` and `code` cells. Numbering starts at
/// [startLine].
///
/// NOTE: mirrors the upstream quirk that a single-line table is never
/// closed: the `<table><tbody>` prefix attaches to the first row while the
/// `</tbody></table>` suffix attaches to the last row only when it is not
/// also the first.
String numberHtmlLinesAsTable(List<String> htmlLines, {int startLine = 1}) {
  if (htmlLines.isEmpty) return '';
  final lastIndex = htmlLines.length - 1;
  final result = StringBuffer();
  for (var index = 0; index < htmlLines.length; index++) {
    final row =
        '<tr><td class="linenos"><pre>${startLine + index}</pre></td>'
        '<td class="code"><pre>${htmlLines[index]}</pre></td></tr>';
    if (index == 0) {
      result.write('<table class="linenotable"><tbody>$row');
    } else if (index == lastIndex) {
      result.write('$row</tbody></table>');
    } else {
      result.write(row);
    }
  }
  return result.toString();
}
