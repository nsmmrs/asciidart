/// Top-level constants ported from `lib/asciidoctor.rb`.
///
/// Constants shared across the library: defaults, file extensions, the
/// typographic replacements, the quote patterns and the [Compliance]
/// settings. Constants used by one file live in that file.
library;

import 'dart:math' as math;

import 'package:ptome/src/presence.dart';
import 'package:ptome/src/rx.dart';

/// String for matching the tab character (`TAB`).
const String tab = '\t';

/// Maximum integer value for "boundless" operations (`MAX_INT`).
///
/// Equal to `MAX_SAFE_INTEGER` in JavaScript.
const int maxInt = 9007199254740991;

/// Byte array for the UTF-8 byte order mark (`BOM_BYTES_UTF_8`).
const List<int> bomBytesUtf8 = <int>[0xef, 0xbb, 0xbf];

/// Byte array for the UTF-16LE byte order mark (`BOM_BYTES_UTF_16LE`).
const List<int> bomBytesUtf16le = <int>[0xff, 0xfe];

/// Byte array for the UTF-16BE byte order mark (`BOM_BYTES_UTF_16BE`).
const List<int> bomBytesUtf16be = <int>[0xfe, 0xff];

/// The default document type (`DEFAULT_DOCTYPE`).
const String defaultDoctype = 'article';

/// The default backend (`DEFAULT_BACKEND`).
const String defaultBackend = 'html5';

/// Stylesheet attribute values that select the default stylesheet
/// (`DEFAULT_STYLESHEET_KEYS`).
const Set<String> defaultStylesheetKeys = <String>{'', 'DEFAULT'};

/// The default stylesheet file name (`DEFAULT_STYLESHEET_NAME`).
const String defaultStylesheetName = 'asciidoctor.css';

/// Pointers to the preferred version for a given backend (`BACKEND_ALIASES`).
const Map<String, String> backendAliases = <String, String>{
  'html': 'html5',
  'docbook': 'docbook5',
};

/// Default page widths for calculating absolute widths
/// (`DEFAULT_PAGE_WIDTHS`).
const Map<String, int> defaultPageWidths = <String, int>{'docbook': 425};

/// Default extensions for the respective base backends (`DEFAULT_EXTENSIONS`).
const Map<String, String> defaultExtensions = <String, String>{
  'html': '.html',
  'docbook': '.xml',
  'pdf': '.pdf',
  'epub': '.epub',
  'manpage': '.man',
  'asciidoc': '.adoc',
};

/// File extensions recognized as AsciiDoc documents (`ASCIIDOC_EXTENSIONS`).
const Map<String, bool> asciidocExtensions = <String, bool>{
  '.adoc': true,
  '.asciidoc': true,
  '.asc': true,
  '.ad': true,
  '.txt': true,
};

/// Head of an attribute reference (`{name}`) (`ATTR_REF_HEAD`).
const String attrRefHead = '{';

/// List continuation marker (`LIST_CONTINUATION`).
const String listContinuation = '+';

/// Hard line break suffix (`HARD_LINE_BREAK`).
const String hardLineBreak = ' +';

/// Block math delimiters by stem type (`BLOCK_MATH_DELIMITERS`).
const Map<String, List<String>> blockMathDelimiters = <String, List<String>>{
  'asciimath': <String>[r'\$', r'\$'],
  'latexmath': <String>[r'\[', r'\]'],
};

/// Stem type aliases (`STEM_TYPE_ALIASES`).
///
/// Lookups of unknown types must fall back to `'asciimath'`.
const Map<String, String> stemTypeAliases = <String, String>{
  'latexmath': 'latexmath',
  'latex': 'latexmath',
  'tex': 'latexmath',
};

/// Pinned highlight.js version (`HIGHLIGHT_JS_VERSION`).
const String highlightJsVersion = '9.18.3';

