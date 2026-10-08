/// Converter framework: registration, factories and the dispatch base
/// classes.
///
/// The backend converters (`html5`, `docbook5`, `manpage`) extend
/// [BuiltInConverter], which dispatches on the kind of node with exhaustive
/// switches. The template and composite converters extend [ConverterBase],
/// which dispatches on transform names registered with
/// [ConverterBase.handle], as templates are found by name.
///
/// ## Explicit registration
///
/// Every converter registers itself explicitly with [Converter.register]
/// (there is no lazy loading by backend name):
///
/// ```dart
/// class Html5Converter extends BuiltInConverter {
///   /// Registers this converter for [backends]. Called by document
///   /// initialization; idempotent.
///   static void registerFor([List<String> backends = const ['html5']]) {
///     Converter.register(Html5Converter.new, backends, provided: true);
///   }
/// }
/// ```
///
/// Registrations flagged `provided: true` survive
/// [Converter.unregisterAll]. Registration is idempotent (re-registering
/// overwrites the same entry), so document initialization can safely call
/// every backend's `registerFor` before looking a converter up.
///
/// ## Method dispatch
///
/// [Converter.handles] reports whether a converter converts a transform
/// (`paragraph`, `inline_quoted`, `embedded`, ...), which is what
/// `CompositeConverter` relies on to put templates in front of a built-in
/// converter.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/constants.dart';
import 'package:ptome/src/document.dart' show Document;
import 'package:ptome/src/inline.dart' show Inline;
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/template.dart'
    show TemplateRegistry, buildTemplateChain;
import 'package:ptome/src/template_loader.dart'
    show FileTemplateLoader, TemplateCache, validateTemplateEngine;

/// Trailing digits stripped from a backend name to derive its base backend.
final RegExp _trailingDigits = RegExp(r'\d+$');

/// The options a converter is created with.
final class ConverterOptions {
  /// Creates converter options.
  const new({
    this.document,
    this.htmlsyntax,
    this.templateDirs = const <String>[],
    this.templateCache = true,
    this.templateCacheStore,
    this.templateEngine,
    this.safe = SafeMode.secure,
    this.delegateBackend,
  });

  /// The document being converted, if known.
  final Document? document;

  /// The HTML syntax requested by the document (`html` or `xml`).
  final String? htmlsyntax;

  /// Directories containing custom templates.
  final List<String> templateDirs;

  /// Whether scanned templates are cached across documents.
  final bool templateCache;

  /// A custom template cache, used instead of the shared one.
  final TemplateCache? templateCacheStore;

  /// The template engine (`mustache` or `dart`).
  final String? templateEngine;

  /// The safe mode level of the document.
  final int safe;

  /// The backend whose converter handles what the templates do not.
  final String? delegateBackend;
}

/// Options for a single conversion: overrides of the `toclevels` and
/// `sectnumlevels` document attributes for a table of contents.
final class ConvertOptions {
  /// Creates conversion options.
  const new({this.toclevels, this.sectnumlevels});

  /// The number of section levels in a table of contents.
  final int? toclevels;

  /// The number of section levels that are numbered.
  final int? sectnumlevels;
}

/// The traits of a backend: its base backend, file type, output file
/// suffix and (for HTML) syntax.
final class BackendTraits {
  /// Creates backend traits.
  new({
    required this.basebackend,
    required this.filetype,
    required this.outfilesuffix,
    this.htmlsyntax,
    this.supportsTemplates = false,
  });

  /// Derives the backend traits for [backend].
  ///
  /// The base backend is [basebackend] when given, otherwise [backend]
  /// with trailing digits stripped (so `'html5'` derives from `'html'`).
  factory derive(String backend, [String? basebackend]) {
    final base = basebackend ?? backend.replaceAll(_trailingDigits, '');
    final outfilesuffix = defaultExtensions[base];
    final String filetype;
    final String suffix;
    if (outfilesuffix != null) {
      suffix = outfilesuffix;
      filetype = outfilesuffix.substring(1);
    } else {
      filetype = base;
      suffix = '.$base';
    }
    return BackendTraits(
      basebackend: base,
      filetype: filetype,
      outfilesuffix: suffix,
      htmlsyntax: filetype == 'html' ? 'html' : null,
    );
  }

