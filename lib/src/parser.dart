/// Methods to parse lines of AsciiDoc into an object hierarchy.
///
/// Port of `lib/asciidoctor/parser.rb` (complete).
///
/// Ruby symbols (`:paragraph`, `:document`, ...) are represented as `String`s
/// throughout this port. Attribute maps that carry positional entries use
/// `Map<Object, Object?>` with `int` keys (exactly like the Ruby hashes);
/// they are converted to string keys when handed to block constructors via
/// [_strKeys] because the ported model types its attribute maps as
/// `Map<String, Object?>`.
///
/// Several collaborators live in waves that have not landed yet; every
/// private workaround for one is marked `TEMP-SEAM (parser)` and must be
/// deleted (routing the call to the real API) when that wave lands:
///
/// * The substitutors wave replaces [_subSpecialchars], [_subAttributes],
///   [_applyHeaderSubs], [_applyAttributeValueSubs],
///   [_parseAttributes], [_resolveSubs], [_commitSubs] and [_titleText].
///   Substitution coverage in these seams is limited to the
///   `specialcharacters` and `attributes` substitutions; quotes, macros,
///   replacements and post-replacements are applied by the real wave.
///   ([_setDocumentAttribute] already delegates to [Document.setAttribute].)
/// * Extension integration is ported: the block/block-macro extension
///   branches in [nextBlock] and [buildBlock] consult
///   `document.extensions`, and attribute entries route through
///   [Document.setAttribute] (whose backend/doctype refresh this needs).
/// * The syntax-highlighter wave restores the `highlight` subs swap in
///   [_commitSubs] (`document.syntaxHighlighter` is always `null`).
/// * The constants wave unifies the `CONST-PENDING` tables below with the
///   canonical module constants; the values here are verbatim copies.
/// * `table.dart` still carries its own `Parser.catalogInlineAnchor` stub
///   (imported here with `hide Parser`); the table wave deletes that stub
///   and imports this library so table cells catalog anchors through
///   [Parser.catalogInlineAnchor].
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/attribute_list.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/callouts.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/extensions.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/highlight/syntax_highlighter.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/substitutors.dart';
import 'package:asciidoctor/src/table.dart';

const String _del = '\u007f';
const String _can = '\u0018';
const String _rs = r'\';

/// Match data for a delimited block boundary line.
///
/// Port of `Parser::BlockMatchData` (`context`, `masq`, `tip`, `terminator`).
class BlockMatchData {
  /// Creates match data for a delimited block of [context].
  const new(this.context, this.masq, this.tip, this.terminator);

  /// The block context the delimiter maps to (e.g. `'listing'`).
  final String context;

  /// The styles this delimiter may masquerade as.
  final Set<String> masq;

  /// The short delimiter tip that was matched (e.g. `'----'`).
  final String tip;

  /// The full delimiter line, which also terminates the block.
  final String terminator;
}

/// Internal marker for a list continuation line inside a list-item buffer.
///
/// Ruby extends the `'+'` (and `''` placeholder) strings with the
/// `ListContinuationMarker` module and tests membership with `===`; the
/// port uses these two singletons in a `List<Object>` buffer instead. The
/// buffer is mapped back to plain strings before a [Reader] is built.
enum _ListContinuation {
  /// A live list continuation (`'+'`).
  active._('+'),

  /// A consumed list continuation (the empty string).
  placeholder._('');

  new _(this.text);

  /// The line text this marker stands for.
  final String text;
}

/// Methods to parse lines of AsciiDoc into an object hierarchy.
///
/// All members are static; the class cannot be instantiated.
abstract final class Parser {
  /// String for matching the tab character. Port of `Parser::TAB`.
  static const String tab = '\t';

  // CONST-PENDING (parser): canonical module constants, owned by the
  // constants wave. Values are verbatim copies of lib/asciidoctor.rb.

  /// Port of `Compliance.block_terminates_paragraph`.
  static const bool _blockTerminatesParagraph = true;

  /// Port of `Compliance.strict_verbatim_paragraphs`.
  static const bool _strictVerbatimParagraphs = true;

  /// Port of `Compliance.underline_style_section_titles`.
  static const bool _underlineStyleSectionTitles = true;

  /// Port of `Compliance.unwrap_standalone_preamble`.
  static const bool _unwrapStandalonePreamble = true;

  /// Port of `Compliance.attribute_missing`.
  static const String _attributeMissing = 'skip';

  /// Port of `Compliance.shorthand_property_syntax`.
  static const bool _shorthandPropertySyntax = true;

  /// Port of `Compliance.markdown_syntax`.
  static const bool _markdownSyntax = true;

  /// Port of `SETEXT_SECTION_LEVELS`.
  static const Map<String, int> _setextSectionLevels = <String, int>{
    '=': 0,
    '-': 1,
    '~': 2,
    '^': 3,
    '+': 4,
  };

  /// Port of `ADMONITION_STYLES`.
  static const Set<String> _admonitionStyles = <String>{
    'NOTE',
    'TIP',
    'IMPORTANT',
    'WARNING',
    'CAUTION',
  };

  /// Port of `ADMONITION_STYLE_HEADS`.
  static const Set<String> _admonitionStyleHeads = <String>{
    'N',
    'T',
    'I',
    'W',
    'C',
  };

