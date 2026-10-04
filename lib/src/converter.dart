/// Converter framework: registration, factories and the dispatch base class.
///
/// Port of `lib/asciidoctor/converter.rb` (framework only). The backend
/// converters (`html5`, `docbook5`, `manpage`) and the template converter
/// arrive in later waves; this library provides the registry, the factory
/// types and the [ConverterBase] dispatch machinery they build on.
///
/// ## Explicit registration (Dart replaces Ruby's lazy `require`)
///
/// Ruby resolves provided backends lazily: `Converter.for 'html5'` runs
/// `require 'asciidoctor/converter/html5'`, which registers the converter
/// class as a side effect (`converter.rb:320`). Dart has no runtime
/// `require`, so every converter registers itself explicitly with
/// [Converter.register]. Backend waves follow this pattern:
///
/// ```dart
/// class Html5Converter extends ConverterBase {
///   Html5Converter(super.backend, [super.opts]) {
///     handle('paragraph', (node, [opts]) => '<p>...</p>');
///   }
///
///   /// Registers this converter for [backends]. Called by document
///   /// initialization (document wave); idempotent.
///   static void registerFor([List<String> backends = const ['html5']]) {
///     Converter.register(Html5Converter.new, backends, provided: true);
///   }
/// }
/// ```
///
/// Registrations flagged `provided: true` survive
/// [Converter.unregisterAll], mirroring how Ruby's `unregister_all` keeps
/// `PROVIDED` backends. Registration is idempotent (re-registering
/// overwrites the same entry), so document initialization can safely call
/// every backend's `registerFor` before looking a converter up.
///
/// ## Method dispatch
///
/// Ruby's `Converter::Base#convert` dispatches with `send 'convert_' +
/// transform`, which has no Dart equivalent. [ConverterBase] replaces the
/// `convert_<transform>` methods with a handler map populated through
/// [ConverterBase.handle]; [ConverterBase.handles] reports whether a
/// transform is registered, preserving the `handles?`/`respond_to?`
/// contract the `CompositeConverter` relies on.
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/template.dart'
    show TemplateRegistry, buildTemplateChain;
import 'package:asciidoctor/src/template_loader.dart'
    show VmTemplateLoader, validateTemplateEngine;

/// Trailing digits stripped from a backend name to derive its base backend.
///
/// Port of `TrailingDigitsRx` in `lib/asciidoctor/rx.rb` (as used by
/// `Converter.derive_backend_traits`).
final RegExp _trailingDigits = RegExp(r'\d+$');

/// Creates a [Converter] for [backend] with constructor options [opts].
///
/// The registry stores either [Converter] instances (returned as-is by
/// `create`) or factory functions of this shape (invoked with the backend
/// and options). A converter class whose constructor is
/// `MyConverter(String backend, [Map<String, Object?> opts])` registers its
/// constructor tear-off (`MyConverter.new`) directly.
typedef ConverterFactoryFn = Converter Function(
  String backend,
  Map<String, Object?> opts,
);

/// Whether [value] counts as set, mirroring Ruby truthiness (`nil`/`false`
/// are unset; everything else, including empty collections, is set).
bool _isSet(Object? value) => value != null && value != false;

/// Resolves a registry [registration] to a [Converter] instance.
Converter _resolveRegistration(
  Object? registration,
  String backend,
  Map<String, Object?> opts,
) {
  if (registration is Converter) return registration;
  if (registration is ConverterFactoryFn) return registration(backend, opts);
  throw StateError(
    'Converter registered for backend "$backend" must be a Converter '
    'instance or a ConverterFactoryFn, but was: $registration',
  );
}