/// Default document attributes (`DEFAULT_ATTRIBUTES`).
const Map<String, String> defaultAttributes = <String, String>{
  'appendix-caption': 'Appendix',
  'appendix-refsig': 'Appendix',
  'caution-caption': 'Caution',
  'chapter-refsig': 'Chapter',
  'example-caption': 'Example',
  'figure-caption': 'Figure',
  'important-caption': 'Important',
  'last-update-label': 'Last updated',
  'note-caption': 'Note',
  'part-refsig': 'Part',
  'prewrap': '',
  'sectids': '',
  'section-refsig': 'Section',
  'table-caption': 'Table',
  'tip-caption': 'Tip',
  'toc-placement': 'auto',
  'toc-title': 'Table of Contents',
  'untitled-label': 'Untitled',
  'version-label': 'Version',
  'warning-caption': 'Warning',
};

/// Attributes that may change throughout the flow of the document
/// (`FLEXIBLE_ATTRIBUTES`).
const List<String> flexibleAttributes = <String>['sectnums'];

/// Intrinsic (built-in) document attributes (`INTRINSIC_ATTRIBUTES`).
const Map<String, String> intrinsicAttributes = <String, String>{
  'startsb': '[',
  'endsb': ']',
  'vbar': '|',
  'caret': '^',
  'asterisk': '*',
  'tilde': '~',
  'plus': '&#43;',
  'backslash': r'\',
  'backtick': '`',
  'blank': '',
  'empty': '',
  'sp': ' ',
  'two-colons': '::',
  'two-semicolons': ';;',
  'nbsp': '&#160;',
  'deg': '&#176;',
  'zwsp': '&#8203;',
  'quot': '&#34;',
  'apos': '&#39;',
  'lsquo': '&#8216;',
  'rsquo': '&#8217;',
  'ldquo': '&#8220;',
  'rdquo': '&#8221;',
  'wj': '&#8288;',
  'brvbar': '&#166;',
  'pp': '&#43;&#43;',
  'cpp': 'C&#43;&#43;',
  'cxx': 'C&#43;&#43;',
  'amp': '&',
  'lt': '<',
  'gt': '>',
};

/// Whether a quote must be bordered by characters that are not word
/// characters (`*strong*`) or may be set within a word (`**strong**`).
enum QuoteScope {
  /// Bordered by non-word characters.
  constrained,

  /// Anywhere, within words too.
  unconstrained,
}

/// What of a replacement rule's match its replacement keeps: nothing
/// (the whole match is replaced), the leading capture, or the leading
/// and trailing captures.
enum ReplacementScope {
  /// The whole match is replaced.
  none,

  /// The first capture, before the replacement, is kept.
  leading,

  /// The first and second captures, around the replacement, are kept.
  bounding,
}

/// One quoted-text substitution rule: a quote [type] (e.g. `'strong'`),
/// a [scope], and the [pattern] that matches it.
///
/// A quote rule: type, scope and pattern; the [guard] lets callers skip
/// the pattern when it cannot match.
class QuoteSub {
  /// Creates a rule with [type], [scope], [pattern] and [guard]; [close]
  /// is the closing delimiter when it differs from [guard].
  const new(this.type, this.scope, this.pattern, this.guard, [String? close])
    : closeGuard = close ?? guard;

  /// The quote type (`'strong'`, `'emphasis'`, `'monospaced'`, ...).
  final String type;

  /// Whether the quote must be bordered by non-word characters.
  final QuoteScope scope;

  /// The pattern matching the quoted span.
  final RegExp pattern;

  /// The opening delimiter, a literal every match of [pattern] contains.
  final String guard;

  /// The closing delimiter, which every match of [pattern] contains after
  /// (and not overlapping) its [guard].
  final String closeGuard;

