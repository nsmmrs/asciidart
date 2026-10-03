/// Syntax-highlighter framework: registry, factory and Document integration.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter.rb` (the
/// `SyntaxHighlighter` module, `Factory`, `CustomFactory`, `DefaultFactory`,
/// `DefaultFactoryProxy` and `Base`).
///
/// The six language adapters in this directory (`coderay.dart`,
/// `highlightjs.dart`, `html_pipeline.dart`, `prettify.dart`, `pygments.dart`,
/// `rouge.dart`) are pure string transformers: every value they need arrives
/// as an explicit parameter. This file binds them to the document model:
///
/// * [SyntaxHighlighterBase] is the base-class contract custom highlighters
///   extend (port of the module defaults plus `Base#format`).
/// * The `*Highlighter` wrapper classes adapt each merged adapter to that
///   contract, translating node/document reads into the adapters' explicit
///   parameters. The merged adapter files are never modified.
/// * [SyntaxHighlighter] is the global registry and factory (port of the
///   `DefaultFactory` statics), [SyntaxHighlighterFactory] an isolated
///   registry (port of `CustomFactory`) and [DefaultFactoryProxy] a seeded
///   registry with global fallback.
/// * [SyntaxHighlighter.resolveForDocument] ports the
///   `Document#save_attributes` hook: it resolves the `source-highlighter`
///   attribute to an instance. The Document wave calls it from the hook and
///   assigns the result to `Document.syntaxHighlighter`; until then callers
///   assign the result themselves.
///
/// Framework instances implement [NodeSyntaxHighlighter], the exact interface
/// the merged HTML5 converter casts `Document.syntaxHighlighter` to, so
/// resolved highlighters work with the converter unchanged.
library;

import '../abstract_block.dart';
import '../core_ext.dart';
import '../document.dart';
import '../html5.dart';
import 'coderay.dart';
import 'highlight.dart';
import 'highlightjs.dart';
import 'html_pipeline.dart';
import 'prettify.dart';
import 'pygments.dart';
import 'rouge.dart';

/// Creates a highlighter instance for a registered name.
///
/// Port of registering a `Class`: [name] is the lookup name, [backend] the
/// document backend (`'html5'` by default) and [opts] carries context (at
/// least `'document'`). The built-in server-side factories additionally honor
/// a `'lexer'` entry holding the [SourceLexer] backend used for real lexing.
typedef SyntaxHighlighterFactoryFn = SyntaxHighlighterBase Function(
  String name,
  String backend,
  Map<String, Object?> opts,
);

/// Base-class contract for syntax highlighters.
///
/// Port of the `SyntaxHighlighter` module defaults plus `Base`. Custom
/// highlighters extend this class and override what they support; anything
/// left at its default either reports absence (`false`) or throws
/// [UnimplementedError] (the Dart shape of Ruby's `NotImplementedError`).
abstract class SyntaxHighlighterBase implements NodeSyntaxHighlighter {
  /// The highlighter name (e.g. `'rouge'`).
  ///
  /// Selects the `{name}-css`, `{name}-style` and `{name}-linenums-mode`
  /// document attributes. Must be non-empty: [SyntaxHighlighter.create]
  /// rejects nameless instances, mirroring the Ruby `NameError`.
  @override
  String get name;

  /// The `<pre>` CSS class (port of `@pre_class`).
  ///
  /// Defaults to [name]; adapters with a distinct class override it.
  String get preClass => name;

  /// Whether highlighting runs during conversion (port of `highlight?`).
  ///
  /// Defaults to `false`. When `true`, the substitutor wave calls
  /// [highlight] to handle the `:specialcharacters` substitution.
  @override
  bool get canHighlight => false;

