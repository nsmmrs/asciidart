/// Syntax-highlighter framework: registry, factory and Document integration.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter.rb` (the
/// `SyntaxHighlighter` module, `Factory`, `CustomFactory`, `DefaultFactory`,
/// `SyntaxHighlighterDefaultFactoryProxy` and `Base`).
///
/// The six language adapters in this directory (`coderay.dart`,
/// `highlightjs.dart`, `html_pipeline.dart`, `prettify.dart`, `pygments.dart`,
/// `rouge.dart`) are pure string transformers: every value they need arrives
/// as an explicit parameter. This file binds them to the document model:
///
/// * [SyntaxHighlighterBase] is the base-class contract custom highlighters
///   extend (port of the module defaults plus `Base#format`).
/// * The `*Highlighter` wrapper classes adapt each adapter to that
///   contract, translating node/document reads into the adapters' explicit
///   parameters.
/// * [SyntaxHighlighter] is the global registry and factory (port of the
///   `DefaultFactory` statics), [SyntaxHighlighterFactory] an isolated
///   registry (port of `CustomFactory`) and
///   [SyntaxHighlighterDefaultFactoryProxy] a seeded registry with global
///   fallback.
/// * [SyntaxHighlighter.resolveForDocument] ports the
///   `Document#save_attributes` hook: it resolves the `source-highlighter`
///   attribute to an instance, which `Document` assigns to
///   `Document.syntaxHighlighter`.
///
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/highlight/highlight.dart';
import 'package:asciidart/src/highlight/highlightjs.dart';
import 'package:asciidart/src/highlight/html_pipeline.dart';
import 'package:asciidart/src/highlight/prettify.dart';
import 'package:asciidart/src/highlight/unavailable.dart';

/// The context a highlighter is created in.
final class HighlighterOptions {
  /// Creates highlighter options.
  const new({this.document});

  /// The document being converted, if known.
  final Document? document;
}

/// Options for formatting a source block.
final class FormatOptions {
  /// Creates format options.
  const new({
    this.nowrap = false,
    this.cssMode = CssMode.classes,
    this.style,
    this.transform,
  });

  /// Whether long lines are not wrapped.
  final bool nowrap;

  /// Whether highlighting uses classes or inline styles (server-side
  /// highlighters only).
  final CssMode cssMode;

  /// The highlighting theme (server-side highlighters only).
  final String? style;

  /// Adjusts the attributes of the `pre` and `code` tags before they are
  /// rendered.
  final void Function(Map<String, String> pre, Map<String, String> code)?
  transform;
}

/// Creates a highlighter instance for a registered name.
///
/// [name] is the lookup name, [backend] the document backend (`'html5'` by
/// default) and [opts] carries the creation context.
typedef SyntaxHighlighterFactoryFn = SyntaxHighlighterBase Function(
  String name,
  String backend,
  HighlighterOptions opts,
);

/// Base-class contract for syntax highlighters.
///
/// Port of the `SyntaxHighlighter` module defaults plus `Base`. Custom
/// highlighters extend this class and override what they support; anything
/// left at its default either reports absence (`false`) or throws
/// [UnimplementedError].
abstract class SyntaxHighlighterBase {
  /// The highlighter name (e.g. `'rouge'`).
  ///
  /// Selects the `{name}-css`, `{name}-style` and `{name}-linenums-mode`
  /// document attributes. Must be non-empty: [SyntaxHighlighter.create]
  /// rejects nameless instances.
  String get name;

  /// The `<pre>` CSS class (port of `@pre_class`).
  ///
  /// Defaults to [name]; adapters with a distinct class override it.
  String get preClass => name;

  /// Whether highlighting runs during conversion (port of `highlight?`).
  ///
  /// Defaults to `false`. When `true`, the substitutions call [highlight] to
  /// handle the `specialcharacters` substitution.
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
  /// `data-lang`, running the [FormatOptions.transform] callback when
  /// present.
  String format(AbstractBlock node, String? language, FormatOptions opts) =>
      wrapSourceBlock(
        preClass: preClass,
        content: node.content() ?? '',
        language: language,
        nowrap: opts.nowrap,
        transform: opts.transform,
      );

