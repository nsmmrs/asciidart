/// Case mapping as Asciidoctor performs it (Ruby's `String#upcase` and
/// `String#downcase`): full Unicode mappings code point by code point, such
/// as `ß` to `SS`, with no context rules (no final sigma).
///
/// The platform's `toUpperCase`/`toLowerCase` cannot be used for non-ASCII
/// text: the Dart VM's tables are older and lack the special mappings, and
/// JavaScript applies the final sigma rule.
library;

import 'package:asciidoctor/src/case_mapping.g.dart';

/// [text] in upper case, as Ruby's `String#upcase` gives it.
String upcase(String text) => _isAscii(text)
    ? text.toUpperCase()
    : _map(text, _upcase ??= _parse(upcaseTable), upper: true);

/// [text] in lower case, as Ruby's `String#downcase` gives it.
String downcase(String text) => _isAscii(text)
    ? text.toLowerCase()
    : _map(text, _downcase ??= _parse(downcaseTable), upper: false);

Map<int, String>? _upcase;
Map<int, String>? _downcase;

bool _isAscii(String text) {
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) >= 0x80) return false;
  }
  return true;
}

String _map(String text, Map<int, String> table, {required bool upper}) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune < 0x80) {
      final isLower = rune >= 0x61 && rune <= 0x7a;
      final isUpper = rune >= 0x41 && rune <= 0x5a;
      out.writeCharCode(
        upper && isLower
            ? rune - 32
            : !upper && isUpper
            ? rune + 32
            : rune,
      );
    } else {
      final mapped = table[rune];
      if (mapped == null) {
        out.writeCharCode(rune);
      } else {
        out.write(mapped);
      }
    }
  }
  return out.toString();
}

/// Parses a generated table (`cp:mapped mapped,...`, base 36).
Map<int, String> _parse(String table) => {
  for (final entry in table.split(','))
    int.parse(
      entry.substring(0, entry.indexOf(':')),
      radix: 36,
    ): String.fromCharCodes([
      for (final code in entry.substring(entry.indexOf(':') + 1).split(' '))
        int.parse(code, radix: 36),
    ]),
};