  /// Highlights [source] written in [language] for [node].
  ///
  /// Port of `highlight`. [callouts] carries the callout marks extracted
  /// from [source] (indexed by 1-based line number); [cssMode] selects class
  /// versus inline CSS; [highlightLines] lists the 1-based lines to
  /// emphasize; [numberLines] selects line numbering; [startLineNumber] is
  /// the 1-based number of the first line; [style] is the requested theme.
  /// Client-side highlighters leave this unimplemented.
  ///
  /// Throws [UnimplementedError] unless overridden.
  HighlightResult highlight(
    AbstractBlock node,
    String source,
    String? language, {
    Map<int, String>? callouts,
    CssMode cssMode = CssMode.classes,
    List<int> highlightLines = const <int>[],
    LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    String? style,
  }) => throw UnimplementedError(
    'SyntaxHighlighter subclass $runtimeType must implement highlight '
    'since canHighlight returns true',
  );

  /// Formats the converted source of [node] as highlighted HTML.
  ///
  /// Direct port of `Base#format`: the
  /// `<pre class="{preClass} highlight[ nowrap]">` envelope with an optional
  /// `data-lang`, running the `transform` callback from [opts] when present.
  /// [opts] carries `nowrap` (any truthy value disables wrapping) and, for
  /// server-side highlighters, `css_mode` and `style`.
  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) {
    final Object? transform = opts['transform'];
    return wrapSourceBlock(
      preClass: preClass,
      content: _s(node.content()),
      language: language,
      nowrap: isTruthy(opts['nowrap']),
      transform:
          transform is void Function(Map<String, String>, Map<String, String>)
          ? transform
          : null,
    );
  }

  /// Whether markup is injected at [location] (port of `docinfo?`).
  ///
  /// [location] is `'head'` or `'footer'`. Defaults to `false`.
  @override
  bool hasDocinfo(String location) => false;

  /// Returns the markup injected at [location] (port of `docinfo`).
  ///
  /// [node] is the document being converted, [cdnBaseUrl] the CDN root for
  /// remote assets, [linkcss] whether stylesheets are linked instead of
  /// embedded, and [selfClosingTagSlash] the converter's void-element slash.
  ///
  /// Throws [UnimplementedError] unless overridden.
  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) => throw UnimplementedError(
    'SyntaxHighlighter subclass $runtimeType must implement docinfo '
    'since hasDocinfo returns true',
  );

  /// Whether the stylesheet is written to disk (port of `write_stylesheet?`).
  ///
  /// Only consulted when both `linkcss` and `copycss` are set. Defaults to
  /// `false`.
  bool wantsStylesheetFile(Document doc) => false;

  /// Writes the stylesheet to [toDir] (port of `write_stylesheet`).
  ///
  /// Throws [UnimplementedError] unless overridden.
  void writeStylesheet(Document doc, String toDir) => throw UnimplementedError(
    'SyntaxHighlighter subclass $runtimeType must implement writeStylesheet '
    'since wantsStylesheetFile returns true',
  );
}

/// Global highlighter registry and factory (port of `DefaultFactory`).
///
/// Ruby lazy-requires four of the six adapters on first lookup; Dart imports
/// are static, so all six built-ins register eagerly on first access instead.
/// Lookups for unknown names return `null` (Ruby memoizes the miss; the
/// observable behavior is identical).
abstract final class SyntaxHighlighter {
  static final Map<String, Object> _registry = <String, Object>{};
  static bool _builtinsRegistered = false;

  /// Associates [highlighter] with each of [names] (port of
  /// `Factory#register`).
  ///
  /// [highlighter] is either a [SyntaxHighlighterBase] instance (returned
  /// as-is by [create]) or a [SyntaxHighlighterFactoryFn] (called by
  /// [create]); this mirrors Ruby, which accepts a class or an object.
  static void register(Object highlighter, Iterable<String> names) {
    _ensureBuiltins();
    for (final String name in names) {
      _registry[name] = highlighter;
    }
  }

  /// Returns the registration for [name], or `null` (port of `Factory#for`).
  ///
  /// Named `for_` because `for` is a reserved word in Dart.
  static Object? for_(String name) {
    _ensureBuiltins();
    return _registry[name];
  }

