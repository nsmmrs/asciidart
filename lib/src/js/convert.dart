/// Conversions between JavaScript values and the typed Dart API, for the
/// npm package's bridge (see `bridge.dart`).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidoctor/src/abstract_node.dart' show SafeMode;
import 'package:asciidoctor/src/cursor.dart';
import 'package:asciidoctor/src/errors.dart';

@JS('Object.keys')
external JSArray<JSString> _keys(JSObject object);

@JS('Array.isArray')
external bool _isArray(JSAny? value);

/// The own enumerable property names of [object].
List<String> keysOf(JSObject object) => [
  for (final key in _keys(object).toDart) key.toDart,
];

/// Whether [value] is a JavaScript array.
bool isArray(JSAny? value) => _isArray(value);

/// [value] as a Dart string, when it is a JavaScript string.
String? stringOrNull(JSAny? value) =>
    value != null && value.isA<JSString>() ? (value as JSString).toDart : null;

/// [value] as a Dart boolean: `undefined`/`null` read as [orElse].
bool boolOr(JSAny? value, {required bool orElse}) {
  if (value == null) return orElse;
  if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
  return orElse;
}

/// [value] as a Dart integer, when it is a JavaScript number.
int? intOrNull(JSAny? value) => value != null && value.isA<JSNumber>()
    ? (value as JSNumber).toDartInt
    : null;

/// The property [name] of [object].
JSAny? prop(JSObject object, String name) =>
    object.getProperty<JSAny?>(name.toJS);

/// The string items of the JavaScript array [value].
List<String> stringList(JSAny? value) {
  if (value == null || !isArray(value)) return const [];
  return [
    for (final item in (value as JSArray<JSAny?>).toDart) ?stringOrNull(item),
  ];
}

/// A JavaScript array of the strings in [values].
JSArray<JSString> jsStrings(Iterable<String> values) =>
    [for (final value in values) value.toJS].toJS;

/// A JavaScript object with the entries of [map].
JSObject jsStringMap(Map<String, String> map) {
  final object = JSObject();
  map.forEach((key, value) => object.setProperty(key.toJS, value.toJS));
  return object;
}

/// A JavaScript object for [cursor] (`file`, `dir`, `path`, `lineno`), or
/// `null`.
JSObject? jsCursor(Cursor? cursor) {
  if (cursor == null) return null;
  return JSObject()
    ..setProperty('file'.toJS, cursor.file?.toJS)
    ..setProperty('dir'.toJS, cursor.dir?.toJS)
    ..setProperty('path'.toJS, cursor.path?.toJS)
    ..setProperty('lineno'.toJS, cursor.lineno.toJS);
}

/// The safe mode named or numbered by [value] (`'secure'`, `20`, ...).
int safeModeOf(JSAny? value, {int orElse = SafeMode.secure}) {
  if (value == null) return orElse;
  if (value.isA<JSNumber>()) return (value as JSNumber).toDartInt;
  final name = stringOrNull(value)?.toLowerCase();
  return switch (name) {
    'unsafe' => SafeMode.unsafe,
    'safe' => SafeMode.safe,
    'server' => SafeMode.server,
    'secure' => SafeMode.secure,
    null => orElse,
    _ => throw AsciidoctorException('unknown safe mode: $name'),
  };
}

/// Attribute overrides from the `attributes` option: an object, a
/// space-separated string, or an array of `name=value` strings.
///
/// As in Asciidoctor.js, `null` and `undefined` values unset an attribute,
/// `false` unsets it softly, `true` sets it to the empty string, and
/// numbers are formatted as strings.
Map<String, String?> attributeOverrides(JSAny? value) {
  if (value == null) return const {};
  if (value.isA<JSString>()) {
    return _entries((value as JSString).toDart.split(RegExp(r'(?<!\\)\s+')));
  }
  if (isArray(value)) return _entries(stringList(value));
  final object = value as JSObject;
  final overrides = <String, String?>{};
  for (final key in keysOf(object)) {
    final item = prop(object, key);
    if (item == null) {
      overrides[key] = null;
    } else if (item.isA<JSBoolean>()) {
      if ((item as JSBoolean).toDart) {
        overrides[key] = '';
      } else {
        overrides['$key!'] = '@';
      }
    } else if (item.isA<JSString>()) {
      overrides[key] = (item as JSString).toDart;
    } else if (item.isA<JSNumber>()) {
      final number = (item as JSNumber).toDartDouble;
      overrides[key] = number == number.truncateToDouble()
          ? '${number.toInt()}'
          : '$number';
    } else {
      overrides[key] = '$item';
    }
  }
  return overrides;
}

Map<String, String?> _entries(Iterable<String> entries) => {
  for (final entry in entries)
    if (entry.isNotEmpty)
      entry.split('=').first.replaceAll(r'\ ', ' '): entry.contains('=')
          ? entry.substring(entry.indexOf('=') + 1).replaceAll(r'\ ', ' ')
          : '',
};
