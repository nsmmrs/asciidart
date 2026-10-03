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