  /// Resolves [name] to a highlighter instance (port of `Factory#create`).
  ///
  /// Returns `null` when [name] is not registered. [opts] carries context
  /// (at least `'document'`); the built-in server-side factories
  /// additionally honor a `'lexer'` entry holding the [SourceLexer] backend.
  static SyntaxHighlighterBase? create(
    String name, [
    String backend = 'html5',
    Map<String, Object?> opts = const <String, Object?>{},
  ]) {
    final Object? found = for_(name);
    if (found == null) return null;
    return _instantiate(found, name, backend, opts);
  }

  /// Resolves the highlighter for [doc] (port of the
  /// `Document#save_attributes` hook).
  ///
  /// Returns `null` unless the base backend is HTML, the `source-highlighter`
  /// attribute is set, and the `{name}-unavailable` attribute is unset —
  /// exactly the Ruby conditions. [factory] and [highlighters] override the
  /// `'syntax_highlighter_factory'` and `'syntax_highlighters'` document
  /// options (Ruby `@options` `:syntax_highlighter_factory` and
  /// `:syntax_highlighters`).
  ///
  /// NOTE there is no Ruby `Document#syntax_highlighter_for` method; the
  /// hook above plus [create] is the actual integration surface.
  static SyntaxHighlighterBase? resolveForDocument(
    Document doc, {
    SyntaxHighlighterFactory? factory,
    Map<String, Object>? highlighters,
  }) {
    if (!doc.basebackend('html')) return null;
    final Object? rawName = doc.attributes['source-highlighter'];
    if (!isTruthy(rawName)) return null;
    final String name = rawName.toString();
    if (isTruthy(doc.attributes['$name-unavailable'])) return null;
    final String backend = doc.backend ?? 'html5';
    final Map<String, Object?> opts = <String, Object?>{'document': doc};
    final Object? resolvedFactory =
        factory ?? doc.options['syntax_highlighter_factory'];
    if (resolvedFactory != null) {
      return (resolvedFactory as SyntaxHighlighterFactory).create(
        name,
        backend,
        opts,
      );
    }
    final Object? resolvedHighlighters =
        highlighters ?? doc.options['syntax_highlighters'];
    if (resolvedHighlighters != null) {
      return DefaultFactoryProxy(
        (resolvedHighlighters as Map<Object?, Object?>).cast<String, Object>(),
      ).create(name, backend, opts);
    }
    return create(name, backend, opts);
  }

  static void _ensureBuiltins() {
    if (_builtinsRegistered) return;
    _builtinsRegistered = true;
    void add(
      SyntaxHighlighterBase Function(Map<String, Object?> opts) make,
      Iterable<String> names,
    ) {
      SyntaxHighlighterBase factory(
        String name,
        String backend,
        Map<String, Object?> opts,
      ) => make(opts);
      for (final String name in names) {
        _registry[name] = factory;
      }
    }

    add(
      (Map<String, Object?> opts) =>
          CodeRayHighlighter(lexer: _lexerFromOpts(opts)),
      CodeRayAdapter.registeredNames,
    );
    add(
      (Map<String, Object?> opts) => HighlightJsHighlighter(),
      HighlightJsAdapter.registeredNames,
    );
    add(
      (Map<String, Object?> opts) => HtmlPipelineHighlighter(),
      HtmlPipelineAdapter.registeredNames,
    );
    add(
      (Map<String, Object?> opts) => PrettifyHighlighter(),
      PrettifyAdapter.registeredNames,
    );
    add(
      (Map<String, Object?> opts) =>
          PygmentsHighlighter(lexer: _lexerFromOpts(opts)),
      PygmentsAdapter.registeredNames,
    );
    add(
      (Map<String, Object?> opts) =>
          RougeHighlighter(lexer: _lexerFromOpts(opts)),
      RougeAdapter.registeredNames,
    );
  }
}

/// Isolated highlighter registry (port of `CustomFactory`).
///
/// Starts empty (or seeded with [seedRegistry]) and never sees the global
/// registrations; use [DefaultFactoryProxy] for a seeded registry that falls
/// back to the globals.
class SyntaxHighlighterFactory {
  /// Creates an isolated factory, optionally seeded with [seedRegistry].
  SyntaxHighlighterFactory([Map<String, Object>? seedRegistry])
    : _registry = <String, Object>{...?seedRegistry};

