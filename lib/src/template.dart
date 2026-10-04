/// Template converter: per-transform Mustache and Dart-function overrides.
///
/// Port of `lib/asciidoctor/converter/template.rb` (ADR-0002). Ruby renders
/// user templates through Tilt (ERB/Haml/Slim, ...); Dart has no runtime code
/// evaluation, so the port ships the two-path story from ADR-0002 T1:
///
/// - **(a) Code-first overrides (primary):** Dart functions registered per
///   transform name with [TemplateConverter.registerFunction] (or
///   [TemplateRegistry.registerFunction]). No files, no IO, works on all
///   platforms.
/// - **(b) Mustache templates (secondary):** `{{name}}.mustache` sources
///   registered per transform name with [TemplateConverter.register] (or
///   [TemplateRegistry.registerTemplate]), rendered by [MustacheTemplate]
///   against the pre-flattened context from `template_context.dart`.
///
/// ## Loader seam (shared with wave B)
///
/// Template *sources* always enter the registry as a `Map<String, String>`
/// (node name to Mustache source); loaders implement [TemplateLoader] and
/// apply last-wins resolution themselves. Wave B provides the `dart:io`
/// directory scanner, the Node-`fs` loader and the in-memory loader behind
/// this one-method interface; this wave only consumes the map.
///
/// ## Composition
///
/// [TemplateConverter.handles] reports exactly the registered transforms, so
/// chaining it ahead of a built-in converter in a [CompositeConverter]
/// (see [TemplateConverter.withFallback]) reproduces Ruby's
/// `Factory.create` semantics: template overrides win per transform, the
/// built-in converter handles everything else.
library;

import 'dart:async' show FutureOr;

import 'package:mustache_template/mustache_template.dart' show Template;

import 'abstract_node.dart';
import 'composite.dart';
import 'converter.dart';
import 'template_context.dart';

/// Loads template sources as a node-name to Mustache-source map.
///
/// Seam contract shared with the wave-B worker: loaders (directory scanner,
/// Node-`fs` interop, in-memory map) produce `Map<String, String>` with
/// last-wins resolution already applied; the [TemplateRegistry] consumes the
/// map. Kept to this one method so both branches merge cleanly.
abstract interface class TemplateLoader {
  /// Loads and returns the template sources.
  FutureOr<Map<String, String>> load();
}

/// One compiled Mustache template (ADR-0002 T1(b)).
///
/// Compiled once at registration with [htmlEscapeValues] defaulting to
/// `false` (raw by default per ADR-0002 T3: converter output is already-safe
/// HTML, and Mustache-default escaping would double-escape every
/// `{{content}}`) and [lenient] defaulting to `true` (missing keys render as
/// empty output, mirroring Ruby's `nil`-to-empty rendering, instead of
/// throwing).
class MustacheTemplate {
  /// Compiles [source] for transform [name].
  MustacheTemplate(
    this.name,
    this.source, {
    this.lenient = true,
    this.htmlEscapeValues = false,
  }) : _template = Template(
         source,
         name: name,
         lenient: lenient,
         htmlEscapeValues: htmlEscapeValues,
       );

  /// The transform name this template is registered under.
  final String name;

  /// The Mustache source this template was compiled from.
  final String source;

  /// Whether missing keys render as empty output instead of throwing.
  final bool lenient;

  /// Whether `{{var}}` interpolations are HTML-escaped.
  final bool htmlEscapeValues;

  /// The compiled template.
  final Template _template;

  /// Renders this template against [values] (see [buildTemplateContext]).
  String render(Map<String, Object?> values) => _template.renderString(values);
}

/// Registry of per-transform template overrides.
///
/// Holds compiled Mustache templates (path (b)), Dart functions (path (a))
/// and helper lambdas (ADR-0002 T4, injected into the render context).
/// Re-registering a name replaces the previous entry (last-wins); when both
/// a function and a Mustache template are registered for one transform, the
/// function wins (code-first path (a) overrides file path (b)).
///
/// The process-wide [TemplateRegistry.global] carries the compiled-in
/// path-(a) overrides of an XMonad-style custom binary (ADR-0002 T6): the
/// converter factory merges them into every template chain it builds, so a
/// `main.dart` that registers functions and then calls `runCli` needs no
/// `-T` directory for its overrides to engage.
class TemplateRegistry {
  /// Creates a registry, optionally seeded with [templates], [functions]
  /// and [helpers].
  TemplateRegistry({
    Map<String, String> templates = const <String, String>{},
    Map<String, ConvertHandler> functions = const <String, ConvertHandler>{},
    Map<String, TemplateHelper> helpers = const <String, TemplateHelper>{},
    this.lenient = true,
    this.htmlEscapeValues = false,
  }) {
    templates.forEach(registerTemplate);
    functions.forEach(registerFunction);
    helpers.forEach(registerHelper);
  }

