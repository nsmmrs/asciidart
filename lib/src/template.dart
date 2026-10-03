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
class TemplateRegistry {
  /// Compiled Mustache templates by transform name.
  final Map<String, MustacheTemplate> _templates = <String, MustacheTemplate>{};

  /// Dart-function overrides by transform name.
  final Map<String, ConvertHandler> _functions = <String, ConvertHandler>{};

  /// Helper lambdas by context key.
  final Map<String, TemplateHelper> _helpers = <String, TemplateHelper>{};

  /// Default `lenient` flag for templates registered on this registry.
  final bool lenient;

  /// Default `htmlEscapeValues` flag for templates registered here.
  final bool htmlEscapeValues;

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
  /// The template, function and helper registrations.
  final TemplateRegistry registry;

  /// Creates a template converter for [backend].
  ///
  /// Sources enter through [registry] (consuming the wave-B loader maps);
  /// use [register], [registerFunction] and [registerHelper] to add more.
  TemplateConverter(super.backend, [super.opts, TemplateRegistry? registry])
    : registry = registry ?? TemplateRegistry();

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