  final Map<String, Object> _registry;

  /// Associates [highlighter] with each of [names] (port of
  /// `Factory#register`). See [SyntaxHighlighter.register] for the accepted
  /// value shapes.
  void register(Object highlighter, Iterable<String> names) {
    for (final String name in names) {
      _registry[name] = highlighter;
    }
  }

  /// Returns the registration for [name], or `null` (port of `Factory#for`).
  Object? for_(String name) => _registry[name];

  /// Resolves [name] to a highlighter instance (port of `Factory#create`).
  SyntaxHighlighterBase? create(
    String name, [
    String backend = 'html5',
    Map<String, Object?> opts = const <String, Object?>{},
  ]) {
    final Object? found = for_(name);
    if (found == null) return null;
    return _instantiate(found, name, backend, opts);
  }
}

/// Seeded registry with global fallback (port of `DefaultFactoryProxy`).
///
/// Looks up the seed registry first, then the global [SyntaxHighlighter]
/// registry — the Dart shape of Ruby's `@options[:syntax_highlighters]`
/// hash.
class DefaultFactoryProxy extends SyntaxHighlighterFactory {
  /// Creates a proxy seeded with [seedRegistry].
  DefaultFactoryProxy([super.seedRegistry]);

  @override
  Object? for_(String name) => _registry[name] ?? SyntaxHighlighter.for_(name);
}

/// Framework binding for the CodeRay adapter.
///
/// Server-side highlighter. `format` is inherited from
/// [SyntaxHighlighterBase] (the Ruby adapter defines no `format` override).
class CodeRayHighlighter extends SyntaxHighlighterBase {
  /// Creates a CodeRay highlighter, optionally with a [lexer] backend.
  ///
  /// Without a backend [canHighlight] is `false`, mirroring the Ruby
  /// adapter when the `coderay` library is unavailable.
  CodeRayHighlighter({SourceLexer? lexer})
    : adapter = CodeRayAdapter(lexer: lexer);

  /// The bound string-transformer adapter.
  final CodeRayAdapter adapter;

  @override
  String get name => CodeRayAdapter.name;

  @override
  String get preClass => CodeRayAdapter.preClass;

  @override
  bool get canHighlight => adapter.canHighlight;

  @override
  HighlightResult highlight(
    AbstractBlock node,
    String source,
    String? language, {
    Map<int, String>? callouts,
    CssMode cssMode = CssMode.classes,
    List<int> highlightLines = const <int>[],
    LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    String? style,
  }) => adapter.highlight(
    source: source,
    language: language,
    cssMode: cssMode,
    numberLines: numberLines,
    startLineNumber: startLineNumber,
    highlightLines: highlightLines,
    hasCallouts: callouts != null && callouts.isNotEmpty,
  );

  @override
  bool hasDocinfo(String location) => adapter.hasDocinfo(
    location == 'head' ? DocinfoLocation.head : DocinfoLocation.footer,
  );

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) => adapter.docinfoHead(
    linkCss: linkcss,
    stylesDir: _s(node.attr('stylesdir')),
    selfClosingSlash: selfClosingTagSlash,
  );

  @override
  bool wantsStylesheetFile(Document doc) => adapter.wantsStylesheetFile;

  @override
  void writeStylesheet(Document doc, String toDir) =>
      adapter.writeStylesheet(toDir);
}

/// Framework binding for the highlight.js adapter.
///
/// Client-side highlighter: [format] emits the markup hooks and [docinfo]
/// the loader tags. Highlighting itself runs in the browser, so
/// [canHighlight] stays `false`.
class HighlightJsHighlighter extends SyntaxHighlighterBase {
  /// The bound string-transformer adapter.
  final HighlightJsAdapter adapter = const HighlightJsAdapter();