  /// Whether [text] could contain a match of [pattern].
  ///
  /// Text without the opening delimiter followed by the closing one cannot
  /// match, so the (comparatively slow) regex scan can be skipped; the
  /// result is identical either way.
  bool mayMatch(String text) {
    final open = literalIndexOf(text, guard);
    return open >= 0 &&
        literalIndexOf(text, closeGuard, open + guard.length) >= 0;
  }

  /// [pattern]'s matches, found by trying it only where one can start: a
  /// match holds the opening delimiter after an optional attribute list
  /// (`[...]`) and a prefix of nothing (`^`), one character (a backslash,
  /// or a character that isn't a word character) or `&#8216;`/`&#8220;`.
  AnchoredScan get scan =>
      AnchoredScan(pattern, [guard], before: 7, attributeList: true);
}

/// [inlineLinkRx]'s matches: each holds `://` at most 11 characters after
/// its start (a prefix such as `link:` or `\&lt;`, a backslash, a scheme
/// such as `https`).
final AnchoredScan inlineLinkScan = AnchoredScan(inlineLinkRx, [
  '://',
], before: 11);

/// [inlineLinkMacroRx]'s matches: each starts at `link:` or `mailto:`, or
/// at the backslash escaping it.
final AnchoredScan inlineLinkMacroScan = AnchoredScan(inlineLinkMacroRx, [
  'link:',
  'mailto:',
], before: 1);

/// [inlineXrefMacroRx]'s matches: each starts at `&lt;&lt;` or `xref:`, or
/// at the backslash escaping it.
final AnchoredScan inlineXrefMacroScan = AnchoredScan(inlineXrefMacroRx, [
  '&lt;&lt;',
  'xref:',
], before: 1);

/// [inlineAnchorRx]'s matches: each starts at `[[` or `anchor:`, or at the
/// backslash escaping it.
final AnchoredScan inlineAnchorScan = AnchoredScan(inlineAnchorRx, [
  '[[',
  'anchor:',
], before: 1);

/// [attributeReferenceRx]'s matches: each starts at `{`, or at the
/// backslash escaping it.
final AnchoredScan attributeReferenceScan = AnchoredScan(attributeReferenceRx, [
  '{',
], before: 1);

/// [inlineFootnoteMacroRx]'s matches: each starts at `footnote`, or at
/// the backslash escaping it.
final AnchoredScan inlineFootnoteMacroScan = AnchoredScan(
  inlineFootnoteMacroRx,
  ['footnote'],
  before: 1,
);

/// [inlinePassRx]'s matches, by compat mode: each holds its delimiter
/// (`+` or a backquote) after a prefix character, a bracketed list and a
/// backslash, each optional.
final Map<bool, AnchoredScan> inlinePassScan = {
  false: AnchoredScan(
    inlinePassRx[false]!.pattern,
    ['+', '`'],
    before: 2,
    attributeList: true,
  ),
  true: AnchoredScan(
    inlinePassRx[true]!.pattern,
    ['`'],
    before: 2,
    attributeList: true,
  ),
};

/// [inlineIndextermMacroRx]'s matches: each starts at `indexterm` or
/// `((`, or at the backslash escaping it.
final AnchoredScan inlineIndextermMacroScan = AnchoredScan(
  inlineIndextermMacroRx,
  ['indexterm', '(('],
  before: 1,
);

/// [inlineKbdBtnMacroRx]'s matches: each starts at `kbd:` or `btn:`, or at
/// the backslash escaping it.
final AnchoredScan inlineKbdBtnMacroScan = AnchoredScan(inlineKbdBtnMacroRx, [
  'kbd:',
  'btn:',
], before: 1);

/// [inlineMenuMacroRx]'s matches: each starts at `menu:`, or at the
/// backslash escaping it.
final AnchoredScan inlineMenuMacroScan = AnchoredScan(inlineMenuMacroRx, [
  'menu:',
], before: 1);

/// [inlineMenuRx]'s matches: each starts at a double quote, or at the
/// backslash escaping it.
final AnchoredScan inlineMenuScan = AnchoredScan(inlineMenuRx, [
  '"',
], before: 1);

