part of 'api.dart';

/// The attributes of a node or document: names to string values.
///
/// An attribute set without a value (`:toc:`) has the empty string as its
/// value. The typed getters read common value shapes.
final class Attributes {
  new _(this._map);

  final Map<String, String> _map;

  /// The value of [name], or `null` when it is not set.
  String? operator [](String name) => _map[name];

  /// Sets [name] to [value].
  void operator []=(String name, String value) => _map[name] = value;

  /// Unsets [name], returning its previous value.
  String? remove(String name) => _map.remove(name);

  /// Whether [name] is set (with any value, including the empty string).
  bool has(String name) => _map.containsKey(name);

  /// The value of [name] as an integer, or `null` when it is not set or not
  /// an integer.
  int? intValue(String name) {
    final value = _map[name];
    return value == null ? null : int.tryParse(value.trim());
  }

  /// The value of [name] split at commas, each item trimmed, empty items
  /// dropped (`'a, b,c'` becomes `['a', 'b', 'c']`); empty when not set.
  List<String> listValue(String name) => [
    for (final item in (_map[name] ?? '').split(','))
      if (item.trim().isNotEmpty) item.trim(),
  ];

  /// The names of the set attributes.
  Iterable<String> get names => _map.keys;

  /// The attributes as an unmodifiable map.
  Map<String, String> toMap() => Map.unmodifiable(_map);

  @override
  String toString() => _map.toString();
}
