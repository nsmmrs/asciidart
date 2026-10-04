/// Internal helper functions for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/helpers.rb`.
library;

import 'dart:io' show Directory, Platform, stderr;

import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/rx.dart';

/// Internal helper functions. Except where noted, everything here is internal.
abstract final class Helpers {
  /// Loads the library [name], handling failure per [onFailure].
  ///
  /// Dart cannot load libraries at runtime, so this always takes the failure
  /// path. When [onFailure] is `'abort'` (the default) it throws a
  /// [StateError] carrying the same message Ruby's `LoadError` would; when
  /// `'warn'` it reports the message and returns `null`; otherwise it
  /// silently returns `null`.
  ///
  /// [gemName] mirrors Ruby's argument: `true` (the default) uses [name],
  /// a [String] names the gem explicitly, and `false` or `null` produces the
  /// generic "cannot load such file" message.
  static bool? requireLibrary(
    String name, [
    Object? gemName = true,
    String onFailure = 'abort',
  ]) {
    if (gemName == null || gemName == false) {
      if (onFailure == 'abort') {
        throw StateError(
          'asciidoctor: FAILED: cannot load such file -- $name. '
          'Processing aborted.',
        );
      }
      if (onFailure == 'warn') {
        stderr.writeln(
          'cannot load such file -- $name. Functionality disabled.',
        );
      }
      return null;
    }
    final gem = gemName == true ? name : gemName as String;
    if (onFailure == 'abort') {
      throw StateError(
        "asciidoctor: FAILED: required gem '$gem' is not available. "
        'Processing aborted.',
      );
    }
    if (onFailure == 'warn') {
      stderr.writeln(
        "optional gem '$gem' is not available. Functionality disabled.",
      );
    }
    return null;
  }

  /// Ensures URI-reading support is available, optionally with a [cache].
  ///
  /// Dart reads URIs through `dart:io` with no setup, so this is a no-op
  /// unless [cache] is requested, in which case it takes the same failure
  /// path as [requireLibrary] for the (unavailable) URI cache library.
  static void requireOpenUri([bool cache = false]) {
    if (cache) requireLibrary('open-uri/cached', 'open-uri-cached');
  }

  /// Prepares source [data] lines for parsing.
  ///
  /// Strips a leading byte-order mark and, per line, removes trailing
  /// whitespace when [trimEnd] is set (the default) or a single trailing
  /// record separator otherwise. Unlike Ruby, the input list is not mutated;
  /// encoding conversion is unnecessary because Dart strings are Unicode.
  static List<String> prepareSourceArray(
    List<String> data, [
    bool trimEnd = true,
  ]) {
    if (data.isEmpty) return [];
    final lines = data[0].startsWith('\uFEFF')
        ? [data[0].substring(1), ...data.skip(1)]
        : data;
    return [for (final line in lines) trimEnd ? line.rstrip() : line.chomp()];
  }

  /// Prepares source [data] text for parsing.
  ///
  /// Strips a leading byte-order mark, splits the text into lines on `\n`
  /// (as Ruby's `each_line` does) and trims each line per [trimEnd] (see
  /// [prepareSourceArray]). A `null` or empty input yields an empty list.
  static List<String> prepareSourceString(String? data, [bool trimEnd = true]) {
    if (data.isNilOrEmpty) return [];
    var text = data!;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = <String>[];
    var start = 0;
    var end = text.indexOf('\n', start);
    while (end != -1) {
      lines.add(text.substring(start, end + 1));
      start = end + 1;
      end = text.indexOf('\n', start);
    }
    if (start < text.length) lines.add(text.substring(start));
    return [for (final line in lines) trimEnd ? line.rstrip() : line.chomp()];
  }

  /// Whether [str] resembles a URI (i.e. starts with a URI prefix).
  ///
  /// No validation of the URI is performed. (The JRuby-only `classloader`
  /// exclusion has no Dart equivalent.)
  static bool isUriish(String str) =>
      str.contains(':') && uriSniffRx.hasMatch(str);