/// [inlineImageMacroRx]'s matches: each starts at `image:` or `icon:`, or
/// at the backslash escaping it.
final AnchoredScan inlineImageMacroScan = AnchoredScan(inlineImageMacroRx, [
  'image:',
  'icon:',
], before: 1);

/// [inlineStemMacroRx]'s matches: each starts at `stem:`, `latexmath:` or
/// `asciimath:`, or at the backslash escaping it.
final AnchoredScan inlineStemMacroScan = AnchoredScan(inlineStemMacroRx, [
  'stem:',
  'latexmath:',
  'asciimath:',
], before: 1);

/// [inlinePassMacroRx]'s matches: each starts at `pass:` or the backslash
/// escaping it, or holds `++` or `$$` after at most two backslashes and
/// before them an attribute list (`[...]`, no brackets inside) and the
/// backslash escaping it, each optional.
final StartsScan inlinePassMacroScan = StartsScan(
  inlinePassMacroRx,
  _passMacroStarts,
);

List<int> _passMacroStarts(String string, int start) {
  final starts = <int>[];
  void add(int at) {
    if (at >= start) starts.add(at);
  }

  for (
    var at = literalIndexOf(string, 'pass:', start);
    at >= 0;
    at = literalIndexOf(string, 'pass:', at + 1)
  ) {
    add(at - 1);
    add(at);
  }
  for (final literal in const ['++', r'$$']) {
    for (
      var at = literalIndexOf(string, literal, start);
      at >= 0;
      at = literalIndexOf(string, literal, at + 1)
    ) {
      add(at - 2);
      add(at - 1);
      add(at);
      // An attribute list right before the literal or its backslashes.
      var close = at - 1;
      for (var k = 0; k <= 2 && close >= 0; k++) {
        if (string.codeUnitAt(close) == 0x5d) {
          final open = string.lastIndexOf('[', close);
          if (open >= 0 &&
              open < close - 1 &&
              string.indexOf(']', open) == close) {
            add(open - 1);
            add(open);
          }
        }
        if (string.codeUnitAt(close) != 0x5c) break;
        close--;
      }
    }
  }
  return _sortedDistinct(starts);
}

/// [starts] sorted, each once.
List<int> _sortedDistinct(List<int> starts) {
  starts.sort();
  var kept = 0;
  for (final at in starts) {
    if (kept == 0 || starts[kept - 1] != at) starts[kept++] = at;
  }
  return starts..length = kept;
}

/// A pattern's matches, the same as [pattern]'s own, found by trying it
/// (anchored) only where a match can start instead of at every position:
/// many times faster on long text.
///
/// Every match of [pattern] holds one of the [literals], at most [before]
/// characters after its start, or with [attributeList], at most [before]
/// characters before an attribute list (`[...]`, no brackets inside)
/// right in front of the literal (or of a backslash in front of it).
final class AnchoredScan implements Pattern {
  /// The matches of [pattern], whose matches hold one of [literals] as
  /// described.
  new(
    this.pattern,
    this.literals, {
    required this.before,
    this.attributeList = false,
  });

  /// The pattern.
  final RegExp pattern;

  /// The literals one of which every match holds.
  final List<String> literals;

  /// How far before the literal (or its attribute list) a match can start.
  final int before;

  /// Whether an attribute list can come between the start and the literal.
  final bool attributeList;