  /// The base backend (e.g. `'html'` for backend `'html5'`).
  String basebackend;

  /// The file type produced (e.g. `'html'`).
  String filetype;

  /// The output file suffix (e.g. `'.html'`).
  String outfilesuffix;

  /// The HTML syntax variant (`'html'` or `'xml'`), when applicable.
  String? htmlsyntax;

  /// Whether template overrides wrap the converter in a composite.
  bool supportsTemplates;
}

/// Creates a [Converter] for [backend] with constructor options [opts].
///
/// A converter class whose constructor is
/// `MyConverter(String backend, [ConverterOptions opts])` registers its
/// constructor tear-off (`MyConverter.new`) directly.
typedef ConverterFactoryFn = Converter Function(
  String backend,
  ConverterOptions opts,
);

/// Shared `create` implementation used by [Converter.create] and the
/// [ConverterFactory] implementations.
///
/// Looks the backend up with [forBackend] and instantiates the
/// registration; returns `null` when nothing is registered. Templates
/// engage through `templateDirs` (an unknown template engine fails first)
/// or through compiled-in [TemplateRegistry.global] overrides: a resolved
/// converter that [BackendTraits.supportsTemplates] is wrapped in a
/// composite with the template converter ahead; one that does not is
/// returned as is. With no registration, `delegateBackend` names the
/// fallback converter, else a bare template converter is returned.
Converter? _createFrom(
  ConverterFactoryFn? Function(String backend) forBackend,
  String backend,
  ConverterOptions opts,
) {
  final hasTemplateDirs = opts.templateDirs.isNotEmpty;
  if (hasTemplateDirs) validateTemplateEngine(opts.templateEngine);
  final templatesEngaged =
      hasTemplateDirs || TemplateRegistry.globalHasOverrides;
  final found = forBackend(backend);
  if (found != null) {
    final converter = found(backend, opts);
    if (templatesEngaged && converter.backendTraits.supportsTemplates) {
      return _templateChain(backend, opts, converter);
    }
    return converter;
  }
  if (hasTemplateDirs) {
    final delegateBackend = opts.delegateBackend;
    if (delegateBackend != null) {
      final delegate = forBackend(delegateBackend);
      if (delegate != null) {
        return _templateChain(backend, opts, delegate(delegateBackend, opts));
      }
    }
    return _templateChain(backend, opts, null);
  }
  if (TemplateRegistry.globalHasOverrides) {
    return _templateChain(backend, opts, null);
  }
  return null;
}

/// Builds the template chain for ([backend], [opts]) with [fallback].
///
/// Loads `*.mustache` sources through [FileTemplateLoader] (last-wins
/// across `templateDirs`, honoring the template cache); the `dart` engine
/// selects code-registered transforms only and scans no files.
Converter _templateChain(
  String backend,
  ConverterOptions opts,
  Converter? fallback,
) {
  final Map<String, String> sources;
  if (opts.templateEngine == 'dart' || opts.templateDirs.isEmpty) {
    sources = const <String, String>{};
  } else {
    sources = FileTemplateLoader(
      templateDirs: opts.templateDirs,
      templateCache: opts.templateCache,
      templateCacheStore: opts.templateCacheStore,
    ).load();
  }
  return buildTemplateChain(backend, opts, fallback, sources: sources);
}

/// Converts [AbstractNode]s in a parsed document to an output (aka backend)
/// format such as HTML or DocBook.
///
/// Port of the `Asciidoctor::Converter` module. A converter is typically
/// instantiated each time a document is processed. Implementing a custom
/// converter entails extending [Converter] (and overriding [convert]) or
/// extending [ConverterBase] (and registering per-transform handlers), then
/// registering the converter for one or more backends with [register]. The
/// built-in converters extend [BuiltInConverter].
///
/// This class also hosts the global (static) converter registry.
abstract class Converter implements NodeConverter {
  /// Creates a converter for [backend] with constructor options [opts].
  new(this.backend, [this.opts = const ConverterOptions()]);

