/// Central regular expression table, ported from `lib/asciidoctor/rx.rb`.
///
/// rewrite rules applied here come from `PORTING-REGEXP.md`:
/// - `CC_ALL` -> `[\s\S]`, `CC_ANY` -> `[^\n]`, `CC_EOL` -> `$`,
///   `CG_BLANK` -> [cgBlank] (tab and the Unicode space separators, as
///   Ruby's `\p{Blank}`).
/// - Ruby's ASCII-only `\s` and `\S` are spelled out as `[ \t\n\v\f\r]`
///   and `[^ \t\n\v\f\r]`: Dart's would also match Unicode spaces (W5,
///   R16).
/// - `\p{Alpha}` -> `\p{Alphabetic}`, `\p{Alnum}` -> split fragments,
///   `\p{Word}` -> `\w`, all with `unicode: true` (B1, R1, R2).
/// - Any pattern containing `^` or `$` gets `multiLine: true` (B9, R3),
///   except [attributeEntryPassMacroRx] and [uriSniffRx], which emulate
///   the upstream `\A` string anchors and therefore use a bare `^` (B2).
/// - Where upstream has a JavaScript variant, [inlineLinkRx],
///   [attributeEntryPassMacroRx] and [uriSniffRx] follow it, while
///   [hardLineBreakRx] follows the default pattern (R5).
library;

// Character class fragments (mirror the CC_*/CG_* constants).

/// Any character, including newlines (`CC_ALL`).
const String ccAll = r'[\s\S]';

/// Any character except newlines (`CC_ANY`).
const String ccAny = r'[^\n]';

/// End of line (`CC_EOL`).
const String ccEol = r'$';

/// Alphabetic character, for use inside a character class (`CC_ALPHA`).
const String ccAlpha = r'\p{Alphabetic}';

/// Alphabetic character, standalone (`CG_ALPHA`).
const String cgAlpha = r'\p{Alphabetic}';

/// Alphanumeric characters, for use inside a character class (`CC_ALNUM`).
const String ccAlnum = r'\p{Alphabetic}\p{Decimal_Number}';

/// Alphanumeric character, standalone (`CG_ALNUM`).
const String cgAlnum = r'(?:\p{Alphabetic}|\p{Decimal_Number})';

/// Blank, standalone (`CG_BLANK`, Ruby's `\p{Blank}`): tab and the Unicode
/// space separators (`Zs`), listed so that no `unicode` flag is needed.
const String cgBlank = '[\t \u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]';

/// Word characters, for use inside a character class (`CC_WORD`).
/// (Dart `\w` stays ASCII-only even with `unicode: true`, so the UTS#18
/// Word union is spelled out. Verified equivalent to upstream `\p{Word}`
/// on letters, marks, decimal digits, `_`, and Join_Controls.)
const String ccWord =
    r'\p{Alphabetic}\p{Mark}\p{Decimal_Number}\p{Connector_Punctuation}\p{Join_Control}';

/// Word character, standalone (`CG_WORD`; same union as [ccWord]).
const String cgWord =
    r'(?:\p{Alphabetic}|\p{Mark}|\p{Decimal_Number}|\p{Connector_Punctuation}|\p{Join_Control})';

/// Matches `[attributes]` in the shorthand quoted-text / passthrough
/// position (`QuoteAttributeListRxt`).
const String quoteAttributeListRxt = r'\[([^\]]+)\]';

/// Admonition style names (`ADMONITION_STYLES.to_a.join '|'`).
const String _admonitionStyles = 'NOTE|TIP|IMPORTANT|WARNING|CAUTION';

// Document header.

/// Matches the author info line immediately following the document title.
final RegExp authorInfoLineRx = RegExp(
  '^($cgWord[$ccWord'
  r"\-'.]*)(?: +("
  '$cgWord[$ccWord'
  r"\-'.]*))?(?: +("
  '$cgWord[$ccWord'
  r"\-'.]*))?(?: +<([^>]+)>)?$",
  multiLine: true,
  unicode: true,
);

/// Matches the delimiter that separates multiple authors.
final RegExp authorDelimiterRx = RegExp(r';(?: |$)', multiLine: true);

