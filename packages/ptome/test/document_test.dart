/// Port of `test/document_test.rb` (156 tests).
///
/// All tests run: `convertFile`/`asciidoctorLoad`/`exampleDocument` are
/// implemented over `load.dart`, and XML/CSS assertions route through the
/// [XmlMatcher] mini-matcher ([assertXpath]/[assertCss]/[xmlnodesAtXpath]).
library;

import 'dart:io' show Directory, File;

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/load.dart' as api;
import 'package:test/test.dart';

import 'support/doc_helpers.dart';
import 'support/paths.dart';

/// Built-in converter element names (port of `BUILT_IN_ELEMENTS`).
const List<String> builtInElements = <String>[
  'admonition',
  'audio',
  'colist',
  'dlist',
  'document',
  'embedded',
  'example',
  'floating_title',
  'image',
  'inline_anchor',
  'inline_break',
  'inline_button',
  'inline_callout',
  'inline_footnote',
  'inline_image',
  'inline_indexterm',
  'inline_kbd',
  'inline_menu',
  'inline_quoted',
  'listing',
  'literal',
  'stem',
  'olist',
  'open',
  'page_break',
  'paragraph',
  'pass',
  'preamble',
  'quote',
  'section',
  'sidebar',
  'table',
  'thematic_break',
  'toc',
  'ulist',
  'verse',
  'video',
];

/// Records log messages for assertions.
class FakeLogger extends LoggerBase {
  /// Creates a recording logger.
  new() : super(Severity.debug);

  /// Messages by severity, in logging order.
  final List<String> debugs = <String>[];
  final List<String> infos = <String>[];
  final List<String> warns = <String>[];
  final List<String> errors = <String>[];
  final List<String> fatals = <String>[];

  /// All recorded messages.
  List<String> get messages => <String>[
    ...debugs,
    ...infos,
    ...warns,
    ...errors,
    ...fatals,
  ];

  @override
  Severity? get maxSeverity => null;

  @override
  void add(Severity severity, LogMessage message) {
    switch (severity) {
      case Severity.debug:
        debugs.add('$message');
      case Severity.info:
        infos.add('$message');
      case Severity.warn:
        warns.add('$message');
      case Severity.error:
        errors.add('$message');
      case Severity.fatal || Severity.unknown:
        fatals.add('$message');
    }
  }

  @override
  Future<void> close() async {}
}

/// Runs [body] with a memory logger installed (port of
/// `using_memory_logger`).
void usingMemoryLogger(void Function(FakeLogger logger) body) {
  final saved = LoggerManager.logger;
  final logger = FakeLogger();
  LoggerManager.logger = logger;
  try {
    body(logger);
  } finally {
    LoggerManager.logger = saved;
  }
}

/// Converts the file at [path] to a string (port of
/// `Asciidoctor.convert_file` with `to_file: false`).
String convertFile(
  String path, {
  bool standalone = false,
  String? backend,
  int safe = SafeMode.secure,
  Map<String, String?> attributes = const <String, String?>{},
}) => api
    .loadFile(
      path,
      options: AsciidoctorOptions(
        standalone: standalone,
        backend: backend,
        safe: safe,
        attributes: attributes,
      ),
    )
    .convert();

/// Loads [input] into a parsed document (port of `Asciidoctor.load`).
Document asciidoctorLoad(
  String input, {
  String? backend,
  bool standalone = false,
}) => api.load(
  input,
  options: AsciidoctorOptions(backend: backend, standalone: standalone),
);

/// Loads a sample document (port of `example_document`).
///
/// Reads `vendor/asciidoctor/test/fixtures/<name>.<ext>` for the first matching `ext` in
/// `adoc`/`asciidoc`/`txt` (port of `sample_doc_path`), then parses it via
/// [documentFromString] with [options].
Document exampleDocument(
  String name, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) {
  for (final ext in const ['adoc', 'asciidoc', 'txt']) {
    final path = fixturePath('$name.$ext');
    if (File(path).existsSync()) {
      return documentFromString(File(path).readAsStringSync(), options);
    }
  }
  throw ArgumentError('no sample document found for name: $name');
}

/// Asserts [content] matches [xpath] [count] times (port of `assert_xpath`).
void assertXpath(String xpath, String? content, int count) {
  final nodes = XmlMatcher.parse(content ?? '').xpath(xpath);
  expect(
    nodes.length,
    equals(count),
    reason:
        'xpath $xpath matched ${nodes.length}, expected $count in:\n$content',
  );
}

/// Asserts [content] matches [css] [count] times (port of `assert_css`).
void assertCss(String css, String? content, int count) {
  final nodes = XmlMatcher.parse(content ?? '').css(css);
  expect(
    nodes.length,
    equals(count),
    reason: 'css $css matched ${nodes.length}, expected $count in:\n$content',
  );
}

/// The nodes matching [xpath] in [content] (port of `xmlnodes_at_xpath`).
XmlNodeSet xmlnodesAtXpath(String xpath, String? content) =>
    XmlMatcher.parse(content ?? '').xpath(xpath);

/// The first node matching [xpath] in [content] (port of
/// `xmlnodes_at_xpath xpath, content, 1`).
XmlNode xmlnodeAtXpath(String xpath, String? content) =>
    xmlnodesAtXpath(xpath, content).first;

/// Fails unless [result] is well-formed XML (port of the
/// `Nokogiri::XML::Document.parse(result) { STRICT | NONET }` assertion).
void assertWellFormedXml(String result) {
  try {
    _checkWellFormedXml(result);
  } on FormatException catch (e) {
    fail(
      'xhtml5 backend did not generate well-formed XML: '
      '${e.message}\n$result',
    );
  }
}

/// Throws [FormatException] unless [source] is well-formed XML.
///
/// Checks tag balance and nesting, quoted attributes, exactly one root
/// element, no markup-looking text (`<` outside tags, undefined entities),
/// and no content outside the root besides the prolog, doctype, comments,
/// processing instructions, and whitespace.
void _checkWellFormedXml(String source) {
  void failAt(String message, int offset) {
    final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
    throw FormatException('$message (line $line)');
  }

  final nameRx = RegExp(r'[A-Za-z_][\w:.-]*');
  final stack = <String>[];
  var offset = 0;
  var rootCount = 0;

  void skipWhitespace() {
    while (offset < source.length &&
        const {' ', '\t', '\r', '\n'}.contains(source[offset])) {
      offset++;
    }
  }

  // Skips one prolog/doctype/comment/PI/cdata token at [offset]; returns
  // whether a token was consumed.
  bool skipTrivia() {
    if (source.startsWith('<!--', offset)) {
      final end = source.indexOf('-->', offset + 4);
      if (end < 0) failAt('unterminated comment', offset);
      offset = end + 3;
      return true;
    }
    if (source.startsWith('<![CDATA[', offset)) {
      final end = source.indexOf(']]>', offset + 9);
      if (end < 0) failAt('unterminated CDATA section', offset);
      offset = end + 3;
      return true;
    }
    if (source.startsWith('<?', offset)) {
      final end = source.indexOf('?>', offset + 2);
      if (end < 0) failAt('unterminated processing instruction', offset);
      offset = end + 2;
      return true;
    }
    if (source.startsWith('<!DOCTYPE', offset) &&
        (offset + 9 >= source.length ||
            RegExp(r'[\s>]').hasMatch(source[offset + 9]))) {
      var pos = offset + 9;
      var depth = 0;
      while (pos < source.length) {
        if (source[pos] == '[') depth++;
        if (source[pos] == ']') depth--;
        if (source[pos] == '>' && depth == 0) break;
        pos++;
      }
      if (pos >= source.length) failAt('unterminated doctype', offset);
      offset = pos + 1;
      return true;
    }
    return false;
  }

  void checkText(String text, int start) {
    if (text.contains(']]>')) failAt(']]> in text', start);
    for (final match in RegExp('&').allMatches(text)) {
      final rest = text.substring(match.start);
      if (!RegExp('^&#(?:[0-9]+|x[0-9A-Fa-f]+);|^&(amp|lt|gt|quot|apos);')
          .hasMatch(rest)) {
        failAt('invalid entity reference', start + match.start);
      }
    }
  }

  while (true) {
    skipWhitespace();
    if (offset >= source.length) break;
    if (skipTrivia()) continue;
    if (source[offset] != '<') {
      final start = offset;
      final end = source.indexOf('<', offset);
      final text = source.substring(start, end < 0 ? source.length : end);
      if (stack.isEmpty && text.trim().isNotEmpty) {
        failAt('content outside root element', start);
      }
      checkText(text, start);
      offset = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('</', offset)) {
      final match = nameRx.matchAsPrefix(source, offset + 2);
      if (match == null) failAt('invalid close tag', offset);
      final name = match!.group(0)!;
      var pos = match.end;
      while (pos < source.length && source[pos].trim().isEmpty) {
        pos++;
      }
      if (pos >= source.length || source[pos] != '>') {
        failAt('invalid close tag', offset);
      }
      offset = pos + 1;
      if (stack.isEmpty) {
        failAt('stray close tag $name', offset);
      }
      if (stack.removeLast() != name) {
        failAt('mismatched close tag $name', offset);
      }
      continue;
    }
    final match = nameRx.matchAsPrefix(source, offset + 1);
    if (match == null) failAt('invalid open tag', offset);
    final name = match!.group(0)!;
    var pos = match.end;
    final attrs = <String>{};
    while (true) {
      while (pos < source.length && source[pos].trim().isEmpty) {
        pos++;
      }
      if (pos >= source.length) failAt('unterminated open tag $name', offset);
      if (source[pos] == '>') {
        pos++;
        stack.add(name);
        if (stack.length == 1) rootCount++;
        break;
      }
      if (source[pos] == '/' &&
          pos + 1 < source.length &&
          source[pos + 1] == '>') {
        pos += 2;
        if (stack.isEmpty) rootCount++;
        break;
      }
      final attr = nameRx.matchAsPrefix(source, pos);
      if (attr == null) failAt('invalid attribute in $name', pos);
      final attrName = attr!.group(0)!;
      if (!attrs.add(attrName)) failAt('duplicate attribute $attrName', pos);
      pos = attr.end;
      while (pos < source.length && source[pos].trim().isEmpty) {
        pos++;
      }
      if (pos >= source.length || source[pos] != '=') {
        failAt('unquoted attribute $attrName', pos);
      }
      pos++;
      while (pos < source.length && source[pos].trim().isEmpty) {
        pos++;
      }
      if (pos >= source.length || (source[pos] != '"' && source[pos] != "'")) {
        failAt('unquoted attribute $attrName', pos);
      }
      final quote = source[pos];
      final end = source.indexOf(quote, pos + 1);
      if (end < 0) failAt('unterminated attribute $attrName', pos);
      checkText(source.substring(pos + 1, end), pos + 1);
      if (source.substring(pos + 1, end).contains('<')) {
        failAt('bare < in attribute $attrName', pos);
      }
      pos = end + 1;
    }
    offset = pos;
  }
  if (stack.isNotEmpty) failAt('unclosed tag ${stack.last}', offset);
  if (rootCount != 1) failAt('expected one root element, found $rootCount', 0);
}

/// A parsed XML/HTML element or text node for the assert helpers.
///
/// Element names and attribute names keep their literal spelling; namespace
/// prefixes are preserved so [namespaces] and `xml:id`-style lookups work.
/// Text nodes have [isText] set and carry their (entity-decoded) content in
/// [text].
class XmlNode {
  /// Creates an element node.
  new element(
    this.name, {
    Map<String, String>? attributes,
    List<XmlNode>? children,
    this.parent,
  }) : attributes = attributes ?? <String, String>{},
       children = children ?? <XmlNode>[],
       isText = false,
       _text = null;

  /// Creates a text node with decoded content [text].
  new text(String text, {this.parent})
    : name = '#text',
      attributes = <String, String>{},
      children = <XmlNode>[],
      isText = true,
      _text = text;

  /// Element name as written (with prefix, if any); `#text` for text nodes.
  final String name;

  /// Decoded attribute values by literal attribute name.
  final Map<String, String> attributes;

  /// Child nodes (elements and text nodes, in document order).
  final List<XmlNode> children;

  /// Parent element, or `null` for top-level nodes.
  final XmlNode? parent;

  /// Sibling context for top-level nodes (set by the parser so
  /// `following-sibling` and `+` work across fragment roots).
  late List<XmlNode>? _rootSiblings;

  /// Whether this is a text node.
  final bool isText;

  final String? _text;

  /// Local element name (prefix stripped); `#text` for text nodes.
  String get localName {
    final idx = name.indexOf(':');
    return idx < 0 ? name : name.substring(idx + 1);
  }

  /// Concatenated descendant text (element) or content (text node).
  String get text {
    if (isText) return _text ?? '';
    final buffer = StringBuffer();
    void collect(XmlNode node) {
      for (final child in node.children) {
        if (child.isText) {
          buffer.write(child._text);
        } else {
          collect(child);
        }
      }
    }

    collect(this);
    return buffer.toString();
  }

  /// Direct child text nodes, in document order.
  List<XmlNode> get textChildren =>
      children.where((child) => child.isText).toList();

  /// Child elements, in document order.
  List<XmlNode> get elementChildren =>
      children.where((child) => !child.isText).toList();

  /// In-scope namespace declarations (`'xmlns'` for the default namespace,
  /// `'xmlns:prefix'` otherwise), nearest wins (port of Nokogiri
  /// `Node#namespaces`).
  Map<String, String> get namespaces {
    final result = <String, String>{};
    final chain = <XmlNode>[];
    XmlNode? node = this;
    while (node != null) {
      chain.add(node);
      node = node.parent;
    }
    for (final ancestor in chain.reversed) {
      ancestor.attributes.forEach((key, value) {
        if (key == 'xmlns' || key.startsWith('xmlns:')) {
          result[key] = value;
        }
      });
    }
    return result;
  }

  /// The default namespace in scope (`''` when none is declared).
  String get namespaceUri => namespaces['xmlns'] ?? '';

  /// Returns the value of attribute [name], or `null` when absent.
  String? attr(String name) => attributes[name];

  /// Sibling elements (fragment roots for top-level nodes).
  List<XmlNode> get _siblings =>
      parent?.elementChildren ??
      _rootSiblings!.where((node) => !node.isText).toList();

  /// Previous sibling element, or `null` when first.
  XmlNode? get previousSiblingElement {
    final siblings = _siblings;
    final idx = siblings.indexOf(this);
    return idx > 0 ? siblings[idx - 1] : null;
  }

  /// Following sibling elements, in document order.
  List<XmlNode> followingSiblings() {
    final siblings = _siblings;
    return siblings.sublist(siblings.indexOf(this) + 1);
  }

  /// All descendant elements, in document order.
  List<XmlNode> descendants() {
    final result = <XmlNode>[];
    void collect(XmlNode node) {
      for (final child in node.elementChildren) {
        result.add(child);
        collect(child);
      }
    }

    collect(this);
    return result;
  }
}

/// A list of matched [XmlNode]s (port of Nokogiri's `NodeSet`).
class XmlNodeSet {
  /// Creates a node set wrapping [nodes].
  new([List<XmlNode>? nodes]) : nodes = nodes ?? <XmlNode>[];

  /// Matched nodes, in document order.
  final List<XmlNode> nodes;

  /// Number of matched nodes.
  int get length => nodes.length;

  /// Whether no nodes matched.
  bool get isEmpty => nodes.isEmpty;

  /// First matched node.
  XmlNode get first => nodes.first;

  /// Concatenated [XmlNode.text] of all matched nodes.
  String get text => nodes.map((node) => node.text).join();
}

