/// Port of the CodeRay 1.1.3 Ruby scanner (`scanners/ruby.rb` with
/// `scanners/ruby/patterns.rb` and `scanners/ruby/string_state.rb`).
///
/// Scans Ruby source into the [CoderayTokenSink] token stream. The port
/// follows the original branch for branch, including its quirks (see the
/// inline notes). Two deliberate simplifications versus the original:
///
/// * The `unicode` flag is always on: the original enables it exactly when
///   the normalized input is UTF-8, which is always the case on the
///   asciidoctor path (`Scanner.normalize` encodes to UTF-8; Dart strings
///   are Unicode by definition).
/// * Incremental scanning (`options[:state]`, `options[:keep_state]`) is
///   not supported: CodeRay's `Duo` never passes scanner options on the
///   asciidoctor path (`get_scanner_options` reads `:scanner_options`,
///   which asciidoctor never sets), so scanning always starts in
///   `:initial` state.
///
/// Regex notes (all patterns compile with `unicode: true` so `.` and
/// character classes follow code points, as in Ruby; `\d`, `\w` and `\s`
/// are ASCII-only in both engines — verified against the Ruby oracle):
///
/// * Dart has no `/x` extended mode, so the whitespace and comments of the
///   original patterns are stripped by hand below.
/// * Dart has no atomic groups or possessive quantifiers. Three sites use
///   `(?>...)` in the original; each is handled explicitly:
///   - `VALUE_FOLLOWS` (`(?>\s+)` before alternatives that all start with
///     a non-space character): backtracking can never help, so plain
///     greedy matching is exactly equivalent.
///   - `simple_key_pattern` (both quote variants): unrolled from
///     `(?>(?:A+|B)*)` to `A*(?:B A*)*`, which matches the same language
///     (the branches start with disjoint characters, so every split is
///     forced) in linear time. A naive greedy port matches the same
///     language but backtracks exponentially on failure (26s for a
///     60-character fuzz case); the `"` variant additionally pins the
///     original's ordered first-win choice between the three `#`
///     branches with negative lookaheads so no backtrack can revisit
///     it.
///   - `(?>METHOD_NAME_EX)(?!\.|::)` (the `:def_expected` and
///     `:undef_expected` states): emulated exactly in two steps — match
///     greedily (identical to possessive for a standalone match), then
///     fail the whole scan without retry when the lookahead fails.
/// * Dart has no `\A`, `\z` or `\Z` anchors. `\z` (backslash at absolute
///   end) is a direct position check; `\Z` (end of string, less one
///   optional trailing newline) is a zero-width lookahead matching an
///   optional newline at the absolute end; the
///   heredoc terminator search (which uses `\A`) is implemented manually
///   in [_RubyStringState.scanContent], which also sidesteps the atomic
///   `(?>[ \t]*)` in the indented-heredoc terminator (that one is NOT
///   equivalent to greedy matching for quoted delimiters with leading
///   spaces, so it is matched possessively by hand).
/// * Ruby `^`/`$` are always line anchors, so any pattern containing them
///   compiles with `multiLine: true`; `.` matches `\n` only where the
///   original pattern carries `/m`, so `dotAll` is set per pattern.
///   Interpolated Ruby patterns keep their own flags; where a `/m` and a
///   non-`/m` part meet in one alternation (the start-of-line comment
///   scan), the port splits the scan in two instead, which is exactly
///   equivalent because the first alternative always matches when it can
///   start.
/// * Unnecessary backslash escapes are dropped (`\/` becomes `/` and so
///   on): Dart rejects unknown identity escapes when `unicode` is set.
library;

import 'coderay_tokens.dart';
import 'string_scanner.dart';

/// Symbol states of the Ruby scanner (the `Symbol` side of the original
/// `state`, as opposed to [_RubyStringState]).
enum _SymbolState {
  initial,
  defExpected,
  dotExpected,
  moduleExpected,
  undefExpected,
  undefCommaExpected,
  aliasExpected,
}

/// Sentinel for the `:colon_expected` value of `value_expected`.
///
/// The original stores `true`, `false`, `nil`, a `String` (the result of
/// `check`) or `:colon_expected` in one variable; the port uses `Object?`
/// with the same values (`null` for `nil`) so every comparison translates
/// directly.
const String _colonExpected = 'colon_expected';

/// Whether a `value_expected` cell counts as truthy (neither `false`
/// nor `null`).
bool _valueTruthy(Object? value) => value != null && value != false;

/// First character of a Ruby identifier.
///
/// Port of the head of `IDENT`. The POSIX classes are Unicode-aware, but
/// the explicit `[^\0-\177]` alternative already covers every non-ASCII
/// character, so the ASCII ranges below are exact.
const String _identHead = r'(?:[A-Za-z_]|[^\x00-\x7F])';

/// Continuation characters of a Ruby identifier (port of the `IDENT` tail).
const String _identTail = r'(?:[A-Za-z0-9_]|[^\x00-\x7F])*';

/// A Ruby identifier (port of `IDENT`).
const String _ident = '$_identHead$_identTail';

/// Operator method names (port of `METHOD_NAME_OPERATOR`).
const String _methodNameOperator =
    r'\*\*?|[-+~]@?|[/%&|^`]|\[\]=?|<<|>>|<=?>?|>=?|===?|=~|![~=@]?';

/// Method-name suffixes (port of `METHOD_SUFFIX`).
const String _methodSuffix = '(?:[?!]|=(?![~>]|=(?!>)))';

/// Extended method names (port of `METHOD_NAME_EX`).
const String _methodNameEx = '(?:$_ident$_methodSuffix?|$_methodNameOperator)';

/// Method names after `.`/`::` (port of `METHOD_AFTER_DOT`).
const String _methodAfterDot = '(?:$_ident[?!]?|$_methodNameOperator)';

/// Port of `INSTANCE_VARIABLE`, `CLASS_VARIABLE`, `OBJECT_VARIABLE`.
const String _instanceVariable = '@$_ident';
const String _classVariable = '@@$_ident';
const String _objectVariable = '@@?$_ident';