/// Matches the revision info line beneath the author info line.
final RegExp revisionInfoLineRx = RegExp(
  r'^(?:[^\d{]*('
  '$ccAny*?),)? *(?!:)($ccAny*?)(?: *(?!^),?: *($ccAny*))?\$',
  multiLine: true,
);

/// Matches the title and volnum in the manpage doctype.
final RegExp manpageTitleVolnumRx = RegExp(
  '^($ccAny'
  r'+?) *\( *('
  '$ccAny'
  r'+?) *\)$',
  multiLine: true,
);

/// Matches the name and purpose in the manpage doctype.
final RegExp manpageNamePurposeRx = RegExp(
  '^($ccAny+?) +- +($ccAny+)\$',
  multiLine: true,
);

// Preprocessor directives.

/// Matches a conditional preprocessor directive
/// (e.g., ifdef, ifndef, ifeval and endif).
final RegExp conditionalDirectiveRx = RegExp(
  r'^(\\)?(ifdef|ifndef|ifeval|endif)::([^ \t\n\v\f\r]*?(?:([,+])[^ \t\n\v\f\r]*?)?)\[('
  '$ccAny'
  r'+)?\]$',
  multiLine: true,
);

/// Matches a restricted (read as safe) eval expression.
final RegExp evalExpressionRx = RegExp(
  '^($ccAny+?) *([=!><]=|[><]) *($ccAny+)\$',
  multiLine: true,
);

/// Matches an include preprocessor directive.
final RegExp includeDirectiveRx = RegExp(
  r'^(\\)?include::([^ \t\n\v\f\r\[](?:[^\[]*[^ \t\n\v\f\r\[])?)\[('
  '$ccAny'
  r'+)?\]$',
  multiLine: true,
);

/// Matches a trailing tag directive in an include file.
final RegExp tagDirectiveRx = RegExp(
  r'\b(?:tag|(e)nd)::([^ \t\n\v\f\r]+?)\[\](?=$|[ \r])',
  multiLine: true,
);

// Attribute entries and references.

/// Matches a document attribute entry.
final RegExp attributeEntryRx = RegExp(
  '^:(!?$cgWord'
  r'[^:]*):(?:[ \t]+('
  '$ccAny*))?\$',
  multiLine: true,
  unicode: true,
);

/// Matches invalid characters in an attribute name.
final RegExp invalidAttributeNameCharsRx = RegExp('[^$ccWord-]', unicode: true);

/// Matches a pass inline macro surrounding the value of an attribute
/// entry once it has been parsed (`^`/`$` without multiLine anchor at the
/// string boundaries).
final RegExp attributeEntryPassMacroRx = RegExp(
  r'^pass:([a-z]+(?:,[a-z-]+)*)?\[('
  '$ccAll'
  r'*)\]$',
);

/// Matches an inline attribute reference.
final RegExp attributeReferenceRx = RegExp(
  r'(\\)?\{('
  '$cgWord[$ccWord-]*|(set|counter2?):$ccAny'
  r'+?)(\\)?\}',
  unicode: true,
);

// Paragraphs and delimited blocks.

/// Matches an anchor (i.e., id + optional reference text) on a line
/// above a block.
final RegExp blockAnchorRx = RegExp(
  r'^\[\[(?:|(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)(?:, *('
  '$ccAny'
  r'+))?)\]\]$',
  multiLine: true,
  unicode: true,
);

/// Matches an attribute list above a block element.
final RegExp blockAttributeListRx = RegExp(
  r'^\[(|['
  '$ccWord'
  r'.#%{,"\x27]'
  '$ccAny'
  r'*)\]$',
  multiLine: true,
  unicode: true,
);