  @override
  String get name => HighlightJsAdapter.name;

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) => adapter.format(
    content: _s(node.content()),
    language: language,
    nowrap: isTruthy(opts['nowrap']),
    nohighlight: node.hasOption('nohighlight'),
  );

  @override
  bool hasDocinfo(String location) => true;

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) {
    final String? highlightjsDir = node.attr('highlightjsdir')?.toString();
    if (location == 'head') {
      return adapter.docinfoHead(
        highlightjsDir: highlightjsDir,
        theme: _s(node.attr('highlightjs-theme', 'github')),
        cdnBaseUrl: cdnBaseUrl,
        selfClosingSlash: selfClosingTagSlash,
      );
    }
    return adapter.docinfoFooter(
      highlightjsDir: highlightjsDir,
      languagesAttr: node.attr('highlightjs-languages')?.toString(),
      cdnBaseUrl: cdnBaseUrl,
    );
  }
}

/// Framework binding for the html-pipeline adapter.
///
/// Emits `<pre lang>` hooks only; highlighting happens downstream in the
/// html-pipeline filter chain. `hasDocinfo` stays `false` and `docinfo` is
/// left unimplemented (calling it throws, as in Ruby).
class HtmlPipelineHighlighter extends SyntaxHighlighterBase {
  /// The bound string-transformer adapter.
  final HtmlPipelineAdapter adapter = const HtmlPipelineAdapter();

  @override
  String get name => HtmlPipelineAdapter.name;

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) => adapter.format(content: _s(node.content()), language: language);
}

/// Framework binding for the Prettify adapter.
///
/// Client-side highlighter: [format] emits the markup hooks and [docinfo]
/// the loader tags. Highlighting itself runs in the browser, so
/// [canHighlight] stays `false`.
class PrettifyHighlighter extends SyntaxHighlighterBase {
  /// The bound string-transformer adapter.
  final PrettifyAdapter adapter = const PrettifyAdapter();

  @override
  String get name => PrettifyAdapter.name;

  @override
  String get preClass => PrettifyAdapter.preClass;

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) => adapter.format(
    content: _s(node.content()),
    language: language,
    nowrap: isTruthy(opts['nowrap']),
    linenums: node.hasOption('linenums'),
    start: node.attr('start')?.toString(),
  );

  @override
  bool hasDocinfo(String location) => true;

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) {
    final String? prettifyDir = node.attr('prettifydir')?.toString();
    if (location == 'head') {
      return adapter.docinfoHead(
        prettifyDir: prettifyDir,
        theme: _s(node.attr('prettify-theme', 'prettify')),
        cdnBaseUrl: cdnBaseUrl,
        selfClosingSlash: selfClosingTagSlash,
      );
    }
    return adapter.docinfoFooter(
      prettifyDir: prettifyDir,
      cdnBaseUrl: cdnBaseUrl,
    );
  }
}

/// Framework binding for the Pygments adapter.
///
/// Server-side highlighter with generated stylesheets.
class PygmentsHighlighter extends SyntaxHighlighterBase {
  /// Creates a Pygments highlighter, optionally with a [lexer] backend.
  ///
  /// Without a backend [canHighlight] is `false`, mirroring the Ruby
  /// adapter when the `pygments` library is unavailable.
  PygmentsHighlighter({SourceLexer? lexer})
    : adapter = PygmentsAdapter(lexer: lexer);

  /// The bound string-transformer adapter.
  final PygmentsAdapter adapter;

  @override
  String get name => PygmentsAdapter.name;

  @override
  bool get canHighlight => adapter.canHighlight;

