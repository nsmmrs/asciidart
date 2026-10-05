/// Configurable fake [SourceLexer] for the syntax-highlighter adapter tests.
///
/// Each fake records the last [HighlightRequest] it received so tests can
/// assert what the adapter asked the backend to do, and returns canned
/// responses. The canned backend payloads used by the adapter tests were
/// captured from the real Ruby backends (rouge 3.30.0, coderay 1.1.3,
/// pygments.rb 5.0.0); see the cross-check log in the port report.
library;

import 'package:asciidart/src/internal.dart';

/// A configurable fake lexing backend.
class FakeSourceLexer implements SourceLexer {
  /// Creates a fake backend.
  ///
  /// Unspecified callbacks use inert defaults: [highlight] returns `null`,
  /// no style is available, no base style or stylesheet exists.
  new({
    this.name = 'fake',
    String? Function(HighlightRequest request)? onHighlight,
    bool Function(String style)? onStyleAvailable,
    String? Function(String style)? onBaseStyle,
    String? Function(String style)? onStylesheet,
  }) : onHighlight = onHighlight ?? ((_) => null),
       onStyleAvailable = onStyleAvailable ?? ((_) => false),
       onBaseStyle = onBaseStyle ?? ((_) => null),
       onStylesheet = onStylesheet ?? ((_) => null);
  @override
  final String name;

  /// The most recent request passed to [highlight], if any.
  HighlightRequest? lastRequest;

  /// Canned responses consulted by each member.
  final String? Function(HighlightRequest request) onHighlight;
  final bool Function(String style) onStyleAvailable;
  final String? Function(String style) onBaseStyle;
  final String? Function(String style) onStylesheet;

  @override
  String? highlight(HighlightRequest request) {
    lastRequest = request;
    return onHighlight(request);
  }

  @override
  bool styleAvailable(String style) => onStyleAvailable(style);

  @override
  String? baseStyle(String style) => onBaseStyle(style);

  @override
  String? stylesheet(String style) => onStylesheet(style);
}