  /// Where a match can start in [string] from [start], in order.
  List<int> _starts(String string, int start) {
    // (Found in order, and so kept, unless a second literal or an
    // attribute list goes back.)
    final starts = <int>[];
    var last = -1;
    var ordered = true;
    void add(int from) {
      for (var at = math.max(from - before, start); at <= from; at++) {
        if (at == last) continue;
        if (at < last) {
          ordered = false;
        } else {
          last = at;
        }
        starts.add(at);
      }
    }

    for (final literal in literals) {
      for (
        var at = literalIndexOf(string, literal, start);
        at >= 0;
        at = literalIndexOf(string, literal, at + 1)
      ) {
        add(at);
        if (!attributeList) continue;
        // (A backslash can come between the list and the literal.)
        var close = at - 1;
        if (close >= 0 && string.codeUnitAt(close) == 0x5c) close--;
        if (close >= 2 && string.codeUnitAt(close) == 0x5d) {
          final open = string.lastIndexOf('[', close - 2);
          if (open >= 0 && string.indexOf(']', open) == close) add(open);
        }
      }
    }
    return ordered ? starts : _sortedDistinct(starts);
  }

  @override
  List<RegExpMatch> allMatches(String string, [int start = 0]) =>
      matchesFrom(string, start);

  /// The matches in [string] from [start], each found from the end of the
  /// one before; a match [skip] rejects is passed over, and the search goes
  /// on from its next character.
  List<RegExpMatch> matchesFrom(
    String string,
    int start, {
    bool Function(Match match)? skip,
  }) {
    final matches = <RegExpMatch>[];
    var at = start;
    for (final candidate in _starts(string, start)) {
      if (candidate < at) continue;
      final match = pattern.matchAsPrefix(string, candidate) as RegExpMatch?;
      if (match == null) continue;
      if (skip != null && skip(match)) {
        at = candidate + 1;
        continue;
      }
      matches.add(match);
      // (A match holds a literal: never empty.)
      at = match.end;
    }
    return matches;
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) =>
      pattern.matchAsPrefix(string, start);
}

/// A pattern's matches, the same as [pattern]'s own, found by trying it
/// (anchored) only at the positions [starts] gives: every position from
/// `start` on where a match can start, in order, each once.
final class StartsScan implements Pattern {
  /// The matches of [pattern], which start only where [starts] says.
  new(this.pattern, this.starts);

  /// The pattern.
  final RegExp pattern;

  /// Where a match of [pattern] can start in a string from a position.
  final List<int> Function(String string, int start) starts;

  @override
  List<RegExpMatch> allMatches(String string, [int start = 0]) {
    final matches = <RegExpMatch>[];
    var at = start;
    for (final candidate in starts(string, start)) {
      if (candidate < at) continue;
      final match = pattern.matchAsPrefix(string, candidate) as RegExpMatch?;
      if (match == null) continue;
      matches.add(match);
      // (A match is never empty.)
      at = match.end;
    }
    return matches;
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) =>
      pattern.matchAsPrefix(string, start);
}

/// Where the em-dash replacement can match in [string] from [start]: its
/// `--` follows a word character (one or two code units), the `;` of
/// `&#8217;` or `&#8221;`, or the `>` of a closing tag `</...>` (whose
/// start is a `</` after the last `>` before it), with an optional
/// backslash between.
List<int> _emDashStarts(String string, int start) {
  final starts = <int>[];
  void add(int at) {
    if (at >= start) starts.add(at);
  }

  for (
    var dash = literalIndexOf(string, '--', start);
    dash >= 0;
    dash = literalIndexOf(string, '--', dash + 1)
  ) {
    for (final back in const [1, 2, 3, 7, 8]) {
      add(dash - back);
    }
    for (final close in [dash - 1, dash - 2]) {
      if (close < 3 || string.codeUnitAt(close) != 0x3e) continue;
      final after = string.lastIndexOf('>', close - 1) + 1;
      for (
        var open = string.indexOf('</', math.max(after, start));
        open >= 0 && open <= close - 3;
        open = string.indexOf('</', open + 1)
      ) {
        starts.add(open);
      }
    }
  }
  return _sortedDistinct(starts);
}

