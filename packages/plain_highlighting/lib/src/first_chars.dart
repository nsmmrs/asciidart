/// The characters a match of a regular expression can start with, read
/// from its source: a superset, so that a search can skip the positions
/// where no match can start and try the expression only at the others
/// (the Dart VM's engine is several times slower than V8's at searching).
library;

import 'dart:typed_data';

/// The characters a match can start with (at least): each ASCII character
/// on its own, and whether any other one may.
final class FirstChars {
  new _(
    this._ascii, {
    required this.nonAscii,
    required this.atEnd,
    required this.wordStart,
    this.run,
  });

  /// 1 for each ASCII character a match can start with.
  final Uint8List _ascii;

  /// Whether a match can start with a character beyond ASCII.
  final bool nonAscii;

  /// Whether an empty match can be at the end of the text (`$`).
  final bool atEnd;

  /// Whether every match starts at the start of a word (`\b` before a
  /// word character): never right after another word character.
  final bool wordStart;

  /// The ASCII characters of the class C when every match starts with a
  /// run of them (`C D*` with C in D, or `C+`) and the expression has no
  /// backreference: then where it doesn't match, it doesn't match
  /// further into the same run either (a match there would start the run
  /// earlier too). 1 for each.
  final Uint8List? run;

  /// Whether a match can start with the ASCII character [c].
  bool has(int c) => _ascii[c] != 0;
}

/// Whether [c] is a word character (`\w`, as `\b` reads it outside
/// Unicode mode).
bool isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c == 0x5f;

/// The characters a match of the regular expression [source] can start
/// with (case-insensitive when [ignoreCase]; not Unicode mode; multiline),
/// or null when its source uses what isn't read here, or it can match
/// without a first character anywhere (an empty match, one that only looks
/// behind) but at the end of a line.
FirstChars? firstChars(String source, {required bool ignoreCase}) {
  final parser = _Parser(source, ignoreCase: ignoreCase);
  try {
    final (chars, nullable) = parser.alternation();
    if (nullable || parser.at < source.length) return null;
    var words = !chars.nonAscii && !chars.atEnd;
    for (var c = 0; c < 128 && words; c++) {
      if (chars.ascii[c] != 0 && !isWordChar(c)) words = false;
    }
    return FirstChars._(
      chars.ascii,
      nonAscii: chars.nonAscii,
      atEnd: chars.atEnd,
      wordStart: chars.boundary && words,
      run: parser.backreferences ? null : chars.run?.ascii,
    );
  } on _Unread {
    return null;
  }
}

/// What [firstChars] doesn't read.
final class _Unread implements Exception {
  const new();
}

/// A set of characters: the ASCII ones, and whether any beyond.
final class _Chars {
  final Uint8List ascii = Uint8List(128);
  bool nonAscii = false;

  /// Whether the text's end may follow (an empty match there).
  bool atEnd = false;

  /// Whether the expression read asserts `\b` before anything else.
  bool boundary = false;

  /// Whether the expression read is one character of this set (whose
  /// ASCII part is then exact).
  bool single = false;

  /// Its quantifier: whether it has one, its minimum, and whether it has
  /// no maximum.
  bool quantified = false;
  int min = 1;
  bool unbounded = false;

  /// The class of the run the expression's matches start with (see
  /// [FirstChars.run]).
  _Chars? run;

  /// Whether this set's ASCII characters are all in [other]'s.
  bool asciiIn(_Chars other) {
    for (var c = 0; c < 128; c++) {
      if (ascii[c] != 0 && other.ascii[c] == 0) return false;
    }
    return true;
  }

  void add(int c) {
    if (c < 128) {
      ascii[c] = 1;
    } else {
      nonAscii = true;
    }
  }

  void addRange(int from, int to) {
    for (var c = from; c <= to && c < 128; c++) {
      ascii[c] = 1;
    }
    if (to >= 128) nonAscii = true;
  }

  void addAll(_Chars other) {
    for (var c = 0; c < 128; c++) {
      if (other.ascii[c] != 0) ascii[c] = 1;
    }
    if (other.nonAscii) nonAscii = true;
    if (other.atEnd) atEnd = true;
  }

  /// The other case of each ASCII letter too.
  void foldCase() {
    for (var c = 0x41; c <= 0x5a; c++) {
      if (ascii[c] != 0 || ascii[c + 32] != 0) ascii[c] = ascii[c + 32] = 1;
    }
  }

  /// Every character this set doesn't have (any beyond ASCII may be).
  _Chars complement() {
    final other = _Chars();
    for (var c = 0; c < 128; c++) {
      other.ascii[c] = ascii[c] ^ 1;
    }
    other.nonAscii = true;
    return other;
  }
}

/// Reads a regular expression (ECMAScript syntax, not Unicode mode) for
/// the characters its matches start with.
final class _Parser {
  new(this.source, {required this.ignoreCase});

  final String source;
  final bool ignoreCase;
  int at = 0;

  /// Whether the expression has a backreference.
  bool backreferences = false;

