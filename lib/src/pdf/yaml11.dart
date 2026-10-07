/// YAML documents as Ruby's Psych reads them (YAML 1.1): plain scalars
/// resolved by YAML 1.1's rules (`yes`, `on` and `off` are booleans,
/// `012` is octal, `1,000` and `1_000` are integers, `1:20` is base 60),
/// as a typed tree of maps, lists and scalars.
library;

import 'package:asciidart/src/pdf/theme.dart';
import 'package:yaml/yaml.dart';

/// A YAML node.
sealed class Y {
  const new();
}

/// A mapping, its keys in document order.
final class YMap extends Y {
  /// A mapping of [entries].
  const new(this.entries);

  /// The entries.
  final Map<String, Y> entries;
}

/// A sequence.
final class YList extends Y {
  /// A sequence of [items].
  const new(this.items);

  /// The items.
  final List<Y> items;
}

/// A scalar, resolved to a string, number, boolean or null.
final class YScalar extends Y {
  /// The scalar [value].
  const new(this.value);

  /// The value.
  final ThemeValue value;
}

/// The document [text] as a tree (null for an empty document); throws
/// [YamlException].
Y? parseYaml11(String text, {Uri? sourceUrl}) {
  final node = loadYamlNode(text, sourceUrl: sourceUrl);
  return _convert(node);
}

Y? _convert(YamlNode node) => switch (node) {
  YamlMap(:final nodes) => YMap({
    for (final entry in nodes.entries)
      switch (entry.key) {
        final YamlScalar scalar => _scalar(scalar).rubyString,
        final other => '$other',
      }: _convert(entry.value) ?? const YScalar(ThemeNull()),
  }),
  YamlList(:final nodes) => YList([
    for (final item in nodes) _convert(item) ?? const YScalar(ThemeNull()),
  ]),
  final YamlScalar scalar => YScalar(_scalar(scalar)),
  _ => null,
};

ThemeValue _scalar(YamlScalar scalar) {
  if (scalar.style != ScalarStyle.PLAIN) {
    return ThemeString(
      scalar.value is String ? scalar.value as String : scalar.span.text,
    );
  }
  return resolvePlainScalar(scalar.span.text.trim());
}

final RegExp _null = RegExp(r'^(?:~|null|Null|NULL)?$');
final RegExp _true = RegExp(r'^(?:yes|true|on)$', caseSensitive: false);
final RegExp _false = RegExp(r'^(?:no|false|off)$', caseSensitive: false);
final RegExp _binary = RegExp(r'^[-+]?0b[0-1_,]+$');
final RegExp _octal = RegExp(r'^[-+]?0[0-7_,]+$');
final RegExp _decimal = RegExp(r'^[-+]?(?:0|[1-9][0-9_,]*)$');
final RegExp _hex = RegExp(r'^[-+]?0x[0-9a-fA-F_,]+$');
final RegExp _float = RegExp(
  r'^(?:[-+]?(?:[0-9][0-9_,]*)?\.[0-9]*(?:[eE][-+][0-9]+)?|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$',
);
final RegExp _sexagesimalInt = RegExp(r'^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+$');
final RegExp _sexagesimalFloat = RegExp(
  r'^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*$',
);

/// A plain scalar's value by YAML 1.1's rules (as Psych resolves them).
ThemeValue resolvePlainScalar(String text) {
  if (_null.hasMatch(text)) return const ThemeNull();
  if (_true.hasMatch(text)) return const ThemeBool(true);
  if (_false.hasMatch(text)) return const ThemeBool(false);
  String digits(String s) => s.replaceAll(RegExp('[_,]'), '');
  int sign(String s) => s.startsWith('-') ? -1 : 1;
  String unsigned(String s) =>
      s.startsWith('-') || s.startsWith('+') ? s.substring(1) : s;
  if (_binary.hasMatch(text)) {
    return ThemeNumber(
      sign(text) * int.parse(digits(unsigned(text)).substring(2), radix: 2),
    );
  }
  if (_hex.hasMatch(text)) {
    return ThemeNumber(
      sign(text) * int.parse(digits(unsigned(text)).substring(2), radix: 16),
    );
  }
  if (_octal.hasMatch(text)) {
    return ThemeNumber(
      sign(text) * int.parse(digits(unsigned(text)), radix: 8),
    );
  }
  if (_decimal.hasMatch(text)) return ThemeNumber(int.parse(digits(text)));
  if (_float.hasMatch(text)) {
    final value = unsigned(text).toLowerCase();
    if (value == '.inf') {
      return ThemeNumber(sign(text) * double.infinity);
    }
    if (value == '.nan') return const ThemeNumber(double.nan);
    final normalized = digits(text);
    return ThemeNumber(
      double.parse(normalized.endsWith('.') ? '${normalized}0' : normalized),
    );
  }
  if (_sexagesimalInt.hasMatch(text) || _sexagesimalFloat.hasMatch(text)) {
    var total = 0.0;
    for (final part in digits(unsigned(text)).split(':')) {
      total = total * 60 + double.parse(part);
    }
    final value = sign(text) * total;
    return _sexagesimalInt.hasMatch(text)
        ? ThemeNumber(value.toInt())
        : ThemeNumber(value);
  }
  return ThemeString(text);
}