/// Quoted-text substitution rules for normal mode (`QUOTE_SUBS`false``).
///
/// Patterns are built from the `rx.dart` character-class fragments
/// (`CC_ALL`/`CC_WORD`/`CG_WORD`); flags follow
/// `PORTING-REGEXP.md` (any pattern containing `^` is a [lineRx],
/// any pattern using `\p{...}` gets `unicode: true`).
final List<QuoteSub> _normalQuoteSubs = <QuoteSub>[
  QuoteSub(
    'strong',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt'
      r')?\*\*('
      '$ccAll'
      r'+?)\*\*',
    ),
    '**',
  ),
  QuoteSub(
    'strong',
    QuoteScope.constrained,
    lineRx(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?\*([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])\*(?!'
      '$cgWord)',
      unicode: true,
    ),
    '*',
  ),
  // Curved quotes may stand inside an emphasis's underscores (#2128).
  QuoteSub(
    'double',
    QuoteScope.constrained,
    lineRx(
      '(^|_|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?"`([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])`"(?!(?!_)'
      '$cgWord)',
      unicode: true,
    ),
    '"`',
    '`"',
  ),
  QuoteSub(
    'single',
    QuoteScope.constrained,
    lineRx(
      '(^|_|[^$ccWord;:`}])(?:$quoteAttributeListRxt'
      r")?'`([^ \t\n\v\f\r]|[^ \t\n\v\f\r]"
      '$ccAll'
      r"*?[^ \t\n\v\f\r])`'(?!(?!_)"
      '$cgWord)',
      unicode: true,
    ),
    "'`",
    "`'",
  ),
  QuoteSub(
    'monospaced',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt)?``($ccAll+?)``',
    ),
    '``',
  ),
  QuoteSub(
    'monospaced',
    QuoteScope.constrained,
    lineRx(
      "(^|[^$ccWord;:\"'`}])(?:$quoteAttributeListRxt)?`([^ \\t\\n\\v\\f\\r]|[^ \\t\\n\\v\\f\\r]$ccAll*?[^ \\t\\n\\v\\f\\r])"
      "`(?![$ccWord\"'`])",
      unicode: true,
    ),
    '`',
  ),
  QuoteSub(
    'emphasis',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt)?__($ccAll+?)__',
    ),
    '__',
  ),
  // Emphasis may start right after a curved quote, converted by then to
  // its character reference (#2128).
  QuoteSub(
    'emphasis',
    QuoteScope.constrained,
    lineRx(
      '(^|&#82(?:16|20);|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?_([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])_(?!'
      '$cgWord)',
      unicode: true,
    ),
    '_',
  ),
  QuoteSub(
    'mark',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt)?##($ccAll+?)##',
    ),
    '##',
  ),
  QuoteSub(
    'mark',
    QuoteScope.constrained,
    lineRx(
      '(^|[^$ccWord&;:}])(?:$quoteAttributeListRxt'
      r')?#([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])#(?!'
      '$cgWord)',
      unicode: true,
    ),
    '#',
  ),
  // A bracketed span inside is one unit, so the `^` or `~` of a macro's
  // text (`^link:fn.html[2^]^`) doesn't end the span, which would leave the
  // macro's markup across its end (#4076).
  QuoteSub(
    'superscript',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt'
      r')?\^((?:\[[^ \t\n\v\f\r\]]*\]|[^ \t\n\v\f\r])+?)\^',
    ),
    '^',
  ),
  QuoteSub(
    'subscript',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt'
      r')?~((?:\[[^ \t\n\v\f\r\]]*\]|[^ \t\n\v\f\r])+?)~',
    ),
    '~',
  ),
];