/// A combined pattern that matches either a block anchor or a block
/// attribute list.
final RegExp blockAttributeLineRx = RegExp(
  r'^\[(?:|['
  '$ccWord'
  r'.#%{,"\x27]'
  '$ccAny'
  r'*|\[(?:|['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*(?:, *'
  '$ccAny'
  r'+)?)\])\]$',
  multiLine: true,
  unicode: true,
);

/// Matches a title above a block.
final RegExp blockTitleRx = RegExp(
  r'^\.(\.?[^ \t.]'
  '$ccAny*)\$',
  multiLine: true,
);

/// Matches an admonition label at the start of a paragraph.
final RegExp admonitionParagraphRx = RegExp(
  '^($_admonitionStyles):[ \\t]+',
  multiLine: true,
);

/// Matches a literal paragraph (a line of text preceded by at least
/// one space).
final RegExp literalParagraphRx = RegExp(
  r'^([ \t]+'
  '$ccAny*)\$',
  multiLine: true,
);

// Section titles.

/// Matches an Atx (single-line) section title.
final RegExp atxSectionTitleRx = RegExp(
  r'^(=={0,5})[ \t]+('
  '$ccAny'
  r'+?)(?:[ \t]+\1)?$',
  multiLine: true,
);

/// Matches an extended Atx section title (Markdown variant included).
/// (`\#` in the upstream source escapes `#` in the string literal, not in
/// the pattern, so a bare `#` is used here.)
final RegExp extAtxSectionTitleRx = RegExp(
  r'^(=={0,5}|##{0,5})[ \t]+('
  '$ccAny'
  r'+?)(?:[ \t]+\1)?$',
  multiLine: true,
);

/// Matches the title-only first line of a Setext (two-line) section
/// title.
final RegExp setextSectionTitleRx = RegExp(
  r'^((?!\.)'
  '$ccAny*?$cgAlnum$ccAny*)\$',
  multiLine: true,
  unicode: true,
);

/// Matches an anchor (i.e., id + optional reference text) inside a
/// section title.
final RegExp inlineSectionAnchorRx = RegExp(
  r' (\\)?\[\[(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)(?:, *('
  '$ccAny'
  r'+))?\]\]$',
  multiLine: true,
  unicode: true,
);

/// Matches invalid ID characters in a section title.
final RegExp invalidSectionIdCharsRx = RegExp(
  r'<[^>]+>|&(?:[a-z][a-z]+\d{0,2}|#\d\d\d{0,4}|#x[\da-f][\da-f][\da-f]{0,3});|[^ '
  '$ccWord'
  r'\-.]+?',
  unicode: true,
);

/// Matches an explicit section level style like sect1.
final RegExp sectionLevelStyleRx = RegExp(r'^sect\d$', multiLine: true);

// Lists.

/// Detects the start of any list item.
final RegExp anyListRx = RegExp(
  r'^(?:[ \t]*(?:-|\*\**|\.\.*|\u2022|\d+\.|[a-zA-Z]\.|[IVXivx]+\))[ \t]|(?!//[^/])[ \t]*[^ \t]'
  '$ccAny'
  r'*?(?::::{0,2}|;;)(?:$|[ \t])|<(?:\d+|\.)>[ \t])',
  multiLine: true,
);

/// Matches an unordered list item.
final RegExp unorderedListRx = RegExp(
  r'^[ \t]*(-|\*\**|\u2022)[ \t]+('
  '$ccAny*)\$',
  multiLine: true,
);

/// Matches an ordered list item (explicit numbering or up to 5
/// consecutive dots).
final RegExp orderedListRx = RegExp(
  r'^[ \t]*(\.\.*|\d+\.|[a-zA-Z]\.|[IVXivx]+\))[ \t]+('
  '$ccAny*)\$',
  multiLine: true,
);

/// Matches the ordinals for each type of ordered list.
final Map<String, RegExp> orderedListMarkerRxMap = {
  'arabic': RegExp(r'\d+\.'),
  'loweralpha': RegExp(r'[a-z]\.'),
  'lowerroman': RegExp(r'[ivx]+\)'),
  'upperalpha': RegExp(r'[A-Z]\.'),
  'upperroman': RegExp(r'[IVX]+\)'),
};

/// Matches a description list entry.
final RegExp descriptionListRx = RegExp(
  r'^(?!//[^/])[ \t]*([^ \t]'
  '$ccAny'
  r'*?)(:::{0,2}|;;)(?:$|[ \t]+('
  '$ccAny*)\$)',
  multiLine: true,
);

/// Matches a sibling description list item (excluding the delimiter
/// specified by the key).
final Map<String, RegExp> descriptionListSiblingRx = {
  '::': RegExp(
    r'^(?!//[^/])[ \t]*([^ \t]'
    '$ccAny'
    r'*?[^:]|[^ \t:])(::)(?:$|[ \t]+('
    '$ccAny*)\$)',
    multiLine: true,
  ),
  ':::': RegExp(
    r'^(?!//[^/])[ \t]*([^ \t]'
    '$ccAny'
    r'*?[^:]|[^ \t:])(:::)(?:$|[ \t]+('
    '$ccAny*)\$)',
    multiLine: true,
  ),
  '::::': RegExp(
    r'^(?!//[^/])[ \t]*([^ \t]'
    '$ccAny'
    r'*?[^:]|[^ \t:])(::::)(?:$|[ \t]+('
    '$ccAny*)\$)',
    multiLine: true,
  ),
  ';;': RegExp(
    r'^(?!//[^/])[ \t]*([^ \t]'
    '$ccAny'
    r'*?)(;;)(?:$|[ \t]+('
    '$ccAny*)\$)',
    multiLine: true,
  ),
};

/// Matches a callout list item.
final RegExp calloutListRx = RegExp(
  r'^<(\d+|\.)>[ \t]+('
  '$ccAny*)\$',
  multiLine: true,
);

/// Matches a callout reference inside literal text.
final RegExp calloutExtractRx = RegExp(
  r'((?://|#|--|;;) ?)?(\\)?<!?(|--)(\d+|\.)\3>(?=(?: ?\\?<!?\3(?:\d+|\.)\3>)*$)',
  multiLine: true,
);

/// Template for building a callout-extract pattern for a specific
/// comment prefix (`CalloutExtractRxt`).
const String calloutExtractRxt =
    r'(\\)?<()(\d+|\.)>(?=(?: ?\\?<(?:\d+|\.)>)*$)';

/// Matches a callout reference for a specific comment prefix
/// (`CalloutExtractRxMap`, a cache of dynamically built patterns).
final CalloutRxMap calloutExtractRxMap = CalloutRxMap(calloutExtractRxt);

/// Scans for callout references (special characters not yet replaced).
final RegExp calloutScanRx = RegExp(
  r'\\?<!?(|--)(\d+|\.)\1>(?=(?: ?\\?<!?\1(?:\d+|\.)\1>)*'
  '$ccEol)',
  multiLine: true,
);

/// Matches a callout reference once special characters have been
/// replaced (SGML output).
final RegExp calloutSourceRx = RegExp(
  r'((?://|#|--|;;) ?)?(\\)?&lt;!?(|--)(\d+|\.)\3&gt;(?=(?: ?\\?&lt;!?\3(?:\d+|\.)\3&gt;)*'
  '$ccEol)',
  multiLine: true,
);

/// Template for building a callout-source pattern for a specific
/// comment prefix (`CalloutSourceRxt`).
const String calloutSourceRxt =
    r'(\\)?&lt;()(\d+|\.)&gt;(?=(?: ?\\?&lt;(?:\d+|\.)&gt;)*$)';

/// Matches a replaced callout reference for a specific comment prefix
/// (`CalloutSourceRxMap`, a cache of dynamically built patterns).
final CalloutRxMap calloutSourceRxMap = CalloutRxMap(calloutSourceRxt);

/// Cache of dynamically built callout patterns, keyed by comment
/// prefix (ports the `Hash.new` default-proc construction of
/// `CalloutExtractRxMap` / `CalloutSourceRxMap`).
class CalloutRxMap {
  /// Creates a callout-pattern cache for [template].
  new(this.template);

  /// The pattern template interpolated after the escaped prefix group.
  final String template;

  final Map<String, RegExp> _cache = {};

  /// Returns the pattern for [prefix], building and caching it on
  /// first use.
  RegExp operator [](String prefix) => _cache.putIfAbsent(
    prefix,
    () => RegExp(
      prefix.isEmpty
          // `(|)` participates with ""; `()?` would yield null for the
          // skipped group.
          ? '(|)$template'
          : '(${RegExp.escape(prefix)} ?)?$template',
      multiLine: true,
    ),
  );
}

/// A Map of regexps for lists used for dynamic access.
final Map<String, RegExp> listRxMap = {
  'ulist': unorderedListRx,
  'olist': orderedListRx,
  'dlist': descriptionListRx,
  'colist': calloutListRx,
};

// Tables.

/// Parses the column spec (i.e., colspec) for a table.
final RegExp columnSpecRx = RegExp(
  r'^(?:(\d+)\*)?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?(\d+%?|~)?([a-z])?$',
  multiLine: true,
);

/// Parses the start of a cell spec (i.e., cellspec) for a table.
final RegExp cellSpecStartRx = RegExp(
  r'^[ \t]*(?:(\d+(?:\.\d*)?|(?:\d*\.)?\d+)([*+]))?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?([a-z])?$',
  multiLine: true,
);

/// Parses the end of a cell spec (i.e., cellspec) for a table.
final RegExp cellSpecEndRx = RegExp(
  r'[ \t]+(?:(\d+(?:\.\d*)?|(?:\d*\.)?\d+)([*+]))?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?([a-z])?$',
  multiLine: true,
);

// Block macros.

/// Matches the custom block macro pattern.
final RegExp customBlockMacroRx = RegExp(
  '^($cgWord[$ccWord'
  r'-]*)::(|[^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
  '$ccAny'
  r'*?[^ \t\n\v\f\r])\[('
  '$ccAny'
  r'+)?\]$',
  multiLine: true,
  unicode: true,
);

/// Matches an image, video or audio block macro.
final RegExp blockMediaMacroRx = RegExp(
  r'^(image|video|audio)::([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
  '$ccAny'
  r'*?[^ \t\n\v\f\r])\[('
  '$ccAny'
  r'+)?\]$',
  multiLine: true,
);

/// Matches the TOC block macro.
final RegExp blockTocMacroRx = RegExp(
  r'^toc::\[('
  '$ccAny'
  r'+)?\]$',
  multiLine: true,
);

// Inline macros.

/// Matches an anchor (i.e., id + optional reference text) in the flow
/// of text.
final RegExp inlineAnchorRx = RegExp(
  r'(\\)?(?:\[\[(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)(?:, *('
  '$ccAny'
  r'+?))? ?\]\]|anchor:(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)\[(?:\]|('
  '$ccAny'
  r'*?[^\\])\]))',
  unicode: true,
);

/// Scans for a non-escaped anchor in the flow of text.
final RegExp inlineAnchorScanRx = RegExp(
  r'(?:^|[^\\\[])\[\[(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)(?:, *('
  '$ccAny'
  r'+?))? ?\]\]|(?:^|[^\\])anchor:(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)\[(?:\]|('
  '$ccAny'
  r'*?[^\\])\])',
  multiLine: true,
  unicode: true,
);

/// Scans for a leading, non-escaped anchor.
final RegExp leadingInlineAnchorRx = RegExp(
  r'^\[\[(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)(?:, *('
  '$ccAny'
  r'+?))?\]\]',
  multiLine: true,
  unicode: true,
);

/// Matches a bibliography anchor at the start of the list item text.
final RegExp inlineBiblioAnchorRx = RegExp(
  r'^\[\[\[(['
  '${ccAlpha}_:][$ccWord'
  r'\-:.]*)(?:, *('
  '$ccAny'
  r'+?))?\]\]\]',
  multiLine: true,
  unicode: true,
);

/// Matches an inline e-mail address.
/// (The upstream lead-in class contains an escaped `>`, which is invalid
/// under `unicode: true`, so a bare `>` is used here.)
final RegExp inlineEmailRx = RegExp(
  r'([\\>:/])?'
  '$cgWord(?:&amp;|[$ccWord'
  r'\-.%+])*@'
  '$cgAlnum[$ccAlnum'
  r'_\-.]*\.[a-zA-Z]{2,5}\b',
  unicode: true,
);

/// Matches an inline footnote macro, which may span multiple lines.
final RegExp inlineFootnoteMacroRx = RegExp(
  r'\\?footnote(?:(ref):|:(['
  '$ccWord'
  r'-]+)?)\[(?:|('
  '$ccAll'
  r'*?[^\\]))\](?!</a>)',
  unicode: true,
);

/// Matches an image or icon inline macro.
final RegExp inlineImageMacroRx = RegExp(
  r'\\?i(?:mage|con):([^: \t\n\v\f\r\[](?:[^\n\[]*[^ \t\n\v\f\r\[])?)\[(|'
  '$ccAll'
  r'*?[^\\])\]',
);

/// Matches an indexterm inline macro, which may span multiple lines.
final RegExp inlineIndextermMacroRx = RegExp(
  r'\\?(?:(indexterm2?):\[('
  '$ccAll'
  r'*?[^\\])\]|\(\(('
  '$ccAll'
  r'+?)\)\)(?!\)))',
);

/// Matches either the kbd or btn inline macro.
final RegExp inlineKbdBtnMacroRx = RegExp(
  r'(\\)?(kbd|btn):\[('
  '$ccAll'
  r'*?[^\\])\]',
);

/// Matches an implicit link and some of the link inline macro (opal
/// variant: in JavaScript a backreference to an unset group matches
/// empty, so the inverted-logic form is required).
///
/// NOTE: unlike the gap catalog's B4 parenthetical, this pattern
/// contains no `\w`-from-Word fragment (only `CG_BLANK`, which maps to
/// ASCII `[ \t]`), so no `unicode` flag is needed; omitting it also
/// keeps `\s` at its narrowest.
final RegExp inlineLinkRx = RegExp(
  '(^|link:|$cgBlank'
  r'|\\?&lt;(?=\\?(?:https?|file|ftp|irc)(:))|[>\(\)\[\];"\x27])(\\?(?:https?|file|ftp|irc)://)(?:([^ \t\n\v\f\r\[\]]+)\[(|'
  '$ccAll'
  r'*?[^\\])\]|(?!\2)([^ \t\n\v\f\r]+?)&gt;|([^ \t\n\v\f\r\[\]<]*([^ \t\n\v\f\r,.?!\[\]<\)])))',
  multiLine: true,
);

/// Matches a link or e-mail inline macro.
final RegExp inlineLinkMacroRx = RegExp(
  r'\\?(?:link|(mailto)):(|[^: \t\n\v\f\r\[][^ \t\n\v\f\r\[]*)\[(|'
  '$ccAll'
  r'*?[^\\])\]',
);

/// Matches the name of a macro.
final RegExp macroNameRx = RegExp(
  '^$cgWord[$ccWord-]*\$',
  multiLine: true,
  unicode: true,
);

/// Matches a stem (and alternatives, asciimath and latexmath) inline
/// macro, which may span multiple lines.
final RegExp inlineStemMacroRx = RegExp(
  r'\\?(stem|(?:latex|ascii)math):([a-z]+(?:,[a-z-]+)*)?\[('
  '$ccAll'
  r'*?[^\\])\]',
);

/// Matches a menu inline macro.
final RegExp inlineMenuMacroRx = RegExp(
  r'\\?menu:('
  '$cgWord|[$ccWord'
  r'&][^\n\[]*[^ \t\n\v\f\r\[])\[ *(?:|('
  '$ccAll'
  r'*?[^\\]))\]',
  unicode: true,
);

/// Matches an implicit menu inline macro.
final RegExp inlineMenuRx = RegExp(
  r'\\?"(['
  '$ccWord'
  r'&][^"]*?[ \n]+&gt;[ \n]+[^"]*)"',
  unicode: true,
);

/// Matches an inline passthrough, which may span multiple lines.
/// Keyed by compat mode: `false` is the modern `+...+` / backtick
/// form, `true` the legacy backtick-only form.
///
/// The compat form carries two deviations from a naive port: `(\Z)`
/// becomes a lookahead-only empty capture (B2), and the upstream
/// quantified lookahead `(?=((\\))?)?` drops its outer `?` (an optional
/// always-succeeding assertion, which Dart rejects at construction);
/// the `?` that makes the enclosing alternation optional is kept.
final Map<bool, InlinePassEntry> inlinePassRx = {
  false: InlinePassEntry(
    '+',
    '-]',
    RegExp(
      '((?:^|[^$ccWord'
      r';:\\])(?=(\[)|\+)|\\(?=\[)|(?=\\\+))(?:\2(x-|[^\]]+ x-)\]|(?:'
      '$quoteAttributeListRxt'
      r')?(?=(\\)?\+))(\5?(\+|`)'
      r'([^ \t\n\v\f\r]|[^ \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])\7)(?!'
      '$cgWord)',
      multiLine: true,
      unicode: true,
    ),
  ),
  true: InlinePassEntry(
    '`',
    null,
    RegExp(
      '(^|[^`$ccWord'
      r'}])(?:((?=\n?(?![\s\S])))()|'
      '$quoteAttributeListRxt'
      r'(?=(\\)?))?(\5?(`)([^` \t\n\v\f\r]|[^` \t\n\v\f\r]'
      '$ccAll'
      r'*?[^ \t\n\v\f\r])\7)(?![`'
      '$ccWord}])',
      multiLine: true,
      unicode: true,
    ),
  ),
};

/// One entry of [inlinePassRx]: the lone passthrough delimiter, the
/// optional closing trim marker, and the match pattern.
class InlinePassEntry {
  /// Creates an entry for [delimiter] with [endTrim] and [pattern].
  new(this.delimiter, this.endTrim, this.pattern);

  /// The delimiter for a lone passthrough (`+` or backtick).
  final String delimiter;

  /// Marker trimmed from the end of the enclosed text, if any.
  final String? endTrim;

  /// The match pattern.
  final RegExp pattern;
}

/// Matches several variants of the passthrough inline macro, which may
/// span multiple lines.
final RegExp inlinePassMacroRx = RegExp(
  r'(?:(?:(\\?)'
  '$quoteAttributeListRxt'
  r')?(\\{0,2})(\+\+\+?|\$\$)('
  '$ccAll'
  r'*?)\4|(\\?)pass:([a-z]+(?:,[a-z-]+)*)?\[(|'
  '$ccAll'
  r'*?[^\\])\])',
);

/// Matches an xref (i.e., cross-reference) inline macro, which may
/// span multiple lines.
final RegExp inlineXrefMacroRx = RegExp(
  r'\\?(?:&lt;&lt;(['
  '$ccWord#/.:{]$ccAll*?)&gt;&gt;|xref:([$ccWord#/.:{]$ccAll'
  r'*?)\[(?:\]|('
  '$ccAll'
  r'*?[^\\])\]))',
  unicode: true,
);

// Layout.

/// Matches a trailing `+` preceded by a space, which forces a hard
/// line break (with multiLine).
final RegExp hardLineBreakRx = RegExp(
  '^($ccAny'
  r'*) \+$',
  multiLine: true,
);

/// Matches a Markdown horizontal rule.
final RegExp markdownThematicBreakRx = RegExp(
  r'^ {0,3}([-*_])( *)\1\2\1$',
  multiLine: true,
);

/// Matches an AsciiDoc or Markdown horizontal rule or AsciiDoc page
/// break.
final RegExp extLayoutBreakRx = RegExp(
  r"^(?:'{3,}|<{3,}|([-*_])( *)\1\2\1)$",
  multiLine: true,
);

// General.

/// Matches consecutive blank lines.
final RegExp blankLineRx = RegExp(r'\n{2,}');

/// Matches whitespace (space, tab, newline) escaped by a backslash.
final RegExp escapedSpaceRx = RegExp(r'\\([ \t\n])');

/// Detects if text is a possible candidate for the replacements
/// substitution.
final RegExp replaceableTextRx = RegExp(r"[&']|--|\.\.\.|\([CRT]M?\)");

/// Matches a whitespace delimiter (spaces, tabs and/or newlines).
final RegExp spaceDelimiterRx = RegExp(r'([^\\])[ \t\n]+');

/// Matches a `+` or `-` modifier in a subs list.
final RegExp subModifierSniffRx = RegExp('[+-]');

/// Matches one or more consecutive digits at the end of a line.
final RegExp trailingDigitsRx = RegExp(r'\d+$', multiLine: true);

/// Detects strings that resemble URIs (`^` without multiLine anchors at the
/// start of the string).
final RegExp uriSniffRx = RegExp(
  '^$cgAlpha[$ccAlnum.+-]+:/{0,2}',
  unicode: true,
);

/// Detects XML tags.
final RegExp xmlSanitizeRx = RegExp('<[^>]+>');