/// Port of `GLOBAL_VARIABLE`.
const String _globalVariable =
    r'\$(?:'
    '$_ident'
    r'|[1-9]\d*|0\w*|[~&+`'
    "'"
    r'=/,;_.<>!@$?*":\\]|-[a-zA-Z_0-9])';

/// Port of `PREFIX_VARIABLE` and `METHOD_NAME_OR_SYMBOL`.
const String _prefixVariable = '(?:$_globalVariable|$_objectVariable)';
const String _symbol =
    ':(?:$_methodNameEx|$_prefixVariable|['
    "'"
    '"]'
    ')';
const String _methodNameOrSymbol = '(?:$_methodNameEx|$_symbol)';

/// Port of `DECIMAL`, `OCTAL`, `HEXADECIMAL`, `BINARY`, `EXPONENT`,
/// `FLOAT_SUFFIX`, `FLOAT_OR_INT` and `NUMERIC`.
const String _decimal = r'\d+(?:_\d+)*';
const String _octal = '0_?[0-7]+(?:_[0-7]+)*';
const String _hexadecimal = '0x[0-9A-Fa-f]+(?:_[0-9A-Fa-f]+)*';
const String _binary = '0b[01]+(?:_[01]+)*';
const String _exponent = '[eE][+-]?$_decimal';
const String _floatSuffix = '(?:$_exponent|\\.$_decimal(?:$_exponent)?)';
const String _floatOrInt = '$_decimal(?:$_floatSuffix())?';
const String _numeric =
    '(?:(?=0)(?:$_octal|$_hexadecimal|$_binary)|$_floatOrInt)';

/// Port of `SIMPLE_ESCAPE`, `CONTROL_META_ESCAPE`, `ESCAPE` and `CHARACTER`.
const String _simpleEscape = '[abefnrstv]|[0-7]{1,3}|x[0-9A-Fa-f]{1,2}|.';
const String _controlMetaEscape =
    '(?:M-|C-|c)(?:\\\\(?:M-|C-|c))*(?:[^\\\\]|\\\\(?:$_simpleEscape))?';
const String _escape = '(?:$_controlMetaEscape|$_simpleEscape)';
const String _character = '\\?(?:[^\\s\\\\]|\\\\(?:$_escape))';

/// Port of `HEREDOC_OPEN` (groups: 1 = `-`/`~`, 2 = bare delimiter,
/// 3 = quote, 4 = quoted delimiter).
const String _heredocOpen =
    '<<([-~])?(?:([A-Za-z_0-9]+)|(["'
    "'"
    r'`/])([^\n]*?)\3)';

/// Absolute end of input (`(?![\s\S])` matches only at the very end).
const String _absoluteEnd = r'(?![\s\S])';

/// Port of `\Z`: end of input, tolerating one trailing newline.
const String _endOfStringOrBeforeTrailingNewline = '(?=\\n?$_absoluteEnd)';

/// Port of `RUBYDOC`, `DATA` and `RUBYDOC_OR_DATA`.
const String _rubydoc =
    '=begin(?!\\S).*?(?:$_endOfStringOrBeforeTrailingNewline|^=end(?!\\S)[^\\n]*)';
const String _dataContent =
    '__END__'
    r'$'
    '.*?(?:$_endOfStringOrBeforeTrailingNewline|(?=^#CODE))';
const String _rubydocOrData = '(?:$_rubydoc|$_dataContent)';

/// Port of `VALUE_FOLLOWS` (atomicity proven equivalent to greedy; see the
/// library documentation).
const String _valueFollows =
    '[ \\t\\f\\v]+(?:[%/][^\\s=]|<<-?\\S|[-+]\\d|$_character)';

/// Port of `FANCY_STRING_START` (groups: 1 = kind letter or empty,
/// 2 = delimiter).
const String _fancyStringStart = '%([iIqQrswWx]|(?![a-zA-Z0-9]))([^a-zA-Z0-9])';

/// Port of `StringState.simple_key_pattern` for `'`, with the original's
/// atomic `(?>...)` unrolled into `A*(?:B A*)*` (same language, linear
/// time; a naive greedy port backtracks exponentially — see the library
/// documentation).
const String _simpleKeySingle = r"[^\\']*(?:\\.[^\\']*)*':";

/// Port of `StringState.simple_key_pattern` for `"`, unrolled like
/// [_simpleKeySingle]. The `#` alternatives additionally encode the
/// original's ordered first-win choice (`#$"`/`#$\` and `#{...}` win over
/// a bare `#`, which can never start where they match), so no
/// backtracking can revisit an earlier iteration's choice.
const String _simpleKeyDouble =
    r'[^\\"#]*(?:(?:\\.|#\$["\\]|#\{[^{}]+\}|#(?!\{)(?!\$["\\]))[^\\"#]*)*":';

// ---------------------------------------------------------------------------
// Compiled patterns.
// ---------------------------------------------------------------------------
//
// Every pattern compiles with `unicode: true` (code-point semantics, as in
// Ruby). `dotAll` is set exactly where the original carries `/m` AND the
// pattern contains a `.` whose behavior it changes; `multiLine` is set
// exactly where the pattern contains `^`/`$` (always line anchors in Ruby).

/// Runs of spaces and tabs (the original also covers form feeds and
/// vertical tabs).
final RegExp _spacesRe = RegExp(r'[ \t\f\v]+', unicode: true);

/// A single newline.
final RegExp _newlineRe = RegExp(r'\n', unicode: true);

/// A backslash-newline continuation.
final RegExp _backslashNewlineRe = RegExp(r'\\\n', unicode: true);

/// An end-of-line comment (away from the start of a line).
final RegExp _commentRe = RegExp('#.*', unicode: true);

/// A `#` comment at the start of a line (group 1: the `!` of a shebang).
final RegExp _commentBolRe = RegExp('#(!)?.*', unicode: true);

/// Embedded documentation and `__END__` data sections.
final RegExp _rubydocOrDataRe = RegExp(
  _rubydocOrData,
  unicode: true,
  dotAll: true,
  multiLine: true,
);