  /// Whether markup is injected at [location] (port of `docinfo?`).
  ///
  /// [location] is `'head'` or `'footer'`. Defaults to `false`.
  bool hasDocinfo(String location) => false;

  /// Returns the markup injected at [location] (port of `docinfo`).
  ///
  /// [node] is the document being converted, [cdnBaseUrl] the CDN root for
  /// remote assets, [linkcss] whether stylesheets are linked instead of
  /// embedded, and [selfClosingTagSlash] the converter's void-element slash.
  ///
  /// Throws [UnimplementedError] unless overridden.
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
/// All six built-in adapters register on first access. Lookups for unknown
/// names return `null`.
abstract final class SyntaxHighlighter {
  static final Map<String, SyntaxHighlighterFactoryFn> _registry =
      <String, SyntaxHighlighterFactoryFn>{};
  static bool _builtinsRegistered = false;

  /// Associates [factory] with each of [names] (port of
  /// `Factory#register`).
  static void register(
    SyntaxHighlighterFactoryFn factory,
    Iterable<String> names,
  ) {
    _ensureBuiltins();
    for (final name in names) {
      _registry[name] = factory;
    }
  }

  /// Associates the [highlighter] instance with each of [names].
  static void registerInstance(
    SyntaxHighlighterBase highlighter,
    Iterable<String> names,
  ) => register((_, _, _) => highlighter, names);

  /// Returns the registration for [name], or `null` (port of `Factory#for`).
  static SyntaxHighlighterFactoryFn? forName(String name) {
    _ensureBuiltins();
    return _registry[name];
  }

  /// Resolves [name] to a highlighter instance (port of `Factory#create`).
  ///
  /// Returns `null` when [name] is not registered.
  static SyntaxHighlighterBase? create(
    String name, [
    String backend = 'html5',
    HighlighterOptions opts = const HighlighterOptions(),
  ]) {
    final found = forName(name);
    if (found == null) return null;
    return _instantiate(found, name, backend, opts);
  }

  /// Resolves the highlighter for [doc] (port of the
  /// `Document#save_attributes` hook).
  ///
  /// Returns `null` unless the base backend is HTML, the `source-highlighter`
  /// attribute is set, and the `{name}-unavailable` attribute is unset —
  /// as in Asciidoctor. The `syntaxHighlighterFactory` and
  /// `syntaxHighlighters` document options take precedence over the global
  /// registry.
  static SyntaxHighlighterBase? resolveForDocument(Document doc) {
    if (!doc.basebackend('html')) return null;
    final name = doc.attributes['source-highlighter'];
    if (name == null) return null;
    if (doc.attributes.containsKey('$name-unavailable')) return null;
    final backend = doc.backend ?? 'html5';
    final opts = HighlighterOptions(document: doc);
    final factory = doc.options.syntaxHighlighterFactory;
    if (factory != null) return factory.create(name, backend, opts);
    final highlighters = doc.options.syntaxHighlighters;
    if (highlighters != null) {
      return SyntaxHighlighterDefaultFactoryProxy(highlighters)
          .create(name, backend, opts);
    }
    return create(name, backend, opts);
  }

