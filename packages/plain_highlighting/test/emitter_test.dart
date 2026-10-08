/// The emitter writes HTML as it goes: the same HTML as building the
/// token tree and rendering it (the previous emitter, kept here as the
/// oracle), for random sequences of what the highlighter emits.
library;

import 'dart:math';

import 'package:plain_highlighting/src/token_tree.dart';
import 'package:plain_highlighting/src/utils.dart';
import 'package:test/test.dart';

/// A node of the oracle's tree.
final class _Node {
  new([this.scope]);
  String? scope;
  final List<Object> children = [];
}

/// The previous emitter: a token tree, rendered at the end.
final class _TreeEmitter {
  new(this.classPrefix);
  final String classPrefix;
  final _Node root = _Node();
  late final List<_Node> _stack = [root];

  void addText(String text) {
    if (text.isEmpty) return;
    _stack.last.children.add(text);
  }

  void openNode(String scope) {
    final node = _Node(scope);
    _stack.last.children.add(node);
    _stack.add(node);
  }

  void closeNode() {
    if (_stack.length > 1) _stack.removeLast();
  }

  void addSublanguage(_TreeEmitter emitter, String? name) {
    final node = emitter.root;
    if (name != null && name.isNotEmpty) node.scope = 'language:$name';
    _stack.last.children.add(node);
  }

  void finalize() {
    while (_stack.length > 1) {
      _stack.removeLast();
    }
  }

  String toHtml() {
    final buffer = StringBuffer();
    _render(root, buffer);
    return buffer.toString();
  }

  void _render(_Node node, StringBuffer buffer) {
    final scope = node.scope;
    final wraps = scope != null && scope.isNotEmpty;
    if (wraps) buffer.write('<span class="${_cssClass(scope)}">');
    for (final child in node.children) {
      if (child is String) {
        buffer.write(escapeHtml(child));
      } else {
        _render(child as _Node, buffer);
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

const _scopes = [
  '',
  'keyword',
  'title.function',
  'meta.prompt.x',
  'language:xml',
  'string',
];
const _texts = ['', 'a', 'x < y', '"&"', "it's", 'é\n'];
const List<String?> _names = [null, '', 'xml', 'css'];

/// Emits the same random operations to both emitters, nesting
/// sub-languages up to [depth].
void _emit(Random random, Emitter emitter, _TreeEmitter tree, int depth) {
  for (var n = random.nextInt(30); n > 0; n--) {
    switch (random.nextInt(10)) {
      case 0 || 1 || 2:
        final text = _texts[random.nextInt(_texts.length)];
        emitter.addText(text);
        tree.addText(text);
      case 3:
        final text = _texts[random.nextInt(_texts.length)];
        final start = random.nextInt(text.length + 1);
        final end = start + random.nextInt(text.length - start + 1);
        emitter.addSlice(text, start, end);
        tree.addText(text.substring(start, end));
      case 4 || 5:
        final scope = _scopes[random.nextInt(_scopes.length)];
        emitter.openNode(scope);
        tree.openNode(scope);
      case 6 || 7:
        emitter.closeNode();
        tree.closeNode();
      case 8 when depth > 0:
        final subEmitter = Emitter(emitter.classPrefix);
        final subTree = _TreeEmitter(tree.classPrefix);
        _emit(random, subEmitter, subTree, depth - 1);
        if (random.nextBool()) {
          subEmitter.finalize();
          subTree.finalize();
        }
        final name = _names[random.nextInt(_names.length)];
        emitter.addSublanguage(subEmitter, name);
        tree.addSublanguage(subTree, name);
      default:
        if (random.nextInt(4) == 0) {
          emitter.finalize();
          tree.finalize();
        }
    }
  }
}

void main() {
  test('HTML as the token tree renders it', () {
    final random = Random(5);
    for (var n = 0; n < 20000; n++) {
      final prefix = n.isEven ? 'hljs-' : 'x-';
      final emitter = Emitter(prefix);
      final tree = _TreeEmitter(prefix);
      _emit(random, emitter, tree, 2);
      expect(emitter.toHtml(), tree.toHtml());
      emitter.finalize();
      tree.finalize();
      expect(emitter.toHtml(), tree.toHtml());
    }
  });
}