  /// Encodes [str] for safe inclusion as a URI component.
  ///
  /// Mirrors Ruby's `CGI.escape` with `+` rewritten to `%20`: everything
  /// except letters, digits and `-_.~` is percent-encoded (uppercase hex,
  /// UTF-8 bytes for non-ASCII). Dart's [Uri.encodeComponent] additionally
  /// leaves `!'()*` raw, so those are encoded here.
  static String encodeUriComponent(String str) =>
      Uri.encodeComponent(str)
          .replaceAll('!', '%21')
          .replaceAll("'", '%27')
          .replaceAll('(', '%28')
          .replaceAll(')', '%29')
          .replaceAll('*', '%2A');

  /// Encodes spaces in [str] as `%20` for safe inclusion in a URI path.
  static String encodeSpacesInUri(String str) => str.replaceAll(' ', '%20');

  /// Removes the file extension from [filename] and returns the result.
  ///
  /// [filename] is expected to be a posix path; a dot outside the last
  /// segment is not treated as an extension separator.
  static String rootname(String filename) {
    final lastDotIdx = filename.lastIndexOf('.');
    if (lastDotIdx == -1) return filename;
    return filename.indexOf('/', lastDotIdx) == -1
        ? filename.substring(0, lastDotIdx)
        : filename;
  }

  /// Returns the last segment of [filename], dropping [dropExt] if given.
  ///
  /// When [dropExt] is `true`, the file extension is dropped; when a
  /// [String], that suffix is dropped (with Ruby's `File.basename` semantics,
  /// including the `.*` wildcard); otherwise the basename is kept whole.
  static String basename(String filename, [Object? dropExt]) {
    var end = filename.length;
    while (end > 1 && _isDirSeparator(filename.codeUnitAt(end - 1))) {
      end--;
    }
    var start = 0;
    for (var k = end - 1; k >= 0; k--) {
      if (_isDirSeparator(filename.codeUnitAt(k))) {
        start = k + 1;
        break;
      }
    }
    var base = filename.substring(start, end);
    if (base.isEmpty && end > 0) base = '/';
    if (dropExt != null && dropExt != false) {
      final suffix = dropExt == true
          ? extname(filename) ?? ''
          : dropExt as String;
      if (suffix == '.*') {
        final dotIdx = base.lastIndexOf('.');
        if (dotIdx != -1 && _hasStem(base, dotIdx)) {
          base = base.substring(0, dotIdx);
        }
      } else if (suffix.isNotEmpty &&
          base.length > suffix.length &&
          base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
      }
    }
    return base;
  }

  /// Whether [unit] is a directory separator (`/` everywhere, plus `\` on
  /// Windows, mirroring Ruby's `File::ALT_SEPARATOR` handling).
  static bool _isDirSeparator(int unit) =>
      unit == 0x2f || (Platform.isWindows && unit == 0x5c);

  /// Whether [base] has a non-dot character before [dotIdx] (i.e. the
  /// `.*` wildcard has a stem to preserve, as in `a..` but not `..`).
  static bool _hasStem(String base, int dotIdx) {
    for (var k = 0; k < dotIdx; k++) {
      if (base.codeUnitAt(k) != 0x2e) return true;
    }
    return false;
  }

  /// Whether [path] has a file extension. [path] is expected to be a posix
  /// path.
  static bool hasExtname(String path) {
    final lastDotIdx = path.lastIndexOf('.');
    return lastDotIdx != -1 && path.indexOf('/', lastDotIdx) == -1;
  }