/// A parsed document fragment (lenient HTML/XML parser) with XPath and CSS
/// matching for exactly the constructs this file's assertions use.
///
/// XPath subset: `/` and `//` steps, `(path)[n]` groups, `child`,
/// `following-sibling` and `self` axes, `tag`/`prefix:tag`/`*`/`text()`
/// node tests, and `[@attr="v"]`, `[text()="v"]`,
/// `[normalize-space(text())="v"]`, `[not(namespace-uri()="u")]`, and `[n]`
/// predicates. Prefixes are ignored (local-name matching), mirroring how
/// Ruby's helper binds `xmlns` to the document's default namespace.
///
/// CSS subset: type, `#id`, `.class`, `[attr]`, `[attr="v"]` (quoted or
/// bare, `prefix|name` for namespaced attributes), descendant/`>`/`+`
/// combinators, `*`, `:root`, and `:not(...)`.
class XmlMatcher {
  /// Creates a matcher over top-level [roots].
  new(this.roots);

  /// Parses [content] into a matcher.
  factory parse(String content) => XmlMatcher(_XmlParser(content).parse());

  /// Top-level nodes (fragments may have several roots).
  final List<XmlNode> roots;

  /// All elements in the fragment, in document order.
  List<XmlNode> get _allElements {
    final result = <XmlNode>[];
    for (final root in roots) {
      if (!root.isText) {
        result
          ..add(root)
          ..addAll(root.descendants());
      }
    }
    return result;
  }

  /// Evaluates [xpath] against the fragment.
  XmlNodeSet xpath(String xpath) => XmlNodeSet(_xpath(xpath).toList());

  /// Evaluates CSS [selector] against the fragment.
  XmlNodeSet css(String selector) {
    final chain = _CssParser(selector).parse();
    final matches = _allElements.where(
      (element) => _matchesCssChain(element, chain, chain.length - 1),
    );
    return XmlNodeSet(matches.toList());
  }

  bool _matchesCssChain(XmlNode element, List<_CssStep> chain, int index) {
    final step = chain[index];
    if (!_matchesCompound(element, step.compound)) return false;
    if (index == 0) return true;
    final combinator = step.combinator;
    if (combinator == '>') {
      final parent = element.parent;
      return parent != null && _matchesCssChain(parent, chain, index - 1);
    }
    if (combinator == '+') {
      final previous = element.previousSiblingElement;
      return previous != null && _matchesCssChain(previous, chain, index - 1);
    }
    var ancestor = element.parent;
    while (ancestor != null) {
      if (_matchesCssChain(ancestor, chain, index - 1)) return true;
      ancestor = ancestor.parent;
    }
    return false;
  }

  bool _matchesCompound(XmlNode element, _CssCompound compound) {
    if (compound.type != null && compound.type != '*') {
      if (element.localName != compound.type) return false;
    }
    for (final id in compound.ids) {
      if (element.attr('id') != id) return false;
    }
    final classes = (element.attr('class') ?? '').split(RegExp(r'\s+'));
    for (final cls in compound.classes) {
      if (!classes.contains(cls)) return false;
    }
    for (final attr in compound.attrs) {
      final actual = element.attr(attr.name);
      if (attr.value == null) {
        if (actual == null) return false;
      } else if (actual != attr.value) {
        return false;
      }
    }
    for (final pseudo in compound.pseudos) {
      if (pseudo == 'root') {
        if (element.parent != null) return false;
      } else if (pseudo.startsWith('not(')) {
        final inner = _CssParser(pseudo.substring(4, pseudo.length - 1))
            .parseSingle();
        if (_matchesCompound(element, inner)) return false;
      } else {
        throw ArgumentError('unsupported CSS pseudo-class: $pseudo');
      }
    }
    return true;
  }

  Iterable<XmlNode> _xpath(String xpath) {
    final parser = _XPathParser(xpath);
    final absolute = parser.consumeAbsolute();
    final elementRoots = roots.where((node) => !node.isText).toList();
    List<XmlNode> current;
    if (parser.atGroupStart) {
      current = parser.parseGroup(elementRoots);
    } else if (absolute == null) {
      throw ArgumentError('relative xpath not supported: $xpath');
    } else if (absolute) {
      current = _applyStepDocument(elementRoots, parser);
    } else {
      // Leading `//`: every element in the fragment, filtered by the step.
      final step = parser.parseStep();
      current = _filterStep(
        _allElements.where((e) => _matchesNodeTest(e, step)).toList(),
        step,
      );
    }
    while (!parser.atEnd) {
      final descendant = parser.consumeSeparator();
      if (parser.atEnd) break;
      current = _applyStep(current, parser.parseStep(), descendant: descendant);
    }
    return current;
  }

  /// Applies the first step of an absolute path to the fragment roots.
  List<XmlNode> _applyStepDocument(
    List<XmlNode> elementRoots,
    _XPathParser parser,
  ) {
    final step = parser.parseStep();
    return _filterStep(
      elementRoots.where((root) => _matchesNodeTest(root, step)).toList(),
      step,
    );
  }

  List<XmlNode> _applyStep(
    List<XmlNode> context,
    _XPathStep step, {
    required bool descendant,
  }) {
    final result = <XmlNode>[];
    for (final node in context) {
      final candidates = descendant ? node.descendants() : _axis(node, step);
      final matched = candidates.where(
        (candidate) => _matchesNodeTest(candidate, step),
      );
      result.addAll(descendant ? _filterStep(matched.toList(), step) : matched);
    }
    return descendant ? result : _filterStep(result, step);
  }

  List<XmlNode> _axis(XmlNode node, _XPathStep step) {
    switch (step.axis) {
      case 'self':
        return [node];
      case 'following-sibling':
        return node.followingSiblings();
      default:
        return node.children;
    }
  }

  bool _matchesNodeTest(XmlNode node, _XPathStep step) {
    if (step.textNode) return node.isText;
    if (node.isText) return false;
    if (step.name == '*') return true;
    return node.localName == step.name;
  }

  List<XmlNode> _filterStep(List<XmlNode> nodes, _XPathStep step) {
    var current = nodes;
    for (final predicate in step.predicates) {
      current = predicate.apply(current);
    }
    return current;
  }
}

/// An XPath predicate in the supported subset.
abstract class _XPathPredicate {
  /// Filters [nodes] (positional predicates are 1-based).
  List<XmlNode> apply(List<XmlNode> nodes);

  /// Parses the predicate starting just after `[`.
  static _XPathPredicate parse(_XPathParser parser) {
    if (parser.consumeNumber() case final position?) {
      parser.expect(']');
      return _PositionPredicate(position);
    }
    if (parser.consumeTextTest()) {
      parser.expect('=');
      final value = parser.parseString();
      parser.expect(']');
      return _TextEqualsPredicate(value);
    }
    if (parser.consumeIdentifier() case final name?) {
      if (name == 'not') {
        parser.expect('(');
        final inner = parser.consumeIdentifier();
        parser
          ..expect('(')
          ..expect(')')
          ..expect('=');
        final value = parser.parseString();
        parser
          ..expect(')')
          ..expect(']');
        if (inner != 'namespace-uri') {
          throw ArgumentError('unsupported not() predicate: $inner');
        }
        return _NotNamespacePredicate(value);
      }
      if (name == 'normalize-space') {
        parser.expect('(');
        if (!parser.consumeTextTest()) {
          throw ArgumentError('expected text() in normalize-space()');
        }
        parser
          ..expect(')')
          ..expect('=');
        final value = parser.parseString();
        parser.expect(']');
        return _NormalizeSpacePredicate(value);
      }
      throw ArgumentError('unsupported predicate function: $name');
    }
    if (parser.consume('@')) {
      final attrName = parser.parseAttrName();
      parser.expect('=');
      final value = parser.parseString();
      parser.expect(']');
      return _AttrEqualsPredicate(attrName, value);
    }
    throw ArgumentError('unsupported predicate in: ${parser.source}');
  }
}

/// Positional predicate (`[n]`, 1-based).
class _PositionPredicate extends _XPathPredicate {
  /// Creates a positional predicate for 1-based [position].
  new(this.position);

  /// 1-based position to keep.
  final int position;

  @override
  List<XmlNode> apply(List<XmlNode> nodes) =>
      position >= 1 && position <= nodes.length
      ? [nodes[position - 1]]
      : <XmlNode>[];
}

/// Attribute-equality predicate (`[@name="value"]`).
class _AttrEqualsPredicate extends _XPathPredicate {
  /// Creates an attribute-equality predicate.
  new(this.name, this.value);

  /// Attribute name (prefix kept literally, e.g. `xml:id`).
  final String name;

  /// Expected decoded value.
  final String value;

  @override
  List<XmlNode> apply(List<XmlNode> nodes) =>
      nodes.where((node) => node.attr(name) == value).toList();
}

/// Text-equality predicate (`[text()="value"]`, any direct text child).
class _TextEqualsPredicate extends _XPathPredicate {
  /// Creates a text-equality predicate.
  new(this.value);

  /// Expected decoded text.
  final String value;

  @override
  List<XmlNode> apply(List<XmlNode> nodes) => nodes
      .where((node) => node.textChildren.any((child) => child.text == value))
      .toList();
}

/// Whitespace-normalized text predicate
/// (`[normalize-space(text())="value"]`).
class _NormalizeSpacePredicate extends _XPathPredicate {
  /// Creates a normalized-text predicate.
  new(this.value);

  /// Expected normalized text.
  final String value;

  @override
  List<XmlNode> apply(List<XmlNode> nodes) => nodes.where((node) {
    final first = node.textChildren.isEmpty ? '' : node.textChildren.first.text;
    final normalized = first.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized == value;
  }).toList();
}

/// Namespace-exclusion predicate (`[not(namespace-uri()="uri")]`).
class _NotNamespacePredicate extends _XPathPredicate {
  /// Creates a namespace-exclusion predicate.
  new(this.uri);

  /// Excluded namespace URI.
  final String uri;

  @override
  List<XmlNode> apply(List<XmlNode> nodes) =>
      nodes.where((node) => node.namespaceUri != uri).toList();
}

/// An XPath location step in the supported subset.
class _XPathStep {
  /// Creates a step with [axis], node-test [name], and [predicates].
  new(this.axis, this.name, this.predicates, {this.textNode = false});

  /// Axis: `child` (default), `following-sibling`, or `self`.
  final String axis;

  /// Local node-test name, or `*`.
  final String name;

  /// Predicates to apply in order.
  final List<_XPathPredicate> predicates;

  /// Whether the node test is `text()`.
  final bool textNode;
}

/// Recursive-descent parser for the XPath subset.
class _XPathParser {
  /// Creates a parser over [source].
  new(this.source);

  /// The expression being parsed.
  final String source;

  /// Current offset.
  int offset = 0;

  /// Whether the parser consumed all input.
  bool get atEnd => offset >= source.length;

  /// Whether the next token opens a group.
  bool get atGroupStart => !atEnd && source[offset] == '(';

  /// Consumes a leading `/` (absolute) or `//` (descendant) marker.
  ///
  /// Returns `true` for `/`, `false` for `//`, `null` when relative.
  bool? consumeAbsolute() {
    if (source.startsWith('//', offset)) {
      offset += 2;
      return false;
    }
    if (offset < source.length && source[offset] == '/') {
      offset += 1;
      return true;
    }
    return null;
  }

  /// Consumes a `/` or `//` separator; returns whether it was `//`.
  bool consumeSeparator() {
    if (source.startsWith('//', offset)) {
      offset += 2;
      return true;
    }
    expect('/');
    return false;
  }

  /// Parses `(path)[n]` (with optional further predicates).
  List<XmlNode> parseGroup(List<XmlNode> roots) {
    expect('(');
    final start = offset;
    var depth = 1;
    while (depth > 0) {
      if (atEnd) throw ArgumentError('unterminated group in: $source');
      if (source[offset] == '(') depth++;
      if (source[offset] == ')') depth--;
      offset++;
    }
    final inner = source.substring(start, offset - 1);
    final evaluated = XmlMatcher(roots).xpath(inner).nodes;
    var current = evaluated;
    while (!atEnd && source[offset] == '[') {
      offset++;
      current = _XPathPredicate.parse(this).apply(current);
    }
    return current;
  }

  /// Parses one location step.
  _XPathStep parseStep() {
    var axis = 'child';
    final axisMatch = RegExp(r'([A-Za-z_][\w.-]*)::')
        .matchAsPrefix(source, offset);
    if (axisMatch != null) {
      axis = axisMatch.group(1)!;
      offset = axisMatch.end;
      if (axis != 'following-sibling' && axis != 'self') {
        throw ArgumentError('unsupported axis: $axis in: $source');
      }
    }
    var textNode = false;
    var name = '*';
    if (consumeTextTest()) {
      textNode = true;
    } else if (!atEnd && source[offset] == '*') {
      offset++;
    } else {
      name = parseName();
      final colon = name.indexOf(':');
      if (colon >= 0) name = name.substring(colon + 1);
    }
    final predicates = <_XPathPredicate>[];
    while (!atEnd && source[offset] == '[') {
      offset++;
      predicates.add(_XPathPredicate.parse(this));
    }
    return _XPathStep(axis, name, predicates, textNode: textNode);
  }

  /// Consumes `text()`, returning whether it matched.
  bool consumeTextTest() {
    if (source.startsWith('text()', offset)) {
      offset += 6;
      return true;
    }
    return false;
  }

  /// Consumes an identifier, returning `null` when absent.
  String? consumeIdentifier() {
    final match = RegExp(r'[A-Za-z_][\w.-]*').matchAsPrefix(source, offset);
    if (match == null) return null;
    offset = match.end;
    return match.group(0);
  }

  /// Consumes a 1-based position, returning `null` when absent.
  int? consumeNumber() {
    final match = RegExp('[0-9]+').matchAsPrefix(source, offset);
    if (match == null) return null;
    offset = match.end;
    return int.parse(match.group(0)!);
  }

  /// Consumes the literal [token], throwing when absent.
  void expect(String token) {
    if (!consume(token)) {
      throw ArgumentError('expected $token in: $source');
    }
  }

  /// Consumes the literal [token], returning whether it matched.
  bool consume(String token) {
    if (source.startsWith(token, offset)) {
      offset += token.length;
      return true;
    }
    return false;
  }

  /// Parses a quoted string (single or double quotes).
  String parseString() {
    if (atEnd || (source[offset] != '"' && source[offset] != "'")) {
      throw ArgumentError('expected string in: $source');
    }
    final quote = source[offset];
    final end = source.indexOf(quote, offset + 1);
    if (end < 0) throw ArgumentError('unterminated string in: $source');
    final value = source.substring(offset + 1, end);
    offset = end + 1;
    return value;
  }

  /// Parses an element or attribute name (prefix kept).
  String parseName() {
    final match = RegExp(r'[A-Za-z_][\w.:-]*').matchAsPrefix(source, offset);
    if (match == null) throw ArgumentError('expected name in: $source');
    offset = match.end;
    return match.group(0)!;
  }

  /// Parses an attribute name (`prefix:name` kept literally).
  String parseAttrName() => parseName();
}

/// A CSS compound selector in the supported subset.
class _CssCompound {
  /// Creates a compound selector.
  new({
    this.type,
    List<String>? ids,
    List<String>? classes,
    List<_CssAttr>? attrs,
    List<String>? pseudos,
  }) : ids = ids ?? <String>[],
       classes = classes ?? <String>[],
       attrs = attrs ?? <_CssAttr>[],
       pseudos = pseudos ?? <String>[];

  /// Type selector (`*` for universal), or `null` when absent.
  final String? type;

  /// Required id values.
  final List<String> ids;

  /// Required class values.
  final List<String> classes;

  /// Required attribute matchers.
  final List<_CssAttr> attrs;

  /// Pseudo-classes (`root`, `not(...)`).
  final List<String> pseudos;
}

/// A CSS attribute matcher.
class _CssAttr {
  /// Creates an attribute matcher ([value] `null` means presence only).
  new(this.name, this.value);

  /// Literal attribute name (`prefix|local` becomes `prefix:local`).
  final String name;

  /// Expected value, or `null` for presence.
  final String? value;
}

/// One compound selector plus the combinator joining it to its predecessor.
class _CssStep {
  /// Creates a chain step.
  new(this.compound, this.combinator);