/// A method name or keyword (port of `METHOD_NAME`).
final RegExp _methodNameRe = RegExp('$_ident[?!]?', unicode: true);

/// A method name after `.`/`::` (port of `METHOD_AFTER_DOT`).
final RegExp _methodAfterDotRe = RegExp(_methodAfterDot, unicode: true);

/// Dots, colons and brackets (groups 1 and 2 steer the follow-up state).
final RegExp _operatorsRe = RegExp(
  // Group 1 is `.`/`::`; group 2 the value-opening operators. The closers
  // are deliberately ungrouped (as in the original): only group 2 sets
  // `valueExpected`, so `)`/`]`/`}` leave it false.
  r'(\.(?!\.)|::)|(\.\.\.?|==?=?|[,(\[{])|[)\]}]',
  unicode: true,
);

/// A symbol literal (port of `SYMBOL`).
final RegExp _symbolRe = RegExp(_symbol, unicode: true);

/// A complete single- or double-quoted string without escapes, or a lone
/// opening quote (multiline strings continue in [_RubyStringState]).
final RegExp _stringsRe = RegExp(
  r"'(?:[^'\\]*')?"
  '|'
  r'"(?:[^"\\#]*")?',
  unicode: true,
);

/// An instance variable (port of `INSTANCE_VARIABLE`).
final RegExp _instanceVariableRe = RegExp(_instanceVariable, unicode: true);

/// A forward slash (opens a regexp when a value is expected).
final RegExp _slashRe = RegExp('/', unicode: true);

/// A numeric literal, with an optional sign when a value is expected
/// (group 1 is set exactly for floats, via the `()` in `FLOAT_OR_INT`).
final RegExp _numericSignedRe = RegExp('[-+]?$_numeric', unicode: true);

/// A numeric literal without a sign.
final RegExp _numericPlainRe = RegExp(_numeric, unicode: true);

/// Assignment and logic operators.
final RegExp _operators2Re = RegExp(
  r'[-+!~^/]=?|[:;]|&\.|[*|&]{1,2}=?|>>?',
  unicode: true,
);

/// A heredoc opener (port of `HEREDOC_OPEN`).
final RegExp _heredocOpenRe = RegExp(_heredocOpen, unicode: true);

/// A `%`-style string/symbol/regexp/shell opener (port of
/// `FANCY_STRING_START`; group 1 is the kind letter or empty, group 2 the
/// delimiter).
final RegExp _fancyStringStartRe = RegExp(_fancyStringStart, unicode: true);

/// A `?x` character literal (port of `CHARACTER`).
final RegExp _characterRe = RegExp(_character, unicode: true, dotAll: true);

/// `%`, `<` and `?` operators.
final RegExp _percentRe = RegExp(r'%=?|<(?:<|=>?)?|\?', unicode: true);

/// A backtick (opens a shell string).
final RegExp _backtickRe = RegExp('`', unicode: true);

/// A global variable (port of `GLOBAL_VARIABLE`).
final RegExp _globalVariableRe = RegExp(_globalVariable, unicode: true);

/// A class variable (port of `CLASS_VARIABLE`).
final RegExp _classVariableRe = RegExp(_classVariable, unicode: true);

/// A colon that does not start `::` (completes an ident `key:` token).
final RegExp _colonNotColonRe = RegExp(':(?!:)', unicode: true);

/// A plain colon (completes a complete-string `key:` token; unlike the
/// ident rule, the original scans `/:/` here, so `"s"::sym` keys on the
/// first colon and leaves `:sym` for the symbol rule).
final RegExp _colonRe = RegExp(':', unicode: true);

/// A value-shaped token after spaces (port of `VALUE_FOLLOWS`).
final RegExp _valueFollowsRe = RegExp(
  _valueFollows,
  unicode: true,
  dotAll: true,
);

/// An extended method name (port of `METHOD_NAME_EX`).
///
/// Used with manual atomic emulation (see [scanRubyTokens]): the match is
/// greedy, then the scan fails outright when `.` or `::` follows.
final RegExp _methodNameExRe = RegExp(_methodNameEx, unicode: true);

/// A dot or double colon.
final RegExp _dotOrColonColonRe = RegExp(r'\.|::', unicode: true);

/// A dotted class or module path (port of `(?:IDENT::)* IDENT`).
final RegExp _moduleNameRe = RegExp('(?:$_ident::)*$_ident', unicode: true);

/// A double left angle (the `<<` of `class << self`).
final RegExp _lshiftRe = RegExp('<<', unicode: true);

/// A comma (separates `undef` names).
final RegExp _undefCommaRe = RegExp(',', unicode: true);

/// An `alias` pair (groups 1-3: name, spaces, name).
final RegExp _aliasRe = RegExp(
  '($_methodNameOrSymbol)([ \t]+)($_methodNameOrSymbol)',
  unicode: true,
);

/// A string escape sequence (port of `ESCAPE`).
final RegExp _escapeRe = RegExp(_escape, unicode: true, dotAll: true);

/// Regexp modifiers (port of `REGEXP_MODIFIERS`; matches empty).
final RegExp _regexpModifiersRe = RegExp('[mousenix]*', unicode: true);

/// The `rational` and `imaginary` numeric suffixes.
final RegExp _rSuffixRe = RegExp('r', unicode: true);
final RegExp _iSuffixRe = RegExp('i', unicode: true);

/// A quoted hash key that continues after the opening quote (port of
/// `StringState.simple_key_pattern`).
final RegExp _simpleKeySingleRe = RegExp(
  _simpleKeySingle,
  unicode: true,
  dotAll: true,
);
final RegExp _simpleKeyDoubleRe = RegExp(
  _simpleKeyDouble,
  unicode: true,
  dotAll: true,
);

/// An opening parenthesis (tests whether an ident is a method call).
final RegExp _lparenRe = RegExp(r'\(', unicode: true);

/// The letter `e` in either case (tests for a float exponent).
final RegExp _eLetterRe = RegExp('e', unicode: true, caseSensitive: false);

