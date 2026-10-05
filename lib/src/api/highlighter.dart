part of 'api.dart';

/// Source code to highlight.
final class SourceCode {
  const new _(this.source, this.language, this.highlightLines);

  /// The code (callout marks removed).
  final String source;

  /// The language, as written on the block, if any.
  final String? language;

  /// The 1-based lines to emphasize (the `highlight` attribute).
  final List<int> highlightLines;
}

/// A syntax highlighter, registered with [Asciidart.new] under the name the
/// `source-highlighter` attribute selects.
abstract class Highlighter {
  /// Creates a highlighter.
  const new();

  /// The HTML for [code]: the content of its `<code>` element, with
  /// special characters escaped.
  String highlight(SourceCode code);

  /// Markup to add to the HTML `<head>` (a stylesheet, for example), if
  /// any.
  String? get head => null;

  /// Markup to add at the end of the HTML body (a script, for example), if
  /// any.
  String? get footer => null;
}

/// Adapts a [Highlighter] to the implementation's highlighter interface.
final class _HighlighterAdapter extends impl.SyntaxHighlighterBase {
  new(this.name, this._highlighter);

  @override
  final String name;

  final Highlighter _highlighter;

  @override
  bool get canHighlight => true;

  @override
  impl.HighlightResult highlight(
    impl.AbstractBlock node,
    String source,
    String? language, {
    Map<int, String>? callouts,
    impl.CssMode cssMode = impl.CssMode.classes,
    List<int> highlightLines = const <int>[],
    impl.LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    String? style,
  }) => impl.HighlightResult(
    _highlighter.highlight(SourceCode._(source, language, highlightLines)),
  );

  @override
  bool hasDocinfo(String location) =>
      (location == 'head' ? _highlighter.head : _highlighter.footer) != null;

  @override
  String docinfo(
    String location,
    impl.Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) => (location == 'head' ? _highlighter.head : _highlighter.footer) ?? '';
}