  /// Compound selector for this step.
  final _CssCompound compound;

  /// Combinator to the previous step (`' '`, `'>'`, or `'+'`).
  final String combinator;
}

/// Recursive-descent parser for the CSS subset.
class _CssParser {
  /// Creates a parser over [source].
  new(this.source);

  /// The selector being parsed.
  final String source;

  /// Current offset.
  int offset = 0;

  /// Parses a full selector chain.
  List<_CssStep> parse() {
    final steps = [_CssStep(parseSingle(), ' ')];
    while (true) {
      _skipWhitespace();
      if (offset >= source.length) return steps;
      var combinator = ' ';
      if (source[offset] == '>' || source[offset] == '+') {
        combinator = source[offset];
        offset++;
        _skipWhitespace();
      }
      steps.add(_CssStep(parseSingle(), combinator));
    }
  }

  /// Parses one compound selector.
  _CssCompound parseSingle() {
    String? type;
    final ids = <String>[];
    final classes = <String>[];
    final attrs = <_CssAttr>[];
    final pseudos = <String>[];
    if (offset < source.length &&
        (source[offset] == '*' || _isNameStart(source[offset]))) {
      if (source[offset] == '*') {
        type = '*';
        offset++;
      } else {
        type = _parseName();
      }
    }
    while (offset < source.length) {
      final char = source[offset];
      if (char == '#') {
        offset++;
        ids.add(_parseName());
      } else if (char == '.') {
        offset++;
        classes.add(_parseName());
      } else if (char == '[') {
        offset++;
        attrs.add(_parseAttr());
      } else if (char == ':') {
        offset++;
        final name = _parseName();
        if (name == 'not') {
          _expect('(');
          final start = offset;
          var depth = 1;
          while (depth > 0) {
            if (offset >= source.length) {
              throw ArgumentError('unterminated :not() in: $source');
            }
            if (source[offset] == '(') depth++;
            if (source[offset] == ')') depth--;
            offset++;
          }
          pseudos.add('not(${source.substring(start, offset - 1)})');
        } else {
          pseudos.add(name);
        }
      } else {
        break;
      }
    }
    return _CssCompound(
      type: type,
      ids: ids,
      classes: classes,
      attrs: attrs,
      pseudos: pseudos,
    );
  }

  _CssAttr _parseAttr() {
    _skipWhitespace();
    var name = _parseName();
    _skipWhitespace();
    if (offset < source.length && source[offset] == '|') {
      offset++;
      name = '$name:${_parseName()}';
      _skipWhitespace();
    }
    String? value;
    if (offset < source.length && source[offset] == '=') {
      offset++;
      _skipWhitespace();
      value = _parseAttrValue();
      _skipWhitespace();
    }
    _expect(']');
    return _CssAttr(name, value);
  }

  String _parseAttrValue() {
    if (offset < source.length &&
        (source[offset] == '"' || source[offset] == "'")) {
      final quote = source[offset];
      final end = source.indexOf(quote, offset + 1);
      if (end < 0) throw ArgumentError('unterminated value in: $source');
      final value = source.substring(offset + 1, end);
      offset = end + 1;
      return value;
    }
    final match = RegExp(r'[^\s\]]+').matchAsPrefix(source, offset);
    if (match == null) throw ArgumentError('expected value in: $source');
    offset = match.end;
    return match.group(0)!;
  }

  String _parseName() {
    final match = RegExp(r'-?[A-Za-z_][\w-]*').matchAsPrefix(source, offset);
    if (match == null) throw ArgumentError('expected name in: $source');
    offset = match.end;
    return match.group(0)!;
  }

  void _expect(String token) {
    if (offset >= source.length || source[offset] != token) {
      throw ArgumentError('expected $token in: $source');
    }
    offset++;
  }

  void _skipWhitespace() {
    while (offset < source.length && source[offset].trim().isEmpty) {
      offset++;
    }
  }

  bool _isNameStart(String char) => RegExp('[A-Za-z_-]').hasMatch(char);
}

/// Lenient HTML/XML parser producing [XmlNode] trees.
///
/// Skips doctype declarations, processing instructions, and comments,
/// treats known void elements as self-closing, tolerates missing or
/// mismatched close tags, and preserves all top-level nodes so embedded
/// fragments keep their roots. Text and attribute values are
/// entity-decoded.
class _XmlParser {
  /// Creates a parser over [source].
  new(this.source);

  /// The markup being parsed.
  final String source;

  /// Current offset.
  int offset = 0;

  /// HTML void elements (never have children or close tags).
  static const Set<String> _voidElements = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };

  /// Named character references decoded in text and attribute values.
  static const Map<String, String> _entities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'laquo': '«',
    'raquo': '»',
    'dagger': '†',
    'Dagger': '‡',
    'bull': '•',
    'middot': '·',
    'sect': '§',
    'para': '¶',
    'oelig': 'œ',
    'OElig': 'Œ',
  };

  /// Parses the markup into top-level nodes.
  List<XmlNode> parse() {
    final roots = <XmlNode>[];
    final stack = <XmlNode>[];
    final text = StringBuffer();
    void flushText() {
      if (text.isEmpty) return;
      final node = XmlNode.text(
        _decodeEntities(text.toString()),
        parent: stack.isEmpty ? null : stack.last,
      );
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      text.clear();
    }

    while (offset < source.length) {
      if (source[offset] == '<') {
        if (source.startsWith('<!--', offset)) {
          flushText();
          final end = source.indexOf('-->', offset + 4);
          offset = end < 0 ? source.length : end + 3;
        } else if (source.startsWith('<![CDATA[', offset)) {
          flushText();
          final end = source.indexOf(']]>', offset + 9);
          final cdata = source.substring(
            offset + 9,
            end < 0 ? source.length : end,
          );
          text.write(cdata);
          flushText();
          offset = end < 0 ? source.length : end + 3;
        } else if (source.startsWith('<!', offset) ||
            source.startsWith('<?', offset)) {
          flushText();
          final end = source.indexOf('>', offset + 2);
          offset = end < 0 ? source.length : end + 1;
        } else if (source.startsWith('</', offset)) {
          flushText();
          final end = source.indexOf('>', offset + 2);
          final name =
              (end < 0
                      ? source.substring(offset + 2)
                      : source.substring(offset + 2, end))
                  .trim()
                  .split(RegExp(r'\s'))
                  .first;
          offset = end < 0 ? source.length : end + 1;
          for (var i = stack.length - 1; i >= 0; i--) {
            if (stack[i].name == name) {
              stack.removeRange(i, stack.length);
              break;
            }
          }
        } else {
          final tag = _parseTag();
          if (tag == null) {
            text.write(source[offset]);
            offset++;
          } else {
            flushText();
            final node = XmlNode.element(
              tag.name,
              attributes: tag.attributes,
              parent: stack.isEmpty ? null : stack.last,
            );
            if (stack.isEmpty) {
              roots.add(node);
            } else {
              stack.last.children.add(node);
            }
            if (!tag.selfClosing &&
                !_voidElements.contains(tag.name.toLowerCase())) {
              stack.add(node);
            }
          }
        }
      } else {
        text.write(source[offset]);
        offset++;
      }
    }
    flushText();
    for (final root in roots) {
      root._rootSiblings = roots;
    }
    return roots;
  }

  _XmlTag? _parseTag() {
    final match = RegExp(r'<([A-Za-z_][\w:.-]*)').matchAsPrefix(source, offset);
    if (match == null) return null;
    final name = match.group(1)!;
    var pos = match.end;
    final attributes = <String, String>{};
    while (pos < source.length) {
      while (pos < source.length && source[pos].trim().isEmpty) {
        pos++;
      }
      if (pos >= source.length) return null;
      if (source[pos] == '>') {
        offset = pos + 1;
        return _XmlTag(name, attributes, selfClosing: false);
      }
      if (source[pos] == '/' &&
          pos + 1 < source.length &&
          source[pos + 1] == '>') {
        offset = pos + 2;
        return _XmlTag(name, attributes, selfClosing: true);
      }
      final attrMatch = RegExp(r'([A-Za-z_][\w:.-]*)')
          .matchAsPrefix(source, pos);
      if (attrMatch == null) return null;
      final attrName = attrMatch.group(1)!;
      pos = attrMatch.end;
      while (pos < source.length && source[pos].trim().isEmpty) {
        pos++;
      }
      var value = '';
      if (pos < source.length && source[pos] == '=') {
        pos++;
        while (pos < source.length && source[pos].trim().isEmpty) {
          pos++;
        }
        if (pos < source.length && (source[pos] == '"' || source[pos] == "'")) {
          final quote = source[pos];
          final end = source.indexOf(quote, pos + 1);
          if (end < 0) return null;
          value = _decodeEntities(source.substring(pos + 1, end));
          pos = end + 1;
        } else {
          final valueMatch = RegExp(r'[^\s>]+').matchAsPrefix(source, pos);
          if (valueMatch == null) return null;
          value = _decodeEntities(valueMatch.group(0)!);
          pos = valueMatch.end;
        }
      }
      attributes[attrName] = value;
    }
    return null;
  }

  /// Decodes numeric and known named character references in [value].
  static String _decodeEntities(String value) => value.replaceAllMapped(
    RegExp(r'&#(x?[0-9A-Fa-f]+);|&([A-Za-z][\w]*);'),
    (match) {
      if (match.group(1) != null) {
        final digits = match.group(1)!;
        final code = digits.startsWith('x') || digits.startsWith('X')
            ? int.tryParse(digits.substring(1), radix: 16)
            : int.tryParse(digits);
        if (code != null) return String.fromCharCode(code);
      } else {
        final entity = _entities[match.group(2)!];
        if (entity != null) return entity;
      }
      return match.group(0)!;
    },
  );
}

/// A parsed open tag.
class _XmlTag {
  /// Creates a tag with [name], [attributes], and [selfClosing].
  new(this.name, this.attributes, {required this.selfClosing});

  /// Tag name as written.
  final String name;

  /// Decoded attribute values.
  final Map<String, String> attributes;

  /// Whether the tag is self-closing (`/>`).
  final bool selfClosing;
}

/// Decodes a numeric character reference (port of `decode_char`).
String decodeChar(int number) => String.fromCharCode(number);

/// Joins a fixture [name] to the fixtures directory (port of
/// `fixture_path`).
String fixturePath(String name) => 'vendor/asciidoctor/test/fixtures/$name';

/// The Ruby test directory (port of `testdir`).
///
/// Canonical absolute path, like Ruby's `ASCIIDOCTOR_TEST_DIR`: include
/// resolution uses it as the jail, which must be absolute in both ports,
/// and jail recovery misfires on `..` segments.
/// Upstream's `test/` directory, whose `fixtures/` are vendored.
String get testdir =>
    Directory('vendor/asciidoctor/test').resolveSymbolicLinksSync();