// ---------------------------------------------------------------------------
// Word lists (port of `Ruby::Patterns` tables).
// ---------------------------------------------------------------------------

/// Ruby keywords (port of `KEYWORDS`).
const Set<String> _keywords = <String>{
  'and',
  'def',
  'end',
  'in',
  'or',
  'unless',
  'begin',
  'defined?',
  'ensure',
  'module',
  'redo',
  'super',
  'until',
  'BEGIN',
  'break',
  'do',
  'next',
  'rescue',
  'then',
  'when',
  'END',
  'case',
  'else',
  'for',
  'retry',
  'while',
  'alias',
  'class',
  'elsif',
  'if',
  'not',
  'return',
  'undef',
  'yield',
};

/// Predefined constants (port of `PREDEFINED_CONSTANTS`).
const Set<String> _predefinedConstants = <String>{
  'nil',
  'true',
  'false',
  'self',
  'DATA',
  'ARGV',
  'ARGF',
  'ENV',
  'FALSE',
  'TRUE',
  'NIL',
  'STDERR',
  'STDIN',
  'STDOUT',
  'TOPLEVEL_BINDING',
  'RUBY_COPYRIGHT',
  'RUBY_DESCRIPTION',
  'RUBY_ENGINE',
  'RUBY_PATCHLEVEL',
  'RUBY_PLATFORM',
  'RUBY_RELEASE_DATE',
  'RUBY_REVISION',
  'RUBY_VERSION',
  '__FILE__',
  '__LINE__',
  '__ENCODING__',
};

/// State entered after `def`/`undef`/`alias`/`class`/`module`
/// (port of `KEYWORD_NEW_STATE`; anything else stays `:initial`).
const Map<String, _SymbolState> _keywordNewState = <String, _SymbolState>{
  'def': _SymbolState.defExpected,
  'undef': _SymbolState.undefExpected,
  'alias': _SymbolState.aliasExpected,
  'class': _SymbolState.moduleExpected,
  'module': _SymbolState.moduleExpected,
};

/// Keywords after which a value is expected (port of
/// `KEYWORDS_EXPECTING_VALUE`).
const Set<String> _keywordsExpectingValue = <String>{
  'and',
  'end',
  'in',
  'or',
  'unless',
  'begin',
  'defined?',
  'ensure',
  'redo',
  'super',
  'until',
  'break',
  'do',
  'next',
  'rescue',
  'then',
  'when',
  'case',
  'else',
  'for',
  'retry',
  'while',
  'elsif',
  'if',
  'not',
  'return',
  'yield',
};

/// Token kind selected by a `%` kind letter (port of `FANCY_STRING_KIND`;
/// anything else is a string).
const Map<String, String> _fancyStringKind = <String, String>{
  'i': 'symbol',
  'I': 'symbol',
  'r': 'regexp',
  's': 'symbol',
  'x': 'shell',
};

/// `%` kind letters that disable interpolation (port of
/// `FANCY_STRING_INTERPRETED`, inverted: everything else interpolates).
const Set<String> _fancyStringNotInterpreted = <String>{'i', 'q', 's', 'w'};

/// Token kind selected by a heredoc quote character (port of
/// `QUOTE_TO_TYPE`; anything else, including no quote, is a string).
const Map<String, String> _quoteToType = <String, String>{
  '`': 'shell',
  '/': 'regexp',
};

/// Closing partner of an opening string delimiter (port of
/// `StringState::CLOSING_PAREN`).
const Map<String, String> _closingParen = <String, String>{
  '(': ')',
  '[': ']',
  '<': '>',
  '{': '}',
};

// ---------------------------------------------------------------------------
// String state (port of `Ruby::StringState`).
// ---------------------------------------------------------------------------

/// How a heredoc terminator line is recognized.
enum _HeredocMode {
  /// The terminator must start the line (`<<E`).
  linestart,

  /// The terminator may be indented (`<<-E` and `<<~E`, which the original
  /// treats identically).
  indented,
}

/// Tracks an open string-like token while its content is scanned.
///
/// Port of `Ruby::StringState`. Instead of the original's lookahead
/// `pattern` regexes, content scanning is implemented directly in
/// [scanContent]: plain strings stop at a fixed character set (exactly the
/// original's character class), while heredoc terminators are matched
/// possessively by hand (the original's atomic `(?>[ \t]*)` is NOT
/// equivalent to greedy matching for quoted delimiters with leading
/// spaces, so a regex translation would diverge).
class _RubyStringState {
  /// Creates a string state for a token of [type].
  ///
  /// [interpreted] enables escapes and `#{}` interpolation, [delimiter] is
  /// the closing delimiter (or the heredoc terminator when [heredoc] is
  /// set). A delimiter with a closing partner (`(`, `[`, `<`, `{`) tracks
  /// nesting depth via [parenDepth].
  _RubyStringState(
    this.type,
    this.interpreted,
    String delimiter, [
    _HeredocMode? heredoc,
  ]) : heredoc = heredoc,
       nextState = _SymbolState.initial {
    if (heredoc != null) {
      heredocDelim = delimiter;
    } else {
      final closer = _closingParen[delimiter];
      if (closer != null) {
        openingParen = delimiter;
        delim = closer;
        parenDepth = 1;
      } else {
        delim = delimiter;
      }
    }
  }

  /// The token kind of the string (`string`, `symbol`, `regexp`, `shell`
  /// or `key`).
  final String type;

  /// Whether escapes and interpolation are processed.
  final bool interpreted;

  /// The closing delimiter, or `null` for heredocs (see [heredocDelim]).
  String? delim;

  /// The heredoc terminator recognition mode, or `null` for plain strings.
  final _HeredocMode? heredoc;

  /// The heredoc terminator (only when [heredoc] is set).
  String? heredocDelim;

  /// The opening delimiter when it differs from [delim] (`(`/`[`/`<`/`{`
  /// openers), otherwise `null`.
  String? openingParen;

  /// The current nesting depth for paired delimiters, otherwise `null`.
  int? parenDepth;

