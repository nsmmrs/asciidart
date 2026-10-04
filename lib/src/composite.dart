/// Composite converter: delegates conversion to a chain of converters.
///
/// Port of `lib/asciidoctor/converter/composite.rb`.
library;

import 'abstract_node.dart';
import 'converter.dart';

/// Implemented by converters that want a back-reference when composed.
///
/// Port of the duck-typed `composed` callback: the [CompositeConverter]
/// invokes [composed] on every delegate that implements this interface
/// (in Ruby, `TemplateConverter` does).
abstract interface class ComposedAware {
  /// Receives the [composite] this converter was composed into.
  void composed(CompositeConverter composite);
}

/// Delegates to the first chained converter that handles each transform.
///
/// Port of `Converter::CompositeConverter`. [converters] holds the chain;
/// [converterFor] selects (and caches) the first converter whose [handles]
/// accepts the transform, and [findConverter] raises a [StateError] when
/// none does (port of Ruby's `raise` with the same message).
///
/// Note that a composite [handles] no transform itself (it registers no
/// handlers), exactly as in Ruby, where `CompositeConverter` defines no
/// `convert_*` methods.
class CompositeConverter extends ConverterBase {
  /// Creates a composite for [backend] delegating to [converters].
  ///
  /// Delegates implementing [ComposedAware] are notified. When
  /// [backendTraitsSource] is given, this composite adopts its backend
  /// traits map (shared by reference, as in Ruby).
  CompositeConverter(
    super.backend,
    List<Converter> converters, {
    Converter? backendTraitsSource,
  }) : converters = List.of(converters) {
    for (final delegate in this.converters) {
      // NOTE `is` alone does not promote: ComposedAware is unrelated to
      // Converter in the type hierarchy, so the call needs an `as` cast.
      if (delegate is ComposedAware) {
        (delegate as ComposedAware).composed(this);
      }
    }
    if (backendTraitsSource != null) {
      initBackendTraits(backendTraitsSource.backendTraits());
    }
  }

  /// The chained converters, in delegation order.
  final List<Converter> converters;

  /// Converters selected per transform (see [converterFor]).
  final Map<String, Converter> _converterCache = <String, Converter>{};

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) {
    transform ??= node.nodeName;
    return converterFor(transform).convert(node, transform, opts);
  }

  /// Returns the cached converter for [transform], selecting it first.
  Converter converterFor(String transform) =>
      _converterCache.putIfAbsent(transform, () => findConverter(transform));

  /// Returns the first chained converter that handles [transform].
  ///
  /// Throws a [StateError] when no chained converter handles it.
  Converter findConverter(String transform) {
    for (final candidate in converters) {
      if (candidate.handles(transform)) return candidate;
    }
    throw StateError(
      'Could not find a converter to handle transform: $transform',
    );
  }
}
