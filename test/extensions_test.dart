/// Port of `test/extensions_test.rb`.
///
/// Extension integration (activation through the `extensionRegistry` and
/// `extensions` options and global groups, preprocessor, tree processor,
/// postprocessor and docinfo invocation, custom blocks, block macros and
/// inline macros) is ported, and converted-output assertions route
/// through the test-only [assertXpath]/[assertCss] matchers below.
///
/// Several Ruby tests are adapted to the typed Dart API: processors are
/// registered as instances or configured through `build` callbacks that
/// assign `onProcess`, where Ruby passes classes, class names or blocks;
/// each adaptation is marked on the test. Ruby tests that rely on class
/// name lookup or on duck-typed registration arguments have no Dart
/// counterpart and are not ported.
library;

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/load.dart' as api;
import 'package:test/test.dart';

import 'support/doc_helpers.dart';

// ---------------------------------------------------------------------------
// Test doubles.
// ---------------------------------------------------------------------------

/// Records log messages for assertions (port of Ruby's `MemoryLogger`).
///
/// Records everything regardless of [level]; the level only drives the
/// `is*Enabled` predicates consulted by level-gated call sites such as the
/// parser's debug probes.
class FakeLogger extends LoggerBase {
  /// Creates a recording logger at [level].
  new([super.level = Severity.unknown]);

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

  Severity? _maxSeverity;

  @override
  Severity? get maxSeverity => _maxSeverity;

