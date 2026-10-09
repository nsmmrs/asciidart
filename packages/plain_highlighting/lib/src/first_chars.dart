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
    required this._ignoreCase,
    required this.nonAscii,
    required this.atEnd,
    required this.wordStart,
    this.run,
    this.follow,
    this.lineStart = false,
    this.prefix,
    this.literal = false,
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

  /// What must follow the run every match starts with, when the match
  /// takes that run whole: see [RunFollow].
  final RunFollow? follow;

  /// Whether every match starts at the start of a line (`^`, multiline):
  /// at the text's start or after a line terminator.
  final bool lineStart;

  /// A literal every match starts with, in lower case when ignoring case
  /// (ASCII only): two characters or more, or any when [literal].
  final String? prefix;

  /// Whether every match is [prefix] and nothing more (no assertion: the
  /// expression is literal characters only).
  final bool literal;

  final bool _ignoreCase;

  /// Whether a match can start with the ASCII character [c].
  bool has(int c) => _ascii[c] != 0;

  /// Whether [at] in [s] is at a line's start, if [lineStart] asks for it.
  bool admitsLine(String s, int at) {
    if (!lineStart || at == 0) return true;
    final c = s.codeUnitAt(at - 1);
    return c == 10 || c == 13 || c == 0x2028 || c == 0x2029;
  }

  /// Whether [s] has [prefix] at [at] (true without one).
  bool admitsPrefix(String s, int at) {
    final prefix = this.prefix;
    if (prefix == null) return true;
    final n = prefix.length;
    if (at + n > s.length) return false;
    for (var k = 0; k < n; k++) {
      var c = s.codeUnitAt(at + k);
      if (_ignoreCase && c >= 0x41 && c <= 0x5a) c |= 0x20;
      if (c != prefix.codeUnitAt(k)) return false;
    }
    return true;
  }
}

/// Whether the expression [source] matches the empty string at every
/// position (`\B|\b`, a mode's default end, alone or before its parent's).
bool matchesEmptyEverywhere(String source) =>
    source == r'\B|\b' || source.startsWith(r'\B|\b|');

/// A match that starts with a run of a class it must take whole: the
/// expression is `C D* R`, `C+ R` or a group of such a run followed by
/// `R`, where every match of the rest `R` takes a character and none
/// starts with one of the run's class (D, or C). Then the run can't stop
/// early (`R` would start inside it), so the character after the run
/// (or the text's end) must be one `R` can start with: a superset test
/// the matcher makes before trying the expression (PCRE2's
/// auto-possessification, used only as a filter).
final class RunFollow {
  new _(
    this._run, {
    required this.runNonAscii,
    required this._follow,
    required this.followNonAscii,
    required this.followAtEnd,
  });

  /// 1 for each ASCII character of the run's class.
  final Uint8List _run;

  /// Whether the run's class may have characters beyond ASCII (which
  /// [admits] then can't see past).
  final bool runNonAscii;

  /// 1 for each ASCII character the rest can start with.
  final Uint8List _follow;

  /// Whether the rest can start with a character beyond ASCII.
  final bool followNonAscii;

  /// Whether the rest can match at the text's end.
  final bool followAtEnd;

  /// Whether a match whose first character is at [at] in [s] may take
  /// the run after it: false when the character after the run (or the
  /// text's end) can't start the rest.
  bool admits(String s, int at) {
    final n = s.length;
    for (var e = at + 1; e < n; e++) {
      final c = s.codeUnitAt(e);
      if (c >= 128) return runNonAscii || followNonAscii;
      if (_run[c] == 0) return _follow[c] != 0;
    }
    return followAtEnd;
  }
}

/// Whether [c] is a word character (`\w`, as `\b` reads it outside
/// Unicode mode).
bool isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c == 0x5f;

