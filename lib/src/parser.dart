/// Temporary parser API contract (wave-4 replaces this stub).
///
/// Defines the [Parser] surface that [Document] and [Reader] compile
/// against until the real `parser.rb` port lands. Every member throws.
/// The parser worker deletes this file content and implements the port,
/// un-skips the reader indent tests, and wires the barrel export.
library;

/// Document parser. STUB — see library comment.
abstract final class Parser {
  /// Parses source from [reader] into [document].
  ///
  /// Types are [Object] until the model/reader/document ports merge;
  /// the parser worker sharpens them to the real node types.
  static void parse(
    Object reader,
    Object document, {
    bool headerOnly = false,
  }) => throw UnimplementedError('Parser.parse (parser wave replaces stub)');

  /// Adjusts indentation of [result] in place (Ruby mutates; Dart returns).
  static String adjustIndentation(String result, int indent, int tabsize) =>
      throw UnimplementedError(
        'Parser.adjustIndentation (parser wave replaces stub)',
      );
}
