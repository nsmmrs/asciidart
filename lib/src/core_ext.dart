/// Core library extensions for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/core_ext/nil_or_empty.rb`,
/// `lib/asciidoctor/core_ext/float/truncate.rb`,
/// `lib/asciidoctor/core_ext/hash/merge.rb`,
/// `lib/asciidoctor/core_ext/match_data/names.rb` and
/// `lib/asciidoctor/core_ext/regexp/is_match.rb`.
///
/// In Ruby these files monkey-patch core classes. In Dart they are expressed
/// as extension methods, which is the idiomatic equivalent.
///
/// This file additionally carries [RubyString], a small set of `String`
/// helpers that mirror the Ruby core methods (`rstrip`, `chomp`) the ported
/// modules rely on. They live here (rather than on `Helpers`) so every
/// future ported module can use them with the same call-site shape as Ruby.
library;

import 'dart:math' show pow;

/// `nil_or_empty?` for nullable strings.
///
/// Mirrors `String#nil_or_empty?` (aliased to `empty?`) combined with
/// `NilClass#nil_or_empty?` (aliased to `nil?`).
extension NullableStringIsNilOrEmpty on String? {
  /// Whether this string is `null` or empty.
  bool get isNilOrEmpty {
    final self = this;
    return self == null || self.isEmpty;
  }
}

/// `nil_or_empty?` for nullable iterables.
///
/// Mirrors `Array#nil_or_empty?` (aliased to `empty?`) combined with
/// `NilClass#nil_or_empty?`.
extension NullableIterableIsNilOrEmpty<T> on Iterable<T>? {
  /// Whether this iterable is `null` or empty.
  bool get isNilOrEmpty {
    final self = this;
    return self == null || self.isEmpty;
  }
}

/// `nil_or_empty?` for nullable maps.
///
/// Mirrors `Hash#nil_or_empty?` (aliased to `empty?`) combined with
/// `NilClass#nil_or_empty?`.
extension NullableMapIsNilOrEmpty<K, V> on Map<K, V>? {
  /// Whether this map is `null` or empty.
  bool get isNilOrEmpty {
    final self = this;
    return self == null || self.isEmpty;
  }
}

/// `nil_or_empty?` for nullable numbers.
///
/// Mirrors `Numeric#nil_or_empty?` (aliased to `nil?`, hence always `false`
/// for a number) combined with `NilClass#nil_or_empty?` (`true` for `null`).
extension NullableNumIsNilOrEmpty on num? {
  /// Whether this number is `null` (a number itself is never "empty").
  bool get isNilOrEmpty => this == null;
}

/// Ruby `String` core methods used across the port.
extension RubyString on String {
  static final RegExp _trailingWhitespace = RegExp(r'[ \t\n\x0B\x0C\r\x00]+$');

  /// Copy of this string with trailing whitespace removed.
  ///
  /// Mirrors Ruby's `String#rstrip`: removes trailing spaces, tabs,
  /// newlines, vertical tabs, form feeds, carriage returns and null bytes.
  /// Unlike [String.trimRight], this is ASCII-only and strips `\x00`.
  String rstrip() => replaceAll(_trailingWhitespace, '');

  /// Copy of this string with one trailing record separator removed.
  ///
  /// Mirrors Ruby's `String#chomp` with the default separator: removes a
  /// single trailing `\r\n`, `\n` or `\r`, if present.
  String chomp() {
    if (endsWith('\r\n')) return substring(0, length - 2);
    if (endsWith('\n') || endsWith('\r')) return substring(0, length - 1);
    return this;
  }
}

/// Precision truncation for doubles.
///
/// Dart port of the `Float#truncate` precision support backfilled by
/// `core_ext/float/truncate.rb` (native since Ruby 2.4). Named
/// [truncateAtPrecision] because [double.truncate] already exists.
extension DoubleTruncatePrecision on double {
  /// Truncates this value to [precision] decimal places.
  ///
  /// Mirrors Ruby's `Float#truncate`: a positive [precision] keeps that many
  /// digits after the point (returning a [double]); a zero or negative
  /// [precision] truncates toward zero before the point (returning an [int]).
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

/// Non-mutating map merges.
///
/// Dart port of the multi-argument `Hash#merge` backfilled by
/// `core_ext/hash/merge.rb` (native since Ruby 2.6). Unlike [Map.addAll],
/// these return a new map and leave the receiver untouched.
extension MergeMaps<K, V> on Map<K, V> {
  /// Copy of this map with the entries of [other] merged in.
  ///
  /// With no argument (or a `null` one), returns a copy of this map.
  Map<K, V> merge([Map<K, V>? other]) =>
      other == null ? Map<K, V>.of(this) : {...this, ...other};

