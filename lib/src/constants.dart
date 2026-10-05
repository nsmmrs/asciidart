/// Top-level constants ported from `lib/asciidoctor.rb`.
///
/// `SCREAMING_SNAKE` names become lowerCamelCase ([maxInt]) and symbolic
/// values are plain strings (list contexts are `'ulist'` etc.).
/// [Compliance] mirrors the `SafeMode` port in `abstract_node.dart` as an
/// `abstract final class` with `static const` members.
///
/// Already ported elsewhere (not duplicated here):
/// - `LF` and `SafeMode` in `abstract_node.dart`
/// - `CC_*`/`CG_*` and `QuoteAttributeListRxt` in `rx.dart`
/// - `MeaningfulVersion`/`VERSION` in `version.dart`
/// - `ORDERED_LIST_KEYWORDS` and `CAPTION_ATTRIBUTE_NAMES` in
///   `abstract_block.dart` (the latter deliberately omits the unreachable
///   `'figure'` string key; see the doc comment there)
///
/// Deliberately not ported (runtime-environment constants): `RUBY_ENGINE`,
/// `RUBY_ENGINE_OPAL`, `ROOT_DIR`, `LIB_DIR`, `DATA_DIR`, `USER_HOME`,
/// `UTF_8`.
library;

import 'package:asciidart/src/rx.dart';

/// The null character used for splitting attribute values (`NULL`).
const String nullChar = '\x00';

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

/// The mode to use when opening a file for reading (`FILE_READ_MODE`).
///
/// An IO mode string kept for reference; nothing here uses it.
const String fileReadMode = 'rb:UTF-8:UTF-8';

/// The mode to use when opening a URI for reading (`URI_READ_MODE`).
const String uriReadMode = fileReadMode;

/// The mode to use when opening a file for writing (`FILE_WRITE_MODE`).
///
/// An IO mode string kept for reference; nothing here uses it.
const String fileWriteMode = 'wb:UTF-8';

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

/// Setext (two-line) underline characters by section level
/// (`SETEXT_SECTION_LEVELS`).
const Map<String, int> setextSectionLevels = <String, int>{
  '=': 0,
  '-': 1,
  '~': 2,
  '^': 3,
  '+': 4,
};

/// Admonition style names (`ADMONITION_STYLES`).
const Set<String> admonitionStyles = <String>{
  'NOTE',
  'TIP',
  'IMPORTANT',
  'WARNING',
  'CAUTION',
};

/// First letters of the admonition style names (`ADMONITION_STYLE_HEADS`).
const Set<String> admonitionStyleHeads = <String>{'N', 'T', 'I', 'W', 'C'};

/// Paragraph styles (`PARAGRAPH_STYLES`).
const Set<String> paragraphStyles = <String>{
  'comment',
  'example',
  'literal',
  'listing',
  'normal',
  'open',
  'pass',
  'quote',
  'sidebar',
  'source',
  'verse',
  'abstract',
  'partintro',
};

/// Paragraph styles treated as verbatim content (`VERBATIM_STYLES`).
const Set<String> verbatimStyles = <String>{
  'literal',
  'listing',
  'source',
  'verse',
};

/// The block context and masquerade styles of one [delimitedBlocks] entry.
///
/// The block context and the set of styles it can masquerade as.
class DelimitedBlockInfo {
  /// Creates an entry with block [context] and accepted [styles].
  const new(this.context, [this.styles = const <String>{}]);

  /// The block context the delimiter maps to (e.g. `'listing'`).
  final String context;

  /// The styles that may masquerade as this delimiter.
  final Set<String> styles;
}

/// Delimiter lines mapped to their block context and masquerade styles
/// (`DELIMITED_BLOCKS`).
const Map<String, DelimitedBlockInfo> delimitedBlocks =
    <String, DelimitedBlockInfo>{
      '--': DelimitedBlockInfo('open', <String>{
        'comment',
        'example',
        'literal',
        'listing',
        'pass',
        'quote',
        'sidebar',
        'source',
        'verse',
        'admonition',
        'abstract',
        'partintro',
      }),
      '----': DelimitedBlockInfo('listing', <String>{'literal', 'source'}),
      '....': DelimitedBlockInfo('literal', <String>{'listing', 'source'}),
      '====': DelimitedBlockInfo('example', <String>{'admonition'}),
      '****': DelimitedBlockInfo('sidebar'),
      '____': DelimitedBlockInfo('quote', <String>{'verse'}),
      '++++': DelimitedBlockInfo('pass', <String>{
        'stem',
        'latexmath',
        'asciimath',
      }),
      '|===': DelimitedBlockInfo('table'),
      ',===': DelimitedBlockInfo('table'),
      ':===': DelimitedBlockInfo('table'),
      '!===': DelimitedBlockInfo('table'),
      '////': DelimitedBlockInfo('comment'),
      '```': DelimitedBlockInfo('fenced_code'),
    };