  /// The symbol state to return to when the string closes (overridden to
  /// [undefCommaExpected][_SymbolState] for `undef :"..."` names).
  _SymbolState nextState;

  /// Scans string content up to the next delimiter, escape, interpolation
  /// or heredoc terminator.
  ///
  /// Advances [scanner] past the returned text and reports it with
  /// [_RubyStringContent.text]; [_RubyStringContent.heredocEnded] mirrors the
  /// original `self[1]` capture (set exactly when a heredoc terminator was
  /// found). When nothing special follows, the rest of the input is
  /// consumed (the original's `scan_until(...) || scan_rest`).
  _RubyStringContent scanContent(CodeRayStringScanner scanner) {
    final input = scanner.string;
    final pos = scanner.pos;
    final end = input.length;
    if (heredoc != null) {
      final stop = _heredocStop(input, pos, end);
      final text = input.substring(pos, stop.position);
      scanner.consume(stop.position - pos);
      return _RubyStringContent(text, stop.terminatorFound);
    }
    final stopAt = _stopCharacters();
    final hashInterpolates = interpreted && delim != '#';
    var i = pos;
    while (i < end) {
      final unit = input.codeUnitAt(i);
      final char = input[i];
      if (stopAt.contains(char)) break;
      if (hashInterpolates &&
          unit == 0x23 &&
          i + 1 < end &&
          _interpolationIntroducer(input.codeUnitAt(i + 1))) {
        break;
      }
      i++;
    }
    final text = input.substring(pos, i);
    scanner.consume(i - pos);
    return _RubyStringContent(text, false);
  }

  /// The characters plain-string content stops at (the original's
  /// `STRING_PATTERN` character class: the delimiter, its opening partner
  /// if any, and the backslash unless the delimiter is one itself).
  Set<String> _stopCharacters() {
    final stopAt = <String>{delim!};
    if (openingParen != null) stopAt.add(openingParen!);
    if (delim != r'\') stopAt.add(r'\');
    return stopAt;
  }

  /// Finds where heredoc content scanning stops at or after [pos].
  ///
  /// Mirrors `scan_until` over the original's heredoc pattern: the
  /// terminator alternative is tried possessively (spaces are munched
  /// greedily and never given back), competing with the backslash and
  /// interpolation alternatives. The terminator match position is the
  /// newline that precedes the terminator line (or [pos] itself for the
  /// `\A` branch), exactly like the original's zero-width lookahead.
  ///
  /// NOTE `StringScanner` matches against the unscanned rest, so the
  /// original's `\A` anchors at the scan position — verified against the
  /// oracle (`StringScanner#scan_until` with `/\A/` matches at any
  /// position). The `\A` terminator branch is therefore tried at [pos],
  /// not at offset zero.
  _HeredocStop _heredocStop(String input, int pos, int end) {
    final delim = heredocDelim!;
    final indented = heredoc == _HeredocMode.indented;
    // The `\A` branch: the terminator line starts right at the scan
    // position. Tried before the backslash and interpolation alternatives
    // below, like the original's first alternative (a quoted delimiter
    // can start with `\` or `#`, so the order is observable).
    if (_terminatorAt(input, pos, end, delim, indented)) {
      return _HeredocStop(pos, true);
    }
    var i = pos;
    while (i < end) {
      final unit = input.codeUnitAt(i);
      if (unit == 0x5C) {
        return _HeredocStop(i, false); // backslash
      }
      if (interpreted &&
          unit == 0x23 &&
          i + 1 < end &&
          _interpolationIntroducer(input.codeUnitAt(i + 1))) {
        return _HeredocStop(i, false);
      }
      if (unit == 0x0A && _terminatorAt(input, i + 1, end, delim, indented)) {
        return _HeredocStop(i, true);
      }
      i++;
    }
    return _HeredocStop(end, false);
  }

  /// Whether the terminator line starts at [j] (spaces munched
  /// possessively for indented heredocs, then the delimiter, then a line
  /// end — the `$` of the original terminator pattern).
  bool _terminatorAt(
    String input,
    int j,
    int end,
    String delim,
    bool indented,
  ) {
    var k = j;
    if (indented) {
      while (k < end) {
        final unit = input.codeUnitAt(k);
        if (unit != 0x20 && unit != 0x09) break;
        k++;
      }
    }
    if (!input.startsWith(delim, k)) return false;
    final after = k + delim.length;
    return after == end || input.codeUnitAt(after) == 0x0A;
  }
}

/// Whether [unit] (`{`, `$` or `@`) starts an interpolation after `#`.
bool _interpolationIntroducer(int unit) =>
    unit == 0x7B || unit == 0x24 || unit == 0x40;

/// One [_RubyStringState.scanContent] result.
class _RubyStringContent {
  /// Creates a content result.
  const _RubyStringContent(this.text, this.heredocEnded);

  /// The scanned content (empty when already at a delimiter).
  final String text;

  /// Whether a heredoc terminator follows (the original's `self[1]`).
  final bool heredocEnded;
}

/// A heredoc content stop: [position] with [terminatorFound].
class _HeredocStop {
  /// Creates a heredoc stop.
  const _HeredocStop(this.position, this.terminatorFound);

  /// The offset scanning stops at.
  final int position;

