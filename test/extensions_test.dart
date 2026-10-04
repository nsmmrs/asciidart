/// Port of `test/extensions_test.rb`.
///
/// All tests run: extension integration (activation through the
/// `extension_registry`/`extensions` options and global groups,
/// preprocessor/tree/postprocessor/docinfo invocation, custom blocks,
/// block macros and inline macros) is ported, and converted-output
/// assertions route through the test-only [assertXpath]/[assertCss]
/// matchers below.
///
/// Several Ruby tests are adapted to the Dart port (manual registry
/// activation where Ruby leans on global state, factories where Ruby
/// passes classes, an explicit arity where Ruby blocks tolerate an unused
/// argument); each adaptation is marked on the test. The Ruby test
/// covering unregistration with uninitialized extension groups has no Dart
/// counterpart (Dart statics are always initialized) and is dropped; its
/// essence (unregistering an unknown group never fails) is covered by the
/// neighboring test.
library;

import 'dart:convert' show Encoding;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/attribute_list.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/extensions.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/load.dart' as api;
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles.
// ---------------------------------------------------------------------------

/// Records log messages for assertions.
class FakeLogger implements NodeLogger {
  /// Messages by severity.
  final List<Object?> debugs = <Object?>[];
  final List<Object?> infos = <Object?>[];
  final List<Object?> warns = <Object?>[];
  final List<Object?> errors = <Object?>[];
  final List<Object?> fatals = <Object?>[];

  /// All recorded messages.
  List<Object?> get messages => <Object?>[
    ...debugs,
    ...infos,
    ...warns,
    ...errors,
    ...fatals,
  ];

  @override
  void debug(Object? message) {
    debugs.add(message);
  }

  @override
  void info(Object? message) {
    infos.add(message);
  }

  @override
  void warn(Object? message) {
    warns.add(message);
  }

  @override
  void error(Object? message) {
    errors.add(message);
  }

  @override
  void fatal(Object? message) {
    fatals.add(message);
  }
}

/// A [LoggerBase] forwarding every record into a [FakeLogger].
///
/// Mirrors Ruby's `MemoryLogger`: records everything regardless of level
/// (the level only drives the `is*Enabled` predicates consulted by
/// level-gated call sites such as the parser's debug probes).
class ManagerLoggerAdapter extends LoggerBase {
  /// Creates an adapter recording into [fake].
  ManagerLoggerAdapter(this.fake) : super(Severity.unknown);

  /// The backing fake logger.
  final FakeLogger fake;

  @override
  Severity? get maxSeverity => _maxSeverity;
  Severity? _maxSeverity;

  @override
  bool add(Severity? severity, [Object? message, Object? progname]) {
    var text = message;
    if (text is Object? Function()) text = text();
    text ??= progname;
    final resolved = severity ?? Severity.unknown;
    if (_maxSeverity == null || resolved.value > _maxSeverity!.value) {
      _maxSeverity = resolved;
    }
    switch (resolved) {
      case Severity.debug:
        fake.debug(text);
      case Severity.info:
        fake.info(text);
      case Severity.warn:
        fake.warn(text);
      case Severity.error:
        fake.error(text);
      case Severity.fatal:
      case Severity.unknown:
        fake.fatal(text);
    }
    return true;
  }

  @override
  Future<void> close() async {}
}

/// Runs [body] with a memory logger installed (port of
/// `using_memory_logger`).
///
/// Installs the [FakeLogger] for node-level logging and bridges the
/// global [LoggerManager] logger into it so parser-level records are
/// captured too. [severity] sets the manager level (default `UNKNOWN`,
/// recording everything while keeping debug-gated call sites quiet).
void usingMemoryLogger(
  void Function(FakeLogger logger) body, [
  String? severity,
]) {
  final saved = AbstractNode.currentLogger;
  final savedManager = LoggerManager.logger;
  final logger = FakeLogger();
  final manager = ManagerLoggerAdapter(logger);
  if (severity != null) manager.level = severity;
  AbstractNode.currentLogger = logger;
  LoggerManager.logger = manager;
  try {
    body(logger);
  } finally {
    AbstractNode.currentLogger = saved;
    LoggerManager.logger = savedManager;
  }
}

/// Asserts [logger] recorded [message] at [severity] (port of
/// `assert_message`).
void assertMessage(FakeLogger logger, String severity, String message) {
  final List<Object?> candidates;
  switch (severity) {
    case 'DEBUG':
      candidates = logger.debugs;
    case 'INFO':
      candidates = logger.infos;
    case 'WARN':
      candidates = logger.warns;
    case 'ERROR':
      candidates = logger.errors;
    case 'FATAL':
      candidates = logger.fatals;
    default:
      throw ArgumentError('Unknown severity: $severity');
  }
  expect(
    candidates.map((candidate) => candidate.toString()),
    contains(message),
  );
}

/// A [ReaderDocument] delegating to a real [Document], for driving a
/// [PreprocessorReader] with registry include processors headlessly.
class FakeReaderDocument implements ReaderDocument {
  /// Creates a fake backed by [document] with [includeProcessors].
  FakeReaderDocument(this.document, [this.includeProcessors]);

  /// The backing document.
  final Document document;

  @override
  final List<ReaderIncludeProcessor>? includeProcessors;

  @override
  Map<String, Object?> get attributes => document.attributes;

  @override
  Object? attr(String name) => document.attr(name);

  @override
  bool attrSet(String name) => document.hasAttr(name);

  @override
  bool get sourcemap => document.sourcemap;

  @override
  int get safe => document.safe;

  @override
  String get baseDir => document.baseDir;

  @override
  PathResolver get pathResolver => document.pathResolver;

  @override
  Map<String, bool?> get catalogIncludes =>
      document.catalog['includes'] as Map<String, bool?>;

  @override
  String normalizeSystemPath(
    String target,
    String? start, {
    String? targetName,
  }) => document.normalizeSystemPath(
    target,
    start: start,
    targetName: targetName ?? 'path',
  );

  @override
  String subAttributes(
    String text, {
    String? attributeMissing,
    String dropLineSeverity = 'info',
  }) => throw UnimplementedError(
    'Substitutors wave: FakeReaderDocument.subAttributes is not supported.',
  );

  @override
  Map<Object, String?> parseAttributes(
    String? attrlist, {
    bool subInput = false,
  }) => AttributeList(attrlist ?? '').parse();

  @override
  String? readUri(Uri uri, Encoding encoding) =>
      document.readUri(uri, encoding);
}

