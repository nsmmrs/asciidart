/// Port of the framework assertions in `test/syntax_highlighter_test.rb`
/// (registration, factory selection including the unknown-highlighter
/// fallback, `Document` integration and docinfo aggregation).
///
/// Tests that parse or convert are skipped with [needsParser] until the
/// parser wave lands; the parser wave must un-skip them. Adapter behavior
/// itself is covered by the per-adapter suites in this directory — here the
/// adapters appear only behind [FakeSourceLexer] to prove the framework
/// plumbing (option routing, node/document attribute reads).
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:asciidoctor/src/highlight/syntax_highlighter.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:test/test.dart';

import 'fake_source_lexer.dart';

/// Skip reason for tests requiring the parser wave.
const String needsParser = 'needs Parser.parse (parser wave)';

/// The CDN root the converter passes to docinfo in these tests.
const String cdnBaseUrl = 'https://cdnjs.cloudflare.com/ajax/libs';

/// A client-side custom highlighter (port of the `'unavailable'` class in
/// the Ruby suite: `format` only, `canHighlight` false).
class _UnavailableHighlighter extends SyntaxHighlighterBase {
  @override
  String get name => 'unavailable';

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) =>
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
  _StubBlock(
    AbstractBlock? parent,
    this.stubbedContent, [
    Map<String, Object?>? attributes,
  ]) : super(parent, 'listing', attributes: attributes ?? <String, Object?>{});

  /// The value [content] returns.
  final String stubbedContent;

  @override
  String? content() => stubbedContent;
}

/// Creates an unparsed document with [attributes] (no parser needed: the
/// constructor applies attribute overrides and backend traits eagerly).
Document _docWithAttributes(
  Map<String, Object?> attributes, {
  String backend = 'html5',
  Map<String, Object?>? options,
}) => Document(<String>[], <String, Object?>{
  'backend': backend,
  'attributes': attributes,
  ...?options,
});

/// Creates a document from [src] (port of `document_from_string`).
///
/// All callers are skipped until the parser wave lands.
Document _documentFromString(String src, [Map<String, Object?>? options]) {
  final Map<String, Object?> opts = Map<String, Object?>.of(
    options ?? const <String, Object?>{},
  );
  final Object parse = opts.remove('parse') ?? true;
  final Document doc = Document(src, opts);
  return parse == true ? doc.parse() : doc;
}

/// Converts [src] to a standalone document (port of `convert_string`).
///
/// All callers are skipped until the parser wave lands.
String _convertString(String src, [Map<String, Object?>? options]) =>
    _documentFromString(src, options).convert() as String;

/// Asserts [content] matches [css] [count] times (port of `assert_css`).
///
/// XML-match wave: stub throwing [UnimplementedError]; all callers are
/// skipped.
void _assertCss(String css, String? content, int count) =>
    throw UnimplementedError('XML-match wave: assertCss is not yet ported.');

