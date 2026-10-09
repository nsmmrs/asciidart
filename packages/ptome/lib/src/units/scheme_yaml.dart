/// Scheme files as a typed tree: maps, lists and scalars, read from YAML.
library;

import 'package:ptome/src/units/files.dart' as p;
import 'package:yaml/yaml.dart';

/// A node of a scheme file.
sealed class SchemeNode {
  const new();

  /// A scalar's text (`true` for a true flag, `20` for a number), or `null`
  /// for a map, a list or a null.
  String? get text => null;
}

/// A mapping, its keys in file order.
final class SchemeMap extends SchemeNode {
  /// A mapping of [entries].
  const new(this.entries);

  /// The entries.
  final Map<String, SchemeNode> entries;

  /// The text under [key], if it is a string.
  String? string(String key) => switch (entries[key]) {
    SchemeText(:final value) => value,
    _ => null,
  };

  /// The flag under [key], if it is a boolean.
  bool? flag(String key) => switch (entries[key]) {
    SchemeFlag(:final value) => value,
    _ => null,
  };

  /// The number under [key], as an integer, if it is a number.
  int? integer(String key) => switch (entries[key]) {
    SchemeNumber(:final value) => value.toInt(),
    _ => null,
  };

  /// The map under [key], if it is one.
  SchemeMap? map(String key) => switch (entries[key]) {
    final SchemeMap m => m,
    _ => null,
  };

  /// The list under [key], or an empty list.
  List<SchemeNode> list(String key) => switch (entries[key]) {
    SchemeList(:final items) => items,
    _ => const [],
  };

  /// The strings under [key] (a list of them), or an empty list.
  List<String> strings(String key) => [
    for (final item in list(key))
      if (item case SchemeText(:final value)) value,
  ];

  /// The maps under this one's keys, by key (`stream:` → each stream).
  Iterable<(String, SchemeMap)> get maps sync* {
    for (final MapEntry(:key, :value) in entries.entries) {
      if (value is SchemeMap) yield (key, value);
    }
  }

  /// The string-valued entries: a level's or a stream's templates.
  Map<String, String> get templates => {
    for (final MapEntry(:key, :value) in entries.entries)
      if (value case SchemeText(value: final text)) key: text,
  };

  /// This map with [other]'s entries added over its own.
  SchemeMap merged(SchemeMap? other) =>
      other == null ? this : SchemeMap({...entries, ...other.entries});
}

/// A sequence.
final class SchemeList extends SchemeNode {
  /// A sequence of [items].
  const new(this.items);

  /// The items.
  final List<SchemeNode> items;
}

/// A string.
final class SchemeText extends SchemeNode {
  /// The string [value].
  const new(this.value);

  /// The string.
  final String value;

  @override
  String get text => value;
}

/// A number.
final class SchemeNumber extends SchemeNode {
  /// The number [value].
  const new(this.value);

  /// The number.
  final num value;

  @override
  String get text => '$value';
}

/// A boolean.
final class SchemeFlag extends SchemeNode {
  /// The flag [value].
  const new({required this.value});

  /// Whether it is set.
  final bool value;

  @override
  String get text => '$value';
}

/// A null (`~`, or a key with nothing after it).
final class SchemeNull extends SchemeNode {
  /// The null node.
  const new();
}

/// The scheme file at [path], which must be a mapping.
SchemeMap readSchemeFile(String path) {
  final node = loadYamlNode(p.readText(path), sourceUrl: Uri.file(path));
  if (_convert(node) case final SchemeMap map) return map;
  throw FormatException('$path: a scheme file is a mapping');
}

SchemeNode _convert(YamlNode node) => switch (node) {
  YamlMap(:final nodes) => SchemeMap({
    for (final MapEntry(:key, :value) in nodes.entries)
      '${key is YamlScalar ? key.value : key}': _convert(value),
  }),
  YamlList(:final nodes) => SchemeList([for (final n in nodes) _convert(n)]),
  YamlScalar(:final value) => switch (value) {
    final String s => SchemeText(s),
    final num n => SchemeNumber(n),
    final bool b => SchemeFlag(value: b),
    null => const SchemeNull(),
    _ => SchemeText('$value'),
  },
  _ => const SchemeNull(),
};