  /// The backend name (aka format) this converter converts to.
  final String backend;

  /// The options this converter was created with.
  final ConverterOptions opts;

  /// The shared logger ([LoggerManager.logger]).
  LoggerBase get logger => LoggerManager.logger;

  /// Converts [node] using the given [transform], or returns `null` when
  /// the converter produces nothing for it.
  ///
  /// When [transform] is omitted, most converters derive it from
  /// [AbstractNode.nodeName]. [opts] carries per-call conversion options.
  @override
  String? convert(AbstractNode node, [String? transform, ConvertOptions? opts]);

  /// Reports whether this converter can convert [transform].
  ///
  /// Used by the `CompositeConverter` to select which converter handles a
  /// node. Returns `true` by default; [ConverterBase] and
  /// [BuiltInConverter] override it to report what they convert.
  bool handles(String transform) => true;

  BackendTraits? _backendTraits;

  /// The backend traits for this converter, derived lazily from [backend]
  /// unless assigned.
  BackendTraits get backendTraits =>
      _backendTraits ??= BackendTraits.derive(backend);

  set backendTraits(BackendTraits value) {
    _backendTraits = value;
  }

  /// The global registry: backend name to factory, or explicit `null`.
  static final Map<String, ConverterFactoryFn?> _registry =
      <String, ConverterFactoryFn?>{};

  /// The global catch-all registration (backend `'*'`), if any.
  static ConverterFactoryFn? _catchAll;

  /// Globally registered backends that survive [unregisterAll].
  static final Set<String> _provided = <String>{};

  /// Registers [factory] globally to handle [backends].
  ///
  /// A `null` [factory] shadows any other registration. Registering backend
  /// `'*'` installs a catch-all used for backends with no registration.
  /// Pass `provided: true` for converters shipped with this package so the
  /// entry survives [unregisterAll].
  static void register(
    ConverterFactoryFn? factory,
    List<String> backends, {
    bool provided = false,
  }) {
    for (final backend in backends) {
      if (backend == '*') {
        _catchAll = factory;
      } else {
        _registry[backend] = factory;
        if (provided) {
          _provided.add(backend);
        } else {
          _provided.remove(backend);
        }
      }
    }
  }

  /// Registers [converter] globally to handle [backends]; [create] returns
  /// this instance for them.
  static void registerInstance(Converter converter, List<String> backends) =>
      register((_, _) => converter, backends);

  /// Looks up the global registration for [backend]; the catch-all (if
  /// any) when [backend] has no registration.
  static ConverterFactoryFn? forBackend(String backend) {
    if (_registry.containsKey(backend)) return _registry[backend];
    return _catchAll;
  }

  /// Creates a converter for [backend], forwarding [opts] to its factory.
  ///
  /// Returns `null` when nothing (or an explicit `null`) is registered. A
  /// non-empty `templateDirs` option (or compiled-in
  /// [TemplateRegistry.global] overrides) engages a template chain ahead
  /// of the resolved converter.
  static Converter? create(
    String backend, [
    ConverterOptions opts = const ConverterOptions(),
  ]) => _createFrom(forBackend, backend, opts);

  /// The backends registered globally (not including the catch-all).
  ///
  /// Intended for testing only.
  static Set<String> get registeredBackends => _registry.keys.toSet();

  /// Unregisters every globally registered converter except `provided` ones.
  ///
  /// The catch-all is always cleared. Intended for testing only.
  static void unregisterAll() {
    _registry.removeWhere((backend, _) => !_provided.contains(backend));
    _catchAll = null;
  }
}

/// A converter whose output is a file of its own format (a package such
/// as an EPUB) rather than the text [Converter.convert] returns: it writes
/// that file itself once the document is converted.
abstract interface class PackagingConverter {
  /// Writes the output of the converted document to [path].
  void write(String path);