  /// Returns the file extension of [path] (leading dot included).
  ///
  /// The extension is the portion of the last path segment starting from the
  /// last period. Returns [fallback] when [path] has no file extension.
  static String? extname(String path, [String? fallback = '']) {
    final lastDotIdx = path.lastIndexOf('.');
    if (lastDotIdx == -1) return fallback;
    if (path.indexOf('/', lastDotIdx) != -1) return fallback;
    if (Platform.isWindows && path.indexOf(r'\', lastDotIdx) != -1) {
      return fallback;
    }
    return path.substring(lastDotIdx);
  }

  /// Makes directory [dir], ensuring all parent directories exist.
  static void mkdirP(String dir) {
    Directory(dir).createSync(recursive: true);
  }

  static const Map<String, int> _romanNumeralsWithReducers = {
    'M': 1000,
    'CM': 900,
    'D': 500,
    'CD': 400,
    'C': 100,
    'XC': 90,
    'L': 50,
    'XL': 40,
    'X': 10,
    'IX': 9,
    'V': 5,
    'IV': 4,
    'I': 1,
  };

  /// Converts integer [val] to a Roman numeral.
  static String intToRoman(int val) {
    final result = StringBuffer();
    for (final entry in _romanNumeralsWithReducers.entries) {
      final repeat = val ~/ entry.value;
      val = val % entry.value;
      for (var i = 0; i < repeat; i++) {
        result.write(entry.key);
      }
    }
    return result.toString();
  }

  static const Map<String, int> _romanNumerals = {
    'I': 1,
    'V': 5,
    'X': 10,
    'L': 50,
    'C': 100,
    'D': 500,
    'M': 1000,
  };

  /// Converts the uppercase Roman numeral [val] to an integer.
  static int romanToInt(String val) {
    var result = 0;
    final values = [for (final c in val.split('')) _romanNumerals[c]!];
    for (var idx = 0; idx < values.length; idx++) {
      final succ = idx + 1 < values.length ? values[idx + 1] : null;
      if (succ != null && succ > values[idx]) {
        result -= values[idx];
      } else {
        result += values[idx];
      }
    }
    return result;
  }

  /// Returns the next value in the sequence after [current].
  ///
  /// Handles both integer and character sequences: an [int] (or a [String]
  /// that round-trips through `int.parse`, such as `'1'`) yields the
  /// incremented integer; any other string yields its Ruby `succ` successor.
  static Object nextVal(Object current) {
    if (current is int) return current + 1;
    if (current is! String) {
      throw ArgumentError(
        'Cannot compute next value for ${current.runtimeType}',
      );
    }
    final intval = int.tryParse(current);
    if (intval != null && intval.toString() == current) return intval + 1;
    // Beyond 64 bits Ruby keeps counting with a bignum; mirror that with
    // BigInt so arbitrarily long digit strings still take the integer path.
    final bigval = BigInt.tryParse(current);
    if (bigval != null && bigval.toString() == current) {
      return bigval + BigInt.one;
    }
    return _succ(current);
  }

  // Alphanumeric per Ruby's Onigmo `\p{Alnum}` (alphabetic or decimal digit).
  static final RegExp _alnumChar = RegExp(r'[\p{Alpha}\p{Nd}]', unicode: true);
  // Decimal digit per Ruby's Onigmo `\p{Digit}` (includes ASCII 0-9).
  static final RegExp _digitChar = RegExp(r'\p{Nd}', unicode: true);

  static bool _isAlnum(int rune) =>
      _alnumChar.hasMatch(String.fromCharCode(rune));
  static bool _isAsciiAlnum(int rune) =>
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x61 && rune <= 0x7a) ||
      (rune >= 0x41 && rune <= 0x5a);

  /// Letter (true) or digit (false) class of the alphanumeric [rune].
  static bool _isLetter(int rune) {
    if (rune >= 0x61 && rune <= 0x7a) return true;
    if (rune >= 0x41 && rune <= 0x5a) return true;
    if (rune >= 0x30 && rune <= 0x39) return false;
    return !_digitChar.hasMatch(String.fromCharCode(rune));
  }

