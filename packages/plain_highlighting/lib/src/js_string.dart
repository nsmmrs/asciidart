/// JavaScript string semantics the engine relies on.
library;

import 'package:plain_unicode/plain_unicode.dart' show lowerCase;

/// [text] in lower case as JavaScript's `toLowerCase` gives it: full
/// Unicode mappings (`İ` becomes `i` + U+0307) and the Final_Sigma rule (a
/// capital sigma that ends a word becomes `ς`), from plain_unicode's
/// tables, the same on the Dart VM and in a browser.
String jsLowerCase(String text) => lowerCase(text, finalSigma: true);

final RegExp _decimal = RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$');
final RegExp _radix = RegExp(r'^0([xXoObB])([0-9a-fA-F]+)$');

/// [text] converted as JavaScript's `Number(text)` does: surrounding
/// whitespace ignored, the empty string is 0, and anything else that is not
/// a number is NaN.
num jsNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  if (_decimal.hasMatch(trimmed)) return num.parse(trimmed);
  final radix = _radix.firstMatch(trimmed);
  if (radix != null) {
    final base = switch (radix[1]!.toLowerCase()) {
      'x' => 16,
      'o' => 8,
      _ => 2,
    };
    return int.tryParse(radix[2]!, radix: base) ?? double.nan;
  }
  return switch (trimmed) {
    'Infinity' || '+Infinity' => double.infinity,
    '-Infinity' => double.negativeInfinity,
    _ => double.nan,
  };
}
