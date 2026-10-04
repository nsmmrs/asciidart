/// Small string, number and collection helpers shared by the converter.
///
/// Several of these deliberately differ from the closest `dart:core` method
/// so that output stays byte-identical to Asciidoctor: the trimming helpers
/// only strip ASCII whitespace and NUL, the number parsers accept a leading
/// numeric prefix and ignore the rest, and the split helper drops trailing
/// empty fields.
library;

import 'dart:math' show pow;

/// Null-or-empty test for nullable strings.
extension NullableStringIsNullOrEmpty on String? {
  /// Whether this string is `null` or empty.
  bool get isNullOrEmpty {
    final self = this;
    return self == null || self.isEmpty;
  }
}

/// Null-or-empty test for nullable iterables.
extension NullableIterableIsNullOrEmpty<T> on Iterable<T>? {
  /// Whether this iterable is `null` or empty.
  bool get isNullOrEmpty {
    final self = this;
    return self == null || self.isEmpty;
  }
}

/// Null-or-empty test for nullable maps.
extension NullableMapIsNullOrEmpty<K, V> on Map<K, V>? {
  /// Whether this map is `null` or empty.
  bool get isNullOrEmpty {
    final self = this;
    return self == null || self.isEmpty;
  }
}

/// Null test for nullable numbers (a number is never empty).
extension NullableNumIsNullOrEmpty on num? {
  /// Whether this number is `null`.
  bool get isNullOrEmpty => this == null;
}

/// ASCII-only trimming for strings.
extension AsciiTrim on String {
  /// Copy of this string with trailing whitespace removed.
  ///
  /// Removes trailing spaces, tabs, newlines, vertical tabs, form feeds,
  /// carriage returns and NUL characters. Unlike [String.trimRight], this
  /// leaves non-ASCII whitespace alone and also strips NUL.
  String trimRightAscii() {
    var end = length;
    while (end > 0 && _isAsciiSpaceOrNul(codeUnitAt(end - 1))) {
      end--;
    }
    return end == length ? this : substring(0, end);
  }

  /// Copy of this string with one trailing line terminator removed: a
  /// single `\r\n`, `\n` or `\r`, if present.
  String withoutTrailingNewline() {
    if (endsWith('\r\n')) return substring(0, length - 2);
    if (endsWith('\n') || endsWith('\r')) return substring(0, length - 1);
    return this;
  }
}

/// Precision truncation for doubles. Named [truncateAtPrecision] because
/// [double.truncate] already exists.
extension DoubleTruncatePrecision on double {
  /// Truncates this value to [precision] decimal places.
  ///
  /// A positive [precision] keeps that many digits after the point
  /// (returning a [double]); a zero or negative [precision] truncates toward
  /// zero before the point (returning an [int]).
  num truncateAtPrecision(int precision) {
    if (precision == 0) return truncate();
    if (precision > 0) {
      final factor = pow(10, precision);
      return (this * factor).truncate() / factor;
    }
    final factor = pow(10, -precision);
    return (this / factor).truncate() * factor;
  }
}

/// Whether [value] counts as set: everything except `null` and `false`.
///
/// Attribute and option values are loosely typed (strings, numbers, booleans
/// or `null`), and only `null` and `false` mean "unset"; an empty string,
/// for example, is set.
bool isTruthy(Object? value) => value != null && value != false;

final RegExp _leadingInteger = RegExp(r'^\s*[+-]?\d+');
final RegExp _leadingFloat = RegExp(
  r'^\s*[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?',
);

/// Parses the leading integer of [value].
///
/// An [int] maps to itself and other numbers truncate. A string contributes
/// its leading signed integer (after leading whitespace) and ignores the
/// rest, so `'12px'` is 12 and `'px'` is 0. `null` maps to 0; any other type
/// throws a [StateError].
int parseLeadingInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value == null) return 0;
  if (value is! String) {
    throw StateError('cannot convert ${value.runtimeType} to an integer');
  }
  final match = _leadingInteger.firstMatch(value);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.trim()) ?? 0;
}