  /// Copy of this map with every map in [others] merged in, in order.
  ///
  /// Later maps win on key conflicts, as with Ruby's multi-argument merge.
  Map<K, V> mergeAll(Iterable<Map<K, V>> others) {
    var result = Map<K, V>.of(this);
    for (final other in others) {
      result = {...result, ...other};
    }
    return result;
  }
}

/// Named-capture introspection for regex matches.
///
/// Dart port of the `MatchData#names` backfill in
/// `core_ext/match_data/names.rb` (an Opal-compat shim upstream). Dart's
/// [RegExpMatch.groupNames] already provides this; the extension keeps the
/// ported call-site shape.
extension MatchNames on RegExpMatch {
  /// Names of the named capture groups in the matched pattern.
  List<String> get names => groupNames.toList();
}

/// Predicate alias for regex matching.
///
/// Dart port of the `Regexp#match?` backfill in
/// `core_ext/regexp/is_match.rb` (native since Ruby 2.4).
extension RegexIsMatch on RegExp {
  /// Whether this pattern matches anywhere in [input].
  bool isMatch(String input) => hasMatch(input);
}

/// Whether [value] is truthy in the Ruby sense (`null` and `false` are the
/// only falsy values).
///
/// Shared shim for the ported modules; every Ruby truthiness test
/// (`if x`, `x || y`, `x && y`) maps onto this helper.
bool isTruthy(Object? value) => value != null && value != false;

final RegExp _leadingInteger = RegExp(r'^\s*[+-]?\d+');
final RegExp _leadingFloat = RegExp(
  r'^\s*[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?',
);

/// Parses [value] the way Ruby's `to_i` does: an [int] maps to itself, other
/// numbers truncate, strings contribute their leading signed integer
/// (after leading whitespace), and anything else yields `0`.
///
/// Note: `null` maps to `0` (as `nil.to_i` does); a [bool] throws, mirroring
/// Ruby's `NoMethodError` for `true.to_i`.
int rubyToInteger(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value == null) return 0;
  if (value is! String) {
    throw StateError(
      'no implicit conversion of ${value.runtimeType} into '
      'Integer (mirrors Ruby NoMethodError)',
    );
  }
  final match = _leadingInteger.firstMatch(value);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.trim()) ?? 0;
}

/// Parses [value] the way Ruby's `to_f` does: numbers convert, strings
/// contribute their leading float literal, and anything else yields `0.0`.
double rubyToDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  if (value is! String) {
    throw StateError(
      'no implicit conversion of ${value.runtimeType} into '
      'Float (mirrors Ruby NoMethodError)',
    );
  }
  final match = _leadingFloat.firstMatch(value);
  if (match == null) return 0;
  return double.tryParse(match.group(0)!.trim()) ?? 0.0;
}

/// Splits [source] on [pattern] the way Ruby's limit-less `String#split`
/// does: trailing empty fields are dropped (Dart's [String.split] keeps
/// them). See `PORTING-REGEXP.md` rule B8c.
List<String> rubySplit(String source, Pattern pattern) {
  final parts = source.split(pattern);
  while (parts.isNotEmpty && parts.last.isEmpty) {
    parts.removeLast();
  }
  return parts;
}

/// Removes the last character of [s]; a trailing CRLF pair counts as one
/// character. Port of Ruby's `String#chop`.
String chopLast(String s) {
  if (s.isEmpty) return s;
  if (s.endsWith('\r\n')) return s.substring(0, s.length - 2);
  return s.substring(0, s.length - 1);
}

/// Removes [suffix] from the end of [s] when present, else returns [s]
/// unchanged. Port of Ruby's `String#chomp` with an explicit argument.
String chompSuffix(String s, String suffix) =>
    suffix.isNotEmpty && s.endsWith(suffix)
    ? s.substring(0, s.length - suffix.length)
    : s;

final RegExp _leadingSpace = RegExp(r'^[\x00 \t\n\x0b\f\r]+');

/// Removes leading ASCII whitespace (and NUL bytes) from [s].
/// Port of Ruby's `String#lstrip`.
String lstrip(String s) => s.replaceFirst(_leadingSpace, '');

/// Collapses every run of [char] in [s] to a single occurrence.
/// Port of Ruby's `String#squeeze` with a single-character argument.
String squeezeChar(String s, String char) {
  if (s.isEmpty) return s;
  final buf = StringBuffer()..write(s[0]);
  for (var i = 1; i < s.length; i++) {
    final c = s[i];
    if (c == char && s[i - 1] == char) continue;
    buf.write(c);
  }
  return buf.toString();
}

/// Transliterates every character of [s] found in [from] to [to], squeezing
/// runs of [to] in the output. Port of Ruby's `String#tr_s` for the
/// single-character replacement case (the only one used here); [from] is
/// treated as a literal character set (verified: the call sites never rely
/// on `tr` range syntax).
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

/// Splits [value] on whitespace runs, ignoring leading and trailing runs.
/// Port of Ruby's bare `String#split`.
List<String> splitWords(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return <String>[];
  return trimmed.split(_whitespaceRun);
}

/// Renders [value] for node `toString` output: `null` becomes `nil` and
/// strings are double-quoted with minimal escaping, mirroring Ruby's
/// `String#inspect`/`nil.inspect` for the values used here.
String inspectString(String? value) {
  if (value == null) return 'nil';
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
