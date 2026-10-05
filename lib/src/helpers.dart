/// Internal helper functions for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/helpers.rb`.
library;

import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/ruby_semantics.dart';
import 'package:asciidart/src/rx.dart';

/// Internal helper functions. Except where noted, everything here is internal.
abstract final class Helpers {
  /// Prepares source [data] lines for parsing.
  ///
  /// Strips a leading byte-order mark and, per line, removes trailing
  /// whitespace when [trimEnd] is set (the default) or a single trailing
  /// line terminator otherwise. The input list is not mutated.
  static List<String> prepareSourceArray(
    List<String> data, {
    bool trimEnd = true,
  }) {
    if (data.isEmpty) return [];
    final lines = [
      if (data[0].startsWith('\uFEFF')) data[0].substring(1) else data[0],
      ...data.skip(1),
    ];
    return [
      for (final line in lines)
        if (trimEnd) line.trimRightAscii() else line.withoutTrailingNewline(),
    ];
  }

  /// Prepares source [data] text for parsing.
  ///
  /// Strips a leading byte-order mark, splits the text into lines on `\n`
  /// and trims each line per [trimEnd] (see
  /// [prepareSourceArray]). A `null` or empty input yields an empty list.
  static List<String> prepareSourceString(String? data, {bool trimEnd = true}) {
    if (data.isNullOrEmpty) return [];
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
    return [
      for (final line in lines)
        if (trimEnd) line.trimRightAscii() else line.withoutTrailingNewline(),
    ];
  }

  /// Whether [str] resembles a URI (i.e. starts with a URI prefix).
  ///
  /// No validation of the URI is performed.
  static bool isUriish(String str) =>
      str.contains(':') && uriSniffRx.hasMatch(str);

  /// Encodes [str] for safe inclusion as a URI component.
  ///
  /// Form-style escaping with spaces as `%20`: everything
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

  /// Returns the last segment of [filename], optionally without a suffix.
  ///
  /// When [dropExtension] is set, the file extension is dropped; when
  /// [dropSuffix] is given, that suffix is dropped (`.*` drops any
  /// extension); otherwise the basename is kept whole.
  static String basename(
    String filename, {
    String? dropSuffix,
    bool dropExtension = false,
  }) {
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
    final suffix = dropExtension ? extname(filename) ?? '' : dropSuffix;
    if (suffix != null) {
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
  /// Windows).
  static bool _isDirSeparator(int unit) =>
      unit == 0x2f || (io.isWindows && unit == 0x5c);

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
    if (io.isWindows && path.indexOf(r'\', lastDotIdx) != -1) {
      return fallback;
    }
    return path.substring(lastDotIdx);
  }

  /// Makes directory [dir], ensuring all parent directories exist.
  static void mkdirP(String dir) {
    io.createDirectories(dir);
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
    var remainder = val;
    for (final entry in _romanNumeralsWithReducers.entries) {
      final repeat = remainder ~/ entry.value;
      remainder = remainder % entry.value;
      for (var i = 0; i < repeat; i++) {
        result.write(entry.key);
      }
    }
    return result.toString();
  }
}