  bool get _done => at >= source.length;
  int get _c => source.codeUnitAt(at);

  /// Alternatives: their first characters, and whether one can match with
  /// none.
  (_Chars, bool) alternation() {
    final chars = _Chars();
    var nullable = false;
    var boundary = true;
    var alternatives = 0;
    _Chars? run;
    while (true) {
      final (first, empty) = _sequence();
      chars.addAll(first);
      nullable = nullable || empty;
      boundary = boundary && first.boundary;
      run = first.run;
      alternatives++;
      if (!_done && _c == 0x7c /* | */ ) {
        at++;
        continue;
      }
      return (
        chars
          ..boundary = boundary
          ..run = alternatives == 1 ? run : null,
        nullable,
      );
    }
  }

  (_Chars, bool) _sequence() {
    final chars = _Chars();
    // Whether every term so far can match without a character.
    var open = true;
    // The first two terms, for the run.
    _Chars? one;
    _Chars? two;
    while (!_done && _c != 0x7c && _c != 0x29 /* ) */ ) {
      final (first, empty) = _term();
      if (one == null) {
        one = first;
        chars.boundary = first.boundary;
      } else {
        two ??= first;
      }
      if (open) {
        chars.addAll(first);
        if (!empty) open = false;
      }
    }
    if (one != null) {
      if (one.single && one.quantified && one.unbounded && one.min >= 1) {
        chars.run = one;
      } else if (one.single &&
          !one.quantified &&
          two != null &&
          two.single &&
          two.unbounded &&
          one.asciiIn(two)) {
        chars.run = one;
      } else if (!one.single && !one.quantified) {
        // (A group whose matches start with a run.)
        chars.run = one.run;
      }
    }
    return (chars, open);
  }

  /// An atom and its quantifier.
  (_Chars, bool) _term() {
    var (chars, empty) = _atom();
    if (_done) return (chars, empty);
    switch (_c) {
      case 0x2a: // *
        at++;
        empty = true;
        chars
          ..boundary = false
          ..quantified = true
          ..min = 0
          ..unbounded = true;
      case 0x3f: // ?
        at++;
        empty = true;
        chars
          ..boundary = false
          ..quantified = true
          ..min = 0;
      case 0x2b: // +
        at++;
        chars
          ..quantified = true
          ..unbounded = true;
      case 0x7b: // {
        final quantifier = _quantifier();
        if (quantifier == null) return (chars, empty);
        final (min, unbounded) = quantifier;
        chars
          ..quantified = true
          ..min = min
          ..unbounded = unbounded;
        if (min == 0) {
          empty = true;
          chars.boundary = false;
        }
      default:
        return (chars, empty);
    }
    // Lazy.
    if (!_done && _c == 0x3f) at++;
    return (chars, empty);
  }

  /// A `{n}`, `{n,}` or `{n,m}` quantifier at [at]: its minimum and
  /// whether it has no maximum, past it; null (and [at] unmoved) for a
  /// literal brace.
  (int, bool)? _quantifier() {
    final match = _braces.matchAsPrefix(source, at);
    if (match == null) return null;
    at = match.end;
    return (int.parse(match[1]!), match[2] == '');
  }

  static final RegExp _braces = RegExp(r'\{(\d+)(?:,(\d*))?\}');

  (_Chars, bool) _atom() {
    final c = _c;
    at++;
    switch (c) {
      case 0x28: // (
        return _group();
      case 0x5b: // [
        return (_class()..single = true, false);
      case 0x2e: // .
        final chars = _Chars()
          ..addRange(0, 127)
          ..nonAscii = true
          ..single = true;
        chars.ascii[10] = chars.ascii[13] = 0;
        return (chars, false);
      case 0x5e: // ^
        return (_Chars(), true);
      case 0x24: // $: a line break (or the end) follows
        final chars = _Chars()
          ..add(10)
          ..add(13)
          ..nonAscii = true
          ..atEnd = true;
        return (chars, false);
      case 0x5c: // \
        return _escape();
      case 0x2a || 0x2b || 0x3f || 0x7c || 0x29:
        throw const _Unread();
      default:
        return (_literal(c)..single = true, false);
    }
  }

  _Chars _literal(int c) {
    final chars = _Chars()..add(c);
    if (ignoreCase) chars.foldCase();
    return chars;
  }

  (_Chars, bool) _group() {
    var lookahead = false;
    var zeroWidth = false;
    if (!_done && _c == 0x3f /* ? */ ) {
      final rest = source.substring(at);
      if (rest.startsWith('?:')) {
        at += 2;
      } else if (rest.startsWith('?=')) {
        at += 2;
        lookahead = true;
      } else if (rest.startsWith('?!') ||
          rest.startsWith('?<=') ||
          rest.startsWith('?<!')) {
        at += rest.startsWith('?!') ? 2 : 3;
        zeroWidth = true;
      } else if (rest.startsWith('?<')) {
        final close = source.indexOf('>', at);
        if (close < 0) throw const _Unread();
        at = close + 1;
      } else {
        throw const _Unread();
      }
    }
    final (chars, empty) = alternation();
    if (_done || _c != 0x29) throw const _Unread();
    at++;
    // A negative lookahead or a lookbehind takes no character and asks
    // nothing of the next one here; a lookahead asks what it matches of
    // it (unless it can match with none).
    if (zeroWidth) return (_Chars(), true);
    if (lookahead) return empty ? (_Chars(), true) : (chars..run = null, false);
    return (chars, empty);
  }