  /// Port of `PARAGRAPH_STYLES`.
  static const Set<String> _paragraphStyles = <String>{
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

  /// Port of `VERBATIM_STYLES`.
  static const Set<String> _verbatimStyles = <String>{
    'literal',
    'listing',
    'source',
    'verse',
  };

  /// Port of `DELIMITED_BLOCKS` (delimiter tip to context and masquerades).
  static const Map<String, (String, Set<String>)> _delimitedBlocks =
      <String, (String, Set<String>)>{
        '--': (
          'open',
          <String>{
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
          },
        ),
        '----': ('listing', <String>{'literal', 'source'}),
        '....': ('literal', <String>{'listing', 'source'}),
        '====': ('example', <String>{'admonition'}),
        '****': ('sidebar', <String>{}),
        '____': ('quote', <String>{'verse'}),
        '++++': ('pass', <String>{'stem', 'latexmath', 'asciimath'}),
        '|===': ('table', <String>{}),
        ',===': ('table', <String>{}),
        ':===': ('table', <String>{}),
        '!===': ('table', <String>{}),
        '~~~~': ('open', <String>{'abstract', 'partintro'}),
        '////': ('comment', <String>{}),
        '```': ('fenced_code', <String>{}),
      };

  /// Port of `DELIMITED_BLOCK_HEADS` (first two chars of each tip).
  static const Set<String> _delimitedBlockHeads = <String>{
    '--',
    '..',
    '==',
    '**',
    '__',
    '++',
    '|=',
    ',=',
    ':=',
    '!=',
    '~~',
    '//',
    '``',
  };

  /// Port of `DELIMITED_BLOCK_TAILS` (tip to tail char, 4-char tips only).
  static const Map<String, String> _delimitedBlockTails = <String, String>{
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
    '~~~~': '~',
    '////': '/',
  };

  /// Port of `LAYOUT_BREAK_CHARS`.
  static const Map<String, String> _layoutBreakChars = <String, String>{
    "'": 'thematic_break',
    '<': 'page_break',
  };

  /// Port of `MARKDOWN_THEMATIC_BREAK_CHARS`.
  static const Map<String, String> _markdownThematicBreakChars =
      <String, String>{
        '-': 'thematic_break',
        '*': 'thematic_break',
        '_': 'thematic_break',
      };

  /// Port of `HYBRID_LAYOUT_BREAK_CHARS`.
  static const Map<String, String> _hybridLayoutBreakChars = <String, String>{
    "'": 'thematic_break',
    '<': 'page_break',
    '-': 'thematic_break',
    '*': 'thematic_break',
    '_': 'thematic_break',
  };

  /// Port of `NESTABLE_LIST_CONTEXTS`.
  static const List<String> _nestableListContexts = <String>[
    'ulist',
    'olist',
    'dlist',
  ];

  /// Port of `ORDERED_LIST_STYLES` (match order is significant).
  static const List<String> _orderedListStyles = <String>[
    'arabic',
    'loweralpha',
    'lowerroman',
    'upperalpha',
    'upperroman',
  ];

  /// Port of `STEM_TYPE_ALIASES` (default when absent is `'asciimath'`).
  static const Map<String, String> _stemTypeAliases = <String, String>{
    'latexmath': 'latexmath',
    'latex': 'latexmath',
    'tex': 'latexmath',
  };

  /// Port of `LINE_CONTINUATION`.
  static const String _lineContinuation = r' \';

  /// Port of `LINE_CONTINUATION_LEGACY`.
  static const String _lineContinuationLegacy = ' +';

  /// Port of `HARD_LINE_BREAK`.
  static const String _hardLineBreak = ' +';

  /// Port of `Parser::AuthorKeys`.
  static const Set<String> _authorKeys = <String>{
    'author',
    'authorinitials',
    'firstname',
    'middlename',
    'lastname',
    'email',
  };

  /// Port of `Parser::TableCellHorzAlignments`.
  static const Map<String, String> _tableCellHorzAlignments = <String, String>{
    '<': 'left',
    '>': 'right',
    '^': 'center',
  };

  /// Port of `Parser::TableCellVertAlignments`.
  static const Map<String, String> _tableCellVertAlignments = <String, String>{
    '<': 'top',
    '>': 'bottom',
    '^': 'middle',
  };

  /// Port of `Parser::TableCellStyles` (symbols become strings).
  static const Map<String, String> _tableCellStyles = <String, String>{
    'd': 'none',
    's': 'strong',
    'e': 'emphasis',
    'm': 'monospaced',
    'h': 'header',
    'l': 'literal',
    'a': 'asciidoc',
  };

  /// Port of `Substitutors::VERBATIM_SUBS` (needed by [_commitSubs]).
  static const List<String> _verbatimSubs = <String>[
    'specialcharacters',
    'callouts',
  ];

  /// Port of `Substitutors::INTRINSIC_ATTRIBUTES` (needed by [_subAttributes]).
  static const Map<String, String> _intrinsicAttributes = <String, String>{
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
  };

  /// Port of `Substitutors::SUB_GROUPS` (needed by [_resolveSubs]).
  static const Map<String, List<String>> _subGroups = <String, List<String>>{
    'none': <String>[],
    'normal': <String>[
      'specialcharacters',
      'quotes',
      'attributes',
      'replacements',
      'macros',
      'post_replacements',
    ],
    'verbatim': <String>['specialcharacters', 'callouts'],
    'specialchars': <String>['specialcharacters'],
  };

  /// Port of `Substitutors::SUB_HINTS` (needed by [_resolveSubs]).
  static const Map<String, String> _subHints = <String, String>{
    'a': 'attributes',
    'm': 'macros',
    'n': 'normal',
    'p': 'post_replacements',
    'q': 'quotes',
    'r': 'replacements',
    'c': 'specialcharacters',
    'v': 'verbatim',
  };

  /// The shared logger (mirrors `Parser.include Logging`).
  static LoggerBase get _logger => LoggerManager.logger;

  /// Matches a whitespace run (for [_splitWhitespace]).
  static final RegExp _whitespaceRx = RegExp(r'\s+');

  /// Matches a leading integer (for [_toInt]).
  static final RegExp _leadingIntRx = RegExp(r'^[+-]?\d+');

  /// Matches leading ASCII whitespace (for [adjustIndentation]).
  static final RegExp _leadingWhitespaceRx = RegExp(r'^[\x00\t\x0b\f\r ]+');

  /// Builds a log message with optional source [location].
  static ContextMessage _msg(String text, [Object? location]) =>
      ContextMessage(text, sourceLocation: location);

  /// Returns the [Document] of [node].
  static Document _docOf(AbstractNode node) => node.document as Document;

  /// TEMP-SEAM (parser): effective doctype of [document].
  ///
  /// [_setDocumentAttribute] cannot reach the document wave's private
  /// doctype updater, so entry-set doctypes only land in the attribute
  /// map; read the map first (it mirrors the field otherwise) and fall
  /// back to the field. Delete with the seam and read
  /// `document.doctype` directly. (If an entry-set doctype is later
  /// unset, this falls back to the stale field where Ruby keeps the
  /// entry value; no test covers that.)
  static String? _doctype(Document document) {
    final fromAttrs = document.attributes['doctype'];
    if (fromAttrs is String) return fromAttrs;
    return document.doctype;
  }

  /// TEMP-SEAM (parser): effective backend of [document].
  ///
  /// Same rationale as [_doctype]; delete with the seam and read
  /// `document.backend` directly.
  static String? _backend(Document document) {
    final fromAttrs = document.attributes['backend'];
    if (fromAttrs is String) return fromAttrs;
    return document.backend;
  }

  /// Wraps a reader [Cursor] as a [NodeSourceLocation].
  static NodeSourceLocation? _loc(Cursor? cursor) =>
      cursor == null ? null : _CursorSourceLocation(cursor);

  /// Converts a parser working map to string keys for block constructors.
  ///
  /// Positional `int` keys become their decimal form (`1` to `'1'`), which
  /// [AbstractNode.attr] resolves identically since it stringifies names.
  /// Returns a fresh map; the input is never modified.
  static Map<String, Object?> _strKeys(Map<Object, Object?> attributes) {
    final result = <String, Object?>{};
    attributes.forEach((key, value) {
      result[key is int ? key.toString() : key as String] = value;
    });
    return result;
  }

  /// The line text of a list-item buffer entry (a [String] or a
  /// [_ListContinuation] marker).
  static String _lineOf(Object? entry) =>
      entry is _ListContinuation ? entry.text : entry as String;

  /// Whether a list-item buffer entry is a [_ListContinuation] marker.
  static bool _isContinuation(Object? entry) => entry is _ListContinuation;

  /// Splits [value] on [sep] with Ruby `split` semantics (trailing empty
  /// fields are dropped).
  static List<String> _rubySplit(String value, String sep) {
    final parts = value.split(sep);
    while (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    return parts;
  }

  /// Splits [value] on [sep] into at most [limit] parts (Ruby `split`
  /// with a limit; the last part keeps the remainder).
  static List<String> _splitLimit(String value, String sep, int limit) {
    final parts = value.split(sep);
    if (parts.length <= limit) return parts;
    return <String>[
      ...parts.sublist(0, limit - 1),
      parts.sublist(limit - 1).join(sep),
    ];
  }

  /// Splits [value] on whitespace runs into at most [limit] parts.
  ///
  /// Port of Ruby `String#split` with a `nil` pattern: leading whitespace
  /// is dropped and trailing empty fields never appear.
  static List<String> _splitWhitespace(String value, [int? limit]) {
    final rest = value.trimLeft();
    if (rest.isEmpty) return <String>[];
    final max = limit ?? 0;
    if (max < 2) return rest.split(_whitespaceRx);
    final parts = <String>[];
    var start = 0;
    while (parts.length < max - 1) {
      final match = _whitespaceRx.firstMatch(rest.substring(start));
      if (match == null) break;
      parts.add(rest.substring(start, start + match.start));
      start += match.end;
    }
    parts.add(rest.substring(start));
    return parts;
  }

  /// The first character of [value] (first rune, mirroring `String#chr`).
  static String _firstChar(String value) =>
      value.isEmpty ? '' : String.fromCharCode(value.runes.first);

  /// Coerces [value] to an integer with Ruby `to_i` semantics.
  ///
  /// `null` and unparsable values become `0`; leading whitespace is
  /// skipped and a leading `[+-]?\d+` run is parsed.
  static int _toInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trimLeft();
    final match = _leadingIntRx.firstMatch(text);
    return match == null ? 0 : int.parse(match.group(0)!);
  }

  // TEMP-SEAM (parser): substitutor ports. Each mirrors a method owned by
  // the substitutors wave (named in the doc comment); delete the seam and
  // route the call to the real API when that wave lands. Substitution
  // coverage here is limited to `specialcharacters` and `attributes`.

  /// TEMP-SEAM (parser): port of `Substitutors#sub_specialchars`.
  static String _subSpecialchars(String text) {
    if (!(text.contains('>') || text.contains('&') || text.contains('<'))) {
      return text;
    }
    // Both Ruby branches agree: only `&`, `<` and `>` are escaped (the
    // gsub branch never touches quotes; the CGI branch only runs when no
    // quotes are present, where its `"` rule is a no-op).
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// TEMP-SEAM (parser): port of `Substitutors#sub_attributes`.
  static String _subAttributes(
    Document document,
    String text, {
    String? attributeMissing,
    String dropLineSeverity = 'info',
  }) {
    if (!text.contains(attrRefHead)) return text;
    final docAttrs = document.attributes;
    var drop = false;
    var dropLine = false;
    var dropEmptyLine = false;
    String? attributeUndefined;
    String? missing;
    final result = text.replaceAllMapped(attributeReferenceRx, (match) {
      final escapeBefore = match.group(1);
      final name = match.group(2)!;
      final setOrCounter = match.group(3);
      final escapeAfter = match.group(4);
      // Escaped attribute; return unescaped.
      if (escapeBefore == _rs || escapeAfter == _rs) return '{$name}';
      if (setOrCounter != null) {
        final args = _splitLimit(name, ':', 3)..removeAt(0);
        switch (setOrCounter) {
          case 'set':
            final stored = storeAttribute(
              args[0],
              args.length > 1 ? args[1] : '',
              document,
            );
            // NOTE since this is an assignment, only drop-line applies
            // here (skip and drop imply the same result).
            if (stored.$2 != null ||
                (attributeUndefined ??=
                        docAttrs['attribute-undefined'] as String? ??
                        Compliance.attributeUndefined) !=
                    'drop-line') {
              drop = true;
              dropEmptyLine = true;
              return _del;
            } else {
              drop = true;
              dropLine = true;
              return _can;
            }
          case 'counter2':
            document.counter(args[0], args.length > 1 ? args[1] : null);
            drop = true;
            dropEmptyLine = true;
            return _del;
          default: // 'counter'
            return document
                .counter(args[0], args.length > 1 ? args[1] : null)
                .toString();
        }
      }
      final key = name.toLowerCase();
      if (docAttrs.containsKey(key)) return '${docAttrs[key]}';
      final intrinsic = _intrinsicAttributes[key];
      if (intrinsic != null) return intrinsic;
      switch (missing ??=
          attributeMissing ??
          docAttrs['attribute-missing'] as String? ??
          _attributeMissing) {
        case 'drop':
          drop = true;
          dropEmptyLine = true;
          return _del;
        case 'drop-line':
          if (dropLineSeverity == 'info') {
            _logger.info(
              'dropping line containing reference to missing attribute: $key',
            );
          }
          drop = true;
          dropLine = true;
          return _can;
        case 'warn':
          _logger.warn('skipping reference to missing attribute: $key');
          return match.group(0)!;
        default: // 'skip'
          return match.group(0)!;
      }
    });
    if (!drop) return result;
    if (dropEmptyLine) {
      final lines = squeezeChar(result, _del).split(lf);
      if (dropLine) {
        return lines
            .where(
              (line) =>
                  line != _del &&
                  line != _can &&
                  !line.startsWith(_can) &&
                  !line.contains(_can),
            )
            .join(lf)
            .replaceAll(_del, '');
      }
      return lines.where((line) => line != _del).join(lf).replaceAll(_del, '');
    }
    if (result.contains(lf)) {
      return result
          .split(lf)
          .where(
            (line) =>
                line != _can && !line.startsWith(_can) && !line.contains(_can),
          )
          .join(lf);
    }
    return '';
  }

  /// TEMP-SEAM (parser): port of `Substitutors#apply_header_subs`
  /// (`specialcharacters`, then `attributes`).
  static String _applyHeaderSubs(Document document, String text) =>
      _subAttributes(document, _subSpecialchars(text));

  /// Assigns the attribute entry [name] to [value] on [document].
  ///
  /// Kept for the substitutors wave's final seam sweep (no remaining
  /// callers: attribute entries route through [Document.setAttribute]).
  // ignore: unused_element
  static String _applyAttributeValueSubs(Document document, String value) {
    final match = attributeEntryPassMacroRx.firstMatch(value);
    if (match == null) return _applyHeaderSubs(document, value);
    var result = match.group(2) ?? '';
    final subs = match.group(1);
    if (subs != null) {
      final resolved = _resolveSubs(subs, 'inline', null, null);
      if (resolved != null) {
        if (resolved.contains('specialcharacters')) {
          result = _subSpecialchars(result);
        }
        if (resolved.contains('attributes')) {
          result = _subAttributes(document, result);
        }
      }
    }
    return result;
  }

  /// Assigns the document attribute [name] to [value].
  ///
  /// Delegates to [Document.setAttribute] (port of `Document#set_attribute`,
  /// lib/asciidoctor/document.rb:870-887), which applies attribute value
  /// substitutions and refreshes the backend/doctype derived attributes
  /// while the header is being parsed.
  static String? _setDocumentAttribute(
    Document document,
    String name,
    String value,
  ) => document.setAttribute(name, value);

  /// TEMP-SEAM (parser): port of `Substitutors#parse_attributes` for the
  /// options the parser uses (`sub_input`, `sub_result`, `into`).
  ///
  /// Single-quoted values are resolved with the partial normal
  /// substitutions (`specialcharacters` and `attributes` only).
  static Map<Object, Object?> _parseAttributes(
    Document document,
    String? attrlist,
    List<String?> posattrs, {
    bool subInput = false,
    bool subResult = false,
    Map<Object, Object?>? into,
  }) {
    if (attrlist == null || attrlist.isEmpty) return <Object, Object?>{};
    var input = attrlist;
    if (subInput && input.contains(attrRefHead)) {
      input = _subAttributes(document, input);
    }
    final parsed = AttributeList(
      input,
      subResult ? _SeamSubsApplier(document) : null,
    ).parse(posattrs);
    if (into != null) {
      into.addAll(parsed);
      return into;
    }
    return Map<Object, Object?>.of(parsed);
  }

  /// TEMP-SEAM (parser): port of `Substitutors#resolve_subs`.
  static List<String>? _resolveSubs(
    String subs,
    String type,
    List<String>? defaults,
    String? subject,
  ) {
    if (subs.isEmpty) return null;
    var input = subs;
    if (input.contains(' ')) input = input.replaceAll(' ', '');
    final modifiersPresent = subModifierSniffRx.hasMatch(input);
    List<String>? candidates;
    for (final rawKey in _rubySplit(input, ',')) {
      var key = rawKey;
      String? modifierOperation;
      if (modifiersPresent) {
        final first = key.isEmpty ? '' : key[0];
        if (first == '+') {
          modifierOperation = 'append';
          key = key.substring(1);
        } else if (first == '-') {
          modifierOperation = 'remove';
          key = key.substring(1);
        } else if (key.endsWith('+')) {
          modifierOperation = 'prepend';
          key = key.substring(0, key.length - 1);
        }
      }
      late final List<String> resolvedKeys;
      if (type == 'inline' && (key == 'verbatim' || key == 'v')) {
        // Special case to disable callouts for inline subs.
        resolvedKeys = _subGroups['specialchars']!;
      } else if (_subGroups.containsKey(key)) {
        resolvedKeys = _subGroups[key]!;
      } else if (type == 'inline' &&
          key.length == 1 &&
          _subHints.containsKey(key)) {
        final resolvedKey = _subHints[key]!;
        final candidate = _subGroups[resolvedKey];
        resolvedKeys = candidate ?? <String>[resolvedKey];
      } else {
        resolvedKeys = <String>[key];
      }
      if (modifierOperation != null) {
        candidates ??= defaults != null
            ? List<String>.of(defaults)
            : <String>[];
        switch (modifierOperation) {
          case 'append':
            candidates.addAll(resolvedKeys);
          case 'prepend':
            candidates = <String>[...resolvedKeys, ...candidates];
          case 'remove':
            candidates.removeWhere(resolvedKeys.contains);
        }
      } else {
        (candidates ??= <String>[]).addAll(resolvedKeys);
      }
    }
    final found = candidates;
    if (found == null) return null;
    final valid = type == 'inline'
        ? const <String>{
            'none',
            'normal',
            'verbatim',
            'specialchars',
            'specialcharacters',
            'quotes',
            'attributes',
            'replacements',
            'macros',
            'post_replacements',
          }
        : const <String>{
            'none',
            'normal',
            'verbatim',
            'specialchars',
            'specialcharacters',
            'quotes',
            'attributes',
            'replacements',
            'macros',
            'post_replacements',
            'callouts',
          };
    final resolved = <String>[];
    for (final candidate in found) {
      if (valid.contains(candidate) && !resolved.contains(candidate)) {
        resolved.add(candidate);
      }
    }
    final invalid = found.where((c) => !valid.contains(c)).toList();
    if (invalid.isNotEmpty) {
      _logger.warn(
        'invalid substitution type${invalid.length > 1 ? 's' : ''}'
        '${subject != null ? ' for ' : ''}${subject ?? ''}: '
        '${invalid.join(', ')}',
      );
    }
    return resolved;
  }

  /// TEMP-SEAM (parser): port of `Substitutors#commit_subs`.
  ///
  /// Mirrors the real [commitSubs], including the `highlight` swap for
  /// source blocks once a highlighting-capable syntax highlighter is set.
  static void _commitSubs(AbstractBlock block) {
    final defaultSubs = block is Block ? block.defaultSubs : null;
    late final List<String> defaults;
    if (defaultSubs == null) {
      switch (block.contentModel) {
        case 'simple':
          defaults = List<String>.of(normalSubs);
        case 'verbatim':
          defaults = block.context == 'verse'
              ? List<String>.of(normalSubs)
              : List<String>.of(_verbatimSubs);
        case 'raw':
          // TODOmake pass subs a compliance setting; AsciiDoc.py performs
          // :attributes and :macros on a pass block.
          defaults = block.context == 'stem'
              ? List<String>.of(basicSubs)
              : <String>[];
        default:
          return;
      }
    } else {
      defaults = List<String>.from(defaultSubs as List<Object?>);
    }
    final customSubs = block.attributes['subs'];
    if (customSubs != null && customSubs != false) {
      block.subs =
          _resolveSubs(
            customSubs as String,
            'block',
            defaults,
            block.context,
          ) ??
          <String>[];
    } else {
      block.subs = defaults;
    }
    // Mirror of the `Substitutors#commit_subs` highlight swap: source
    // blocks highlight through the document highlighter when it can.
    final syntaxHl = _docOf(block).syntaxHighlighter;
    if (block.context == 'listing' &&
        block.style == 'source' &&
        syntaxHl is SyntaxHighlighterBase &&
        syntaxHl.canHighlight) {
      final idx = block.subs.indexOf('specialcharacters');
      if (idx != -1) block.subs[idx] = 'highlight';
    }
  }

  /// TEMP-SEAM (parser): converted title with the partial title
  /// substitutions (`specialcharacters`, then `attributes`).
  ///
  /// Used where Ruby reads `block.title` (conversion plus memoization):
  /// attribute and counter side effects run, but quotes, macros and
  /// replacements need the substitutors wave.
  static String _titleText(AbstractBlock block) {
    final source = block.sourceTitle;
    if (source == null) return '';
    return _subAttributes(_docOf(block), _subSpecialchars(source));
  }

  /// TEMP-SEAM (parser): partial normal substitutions for quote credit
  /// lines (`specialcharacters`, then `attributes`).
  static String _creditText(Document document, String text) =>
      _subAttributes(document, _subSpecialchars(text));

  /// TEMP-SEAM (parser): port of `AttributeList.rekey` for parser working
  /// maps, which hold `Object?` values (attribute entry lists) that
  /// [AttributeList.rekeyAttributes] (`Map<Object, String?>`) rejects.
  /// Positional attribute names from an extension [config] (port of
  /// `ext_config[:positional_attrs] || ext_config[:pos_attrs] || []`).
  static List<String?> _posAttrsOf(Map<String, Object?> config) {
    final value = config['positional_attrs'] ?? config['pos_attrs'];
    if (value is List) return value.map((e) => e?.toString()).toList();
    return <String?>[];
  }

  static void _rekey(Map<Object, Object?> attributes, List<String?> posattrs) {
    for (var index = 0; index < posattrs.length; index++) {
      final key = posattrs[index];
      if (key == null) continue;
      final value = attributes[index + 1];
      if (value == null) continue;
      attributes[key] = value;
    }
  }

  /// TEMP-SEAM (parser): port of `Document::AttributeEntry#save_to` for
  /// parser working maps, which carry `int` positional keys that
  /// [DocumentAttributeEntry.saveTo] (`Map<String, Object?>`) rejects.
  static void _saveAttributeEntry(
    DocumentAttributeEntry entry,
    Map<Object, Object?> attributes,
  ) {
    var entries = attributes['attribute_entries'];
    if (entries == null || entries == false) {
      entries = <DocumentAttributeEntry>[];
      attributes['attribute_entries'] = entries;
    }
    (entries as List<DocumentAttributeEntry>).add(entry);
  }

  /// Whether [value] is `null` or empty (port of `nil_or_empty?`).
  static bool _isNilOrEmpty(Object? value) {
    if (value == null) return true;
    if (value is String) return value.isEmpty;
    if (value is Iterable) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  /// Parses AsciiDoc source read from [reader] into [document].
  ///
  /// Port of `Parser.parse`. Processes the document header, then parses
  /// the body into nested sections and blocks (skipped when [headerOnly]
  /// is set). Returns [document].
  static Document parse(
    Reader reader,
    Document document, {
    bool headerOnly = false,
  }) {
    final blockAttributes = parseDocumentHeader(reader, document, headerOnly);

    if (!headerOnly) {
      while (reader.hasMoreLines()) {
        final (newSection, orphaned) = nextSection(
          reader,
          document,
          blockAttributes,
        );
        // nextSection returns a merged copy; keep the local map in sync.
        blockAttributes
          ..clear()
          ..addAll(orphaned);
        if (newSection != null) {
          document.assignNumeral(newSection);
          document.blocks.add(newSection);
        }
      }
    }

    return document;
  }

  /// Parses the document header of the AsciiDoc source read from [reader].
  ///
  /// Port of `Parser.parse_document_header`. Returns the map of orphan
  /// block attributes captured above the header.
  static Map<Object, Object?> parseDocumentHeader(
    Reader reader,
    Document document, [
    bool headerOnly = false,
  ]) {
    // Capture lines of block-level metadata and plow away comment lines
    // that precede first block.
    final blockAttrs = reader.skipBlankLines() != null
        ? parseBlockMetadataLines(reader, document, <Object, Object?>{})
        : <Object, Object?>{};
    final docAttrs = document.attributes;

    // Special cases, block style or title is not allowed above document
    // title, carry attributes over to the document body.
    final implicitDoctitle = isNextLineDoctitle(
      reader,
      blockAttrs,
      docAttrs['leveloffset'],
    );
    if (implicitDoctitle &&
        (isTruthy(blockAttrs['title']) || isTruthy(blockAttrs['style']))) {
      docAttrs['authorcount'] = 0;
      return document.finalizeHeader(blockAttrs, false);
    }

    String? doctitleAttrVal;
    final presetDoctitle = docAttrs['doctitle'];
    if (!_isNilOrEmpty(presetDoctitle)) {
      document.title = doctitleAttrVal = presetDoctitle as String?;
    }

    // If the first line is the document title, add a header to the
    // document and parse the header metadata.
    if (implicitDoctitle) {
      final sourceLocation = document.sourcemap ? reader.cursor() : null;
      final sectionTitle = parseSectionTitle(reader, document);
      String? l0SectionTitle = sectionTitle.title;
      final atx = sectionTitle.atx;
      if (doctitleAttrVal != null) {
        // NOTE doctitle attribute (set above or below implicit doctitle)
        // overrides implicit doctitle.
        l0SectionTitle = null;
      } else {
        document.title = l0SectionTitle;
        final converted = _subSpecialchars(l0SectionTitle);
        docAttrs['doctitle'] = doctitleAttrVal = converted;
        if (converted.contains(attrRefHead)) {
          // QUESTION should we defer substituting attributes until the end
          // of the header? or should we substitute again if necessary?
          docAttrs['doctitle'] = doctitleAttrVal = _subAttributes(
            document,
            converted,
            attributeMissing: 'skip',
          );
        }
      }
      if (sourceLocation != null) {
        document.header!.sourceLocation = _loc(sourceLocation);
      }
      // Default to compat-mode if document has setext doctitle.
      if (!atx && !document.attributeLocked('compat-mode')) {
        docAttrs['compat-mode'] = '';
      }
      final separator = blockAttrs['separator'];
      if (isTruthy(separator) && !document.attributeLocked('title-separator')) {
        docAttrs['title-separator'] = separator;
      }
      final blockId = blockAttrs['id'];
      String? docId;
      if (isTruthy(blockId)) {
        document.id = docId = blockId as String?;
      } else {
        docId = document.id;
      }
      final role = blockAttrs['role'];
      if (isTruthy(role)) docAttrs['role'] = role;
      final reftext = blockAttrs['reftext'];
      if (isTruthy(reftext)) docAttrs['reftext'] = reftext;
      blockAttrs.clear();
      // TEMP-SEAM (parser): the document wave's `@attributes_modified`
      // set is private; detect a doctitle change by snapshotting the
      // value instead (observably equivalent; see analysis in the port
      // notes). The `elsif` branch only appends to that set, which no
      // ported reader consults for `doctitle`, so it is omitted.
      final doctitleBefore = docAttrs['doctitle'];
      parseHeaderMetadata(reader, document, false);
      if (docAttrs['doctitle'] != doctitleBefore) {
        final val = docAttrs['doctitle'];
        if (_isNilOrEmpty(val) || val == doctitleAttrVal) {
          docAttrs['doctitle'] = doctitleAttrVal;
        } else {
          document.title = val as String?;
        }
      }
      if (docId != null) document.register('refs', [docId, document]);
    } else if (isTruthy(docAttrs['author'])) {
      final authorMetadata = processAuthors(docAttrs['author']!, true, false);
      if (docAttrs.containsKey('authorinitials')) {
        authorMetadata.remove('authorinitials');
      }
      docAttrs.addAll(authorMetadata);
    } else if (isTruthy(docAttrs['authors'])) {
      final authorMetadata = processAuthors(docAttrs['authors']!, true);
      docAttrs.addAll(authorMetadata);
    } else {
      docAttrs['authorcount'] = 0;
    }

    // Parse title and consume name section of manpage document.
    if (_doctype(document) == 'manpage') {
      parseManpageHeader(reader, document, blockAttrs, headerOnly);
    }

    // NOTE blockAttrs are the block-level attributes (not document
    // attributes) that precede the first line of content (document title,
    // first section or first block).
    return document.finalizeHeader(blockAttrs);
  }

  /// Parses the manpage header of the AsciiDoc source read from [reader].
  ///
  /// Port of `Parser.parse_manpage_header`.
  static void parseManpageHeader(
    Reader reader,
    Document document,
    Map<Object, Object?> blockAttributes, [
    bool headerOnly = false,
  ]) {
    final docAttrs = document.attributes;
    final doctitle = docAttrs['doctitle'];
    final volnumMatch = doctitle is String
        ? manpageTitleVolnumRx.firstMatch(doctitle)
        : null;
    late final String manvolnum;
    if (volnumMatch != null) {
      docAttrs['manvolnum'] = manvolnum = volnumMatch.group(2)!;
      final mantitle = volnumMatch.group(1)!;
      docAttrs['mantitle'] =
          (mantitle.contains(attrRefHead)
                  ? _subAttributes(document, mantitle)
                  : mantitle)
              .toLowerCase();
    } else {
      _logger.error(
        _msg('non-conforming manpage title', reader.cursorAtLine(1)),
      );
      // Provide sensible fallbacks.
      docAttrs['mantitle'] =
          docAttrs['doctitle'] ?? docAttrs['docname'] ?? 'command';
      docAttrs['manvolnum'] = manvolnum = '1';
    }
    final mannameAttr = docAttrs['manname'];
    if (isTruthy(mannameAttr) && isTruthy(docAttrs['manpurpose'])) {
      if (!isTruthy(docAttrs['manname-title'])) {
        docAttrs['manname-title'] = 'Name';
      }
      docAttrs['mannames'] = [mannameAttr];
      if (_backend(document) == 'manpage') {
        docAttrs['docname'] = mannameAttr;
        docAttrs['outfilesuffix'] = '.$manvolnum';
      }
    } else if (!headerOnly) {
      reader.skipBlankLines();
      reader.save();
      blockAttributes.addAll(
        parseBlockMetadataLines(reader, document, <Object, Object?>{}),
      );
      String? errorMsg;
      final nameSectionLevel = isNextLineSection(reader, {});
      if (nameSectionLevel != null) {
        if (nameSectionLevel == 1) {
          final nameSection = initializeSection(reader, document, {});
          final nameSectionBuffer = reader
              .readLinesUntil(breakOnBlankLines: true, skipLineComments: true)
              .map((l) => l.trimLeft())
              .join(' ');
          final purposeMatch = manpageNamePurposeRx.firstMatch(
            nameSectionBuffer,
          );
          if (purposeMatch != null) {
            var manname = purposeMatch.group(1)!;
            if (manname.contains(attrRefHead)) {
              manname = _subAttributes(document, manname);
            }
            late final List<String> mannames;
            String? resolvedManname = manname;
            if (manname.contains(',')) {
              mannames = _rubySplit(
                manname,
                ',',
              ).map((n) => n.trimLeft()).toList();
              resolvedManname = mannames.isEmpty ? null : mannames[0];
            } else {
              mannames = [manname];
            }
            var manpurpose = purposeMatch.group(2)!;
            if (manpurpose.contains(attrRefHead)) {
              manpurpose = _subAttributes(document, manpurpose);
            }
            if (!isTruthy(docAttrs['manname-title'])) {
              // TEMP-SEAM (parser): `nameSection.title` needs the
              // substitutors wave; the partial conversion runs the same
              // attribute side effects.
              docAttrs['manname-title'] = _titleText(nameSection);
            }
            if (nameSection.id != null) {
              docAttrs['manname-id'] = nameSection.id;
            }
            docAttrs['manname'] = resolvedManname;
            docAttrs['mannames'] = mannames;
            docAttrs['manpurpose'] = manpurpose;
            if (_backend(document) == 'manpage') {
              docAttrs['docname'] = resolvedManname;
              docAttrs['outfilesuffix'] = '.$manvolnum';
            }
          } else {
            errorMsg = 'non-conforming name section body';
          }
        } else {
          errorMsg = 'name section must be at level 1';
        }
      } else {
        errorMsg = 'name section expected';
      }
      if (errorMsg != null) {
        reader.restoreSave();
        _logger.error(_msg(errorMsg, reader.cursor()));
        final fallback = docAttrs['docname'] ?? 'command';
        docAttrs['manname'] = fallback;
        docAttrs['mannames'] = [fallback];
        if (_backend(document) == 'manpage') {
          docAttrs['docname'] = fallback;
          docAttrs['outfilesuffix'] = '.$manvolnum';
        }
      } else {
        reader.discardSave();
      }
    }
  }

  /// Returns the next section from [reader].
  ///
  /// Port of `Parser.next_section`. Returns a record of the new [Section]
  /// (`null` when [parent] itself was consumed, i.e. the preamble case)
  /// and the map of orphaned attributes for the next section or block.
  static (Section?, Map<Object, Object?>) nextSection(
    Reader reader,
    AbstractBlock parent, [
    Map<Object, Object?>? attributes,
  ]) {
    var attrs = attributes ?? <Object, Object?>{};
    Block? preamble;
    Block? intro;
    var part = false;
    String? sectname;

    late final Document document;
    late final bool book;
    late AbstractBlock section;
    late int currentLevel;
    int? expectedNextLevel;
    int? expectedNextLevelAlt;

    // Check if we are at the start of processing the document.
    var hasHeader = false;
    final parentDocument = parent is Document ? parent : null;
    if (parent.context == 'document' &&
        parent.blocks.isEmpty &&
        ((hasHeader = parentDocument?.hasHeader ?? false) ||
            isTruthy(attrs.remove('invalid-header')) ||
            isNextLineSection(reader, attrs) == null)) {
      document = parentDocument!;
      book = _doctype(document) == 'book';
      if (hasHeader || (book && attrs[1] != 'abstract')) {
        intro = preamble = Block(
          document,
          'preamble',
          contentModel: 'compound',
        );
        if (book && document.hasAttr('preface-title')) {
          preamble.title = document.attr('preface-title') as String?;
        }
        parent.blocks.add(preamble);
      }
      section = parent;
      currentLevel = 0;
      if (document.attributes.containsKey('fragment')) {
        expectedNextLevel = -1;
      } else if (book) {
        // Small tweak to allow subsequent level-0 sections for book doctype.
        expectedNextLevel = 1;
        expectedNextLevelAlt = 0;
      } else {
        expectedNextLevel = 1;
      }
    } else {
      document = _docOf(parent);
      book = _doctype(document) == 'book';
      final newSection = initializeSection(reader, parent, attrs);
      // Clear attributes except for title attribute, which must be carried
      // over to next content block.
      final carriedTitle = attrs['title'];
      attrs = isTruthy(carriedTitle)
          ? <Object, Object?>{'title': carriedTitle}
          : <Object, Object?>{};
      currentLevel = newSection.level!;
      expectedNextLevel = currentLevel + 1;
      section = newSection;
      if (currentLevel == 0) {
        part = book;
      } else if (currentLevel == 1 && newSection.special) {
        // NOTE technically preface sections are only permitted in the book
        // doctype.
        sectname = newSection.sectname;
        if (sectname != 'appendix' &&
            sectname != 'preface' &&
            sectname != 'abstract') {
          expectedNextLevel = null;
        }
      }
    }

    reader.skipBlankLines();

    // Parse lines belonging to this section and its subsections until we
    // reach the end of this section level.
    while (reader.hasMoreLines()) {
      parseBlockMetadataLines(reader, document, attrs);
      var nextLevel = isNextLineSection(reader, attrs);
      if (nextLevel != null) {
        if (document.hasAttr('leveloffset')) {
          nextLevel += _toInt(document.attr('leveloffset'));
          if (nextLevel < 0) nextLevel = 0;
        }
        if (nextLevel > currentLevel) {
          if (expectedNextLevel != null) {
            if (nextLevel != expectedNextLevel &&
                !(expectedNextLevelAlt != null &&
                    nextLevel == expectedNextLevelAlt) &&
                expectedNextLevel >= 0) {
              final expectedCondition = expectedNextLevelAlt != null
                  ? 'expected levels $expectedNextLevelAlt or '
                        '$expectedNextLevel'
                  : 'expected level $expectedNextLevel';
              _logger.warn(
                _msg(
                  'section title out of sequence: $expectedCondition, '
                  'got level $nextLevel',
                  reader.cursor(),
                ),
              );
            }
          } else {
            _logger.error(
              _msg(
                '$sectname sections do not support nested sections',
                reader.cursor(),
              ),
            );
          }
          final (child, childAttrs) = nextSection(reader, section, attrs);
          attrs = childAttrs;
          // The recursive call always takes the section branch, so the
          // child is never null here.
          section.assignNumeral(child!);
          section.blocks.add(child);
        } else if (nextLevel == 0 && identical(section, document)) {
          if (!book) {
            _logger.error(
              _msg(
                'level 0 sections can only be used when doctype is book',
                reader.cursor(),
              ),
            );
          }
          final (child, childAttrs) = nextSection(reader, section, attrs);
          attrs = childAttrs;
          section.assignNumeral(child!);
          section.blocks.add(child);
        } else {
          // Close this section (and break out of the nesting) to begin a
          // new one.
          break;
        }
      } else {
        // Just take one block or else we run the risk of overrunning
        // section boundaries.
        final blockCursor = reader.cursor();
        final newBlock = nextBlock(
          reader,
          intro ?? section,
          attributes: attrs,
          parseMetadata: false,
        );
        if (newBlock != null) {
          // REVIEW this may be doing too much.
          if (part) {
            if (section.blocks.isEmpty) {
              // If this not a [partintro] open block, enclose it in a
              // [partintro] open block.
              if (newBlock.style != 'partintro') {
                // If this is already a normal open block, simply add the
                // partintro style.
                if (newBlock.style == 'open' && newBlock.context == 'open') {
                  newBlock.style = 'partintro';
                } else {
                  final newIntro = Block(
                    section,
                    'open',
                    contentModel: 'compound',
                  );
                  newBlock.parent = newIntro;
                  newIntro.style = 'partintro';
                  section.blocks.add(newIntro);
                  intro = newIntro;
                }
              } else if (newBlock.contentModel == 'simple') {
                // If this is a [partintro] paragraph, convert it to a
                // [partintro] open block w/ single paragraph. (Only a
                // Block can have the simple model; lists and tables
                // never reach this branch.)
                final partBlock = newBlock as Block;
                newBlock.contentModel = 'compound';
                final paragraph = Block(
                  newBlock,
                  'paragraph',
                  source: partBlock.lines,
                );
                // TEMP-SEAM (parser): `subs:` would call the substitutors
                // wave's commitSubs (throws); replicate its fixed-list
                // outcome instead.
                paragraph.defaultSubs = List<String>.of(newBlock.subs);
                paragraph.attributes.remove('subs');
                paragraph.subs = List<String>.of(newBlock.subs);
                newBlock << paragraph;
                partBlock.lines.clear();
                newBlock.subs.clear();
              }
            } else if (section.blocks.length == 1) {
              final firstBlock = section.blocks[0];
              // Open the [partintro] open block for appending.
              if (intro == null && firstBlock.contentModel == 'compound') {
                _logger.error(
                  _msg(
                    'illegal block content outside of partintro block',
                    blockCursor,
                  ),
                );
              } else if (firstBlock.contentModel != 'compound') {
                // Rebuild [partintro] paragraph as an open block.
                final newIntro = Block(
                  section,
                  'open',
                  contentModel: 'compound',
                );
                newBlock.parent = newIntro;
                newIntro.style = 'partintro';
                if (firstBlock.style == 'partintro') {
                  firstBlock.context = 'paragraph';
                  firstBlock.style = null;
                }
                section.blocks.removeAt(0);
                newIntro << firstBlock;
                section.blocks.add(newIntro);
                intro = newIntro;
              }
            }
          }

          (intro ?? section).blocks.add(newBlock);
          attrs.clear();
        }
      }

      if (reader.skipBlankLines() == null) break;
    }

    if (part) {
      if (section.blocks.isEmpty || section.blocks.last.context != 'section') {
        _logger.error(
          _msg(
            'invalid part, must have at least one section (e.g., chapter, '
            'appendix, etc.)',
            reader.cursor(),
          ),
        );
      }
      // NOTE we could try to avoid creating a preamble in the first place,
      // though that would require reworking assumptions in nextSection
      // since the preamble is treated like an untitled section.
    } else if (preamble != null) {
      // Implies parent == document.
      if (preamble.blocks.isNotEmpty) {
        if (book || document.blocks.length > 1 || !_unwrapStandalonePreamble) {
          if (document.sourcemap) {
            preamble.sourceLocation = preamble.blocks[0].sourceLocation;
          }
        } else {
          // Unwrap standalone preamble (i.e., document has no sections)
          // except for books, if permissible.
          document.blocks.removeAt(0);
          while (preamble.blocks.isNotEmpty) {
            document << preamble.blocks.removeAt(0);
          }
        }
      } else {
        // Drop the preamble if it has no content.
        document.blocks.removeAt(0);
      }
    }

    // The attributes returned here are orphaned attributes that fall at the
    // end of a section that need to get transferred to the next section.
    return (
      identical(section, parent) ? null : section as Section,
      Map<Object, Object?>.of(attrs),
    );
  }

  /// Initializes a new [Section] and assigns any attributes provided.
  ///
  /// Port of `Parser.initialize_section`.
  static Section initializeSection(
    Reader reader,
    AbstractBlock parent, [
    Map<Object, Object?>? attributes,
  ]) {
    final attrs = attributes ?? <Object, Object?>{};
    final document = _docOf(parent);
    final doctype = _doctype(document);
    final book = doctype == 'book';
    final sourceLocation = document.sourcemap ? reader.cursor() : null;
    final sectStyle = attrs[1] as String?;
    var (id: sectId, :reftext, title: sectTitle, :level, :atx) =
        parseSectionTitle(reader, document, attrs['id'] as String?);

    String? sectName;
    var sectSpecial = false;
    var sectNumbered = false;
    if (sectStyle != null) {
      if (book && sectStyle == 'abstract') {
        sectName = 'chapter';
        level = 1;
      } else if (sectStyle.startsWith('sect') &&
          sectionLevelStyleRx.hasMatch(sectStyle)) {
        sectName = 'section';
      } else {
        sectName = sectStyle;
        sectSpecial = true;
        if (level == 0) level = 1;
        sectNumbered = sectName == 'appendix';
      }
    } else if (book) {
      sectName = level == 0 ? 'part' : (level > 1 ? 'section' : 'chapter');
    } else if (doctype == 'manpage' && sectTitle.toLowerCase() == 'synopsis') {
      sectName = 'synopsis';
      sectSpecial = true;
    } else {
      sectName = 'section';
    }

    if (reftext != null) attrs['reftext'] = reftext;
    final section = Section(parent, level);
    section.id = sectId;
    section.title = sectTitle;
    section.sectname = sectName;
    section.sourceLocation = _loc(sourceLocation);
    if (sectSpecial) {
      section.special = true;
      if (sectNumbered) {
        section.numbered = true;
      } else if (document.attributes['sectnums'] == 'all') {
        section.numbered = book && level == 1 ? 'chapter' : true;
      }
    } else if (isTruthy(document.attributes['sectnums']) && level > 0) {
      // NOTE a special section here is guaranteed to be nested in another
      // section.
      if (section.special && parent is Section) {
        final parentNumbered = parent.numbered;
        section.numbered = (parentNumbered == null || parentNumbered == false)
            ? parentNumbered
            : true;
      } else {
        section.numbered = true;
      }
    } else if (book &&
        level == 0 &&
        isTruthy(document.attributes['partnums'])) {
      section.numbered = true;
    }

    // Generate an ID if one was not embedded or specified as anchor above
    // section title.
    var id = section.id;
    if (id != null) {
      if (id.isEmpty) {
        section.id = id = null;
      } else if (sectTitle.contains(attrRefHead)) {
        // Convert title to resolve attributes while in scope.
        // TEMP-SEAM (parser): `section.title` needs the substitutors
        // wave; the partial conversion runs the same side effects.
        _titleText(section);
      }
    } else if (document.attributes.containsKey('sectids')) {
      // TEMP-SEAM (parser): `section.title` needs the substitutors wave;
      // the partial conversion feeds the ID generator instead.
      section.id = id = Section.generateId(_titleText(section), document);
    }
    if (id != null) {
      if (document.register('refs', [id, section]) == null) {
        _logger.warn(
          _msg(
            'id assigned to section already in use: $id',
            reader.cursorAtLine(reader.lineno - (atx ? 1 : 2)),
          ),
        );
      }
    }

    section.updateAttributes(_strKeys(attrs));
    reader.skipBlankLines();

    return section;
  }

  /// Checks if the next line on [reader] is a section title.
  ///
  /// Port of `Parser.is_next_line_section?`. Returns the section level, or
  /// `null` when the reader is not positioned at a section title.
  static int? isNextLineSection(
    Reader reader,
    Map<Object, Object?> attributes,
  ) {
    final style = attributes[1] as String?;
    if (style != null && (style == 'discrete' || style == 'float')) return null;
    if (_underlineStyleSectionTitles) {
      final nextLines = reader.peekLines(
        2,
        style != null && style == 'comment',
      );
      return isSectionTitle(
        nextLines.isNotEmpty ? nextLines[0] : '',
        nextLines.length > 1 ? nextLines[1] : null,
      );
    }
    return atxSectionTitle(reader.peekLine() ?? '');
  }

  /// Checks if the next line on [reader] is the document title.
  ///
  /// Port of `Parser.is_next_line_doctitle?`.
  static bool isNextLineDoctitle(
    Reader reader,
    Map<Object, Object?> attributes,
    Object? leveloffset,
  ) {
    if (leveloffset != null) {
      final sectLevel = isNextLineSection(reader, attributes);
      return sectLevel != null && sectLevel + _toInt(leveloffset) == 0;
    }
    return isNextLineSection(reader, attributes) == 0;
  }

  /// Checks whether the lines given are an atx or setext section title.
  ///
  /// Port of `Parser.is_section_title?`. Returns the section level, or
  /// `null` when the lines are not a section title.
  static int? isSectionTitle(String line1, [String? line2]) =>
      atxSectionTitle(line1) ??
      (_isNilOrEmpty(line2) ? null : setextSectionTitle(line1, line2!));

  /// Checks whether the line given is an atx section title.
  ///
  /// Port of `Parser.atx_section_title?`. The level returned is 1 less
  /// than the number of leading markers.
  static int? atxSectionTitle(String line) {
    final match = _markdownSyntax
        ? (line.startsWith('=') || line.startsWith('#'))
              ? extAtxSectionTitleRx.firstMatch(line)
              : null
        : line.startsWith('=')
        ? atxSectionTitleRx.firstMatch(line)
        : null;
    return match == null ? null : match.group(1)!.length - 1;
  }

  /// Checks whether the lines given are a setext section title.
  ///
  /// Port of `Parser.setext_section_title?`.
  static int? setextSectionTitle(String line1, String line2) {
    final line2ch0 = _firstChar(line2);
    final level = _setextSectionLevels[line2ch0];
    if (level == null) return null;
    final line2len = line2.length;
    if (!uniform(line2, line2ch0, line2len)) return null;
    if (!setextSectionTitleRx.hasMatch(line1)) return null;
    if ((line1.length - line2len).abs() >= 2) return null;
    return level;
  }

  /// Parses the section title from the current position of [reader].
  ///
  /// Port of `Parser.parse_section_title`. Returns a record with the id,
  /// reftext, title, level and whether an atx title was matched.
  static ({String? id, String? reftext, String title, int level, bool atx})
  parseSectionTitle(Reader reader, Document document, [String? sectId]) {
    String? sectReftext;
    final line1 = reader.readLine()!;

    String sectTitle;
    int sectLevel;
    bool atx;
    final atxMatch = _markdownSyntax
        ? (line1.startsWith('=') || line1.startsWith('#'))
              ? extAtxSectionTitleRx.firstMatch(line1)
              : null
        : line1.startsWith('=')
        ? atxSectionTitleRx.firstMatch(line1)
        : null;
    if (atxMatch != null) {
      // NOTE level is 1 less than number of line markers.
      sectLevel = atxMatch.group(1)!.length - 1;
      sectTitle = atxMatch.group(2)!;
      atx = true;
      if (sectId == null && sectTitle.endsWith(']]')) {
        final anchorMatch = inlineSectionAnchorRx.firstMatch(sectTitle);
        if (anchorMatch != null && anchorMatch.group(1) == null) {
          sectTitle = sectTitle.substring(
            0,
            sectTitle.length - anchorMatch.group(0)!.length,
          );
          sectId = anchorMatch.group(2);
          sectReftext = anchorMatch.group(3);
        }
      }
    } else {
      final line2 = _underlineStyleSectionTitles ? reader.peekLine(true) : null;
      final line2ch0 = line2 == null ? null : _firstChar(line2);
      final level = line2ch0 == null ? null : _setextSectionLevels[line2ch0];
      final setextMatch =
          line2 != null &&
              level != null &&
              uniform(line2, line2ch0!, line2.length) &&
              (line1.length - line2.length).abs() < 2
          ? setextSectionTitleRx.firstMatch(line1)
          : null;
      if (line2 != null && level != null && setextMatch != null) {
        sectLevel = level;
        sectTitle = setextMatch.group(1)!;
        atx = false;
        if (sectId == null && sectTitle.endsWith(']]')) {
          final anchorMatch = inlineSectionAnchorRx.firstMatch(sectTitle);
          if (anchorMatch != null && anchorMatch.group(1) == null) {
            sectTitle = sectTitle.substring(
              0,
              sectTitle.length - anchorMatch.group(0)!.length,
            );
            sectId = anchorMatch.group(2);
            sectReftext = anchorMatch.group(3);
          }
        }
        reader.shift();
      } else {
        throw StateError(
          'Unrecognized section at ${reader.cursorAtPrevLine()}',
        );
      }
    }
    if (document.hasAttr('leveloffset')) {
      sectLevel += _toInt(document.attr('leveloffset'));
      if (sectLevel < 0) sectLevel = 0;
    }
    return (
      id: sectId,
      reftext: sectReftext,
      title: sectTitle,
      level: sectLevel,
      atx: atx,
    );
  }

  /// Parses and returns the next [Block] at the current location of [reader].
  ///
  /// Port of `Parser.next_block`. Returns `null` when no block is found
  /// (or the line should be dropped).
  static AbstractBlock? nextBlock(
    Reader reader,
    AbstractBlock parent, {
    Map<Object, Object?>? attributes,
    bool textOnly = false,
    String? listType,
    bool parseMetadata = true,
  }) {
    // Skip ahead to the block content; bail if we've reached the end of
    // the reader.
    final skipped = reader.skipBlankLines();
    if (skipped == null) return null;

    // Check for option to find list item text only. If skipped a line,
    // assume a list continuation was used and block content is acceptable.
    var textOnly_ = textOnly;
    if (textOnly_ && skipped > 0) textOnly_ = false;

    final attrs = attributes ?? <Object, Object?>{};
    final document = _docOf(parent);
    final docAttrs = document.attributes;

    if (parseMetadata) {
      // Read lines until there are no more metadata lines to read; note
      // that textOnly impacts parsing rules.
      while (parseBlockMetadataLine(
        reader,
        document,
        attrs,
        textOnly: textOnly_,
      )) {
        // Discard the line just processed.
        reader.shift();
        // QUESTION should we clear the attributes? no known cases when
        // it's necessary.
        if (reader.skipBlankLines() == null) return null;
      }
    }

    // Port of `Parser.next_block` (lib/asciidoctor/parser.rb:528-530).
    final extensions = document.extensions;
    final blockExtensions = extensions?.hasBlocks ?? false;
    final blockMacroExtensions = extensions?.hasBlockMacros ?? false;

    // QUESTION should we introduce a parsing context object?
    reader.mark();
    final thisLine = reader.readLine()!;
    var style = attrs[1] as String?;
    AbstractBlock? block;
    String? blockContext;
    String? cloakedContext;
    String? terminator;
    String? blockTitle;

    final delimitedBlock = isDelimitedBlock(thisLine);
    if (delimitedBlock != null) {
      blockContext = cloakedContext = delimitedBlock.context;
      terminator = delimitedBlock.terminator;
      if (style != null) {
        if (style != blockContext) {
          if (delimitedBlock.masq.contains(style)) {
            blockContext = style;
          } else if (delimitedBlock.masq.contains('admonition') &&
              _admonitionStyles.contains(style)) {
            blockContext = 'admonition';
          } else if (blockExtensions &&
              extensions!.registeredForBlock(style, blockContext) != null) {
            blockContext = style;
          } else {
            if (_logger.isDebugEnabled) {
              _logger.debug(
                _msg(
                  'unknown style for $blockContext block: $style',
                  reader.cursorAtMark(),
                ),
              );
            }
            style = blockContext;
          }
        }
      } else {
        style = attrs['style'] = blockContext;
      }
    }

    // This loop is used for flow control; it only executes once, and only
    // when delimitedBlock is not set. Break once a block is found or at
    // end of loop. Returns null if the line should be dropped.
    while (delimitedBlock == null) {
      // Process lines verbatim.
      if (style != null &&
          _strictVerbatimParagraphs &&
          _verbatimStyles.contains(style)) {
        blockContext = style;
        cloakedContext = 'paragraph';
        reader.unshiftLine(thisLine);
        // Advance to block parsing.
        break;
      }

      // Process lines normally.
      final bool indented;
      String? ch0;
      if (textOnly_) {
        indented = thisLine.startsWith(' ') || thisLine.startsWith(tab);
      } else {
        // NOTE move this declaration up if we need it when textOnly is true.
        if (thisLine.startsWith(' ')) {
          indented = true;
          ch0 = ' ';
          // QUESTION should we test line length?
          final lstripped = thisLine.trimLeft();
          if (_markdownSyntax &&
              _markdownThematicBreakChars.keys.any(lstripped.startsWith) &&
              //!thisLine.startsWith('    ') &&
              markdownThematicBreakRx.hasMatch(thisLine)) {
            // NOTE we're letting break lines (horizontal rule, page_break,
            // etc) have attributes.
            block = Block(parent, 'thematic_break', contentModel: 'empty');
            break;
          }
        } else if (thisLine.startsWith(tab)) {
          indented = true;
          ch0 = tab;
        } else {
          indented = false;
          ch0 = thisLine.isEmpty ? '' : thisLine[0];
          const layoutBreakChars = _markdownSyntax
              ? _hybridLayoutBreakChars
              : _layoutBreakChars;
          if (layoutBreakChars.containsKey(ch0) &&
              (_markdownSyntax
                  ? extLayoutBreakRx.hasMatch(thisLine)
                  : uniform(thisLine, ch0, thisLine.length) &&
                        thisLine.length > 2)) {
            // NOTE we're letting break lines (horizontal rule, page_break,
            // etc) have attributes.
            block = Block(
              parent,
              layoutBreakChars[ch0]!,
              contentModel: 'empty',
            );
            break;
            // NOTE very rare that a text-only line will end in ] (e.g.,
            // inline macro), so check that first.
          } else if (thisLine.endsWith(']') && thisLine.contains('::')) {
            //if (this_line.start_with? 'image', 'video', 'audio') &&
            //    BlockMediaMacroRx =~ this_line
            final mediaMatch =
                (ch0 == 'i' ||
                    thisLine.startsWith('video:') ||
                    thisLine.startsWith('audio:'))
                ? blockMediaMacroRx.firstMatch(thisLine)
                : null;
            if (mediaMatch != null) {
              final blkCtx = mediaMatch.group(1)!;
              var target = mediaMatch.group(2)!;
              final blkAttrs = mediaMatch.group(3);
              block = Block(parent, blkCtx, contentModel: 'empty');
              if (blkAttrs != null) {
                final List<String?> posattrs;
                if (blkCtx == 'video') {
                  posattrs = ['poster', 'width', 'height'];
                } else if (blkCtx == 'audio') {
                  posattrs = [];
                } else {
                  // 'image'
                  posattrs = ['alt', 'width', 'height'];
                }
                _parseAttributes(
                  document,
                  blkAttrs,
                  posattrs,
                  subInput: true,
                  into: attrs,
                );
              }
              // Style doesn't have special meaning for media macros.
              if (attrs.containsKey('style')) attrs.remove('style');
              if (target.contains(attrRefHead)) {
                final expandedTarget = _subAttributes(document, target);
                if (expandedTarget.isEmpty &&
                    (docAttrs['attribute-missing'] as String? ??
                            _attributeMissing) ==
                        'drop-line' &&
                    _subAttributes(
                      document,
                      '$target ',
                      attributeMissing: 'drop-line',
                      dropLineSeverity: 'ignore',
                    ).isEmpty) {
                  attrs.clear();
                  return null;
                }
                target = expandedTarget;
              }
              if (blkCtx == 'image') {
                document.register('images', target);
                if (!isTruthy(attrs['imagesdir'])) {
                  attrs['imagesdir'] = docAttrs['imagesdir'];
                }
                // NOTE style is the value of the first positional
                // attribute in the block attribute line.
                if (!isTruthy(attrs['alt'])) {
                  attrs['alt'] =
                      style ??
                      (attrs['default-alt'] = Helpers.basename(
                        target,
                        true,
                      ).replaceAll('_', ' ').replaceAll('-', ' '));
                }
                final scaledwidth = attrs.remove('scaledwidth') as String?;
                if (!_isNilOrEmpty(scaledwidth)) {
                  // NOTE assume % units if not specified.
                  attrs['scaledwidth'] = trailingDigitsRx.hasMatch(scaledwidth!)
                      ? '$scaledwidth%'
                      : scaledwidth;
                }
                if (isTruthy(attrs['title'])) {
                  block.title = blockTitle = attrs.remove('title') as String?;
                  block.assignCaption(attrs.remove('caption'), 'figure');
                }
              }
              attrs['target'] = target;
              break;
            }
            final tocMatch = ch0 == 't' && thisLine.startsWith('toc:')
                ? blockTocMacroRx.firstMatch(thisLine)
                : null;
            if (tocMatch != null) {
              block = Block(parent, 'toc', contentModel: 'empty');
              final tocAttrs = tocMatch.group(1);
              if (tocAttrs != null) {
                _parseAttributes(
                  document,
                  tocAttrs,
                  [],
                  subInput: true,
                  into: attrs,
                );
              }
              break;
            }
            // Port of `Parser.next_block` (lib/asciidoctor/parser.rb:648-679):
            // custom block macros, including the unknown-macro debug probe.
            final macroMatch = customBlockMacroRx.firstMatch(thisLine);
            ProcessorExtension? macroExtension;
            var reportUnknownBlockMacro = false;
            if (macroMatch != null) {
              if (blockMacroExtensions) {
                macroExtension = extensions!.registeredForBlockMacro(
                  macroMatch.group(1)!,
                );
                if (macroExtension == null) {
                  reportUnknownBlockMacro = _logger.isDebugEnabled;
                }
              } else {
                reportUnknownBlockMacro = _logger.isDebugEnabled;
              }
            }
            if (reportUnknownBlockMacro) {
              _logger.debug(
                _msg(
                  'unknown name for block macro: ${macroMatch!.group(1)}',
                  reader.cursorAtMark(),
                ),
              );
            } else if (macroExtension != null) {
              final content = macroMatch!.group(3);
              var target = macroMatch.group(2)!;
              if (target.contains(attrRefHead)) {
                final expandedTarget = _subAttributes(document, target);
                if (expandedTarget.isEmpty &&
                    (docAttrs['attribute-missing'] as String? ??
                            _attributeMissing) ==
                        'drop-line' &&
                    _subAttributes(
                      document,
                      '$target ',
                      attributeMissing: 'drop-line',
                      dropLineSeverity: 'ignore',
                    ).isEmpty) {
                  attrs.clear();
                  return null;
                } else {
                  target = expandedTarget;
                }
              }
              final extConfig = macroExtension.config;
              if (extConfig['content_model'] == 'attributes') {
                if (content != null) {
                  _parseAttributes(
                    document,
                    content,
                    _posAttrsOf(extConfig),
                    subInput: true,
                    into: attrs,
                  );
                }
              } else {
                attrs['text'] = content ?? '';
              }
              final defaultAttrs = extConfig['default_attrs'];
              if (defaultAttrs is Map) {
                for (final entry in defaultAttrs.entries) {
                  final defaultKey = entry.key as Object;
                  if (!attrs.containsKey(defaultKey)) {
                    attrs[defaultKey] = entry.value;
                  }
                }
              }
              final macroBlock =
                  (macroExtension.processMethod
                      as Object? Function(
                        AbstractBlock,
                        String,
                        Map<Object, Object?>,
                      ))(parent, target, attrs);
              if (macroBlock is AbstractBlock &&
                  !identical(macroBlock, parent)) {
                // `attributes.replace block.attributes`: the extension
                // result owns the attribute set from here on.
                attrs
                  ..clear()
                  ..addAll(macroBlock.attributes);
                block = macroBlock;
                break;
              } else {
                attrs.clear();
                return null;
              }
            }
          }
        }
      }

      // Haven't found anything yet, continue.
      ch0 ??= thisLine.isEmpty ? '' : thisLine[0];
      final calloutMatch = !indented && ch0 == '<'
          ? calloutListRx.firstMatch(thisLine)
          : null;
      final dlistMatch =
          (thisLine.contains('::') || thisLine.contains(';;')) &&
              calloutMatch == null &&
              !unorderedListRx.hasMatch(thisLine) &&
              !orderedListRx.hasMatch(thisLine)
          ? descriptionListRx.firstMatch(thisLine)
          : null;
      if (calloutMatch != null) {
        reader.unshiftLine(thisLine);
        block = parseCalloutList(
          reader,
          calloutMatch,
          parent,
          document.callouts,
        );
        attrs['style'] = 'arabic';
        break;
      } else if (unorderedListRx.hasMatch(thisLine)) {
        reader.unshiftLine(thisLine);
        if (style == null &&
            parent is Section &&
            parent.sectname == 'bibliography') {
          attrs['style'] = style = 'bibliography';
        }
        block = parseList(reader, 'ulist', parent, style);
        break;
      } else if (orderedListRx.hasMatch(thisLine)) {
        reader.unshiftLine(thisLine);
        block = parseList(
          reader,
          'olist',
          parent,
          style,
          start: attrs.remove('start'),
        );
        if (block.style != null) attrs['style'] = block.style;
        break;
      } else if (dlistMatch != null) {
        reader.unshiftLine(thisLine);
        block = parseDescriptionList(reader, dlistMatch, parent);
        break;
      } else if ((style == 'float' || style == 'discrete') &&
          (_underlineStyleSectionTitles
              ? isSectionTitle(thisLine, reader.peekLine()) != null
              : !indented && atxSectionTitle(thisLine) != null)) {
        reader.unshiftLine(thisLine);
        final floatTitle = parseSectionTitle(
          reader,
          document,
          attrs['id'] as String?,
        );
        if (floatTitle.reftext != null) {
          attrs['reftext'] = floatTitle.reftext;
        }
        block = Block(parent, 'floating_title', contentModel: 'empty');
        block.title = floatTitle.title;
        attrs.remove('title');
        // TEMP-SEAM (parser): `block.title` needs the substitutors wave;
        // the partial conversion feeds the ID generator instead.
        block.id =
            floatTitle.id ??
            (docAttrs.containsKey('sectids')
                ? Section.generateId(_titleText(block), document)
                : null);
        block.level = floatTitle.level;
        break;

        // FIXME create another set for "passthrough" styles
        // FIXME make this more DRY!
      } else if (style != null && style != 'normal') {
        if (_paragraphStyles.contains(style)) {
          blockContext = style;
          cloakedContext = 'paragraph';
          reader.unshiftLine(thisLine);
          // Advance to block parsing.
          break;
        } else if (_admonitionStyles.contains(style)) {
          blockContext = 'admonition';
          cloakedContext = 'paragraph';
          reader.unshiftLine(thisLine);
          // Advance to block parsing.
          break;
          // Port of `Parser.next_block` (lib/asciidoctor/parser.rb:737-741).
        } else if (blockExtensions &&
            extensions!.registeredForBlock(style, 'paragraph') != null) {
          blockContext = style;
          cloakedContext = 'paragraph';
          reader.unshiftLine(thisLine);
          // Advance to block parsing.
          break;
        } else {
          if (_logger.isDebugEnabled) {
            _logger.debug(
              _msg(
                'unknown style for paragraph: $style',
                reader.cursorAtMark(),
              ),
            );
          }
          style = null;
          // Continue to process paragraph.
        }
      }

      reader.unshiftLine(thisLine);

      // A literal paragraph: contiguous lines starting with at least one
      // whitespace character.
      // NOTE style can only be null or "normal" at this point.
      if (indented && style == null) {
        final contentAdjacent = skipped == 0 ? listType : null;
        final lines = readParagraphLines(
          reader,
          contentAdjacent,
          skipLineComments: textOnly_,
        );
        adjustIndentation(lines);
        if (textOnly_ || contentAdjacent == 'dlist') {
          // This block gets folded into the list item text.
          block = Block(
            parent,
            'paragraph',
            contentModel: 'simple',
            source: lines,
            attributes: _strKeys(attrs),
          );
        } else {
          block = Block(
            parent,
            'literal',
            contentModel: 'verbatim',
            source: lines,
            attributes: _strKeys(attrs),
          );
        }
      } else {
        // A normal paragraph: contiguous non-blank/non-continuation lines
        // (left-indented or normal style).
        final lines = readParagraphLines(
          reader,
          skipped == 0 ? listType : null,
          skipLineComments: true,
        );
        final admonitionMatch =
            _admonitionStyleHeads.contains(ch0) && thisLine.contains(':')
            ? admonitionParagraphRx.firstMatch(thisLine)
            : null;
        // NOTE don't check indented here since it's extremely rare
        //if text_only || indented
        if (textOnly_) {
          // If [normal] is used over an indented paragraph, shift content
          // to left margin.
          // QUESTION do we even need to shift since whitespace is
          // normalized by XML in this case?
          if (indented && style == 'normal') adjustIndentation(lines);
          block = Block(
            parent,
            'paragraph',
            contentModel: 'simple',
            source: lines,
            attributes: _strKeys(attrs),
          );
        } else if (admonitionMatch != null) {
          lines[0] = thisLine.substring(admonitionMatch.end);
          attrs['style'] = admonitionMatch.group(1);
          final admonitionName = (attrs['style'] as String).toLowerCase();
          attrs['name'] = admonitionName;
          final caption = attrs.remove('caption');
          attrs['textlabel'] = isTruthy(caption)
              ? caption
              : docAttrs['$admonitionName-caption'];
          block = Block(
            parent,
            'admonition',
            contentModel: 'simple',
            source: lines,
            attributes: _strKeys(attrs),
          );
        } else if (_markdownSyntax && ch0 == '>' && thisLine.startsWith('> ')) {
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            lines[i] = line == '>'
                ? line.substring(1)
                : line.startsWith('> ')
                ? line.substring(2)
                : line;
          }
          String? creditLine;
          if (lines.isNotEmpty && lines.last.startsWith('-- ')) {
            final popped = lines.removeLast();
            creditLine = popped.substring(3);
            while (lines.isNotEmpty && lines.last.isEmpty) {
              lines.removeLast();
            }
          }
          attrs['style'] = 'quote';
          // NOTE will only detect discrete (aka free-floating) headings
          // TODOcould assume a discrete heading when inside a block context
          // FIXME Reader needs to be created w/ line info
          block = buildBlock(
            'quote',
            'compound',
            false,
            parent,
            Reader(lines),
            attrs,
          )!;
          if (creditLine != null) {
            final parts = _splitLimit(
              _creditText(document, creditLine),
              ', ',
              2,
            );
            final attribution = parts[0];
            final citetitle = parts.length > 1 ? parts[1] : null;
            attrs['attribution'] = attribution;
            if (citetitle != null) attrs['citetitle'] = citetitle;
          }
        } else if (ch0 == '"' &&
            lines.length > 1 &&
            lines.last.startsWith('-- ') &&
            lines[lines.length - 2].endsWith('"')) {
          lines[0] = thisLine.substring(1); // strip leading quote
          final popped = lines.removeLast();
          final creditLine = popped.substring(3);
          while (lines.isNotEmpty && lines.last.isEmpty) {
            lines.removeLast();
          }
          final stripped = lines.removeLast();
          lines.add(
            stripped.substring(0, stripped.length - 1),
          ); // strip trailing quote
          attrs['style'] = 'quote';
          block = Block(
            parent,
            'quote',
            contentModel: 'simple',
            source: lines,
            attributes: _strKeys(attrs),
          );
          final parts = _splitLimit(_creditText(document, creditLine), ', ', 2);
          final attribution = parts[0];
          final citetitle = parts.length > 1 ? parts[1] : null;
          attrs['attribution'] = attribution;
          if (citetitle != null) attrs['citetitle'] = citetitle;
        } else {
          // If [normal] is used over an indented paragraph, shift content
          // to left margin.
          // QUESTION do we even need to shift since whitespace is
          // normalized by XML in this case?
          if (indented && style == 'normal') adjustIndentation(lines);
          block = Block(
            parent,
            'paragraph',
            contentModel: 'simple',
            source: lines,
            attributes: _strKeys(attrs),
          );
        }

        catalogInlineAnchors(lines.join(lf), block, document, reader);
      }

      break; // forbid loop from executing more than once
    }

    // Either delimited block or styled paragraph.
    if (block == null) {
      final bc = blockContext!;
      if (bc == 'listing' || bc == 'source') {
        Object? language;
        if (bc != 'source') {
          language = isTruthy(attrs[1])
              ? null
              : (isTruthy(attrs[2]) ? attrs[2] : docAttrs['source-language']);
        }
        if (bc == 'source' || isTruthy(language)) {
          if (isTruthy(language)) {
            // :listing with language
            attrs['style'] = 'source';
            attrs['language'] = language;
            _rekey(attrs, [null, null, 'linenums']);
          } else {
            // :source
            _rekey(attrs, [null, 'language', 'linenums']);
            if (docAttrs.containsKey('source-language') &&
                !attrs.containsKey('language')) {
              attrs['language'] = docAttrs['source-language'];
            }
            if (cloakedContext != 'listing') {
              attrs['cloaked-context'] = cloakedContext;
            }
          }
          if (!attrs.containsKey('linenums-option') &&
              (attrs.containsKey('linenums') ||
                  docAttrs.containsKey('source-linenums-option'))) {
            attrs['linenums-option'] = '';
          }
          if (!attrs.containsKey('indent') &&
              docAttrs.containsKey('source-indent')) {
            attrs['indent'] = docAttrs['source-indent'];
          }
        }
        block = buildBlock(
          'listing',
          'verbatim',
          terminator,
          parent,
          reader,
          attrs,
        );
      } else if (bc == 'fenced_code') {
        attrs['style'] = 'source';
        String? language;
        final ll = thisLine.length;
        if (ll > 3) {
          final info = thisLine.substring(3);
          language = info;
          final commaIdx = info.indexOf(',');
          if (commaIdx >= 0) {
            if (commaIdx > 0) {
              language = info.substring(0, commaIdx).trim();
              if (commaIdx < ll - 4) attrs['linenums'] = '';
            } else if (ll > 4) {
              attrs['linenums'] = '';
            }
          } else {
            language = info.trimLeft();
          }
        }
        if (_isNilOrEmpty(language)) {
          if (docAttrs.containsKey('source-language')) {
            attrs['language'] = docAttrs['source-language'];
          }
        } else {
          attrs['language'] = language;
        }
        attrs['cloaked-context'] = cloakedContext;
        if (!attrs.containsKey('linenums-option') &&
            (attrs.containsKey('linenums') ||
                docAttrs.containsKey('source-linenums-option'))) {
          attrs['linenums-option'] = '';
        }
        if (!attrs.containsKey('indent') &&
            docAttrs.containsKey('source-indent')) {
          attrs['indent'] = docAttrs['source-indent'];
        }
        terminator = terminator!.substring(0, 3);
        block = buildBlock(
          'listing',
          'verbatim',
          terminator,
          parent,
          reader,
          attrs,
        );
      } else if (bc == 'table') {
        final blockCursor = reader.cursor();
        final tableReader = Reader(
          reader.readLinesUntil(
            terminator: terminator,
            skipLineComments: true,
            context: 'table',
            cursor: Reader.atMark,
          ),
          blockCursor,
        );
        // NOTE it's very rare that format is set when using a format hint
        // char, so short-circuit.
        if (!terminator!.startsWith('|') && !terminator.startsWith('!')) {
          // NOTE infer dsv once all other format hint chars are ruled out.
          if (!isTruthy(attrs['format'])) {
            attrs['format'] = terminator.startsWith(',') ? 'csv' : 'dsv';
          }
        }
        block = parseTable(tableReader, parent, attrs);
      } else if (bc == 'sidebar') {
        block = buildBlock(bc, 'compound', terminator, parent, reader, attrs);
      } else if (bc == 'admonition') {
        final admonitionName = style!.toLowerCase();
        attrs['name'] = admonitionName;
        final caption = attrs.remove('caption');
        attrs['textlabel'] = isTruthy(caption)
            ? caption
            : docAttrs['$admonitionName-caption'];
        block = buildBlock(bc, 'compound', terminator, parent, reader, attrs);
      } else if (bc == 'open' || bc == 'abstract' || bc == 'partintro') {
        block = buildBlock(
          'open',
          'compound',
          terminator,
          parent,
          reader,
          attrs,
        );
      } else if (bc == 'literal') {
        block = buildBlock(bc, 'verbatim', terminator, parent, reader, attrs);
      } else if (bc == 'example') {
        if (isTruthy(attrs['collapsible-option'])) attrs['caption'] = '';
        block = buildBlock(bc, 'compound', terminator, parent, reader, attrs);
      } else if (bc == 'quote' || bc == 'verse') {
        _rekey(attrs, [null, 'attribution', 'citetitle']);
        block = buildBlock(
          bc,
          bc == 'verse' ? 'verbatim' : 'compound',
          terminator,
          parent,
          reader,
          attrs,
        );
      } else if (bc == 'stem' || bc == 'latexmath' || bc == 'asciimath') {
        if (bc == 'stem') {
          attrs['style'] =
              _stemTypeAliases[attrs[2] ?? docAttrs['stem']] ?? 'asciimath';
        }
        block = buildBlock('stem', 'raw', terminator, parent, reader, attrs);
      } else if (bc == 'pass') {
        block = buildBlock(bc, 'raw', terminator, parent, reader, attrs);
      } else if (bc == 'comment') {
        buildBlock(bc, 'skip', terminator, parent, reader, attrs);
        attrs.clear();
        return null;
      } else {
        // Port of `Parser.next_block` (lib/asciidoctor/parser.rb:905-923):
        // custom block contexts handled by a registered extension.
        ProcessorExtension? blockExtension;
        if (blockExtensions) {
          blockExtension = extensions!.registeredForBlock(bc, cloakedContext!);
        }
        if (blockExtension == null) {
          // This should only happen if there's a misconfiguration.
          throw StateError('Unsupported block type $bc at ${reader.cursor()}');
        }
        final extConfig = blockExtension.config;
        final contentModel = extConfig['content_model'] as String?;
        if (contentModel != 'skip') {
          final positionalAttrs = _posAttrsOf(extConfig);
          if (positionalAttrs.isNotEmpty) {
            _rekey(attrs, [null, ...positionalAttrs]);
          }
          final defaultAttrs = extConfig['default_attrs'];
          if (defaultAttrs is Map) {
            for (final entry in defaultAttrs.entries) {
              final defaultKey = entry.key as Object;
              if (!isTruthy(attrs[defaultKey])) {
                attrs[defaultKey] = entry.value;
              }
            }
          }
          // QUESTION should we clone the extension for each cloaked
          // context and set in config?
          attrs['cloaked-context'] = cloakedContext;
        }
        final customBlock = buildBlock(
          bc,
          contentModel ?? 'compound',
          terminator,
          parent,
          reader,
          attrs,
          extension: blockExtension,
        );
        if (customBlock == null) {
          attrs.clear();
          return null;
        }
        block = customBlock;
      }
    }

    // FIXME we've got to clean this up, it's horrible!
    final result = block!;
    if (document.sourcemap) {
      result.sourceLocation = _loc(reader.cursorAtMark());
    }
    // FIXME title and caption should be assigned when block is constructed
    // (though we need to handle all cases)
    if (isTruthy(attrs['title'])) {
      result.title = blockTitle = attrs.remove('title') as String?;
      if (captionAttributeNames.containsKey(result.context)) {
        result.assignCaption(attrs.remove('caption'));
      }
    }
    // TODOeventually remove the style attribute from the attributes hash
    //block.style = attributes.delete 'style'
    result.style = attrs['style'] as String?;
    final blockId = result.id ?? (result.id = attrs['id'] as String?);
    if (blockId != null) {
      // Convert title to resolve attributes while in scope.
      // TEMP-SEAM (parser): `result.title` needs the substitutors wave;
      // the partial conversion runs the same side effects.
      if (blockTitle != null) {
        if (blockTitle.contains(attrRefHead)) _titleText(result);
      } else if (result.hasTitle) {
        _titleText(result);
      }
      if (document.register('refs', [blockId, result]) == null) {
        _logger.warn(
          _msg(
            'id assigned to block already in use: $blockId',
            reader.cursorAtMark(),
          ),
        );
      }
    }
    // FIXME remove the need for this update!
    if (attrs.isNotEmpty) result.updateAttributes(_strKeys(attrs));
    _commitSubs(result);

    //if doc_attrs.key? :pending_attribute_entries
    //  doc_attrs.delete(:pending_attribute_entries).each do |entry|
    //    entry.save_to block.attributes
    //  end
    //end

    if (result.hasSub('callouts')) {
      // Only simple content-model blocks can carry the callouts sub, so
      // this is always a Block here (lists and tables short-circuit in
      // _commitSubs, exactly like Ruby, which would fail on `source`).
      // No need to sub callouts if none are found when cataloging.
      if (!catalogCallouts((result as Block).source(), document)) {
        result.removeSub('callouts');
      }
    }

    return result;
  }

  /// Reads paragraph lines from [reader], stopping at blank lines, list
  /// continuations and (depending on [breakAtList]) block/list starts.
  ///
  /// Port of `Parser.read_paragraph_lines`.
  static List<String> readParagraphLines(
    Reader reader,
    Object? breakAtList, {
    bool skipLineComments = false,
    bool skipProcessing = false,
  }) {
    final bool Function(String)? breakCondition;
    if (isTruthy(breakAtList)) {
      breakCondition = _blockTerminatesParagraph
          ? _startOfBlockOrList
          : _startOfList;
    } else {
      breakCondition = _blockTerminatesParagraph ? _startOfBlock : null;
    }
    return reader.readLinesUntil(
      breakOnBlankLines: true,
      breakOnListContinuation: true,
      preserveLastLine: true,
      skipLineComments: skipLineComments,
      skipProcessing: skipProcessing,
      test: breakCondition,
    );
  }

  /// Whether [line] starts a block (port of `StartOfBlockProc`).
  static bool _startOfBlock(String line) =>
      (line.startsWith('[') && blockAttributeLineRx.hasMatch(line)) ||
      isDelimitedBlock(line) != null;

  /// Whether [line] starts a list (port of `StartOfListProc`).
  static bool _startOfList(String line) => anyListRx.hasMatch(line);

  /// Whether [line] starts a block or list
  /// (port of `StartOfBlockOrListProc`).
  static bool _startOfBlockOrList(String line) =>
      isDelimitedBlock(line) != null ||
      (line.startsWith('[') && blockAttributeLineRx.hasMatch(line)) ||
      anyListRx.hasMatch(line);

  /// Determines whether [line] is the start of a known delimited block.
  ///
  /// Port of `Parser.is_delimited_block?`. Returns the [BlockMatchData]
  /// when it is, else `null`. (Ruby returns `true` instead of the data
  /// unless `return_match_data` is set; every call site only needs
  /// truthiness or the data, so the port always returns the data.)
  static BlockMatchData? isDelimitedBlock(String line) {
    // Highly optimized for best performance.
    final lineLen = line.length;
    if (lineLen <= 1 || !_delimitedBlockHeads.contains(line.substring(0, 2))) {
      return null;
    }
    // Open block.
    String tip;
    int tipLen;
    var workLine = line;
    var workLen = lineLen;
    if (lineLen == 2) {
      tip = line;
      tipLen = 2;
    } else {
      // All other delimited blocks, including fenced code.
      if (lineLen < 5) {
        tip = line;
        tipLen = lineLen;
      } else {
        tipLen = 4;
        tip = line.substring(0, 4);
      }
      // Special case for fenced code blocks.
      if (_markdownSyntax && tip.startsWith('`')) {
        if (tipLen == 4) {
          final fullTip = tip;
          tip = tip.substring(0, tip.length - 1);
          if (fullTip == '````' || tip != '```') {
            return null;
          }
          workLine = tip;
          workLen = tipLen = 3;
        } else if (tip != '```') {
          return null;
        }
      } else if (tipLen == 3) {
        return null;
      }
    }
    // NOTE line matches the tip when delimiter is minimum length or
    // fenced code.
    final entry = _delimitedBlocks[tip];
    if (entry == null) return null;
    if (workLen == tipLen ||
        uniform(
          workLine.substring(1),
          _delimitedBlockTails[tip]!,
          workLen - 1,
        )) {
      return BlockMatchData(entry.$1, entry.$2, tip, workLine);
    }
    return null;
  }

  /// Builds a block of [blockContext] with [contentModel] from [reader].
  ///
  /// Port of `Parser.build_block`. [terminator] is the delimiter line, or
  /// `null` for a styled paragraph, or `false` when [reader] is already
  /// prepared. When [extension] is given, its process method builds the
  /// block instead. Returns the block, or `null` for the `skip` model (or
  /// when the extension returns `null` or the parent).
  static AbstractBlock? buildBlock(
    String blockContext,
    String contentModel,
    Object? terminator,
    AbstractBlock parent,
    Reader reader,
    Map<Object, Object?> attributes, {
    ProcessorExtension? extension,
  }) {
    final bool skipProcessing;
    final String parseAsContentModel;
    if (contentModel == 'skip') {
      skipProcessing = true;
      parseAsContentModel = 'simple';
    } else if (contentModel == 'raw') {
      skipProcessing = false;
      parseAsContentModel = 'simple';
    } else {
      skipProcessing = false;
      parseAsContentModel = contentModel;
    }

    var model = contentModel;
    List<String>? lines;
    Reader? blockReader;
    if (terminator == null) {
      if (parseAsContentModel == 'verbatim') {
        lines = reader.readLinesUntil(
          breakOnBlankLines: true,
          breakOnListContinuation: true,
        );
      } else {
        if (model == 'compound') model = 'simple';
        // TODOwe could also skip processing if we're able to detect
        // reader is a BlockReader.
        lines = readParagraphLines(
          reader,
          null,
          skipLineComments: true,
          skipProcessing: skipProcessing,
        );
        // QUESTION check for empty lines after grabbing lines for simple
        // content model?
      }
    } else if (parseAsContentModel != 'compound') {
      lines = reader.readLinesUntil(
        terminator: terminator as String,
        skipProcessing: skipProcessing,
        context: blockContext,
        cursor: Reader.atMark,
      );
    } else if (identical(terminator, false)) {
      // Terminator is false when reader has already been prepared.
      blockReader = reader;
    } else {
      final blockCursor = reader.cursor();
      blockReader = Reader(
        reader.readLinesUntil(
          terminator: terminator as String,
          skipProcessing: skipProcessing,
          context: blockContext,
          cursor: Reader.atMark,
        ),
        blockCursor,
      );
    }

    if (model == 'verbatim') {
      final tabsizeRaw = isTruthy(attributes['tabsize'])
          ? attributes['tabsize']
          : _docOf(parent).attributes['tabsize'];
      final tabSize = _toInt(tabsizeRaw);
      final indent = attributes['indent'];
      if (isTruthy(indent)) {
        adjustIndentation(lines!, _toInt(indent), tabSize);
      } else if (tabSize > 0) {
        adjustIndentation(lines!, -1, tabSize);
      }
    } else if (model == 'skip') {
      // QUESTION should we still invoke process method if extension is
      // specified?
      return null;
    }

    // Port of `Parser.build_block` (lib/asciidoctor/parser.rb:1039-1054).
    final AbstractBlock block;
    if (extension != null) {
      // QUESTION do we want to delete the style?
      attributes.remove('style');
      final processAttrs = <String, Object?>{
        for (final entry in attributes.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final extBlock =
          (extension.processMethod
              as Object? Function(AbstractBlock, Reader, Map<String, Object?>))(
            parent,
            blockReader ?? Reader(lines),
            processAttrs,
          );
      if (extBlock == null || identical(extBlock, parent)) return null;
      block = extBlock as AbstractBlock;
      attributes
        ..clear()
        ..addAll(block.attributes);
      // NOTE an extension can change the content model from simple to
      // compound. It's up to the extension to decide which one to use. The
      // extension can consult the cloaked-context attribute to determine
      // if the input is a paragraph or delimited block.
      if (block.contentModel == 'compound' &&
          block is Block &&
          block.lines.isNotEmpty) {
        model = 'compound';
        blockReader = Reader(block.lines);
      }
    } else {
      block = Block(
        parent,
        blockContext,
        contentModel: model,
        source: lines,
        attributes: _strKeys(attributes),
      );
    }

    // Reader is confined within boundaries of a delimited block, so look
    // for blocks until there are no more lines.
    if (model == 'compound') parseBlocks(blockReader!, block);

    return block;
  }

  /// Parses blocks from [reader] until there are no more lines.
  ///
  /// Port of `Parser.parse_blocks`.
  static void parseBlocks(
    Reader reader,
    AbstractBlock parent, [
    Map<Object, Object?>? attributes,
  ]) {
    while (true) {
      final block = nextBlock(
        reader,
        parent,
        attributes: attributes == null
            ? null
            : Map<Object, Object?>.of(attributes),
      );
      if (block != null) {
        parent.blocks.add(block);
      } else if (!reader.hasMoreLines()) {
        break;
      }
    }
  }

  /// Parses an ordered or unordered list at the current position of [reader].
  ///
  /// Port of `Parser.parse_list`.
  static ListBlock parseList(
    Reader reader,
    String listType,
    AbstractBlock parent,
    String? style, {
    Object? start,
  }) {
    final listBlock = isTruthy(start) && _toInt(start) != 1
        ? ListBlock(
            parent,
            listType,
            attributes: <String, Object?>{'start': _toInt(start)},
          )
        : ListBlock(parent, listType);
    final listRx = listRxMap[listType]!;

    while (reader.hasMoreLines()) {
      final peeked = reader.peekLine();
      final match = peeked == null ? null : listRx.firstMatch(peeked);
      if (match == null) break;
      // NOTE parseListItem will stop at sibling item or end of list; never
      // sees ancestor items.
      listBlock.items.add(
        parseListItem(reader, listBlock, match, match.group(1)!, style),
      );
      if (reader.skipBlankLines() == null) break;
    }

    return listBlock;
  }

  /// Catalogs any callouts found in [text], but doesn't process them.
  ///
  /// Port of `Parser.catalog_callouts`. Returns whether callouts were found.
  static bool catalogCallouts(String text, Document document) {
    if (!text.contains('<')) return false;
    var found = false;
    var autonum = 0;
    for (final match in calloutScanRx.allMatches(text)) {
      if (!match.group(0)!.startsWith(r'\')) {
        final num = match.group(2)!;
        document.callouts.register(num == '.' ? ++autonum : int.parse(num));
      }
      // We have to mark as found even if it's escaped so it can be
      // unescaped.
      found = true;
    }
    return found;
  }

  /// Catalogs a matched inline anchor.
  ///
  /// Port of `Parser.catalog_inline_anchor`.
  static void catalogInlineAnchor(
    String id,
    String? reftext,
    AbstractNode node,
    Object? location, [
    Document? doc,
  ]) {
    final document = doc ?? _docOf(node);
    var ref = reftext;
    if (ref != null && ref.contains(attrRefHead)) {
      ref = _subAttributes(document, ref);
    }
    if (document.register('refs', [
          id,
          Inline(
            node as AbstractBlock,
            'anchor',
            text: ref,
            type: 'ref',
            id: id,
          ),
        ]) ==
        null) {
      if (location is Reader) location = location.cursor();
      _logger.warn(_msg('id assigned to anchor already in use: $id', location));
    }
  }

  /// Catalogs any inline anchors found in [text] (but doesn't convert).
  ///
  /// Port of `Parser.catalog_inline_anchors`.
  static void catalogInlineAnchors(
    String text,
    AbstractBlock block,
    Document document,
    Reader reader,
  ) {
    if (!text.contains('[[') && !text.contains('or:')) return;
    for (final match in inlineAnchorScanRx.allMatches(text)) {
      final String id;
      String? reftext;
      if (match.group(1) != null) {
        id = match.group(1)!;
        reftext = match.group(2);
        if (reftext != null && reftext.contains(attrRefHead)) {
          reftext = _subAttributes(document, reftext);
          if (reftext.isEmpty) continue;
        }
      } else {
        id = match.group(3)!;
        reftext = match.group(4);
        if (reftext != null) {
          if (reftext.contains(']')) {
            reftext = reftext.replaceAll(r'\]', ']');
            if (reftext.contains(attrRefHead)) {
              reftext = _subAttributes(document, reftext);
            }
          } else if (reftext.contains(attrRefHead)) {
            reftext = _subAttributes(document, reftext);
            if (reftext.isEmpty) reftext = null;
          }
        }
      }
      if (document.register('refs', [
            id,
            Inline(block, 'anchor', text: reftext, type: 'ref', id: id),
          ]) ==
          null) {
        final mark = reader.cursorAtMark();
        final pre = text.substring(0, match.start);
        final offset =
            '\n'.allMatches(pre).length +
            (match.group(0)!.startsWith('\n') ? 1 : 0);
        final location = offset > 0
            ? Cursor(mark.file, mark.dir, mark.path, mark.lineno + offset)
            : mark;
        _logger.warn(
          _msg('id assigned to anchor already in use: $id', location),
        );
      }
    }
  }

  /// Catalogs the bibliography inline anchor at the start of a list item.
  ///
  /// Port of `Parser.catalog_inline_biblio_anchor`.
  static void catalogInlineBiblioAnchor(
    String id,
    String? reftext,
    AbstractNode node,
    Reader reader,
  ) {
    // QUESTION should we sub attributes in reftext (like with regular
    // anchors)?
    if (_docOf(node).register('refs', [
          id,
          Inline(
            node as AbstractBlock,
            'anchor',
            text: reftext == null ? null : '[$reftext]',
            type: 'bibref',
            id: id,
          ),
        ]) ==
        null) {
      _logger.warn(
        _msg(
          'id assigned to bibliography anchor already in use: $id',
          reader.cursor(),
        ),
      );
    }
  }

  /// Parses a description list from the current position of [reader].
  ///
  /// Port of `Parser.parse_description_list`.
  static ListBlock parseDescriptionList(
    Reader reader,
    RegExpMatch match,
    AbstractBlock parent,
  ) {
    final listBlock = ListBlock(parent, 'dlist');
    // Detects a description list item that uses the same delimiter
    // (::, :::, :::: or ;;).
    final siblingPattern = descriptionListSiblingRx[match.group(2)!]!;
    var currentPair = parseListItem(
      reader,
      listBlock,
      match,
      siblingPattern,
    ) as List<Object?>;
    listBlock.items.add(currentPair);

    while (reader.hasMoreLines()) {
      final peeked = reader.peekLine();
      final sibling = peeked == null ? null : siblingPattern.firstMatch(peeked);
      if (sibling == null) break;
      final nextPair = parseListItem(
        reader,
        listBlock,
        sibling,
        siblingPattern,
      ) as List<Object?>;
      if (currentPair[1] != null) {
        currentPair = nextPair;
        listBlock.items.add(currentPair);
      } else {
        (currentPair[0] as List<Object?>).add(
          (nextPair[0] as List<Object?>)[0],
        );
        currentPair[1] = nextPair[1];
      }
    }

    return listBlock;
  }

  /// Parses a callout list from the current position of [reader] and
  /// advances [callouts] to the next list.
  ///
  /// Port of `Parser.parse_callout_list`.
  static ListBlock parseCalloutList(
    Reader reader,
    RegExpMatch firstMatch,
    AbstractBlock parent,
    Callouts callouts,
  ) {
    final listBlock = ListBlock(parent, 'colist');
    var nextIndex = 1;
    var autonum = 0;
    RegExpMatch? match = firstMatch;
    // NOTE skip the match on the first time through as we've already done
    // it (emulates begin...while).
    while (true) {
      if (match == null) {
        final peeked = reader.peekLine();
        final rematch = peeked == null
            ? null
            : calloutListRx.firstMatch(peeked);
        if (rematch == null || !reader.mark()) break;
        match = rematch;
      }
      var num = match.group(1)!;
      if (num == '.') num = (++autonum).toString();
      // Might want to move this check to a validate method.
      if (num != nextIndex.toString()) {
        _logger.warn(
          _msg(
            'callout list item index: expected $nextIndex, got $num',
            reader.cursorAtMark(),
          ),
        );
      }
      final current = match;
      match = null;
      final listItem =
          parseListItem(reader, listBlock, current, '<1>') as ListItem;
      listBlock.items.add(listItem);
      final coids = callouts.calloutIds(listBlock.items.length);
      if (coids.isEmpty) {
        _logger.warn(
          _msg(
            'no callout found for <${listBlock.items.length}>',
            reader.cursorAtMark(),
          ),
        );
      } else {
        listItem.attributes['coids'] = coids;
      }
      nextIndex += 1;
    }

    callouts.nextList();
    return listBlock;
  }

  /// Parses the next list item (or description term/description pair).
  ///
  /// Port of `Parser.parse_list_item`. Returns the next [ListItem], or a
  /// `[terms, description]` pair (a `List`) for description lists.
  static Object parseListItem(
    Reader reader,
    ListBlock listBlock,
    RegExpMatch match,
    Object siblingTrait, [
    String? style,
  ]) {
    final listType = listBlock.context;
    final dlist = listType == 'dlist';
    late final ListItem listItem;
    ListItem? listTerm;
    var hasText = false;
    var sourcemapAssignmentDeferred = false;
    if (dlist) {
      final termText = match.group(1)!;
      listTerm = ListItem(listBlock, termText);
      final termAnchor = termText.startsWith('[[')
          ? leadingInlineAnchorRx.firstMatch(termText)
          : null;
      if (termAnchor != null) {
        catalogInlineAnchor(
          termAnchor.group(1)!,
          termAnchor.group(2) ?? termText.substring(termAnchor.end).trimLeft(),
          listTerm,
          reader,
        );
      }
      final itemText = match.group(3);
      if (itemText != null) hasText = true;
      listItem = ListItem(listBlock, itemText);
      if (_docOf(listBlock).sourcemap) {
        listTerm.sourceLocation = _loc(reader.cursor());
        if (hasText) {
          listItem.sourceLocation = listTerm.sourceLocation;
        } else {
          sourcemapAssignmentDeferred = true;
        }
      }
    } else {
      hasText = true;
      final itemText = match.group(2)!;
      listItem = ListItem(listBlock, itemText);
      if (_docOf(listBlock).sourcemap) {
        listItem.sourceLocation = _loc(reader.cursor());
      }
      if (listType == 'ulist') {
        listItem.marker = siblingTrait as String;
        if (itemText.startsWith('[')) {
          if (style != null && style == 'bibliography') {
            final biblioMatch = inlineBiblioAnchorRx.firstMatch(itemText);
            if (biblioMatch != null) {
              catalogInlineBiblioAnchor(
                biblioMatch.group(1)!,
                biblioMatch.group(2),
                listItem,
                reader,
              );
            }
          } else if (itemText.startsWith('[[')) {
            final anchorMatch = leadingInlineAnchorRx.firstMatch(itemText);
            if (anchorMatch != null) {
              catalogInlineAnchor(
                anchorMatch.group(1)!,
                anchorMatch.group(2),
                listItem,
                reader,
              );
            }
          } else if (itemText.startsWith('[ ] ') ||
              itemText.startsWith('[x] ') ||
              itemText.startsWith('[*] ')) {
            listBlock.attributes['checklist-option'] = '';
            listItem.attributes['checkbox'] = '';
            if (!itemText.startsWith('[ ')) {
              listItem.attributes['checked'] = '';
            }
            listItem.text = itemText.substring(4);
          }
        }
      } else if (listType == 'olist') {
        var ordinal = listBlock.items.length;
        final first = ordinal == 0;
        var validate = true;
        final startAttr = listBlock.attributes['start'];
        if (startAttr != null) {
          ordinal += (startAttr as int) - 1;
        } else if (first) {
          final start = resolveOrderedListStart(siblingTrait as String);
          if (start != 1) {
            listBlock.attributes['start'] = start;
            ordinal += start - 1;
            validate = false;
          }
        }
        final (resolvedMarker, implicitStyle) = resolveOrderedListMarker(
          siblingTrait as String,
          ordinal,
          validate,
          reader,
        );
        siblingTrait = resolvedMarker;
        listItem.marker = resolvedMarker;
        if (first && style == null) {
          // Using list level makes more sense, but we don't track it.
          // Basing style on marker level is compliant with AsciiDoc.py.
          final fallbackIndex = resolvedMarker.length - 1;
          listBlock.style =
              implicitStyle ??
              (fallbackIndex >= 0 && fallbackIndex < _orderedListStyles.length
                  ? _orderedListStyles[fallbackIndex]
                  : 'arabic');
        }
        if (itemText.startsWith('[[')) {
          final anchorMatch = leadingInlineAnchorRx.firstMatch(itemText);
          if (anchorMatch != null) {
            catalogInlineAnchor(
              anchorMatch.group(1)!,
              anchorMatch.group(2),
              listItem,
              reader,
            );
          }
        }
      } else {
        // 'colist'
        listItem.marker = siblingTrait as String;
        if (itemText.startsWith('[[')) {
          final anchorMatch = leadingInlineAnchorRx.firstMatch(itemText);
          if (anchorMatch != null) {
            catalogInlineAnchor(
              anchorMatch.group(1)!,
              anchorMatch.group(2),
              listItem,
              reader,
            );
          }
        }
      }
    }

    // First skip the line with the marker / term (it gets put back onto
    // the reader by nextBlock).
    reader.shift();
    final blockCursor = reader.cursor();
    final listItemReader = Reader(
      readLinesForListItem(reader, listType, siblingTrait, hasText),
      blockCursor,
    );
    if (listItemReader.hasMoreLines()) {
      if (sourcemapAssignmentDeferred) {
        listItem.sourceLocation = _loc(blockCursor);
      }
      // NOTE peek on the other side of any comment lines.
      final commentLines = listItemReader.skipLineComments();
      final subsequentLine = listItemReader.peekLine();
      var contentAdjacent = false;
      if (subsequentLine != null) {
        if (commentLines.isNotEmpty) {
          listItemReader.unshiftLines(commentLines);
        }
        if (subsequentLine.isNotEmpty) {
          contentAdjacent = true;
          // Treat lines as paragraph text if continuation does not connect
          // first block (i.e., has_text = nil).
          if (!dlist) hasText = false;
        }
      }

      // Reader is confined to boundaries of list, which means only blocks
      // will be found (no sections).
      final firstBlock = nextBlock(
        listItemReader,
        listItem,
        attributes: {},
        textOnly: !hasText,
        listType: listType,
      );
      if (firstBlock != null) listItem.blocks.add(firstBlock);

      while (listItemReader.hasMoreLines()) {
        final block = nextBlock(
          listItemReader,
          listItem,
          attributes: {},
          listType: listType,
        );
        if (block != null) listItem.blocks.add(block);
      }

      if (contentAdjacent &&
          listItem.blocks.isNotEmpty &&
          listItem.blocks[0].context == 'paragraph') {
        listItem.foldFirst();
      }
    }

    if (dlist) {
      final description = listItem.hasText || listItem.blocks.isNotEmpty
          ? listItem
          : null;
      return <Object?>[
        <ListItem>[listTerm!],
        description,
      ];
    }
    return listItem;
  }

  /// Collects the lines belonging to the current list item.
  ///
  /// Port of `Parser.read_lines_for_list_item`.
  static List<String> readLinesForListItem(
    Reader reader,
    String listType, [
    Object? siblingTrait,
    bool hasText = true,
  ]) {
    final buffer = <Object>[];

    // Three states for continuation: inactive, active & frozen.
    // Frozen signifies we've detected sequential continuation lines &
    // continuation is not permitted until reset.
    var continuation = 'inactive';

    // If we are within a nested list, we don't throw away the list
    // continuation marks because they will be processed when grabbing
    // the lines for those nested lists.
    var withinNestedList = false;

    // A detached continuation is a list continuation that follows a blank
    // line; it gets associated with the outermost block.
    int? detachedContinuation;

    final dlist = listType == 'dlist';
    var hasText_ = hasText;

    String? pendingLine;
    while (reader.hasMoreLines()) {
      final rawLine = reader.readLine();
      if (rawLine == null) break;
      pendingLine = rawLine;

      // If we've arrived at a sibling item in this list, we've captured
      // the complete list item and can begin processing it. The remainder
      // of the method determines whether we've reached the termination
      // of the list.
      if (isSiblingListItem(rawLine, listType, siblingTrait)) break;

      final thisLine = rawLine == listContinuation
          ? _ListContinuation.active
          : rawLine;
      final prevLine = buffer.isEmpty ? null : buffer.last;

      if (_isContinuation(prevLine)) {
        if (continuation == 'inactive') {
          continuation = 'active';
          hasText_ = true;
          if (!withinNestedList) {
            buffer[buffer.length - 1] = _ListContinuation.placeholder;
          }
        }

        // Dealing with adjacent list continuations (which is really a
        // syntax error).
        if (_isContinuation(thisLine)) {
          if (continuation != 'frozen') {
            continuation = 'frozen';
            buffer.add(thisLine);
          }
          pendingLine = null;
          continue;
        }
      }

      // A delimited block immediately breaks the list unless preceded
      // by a list continuation (they are harsh like that ;0).
      final delimitedMatch = thisLine is String
          ? isDelimitedBlock(thisLine)
          : null;
      if (delimitedMatch != null) {
        if (continuation != 'active') break;
        buffer.add(thisLine);
        // Grab all the lines in the block, leaving the delimiters in
        // place. We're being more strict here about the terminator, but
        // I think that's a good thing.
        buffer.addAll(
          reader.readLinesUntil(
            terminator: delimitedMatch.terminator,
            readLastLine: true,
            context: null,
          ),
        );
        continuation = 'inactive';
      } else if (dlist &&
          continuation != 'active' &&
          thisLine is String &&
          thisLine.startsWith('[') &&
          blockAttributeLineRx.hasMatch(thisLine)) {
        // BlockAttributeLineRx only breaks dlist if ensuing line is not a
        // list item.
        final blockAttributeLines = <String>[thisLine];
        var interrupt = false;
        while (true) {
          final nextLine = reader.peekLine();
          if (nextLine == null) break;
          if (isDelimitedBlock(nextLine) != null) {
            interrupt = true;
          } else if (nextLine.isEmpty ||
              (nextLine.startsWith('[') &&
                  blockAttributeLineRx.hasMatch(nextLine))) {
            blockAttributeLines.add(reader.readLine()!);
            continue;
          } else if (anyListRx.hasMatch(nextLine) &&
              !isSiblingListItem(nextLine, listType, siblingTrait)) {
            buffer.addAll(blockAttributeLines);
          } else {
            interrupt = true;
          }
          break;
        }
        if (interrupt) {
          pendingLine = null;
          reader.unshiftLines(blockAttributeLines);
          break;
        }
      } else if (continuation == 'active' && _lineOf(thisLine).isNotEmpty) {
        // Literal paragraphs have special considerations (and this is one
        // of two entry points into one). If we don't process it as a
        // whole, then a line in it that looks like a list item will throw
        // off the exit from it.
        if (literalParagraphRx.hasMatch(_lineOf(thisLine))) {
          reader.unshiftLine(_lineOf(thisLine));
          if (dlist) {
            // We may be in an indented list disguised as a literal
            // paragraph, so we need to make sure we don't slurp up a
            // legitimate sibling.
            buffer.addAll(
              reader.readLinesUntil(
                preserveLastLine: true,
                breakOnBlankLines: true,
                breakOnListContinuation: true,
                test: (line) => isSiblingListItem(line, listType, siblingTrait),
              ),
            );
          } else {
            buffer.addAll(
              reader.readLinesUntil(
                preserveLastLine: true,
                breakOnBlankLines: true,
                breakOnListContinuation: true,
              ),
            );
          }
          continuation = 'inactive';
        } else if (_lineOf(thisLine) case final text
            when (text.startsWith('.') && blockTitleRx.hasMatch(text)) ||
                (text.startsWith('[') && blockAttributeLineRx.hasMatch(text)) ||
                (text.startsWith(':') && attributeEntryRx.hasMatch(text))) {
          // Let block metadata play out until we find the block.
          buffer.add(thisLine);
        } else {
          final nested = _findNestedList(
            _lineOf(thisLine),
            withinNestedList ? const ['dlist'] : _nestableListContexts,
          );
          if (nested != null) {
            withinNestedList = true;
            if (nested.$1 == 'dlist' && _isNilOrEmpty(nested.$2.group(3))) {
              // Get greedy again.
              hasText_ = false;
            }
          }
          buffer.add(thisLine);
          continuation = 'inactive';
        }
      } else if (prevLine != null && _lineOf(prevLine).isEmpty) {
        var current = _lineOf(thisLine);
        // Advance to the next line of content.
        if (current.isEmpty) {
          // Stop reading if we reach eof.
          if (reader.skipBlankLines() == null) {
            pendingLine = null;
            break;
          }
          final advanced = reader.readLine();
          if (advanced == null) {
            pendingLine = null;
            break;
          }
          current = advanced;
          // Stop reading if we hit a sibling list item.
          if (isSiblingListItem(current, listType, siblingTrait)) {
            pendingLine = current;
            break;
          }
        }

        if (current == listContinuation) {
          detachedContinuation = buffer.length;
          buffer.add(_ListContinuation.active);
        } else if (hasText_) {
          // Has_text only relevant for dlist, which is more greedy until
          // it has text for an item; has_text is always true for all other
          // lists. In this block, we have to see whether we stay in the
          // list.
          // TODOany way to combine this with the check after skipping
          // blank lines?
          if (isSiblingListItem(current, listType, siblingTrait)) {
            pendingLine = current;
            break;
          }
          final nested = _findNestedList(current, _nestableListContexts);
          if (nested != null) {
            buffer.add(current);
            withinNestedList = true;
            if (nested.$1 == 'dlist' && _isNilOrEmpty(nested.$2.group(3))) {
              // Get greedy again.
              hasText_ = false;
            }
          } else if (literalParagraphRx.hasMatch(current)) {
            // Slurp up any literal paragraph offset by blank lines.
            // NOTE we have to check for indented list items first.
            reader.unshiftLine(current);
            if (dlist) {
              // We may be in an indented list disguised as a literal
              // paragraph, so we need to make sure we don't slurp up a
              // legitimate sibling.
              buffer.addAll(
                reader.readLinesUntil(
                  preserveLastLine: true,
                  breakOnBlankLines: true,
                  breakOnListContinuation: true,
                  test: (line) =>
                      isSiblingListItem(line, listType, siblingTrait),
                ),
              );
            } else {
              buffer.addAll(
                reader.readLinesUntil(
                  preserveLastLine: true,
                  breakOnBlankLines: true,
                  breakOnListContinuation: true,
                ),
              );
            }
          } else {
            pendingLine = current;
            break;
          }
        } else {
          // Only dlist in need of item text, so slurp it up!
          // Pop the blank line so it's not interpreted as a list
          // continuation.
          if (!withinNestedList) buffer.removeLast();
          buffer.add(current);
          hasText_ = true;
        }
      } else if (_isContinuation(thisLine)) {
        hasText_ = true;
        buffer.add(thisLine);
      } else {
        final text = _lineOf(thisLine);
        if (text.isNotEmpty) {
          hasText_ = true;
          final nested = _findNestedList(
            text,
            withinNestedList ? const ['dlist'] : _nestableListContexts,
          );
          if (nested != null) {
            withinNestedList = true;
            if (nested.$1 == 'dlist' && _isNilOrEmpty(nested.$2.group(3))) {
              // Get greedy again.
              hasText_ = false;
            }
          }
        }
        buffer.add(thisLine);
      }
      pendingLine = null;
    }

    if (pendingLine != null) reader.unshiftLine(pendingLine);

    if (detachedContinuation != null) {
      buffer[detachedContinuation] = _ListContinuation.placeholder;
    }

    while (buffer.isNotEmpty) {
      final lastLine = buffer.last;
      if (_isContinuation(lastLine)) {
        // Drop optional trailing continuation.
        buffer.removeLast();
        break;
      } else if (_lineOf(lastLine).isEmpty) {
        // Strip trailing blank lines to prevent empty blocks.
        buffer.removeLast();
      } else {
        break;
      }
    }

    return buffer.map(_lineOf).toList();
  }

  /// Finds the first list context in [contexts] matching [line].
  ///
  /// Returns the context and match, or `null` when nothing matches.
  static (String, RegExpMatch)? _findNestedList(
    String line,
    List<String> contexts,
  ) {
    for (final context in contexts) {
      final match = listRxMap[context]!.firstMatch(line);
      if (match != null) return (context, match);
    }
    return null;
  }

  /// Resolves the 0-index marker for a list item.
  ///
  /// Port of `Parser.resolve_list_marker`.
  static String resolveListMarker(String listType, String marker) {
    if (listType == 'ulist') return marker;
    if (listType == 'olist') return resolveOrderedListMarker(marker).$1;
    // 'colist'
    return '<1>';
  }

  /// Resolves the 0-index marker for an ordered list item.
  ///
  /// Port of `Parser.resolve_ordered_list_marker`. Returns the first
  /// marker in the number series and, when [ordinal] is given, the
  /// implicit list style.
  static (String, String?) resolveOrderedListMarker(
    String marker, [
    int? ordinal,
    bool validate = false,
    Reader? reader,
  ]) {
    if (marker.startsWith('.')) return (marker, null);
    // NOTE case statement is guaranteed to match one of the conditions.
    String? style;
    for (final candidate in _orderedListStyles) {
      if (orderedListMarkerRxMap[candidate]!.hasMatch(marker)) {
        style = candidate;
        break;
      }
    }
    var expected = '';
    var actual = '';
    var resolved = marker;
    if (style == 'arabic') {
      if (validate) {
        expected = (ordinal! + 1).toString();
        actual = _toInt(marker).toString(); // remove trailing .
      }
      resolved = '1.';
    } else if (style == 'loweralpha') {
      if (validate) {
        expected = String.fromCharCode(97 + ordinal!); // 97 is a
        actual = marker.substring(0, marker.length - 1); // remove .
      }
      resolved = 'a.';
    } else if (style == 'upperalpha') {
      if (validate) {
        expected = String.fromCharCode(65 + ordinal!); // 65 is A
        actual = marker.substring(0, marker.length - 1); // remove .
      }
      resolved = 'A.';
    } else if (style == 'lowerroman') {
      if (validate) {
        expected = Helpers.intToRoman(ordinal! + 1).toLowerCase();
        actual = marker.substring(0, marker.length - 1); // remove )
      }
      resolved = 'i)';
    } else if (style == 'upperroman') {
      if (validate) {
        expected = Helpers.intToRoman(ordinal! + 1);
        actual = marker.substring(0, marker.length - 1); // remove )
      }
      resolved = 'I)';
    }

    if (ordinal != null) {
      if (validate && expected != actual) {
        _logger.warn(
          _msg(
            'list item index: expected $expected, got $actual',
            reader!.cursor(),
          ),
        );
      }
      return (resolved, style);
    }
    return (resolved, null);
  }

  /// Resolves the start value for an ordered list marker.
  ///
  /// Port of `Parser.resolve_ordered_list_start`.
  static int resolveOrderedListStart(String marker) {
    var start = 1;
    if (marker.startsWith('.')) return start;
    String? style;
    for (final candidate in _orderedListStyles) {
      if (orderedListMarkerRxMap[candidate]!.hasMatch(marker)) {
        style = candidate;
        break;
      }
    }
    if (style == 'arabic') {
      start = _toInt(marker); // remove trailing . and coerce to int
    } else if (style == 'loweralpha') {
      start =
          marker.substring(0, marker.length - 1).codeUnitAt(0) -
          96; // remove trailing .
    } else if (style == 'upperalpha') {
      start =
          marker.substring(0, marker.length - 1).codeUnitAt(0) -
          64; // remove trailing .
    } else if (style == 'lowerroman') {
      start = Helpers.romanToInt(
        marker.substring(0, marker.length - 1).toUpperCase(),
      ); // remove trailing )
    } else if (style == 'upperroman') {
      start = Helpers.romanToInt(
        marker.substring(0, marker.length - 1),
      ); // remove trailing )
    }
    return start;
  }

  /// Determines whether [line] is a sibling list item.
  ///
  /// Port of `Parser.is_sibling_list_item?`. [siblingTrait] is the list
  /// marker or (for description lists) the sibling pattern.
  static bool isSiblingListItem(
    String line,
    String listType,
    Object? siblingTrait,
  ) {
    if (siblingTrait == null) return false;
    if (siblingTrait is RegExp) return siblingTrait.hasMatch(line);
    final match = listRxMap[listType]!.firstMatch(line);
    return match != null &&
        siblingTrait == resolveListMarker(listType, match.group(1)!);
  }

  /// Parses the table contained in [tableReader].
  ///
  /// Port of `Parser.parse_table`.
  static Table parseTable(
    Reader tableReader,
    AbstractBlock parent,
    Map<Object, Object?> attributes,
  ) {
    final table = Table(parent, _strKeys(attributes));

    var explicitColspecs = false;
    if (attributes.containsKey('cols')) {
      final colspecs = parseColspecs(attributes['cols'] as String);
      if (colspecs.isNotEmpty) {
        table.createColumns(colspecs);
        explicitColspecs = true;
      }
    }

    final skipped = tableReader.skipBlankLines() ?? 0;
    var implicitHeader = false;
    if (isTruthy(attributes['header-option'])) {
      table.hasHeaderOption = true;
    } else if (skipped == 0 && !isTruthy(attributes['noheader-option'])) {
      // NOTE assume table has header until we know otherwise; if it
      // doesn't (nil), cells in first row get reprocessed.
      table.hasHeaderOption = 'implicit';
      implicitHeader = true;
    }
    final parserCtx = TableParserContext(
      tableReader,
      table,
      _strKeys(attributes),
    );
    final format = parserCtx.format!;
    var loopIdx = -1;
    int? implicitHeaderBoundary;

    String? line;
    while ((line = tableReader.readLine()) != null) {
      var current = line;
      loopIdx += 1;
      final beyondFirst = loopIdx > 0;
      if (beyondFirst && current!.isEmpty) {
        current = null;
        if (implicitHeaderBoundary != null) implicitHeaderBoundary += 1;
      } else if (format == 'psv') {
        if (parserCtx.startsWithDelimiter(current!)) {
          current = current.substring(1);
          // Push empty cell spec if cell boundary appears at start of line.
          parserCtx.closeOpenCell();
          if (implicitHeaderBoundary != null) implicitHeaderBoundary = null;
        } else {
          final (nextCellspec, rest) = parseCellspec(
            current,
            'start',
            parserCtx.delimiter,
          );
          // If cellspec is not nil, we're at a cell boundary.
          if (nextCellspec != null) {
            parserCtx.closeOpenCell(nextCellspec);
            if (implicitHeaderBoundary != null) {
              implicitHeaderBoundary = null;
            }
          } else if (implicitHeaderBoundary != null &&
              implicitHeaderBoundary == loopIdx) {
            // Otherwise, the cell continues from previous line.
            table.hasHeaderOption = null;
            implicitHeader = false;
            implicitHeaderBoundary = null;
          }
          current = rest;
        }
      }

      if (!beyondFirst) {
        tableReader.mark();
        // NOTE implicit header is offset by at least one blank line;
        // implicit_header_boundary tracks size of gap.
        if (implicitHeader) {
          if (tableReader.hasMoreLines() &&
              (tableReader.peekLine() ?? '').isEmpty) {
            implicitHeaderBoundary = 1;
          } else {
            table.hasHeaderOption = null;
            implicitHeader = false;
          }
        }
      }

      // This loop is used for flow control; internal logic controls how
      // many times it executes.
      while (true) {
        final delimiterMatch = current == null
            ? null
            : parserCtx.matchDelimiter(current);
        if (current != null && delimiterMatch != null) {
          final preMatch = current.substring(0, delimiterMatch.start);
          final postMatch = current.substring(delimiterMatch.end);
          if (format == 'csv') {
            if (parserCtx.bufferHasUnclosedQuotes(preMatch)) {
              parserCtx.skipPastDelimiter(preMatch);
              current = postMatch;
              if (current.isEmpty) break;
              continue;
            }
            parserCtx.buffer = '${parserCtx.buffer}$preMatch';
          } else if (format == 'dsv') {
            if (preMatch.endsWith(r'\')) {
              parserCtx.skipPastEscapedDelimiter(preMatch);
              current = postMatch;
              if (current.isEmpty) {
                parserCtx.buffer = '${parserCtx.buffer}$lf';
                parserCtx.keepCellOpen();
                break;
              }
              continue;
            }
            parserCtx.buffer = '${parserCtx.buffer}$preMatch';
          } else {
            // psv
            if (preMatch.endsWith(r'\')) {
              parserCtx.skipPastEscapedDelimiter(preMatch);
              current = postMatch;
              if (current.isEmpty) {
                parserCtx.buffer = '${parserCtx.buffer}$lf';
                parserCtx.keepCellOpen();
                break;
              }
              continue;
            }
            final (nextCellspec, cellText) = parseCellspec(preMatch);
            parserCtx.pushCellspect(nextCellspec);
            parserCtx.buffer = '${parserCtx.buffer}$cellText';
          }
          // Don't break if empty to preserve empty cell found at end of
          // line (see issue #1106).
          current = postMatch;
          if (current.isEmpty) current = null;
          parserCtx.closeCell();
        } else {
          // No other delimiters to see here; suck up this line into the
          // buffer and move on.
          parserCtx.buffer = '${parserCtx.buffer}${current ?? ''}$lf';
          if (format == 'csv') {
            if (parserCtx.bufferHasUnclosedQuotes()) {
              if (implicitHeaderBoundary != null && loopIdx == 0) {
                table.hasHeaderOption = null;
                implicitHeader = false;
                implicitHeaderBoundary = null;
              }
              parserCtx.keepCellOpen();
            } else {
              parserCtx.closeCell(true);
            }
          } else if (format == 'dsv') {
            parserCtx.closeCell(true);
          } else {
            // psv
            parserCtx.keepCellOpen();
          }
          break;
        }
      }

      // NOTE cell may already be closed if table format is csv or dsv.
      if (parserCtx.isCellOpen) {
        if (!tableReader.hasMoreLines()) parserCtx.closeCell(true);
      } else {
        if (tableReader.skipBlankLines() == null) break;
      }
    }

    parserCtx.closeTable();
    if (!isTruthy(table.attributes['colcount'])) {
      table.attributes['colcount'] = table.columns.length;
    }
    if (table.attributes['colcount'] != 0 && !explicitColspecs) {
      table.assignColumnWidths();
    }
    if (implicitHeader) table.hasHeaderOption = true;
    table.partitionHeaderFooter(_strKeys(attributes));

    return table;
  }

  /// Parses the column specs for a table.
  ///
  /// Port of `Parser.parse_colspecs`.
  static List<Map<String, Object?>> parseColspecs(String records) {
    var input = records;
    if (input.contains(' ')) input = input.replaceAll(' ', '');
    // Check for deprecated syntax: single number, equal column spread.
    if (input == _toInt(input).toString()) {
      return List.generate(_toInt(input), (_) => <String, Object?>{'width': 1});
    }

    final specs = <Map<String, Object?>>[];
    // NOTE Dart split keeps trailing empty records, like split with -1.
    final parts = input.contains(',') ? input.split(',') : input.split(';');
    for (final record in parts) {
      if (record.isEmpty) {
        specs.add(<String, Object?>{'width': 1});
      } else {
        // TODOmight want to use scan rather than this mega-regexp.
        final m = columnSpecRx.firstMatch(record);
        if (m != null) {
          final spec = <String, Object?>{};
          if (m.group(2) != null) {
            // Make this an operation.
            final alignParts = _rubySplit(m.group(2)!, '.');
            final colspec = alignParts[0];
            final rowspec = alignParts.length > 1 ? alignParts[1] : null;
            if (!_isNilOrEmpty(colspec) &&
                _tableCellHorzAlignments.containsKey(colspec)) {
              spec['halign'] = _tableCellHorzAlignments[colspec];
            }
            if (!_isNilOrEmpty(rowspec) &&
                _tableCellVertAlignments.containsKey(rowspec)) {
              spec['valign'] = _tableCellVertAlignments[rowspec];
            }
          }

          final width = m.group(3);
          if (width != null) {
            // to_i will strip the optional %.
            spec['width'] = width == '~' ? -1 : _toInt(width);
          } else {
            spec['width'] = 1;
          }

          // Make this an operation.
          final styleKey = m.group(4);
          if (styleKey != null && _tableCellStyles.containsKey(styleKey)) {
            spec['style'] = _tableCellStyles[styleKey];
          }

          final repeat = m.group(1);
          if (repeat != null) {
            final count = int.parse(repeat);
            for (var i = 0; i < count; i++) {
              specs.add(Map<String, Object?>.of(spec));
            }
          } else {
            specs.add(spec);
          }
        }
      }
    }
    return specs;
  }

  /// Parses the cell specs for the current cell.
  ///
  /// Port of `Parser.parse_cellspec`. [pos] is `'start'` or `'end'`.
  /// Returns the spec (or `null` at `'start'` when no boundary is found)
  /// and the remaining text.
  static (Map<String, Object?>?, String) parseCellspec(
    String line, [
    String pos = 'end',
    String? delimiter,
  ]) {
    if (pos == 'start') {
      if (!line.contains(delimiter!)) return (null, line);
      final sepIndex = line.indexOf(delimiter);
      final specPart = line.substring(0, sepIndex);
      final rest = line.substring(sepIndex + delimiter.length);
      final m = cellSpecStartRx.firstMatch(specPart);
      if (m == null) return (null, line);
      if (m.group(0)!.isEmpty) return (<String, Object?>{}, rest);
      return _cellspecFromMatch(m, rest);
    }
    final m = cellSpecEndRx.firstMatch(line);
    if (m == null) return (<String, Object?>{}, line);
    // NOTE return the line stripped of trailing whitespace if no cellspec
    // is found in this case.
    if (m.group(0)!.trimLeft().isEmpty) {
      return (<String, Object?>{}, line.trimRight());
    }
    return _cellspecFromMatch(m, line.substring(0, m.start));
  }

  /// Builds a cell spec from a cellspec regex [match] and [rest] text.
  static (Map<String, Object?>, String) _cellspecFromMatch(
    RegExpMatch m,
    String rest,
  ) {
    final spec = <String, Object?>{};
    if (m.group(1) != null) {
      final spanParts = _rubySplit(m.group(1)!, '.');
      final colspec = spanParts[0];
      final rowspec = spanParts.length > 1 ? spanParts[1] : null;
      final col = _isNilOrEmpty(colspec) ? 1 : _toInt(colspec);
      final row = _isNilOrEmpty(rowspec) ? 1 : _toInt(rowspec);
      if (m.group(2) == '+') {
        if (col != 1) spec['colspan'] = col;
        if (row != 1) spec['rowspan'] = row;
      } else if (m.group(2) == '*') {
        if (col != 1) spec['repeatcol'] = col;
      }
    }

    if (m.group(3) != null) {
      final alignParts = _rubySplit(m.group(3)!, '.');
      final colspec = alignParts[0];
      final rowspec = alignParts.length > 1 ? alignParts[1] : null;
      if (!_isNilOrEmpty(colspec) &&
          _tableCellHorzAlignments.containsKey(colspec)) {
        spec['halign'] = _tableCellHorzAlignments[colspec];
      }
      if (!_isNilOrEmpty(rowspec) &&
          _tableCellVertAlignments.containsKey(rowspec)) {
        spec['valign'] = _tableCellVertAlignments[rowspec];
      }
    }

    final styleKey = m.group(4);
    if (styleKey != null && _tableCellStyles.containsKey(styleKey)) {
      spec['style'] = _tableCellStyles[styleKey];
    }

    return (spec, rest);
  }

  /// Parses lines of metadata until a line of metadata is not found.
  ///
  /// Port of `Parser.parse_block_metadata_lines`.
  static Map<Object, Object?> parseBlockMetadataLines(
    Reader reader,
    Document document,
    Map<Object, Object?> attributes, {
    bool textOnly = false,
  }) {
    final attrs = attributes;
    while (parseBlockMetadataLine(
      reader,
      document,
      attrs,
      textOnly: textOnly,
    )) {
      // Discard the line just processed.
      reader.shift();
      if (reader.skipBlankLines() == null) break;
    }
    return attrs;
  }

  /// Parses the next line if it contains metadata for the following block.
  ///
  /// Port of `Parser.parse_block_metadata_line`. Returns whether the line
  /// contained metadata.
  static bool parseBlockMetadataLine(
    Reader reader,
    Document document,
    Map<Object, Object?> attributes, {
    bool textOnly = false,
  }) {
    final nextLine = reader.peekLine();
    if (nextLine == null) return false;
    final normal =
        !textOnly &&
        (nextLine.startsWith('[') ||
            nextLine.startsWith('.') ||
            nextLine.startsWith('/') ||
            nextLine.startsWith(':'));
    if (!(textOnly
        ? (nextLine.startsWith('[') || nextLine.startsWith('/'))
        : normal)) {
      return false;
    }
    if (nextLine.startsWith('[')) {
      if (nextLine.startsWith('[[')) {
        final anchorMatch = nextLine.endsWith(']]')
            ? blockAnchorRx.firstMatch(nextLine)
            : null;
        if (anchorMatch != null) {
          // NOTE registration of id and reftext is deferred until block is
          // processed.
          attributes['id'] = anchorMatch.group(1);
          final reftext = anchorMatch.group(2);
          if (reftext != null) {
            attributes['reftext'] = reftext.contains(attrRefHead)
                ? _subAttributes(document, reftext)
                : reftext;
          }
          return true;
        }
      } else if (nextLine.endsWith(']')) {
        final attrMatch = blockAttributeListRx.firstMatch(nextLine);
        if (attrMatch != null) {
          final currentStyle = attributes[1];
          // Extract id, role, and options from first positional attribute
          // and remove, if present.
          final parsed = _parseAttributes(
            document,
            attrMatch.group(1),
            [],
            subInput: true,
            subResult: true,
            into: attributes,
          );
          if (parsed[1] != null) {
            attributes[1] =
                parseStyleAttribute(attributes, reader) ?? currentStyle;
          }
          return true;
        }
      }
    } else if (normal && nextLine.startsWith('.')) {
      final titleMatch = blockTitleRx.firstMatch(nextLine);
      if (titleMatch != null) {
        // NOTE title doesn't apply to section, but we need to stash it for
        // the first block.
        // TODOshould issue an error if this is found above the document
        // title.
        attributes['title'] = titleMatch.group(1);
        return true;
      }
    } else if (!normal || nextLine.startsWith('/')) {
      if (nextLine.startsWith('//')) {
        if (nextLine == '//') {
          return true;
        } else if (normal && uniform(nextLine, '/', nextLine.length)) {
          if (nextLine.length != 3) {
            reader.readLinesUntil(
              terminator: nextLine,
              skipFirstLine: true,
              preserveLastLine: true,
              skipProcessing: true,
              context: 'comment',
            );
            return true;
          }
        } else {
          if (!nextLine.startsWith('///')) return true;
        }
      }
      // NOTE the final condition can be consolidated into single line.
    } else if (normal && nextLine.startsWith(':')) {
      final entryMatch = attributeEntryRx.firstMatch(nextLine);
      if (entryMatch == null) return false;
      processAttributeEntry(reader, document, attributes, entryMatch);
      return true;
    }
    return false;
  }

  /// Processes consecutive attribute entry lines, ignoring adjacent line
  /// comments and comment blocks.
  ///
  /// Port of `Parser.process_attribute_entries`.
  static void processAttributeEntries(
    Reader reader,
    Document? document, [
    Map<Object, Object?>? attributes,
  ]) {
    reader.skipCommentLines();
    while (processAttributeEntry(reader, document, attributes)) {
      // Discard line just processed.
      reader.shift();
      reader.skipCommentLines();
    }
  }

  /// Processes a single attribute entry line.
  ///
  /// Port of `Parser.process_attribute_entry`. Returns whether an entry
  /// was processed.
  static bool processAttributeEntry(
    Reader reader,
    Document? document, [
    Map<Object, Object?>? attributes,
    RegExpMatch? match,
  ]) {
    final entryMatch =
        match ??
        (reader.hasMoreLines()
            ? attributeEntryRx.firstMatch(reader.peekLine() ?? '')
            : null);
    if (entryMatch == null) return false;
    final rawValue = entryMatch.group(2);
    final String value;
    if (rawValue == null || rawValue.isEmpty) {
      value = '';
    } else if (rawValue.endsWith(_lineContinuation) ||
        rawValue.endsWith(_lineContinuationLegacy)) {
      final con = rawValue.substring(rawValue.length - 2);
      var joined = rawValue.substring(0, rawValue.length - 2).trimRight();
      while (reader.advance()) {
        var nextLine = (reader.peekLine() ?? '').trimLeft();
        if (nextLine.isEmpty) break;
        final keepOpen = nextLine.endsWith(con);
        if (keepOpen) {
          nextLine = nextLine.substring(0, nextLine.length - 2).trimRight();
        }
        joined =
            '$joined${joined.endsWith(_hardLineBreak) ? lf : ' '}$nextLine';
        if (!keepOpen) break;
      }
      value = joined;
    } else {
      value = rawValue;
    }

    storeAttribute(entryMatch.group(1)!, value, document, attributes);
    return true;
  }

  /// Stores the attribute in the document and registers the attribute
  /// entry if accessible.
  ///
  /// Port of `Parser.store_attribute`. A leading or trailing `!` on [name]
  /// unsets the attribute. Returns the resolved name and value.
  static (String, Object?) storeAttribute(
    String name,
    Object? value, [
    Document? doc,
    Map<Object, Object?>? attrs,
  ]) {
    // TODOmove processing of attribute value to utility method.
    var resolvedName = name;
    var resolvedValue = value;
    if (resolvedName.endsWith('!')) {
      // A nil value signals the attribute should be deleted (unset).
      resolvedName = resolvedName.substring(0, resolvedName.length - 1);
      resolvedValue = null;
    } else if (resolvedName.startsWith('!')) {
      // A nil value signals the attribute should be deleted (unset).
      resolvedName = resolvedName.substring(1);
      resolvedValue = null;
    }

    resolvedName = sanitizeAttributeName(resolvedName);
    if (resolvedName == 'numbered') {
      resolvedName = 'sectnums';
    } else if (resolvedName == 'hardbreaks') {
      resolvedName = 'hardbreaks-option';
    } else if (resolvedName == 'showtitle') {
      storeAttribute(
        'notitle',
        isTruthy(resolvedValue) ? null : '',
        doc,
        attrs,
      );
    }

    if (doc != null) {
      if (resolvedValue != null) {
        var stringValue = resolvedValue as String;
        if (resolvedName == 'leveloffset') {
          // Support relative leveloffset values.
          if (stringValue.startsWith('+')) {
            stringValue =
                (_toInt(doc.attr('leveloffset', 0)) +
                        _toInt(stringValue.substring(1)))
                    .toString();
          } else if (stringValue.startsWith('-')) {
            stringValue =
                (_toInt(doc.attr('leveloffset', 0)) -
                        _toInt(stringValue.substring(1)))
                    .toString();
          }
        }
        // QUESTION should we set value to locked value if set_attribute
        // returns false?
        final resolved = _setDocumentAttribute(doc, resolvedName, stringValue);
        if (resolved != null) {
          resolvedValue = resolved;
          if (attrs != null) {
            _saveAttributeEntry(
              DocumentAttributeEntry(resolvedName, resolvedValue),
              attrs,
            );
          }
        }
      } else if (!doc.attributeLocked(resolvedName)) {
        // TEMP-SEAM (parser): Ruby `delete_attribute` returns true
        // whenever the attribute is unlocked (even when absent), but the
        // document wave's port returns whether it was present; gate on
        // the lock instead so the entry is recorded exactly like Ruby.
        // The document wave must fix `deleteAttribute` to return true
        // when unlocked (document.rb `delete_attribute`).
        doc.deleteAttribute(resolvedName);
        if (attrs != null) {
          _saveAttributeEntry(
            DocumentAttributeEntry(resolvedName, resolvedValue),
            attrs,
          );
        }
      }
    } else if (attrs != null) {
      _saveAttributeEntry(
        DocumentAttributeEntry(resolvedName, resolvedValue),
        attrs,
      );
    }

    return (resolvedName, resolvedValue);
  }

  /// Parses the first positional attribute and assigns named attributes.
  ///
  /// Port of `Parser.parse_style_attribute`. Returns the parsed style.
  static String? parseStyleAttribute(
    Map<Object, Object?> attributes, [
    Reader? reader,
  ]) {
    // NOTE spaces are not allowed in shorthand, so if we detect one, this
    // ain't no shorthand.
    final rawStyle = attributes[1] as String?;
    if (rawStyle != null &&
        !rawStyle.contains(' ') &&
        _shorthandPropertySyntax) {
      String? name;
      var accum = '';
      final parsedAttrs = <String, Object?>{};

      for (final rune in rawStyle.runes) {
        final c = String.fromCharCode(rune);
        if (c == '.') {
          yieldBufferedAttribute(parsedAttrs, name, accum, reader);
          accum = '';
          name = 'role';
        } else if (c == '#') {
          yieldBufferedAttribute(parsedAttrs, name, accum, reader);
          accum = '';
          name = 'id';
        } else if (c == '%') {
          yieldBufferedAttribute(parsedAttrs, name, accum, reader);
          accum = '';
          name = 'option';
        } else {
          accum += c;
        }
      }

      // Small optimization if no shorthand is found.
      if (name != null) {
        yieldBufferedAttribute(parsedAttrs, name, accum, reader);

        final parsedStyle = parsedAttrs['style'] as String?;
        if (parsedStyle != null) attributes['style'] = parsedStyle;

        if (parsedAttrs.containsKey('id')) {
          attributes['id'] = parsedAttrs['id'];
        }

        if (parsedAttrs.containsKey('role')) {
          final roles = (parsedAttrs['role'] as List<String>).join(' ');
          final existingRole = attributes['role'];
          attributes['role'] = _isNilOrEmpty(existingRole)
              ? roles
              : '$existingRole $roles';
        }

        if (parsedAttrs.containsKey('option')) {
          for (final opt in parsedAttrs['option'] as List<String>) {
            attributes['$opt-option'] = '';
          }
        }

        return parsedStyle;
      }
    }
    attributes['style'] = rawStyle;
    return rawStyle;
  }

  /// Saves the collected attribute (`id`, `option`, `role`, or `null` for
  /// `style`) in the attribute map.
  ///
  /// Port of `Parser.yield_buffered_attribute`.
  static void yieldBufferedAttribute(
    Map<String, Object?> attrs,
    String? name,
    String value,
    Reader? reader,
  ) {
    if (name != null) {
      if (value.isEmpty) {
        if (reader != null) {
          _logger.warn(
            _msg(
              'invalid empty $name detected in style attribute',
              reader.cursorAtPrevLine(),
            ),
          );
        } else {
          _logger.warn('invalid empty $name detected in style attribute');
        }
      } else if (name == 'id') {
        if (attrs.containsKey('id')) {
          if (reader != null) {
            _logger.warn(
              _msg(
                'multiple ids detected in style attribute',
                reader.cursorAtPrevLine(),
              ),
            );
          } else {
            _logger.warn('multiple ids detected in style attribute');
          }
        }
        attrs[name] = value;
      } else {
        ((attrs[name] ??= <String>[]) as List<String>).add(value);
      }
    } else if (value.isNotEmpty) {
      attrs['style'] = value;
    }
  }

  /// Consumes and parses the two header lines (line 1 = author info,
  /// line 2 = revision info).
  ///
  /// Port of `Parser.parse_header_metadata`. When [document] is given,
  /// the metadata is applied to it. Returns the merged metadata map when
  /// [retrieve] is set, else an empty map.
  static Map<String, Object?> parseHeaderMetadata(
    Reader reader, [
    Document? document,
    bool retrieve = true,
  ]) {
    final docAttrs = document?.attributes;
    // NOTE this will discard any comment lines, but not skip blank lines.
    processAttributeEntries(reader, document);

    Map<String, Object?> implicitAuthorMetadata;
    Map<String, Object?>? revMetadata;
    Map<String, Object?>? authorMetadata;
    int? authorcount;
    Object? implicitAuthor;
    Object? implicitAuthorinitials;
    Object? implicitAuthors;
    if (reader.hasMoreLines() && !reader.isNextLineEmpty()) {
      implicitAuthorMetadata = processAuthors(reader.readLine()!);
      authorcount = implicitAuthorMetadata.remove('authorcount') as int?;
      if (document != null && docAttrs != null) {
        docAttrs['authorcount'] = authorcount;
        if ((authorcount ?? 0) > 0) {
          implicitAuthorMetadata.forEach((key, val) {
            // Apply header subs and assign to document; attributes
            // substitution only relevant for email.
            // TEMP-SEAM (parser): `apply_header_subs` needs the
            // substitutors wave.
            if (!docAttrs.containsKey(key)) {
              docAttrs[key] = _applyHeaderSubs(document, val as String);
            }
          });
          implicitAuthor = docAttrs['author'];
          implicitAuthorinitials = docAttrs['authorinitials'];
          implicitAuthors = docAttrs['authors'];
        }
      }
      implicitAuthorMetadata['authorcount'] = authorcount;

      // NOTE this will discard any comment lines, but not skip blank lines.
      processAttributeEntries(reader, document);

      if (reader.hasMoreLines() && !reader.isNextLineEmpty()) {
        final revLine = reader.readLine()!;
        final revMatch = revisionInfoLineRx.firstMatch(revLine);
        if (revMatch != null) {
          revMetadata = <String, Object?>{};
          if (revMatch.group(1) != null) {
            revMetadata['revnumber'] = revMatch.group(1)!.trimRight();
          }
          final component = revMatch.group(2)!.trim();
          if (component.isNotEmpty) {
            // Version must begin with 'v' if date is absent.
            if (revMatch.group(1) == null && component.startsWith('v')) {
              revMetadata['revnumber'] = component.substring(1);
            } else {
              revMetadata['revdate'] = component;
            }
          }
          if (revMatch.group(3) != null) {
            revMetadata['revremark'] = revMatch.group(3)!.trimRight();
          }
          if (document != null && docAttrs != null && revMetadata.isNotEmpty) {
            // Apply header subs and assign to document.
            revMetadata.forEach((key, val) {
              if (!docAttrs.containsKey(key)) {
                docAttrs[key] = _applyHeaderSubs(document, val as String);
              }
            });
          }
        } else {
          // Throw it back.
          reader.unshiftLine(revLine);
        }
      }

      // NOTE this will discard any comment lines, but not skip blank lines.
      processAttributeEntries(reader, document);

      reader.skipBlankLines();
    } else {
      implicitAuthorMetadata = <String, Object?>{};
    }

    // Process author attribute entries that override (or stand in for)
    // the implicit author line.
    if (document != null && docAttrs != null) {
      if (docAttrs.containsKey('author') &&
          docAttrs['author'] != implicitAuthor) {
        // Do not allow multiple, process as names only.
        authorMetadata = processAuthors(docAttrs['author'] ?? '', true, false);
        if (docAttrs['authorinitials'] != implicitAuthorinitials) {
          authorMetadata.remove('authorinitials');
        }
      } else if (docAttrs.containsKey('authors') &&
          docAttrs['authors'] != implicitAuthors) {
        // Allow multiple, process as names only.
        authorMetadata = processAuthors(docAttrs['authors']!, true);
      } else {
        final authors = <String?>[];
        var authorIdx = 1;
        var authorKey = 'author_1';
        var explicit = false;
        var sparse = false;
        while (docAttrs.containsKey(authorKey)) {
          // Only use indexed author attribute if value is different.
          // Leaves corner case if line matches with underscores converted
          // to spaces; use double space to force.
          final authorOverride = docAttrs[authorKey] as String?;
          if (authorOverride == implicitAuthorMetadata[authorKey]) {
            authors.add(null);
            sparse = true;
          } else {
            authors.add(authorOverride);
            explicit = true;
          }
          authorIdx += 1;
          authorKey = 'author_$authorIdx';
        }
        if (explicit) {
          // Rebuild implicit author names to reparse.
          if (sparse) {
            for (var idx = 0; idx < authors.length; idx++) {
              if (authors[idx] != null) continue;
              final nameIdx = idx + 1;
              authors[idx] =
                  [
                        implicitAuthorMetadata['firstname_$nameIdx'],
                        implicitAuthorMetadata['middlename_$nameIdx'],
                        implicitAuthorMetadata['lastname_$nameIdx'],
                      ]
                      .whereType<String>()
                      .map((name) => name.replaceAll(' ', '_'))
                      .join(' ');
            }
          }
          // Process as names only.
          authorMetadata = processAuthors(authors, true, false);
        } else {
          authorMetadata = <String, Object?>{'authorcount': 0};
        }
      }

      if (authorMetadata['authorcount'] == 0) {
        if (authorcount != null) {
          authorMetadata = null;
        } else {
          docAttrs['authorcount'] = 0;
        }
      } else {
        docAttrs.addAll(authorMetadata);

        // Special case.
        if (!docAttrs.containsKey('email') && docAttrs.containsKey('email_1')) {
          docAttrs['email'] = docAttrs['email_1'];
        }
      }
    }

    if (!retrieve) return <String, Object?>{};
    return <String, Object?>{}
      ..addAll(implicitAuthorMetadata)
      ..addAll(revMetadata ?? const <String, Object?>{})
      ..addAll(authorMetadata ?? const <String, Object?>{});
  }

  /// Parses the author line into a map of author metadata.
  ///
  /// Port of `Parser.process_authors`. [authorLine] is a `String` author
  /// line or a `List` of entries.
  static Map<String, Object?> processAuthors(
    Object authorLine, [
    bool namesOnly = false,
    bool multiple = true,
  ]) {
    final authorMetadata = <String, Object?>{};
    var authorIdx = 0;
    final List<String> entries;
    if (authorLine is String) {
      entries = multiple && authorLine.contains(';')
          ? authorLine.split(authorDelimiterRx)
          : [authorLine];
    } else {
      entries = List<String>.from(authorLine as List<Object?>);
    }
    for (final authorEntry in entries) {
      if (authorEntry.isEmpty) continue;
      final keyMap = <String, String>{};
      authorIdx += 1;
      if (authorIdx == 1) {
        for (final key in _authorKeys) {
          keyMap[key] = key;
        }
      } else {
        for (final key in _authorKeys) {
          keyMap[key] = '${key}_$authorIdx';
        }
      }

      List<String?>? segments;
      if (namesOnly) {
        // When parsing an attribute value.
        // QUESTION should we rstrip author_entry?
        var entry = authorEntry;
        if (entry.contains('<')) {
          authorMetadata[keyMap['author']!] = entry.replaceAll('_', ' ');
          entry = entry.replaceAll(xmlSanitizeRx, '');
        }
        // NOTE split names and collapse repeating whitespace (split drops
        // any leading whitespace).
        final parts = _splitWhitespace(entry, 3);
        if (parts.length == 3) {
          parts[2] = squeezeChar(parts[2], ' ');
        }
        segments = parts;
      } else {
        final authorMatch = authorInfoLineRx.firstMatch(authorEntry);
        if (authorMatch != null) {
          segments = <String?>[
            authorMatch.group(1),
            authorMatch.group(2),
            authorMatch.group(3),
            authorMatch.group(4),
          ];
        }
      }

      if (segments != null) {
        // NOTE Ruby returns nil for out-of-range indexes; Dart throws, so
        // read defensively (segments has 1-3 entries when names_only).
        final seg1 = segments.length > 1 ? segments[1] : null;
        final seg2 = segments.length > 2 ? segments[2] : null;
        final seg3 = segments.length > 3 ? segments[3] : null;
        var author = authorMetadata[keyMap['firstname']!] = segments[0]!
            .replaceAll('_', ' ');
        final fname = author;
        authorMetadata[keyMap['authorinitials']!] = _firstChar(fname);
        if (seg1 != null) {
          if (seg2 != null) {
            final mname = seg1.replaceAll('_', ' ');
            final lname = seg2.replaceAll('_', ' ');
            authorMetadata[keyMap['middlename']!] = mname;
            authorMetadata[keyMap['lastname']!] = lname;
            author = '$fname $mname $lname';
            authorMetadata[keyMap['authorinitials']!] =
                '${_firstChar(fname)}${_firstChar(mname)}${_firstChar(lname)}';
          } else {
            final lname = seg1.replaceAll('_', ' ');
            authorMetadata[keyMap['lastname']!] = lname;
            author = '$fname $lname';
            authorMetadata[keyMap['authorinitials']!] =
                '${_firstChar(fname)}${_firstChar(lname)}';
          }
        }
        authorMetadata[keyMap['author']!] ??= author;
        if (!namesOnly && seg3 != null) {
          authorMetadata[keyMap['email']!] = seg3;
        }
      } else {
        final fname = squeezeChar(authorEntry, ' ').trim();
        authorMetadata[keyMap['author']!] =
            authorMetadata[keyMap['firstname']!] = fname;
        authorMetadata[keyMap['authorinitials']!] = _firstChar(fname);
      }

      if (authorIdx == 1) {
        authorMetadata['authors'] = authorMetadata[keyMap['author']];
      } else {
        // Only assign the _1 attributes once we see the second author.
        if (authorIdx == 2) {
          for (final key in _authorKeys) {
            if (authorMetadata.containsKey(key)) {
              authorMetadata['${key}_1'] = authorMetadata[key];
            }
          }
        }
        authorMetadata['authors'] =
            '${authorMetadata['authors']}, ${authorMetadata[keyMap['author']]}';
      }
    }

    authorMetadata['authorcount'] = authorIdx;
    return authorMetadata;
  }

  /// Removes the block indentation, expands tabs and re-indents by
  /// [indentSize]. Modifies [lines] in place.
  ///
  /// Port of `Parser.adjust_indentation!`.
  static void adjustIndentation(
    List<String> lines, [
    int indentSize = 0,
    int tabSize = 0,
  ]) {
    if (lines.isEmpty) return;

    // Expand tabs if a tab character is detected and tab_size > 0.
    if (tabSize > 0 && lines.any((line) => line.contains(tab))) {
      final fullTabSpace = ' ' * tabSize;
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.isEmpty || !line.contains(tab)) continue;
        if (line.startsWith(tab)) {
          var leadingTabs = 0;
          for (final unit in line.codeUnits) {
            if (unit != 9) break;
            leadingTabs += 1;
          }
          line = '${fullTabSpace * leadingTabs}${line.substring(leadingTabs)}';
          if (!line.contains(tab)) {
            lines[i] = line;
            continue;
          }
        }
        // Keeps track of how many spaces were added to adjust offset in
        // match data.
        var spacesAdded = 0;
        var idx = 0;
        final result = StringBuffer();
        for (final rune in line.runes) {
          final c = String.fromCharCode(rune);
          if (c == tab) {
            // Calculate how many spaces this tab represents, then replace
            // tab with spaces.
            final offset = idx + spacesAdded;
            if (offset % tabSize == 0) {
              spacesAdded += tabSize - 1;
              result.write(fullTabSpace);
            } else {
              final spaces = tabSize - offset % tabSize;
              if (spaces != 1) spacesAdded += spaces - 1;
              result.write(' ' * spaces);
            }
          } else {
            result.write(c);
          }
          idx += 1;
        }
        lines[i] = result.toString();
      }
    }

    // Skip block indent adjustment if indent_size is < 0.
    if (indentSize < 0) return;

    // Determine block indent (assumes no whitespace-only lines are
    // present). The indent prefix is ASCII whitespace only (mirroring
    // Ruby `lstrip`), so UTF-16 offsets equal character offsets.
    int? blockIndent;
    for (final line in lines) {
      if (line.isEmpty) continue;
      final lineIndent =
          line.length - line.replaceFirst(_leadingWhitespaceRx, '').length;
      if (lineIndent == 0) {
        blockIndent = null;
        break;
      }
      if (blockIndent == null || lineIndent < blockIndent) {
        blockIndent = lineIndent;
      }
    }

    // Remove block indent then apply indent_size if specified.
    // NOTE block_indent is > 0 if not nil.
    if (indentSize == 0) {
      if (blockIndent != null) {
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].isEmpty) continue;
          lines[i] = lines[i].substring(blockIndent);
        }
      }
    } else {
      final newBlockIndent = ' ' * indentSize;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].isEmpty) continue;
        lines[i] = blockIndent != null
            ? '$newBlockIndent${lines[i].substring(blockIndent)}'
            : '$newBlockIndent${lines[i]}';
      }
    }
  }

  /// Whether [str] consists of [len] occurrences of [chr].
  ///
  /// Port of `Parser.uniform?`.
  static bool uniform(String str, String chr, int len) {
    var count = 0;
    var index = 0;
    while (true) {
      index = str.indexOf(chr, index);
      if (index < 0) break;
      count++;
      index += chr.length;
    }
    return count == len;
  }

  /// Converts a string to a legal attribute name.
  ///
  /// Port of `Parser.sanitize_attribute_name`.
  static String sanitizeAttributeName(String name) =>
      name.replaceAll(invalidAttributeNameCharsRx, '').toLowerCase();
}

/// Adapts a reader [Cursor] to a [NodeSourceLocation].
///
/// Mirrors the private adapters each wave keeps locally (the reader wave
/// does not make [Cursor] implement the interface); the merger may unify
/// them.
class _CursorSourceLocation implements NodeSourceLocation {
  /// Creates a source location from [cursor].
  new(this._cursor);

  final Cursor _cursor;

  @override
  String? get file {
    final file = _cursor.file;
    return file is String ? file : file?.toString();
  }

  @override
  int? get lineno => _cursor.lineno;
}

/// TEMP-SEAM (parser): applies the partial normal substitutions
/// (`specialcharacters`, then `attributes`) to single-quoted
/// attribute-list values for [Parser._parseAttributes].
class _SeamSubsApplier implements SubsApplier {
  /// Creates an applier resolving references against [document].
  new(this.document);

  /// The document attributes resolve against.
  final Document document;

  @override
  String applySubs(String value) =>
      Parser._subAttributes(document, Parser._subSpecialchars(value));
}