  /// Whether a heredoc terminator was found there.
  final bool terminatorFound;
}

// ---------------------------------------------------------------------------
// Scanner (port of `Ruby#scan_tokens`).
// ---------------------------------------------------------------------------

/// Scans Ruby [source] into [sink], starting in `:initial` state.
///
/// Port of `CodeRay::Scanners::Ruby#scan_tokens`. The branch structure
/// follows the original line by line; see the inline notes for the few
/// spots where Dart needs a different shape for identical behavior.
void scanRubyTokens(String source, CoderayTokenSink sink) {
  final s = CodeRayStringScanner(source);
  Object state = _SymbolState.initial;
  Object? lastState;
  String? methodCallExpected;
  Object? valueExpected = true;
  List<({_RubyStringState state, int depth, List<_RubyStringState>? heredocs})>?
  inlineStack;
  var inlineCurlyDepth = 0;
  List<_RubyStringState>? heredocs;

  while (!s.eos) {
    final current = state;
    if (current is _RubyStringState) {
      // ------------------------------------------------ String state ---
      final content = current.scanContent(s);
      if (content.text.isNotEmpty) {
        sink.textToken(content.text, 'content');
        if (s.eos) break;
      }
      if (current.heredoc != null && content.heredocEnded) {
        var terminator = s.getch() ?? '';
        if (!s.eos) terminator += _scanToEndOfLine(s);
        if (terminator.isNotEmpty) {
          sink.textToken(terminator, 'delimiter');
        }
        sink.endGroup(current.type);
        state = current.nextState;
        continue;
      }
      final ch = s.getch();
      if (ch == null) break; // Unreachable: content scan left input behind.
      final delim = current.delim;
      if (delim != null && ch == delim) {
        if (current.parenDepth != null) {
          current.parenDepth = current.parenDepth! - 1;
          if (current.parenDepth! > 0) {
            sink.textToken(ch, 'content');
            continue;
          }
        }
        sink.textToken(ch, 'delimiter');
        if (current.type == 'regexp' && !s.eos) {
          final modifiers = s.scan(_regexpModifiersRe);
          if (modifiers != null && modifiers.isNotEmpty) {
            sink.textToken(modifiers, 'modifier');
          }
        }
        sink.endGroup(current.type);
        valueExpected = false;
        state = current.nextState;
      } else if (ch == r'\') {
        if (current.interpreted) {
          final esc = s.scan(_escapeRe);
          if (esc != null) {
            sink.textToken(ch + esc, 'char');
          } else {
            sink.textToken(ch, 'error');
          }
        } else {
          final esc = s.getch();
          if (esc == null) {
            sink.textToken(ch, 'content');
          } else if (esc == current.delim || esc == r'\') {
            sink.textToken(ch + esc, 'char');
          } else {
            sink.textToken(ch + esc, 'content');
          }
        }
      } else if (ch == '#') {
        final next = s.peek(1);
        if (next == '{') {
          (inlineStack ??= []).add((
            state: current,
            depth: inlineCurlyDepth,
            heredocs: heredocs,
          ));
          valueExpected = true;
          state = _SymbolState.initial;
          inlineCurlyDepth = 1;
          sink.beginGroup('inline');
          sink.textToken(ch + s.getch()!, 'inline_delimiter');
        } else if (next == r'$' || next == '@') {
          sink.textToken(ch, 'escape');
          lastState = current;
          state = _SymbolState.initial;
        } else {
          // Unreachable: content scanning only stops at `#` before
          // `{`, `$` or `@` (the original raises here too).
          throw StateError('Ruby scanner: unexpected $next after #.');
        }
      } else if (current.openingParen != null && ch == current.openingParen) {
        current.parenDepth = current.parenDepth! + 1;
        sink.textToken(ch, 'content');
      } else {
        // Unreachable: content scanning only stops at a handled
        // character (the original raises here too).
        throw StateError('Ruby scanner: unexpected $ch in string.');
      }
    } else if (s.scan(_spacesRe) case final space?) {
      // -------------------------------------------------- Whitespace ---
      sink.textToken(space, 'space');
    } else if (s.scan(_newlineRe) case final newline?) {
      if (heredocs != null) {
        // Heredoc scanning needs the newline back at the start.
        s.unscan();
        final next = heredocs.removeAt(0);
        state = next;
        sink.beginGroup(next.type);
        if (heredocs.isEmpty) heredocs = null;
      } else {
        if (current == _SymbolState.undefCommaExpected) {
          state = _SymbolState.initial;
        }
        sink.textToken(newline, 'space');
        valueExpected = true;
      }
    } else if (_scanCommentText(s) case final comment?) {
      // ----------------------------------------------------- Comment ---
      sink.textToken(comment.text, comment.doctype ? 'doctype' : 'comment');
    } else if (s.scan(_backslashNewlineRe) case final backslashNl?) {
      // ----------------------------------------- Backslash newline ---
      if (heredocs != null) {
        // Heredoc scanning needs the newline back at the start.
        s.unscan();
        sink.textToken(s.getch()!, 'space');
        final next = heredocs.removeAt(0);
        state = next;
        sink.beginGroup(next.type);
        if (heredocs.isEmpty) heredocs = null;
      } else {
        sink.textToken(backslashNl, 'space');
      }
    } else if (current == _SymbolState.initial) {
      // ------------------------------------------------------ Initial ---
      if (methodCallExpected == null ? s.scan(_methodNameRe) : null
          case final name?) {
        var kind = _identKind(name);
        if (valueExpected != _colonExpected &&
            s.scan(_colonNotColonRe) != null) {
          valueExpected = true;
          sink.textToken(name, 'key');
          sink.textToken(':', 'operator');
        } else {
          valueExpected = false;
          if (kind == 'ident') {
            if (_startsUppercase(name) &&
                !_endsWithBangOrQuestion(name) &&
                s.check(_lparenRe) == null) {
              kind = 'constant';
            }
          } else if (kind == 'keyword') {
            state = _keywordNewState[name] ?? _SymbolState.initial;
            if (_keywordsExpectingValue.contains(name)) {
              valueExpected = name == 'when' ? _colonExpected : true;
            }
          }
          if (!_valueTruthy(valueExpected) &&
              s.check(_valueFollowsRe) != null) {
            valueExpected = true;
          }
          sink.textToken(name, kind);
        }
      } else if (methodCallExpected != null ? s.scan(_methodAfterDotRe) : null
          case final afterDot?) {
        if (methodCallExpected == '::' &&
            _startsUppercase(afterDot) &&
            s.check(_lparenRe) == null) {
          sink.textToken(afterDot, 'constant');
        } else {
          sink.textToken(afterDot, 'ident');
        }
        methodCallExpected = null;
        valueExpected = s.check(_valueFollowsRe);
      } else if (methodCallExpected == null ? s.scan(_operatorsRe) : null
          case final op?) {
        methodCallExpected = s.capture(1);
        valueExpected = methodCallExpected == null && s.capture(2) != null;
        if (inlineStack != null) {
          if (op == '{') {
            inlineCurlyDepth++;
          } else if (op == '}') {
            inlineCurlyDepth--;
            if (inlineCurlyDepth == 0) {
              // Closing brace of an inline block reached.
              final frame = inlineStack.removeLast();
              state = frame.state;
              inlineCurlyDepth = frame.depth;
              heredocs = frame.heredocs;
              if (inlineStack.isEmpty) inlineStack = null;
              if (heredocs != null && heredocs.isEmpty) heredocs = null;
              sink.textToken(op, 'inline_delimiter');
              sink.endGroup('inline');
              continue;
            }
          }
        }
        sink.textToken(op, 'operator');
      } else if (s.scan(_symbolRe) case final sym?) {
        final second = sym.length > 1 ? sym[1] : '';
        if (second == "'" || second == '"') {
          sink.beginGroup('symbol');
          sink.textToken(':', 'symbol');
          sink.textToken(second, 'delimiter');
          state = _RubyStringState('symbol', second == '"', second);
        } else {
          sink.textToken(sym, 'symbol');
          valueExpected = false;
        }
      } else if (s.scan(_stringsRe) case final str?) {
        if (str.length == 1) {
          final kind =
              s.check(str == '"' ? _simpleKeyDoubleRe : _simpleKeySingleRe) !=
                  null
              ? 'key'
              : 'string';
          sink.beginGroup(kind);
          sink.textToken(str, 'delimiter');
          // Important for streaming: the state carries the quote.
          state = _RubyStringState(kind, str == '"', str);
        } else {
          final isKey = valueExpected == true && s.scan(_colonRe) != null;
          final kind = isKey ? 'key' : 'string';
          sink.beginGroup(kind);
          sink.textToken(str.substring(0, 1), 'delimiter');
          if (str.length > 2) {
            sink.textToken(str.substring(1, str.length - 1), 'content');
          }
          sink.textToken(str.substring(str.length - 1), 'delimiter');
          sink.endGroup(kind);
          if (isKey) sink.textToken(':', 'operator');
          valueExpected = false;
        }
      } else if (s.scan(_instanceVariableRe) case final ivar?) {
        valueExpected = false;
        sink.textToken(ivar, 'instance_variable');
      } else if (_valueTruthy(valueExpected) ? s.scan(_slashRe) : null
          case final slash?) {
        sink.beginGroup('regexp');
        sink.textToken(slash, 'delimiter');
        state = _RubyStringState('regexp', true, '/');
      } else if (s.scan(
            _valueTruthy(valueExpected) ? _numericSignedRe : _numericPlainRe,
          )
          case var num?) {
        if (methodCallExpected != null) {
          sink.textToken(num, 'error');
          methodCallExpected = null;
        } else {
          final kind = s.capture(1) != null ? 'float' : 'integer';
          if (!_eLetterRe.hasMatch(num) && s.scan(_rSuffixRe) != null) {
            num += 'r';
          }
          if (s.scan(_iSuffixRe) != null) num += 'i';
          sink.textToken(num, kind);
        }
        valueExpected = false;
      } else if (s.scan(_operators2Re) case final op2?) {
        valueExpected = true;
        sink.textToken(op2, 'operator');
      } else if (_valueTruthy(valueExpected) ? s.scan(_heredocOpenRe) : null
          case final heredoc?) {
        final quote = s.capture(3);
        final delim = quote != null ? s.capture(4)! : s.capture(2)!;
        final kind = _quoteToType[quote] ?? 'string';
        sink.beginGroup(kind);
        sink.textToken(heredoc, 'delimiter');
        sink.endGroup(kind);
        // Create the heredoc queue when empty.
        (heredocs ??= []).add(
          _RubyStringState(
            kind,
            quote != "'",
            delim,
            s.capture(1) != null
                ? _HeredocMode.indented
                : _HeredocMode.linestart,
          ),
        );
        valueExpected = false;
      } else if (_valueTruthy(valueExpected)
              ? s.scan(_fancyStringStartRe)
              : null
          case final fancy?) {
        final letter = s.capture(1)!;
        final kind = _fancyStringKind[letter] ?? 'string';
        sink.beginGroup(kind);
        state = _RubyStringState(
          kind,
          !_fancyStringNotInterpreted.contains(letter),
          s.capture(2)!,
        );
        sink.textToken(fancy, 'delimiter');
      } else if (_valueTruthy(valueExpected) ? s.scan(_characterRe) : null
          case final char?) {
        valueExpected = false;
        sink.textToken(char, 'integer');
      } else if (s.scan(_percentRe) case final percent?) {
        valueExpected = percent == '?' ? _colonExpected : true;
        sink.textToken(percent, 'operator');
      } else if (s.scan(_backtickRe) case final tick?) {
        sink.beginGroup('shell');
        sink.textToken(tick, 'delimiter');
        state = _RubyStringState('shell', true, tick);
      } else if (s.scan(_globalVariableRe) case final gvar?) {
        sink.textToken(gvar, 'global_variable');
        valueExpected = false;
      } else if (s.scan(_classVariableRe) case final cvar?) {
        sink.textToken(cvar, 'class_variable');
        valueExpected = false;
      } else if (_scanTrailingBackslash(s)) {
        sink.textToken(s.getch()!, 'space');
      } else {
        if (methodCallExpected != null) {
          methodCallExpected = null;
          continue;
        }
        // The original retries with `unicode` here when unset; the port
        // always scans Unicode-aware, so anything left is an error token.
        sink.textToken(s.getch()!, 'error');
      }
      if (lastState != null) {
        // A simple `def"` would otherwise leave tokens unclosed.
        if (state is! _RubyStringState) state = lastState;
        lastState = null;
      }
    } else if (current == _SymbolState.defExpected) {
      // -------------------------------------------------- Def expected ---
      final name = _scanAtomicMethodName(s);
      if (name != null) {
        sink.textToken(name, 'method');
        state = _SymbolState.initial;
      } else {
        lastState = _SymbolState.dotExpected;
        state = _SymbolState.initial;
      }
    } else if (current == _SymbolState.dotExpected) {
      // -------------------------------------------------- Dot expected ---
      final dot = s.scan(_dotOrColonColonRe);
      if (dot != null) {
        // Invalid definition.
        state = _SymbolState.defExpected;
        sink.textToken(dot, 'operator');
      } else {
        state = _SymbolState.initial;
      }
    } else if (current == _SymbolState.moduleExpected) {
      // ----------------------------------------------- Module expected ---
      final shift = s.scan(_lshiftRe);
      if (shift != null) {
        sink.textToken(shift, 'operator');
      } else {
        state = _SymbolState.initial;
        final name = s.scan(_moduleNameRe);
        if (name != null) sink.textToken(name, 'class');
      }
    } else if (current == _SymbolState.undefExpected) {
      // ------------------------------------------------ Undef expected ---
      state = _SymbolState.undefCommaExpected;
      final name = _scanAtomicMethodName(s);
      if (name != null) {
        sink.textToken(name, 'method');
      } else {
        final sym = s.scan(_symbolRe);
        if (sym != null) {
          final second = sym.length > 1 ? sym[1] : '';
          if (second == "'" || second == '"') {
            sink.beginGroup('symbol');
            sink.textToken(':', 'symbol');
            sink.textToken(second, 'delimiter');
            final stringState = _RubyStringState(
              'symbol',
              second == '"',
              second,
            );
            stringState.nextState = _SymbolState.undefCommaExpected;
            state = stringState;
          } else {
            sink.textToken(sym, 'symbol');
          }
        } else {
          state = _SymbolState.initial;
        }
      }
    } else if (current == _SymbolState.undefCommaExpected) {
      // ------------------------------------------ Undef comma expected ---
      final comma = s.scan(_undefCommaRe);
      if (comma != null) {
        sink.textToken(comma, 'operator');
        state = _SymbolState.undefExpected;
      } else {
        state = _SymbolState.initial;
      }
    } else if (current == _SymbolState.aliasExpected) {
      // ------------------------------------------------ Alias expected ---
      final alias = s.scan(_aliasRe);
      if (alias != null) {
        final first = s.capture(1)!;
        final spaces = s.capture(2)!;
        final third = s.capture(3)!;
        sink.textToken(first, first.startsWith(':') ? 'symbol' : 'method');
        sink.textToken(spaces, 'space');
        sink.textToken(third, third.startsWith(':') ? 'symbol' : 'method');
      }
      state = _SymbolState.initial;
    } else {
      // Unreachable: every symbol state is handled above (the original
      // raises here too).
      throw StateError('Ruby scanner: unknown state $current.');
    }
  }

  // Cleaning up.
  final leftover = state;
  if (leftover is _RubyStringState) {
    sink.endGroup(leftover.type);
  }
  if (inlineStack != null) {
    for (final frame in inlineStack.reversed) {
      sink.endGroup('inline');
      sink.endGroup(frame.state.type);
    }
  }
}

/// Scans a comment, shebang, embedded document or `__END__` section.
///
/// Returns the matched text plus whether it is a doctype (`#!...`). At the
/// start of a line a `#` comment wins when the line starts with `#` (the
/// original's alternation order); otherwise embedded documents are tried.
/// Splitting the original's single alternation this way is exactly
/// equivalent (see the library documentation).
({String text, bool doctype})? _scanCommentText(CodeRayStringScanner s) {
  if (s.bol) {
    final hash = s.scan(_commentBolRe);
    if (hash != null) {
      return (text: hash, doctype: s.capture(1) != null);
    }
    final doc = s.scan(_rubydocOrDataRe);
    if (doc != null) return (text: doc, doctype: false);
    return null;
  }
  final hash = s.scan(_commentRe);
  if (hash != null) return (text: hash, doctype: false);
  return null;
}

/// Matches an extended method name atomically, failing outright (without
/// backtracking) when `.` or `::` follows.
///
/// Ports `(?>METHOD_NAME_EX)(?!\.|::)`: the greedy standalone match is
/// identical to the possessive one, so checking the lookahead afterwards
/// and rewinding on failure is exactly equivalent.
String? _scanAtomicMethodName(CodeRayStringScanner s) {
  final match = s.scan(_methodNameExRe);
  if (match == null) return null;
  final rest = s.rest;
  if (rest.startsWith('.') || rest.startsWith('::')) {
    s.unscan();
    s.lastMatch = null;
    return null;
  }
  return match;
}

/// Whether the cursor sits on a backslash at the absolute end of input
/// (port of `/\\\z/`, which Dart cannot spell as a regex).
bool _scanTrailingBackslash(CodeRayStringScanner s) =>
    s.pos == s.string.length - 1 && s.string.codeUnitAt(s.pos) == 0x5C;

/// Scans to the end of the current line without consuming the newline
/// (port of `scan_until(/$/)`).
String _scanToEndOfLine(CodeRayStringScanner s) {
  final newline = s.string.indexOf('\n', s.pos);
  final end = newline == -1 ? s.string.length : newline;
  final text = s.string.substring(s.pos, end);
  s.consume(end - s.pos);
  return text;
}

/// Classifies an identifier (port of `IDENT_KIND`).
String _identKind(String ident) => _keywords.contains(ident)
    ? 'keyword'
    : _predefinedConstants.contains(ident)
    ? 'predefined_constant'
    : 'ident';

/// Whether [ident] starts with an uppercase ASCII letter
/// (port of `match[/\A[A-Z]/]`).
bool _startsUppercase(String ident) {
  final unit = ident.codeUnitAt(0);
  return unit >= 0x41 && unit <= 0x5A;
}

/// Whether [ident] ends with `!` or `?` (port of `match[/[!?]$/]`).
bool _endsWithBangOrQuestion(String ident) =>
    ident.endsWith('!') || ident.endsWith('?');
