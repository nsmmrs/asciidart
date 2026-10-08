/// Which ASCII characters a text holds, to answer the substitutions'
/// guards ("does the text contain `link:`?") without a search per guard.
///
/// The VM's `String.indexOf` with a pattern of more than one code unit
/// calls a matcher at every position, and the substitutions ask dozens of
/// such questions of each paragraph, most of which leave it unchanged. The
/// ASCII characters present are worked out once per text (one pass, kept
/// until a different text is asked about); a literal with a character
/// the text lacks cannot occur, and one whose characters are all there is
/// then searched for by its first code unit.
library;

/// The text the mask describes (compared by identity: a pass that
/// changes nothing returns the same string).
String? _maskedText;

// The ASCII characters [_maskedText] holds: a bit per code unit, 32 to a
// word (words that fit in JavaScript's 32-bit operations too).
int _m0 = 0;
int _m1 = 0;
int _m2 = 0;
int _m3 = 0;

void _mask(String text) {
  if (identical(text, _maskedText)) return;
  var m0 = 0;
  var m1 = 0;
  var m2 = 0;
  var m3 = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0x80) continue;
    final bit = 1 << (c & 31);
    switch (c >> 5) {
      case 0:
        m0 |= bit;
      case 1:
        m1 |= bit;
      case 2:
        m2 |= bit;
      default:
        m3 |= bit;
    }
  }
  _m0 = m0;
  _m1 = m1;
  _m2 = m2;
  _m3 = m3;
  _maskedText = text;
}

/// Whether the text last masked could hold [c]: it holds it, or [c] is
/// not ASCII (which the mask does not record).
bool _has(int c) {
  if (c >= 0x80) return true;
  final word = switch (c >> 5) {
    0 => _m0,
    1 => _m1,
    2 => _m2,
    _ => _m3,
  };
  return word & (1 << (c & 31)) != 0;
}

/// Whether [text] holds the character [char] (one ASCII code unit), as
/// `text.contains(char)`.
bool hasChar(String text, String char) {
  assert(char.length == 1 && char.codeUnitAt(0) < 0x80, 'one ASCII character');
  _mask(text);
  return _has(char.codeUnitAt(0));
}

/// Whether [text] holds any of the ASCII characters [chars].
bool hasAnyChar(String text, String chars) {
  _mask(text);
  for (var k = 0; k < chars.length; k++) {
    if (_has(chars.codeUnitAt(k))) return true;
  }
  return false;
}

/// The index of the first [literal] in [text] at or after [start], as
/// `text.indexOf(literal, start)`.
int literalIndexOf(String text, String literal, [int start = 0]) {
  final n = literal.length;
  if (n == 0) return text.indexOf(literal, start);
  RangeError.checkValueInInterval(start, 0, text.length, 'start');
  _mask(text);
  for (var k = 0; k < n; k++) {
    if (!_has(literal.codeUnitAt(k))) return -1;
  }
  if (n == 1) return text.indexOf(literal, start);
  final c0 = literal.codeUnitAt(0);
  final last = text.length - n;
  outer:
  for (var i = start; i <= last; i++) {
    if (text.codeUnitAt(i) != c0) continue;
    for (var k = 1; k < n; k++) {
      if (text.codeUnitAt(i + k) != literal.codeUnitAt(k)) continue outer;
    }
    return i;
  }
  return -1;
}

/// Whether [text] contains [literal], as `text.contains(literal)`.
bool hasLiteral(String text, String literal) {
  if (literal.length == 1 && literal.codeUnitAt(0) < 0x80) {
    _mask(text);
    return _has(literal.codeUnitAt(0));
  }
  return literalIndexOf(text, literal) >= 0;
}