/// First two characters of every [delimitedBlocks] key
/// (`DELIMITED_BLOCK_HEADS`).
const Map<String, bool> delimitedBlockHeads = <String, bool>{
  '--': true,
  '..': true,
  '==': true,
  '**': true,
  '__': true,
  '++': true,
  '|=': true,
  ',=': true,
  ':=': true,
  '!=': true,
  '//': true,
  '``': true,
};

/// Four-character [delimitedBlocks] keys mapped to their last character
/// (`DELIMITED_BLOCK_TAILS`).
const Map<String, String> delimitedBlockTails = <String, String>{
  '----': '-',
  '....': '.',
  '====': '=',
  '****': '*',
  '____': '_',
  '++++': '+',
  '|===': '=',
  ',===': '=',
  ':===': '=',
  '!===': '=',
  '////': '/',
};

/// Characters that start a break block and the context each maps to
/// (`LAYOUT_BREAK_CHARS`).
const Map<String, String> layoutBreakChars = <String, String>{
  "'": 'thematic_break',
  '<': 'page_break',
};

/// Markdown thematic-break characters (`MARKDOWN_THEMATIC_BREAK_CHARS`).
const Map<String, String> markdownThematicBreakChars = <String, String>{
  '-': 'thematic_break',
  '*': 'thematic_break',
  '_': 'thematic_break',
};

/// The union of [layoutBreakChars] and [markdownThematicBreakChars]
/// (`HYBRID_LAYOUT_BREAK_CHARS`).
const Map<String, String> hybridLayoutBreakChars = <String, String>{
  ...layoutBreakChars,
  ...markdownThematicBreakChars,
};

/// List contexts that may nest (`NESTABLE_LIST_CONTEXTS`).
const List<String> nestableListContexts = <String>['ulist', 'olist', 'dlist'];

/// Ordered-list styles (`ORDERED_LIST_STYLES`).
const List<String> orderedListStyles = <String>[
  'arabic',
  'loweralpha',
  'lowerroman',
  'upperalpha',
  'upperroman',
];

/// Head of an attribute reference (`{name}`) (`ATTR_REF_HEAD`).
const String attrRefHead = '{';

/// List continuation marker (`LIST_CONTINUATION`).
const String listContinuation = '+';

/// Hard line break suffix (`HARD_LINE_BREAK`).
const String hardLineBreak = ' +';

/// Line continuation suffix (`LINE_CONTINUATION`).
const String lineContinuation = r' \';

/// Legacy line continuation suffix (`LINE_CONTINUATION_LEGACY`).
const String lineContinuationLegacy = ' +';

/// Block math delimiters by stem type (`BLOCK_MATH_DELIMITERS`).
const Map<String, List<String>> blockMathDelimiters = <String, List<String>>{
  'asciimath': <String>[r'\$', r'\$'],
  'latexmath': <String>[r'\[', r'\]'],
};

/// Inline math delimiters by stem type (`INLINE_MATH_DELIMITERS`).
const Map<String, List<String>> inlineMathDelimiters = <String, List<String>>{
  'asciimath': <String>[r'\$', r'\$'],
  'latexmath': <String>[r'\(', r'\)'],
};

/// Stem type aliases (`STEM_TYPE_ALIASES`).
///
/// Lookups of unknown types must fall back to `'asciimath'`.
const Map<String, String> stemTypeAliases = <String, String>{
  'latexmath': 'latexmath',
  'latex': 'latexmath',
  'tex': 'latexmath',
};

/// Pinned Font Awesome version (`FONT_AWESOME_VERSION`).
const String fontAwesomeVersion = '4.7.0';

/// Pinned highlight.js version (`HIGHLIGHT_JS_VERSION`).
const String highlightJsVersion = '9.18.3';

/// Pinned MathJax version (`MATHJAX_VERSION`).
const String mathJaxVersion = '2.7.9';

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
  'amp': '&',
  'lt': '<',
  'gt': '>',
};

/// One quoted-text substitution rule: a quote [type] (e.g. `'strong'`),
/// a [scope] (`'constrained'` or `'unconstrained'`), and the [pattern]
/// that matches it.
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
  final String scope;

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
    final open = text.indexOf(guard);
    return open >= 0 && text.indexOf(closeGuard, open + guard.length) >= 0;
  }
}

