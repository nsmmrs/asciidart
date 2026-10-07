/// JavaScript string semantics the engine relies on.
library;

/// [text] in lower case as JavaScript's `toLowerCase` gives it.
///
/// Dart's mapping agrees except for the two context-dependent or
/// multi-character cases of Unicode's SpecialCasing: `İ` (U+0130) becomes
/// `i` + U+0307, and a capital sigma at the end of a word becomes `ς`.
String jsLowerCase(String text) {
  final lower = text.toLowerCase();
  if (!_hasSpecial(text)) return lower;
  final out = StringBuffer();
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    if (r == 0x130) {
      out.write('i\u0307');
    } else if (r == 0x3a3) {
      out.write(_isFinalSigma(runes, i) ? 'ς' : 'σ');
    } else {
      out.write(String.fromCharCode(r).toLowerCase());
    }
  }
  return out.toString();
}

/// Whether [text] has a capital I with a dot above or a capital sigma,
/// which JavaScript lower-cases differently.
bool _hasSpecial(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x130 || unit == 0x3a3) return true;
  }
  return false;
}

final RegExp _cased = RegExp(r'^\p{Cased}$', unicode: true);
final RegExp _caseIgnorable = RegExp(r'^\p{Case_Ignorable}$', unicode: true);

bool _is(RegExp property, int rune) =>
    property.hasMatch(String.fromCharCode(rune));

/// Unicode's Final_Sigma: a cased letter before (skipping case-ignorable
/// ones), and none after.
bool _isFinalSigma(List<int> runes, int index) {
  var before = false;
  for (var i = index - 1; i >= 0; i--) {
    if (_is(_caseIgnorable, runes[i])) continue;
    before = _is(_cased, runes[i]);
    break;
  }
  if (!before) return false;
  for (var i = index + 1; i < runes.length; i++) {
    if (_is(_caseIgnorable, runes[i])) continue;
    return !_is(_cased, runes[i]);
  }
  return true;
}

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