  /// Compiled Mustache templates by transform name.
  final Map<String, MustacheTemplate> _templates = <String, MustacheTemplate>{};

  /// Dart-function overrides by transform name.
  final Map<String, ConvertHandler> _functions = <String, ConvertHandler>{};

  /// Helper lambdas by context key.
  final Map<String, TemplateHelper> _helpers = <String, TemplateHelper>{};

  /// Process-wide registry for compiled-in path-(a) overrides (ADR-0002
  /// T6).
  ///
  /// A custom binary registers its Dart functions (and helpers) here
  /// before converting; the converter factory merges them into every
  /// template chain (see [buildTemplateChain]) and engages a template
  /// chain even without `template_dirs` while any are registered. Starts
  /// empty, so programs that never touch it behave exactly as before.
  static final TemplateRegistry global = TemplateRegistry();

  /// Whether [global] holds any registration (function, template or
  /// helper), i.e. whether a template chain engages without
  /// `template_dirs`.
  static bool get globalHasOverrides =>
      global._functions.isNotEmpty ||
      global._templates.isNotEmpty ||
      global._helpers.isNotEmpty;

  /// Clears every registration on [global].
  ///
  /// Intended for tests (which must not leak registrations into each
  /// other) and for binaries that re-initialize their transforms.
  static void resetGlobal() {
    global._templates.clear();
    global._functions.clear();
    global._helpers.clear();
  }

  /// Default `lenient` flag for templates registered on this registry.
  final bool lenient;

  /// Default `htmlEscapeValues` flag for templates registered here.
  final bool htmlEscapeValues;

  /// Registers (compiling) Mustache [source] for transform [name].
  ///
  /// Replaces any template previously registered for [name].
  void registerTemplate(String name, String source) {
    _templates[name] = MustacheTemplate(
      name,
      source,
      lenient: lenient,
      htmlEscapeValues: htmlEscapeValues,
    );
  }

  /// Registers Dart function [fn] for transform [name] (path (a)).
  ///
  /// Replaces any function previously registered for [name]. The function
  /// follows [ConvertHandler]: it receives the node and, when `convert` is
  /// called with a non-`null` options map, that map.
  void registerFunction(String name, ConvertHandler fn) {
    _functions[name] = fn;
  }

  /// Registers helper [helper] under context key [name] (ADR-0002 T4).
  ///
  /// The helper is evaluated against the converted node on every Mustache
  /// render and injected into the context; it is the Dart replacement for
  /// Ruby's loadable `helpers.rb` (no helper file loading exists).
  void registerHelper(String name, TemplateHelper helper) {
    _helpers[name] = helper;
  }

  /// Whether a function or template is registered for [name].
  bool handles(String name) =>
      _functions.containsKey(name) || _templates.containsKey(name);

  /// The function registered for [name], if any.
  ConvertHandler? lookupFunction(String name) => _functions[name];

  /// The compiled template registered for [name], if any.
  MustacheTemplate? lookupTemplate(String name) => _templates[name];

  /// A copy of the registered Mustache sources by transform name.
  ///
  /// Mirrors Ruby's `TemplateConverter#templates` (which returns Tilt
  /// objects; the port returns their sources).
  Map<String, String> get templates => <String, String>{
    for (final entry in _templates.entries) entry.key: entry.value.source,
  };

  /// A copy of the registered functions by transform name.
  Map<String, ConvertHandler> get functions =>
      Map<String, ConvertHandler>.of(_functions);

  /// A copy of the registered helpers by context key.
  Map<String, TemplateHelper> get helpers =>
      Map<String, TemplateHelper>.of(_helpers);