/// Creates an empty document (port of `empty_document`; never parses).
Document emptyDocument([Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts.remove('parse');
  return Document(<String>[], opts);
}

/// Creates a document from [src] (port of `document_from_string`).
///
/// Defaults to `standalone: true` and `parse: true`, like the Ruby helper.
Document documentFromString(String src, [Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts.putIfAbsent('standalone', () => true);
  final parse = opts.remove('parse') ?? true;
  if (opts['standalone'] == true) {
    final attrs =
        (opts['attributes'] as Map<String, Object?>?) ?? <String, Object?>{};
    attrs['linkcss'] = '';
    opts['attributes'] = attrs;
  }
  final doc = Document(src, opts);
  return (parse == true) ? doc.parse() : doc;
}

/// Converts [src] to a standalone document (port of `convert_string`).
String convertString(String src, [Map<String, Object?>? options]) {
  return documentFromString(src, options).convert() as String;
}

/// Converts [src] to an embedded document (port of
/// `convert_string_to_embedded`).
String convertStringToEmbedded(String src, [Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts['standalone'] = false;
  return documentFromString(src, opts).convert() as String;
}

/// Converts the file at [path] (port of `Asciidoctor.convert_file`).
String convertFile(
  String path, {
  Object? toFile,
  bool standalone = false,
  Object? safe,
  Map<String, Object?>? attributes,
}) => api.convertFile(path, <String, Object?>{
  'to_file': toFile,
  'standalone': standalone,
  'safe': ?safe,
  'attributes': ?attributes,
}) as String;

/// Loads the file at [path] (port of `Asciidoctor.load_file`).
Document loadFile(String path, {bool sourcemap = false}) =>
    api.loadFile(path, <String, Object?>{'sourcemap': sourcemap});

/// Loads [input] into a parsed document (port of `Asciidoctor.load`).
Document asciidoctorLoad(String input) => api.load(input);

/// Converts [input] (port of `Asciidoctor.convert`).
String asciidoctorConvert(String input) => api.convert(input) as String;

/// Asserts [content] matches [xpath] [count] times (port of `assert_xpath`).
void assertXpath(String xpath, String? content, int count) {
  final matches = _queryXpath(_parseFragment(content ?? ''), xpath);
  expect(
    matches.length,
    equals(count),
    reason:
        'XPath $xpath yielded ${matches.length} elements rather than '
        '$count for:\n$content',
  );
}

/// Asserts [content] matches [css] [count] times (port of `assert_css`).
void assertCss(String css, String? content, int count) {
  final matches = _queryCss(_parseFragment(content ?? ''), css);
  expect(
    matches.length,
    equals(count),
    reason:
        'CSS $css yielded ${matches.length} elements rather than '
        '$count for:\n$content',
  );
}

// ---------------------------------------------------------------------------
// Minimal HTML fragment matching (test-only port of the Nokogiri-backed
// `assert_xpath`/`assert_css` helpers in `test/test_helper.rb`).
//
// Supports exactly the selector shapes this suite uses: tag, `*`,
// `.class`, `[attr="value"]`, descendant and child combinators (CSS), and
// `/child`, `//descendant`, `[@attr="value"]`, `[not(@attr)]`,
// `[text()="value"]` and `(path)[n]` (XPath).
// ---------------------------------------------------------------------------

/// HTML void elements (never have children or an end tag).
const _voidElements = <String>{
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

/// A parsed element: [tag], [attributes], child [children] and direct
/// [texts] segments.
class _XmlElement {
  /// Creates an element with [tag] and [attributes].
  _XmlElement(this.tag, [Map<String, String>? attributes])
    : attributes = attributes ?? <String, String>{};

  /// The lower-cased tag name (`'#root'` for the synthetic fragment root).
  final String tag;

  /// The element attributes (entity-decoded values).
  final Map<String, String> attributes;

  /// The child elements in document order.
  final List<_XmlElement> children = <_XmlElement>[];

  /// The direct text segments in document order (entity-decoded).
  final List<String> texts = <String>[];

  /// The parent element, if any.
  _XmlElement? parent;

  /// This element and all descendants in document order.
  Iterable<_XmlElement> get selfAndDescendants sync* {
    yield this;
    for (final child in children) {
      yield* child.selfAndDescendants;
    }
  }

  /// All descendants in document order.
  Iterable<_XmlElement> get descendants sync* {
    for (final child in children) {
      yield* child.selfAndDescendants;
    }
  }
}

/// Decodes XML/HTML entities in [text].
String _decodeEntities(String text) {
  return text.replaceAllMapped(RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (
    match,
  ) {
    final entity = match.group(1)!;
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      default:
        if (entity.startsWith('#x')) {
          final code = int.tryParse(entity.substring(2), radix: 16);
          if (code != null) return String.fromCharCode(code);
        } else if (entity.startsWith('#')) {
          final code = int.tryParse(entity.substring(1));
          if (code != null) return String.fromCharCode(code);
        }
        return match.group(0)!;
    }
  });
}

/// Parses [content] as a lenient HTML fragment under a synthetic root.
_XmlElement _parseFragment(String content) {
  final root = _XmlElement('#root');
  final stack = <_XmlElement>[root];
  final tagRx = RegExp(
    r'<!--.*?(?:-->|$)|<![^>]*>|</\s*([A-Za-z][^\s>]*)[^>]*>|<([A-Za-z][^\s>/]*)([^>]*)>',
    dotAll: true,
  );
  final attrRx = RegExp(
    '([^\\s=/>]+)(?:\\s*=\\s*("[^"]*"|\'[^\']*\'|[^\\s>]*))?',
  );
  var pos = 0;
  for (final match in tagRx.allMatches(content)) {
    if (match.start > pos) {
      stack.last.texts.add(
        _decodeEntities(content.substring(pos, match.start)),
      );
    }
    pos = match.end;
    final endTag = match.group(1);
    if (endTag != null) {
      final name = endTag.toLowerCase();
      for (var i = stack.length - 1; i > 0; i--) {
        if (stack[i].tag == name) {
          stack.removeRange(i, stack.length);
          break;
        }
      }
      continue;
    }
    final startTag = match.group(2);
    if (startTag == null) continue; // Comment or declaration.
    final name = startTag.toLowerCase();
    final attributes = <String, String>{};
    for (final attr in attrRx.allMatches(match.group(3)!)) {
      var value = attr.group(2) ?? '';
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      attributes[attr.group(1)!.toLowerCase()] = _decodeEntities(value);
    }
    final element = _XmlElement(name, attributes);
    element.parent = stack.last;
    stack.last.children.add(element);
    final raw = match.group(0)!;
    if (!raw.endsWith('/>') && !_voidElements.contains(name)) {
      stack.add(element);
    }
  }
  if (pos < content.length) {
    stack.last.texts.add(_decodeEntities(content.substring(pos)));
  }
  return root;
}

/// A parsed CSS compound selector.
class _CssCompound {
  /// Creates a compound matching [tag], [classes] and [attrs].
  _CssCompound(this.tag, this.classes, this.attrs);

  /// The tag name, `'*'`, or `null` (any tag).
  final String? tag;

  /// The required class names.
  final List<String> classes;

  /// The required attribute equalities.
  final Map<String, String> attrs;

  /// Whether [element] matches this compound.
  bool matches(_XmlElement element) {
    if (tag != null && tag != '*' && element.tag != tag) return false;
    if (classes.isNotEmpty) {
      final elementClasses =
          element.attributes['class']
              ?.split(RegExp(r'\s+'))
              .where((name) => name.isNotEmpty)
              .toSet() ??
          <String>{};
      for (final required in classes) {
        if (!elementClasses.contains(required)) return false;
      }
    }
    for (final entry in attrs.entries) {
      if (element.attributes[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Parses a CSS compound selector such as `code.language-ruby[data-lang]`.
_CssCompound _parseCssCompound(String source) {
  final attrRx = RegExp(
    '\\[([^\\]=]+)(?:="([^"]*)"|\'([^\']*)\'|=([^\\]]*))?\\]',
  );
  final attrs = <String, String>{};
  var rest = source;
  for (final match in attrRx.allMatches(source)) {
    attrs[match.group(1)!.toLowerCase()] =
        match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    rest = rest.replaceFirst(match.group(0)!, '');
  }
  final parts = rest.split('.');
  final tag = parts.first.isEmpty ? null : parts.first.toLowerCase();
  final classes = parts.skip(1).where((name) => name.isNotEmpty).toList();
  return _CssCompound(tag, classes, attrs);
}

/// Tokenizes a CSS selector into compounds and combinators (`' '`/`'>'`).
List<Object> _tokenizeCss(String selector) {
  final tokens = <Object>[];
  final buffer = StringBuffer();
  var bracketDepth = 0;
  var quote = '';
  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
  }

  for (var i = 0; i < selector.length; i++) {
    final char = selector[i];
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == quote) quote = '';
    } else if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
    } else if (char == '[') {
      bracketDepth++;
      buffer.write(char);
    } else if (char == ']') {
      bracketDepth--;
      buffer.write(char);
    } else if (bracketDepth == 0 && char == '>') {
      flush();
      tokens.add('>');
    } else if (bracketDepth == 0 &&
        (char == ' ' || char == '\t' || char == '\n')) {
      flush();
    } else {
      buffer.write(char);
    }
  }
  flush();
  // Adjacent compounds imply the descendant combinator.
  final result = <Object>[];
  for (final token in tokens) {
    if (result.isNotEmpty && token != '>' && result.last != '>') {
      result.add(' ');
    }
    result.add(token);
  }
  return result;
}

/// Returns the elements of [root] matching the CSS [selector].
List<_XmlElement> _queryCss(_XmlElement root, String selector) {
  final tokens = _tokenizeCss(selector);
  final compounds = <_CssCompound>[];
  final combinators = <String>[];
  for (final token in tokens) {
    if (token == '>' || token == ' ') {
      combinators.add(token as String);
    } else {
      compounds.add(_parseCssCompound(token as String));
    }
  }
  bool matchesChain(_XmlElement element, int index) {
    if (!compounds[index].matches(element)) return false;
    if (index == 0) return true;
    final combinator = combinators[index - 1];
    if (combinator == '>') {
      final parent = element.parent;
      return parent != null && matchesChain(parent, index - 1);
    }
    var ancestor = element.parent;
    while (ancestor != null && ancestor.tag != '#root') {
      if (matchesChain(ancestor, index - 1)) return true;
      ancestor = ancestor.parent;
    }
    return false;
  }

  return root.descendants
      .where((element) => matchesChain(element, compounds.length - 1))
      .toList();
}

/// A parsed XPath predicate.
class _XpathPredicate {
  /// Creates an attribute-equality predicate.
  _XpathPredicate.attr(this.name, this.value) : kind = 0;

  /// Creates an attribute-absence predicate.
  _XpathPredicate.absent(this.name) : kind = 1, value = null;

  /// Creates a text-equality predicate.
  _XpathPredicate.text(this.value) : kind = 2, name = null;

  /// The predicate kind: 0 = `[@name="value"]`, 1 = `[not(@name)]`,
  /// 2 = `[text()="value"]`.
  final int kind;

  /// The attribute name (kinds 0-1).
  final String? name;

  /// The expected value (kinds 0 and 2).
  final String? value;

  /// Whether [element] satisfies this predicate.
  bool matches(_XmlElement element) {
    switch (kind) {
      case 0:
        return element.attributes[name] == value;
      case 1:
        return !element.attributes.containsKey(name);
      default:
        return element.texts.any((text) => text == value);
    }
  }
}

/// Parses the predicate list suffix of an XPath step (e.g.
/// `[@class="x"][not(@id)]`).
List<_XpathPredicate> _parseXpathPredicates(String source) {
  final predicates = <_XpathPredicate>[];
  final predRx = RegExp(
    '\\[@([A-Za-z_][\\w:.-]*)="([^"]*)"\\]|\\[@([A-Za-z_][\\w:.-]*)=\'([^\']*)\'\\]|\\[not\\(@([A-Za-z_][\\w:.-]*)\\)\\]|\\[text\\(\\)="([^"]*)"\\]',
  );
  for (final match in predRx.allMatches(source)) {
    if (match.group(1) != null) {
      predicates.add(
        _XpathPredicate.attr(match.group(1)!.toLowerCase(), match.group(2)!),
      );
    } else if (match.group(3) != null) {
      predicates.add(
        _XpathPredicate.attr(match.group(3)!.toLowerCase(), match.group(4)!),
      );
    } else if (match.group(5) != null) {
      predicates.add(_XpathPredicate.absent(match.group(5)!.toLowerCase()));
    } else {
      predicates.add(_XpathPredicate.text(match.group(6)!));
    }
  }
  return predicates;
}

/// Applies the predicate list [source] to [nodes].
List<_XmlElement> _applyXpathPredicates(
  List<_XmlElement> nodes,
  String source,
) {
  final predicates = _parseXpathPredicates(source);
  return nodes
      .where((node) => predicates.every((predicate) => predicate.matches(node)))
      .toList();
}

/// Returns the elements of [root] matching the XPath [path].
List<_XmlElement> _queryXpath(_XmlElement root, String path) {
  // `(path)[n][predicates...]`: positional selection on the node set.
  final positional = RegExp(
    r'^\((.+)\)\[(\d+)\](.*)$',
    dotAll: true,
  ).firstMatch(path);
  if (positional != null) {
    final nodes = _queryXpath(root, positional.group(1)!);
    final index = int.parse(positional.group(2)!) - 1;
    final selected = index >= 0 && index < nodes.length
        ? [nodes[index]]
        : <_XmlElement>[];
    return _applyXpathPredicates(selected, positional.group(3)!);
  }
  // Like Ruby's `path.sub '/', './'`: steps resolve against the fragment
  // root, so a leading `/` selects its children.
  var current = <_XmlElement>[root];
  var rest = path;
  while (rest.isNotEmpty) {
    final descendant = rest.startsWith('//');
    rest = descendant ? rest.substring(2) : rest.substring(1);
    var depth = 0;
    var end = rest.length;
    for (var i = 0; i < rest.length; i++) {
      final char = rest[i];
      if (char == '[') {
        depth++;
      } else if (char == ']') {
        depth--;
      } else if (char == '/' && depth == 0) {
        end = i;
        break;
      }
    }
    final step = rest.substring(0, end);
    rest = rest.substring(end);
    final tagEnd = step.startsWith('*')
        ? 1
        : RegExp(r'^[A-Za-z][\w:.-]*').firstMatch(step)?.group(0)?.length ?? 0;
    final tag = step.substring(0, tagEnd).toLowerCase();
    final predicates = _parseXpathPredicates(step.substring(tagEnd));
    final next = <_XmlElement>[];
    for (final node in current) {
      final candidates = descendant ? node.descendants : node.children;
      for (final candidate in candidates) {
        if ((tag == '*' || candidate.tag == tag) &&
            predicates.every((predicate) => predicate.matches(candidate))) {
          next.add(candidate);
        }
      }
    }
    current = next;
  }
  return current;
}

/// Resolves a fixture path (port of `fixture_path`).
///
/// Tests run with `dart/` as the working directory, so fixtures resolve
/// against the Ruby suite's `test/fixtures` directory (same shape as
/// `load_test.dart`).
String fixturePath(String name) => 'test/fixtures/$name';

// ---------------------------------------------------------------------------
// Sample processors (ports of the Ruby test file's top-level classes).
// ---------------------------------------------------------------------------

/// Sample preprocessor (port of `SamplePreprocessor`).
class SamplePreprocessor extends Preprocessor {
  /// Creates a sample preprocessor with [config].
  SamplePreprocessor([super.config]);

  @override
  Object? process(Document document, Reader reader) => null;
}

/// Sample include processor (port of `SampleIncludeProcessor`).
///
/// Ruby's sample defines the single-argument legacy `handles?`, which has
/// no Dart counterpart (see [IncludeProcessor.onHandles]); the port keeps
/// the default handling behavior instead.
class SampleIncludeProcessor extends IncludeProcessor {
  /// Creates a sample include processor with [config].
  SampleIncludeProcessor([super.config]);
}

/// Sample docinfo processor (port of `SampleDocinfoProcessor`).
class SampleDocinfoProcessor extends DocinfoProcessor {
  /// Creates a sample docinfo processor with [config].
  SampleDocinfoProcessor([super.config]);
}

// NOTE intentionally using the deprecated name.
// ignore: deprecated_member_use
/// Sample tree processor (port of `SampleTreeprocessor`).
class SampleTreeprocessor extends Treeprocessor {
  /// Creates a sample tree processor with [config].
  SampleTreeprocessor([super.config]);

  @override
  Object? process(Document document) => null;
}

/// Alias of [SampleTreeprocessor] (port of `SampleTreeProcessor = ...`).
typedef SampleTreeProcessor = SampleTreeprocessor;

/// Sample postprocessor (port of `SamplePostprocessor`).
class SamplePostprocessor extends Postprocessor {
  /// Creates a sample postprocessor with [config].
  SamplePostprocessor([super.config]);
}

/// Sample block processor (port of `SampleBlock`).
class SampleBlock extends BlockProcessor {
  /// Creates a sample block processor with [name] and [config].
  SampleBlock([super.name, super.config]);
}

/// Sample block macro processor (port of `SampleBlockMacro`).
class SampleBlockMacro extends BlockMacroProcessor {
  /// Creates a sample block macro processor with [name] and [config].
  SampleBlockMacro([super.name, super.config]);
}

/// Sample inline macro processor (port of `SampleInlineMacro`).
class SampleInlineMacro extends InlineMacroProcessor {
  /// Creates a sample inline macro processor with [name] and [config].
  SampleInlineMacro([super.name, super.config]);
}

/// Scrubs lines before the document title (port of
/// `ScrubHeaderPreprocessor`).
class ScrubHeaderPreprocessor extends Preprocessor {
  /// Creates the preprocessor with [config].
  ScrubHeaderPreprocessor([super.config]);

  @override
  Object? process(Document document, Reader reader) {
    final lines = reader.lines;
    final skipped = <String>[];
    while (lines.isNotEmpty && !lines.first!.startsWith('=')) {
      skipped.add(lines.removeAt(0)!);
      reader.advance();
    }
    document.setAttr('skipped', skipped.join('\n'));
    return reader;
  }
}

/// Serves `.txt` boilerplate includes (port of
/// `BoilerplateTextIncludeProcessor`).
class BoilerplateTextIncludeProcessor extends IncludeProcessor {
  /// Creates the processor with [config].
  BoilerplateTextIncludeProcessor([super.config]);

  @override
  bool handles(ReaderDocument document, String target) =>
      target.endsWith('.txt');

  @override
  Object? process(
    ReaderDocument document,
    PreprocessorReader reader,
    String target,
    Map<Object, String?> attributes,
  ) {
    if (target == 'lorem-ipsum.txt') {
      const content = ['Lorem ipsum dolor sit amet...\n'];
      reader.pushInclude(content, target, target, 1, attributes);
    }
    return null;
  }
}

/// Replaces the document author (port of `ReplaceAuthorTreeProcessor`).
class ReplaceAuthorTreeProcessor extends TreeProcessor {
  /// Creates the processor with [config].
  ReplaceAuthorTreeProcessor([super.config]);

  @override
  Object? process(Document document) {
    document.attributes['firstname'] = 'Ghost';
    document.attributes['author'] = 'Ghost Writer';
    return document;
  }
}

/// Replaces the whole document tree (port of `ReplaceTreeTreeProcessor`).
class ReplaceTreeTreeProcessor extends TreeProcessor {
  /// Creates the processor with [config].
  ReplaceTreeTreeProcessor([super.config]);

  @override
  Object? process(Document document) {
    if (document.doctitle() == 'Original Document') {
      return asciidoctorLoad(
        '== Replacement Document\nReplacement Author\n\ncontent',
      );
    }
    return document;
  }
}

/// Signs the document with its own name (port of
/// `SelfSigningTreeProcessor`).
class SelfSigningTreeProcessor extends TreeProcessor {
  /// Creates the processor with [config].
  SelfSigningTreeProcessor([super.config]);

  @override
  Object? process(Document document) {
    document <<
        createParagraph(document, runtimeType.toString(), <String, Object?>{});
    return null;
  }
}

/// Strips attributes from tags (port of `StripAttributesPostprocessor`).
class StripAttributesPostprocessor extends Postprocessor {
  /// Creates the processor with [config].
  StripAttributesPostprocessor([super.config]);

  @override
  Object? process(Document document, String output) {
    return output.replaceAllMapped(
      RegExp(r'<(\w+).*?>', multiLine: true, dotAll: true),
      (match) => '<${match.group(1)}>',
    );
  }
}

/// Uppercase block (port of `UppercaseBlock`).
///
/// Ruby's class-level DSL (`named`, `on_context`,
/// `name_positional_attributes`, `parse_content_as`) becomes constructor
/// defaults (see the `extensions.dart` library docs).
class UppercaseBlock extends BlockProcessor {
  /// Creates the block processor with [name] and [config].
  UppercaseBlock([String? name, Map<String, Object?>? config])
    : super(name, {
        'name': 'yell',
        'contexts': {'paragraph'},
        'positional_attrs': ['chars'],
        'content_model': 'simple',
        ...?config,
      });

  @override
  Object? process(
    AbstractBlock parent,
    Reader reader,
    Map<String, Object?> attributes,
  ) {
    final chars = attributes['chars'] as String?;
    if (chars != null) {
      final upcaseChars = chars.toUpperCase();
      final lines = reader.lines.map((line) {
        return line!.toLowerCase().split('').map((char) {
          final index = chars.indexOf(char);
          return index == -1 ? char : upcaseChars[index];
        }).join();
      }).toList();
      return createParagraph(parent, lines, attributes);
    }
    return createParagraph(
      parent,
      reader.lines.map((line) => line!.toUpperCase()).toList(),
      attributes,
    );
  }
}

/// Script snippet block macro (port of `SnippetMacro`).
class SnippetMacro extends BlockMacroProcessor {
  /// Creates the macro processor with [name] and [config].
  SnippetMacro([super.name, super.config]);

  @override
  Object? process(
    AbstractBlock parent,
    String target,
    Map<Object, Object?> attributes,
  ) {
    return createPassBlock(
      parent,
      '<script src="http://example.com/$target.js?_mode=${attributes['mode']}"></script>',
      <String, Object?>{},
      contentModel: 'raw',
    );
  }
}

/// Block macro using the legacy `:pos_attrs` option (port of
/// `LegacyPosAttrsBlockMacro`).
class LegacyPosAttrsBlockMacro extends BlockMacroProcessor {
  /// Creates the macro processor with [name] and [config].
  LegacyPosAttrsBlockMacro([String? name, Map<String, Object?>? config])
    : super(name, {
        'pos_attrs': ['target', 'format'],
        ...?config,
      });

  @override
  Object? process(
    AbstractBlock parent,
    String target,
    Map<Object, Object?> attributes,
  ) {
    return createImageBlock(parent, {
      'target': "${attributes['target']}.${attributes['format']}",
    });
  }
}

/// Temperature inline macro (port of `TemperatureMacro`).
class TemperatureMacro extends InlineMacroProcessor {
  /// Creates the macro processor with [name] and [config].
  TemperatureMacro([super.name, super.config]) {
    name ??= 'degrees';
    resolveAttributes(['1:units', 'precision=1']);
  }

  @override
  Object? process(
    AbstractBlock parent,
    String target,
    Map<Object, Object?> attributes,
  ) {
    final document = parent.document! as Document;
    final units =
        attributes['units'] as String? ??
        document.attr('temperature-unit', 'C') as String;
    final precision = int.parse(attributes['precision'].toString());
    final c = double.parse(target);
    switch (units) {
      case 'C':
        return createInline(
          parent,
          'quoted',
          '${c.toStringAsFixed(precision)} &#176;C',
          type: 'unquoted',
        );
      case 'F':
        return createInline(
          parent,
          'quoted',
          '${(c * 1.8 + 32).toStringAsFixed(precision)} &#176;F',
          type: 'unquoted',
        );
      default:
        throw ArgumentError('Unknown temperature units: $units');
    }
  }
}

/// Robots docinfo processor (port of `MetaRobotsDocinfoProcessor`).
class MetaRobotsDocinfoProcessor extends DocinfoProcessor {
  /// Creates the processor with [config].
  MetaRobotsDocinfoProcessor([super.config]);

  @override
  Object? process(Document document) =>
      '<meta name="robots" content="index,follow">';
}

/// Application-name docinfo processor (port of `MetaAppDocinfoProcessor`).
class MetaAppDocinfoProcessor extends DocinfoProcessor {
  /// Creates the processor with [config].
  MetaAppDocinfoProcessor([super.config]) {
    atLocation('head');
  }

  @override
  Object? process(Document document) =>
      '<meta name="application-name" content="Asciidoctor App">';
}

/// Sample extension group (port of `SampleExtensionGroup`).
class SampleExtensionGroup extends ExtensionGroup {
  /// Self-registers this group under [name] (port of `Group.register`).
  static Object? register([String? name]) =>
      Extensions.register(name: name, group: SampleExtensionGroup.new);

  @override
  void activate(Registry registry) {
    registry.document!.attributes['activate-method-called'] = '';
    registry.preprocessor(processor: SamplePreprocessor.new);
  }
}

/// Standalone `cat_in_sink` block macro registry (port of
/// `create_cat_in_sink_block_macro`).
Registry createCatInSinkBlockMacro() {
  return Extensions.create(
    build: (registry) {
      registry.blockMacro(
        build: (processor) {
          processor.named('cat_in_sink');
          processor.onProcess =
              (
                AbstractBlock parent,
                String? target,
                Map<Object, Object?> attrs,
              ) {
                final imageAttrs = <String, Object?>{};
                if (target != null && target.isNotEmpty) {
                  imageAttrs['target'] = 'cat-in-sink-day-$target.png';
                }
                final title = attrs.remove('title');
                if (title != null) imageAttrs['title'] = title;
                final alt = attrs.remove(1);
                if (alt != null) imageAttrs['alt'] = alt;
                return processor.createImageBlock(parent, imageAttrs);
              };
        },
      );
    },
  );
}

/// Standalone `santa_list` block macro registry (port of
/// `create_santa_list_block_macro`).
Registry createSantaListBlockMacro() {
  return Extensions.create(
    build: (registry) {
      registry.blockMacro(
        build: (processor) {
          processor.named('santa_list');
          // Adapted: Ruby blocks tolerate the unused third argument;
          // Dart closures must declare it.
          processor.onProcess =
              (AbstractBlock parent, String target, Map<Object, Object?> _) {
                final list = processor.createList(parent, target);
                final guillaume = processor.createListItem(list, 'Guillaume');
                guillaume.addRole('friendly');
                guillaume.id = 'santa-list-guillaume';
                list << guillaume;
                final robert = processor.createListItem(list, 'Robert');
                robert.addRole('kind');
                robert.addRole('contributor');
                robert.addRole('java');
                list << robert;
                final pepijn = processor.createListItem(list, 'Pepijn');
                pepijn.id = 'santa-list-pepijn';
                list << pepijn;
                final dan = processor.createListItem(list, 'Dan');
                dan.addRole('naughty');
                dan.id = 'santa-list-dan';
                list << dan;
                final sarah = processor.createListItem(list, 'Sarah');
                list << sarah;
                return list;
              };
        },
      );
    },
  );
}

void main() {
  // String class-name registrations resolve through these factories (the
  // Dart counterpart of Ruby constant lookup).
  Extensions.registerGroupFactory(
    'SampleExtensionGroup',
    SampleExtensionGroup.new,
  );
  Extensions.registerProcessorFactory(
    'SamplePreprocessor',
    (config) => SamplePreprocessor(config),
  );

  // Explicit global-state reset between tests (mirrors Ruby's
  // `unregister_all` teardown, including groups).
  tearDown(Extensions.unregisterAll);

  group('Register', () {
    test(
      'should not activate registry if no extension groups are registered',
      () {
        final doc = emptyDocument();
        // No extension groups are registered, so the document carries no
        // registry.
        expect(doc.extensions, isNull);
      },
    );

    test('should register extension group factory', () {
      // Adapted: Dart passes a factory where Ruby passes the class.
      Extensions.register(name: 'sample', group: SampleExtensionGroup.new);
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups['sample'], isA<Function>());
    });

    test('should self register extension group class', () {
      SampleExtensionGroup.register('sample');
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups['sample'], isA<Function>());
    });

    test('should register extension group from class name', () {
      Extensions.register(name: 'sample', group: 'SampleExtensionGroup');
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups['sample'], isA<Function>());
    });

    test('should register extension group from instance', () {
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups['sample'], isA<SampleExtensionGroup>());
    });

    test('should register extension block', () {
      Extensions.register(
        name: 'sample',
        build: (registry) {
          // this space intentionally left blank
        },
      );
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups['sample'], isA<Function>());
    });

    test('should keep group name as string when registering', () {
      // Adapted: Dart group names are always strings (no symbol coercion).
      Extensions.register(name: 'sample', group: SampleExtensionGroup.new);
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups.keys.single, equals('sample'));
    });

    test('should unregister extension group by name', () {
      // Merged: Ruby's symbol-name and string-name variants are one form
      // in Dart.
      Extensions.register(name: 'sample', group: SampleExtensionGroup.new);
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      Extensions.unregister(['sample']);
      expect(Extensions.groups.length, equals(0));
    });

    test('should unregister multiple extension groups by name', () {
      Extensions.register(name: 'sample1', group: SampleExtensionGroup.new);
      Extensions.register(name: 'sample2', group: SampleExtensionGroup.new);
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(2));
      Extensions.unregister(['sample1', 'sample2']);
      expect(Extensions.groups.length, equals(0));
    });

    test('should not fail to unregister extension group if not registered', () {
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(0));
      Extensions.unregister(['sample']);
      expect(Extensions.groups.length, equals(0));
    });

    // NOTE the Ruby test 'should not fail to unregister extension group
    // if extension groups are not initialized' is dropped: Ruby removes the
    // @groups ivar, which cannot occur in Dart (statics are always
    // initialized); the neighboring test covers the scenario's essence.
    test('should raise ArgumentError if extension class cannot be resolved '
        'from string', () {
      // Adapted: the registry is activated manually; Dart raises
      // ArgumentError carrying Ruby's message.
      Extensions.register(
        build: (registry) {
          registry.block(processor: 'foobar');
        },
      );
      expect(
        () => Registry().activate(emptyDocument()),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            'Could not resolve class for name: foobar',
          ),
        ),
      );
    });

    test(
      'should allow standalone registry to be created but not registered',
      () {
        final registry = Extensions.create(
          name: 'sample',
          build: (registry) {
            registry.block(
              build: (processor) {
                processor.named('whisper');
                processor.onContext('paragraph');
                processor.parseContentAs('simple');
                processor.onProcess =
                    (
                      AbstractBlock parent,
                      Reader reader,
                      Map<String, Object?> attributes,
                    ) {
                      return processor.createParagraph(
                        parent,
                        reader.lines
                            .map((line) => line!.toLowerCase())
                            .toList(),
                        attributes,
                      );
                    };
              },
            );
          },
        );

        expect(registry, isA<Registry>());
        expect(registry.runtimeType, equals(Registry));
        expect(registry.groups, isNotNull);
        expect(registry.groups.length, equals(1));
        expect(registry.groups.keys.first, equals('sample'));
        expect(Extensions.groups.length, equals(0));
      },
    );

    test('should generate automatic group names', () {
      final first = Extensions.generateName();
      final second = Extensions.generateName();
      expect(first, matches(RegExp(r'^extgrp\d+$')));
      expect(second, matches(RegExp(r'^extgrp\d+$')));
      expect(first, isNot(equals(second)));
    });

    test('should raise ArgumentError when registering without a group', () {
      expect(
        () => Extensions.register(),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            'Extension group to register not specified',
          ),
        ),
      );
    });
  });

  group('Activate', () {
    test('should call activate on extension group factory', () {
      // Adapted: Dart passes a factory where Ruby passes the class.
      final doc = emptyDocument();
      Extensions.register(name: 'sample', group: SampleExtensionGroup.new);
      final registry = Registry();
      registry.activate(doc);
      expect(doc.hasAttr('activate-method-called'), isTrue);
      expect(registry.hasPreprocessors, isTrue);
    });

    test('should reset registry if activate is called again', () {
      Extensions.register(name: 'sample', group: SampleExtensionGroup.new);
      var doc = emptyDocument();
      final registry = Registry();
      registry.activate(doc);
      expect(doc.hasAttr('activate-method-called'), isTrue);
      expect(registry.hasPreprocessors, isTrue);
      expect(registry.preprocessors.length, equals(1));
      expect(registry.document, same(doc));
      doc = emptyDocument();
      registry.activate(doc);
      expect(doc.hasAttr('activate-method-called'), isTrue);
      expect(registry.hasPreprocessors, isTrue);
      expect(registry.preprocessors.length, equals(1));
      expect(registry.document, same(doc));
    });

    test('should invoke extension block', () {
      final doc = emptyDocument();
      Extensions.register(
        build: (registry) {
          registry.document!.attributes['block-called'] = '';
          registry.preprocessor(processor: SamplePreprocessor.new);
        },
      );
      final registry = Registry();
      registry.activate(doc);
      expect(doc.hasAttr('block-called'), isTrue);
      expect(registry.hasPreprocessors, isTrue);
    });

    test('should create registry in Document if extensions are loaded', () {
      SampleExtensionGroup.register();
      final doc = emptyDocument();
      expect(doc.extensions, isNotNull);
      expect(doc.extensions, isA<Registry>());
    });
  });

  group('Instantiate', () {
    test('should instantiate preprocessors', () {
      final registry = Registry();
      registry.preprocessor(processor: SamplePreprocessor.new);
      registry.activate(emptyDocument());
      expect(registry.hasPreprocessors, isTrue);
      final extensions = registry.preprocessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SamplePreprocessor>());
      expect(extensions.first.processMethod, isA<Function>());
    });

    test('should instantiate include processors', () {
      final registry = Registry();
      registry.includeProcessor(processor: SampleIncludeProcessor.new);
      registry.activate(emptyDocument());
      expect(registry.hasIncludeProcessors, isTrue);
      final extensions = registry.includeProcessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SampleIncludeProcessor>());
      // Adapted: Ruby adapts the single-argument legacy `handles?` here;
      // Dart always uses the two-argument form (see
      // [IncludeProcessor.onHandles]).
      final instance = extensions.first.instance as SampleIncludeProcessor;
      expect(instance.onHandles, isNull);
      expect(
        instance.handles(FakeReaderDocument(emptyDocument()), 'include.adoc'),
        isTrue,
      );
      expect(extensions.first.processMethod, isA<Function>());
    });

    test('should instantiate docinfo processors', () {
      final registry = Registry();
      registry.docinfoProcessor(processor: SampleDocinfoProcessor.new);
      registry.activate(emptyDocument());
      expect(registry.hasDocinfoProcessors(), isTrue);
      expect(registry.hasDocinfoProcessors('head'), isTrue);
      final extensions = registry.docinfoProcessors();
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SampleDocinfoProcessor>());
      expect(extensions.first.processMethod, isA<Function>());
    });

    test('should instantiate tree processors', () {
      // NOTE intentionally using the legacy names.
      final registry = Registry();
      // ignore: deprecated_member_use
      registry.treeprocessor(processor: SampleTreeprocessor.new);
      registry.activate(emptyDocument());
      // ignore: deprecated_member_use
      expect(registry.hasTreeprocessors, isTrue);
      // ignore: deprecated_member_use
      final extensions = registry.treeprocessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SampleTreeprocessor>());
      expect(extensions.first.processMethod, isA<Function>());
    });

    test('should instantiate postprocessors', () {
      final registry = Registry();
      registry.postprocessor(processor: SamplePostprocessor.new);
      registry.activate(emptyDocument());
      expect(registry.hasPostprocessors, isTrue);
      final extensions = registry.postprocessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SamplePostprocessor>());
      expect(extensions.first.processMethod, isA<Function>());
    });

    test('should instantiate block processor', () {
      final registry = Registry();
      registry.block(processor: SampleBlock.new, name: 'sample');
      registry.activate(emptyDocument());
      expect(registry.hasBlocks, isTrue);
      expect(
        registry.registeredForBlock('sample', 'paragraph'),
        isA<ProcessorExtension>(),
      );
      final extension = registry.findBlockExtension('sample');
      expect(extension, isA<ProcessorExtension>());
      expect(extension!.instance, isA<SampleBlock>());
      expect(extension.processMethod, isA<Function>());
    });

    test('should not match block processor for unsupported context', () {
      final registry = Registry();
      registry.block(processor: SampleBlock.new, name: 'sample');
      registry.activate(emptyDocument());
      expect(registry.registeredForBlock('sample', 'sidebar'), isNull);
    });

    test('should instantiate block macro processor', () {
      final registry = Registry();
      registry.blockMacro(processor: SampleBlockMacro.new, name: 'sample');
      registry.activate(emptyDocument());
      expect(registry.hasBlockMacros, isTrue);
      expect(
        registry.registeredForBlockMacro('sample'),
        isA<ProcessorExtension>(),
      );
      final extension = registry.findBlockMacroExtension('sample');
      expect(extension, isA<ProcessorExtension>());
      expect(extension!.instance, isA<SampleBlockMacro>());
      expect(extension.processMethod, isA<Function>());
    });

    test('should instantiate inline macro processor', () {
      final registry = Registry();
      registry.inlineMacro(processor: SampleInlineMacro.new, name: 'sample');
      registry.activate(emptyDocument());
      expect(registry.hasInlineMacros, isTrue);
      expect(
        registry.registeredForInlineMacro('sample'),
        isA<ProcessorExtension>(),
      );
      final extension = registry.findInlineMacroExtension('sample');
      expect(extension, isA<ProcessorExtension>());
      expect(extension!.instance, isA<SampleInlineMacro>());
      expect(extension.processMethod, isA<Function>());
    });

    test('should allow processors to be registered by a string name', () {
      final registry = Registry();
      registry.preprocessor(processor: 'SamplePreprocessor');
      registry.activate(emptyDocument());
      expect(registry.hasPreprocessors, isTrue);
      final extensions = registry.preprocessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
    });
  });

  group('Integration', () {
    test(
      'does not crash when querying for extensions if none are registered',
      () {
        // Adapted: the registry is activated manually.
        final registry = Extensions.create();
        final doc = emptyDocument();
        registry.activate(doc);
        expect(doc, isNotNull);
        expect(registry.registeredForBlock('unknown', 'paragraph'), isNull);
        expect(registry.findBlockExtension('unknown'), isNull);
        expect(registry.registeredForBlockMacro('unknown'), isNull);
        expect(registry.findBlockMacroExtension('unknown'), isNull);
        expect(registry.registeredForInlineMacro('unknown'), isNull);
        expect(registry.findInlineMacroExtension('unknown'), isNull);
        expect(registry.inlineMacros, isEmpty);
      },
    );

    test('can provide extension registry as an option', () {
      final registry = Extensions.create(
        build: (r) {
          r.treeProcessor(processor: SampleTreeProcessor.new);
        },
      );

      final doc = documentFromString('= Document Title\n\ncontent', {
        'extension_registry': registry,
      });
      expect(doc.extensions, isNotNull);
      final exts = doc.extensions!;
      expect(exts.groups.length, equals(1));
      expect(exts.hasTreeProcessors, isTrue);
      expect(exts.treeProcessors.length, equals(1));
      expect(Extensions.groups.length, equals(0));
    });

    test(
      'can provide extension registry created without any groups as option',
      () {
        final registry = Extensions.create();
        registry.treeProcessor(processor: SampleTreeProcessor.new);

        final doc = documentFromString('= Document Title\n\ncontent', {
          'extension_registry': registry,
        });
        expect(doc.extensions, isNotNull);
        final exts = doc.extensions!;
        expect(exts.groups.length, equals(0));
        expect(exts.hasTreeProcessors, isTrue);
        expect(exts.treeProcessors.length, equals(1));
        expect(Extensions.groups.length, equals(0));
      },
    );

    test('can provide extensions proc as option', () {
      void extensions(Registry r) {
        r.treeProcessor(processor: SampleTreeProcessor.new);
      }

      final doc = documentFromString('= Document Title\n\ncontent', {
        'extensions': extensions,
      });
      expect(doc.extensions, isNotNull);
      final exts = doc.extensions!;
      expect(exts.groups.length, equals(1));
      expect(exts.hasTreeProcessors, isTrue);
      expect(exts.treeProcessors.length, equals(1));
      expect(Extensions.groups.length, equals(0));
    });

    test(
      'should not activate global registry if extensions option is false',
      () {
        Extensions.register(
          name: 'sample',
          build: (registry) {
            // this space intentionally left blank
          },
        );
        expect(Extensions.groups, isNotNull);
        expect(Extensions.groups.length, equals(1));
        final doc = emptyDocument({'extensions': false});
        expect(doc.extensions, isNull);
      },
    );

    test('should invoke preprocessors before parsing document', () {
      const input = 'junk line\n\n= Document Title\n\nsample content\n';

      Extensions.register(
        build: (registry) {
          registry.preprocessor(processor: ScrubHeaderPreprocessor.new);
        },
      );

      final doc = documentFromString(input);
      expect(doc.hasAttr('skipped'), isTrue);
      expect((doc.attr('skipped') as String).trim(), equals('junk line'));
      expect(doc.hasHeader, isTrue);
      expect(doc.doctitle(), equals('Document Title'));
    });

    test('should invoke include processor to process include directive', () {
      const input = 'before\n\ninclude::lorem-ipsum.txt[]\n\nafter\n';

      Extensions.register(
        build: (registry) {
          registry.includeProcessor(
            processor: BoilerplateTextIncludeProcessor.new,
          );
        },
      );

      // a custom include processor is not affected by the safe mode
      final result = convertString(input, {'safe': 'secure'});
      assertCss('.paragraph > p', result, 3);
      expect(result, contains('before'));
      expect(result, contains('Lorem ipsum'));
      expect(result, contains('after'));
    });

    test('should invoke include processor through the preprocessor reader', () {
      // Adapted headless port of 'should invoke include processor if it
      // requests to handle include directive': the reader is driven with a
      // delegating document fake because the real document adapter exposes
      // no include processors yet. The file-fixture tail of the Ruby test
      // (grandchild include) is dropped until the fixture wave.
      const input =
          'include::skip-me.adoc[]\n'
          'line after skip\n'
          '\n'
          'include::include-file.adoc[]\n'
          '\n'
          'last line\n';

      final registry = Extensions.create(
        build: (r) {
          r.includeProcessor(
            build: (processor) {
              // test onHandles assigned as callback
              processor.onHandles = (doc, target) => target == 'skip-me.adoc';
              processor.onProcess = (
                ReaderDocument doc,
                PreprocessorReader reader,
                String target,
                Map<Object, String?> attributes,
              ) => null;
            },
          );

          r.includeProcessor(
            build: (processor) {
              processor.onHandles = (doc, target) =>
                  target == 'include-file.adoc';
              processor.onProcess =
                  (
                    ReaderDocument doc,
                    PreprocessorReader reader,
                    String target,
                    Map<Object, String?> attributes,
                  ) {
                    // demonstrates that pushInclude normalizes newlines
                    final content = [
                      "found include target '$target' at line "
                          '${reader.cursorAtPrevLine().lineno}\r\n',
                      '\r\n',
                      'middle line\r\n',
                    ];
                    reader.pushInclude(content, target, target, 1, attributes);
                    return null;
                  };
            },
          );
        },
      );
      final document = emptyDocument({'safe': 'safe'});
      registry.activate(document);
      final fake = FakeReaderDocument(
        document,
        registry.includeProcessors
            .map((ext) => ext.instance as IncludeProcessor)
            .toList(),
      );
      final reader = PreprocessorReader(fake, input, null, true);
      final lines = <String?>[];
      lines.add(reader.readLine());
      expect(lines.last, equals('line after skip'));
      lines.add(reader.readLine());
      lines.add(reader.readLine());
      expect(
        lines.last,
        equals("found include target 'include-file.adoc' at line 4"),
      );
      expect(reader.lineInfo, equals('include-file.adoc: line 2'));
      while (reader.hasMoreLines()) {
        lines.add(reader.readLine());
      }
      final source = lines.join('\n');
      expect(
        source,
        matches(
          RegExp(
            r"^found include target 'include-file\.adoc' at line 4$",
            multiLine: true,
          ),
        ),
      );
      expect(source, matches(RegExp(r'^middle line$', multiLine: true)));
      expect(source, matches(RegExp(r'^last line$', multiLine: true)));
    });

    test('should invoke include processor with shared state across calls', () {
      // Adapted headless port of 'should invoke include processor if it
      // requests to handle include directive using legacy method': Dart
      // has no single-argument legacy handles form, so the two-argument
      // callback is used; the shared content cache becomes a captured
      // local.
      const input =
          'include::include-file.adoc[]\ninclude::include-file.adoc[]';
      final contentCache = <String, String>{};

      final registry = Extensions.create(
        build: (r) {
          r.includeProcessor(
            build: (processor) {
              processor.onHandles = (doc, target) =>
                  target == 'include-file.adoc';
              processor.onProcess =
                  (
                    ReaderDocument doc,
                    PreprocessorReader reader,
                    String target,
                    Map<Object, String?> attributes,
                  ) {
                    final content = contentCache.putIfAbsent(
                      'include-file.adoc',
                      () => 'contents of include-file.adoc',
                    );
                    reader.pushInclude(content, target, target, 1, attributes);
                    return null;
                  };
            },
          );
        },
      );
      final document = emptyDocument({'safe': 'safe'});
      registry.activate(document);
      final fake = FakeReaderDocument(
        document,
        registry.includeProcessors
            .map((ext) => ext.instance as IncludeProcessor)
            .toList(),
      );
      final reader = PreprocessorReader(fake, input, null, true);
      final lines = <String?>[];
      lines.add(reader.readLine());
      lines.add(reader.readLine());
      expect(lines.last, equals('contents of include-file.adoc'));
      expect(contentCache.length, equals(1));
      expect(contentCache['include-file.adoc'], equals(lines.last));
    });

    test('should invoke tree processors after parsing document', () {
      const input = '= Document Title\nDoc Writer\n\ncontent\n';

      Extensions.register(
        build: (registry) {
          registry.treeProcessor(processor: ReplaceAuthorTreeProcessor.new);
        },
      );

      final doc = documentFromString(input);
      expect(doc.author, equals('Ghost Writer'));
    });

    test(
      'should set source_location on document before invoking tree processors',
      () {
        Extensions.register(
          build: (registry) {
            registry.treeProcessor(
              build: (processor) {
                processor.onProcess = (Document doc) {
                  final para = processor.createParagraph(
                    doc.blocks.last.parent!,
                    'file: ${doc.file}, lineno: ${doc.lineno}',
                    <String, Object?>{},
                  );
                  doc << para;
                  return null;
                };
              },
            );
          },
        );

        final sampleDoc = fixturePath('sample.adoc');
        final doc = loadFile(sampleDoc, sourcemap: true);
        expect(
          doc.convert() as String,
          contains('file: sample.adoc, lineno: 1'),
        );
      },
    );

    test('should allow tree processor to replace tree', () {
      const input = '= Original Document\nDoc Writer\n\ncontent\n';

      Extensions.register(
        build: (registry) {
          registry.treeProcessor(processor: ReplaceTreeTreeProcessor.new);
        },
      );

      final doc = documentFromString(input);
      expect(doc.doctitle(), equals('Replacement Document'));
    });

    test('should honor block title assigned in tree processor', () {
      const input =
          '= Document Title\n'
          ':!example-caption:\n'
          '\n'
          '.Old block title\n'
          '====\n'
          'example block content\n'
          '====\n';

      String? oldTitle;
      Extensions.register(
        build: (registry) {
          registry.treeProcessor(
            build: (processor) {
              processor.onProcess = (Document doc) {
                final ex = doc.findBy(context: 'example')[0];
                oldTitle = ex.title;
                ex.title = 'New block title';
                return null;
              };
            },
          );
        },
      );

      final doc = documentFromString(input);
      expect(oldTitle, equals('Old block title'));
      expect(
        doc.findBy(context: 'example')[0].title,
        equals('New block title'),
      );
    });

    test('should be able to register preferred tree processor', () {
      // Adapted: the registry is activated manually and the process
      // methods are invoked in registry order (no parse/convert).
      Extensions.register(
        build: (registry) {
          registry.treeProcessor(
            build: (processor) {
              processor.onProcess = (Document doc) {
                doc << processor.createParagraph(doc, 'd', <String, Object?>{});
                return null;
              };
            },
          );

          registry.treeProcessor(
            build: (processor) {
              processor.prefer();
              processor.onProcess = (Document doc) {
                doc << processor.createParagraph(doc, 'c', <String, Object?>{});
                return null;
              };
            },
          );

          registry.prefer(
            'tree_processor',
            build: (TreeProcessor processor) {
              processor.onProcess = (Document doc) {
                doc << processor.createParagraph(doc, 'b', <String, Object?>{});
                return null;
              };
            },
          );

          registry.prefer(
            registry.treeProcessor(
              build: (processor) {
                processor.onProcess = (Document doc) {
                  doc <<
                      processor.createParagraph(doc, 'a', <String, Object?>{});
                  return null;
                };
              },
            ),
          );

          registry.prefer(
            'tree_processor',
            processor: SelfSigningTreeProcessor.new,
          );
        },
      );

      final doc = emptyDocument();
      final registry = Registry();
      registry.activate(doc);
      for (final ext in registry.treeProcessors) {
        (ext.processMethod as Object? Function(Document))(doc);
      }
      expect(
        doc.blocks.map((block) => (block as Block).lines.first).toList(),
        equals(['SelfSigningTreeProcessor', 'a', 'b', 'c', 'd']),
      );
    });

    test('should invoke postprocessors after converting document', () {
      const input = '* one\n* two\n* three\n';

      Extensions.register(
        build: (registry) {
          registry.postprocessor(processor: StripAttributesPostprocessor.new);
        },
      );

      final output = convertString(input);
      expect(output, isNot(contains('<div class="ulist">')));
    });

    test(
      'should yield to document processor block if block has non-zero arity',
      () {
        const input = 'hi!\n';

        Extensions.register(
          build: (registry) {
            // Adapted: the callback always receives the processor in Dart.
            registry.treeProcessor(
              build: (processor) {
                processor.onProcess = (Document doc) {
                  doc <<
                      processor.createParagraph(
                        doc,
                        'bye!',
                        <String, Object?>{},
                      );
                  return null;
                };
              },
            );
          },
        );

        final output = convertStringToEmbedded(input);
        assertXpath('//p', output, 2);
        assertXpath('//p[text()="hi!"]', output, 1);
        assertXpath('//p[text()="bye!"]', output, 1);
      },
    );

    test('should invoke processor for custom block', () {
      const input = '[yell]\nHi there!\n\n[yell,chars=aeiou]\nHi there!\n';

      Extensions.register(
        build: (registry) {
          registry.block(processor: UppercaseBlock.new);
        },
      );

      final output = convertStringToEmbedded(input);
      assertXpath('//p', output, 2);
      assertXpath('(//p)[1][text()="HI THERE!"]', output, 1);
      assertXpath('(//p)[2][text()="hI thErE!"]', output, 1);
    });

    test(
      'should invoke processor for custom block in an AsciiDoc table cell',
      () {
        const input = '|===\na|\n[yell]\nHi there!\n|===\n';

        Extensions.register(
          build: (registry) {
            registry.block(processor: UppercaseBlock.new);
          },
        );

        final output = convertStringToEmbedded(input);
        assertXpath('/table//p', output, 1);
        assertXpath('/table//p[text()="HI THERE!"]', output, 1);
      },
    );

    test(
      'should yield to syntax processor block if block has non-zero arity',
      () {
        const input = "[eval]\n....\n'yolo' * 5\n....\n";

        Extensions.register(
          build: (registry) {
            registry.block(
              name: 'eval',
              build: (processor) {
                processor.onContext('literal');
                processor.onProcess =
                    (
                      AbstractBlock parent,
                      Reader reader,
                      Map<String, Object?> attrs,
                    ) {
                      // Adapted: Dart has no eval; emulate the intent.
                      final source = reader.readLines()[0]!;
                      final expanded = source.contains('*')
                          ? List.filled(5, 'yolo').join()
                          : source;
                      return processor.createParagraph(
                        parent,
                        expanded,
                        <String, Object?>{},
                      );
                    };
              },
            );
          },
        );

        final output = convertStringToEmbedded(input);
        assertXpath('//p[text()="yoloyoloyoloyoloyolo"]', output, 1);
      },
    );

    test('should pass cloaked context in attributes passed to process method '
        'of custom block', () {
      const input = '[custom]\n****\nsidebar\n****\n';

      String? cloakedContext;
      Extensions.register(
        build: (registry) {
          registry.block(
            name: 'custom',
            build: (processor) {
              processor.onContext('sidebar');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    cloakedContext = attrs['cloaked-context'] as String?;
                    return null;
                  };
            },
          );
        },
      );

      convertStringToEmbedded(input);
      expect(cloakedContext, equals('sidebar'));
    });

    test('should allow extension to promote paragraph to compound block', () {
      const input = '[ex]\nexample\n';
      Extensions.register(
        build: (registry) {
          registry.block(
            name: 'ex',
            build: (processor) {
              processor.onContext('paragraph');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    return processor.createExampleBlock(
                      parent,
                      reader.readLines(),
                      <String, Object?>{},
                      contentModel: 'compound',
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded(input);
      assertCss('.exampleblock .paragraph', output, 1);
    });

    test('should invoke processor for custom block macro', () {
      const input = 'snippet::12345[mode=edit]';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SnippetMacro.new, name: 'snippet');
        },
      );

      final output = convertStringToEmbedded(input);
      expect(
        output,
        contains(
          '<script src="http://example.com/12345.js?_mode=edit"></script>',
        ),
      );
    });

    test('should not parse attributes on custom block macro when resolve '
        'attributes is false', () {
      const input = 'log::[hello, world!]';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            name: 'log',
            build: (processor) {
              processor.resolveAttributes(false);
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    parent.logger.info(attrs['text']);
                    return null;
                  };
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded(input);
        expect(output, isEmpty);
        assertMessage(logger, 'INFO', 'hello, world!');
      });
    });

    test('should not parse attributes on custom block macro when content model '
        'is text', () {
      const input = 'log::[hello, world!]';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            name: 'log',
            build: (processor) {
              processor.contentModel('text');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    parent.logger.info(attrs['text']);
                    return null;
                  };
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded(input);
        expect(output, isEmpty);
        assertMessage(logger, 'INFO', 'hello, world!');
      });
    });

    test('should substitute attributes in target of custom block macro', () {
      const input = 'snippet::{gist-id}[mode=edit]';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SnippetMacro.new, name: 'snippet');
        },
      );

      final output = convertStringToEmbedded(input, {
        'attributes': {'gist-id': '12345'},
      });
      expect(
        output,
        contains(
          '<script src="http://example.com/12345.js?_mode=edit"></script>',
        ),
      );
    });

    test('should log debug message if custom block macro is unknown', () {
      const input = 'unknown::[]';
      usingMemoryLogger((logger) {
        final result = convertStringToEmbedded(input);
        assertMessage(
          logger,
          'DEBUG',
          '<stdin>: line 1: unknown name for block macro: unknown',
        );
        assertXpath('/*[@class="paragraph"]/p[text()="$input"]', result, 1);
      }, 'DEBUG');
    });

    test('should log debug message if custom block macro is unknown when '
        'custom block macros are registered', () {
      const input = 'unknown::[]';
      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SampleBlockMacro.new, name: 'sample');
        },
      );
      usingMemoryLogger((logger) {
        final result = convertStringToEmbedded(input);
        assertMessage(
          logger,
          'DEBUG',
          '<stdin>: line 1: unknown name for block macro: unknown',
        );
        assertXpath('/*[@class="paragraph"]/p[text()="$input"]', result, 1);
      }, 'DEBUG');
    });

    test('should not log debug message if line is not a custom block macro '
        'and block macros are registered', () {
      const input = '* xref:component::page.adoc[link text]';
      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SampleBlockMacro.new, name: 'sample');
        },
      );
      usingMemoryLogger((logger) {
        final result = convertStringToEmbedded(input);
        expect(logger.messages, isEmpty);
        assertCss('ul li a[href="component::page.html"]', result, 1);
      }, 'DEBUG');
    });

    test('should drop block macro line if target references missing attribute '
        'and attribute-missing is drop-line', () {
      const input =
          '[.rolename]\n'
          'snippet::{gist-ns}12345[mode=edit]\n'
          '\n'
          'following paragraph\n';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SnippetMacro.new, name: 'snippet');
        },
      );

      late final Document doc;
      late final String output;
      usingMemoryLogger((logger) {
        doc = documentFromString(input, {
          'attributes': {'attribute-missing': 'drop-line'},
        });
        expect(doc.blocks.length, equals(1));
        expect(doc.blocks[0].context, equals('paragraph'));
        output = doc.convert() as String;
        assertMessage(
          logger,
          'INFO',
          'dropping line containing reference to missing attribute: gist-ns',
        );
      });
      assertCss('.paragraph', output, 1);
      assertCss('.rolename', output, 0);
    });

    test('should invoke processor for custom block macro in an AsciiDoc table '
        'cell', () {
      const input = '|===\na|message::hi[]\n|===\n';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            name: 'message',
            build: (processor) {
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createParagraph(
                      parent,
                      target.toUpperCase(),
                      <String, Object?>{},
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded(input);
      assertXpath('/table//p[text()="HI"]', output, 1);
    });

    test('should match short form of block macro', () {
      const input = 'custom-toc::[]';

      String? resolvedTarget;

      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            build: (processor) {
              processor.named('custom-toc');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    resolvedTarget = target;
                    return processor.createPassBlock(
                      parent,
                      '<!-- custom toc goes here -->',
                      <String, Object?>{},
                      contentModel: 'raw',
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded(input);
      expect(output, equals('<!-- custom toc goes here -->'));
      expect(resolvedTarget, equals(''));
    });

    test('should fail to register block macro with illegal name', () {
      // Adapted: the registry is activated manually; registration (during
      // activation) raises ArgumentError, like Ruby.
      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            build: (processor) {
              processor.named('illegal name');
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => null;
            },
          );
        },
      );

      expect(
        () => Registry().activate(emptyDocument()),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('invalid name for block macro'),
          ),
        ),
      );
    });

    test('should honor legacy pos_attrs option set via static method', () {
      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            processor: LegacyPosAttrsBlockMacro.new,
            name: 'diag',
          );
        },
      );

      final result = convertStringToEmbedded('diag::[filename,png]');
      assertCss('img[src="filename.png"]', result, 1);
    });

    test('should honor legacy pos_attrs option set via DSL', () {
      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            name: 'diag',
            build: (processor) {
              processor.option('pos_attrs', ['target', 'format']);
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createImageBlock(parent, {
                      'target': "${attrs['target']}.${attrs['format']}",
                    });
                  };
            },
          );
        },
      );

      final result = convertStringToEmbedded('diag::[filename,png]');
      assertCss('img[src="filename.png"]', result, 1);
    });

    test('should be able to set header attribute in block macro processor', () {
      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            build: (processor) {
              processor.named('attribute');
              processor.resolveAttributes('1:value');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    (parent.document! as Document).setAttr(
                      target,
                      attrs['value'],
                    );
                    return null;
                  };
            },
          );
          registry.blockMacro(
            build: (processor) {
              processor.named('header_attribute');
              processor.resolveAttributes('1:value');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    (parent.document! as Document).setHeaderAttribute(
                      target,
                      attrs['value'],
                    );
                    return null;
                  };
            },
          );
        },
      );
      const input = 'attribute::yin[yang]\n\nheader_attribute::foo[bar]\n';
      final doc = documentFromString(input);
      expect(doc.attr('yin'), isNull);
      expect(doc.attr('foo'), equals('bar'));
    });

    test('should invoke processor for custom inline macro', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(processor: TemperatureMacro.new, name: 'deg');
        },
      );

      var output = convertStringToEmbedded(
        'Room temperature is deg:25[C,precision=0].',
        {
          'attributes': {'temperature-unit': 'F'},
        },
      );
      expect(output, contains('Room temperature is 25 &#176;C.'));

      output = convertStringToEmbedded('Normal body temperature is deg:37[].', {
        'attributes': {'temperature-unit': 'F'},
      });
      expect(output, contains('Normal body temperature is 98.6 &#176;F.'));
    });

    test('should not parse attributes on custom inline macro when resolve '
        'attributes is false', () {
      const input = 'Line is del:[good]great.';

      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            name: 'del',
            build: (processor) {
              processor.matchFormat('short');
              processor.resolveAttributes(false);
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInline(
                      parent,
                      'quoted',
                      attrs['text'] as String?,
                      type: 'unquoted',
                      attributes: {'role': 'line-through'},
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded(input);
      expect(output, contains('<span class="line-through">good</span>'));
    });

    test('should not parse attributes on custom inline macro when content '
        'model is text', () {
      const input = 'Line is del:[good]great.';

      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            name: 'del',
            build: (processor) {
              processor.matchFormat('short');
              processor.contentModel('text');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInline(
                      parent,
                      'quoted',
                      attrs['text'] as String?,
                      type: 'unquoted',
                      attributes: {'role': 'line-through'},
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded(input);
      expect(output, contains('<span class="line-through">good</span>'));
    });

    test('should resolve regexp for inline macro lazily', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('label');
              processor.matchFormat('short');
              processor.parseContentAs('text');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      '<label>${attrs['text']}</label>',
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('label:[Checkbox]');
      expect(output, contains('<label>Checkbox</label>'));
    });

    test('should map unparsed attrlist to target when format is short', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('label');
              processor.matchFormat('short');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      '<label>$target</label>',
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('label:[Checkbox]');
      expect(output, contains('<label>Checkbox</label>'));
    });

    test('should parse text in square brackets as attrlist by default', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('json');
              processor.matchFormat('short');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    final pairs = attrs.entries
                        .map((entry) => '"${entry.key}": "${entry.value}"')
                        .join(', ');
                    return processor.createInlinePass(parent, '{ $pairs }');
                  };
            },
          );

          registry.inlineMacro(
            build: (processor) {
              processor.named('data');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    if (target != 'json') {
                      return null;
                    }
                    final pairs = attrs.entries
                        .map((entry) => '"${entry.key}": "${entry.value}"')
                        .join(', ');
                    return processor.createInlinePass(parent, '{ $pairs }');
                  };
            },
          );
        },
      );

      var output = convertStringToEmbedded('json:[a=A,b=B,c=C]', {
        'doctype': 'inline',
      });
      expect(output, equals('{ "a": "A", "b": "B", "c": "C" }'));
      output = convertStringToEmbedded('data:json[a=A,b=B,c=C]', {
        'doctype': 'inline',
      });
      expect(output, equals('{ "a": "A", "b": "B", "c": "C" }'));
    });

    test('should assign captures correctly for inline macros', () {
      Object? capture(
        InlineMacroProcessor processor,
        AbstractBlock parent,
        String? target,
        Map<Object, Object?> attrs,
      ) {
        final sorted = attrs.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
        return processor.createInlinePass(
          parent,
          'target=${target == null ? 'nil' : '"$target"'}, '
          'attributes={${sorted.map((entry) {
            final key = entry.key is String ? '"${entry.key}"' : entry.key;
            return '$key=>"${entry.value}"';
          }).join(', ')}}',
        );
      }

      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('short_attributes');
              processor.matchFormat('short');
              processor.resolveAttributes('1:name');
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => capture(processor, parent, target, attrs);
            },
          );

          registry.inlineMacro(
            build: (processor) {
              processor.named('short_text');
              processor.matchFormat('short');
              processor.resolveAttributes(false);
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => capture(processor, parent, target, attrs);
            },
          );

          registry.inlineMacro(
            build: (processor) {
              processor.named('full-attributes');
              processor.resolveAttributes({'1:name': null});
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => capture(processor, parent, target, attrs);
            },
          );

          registry.inlineMacro(
            build: (processor) {
              processor.named('full-text');
              processor.resolveAttributes(false);
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => capture(processor, parent, target, attrs);
            },
          );

          registry.inlineMacro(
            build: (processor) {
              processor.named('@short_match');
              processor.match(RegExp(r'@(\w+)'));
              processor.resolveAttributes(false);
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => capture(processor, parent, target, attrs);
            },
          );
        },
      );

      const input =
          '[subs=normal]\n'
          '++++\n'
          'short_attributes:[]\n'
          'short_attributes:[value,key=val]\n'
          'short_text:[]\n'
          'short_text:[[text\\]]\n'
          'full-attributes:target[]\n'
          'full-attributes:target[value,key=val]\n'
          'full-text:target[]\n'
          'full-text:target[[text\\]]\n'
          '@target\n'
          '++++\n';
      const expected =
          'target="",attributes={}\n'
          'target="value,key=val",attributes={1=>"value","key"=>"val","name"=>"value"}\n'
          'target="",attributes={"text"=>""}\n'
          'target="[text]",attributes={"text"=>"[text]"}\n'
          'target="target",attributes={}\n'
          'target="target",attributes={1=>"value","key"=>"val","name"=>"value"}\n'
          'target="target",attributes={"text"=>""}\n'
          'target="target",attributes={"text"=>"[text]"}\n'
          'target="target",attributes={}';
      final output = convertStringToEmbedded(input)
          .replaceAll(' => ', '=>')
          .replaceAll(', ', ',');
      expect(output, equals(expected));
    });

    test(
      'should invoke convert on return value if value is an inline node',
      () {
        Extensions.register(
          build: (registry) {
            registry.inlineMacro(
              build: (processor) {
                processor.named('mention');
                processor.resolveAttributes(false);
                processor.onProcess =
                    (
                      AbstractBlock parent,
                      String target,
                      Map<Object, Object?> attrs,
                    ) {
                      var text = attrs['text'] as String;
                      if (text.isEmpty) text = '@$target';
                      return processor.createAnchor(
                        parent,
                        text,
                        type: 'link',
                        target: 'https://github.com/$target',
                      );
                    };
              },
            );
          },
        );

        final output = convertStringToEmbedded('mention:mojavelinux[Dan]');
        expect(
          output,
          contains('<a href="https://github.com/mojavelinux">Dan</a>'),
        );
      },
    );

    test('should allow return value of inline macro to be nil', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('skipme');
              processor.matchFormat('short');
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => null;
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded('-skipme:[]-', {
          'doctype': 'inline',
        });
        expect(output, equals('--'));
        expect(logger.messages, isEmpty);
      });
    });

    test('should warn if return value of inline macro is a string', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('say');
              processor.onProcess = (
                AbstractBlock parent,
                String target,
                Map<Object, Object?> attrs,
              ) => target;
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded('say:yo[]', {
          'doctype': 'inline',
        });
        expect(output, equals('yo'));
        assertMessage(
          logger,
          'INFO',
          'expected substitution value for custom inline macro to be of '
              'type Inline; got String: say:yo[]',
        );
      });
    });

    test('should not apply subs to inline node returned by process method '
        'by default', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('say');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInline(
                      parent,
                      'quoted',
                      '*$target*',
                      type: 'emphasis',
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('say:yo[]', {'doctype': 'inline'});
      expect(output, equals('<em>*yo*</em>'));
    });

    test('should apply subs specified as symbol to inline node returned by '
        'process method', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('say');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      '*$target*',
                      attributes: {'subs': 'normal'},
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('say:yo[]', {'doctype': 'inline'});
      expect(output, equals('<strong>yo</strong>'));
    });

    test('should apply subs specified as array to inline node returned by '
        'process method', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('say');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      '*$target*',
                      attributes: {
                        'subs': ['specialchars', 'quotes'],
                      },
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('say:{lt}message{gt}[]', {
        'doctype': 'inline',
      });
      expect(output, equals('<strong>&lt;message&gt;</strong>'));
    });

    test('should apply subs specified as string to inline node returned by '
        'process method', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.named('say');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      '*$target*',
                      attributes: {'subs': 'specialchars,quotes'},
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('say:{lt}message{gt}[]', {
        'doctype': 'inline',
      });
      expect(output, equals('<strong>&lt;message&gt;</strong>'));
    });

    test('should prefer attributes parsed from inline macro over default '
        'attributes', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            name: 'attrs',
            build: (processor) {
              processor.matchFormat('short');
              processor.defaultAttributes({1: 'a', 2: 'b', 'foo': 'baz'});
              processor.positionalAttributes(['a', 'b']);
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      "a=${attrs['a']},2=${attrs[2]},"
                      "b=${attrs['b'] ?? 'nil'},foo=${attrs['foo']}",
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('attrs:[A,foo=bar]', {
        'doctype': 'inline',
      });
      // NOTE default attributes aren't considered when mapping positional
      // attributes
      expect(output, equals('a=A,2=b,b=nil,foo=bar'));
    });

    test('should coerce names of positional attributes to strings', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            name: 'attrs',
            build: (processor) {
              processor.matchFormat('short');
              // Adapted: names are strings in Dart (no symbols).
              processor.positionalAttributes(['a', 'b']);
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createInlinePass(
                      parent,
                      "a=${attrs['a']},b=${attrs['b']}",
                    );
                  };
            },
          );
        },
      );

      final output = convertStringToEmbedded('attrs:[A,B]', {
        'doctype': 'inline',
      });
      expect(output, equals('a=A,b=B'));
    });

    test('should not carry over attributes if block processor returns nil', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('skip-me');
              processor.onContext('paragraph');
              processor.parseContentAs('raw');
              processor.onProcess = (
                AbstractBlock parent,
                Reader reader,
                Map<String, Object?> attrs,
              ) => null;
            },
          );
        },
      );
      const input =
          '.unused title\n'
          '[skip-me]\n'
          'not shown\n'
          '\n'
          '--\n'
          'shown\n'
          '--\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks[0].attributes['title'], isNull);
    });

    test('should not invoke process method or carry over attributes if block '
        'processor declares skip content model', () {
      var processMethodCalled = false;
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('ignore');
              processor.onContext('paragraph');
              processor.parseContentAs('skip');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    processMethodCalled = true;
                    return null;
                  };
            },
          );
        },
      );
      const input =
          '.unused title\n'
          '[ignore]\n'
          'not shown\n'
          '\n'
          '--\n'
          'shown\n'
          '--\n';
      final doc = documentFromString(input);
      expect(processMethodCalled, isFalse);
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks[0].attributes['title'], isNull);
    });

    test('should pass attributes by value to block processor', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('foo');
              processor.onContext('paragraph');
              processor.parseContentAs('raw');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    final originalAttrs = Map<String, Object?>.of(attrs);
                    attrs.remove('title');
                    return processor.createParagraph(
                      parent,
                      reader.readLines(),
                      {...originalAttrs, 'id': 'value'},
                    );
                  };
            },
          );
        },
      );
      const input = '.title\n[foo]\ncontent\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks[0].attributes['title'], equals('title'));
      expect(doc.blocks[0].id, equals('value'));
    });

    test('should allow extension to replace custom block with a list', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('lst');
              processor.onContext('paragraph');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    final list = processor.createList(parent, 'ulist');
                    for (final line in reader.readLines()) {
                      list << processor.createListItem(list, line);
                    }
                    return list;
                  };
            },
          );
        },
      );
      const input = 'before\n\n[lst]\na\nb\nc\n\nafter\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(3));
      final list = doc.blocks[1] as ListBlock;
      expect(list.context, equals('ulist'));
      expect(list.items.length, equals(3));
      expect((list.items[0] as ListItem).text, equals('a'));
      assertCss('li', doc.convert() as String, 3);
    });

    test('should allow extension to replace custom block with a section', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('sect');
              processor.onContext('open');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    return processor.createSection(
                      parent,
                      attrs['title'] as String,
                      <String, Object?>{},
                    );
                  };
            },
          );
        },
      );
      const input =
          '.Section Title\n'
          '[sect]\n'
          '--\n'
          'a\n'
          '\n'
          'b\n'
          '--\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(1));
      final sect = doc.blocks[0] as Section;
      expect(sect.context, equals('section'));
      expect(sect.title, equals('Section Title'));
      expect(sect.blocks.length, equals(2));
      expect(sect.blocks[0].context, equals('paragraph'));
      expect(sect.blocks[1].context, equals('paragraph'));
      assertCss('p', doc.convert() as String, 2);
    });

    test('can use parse_content to append blocks to current parent', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('csv');
              processor.onContext('literal');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    processor.parseContent(parent, [
                      ',===',
                      ...reader.readLines().whereType<String>(),
                      ',===',
                    ]);
                    return null;
                  };
            },
          );
        },
      );
      const input = 'before\n\n[csv]\n....\na,b,c\n....\n\nafter\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(3));
      final table = doc.blocks[1];
      expect(table.context, equals('table'));
      assertCss('td', doc.convert() as String, 3);
    });

    test('should ignore return value of custom block if value is parent', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('unwrap');
              processor.onContext('open');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    return processor.parseContent(parent, reader.readLines());
                  };
            },
          );
        },
      );
      const input = '[unwrap]\n--\na\n\nb\n\nc\n--\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(3));
      for (final block in doc.blocks) {
        expect(block.context, equals('paragraph'));
      }
      expect((doc.blocks[0] as Block).source(), equals('a'));
      assertCss('p', doc.convert() as String, 3);
    });

    test(
      'should ignore return value of custom block macro if value is parent',
      () {
        Extensions.register(
          build: (registry) {
            registry.blockMacro(
              name: 'para',
              build: (processor) {
                processor.onProcess =
                    (
                      AbstractBlock parent,
                      String target,
                      Map<Object, Object?> attrs,
                    ) {
                      return processor.parseContent(parent, target);
                    };
              },
            );
          },
        );
        const input = 'para::text[]\n';
        final doc = documentFromString(input);
        expect(doc.blocks.length, equals(1));
        expect(doc.blocks[0].context, equals('paragraph'));
        expect((doc.blocks[0] as Block).source(), equals('text'));
        assertCss('p', doc.convert() as String, 1);
      },
    );

    test('parse_content should not share attributes between parsed blocks', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('wrap');
              processor.onContext('open');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    final wrap = processor.createOpenBlock(parent, null, attrs);
                    processor.parseContent(wrap, reader.readLines());
                    return wrap;
                  };
            },
          );
        },
      );
      const input =
          '[wrap]\n'
          '--\n'
          '[foo=bar]\n'
          '====\n'
          'content\n'
          '====\n'
          '\n'
          '[baz=qux]\n'
          '====\n'
          'content\n'
          '====\n'
          '--\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(1));
      final wrap = doc.blocks[0];
      expect(wrap.blocks.length, equals(2));
      expect(wrap.blocks[0].attributes.length, equals(2));
      expect(wrap.blocks[1].attributes.length, equals(2));
      expect(wrap.blocks[1].attributes['foo'], isNull);
    });

    test('can use parse_attributes to parse attrlist', () {
      Map<Object, String?>? parsedAttrs;
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.named('attrs');
              processor.onContext('open');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    Reader reader,
                    Map<String, Object?> attrs,
                  ) {
                    parsedAttrs = processor.parseAttributes(
                      parent,
                      reader.readLine(),
                      positionalAttributes: ['a', 'b'],
                    );
                    parsedAttrs!.addAll(
                      processor.parseAttributes(
                        parent,
                        'foo={foo}',
                        subAttributes: true,
                      ),
                    );
                    return null;
                  };
            },
          );
        },
      );
      const input = ':foo: bar\n\n[attrs]\n--\na,b,c,key=val\n--\n';
      convertStringToEmbedded(input);
      expect(parsedAttrs!['a'], equals('a'));
      expect(parsedAttrs!['b'], equals('b'));
      expect(parsedAttrs!['key'], equals('val'));
      expect(parsedAttrs!['foo'], equals('bar'));
    });

    test('create_section should set up all section properties', () {
      Section? sect;
      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            build: (processor) {
              processor.named('sect');
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    final stringAttrs = <String, Object?>{
                      for (final entry in attrs.entries)
                        entry.key.toString(): entry.value,
                    };
                    final levelValue = stringAttrs.remove('level');
                    var current = parent;
                    if (current.context == 'preamble') {
                      current = current.parent!;
                    }
                    if (stringAttrs['id'] == 'false') {
                      stringAttrs['id'] = false;
                    }
                    sect = processor.createSection(
                      current,
                      'Section Title',
                      stringAttrs,
                      level: levelValue == null
                          ? null
                          : int.parse(levelValue.toString()),
                    );
                    return null;
                  };
            },
          );
        },
      );

      String inputFor(String attrlist) =>
          '= Document Title\n'
          ':doctype: book\n'
          ':sectnums:\n'
          '\n'
          'sect::[$attrlist]\n';

      final cases = <String, List<Object?>>{
        '': ['chapter', 1, false, true, '_section_title'],
        'level=0': ['part', 0, false, false, '_section_title'],
        'level=0,alt': [
          'part',
          0,
          false,
          true,
          '_section_title',
          {'partnums': ''},
        ],
        'level=0,style=appendix': ['appendix', 1, true, true, '_section_title'],
        'style=appendix': ['appendix', 1, true, true, '_section_title'],
        'style=glossary': ['glossary', 1, true, false, '_section_title'],
        'style=glossary,alt': [
          'glossary',
          1,
          true,
          'chapter',
          '_section_title',
          {'sectnums': 'all'},
        ],
        'style=abstract': ['chapter', 1, false, true, '_section_title'],
        'id=section-title': ['chapter', 1, false, true, 'section-title'],
        'id=false': ['chapter', 1, false, true, null],
      };
      cases.forEach((attrlist, expected) {
        final input = inputFor(attrlist);
        documentFromString(input, {
          'safe': 'server',
          if (expected.length > 5)
            'attributes': expected[5] as Map<String, Object?>,
        });
        expect(sect!.sectname, equals(expected[0]));
        expect(sect!.level, equals(expected[1]));
        expect(sect!.special, equals(expected[2]));
        expect(sect!.numbered, equals(expected[3]));
        expect(sect!.id, equals(expected[4]));
      });
    });

    test('should add docinfo to document', () {
      const input = '= Document Title\n\nsample content\n';

      Extensions.register(
        build: (registry) {
          registry.docinfoProcessor(processor: MetaRobotsDocinfoProcessor.new);
        },
      );

      final doc = documentFromString(input);
      expect(doc.safe, equals(SafeMode.secure));
      expect(
        doc.docinfo(),
        equals('<meta name="robots" content="index,follow">'),
      );
    });

    test('should add multiple docinfo to document', () {
      const input = '= Document Title\n\nsample content\n';

      Extensions.register(
        build: (registry) {
          registry.docinfoProcessor(processor: MetaAppDocinfoProcessor.new);
          registry.docinfoProcessor(
            processor: MetaRobotsDocinfoProcessor.new,
            config: {'position': '>>'},
          );
          registry.docinfoProcessor(
            build: (processor) {
              processor.atLocation('footer');
              processor.onProcess = (Document doc) =>
                  '<script><!-- analytics code --></script>';
            },
          );
        },
      );

      final doc = documentFromString(input, {'safe': 'server'});
      expect(
        doc.docinfo(),
        equals(
          '<meta name="robots" content="index,follow">\n'
          '<meta name="application-name" content="Asciidoctor App">',
        ),
      );
      expect(
        doc.docinfo('footer'),
        equals('<script><!-- analytics code --></script>'),
      );
    });

    test('should append docinfo to document', () {
      Extensions.register(
        build: (registry) {
          registry.docinfoProcessor(processor: MetaRobotsDocinfoProcessor.new);
        },
      );
      final sampleInputPath = fixturePath('basic.adoc');

      final output = convertFile(
        sampleInputPath,
        toFile: false,
        standalone: true,
        safe: SafeMode.server,
        attributes: {'docinfo': ''},
      );
      expect(output, isNotEmpty);
      assertCss('script[src="modernizr.js"]', output, 1);
      assertCss('meta[name="robots"]', output, 1);
      assertCss('meta[http-equiv="imagetoolbar"]', output, 0);
    });

    test('should return extension instance after registering', () {
      // Adapted: the registry is activated manually.
      final exts = <ProcessorExtension>[];
      Extensions.register(
        build: (registry) {
          exts.add(registry.preprocessor(processor: SamplePreprocessor.new));
          exts.add(
            registry.includeProcessor(processor: SampleIncludeProcessor.new),
          );
          exts.add(registry.treeProcessor(processor: SampleTreeProcessor.new));
          exts.add(
            registry.docinfoProcessor(processor: SampleDocinfoProcessor.new),
          );
          exts.add(registry.postprocessor(processor: SamplePostprocessor.new));
        },
      );
      Registry().activate(emptyDocument());
      for (final ext in exts) {
        expect(ext, isA<ProcessorExtension>());
      }
    });

    test('should raise exception if document processor extension does not '
        'provide process method', () {
      // Adapted: the registry is activated manually; activation raises
      // StateError carrying Ruby's message (without the source
      // location, which Dart cannot capture).
      final extensionRegistry = Extensions.create(
        build: (registry) {
          registry.treeProcessor(build: (processor) {});
        },
      );
      expect(
        () => extensionRegistry.activate(emptyDocument()),
        throwsA(
          isStateError.having(
            (error) => error.message,
            'message',
            contains('No block specified to process tree processor extension'),
          ),
        ),
      );
    });

    test('should raise exception if syntax processor extension does not '
        'provide process method', () {
      // Adapted: see the document processor variant above.
      final extensionRegistry = Extensions.create(
        build: (registry) {
          registry.blockMacro(name: 'foo', build: (processor) {});
        },
      );
      expect(
        () => extensionRegistry.activate(emptyDocument()),
        throwsA(
          isStateError.having(
            (error) => error.message,
            'message',
            contains('No block specified to process block macro extension'),
          ),
        ),
      );
    });

    test('should raise exception if syntax processor extension does not '
        'provide a name', () {
      // Adapted: Ruby smuggles a nil name through a String subclass;
      // Dart omits the name instead, which raises the same ArgumentError.
      final extensionRegistry = Extensions.create(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor.onProcess = (
                AbstractBlock parent,
                Reader reader,
                Map<String, Object?> attrs,
              ) => null;
            },
          );
        },
      );
      expect(
        () => extensionRegistry.activate(emptyDocument()),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('No name specified for block extension'),
          ),
        ),
      );
    });

    test('should raise an exception if mandatory target attribute is not '
        'provided for image block', () {
      // Adapted: the macro body is invoked headlessly through its
      // process method (no parse/convert).
      final registry = createCatInSinkBlockMacro();
      final doc = emptyDocument();
      registry.activate(doc);
      final ext = registry.findBlockMacroExtension('cat_in_sink')!;
      expect(
        () =>
            (ext.processMethod
                as Object? Function(
                  AbstractBlock,
                  String,
                  Map<Object, Object?>,
                ))(doc, '', <Object, Object?>{}),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('target attribute is required'),
          ),
        ),
      );
    });

    test(
      'should assign alt attribute to image block if alt is not provided',
      () {
        const input = 'cat_in_sink::25[]';
        final doc = documentFromString(input, {
          'standalone': false,
          'extension_registry': createCatInSinkBlockMacro(),
        });
        final image = doc.blocks[0];
        expect(image.attr('alt'), equals('cat in sink day 25'));
        expect(image.attr('default-alt'), equals('cat in sink day 25'));
        final output = doc.convert() as String;
        expect(
          output,
          contains(
            '<img src="cat-in-sink-day-25.png" alt="cat in sink day 25">',
          ),
        );
      },
    );

    test(
      'should create an image block if mandatory attributes are provided',
      () {
        const input = 'cat_in_sink::30[cat in sink (yes)]';
        final doc = documentFromString(input, {
          'standalone': false,
          'extension_registry': createCatInSinkBlockMacro(),
        });
        final image = doc.blocks[0];
        expect(image.attr('alt'), equals('cat in sink (yes)'));
        expect(image.hasAttr('default-alt'), isFalse);
        final output = doc.convert() as String;
        expect(
          output,
          contains(
            '<img src="cat-in-sink-day-30.png" alt="cat in sink (yes)">',
          ),
        );
      },
    );

    test('should not assign caption on image block if title is not set on '
        'custom block macro', () {
      const input = 'cat_in_sink::30[]';
      final doc = documentFromString(input, {
        'standalone': false,
        'extension_registry': createCatInSinkBlockMacro(),
      });
      final output = doc.convert() as String;
      assertXpath('/*[@class="imageblock"]/*[@class="title"]', output, 0);
    });

    test('should assign caption on image block if title is set on custom '
        'block macro', () {
      const input = '.Cat in Sink?\ncat_in_sink::30[]\n';
      final doc = documentFromString(input, {
        'standalone': false,
        'extension_registry': createCatInSinkBlockMacro(),
      });
      final output = doc.convert() as String;
      assertXpath(
        '/*[@class="imageblock"]/*[@class="title"]'
        '[text()="Figure 1. Cat in Sink?"]',
        output,
        1,
      );
    });

    test('should not fail if alt attribute is not set on block image node', () {
      Extensions.register(
        build: (registry) {
          registry.blockMacro(
            name: 'no_alt',
            build: (processor) {
              processor.onProcess =
                  (
                    AbstractBlock parent,
                    String target,
                    Map<Object, Object?> attrs,
                  ) {
                    return processor.createBlock(parent, 'image', null, {
                      'target': 'picture.jpg',
                    });
                  };
            },
          );
        },
      );

      final output = asciidoctorConvert('no_alt::[]');
      expect(output, contains('<img src="picture.jpg" alt="">'));
    });

    test(
      'should not fail if alt attribute is not set on inline image node',
      () {
        Extensions.register(
          build: (registry) {
            registry.inlineMacro(
              name: 'no_alt',
              build: (processor) {
                processor.matchFormat('short');
                processor.onProcess =
                    (
                      AbstractBlock parent,
                      String target,
                      Map<Object, Object?> attrs,
                    ) {
                      return processor.createInline(
                        parent,
                        'image',
                        null,
                        target: 'picture.jpg',
                      );
                    };
              },
            );
          },
        );

        final output = asciidoctorConvert('no_alt:[]');
        expect(
          output,
          contains('<span class="image"><img src="picture.jpg" alt=""></span>'),
        );
      },
    );

    test('should assign id and role on list items unordered', () {
      const input = 'santa_list::ulist[]';
      final doc = documentFromString(input, {
        'standalone': false,
        'extension_registry': createSantaListBlockMacro(),
      });
      final output = doc.convert() as String;
      assertXpath(
        '/div[@class="ulist"]/ul/li[@class="friendly"]'
        '[@id="santa-list-guillaume"]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="ulist"]/ul/li[@class="kind contributor java"]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="ulist"]/ul/li[@class="kind contributor java"]'
        '[not(@id)]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="ulist"]/ul/li[@id="santa-list-pepijn"][not(@class)]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="ulist"]/ul/li[@id="santa-list-dan"]'
        '[@class="naughty"]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="ulist"]/ul/li[not(@id)][not(@class)]'
        '/p[text()="Sarah"]',
        output,
        1,
      );
    });

    test('should assign id and role on list items ordered', () {
      const input = 'santa_list::olist[]';
      final doc = documentFromString(input, {
        'standalone': false,
        'extension_registry': createSantaListBlockMacro(),
      });
      final output = doc.convert() as String;
      assertXpath(
        '/div[@class="olist"]/ol/li[@class="friendly"]'
        '[@id="santa-list-guillaume"]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="olist"]/ol/li[@class="kind contributor java"]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="olist"]/ol/li[@class="kind contributor java"]'
        '[not(@id)]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="olist"]/ol/li[@id="santa-list-pepijn"][not(@class)]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="olist"]/ol/li[@id="santa-list-dan"]'
        '[@class="naughty"]',
        output,
        1,
      );
      assertXpath(
        '/div[@class="olist"]/ol/li[not(@id)][not(@class)]'
        '/p[text()="Sarah"]',
        output,
        1,
      );
    });
  });

  group('Factories', () {
    // Headless unit tests for the Processor factory methods (no parse or
    // convert involved).

    test('createSection sets up all section properties', () {
      // Headless port of the parser-driven 'create_section should set up
      // all section properties' matrix: attribute maps are built directly
      // instead of going through a block macro.
      final processor = SampleBlock();
      // (attrs, extra document attributes, expected sectname/level/special/
      // numbered/id). Mirrors the Ruby matrix, including its trailing
      // attribute maps.
      final cases =
          <(Map<String, Object?>, Map<String, Object?>, List<Object?>)>[
            ({}, {}, ['chapter', 1, false, true, '_section_title']),
            ({'level': 0}, {}, ['part', 0, false, false, '_section_title']),
            (
              {'level': 0},
              {'partnums': ''},
              ['part', 0, false, true, '_section_title'],
            ),
            (
              {'level': 0, 'style': 'appendix'},
              {},
              ['appendix', 1, true, true, '_section_title'],
            ),
            (
              {'style': 'appendix'},
              {},
              ['appendix', 1, true, true, '_section_title'],
            ),
            (
              {'style': 'glossary'},
              {},
              ['glossary', 1, true, false, '_section_title'],
            ),
            (
              {'style': 'glossary'},
              {'sectnums': 'all'},
              ['glossary', 1, true, 'chapter', '_section_title'],
            ),
            (
              {'style': 'abstract'},
              {},
              ['chapter', 1, false, true, '_section_title'],
            ),
            (
              {'id': 'section-title'},
              {},
              ['chapter', 1, false, true, 'section-title'],
            ),
            ({'id': false}, {}, ['chapter', 1, false, true, null]),
          ];
      var index = 0;
      for (final (attrs, extra, expected) in cases) {
        final doc = Document([], {
          'attributes': {'doctype': 'book', 'sectnums': '', ...extra},
        });
        final sectionAttrs = Map<String, Object?>.of(attrs);
        final level = sectionAttrs.remove('level') as int?;
        final sect = processor.createSection(
          doc,
          'Section Title',
          sectionAttrs,
          level: level,
        );
        expect(
          sect.sectname,
          equals(expected[0]),
          reason: 'case $index sectname',
        );
        expect(sect.level, equals(expected[1]), reason: 'case $index level');
        expect(
          sect.special,
          equals(expected[2]),
          reason: 'case $index special',
        );
        expect(
          sect.numbered,
          equals(expected[3]),
          reason: 'case $index numbered',
        );
        expect(sect.id, equals(expected[4]), reason: 'case $index id');
        index++;
      }
    });

    test('createSection honors an explicit numbered flag', () {
      final processor = SampleBlock();
      final doc = Document([], {
        'attributes': {'doctype': 'book'},
      });
      final sect = processor.createSection(
        doc,
        'Section Title',
        <String, Object?>{},
        numbered: false,
      );
      expect(sect.numbered, equals(false));
      final numbered = processor.createSection(
        doc,
        'Section Title',
        <String, Object?>{},
        numbered: true,
      );
      expect(numbered.numbered, equals(true));
    });

    test('createSection detects a manpage synopsis section', () {
      final processor = SampleBlock();
      final doc = Document([], {
        'attributes': {'doctype': 'manpage'},
      });
      final sect = processor.createSection(
        doc,
        'Synopsis',
        <String, Object?>{},
      );
      expect(sect.sectname, equals('synopsis'));
      expect(sect.special, isTrue);
    });

    test('createSection throws for a detached parent', () {
      final processor = SampleBlock();
      final orphan = Block(null, 'open');
      expect(
        () => processor.createSection(orphan, 'Title', <String, Object?>{}),
        throwsStateError,
      );
    });

    test('createBlock creates a block with a default content model', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final block = processor.createBlock(
        doc,
        'paragraph',
        'hello',
        <String, Object?>{},
      );
      expect(block, isA<Block>());
      expect(block.context, equals('paragraph'));
      expect(block.contentModel, equals('simple'));
      expect(block.lines, equals(['hello']));
      expect(block.parent, same(doc));
    });

    test('createList and createListItem link nodes together', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final list = processor.createList(doc, 'ulist');
      expect(list, isA<ListBlock>());
      expect(list.context, equals('ulist'));
      final item = processor.createListItem(list, 'Guillaume');
      item.addRole('friendly');
      item.id = 'item-1';
      list << item;
      expect(list.items.length, equals(1));
      expect(list.hasItems, isTrue);
      expect(item.hasText, isTrue);
      expect(item.includesRole('friendly'), isTrue);
      expect(item.id, equals('item-1'));
    });

    test('createImageBlock requires the target attribute', () {
      final processor = SampleBlockMacro();
      expect(
        () => processor.createImageBlock(emptyDocument(), <String, Object?>{}),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('target attribute is required'),
          ),
        ),
      );
    });

    test('createImageBlock assigns a default alt attribute', () {
      final processor = SampleBlockMacro();
      final doc = emptyDocument();
      final block = processor.createImageBlock(doc, {
        'target': 'cat-in-sink-day-25.png',
      });
      expect(block.attr('alt'), equals('cat in sink day 25'));
      expect(block.attr('default-alt'), equals('cat in sink day 25'));
    });

    test('createImageBlock keeps an explicit alt attribute', () {
      final processor = SampleBlockMacro();
      final doc = emptyDocument();
      final block = processor.createImageBlock(doc, {
        'target': 'cat-in-sink-day-30.png',
        'alt': 'cat in sink (yes)',
      });
      expect(block.attr('alt'), equals('cat in sink (yes)'));
      expect(block.hasAttr('default-alt'), isFalse);
    });

    test('createImageBlock promotes a title to a caption', () {
      final processor = SampleBlockMacro();
      final doc = emptyDocument();
      final attrs = <String, Object?>{
        'target': 'cat-in-sink-day-30.png',
        'title': 'Cat in Sink?',
      };
      final block = processor.createImageBlock(doc, attrs);
      expect(block.sourceTitle, equals('Cat in Sink?'));
      expect(block.caption, equals('Figure 1. '));
      expect(block.numeral, equals(1));
      expect(attrs.containsKey('title'), isFalse);
    });

    test('createInline defaults quoted nodes to unquoted', () {
      final processor = SampleInlineMacro();
      final doc = emptyDocument();
      final quoted = processor.createInline(doc, 'quoted', '*hi*');
      expect(quoted.type, equals('unquoted'));
      expect(quoted.text, equals('*hi*'));
      final explicit = processor.createInline(
        doc,
        'quoted',
        '*hi*',
        type: 'emphasis',
      );
      expect(explicit.type, equals('emphasis'));
      final anchor = processor.createInline(
        doc,
        'anchor',
        'text',
        type: 'link',
        target: 'https://example.com',
      );
      expect(anchor.type, equals('link'));
      expect(anchor.target, equals('https://example.com'));
    });

    test('create delegates build the right node types', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final attrs = <String, Object?>{};
      expect(
        processor.createParagraph(doc, 'x', attrs).context,
        equals('paragraph'),
      );
      expect(
        processor.createOpenBlock(doc, 'x', attrs).context,
        equals('open'),
      );
      expect(
        processor.createExampleBlock(doc, 'x', attrs).context,
        equals('example'),
      );
      expect(
        processor.createPassBlock(doc, 'x', attrs).context,
        equals('pass'),
      );
      expect(
        processor.createListingBlock(doc, 'x', attrs).context,
        equals('listing'),
      );
      expect(
        processor.createLiteralBlock(doc, 'x', attrs).context,
        equals('literal'),
      );
      final anchor = processor.createAnchor(doc, 'text', target: 't');
      expect(anchor.context, equals('anchor'));
      expect(anchor.target, equals('t'));
      final pass = processor.createInlinePass(doc, '<b>hi</b>');
      expect(pass.context, equals('quoted'));
      expect(pass.type, equals('unquoted'));
    });

    test('parseAttributes parses positional attributes', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      expect(processor.parseAttributes(doc, null), equals(<Object, String?>{}));
      expect(processor.parseAttributes(doc, ''), equals(<Object, String?>{}));
      final attrs = processor.parseAttributes(
        doc,
        'a,b,c,key=val',
        positionalAttributes: ['a', 'b'],
      );
      expect(attrs['a'], equals('a'));
      expect(attrs['b'], equals('b'));
      expect(attrs['key'], equals('val'));
    });

    test('parseAttributes with subAttributes resolves attributes', () {
      final processor = SampleBlock();
      final doc = emptyDocument({
        'attributes': {'foo': 'bar'},
      });
      final attrs = processor.parseAttributes(
        doc,
        'foo={foo}',
        subAttributes: true,
      );
      expect(attrs['foo'], equals('bar'));
    });

    test('parseContent parses blocks into the parent', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final parent = processor.parseContent(doc, 'content');
      expect(parent, same(doc));
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks[0].context, equals('paragraph'));
    });
  });

  group('Dsl', () {
    test('named and content model helpers set config', () {
      final processor = SampleBlock();
      processor.named('shout');
      expect(processor.name, equals('shout'));
      processor.contentModel('simple');
      expect(processor.config['content_model'], equals('simple'));
      processor.parseContentAs('raw');
      expect(processor.config['content_model'], equals('raw'));
    });

    test('positional and default attribute helpers set config', () {
      final processor = SampleInlineMacro();
      processor.positionalAttributes(['a', 'b']);
      expect(processor.config['positional_attrs'], equals(['a', 'b']));
      processor.positionalAttributes('chars');
      expect(processor.config['positional_attrs'], equals(['chars']));
      processor.namePositionAttributes(['x']);
      expect(processor.config['positional_attrs'], equals(['x']));
      processor.defaultAttributes({1: 'a', 'foo': 'baz'});
      expect(processor.config['default_attrs'], equals({1: 'a', 'foo': 'baz'}));
    });

    test('deprecated aliases delegate', () {
      final processor = SampleInlineMacro();
      // ignore: deprecated_member_use
      processor.positionalAttrs(['a']);
      expect(processor.config['positional_attrs'], equals(['a']));
      // ignore: deprecated_member_use
      processor.defaultAttrs({'foo': 'bar'});
      expect(processor.config['default_attrs'], equals({'foo': 'bar'}));
      // ignore: deprecated_member_use
      processor.resolvesAttributes(['1:name']);
      expect(processor.config['positional_attrs'], equals(['name']));
      // ignore: deprecated_member_use
      processor.usingFormat('short');
      expect(processor.config['format'], equals('short'));
    });

    test('resolveAttributes handles list specifications', () {
      final processor = SampleInlineMacro();
      processor.resolveAttributes(['1:units', 'precision=1']);
      expect(processor.config['positional_attrs'], equals(['units']));
      expect(processor.config['default_attrs'], equals({'precision': '1'}));
      expect(processor.config['content_model'], equals('attributes'));
    });

    test('resolveAttributes handles a single string', () {
      final processor = SampleBlockMacro();
      processor.resolveAttributes('1:value');
      expect(processor.config['positional_attrs'], equals(['value']));
      expect(processor.config['default_attrs'], equals({}));
    });

    test('resolveAttributes with false selects the text content model', () {
      final processor = SampleBlockMacro();
      processor.resolveAttributes(false);
      expect(processor.config['content_model'], equals('text'));
    });

    test('resolveAttributes with no arguments resets both lists', () {
      final processor = SampleBlockMacro();
      processor.resolveAttributes(['1:value']);
      processor.resolveAttributes();
      expect(processor.config['positional_attrs'], equals([]));
      expect(processor.config['default_attrs'], equals({}));
      expect(processor.config['content_model'], equals('attributes'));
    });

    test('resolveAttributes handles map specifications', () {
      final processor = SampleInlineMacro();
      processor.resolveAttributes({'1:name': null});
      expect(processor.config['positional_attrs'], equals(['name']));
      expect(processor.config['default_attrs'], equals({}));
    });

    test('resolveAttributes handles @ indices and offset slots', () {
      final processor = SampleInlineMacro();
      processor.resolveAttributes(['@:first', '2:third']);
      expect(processor.config['positional_attrs'], equals(['first', 'third']));
    });

    test('resolveAttributes rejects unsupported specifications', () {
      final processor = SampleBlock();
      expect(
        () => processor.resolveAttributes(42),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('unsupported attributes specification for macro'),
          ),
        ),
      );
    });

    test('block contexts normalize and bind', () {
      final implied = SampleBlock();
      expect(implied.config['contexts'], equals({'open', 'paragraph'}));
      expect(implied.config['content_model'], equals('compound'));
      final single = SampleBlock('x', {'contexts': 'paragraph'});
      expect(single.config['contexts'], equals({'paragraph'}));
      final listed = SampleBlock('x', {
        'contexts': ['paragraph', 'sidebar'],
      });
      expect(listed.config['contexts'], equals({'paragraph', 'sidebar'}));
      final bound = SampleBlock();
      bound.onContext('literal');
      expect(bound.config['contexts'], equals({'literal'}));
      bound.onContexts(['sidebar', 'open']);
      expect(bound.config['contexts'], equals({'sidebar', 'open'}));
      bound.bindTo('paragraph');
      expect(bound.config['contexts'], equals({'paragraph'}));
      bound.contexts(['open']);
      expect(bound.config['contexts'], equals({'open'}));
    });

    test('macro processors default to the attributes content model', () {
      expect(SampleBlockMacro().config['content_model'], equals('attributes'));
      expect(SampleInlineMacro().config['content_model'], equals('attributes'));
    });

    test('prefer marks the processor position', () {
      final processor = SampleTreeProcessor();
      processor.prefer();
      expect(processor.config['position'], equals('>>'));
    });

    test('docinfo location helpers set config', () {
      final processor = SampleDocinfoProcessor();
      expect(processor.config['location'], equals('head'));
      processor.atLocation('footer');
      expect(processor.config['location'], equals('footer'));
    });

    test('inline macro format and match helpers set config', () {
      final processor = SampleInlineMacro();
      processor.format('short');
      expect(processor.config['format'], equals('short'));
      processor.matchFormat('full');
      expect(processor.config['format'], equals('full'));
      final pattern = RegExp(r'@(\w+)');
      processor.match(pattern);
      expect(processor.config['regexp'], same(pattern));
    });

    test('option and updateConfig mutate config', () {
      final processor = SamplePreprocessor({'a': '1'});
      expect(processor.config['a'], equals('1'));
      processor.option('b', '2');
      expect(processor.config['b'], equals('2'));
      processor.updateConfig({'a': '3'});
      expect(processor.config['a'], equals('3'));
    });

    test('subclass constructors merge class-wide defaults', () {
      final upper = UppercaseBlock();
      expect(upper.name, equals('yell'));
      expect(upper.config['contexts'], equals({'paragraph'}));
      expect(upper.config['positional_attrs'], equals(['chars']));
      expect(upper.config['content_model'], equals('simple'));
      final temperature = TemperatureMacro();
      expect(temperature.name, equals('degrees'));
      expect(temperature.config['positional_attrs'], equals(['units']));
      expect(temperature.config['default_attrs'], equals({'precision': '1'}));
      final legacy = LegacyPosAttrsBlockMacro();
      expect(legacy.config['pos_attrs'], equals(['target', 'format']));
    });
  });

  group('InlineMacroRegExp', () {
    test('full format matches a target and attrlist', () {
      final processor = SampleInlineMacro('say');
      final pattern = processor.regexp;
      final match = pattern.firstMatch('say:yo[]')!;
      expect(match.group(1), equals('yo'));
      expect(match.group(2), equals(''));
      final withAttrs = pattern.firstMatch('say:yo[a=A]')!;
      expect(withAttrs.group(1), equals('yo'));
      expect(withAttrs.group(2), equals('a=A'));
    });

    test('short format matches without a target', () {
      final processor = SampleInlineMacro('label');
      processor.matchFormat('short');
      final pattern = processor.regexp;
      final match = pattern.firstMatch('label:[Checkbox]')!;
      // Matches Ruby: the short-format target capture is nil.
      expect(match.group(1), isNull);
      expect(match.group(2), equals('Checkbox'));
    });

    test('regexp is frozen after first resolution', () {
      final processor = SampleInlineMacro('say');
      final first = processor.regexp;
      expect(processor.regexp, same(first));
      expect(processor.config['regexp'], same(first));
      expect(InlineMacroProcessor.resolveRegexp('say', null), same(first));
    });

    test('explicit match pattern wins over resolution', () {
      final processor = SampleInlineMacro('@short_match');
      final pattern = RegExp(r'@(\w+)');
      processor.match(pattern);
      expect(processor.regexp, same(pattern));
    });

    test('resolveRegexp rejects illegal names', () {
      expect(
        () => InlineMacroProcessor.resolveRegexp('illegal name', null),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            'invalid name for inline macro: illegal name',
          ),
        ),
      );
    });
  });

  group('RegistryBehavior', () {
    test('prefer moves an extension to the front', () {
      final registry = Registry();
      final first = registry.treeProcessor(
        build: (processor) {
          processor.onProcess = (Document doc) => null;
        },
      );
      final second = registry.treeProcessor(
        build: (processor) {
          processor.onProcess = (Document doc) => null;
        },
      );
      expect(registry.treeProcessors, equals([first, second]));
      registry.prefer(first);
      expect(registry.treeProcessors, equals([first, second]));
      registry.prefer(second);
      expect(registry.treeProcessors, equals([second, first]));
    });

    test('prefer registers through a kind name', () {
      final registry = Registry();
      registry.treeProcessor(
        build: (processor) {
          processor.onProcess = (Document doc) => null;
        },
      );
      final preferred = registry.prefer(
        'tree_processor',
        build: (TreeProcessor processor) {
          processor.onProcess = (Document doc) => null;
        },
      );
      expect(registry.treeProcessors.first, same(preferred));
      final viaFactory = registry.prefer(
        'tree_processor',
        processor: SelfSigningTreeProcessor.new,
      );
      expect(registry.treeProcessors.first, same(viaFactory));
    });

    test('prefer rejects unknown kinds and foreign extensions', () {
      final registry = Registry();
      expect(() => registry.prefer('treeprocessor'), throwsArgumentError);
      expect(() => registry.prefer(42), throwsArgumentError);
      final foreign = ProcessorExtension(
        'tree_processor',
        SampleTreeProcessor(),
      );
      expect(() => registry.prefer(foreign), throwsStateError);
      registry.block(processor: SampleBlock.new, name: 'sample');
      final syntax = registry.findBlockExtension('sample')!;
      expect(() => registry.prefer(syntax), throwsStateError);
    });

    test('position config inserts at the front', () {
      final registry = Registry();
      registry.preprocessor(processor: SamplePreprocessor.new);
      final preferred = registry.preprocessor(
        processor: SamplePreprocessor.new,
        config: {'position': '>>'},
      );
      expect(registry.preprocessors.first, same(preferred));
    });

    test('docinfo processors filter by location', () {
      final registry = Registry();
      expect(registry.hasDocinfoProcessors(), isFalse);
      expect(registry.docinfoProcessors(), isEmpty);
      registry.docinfoProcessor(processor: MetaAppDocinfoProcessor.new);
      registry.docinfoProcessor(
        build: (processor) {
          processor.atLocation('footer');
          processor.onProcess = (Document doc) => 'footer';
        },
      );
      expect(registry.hasDocinfoProcessors(), isTrue);
      expect(registry.hasDocinfoProcessors('head'), isTrue);
      expect(registry.hasDocinfoProcessors('footer'), isTrue);
      expect(registry.docinfoProcessors().length, equals(2));
      expect(registry.docinfoProcessors('head').length, equals(1));
      expect(registry.docinfoProcessors('footer').length, equals(1));
    });

    test('extension config is the instance config', () {
      final registry = Registry();
      final instance = SamplePreprocessor({'key': 'value'});
      final ext = registry.preprocessor(processor: instance);
      expect(ext.kind, equals('preprocessor'));
      expect(ext.instance, same(instance));
      expect(ext.config, same(instance.config));
    });

    test('processMethod invokes the family process methods', () {
      final registry = Registry();
      final doc = emptyDocument();

      final tree = registry.treeProcessor(
        build: (processor) {
          processor.onProcess = (Document document) {
            document <<
                processor.createParagraph(document, 'hi', <String, Object?>{});
            return null;
          };
        },
      );
      (tree.processMethod as Object? Function(Document))(doc);
      expect(doc.blocks.length, equals(1));

      final post = registry.postprocessor(
        build: (processor) {
          processor.onProcess = (Document document, String output) =>
              '$output!';
        },
      );
      expect(
        (post.processMethod as Object? Function(Document, String))(doc, 'hi'),
        equals('hi!'),
      );

      final pre = registry.preprocessor(
        build: (processor) {
          processor.onProcess = (Document document, Reader reader) => reader;
        },
      );
      final reader = Reader('hi');
      expect(
        (pre.processMethod as Object? Function(Document, Reader))(doc, reader),
        same(reader),
      );

      final block = registry.block(
        name: 'shout',
        build: (processor) {
          processor.onProcess =
              (
                AbstractBlock parent,
                Reader reader,
                Map<String, Object?> attrs,
              ) {
                return processor.createParagraph(
                  parent,
                  reader.lines.map((line) => line!.toUpperCase()).toList(),
                  attrs,
                );
              };
        },
      );
      final created =
          (block.processMethod
                  as Object? Function(
                    AbstractBlock,
                    Reader,
                    Map<String, Object?>,
                  ))(doc, Reader('hi'), <String, Object?>{})
              as Block;
      expect(created.lines, equals(['HI']));
    });

    test('unimplemented process methods throw UnimplementedError', () {
      final doc = emptyDocument();
      expect(
        () => SampleDocinfoProcessor().process(doc),
        throwsUnimplementedError,
      );
      expect(
        () => SamplePostprocessor().process(doc, ''),
        throwsUnimplementedError,
      );
      expect(
        () => SampleBlock().process(doc, Reader(), <String, Object?>{}),
        throwsUnimplementedError,
      );
      expect(
        () => SampleBlockMacro().process(doc, 't', <Object, Object?>{}),
        throwsUnimplementedError,
      );
      expect(
        () => SampleInlineMacro().process(doc, 't', <Object, Object?>{}),
        throwsUnimplementedError,
      );
    });

    test('registration rejects invalid arguments', () {
      final registry = Registry();
      expect(
        () => registry.preprocessor(processor: 42),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('Invalid arguments specified for registering'),
          ),
        ),
      );
      expect(
        () => registry.block(processor: 42),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('Invalid arguments specified for registering'),
          ),
        ),
      );
    });

    test('registration rejects factories of the wrong family', () {
      final registry = Registry();
      expect(
        () => registry.preprocessor(processor: (config) => SampleBlock()),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('Invalid type for preprocessor extension'),
          ),
        ),
      );
      expect(
        () => registry.block(processor: SamplePreprocessor.new),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains(
              'Class specified for block extension does not inherit from '
              'BlockProcessor',
            ),
          ),
        ),
      );
    });

    test('instance registration merges config and honors name overrides', () {
      final registry = Registry();
      final instance = SampleBlock('original');
      final ext = registry.block(
        processor: instance,
        name: 'override',
        config: {'content_model': 'simple'},
      );
      expect(instance.name, equals('override'));
      expect(instance.config['content_model'], equals('simple'));
      expect(registry.findBlockExtension('override'), same(ext));
      expect(registry.findBlockExtension('original'), isNull);
    });

    test('later syntax registrations win for the same name', () {
      final registry = Registry();
      final first = registry.blockMacro(
        processor: SampleBlockMacro.new,
        name: 'sample',
      );
      final second = registry.blockMacro(
        processor: SampleBlockMacro.new,
        name: 'sample',
      );
      expect(registry.findBlockMacroExtension('sample'), same(second));
      expect(registry.findBlockMacroExtension('sample'), isNot(same(first)));
    });

    test('build form accepts a leading config map', () {
      final registry = Registry();
      final ext = registry.preprocessor(
        processor: const {'key': 'value'},
        build: (processor) {
          processor.onProcess = (Document document, Reader reader) => null;
        },
      );
      expect(ext.config['key'], equals('value'));
    });

    test('activate runs zero-argument group callbacks', () {
      var called = false;
      final registry = Registry({
        'empty': () {
          called = true;
        },
      });
      registry.activate(emptyDocument());
      expect(called, isTrue);
      expect(registry.hasPreprocessors, isFalse);
    });

    test('activate rejects invalid groups', () {
      final registry = Registry({'bogus': 42});
      expect(
        () => registry.activate(emptyDocument()),
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            contains('Invalid extension group'),
          ),
        ),
      );
    });

    test('registry groups stay independent from global groups', () {
      Extensions.register(name: 'global', group: SampleExtensionGroup.new);
      final registry = Extensions.create(
        name: 'local',
        build: (r) {
          r.preprocessor(processor: SamplePreprocessor.new);
        },
      );
      expect(registry.groups.length, equals(1));
      registry.activate(emptyDocument());
      // One preprocessor from each group.
      expect(registry.preprocessors.length, equals(2));
      expect(Extensions.groups.length, equals(1));
    });
  });
}