/// Parses the leading floating-point number of [value].
///
/// Numbers convert directly. A string contributes its leading decimal
/// literal (after leading whitespace) and ignores the rest; `null` maps to
/// 0.0; any other type throws a [StateError].
double parseLeadingDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  if (value is! String) {
    throw StateError('cannot convert ${value.runtimeType} to a number');
  }
  final match = _leadingFloat.firstMatch(value);
  if (match == null) return 0;
  return double.tryParse(match.group(0)!.trim()) ?? 0.0;
}

/// Splits [source] on [pattern] and drops trailing empty fields, which
/// [String.split] keeps (`'a,b,,'` gives `['a', 'b']`). See
/// `PORTING-REGEXP.md` rule B8c.
List<String> splitDropTrailingEmpty(String source, Pattern pattern) {
  final parts = source.split(pattern);
  while (parts.isNotEmpty && parts.last.isEmpty) {
    parts.removeLast();
  }
  return parts;
}

/// Removes the last character of [s]; a trailing `\r\n` pair counts as one
/// character.
String dropLastChar(String s) {
  if (s.isEmpty) return s;
  if (s.endsWith('\r\n')) return s.substring(0, s.length - 2);
  return s.substring(0, s.length - 1);
}

/// Removes [suffix] from the end of [s] when present, else returns [s]
/// unchanged.
String removeSuffix(String s, String suffix) =>
    suffix.isNotEmpty && s.endsWith(suffix)
    ? s.substring(0, s.length - suffix.length)
    : s;

/// Removes leading ASCII whitespace and NUL characters from [s] (the
/// leading counterpart of [AsciiTrim.trimRightAscii]).
String trimLeftAscii(String s) {
  var start = 0;
  while (start < s.length && _isAsciiSpaceOrNul(s.codeUnitAt(start))) {
    start++;
  }
  return start == 0 ? s : s.substring(start);
}

/// Whether [codeUnit] is NUL, tab, newline, vertical tab, form feed,
/// carriage return or space.
bool _isAsciiSpaceOrNul(int codeUnit) =>
    codeUnit == 0x20 || (codeUnit >= 0x09 && codeUnit <= 0x0D) || codeUnit == 0;

/// Collapses every run of [char] in [s] to a single occurrence.
String collapseRuns(String s, String char) {
  if (s.isEmpty) return s;
  final buf = StringBuffer()..write(s[0]);
  for (var i = 1; i < s.length; i++) {
    final c = s[i];
    if (c == char && s[i - 1] == char) continue;
    buf.write(c);
  }
  return buf.toString();
}

/// Replaces every character of [s] found in [from] with [to], collapsing
/// runs of [to] in the output. [from] is a literal set of characters (no
/// range syntax).
String transliterateSqueeze(String s, String from, String to) {
  final buf = StringBuffer();
  var previousOut = '';
  var first = true;
  for (var i = 0; i < s.length; i++) {
    final out = from.contains(s[i]) ? to : s[i];
    if (!first && out == to && previousOut == to) continue;
    first = false;
    previousOut = out;
    buf.write(out);
  }
  return buf.toString();
}

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Splits [value] on whitespace runs, ignoring leading and trailing
/// whitespace.
List<String> splitWords(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return <String>[];
  return trimmed.split(_whitespaceRun);
}

/// Renders [value] for `toString` output: `null` stays `null` and strings
/// are double-quoted with backslash escapes for `\`, `"`, newline, carriage
/// return and tab.
String debugQuote(String? value) {
  if (value == null) return 'null';
  final buf = StringBuffer('"');
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    switch (c) {
      case r'\':
        buf.write(r'\\');
      case '"':
        buf.write(r'\"');
      case '\n':
        buf.write(r'\n');
      case '\r':
        buf.write(r'\r');
      case '\t':
        buf.write(r'\t');
      default:
        buf.write(c);
    }
  }
  buf.write('"');
  return buf.toString();
}