/// Quoted-text substitution rules for normal mode (`QUOTE_SUBS`false``).
///
/// Patterns are built from the `rx.dart` character-class fragments
/// (`CC_ALL`/`CC_WORD`/`CG_WORD`); flags follow
/// `PORTING-REGEXP.md` (any pattern containing `^` gets `multiLine: true`,
/// any pattern using `\p{...}` gets `unicode: true`).
final List<QuoteSub> _normalQuoteSubs = <QuoteSub>[
  QuoteSub(
    'strong',
    'unconstrained',
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
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?\*([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])\*(?!'
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    '*',
  ),
  QuoteSub(
    'double',
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?"`([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])`"(?!'
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    '"`',
    '`"',
  ),
  QuoteSub(
    'single',
    'constrained',
    RegExp(
      '(^|[^$ccWord;:`}])(?:$quoteAttributeListRxt'
      r")?'`([^ \t\n\v\f\r]|[^ \t\n\v\f\r]"
      '$ccAll'
      r"*?[^ \t\n\v\f\r])`'(?!"
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    "'`",
    "`'",
  ),
  QuoteSub(
    'monospaced',
    'unconstrained',
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt)?``($ccAll+?)``',
    ),
    '``',
  ),
  QuoteSub(
    'monospaced',
    'constrained',
    RegExp(
      "(^|[^$ccWord;:\"'`}])(?:$quoteAttributeListRxt)?`([^ \\t\\n\\v\\f\\r]|[^ \\t\\n\\v\\f\\r]$ccAll*?[^ \\t\\n\\v\\f\\r])"
      "`(?![$ccWord\"'`])",
      multiLine: true,
      unicode: true,
    ),
    '`',
  ),
  QuoteSub(
    'emphasis',
    'unconstrained',
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt)?__($ccAll+?)__',
    ),
    '__',
  ),
  QuoteSub(
    'emphasis',
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?_([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])_(?!'
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    '_',
  ),
  QuoteSub(
    'mark',
    'unconstrained',
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt)?##($ccAll+?)##',
    ),
    '##',
  ),
  QuoteSub(
    'mark',
    'constrained',
    RegExp(
      '(^|[^$ccWord&;:}])(?:$quoteAttributeListRxt'
      r')?#([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])#(?!'
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    '#',
  ),
  QuoteSub(
    'superscript',
    'unconstrained',
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt'
      r')?\^([^ \t\n\v\f\r]+?)\^',
    ),
    '^',
  ),
  QuoteSub(
    'subscript',
    'unconstrained',
    RegExp(
      r'\\?(?:'
      '$quoteAttributeListRxt'
      r')?~([^ \t\n\v\f\r]+?)~',
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
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?``([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r"*?[^ \t\n\v\f\r])''(?!"
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    '``',
    "''",
  ),
  QuoteSub(
    'emphasis',
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r")?'([^ \t\n\v\f\r]|[^ \t\n\v\f\r]"
      '$ccAll'
      r"*?[^ \t\n\v\f\r])'(?!"
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    "'",
  ),
  QuoteSub(
    'single',
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?`([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r"*?[^ \t\n\v\f\r])'(?!"
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
    '`',
    "'",
  ),
  QuoteSub(
    'monospaced',
    'unconstrained',
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
    'constrained',
    RegExp(
      '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt'
      r')?\+([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])\+(?!'
      '$cgWord)',
      multiLine: true,
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
/// and the [scope] (`'none'`, `'leading'` or `'bounding'`).
///
/// A replacement rule: pattern, replacement and scope.
class Replacement {
  /// Creates a rule with [pattern], [replacement], [scope] and [guard].
  const new(this.pattern, this.replacement, this.scope, this.guard);

  /// The pattern matching the source text.
  final RegExp pattern;

  /// The replacement string.
  final String replacement;

  /// How the match boundaries are preserved.
  final String scope;

  /// A literal every match of [pattern] contains.
  ///
  /// Text without it cannot match, so the regex scan is skipped; the
  /// result is identical either way.
  final String guard;
}

/// Textual replacements (`REPLACEMENTS`).
///
/// Order is significant: replacements apply in list order.
final List<Replacement> replacements = <Replacement>[
  Replacement(RegExp(r'\\?\(C\)'), '&#169;', 'none', '(C)'),
  Replacement(RegExp(r'\\?\(R\)'), '&#174;', 'none', '(R)'),
  Replacement(RegExp(r'\\?\(TM\)'), '&#8482;', 'none', '(TM)'),
  Replacement(
    RegExp(r'(?: |\n|^|\\)--(?: |\n|$)', multiLine: true),
    '&#8201;&#8212;&#8201;',
    'none',
    '--',
  ),
  Replacement(
    RegExp(
      '($cgWord'
      r')\\?--(?='
      '$cgWord)',
      unicode: true,
    ),
    '&#8212;&#8203;',
    'leading',
    '--',
  ),
  Replacement(RegExp(r'\\?\.\.\.'), '&#8230;&#8203;', 'none', '...'),
  Replacement(RegExp(r"\\?`'"), '&#8217;', 'none', "`'"),
  Replacement(
    RegExp(
      '($cgAlnum'
      r")\\?'(?="
      '$cgAlpha)',
      unicode: true,
    ),
    '&#8217;',
    'leading',
    "'",
  ),
  Replacement(RegExp(r'\\?-&gt;'), '&#8594;', 'none', '-&gt;'),
  Replacement(RegExp(r'\\?=&gt;'), '&#8658;', 'none', '=&gt;'),
  Replacement(RegExp(r'\\?&lt;-'), '&#8592;', 'none', '&lt;-'),
  Replacement(RegExp(r'\\?&lt;='), '&#8656;', 'none', '&lt;='),
  Replacement(
    RegExp(
      r'\\?(&)amp;((?:[a-zA-Z][a-zA-Z]+\d{0,2}|#\d\d\d{0,4}|#x[\da-fA-F]'
      r'[\da-fA-F][\da-fA-F]{0,3});)',
    ),
    '',
    'bounding',
    '&amp;',
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