  /// Copies every registration from [other] into this registry.
  ///
  /// Last-wins per name: [other]'s entries replace same-named ones. Used
  /// by [buildTemplateChain] to merge [TemplateRegistry.global] over the
  /// scanned file templates (explicit in-process registrations beat
  /// files).
  void absorb(TemplateRegistry other) {
    _templates.addAll(other._templates);
    _functions.addAll(other._functions);
    _helpers.addAll(other._helpers);
  }

  /// Whether this registry holds no registration at all.
  bool get isEmpty =>
      _templates.isEmpty && _functions.isEmpty && _helpers.isEmpty;
}

/// Converts nodes through registered Mustache templates and Dart functions.
///
/// Port of `Converter::TemplateConverter`. [convert] derives the transform
/// from the node name (unless given), runs the registered function when one
/// exists, else renders the registered Mustache template against
/// [buildTemplateContext], else throws a [StateError] mirroring Ruby's
/// `Could not find a custom template to handle transform: ...`.
///
/// Mustache output is trimmed like Ruby (`strip` for `document`,
/// `rstrip` otherwise); function results pass through unmodified, exactly
/// like [ConverterBase] handler results.
class TemplateConverter extends ConverterBase {
  /// Creates a template converter for [backend].
  ///
  /// Sources enter through [registry] (consuming the wave-B loader maps);
  /// use [register], [registerFunction] and [registerHelper] to add more.
  TemplateConverter(super.backend, [super.opts, TemplateRegistry? registry])
    : registry = registry ?? TemplateRegistry();

  /// The template, function and helper registrations.
  final TemplateRegistry registry;

  /// Registers Mustache [source] for transform [name] (path (b)).
  ///
  /// Mirrors Ruby's `TemplateConverter#register` (which takes a Tilt
  /// template object; the port compiles the source instead).
  void register(String name, String source) {
    registry.registerTemplate(name, source);
  }

  /// Registers Dart function [fn] for transform [name] (path (a)).
  void registerFunction(String name, ConvertHandler fn) {
    registry.registerFunction(name, fn);
  }

  /// Registers helper [helper] under context key [name] (ADR-0002 T4).
  void registerHelper(String name, TemplateHelper helper) {
    registry.registerHelper(name, helper);
  }

  /// A copy of the registered Mustache sources by transform name.
  Map<String, String> get templates => registry.templates;

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) {
    transform ??= node.nodeName;
    final fn = registry.lookupFunction(transform);
    if (fn != null) return opts == null ? fn(node) : fn(node, opts);
    final template = registry.lookupTemplate(transform);
    if (template == null) {
      throw StateError(
        'Could not find a custom template to handle transform: $transform',
      );
    }
    final context = buildTemplateContext(
      node,
      helpers: registry.helpers,
      opts: opts,
    );
    final rendered = template.render(context);
    return transform == 'document' ? rendered.trim() : rendered.trimRight();
  }

  /// Whether a function or template is registered for [transform].
  ///
  /// Port of `TemplateConverter#handles?`; lets a [CompositeConverter] fall
  /// back to the built-in converter for missing transforms.
  @override
  bool handles(String transform) => registry.handles(transform);

  /// Chains this converter ahead of [fallback] in a [CompositeConverter].
  ///
  /// Mirrors the Ruby `Factory.create` template chain: template overrides
  /// win per transform, [fallback] (typically the built-in converter)
  /// handles the rest, and the composite adopts [fallback]'s backend traits.
  CompositeConverter withFallback(Converter fallback) => CompositeConverter(
    backend,
    [this, fallback],
    backendTraitsSource: fallback,
  );
}

/// Builds the template side of a converter-factory `create` call.
///
/// Port of the `TemplateConverter.new backend, template_dirs, opts` half
/// of Ruby's `Factory.create`: compiles [sources] (the loader's
/// node-name-to-Mustache-source map) into a fresh registry, merges
/// [TemplateRegistry.global] over them (explicit in-process registrations
/// beat files; functions beat templates per transform as usual), and
/// chains the resulting [TemplateConverter] ahead of [fallback] (or
/// returns it bare when [fallback] is `null`, the unknown-backend case).
/// [opts] become the template converter's constructor options.
Converter buildTemplateChain(
  String backend,
  Map<String, Object?> opts,
  Converter? fallback, {
  required Map<String, String> sources,
}) {
  final registry = TemplateRegistry(templates: sources)
    ..absorb(TemplateRegistry.global);
  final template = TemplateConverter(backend, opts, registry);
  return fallback == null ? template : template.withFallback(fallback);
}