/// Shared `create` implementation used by [Converter.create] and the
/// [ConverterFactory] implementations. Looks the backend up with
/// [forBackend], instantiates factory registrations, and returns `null`
/// when nothing is registered (or an explicit `null` is registered).
///
/// Port of the `Factory.create` template branches: a truthy
/// `template_dirs` option engages a template chain (unknown
/// `template_engine` names fail first via [validateTemplateEngine] with
/// the port's missing-engine diagnostic). A registered converter that
/// [Converter.supportsTemplates] is wrapped in a composite with the
/// template converter ahead; one that does not is returned as-is
/// (templates ignored). With no registration, `delegate_backend` names
/// the fallback converter, else a bare template converter is returned
/// (its backend traits derive from [backend]). A `delegate_backend`
/// without `template_dirs` stays inert (Ruby parity: both branches miss
/// and `create` returns `null`).
///
/// Dart-only addition (ADR-0002 T6): compiled-in [TemplateRegistry.global]
/// overrides engage a template chain even without `template_dirs`, so an
/// XMonad-style custom binary needs no `-T` directory.
Converter? _createFrom(
  Object? Function(String backend) forBackend,
  String backend,
  Map<String, Object?> opts,
) {
  final templateDirsOpt = opts['template_dirs'];
  if (_isSet(templateDirsOpt)) {
    // Unknown engines fail here — before any TemplateConverter work — so
    // `-E bogus -T dir` reports Ruby's missing-engine failure.
    validateTemplateEngine(opts['template_engine']);
  }
  // Templates engage through `template_dirs` (Ruby) or through compiled-in
  // global overrides (Dart-only path (a)).
  final templatesEngaged =
      _isSet(templateDirsOpt) || TemplateRegistry.globalHasOverrides;
  final found = forBackend(backend);
  if (found != null) {
    final converter = _resolveRegistration(found, backend, opts);
    if (templatesEngaged && converter.supportsTemplates) {
      return _templateChain(backend, opts, converter);
    }
    return converter;
  }
  if (_isSet(templateDirsOpt)) {
    final delegateBackend = opts['delegate_backend'];
    if (_isSet(delegateBackend)) {
      final delegate = forBackend(delegateBackend.toString());
      if (delegate != null) {
        return _templateChain(
          backend,
          opts,
          _resolveRegistration(delegate, delegateBackend.toString(), opts),
        );
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
/// Loads `*.mustache` sources through [VmTemplateLoader] (last-wins
/// across `template_dirs`, honoring `template_cache`); the `dart` engine
/// selects code-registered transforms only and scans no files. A lone
/// `template_dirs` string coerces to a one-element list (Ruby's
/// `[*template_dirs]`). See [buildTemplateChain] for the assembly.
Converter _templateChain(
  String backend,
  Map<String, Object?> opts,
  Converter? fallback,
) {
  final templateDirsOpt = opts['template_dirs'];
  final Map<String, String> sources;
  if (opts['template_engine'] == 'dart' || !_isSet(templateDirsOpt)) {
    sources = const <String, String>{};
  } else {
    final dirs = templateDirsOpt is Iterable
        ? templateDirsOpt.map((dir) => dir.toString()).toList()
        : <String>[templateDirsOpt.toString()];
    sources = VmTemplateLoader(
      templateDirs: dirs,
      templateCache: opts.containsKey('template_cache')
          ? opts['template_cache']
          : true,
    ).load();
  }
  return buildTemplateChain(backend, opts, fallback, sources: sources);
}

/// Guards [Converter.register] and the factory seed maps. The registry only
/// accepts [Converter] instances, [ConverterFactoryFn] factories and
/// explicit `null` (which shadows any other registration for that backend).
void _checkRegistration(Object? converter) {
  if (converter == null ||
      converter is Converter ||
      converter is ConverterFactoryFn) {
    return;
  }
  throw ArgumentError.value(
    converter,
    'converter',
    'must be a Converter instance, a ConverterFactoryFn, or null',
  );
}

/// Converts [AbstractNode]s in a parsed document to an output (aka backend)
/// format such as HTML or DocBook.
///
/// Port of the `Asciidoctor::Converter` module. A converter is typically
/// instantiated each time a document is processed. Implementing a custom
/// converter entails extending [Converter] (and overriding [convert]) or
/// extending [ConverterBase] (and registering per-transform handlers), then
/// registering the converter for one or more backends with [register].
///
/// This class also hosts the global (static) converter registry, port of
/// the `DefaultFactory` state mixed into the Ruby `Converter` module. Ruby
/// guards the global registry with a mutex; Dart's single-threaded
/// execution model makes that unnecessary.
abstract class Converter implements NodeConverter {
  /// Creates a converter for [backend] with constructor options [opts].
  new(this.backend, [this.opts = const <String, Object?>{}]);

  /// The backend name (aka format) this converter converts to.
  final String backend;

  /// The options this converter was created with.
  ///
  /// Ruby's `Converter#initialize` accepts but ignores `opts`; subclasses
  /// consume them. The port stores the map so subclasses can read it.
  final Map<String, Object?> opts;

  /// Lazily derived backend traits (see [backendTraits]).
  Map<String, Object?>? _backendTraits;

  /// The shared logger. Mirrors the `logger` method from the `Logging`
  /// mixin (mixed into `Converter::Base` in Ruby).
  NodeLogger get logger => AbstractNode.currentLogger;

  /// Converts [node] using the given [transform].
  ///
  /// When [transform] is omitted, most converters derive it from
  /// [AbstractNode.nodeName]. [opts] carries per-call conversion hints.
  ///
  /// The default implementation throws [UnimplementedError], mirroring
  /// Ruby's `NotImplementedError`, so subclasses that forget to override
  /// it fail loudly instead of silently.
  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) {
    throw UnimplementedError(
      '$runtimeType (backend: $backend) must implement the convert method',
    );
  }

  /// Reports whether this converter can convert [transform].
  ///
  /// Used by the `CompositeConverter` to select which converter handles a
  /// node. Returns `true` by default; [ConverterBase] overrides it to
  /// report registered handlers.
  bool handles(String transform) => true;

  /// Derives the backend traits for [backend].
  ///
  /// The base backend is [baseBackend] when given, otherwise [backend]
  /// with trailing digits stripped (so `'html5'` derives from `'html'`).
  /// Returns `{}` when [backend] is `null`.
  static Map<String, Object?> deriveBackendTraits(
    String? backend, [
    String? baseBackend,
  ]) {
    if (backend == null) return <String, Object?>{};
    baseBackend ??= backend.replaceAll(_trailingDigits, '');
    final outfilesuffix = defaultExtensions[baseBackend];
    late final String filetype;
    late final String suffix;
    if (outfilesuffix != null) {
      suffix = outfilesuffix;
      filetype = outfilesuffix.substring(1);
    } else {
      filetype = baseBackend;
      suffix = '.$baseBackend';
    }
    return filetype == 'html'
        ? <String, Object?>{
            'basebackend': baseBackend,
            'filetype': filetype,
            'htmlsyntax': 'html',
            'outfilesuffix': suffix,
          }
        : <String, Object?>{
            'basebackend': baseBackend,
            'filetype': filetype,
            'outfilesuffix': suffix,
          };
  }

  /// The backend traits for this converter, derived lazily from [backend].
  ///
  /// Port of `BackendTraits#backend_traits`. [baseBackend] is honored only
  /// on the first call (the result is memoized), exactly as in Ruby.
  Map<String, Object?> backendTraits([String? baseBackend]) =>
      _backendTraits ??= deriveBackendTraits(backend, baseBackend);

  /// Alias of [backendTraits]. Port of `BackendTraits#backend_info`.
  Map<String, Object?> backendInfo([String? baseBackend]) =>
      backendTraits(baseBackend);

  /// Replaces the memoized [backendTraits] with [value] (or `{}`).
  ///
  /// Port of `BackendTraits#init_backend_traits`. Used by the
  /// `CompositeConverter` to adopt its delegate's traits.
  void initBackendTraits([Map<String, Object?>? value]) {
    _backendTraits = value ?? <String, Object?>{};
  }

  /// The base backend (e.g. `'html'` for backend `'html5'`).
  ///
  /// Setting re-derives the memoized traits from `value` first (when not
  /// yet derived), so `filetype` and `outfilesuffix` follow the new base
  /// backend — mirroring Ruby, where the setter delegates to
  /// `backend_traits value`.
  String? get baseBackend => backendTraits()['basebackend'] as String?;
  set baseBackend(String? value) {
    backendTraits(value)['basebackend'] = value;
  }

  /// The file type produced by this converter (e.g. `'html'`).
  String? get fileType => backendTraits()['filetype'] as String?;
  set fileType(String? value) {
    backendTraits()['filetype'] = value;
  }

  /// The HTML syntax variant (`'html'` or `'xml'`), when applicable.
  String? get htmlSyntax => backendTraits()['htmlsyntax'] as String?;
  set htmlSyntax(String? value) {
    backendTraits()['htmlsyntax'] = value;
  }

  /// The output file suffix (e.g. `'.html'`).
  String? get outfileSuffix => backendTraits()['outfilesuffix'] as String?;
  set outfileSuffix(String? value) {
    backendTraits()['outfilesuffix'] = value;
  }

  /// Whether template overrides wrap this converter in a composite.
  ///
  /// Ruby spells the setter `supports_templates` (defaulting to `true`)
  /// and the getter `supports_templates?`; Dart uses one property.
  /// Defaults to `false`.
  bool get supportsTemplates => backendTraits()['supports_templates'] == true;
  set supportsTemplates(bool value) {
    backendTraits()['supports_templates'] = value;
  }

  /// The global registry: backend name to [Converter] instance,
  /// [ConverterFactoryFn], or explicit `null`.
  static final Map<String, Object?> _registry = <String, Object?>{};

  /// The global catch-all registration (backend `'*'`), if any.
  static Object? _catchAll;

  /// Globally registered backends that survive [unregisterAll].
  ///
  /// Mirrors Ruby's `PROVIDED` map: backends whose converters are part of
  /// the port register with `provided: true` and are kept when test
  /// doubles are unregistered.
  static final Set<String> _provided = <String>{};

  /// Registers [converter] globally to handle [backends].
  ///
  /// Port of `Converter.register` (invoked via the `register_for` DSL in
  /// Ruby). [converter] is a [Converter] instance (returned as-is by
  /// [create]), a [ConverterFactoryFn] (invoked per [create] call), or
  /// `null` (shadowing any other registration). Registering backend `'*'`
  /// installs a catch-all used for backends with no registration. Pass
  /// `provided: true` for converters shipped by the port so the entry
  /// survives [unregisterAll].
  static void register(
    Object? converter,
    List<String> backends, {
    bool provided = false,
  }) {
    _checkRegistration(converter);
    for (final backend in backends) {
      if (backend == '*') {
        _catchAll = converter;
      } else {
        _registry[backend] = converter;
        if (provided) {
          _provided.add(backend);
        } else {
          _provided.remove(backend);
        }
      }
    }
  }

  /// Looks up the global registration for [backend].
  ///
  /// Port of `Converter.for`. Returns the registered [Converter] instance,
  /// [ConverterFactoryFn], or explicit `null`; returns the catch-all (if
  /// any) when [backend] has no registration. Unlike Ruby, there is no
  /// lazy loading: backends must be registered explicitly (see the
  /// library documentation).
  static Object? forBackend(String backend) {
    if (_registry.containsKey(backend)) return _registry[backend];
    return _catchAll;
  }

  /// Creates a converter for [backend], forwarding [opts] to its factory.
  ///
  /// Port of `Converter.create`. Returns a registered instance as-is,
  /// invokes a registered factory with ([backend], [opts]), and returns
  /// `null` when nothing (or an explicit `null`) is registered. A truthy
  /// `template_dirs` option (or compiled-in [TemplateRegistry.global]
  /// overrides) engages a template chain ahead of the resolved converter
  /// (see [_createFrom]).
  static Converter? create(
    String backend, [
    Map<String, Object?> opts = const <String, Object?>{},
  ]) => _createFrom(forBackend, backend, opts);

  /// A copy of the global registry, keyed by backend name.
  ///
  /// Port of `Converter.converters`. Intended for testing only. The
  /// catch-all is not included (it is not keyed by backend).
  static Map<String, Object?> get converters => Map.of(_registry);

  /// Unregisters every globally registered converter except `provided` ones.
  ///
  /// Port of `Converter.unregister_all`. The catch-all is always cleared.
  /// Intended for testing only.
  static void unregisterAll() {
    _registry.removeWhere((backend, _) => !_provided.contains(backend));
    _catchAll = null;
  }
}

/// Registers and instantiates [Converter]s for backend names.
///
/// Port of the `Converter::Factory` module. Use the factory constructor
/// (port of `Factory.new`): `ConverterFactory()` proxies the global
/// registry, while `ConverterFactory(proxyDefault: false)` resolves only its
/// own registrations.
abstract class ConverterFactory {
  /// Creates a factory, optionally seeded with [converters].
  ///
  /// Keys are backend names (`'*'` seeds the catch-all); values are
  /// [Converter] instances, [ConverterFactoryFn] factories, or explicit
  /// `null`. When [proxyDefault] is `true` (default), lookups fall through
  /// to the global registry; otherwise only the seed (and later
  /// [register] calls) resolve.
  factory({Map<String, Object?>? converters, bool proxyDefault = true}) =>
      proxyDefault
      ? DefaultFactoryProxy(converters)
      : CustomFactory(converters);

  /// Looks up the registration for [backend].
  Object? forBackend(String backend);

  /// Creates a converter for [backend] (see [Converter.create]).
  Converter? create(
    String backend, [
    Map<String, Object?> opts = const <String, Object?>{},
  ]);

  /// A copy of this factory's registry, keyed by backend name.
  Map<String, Object?> get converters;

  /// Registers [converter] with this factory to handle [backends].
  ///
  /// Backend `'*'` installs a catch-all. See [Converter.register] for the
  /// accepted registration shapes.
  void register(Object? converter, List<String> backends);

  /// Unregisters every converter registered with this factory.
  ///
  /// Intended for testing only. Note that [DefaultFactoryProxy] also
  /// clears the global registry, mirroring Ruby.
  void unregisterAll();
}

/// A standalone converter factory with its own registry.
///
/// Port of `Converter::CustomFactory`. Never consults the global registry.
class CustomFactory implements ConverterFactory {
  /// Creates a factory seeded with [seed] (a copy; the map is not mutated).
  new([Map<String, Object?>? seed]) {
    seed?.forEach((backend, converter) {
      _checkRegistration(converter);
      if (backend == '*') {
        _catchAll = converter;
      } else {
        _registry[backend] = converter;
      }
    });
  }

  /// This factory's registry (never contains `'*'`).
  final Map<String, Object?> _registry = <String, Object?>{};

  /// This factory's catch-all registration (backend `'*'`), if any.
  Object? _catchAll;

  @override
  Object? forBackend(String backend) {
    if (_registry.containsKey(backend)) return _registry[backend];
    return _catchAll;
  }

  @override
  Converter? create(
    String backend, [
    Map<String, Object?> opts = const <String, Object?>{},
  ]) => _createFrom(forBackend, backend, opts);

  @override
  Map<String, Object?> get converters => Map.of(_registry);

  @override
  void register(Object? converter, List<String> backends) {
    _checkRegistration(converter);
    for (final backend in backends) {
      if (backend == '*') {
        _catchAll = converter;
      } else {
        _registry[backend] = converter;
      }
    }
  }

  @override
  void unregisterAll() {
    _registry.clear();
    _catchAll = null;
  }
}

/// A factory that prefers its own registry, then the global one.
///
/// Port of `Converter::DefaultFactoryProxy`. Lookup order for an
/// unregistered backend is: global registry hit, this factory's catch-all,
/// global catch-all (mirroring Ruby's `fetch`-then-`catch_all` chain). An
/// explicit `null` registered here shadows the global registry.
class DefaultFactoryProxy extends CustomFactory {
  /// Creates a proxy factory seeded with [seed] (see [CustomFactory]).
  new([super.seed]);

  @override
  Object? forBackend(String backend) {
    if (_registry.containsKey(backend)) return _registry[backend];
    if (Converter._registry.containsKey(backend)) {
      return Converter._registry[backend];
    }
    return _catchAll ?? Converter._catchAll;
  }

  /// Clears this factory's registry and the global one.
  ///
  /// Mirrors Ruby, where `DefaultFactoryProxy#unregister_all` delegates to
  /// `DefaultFactory#unregister_all` (clearing non-provided global entries
  /// and the global catch-all) before clearing its own registry.
  @override
  void unregisterAll() {
    Converter.unregisterAll();
    super.unregisterAll();
  }
}

/// Base class for converters that dispatch per transform.
///
/// Port of `Converter::Base`. Subclasses register one handler per
/// transform with [handle] (the Dart equivalent of defining
/// `convert_<transform>` methods); [convert] dispatches on the transform
/// and warns (returning `null`) when no handler is registered, mirroring
/// Ruby's `NoMethodError` rescue. Subclasses may override [convert] and
/// [handles] directly instead (as Ruby converters that override `convert`
/// and alias `handles?` do).
abstract class ConverterBase extends Converter {
  /// Creates a converter for [backend] with constructor options [opts].
  new(super.backend, [super.opts]);

  /// Handlers by transform name.
  final Map<String, ConvertHandler> _handlers = <String, ConvertHandler>{};

  /// Registers [handler] for [transform].
  ///
  /// The handler receives the node and, when [convert] is called with a
  /// non-`null` options map, that map — mirroring how Ruby's `Base#convert`
  /// calls two-argument dispatch methods only when `opts` is non-nil.
  void handle(String transform, ConvertHandler handler) {
    _handlers[transform] = handler;
  }

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) {
    transform ??= node.nodeName;
    final handler = _handlers[transform];
    if (handler == null) {
      logger.warn(
        'missing convert handler for $transform node in $backend backend '
        '($runtimeType)',
      );
      return null;
    }
    return opts == null ? handler(node) : handler(node, opts);
  }

  /// Reports whether a handler is registered for [transform].
  ///
  /// Port of `Base#handles?` (`respond_to? 'convert_<transform>'`).
  @override
  bool handles(String transform) => _handlers.containsKey(transform);

  /// Converts [node] using only its converted content.
  Object? contentOnly(AbstractNode node) {
    if (node is AbstractBlock) return node.content();
    throw ArgumentError.value(node, 'node', 'must be a block with content');
  }

  /// Skips conversion of [node]. Returns `null`.
  Object? skip(AbstractNode node) => null;
}

/// Converts [node], optionally guided by conversion [opts].
///
/// Handlers registered with [ConverterBase.handle]. The optional [opts]
/// parameter mirrors Ruby dispatch methods, which declare a second
/// parameter only when they accept conversion options.
typedef ConvertHandler = Object? Function(
  AbstractNode node, [
  Map<String, Object?>? opts,
]);
