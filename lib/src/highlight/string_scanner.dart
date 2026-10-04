/// Minimal string scanner for the CodeRay scanners.
///
/// Only the surface the Ruby-language scanner exercises is implemented: `scan`,
/// `scanUntil`, `scanRest`, `check`, `getch`, `peek`, `unscan`, `eos`,
/// `bol`, `pos`, `lastMatch` (captures via `capture`) and `terminate`.
///
/// Positions are UTF-16 code-unit offsets (Dart string convention); CodeRay
/// counts characters. The two agree on the Basic Multilingual Plane
/// and differ only inside astral characters, which the supported scanners
/// treat as opaque identifier characters either way.
library;

/// A scanning cursor over [string], mirroring `StringScanner` semantics.
class CodeRayStringScanner {
  /// Creates a scanner over [source] at position zero.
  new(String source) : string = source;

  /// The scanned string (already normalized to `\n` newlines by the caller,
  /// mirroring `Scanner.normalize`).
  final String string;

  /// The current scan offset in UTF-16 code units.
  int _pos = 0;

  /// The most recent match, or `null` after a failed match operation.
  ///
  /// Mirrors `StringScanner#matched` plus the capture registers (`self[1]`
  /// reads [capture]`(1)`). Failed matches clear it.
  Match? lastMatch;

  /// Length of the most recent [scan], for [unscan].
  int _lastLength = 0;

  /// The current scan offset.
  int get pos => _pos;

  /// Whether the cursor is at the end of [string].
  bool get eos => _pos >= string.length;

  /// Whether the cursor is at the start of a line (offset zero or right
  /// after a `\n`).
  bool get bol => _pos == 0 || string.codeUnitAt(_pos - 1) == 0x0A;

  /// The unscanned remainder of [string].
  String get rest => string.substring(_pos);

  /// Tries to match [pattern] anchored at the cursor.
  ///
  /// Returns the matched text and advances past it, or returns `null`
  /// without moving when [pattern] does not match here. A zero-width match
  /// returns `''` without moving.
  String? scan(RegExp pattern) {
    final match = pattern.matchAsPrefix(string, _pos);
    _lastLength = 0;
    if (match == null) {
      lastMatch = null;
      return null;
    }
    lastMatch = match;
    _lastLength = match.end - match.start;
    _pos = match.end;
    return match.group(0);
  }

  /// Matches [pattern] anchored at the cursor without consuming input.
  ///
  /// Returns the matched text, or `null` without moving. Captures are
  /// recorded in [lastMatch].
  String? check(RegExp pattern) {
    final match = pattern.matchAsPrefix(string, _pos);
    lastMatch = match;
    return match?.group(0);
  }

  /// Returns the capture group [index] of [lastMatch], or `null` when there
  /// is no match or the group did not participate.
  ///
  /// Mirrors `StringScanner#self[]`. Note that a group matching the empty
  /// string (such as the heredoc-end marker `()`) yields `''`, not `null`.
  String? capture(int index) => lastMatch?.group(index);

  /// Scans forward through the first match of [pattern] at or after the
  /// cursor.
  ///
  /// Returns everything from the cursor through the end of the match and
  /// advances past it, or returns `null` without moving when [pattern]
  /// never matches again. A zero-width match at the cursor returns `''`
  /// without moving.
  ///
  /// One known deviation: CodeRay matches against the unscanned rest, so
  /// `\A` anchors at the scan position there; here
  /// cannot spell `\A` at all, so no caller passes `\A` patterns. (The
  /// heredoc terminator search, the one `\A` use in the original, is
  /// implemented by hand with faithful scan-position semantics.)
  String? scanUntil(RegExp pattern) {
    final matches = pattern.allMatches(string, _pos).iterator;
    final match = matches.moveNext() ? matches.current : null;
    if (match == null) {
      lastMatch = null;
      return null;
    }
    lastMatch = match;
    final text = string.substring(_pos, match.end);
    _lastLength = match.end - _pos;
    _pos = match.end;
    return text;
  }

  /// Consumes and returns the rest of [string] (possibly `''` at [eos]).
  ///
  /// Mirrors the `scan_rest` helper; match registers are left untouched.
  String scanRest() {
    final text = string.substring(_pos);
    _pos = string.length;
    return text;
  }

  /// Consumes and returns one Unicode code point, or `null` at [eos].
  ///
  /// Mirrors `StringScanner#getch` on a UTF-8 string.
  String? getch() {
    if (_pos >= string.length) return null;
    final code = string.codeUnitAt(_pos);
    if (_isLeadSurrogate(code) && _pos + 1 < string.length) {
      final next = string.codeUnitAt(_pos + 1);
      if (_isTrailSurrogate(next)) {
        _pos += 2;
        return string.substring(_pos - 2, _pos);
      }
    }
    _pos += 1;
    return string.substring(_pos - 1, _pos);
  }

  /// Returns up to [length] code units ahead of the cursor without consuming
  /// input (fewer at the end of [string]).
  ///
  /// Mirrors `StringScanner#peek`.
  String peek(int length) {
    var end = _pos + length;
    if (end < 0) end = 0;
    if (end > string.length) end = string.length;
    return string.substring(_pos, end);
  }

  /// Moves the cursor back over the most recent [scan].
  ///
  /// Mirrors `StringScanner#unscan` (only single-step unscan is used).
  void unscan() {
    _pos -= _lastLength;
    _lastLength = 0;
  }

  /// Advances the cursor by [length] code units without matching.
  ///
  /// Used by the string-state content scan, which locates its stop
  /// position by hand. Match registers are cleared, mirroring a successful
  /// zero-width scan for the reads the callers perform (none read captures
  /// after this call).
  void consume(int length) {
    _pos += length;
    _lastLength = 0;
    lastMatch = null;
  }

  /// Moves the cursor to the end of [string].
  void terminate() {
    _pos = string.length;
  }

  /// Whether [unit] is a UTF-16 lead surrogate.
  static bool _isLeadSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  /// Whether [unit] is a UTF-16 trail surrogate.
  static bool _isTrailSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}