  /// Ruby `String#succ` successor for [current].
  ///
  /// Increments the trailing alphanumeric run with carry (`'a9'` becomes
  /// `'b0'`). Non-alphanumeric separators inside the run are transparent
  /// (`'1-9'` becomes `'2-0'`), but the run aborts before an ASCII letter
  /// or digit whose class differs from the nearest alphanumeric on its
  /// right (`'a-9'` becomes `'a-10'`, `'1-z9'` becomes `'1-aa0'`).
  /// Non-ASCII alphanumerics increment by codepoint and absorb the carry
  /// (`'ä9'` becomes `'å0'`). With no alphanumeric present, the last
  /// character is incremented by codepoint.
  static String _succ(String current) {
    if (current.isEmpty) return current;
    final runes = current.runes.toList();
    var i = runes.length;
    while (i > 0 && !_isAlnum(runes[i - 1])) {
      i--;
    }
    if (i == 0) {
      runes[runes.length - 1] = runes.last + 1;
      return String.fromCharCodes(runes);
    }
    final lastAlnumEnd = i;
    var last = runes[i - 1];
    i--;
    var pendingSeps = 0;
    while (i > 0) {
      final c = runes[i - 1];
      if (_isAlnum(c)) {
        if (pendingSeps > 0 &&
            _isAsciiAlnum(c) &&
            _isLetter(c) != _isLetter(last)) {
          break;
        }
        last = c;
        pendingSeps = 0;
        i--;
      } else {
        pendingSeps++;
        i--;
      }
    }
    final regionStart = i + pendingSeps;
    var carry = true;
    var j = lastAlnumEnd - 1;
    while (carry && j >= regionStart) {
      final c = runes[j];
      if (c >= 0x30 && c <= 0x39) {
        if (c == 0x39) {
          runes[j] = 0x30;
        } else {
          runes[j] = c + 1;
          carry = false;
        }
      } else if (c >= 0x61 && c <= 0x7a) {
        if (c == 0x7a) {
          runes[j] = 0x61;
        } else {
          runes[j] = c + 1;
          carry = false;
        }
      } else if (c >= 0x41 && c <= 0x5a) {
        if (c == 0x5a) {
          runes[j] = 0x41;
        } else {
          runes[j] = c + 1;
          carry = false;
        }
      } else if (_isAlnum(c)) {
        runes[j] = c + 1;
        carry = false;
      } else {
        // Transparent separator; the carry passes through.
      }
      j--;
    }
    if (carry) {
      // The char at regionStart rolled over (9/z/Z became 0/a/A); the carry
      // materializes as a new leading 1/a/A.
      final first = runes[regionStart];
      runes.insert(regionStart, first == 0x30 ? 0x31 : first);
    }
    return String.fromCharCodes(runes);
  }

  /// Registry backing [classForName]. Dart has no reflection by name, so
  /// ported classes register themselves (or are registered by their
  /// library) under their Ruby qualified name.
  static final Map<String, Type> _classRegistry = {
    'String': String,
    'int': int,
    'double': double,
    'bool': bool,
    'List': List,
    'Map': Map,
    'Object': Object,
  };

  /// Registers [type] under [qualifiedName] for [classForName] lookups.
  static void registerClass(String qualifiedName, Type type) {
    _classRegistry[qualifiedName] = type;
  }

  /// Resolves the [Type] registered under [qualifiedName].
  ///
  /// A leading `::` is ignored. Throws an [ArgumentError] carrying Ruby's
  /// `Could not resolve class for name: ...` message when nothing is
  /// registered under that name.
  static Type classForName(String qualifiedName) {
    final name = qualifiedName.startsWith('::')
        ? qualifiedName.substring(2)
        : qualifiedName;
    final type = _classRegistry[name];
    if (type == null) {
      throw ArgumentError('Could not resolve class for name: $qualifiedName');
    }
    return type;
  }

  /// Resolves [object] as a [Type].
  ///
  /// Returns [object] itself when it is already a [Type], resolves it via
  /// [classForName] when it is a [String], and returns `null` otherwise.
  static Type? resolveClass(Object? object) {
    if (object is Type) return object;
    if (object is String) return classForName(object);
    return null;
  }
}
