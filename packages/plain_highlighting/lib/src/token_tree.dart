/// What the highlighter emits: HTML, written as it goes.
///
/// Port of `src/lib/token_tree.js` and `src/lib/html_renderer.js`, without
/// the tree: nothing reads it but the renderer, so each node's HTML is
/// written when the node opens, text as it is added, and the spans still
/// open are closed at the end, as rendering the tree would.
library;

import 'package:plain_highlighting/src/utils.dart';

/// Writes the HTML of the token tree while highlighting
/// (`TokenTreeEmitter` and `HTMLRenderer`).
final class Emitter {
  /// An emitter writing CSS classes with [classPrefix].
  new(this.classPrefix);

  /// The prefix of the CSS classes ([toHtml]).
  final String classPrefix;

  final StringBuffer _html = StringBuffer();

  /// For each open node, whether it wrote a span (a node with an empty
  /// scope wraps nothing).
  final List<bool> _open = [];

  /// The number of open nodes that wrote a span.
  int _spans = 0;

  /// Adds [text] to the current node.
  void addText(String text) {
    if (text.isEmpty) return;
    writeEscapedHtml(_html, text);
  }

  /// Adds the text of [source] from [start] to [end] to the current node.
  void addSlice(String source, int start, int end) {
    if (start >= end) return;
    writeEscapedHtml(_html, source, start, end);
  }

  /// Opens a node for [scope] inside the current one.
  void openNode(String scope) {
    final wraps = scope.isNotEmpty;
    if (wraps) _openSpan(_classes[scope] ??= _cssClass(scope));
    _open.add(wraps);
  }

  void _openSpan(String cssClass) {
    _html
      ..write('<span class="')
      ..write(cssClass)
      ..write('">');
    _spans++;
  }

  /// Closes the current node (none at the top).
  void closeNode() {
    if (_open.isEmpty) return;
    if (_open.removeLast()) {
      _html.write('</span>');
      _spans--;
    }
  }

  /// Adds what a sub-language's [emitter] emitted, scoped `language:name`
  /// when [name] is given.
  void addSublanguage(Emitter emitter, String? name) {
    final wraps = name != null && name.isNotEmpty;
    if (wraps) _openSpan(_classes['language:$name'] ??= 'language-$name');
    _html.write(emitter.toHtml());
    if (wraps) {
      _html.write('</span>');
      _spans--;
    }
  }

  /// Closes every open node.
  void finalize() {
    while (_open.isNotEmpty) {
      closeNode();
    }
  }

  /// The HTML, with the nodes still open closed.
  String toHtml() {
    if (_spans == 0) return _html.toString();
    return '$_html${'</span>' * _spans}';
  }

  /// The CSS classes of each scope, with [classPrefix].
  late final Map<String, String> _classes = _classesByPrefix[classPrefix] ??=
      {};
  static final Map<String, Map<String, String>> _classesByPrefix = {};

  String _cssClass(String name) {
    if (name.startsWith('language:')) {
      return name.replaceFirst('language:', 'language-');
    }
    if (name.contains('.')) {
      final pieces = name.split('.');
      return [
        '$classPrefix${pieces.first}',
        for (var i = 1; i < pieces.length; i++) '${pieces[i]}${'_' * i}',
      ].join(' ');
    }
    return '$classPrefix$name';
  }
}