  /// The output of the converted document as one file's bytes, or null
  /// when it is several files (a website).
  Uint8List? get output;
}

/// A [PackagingConverter] whose output may wait for work on other cores
/// (ADR-0016): [finish] awaits it; [PackagingConverter.write] does it
/// itself when it wasn't awaited.
@internal
abstract interface class FinishingConverter implements PackagingConverter {
  /// Waits for the work the converted document's output needs.
  Future<void> finish();
}

/// Registers and instantiates [Converter]s for backend names.
///
/// `ConverterFactory()` proxies the global registry, while
/// `ConverterFactory(proxyDefault: false)` resolves only its own
/// registrations.
abstract class ConverterFactory {
  /// Creates a factory, optionally seeded with [converters] (by backend;
  /// `'*'` seeds the catch-all, and a `null` value shadows the global
  /// registry). When [proxyDefault] is `true` (default), lookups fall
  /// through to the global registry.
  factory({
    Map<String, ConverterFactoryFn?>? converters,
    bool proxyDefault = true,
  }) => proxyDefault
      ? DefaultFactoryProxy(converters)
      : CustomFactory(converters);

  /// Looks up the registration for [backend].
  ConverterFactoryFn? forBackend(String backend);

  /// Creates a converter for [backend] (see [Converter.create]).
  Converter? create(
    String backend, [
    ConverterOptions opts = const ConverterOptions(),
  ]);

  /// Registers [factory] with this factory to handle [backends] (backend
  /// `'*'` installs a catch-all).
  void register(ConverterFactoryFn? factory, List<String> backends);

  /// Registers [converter] to handle [backends].
  void registerInstance(Converter converter, List<String> backends);

  /// Unregisters every converter registered with this factory.
  ///
  /// Intended for testing only. Note that [DefaultFactoryProxy] also
  /// clears the global registry.
  void unregisterAll();
}

/// A standalone converter factory with its own registry; it never consults
/// the global registry.
class CustomFactory implements ConverterFactory {
  /// Creates a factory seeded with [seed] (copied).
  new([Map<String, ConverterFactoryFn?>? seed]) {
    seed?.forEach((backend, factory) => register(factory, [backend]));
  }

  final Map<String, ConverterFactoryFn?> _registry =
      <String, ConverterFactoryFn?>{};

  ConverterFactoryFn? _catchAll;

  @override
  ConverterFactoryFn? forBackend(String backend) {
    if (_registry.containsKey(backend)) return _registry[backend];
    return _catchAll;
  }

  @override
  Converter? create(
    String backend, [
    ConverterOptions opts = const ConverterOptions(),
  ]) => _createFrom(forBackend, backend, opts);

  @override
  void register(ConverterFactoryFn? factory, List<String> backends) {
    for (final backend in backends) {
      if (backend == '*') {
        _catchAll = factory;
      } else {
        _registry[backend] = factory;
      }
    }
  }

  @override
  void registerInstance(Converter converter, List<String> backends) =>
      register((_, _) => converter, backends);

  @override
  void unregisterAll() {
    _registry.clear();
    _catchAll = null;
  }
}

/// A factory that prefers its own registry, then the global one.
///
/// Lookup order for an unregistered backend is: global registry hit, this
/// factory's catch-all, global catch-all. An explicit `null` registered
/// here shadows the global registry.
class DefaultFactoryProxy extends CustomFactory {
  /// Creates a proxy factory seeded with [seed] (see [CustomFactory]).
  new([super.seed]);

  @override
  ConverterFactoryFn? forBackend(String backend) {
    if (_registry.containsKey(backend)) return _registry[backend];
    if (Converter._registry.containsKey(backend)) {
      return Converter._registry[backend];
    }
    return _catchAll ?? Converter._catchAll;
  }

  /// Clears this factory's registry and the global (non-provided) one.
  @override
  void unregisterAll() {
    Converter.unregisterAll();
    super.unregisterAll();
  }
}