/// The characters a match of the regular expression [source] can start
/// with (case-insensitive when [ignoreCase]; in Unicode mode when
/// [unicode]; multiline), or null when its source uses what isn't read
/// here, or it can match without a first character anywhere (an empty
/// match, one that only looks behind) but at the end of a line.
///
/// In Unicode mode, a match never starts inside a surrogate pair, which
/// the matcher has to see to; ignoring case, `ſ` (U+017F) and `K`
/// (U+212A) match `s` and `k` too.
FirstChars? firstChars(
  String source, {
  required bool ignoreCase,
  bool unicode = false,
}) {
  final parser = _Parser(source, ignoreCase: ignoreCase, unicode: unicode);
  try {
    final (chars, nullable) = parser.alternation();
    if (nullable || parser.at < source.length) return null;
    var words = !chars.nonAscii && !chars.atEnd;
    for (var c = 0; c < 128 && words; c++) {
      if (chars.ascii[c] != 0 && !isWordChar(c)) words = false;
    }
    var prefix = chars.prefix;
    var literal = chars.literal;
    if (prefix != null && parser._foldsBeyondAscii && prefix.contains(_sk)) {
      // (Compared by code unit, it would miss `ſ` and `K`.)
      prefix = null;
      literal = false;
    }
    return FirstChars._(
      chars.ascii,
      ignoreCase: ignoreCase,
      nonAscii: chars.nonAscii,
      atEnd: chars.atEnd,
      wordStart: chars.boundary && words,
      run: parser.backreferences ? null : chars.run?.ascii,
      follow: parser.backreferences ? null : _runFollow(chars),
      lineStart: chars.lineStart,
      prefix: prefix != null && (prefix.length > 1 || literal) ? prefix : null,
      literal: literal,
    );
  } on _Unread {
    return null;
  }
}

final RegExp _sk = RegExp('[sk]');

