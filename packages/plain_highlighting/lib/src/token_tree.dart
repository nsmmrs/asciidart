/// The token tree the highlighter builds, and its HTML rendering.
///
/// Port of `src/lib/token_tree.js` and `src/lib/html_renderer.js`.
library;

import 'package:plain_highlighting/src/utils.dart';

/// A node of the token tree: a scope with children (text and nodes).
final class TokenNode {
  /// A node for [scope].
  new([this.scope]);

  /// The scope (`keyword`, `title.function`, `language:xml`), or `null` for
  /// a node that wraps nothing (the root of a tree).
  String? scope;

  /// Text (`String`) and nested [TokenNode]s, in order.
  final List<Object> children = [];
}

/// Builds the token tree while highlighting (`TokenTreeEmitter`).
final class Emitter {
  /// An emitter writing CSS classes with [classPrefix].
  new(this.classPrefix);

  /// The prefix of the CSS classes ([toHtml]).
  final String classPrefix;

  /// The root of the tree.
  final TokenNode root = TokenNode();

  late final List<TokenNode> _stack = [root];

  TokenNode get _top => _stack.last;

  /// Adds [text] to the current node.
  void addText(String text) {
    if (text.isEmpty) return;
    _top.children.add(text);
  }

  /// Opens a node for [scope] inside the current one.
  void openNode(String scope) {
    final node = TokenNode(scope);
    _top.children.add(node);
    _stack.add(node);
  }

  /// Closes the current node.
  void closeNode() {
    if (_stack.length > 1) _stack.removeLast();
  }

  /// Adds the tree of a sub-language's [emitter], scoped `language:name`
  /// when [name] is given.
  void addSublanguage(Emitter emitter, String? name) {
    final node = emitter.root;
    if (name != null && name.isNotEmpty) node.scope = 'language:$name';
    _top.children.add(node);
  }

  /// Closes every open node.
  void finalize() {
    while (_stack.length > 1) {
      _stack.removeLast();
    }
  }

  /// The tree as HTML.
  String toHtml() {
    final buffer = StringBuffer();
    _render(root, buffer);
    return buffer.toString();
  }

  void _render(TokenNode node, StringBuffer buffer) {
    final scope = node.scope;
    final wraps = scope != null && scope.isNotEmpty;
    if (wraps) buffer.write('<span class="${_cssClass(scope)}">');
    for (final child in node.children) {
      if (child is String) {
        buffer.write(escapeHtml(child));
      } else {
        _render(child as TokenNode, buffer);
      }
    }
    if (wraps) buffer.write('</span>');
  }

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
