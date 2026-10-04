/// CodeRay adapter: server-side highlighting with a static stylesheet.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter/coderay.rb`.
///
/// The HTML format/wrap/docinfo logic is fully ported. Actual lexing sits
/// behind the [SourceLexer] seam: CodeRay uses only [SourceLexer.highlight],
/// which must replicate `CodeRay::Duo[lang, :html, opts].highlight source`
/// end to end (the backend owns line numbers, line emphasis, and the
/// unknown-language `:text` fallback). The stylesheet is a static asset
/// served from the embedded data files, so the lexer's style members are
/// never consulted.
library;

import 'dart:io';

import 'package:asciidoctor/src/stylesheets.dart';
import 'package:asciidoctor/src/highlight/highlight.dart';

/// Syntax-highlighter adapter for CodeRay.
///
/// Server-side adapter: [highlight] delegates lexing to the injected
/// [SourceLexer] and only computes the callout offset for table-numbered
/// output. [format] is the plain [wrapSourceBlock] wrapper (the Ruby adapter
/// defines no `format` override).
class CodeRayAdapter {
  /// Creates a CodeRay adapter, optionally with a [lexer] backend.
  CodeRayAdapter({this.lexer});

  /// Names this adapter registers for (`register_for 'coderay'`).
  static const List<String> registeredNames = ['coderay'];

  /// The adapter name.
  static const String name = 'coderay';

  /// The `<pre>` CSS class.
  static const String preClass = 'CodeRay';

  /// The stylesheet file name.
  static const String stylesheetBasename = 'coderay-asciidoctor.css';

  /// Opening tag of the code cell in table-numbered output, anchoring the
  /// callout-restoration offset.
  static const String _codeCellStartTag = '<td class="code"><pre>';

  /// The lexing backend, or `null` when no backend is available.
  ///
  /// Mirrors the Ruby loader: the library counts as available exactly when a
  /// backend is present.
  final SourceLexer? lexer;

  bool _requiresStylesheet = false;

  /// Whether server-side highlighting can run (`highlight?`).
  ///
  /// True exactly when a [lexer] backend was provided.
  bool get canHighlight => lexer != null;

  /// Whether any highlighted output so far requires the adapter stylesheet.
  ///
  /// Set by the first [highlight] call in [CssMode.classes] mode.
  bool get requiresStylesheet => _requiresStylesheet;

  /// Highlights [source] using the [lexer] backend.
  ///
  /// [language] is passed through untouched (a missing language arrives as
  /// `'text'`, mirroring the Ruby `:text` default); unknown-alias fallback
  /// is the backend's job. [numberLines], [startLineNumber], and
  /// [highlightLines] are forwarded to the backend, which renders them
  /// (Ruby `CodeRay::Duo` options `line_numbers`, `line_number_start`, and
  /// `highlight_lines`).
  ///
  /// When [numberLines] is [LineNumbersMode.table] and [hasCallouts] is set,
  /// the result carries the offset just past the code cell's opening tag so
  /// extracted callout marks can be restored (`nil` when the tag is absent).
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
  }) {
    final backend = lexer;
    if (backend == null) {
      throw UnimplementedError(
        'CodeRay highlighting needs a SourceLexer backend; '
        'real lexers are a later wave.',
      );
    }
    if (cssMode == CssMode.classes) _requiresStylesheet = true;
    final html = backend.highlight(
      HighlightRequest(
        source: source,
        language: language ?? 'text',
        cssMode: cssMode,
        numberLines: numberLines,
        startLineNumber: startLineNumber ?? 1,
        highlightLines: highlightLines,
      ),
    );
    if (html == null) {
      throw StateError('CodeRay backend returned no output.');
    }
    if (numberLines == LineNumbersMode.table && hasCallouts) {
      final index = html.indexOf(_codeCellStartTag);
      return HighlightResult(
        html,
        index < 0 ? null : index + _codeCellStartTag.length,
      );
    }
    return HighlightResult(html);
  }

  /// Wraps converted [content] in the plain `<pre>`/`<code>` envelope.
  ///
  /// The Ruby adapter defines no `format` override, so this is exactly
  /// [wrapSourceBlock] with the `CodeRay` pre class.
  String format({
    required String content,
    String? language,
    bool nowrap = false,
  }) => wrapSourceBlock(
    preClass: preClass,
    content: content,
    language: language,
    nowrap: nowrap,
  );

  /// Whether this adapter injects markup at [location].
  ///
  /// True only for [DocinfoLocation.head] once [requiresStylesheet] is set.
  bool hasDocinfo(DocinfoLocation location) =>
      _requiresStylesheet && location == DocinfoLocation.head;

  /// Returns the head markup for the CodeRay stylesheet.
  ///
  /// When [linkCss] is set, links `{stylesDir}/coderay-asciidoctor.css`
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
          'href="${stylesheetHref(stylesheetBasename, stylesDir)}"'
          '$selfClosingSlash>';
    }
    return '<style>\n$stylesheetData\n</style>';
  }

  /// Whether the adapter wants its stylesheet written to disk
  /// (`write_stylesheet?`).
  bool get wantsStylesheetFile => _requiresStylesheet;

  /// Writes the CodeRay stylesheet to [toDir] (`write_stylesheet`).
  void writeStylesheet(String toDir) {
    File('$toDir/$stylesheetBasename').writeAsStringSync(stylesheetData);
  }

  /// The CodeRay stylesheet data (`read_stylesheet`).
  ///
  /// Served from the embedded data files with trailing whitespace stripped,
  /// exactly like the Ruby `File.read(...).rstrip`.
  String get stylesheetData => Stylesheets.instance.coderayStylesheetData;
}
