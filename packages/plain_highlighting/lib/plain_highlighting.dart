/// plain_highlighting: syntax highlighting for 190+ languages in pure Dart,
/// compatible with highlight.js 11.12.0.
///
/// ```dart
/// import 'package:plain_highlighting/plain_highlighting.dart';
///
/// void main() {
///   final result = highlighting.highlight('final x = 1;', language: 'dart');
///   print(result.html); // <span class="hljs-keyword">final</span> x = ...
/// }
/// ```
///
/// The output is HTML with highlight.js's CSS classes (`hljs-keyword`,
/// `hljs-string`, ...), so any highlight.js theme styles it.
library;

export 'src/api.dart' show HighlightResult, Highlighting, highlighting;
export 'src/styles.g.dart' show highlightJsStyles;