  @override
  HighlightResult highlight(
    AbstractBlock node,
    String source,
    String? language, {
    Map<int, String>? callouts,
    CssMode cssMode = CssMode.classes,
    List<int> highlightLines = const <int>[],
    LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    String? style,
  }) => adapter.highlight(
    source: source,
    language: language,
    cssMode: cssMode,
    numberLines: numberLines,
    startLineNumber: startLineNumber,
    highlightLines: highlightLines,
    hasCallouts: callouts != null && callouts.isNotEmpty,
    style: style,
    mixed: node.hasOption('mixed'),
  );

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) => adapter.format(
    content: _s(node.content()),
    language: language,
    nowrap: isTruthy(opts['nowrap']),
    cssMode: CssMode.fromAttribute(opts['css_mode']?.toString()),
    style: opts['style']?.toString(),
  );

  @override
  bool hasDocinfo(String location) => adapter.hasDocinfo(
    location == 'head' ? DocinfoLocation.head : DocinfoLocation.footer,
  );

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) => adapter.docinfoHead(
    linkCss: linkcss,
    stylesDir: _s(node.attr('stylesdir')),
    selfClosingSlash: selfClosingTagSlash,
  );

  @override
  bool wantsStylesheetFile(Document doc) => adapter.wantsStylesheetFile;

  @override
  void writeStylesheet(Document doc, String toDir) =>
      adapter.writeStylesheet(toDir);
}

/// Framework binding for the Rouge adapter.
///
/// Server-side highlighter with theme stylesheets.
class RougeHighlighter extends SyntaxHighlighterBase {
  /// Creates a Rouge highlighter, optionally with a [lexer] backend.
  ///
  /// Without a backend [canHighlight] is `false`, mirroring the Ruby
  /// adapter when the `rouge` library is unavailable.
  RougeHighlighter({SourceLexer? lexer}) : adapter = RougeAdapter(lexer: lexer);

  /// The bound string-transformer adapter.
  final RougeAdapter adapter;

  @override
  String get name => RougeAdapter.name;

  @override
  bool get canHighlight => adapter.canHighlight;

  @override
  HighlightResult highlight(
    AbstractBlock node,
    String source,
    String? language, {
    Map<int, String>? callouts,
    CssMode cssMode = CssMode.classes,
    List<int> highlightLines = const <int>[],
    LineNumbersMode? numberLines,
    int? startLineNumber = 1,
    String? style,
  }) => adapter.highlight(
    source: source,
    language: language,
    cssMode: cssMode,
    numberLines: numberLines,
    startLineNumber: startLineNumber,
    highlightLines: highlightLines,
    hasCallouts: callouts != null && callouts.isNotEmpty,
    style: style,
    mixed: node.hasOption('mixed'),
  );

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) => adapter.format(
    content: _s(node.content()),
    language: language,
    nowrap: isTruthy(opts['nowrap']),
    cssMode: CssMode.fromAttribute(opts['css_mode']?.toString()),
    style: opts['style']?.toString(),
  );

  @override
  bool hasDocinfo(String location) => adapter.hasDocinfo(
    location == 'head' ? DocinfoLocation.head : DocinfoLocation.footer,
  );

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) => adapter.docinfoHead(
    linkCss: linkcss,
    stylesDir: _s(node.attr('stylesdir')),
    selfClosingSlash: selfClosingTagSlash,
  );

  @override
  bool wantsStylesheetFile(Document doc) => adapter.wantsStylesheetFile;

  @override
  void writeStylesheet(Document doc, String toDir) =>
      adapter.writeStylesheet(toDir);
}

/// Instantiates a registry [value] (port of the `Factory#create` tail).
///
/// Factory functions are called; instances are returned as-is. Instances
/// without a name are rejected, mirroring the Ruby `NameError`.
SyntaxHighlighterBase _instantiate(
  Object value,
  String name,
  String backend,
  Map<String, Object?> opts,
) {
  final SyntaxHighlighterBase instance = value is SyntaxHighlighterFactoryFn
      ? value(name, backend, opts)
      : value as SyntaxHighlighterBase;
  if (instance.name.isEmpty) {
    throw StateError('${instance.runtimeType} must specify a value for `name`');
  }
  return instance;
}

/// Reads the optional [SourceLexer] backend from factory [opts].
SourceLexer? _lexerFromOpts(Map<String, Object?> opts) =>
    opts['lexer'] as SourceLexer?;

/// Renders [value] the way Ruby string interpolation does: `null` becomes
/// the empty string instead of `'null'`.
String _s(Object? value) => value?.toString() ?? '';