void main() {
  group('registration', () {
    test('registers and retrieves a custom highlighter by name', () {
      SyntaxHighlighterBase makeUnavailable(
        String name,
        String backend,
        Map<String, Object?> opts,
      ) => _UnavailableHighlighter();
      final SyntaxHighlighterFactoryFn factory = makeUnavailable;
      SyntaxHighlighter.register(factory, <String>['hlfw-foobar']);
      expect(identical(SyntaxHighlighter.for_('hlfw-foobar'), factory), isTrue);
    });

    test('registers one highlighter under several names', () {
      final _UnavailableHighlighter instance = _UnavailableHighlighter();
      SyntaxHighlighter.register(instance, <String>[
        'hlfw-multi',
        'hlfw.multi',
      ]);
      expect(identical(SyntaxHighlighter.for_('hlfw-multi'), instance), isTrue);
      expect(identical(SyntaxHighlighter.for_('hlfw.multi'), instance), isTrue);
    });

    test('registers the six built-in adapters', () {
      for (final String name in <String>[
        'coderay',
        'highlightjs',
        'highlight.js',
        'html-pipeline',
        'prettify',
        'pygments',
        'rouge',
      ]) {
        expect(SyntaxHighlighter.for_(name), isNotNull, reason: name);
      }
    });

    test('returns null for unknown names', () {
      expect(SyntaxHighlighter.for_('hlfw-no-such-highlighter'), isNull);
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
      Map<String, Object?>? seenOpts;
      SyntaxHighlighter.register((
        String name,
        String backend,
        Map<String, Object?> opts,
      ) {
        seenBackend = backend;
        seenOpts = opts;
        return _UnavailableHighlighter();
      }, <String>['hlfw-capture']);
      SyntaxHighlighter.create('hlfw-capture', 'docbook5', <String, Object?>{
        'key': 'value',
      });
      expect(seenBackend, 'docbook5');
      expect(seenOpts, <String, Object?>{'key': 'value'});
    });

    test('defaults the backend to html5', () {
      String? seenBackend;
      SyntaxHighlighter.register((
        String name,
        String backend,
        Map<String, Object?> opts,
      ) {
        seenBackend = backend;
        return _UnavailableHighlighter();
      }, <String>['hlfw-backend-default']);
      SyntaxHighlighter.create('hlfw-backend-default');
      expect(seenBackend, 'html5');
    });

    test('returns a registered instance as-is', () {
      final _UnavailableHighlighter instance = _UnavailableHighlighter();
      SyntaxHighlighter.register(instance, <String>['hlfw-instance']);
      expect(
        identical(SyntaxHighlighter.create('hlfw-instance'), instance),
        isTrue,
      );
    });

    test('rejects instances without a name', () {
      SyntaxHighlighter.register(_NamelessHighlighter(), <String>[
        'hlfw-nameless',
      ]);
      expect(() => SyntaxHighlighter.create('hlfw-nameless'), throwsStateError);
    });

    test('injects the lexer backend from the create options', () {
      final FakeSourceLexer lexer = FakeSourceLexer();
      final SyntaxHighlighterBase? created = SyntaxHighlighter.create(
        'rouge',
        'html5',
        <String, Object?>{'lexer': lexer},
      );
      expect(created, isA<RougeHighlighter>());
      expect((created! as RougeHighlighter).adapter.lexer, same(lexer));
      expect(created.canHighlight, isTrue);
    });

    test('isolates custom factory registries', () {
      final SyntaxHighlighterFactory factory = SyntaxHighlighterFactory();
      expect(factory.for_('rouge'), isNull);
      expect(factory.create('rouge'), isNull);
      SyntaxHighlighterBase makeCustom(
        String name,
        String backend,
        Map<String, Object?> opts,
      ) => _UnavailableHighlighter();
      final SyntaxHighlighterFactoryFn custom = makeCustom;
      factory.register(custom, <String>['hlfw-custom-only']);
      expect(identical(factory.for_('hlfw-custom-only'), custom), isTrue);
      expect(
        factory.create('hlfw-custom-only'),
        isA<_UnavailableHighlighter>(),
      );
      expect(SyntaxHighlighter.for_('hlfw-custom-only'), isNull);
    });

    test('seeds a custom factory from a registry map', () {
      final _UnavailableHighlighter instance = _UnavailableHighlighter();
      final SyntaxHighlighterFactory factory = SyntaxHighlighterFactory(
        <String, Object>{'hlfw-seeded': instance},
      );
      expect(identical(factory.create('hlfw-seeded'), instance), isTrue);
    });

    test('falls back to the global registry for unseeded names', () {
      final DefaultFactoryProxy proxy = DefaultFactoryProxy(<String, Object>{
        'hlfw-seed': _UnavailableHighlighter(),
      });
      expect(proxy.create('hlfw-seed'), isA<_UnavailableHighlighter>());
      expect(proxy.create('rouge'), isA<RougeHighlighter>());
    });

    test('prefers the seed registry over the globals', () {
      final DefaultFactoryProxy proxy = DefaultFactoryProxy(<String, Object>{
        'rouge': _UnavailableHighlighter(),
      });
      expect(proxy.create('rouge'), isA<_UnavailableHighlighter>());
      // The global registration is untouched.
      expect(SyntaxHighlighter.create('rouge'), isA<RougeHighlighter>());
    });
  });

  group('Document integration', () {
    test('resolves the highlighter when source-highlighter is set', () {
      final Document doc = _docWithAttributes(<String, Object?>{
        'source-highlighter': 'coderay',
      });
      final SyntaxHighlighterBase? resolved =
          SyntaxHighlighter.resolveForDocument(doc);
      expect(resolved, isA<CodeRayHighlighter>());
      doc.syntaxHighlighter = resolved;
      expect(doc.syntaxHighlighter, same(resolved));
      // The merged converter casts to this interface; the cast must hold.
      expect(doc.syntaxHighlighter, isA<NodeSyntaxHighlighter>());
    });

    test('returns null when the base backend is not html', () {
      final Document doc = _docWithAttributes(<String, Object?>{
        'source-highlighter': 'coderay',
      }, backend: 'docbook');
      expect(doc.basebackend('html'), isFalse);
      expect(SyntaxHighlighter.resolveForDocument(doc), isNull);
    });

    test('returns null when source-highlighter is not set', () {
      expect(
        SyntaxHighlighter.resolveForDocument(
          _docWithAttributes(<String, Object?>{}),
        ),
        isNull,
      );
    });

    test('returns null when the highlighter name is unknown', () {
      expect(
        SyntaxHighlighter.resolveForDocument(
          _docWithAttributes(<String, Object?>{
            'source-highlighter': 'unknown',
          }),
        ),
        isNull,
      );
    });

    test('returns null when the highlighter is marked unavailable', () {
      expect(
        SyntaxHighlighter.resolveForDocument(
          _docWithAttributes(<String, Object?>{
            'source-highlighter': 'coderay',
            'coderay-unavailable': '',
          }),
        ),
        isNull,
      );
    });

    test('honors the syntax_highlighter_factory document option', () {
      final SyntaxHighlighterFactory factory = SyntaxHighlighterFactory();
      factory.register(_UnavailableHighlighter(), <String>['unavailable']);
      final Document doc = _docWithAttributes(
        <String, Object?>{'source-highlighter': 'unavailable'},
        options: <String, Object?>{'syntax_highlighter_factory': factory},
      );
      expect(
        SyntaxHighlighter.resolveForDocument(doc),
        isA<_UnavailableHighlighter>(),
      );
    });

    test('does not fall back to the globals with a custom factory', () {
      final Document doc = _docWithAttributes(
        <String, Object?>{'source-highlighter': 'rouge'},
        options: <String, Object?>{
          'syntax_highlighter_factory': SyntaxHighlighterFactory(),
        },
      );
      expect(SyntaxHighlighter.resolveForDocument(doc), isNull);
    });

    test('honors the syntax_highlighters document option', () {
      final Document doc = _docWithAttributes(
        <String, Object?>{'source-highlighter': 'coderay'},
        options: <String, Object?>{
          'syntax_highlighters': <String, Object>{
            'coderay': _UnavailableHighlighter(),
          },
        },
      );
      expect(
        SyntaxHighlighter.resolveForDocument(doc),
        isA<_UnavailableHighlighter>(),
      );
    });

    test('falls back to the globals for names missing from the option map', () {
      final Document doc = _docWithAttributes(
        <String, Object?>{'source-highlighter': 'rouge'},
        options: <String, Object?>{
          'syntax_highlighters': <String, Object>{
            'coderay': _UnavailableHighlighter(),
          },
        },
      );
      expect(
        SyntaxHighlighter.resolveForDocument(doc),
        isA<RougeHighlighter>(),
      );
    });
  });

  group('base contract', () {
    test('does not highlight when canHighlight is false', () {
      final _UnavailableHighlighter highlighter = _UnavailableHighlighter();
      expect(highlighter.canHighlight, isFalse);
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1');
      expect(
        () => highlighter.highlight(block, 'puts 1', 'ruby'),
        throwsUnimplementedError,
      );
    });

    test('reports no docinfo by default', () {
      final _UnavailableHighlighter highlighter = _UnavailableHighlighter();
      expect(highlighter.hasDocinfo('head'), isFalse);
      expect(highlighter.hasDocinfo('footer'), isFalse);
    });

    test('throws from docinfo when unimplemented', () {
      final HtmlPipelineHighlighter highlighter = HtmlPipelineHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
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
      final HighlightJsHighlighter highlighter = HighlightJsHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      expect(highlighter.wantsStylesheetFile(doc), isFalse);
      expect(
        () => highlighter.writeStylesheet(doc, '.'),
        throwsUnimplementedError,
      );
    });

    test('wraps content in the base pre/code envelope', () {
      final CodeRayHighlighter highlighter = CodeRayHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': false}),
        '<pre class="CodeRay highlight">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('appends nowrap and runs the transform with data-lang last', () {
      final CodeRayHighlighter highlighter = CodeRayHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{
          'nowrap': true,
          'transform': (Map<String, String> pre, Map<String, String> code) {
            code['class'] = 'language-ruby hljs';
          },
        }),
        '<pre class="CodeRay highlight nowrap">'
        '<code class="language-ruby hljs" data-lang="ruby">x</code></pre>',
      );
    });
  });

  group('format wiring', () {
    test('marks highlight.js blocks for client-side highlighting', () {
      final HighlightJsHighlighter highlighter = HighlightJsHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': false}),
        '<pre class="highlightjs highlight">'
        '<code class="language-ruby hljs" data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('drops the highlight marker when nohighlight is set', () {
      final HighlightJsHighlighter highlighter = HighlightJsHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1')
        ..setOption('nohighlight');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': false}),
        '<pre class="highlightjs">'
        '<code class="language-ruby hljs" data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('uses language-none when the language is absent', () {
      final HighlightJsHighlighter highlighter = HighlightJsHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x');
      expect(
        highlighter.format(block, null, <String, Object?>{'nowrap': false}),
        '<pre class="highlightjs highlight">'
        '<code class="language-none hljs">x</code></pre>',
      );
    });

    test('numbers prettify lines from the start attribute', () {
      final PrettifyHighlighter highlighter = PrettifyHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x')
        ..setOption('linenums')
        ..setAttr('start', '7');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': false}),
        '<pre class="prettyprint highlight linenums:7">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('numbers prettify lines without a start value', () {
      final PrettifyHighlighter highlighter = PrettifyHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x')..setOption('linenums');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': false}),
        '<pre class="prettyprint highlight linenums">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('emits html-pipeline pre hooks', () {
      final HtmlPipelineHighlighter highlighter = HtmlPipelineHighlighter();
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': true}),
        '<pre lang="ruby"><code>puts 1</code></pre>',
      );
    });

    test('attaches the rouge base style in inline-css mode', () {
      final FakeSourceLexer lexer = FakeSourceLexer(
        onStyleAvailable: (String style) => true,
        onBaseStyle: (String style) =>
            'color: #f8f8f2;background-color: #49483e',
      );
      final RougeHighlighter highlighter = RougeHighlighter(lexer: lexer);
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{
          'nowrap': false,
          'css_mode': 'style',
          'style': 'monokai',
        }),
        '<pre class="rouge highlight" '
        'style="color: #f8f8f2;background-color: #49483e">'
        '<code data-lang="ruby">puts 1</code></pre>',
      );
    });

    test('omits the pre style in class mode', () {
      final FakeSourceLexer lexer = FakeSourceLexer(
        onStyleAvailable: (String style) => true,
        onBaseStyle: (String style) => 'color: #000;',
      );
      final PygmentsHighlighter highlighter = PygmentsHighlighter(lexer: lexer);
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x');
      expect(
        highlighter.format(block, 'ruby', <String, Object?>{'nowrap': false}),
        '<pre class="pygments highlight">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });
  });

  group('highlight wiring', () {
    test('routes rouge highlight options to the backend', () {
      final FakeSourceLexer lexer = FakeSourceLexer(
        onHighlight: (HighlightRequest request) =>
            '<span class="nb">puts</span> 1',
        onStyleAvailable: (String style) => style == 'monokai',
      );
      final RougeHighlighter highlighter = RougeHighlighter(lexer: lexer);
      expect(highlighter.canHighlight, isTrue);
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1')..setOption('mixed');
      final HighlightResult result = highlighter.highlight(
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
      final HighlightRequest request = lexer.lastRequest!;
      expect(request.language, 'ruby');
      expect(request.mixed, isTrue);
      expect(request.style, 'monokai');
      expect(request.highlightLines, <int>[1]);
    });

    test('routes pygments highlight options to the backend', () {
      final FakeSourceLexer lexer = FakeSourceLexer(
        onHighlight: (HighlightRequest request) => '<div class="lineno"><pre><span class="tok-n">puts</span> 1</pre></div>',
        onStyleAvailable: (String style) => true,
      );
      final PygmentsHighlighter highlighter = PygmentsHighlighter(lexer: lexer);
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'puts 1');
      final HighlightResult result = highlighter.highlight(
        block,
        'puts 1',
        'ruby',
        style: 'colorful',
      );
      expect(result.html, '<span class="tok-n">puts</span> 1');
      final HighlightRequest request = lexer.lastRequest!;
      expect(request.language, 'ruby');
      expect(request.mixed, isFalse);
      expect(request.style, 'colorful');
    });

    test('maps callouts to the coderay table offset', () {
      const String backendHtml =
          '<table><tr><td class="code"><pre>x</pre></td></tr></table>';
      final FakeSourceLexer lexer = FakeSourceLexer(
        onHighlight: (HighlightRequest request) => backendHtml,
      );
      final CodeRayHighlighter highlighter = CodeRayHighlighter(lexer: lexer);
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x');
      final HighlightResult withCallouts = highlighter.highlight(
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
      final HighlightResult withoutCallouts = highlighter.highlight(
        block,
        'x',
        'ruby',
        numberLines: LineNumbersMode.table,
      );
      expect(withoutCallouts.sourceOffset, isNull);
    });

    test('throws when highlighting without a lexer backend', () {
      final Document doc = _docWithAttributes(<String, Object?>{});
      final _StubBlock block = _StubBlock(doc, 'x');
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
      final HighlightJsHighlighter highlightjs = HighlightJsHighlighter();
      expect(highlightjs.hasDocinfo('head'), isTrue);
      expect(highlightjs.hasDocinfo('footer'), isTrue);
      final PrettifyHighlighter prettify = PrettifyHighlighter();
      expect(prettify.hasDocinfo('head'), isTrue);
      expect(prettify.hasDocinfo('footer'), isTrue);
      final HtmlPipelineHighlighter pipeline = HtmlPipelineHighlighter();
      expect(pipeline.hasDocinfo('head'), isFalse);
      expect(pipeline.hasDocinfo('footer'), isFalse);
    });

    test('links the highlight.js theme in the head', () {
      final Document doc = _docWithAttributes(<String, Object?>{});
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
      final Document doc = _docWithAttributes(<String, Object?>{
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
        "code[data-lang]')).forEach(function (el) { hljs.highlightBlock(el) })\n"
        '}\n'
        '</script>',
      );
    });

    test('links the prettify theme in the head', () {
      final Document doc = _docWithAttributes(<String, Object?>{});
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
      final Document doc = _docWithAttributes(<String, Object?>{
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
      final Document doc = _docWithAttributes(<String, Object?>{});
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
      final FakeSourceLexer lexer = FakeSourceLexer(
        onHighlight: (HighlightRequest request) => 'x',
      );
      final CodeRayHighlighter highlighter = CodeRayHighlighter(lexer: lexer);
      expect(highlighter.hasDocinfo('head'), isFalse);
      final Document doc = _docWithAttributes(<String, Object?>{});
      highlighter.highlight(_StubBlock(doc, 'x'), 'x', 'ruby');
      expect(highlighter.hasDocinfo('head'), isTrue);
      expect(highlighter.hasDocinfo('footer'), isFalse);
      expect(highlighter.wantsStylesheetFile(doc), isTrue);
    });

    test('links the coderay stylesheet when linkcss is set', () {
      final FakeSourceLexer lexer = FakeSourceLexer(
        onHighlight: (HighlightRequest request) => 'x',
      );
      final CodeRayHighlighter highlighter = CodeRayHighlighter(lexer: lexer);
      final Document doc = _docWithAttributes(<String, Object?>{
        'stylesdir': 'css',
      });
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
      final FakeSourceLexer lexer = FakeSourceLexer(
        onHighlight: (HighlightRequest request) => 'x',
        onStylesheet: (String style) => '/* $style */',
      );
      final RougeHighlighter highlighter = RougeHighlighter(lexer: lexer);
      final Document doc = _docWithAttributes(<String, Object?>{});
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

  group('Ruby suite ports requiring the parser', () {
    test(
      'sets syntax_highlighter on the document when source-highlighter is set',
      skip: needsParser,
      () {
        const String input =
            ':source-highlighter: coderay\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final Document doc = _documentFromString(input, <String, Object?>{
          'safe': 'safe',
          'parse': true,
        });
        expect(doc.basebackend('html'), isTrue);
        expect(doc.syntaxHighlighter, isNotNull);
        expect(doc.syntaxHighlighter, isA<SyntaxHighlighterBase>());
      },
    );

    test(
      'leaves syntax_highlighter unset when the base backend is not html',
      skip: needsParser,
      () {
        const String input =
            ':source-highlighter: coderay\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final Document doc = _documentFromString(input, <String, Object?>{
          'safe': 'safe',
          'backend': 'docbook',
          'parse': true,
        });
        expect(doc.basebackend('html'), isFalse);
        expect(doc.syntaxHighlighter, isNull);
      },
    );

    test(
      'leaves syntax_highlighter unset when source-highlighter is not set',
      skip: needsParser,
      () {
        const String input =
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final Document doc = _documentFromString(input, <String, Object?>{
          'safe': 'safe',
          'parse': true,
        });
        expect(doc.syntaxHighlighter, isNull);
      },
    );

    test(
      'leaves syntax_highlighter unset when the highlighter is unknown',
      skip: needsParser,
      () {
        const String input =
            ':source-highlighter: unknown\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final Document doc = _documentFromString(input, <String, Object?>{
          'safe': 'safe',
          'parse': true,
        });
        expect(doc.syntaxHighlighter, isNull);
      },
    );

    test(
      'does not allow the document to enable the highlighter in server safe mode',
      skip: needsParser,
      () {
        const String input = ':source-highlighter: coderay';
        final Document doc = _documentFromString(input, <String, Object?>{
          'safe': 'server',
          'parse': true,
        });
        expect(doc.attributes['source-highlighter'], isNull);
        expect(doc.syntaxHighlighter, isNull);
      },
    );

    test(
      'does not invoke highlight when canHighlight is false',
      skip: needsParser,
      () {
        SyntaxHighlighter.register(_UnavailableHighlighter(), <String>[
          'unavailable',
        ]);
        const String input =
            '[source,ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final Document doc = _documentFromString(input, <String, Object?>{
          'attributes': <String, Object?>{'source-highlighter': 'unavailable'},
        });
        final String output = doc.convert() as String;
        _assertCss('pre.highlight > code.language-ruby', output, 1);
      },
    );

    test(
      'sets the language on source output when no highlighter is set',
      skip: needsParser,
      () {
        const String input =
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final String output = _convertString(input, <String, Object?>{
          'safe': 'safe',
        });
        _assertCss('pre.highlight', output, 1);
        _assertCss('pre.highlight > code.language-ruby', output, 1);
        _assertCss(
          'pre.highlight > code.language-ruby[data-lang="ruby"]',
          output,
          1,
        );
      },
    );

    test(
      'sets the language on source output when the highlighter is unknown',
      skip: needsParser,
      () {
        const String input =
            ':source-highlighter: unknown\n'
            '\n'
            '[source, ruby]\n'
            '----\n'
            "puts 'Hello, World!'\n"
            '----\n';
        final String output = _convertString(input, <String, Object?>{
          'safe': 'safe',
        });
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