  @override
  void add(Severity severity, LogMessage message) {
    final max = _maxSeverity;
    if (max == null || severity.value > max.value) _maxSeverity = severity;
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
/// `using_memory_logger`); [level] sets the logger level (default
/// [Severity.unknown], recording everything while keeping debug-gated call
/// sites quiet).
void usingMemoryLogger(
  void Function(FakeLogger logger) body, [
  Severity level = Severity.unknown,
]) {
  final saved = LoggerManager.logger;
  final logger = FakeLogger(level);
  LoggerManager.logger = logger;
  try {
    body(logger);
  } finally {
    LoggerManager.logger = saved;
  }
}

/// Asserts [logger] recorded [message] at [severity] (port of
/// `assert_message`).
void assertMessage(FakeLogger logger, Severity severity, String message) {
  final candidates = switch (severity) {
    Severity.debug => logger.debugs,
    Severity.info => logger.infos,
    Severity.warn => logger.warns,
    Severity.error => logger.errors,
    Severity.fatal || Severity.unknown => logger.fatals,
  };
  expect(candidates, contains(message));
}

/// Converts the file at [path] to a string (port of
/// `Asciidoctor.convert_file` with `to_file: false`).
String convertFile(
  String path, {
  bool standalone = false,
  int safe = SafeMode.secure,
  Map<String, String?> attributes = const <String, String?>{},
}) => api
    .loadFile(
      path,
      options: AsciidoctorOptions(
        standalone: standalone,
        safe: safe,
        attributes: attributes,
      ),
    )
    .convert();

/// Loads the file at [path] (port of `Asciidoctor.load_file`).
Document loadFile(String path, {bool sourcemap = false}) =>
    api.loadFile(path, options: AsciidoctorOptions(sourcemap: sourcemap));

/// Loads [input] into a parsed document (port of `Asciidoctor.load`).
Document asciidoctorLoad(String input) => api.load(input);

/// Converts [input] (port of `Asciidoctor.convert`).
String asciidoctorConvert(String input) => api.convert(input);

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
  new(this.tag, [Map<String, String>? attributes])
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
    final element = (_XmlElement(name, attributes))..parent = stack.last;
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
  new(this.tag, this.classes, this.attrs);

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
  new attr(this.name, this.value) : kind = 0;

  /// Creates an attribute-absence predicate.
  new absent(this.name) : kind = 1, value = null;

  /// Creates a text-equality predicate.
  new text(this.value) : kind = 2, name = null;

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
        _XpathPredicate.attr(match.group(1)!.toLowerCase(), match.group(2)),
      );
    } else if (match.group(3) != null) {
      predicates.add(
        _XpathPredicate.attr(match.group(3)!.toLowerCase(), match.group(4)),
      );
    } else if (match.group(5) != null) {
      predicates.add(_XpathPredicate.absent(match.group(5)!.toLowerCase()));
    } else {
      predicates.add(_XpathPredicate.text(match.group(6)));
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
/// against the Ruby suite's `vendor/asciidoctor/test/fixtures` directory (same shape as
/// `load_test.dart`).
String fixturePath(String name) => 'vendor/asciidoctor/test/fixtures/$name';

// ---------------------------------------------------------------------------
// Sample processors (ports of the Ruby test file's top-level classes).
// ---------------------------------------------------------------------------

/// Sample preprocessor (port of `SamplePreprocessor`).
class SamplePreprocessor extends Preprocessor {
  /// Creates a sample preprocessor with [config].
  new([super.config]);

  @override
  Reader? process(Document document, Reader reader) => null;
}

/// Sample include processor (port of `SampleIncludeProcessor`).
class SampleIncludeProcessor extends IncludeProcessor {
  /// Creates a sample include processor with [config].
  new([super.config]);
}

/// Sample docinfo processor (port of `SampleDocinfoProcessor`).
class SampleDocinfoProcessor extends DocinfoProcessor {
  /// Creates a sample docinfo processor with [config].
  new([super.config]);
}

/// Sample tree processor (port of `SampleTreeProcessor`).
class SampleTreeProcessor extends TreeProcessor {
  /// Creates a sample tree processor with [config].
  new([super.config]);

  @override
  Document? process(Document document) => null;
}

/// Sample postprocessor (port of `SamplePostprocessor`).
class SamplePostprocessor extends Postprocessor {
  /// Creates a sample postprocessor with [config].
  new([super.config]);
}

/// Sample block processor (port of `SampleBlock`).
class SampleBlock extends BlockProcessor {
  /// Creates a sample block processor with [name] and [config].
  new([super.name, super.config]);
}

/// Sample block macro processor (port of `SampleBlockMacro`).
class SampleBlockMacro extends BlockMacroProcessor {
  /// Creates a sample block macro processor with [name] and [config].
  new([super.name, super.config]);
}

/// Sample inline macro processor (port of `SampleInlineMacro`).
class SampleInlineMacro extends InlineMacroProcessor {
  /// Creates a sample inline macro processor with [name] and [config].
  new([super.name, super.config]);
}

/// Scrubs lines before the document title (port of
/// `ScrubHeaderPreprocessor`).
class ScrubHeaderPreprocessor extends Preprocessor {
  /// Creates the preprocessor with [config].
  new([super.config]);

  @override
  Reader? process(Document document, Reader reader) {
    final lines = reader.lines;
    final skipped = <String>[];
    while (lines.isNotEmpty && !lines.first.startsWith('=')) {
      skipped.add(lines.removeAt(0));
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
  new([super.config]);

  @override
  bool handles(String target) => target.endsWith('.txt');

  @override
  void process(
    Document document,
    PreprocessorReader reader,
    String target,
    Map<String, String> attributes,
  ) {
    if (target == 'lorem-ipsum.txt') {
      reader.pushInclude(
        'Lorem ipsum dolor sit amet...\n',
        target,
        target,
        1,
        attributes,
      );
    }
  }
}

/// Replaces the document author (port of `ReplaceAuthorTreeProcessor`).
class ReplaceAuthorTreeProcessor extends TreeProcessor {
  /// Creates the processor with [config].
  new([super.config]);

  @override
  Document? process(Document document) {
    document.attributes['firstname'] = 'Ghost';
    document.attributes['author'] = 'Ghost Writer';
    return document;
  }
}

/// Replaces the whole document tree (port of `ReplaceTreeTreeProcessor`).
class ReplaceTreeTreeProcessor extends TreeProcessor {
  /// Creates the processor with [config].
  new([super.config]);

  @override
  Document? process(Document document) {
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
  new([super.config]);

  @override
  Document? process(Document document) {
    document.append(createParagraph(document, 'SelfSigningTreeProcessor', {}));
    return null;
  }
}

/// Strips attributes from tags (port of `StripAttributesPostprocessor`).
class StripAttributesPostprocessor extends Postprocessor {
  /// Creates the processor with [config].
  new([super.config]);

  @override
  String process(Document document, String output) => output.replaceAllMapped(
    RegExp(r'<(\w+).*?>', multiLine: true, dotAll: true),
    (match) => '<${match.group(1)}>',
  );
}

/// Uppercase block (port of `UppercaseBlock`).
///
/// Ruby's class-level DSL (`named`, `on_context`,
/// `name_positional_attributes`, `parse_content_as`) becomes constructor
/// defaults.
class UppercaseBlock extends BlockProcessor {
  /// Creates the block processor with [name] and [config].
  new([String? name, ProcessorConfig? config])
    : super(
        name ?? 'yell',
        config ??
            ProcessorConfig(
              contexts: {'paragraph'},
              positionalAttrs: ['chars'],
              contentModel: ContentModel.simple,
            ),
      );

  @override
  AbstractBlock? process(
    AbstractBlock parent,
    Reader reader,
    Map<String, String> attributes,
  ) {
    final chars = attributes['chars'];
    if (chars != null) {
      final upcaseChars = chars.toUpperCase();
      final lines = reader.lines.map((line) {
        return line.toLowerCase().split('').map((char) {
          final index = chars.indexOf(char);
          return index == -1 ? char : upcaseChars[index];
        }).join();
      });
      return createParagraph(parent, lines.join('\n'), attributes);
    }
    return createParagraph(
      parent,
      reader.lines.map((line) => line.toUpperCase()).join('\n'),
      attributes,
    );
  }
}

/// Script snippet block macro (port of `SnippetMacro`).
class SnippetMacro extends BlockMacroProcessor {
  /// Creates the macro processor with [name] and [config].
  new([super.name, super.config]);

  @override
  AbstractBlock? process(
    AbstractBlock parent,
    String target,
    Map<String, String> attributes,
  ) => createPassBlock(
    parent,
    '<script src="http://example.com/$target.js?_mode=${attributes['mode']}"></script>',
    {},
    contentModel: ContentModel.raw,
  );
}

/// Block macro naming its positional attributes in its configuration (port
/// of `LegacyPosAttrsBlockMacro`).
class LegacyPosAttrsBlockMacro extends BlockMacroProcessor {
  /// Creates the macro processor with [name] and [config].
  new([String? name, ProcessorConfig? config])
    : super(
        name,
        config ?? ProcessorConfig(positionalAttrs: ['target', 'format']),
      );

  @override
  AbstractBlock? process(
    AbstractBlock parent,
    String target,
    Map<String, String> attributes,
  ) => createImageBlock(parent, {
    'target': '${attributes['target']}.${attributes['format']}',
  });
}

/// Temperature inline macro (port of `TemperatureMacro`).
class TemperatureMacro extends InlineMacroProcessor {
  /// Creates the macro processor with [name] and [config].
  new([super.name, super.config]) {
    name ??= 'degrees';
    resolveAttributes(['1:units', 'precision=1']);
  }

  @override
  Inline? process(
    AbstractBlock parent,
    String target,
    Map<String, String> attributes,
  ) {
    final document = parent.document! as Document;
    final units =
        attributes['units'] ?? document.attr('temperature-unit', 'C')!;
    final precision = int.parse(attributes['precision']!);
    final c = double.parse(target);
    switch (units) {
      case 'C':
        return createInline(
          parent,
          InlineContext.quoted,
          '${c.toStringAsFixed(precision)} &#176;C',
          type: 'unquoted',
        );
      case 'F':
        return createInline(
          parent,
          InlineContext.quoted,
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
  new([super.config]);

  @override
  String? process(Document document) =>
      '<meta name="robots" content="index,follow">';
}

/// Application-name docinfo processor (port of `MetaAppDocinfoProcessor`).
class MetaAppDocinfoProcessor extends DocinfoProcessor {
  /// Creates the processor with [config].
  new([super.config]) {
    config.location = 'head';
  }

  @override
  String? process(Document document) =>
      '<meta name="application-name" content="Asciidoctor App">';
}

/// Sample extension group (port of `SampleExtensionGroup`).
class SampleExtensionGroup extends ExtensionGroup {
  /// Self-registers this group under [name] (port of `Group.register`).
  static String register([String? name]) =>
      Extensions.register(name: name, group: SampleExtensionGroup());

  @override
  void activate(Registry registry) {
    registry.document!.attributes['activate-method-called'] = '';
    registry.preprocessor(processor: SamplePreprocessor());
  }
}

/// Standalone `cat_in_sink` block macro registry (port of
/// `create_cat_in_sink_block_macro`).
Registry createCatInSinkBlockMacro() {
  return Extensions.create(
    build: (registry) {
      registry.blockMacro(
        build: (processor) {
          processor
            ..name = 'cat_in_sink'
            ..onProcess = (parent, target, attrs) {
              final imageAttrs = <String, String>{};
              if (target.isNotEmpty) {
                imageAttrs['target'] = 'cat-in-sink-day-$target.png';
              }
              final title = attrs.remove('title');
              if (title != null) imageAttrs['title'] = title;
              final alt = attrs.remove('1');
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
          processor.name = 'santa_list';
          // Adapted: Ruby blocks tolerate the unused third argument;
          // Dart closures must declare it.
          processor.onProcess = (parent, target, _) {
            final list = processor.createList(
              parent,
              BlockContext.parse(target),
            );
            final guillaume = (processor.createListItem(list, 'Guillaume'))
              ..addRole('friendly')
              ..id = 'santa-list-guillaume';
            list.append(guillaume);
            final robert = (processor.createListItem(list, 'Robert'))
              ..addRole('kind')
              ..addRole('contributor')
              ..addRole('java');
            list.append(robert);
            final pepijn = (processor.createListItem(list, 'Pepijn'))
              ..id = 'santa-list-pepijn';
            list.append(pepijn);
            final dan = (processor.createListItem(list, 'Dan'))
              ..addRole('naughty')
              ..id = 'santa-list-dan';
            list.append(dan);
            final sarah = processor.createListItem(list, 'Sarah');
            list.append(sarah);
            return list;
          };
        },
      );
    },
  );
}

void main() {
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
      // Adapted: Dart passes an instance where Ruby passes the class.
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
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

    test('should register extension group from instance', () {
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups['sample'], isA<Function>());
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
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      expect(Extensions.groups.keys.single, equals('sample'));
    });

    test('should unregister extension group by name', () {
      // Merged: Ruby's symbol-name and string-name variants are one form
      // in Dart.
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
      expect(Extensions.groups, isNotNull);
      expect(Extensions.groups.length, equals(1));
      Extensions.unregister(['sample']);
      expect(Extensions.groups.length, equals(0));
    });

    test('should unregister multiple extension groups by name', () {
      Extensions.register(name: 'sample1', group: SampleExtensionGroup());
      Extensions.register(name: 'sample2', group: SampleExtensionGroup());
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
    test(
      'should allow standalone registry to be created but not registered',
      () {
        final registry = Extensions.create(
          name: 'sample',
          build: (registry) {
            registry.block(
              build: (processor) {
                processor
                  ..name = 'whisper'
                  ..onContext('paragraph')
                  ..config.contentModel = ContentModel.simple;
                processor.onProcess = (parent, reader, attributes) {
                  return processor.createParagraph(
                    parent,
                    reader.lines.map((line) => line.toLowerCase()).join('\n'),
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
        Extensions.register,
        throwsA(
          isArgumentError.having(
            (error) => error.message,
            'message',
            'Pass either an extension group or a build callback',
          ),
        ),
      );
    });
  });

  group('Activate', () {
    test('should call activate on extension group factory', () {
      // Adapted: Dart passes an instance where Ruby passes the class.
      final doc = emptyDocument();
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
      final registry = (Registry())..activate(doc);
      expect(doc.hasAttr('activate-method-called'), isTrue);
      expect(registry.hasPreprocessors, isTrue);
    });

    test('should reset registry if activate is called again', () {
      Extensions.register(name: 'sample', group: SampleExtensionGroup());
      var doc = emptyDocument();
      final registry = (Registry())..activate(doc);
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
          registry.preprocessor(processor: SamplePreprocessor());
        },
      );
      final registry = (Registry())..activate(doc);
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
      final registry = (Registry())
        ..preprocessor(processor: SamplePreprocessor())
        ..activate(emptyDocument());
      expect(registry.hasPreprocessors, isTrue);
      final extensions = registry.preprocessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SamplePreprocessor>());
    });

    test('should instantiate include processors', () {
      final registry = (Registry())
        ..includeProcessor(processor: SampleIncludeProcessor())
        ..activate(emptyDocument());
      expect(registry.hasIncludeProcessors, isTrue);
      final extensions = registry.includeProcessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SampleIncludeProcessor>());
      final instance = extensions.first.instance as SampleIncludeProcessor;
      expect(instance.onHandles, isNull);
      expect(instance.handles('include.adoc'), isTrue);
    });

    test('should instantiate docinfo processors', () {
      final registry = (Registry())
        ..docinfoProcessor(processor: SampleDocinfoProcessor())
        ..activate(emptyDocument());
      expect(registry.hasDocinfoProcessors(), isTrue);
      expect(registry.hasDocinfoProcessors('head'), isTrue);
      final extensions = registry.docinfoProcessors();
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SampleDocinfoProcessor>());
    });

    test('should instantiate tree processors', () {
      final registry = (Registry())
        ..treeProcessor(processor: SampleTreeProcessor())
        ..activate(emptyDocument());
      expect(registry.hasTreeProcessors, isTrue);
      final extensions = registry.treeProcessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SampleTreeProcessor>());
    });

    test('should instantiate postprocessors', () {
      final registry = (Registry())
        ..postprocessor(processor: SamplePostprocessor())
        ..activate(emptyDocument());
      expect(registry.hasPostprocessors, isTrue);
      final extensions = registry.postprocessors;
      expect(extensions.length, equals(1));
      expect(extensions.first, isA<ProcessorExtension>());
      expect(extensions.first.instance, isA<SamplePostprocessor>());
    });

    test('should instantiate block processor', () {
      final registry = (Registry())
        ..block(processor: SampleBlock(), name: 'sample')
        ..activate(emptyDocument());
      expect(registry.hasBlocks, isTrue);
      expect(
        registry.registeredForBlock('sample', 'paragraph'),
        isA<ProcessorExtension>(),
      );
      final extension = registry.findBlockExtension('sample');
      expect(extension, isA<ProcessorExtension>());
      expect(extension!.instance, isA<SampleBlock>());
    });

    test('should not match block processor for unsupported context', () {
      final registry = (Registry())
        ..block(processor: SampleBlock(), name: 'sample')
        ..activate(emptyDocument());
      expect(registry.registeredForBlock('sample', 'sidebar'), isNull);
    });

    test('should instantiate block macro processor', () {
      final registry = (Registry())
        ..blockMacro(processor: SampleBlockMacro(), name: 'sample')
        ..activate(emptyDocument());
      expect(registry.hasBlockMacros, isTrue);
      expect(
        registry.registeredForBlockMacro('sample'),
        isA<ProcessorExtension>(),
      );
      final extension = registry.registeredForBlockMacro('sample');
      expect(extension, isA<ProcessorExtension>());
      expect(extension!.instance, isA<SampleBlockMacro>());
    });

    test('should instantiate inline macro processor', () {
      final registry = (Registry())
        ..inlineMacro(processor: SampleInlineMacro(), name: 'sample')
        ..activate(emptyDocument());
      expect(registry.hasInlineMacros, isTrue);
      expect(
        registry.registeredForInlineMacro('sample'),
        isA<ProcessorExtension>(),
      );
      final extension = registry.registeredForInlineMacro('sample');
      expect(extension, isA<ProcessorExtension>());
      expect(extension!.instance, isA<SampleInlineMacro>());
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
        expect(registry.registeredForInlineMacro('unknown'), isNull);
        expect(registry.inlineMacros, isEmpty);
      },
    );

    test('can provide extension registry as an option', () {
      final registry = Extensions.create(
        build: (r) {
          r.treeProcessor(processor: SampleTreeProcessor());
        },
      );

      final doc = documentFromString(
        '= Document Title\n\ncontent',
        AsciidoctorOptions(extensionRegistry: registry),
      );
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
        final registry = (Extensions.create())
          ..treeProcessor(processor: SampleTreeProcessor());

        final doc = documentFromString(
          '= Document Title\n\ncontent',
          AsciidoctorOptions(extensionRegistry: registry),
        );
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
        r.treeProcessor(processor: SampleTreeProcessor());
      }

      final doc = documentFromString(
        '= Document Title\n\ncontent',
        AsciidoctorOptions(extensions: extensions),
      );
      expect(doc.extensions, isNotNull);
      final exts = doc.extensions!;
      expect(exts.groups.length, equals(1));
      expect(exts.hasTreeProcessors, isTrue);
      expect(exts.treeProcessors.length, equals(1));
      expect(Extensions.groups.length, equals(0));
    });

    test('should invoke preprocessors before parsing document', () {
      const input = 'junk line\n\n= Document Title\n\nsample content\n';

      Extensions.register(
        build: (registry) {
          registry.preprocessor(processor: ScrubHeaderPreprocessor());
        },
      );

      final doc = documentFromString(input);
      expect(doc.hasAttr('skipped'), isTrue);
      expect((doc.attr('skipped')!).trim(), equals('junk line'));
      expect(doc.hasHeader, isTrue);
      expect(doc.doctitle(), equals('Document Title'));
    });

    test('should invoke include processor to process include directive', () {
      const input = 'before\n\ninclude::lorem-ipsum.txt[]\n\nafter\n';

      Extensions.register(
        build: (registry) {
          registry.includeProcessor(
            processor: BoilerplateTextIncludeProcessor(),
          );
        },
      );

      // a custom include processor is not affected by the safe mode
      final result = convertString(input);
      assertCss('.paragraph > p', result, 3);
      expect(result, contains('before'));
      expect(result, contains('Lorem ipsum'));
      expect(result, contains('after'));
    });

    test('should invoke include processor through the preprocessor reader', () {
      // Adapted headless port of 'should invoke include processor if it
      // requests to handle include directive': the reader is driven
      // directly over a document carrying the registry.
      const input =
          'include::skip-me.adoc[]\n'
          'line after skip\n'
          '\n'
          'include::include-file.adoc[]\n'
          '\n'
          'last line\n';

      final registry = Extensions.create(
        build: (r) {
          r
            ..includeProcessor(
              build: (processor) {
                // test onHandles assigned as callback
                processor
                  ..onHandles = ((target) => target == 'skip-me.adoc')
                  ..onProcess = (doc, reader, target, attributes) {};
              },
            )
            ..includeProcessor(
              build: (processor) {
                processor
                  ..onHandles = ((target) => target == 'include-file.adoc')
                  ..onProcess = (doc, reader, target, attributes) {
                    // demonstrates that pushInclude normalizes newlines
                    final lineno = reader.cursorAtPrevLine().lineno;
                    final content = [
                      "found include target '$target' at line $lineno\r\n",
                      '\r\n',
                      'middle line\r\n',
                    ];
                    reader.pushIncludeLines(
                      content,
                      target,
                      target,
                      1,
                      attributes,
                    );
                  };
              },
            );
        },
      );
      final document = emptyDocument(
        AsciidoctorOptions(safe: SafeMode.safe, extensionRegistry: registry),
      );
      final reader = PreprocessorReader.fromString(
        document,
        input,
        normalize: true,
      );
      final lines = (<String>[])..add(reader.readLine()!);
      expect(lines.last, equals('line after skip'));
      lines
        ..add(reader.readLine()!)
        ..add(reader.readLine()!);
      expect(
        lines.last,
        equals("found include target 'include-file.adoc' at line 4"),
      );
      expect(reader.lineInfo, equals('include-file.adoc: line 2'));
      while (reader.hasMoreLines()) {
        lines.add(reader.readLine()!);
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
              processor
                ..onHandles = ((target) => target == 'include-file.adoc')
                ..onProcess = (doc, reader, target, attributes) {
                  final content = contentCache.putIfAbsent(
                    'include-file.adoc',
                    () => 'contents of include-file.adoc',
                  );
                  reader.pushInclude(content, target, target, 1, attributes);
                };
            },
          );
        },
      );
      final document = emptyDocument(
        AsciidoctorOptions(safe: SafeMode.safe, extensionRegistry: registry),
      );
      final reader = PreprocessorReader.fromString(
        document,
        input,
        normalize: true,
      );
      final lines = (<String>[])
        ..add(reader.readLine()!)
        ..add(reader.readLine()!);
      expect(lines.last, equals('contents of include-file.adoc'));
      expect(contentCache.length, equals(1));
      expect(contentCache['include-file.adoc'], equals(lines.last));
    });

    test('should invoke tree processors after parsing document', () {
      const input = '= Document Title\nDoc Writer\n\ncontent\n';

      Extensions.register(
        build: (registry) {
          registry.treeProcessor(processor: ReplaceAuthorTreeProcessor());
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
                processor.onProcess = (doc) {
                  final para = processor.createParagraph(
                    doc.blocks.last.parent!,
                    'file: ${doc.file}, lineno: ${doc.lineno}',
                    <String, String>{},
                  );
                  doc.append(para);
                  return null;
                };
              },
            );
          },
        );

        final sampleDoc = fixturePath('sample.adoc');
        final doc = loadFile(sampleDoc, sourcemap: true);
        expect(doc.convert(), contains('file: sample.adoc, lineno: 1'));
      },
    );

    test('should allow tree processor to replace tree', () {
      const input = '= Original Document\nDoc Writer\n\ncontent\n';

      Extensions.register(
        build: (registry) {
          registry.treeProcessor(processor: ReplaceTreeTreeProcessor());
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
              processor.onProcess = (doc) {
                final ex = doc.findBy(context: BlockContext.example)[0];
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
        doc.findBy(context: BlockContext.example)[0].title,
        equals('New block title'),
      );
    });

    test('should be able to register preferred tree processor', () {
      // Adapted: the registry is activated manually and the process
      // methods are invoked in registry order (no parse/convert).
      Extensions.register(
        build: (registry) {
          TreeProcessorCallback append(TreeProcessor processor, String text) =>
              (doc) {
                doc.append(processor.createParagraph(doc, text, {}));
                return null;
              };
          registry
            ..treeProcessor(
              build: (processor) =>
                  processor.onProcess = append(processor, 'd'),
            )
            ..treeProcessor(
              build: (processor) => processor
                ..prefer()
                ..onProcess = append(processor, 'c'),
            )
            ..prefer(
              registry.treeProcessor(
                build: (processor) =>
                    processor.onProcess = append(processor, 'b'),
              ),
            )
            ..prefer(
              registry.treeProcessor(
                build: (processor) =>
                    processor.onProcess = append(processor, 'a'),
              ),
            )
            ..prefer(
              registry.treeProcessor(processor: SelfSigningTreeProcessor()),
            );
        },
      );

      final doc = emptyDocument();
      final registry = (Registry())..activate(doc);
      for (final ext in registry.treeProcessors) {
        ext.instance.process(doc);
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
          registry.postprocessor(processor: StripAttributesPostprocessor());
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
                processor.onProcess = (doc) {
                  doc.append(
                    processor.createParagraph(doc, 'bye!', <String, String>{}),
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
          registry.block(processor: UppercaseBlock());
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
            registry.block(processor: UppercaseBlock());
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
                processor.onProcess = (parent, reader, attrs) {
                  // Adapted: Dart has no eval; emulate the intent.
                  final source = reader.readLines()[0];
                  final expanded = source.contains('*')
                      ? List.filled(5, 'yolo').join()
                      : source;
                  return processor.createParagraph(
                    parent,
                    expanded,
                    <String, String>{},
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
              processor
                ..onContext('sidebar')
                ..onProcess = (parent, reader, attrs) {
                  cloakedContext = attrs['cloaked-context'];
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
              processor.onProcess = (parent, reader, attrs) {
                return processor.createExampleBlock(
                  parent,
                  reader.readLines().join('\n'),
                  <String, String>{},
                  contentModel: ContentModel.compound,
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
          registry.blockMacro(processor: SnippetMacro(), name: 'snippet');
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
              processor
                ..passAttributesAsText()
                ..onProcess = (parent, target, attrs) {
                  parent.logger.info(attrs['text']!);
                  return null;
                };
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded(input);
        expect(output, isEmpty);
        assertMessage(logger, Severity.info, 'hello, world!');
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
              processor
                ..config.macroAttributes = MacroAttributes.text
                ..onProcess = (parent, target, attrs) {
                  parent.logger.info(attrs['text']!);
                  return null;
                };
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded(input);
        expect(output, isEmpty);
        assertMessage(logger, Severity.info, 'hello, world!');
      });
    });

    test('should substitute attributes in target of custom block macro', () {
      const input = 'snippet::{gist-id}[mode=edit]';

      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SnippetMacro(), name: 'snippet');
        },
      );

      final output = convertStringToEmbedded(
        input,
        const AsciidoctorOptions(attributes: {'gist-id': '12345'}),
      );
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
          Severity.debug,
          '<stdin>: line 1: unknown name for block macro: unknown',
        );
        assertXpath('/*[@class="paragraph"]/p[text()="$input"]', result, 1);
      }, Severity.debug);
    });

    test('should log debug message if custom block macro is unknown when '
        'custom block macros are registered', () {
      const input = 'unknown::[]';
      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SampleBlockMacro(), name: 'sample');
        },
      );
      usingMemoryLogger((logger) {
        final result = convertStringToEmbedded(input);
        assertMessage(
          logger,
          Severity.debug,
          '<stdin>: line 1: unknown name for block macro: unknown',
        );
        assertXpath('/*[@class="paragraph"]/p[text()="$input"]', result, 1);
      }, Severity.debug);
    });

    test('should not log debug message if line is not a custom block macro '
        'and block macros are registered', () {
      const input = '* xref:component::page.adoc[link text]';
      Extensions.register(
        build: (registry) {
          registry.blockMacro(processor: SampleBlockMacro(), name: 'sample');
        },
      );
      usingMemoryLogger((logger) {
        final result = convertStringToEmbedded(input);
        expect(logger.messages, isEmpty);
        assertCss('ul li a[href="component::page.html"]', result, 1);
      }, Severity.debug);
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
          registry.blockMacro(processor: SnippetMacro(), name: 'snippet');
        },
      );

      late final Document doc;
      late final String output;
      usingMemoryLogger((logger) {
        doc = documentFromString(
          input,
          const AsciidoctorOptions(
            attributes: {'attribute-missing': 'drop-line'},
          ),
        );
        expect(doc.blocks.length, equals(1));
        expect(doc.blocks[0].contextName, equals('paragraph'));
        output = doc.convert();
        assertMessage(
          logger,
          Severity.info,
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
              processor.onProcess = (parent, target, attrs) {
                return processor.createParagraph(
                  parent,
                  target.toUpperCase(),
                  <String, String>{},
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
              processor.name = 'custom-toc';
              processor.onProcess = (parent, target, attrs) {
                resolvedTarget = target;
                return processor.createPassBlock(
                  parent,
                  '<!-- custom toc goes here -->',
                  <String, String>{},
                  contentModel: ContentModel.raw,
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
              processor
                ..name = 'illegal name'
                ..onProcess = (parent, target, attrs) => null;
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
            processor: LegacyPosAttrsBlockMacro(),
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
              processor.positionalAttributes(['target', 'format']);
              processor.onProcess = (parent, target, attrs) {
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
          registry
            ..blockMacro(
              build: (processor) {
                processor
                  ..name = 'attribute'
                  ..resolveAttributes(['1:value'])
                  ..onProcess = (parent, target, attrs) {
                    (parent.document! as Document).setAttr(
                      target,
                      attrs['value']!,
                    );
                    return null;
                  };
              },
            )
            ..blockMacro(
              build: (processor) {
                processor
                  ..name = 'header_attribute'
                  ..resolveAttributes(['1:value'])
                  ..onProcess = (parent, target, attrs) {
                    (parent.document! as Document).setHeaderAttribute(
                      target,
                      attrs['value']!,
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
          registry.inlineMacro(processor: TemperatureMacro(), name: 'deg');
        },
      );

      var output = convertStringToEmbedded(
        'Room temperature is deg:25[C,precision=0].',
        const AsciidoctorOptions(attributes: {'temperature-unit': 'F'}),
      );
      expect(output, contains('Room temperature is 25 &#176;C.'));

      output = convertStringToEmbedded(
        'Normal body temperature is deg:37[].',
        const AsciidoctorOptions(attributes: {'temperature-unit': 'F'}),
      );
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
              processor
                ..config.format = 'short'
                ..passAttributesAsText();
              processor.onProcess = (parent, target, attrs) {
                return processor.createInline(
                  parent,
                  InlineContext.quoted,
                  attrs['text'],
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
              processor
                ..config.format = 'short'
                ..config.macroAttributes = MacroAttributes.text;
              processor.onProcess = (parent, target, attrs) {
                return processor.createInline(
                  parent,
                  InlineContext.quoted,
                  attrs['text'],
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
              processor
                ..name = 'label'
                ..config.format = 'short'
                ..config.macroAttributes = MacroAttributes.text
                ..onProcess = (parent, target, attrs) {
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
              processor
                ..name = 'label'
                ..config.format = 'short';
              processor.onProcess = (parent, target, attrs) {
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
          registry
            ..inlineMacro(
              build: (processor) {
                processor
                  ..name = 'json'
                  ..config.format = 'short';
                processor.onProcess = (parent, target, attrs) {
                  final pairs = attrs.entries
                      .map((entry) => '"${entry.key}": "${entry.value}"')
                      .join(', ');
                  return processor.createInlinePass(parent, '{ $pairs }');
                };
              },
            )
            ..inlineMacro(
              build: (processor) {
                processor.name = 'data';
                processor.onProcess = (parent, target, attrs) {
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

      var output = convertStringToEmbedded(
        'json:[a=A,b=B,c=C]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
      expect(output, equals('{ "a": "A", "b": "B", "c": "C" }'));
      output = convertStringToEmbedded(
        'data:json[a=A,b=B,c=C]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
      expect(output, equals('{ "a": "A", "b": "B", "c": "C" }'));
    });

    test('should assign captures correctly for inline macros', () {
      Inline capture(
        InlineMacroProcessor processor,
        AbstractBlock parent,
        String target,
        Map<String, String> attrs,
      ) {
        final sorted = attrs.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final rendered = sorted
            .map((entry) => '"${entry.key}"=>"${entry.value}"')
            .join(', ');
        return processor.createInlinePass(
          parent,
          'target="$target", attributes={$rendered}',
        );
      }

      Extensions.register(
        build: (registry) {
          registry
            ..inlineMacro(
              build: (processor) {
                processor
                  ..name = 'short_attributes'
                  ..config.format = 'short'
                  ..resolveAttributes(['1:name']);
                processor.onProcess = (parent, target, attrs) =>
                    capture(processor, parent, target, attrs);
              },
            )
            ..inlineMacro(
              build: (processor) {
                processor
                  ..name = 'short_text'
                  ..config.format = 'short'
                  ..passAttributesAsText();
                processor.onProcess = (parent, target, attrs) =>
                    capture(processor, parent, target, attrs);
              },
            )
            ..inlineMacro(
              build: (processor) {
                processor
                  ..name = 'full-attributes'
                  ..resolveAttributes(['1:name']);
                processor.onProcess = (parent, target, attrs) =>
                    capture(processor, parent, target, attrs);
              },
            )
            ..inlineMacro(
              build: (processor) {
                processor
                  ..name = 'full-text'
                  ..passAttributesAsText();
                processor.onProcess = (parent, target, attrs) =>
                    capture(processor, parent, target, attrs);
              },
            )
            ..inlineMacro(
              build: (processor) {
                processor
                  ..name = '@short_match'
                  ..config.regexp = RegExp(r'@(\w+)')
                  ..passAttributesAsText();
                processor.onProcess = (parent, target, attrs) =>
                    capture(processor, parent, target, attrs);
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
      const fullAttributes = '{"1"=>"value","key"=>"val","name"=>"value"}';
      const expected =
          'target="",attributes={}\n'
          'target="value,key=val",attributes=$fullAttributes\n'
          'target="",attributes={"text"=>""}\n'
          'target="[text]",attributes={"text"=>"[text]"}\n'
          'target="target",attributes={}\n'
          'target="target",attributes=$fullAttributes\n'
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
                processor
                  ..name = 'mention'
                  ..passAttributesAsText();
                processor.onProcess = (parent, target, attrs) {
                  var text = attrs['text']!;
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
              processor
                ..name = 'skipme'
                ..config.format = 'short'
                ..onProcess = (parent, target, attrs) => null;
            },
          );
        },
      );

      usingMemoryLogger((logger) {
        final output = convertStringToEmbedded(
          '-skipme:[]-',
          const AsciidoctorOptions(doctype: 'inline'),
        );
        expect(output, equals('--'));
        expect(logger.messages, isEmpty);
      });
    });

    test('should not apply subs to inline node returned by process method '
        'by default', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.name = 'say';
              processor.onProcess = (parent, target, attrs) {
                return processor.createInline(
                  parent,
                  InlineContext.quoted,
                  '*$target*',
                  type: 'emphasis',
                );
              };
            },
          );
        },
      );

      final output = convertStringToEmbedded(
        'say:yo[]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
      expect(output, equals('<em>*yo*</em>'));
    });

    test('should apply subs specified as symbol to inline node returned by '
        'process method', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.name = 'say';
              processor.onProcess = (parent, target, attrs) {
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

      final output = convertStringToEmbedded(
        'say:yo[]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
      expect(output, equals('<strong>yo</strong>'));
    });

    test('should apply subs specified as string to inline node returned by '
        'process method', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            build: (processor) {
              processor.name = 'say';
              processor.onProcess = (parent, target, attrs) {
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

      final output = convertStringToEmbedded(
        'say:{lt}message{gt}[]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
      expect(output, equals('<strong>&lt;message&gt;</strong>'));
    });

    test('should prefer attributes parsed from inline macro over default '
        'attributes', () {
      Extensions.register(
        build: (registry) {
          registry.inlineMacro(
            name: 'attrs',
            build: (processor) {
              processor
                ..config.format = 'short'
                ..defaultAttributes({'1': 'a', '2': 'b', 'foo': 'baz'})
                ..positionalAttributes(['a', 'b'])
                ..onProcess = (parent, target, attrs) {
                  return processor.createInlinePass(
                    parent,
                    "a=${attrs['a']},2=${attrs['2']},"
                    "b=${attrs['b'] ?? 'nil'},foo=${attrs['foo']}",
                  );
                };
            },
          );
        },
      );

      final output = convertStringToEmbedded(
        'attrs:[A,foo=bar]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
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
              // Adapted: names are strings in Dart (no symbols).
              processor
                ..config.format = 'short'
                ..positionalAttributes(['a', 'b'])
                ..onProcess = (parent, target, attrs) {
                  return processor.createInlinePass(
                    parent,
                    "a=${attrs['a']},b=${attrs['b']}",
                  );
                };
            },
          );
        },
      );

      final output = convertStringToEmbedded(
        'attrs:[A,B]',
        const AsciidoctorOptions(doctype: 'inline'),
      );
      expect(output, equals('a=A,b=B'));
    });

    test('should not carry over attributes if block processor returns nil', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor
                ..name = 'skip-me'
                ..onContext('paragraph')
                ..config.contentModel = ContentModel.raw
                ..onProcess = (parent, reader, attrs) => null;
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
              processor
                ..name = 'ignore'
                ..onContext('paragraph')
                ..config.contentModel = ContentModel.skip
                ..onProcess = (parent, reader, attrs) {
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
              processor
                ..name = 'foo'
                ..onContext('paragraph')
                ..config.contentModel = ContentModel.raw
                ..onProcess = (parent, reader, attrs) {
                  final originalAttrs = Map<String, String>.of(attrs);
                  attrs.remove('title');
                  return processor.createParagraph(
                    parent,
                    reader.readLines().join('\n'),
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
              processor
                ..name = 'lst'
                ..onContext('paragraph');
              processor.onProcess = (parent, reader, attrs) {
                final list = processor.createList(parent, BlockContext.ulist);
                for (final line in reader.readLines()) {
                  list.append(processor.createListItem(list, line));
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
      expect(list.contextName, equals('ulist'));
      expect(list.items.length, equals(3));
      expect(list.items[0].text, equals('a'));
      assertCss('li', doc.convert(), 3);
    });

    test('should allow extension to replace custom block with a section', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor
                ..name = 'sect'
                ..onContext('open');
              processor.onProcess = (parent, reader, attrs) {
                return processor.createSection(
                  parent,
                  attrs['title']!,
                  <String, String>{},
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
      expect(sect.contextName, equals('section'));
      expect(sect.title, equals('Section Title'));
      expect(sect.blocks.length, equals(2));
      expect(sect.blocks[0].contextName, equals('paragraph'));
      expect(sect.blocks[1].contextName, equals('paragraph'));
      assertCss('p', doc.convert(), 2);
    });

    test('can use parse_content to append blocks to current parent', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor
                ..name = 'csv'
                ..onContext('literal');
              processor.onProcess = (parent, reader, attrs) {
                processor.parseContent(
                  parent,
                  Reader([',===', ...reader.readLines(), ',===']),
                );
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
      expect(table.contextName, equals('table'));
      assertCss('td', doc.convert(), 3);
    });

    test('should ignore return value of custom block if value is parent', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor
                ..name = 'unwrap'
                ..onContext('open');
              processor.onProcess = (parent, reader, attrs) {
                return processor.parseContent(
                  parent,
                  Reader(reader.readLines()),
                );
              };
            },
          );
        },
      );
      const input = '[unwrap]\n--\na\n\nb\n\nc\n--\n';
      final doc = documentFromString(input);
      expect(doc.blocks.length, equals(3));
      for (final block in doc.blocks) {
        expect(block.contextName, equals('paragraph'));
      }
      expect((doc.blocks[0] as Block).source(), equals('a'));
      assertCss('p', doc.convert(), 3);
    });

    test(
      'should ignore return value of custom block macro if value is parent',
      () {
        Extensions.register(
          build: (registry) {
            registry.blockMacro(
              name: 'para',
              build: (processor) {
                processor.onProcess = (parent, target, attrs) {
                  return processor.parseSource(parent, target);
                };
              },
            );
          },
        );
        const input = 'para::text[]\n';
        final doc = documentFromString(input);
        expect(doc.blocks.length, equals(1));
        expect(doc.blocks[0].contextName, equals('paragraph'));
        expect((doc.blocks[0] as Block).source(), equals('text'));
        assertCss('p', doc.convert(), 1);
      },
    );

    test('parse_content should not share attributes between parsed blocks', () {
      Extensions.register(
        build: (registry) {
          registry.block(
            build: (processor) {
              processor
                ..name = 'wrap'
                ..onContext('open');
              processor.onProcess = (parent, reader, attrs) {
                final wrap = processor.createOpenBlock(parent, null, attrs);
                processor.parseContent(wrap, Reader(reader.readLines()));
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
              processor
                ..name = 'attrs'
                ..onContext('open');
              processor.onProcess = (parent, reader, attrs) {
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
              processor.name = 'sect';
              processor.onProcess = (parent, target, attrs) {
                final sectAttrs = Map<String, String>.of(attrs);
                final level = sectAttrs.remove('level');
                final noId = sectAttrs['id'] == 'false';
                if (noId) sectAttrs.remove('id');
                final current = parent.context == BlockContext.preamble
                    ? parent.parent!
                    : parent;
                sect = processor.createSection(
                  current,
                  'Section Title',
                  sectAttrs,
                  level: level == null ? null : int.parse(level),
                  generateId: !noId,
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

      // sectname, level, special, numbered, chapter numbering, id, extra
      // document attributes.
      const cases =
          <
            String,
            (String, int, bool, bool, bool, String?, Map<String, String>)
          >{
            '': ('chapter', 1, false, true, false, '_section_title', {}),
            'level=0': ('part', 0, false, false, false, '_section_title', {}),
            'level=0,alt': (
              'part',
              0,
              false,
              true,
              false,
              '_section_title',
              {'partnums': ''},
            ),
            'level=0,style=appendix': (
              'appendix',
              1,
              true,
              true,
              false,
              '_section_title',
              {},
            ),
            'style=appendix': (
              'appendix',
              1,
              true,
              true,
              false,
              '_section_title',
              {},
            ),
            'style=glossary': (
              'glossary',
              1,
              true,
              false,
              false,
              '_section_title',
              {},
            ),
            'style=glossary,alt': (
              'glossary',
              1,
              true,
              true,
              true,
              '_section_title',
              {'sectnums': 'all'},
            ),
            'style=abstract': (
              'chapter',
              1,
              false,
              true,
              false,
              '_section_title',
              {},
            ),
            'id=section-title': (
              'chapter',
              1,
              false,
              true,
              false,
              'section-title',
              {},
            ),
            'id=false': ('chapter', 1, false, true, false, null, {}),
          };
      cases.forEach((attrlist, expected) {
        final (sectname, level, special, numbered, chapters, id, attrs) =
            expected;
        documentFromString(
          inputFor(attrlist),
          AsciidoctorOptions(safe: SafeMode.server, attributes: attrs),
        );
        expect(sect!.sectname, equals(sectname), reason: attrlist);
        expect(sect!.level, equals(level), reason: attrlist);
        expect(sect!.special, equals(special), reason: attrlist);
        expect(sect!.numbered, equals(numbered), reason: attrlist);
        expect(sect!.chapterNumbering, equals(chapters), reason: attrlist);
        expect(sect!.id, equals(id), reason: attrlist);
      });
    });

    test('should add docinfo to document', () {
      const input = '= Document Title\n\nsample content\n';

      Extensions.register(
        build: (registry) {
          registry.docinfoProcessor(processor: MetaRobotsDocinfoProcessor());
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
          registry
            ..docinfoProcessor(processor: MetaAppDocinfoProcessor())
            ..docinfoProcessor(
              processor: MetaRobotsDocinfoProcessor(
                ProcessorConfig(preferred: true),
              ),
            )
            ..docinfoProcessor(
              build: (processor) {
                processor
                  ..config.location = 'footer'
                  ..onProcess = (doc) =>
                      '<script><!-- analytics code --></script>';
              },
            );
        },
      );

      final doc = documentFromString(
        input,
        const AsciidoctorOptions(safe: SafeMode.server),
      );
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
          registry.docinfoProcessor(processor: MetaRobotsDocinfoProcessor());
        },
      );
      final sampleInputPath = fixturePath('basic.adoc');

      final output = convertFile(
        sampleInputPath,
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
          exts
            ..add(registry.preprocessor(processor: SamplePreprocessor()))
            ..add(
              registry.includeProcessor(processor: SampleIncludeProcessor()),
            )
            ..add(registry.treeProcessor(processor: SampleTreeProcessor()))
            ..add(
              registry.docinfoProcessor(processor: SampleDocinfoProcessor()),
            )
            ..add(registry.postprocessor(processor: SamplePostprocessor()));
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
            contains(
              'No process callback assigned for tree processor extension',
            ),
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
            contains('No process callback assigned for block macro extension'),
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
              processor.onProcess = (parent, reader, attrs) => null;
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
      final ext = registry.registeredForBlockMacro('cat_in_sink')!;
      expect(
        () => ext.instance.process(doc, '', <String, String>{}),
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
        final doc = documentFromString(
          input,
          AsciidoctorOptions(
            standalone: false,
            extensionRegistry: createCatInSinkBlockMacro(),
          ),
        );
        final image = doc.blocks[0];
        expect(image.attr('alt'), equals('cat in sink day 25'));
        expect(image.attr('default-alt'), equals('cat in sink day 25'));
        final output = doc.convert();
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
        final doc = documentFromString(
          input,
          AsciidoctorOptions(
            standalone: false,
            extensionRegistry: createCatInSinkBlockMacro(),
          ),
        );
        final image = doc.blocks[0];
        expect(image.attr('alt'), equals('cat in sink (yes)'));
        expect(image.hasAttr('default-alt'), isFalse);
        final output = doc.convert();
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
      final doc = documentFromString(
        input,
        AsciidoctorOptions(
          standalone: false,
          extensionRegistry: createCatInSinkBlockMacro(),
        ),
      );
      final output = doc.convert();
      assertXpath('/*[@class="imageblock"]/*[@class="title"]', output, 0);
    });

    test('should assign caption on image block if title is set on custom '
        'block macro', () {
      const input = '.Cat in Sink?\ncat_in_sink::30[]\n';
      final doc = documentFromString(
        input,
        AsciidoctorOptions(
          standalone: false,
          extensionRegistry: createCatInSinkBlockMacro(),
        ),
      );
      final output = doc.convert();
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
              processor.onProcess = (parent, target, attrs) {
                return processor.createBlock(parent, BlockContext.image, null, {
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
                processor.config.format = 'short';
                processor.onProcess = (parent, target, attrs) {
                  return processor.createInline(
                    parent,
                    InlineContext.image,
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
      final doc = documentFromString(
        input,
        AsciidoctorOptions(
          standalone: false,
          extensionRegistry: createSantaListBlockMacro(),
        ),
      );
      final output = doc.convert();
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
      final doc = documentFromString(
        input,
        AsciidoctorOptions(
          standalone: false,
          extensionRegistry: createSantaListBlockMacro(),
        ),
      );
      final output = doc.convert();
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

    test('createSection honors an explicit numbered flag', () {
      final processor = SampleBlock();
      final doc = Document(
        null,
        const AsciidoctorOptions(attributes: {'doctype': 'book'}),
      );
      final sect = processor.createSection(
        doc,
        'Section Title',
        <String, String>{},
        numbered: false,
      );
      expect(sect.numbered, equals(false));
      final numbered = processor.createSection(
        doc,
        'Section Title',
        <String, String>{},
        numbered: true,
      );
      expect(numbered.numbered, equals(true));
    });

    test('createSection detects a manpage synopsis section', () {
      final processor = SampleBlock();
      final doc = Document(
        null,
        const AsciidoctorOptions(attributes: {'doctype': 'manpage'}),
      );
      final sect = processor.createSection(doc, 'Synopsis', <String, String>{});
      expect(sect.sectname, equals('synopsis'));
      expect(sect.special, isTrue);
    });

    test('createSection throws for a detached parent', () {
      final processor = SampleBlock();
      final orphan = Block(null, BlockContext.open);
      expect(
        () => processor.createSection(orphan, 'Title', <String, String>{}),
        throwsStateError,
      );
    });

    test('createBlock creates a block with a default content model', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final block = processor.createBlock(
        doc,
        BlockContext.paragraph,
        'hello',
        <String, String>{},
      );
      expect(block, isA<Block>());
      expect(block.contextName, equals('paragraph'));
      expect(block.contentModel, equals(ContentModel.simple));
      expect(block.lines, equals(['hello']));
      expect(block.parent, same(doc));
    });

    test('createList and createListItem link nodes together', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final list = processor.createList(doc, BlockContext.ulist);
      expect(list, isA<ListBlock>());
      expect(list.contextName, equals('ulist'));
      final item = (processor.createListItem(list, 'Guillaume'))
        ..addRole('friendly')
        ..id = 'item-1';
      list.append(item);
      expect(list.items.length, equals(1));
      expect(list.hasItems, isTrue);
      expect(item.hasText, isTrue);
      expect(item.includesRole('friendly'), isTrue);
      expect(item.id, equals('item-1'));
    });

    test('createImageBlock requires the target attribute', () {
      final processor = SampleBlockMacro();
      expect(
        () => processor.createImageBlock(emptyDocument(), <String, String>{}),
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
      final attrs = <String, String>{
        'target': 'cat-in-sink-day-30.png',
        'title': 'Cat in Sink?',
      };
      final block = processor.createImageBlock(doc, attrs);
      expect(block.sourceTitle, equals('Cat in Sink?'));
      expect(block.caption, equals('Figure 1. '));
      expect(block.numeral, equals('1'));
      expect(attrs.containsKey('title'), isFalse);
    });

    test('createInline defaults quoted nodes to unquoted', () {
      final processor = SampleInlineMacro();
      final doc = emptyDocument();
      final quoted = processor.createInline(doc, InlineContext.quoted, '*hi*');
      expect(quoted.type, equals('unquoted'));
      expect(quoted.text, equals('*hi*'));
      final explicit = processor.createInline(
        doc,
        InlineContext.quoted,
        '*hi*',
        type: 'emphasis',
      );
      expect(explicit.type, equals('emphasis'));
      final anchor = processor.createInline(
        doc,
        InlineContext.anchor,
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
      final attrs = <String, String>{};
      expect(
        processor.createParagraph(doc, 'x', attrs).contextName,
        equals('paragraph'),
      );
      expect(
        processor.createOpenBlock(doc, 'x', attrs).contextName,
        equals('open'),
      );
      expect(
        processor.createExampleBlock(doc, 'x', attrs).contextName,
        equals('example'),
      );
      expect(
        processor.createPassBlock(doc, 'x', attrs).contextName,
        equals('pass'),
      );
      expect(
        processor.createListingBlock(doc, 'x', attrs).contextName,
        equals('listing'),
      );
      expect(
        processor.createLiteralBlock(doc, 'x', attrs).contextName,
        equals('literal'),
      );
      final anchor = processor.createAnchor(doc, 'text', target: 't');
      expect(anchor.contextName, equals('anchor'));
      expect(anchor.target, equals('t'));
      final pass = processor.createInlinePass(doc, '<b>hi</b>');
      expect(pass.contextName, equals('quoted'));
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
      final doc = emptyDocument(
        const AsciidoctorOptions(attributes: {'foo': 'bar'}),
      );
      final attrs = processor.parseAttributes(
        doc,
        'foo={foo}',
        subAttributes: true,
      );
      expect(attrs['foo'], equals('bar'));
    });

    test('parseSource parses blocks into the parent', () {
      final processor = SampleBlock();
      final doc = emptyDocument();
      final parent = processor.parseSource(doc, 'content');
      expect(parent, same(doc));
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks[0].contextName, equals('paragraph'));
    });
  });

  group('Dsl', () {
    test('named and content model helpers set config', () {
      final processor = (SampleBlock())..name = 'shout';
      expect(processor.name, equals('shout'));
      processor.config.contentModel = ContentModel.simple;
      expect(processor.config.contentModel, equals(ContentModel.simple));
    });

    test('positional and default attribute helpers set config', () {
      final processor = (SampleInlineMacro())..positionalAttributes(['a', 'b']);
      expect(processor.config.positionalAttrs, equals(['a', 'b']));
      processor.defaultAttributes({'1': 'a', 'foo': 'baz'});
      expect(processor.config.defaultAttrs, equals({'1': 'a', 'foo': 'baz'}));
    });

    test('resolveAttributes handles list specifications', () {
      final processor = (SampleInlineMacro())
        ..resolveAttributes(['1:units', 'precision=1']);
      expect(processor.config.positionalAttrs, equals(['units']));
      expect(processor.config.defaultAttrs, equals({'precision': '1'}));
      expect(processor.config.macroAttributes, equals(MacroAttributes.parsed));
    });

    test('passAttributesAsText selects the text content model', () {
      final processor = (SampleBlockMacro())..passAttributesAsText();
      expect(processor.config.macroAttributes, equals(MacroAttributes.text));
    });

    test('resolveAttributes with no arguments resets both lists', () {
      final processor = (SampleBlockMacro())
        ..resolveAttributes(['1:value'])
        ..resolveAttributes();
      expect(processor.config.positionalAttrs, isEmpty);
      expect(processor.config.defaultAttrs, isEmpty);
      expect(processor.config.macroAttributes, equals(MacroAttributes.parsed));
    });

    test('resolveAttributes handles @ indices and offset slots', () {
      final processor = (SampleInlineMacro())
        ..resolveAttributes(['@:first', '2:third']);
      expect(processor.config.positionalAttrs, equals(['first', 'third']));
    });

    test('block contexts normalize and bind', () {
      final implied = SampleBlock();
      expect(implied.config.contexts, equals({'open', 'paragraph'}));
      expect(implied.config.contentModel, equals(ContentModel.compound));
      final single = SampleBlock('x', ProcessorConfig(contexts: {'paragraph'}));
      expect(single.config.contexts, equals({'paragraph'}));
      final bound = (SampleBlock())..onContext('literal');
      expect(bound.config.contexts, equals({'literal'}));
      bound.contexts(['open']);
      expect(bound.config.contexts, equals({'open'}));
    });

    test('macro processors default to the attributes content model', () {
      expect(
        SampleBlockMacro().config.macroAttributes,
        equals(MacroAttributes.parsed),
      );
      expect(
        SampleInlineMacro().config.macroAttributes,
        equals(MacroAttributes.parsed),
      );
    });

    test('prefer marks the processor as preferred', () {
      expect(SampleTreeProcessor().config.preferred, isFalse);
      final processor = (SampleTreeProcessor())..prefer();
      expect(processor.config.preferred, isTrue);
    });

    test('docinfo location defaults to head', () {
      final processor = SampleDocinfoProcessor();
      expect(processor.config.location, equals('head'));
      processor.config.location = 'footer';
      expect(processor.config.location, equals('footer'));
    });

    test('subclass constructors supply class-wide defaults', () {
      final upper = UppercaseBlock();
      expect(upper.name, equals('yell'));
      expect(upper.config.contexts, equals({'paragraph'}));
      expect(upper.config.positionalAttrs, equals(['chars']));
      expect(upper.config.contentModel, equals(ContentModel.simple));
      final temperature = TemperatureMacro();
      expect(temperature.name, equals('degrees'));
      expect(temperature.config.positionalAttrs, equals(['units']));
      expect(temperature.config.defaultAttrs, equals({'precision': '1'}));
      final legacy = LegacyPosAttrsBlockMacro();
      expect(legacy.config.positionalAttrs, equals(['target', 'format']));
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
      final processor = (SampleInlineMacro('label'))..config.format = 'short';
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
      expect(processor.config.regexp, same(first));
      expect(InlineMacroProcessor.resolveRegexp('say', null), same(first));
    });

    test('explicit match pattern wins over resolution', () {
      final processor = SampleInlineMacro('@short_match');
      final pattern = RegExp(r'@(\w+)');
      processor.config.regexp = pattern;
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
          processor.onProcess = (doc) => null;
        },
      );
      final second = registry.treeProcessor(
        build: (processor) {
          processor.onProcess = (doc) => null;
        },
      );
      expect(registry.treeProcessors, equals([first, second]));
      registry.prefer(first);
      expect(registry.treeProcessors, equals([first, second]));
      registry.prefer(second);
      expect(registry.treeProcessors, equals([second, first]));
    });

    test('prefer rejects foreign and syntax extensions', () {
      final registry = Registry();
      final foreign = ProcessorExtension(
        'tree_processor',
        SampleTreeProcessor(),
      );
      expect(() => registry.prefer(foreign), throwsStateError);
      registry.block(processor: SampleBlock(), name: 'sample');
      final syntax = registry.findBlockExtension('sample')!;
      expect(() => registry.prefer(syntax), throwsStateError);
    });

    test('preferred config inserts at the front', () {
      final registry = (Registry())
        ..preprocessor(processor: SamplePreprocessor());
      final preferred = registry.preprocessor(
        processor: SamplePreprocessor(ProcessorConfig(preferred: true)),
      );
      expect(registry.preprocessors.first, same(preferred));
    });

    test('docinfo processors filter by location', () {
      final registry = Registry();
      expect(registry.hasDocinfoProcessors(), isFalse);
      expect(registry.docinfoProcessors(), isEmpty);
      registry
        ..docinfoProcessor(processor: MetaAppDocinfoProcessor())
        ..docinfoProcessor(
          build: (processor) {
            processor
              ..config.location = 'footer'
              ..onProcess = (doc) => 'footer';
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
      final instance = SamplePreprocessor(ProcessorConfig());
      final ext = registry.preprocessor(processor: instance);
      expect(ext.kind, equals('preprocessor'));
      expect(ext.instance, same(instance));
      expect(ext.config, same(instance.config));
    });

    test('instances run the family process callbacks', () {
      final registry = Registry();
      final doc = emptyDocument();

      final tree = registry.treeProcessor(
        build: (processor) {
          processor.onProcess = (document) {
            document.append(
              processor.createParagraph(document, 'hi', <String, String>{}),
            );
            return null;
          };
        },
      );
      tree.instance.process(doc);
      expect(doc.blocks.length, equals(1));

      final post = registry.postprocessor(
        build: (processor) {
          processor.onProcess = (document, output) => '$output!';
        },
      );
      expect(post.instance.process(doc, 'hi'), equals('hi!'));

      final pre = registry.preprocessor(
        build: (processor) {
          processor.onProcess = (document, reader) => reader;
        },
      );
      final reader = Reader.fromString('hi');
      expect(pre.instance.process(doc, reader), same(reader));

      final block = registry.block(
        name: 'shout',
        build: (processor) {
          processor.onProcess = (parent, reader, attrs) {
            return processor.createParagraph(
              parent,
              reader.lines.map((line) => line.toUpperCase()).join('\n'),
              attrs,
            );
          };
        },
      );
      final created =
          block.instance.process(doc, Reader.fromString('hi'), {})! as Block;
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
        () => SampleBlock().process(doc, Reader(const []), <String, String>{}),
        throwsUnimplementedError,
      );
      expect(
        () => SampleBlockMacro().process(doc, 't', <String, String>{}),
        throwsUnimplementedError,
      );
      expect(
        () => SampleInlineMacro().process(doc, 't', <String, String>{}),
        throwsUnimplementedError,
      );
    });

    test('instance registration honors name overrides', () {
      final registry = Registry();
      final instance = SampleBlock('original');
      final ext = registry.block(processor: instance, name: 'override');
      expect(instance.name, equals('override'));
      expect(registry.findBlockExtension('override'), same(ext));
      expect(registry.findBlockExtension('original'), isNull);
    });

    test('later syntax registrations win for the same name', () {
      final registry = Registry();
      final first = registry.blockMacro(
        processor: SampleBlockMacro(),
        name: 'sample',
      );
      final second = registry.blockMacro(
        processor: SampleBlockMacro(),
        name: 'sample',
      );
      expect(registry.registeredForBlockMacro('sample'), same(second));
      expect(registry.registeredForBlockMacro('sample'), isNot(same(first)));
    });

    test('registry groups stay independent from global groups', () {
      Extensions.register(name: 'global', group: SampleExtensionGroup());
      final registry = Extensions.create(
        name: 'local',
        build: (r) {
          r.preprocessor(processor: SamplePreprocessor());
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