  static void _ensureBuiltins() {
    if (_builtinsRegistered) return;
    _builtinsRegistered = true;
    void add(
      SyntaxHighlighterBase Function(HighlighterOptions opts) make,
      Iterable<String> names,
    ) {
      for (final name in names) {
        _registry[name] = (_, _, opts) => make(opts);
      }
    }

    // highlight.js is asciidart's highlighter (hilite); html-pipeline and
    // prettify only emit markup for tools that highlight later. Rouge,
    // Pygments and CodeRay behave as without their gems.
    add(
      (opts) => HighlightJsHighlighter(document: opts.document),
      HighlightJsAdapter.registeredNames,
    );
    add(
      (opts) => HtmlPipelineHighlighter(),
      HtmlPipelineAdapter.registeredNames,
    );
    add((opts) => PrettifyHighlighter(), PrettifyAdapter.registeredNames);
    add((opts) => UnavailableHighlighter.pygments(), const ['pygments']);
    add((opts) => UnavailableHighlighter.rouge(), const ['rouge']);
    add((opts) => UnavailableHighlighter.coderay(), const ['coderay']);
  }
}

/// Isolated highlighter registry (port of `CustomFactory`).
///
/// Starts empty (or seeded with `seedRegistry`) and never sees the global
/// registrations; use [SyntaxHighlighterDefaultFactoryProxy] for a seeded
/// registry that falls back to the globals.
class SyntaxHighlighterFactory {
  /// Creates an isolated factory, optionally seeded with [seedRegistry].
  new([Map<String, SyntaxHighlighterFactoryFn>? seedRegistry])
    : _registry = <String, SyntaxHighlighterFactoryFn>{...?seedRegistry};

  final Map<String, SyntaxHighlighterFactoryFn> _registry;

  /// Associates [factory] with each of [names].
  void register(SyntaxHighlighterFactoryFn factory, Iterable<String> names) {
    for (final name in names) {
      _registry[name] = factory;
    }
  }

  /// Associates the [highlighter] instance with each of [names].
  void registerInstance(
    SyntaxHighlighterBase highlighter,
    Iterable<String> names,
  ) => register((_, _, _) => highlighter, names);

  /// Returns the registration for [name], or `null` (port of `Factory#for`).
  SyntaxHighlighterFactoryFn? forName(String name) => _registry[name];

  /// Resolves [name] to a highlighter instance (port of `Factory#create`).
  SyntaxHighlighterBase? create(
    String name, [
    String backend = 'html5',
    HighlighterOptions opts = const HighlighterOptions(),
  ]) {
    final found = forName(name);
    if (found == null) return null;
    return _instantiate(found, name, backend, opts);
  }
}

/// Seeded registry with global fallback (port of
/// `SyntaxHighlighter::DefaultFactoryProxy`).
///
/// Looks up the seed registry first, then the global [SyntaxHighlighter]
/// registry (the `syntaxHighlighters` document option).
class SyntaxHighlighterDefaultFactoryProxy extends SyntaxHighlighterFactory {
  /// Creates a proxy seeded with [seedRegistry].
  new([super.seedRegistry]);

  @override
  SyntaxHighlighterFactoryFn? forName(String name) =>
      _registry[name] ?? SyntaxHighlighter.forName(name);
}

/// Framework binding for the html-pipeline adapter.
///
/// Emits `<pre lang>` hooks only; highlighting happens downstream in the
/// html-pipeline filter chain. `hasDocinfo` stays `false` and `docinfo` is
/// left unimplemented (calling it throws).
class HtmlPipelineHighlighter extends SyntaxHighlighterBase {
  /// The bound string-transformer adapter.
  final HtmlPipelineAdapter adapter = const HtmlPipelineAdapter();

  @override
  String get name => HtmlPipelineAdapter.name;

  @override
  String format(AbstractBlock node, String? language, FormatOptions opts) =>
      adapter.format(content: node.content() ?? '', language: language);
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
  String format(AbstractBlock node, String? language, FormatOptions opts) =>
      adapter.format(
        content: node.content() ?? '',
        language: language,
        nowrap: opts.nowrap,
        linenums: node.hasOption('linenums'),
        start: node.attr('start'),
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
    final prettifyDir = node.attr('prettifydir');
    if (location == 'head') {
      return adapter.docinfoHead(
        prettifyDir: prettifyDir,
        theme: node.attr('prettify-theme', 'prettify')!,
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

/// Instantiates a registered [factory] (port of the `Factory#create`
/// tail), rejecting instances without a name.
SyntaxHighlighterBase _instantiate(
  SyntaxHighlighterFactoryFn factory,
  String name,
  String backend,
  HighlighterOptions opts,
) {
  final instance = factory(name, backend, opts);
  if (instance.name.isEmpty) {
    throw StateError('${instance.runtimeType} must specify a value for `name`');
  }
  return instance;
}