/// Quoted-text substitution rules for compat mode (`QUOTE_SUBS`true``).
///
/// A copy of [_normalQuoteSubs] with the
/// double-quote, single-quote and `+`-monospace entries replaced and the
/// legacy `'`-emphasis entry inserted at index 3 (shared entries reuse the
/// same rule objects).
final List<QuoteSub> _compatQuoteSubs = <QuoteSub>[
  _normalQuoteSubs[0],
  _normalQuoteSubs[1],
  QuoteSub(
    'double',
    QuoteScope.constrained,
    lineRx(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?``([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r"*?[^ \t\n\v\f\r])''(?!"
      '$cgWord)',
      unicode: true,
    ),
    '``',
    "''",
  ),
  QuoteSub(
    'emphasis',
    QuoteScope.constrained,
    lineRx(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r")?'([^ \t\n\v\f\r]|[^ \t\n\v\f\r]"
      '$ccAll'
      r"*?[^ \t\n\v\f\r])'(?!"
      '$cgWord)',
      unicode: true,
    ),
    "'",
  ),
  QuoteSub(
    'single',
    QuoteScope.constrained,
    lineRx(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?`([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r"*?[^ \t\n\v\f\r])'(?!"
      '$cgWord)',
      unicode: true,
    ),
    '`',
    "'",
  ),
  QuoteSub(
    'monospaced',
    QuoteScope.unconstrained,
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt'
      r')?\+\+('
      '$ccAll'
      r'+?)\+\+',
    ),
    '++',
  ),
  QuoteSub(
    'monospaced',
    QuoteScope.constrained,
    lineRx(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?\+([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])\+(?!'
      '$cgWord)',
      unicode: true,
    ),
    '+',
  ),
  ..._normalQuoteSubs.sublist(6),
];

/// Quoted-text substitution rules by compat mode (`QUOTE_SUBS`).
///
/// The `false` key holds the normal rules, the `true` key the compat-mode
/// rules. Order is significant: rules apply in list order.
final Map<bool, List<QuoteSub>> quoteSubs = <bool, List<QuoteSub>>{
  false: _normalQuoteSubs,
  true: _compatQuoteSubs,
};

/// One textual replacement rule: the [pattern] to match, its [replacement],
/// and the [scope] (what of the match it keeps).
///
/// A replacement rule: pattern, replacement and scope.
class Replacement {
  /// Creates a rule with [pattern], [replacement], [scope] and [guard];
  /// every match starting at most [before] code units before its guard
  /// (or [scan] finding where they start).
  new(
    this.pattern,
    this.replacement,
    this.scope,
    this.guard, {
    int before = 0,
    Pattern Function(RegExp pattern)? scan,
  }) : scan = scan == null
           ? AnchoredScan(pattern, [guard], before: before)
           : scan(pattern);

  /// The pattern matching the source text.
  final RegExp pattern;

  /// The replacement string.
  final String replacement;

  /// How the match boundaries are preserved.
  final ReplacementScope scope;

  /// A literal every match of [pattern] contains.
  ///
  /// Text without it cannot match, so the regex scan is skipped; the
  /// result is identical either way.
  final String guard;

  /// [pattern]'s matches, found by trying it only where one can start.
  final Pattern scan;
}

/// Textual replacements (`REPLACEMENTS`).
///
/// Order is significant: replacements apply in list order.
final List<Replacement> replacements = <Replacement>[
  Replacement(
    RegExp(r'\\?\(C\)'),
    '&#169;',
    ReplacementScope.none,
    '(C)',
    before: 1,
  ),
  Replacement(
    RegExp(r'\\?\(R\)'),
    '&#174;',
    ReplacementScope.none,
    '(R)',
    before: 1,
  ),
  Replacement(
    RegExp(r'\\?\(TM\)'),
    '&#8482;',
    ReplacementScope.none,
    '(TM)',
    before: 1,
  ),
  Replacement(
    lineRx(r'(?: |\n|^|\\)--(?: |\n|$)'),
    '&#8201;&#8212;&#8201;',
    ReplacementScope.none,
    '--',
    before: 1,
  ),
  // Between words; the end of formatted text or a closing curved quote
  // counts as the end of a word, and the start of either as the start of
  // one (#1578, #3946).
  Replacement(
    RegExp(
      '($cgWord'
      r'|</[^>]+>|&#82(?:17|21);)\\?--(?='
      '$cgWord'
      '|<[^/!]|&#82(?:16|20);)',
      unicode: true,
    ),
    '&#8212;&#8203;',
    ReplacementScope.leading,
    '--',
    scan: (pattern) => StartsScan(pattern, _emDashStarts),
  ),
  Replacement(
    RegExp(r'\\?\.\.\.'),
    '&#8230;&#8203;',
    ReplacementScope.none,
    '...',
    before: 1,
  ),
  Replacement(
    RegExp(r"\\?`'"),
    '&#8217;',
    ReplacementScope.none,
    "`'",
    before: 1,
  ),
  Replacement(
    RegExp(
      '($cgAlnum'
      r")\\?'(?="
      '$cgAlpha)',
      unicode: true,
    ),
    '&#8217;',
    ReplacementScope.leading,
    "'",
    // (An astral letter or digit is two code units.)
    before: 3,
  ),
  Replacement(
    RegExp(r'\\?-&gt;'),
    '&#8594;',
    ReplacementScope.none,
    '-&gt;',
    before: 1,
  ),
  Replacement(
    RegExp(r'\\?=&gt;'),
    '&#8658;',
    ReplacementScope.none,
    '=&gt;',
    before: 1,
  ),
  Replacement(
    RegExp(r'\\?&lt;-'),
    '&#8592;',
    ReplacementScope.none,
    '&lt;-',
    before: 1,
  ),
  Replacement(
    RegExp(r'\\?&lt;='),
    '&#8656;',
    ReplacementScope.none,
    '&lt;=',
    before: 1,
  ),
  Replacement(
    RegExp(
      r'\\?(&)amp;((?:[a-zA-Z][a-zA-Z]+\d{0,2}|#\d\d\d{0,4}|#x[\da-fA-F]'
      r'[\da-fA-F][\da-fA-F]{0,3});)',
    ),
    '',
    ReplacementScope.bounding,
    '&amp;',
    before: 1,
  ),
];

/// Flags controlling compliance with the behavior of AsciiDoc.
///
/// Port of the `Compliance` module in `lib/asciidoctor.rb`, with the
/// default values as constants (Asciidoctor lets them be changed at
/// runtime).
abstract final class Compliance {
  /// Terminates a paragraph adjacent to block content.
  static const bool blockTerminatesParagraph = true;

  /// Does not parse verbatim-style paragraphs as verbatim content.
  static const bool strictVerbatimParagraphs = true;

  /// Supports setext (underlined) section titles.
  static const bool underlineStyleSectionTitles = true;

  /// Unwraps a standalone preamble when the document has a title.
  static const bool unwrapStandalonePreamble = true;

  /// How to handle references to missing attributes (`'skip'`).
  static const String attributeMissing = 'skip';

  /// How to handle attribute unassignments (`'drop-line'`).
  static const String attributeUndefined = 'drop-line';

  /// Allows `#id.rolename%optionname` shorthand on blocks.
  static const bool shorthandPropertySyntax = true;

  /// Resolves cross references by matching reference text.
  static const bool naturalXrefs = true;

  /// Start index when generating unique ids on conflict.
  static const int uniqueIdStartIndex = 2;

  /// Recognizes commonly-used Markdown syntax where it does not interfere
  /// with existing AsciiDoc syntax and behavior.
  static const bool markdownSyntax = true;

  /// The compliance key names, in definition order (`Compliance.keys`).
  static const Set<String> keys = <String>{
    'block_terminates_paragraph',
    'strict_verbatim_paragraphs',
    'underline_style_section_titles',
    'unwrap_standalone_preamble',
    'attribute_missing',
    'attribute_undefined',
    'shorthand_property_syntax',
    'natural_xrefs',
    'unique_id_start_index',
    'markdown_syntax',
  };
}
