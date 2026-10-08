/// Full Unicode case mapping (The Unicode Standard, section 3.13), the same
/// on every platform: the Dart VM's own tables are older and lack the
/// special mappings, and JavaScript's apply the Final_Sigma rule.
library;

import 'package:plain_unicode/src/case_data.g.dart';

/// [text] in upper case: each code point's full mapping, such as `ß` to
/// `SS` (as Ruby's `String#upcase` and JavaScript's `toUpperCase` do).
String upperCase(String text) =>
    _isAscii(text) ? text.toUpperCase() : _map(text, _upper, upper: true);

/// [text] in lower case: each code point's full mapping, such as `İ` to
/// `i̇`. With [finalSigma], a capital sigma that ends a word becomes `ς`
/// (Unicode's Final_Sigma context, as JavaScript's `toLowerCase` does);
/// without it, every capital sigma becomes `σ` (as Ruby's
/// `String#downcase` does).
String lowerCase(String text, {bool finalSigma = false}) {
  if (_isAscii(text)) return text.toLowerCase();
  if (!finalSigma || !text.contains('Σ')) {
    return _map(text, _lower, upper: false);
  }
  final runes = text.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune == 0x3a3) {
      out.write(_isFinalSigma(runes, i) ? 'ς' : 'σ');
    } else {
      _write(out, rune, _lower, upper: false);
    }
  }
  return out.toString();
}

/// Whether [rune] is Cased (it has a case, or is a letter with a case
/// property).
bool isCased(int rune) => _in(_cased, rune);

/// Whether [rune] is Case_Ignorable (marks, format characters, modifier
/// letters and the like, skipped by case contexts).
bool isCaseIgnorable(int rune) => _in(_caseIgnorable, rune);

final Map<int, String> _upper = _parse(upperTable);
final Map<int, String> _lower = _parse(lowerTable);
final List<int> _cased = _parseRanges(casedRanges);
final List<int> _caseIgnorable = _parseRanges(caseIgnorableRanges);

bool _isAscii(String text) {
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) >= 0x80) return false;
  }
  return true;
}

String _map(String text, Map<int, String> table, {required bool upper}) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    _write(out, rune, table, upper: upper);
  }
  return out.toString();
}

void _write(
  StringBuffer out,
  int rune,
  Map<int, String> table, {
  required bool upper,
}) {
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
    return;
  }
  final mapped = table[rune];
  if (mapped == null) {
    out.writeCharCode(rune);
  } else {
    out.write(mapped);
  }
}

/// Final_Sigma: a cased letter before (case-ignorable ones skipped), and
/// none after.
bool _isFinalSigma(List<int> runes, int index) {
  var before = false;
  for (var i = index - 1; i >= 0; i--) {
    if (isCaseIgnorable(runes[i])) continue;
    before = isCased(runes[i]);
    break;
  }
  if (!before) return false;
  for (var i = index + 1; i < runes.length; i++) {
    if (isCaseIgnorable(runes[i])) continue;
    return !isCased(runes[i]);
  }
  return true;
}

/// A generated mapping table: runs (`start:delta:count:stride`) and
/// mappings to several code points (`cp=mapped mapped`), in base 36.
Map<int, String> _parse(String table) {
  final map = <int, String>{};
  for (final entry in table.split(',')) {
    if (entry.split('=') case [final cp, final mapped]) {
      map[int.parse(cp, radix: 36)] = String.fromCharCodes([
        for (final c in mapped.split(' ')) int.parse(c, radix: 36),
      ]);
    } else if (entry.split(':') case [
      final start,
      final delta,
      final count,
      final stride,
    ]) {
      final first = int.parse(start, radix: 36);
      final offset = int.parse(delta, radix: 36);
      final step = int.parse(stride);
      for (var i = 0; i < int.parse(count, radix: 36); i++) {
        final cp = first + i * step;
        map[cp] = String.fromCharCode(cp + offset);
      }
    }
  }
  return map;
}

/// Generated ranges (`start-end,...`, base 36) as a flat sorted list.
List<int> _parseRanges(String ranges) => [
  for (final range in ranges.split(','))
    for (final end in range.split('-')) int.parse(end, radix: 36),
];

/// Whether [rune] is in the flat range list [ranges] (binary search).
bool _in(List<int> ranges, int rune) {
  var lo = 0;
  var hi = ranges.length ~/ 2 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (rune < ranges[2 * mid]) {
      hi = mid - 1;
    } else if (rune > ranges[2 * mid + 1]) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}
