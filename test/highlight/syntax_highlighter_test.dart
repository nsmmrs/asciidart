/// Port of the framework assertions in `test/syntax_highlighter_test.rb`
/// (registration, factory selection including the unknown-highlighter
/// fallback, `Document` integration and docinfo aggregation).
///
/// All tests run, including the `Document` integration group (parse and
/// convert). Adapter behavior itself is covered by the per-adapter suites
/// in this directory — here the adapters appear only behind
/// [FakeSourceLexer] to prove the framework plumbing (option routing,
/// node/document attribute reads). Converted-output assertions route
/// through the test-only `_assertCss` matcher below.
library;

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

import 'fake_source_lexer.dart';

/// The CDN root the converter passes to docinfo in these tests.
const String cdnBaseUrl = 'https://cdnjs.cloudflare.com/ajax/libs';

/// A client-side custom highlighter (port of the `'unavailable'` class in
/// the Ruby suite: `format` only, `canHighlight` false).
class _UnavailableHighlighter extends SyntaxHighlighterBase {
  @override
  String get name => 'unavailable';

  @override
  String format(AbstractBlock node, String? language, FormatOptions opts) =>
      '<pre class="highlight">'
      '<code class="language-$language" data-lang="$language">'
      '${node.content()}</code></pre>';
}

/// A nameless highlighter (rejected by `create`, mirroring Ruby's
/// `NameError`).
class _NamelessHighlighter extends SyntaxHighlighterBase {
  @override
  String get name => '';
}

/// A listing block with canned converted content (avoids the substitutor
/// wave).
class _StubBlock extends Block {
  new(
    AbstractBlock? parent,
    this.stubbedContent, [
    Map<String, String>? attributes,
  ]) : super(parent, 'listing', attributes: attributes ?? <String, String>{});

  /// The value [content] returns.
  final String stubbedContent;

  @override
  String? content() => stubbedContent;
}

/// Creates an unparsed document with [attributes] (no parser needed: the
/// constructor applies attribute overrides and backend traits eagerly).
Document _docWithAttributes(
  Map<String, String?> attributes, {
  String backend = 'html5',
  AsciidoctorOptions options = const AsciidoctorOptions(),
}) => Document.lines(
  <String>[],
  options.copyWith(backend: backend, attributes: attributes),
);

/// Creates a document from [src] (port of `document_from_string`).
Document _documentFromString(
  String src, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
  bool parse = true,
]) {
  final doc = Document(src, options);
  return parse ? doc.parse() : doc;
}