void main() {
  group('Document', () {
    group('Example document', () {
      test(testOn: 'vm', 'document title', () {
        final doc = exampleDocument('asciidoc_index');
        expect(doc.doctitle(), equals('AsciiDoc Home Page'));
        expect(doc.doctitle(), equals('AsciiDoc Home Page'));
        expect(doc.header, isNotNull);
        expect(doc.header!.contextName, equals('section'));
        expect(doc.header!.sectname, equals('header'));
        expect(doc.blocks.length, equals(14));
        expect(doc.blocks[0].contextName, equals('preamble'));
        expect(doc.blocks[1].contextName, equals('section'));

        // Verify compat-mode is set when atx-style doctitle is used.
        final result = doc.blocks[0].convert();
        assertXpath('//em[text()="Stuart Rackham"]', result, 1);
      });
    });

    group('Default settings', () {
      test('safe mode level set to SECURE by default', () {
        final doc = emptyDocument();
        expect(doc.safe, equals(SafeMode.secure));
      });

      test('safe mode level set using integer', () {
        var doc = emptyDocument(
          const AsciidoctorOptions(safe: SafeMode.server),
        );
        expect(doc.safe, equals(SafeMode.server));

        doc = emptyDocument(const AsciidoctorOptions(safe: 100));
        expect(doc.safe, equals(100));
      });

      test('safe mode attributes are set on document', () {
        final doc = emptyDocument();
        expect(doc.attr('safe-mode-level'), equals('${SafeMode.secure}'));
        expect(doc.attr('safe-mode-name'), equals('secure'));
        expect(doc.hasAttr('safe-mode-secure'), isTrue);
        expect(doc.hasAttr('safe-mode-unsafe'), isFalse);
        expect(doc.hasAttr('safe-mode-safe'), isFalse);
        expect(doc.hasAttr('safe-mode-server'), isFalse);
      });

      test('safe mode level can be set in the constructor', () {
        final doc = Document(
          null,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.safe, equals(SafeMode.safe));
      });

      test('safe mode level cannot be modified', () {
        // `safe` is a final field in Dart, so reassignment is a compile
        // error and there is no runtime behavior to assert (Ruby raises
        // NoMethodError instead).
        final doc = emptyDocument();
        expect(doc.safe, equals(SafeMode.secure));
      });

      test(
        'toc and sectnums should be enabled by default in DocBook backend',
        () {
          final doc = documentFromString(
            'content',
            const AsciidoctorOptions(backend: 'docbook'),
          );
          expect(doc.hasAttr('toc'), isTrue);
          expect(doc.hasAttr('sectnums'), isTrue);
          final result = doc.convert();
          expect(result, contains('<?asciidoc-toc?>'));
          expect(result, contains('<?asciidoc-numbered?>'));
        },
      );

      test('maxdepth attribute should be set on asciidoc-toc and '
          'asciidoc-numbered processing instructions in DocBook backend', () {
        final doc = documentFromString(
          'content',
          const AsciidoctorOptions(
            backend: 'docbook',
            attributes: {'toclevels': '1', 'sectnumlevels': '1'},
          ),
        );
        expect(doc.hasAttr('toc'), isTrue);
        expect(doc.hasAttr('sectnums'), isTrue);
        final result = doc.convert();
        expect(result, contains('<?asciidoc-toc maxdepth="1"?>'));
        expect(result, contains('<?asciidoc-numbered maxdepth="1"?>'));
      });

      test('should be able to disable toc and sectnums in document header '
          'in DocBook backend', () {
        const input = '= Document Title\n:toc!:\n:sectnums!:\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        expect(doc.hasAttr('toc'), isFalse);
        expect(doc.hasAttr('sectnums'), isFalse);
      });

      test('noheader attribute should suppress info element when converting '
          'to DocBook', () {
        const input = '= Document Title\n:noheader:\n\ncontent\n';
        final result = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertXpath('/article', result, 1);
        assertXpath('/article/info', result, 0);
      });

      test('should be able to disable section numbering using numbered '
          'attribute in document header in DocBook backend', () {
        const input = '= Document Title\n:numbered!:\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        expect(doc.hasAttr('sectnums'), isFalse);
      });
    });

    group('Docinfo files', () {
      test('should include docinfo files for html backend', () {
        final sampleInputPath = fixturePath('basic.adoc');

        // NOTE the Ruby test passes the attribute overrides as a string;
        // `convertFile` forwards the '_attr_string_' entry verbatim since
        // `load.dart` already coerces attribute strings.
        (<String, Map<String, int>>{
          'docinfo': {
            'head_script': 1,
            'meta': 0,
            'top_link': 0,
            'footer_script': 1,
            'navbar': 1,
          },
          'docinfo=private': {
            'head_script': 1,
            'meta': 0,
            'top_link': 0,
            'footer_script': 1,
            'navbar': 1,
          },
          'docinfo1': {
            'head_script': 0,
            'meta': 1,
            'top_link': 1,
            'footer_script': 0,
            'navbar': 0,
          },
          'docinfo=shared': {
            'head_script': 0,
            'meta': 1,
            'top_link': 1,
            'footer_script': 0,
            'navbar': 0,
          },
          'docinfo2': {
            'head_script': 1,
            'meta': 1,
            'top_link': 1,
            'footer_script': 1,
            'navbar': 1,
          },
          'docinfo docinfo2': {
            'head_script': 1,
            'meta': 1,
            'top_link': 1,
            'footer_script': 1,
            'navbar': 1,
          },
          'docinfo=private,shared': {
            'head_script': 1,
            'meta': 1,
            'top_link': 1,
            'footer_script': 1,
            'navbar': 1,
          },
          'docinfo=private-head': {
            'head_script': 1,
            'meta': 0,
            'top_link': 0,
            'footer_script': 0,
            'navbar': 0,
          },
          'docinfo=private-header': {
            'head_script': 0,
            'meta': 0,
            'top_link': 0,
            'footer_script': 0,
            'navbar': 1,
          },
          'docinfo=shared-head': {
            'head_script': 0,
            'meta': 1,
            'top_link': 0,
            'footer_script': 0,
            'navbar': 0,
          },
          'docinfo=private-footer': {
            'head_script': 0,
            'meta': 0,
            'top_link': 0,
            'footer_script': 1,
            'navbar': 0,
          },
          'docinfo=shared-footer': {
            'head_script': 0,
            'meta': 0,
            'top_link': 1,
            'footer_script': 0,
            'navbar': 0,
          },
          r'docinfo=private-head\ ,\ shared-footer': {
            'head_script': 1,
            'meta': 0,
            'top_link': 1,
            'footer_script': 0,
            'navbar': 0,
          },
        }).forEach((attrVal, markup) {
          final output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: attributeString('linkcss copycss! $attrVal'),
          );
          expect(output, isNotEmpty);
          assertCss(
            'script[src="modernizr.js"]',
            output,
            markup['head_script']!,
          );
          assertCss('meta[http-equiv="imagetoolbar"]', output, markup['meta']!);
          assertCss('body > a#top', output, markup['top_link']!);
          assertCss('body > script', output, markup['footer_script']!);
          assertCss('body > nav.navbar', output, markup['navbar']!);
          assertCss('body > nav.navbar + #header', output, markup['navbar']!);
        });
      });

      test(
        'should include docinfo header even if noheader attribute is set',
        () {
          final sampleInputPath = fixturePath('basic.adoc');
          final output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo': 'private-header', 'noheader': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body > nav.navbar', output, 1);
          assertCss('body > nav.navbar + #content', output, 1);
        },
      );

      test(
        'should include docinfo footer even if nofooter attribute is set',
        () {
          final sampleInputPath = fixturePath('basic.adoc');
          final output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo1': '', 'nofooter': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body > a#top', output, 1);
        },
      );

      test('should include user docinfo after built-in docinfo', () {
        final sampleInputPath = fixturePath('basic.adoc');
        final attrs = <String, String?>{
          'docinfo': 'shared',
          'source-highlighter': 'highlight.js',
          // The footer script loads highlight.js in the browser.
          'highlightjs-mode': 'client',
          'linkcss': '',
          'copycss': null,
        };
        final output = convertFile(
          sampleInputPath,
          standalone: true,
          safe: SafeMode.safe,
          attributes: attrs,
        );
        assertCss(
          'link[rel=stylesheet] + meta[http-equiv=imagetoolbar]',
          output,
          1,
        );
        assertCss('meta[http-equiv=imagetoolbar] + *', output, 0);
        assertCss('script + a#top', output, 1);
        assertCss('a#top + *', output, 0);
      });

      test(
        'should include docinfo files for html backend with custom docinfodir',
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo': '', 'docinfodir': 'custom-docinfodir'},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 1);
          assertCss('meta[name="robots"]', output, 0);

          output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo1': '', 'docinfodir': 'custom-docinfodir'},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 0);
          assertCss('meta[name="robots"]', output, 1);

          output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo2': '', 'docinfodir': './custom-docinfodir'},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 1);
          assertCss('meta[name="robots"]', output, 1);

          output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {
              'docinfo2': '',
              'docinfodir': 'custom-docinfodir/subfolder',
            },
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 0);
          assertCss('meta[name="robots"]', output, 0);
        },
      );

      test('should include docinfo files in docbook backend', () {
        final sampleInputPath = fixturePath('basic.adoc');

        var output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo': ''},
        );
        expect(output, isNotEmpty);
        assertCss('productname', output, 0);
        assertCss('copyright', output, 1);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo1': ''},
        );
        expect(output, isNotEmpty);
        assertCss('productname', output, 1);
        assertXpath('//xmlns:productname[text()="Asciidoctor™"]', output, 1);
        assertCss('edition', output, 1);
        // Verifies substitutions are performed.
        assertXpath('//xmlns:edition[text()="1.0"]', output, 1);
        assertCss('copyright', output, 0);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo2': ''},
        );
        expect(output, isNotEmpty);
        assertCss('productname', output, 1);
        assertXpath('//xmlns:productname[text()="Asciidoctor™"]', output, 1);
        assertCss('edition', output, 1);
        // Verifies substitutions are performed.
        assertXpath('//xmlns:edition[text()="1.0"]', output, 1);
        assertCss('copyright', output, 1);
      });

      test('should use header docinfo in place of default header', () {
        final output = convertFile(
          fixturePath('sample.adoc'),
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo': 'private-header', 'noheader': ''},
        );
        expect(output, isNotEmpty);
        assertCss('article > info', output, 1);
        assertCss('article > info > title', output, 1);
        assertCss('article > info > revhistory', output, 1);
        assertCss('article > info > revhistory > revision', output, 2);
      });

      test('should include docinfo footer files for html backend', () {
        final sampleInputPath = fixturePath('basic.adoc');

        var output = convertFile(
          sampleInputPath,
          standalone: true,
          safe: SafeMode.server,
          attributes: {'docinfo': ''},
        );
        expect(output, isNotEmpty);
        assertCss('body script', output, 1);
        assertCss('a#top', output, 0);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          safe: SafeMode.server,
          attributes: {'docinfo1': ''},
        );
        expect(output, isNotEmpty);
        assertCss('body script', output, 0);
        assertCss('a#top', output, 1);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          safe: SafeMode.server,
          attributes: {'docinfo2': ''},
        );
        expect(output, isNotEmpty);
        assertCss('body script', output, 1);
        assertCss('a#top', output, 1);
      });

      test('should include docinfo footer files in DocBook backend', () {
        final sampleInputPath = fixturePath('basic.adoc');

        var output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo': ''},
        );
        expect(output, isNotEmpty);
        assertCss('article > revhistory', output, 1);
        // Verifies substitutions are performed.
        assertXpath(
          '/xmlns:article/xmlns:revhistory/xmlns:revision/xmlns:revnumber[text()="1.0"]',
          output,
          1,
        );
        assertCss('glossary', output, 0);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo1': ''},
        );
        expect(output, isNotEmpty);
        assertCss('article > revhistory', output, 0);
        assertCss('glossary[xml|id="_glossary"]', output, 1);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo2': ''},
        );
        expect(output, isNotEmpty);
        assertCss('article > revhistory', output, 1);
        // Verifies substitutions are performed.
        assertXpath(
          '/xmlns:article/xmlns:revhistory/xmlns:revision/xmlns:revnumber[text()="1.0"]',
          output,
          1,
        );
        assertCss('glossary[xml|id="_glossary"]', output, 1);
      });

      test('should force encoding of docinfo files to UTF-8', () {
        // Dart strings are always UTF-8; there are no default external
        // or internal encodings to manipulate.
        final sampleInputPath = fixturePath('basic.adoc');
        final output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo': 'private,shared'},
        );
        expect(output, isNotEmpty);
        assertCss('productname', output, 1);
        expect(output, contains('<productname>Asciidoctor™</productname>'));
        assertCss('edition', output, 1);
        // Verifies substitutions are performed.
        assertXpath('//xmlns:edition[text()="1.0"]', output, 1);
        assertCss('copyright', output, 1);
      });

      test('should not include docinfo files by default', () {
        final sampleInputPath = fixturePath('basic.adoc');

        var output = convertFile(
          sampleInputPath,
          standalone: true,
          safe: SafeMode.server,
        );
        expect(output, isNotEmpty);
        assertCss('script[src="modernizr.js"]', output, 0);
        assertCss('meta[http-equiv="imagetoolbar"]', output, 0);

        output = convertFile(
          sampleInputPath,
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
        );
        expect(output, isNotEmpty);
        assertCss('productname', output, 0);
        assertCss('copyright', output, 0);
      });

      test(
        'should not include docinfo files if safe mode is SECURE or greater',
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            standalone: true,
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="modernizr.js"]', output, 0);
          assertCss('meta[http-equiv="imagetoolbar"]', output, 0);

          output = convertFile(
            sampleInputPath,
            standalone: true,
            backend: 'docbook',
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 0);
          assertCss('copyright', output, 0);
        },
      );

      test('should substitute attributes in docinfo files by default', () {
        final sampleInputPath = fixturePath('subs.adoc');
        usingMemoryLogger((logger) {
          final output = convertFile(
            sampleInputPath,
            standalone: true,
            safe: SafeMode.server,
            attributes: {
              'docinfo': '',
              'bootstrap-version': null,
              'linkcss': '',
              'attribute-missing': 'drop-line',
            },
          );
          expect(output, isNotEmpty);
          assertCss('script', output, 0);
          assertXpath(
            '//meta[@name="copyright"][@content="(C) OpenDevise"]',
            output,
            1,
          );
          expect(
            logger.infos,
            contains(
              'dropping line containing reference to missing attribute: '
              'bootstrap-version',
            ),
          );
        });
      });

      test('should apply explicit substitutions to docinfo files', () {
        final sampleInputPath = fixturePath('subs.adoc');
        final output = convertFile(
          sampleInputPath,
          standalone: true,
          safe: SafeMode.server,
          attributes: {
            'docinfo': '',
            'docinfosubs': 'attributes,replacements',
            'linkcss': '',
          },
        );
        expect(output, isNotEmpty);
        assertCss('script[src="bootstrap.3.2.0.min.js"]', output, 1);
        assertXpath(
          '//meta[@name="copyright"][@content="${decodeChar(169)} OpenDevise"]',
          output,
          1,
        );
      });
    });

    group('MathJax', () {
      test(
        'should add MathJax script to HTML head if stem attribute is set',
        () {
          final output = convertString(
            '',
            const AsciidoctorOptions(attributes: {'stem': ''}),
          );
          expect(output, contains('<script type="text/x-mathjax-config">'));
          expect(output, contains(r'inlineMath: [["\\(", "\\)"]]'));
          expect(output, contains(r'displayMath: [["\\[", "\\]"]]'));
          expect(output, contains(r'delimiters: [["\\$", "\\$"]]'));
        },
      );
    });

    group('Converter', () {
      test(
        'convert methods on built-in converter are registered by default',
        () {
          final doc = emptyDocument();
          expect(doc.attributes['backend'], equals('html5'));
          expect(doc.attributes.containsKey('backend-html5'), isTrue);
          expect(doc.attributes['basebackend'], equals('html'));
          expect(doc.attributes.containsKey('basebackend-html'), isTrue);
          expect(doc.converter, isNotNull);
          // Converter wave: assert the converter type and that it responds
          // to convert_<element> for every builtInElements entry.
          expect(builtInElements, isNotEmpty);
        },
      );

      test('convert methods on built-in converter are registered when '
          'backend is docbook5', () {
        final doc = emptyDocument(
          const AsciidoctorOptions(attributes: {'backend': 'docbook5'}),
        );
        expect(doc.attributes['backend'], equals('docbook5'));
        expect(doc.attributes.containsKey('backend-docbook5'), isTrue);
        expect(doc.attributes['basebackend'], equals('docbook'));
        expect(doc.attributes.containsKey('basebackend-docbook'), isTrue);
        expect(doc.converter, isNotNull);
        // Converter wave: assert the converter type and that it responds
        // to convert_<element> for every builtInElements entry.
      });

      test('should add favicon if favicon attribute is set', () {
        (<String, List<String>>{
          '': ['favicon.ico', 'image/x-icon'],
          '/favicon.ico': ['/favicon.ico', 'image/x-icon'],
          '/img/favicon.png': ['/img/favicon.png', 'image/png'],
        }).forEach((val, hrefAndType) {
          final result = convertString(
            '= Untitled',
            AsciidoctorOptions(attributes: {'favicon': val}),
          );
          assertCss('link[rel="icon"]', result, 1);
          assertCss('link[rel="icon"][href="${hrefAndType[0]}"]', result, 1);
          assertCss('link[rel="icon"][type="${hrefAndType[1]}"]', result, 1);
        });
      });
    });

    group('Structure', () {
      test('document with no doctitle', () {
        final doc = documentFromString('Snorf');
        expect(doc.doctitle(), isNull);
        expect(doc.doctitle(), isNull);
        expect(doc.hasHeader, isFalse);
        expect(doc.header, isNull);
      });

      test('an anchor at the end of the doctitle is the document id', () {
        // Found by the ascii-docs fuzzer: Asciidoctor gives the title's
        // heading the id when the title is shown.
        const input = '= `title` text [[_id]]\n:showtitle:\n\nbody\n';
        final doc = documentFromString(input);
        expect(doc.id, '_id');
        expect(convertStringToEmbedded(input), contains('<h1 id="_id">'));
      });

      test('should enable compat mode for document with legacy doctitle', () {
        const input = 'Document Title\n==============\n\n+content+\n';
        final doc = documentFromString(input);
        expect(doc.hasAttr('compat-mode'), isTrue);
        final result = doc.convert();
        assertXpath('//code[text()="content"]', result, 1);
      });

      test('should not enable compat mode for document with legacy doctitle '
          'if compat mode disable by header', () {
        const input =
            'Document Title\n==============\n:compat-mode!:\n\n+content+\n';
        final doc = documentFromString(input);
        expect(doc.attr('compat-mode'), isNull);
        final result = doc.convert();
        assertXpath('//code[text()="content"]', result, 0);
      });

      test('should not enable compat mode for document with legacy doctitle '
          'if compat mode is locked by API', () {
        const input = 'Document Title\n==============\n\n+content+\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(
            attributes: <String, String?>{'compat-mode': null},
          ),
        );
        expect(doc.attributeLocked('compat-mode'), isTrue);
        expect(doc.attr('compat-mode'), isNull);
        final result = doc.convert();
        assertXpath('//code[text()="content"]', result, 0);
      });

      test('should apply max-width to each top-level container', () {
        const input = '= Document Title\n\ncontentfootnote:[placeholder]\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(attributes: {'max-width': '70em'}),
        );
        assertCss('body[style]', output, 0);
        assertCss('#header[style="max-width: 70em;"]', output, 1);
        assertCss('#content[style="max-width: 70em;"]', output, 1);
        assertCss('#footnotes[style="max-width: 70em;"]', output, 1);
        assertCss('#footer[style="max-width: 70em;"]', output, 1);
      });

      test('title partition API with default separator', () {
        final title = DocumentTitle('Main Title: And More: Subtitle');
        expect(title.main, equals('Main Title: And More'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('title partition API with custom separator', () {
        final title = DocumentTitle(
          'Main Title:: And More:: Subtitle',
          separator: '::',
        );
        expect(title.main, equals('Main Title:: And More'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('document with subtitle', () {
        const input = '= Main Title: *Subtitle*\nAuthor Name\n\ncontent\n';
        final doc = documentFromString(input);
        final title = doc.partitionedTitle(sanitize: true)!;
        expect(title.hasSubtitle, isTrue);
        expect(title.sanitized, isTrue);
        expect(title.main, equals('Main Title'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('document with subtitle and custom separator', () {
        const input =
            '[separator=::]\n= Main Title:: *Subtitle*\nAuthor '
            'Name\n\ncontent\n';
        final doc = documentFromString(input);
        final title = doc.partitionedTitle(sanitize: true)!;
        expect(title.hasSubtitle, isTrue);
        expect(title.sanitized, isTrue);
        expect(title.main, equals('Main Title'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('should not honor custom separator for doctitle if attribute is '
          'locked by API', () {
        const input =
            '[separator=::]\n= Main Title - *Subtitle*\nAuthor '
            'Name\n\ncontent\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(attributes: {'title-separator': ' -'}),
        );
        final title = doc.partitionedTitle(sanitize: true)!;
        expect(title.hasSubtitle, isTrue);
        expect(title.sanitized, isTrue);
        expect(title.main, equals('Main Title'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('document with doctitle defined as attribute entry', () {
        const input =
            ':doctitle: Document Title\n\npreamble\n\n== First Section\n';
        final doc = documentFromString(input);
        expect(doc.doctitle(), equals('Document Title'));
        expect(doc.hasHeader, isTrue);
        expect(doc.header!.title, equals('Document Title'));
        expect(doc.firstSection!.title, equals('Document Title'));
      });

      test('document with doctitle defined as attribute entry followed by '
          'block with title', () {
        const input =
            ':doctitle: Document Title\n\n.Block title\nBlock content\n';
        final doc = documentFromString(input);
        expect(doc.doctitle(), equals('Document Title'));
        expect(doc.hasHeader, isTrue);
        expect(doc.blocks.length, equals(1));
        expect(doc.blocks[0].contextName, equals('paragraph'));
        expect(doc.blocks[0].title, equals('Block title'));
      });

      test('document with title attribute entry overrides doctitle', () {
        const input =
            '= Document Title\n:title: Override\n\n{doctitle}\n\n== '
            'First Section\n';
        final doc = documentFromString(input);
        expect(doc.doctitle(), equals('Override'));
        expect(doc.title, equals('Override'));
        expect(doc.hasHeader, isTrue);
        expect(doc.header!.title, equals('Document Title'));
        expect(doc.firstSection!.title, equals('Document Title'));
        assertXpath(
          '//*[@id="preamble"]//p[text()="Document Title"]',
          doc.convert(),
          1,
        );
      });

      test('document with blank title attribute entry overrides doctitle', () {
        const input =
            '= Document Title\n:title:\n\n{doctitle}\n\n== First Section\n';
        final doc = documentFromString(input);
        expect(doc.doctitle(), equals(''));
        expect(doc.title, equals(''));
        expect(doc.hasHeader, isTrue);
        expect(doc.header!.title, equals('Document Title'));
        expect(doc.firstSection!.title, equals('Document Title'));
        assertXpath(
          '//*[@id="preamble"]//p[text()="Document Title"]',
          doc.convert(),
          1,
        );
      });

      test('document header can reference intrinsic doctitle attribute', () {
        const input =
            '= ACME Documentation\n:intro: Welcome to the '
            '{doctitle}!\n\n{intro}\n';
        final doc = documentFromString(input);
        expect(doc.attr('intro'), equals('Welcome to the ACME Documentation!'));
        assertXpath(
          '//p[text()="Welcome to the ACME Documentation!"]',
          doc.convert(),
          1,
        );
      });

      test('document with title attribute entry overrides doctitle attribute '
          'entry', () {
        const input =
            '= Document Title\n'
            ':snapshot: {doctitle}\n'
            ':doctitle: doctitle\n'
            ':title: Override\n'
            '\n'
            '{snapshot}, {doctitle}\n'
            '\n'
            '== First Section\n';
        final doc = documentFromString(input);
        expect(doc.doctitle(), equals('Override'));
        expect(doc.title, equals('Override'));
        expect(doc.hasHeader, isTrue);
        expect(doc.header!.title, equals('doctitle'));
        expect(doc.firstSection!.title, equals('doctitle'));
        assertXpath(
          '//*[@id="preamble"]//p[text()="Document Title, doctitle"]',
          doc.convert(),
          1,
        );
      });

      test(
        'document with doctitle attribute entry overrides implicit doctitle',
        () {
          const input =
              '= Document Title\n:snapshot: {doctitle}\n:doctitle: Override\n\n'
              '{snapshot}, {doctitle}\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Override'));
          expect(doc.attributes['title'], isNull);
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('Override'));
          expect(doc.firstSection!.title, equals('Override'));
          assertXpath(
            '//*[@id="preamble"]//p[text()="Document Title, Override"]',
            doc.convert(),
            1,
          );
        },
      );

      test('doctitle attribute entry above header overrides implicit '
          'doctitle', () {
        const input =
            ':doctitle: Override\n= Document Title\n\n{doctitle}\n\n== '
            'First Section\n';
        final doc = documentFromString(input);
        expect(doc.doctitle(), equals('Override'));
        expect(doc.attributes['title'], isNull);
        expect(doc.hasHeader, isTrue);
        expect(doc.header!.title, equals('Override'));
        expect(doc.firstSection!.title, equals('Override'));
        assertXpath(
          '//*[@id="preamble"]//p[text()="Override"]',
          doc.convert(),
          1,
        );
      });

      test('should apply header substitutions to value of the doctitle '
          'attribute assigned from implicit doctitle', () {
        const input =
            '= <Foo> {plus} <Bar>\n\nThe name of the game is {doctitle}.\n';
        final doc = documentFromString(input);
        expect(doc.attr('doctitle'), equals('&lt;Foo&gt; &#43; &lt;Bar&gt;'));
        expect(
          doc.blocks[0].content(),
          contains('&lt;Foo&gt; &#43; &lt;Bar&gt;'),
        );
      });

      test('should substitute attribute reference in implicit document title '
          'for attribute defined earlier in header', () {
        usingMemoryLogger((logger) {
          const input =
              ':project-name: ACME\n= {project-name} Docs\n\n{doctitle}\n';
          final doc = documentFromString(
            input,
            const AsciidoctorOptions(attributes: {'attribute-missing': 'warn'}),
          );
          expect(logger.messages, isEmpty);
          expect(doc.attr('doctitle'), equals('ACME Docs'));
          expect(doc.doctitle(), equals('ACME Docs'));
          assertXpath('//p[text()="ACME Docs"]', doc.convert(), 1);
        });
      });

      test('should not warn if implicit document title contains attribute '
          'reference for attribute defined later in header', () {
        usingMemoryLogger((logger) {
          const input =
              '= {project-name} Docs\n:project-name: ACME\n\n{doctitle}\n';
          final doc = documentFromString(
            input,
            const AsciidoctorOptions(attributes: {'attribute-missing': 'warn'}),
          );
          expect(logger.messages, isEmpty);
          expect(doc.attr('doctitle'), equals('{project-name} Docs'));
          expect(doc.doctitle(), equals('ACME Docs'));
          assertXpath('//p[text()="{project-name} Docs"]', doc.convert(), 1);
        });
      });

      test('should recognize document title when preceded by blank lines', () {
        const input = '\n= Title\n\npreamble\n\n== Section 1\n\ntext\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        assertCss('#header h1', output, 1);
        assertCss('#content h1', output, 0);
      });

      test('should recognize document title when preceded by blank lines '
          'introduced by a preprocessor conditional', () {
        const input =
            'ifdef::sectids[]\n\n:foo: bar\nendif::[]\n= '
            'Title\n\npreamble\n\n== Section 1\n\ntext\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        assertCss('#header h1', output, 1);
        assertCss('#content h1', output, 0);
      });

      test('should recognize document title when preceded by blank lines '
          'after an attribute entry', () {
        const input =
            ':doctype: book\n\n= Title\n\npreamble\n\n== Section 1\n\ntext\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        assertCss('#header h1', output, 1);
        assertCss('#content h1', output, 0);
      });

      test(
        testOn: 'vm',
        'should recognize document title in include file when preceded by '
        'blank lines',
        () {
          const input =
              'include::fixtures/include-with-leading-blank-line.adoc[]\n';
          final output = convertString(
            input,
            AsciidoctorOptions(
              safe: SafeMode.safe,
              attributes: {'docdir': testdir},
            ),
          );
          assertXpath('//h1[text()="Document Title"]', output, 1);
          assertCss('#toc', output, 1);
        },
      );

      test(
        testOn: 'vm',
        'should include specified lines even when leading lines are '
        'skipped',
        () {
          const input =
              'include::fixtures/include-with-leading-blank-line.adoc[lines=6]\n';
          final output = convertString(
            input,
            AsciidoctorOptions(
              safe: SafeMode.safe,
              attributes: {'docdir': testdir},
            ),
          );
          assertXpath('//h2[text()="Section"]', output, 1);
        },
      );

      test('document with multiline attribute entry but only one line should '
          'not crash', () {
        // Port of Asciidoctor::LINE_CONTINUATION (' \\').
        const input = r':foo: bar \';
        final doc = documentFromString(input);
        expect(doc.attributes['foo'], equals('bar'));
      });

      test('should sanitize contents of HTML title element', () {
        const input =
            '= *Document* image:logo.png[] _Title_ '
            'image:another-logo.png[another logo]\n\ncontent\n';
        final output = convertString(input);
        assertXpath('/html/head/title[text()="Document Title"]', output, 1);
        final nodes = xmlnodesAtXpath('//*[@id="header"]/h1', output);
        expect(nodes.length, equals(1));
        expect(
          output,
          contains(
            '<h1><strong>Document</strong> <span class="image"><img src="logo.png" alt="logo"></span> '
            '<em>Title</em> <span class="image"><img src="another-logo.png" alt="another logo"></span></h1>',
          ),
        );
      });

      test('should not choke on empty source', () {
        final doc = Document('');
        expect(doc.blocks, isEmpty);
        expect(doc.doctitle(), isNull);
        expect(doc.hasHeader, isFalse);
        expect(doc.header, isNull);
      });

      test('should not choke on nil source', () {
        final doc = Document();
        expect(doc.blocks, isEmpty);
        expect(doc.doctitle(), isNull);
        expect(doc.hasHeader, isFalse);
        expect(doc.header, isNull);
      });

      test('with metadata', () {
        const input =
            '= AsciiDoc\n'
            'Stuart Rackham <founder@asciidoc.org>\n'
            'v8.6.8, 2012-07-12: See changelog.\n'
            ':description: AsciiDoc user guide\n'
            ':keywords: asciidoc,documentation\n'
            ':copyright: Stuart Rackham\n'
            '\n'
            '== Version 8.6.8\n'
            '\n'
            'more info...\n';
        final output = convertString(input);
        assertXpath(
          '//meta[@name="author"][@content="Stuart Rackham"]',
          output,
          1,
        );
        assertXpath(
          '//meta[@name="description"][@content="AsciiDoc user guide"]',
          output,
          1,
        );
        assertXpath(
          '//meta[@name="keywords"][@content="asciidoc,documentation"]',
          output,
          1,
        );
        assertXpath(
          '//meta[@name="copyright"][@content="Stuart Rackham"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="author"][text()="Stuart Rackham"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="email"]/a[@href="mailto:founder@asciidoc.org"][text()="founder@asciidoc.org"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="revnumber"][text()="version 8.6.8,"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="revdate"][text()="2012-07-12"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="revremark"][text()="See changelog."]',
          output,
          1,
        );
      });

      test('should parse revision line if date is empty', () {
        const input =
            '= Document Title\nAuthor Name\nv1.0.0,:remark\n\ncontent\n';
        final doc = documentFromString(input);
        expect(doc.attributes['revnumber'], equals('1.0.0'));
        expect(doc.attributes['revdate'], isNull);
        expect(doc.attributes['revremark'], equals('remark'));
      });

      test('should include revision history in DocBook output if revdate and '
          'revnumber is set', () {
        const input =
            '= Document Title\nAuthor Name\n:revdate: '
            '2011-11-11\n:revnumber: 1.0\n\ncontent\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertCss('revhistory', output, 1);
        assertCss('revhistory > revision', output, 1);
        assertCss('revhistory > revision > date', output, 1);
        assertCss('revhistory > revision > revnumber', output, 1);
      });

      test('should include revision history in DocBook output if revdate and '
          'revremark is set', () {
        const input =
            '= Document Title\nAuthor Name\n:revdate: '
            '2011-11-11\n:revremark: features!\n\ncontent\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertCss('revhistory', output, 1);
        assertCss('revhistory > revision', output, 1);
        assertCss('revhistory > revision > date', output, 1);
        assertCss('revhistory > revision > revremark', output, 1);
      });

      test('should not include revision history in DocBook output if revdate '
          'is not set', () {
        const input =
            '= Document Title\nAuthor Name\n:revnumber: 1.0\n\ncontent\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertCss('revhistory', output, 0);
      });

      test('with metadata to DocBook 5', () {
        const input =
            '= AsciiDoc\nStuart Rackham <founder@asciidoc.org>\n\n== '
            'Version 8.6.8\n\nmore info...\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook5'),
        );
        assertXpath('/article/info', output, 1);
        assertXpath('/article/info/title[text()="AsciiDoc"]', output, 1);
        assertXpath('/article/info/author/personname', output, 1);
        assertXpath(
          '/article/info/author/personname/firstname[text()="Stuart"]',
          output,
          1,
        );
        assertXpath(
          '/article/info/author/personname/surname[text()="Rackham"]',
          output,
          1,
        );
        assertXpath(
          '/article/info/author/email[text()="founder@asciidoc.org"]',
          output,
          1,
        );
        assertCss('article:root:not([xml|id])', output, 1);
        assertCss('article:root[xml|lang="en"]', output, 1);
      });

      test('with document ID to Docbook 5', () {
        const input = '[[document-id]]\n= Document Title\n\nmore info...\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertCss('article:root[xml|id="document-id"]', output, 1);
      });

      test('with author defined using attribute entry to DocBook', () {
        const input =
            '= Document Title\n:author: Doc Writer\n:email: '
            'thedoctor@asciidoc.org\n\ncontent\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertXpath('/article/info/author', output, 1);
        assertXpath(
          '/article/info/author/personname/firstname[text()="Doc"]',
          output,
          1,
        );
        assertXpath(
          '/article/info/author/personname/surname[text()="Writer"]',
          output,
          1,
        );
        assertXpath(
          '/article/info/author/email[text()="thedoctor@asciidoc.org"]',
          output,
          1,
        );
        assertXpath('/article/info/authorinitials[text()="DW"]', output, 1);
      });

      test('should substitute replacements in author names in HTML output', () {
        const input =
            "= Document Title\nStephen O'Grady "
            '<founder@redmonk.com>\n\ncontent\n';
        final output = convertString(input);
        assertXpath(
          '//meta[@name="author"][@content="Stephen O${decodeChar(8217)}Grady"]',
          output,
          1,
        );
        assertXpath(
          '//span[@id="author"][text()="Stephen O${decodeChar(8217)}Grady"]',
          output,
          1,
        );
      });

      test('should substitute replacements in author names in DocBook '
          'output', () {
        const input =
            "= Document Title\nStephen O'Grady "
            '<founder@redmonk.com>\n\ncontent\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertXpath('//author', output, 1);
        assertXpath(
          '//author/personname/surname[text()="O${decodeChar(8217)}Grady"]',
          output,
          1,
        );
      });

      test('should sanitize content of HTML meta authors tag', () {
        const input =
            '= Document Title\n:author: pass:n[http://example.org/community/team.html[Ze *Product* team]]\n\ncontent\n';
        final output = convertString(input);
        assertXpath(
          '//meta[@name="author"][@content="Ze Product team"]',
          output,
          1,
        );
      });

      test('should not double escape ampersand in author attribute', () {
        const input = '= Document Title\nR&D Lab\n\n{author}\n';
        final output = convertString(input);
        expect(output, contains('R&amp;D Lab'));
      });

      test('should include multiple authors in HTML output', () {
        const input =
            '= Document Title\nDoc Writer <thedoctor@asciidoc.org>; '
            'Junior Writer <junior@asciidoctor.org>\n\ncontent\n';
        final output = convertString(input);
        assertXpath('//span[@id="author"]', output, 1);
        assertXpath('//span[@id="author"][text()="Doc Writer"]', output, 1);
        assertXpath('//span[@id="email"]', output, 1);
        assertXpath('//span[@id="email"]/a', output, 1);
        assertXpath(
          '//span[@id="email"]/a[@href="mailto:thedoctor@asciidoc.org"][text()="thedoctor@asciidoc.org"]',
          output,
          1,
        );
        assertXpath('//span[@id="author2"]', output, 1);
        assertXpath('//span[@id="author2"][text()="Junior Writer"]', output, 1);
        assertXpath('//span[@id="email2"]', output, 1);
        assertXpath('//span[@id="email2"]/a', output, 1);
        assertXpath(
          '//span[@id="email2"]/a[@href="mailto:junior@asciidoctor.org"][text()="junior@asciidoctor.org"]',
          output,
          1,
        );
      });

      test('should create authorgroup in DocBook when multiple authors', () {
        const input =
            '= Document Title\nDoc Writer <thedoctor@asciidoc.org>; '
            'Junior Writer <junior@asciidoctor.org>\n\ncontent\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertXpath('/article/info/author', output, 0);
        assertXpath('/article/info/authorgroup', output, 1);
        assertXpath('/article/info/authorgroup/author', output, 2);
        assertXpath(
          '(/article/info/authorgroup/author)[1]/personname/firstname[text()="Doc"]',
          output,
          1,
        );
        assertXpath(
          '(/article/info/authorgroup/author)[2]/personname/firstname[text()="Junior"]',
          output,
          1,
        );
      });

      test('should process author defined by attribute when implicit doctitle '
          'is absent', () {
        const input =
            ':author: Doc Writer\n\n{lastname}, {firstname} '
            '({authorinitials})\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(standalone: false),
        );
        expect(doc.attr('author'), equals('Doc Writer'));
        expect(doc.attr('author_1'), isNull);
        expect(doc.attr('lastname'), equals('Writer'));
        expect(doc.attr('firstname'), equals('Doc'));
        expect(doc.attr('authorinitials'), equals('DW'));
        expect(doc.attr('authorcount'), equals('1'));
        final output = doc.convert();
        assertXpath('//p[text()="Writer, Doc (DW)"]', output, 1);
      });

      test('should process author and authorinitials defined by attribute '
          'when implicit doctitle is absent', () {
        const input =
            ':authorinitials: DOC\n:author: Doc Writer\n\n{lastname}, '
            '{firstname} ({authorinitials})\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(standalone: false),
        );
        expect(doc.attr('author'), equals('Doc Writer'));
        expect(doc.attr('authorinitials'), equals('DOC'));
        expect(doc.attr('authorcount'), equals('1'));
        final output = doc.convert();
        assertXpath('//p[text()="Writer, Doc (DOC)"]', output, 1);
      });

      test('should process authors defined by attribute when implicit '
          'doctitle is absent', () {
        const input =
            ':authors: Doc Writer; Other Author\n\n{lastname}, '
            '{firstname} ({authorinitials})\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(standalone: false),
        );
        expect(doc.attr('author'), equals('Doc Writer'));
        expect(doc.attr('authors'), equals('Doc Writer, Other Author'));
        expect(doc.attr('author_1'), equals('Doc Writer'));
        expect(doc.attr('lastname'), equals('Writer'));
        expect(doc.attr('lastname_1'), equals('Writer'));
        expect(doc.attr('firstname'), equals('Doc'));
        expect(doc.attr('firstname_1'), equals('Doc'));
        expect(doc.attr('authorinitials'), equals('DW'));
        expect(doc.attr('authorinitials_1'), equals('DW'));
        expect(doc.attr('author_2'), equals('Other Author'));
        expect(doc.attr('authorinitials_2'), equals('OA'));
        expect(doc.attr('authorcount'), equals('2'));
        final output = doc.convert();
        assertXpath('//p[text()="Writer, Doc (DW)"]', output, 1);
      });

      test('should process authors and authorinitials defined by attribute '
          'when implicit doctitle is absent', () {
        const input =
            ':authorinitials: DOC\n:authors: Doc Writer; Other Author\n'
            '\n{lastname}, {firstname} ({authorinitials})\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(standalone: false),
        );
        expect(doc.attr('author'), equals('Doc Writer'));
        expect(doc.attr('author_1'), equals('Doc Writer'));
        // The assigned initials win (bugfix #4209; upstream's FIXME).
        expect(doc.attr('authorinitials'), equals('DOC'));
        expect(doc.attr('author_2'), equals('Other Author'));
        expect(doc.attr('authorcount'), equals('2'));
        final output = doc.convert();
        assertXpath('//p[text()="Writer, Doc (DOC)"]', output, 1);
      });

      test('should set authorcount to 0 if document has no header', () {
        final doc = documentFromString('content');
        expect(doc.attr('authorcount'), equals('0'));
      });

      test('should set authorcount to 0 if author not set by attribute and '
          'implicit doctitle is missing', () {
        const input = ':idprefix:\n\n== Section Title\n\ncontent\n';
        final doc = documentFromString(input);
        expect(doc.attr('authorcount'), equals('0'));
      });

      test('should set authorcount to 0 if author not set by attribute and '
          'document starts with level-0 section with style', () {
        const input =
            ':doctype: book\n\n[preface]\n= Preface\n\ncontent\n\n= '
            'Part\n\n== Chapter\n\ncontent\n';
        final doc = documentFromString(input);
        expect(doc.attr('authorcount'), equals('0'));
      });

      test('with author defined by indexed attribute name', () {
        const input = '= Document Title\n:author_1: Doc Writer\n\n{author}\n';
        final doc = documentFromString(input);
        expect(doc.attr('author'), equals('Doc Writer'));
        expect(doc.attr('author_1'), equals('Doc Writer'));
      });

      test('with authors defined using attribute entry to DocBook', () {
        const input =
            '= Document Title\n'
            ':authors: Doc Writer; Junior Writer\n'
            ':email_1: thedoctor@asciidoc.org\n'
            ':email_2: junior@asciidoc.org\n'
            '\n'
            'content\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook'),
        );
        assertXpath('/article/info/author', output, 0);
        assertXpath('/article/info/authorgroup', output, 1);
        assertXpath('/article/info/authorgroup/author', output, 2);
        assertXpath(
          '(/article/info/authorgroup/author)[1]/personname/firstname[text()="Doc"]',
          output,
          1,
        );
        assertXpath(
          '(/article/info/authorgroup/author)[1]/email[text()="thedoctor@asciidoc.org"]',
          output,
          1,
        );
        assertXpath(
          '(/article/info/authorgroup/author)[2]/personname/firstname[text()="Junior"]',
          output,
          1,
        );
        assertXpath(
          '(/article/info/authorgroup/author)[2]/email[text()="junior@asciidoc.org"]',
          output,
          1,
        );
      });

      test('should populate copyright element in DocBook output if copyright '
          'attribute is defined', () {
        const input =
            '= Jet Bike\n:copyright: ACME, Inc.\n\nEssential for '
            'catching road runners.\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook5'),
        );
        // ptome: a legal notice, since DocBook 5.0 wants a year in a
        // copyright (benchmark/PARITY.md).
        assertXpath('/article/info/copyright', output, 0);
        assertXpath(
          '/article/info/legalnotice/simpara[text()="ACME, Inc."]',
          output,
          1,
        );
      });

      test('should populate copyright element in DocBook output if copyright '
          'attribute is defined with year', () {
        const input =
            '= Jet Bike\n:copyright: ACME, Inc. 1956\n\nEssential for '
            'catching road runners.\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook5'),
        );
        assertXpath('/article/info/copyright', output, 1);
        assertXpath(
          '/article/info/copyright/holder[text()="ACME, Inc."]',
          output,
          1,
        );
        assertXpath('/article/info/copyright/year', output, 1);
        assertXpath('/article/info/copyright/year[text()="1956"]', output, 1);
      });

      test('should populate copyright element in DocBook output if copyright '
          'attribute is defined with year range', () {
        const input =
            '= Jet Bike\n:copyright: ACME, Inc. 1956-2018\n\nEssential '
            'for catching road runners.\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook5'),
        );
        assertXpath('/article/info/copyright', output, 1);
        assertXpath(
          '/article/info/copyright/holder[text()="ACME, Inc."]',
          output,
          1,
        );
        assertXpath('/article/info/copyright/year', output, 1);
        assertXpath(
          '/article/info/copyright/year[text()="1956-2018"]',
          output,
          1,
        );
      });

      test('with header footer', () {
        final doc = documentFromString('= Title\n\nparagraph');
        expect(doc.hasAttr('embedded'), isFalse);
        final result = doc.convert();
        assertXpath('/html', result, 1);
        assertXpath('//*[@id="header"]', result, 1);
        assertXpath('//*[@id="header"]/h1', result, 1);
        assertXpath('//*[@id="footer"]', result, 1);
        assertXpath('//*[@id="content"]', result, 1);
      });

      test('does not output footer if nofooter is set', () {
        const input = ':nofooter:\n\ncontent\n';
        final result = convertString(input);
        assertXpath('//*[@id="footer"]', result, 0);
      });

      test('can disable last updated in footer', () {
        final doc = documentFromString(
          '= Document Title\n\npreamble',
          const AsciidoctorOptions(attributes: {'last-update-label!': ''}),
        );
        final result = doc.convert();
        assertXpath('//*[@id="footer-text"]', result, 1);
        assertXpath(
          '//*[@id="footer-text"][normalize-space(text())=""]',
          result,
          1,
        );
      });

      test('should create embedded document if standalone option passed to '
          'constructor is false', () {
        final doc = Document(
          '= Document Title\n\ncontent',
          const AsciidoctorOptions(standalone: false),
        ).parse();
        expect(doc.hasAttr('embedded'), isTrue);
        final result = doc.convert();
        assertXpath('/html', result, 0);
        assertXpath('/h1', result, 0);
        assertXpath('/*[@id="header"]', result, 0);
        assertXpath('/*[@id="footer"]', result, 0);
        assertXpath('/*[@class="paragraph"]', result, 1);
      });

      test('should create embedded document if standalone option passed to '
          'convert method is false', () {
        final doc = Document(
          '= Document Title\n\ncontent',
          const AsciidoctorOptions(standalone: true),
        ).parse();
        expect(doc.hasAttr('embedded'), isFalse);
        final result = doc.convert(standalone: false);
        assertXpath('/html', result, 0);
        assertXpath('/h1', result, 1);
        assertXpath('/*[@id="header"]', result, 0);
        assertXpath('/*[@id="footer"]', result, 0);
        assertXpath('/*[@class="paragraph"]', result, 1);
      });

      test('should create embedded document if deprecated header_footer '
          'option is false', () {
        final doc = Document(
          '= Document Title\n\ncontent',
          const AsciidoctorOptions(standalone: false),
        ).parse();
        expect(doc.hasAttr('embedded'), isTrue);
        final result = doc.convert();
        assertXpath('/html', result, 0);
        assertXpath('/h1', result, 0);
        assertXpath('/*[@id="header"]', result, 0);
        assertXpath('/*[@id="footer"]', result, 0);
        assertXpath('/*[@class="paragraph"]', result, 1);
      });

      test('should create embedded document if header_footer option passed '
          'to convert method is false', () {
        final doc = Document(
          '= Document Title\n\ncontent',
          const AsciidoctorOptions(standalone: true),
        ).parse();
        expect(doc.hasAttr('embedded'), isFalse);
        final result = doc.convert(standalone: false);
        assertXpath('/html', result, 0);
        assertXpath('/h1', result, 1);
        assertXpath('/*[@id="header"]', result, 0);
        assertXpath('/*[@id="footer"]', result, 0);
        assertXpath('/*[@class="paragraph"]', result, 1);
      });

      test(
        'enable title in embedded document by unassigning notitle attribute',
        () {
          const input = '= Document Title\n\ncontent\n';
          final result = convertStringToEmbedded(
            input,
            const AsciidoctorOptions(attributes: {'notitle!': ''}),
          );
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 1);
          assertXpath('/*[@id="header"]', result, 0);
          assertXpath('/*[@id="footer"]', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
          assertXpath('(/*)[1]/self::h1', result, 1);
          assertXpath('(/*)[2]/self::*[@class="paragraph"]', result, 1);
        },
      );

      test('should be able to enable doctitle for embedded document', () {
        final cases = <(Map<String, String?>, List<String>?)>[
          ({'notitle': null}, null),
          ({'notitle': null}, [':!showtitle:']),
          ({'notitle!@': ''}, null),
          ({'notitle': '@'}, [':!notitle:']),
          ({'notitle': '@'}, [':showtitle:']),
          ({'showtitle': ''}, [':notitle:']),
          ({'showtitle': '@'}, null),
          ({'showtitle!@': ''}, [':!notitle:']),
          (<String, String?>{}, [':!notitle:']),
          (<String, String?>{}, [':notitle:', ':showtitle:']),
          (<String, String?>{}, [':showtitle:']),
          (<String, String?>{}, [':!showtitle:', ':!notitle:']),
        ];
        for (final entry in cases) {
          final (apiAttrs, attrEntries) = entry;
          final input =
              '= Document '
              'Title${attrEntries == null ? '' : '\n${attrEntries.join('\n')}'}'
              '\n\nifdef::showtitle[showtitle: set]\n'
              'ifndef::showtitle[showtitle: not set]\n'
              'ifdef::notitle[notitle: set]\n'
              'ifndef::notitle[notitle: not set]\n';
          final result = convertStringToEmbedded(
            input,
            AsciidoctorOptions(attributes: apiAttrs),
          );
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 1);
          assertXpath('(/*)[1]/self::h1', result, 1);
          assertXpath('(/*)[2]/self::*[@class="paragraph"]', result, 1);
          // NOTE showtitle may not match notitle if never used
          expect(result, contains('notitle: not set'));
        }
      });

      test('should be able to explicitly disable doctitle for embedded '
          'document', () {
        final cases = <(Map<String, String?>, List<String>?)>[
          ({'notitle': ''}, null),
          ({'notitle': '@'}, null),
          ({'notitle': '@'}, [':!showtitle:']),
          ({'showtitle': null}, null),
          ({'showtitle!@': ''}, null),
          ({'showtitle': '@'}, [':notitle:']),
          (<String, String?>{}, [':notitle:']),
          (<String, String?>{}, [':!showtitle:']),
          (<String, String?>{}, [':!showtitle:', ':notitle:']),
        ];
        for (final entry in cases) {
          final (apiAttrs, attrEntries) = entry;
          final input =
              '= Document '
              'Title${attrEntries == null ? '' : '\n${attrEntries.join('\n')}'}'
              '\n\nifdef::showtitle[showtitle: set]\n'
              'ifndef::showtitle[showtitle: not set]\n'
              'ifdef::notitle[notitle: set]\n'
              'ifndef::notitle[notitle: not set]\n';
          final result = convertStringToEmbedded(
            input,
            AsciidoctorOptions(attributes: apiAttrs),
          );
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
          // NOTE showtitle may not match notitle if never used
          expect(result, contains('notitle: set'));
        }
      });

      test('parse header only', () {
        const input = '= Document Title\nAuthor Name\n:foo: bar\n\npreamble\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(parseHeaderOnly: true),
        );
        expect(doc.doctitle(), equals('Document Title'));
        expect(doc.author, equals('Author Name'));
        expect(doc.attributes['foo'], equals('bar'));
        // There would be at least 1 block had it parsed beyond the header.
        expect(doc.blocks.length, equals(0));
      });

      test('should parse header only when docytpe is manpage', () {
        const input =
            '= cmd(1)\nAuthor Name\n:doctype: manpage\n\n== '
            'Name\n\ncmd - does stuff\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(parseHeaderOnly: true),
        );
        expect(doc.doctitle(), equals('cmd(1)'));
        expect(doc.author, equals('Author Name'));
        expect(doc.attributes['mantitle'], equals('cmd'));
        expect(doc.attributes['manvolnum'], equals('1'));
        expect(doc.attributes['manname'], isNull);
        expect(doc.attributes['manpurpose'], isNull);
        expect(doc.blocks.length, equals(0));
      });

      test('should not warn when parsing header only when docytpe is manpage '
          'and body is empty', () {
        const input = '= cmd(1)\nAuthor Name\n:doctype: manpage\n';
        usingMemoryLogger((logger) {
          final doc = documentFromString(
            input,
            const AsciidoctorOptions(parseHeaderOnly: true),
          );
          expect(logger.messages, isEmpty);
          expect(doc.doctitle(), equals('cmd(1)'));
          expect(doc.author, equals('Author Name'));
          expect(doc.attributes['mantitle'], equals('cmd'));
          expect(doc.attributes['manvolnum'], equals('1'));
          expect(doc.attributes['manname'], isNull);
          expect(doc.attributes['manpurpose'], isNull);
          expect(doc.blocks.length, equals(0));
        });
      });

      test('outputs footnotes in footer', () {
        const input =
            'A footnote footnote:[An example footnote.];\n'
            'a second footnote with a reference ID footnote:note2[Second '
            'footnote.];\n'
            'and finally a reference to the second footnote '
            'footnote:note2[].\n';
        final output = convertString(input);
        assertCss('#footnotes', output, 1);
        assertCss('#footnotes .footnote', output, 2);
        assertCss('#footnotes .footnote#_footnotedef_1', output, 1);
        assertXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_1"]/a[@href="#_footnoteref_1"][text()="1"]',
          output,
          1,
        );
        final text1 = xmlnodesAtXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_1"]/text()',
          output,
        );
        expect(text1.text.trim(), equals('. An example footnote.'));
        assertCss('#footnotes .footnote#_footnotedef_2', output, 1);
        assertXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_2"]/a[@href="#_footnoteref_2"][text()="2"]',
          output,
          1,
        );
        final text2 = xmlnodesAtXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_2"]/text()',
          output,
        );
        expect(text2.text.trim(), equals('. Second footnote.'));
      });

      test('outputs footnotes block in embedded document by default', () {
        const input =
            'Text that has supporting information{empty}footnote:[An '
            'example footnote.].';
        final output = convertStringToEmbedded(input);
        assertCss('#footnotes', output, 1);
        assertCss('#footnotes .footnote', output, 1);
        assertCss('#footnotes .footnote#_footnotedef_1', output, 1);
        assertXpath(
          '/div[@id="footnotes"]/div[@id="_footnotedef_1"]/a[@href="#_footnoteref_1"][text()="1"]',
          output,
          1,
        );
        final text = xmlnodesAtXpath(
          '/div[@id="footnotes"]/div[@id="_footnotedef_1"]/text()',
          output,
        );
        expect(text.text.trim(), equals('. An example footnote.'));
      });

      test('does not output footnotes block in embedded document if '
          'nofootnotes attribute is set', () {
        const input =
            'Text that has supporting information{empty}footnote:[An '
            'example footnote.].';
        final output = convertStringToEmbedded(
          input,
          const AsciidoctorOptions(attributes: {'nofootnotes': ''}),
        );
        assertCss('#footnotes', output, 0);
      });
    });

    group('Catalog', () {
      test('should expose references and footnotes via the catalog', () {
        const input =
            '= Document Title\n\n== Section A\n\nContent\n\n== Section '
            'B\n\nContent.footnote:[commentary]\n';
        final doc = documentFromString(input);
        expect(
          doc.catalog.refs.keys,
          containsAll(['_section_a', '_section_b']),
        );
        expect(doc.catalog.footnotes, isEmpty);
        doc.convert();
        expect(doc.catalog.footnotes.single.text, equals('commentary'));
        expect(doc.catalog.links, isEmpty);
        expect(doc.catalog.images, isEmpty);
        expect(doc.catalog.includes, isEmpty);
        expect(doc.resolveId('Section A'), equals('_section_a'));
      });

      test('should register a reference with reftext', () {
        final doc = emptyDocument();
        final ref = Inline(
          doc,
          InlineContext.anchor,
          text: 'Foo Bar',
          type: 'ref',
          target: 'foobar',
        );
        expect(doc.registerRef('foobar', ref), isTrue);
        expect(doc.catalog.refs['foobar'], same(ref));
        expect(ref.reftext, equals('Foo Bar'));
        expect(doc.resolveId('Foo Bar'), equals('foobar'));
      });

      test('should not replace an existing entry for ID in the refs table', () {
        final doc = emptyDocument();
        final ref = Inline(
          doc,
          InlineContext.anchor,
          text: '[tigers]',
          type: 'ref',
          target: 'tigers',
        );
        expect(doc.registerRef('tigers', ref), isTrue);
        expect(
          doc.registerRef(
            'tigers',
            Inline(doc, InlineContext.anchor, type: 'ref'),
          ),
          isFalse,
        );
        expect(doc.catalog.refs['tigers'], same(ref));
      });

      test('should record imagesdir when image is registered with catalog', () {
        final doc = emptyDocument(
          const AsciidoctorOptions(
            attributes: {'imagesdir': 'img'},
            catalogAssets: true,
          ),
        )..registerImage('diagram.svg');
        final images = doc.catalog.images;
        expect(images.length, equals(1));
        expect(images[0].target, equals('diagram.svg'));
        expect(images[0].imagesdir, equals('img'));
      });

      test('should catalog assets inside nested document', () {
        const input =
            'image::outer.png[]\n\n|===\na|\nimage::inner.png[]\n|===\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(catalogAssets: true),
        );
        final images = doc.catalog.images;
        expect(images, isNotEmpty);
        expect(images.length, equals(2));
        expect(
          images.map((image) => image.target).toList(),
          orderedEquals(['outer.png', 'inner.png']),
        );
      });
    });

    group('Backends and Doctypes', () {
      test('html5 backend doctype article', () {
        final result = convertString(
          '= Title\n\nparagraph',
          const AsciidoctorOptions(attributes: {'backend': 'html5'}),
        );
        assertXpath('/html', result, 1);
        assertXpath('/html/body[@class="article"]', result, 1);
        assertXpath('/html//*[@id="header"]/h1[text()="Title"]', result, 1);
        assertXpath(
          '/html//*[@id="content"]//p[text()="paragraph"]',
          result,
          1,
        );
      });

      test('html5 backend doctype book', () {
        final result = convertString(
          '= Title\n\nparagraph',
          const AsciidoctorOptions(
            attributes: {'backend': 'html5', 'doctype': 'book'},
          ),
        );
        assertXpath('/html', result, 1);
        assertXpath('/html/body[@class="book"]', result, 1);
        assertXpath('/html//*[@id="header"]/h1[text()="Title"]', result, 1);
        assertXpath(
          '/html//*[@id="content"]//p[text()="paragraph"]',
          result,
          1,
        );
      });

      test('xhtml5 backend should map to html5 and set htmlsyntax to xml', () {
        const input = 'content';
        final doc = Document(
          input,
          const AsciidoctorOptions(backend: 'xhtml5'),
        );
        expect(doc.backend, equals('html5'));
        expect(doc.attr('htmlsyntax'), equals('xml'));
      });

      test('xhtml backend should map to html5 and set htmlsyntax to xml', () {
        const input = 'content';
        final doc = Document(input, const AsciidoctorOptions(backend: 'xhtml'));
        expect(doc.backend, equals('html5'));
        expect(doc.attr('htmlsyntax'), equals('xml'));
      });

      test('honor htmlsyntax attribute passed via API if backend is html', () {
        const input = '---';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(
            safe: SafeMode.safe,
            attributes: {'htmlsyntax': 'xml'},
          ),
        );
        expect(doc.backend, equals('html5'));
        expect(doc.attr('htmlsyntax'), equals('xml'));
        final result = doc.convert(standalone: false);
        expect(result, equals('<hr/>'));
      });

      test('honor htmlsyntax attribute in document header if followed by '
          'backend attribute', () {
        const input = ':htmlsyntax: xml\n:backend: html5\n\n---\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.backend, equals('html5'));
        expect(doc.attr('htmlsyntax'), equals('xml'));
        final result = doc.convert(standalone: false);
        expect(result, equals('<hr/>'));
      });

      test('does not honor htmlsyntax attribute in document header if not '
          'followed by backend attribute', () {
        const input = ':backend: html5\n:htmlsyntax: xml\n\n---\n';
        final result = convertStringToEmbedded(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(result, equals('<hr>'));
      });

      test('should close all short tags when htmlsyntax is xml', () {
        const input =
            '= Document Title\n'
            'Author Name\n'
            'v1.0, 2001-01-01\n'
            ':icons:\n'
            ':favicon:\n'
            '\n'
            'image:tiger.png[]\n'
            '\n'
            'image::tiger.png[]\n'
            '\n'
            '* [x] one\n'
            '* [ ] two\n'
            '\n'
            '|===\n'
            '|A |B\n'
            '|===\n'
            '\n'
            '[horizontal, labelwidth="25%", itemwidth="75%"]\n'
            'term:: description\n'
            '\n'
            'NOTE: note\n'
            '\n'
            '[quote,Author,Source]\n'
            '____\n'
            'Quote me.\n'
            '____\n'
            '\n'
            '[verse,Author,Source]\n'
            '____\n'
            'A tall tale.\n'
            '____\n'
            '\n'
            '[options="autoplay,loop"]\n'
            'video::screencast.ogg[]\n'
            '\n'
            'video::12345[vimeo]\n'
            '\n'
            '[options="autoplay,loop"]\n'
            'audio::podcast.ogg[]\n'
            '\n'
            'one +\n'
            'two\n'
            '\n'
            "'''\n";
        final result = convertString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe, backend: 'xhtml'),
        );
        assertWellFormedXml(result);
      });

      test('xhtml backend should emit elements in proper namespace', () {
        const input = 'content';
        final result = convertString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe, backend: 'xhtml'),
        );
        assertXpath(
          '//*[not(namespace-uri()="http://www.w3.org/1999/xhtml")]',
          result,
          0,
        );
      });

      test('should parse out subtitle when backend is DocBook', () {
        const input = '= Document Title: Subtitle\n:doctype: book\n\ntext\n';
        final result = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook5'),
        );
        assertXpath('/book', result, 1);
        assertXpath('/book/info/title[text()="Document Title"]', result, 1);
        assertXpath('/book/info/subtitle[text()="Subtitle"]', result, 1);
      });

      test('should be able to set doctype to article when converting '
          'to DocBook', () {
        const input =
            '= Title\nAuthor Name\n\npreamble\n\n== First '
            'Section\n\nsection body\n';
        final result = convertString(
          input,
          const AsciidoctorOptions(attributes: {'backend': 'docbook5'}),
        );
        assertXpath('/xmlns:article', result, 1);
        final doc = xmlnodeAtXpath('/xmlns:article', result);
        expect(
          doc.namespaces['xmlns'],
          equals('http://docbook.org/ns/docbook'),
        );
        expect(
          doc.namespaces['xmlns:xl'],
          equals('http://www.w3.org/1999/xlink'),
        );
        assertXpath('/xmlns:article[@version="5.0"]', result, 1);
        assertXpath(
          '/xmlns:article/xmlns:info/xmlns:title[text()="Title"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:simpara[text()="preamble"]',
          result,
          1,
        );
        assertXpath('/xmlns:article/xmlns:section', result, 1);
        assertCss('article:root > section[xml|id="_first_section"]', result, 1);
      });

      test('should set doctype to article by default for document with no '
          'title when converting to DocBook', () {
        final result = convertString(
          'text',
          const AsciidoctorOptions(attributes: {'backend': 'docbook'}),
        );
        assertXpath('/article', result, 1);
        assertXpath('/article/info/title', result, 1);
        assertXpath('/article/info/title[text()="Untitled"]', result, 1);
        assertXpath('/article/info/date', result, 1);
      });

      test('should be able to convert DocBook manpage output when backend is '
          'DocBook and doctype is manpage', () {
        const input =
            '= asciidoctor(1)\n'
            ':mansource: Asciidoctor\n'
            ':manmanual: Asciidoctor Manual\n'
            '\n'
            '== NAME\n'
            '\n'
            'asciidoctor - Process text\n'
            '\n'
            '== SYNOPSIS\n'
            '\n'
            'some text\n'
            '\n'
            '== First Section\n'
            '\n'
            'section body\n';
        final result = convertString(
          input,
          const AsciidoctorOptions(
            attributes: {'backend': 'docbook5', 'doctype': 'manpage'},
          ),
        );
        assertXpath('/xmlns:article', result, 1);
        assertXpath('/xmlns:article/xmlns:refentry', result, 1);
        final doc = xmlnodeAtXpath('/xmlns:article', result);
        expect(
          doc.namespaces['xmlns'],
          equals('http://docbook.org/ns/docbook'),
        );
        expect(
          doc.namespaces['xmlns:xl'],
          equals('http://www.w3.org/1999/xlink'),
        );
        expect(doc.attr('version'), equals('5.0'));
        assertXpath(
          '/xmlns:article/xmlns:info/xmlns:title[text()="asciidoctor(1)"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refentrytitle[text()="asciidoctor"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:manvolnum[text()="1"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="source"][text()="Asciidoctor"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="manual"][text()="Asciidoctor Manual"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refnamediv/xmlns:refname[text()="asciidoctor"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refnamediv/xmlns:refpurpose[text()="Process text"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refsynopsisdiv',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refsynopsisdiv/xmlns:simpara[text()="some text"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refsection',
          result,
          1,
        );
        assertCss(
          'article:root > refentry > refsection[xml|id="_first_section"]',
          result,
          1,
        );
      });

      test('should output non-breaking space for source and manual in docbook '
          'manpage output if absent from source', () {
        const input =
            '= asciidoctor(1)\n\n== NAME\n\nasciidoctor - Process '
            'text\n\n== SYNOPSIS\n\nsome text\n';
        final result = convertString(
          input,
          const AsciidoctorOptions(
            attributes: {'backend': 'docbook5', 'doctype': 'manpage'},
          ),
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="source"][text()="${decodeChar(160)}"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="manual"][text()="${decodeChar(160)}"]',
          result,
          1,
        );
      });

      test('should apply replacements substitution to value of mantitle '
          'attribute used in DocBook output', () {
        const input =
            '= foo\\--bar(1)\nAuthor Name\n:doctype: manpage\n:man manual: Foo Bar Manual\n'
            ':man source: Foo Bar 1.0\n\n== NAME\n\nfoo--bar - puts '
            'the foo in your bar\n';
        final doc = asciidoctorLoad(
          input,
          backend: 'docbook',
          standalone: true,
        );
        expect(doc.attr('mantitle'), equals(r'foo\--bar'));
        final result = doc.convert();
        assertXpath(
          '/xmlns:article/xmlns:info/xmlns:title[text()="foo--bar(1)"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refentrytitle[text()="foo--bar"]',
          result,
          1,
        );
      });

      test('should be able to set doctype to book when converting to '
          'DocBook', () {
        const input =
            '= Title\nAuthor Name\n\npreamble\n\n== First '
            'Chapter\n\nchapter body\n';
        final result = convertString(
          input,
          const AsciidoctorOptions(
            attributes: {'backend': 'docbook5', 'doctype': 'book'},
          ),
        );
        assertXpath('/xmlns:book', result, 1);
        final doc = xmlnodeAtXpath('/xmlns:book', result);
        expect(
          doc.namespaces['xmlns'],
          equals('http://docbook.org/ns/docbook'),
        );
        expect(
          doc.namespaces['xmlns:xl'],
          equals('http://www.w3.org/1999/xlink'),
        );
        assertXpath('/xmlns:book[@version="5.0"]', result, 1);
        assertXpath(
          '/xmlns:book/xmlns:info/xmlns:title[text()="Title"]',
          result,
          1,
        );
        assertXpath(
          '/xmlns:book/xmlns:preface/xmlns:simpara[text()="preamble"]',
          result,
          1,
        );
        assertXpath('/xmlns:book/xmlns:chapter', result, 1);
        assertCss('book:root > chapter[xml|id="_first_chapter"]', result, 1);
      });

      test('should be able to set doctype to book for document with no title '
          'when converting to DocBook', () {
        final result = convertString(
          'text',
          const AsciidoctorOptions(
            attributes: {'backend': 'docbook5', 'doctype': 'book'},
          ),
        );
        assertXpath('/book', result, 1);
        assertXpath('/book/info/date', result, 1);
        // NOTE simpara cannot be a direct child of book, so content must
        // be treated as a preface.
        assertXpath('/book/preface/simpara[text()="text"]', result, 1);
      });

      test('adds refname to DocBook output for each name defined in NAME '
          'section of manpage', () {
        const input =
            '= eve(1)\n'
            'Andrew Stanton\n'
            'v1.0.0\n'
            ':doctype: manpage\n'
            ':manmanual: EVE\n'
            ':mansource: EVE\n'
            '\n'
            '== NAME\n'
            '\n'
            "eve, islifeform - analyzes an image to determine if it's a "
            'picture of a life form\n'
            '\n'
            '== SYNOPSIS\n'
            '\n'
            "*eve* ['OPTION']... 'FILE'...\n";
        final result = convertString(
          input,
          const AsciidoctorOptions(backend: 'docbook5'),
        );
        assertXpath('/article/refentry/refnamediv/refname', result, 2);
        assertXpath(
          '(/article/refentry/refnamediv/refname)[1][text()="eve"]',
          result,
          1,
        );
        assertXpath(
          '(/article/refentry/refnamediv/refname)[2][text()="islifeform"]',
          result,
          1,
        );
      });

      test(
        'adds a front and back cover image to DocBook 5 when doctype is book',
        () {
          const input =
              '= Title\n:doctype: book\n:imagesdir: images\n'
              ':front-cover-image: image:front-cover.jpg[scaledwidth=210mm]\n'
              ':back-cover-image: image:back-cover.jpg[]\n\npreamble\n\n'
              '== First Chapter\n\nchapter body\n';
          final result = convertString(
            input,
            const AsciidoctorOptions(attributes: {'backend': 'docbook5'}),
          );
          assertXpath('//info/cover[@role="front"]', result, 1);
          assertXpath(
            '//info/cover[@role="front"]//imagedata[@fileref="images/front-cover.jpg"]',
            result,
            1,
          );
          assertXpath('//info/cover[@role="back"]', result, 1);
          assertXpath(
            '//info/cover[@role="back"]//imagedata[@fileref="images/back-cover.jpg"]',
            result,
            1,
          );
        },
      );

      test('should be able to set backend using :backend option key', () {
        final doc = emptyDocument(const AsciidoctorOptions(backend: 'html5'));
        expect(doc.attributes['backend'], equals('html5'));
      });

      test(':backend option should override backend attribute', () {
        final doc = emptyDocument(
          const AsciidoctorOptions(
            backend: 'html5',
            attributes: {'backend': 'docbook5'},
          ),
        );
        expect(doc.attributes['backend'], equals('html5'));
      });

      test('should be able to set doctype using :doctype option key', () {
        final doc = emptyDocument(const AsciidoctorOptions(doctype: 'book'));
        expect(doc.attributes['doctype'], equals('book'));
      });

      test(':doctype option should override doctype attribute', () {
        final doc = emptyDocument(
          const AsciidoctorOptions(
            doctype: 'book',
            attributes: {'doctype': 'article'},
          ),
        );
        expect(doc.attributes['doctype'], equals('book'));
      });

      test('do not override explicit author initials', () {
        const input =
            '= AsciiDoc\nStuart Rackham <founder@asciidoc.org>\n'
            ':Author Initials: SJR\n\nmore info...\n';
        final output = convertString(
          input,
          const AsciidoctorOptions(attributes: {'backend': 'docbook5'}),
        );
        assertXpath('/article/info/authorinitials[text()="SJR"]', output, 1);
      });

      test('attribute entry can appear immediately after document title', () {
        const input = 'Reference Guide\n===============\n:toc:\n\npreamble\n';
        final doc = documentFromString(input);
        expect(doc.hasAttr('toc'), isTrue);
        expect(doc.attr('toc'), equals(''));
      });

      test('attribute entry can appear before author line under '
          'document title', () {
        const input =
            'Reference Guide\n===============\n:toc:\nDan Allen\n\npreamble\n';
        final doc = documentFromString(input);
        expect(doc.hasAttr('toc'), isTrue);
        expect(doc.attr('toc'), equals(''));
        expect(doc.attr('author'), equals('Dan Allen'));
      });

      test('should parse mantitle and manvolnum from document title for '
          'manpage doctype', () {
        const input =
            '= asciidoctor ( 1 )\n:doctype: manpage\n\n== NAME\n\nasciidoctor '
            '- converts AsciiDoc source files to HTML, DocBook and '
            'other formats\n';
        final doc = documentFromString(input);
        expect(doc.attr('mantitle'), equals('asciidoctor'));
        expect(doc.attr('manvolnum'), equals('1'));
      });

      test('should perform attribute substitution on mantitle in '
          'manpage doctype', () {
        const input =
            '= {app}(1)\n:doctype: manpage\n:app: Asciidoctor\n\n== '
            'NAME\n\nasciidoctor - converts AsciiDoc source files '
            'to HTML, DocBook and other formats\n';
        final doc = documentFromString(input);
        expect(doc.attr('mantitle'), equals('asciidoctor'));
      });

      test('should consume name section as manname and manpurpose for manpage '
          'doctype', () {
        const input =
            '= asciidoctor(1)\n:doctype: manpage\n\n== NAME\n\nasciidoctor - '
            'converts AsciiDoc source files to HTML, DocBook and '
            'other formats\n';
        final doc = documentFromString(input);
        expect(doc.attr('manname'), equals('asciidoctor'));
        expect(
          doc.attr('manpurpose'),
          equals(
            'converts AsciiDoc source files to HTML, DocBook and other formats',
          ),
        );
        expect(doc.attr('manname-id'), equals('_name'));
        expect(doc.blocks.length, equals(0));
      });

      test('should set docname and outfilesuffix from manname and manvolnum '
          'for manpage backend and doctype', () {
        const input =
            '= asciidoctor(1)\n:doctype: manpage\n\n== NAME\n\nasciidoctor - '
            'converts AsciiDoc source files to HTML, DocBook and '
            'other formats\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(backend: 'manpage'),
        );
        expect(doc.attributes['docname'], equals('asciidoctor'));
        expect(doc.attributes['outfilesuffix'], equals('.1'));
      });

      test('should mark synopsis as special section in manpage doctype', () {
        const input =
            '= asciidoctor(1)\n'
            ':doctype: manpage\n'
            '\n'
            '== NAME\n'
            '\n'
            'asciidoctor - converts AsciiDoc source files to HTML, DocBook and '
            'other formats\n'
            '\n'
            '== SYNOPSIS\n'
            '\n'
            "*asciidoctor* ['OPTION']... 'FILE'..\n";
        final doc = documentFromString(input);
        final synopsisSection = doc.blocks.first as Section;
        expect(synopsisSection.contextName, equals('section'));
        expect(synopsisSection.special, isTrue);
        expect(synopsisSection.sectname, equals('synopsis'));
      });

      test(
        'should output special header block in HTML for manpage doctype',
        () {
          const input =
              '= asciidoctor(1)\n'
              ':doctype: manpage\n'
              '\n'
              '== NAME\n'
              '\n'
              'asciidoctor - converts AsciiDoc source files to HTML, DocBook '
              'and other formats\n'
              '\n'
              '== SYNOPSIS\n'
              '\n'
              "*asciidoctor* ['OPTION']... 'FILE'..\n";
          final output = convertString(input);
          assertCss('body.manpage', output, 1);
          assertXpath(
            '//body/*[@id="header"]/h1[text()="asciidoctor(1) Manual Page"]',
            output,
            1,
          );
          assertXpath(
            '//body/*[@id="header"]/h1/following-sibling::h2[text()="NAME"]',
            output,
            1,
          );
          assertXpath('//h2[@id="_name"][text()="NAME"]', output, 1);
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]',
            output,
            1,
          );
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]/p[text()="asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats"]',
            output,
            1,
          );
          assertXpath(
            '//*[@id="content"]/*[@class="sect1"]/h2[text()="SYNOPSIS"]',
            output,
            1,
          );
        },
      );

      test('should output special header block in embeddable HTML for manpage '
          'doctype', () {
        const input =
            '= asciidoctor(1)\n'
            ':doctype: manpage\n'
            ':showtitle:\n'
            '\n'
            '== NAME\n'
            '\n'
            'asciidoctor - converts AsciiDoc source files to HTML, DocBook and '
            'other formats\n'
            '\n'
            '== SYNOPSIS\n'
            '\n'
            "*asciidoctor* ['OPTION']... 'FILE'..\n";
        final output = convertStringToEmbedded(input);
        assertXpath('/h1[text()="asciidoctor(1) Manual Page"]', output, 1);
        assertXpath('/h1/following-sibling::h2[text()="NAME"]', output, 1);
        assertXpath('//h2[@id="_name"][text()="NAME"]', output, 1);
        assertXpath(
          '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]',
          output,
          1,
        );
        assertXpath(
          '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]/p[text()="asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats"]',
          output,
          1,
        );
      });

      test('should output all mannames in name section in man page output', () {
        const input =
            '= eve(1)\n'
            ':doctype: manpage\n'
            '\n'
            '== NAME\n'
            '\n'
            'eve, probe - analyzes an image to determine if it is a picture of '
            'a life form\n'
            '\n'
            '== SYNOPSIS\n'
            '\n'
            '*eve* [OPTION]... FILE...\n';
        final output = convertString(input);
        assertCss('body.manpage', output, 1);
        assertXpath(
          '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]/p[text()="eve, probe - analyzes an image to determine if it is a picture of a life form"]',
          output,
          1,
        );
      });
    });

    group('Secure Asset Path', () {
      test(
        testOn: 'vm',
        'allows us to specify a path relative to the current dir',
        () {
          final doc = emptyDocument();
          final legitPath = '$currentPath/foo';
          expect(doc.normalizeAssetPath(legitPath), equals(legitPath));
        },
      );

      test('keeps naughty absolute paths from getting outside', () {
        const naughtyPath = '/etc/passwd';
        usingMemoryLogger((logger) {
          final doc = emptyDocument();
          final securePath = doc.normalizeAssetPath(naughtyPath);
          expect(securePath, isNot(equals(naughtyPath)));
          expect(securePath, equals('${doc.baseDir}/etc/passwd'));
          expect(logger.warns, hasLength(1));
          expect(
            logger.warns.single,
            equals('path is outside of jail; recovering automatically'),
          );
        });
      });

      test('keeps naughty relative paths from getting outside', () {
        const naughtyPath = 'safe/ok/../../../../../etc/passwd';
        usingMemoryLogger((logger) {
          final doc = emptyDocument();
          final securePath = doc.normalizeAssetPath(naughtyPath);
          expect(securePath, isNot(equals(naughtyPath)));
          expect(securePath, startsWith('${doc.baseDir}/'));
        });
      });

      test('should raise an exception when a converter cannot be resolved '
          'before conversion', () {
        const input = '= Document Title\n\ntext\n';
        expect(
          () => Document(
            input,
            const AsciidoctorOptions(backend: 'unknownBackend'),
          ),
          throwsA(
            isA<AsciidoctorException>().having(
              (error) => error.message,
              'message',
              contains("missing converter for backend 'unknownBackend'"),
            ),
          ),
        );
      });

      test('should raise an exception when a converter cannot be resolved '
          'while parsing', () {
        const input = '= Document Title\n\n== A _Big_ Section\n\ntext\n';
        expect(
          () => Document(
            input,
            const AsciidoctorOptions(backend: 'unknownBackend'),
          ),
          throwsA(
            isA<AsciidoctorException>().having(
              (error) => error.message,
              'message',
              contains("missing converter for backend 'unknownBackend'"),
            ),
          ),
        );
      });
    });

    group('Date time attributes', () {
      test(
        'should compute docyear and docdatetime from docdate and doctime',
        () {
          final doc = Document(
            null,
            const AsciidoctorOptions(
              attributes: {'docdate': '2015-01-01', 'doctime': '10:00:00-0700'},
            ),
          );
          expect(doc.attr('docdate'), equals('2015-01-01'));
          expect(doc.attr('docyear'), equals('2015'));
          expect(doc.attr('doctime'), equals('10:00:00-0700'));
          expect(doc.attr('docdatetime'), equals('2015-01-01 10:00:00-0700'));
        },
      );

      test('should allow docdate and doctime to be overridden', () {
        final doc = Document(
          null,
          AsciidoctorOptions(
            inputMtime: DateTime.now(),
            attributes: {'docdate': '2015-01-01', 'doctime': '10:00:00-0700'},
          ),
        );
        expect(doc.attr('docdate'), equals('2015-01-01'));
        expect(doc.attr('docyear'), equals('2015'));
        expect(doc.attr('doctime'), equals('10:00:00-0700'));
        expect(doc.attr('docdatetime'), equals('2015-01-01 10:00:00-0700'));
      });

      test('should compute docdatetime from doctime', () {
        final doc = Document(
          null,
          const AsciidoctorOptions(attributes: {'doctime': '10:00:00-0700'}),
        );
        expect(doc.attr('doctime'), equals('10:00:00-0700'));
        expect(doc.attr('docdatetime'), endsWith(' 10:00:00-0700'));
      });

      test('should compute docyear from docdate', () {
        final doc = Document(
          null,
          const AsciidoctorOptions(attributes: {'docdate': '2015-01-01'}),
        );
        expect(doc.attr('docyear'), equals('2015'));
        expect(doc.attr('docdatetime'), startsWith('2015-01-01 '));
      });

      test('should allow doctime to be overridden', () {
        // NOTE Dart cannot unset SOURCE_DATE_EPOCH (Platform.environment is
        // read-only); this test assumes it is not set, as in the Ruby test
        // which deletes it first.
        final doc = Document(
          null,
          AsciidoctorOptions(
            inputMtime: DateTime(2019, 1, 2, 3, 4, 5),
            attributes: {'doctime': '10:00:00-0700'},
          ),
        );
        expect(doc.attr('docdate'), equals('2019-01-02'));
        expect(doc.attr('docyear'), equals('2019'));
        expect(doc.attr('doctime'), equals('10:00:00-0700'));
        expect(doc.attr('docdatetime'), equals('2019-01-02 10:00:00-0700'));
      });

      test('should allow docdate to be overridden', () {
        // NOTE Dart cannot unset SOURCE_DATE_EPOCH (Platform.environment is
        // read-only); this test assumes it is not set, as in the Ruby test
        // which deletes it first. Dart also has no fixed-offset DateTime,
        // so the expected offset is derived from the input value; a UTC
        // input additionally locks the exact 'UTC' rendering.
        final input = DateTime(2019, 1, 2, 3, 4, 5);
        final doc = Document(
          null,
          AsciidoctorOptions(
            inputMtime: input,
            attributes: {'docdate': '2015-01-01'},
          ),
        );
        expect(doc.attr('docdate'), equals('2015-01-01'));
        expect(doc.attr('docyear'), equals('2015'));
        final offset = input.timeZoneOffset;
        final zone = offset == Duration.zero
            ? 'UTC'
            : '${offset.isNegative ? '-' : '+'}'
                  '${offset.inHours.abs().toString().padLeft(2, '0')}'
                  '${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
        expect(doc.attr('docdatetime'), equals('2015-01-01 03:04:05 $zone'));

        final utcDoc = Document(
          null,
          AsciidoctorOptions(
            inputMtime: DateTime.utc(2019, 1, 2, 3, 4, 5),
            attributes: {'docdate': '2015-01-01'},
          ),
        );
        expect(utcDoc.attr('docdatetime'), equals('2015-01-01 03:04:05 UTC'));
      });
    });
  });
}