/// The [RunFollow] of an expression read as [chars], if it has one.
RunFollow? _runFollow(_Chars chars) {
  final run = chars.runClass;
  final follow = chars.follow;
  if (run == null || follow == null) return null;
  for (var c = 0; c < 128; c++) {
    if (run.ascii[c] != 0 && follow.ascii[c] != 0) return null;
  }
  return RunFollow._(
    run.ascii,
    runNonAscii: run.nonAscii,
    follow: follow.ascii,
    followNonAscii: follow.nonAscii,
    followAtEnd: follow.atEnd,
  );
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

  /// The class of the run the expression's matches start with after
  /// their first character, and what can follow that run (the first
  /// characters of the rest, when the rest can't match empty): see
  /// [RunFollow]. With [exactRun], the expression is the run alone.
  _Chars? runClass;
  _Chars? follow;
  bool exactRun = false;

  /// Whether the expression read asserts `^` before anything else.
  bool lineStart = false;

  /// The literal the expression's matches start with (see
  /// [FirstChars.prefix]), and whether they are that literal alone
  /// ([FirstChars.literal]).
  String? prefix;
  bool literal = false;

  /// Whether the expression read is an assertion: it takes no character.
  bool assertion = false;

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
  new(this.source, {required this.ignoreCase, required this.unicode});

  final String source;
  final bool ignoreCase;
  final bool unicode;
  int at = 0;

  /// Whether characters beyond ASCII match ASCII ones: `ſ` (U+017F) is
  /// `s` and `K` (U+212A) is `k` when ignoring case in Unicode mode.
  bool get _foldsBeyondAscii => unicode && ignoreCase;

  /// [chars], with what [_foldsBeyondAscii] adds: the ASCII letters of
  /// the characters [low] to [high] that fold to them, and characters
  /// beyond ASCII for `s` and `k`.
  _Chars _fold(_Chars chars, [int low = 0, int high = -1]) {
    if (!_foldsBeyondAscii) return chars;
    if (low <= 0x17f && 0x17f <= high) {
      chars.ascii[0x53] = chars.ascii[0x73] = 1;
    }
    if (low <= 0x212a && 0x212a <= high) {
      chars.ascii[0x4b] = chars.ascii[0x6b] = 1;
    }
    for (final c in const [0x53, 0x73, 0x4b, 0x6b]) {
      if (chars.ascii[c] != 0) chars.nonAscii = true;
    }
    return chars;
  }

  /// A character of the source in Unicode mode: a surrogate (half of a
  /// pair, which is one character there) isn't read.
  int _checked(int c) {
    if (unicode && c >= 0xd800 && c <= 0xdfff) throw const _Unread();
    return c;
  }

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
    var lineStart = true;
    var alternatives = 0;
    _Chars? run;
    while (true) {
      final (first, empty) = _sequence();
      chars.addAll(first);
      nullable = nullable || empty;
      boundary = boundary && first.boundary;
      lineStart = lineStart && first.lineStart;
      run = first.run;
      alternatives++;
      if (!_done && _c == 0x7c /* | */ ) {
        at++;
        continue;
      }
      if (alternatives == 1) {
        chars
          ..runClass = first.runClass
          ..follow = first.follow
          ..exactRun = first.exactRun
          ..prefix = first.prefix
          ..literal = first.literal;
      }
      return (
        chars
          ..boundary = boundary
          ..lineStart = lineStart
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
    final terms = <(_Chars, bool)>[];
    while (!_done && _c != 0x7c && _c != 0x29 /* ) */ ) {
      final (first, empty) = _term();
      terms.add((first, empty));
      if (one == null) {
        one = first;
        chars
          ..boundary = first.boundary
          ..lineStart = first.lineStart;
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
      _readRunFollow(chars, terms);
      _readPrefix(chars, terms);
    }
    return (chars, open);
  }

  /// The literal a sequence of [terms] starts with, and whether it is
  /// that literal alone, into [chars].
  void _readPrefix(_Chars chars, List<(_Chars, bool)> terms) {
    final prefix = StringBuffer();
    var literal = true;
    for (final (term, _) in terms) {
      if (term.prefix case final p? when !term.quantified) {
        prefix.write(p);
        if (term.literal) continue;
      } else if (term.assertion) {
        // (It takes no character.)
        literal = false;
        continue;
      }
      literal = false;
      break;
    }
    if (prefix.isEmpty) return;
    chars
      ..prefix = prefix.toString()
      ..literal = literal;
  }

  /// The run a sequence of [terms] starts with after its first character
  /// (`C D*`, `C+`, or a group that is such a run alone), and what can
  /// follow it, into [chars].
  void _readRunFollow(_Chars chars, List<(_Chars, bool)> terms) {
    final (one, _) = terms[0];
    final _Chars? runClass;
    var rest = 1;
    if (one.single && one.quantified && one.unbounded && one.min >= 1) {
      runClass = one;
    } else if (one.single &&
        !one.quantified &&
        terms.length > 1 &&
        terms[1].$1.single &&
        terms[1].$1.unbounded) {
      runClass = terms[1].$1;
      rest = 2;
    } else if (!one.single && !one.quantified && one.exactRun) {
      runClass = one.runClass;
    } else {
      return;
    }
    if (rest == terms.length) {
      chars
        ..exactRun = true
        ..runClass = runClass;
      return;
    }
    final follow = _Chars();
    for (final (term, empty) in terms.skip(rest)) {
      follow.addAll(term);
      if (!empty) {
        chars
          ..runClass = runClass
          ..follow = follow;
        return;
      }
    }
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
          ..lineStart = false
          ..quantified = true
          ..min = 0
          ..unbounded = true;
      case 0x3f: // ?
        at++;
        empty = true;
        chars
          ..boundary = false
          ..lineStart = false
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
          chars
            ..boundary = false
            ..lineStart = false;
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
        return (
          _Chars()
            ..lineStart = true
            ..assertion = true,
          true,
        );
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
        return (_literal(_checked(c))..single = true, false);
    }
  }

  _Chars _literal(int c) {
    final chars = _Chars()..add(c);
    if (ignoreCase) chars.foldCase();
    _fold(chars, c, c);
    // (ASCII only; a letter in lower case when ignoring case.)
    if (c < 128) {
      final letter = (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a;
      chars
        ..prefix = String.fromCharCode(ignoreCase && letter ? c | 0x20 : c)
        ..literal = true;
    }
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
    if (zeroWidth) return (_Chars()..assertion = true, true);
    if (lookahead) {
      // (It takes no character: no run or literal starts with it.)
      chars
        ..runClass = null
        ..follow = null
        ..exactRun = false
        ..prefix = null
        ..literal = false;
      return empty
          ? (_Chars()..assertion = true, true)
          : (chars..run = null, false);
    }
    return (chars, empty);
  }

  (_Chars, bool) _escape() {
    if (_done) throw const _Unread();
    final c = _c;
    at++;
    switch (c) {
      case 0x62: // \b
        return (
          _Chars()
            ..boundary = true
            ..assertion = true,
          true,
        );
      case 0x42: // \B
        return (_Chars()..assertion = true, true);
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
        return (_property(negated: c == 0x50)..single = true, false);
    }
    if (_classEscape(c) case final chars?) {
      return (_fold(chars)..single = true, false);
    }
    return (_literal(_charEscape(c))..single = true, false);
  }

  /// A Unicode property escape, past its `\p` or `\P` ([negated]): the
  /// ASCII characters that match it (asked of the engine), and any beyond.
  _Chars _property({required bool negated}) {
    if (!unicode) throw const _Unread();
    final close = source.indexOf('}', at);
    if (!source.startsWith('{', at) || close < 0) throw const _Unread();
    final name = source.substring(at + 1, close);
    at = close + 1;
    final ascii = _properties['${negated ? 'P' : 'p'}$ignoreCase$name'] ??=
        _propertyAscii(name, negated: negated);
    return _Chars()
      ..ascii.setAll(0, ascii)
      ..nonAscii = true;
  }

  Uint8List _propertyAscii(String name, {required bool negated}) {
    final re = RegExp(
      '^\\${negated ? 'P' : 'p'}{$name}\$',
      unicode: true,
      caseSensitive: !ignoreCase,
    );
    return Uint8List.fromList([
      for (var c = 0; c < 128; c++)
        if (re.hasMatch(String.fromCharCode(c))) 1 else 0,
    ]);
  }

  static final Map<String, Uint8List> _properties = {};

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
      case 0x75: // \uHHHH, \u{H...} in Unicode mode
        if (!_done && _c == 0x7b) {
          final close = source.indexOf('}', at);
          if (!unicode || close < 0) throw const _Unread();
          final value = int.tryParse(
            source.substring(at + 1, close),
            radix: 16,
          );
          if (value == null || value > 0x10ffff) throw const _Unread();
          at = close + 1;
          return _checked(value);
        }
        return _checked(_hex(4));
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
        _fold(chars, low, high);
      } else {
        chars.add(low!);
        _fold(chars, low, low);
      }
    }
    if (ignoreCase) chars.foldCase();
    _fold(chars);
    return negated ? chars.complement() : chars;
  }

  /// A character of a class, or the set of a class escape in it.
  (int?, _Chars?) _classAtom() {
    final c = _c;
    at++;
    if (c != 0x5c) return (_checked(c), null);
    if (_done) throw const _Unread();
    final e = _c;
    at++;
    if (_classEscape(e) case final chars?) return (null, chars);
    if (e == 0x62) return (8, null); // \b: backspace
    if (e == 0x70 || e == 0x50) return (null, _property(negated: e == 0x50));
    if ((e >= 0x31 && e <= 0x39) || e == 0x6b) throw const _Unread();
    return (_charEscape(e), null);
  }
}