  (_Chars, bool) _escape() {
    if (_done) throw const _Unread();
    final c = _c;
    at++;
    switch (c) {
      case 0x62: // \b
        return (_Chars()..boundary = true, true);
      case 0x42: // \B
        return (_Chars(), true);
      case >= 0x31 && <= 0x39: // a backreference: anything, or nothing
        backreferences = true;
        while (!_done && _c >= 0x30 && _c <= 0x39) {
          at++;
        }
        return (_Chars().complement(), true);
      case 0x6b: // \k<name>
        backreferences = true;
        final close = source.indexOf('>', at);
        if (!source.startsWith('<', at) || close < 0) throw const _Unread();
        at = close + 1;
        return (_Chars().complement(), true);
      case 0x70 || 0x50: // \p \P
        throw const _Unread();
    }
    if (_classEscape(c) case final chars?) return (chars..single = true, false);
    return (_literal(_charEscape(c))..single = true, false);
  }

  /// `\d`, `\w`, `\s` and their complements, or null.
  _Chars? _classEscape(int c) => switch (c) {
    0x64 => _Chars()..addRange(0x30, 0x39),
    0x44 => (_Chars()..addRange(0x30, 0x39)).complement(),
    0x77 => _word(),
    0x57 => _word().complement(),
    0x73 => _space(),
    0x53 => (_space()..nonAscii = false).complement(),
    _ => null,
  };

  static _Chars _word() => _Chars()
    ..addRange(0x30, 0x39)
    ..addRange(0x41, 0x5a)
    ..addRange(0x61, 0x7a)
    ..add(0x5f);

  static _Chars _space() => _Chars()
    ..addRange(9, 13)
    ..add(0x20)
    ..nonAscii = true;

  /// The character an escape [c] (past the backslash) stands for, reading
  /// what follows it (`\x41`, `A`, `\cJ`).
  int _charEscape(int c) {
    switch (c) {
      case 0x6e:
        return 10;
      case 0x72:
        return 13;
      case 0x74:
        return 9;
      case 0x66:
        return 12;
      case 0x76:
        return 11;
      case 0x30:
        if (!_done && _c >= 0x30 && _c <= 0x39) throw const _Unread();
        return 0;
      case 0x78: // \xHH
        return _hex(2);
      case 0x75: // \uHHHH
        if (!_done && _c == 0x7b) throw const _Unread();
        return _hex(4);
      case 0x63: // \cX
        if (_done) throw const _Unread();
        final letter = _c;
        at++;
        return letter % 32;
      default:
        return c;
    }
  }

  int _hex(int digits) {
    if (at + digits > source.length) throw const _Unread();
    final value = int.tryParse(source.substring(at, at + digits), radix: 16);
    if (value == null) throw const _Unread();
    at += digits;
    return value;
  }

  /// A character class (past its `[`).
  _Chars _class() {
    final negated = !_done && _c == 0x5e;
    if (negated) at++;
    final chars = _Chars();
    // (A `-` after a class escape is itself.)
    var afterSet = false;
    while (true) {
      if (_done) throw const _Unread();
      if (_c == 0x5d /* ] */ ) {
        at++;
        break;
      }
      final (low, set) = _classAtom();
      if (set != null) {
        chars.addAll(set);
        afterSet = true;
        continue;
      }
      if (afterSet && low == 0x2d) {
        chars.add(low!);
        afterSet = false;
        continue;
      }
      afterSet = false;
      // A range.
      if (at + 1 < source.length &&
          _c == 0x2d &&
          source.codeUnitAt(at + 1) != 0x5d) {
        at++;
        final (high, highSet) = _classAtom();
        if (highSet != null || high! < low!) throw const _Unread();
        chars.addRange(low, high);
      } else {
        chars.add(low!);
      }
    }
    if (ignoreCase) chars.foldCase();
    return negated ? chars.complement() : chars;
  }

  /// A character of a class, or the set of a class escape in it.
  (int?, _Chars?) _classAtom() {
    final c = _c;
    at++;
    if (c != 0x5c) return (c, null);
    if (_done) throw const _Unread();
    final e = _c;
    at++;
    if (_classEscape(e) case final chars?) return (null, chars);
    if (e == 0x62) return (8, null); // \b: backspace
    if ((e >= 0x31 && e <= 0x39) || e == 0x6b || e == 0x70 || e == 0x50) {
      throw const _Unread();
    }
    return (_charEscape(e), null);
  }
}