/// Converts [src] to a standalone document (port of `convert_string`).
String _convertString(
  String src, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => _documentFromString(src, options).convert();

/// Asserts [content] matches [css] [count] times (port of `assert_css`).
void _assertCss(String css, String? content, int count) {
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
// `assert_css` helper in `test/test_helper.rb`; mirrors the fuller engine in
// `test/extensions_test.dart`, restricted to the shapes this suite uses:
// tag, `.class`, `[attr="value"]`, descendant and child combinators).
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
/// `texts` segments.
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

  /// The parent element, if any.
  _XmlElement? parent;

  /// All descendants in document order.
  Iterable<_XmlElement> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
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
  for (final match in tagRx.allMatches(content)) {
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

void main() {
  group('registration', () {
    test('registers and retrieves a custom highlighter by name', () {
      SyntaxHighlighterBase makeUnavailable(
        String name,
        String backend,
        HighlighterOptions opts,
      ) => _UnavailableHighlighter();
      final factory = makeUnavailable;
      SyntaxHighlighter.register(factory, <String>['hlfw-foobar']);
      expect(
        identical(SyntaxHighlighter.forName('hlfw-foobar'), factory),
        isTrue,
      );
    });

    test('registers one highlighter under several names', () {
      final instance = _UnavailableHighlighter();
      SyntaxHighlighter.registerInstance(instance, <String>[
        'hlfw-multi',
        'hlfw.multi',
      ]);
      expect(SyntaxHighlighter.create('hlfw-multi'), same(instance));
      expect(SyntaxHighlighter.create('hlfw.multi'), same(instance));
    });

    test('registers the six built-in adapters', () {
      for (final name in <String>[
        'coderay',
        'highlightjs',
        'highlight.js',
        'html-pipeline',
        'prettify',
        'pygments',
        'rouge',
      ]) {
        expect(SyntaxHighlighter.forName(name), isNotNull, reason: name);
      }
    });

    test('returns null for unknown names', () {
      expect(SyntaxHighlighter.forName('hlfw-no-such-highlighter'), isNull);
      expect(SyntaxHighlighter.create('hlfw-no-such-highlighter'), isNull);
    });
  });

  group('factory selection', () {
    test('creates the registered wrapper for each built-in name', () {
      expect(SyntaxHighlighter.create('coderay'), isA<CodeRayHighlighter>());
      expect(
        SyntaxHighlighter.create('highlightjs'),
        isA<HighlightJsHighlighter>(),
      );
      expect(
        SyntaxHighlighter.create('highlight.js'),
        isA<HighlightJsHighlighter>(),
      );
      expect(
        SyntaxHighlighter.create('html-pipeline'),
        isA<HtmlPipelineHighlighter>(),
      );
      expect(SyntaxHighlighter.create('prettify'), isA<PrettifyHighlighter>());
      expect(SyntaxHighlighter.create('pygments'), isA<PygmentsHighlighter>());
      expect(SyntaxHighlighter.create('rouge'), isA<RougeHighlighter>());
    });

    test('resolves aliases to the canonical name', () {
      expect(SyntaxHighlighter.create('highlight.js')!.name, 'highlightjs');
    });

    test('returns null when the highlighter cannot be resolved', () {
      expect(SyntaxHighlighter.create('unknown'), isNull);
    });

    test('passes the backend and options to the factory', () {
      String? seenBackend;
      HighlighterOptions? seenOpts;
      SyntaxHighlighter.register((name, backend, opts) {
        seenBackend = backend;
        seenOpts = opts;
        return _UnavailableHighlighter();
      }, <String>['hlfw-capture']);
      final lexer = FakeSourceLexer();
      SyntaxHighlighter.create(
        'hlfw-capture',
        'docbook5',
        HighlighterOptions(lexer: lexer),
      );
      expect(seenBackend, 'docbook5');
      expect(seenOpts!.lexer, same(lexer));
    });

    test('defaults the backend to html5', () {
      String? seenBackend;
      SyntaxHighlighter.register((name, backend, opts) {
        seenBackend = backend;
        return _UnavailableHighlighter();
      }, <String>['hlfw-backend-default']);
      SyntaxHighlighter.create('hlfw-backend-default');
      expect(seenBackend, 'html5');
    });

    test('returns a registered instance as-is', () {
      final instance = _UnavailableHighlighter();
      SyntaxHighlighter.registerInstance(instance, <String>['hlfw-instance']);
      expect(
        identical(SyntaxHighlighter.create('hlfw-instance'), instance),
        isTrue,
      );
    });

    test('rejects instances without a name', () {
      SyntaxHighlighter.registerInstance(_NamelessHighlighter(), <String>[
        'hlfw-nameless',
      ]);
      expect(() => SyntaxHighlighter.create('hlfw-nameless'), throwsStateError);
    });

    test('injects the lexer backend from the create options', () {
      final lexer = FakeSourceLexer();
      final created = SyntaxHighlighter.create(
        'rouge',
        'html5',
        HighlighterOptions(lexer: lexer),
      );
      expect(created, isA<RougeHighlighter>());
      expect((created! as RougeHighlighter).adapter.lexer, same(lexer));
      expect(created.canHighlight, isTrue);
    });

    test('isolates custom factory registries', () {
      final factory = SyntaxHighlighterFactory();
      expect(factory.forName('rouge'), isNull);
      expect(factory.create('rouge'), isNull);
      SyntaxHighlighterBase makeCustom(
        String name,
        String backend,
        HighlighterOptions opts,
      ) => _UnavailableHighlighter();
      final custom = makeCustom;
      factory.register(custom, <String>['hlfw-custom-only']);
      expect(identical(factory.forName('hlfw-custom-only'), custom), isTrue);
      expect(
        factory.create('hlfw-custom-only'),
        isA<_UnavailableHighlighter>(),
      );
      expect(SyntaxHighlighter.forName('hlfw-custom-only'), isNull);
    });

    test('seeds a custom factory from a registry map', () {
      final instance = _UnavailableHighlighter();
      final factory = SyntaxHighlighterFactory({
        'hlfw-seeded': (name, backend, opts) => instance,
      });
      expect(identical(factory.create('hlfw-seeded'), instance), isTrue);
    });

    test('falls back to the global registry for unseeded names', () {
      final proxy = SyntaxHighlighterDefaultFactoryProxy({
        'hlfw-seed': (name, backend, opts) => _UnavailableHighlighter(),
      });
      expect(proxy.create('hlfw-seed'), isA<_UnavailableHighlighter>());
      expect(proxy.create('rouge'), isA<RougeHighlighter>());
    });

    test('prefers the seed registry over the globals', () {
      final proxy = SyntaxHighlighterDefaultFactoryProxy({
        'rouge': (name, backend, opts) => _UnavailableHighlighter(),
      });
      expect(proxy.create('rouge'), isA<_UnavailableHighlighter>());
      // The global registration is untouched.
      expect(SyntaxHighlighter.create('rouge'), isA<RougeHighlighter>());
    });
  });

  group('Document integration', () {
    test('resolves the highlighter when source-highlighter is set', () {
      final doc = _docWithAttributes(<String, String?>{
        'source-highlighter': 'coderay',
      });
      final resolved = SyntaxHighlighter.resolveForDocument(doc);
      expect(resolved, isA<CodeRayHighlighter>());
      doc.syntaxHighlighter = resolved;
      expect(doc.syntaxHighlighter, same(resolved));
    });

    test('returns null when the base backend is not html', () {
      final doc = _docWithAttributes(<String, String?>{
        'source-highlighter': 'coderay',
      }, backend: 'docbook');
      expect(doc.basebackend('html'), isFalse);
      expect(SyntaxHighlighter.resolveForDocument(doc), isNull);
    });

    test('returns null when source-highlighter is not set', () {
      expect(
        SyntaxHighlighter.resolveForDocument(
          _docWithAttributes(<String, String?>{}),
        ),
        isNull,
      );
    });

    test('returns null when the highlighter name is unknown', () {
      expect(
        SyntaxHighlighter.resolveForDocument(
          _docWithAttributes(<String, String?>{
            'source-highlighter': 'unknown',
          }),
        ),
        isNull,
      );
    });

    test('returns null when the highlighter is marked unavailable', () {
      expect(
        SyntaxHighlighter.resolveForDocument(
          _docWithAttributes(<String, String?>{
            'source-highlighter': 'coderay',
            'coderay-unavailable': '',
          }),
        ),
        isNull,
      );
    });

    test('honors the syntax_highlighter_factory document option', () {
      final factory = (SyntaxHighlighterFactory())
        ..registerInstance(_UnavailableHighlighter(), <String>['unavailable']);
      final doc = _docWithAttributes(<String, String?>{
        'source-highlighter': 'unavailable',
      }, options: AsciidoctorOptions(syntaxHighlighterFactory: factory));
      expect(
        SyntaxHighlighter.resolveForDocument(doc),
        isA<_UnavailableHighlighter>(),
      );
    });

    test('does not fall back to the globals with a custom factory', () {
      final doc = _docWithAttributes(
        <String, String?>{'source-highlighter': 'rouge'},
        options: AsciidoctorOptions(
          syntaxHighlighterFactory: SyntaxHighlighterFactory(),
        ),
      );
      expect(SyntaxHighlighter.resolveForDocument(doc), isNull);
    });

    test('honors the syntax_highlighters document option', () {
      final doc = _docWithAttributes(
        <String, String?>{'source-highlighter': 'coderay'},
        options: AsciidoctorOptions(
          syntaxHighlighters: {
            'coderay': (name, backend, opts) => _UnavailableHighlighter(),
          },
        ),
      );
      expect(
        SyntaxHighlighter.resolveForDocument(doc),
        isA<_UnavailableHighlighter>(),
      );
    });

    test('falls back to the globals for names missing from the option map', () {
      final doc = _docWithAttributes(
        <String, String?>{'source-highlighter': 'rouge'},
        options: AsciidoctorOptions(
          syntaxHighlighters: {
            'coderay': (name, backend, opts) => _UnavailableHighlighter(),
          },
        ),
      );
      expect(
        SyntaxHighlighter.resolveForDocument(doc),
        isA<RougeHighlighter>(),
      );
    });
  });

  group('base contract', () {
    test('does not highlight when canHighlight is false', () {
      final highlighter = _UnavailableHighlighter();
      expect(highlighter.canHighlight, isFalse);
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1');
      expect(
        () => highlighter.highlight(block, 'puts 1', 'ruby'),
        throwsUnimplementedError,
      );
    });

    test('reports no docinfo by default', () {
      final highlighter = _UnavailableHighlighter();
      expect(highlighter.hasDocinfo('head'), isFalse);
      expect(highlighter.hasDocinfo('footer'), isFalse);
    });

    test('throws from docinfo when unimplemented', () {
      final highlighter = HtmlPipelineHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      expect(
        () => highlighter.docinfo(
          'head',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        throwsUnimplementedError,
      );
    });

    test('reports no stylesheet file by default', () {
      final highlighter = HighlightJsHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      expect(highlighter.wantsStylesheetFile(doc), isFalse);
      expect(
        () => highlighter.writeStylesheet(doc, '.'),
        throwsUnimplementedError,
      );
    });

    test('wraps content in the base pre/code envelope', () {
      final highlighter = CodeRayHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', const FormatOptions()),
        '<pre class="CodeRay highlight">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('appends nowrap and runs the transform with data-lang last', () {
      final highlighter = CodeRayHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x');
      expect(
        highlighter.format(
          block,
          'ruby',
          FormatOptions(
            nowrap: true,
            transform: (pre, code) => code['class'] = 'language-ruby hljs',
          ),
        ),
        '<pre class="CodeRay highlight nowrap">'
        '<code class="language-ruby hljs" data-lang="ruby">x</code></pre>',
      );
    });
  });

  group('format wiring', () {
    test('marks highlight.js blocks for client-side highlighting', () {
      final highlighter = HighlightJsHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', const FormatOptions()),
        '<pre class="highlightjs highlight">'
        '<code class="language-ruby hljs" data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('uses language-none when the language is absent', () {
      final highlighter = HighlightJsHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x');
      expect(
        highlighter.format(block, null, const FormatOptions()),
        '<pre class="highlightjs highlight">'
        '<code class="language-none hljs">x</code></pre>',
      );
    });

    test('numbers prettify lines from the start attribute', () {
      final highlighter = PrettifyHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x')
        ..setAttr('linenums', '')
        ..setAttr('start', '7');
      expect(
        highlighter.format(block, 'ruby', const FormatOptions()),
        '<pre class="prettyprint highlight linenums:7">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('numbers prettify lines without a start value', () {
      final highlighter = PrettifyHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x')..setAttr('linenums', '');
      expect(
        highlighter.format(block, 'ruby', const FormatOptions()),
        '<pre class="prettyprint highlight linenums">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('emits html-pipeline pre hooks', () {
      final highlighter = HtmlPipelineHighlighter();
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', const FormatOptions(nowrap: true)),
        '<pre lang="ruby"><code>puts 1</code></pre>',
      );
    });

    test('attaches the rouge base style in inline-css mode', () {
      final lexer = FakeSourceLexer(
        onStyleAvailable: (style) => true,
        onBaseStyle: (style) => 'color: #f8f8f2;background-color: #49483e',
      );
      final highlighter = RougeHighlighter(lexer: lexer);
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(
          block,
          'ruby',
          const FormatOptions(cssMode: CssMode.inline, style: 'monokai'),
        ),
        '<pre class="rouge highlight" '
        'style="color: #f8f8f2;background-color: #49483e">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('omits the pre style in class mode', () {
      final lexer = FakeSourceLexer(
        onStyleAvailable: (style) => true,
        onBaseStyle: (style) => 'color: #000;',
      );
      final highlighter = PygmentsHighlighter(lexer: lexer);
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x');
      expect(
        highlighter.format(block, 'ruby', const FormatOptions()),
        '<pre class="pygments highlight">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });
  });

  group('highlight wiring', () {
    test('routes rouge highlight options to the backend', () {
      final lexer = FakeSourceLexer(
        onHighlight: (request) => '<span class="nb">puts</span> 1',
        onStyleAvailable: (style) => style == 'monokai',
      );
      final highlighter = RougeHighlighter(lexer: lexer);
      expect(highlighter.canHighlight, isTrue);
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1')..setOption('mixed');
      final result = highlighter.highlight(
        block,
        'puts 1',
        'ruby',
        highlightLines: <int>[1],
        style: 'monokai',
      );
      expect(
        result.html,
        '<span class="hll"><span class="nb">puts</span> 1\n</span>',
      );
      final request = lexer.lastRequest!;
      expect(request.language, 'ruby');
      expect(request.mixed, isTrue);
      expect(request.style, 'monokai');
      expect(request.highlightLines, <int>[1]);
    });

    test('routes pygments highlight options to the backend', () {
      final lexer = FakeSourceLexer(
        onHighlight: (request) => '<div class="lineno"><pre><span class="tok-n">puts</span> 1</pre></div>',
        onStyleAvailable: (style) => true,
      );
      final highlighter = PygmentsHighlighter(lexer: lexer);
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'puts 1');
      final result = highlighter.highlight(
        block,
        'puts 1',
        'ruby',
        style: 'colorful',
      );
      expect(result.html, '<span class="tok-n">puts</span> 1');
      final request = lexer.lastRequest!;
      expect(request.language, 'ruby');
      expect(request.mixed, isFalse);
      expect(request.style, 'colorful');
    });

    test('maps callouts to the coderay table offset', () {
      const backendHtml =
          '<table><tr><td class="code"><pre>x</pre></td></tr></table>';
      final lexer = FakeSourceLexer(onHighlight: (request) => backendHtml);
      final highlighter = CodeRayHighlighter(lexer: lexer);
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x');
      final withCallouts = highlighter.highlight(
        block,
        'x',
        'ruby',
        numberLines: LineNumbersMode.table,
        callouts: <int, String>{1: 'callout'},
      );
      expect(withCallouts.html, backendHtml);
      expect(
        withCallouts.sourceOffset,
        backendHtml.indexOf('<td class="code"><pre>') +
            '<td class="code"><pre>'.length,
      );
      expect(lexer.lastRequest!.numberLines, LineNumbersMode.table);
      final withoutCallouts = highlighter.highlight(
        block,
        'x',
        'ruby',
        numberLines: LineNumbersMode.table,
      );
      expect(withoutCallouts.sourceOffset, isNull);
    });

    test('throws when highlighting without a lexer backend', () {
      final doc = _docWithAttributes(<String, String?>{});
      final block = _StubBlock(doc, 'x');
      expect(CodeRayHighlighter().canHighlight, isFalse);
      expect(
        () => CodeRayHighlighter().highlight(block, 'x', 'ruby'),
        throwsUnimplementedError,
      );
      expect(
        () => PygmentsHighlighter().highlight(block, 'x', 'ruby'),
        throwsUnimplementedError,
      );
      expect(
        () => RougeHighlighter().highlight(block, 'x', 'ruby'),
        throwsUnimplementedError,
      );
    });
  });

  group('docinfo aggregation', () {
    test('reports docinfo locations per adapter', () {
      final highlightjs = HighlightJsHighlighter();
      expect(highlightjs.hasDocinfo('head'), isTrue);
      expect(highlightjs.hasDocinfo('footer'), isTrue);
      final prettify = PrettifyHighlighter();
      expect(prettify.hasDocinfo('head'), isTrue);
      expect(prettify.hasDocinfo('footer'), isTrue);
      final pipeline = HtmlPipelineHighlighter();
      expect(pipeline.hasDocinfo('head'), isFalse);
      expect(pipeline.hasDocinfo('footer'), isFalse);
    });

    test('links the highlight.js theme in the head', () {
      final doc = _docWithAttributes(<String, String?>{});
      expect(
        HighlightJsHighlighter().docinfo(
          'head',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        '<link rel="stylesheet" '
        'href="$cdnBaseUrl/highlight.js/9.18.3/styles/github.min.css">',
      );
    });

    test('loads highlight.js languages in the footer', () {
      final doc = _docWithAttributes(<String, String?>{
        'highlightjs-languages': 'ruby, python',
      });
      expect(
        HighlightJsHighlighter().docinfo(
          'footer',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        '<script src="$cdnBaseUrl/highlight.js/9.18.3/highlight.min.js">'
        '</script>\n'
        '<script src="$cdnBaseUrl/highlight.js/9.18.3/languages/ruby.min.js">'
        '</script>\n'
        '<script src="$cdnBaseUrl/highlight.js/9.18.3/languages/python.min.js">'
        '</script>\n'
        '<script>\n'
        'if (!hljs.initHighlighting.called) {\n'
        '  hljs.initHighlighting.called = true\n'
        "  ;[].slice.call(document.querySelectorAll('pre.highlight > "
        "code[data-lang]')).forEach(function (el) { "
        'hljs.highlightBlock(el) })\n'
        '}\n'
        '</script>',
      );
    });

    test('links the prettify theme in the head', () {
      final doc = _docWithAttributes(<String, String?>{});
      expect(
        PrettifyHighlighter().docinfo(
          'head',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        '<link rel="stylesheet" '
        'href="$cdnBaseUrl/prettify/r298/prettify.min.css">',
      );
    });

    test('passes absolute prettify themes through verbatim', () {
      final doc = _docWithAttributes(<String, String?>{
        'prettify-theme': 'https://example.com/custom.min.css',
      });
      expect(
        PrettifyHighlighter().docinfo(
          'head',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        '<link rel="stylesheet" '
        'href="https://example.com/custom.min.css">',
      );
    });

    test('loads the prettify runner in the footer', () {
      final doc = _docWithAttributes(<String, String?>{});
      expect(
        PrettifyHighlighter().docinfo(
          'footer',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        '<script src="$cdnBaseUrl/prettify/r298/run_prettify.min.js">'
        '</script>',
      );
    });

    test('gates server docinfo on highlighted output', () {
      final lexer = FakeSourceLexer(onHighlight: (request) => 'x');
      final highlighter = CodeRayHighlighter(lexer: lexer);
      expect(highlighter.hasDocinfo('head'), isFalse);
      final doc = _docWithAttributes(<String, String?>{});
      highlighter.highlight(_StubBlock(doc, 'x'), 'x', 'ruby');
      expect(highlighter.hasDocinfo('head'), isTrue);
      expect(highlighter.hasDocinfo('footer'), isFalse);
      expect(highlighter.wantsStylesheetFile(doc), isTrue);
    });

    test('links the coderay stylesheet when linkcss is set', () {
      final lexer = FakeSourceLexer(onHighlight: (request) => 'x');
      final highlighter = CodeRayHighlighter(lexer: lexer);
      final doc = _docWithAttributes(<String, String?>{'stylesdir': 'css'});
      highlighter.highlight(_StubBlock(doc, 'x'), 'x', 'ruby');
      expect(
        highlighter.docinfo(
          'head',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: true,
          selfClosingTagSlash: '/',
        ),
        '<link rel="stylesheet" href="css/coderay-asciidoctor.css"/>',
      );
    });

    test('embeds the rouge stylesheet for the resolved style', () {
      final lexer = FakeSourceLexer(
        onHighlight: (request) => 'x',
        onStylesheet: (style) => '/* $style */',
      );
      final highlighter = RougeHighlighter(lexer: lexer);
      final doc = _docWithAttributes(<String, String?>{});
      highlighter.highlight(
        _StubBlock(doc, 'x'),
        'x',
        'ruby',
        style: 'monokai',
      );
      // 'monokai' is unknown to the fake, so the default style wins.
      expect(
        highlighter.docinfo(
          'head',
          doc,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: false,
          selfClosingTagSlash: '',
        ),
        '<style>\n/* github */\n</style>',
      );
    });
  });

  group('Ruby suite ports: parse and convert integration', () {
    test(
      'sets syntax_highlighter on the document when source-highlighter is set',
      () {
        const input =
            ':source-highlighter: coderay\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final doc = _documentFromString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.basebackend('html'), isTrue);
        expect(doc.syntaxHighlighter, isNotNull);
        expect(doc.syntaxHighlighter, isA<SyntaxHighlighterBase>());
      },
    );

    test(
      'leaves syntax_highlighter unset when the base backend is not html',
      () {
        const input =
            ':source-highlighter: coderay\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final doc = _documentFromString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe, backend: 'docbook'),
        );
        expect(doc.basebackend('html'), isFalse);
        expect(doc.syntaxHighlighter, isNull);
      },
    );

    test(
      'leaves syntax_highlighter unset when source-highlighter is not set',
      () {
        const input =
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final doc = _documentFromString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.syntaxHighlighter, isNull);
      },
    );

    test('leaves syntax_highlighter unset when the highlighter is unknown', () {
      const input =
          ':source-highlighter: unknown\n'
          '\n'
          '[source, ruby]\n'
          '----\n'
          "puts 'Hello, World!'\n"
          '----\n';
      final doc = _documentFromString(
        input,
        const AsciidoctorOptions(safe: SafeMode.safe),
      );
      expect(doc.syntaxHighlighter, isNull);
    });

    test('does not allow the document to enable the highlighter in '
        'server safe mode', () {
      const input = ':source-highlighter: coderay';
      final doc = _documentFromString(
        input,
        const AsciidoctorOptions(safe: SafeMode.server),
      );
      expect(doc.attributes['source-highlighter'], isNull);
      expect(doc.syntaxHighlighter, isNull);
    });

    test('does not invoke highlight when canHighlight is false', () {
      SyntaxHighlighter.registerInstance(_UnavailableHighlighter(), <String>[
        'unavailable',
      ]);
      const input =
          '[source,ruby]\n'
          '----\n'
          "puts 'Hello, World!'\n"
          '----\n';
      final doc = _documentFromString(
        input,
        const AsciidoctorOptions(
          attributes: <String, String?>{'source-highlighter': 'unavailable'},
        ),
      );
      final output = doc.convert();
      _assertCss('pre.highlight > code.language-ruby', output, 1);
    });

    test('sets the language on source output when no highlighter is set', () {
      const input =
          '[source, ruby]\n'
          '----\n'
          "puts 'Hello, World!'\n"
          '----\n';
      final output = _convertString(
        input,
        const AsciidoctorOptions(safe: SafeMode.safe),
      );
      _assertCss('pre.highlight', output, 1);
      _assertCss('pre.highlight > code.language-ruby', output, 1);
      _assertCss(
        'pre.highlight > code.language-ruby[data-lang="ruby"]',
        output,
        1,
      );
    });

    test(
      'sets the language on source output when the highlighter is unknown',
      () {
        const input =
            ':source-highlighter: unknown\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final output = _convertString(
          input,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        _assertCss('pre.highlight', output, 1);
        _assertCss('pre.highlight > code.language-ruby', output, 1);
        _assertCss(
          'pre.highlight > code.language-ruby[data-lang="ruby"]',
          output,
          1,
        );
      },
    );
  });
}