/// Base class for converters that dispatch per transform.
///
/// Port of `Converter::Base`. Subclasses register one handler per
/// transform with [handle]; [convert] dispatches on the transform and warns
/// (returning `null`) when no handler is registered.
abstract class ConverterBase extends Converter {
  /// Creates a converter for [backend] with constructor options [opts].
  new(super.backend, [super.opts]);

  final Map<String, ConvertHandler> _handlers = <String, ConvertHandler>{};

  /// The name of this converter in diagnostics: its class name, which
  /// the built-in converters spell out so that it survives minification.
  String get converterName => '$runtimeType';

  /// Registers [handler] for [transform].
  void handle(String transform, ConvertHandler handler) {
    _handlers[transform] = handler;
  }

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) {
    transform ??= node.nodeName;
    final handler = _handlers[transform];
    if (handler == null) {
      logger.warn(
        'missing convert handler for $transform node in $backend backend '
        '($converterName)',
      );
      return null;
    }
    return handler(node, opts);
  }

  /// Reports whether a handler is registered for [transform].
  @override
  bool handles(String transform) => _handlers.containsKey(transform);

  /// Converts [node] using only its converted content.
  String? contentOnly(AbstractNode node) {
    if (node is AbstractBlock) return node.content();
    throw ArgumentError.value(node, 'node', 'must be a block with content');
  }

  /// Skips conversion of [node] (produces nothing).
  String? skip(AbstractNode node) => null;
}

/// Base class of the built-in converters (HTML, DocBook, man page).
///
/// [convert] dispatches on the kind of node to [convertBlock] and
/// [convertInline], whose switches are exhaustive: a new kind of node is a
/// compile error until every converter decides what to do with it. Kinds a
/// converter leaves to their parent (list items, table cells) go to
/// [missing], and [handlesBlock] and [handlesInline] report them.
abstract class BuiltInConverter extends Converter {
  /// Creates a converter for [backend] with constructor options [opts].
  new(super.backend, [super.opts]);

  /// The name of this converter in diagnostics, spelled out so that it
  /// survives minification.
  String get converterName;

  /// Converts [node] according to its kind.
  String? convertBlock(AbstractBlock node, ConvertOptions? opts);

  /// Converts the inline element [node] according to its kind.
  String? convertInline(Inline node);

  /// Converts [node] with a transform that is not a node name
  /// (`'embedded'`, `'outline'`), or reports it [missing].
  String? convertTransform(
    AbstractNode node,
    String transform,
    ConvertOptions? opts,
  ) => missing(transform);

  /// Whether [convertBlock] converts blocks of [context].
  bool handlesBlock(BlockContext context) => true;

  /// Whether [convertInline] converts inline elements of [context].
  bool handlesInline(InlineContext context) => true;

  /// The transforms [convertTransform] handles.
  Set<String> get transforms => const {};

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) {
    if (transform != null && transform != node.nodeName) {
      return convertTransform(node, transform, opts);
    }
    return switch (node) {
      final Inline inline => convertInline(inline),
      final AbstractBlock block => convertBlock(block, opts),
      _ => missing(node.nodeName),
    };
  }

  @override
  bool handles(String transform) {
    if (transforms.contains(transform)) return true;
    if (transform.startsWith('inline_')) {
      final context = InlineContext.tryParse(transform.substring(7));
      return context != null && handlesInline(context);
    }
    final context = BlockContext.tryParse(transform);
    return context != null && handlesBlock(context);
  }

  /// Warns that this converter has no handler for [transform] and
  /// produces nothing.
  String? missing(String transform) {
    logger.warn(
      'missing convert handler for $transform node in $backend backend '
      '($converterName)',
    );
    return null;
  }

  /// Converts [node] using only its converted content.
  String? contentOnly(AbstractBlock node) => node.content();
}

/// Converts [node], optionally guided by conversion [opts], or returns
/// `null` to produce nothing.
///
/// Handlers are registered with [ConverterBase.handle].
typedef ConvertHandler = String? Function(
  AbstractNode node, [
  ConvertOptions? opts,
]);
