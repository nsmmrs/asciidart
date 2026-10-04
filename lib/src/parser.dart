/// Methods to parse lines of AsciiDoc into an object hierarchy.
///
/// Port of `lib/asciidoctor/parser.rb` (complete).
///
/// Node contexts and other symbolic names are `String`s throughout. The
/// attributes collected for the next block travel in a [BlockAttributes]
/// map, which also carries the attribute entries that preceded the block.
///
/// Substitutions go through `substitutors.dart` and the node title
/// getters, and attribute entries through [Document.setAttribute], so the
/// parser applies exactly the substitutions Asciidoctor applies at each
/// step. A few tables below duplicate values from `constants.dart`.
library;

import 'dart:collection' show MapBase;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/callouts.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/extensions.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/substitutors.dart';
import 'package:asciidoctor/src/table.dart';
import 'package:asciidoctor/src/text_case.dart';

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

/// The attributes collected for the next block while parsing.
///
/// A string map of the block attributes (positional attributes under `'1'`,
/// `'2'`, ...) that also carries the attribute entries (`:name: value`
/// lines) recorded before the block, which are replayed when the block is
/// converted.
final class BlockAttributes extends MapBase<String, String> {
  /// Creates a map holding a copy of [attributes].
  new([Map<String, String>? attributes])
    : _attributes = <String, String>{...?attributes};

  final Map<String, String> _attributes;

  /// The attribute entries recorded before the block, if any.
  List<DocumentAttributeEntry>? attributeEntries;

  /// Whether the document header preceding these attributes was invalid.
  bool invalidHeader = false;

  /// Records [entry] for replay when the block is converted.
  void addEntry(DocumentAttributeEntry entry) {
    (attributeEntries ??= <DocumentAttributeEntry>[]).add(entry);
  }

  /// Returns a copy, including the attribute entries.
  BlockAttributes copy() => BlockAttributes(_attributes)
    ..attributeEntries = attributeEntries == null
        ? null
        : List.of(attributeEntries!)
    ..invalidHeader = invalidHeader;

  @override
  String? operator [](Object? key) => _attributes[key];

  @override
  void operator []=(String key, String value) {
    _attributes[key] = value;
  }

  @override
  void clear() {
    _attributes.clear();
    attributeEntries = null;
    invalidHeader = false;
  }

  @override
  Iterable<String> get keys => _attributes.keys;

  @override
  String? remove(Object? key) => _attributes.remove(key);
}

/// A line in a list-item buffer: a text line or a list continuation
/// marker.
sealed class _ItemLine {
  /// The line text.
  String get text;
}

/// A plain text line in a list-item buffer.
final class _TextLine implements _ItemLine {
  const new(this.text);

  @override
  final String text;
}

/// A list continuation line inside a list-item buffer.
enum _ListContinuation implements _ItemLine {
  /// A live list continuation (`'+'`).
  active._('+'),

  /// A consumed list continuation (the empty string).
  placeholder._('');

  new _(this.text);

  @override
  final String text;
}

/// Methods to parse lines of AsciiDoc into an object hierarchy.
///
/// All members are static; the class cannot be instantiated.
abstract final class Parser {
  /// String for matching the tab character. Port of `Parser::TAB`.
  static const String tab = '\t';

  // Values copied from `lib/asciidoctor.rb` (some duplicate
  // `constants.dart`).

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

  /// The shared logger (mirrors `Parser.include Logging`).
  static LoggerBase get _logger => LoggerManager.logger;

  /// Matches a whitespace run (for [_splitWhitespace]).
  static final RegExp _whitespaceRx = RegExp(r'[ \t\n\v\f\r]+');

  /// Matches a leading integer (for [_toInt]).
  static final RegExp _leadingIntRx = RegExp(r'^[+-]?\d+');

  /// Matches leading ASCII whitespace (for [adjustIndentation]).
  static final RegExp _leadingWhitespaceRx = RegExp(r'^[\x00\t\x0b\f\r ]+');

  /// Returns the [Document] of [node].
  static Document _docOf(AbstractNode node) => node.document! as Document;

  /// Applies the collected [attributes] to [block], including the attribute
  /// entries (ahead of any the block recorded itself).
  static void _applyAttributes(
    AbstractBlock block,
    BlockAttributes attributes,
  ) {
    block.updateAttributes(attributes);
    final entries = attributes.attributeEntries;
    if (entries != null) {
      block.attributeEntries = [...entries, ...?block.attributeEntries];
    }
  }

  /// Splits [value] on [sep] into at most [limit] parts (the last part keeps
  /// the remainder).
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
  /// Splits on whitespace runs: leading whitespace is dropped and trailing
  /// empty fields never appear.
  static List<String> _splitWhitespace(String value, [int? limit]) {
    final rest = trimLeftAscii(value);
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

  /// The first character of [value] (first rune).
  static String _firstChar(String value) =>
      value.isEmpty ? '' : String.fromCharCode(value.runes.first);

  /// Coerces [value] to an integer (its leading integer, else 0).
  ///
  /// `null` and unparsable values become `0`; leading whitespace is
  /// skipped and a leading `[+-]?\d+` run is parsed.
  static int _toInt(String? value) {
    if (value == null) return 0;
    final match = _leadingIntRx.firstMatch(trimLeftAscii(value));
    return match == null ? 0 : int.parse(match.group(0)!);
  }

  /// Port of `AttributeList.rekey`: copies the positional attributes to
  /// the names in [posattrs].
  static void _rekey(Map<String, String> attributes, List<String?> posattrs) {
    for (var index = 0; index < posattrs.length; index++) {
      final key = posattrs[index];
      if (key == null) continue;
      final value = attributes['${index + 1}'];
      if (value == null) continue;
      attributes[key] = value;
    }
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
    final blockAttributes = parseDocumentHeader(
      reader,
      document,
      headerOnly: headerOnly,
    );

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
          ..addAll(orphaned)
          ..attributeEntries = orphaned.attributeEntries
          ..invalidHeader = orphaned.invalidHeader;
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
  static BlockAttributes parseDocumentHeader(
    Reader reader,
    Document document, {
    bool headerOnly = false,
  }) {
    // Capture lines of block-level metadata and plow away comment lines
    // that precede first block.
    final blockAttrs = reader.skipBlankLines() != null
        ? parseBlockMetadataLines(reader, document, BlockAttributes())
        : BlockAttributes();
    final docAttrs = document.attributes;

    // Special cases, block style or title is not allowed above document
    // title, carry attributes over to the document body.
    final implicitDoctitle = isNextLineDoctitle(
      reader,
      blockAttrs,
      docAttrs['leveloffset'],
    );
    if (implicitDoctitle && blockAttrs.containsKey('title')) {
      docAttrs['authorcount'] = '0';
      return _finalizeHeader(document, blockAttrs, headerValid: false);
    }

    String? doctitleAttrVal;
    final presetDoctitle = docAttrs['doctitle'];
    if (!presetDoctitle.isNullOrEmpty) {
      document.title = doctitleAttrVal = presetDoctitle;
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
        final converted = subSpecialchars(l0SectionTitle);
        docAttrs['doctitle'] = doctitleAttrVal = converted;
        if (converted.contains(attrRefHead)) {
          // QUESTION should we defer substituting attributes until the end
          // of the header? or should we substitute again if necessary?
          docAttrs['doctitle'] = doctitleAttrVal = subAttributes(
            document,
            converted,
            attributeMissing: 'skip',
          );
        }
      }
      if (sourceLocation != null) {
        document.header!.sourceLocation = sourceLocation;
      }
      // Default to compat-mode if document has setext doctitle.
      if (!atx && !document.attributeLocked('compat-mode')) {
        docAttrs['compat-mode'] = '';
      }
      final separator = blockAttrs['separator'];
      if (separator != null && !document.attributeLocked('title-separator')) {
        docAttrs['title-separator'] = separator;
      }
      final blockId = blockAttrs['id'];
      String? docId;
      if (blockId != null) {
        document.id = docId = blockId;
      } else {
        docId = document.id;
      }
      final role = blockAttrs['role'];
      if (role != null) docAttrs['role'] = role;
      final reftext = blockAttrs['reftext'];
      if (reftext != null) docAttrs['reftext'] = reftext;
      blockAttrs.clear();
      // Detect a doctitle change by snapshotting the value (the document's
      // modified-attributes set is private; observably equivalent). The `elsif`
      // branch only appends to that set, which no ported reader consults for
      // `doctitle`, so it is omitted.
      final doctitleBefore = docAttrs['doctitle'];
      parseHeaderMetadata(reader, document: document, retrieve: false);
      if (docAttrs['doctitle'] != doctitleBefore) {
        final val = docAttrs['doctitle'];
        if (val == null || val.isEmpty || val == doctitleAttrVal) {
          _setOrRemove(docAttrs, 'doctitle', doctitleAttrVal);
        } else {
          document.title = val;
        }
      }
      if (docId != null) document.registerRef(docId, document);
    } else if (docAttrs['author'] case final author?) {
      final authorMetadata = processAuthors(
        author,
        namesOnly: true,
        multiple: false,
      );
      if (docAttrs.containsKey('authorinitials')) {
        authorMetadata.remove('authorinitials');
      }
      docAttrs.addAll(authorMetadata);
    } else if (docAttrs['authors'] case final authors?) {
      final authorMetadata = processAuthors(authors, namesOnly: true);
      docAttrs.addAll(authorMetadata);
    } else {
      docAttrs['authorcount'] = '0';
    }

    // Parse title and consume name section of manpage document.
    if (document.doctype == 'manpage') {
      parseManpageHeader(reader, document, blockAttrs, headerOnly: headerOnly);
    }

    // NOTE blockAttrs are the block-level attributes (not document
    // attributes) that precede the first line of content (document title,
    // first section or first block).
    return _finalizeHeader(document, blockAttrs);
  }

  /// Finishes the header: drops the attribute entries recorded before the
  /// first block (they were applied to the header), saves the header
  /// attributes on [document] and flags an invalid header. Returns
  /// [blockAttrs].
  static BlockAttributes _finalizeHeader(
    Document document,
    BlockAttributes blockAttrs, {
    bool headerValid = true,
  }) {
    blockAttrs.attributeEntries = null;
    document.finalizeHeader();
    if (!headerValid) blockAttrs.invalidHeader = true;
    return blockAttrs;
  }

  /// Sets [name] to [value] in [attributes], or removes it when [value] is
  /// `null`.
  static void _setOrRemove(
    Map<String, String> attributes,
    String name,
    String? value,
  ) {
    if (value == null) {
      attributes.remove(name);
    } else {
      attributes[name] = value;
    }
  }

  /// Parses the manpage header of the AsciiDoc source read from [reader].
  ///
  /// Port of `Parser.parse_manpage_header`.
  static void parseManpageHeader(
    Reader reader,
    Document document,
    BlockAttributes blockAttributes, {
    bool headerOnly = false,
  }) {
    final docAttrs = document.attributes;
    final doctitle = docAttrs['doctitle'];
    final volnumMatch = doctitle != null
        ? manpageTitleVolnumRx.firstMatch(doctitle)
        : null;
    late final String manvolnum;
    if (volnumMatch != null) {
      docAttrs['manvolnum'] = manvolnum = volnumMatch.group(2)!;
      final mantitle = volnumMatch.group(1)!;
      docAttrs['mantitle'] = downcase(
        mantitle.contains(attrRefHead)
            ? subAttributes(document, mantitle)
            : mantitle,
      );
    } else {
      _logger.error('non-conforming manpage title', at: reader.cursorAtLine(1));
      // Provide sensible fallbacks.
      docAttrs['mantitle'] =
          docAttrs['doctitle'] ?? docAttrs['docname'] ?? 'command';
      docAttrs['manvolnum'] = manvolnum = '1';
    }
    final mannameAttr = docAttrs['manname'];
    if (mannameAttr != null && docAttrs.containsKey('manpurpose')) {
      docAttrs['manname-title'] ??= 'Name';
      _setMannames(document, [mannameAttr]);
      if (document.backend == 'manpage') {
        docAttrs['docname'] = mannameAttr;
        docAttrs['outfilesuffix'] = '.$manvolnum';
      }
    } else if (!headerOnly) {
      reader
        ..skipBlankLines()
        ..save();
      final nameAttributes = parseBlockMetadataLines(
        reader,
        document,
        BlockAttributes(),
      );
      blockAttributes.addAll(nameAttributes);
      if (nameAttributes.attributeEntries case final entries?) {
        entries.forEach(blockAttributes.addEntry);
      }
      String? errorMsg;
      final nameSectionLevel = isNextLineSection(reader, BlockAttributes());
      if (nameSectionLevel != null) {
        if (nameSectionLevel == 1) {
          final nameSection = initializeSection(
            reader,
            document,
            BlockAttributes(),
          );
          final nameSectionBuffer = reader
              .readLinesUntil(breakOnBlankLines: true, skipLineComments: true)
              .map(trimLeftAscii)
              .join(' ');
          final purposeMatch = manpageNamePurposeRx.firstMatch(
            nameSectionBuffer,
          );
          if (purposeMatch != null) {
            var manname = purposeMatch.group(1)!;
            if (manname.contains(attrRefHead)) {
              manname = subAttributes(document, manname);
            }
            late final List<String> mannames;
            String? resolvedManname = manname;
            if (manname.contains(',')) {
              mannames = splitDropTrailingEmpty(
                manname,
                ',',
              ).map(trimLeftAscii).toList();
              resolvedManname = mannames.isEmpty ? null : mannames[0];
            } else {
              mannames = [manname];
            }
            var manpurpose = purposeMatch.group(2)!;
            if (manpurpose.contains(attrRefHead)) {
              manpurpose = subAttributes(document, manpurpose);
            }
            docAttrs['manname-title'] ??= nameSection.title ?? '';
            if (nameSection.id case final id?) docAttrs['manname-id'] = id;
            _setOrRemove(docAttrs, 'manname', resolvedManname);
            _setMannames(document, mannames);
            docAttrs['manpurpose'] = manpurpose;
            if (document.backend == 'manpage') {
              _setOrRemove(docAttrs, 'docname', resolvedManname);
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
        _logger.error(errorMsg, at: reader.cursor());
        final fallback = docAttrs['docname'] ?? 'command';
        docAttrs['manname'] = fallback;
        _setMannames(document, [fallback]);
        if (document.backend == 'manpage') {
          docAttrs['docname'] = fallback;
          docAttrs['outfilesuffix'] = '.$manvolnum';
        }
      } else {
        reader.discardSave();
      }
    }
  }

  /// Records the names a man page documents on [document], also as the
  /// `mannames` attribute (in Asciidoctor's list notation).
  static void _setMannames(Document document, List<String> mannames) {
    document.mannames = mannames;
    document.attributes['mannames'] =
        '[${mannames.map(debugQuote).join(', ')}]';
  }

  /// Returns the next section from [reader].
  ///
  /// Port of `Parser.next_section`. Returns a record of the new [Section]
  /// (`null` when [parent] itself was consumed, i.e. the preamble case)
  /// and the map of orphaned attributes for the next section or block.
  static (Section?, BlockAttributes) nextSection(
    Reader reader,
    AbstractBlock parent, [
    BlockAttributes? attributes,
  ]) {
    var attrs = attributes ?? BlockAttributes();
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
            _takeInvalidHeader(attrs) ||
            isNextLineSection(reader, attrs) == null)) {
      document = parentDocument!;
      book = document.doctype == 'book';
      if (hasHeader || (book && attrs['1'] != 'abstract')) {
        intro = preamble = Block(
          document,
          'preamble',
          contentModel: 'compound',
        );
        if (book && document.hasAttr('preface-title')) {
          preamble.title = document.attr('preface-title');
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
      book = document.doctype == 'book';
      final newSection = initializeSection(reader, parent, attrs);
      // Clear attributes except for title attribute, which must be carried
      // over to next content block.
      final carriedTitle = attrs['title'];
      attrs = carriedTitle != null
          ? BlockAttributes({'title': carriedTitle})
          : BlockAttributes();
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
                'section title out of sequence: $expectedCondition, '
                'got level $nextLevel',
                at: reader.cursor(),
              );
            }
          } else {
            _logger.error(
              '$sectname sections do not support nested sections',
              at: reader.cursor(),
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
              'level 0 sections can only be used when doctype is book',
              at: reader.cursor(),
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
                // Give the paragraph the open block's resolved subs as a
                // fixed list.
                final paragraph = (Block(
                  newBlock,
                  'paragraph',
                  lines: partBlock.lines,
                ))..defaultSubs = List<String>.of(newBlock.subs);
                paragraph.attributes.remove('subs');
                paragraph.subs = List<String>.of(newBlock.subs);
                newBlock.append(paragraph);
                partBlock.lines.clear();
                newBlock.subs.clear();
              }
            } else if (section.blocks.length == 1) {
              final firstBlock = section.blocks[0];
              // Open the [partintro] open block for appending.
              if (intro == null && firstBlock.contentModel == 'compound') {
                _logger.error(
                  'illegal block content outside of partintro block',
                  at: blockCursor,
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
                  firstBlock
                    ..context = 'paragraph'
                    ..style = null;
                }
                section.blocks.removeAt(0);
                newIntro.append(firstBlock);
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
          'invalid part, must have at least one section (e.g., chapter, '
          'appendix, etc.)',
          at: reader.cursor(),
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
            document.append(preamble.blocks.removeAt(0));
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
      attrs.copy(),
    );
  }

  /// Returns and clears the invalid-header flag of [attrs].
  static bool _takeInvalidHeader(BlockAttributes attrs) {
    final invalid = attrs.invalidHeader;
    attrs.invalidHeader = false;
    return invalid;
  }

  /// Initializes a new [Section] and assigns any attributes provided.
  ///
  /// Port of `Parser.initialize_section`.
  static Section initializeSection(
    Reader reader,
    AbstractBlock parent, [
    BlockAttributes? attributes,
  ]) {
    final attrs = attributes ?? BlockAttributes();
    final document = _docOf(parent);
    final doctype = document.doctype;
    final book = doctype == 'book';
    final sourceLocation = document.sourcemap ? reader.cursor() : null;
    final sectStyle = attrs['1'];
    var (id: sectId, :reftext, title: sectTitle, :level, :atx) =
        parseSectionTitle(reader, document, attrs['id']);

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
    } else if (doctype == 'manpage' && downcase(sectTitle) == 'synopsis') {
      sectName = 'synopsis';
      sectSpecial = true;
    } else {
      sectName = 'section';
    }

    if (reftext != null) attrs['reftext'] = reftext;
    final section = (Section(parent, level))
      ..id = sectId
      ..title = sectTitle
      ..sectname = sectName
      ..sourceLocation = sourceLocation;
    if (sectSpecial) {
      section.special = true;
      if (sectNumbered) {
        section.numbered = true;
      } else if (document.attributes['sectnums'] == 'all') {
        section
          ..numbered = true
          ..chapterNumbering = book && level == 1;
      }
    } else if (document.attributes.containsKey('sectnums') && level > 0) {
      // NOTE a special section here is guaranteed to be nested in another
      // section.
      if (section.special && parent is Section) {
        section.numbered = parent.numbered;
      } else {
        section.numbered = true;
      }
    } else if (book &&
        level == 0 &&
        document.attributes.containsKey('partnums')) {
      section.numbered = true;
    }

    // Generate an ID if one was not embedded or specified as anchor above
    // section title.
    var id = section.id;
    var generatedId = false;
    if (id == null && document.attributes.containsKey('sectids')) {
      section.id = id = Section.generateId(section.title ?? '', document);
      generatedId = true;
    }
    if (id != null) {
      if (!generatedId && sectTitle.contains(attrRefHead)) {
        // Convert title to resolve attributes while in scope.
        final _ = section.title;
      }
      if (!document.registerRef(id, section)) {
        _logger.warn(
          'id assigned to section already in use: $id',
          at: reader.cursorAtLine(reader.lineno - (atx ? 1 : 2)),
        );
      }
    }

    _applyAttributes(section, attrs);
    reader.skipBlankLines();

    return section;
  }

  /// Checks if the next line on [reader] is a section title.
  ///
  /// Port of `Parser.is_next_line_section?`. Returns the section level, or
  /// `null` when the reader is not positioned at a section title.
  static int? isNextLineSection(Reader reader, BlockAttributes attributes) {
    final style = attributes['1'];
    if (style != null && (style == 'discrete' || style == 'float')) return null;
    if (_underlineStyleSectionTitles) {
      final nextLines = reader.peekLines(
        2,
        direct: style != null && style == 'comment',
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
    BlockAttributes attributes,
    String? leveloffset,
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
      (line2 == null || line2.isEmpty
          ? null
          : setextSectionTitle(line1, line2));

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
    var resolvedSectId = sectId;
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
      if (resolvedSectId == null && sectTitle.endsWith(']]')) {
        final anchorMatch = inlineSectionAnchorRx.firstMatch(sectTitle);
        if (anchorMatch != null && anchorMatch.group(1) == null) {
          sectTitle = sectTitle.substring(
            0,
            sectTitle.length - anchorMatch.group(0)!.length,
          );
          resolvedSectId = anchorMatch.group(2);
          sectReftext = anchorMatch.group(3);
        }
      }
    } else {
      final line2 = _underlineStyleSectionTitles
          ? reader.peekLine(direct: true)
          : null;
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
        if (resolvedSectId == null && sectTitle.endsWith(']]')) {
          final anchorMatch = inlineSectionAnchorRx.firstMatch(sectTitle);
          if (anchorMatch != null && anchorMatch.group(1) == null) {
            sectTitle = sectTitle.substring(
              0,
              sectTitle.length - anchorMatch.group(0)!.length,
            );
            resolvedSectId = anchorMatch.group(2);
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
      id: resolvedSectId,
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
    BlockAttributes? attributes,
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

    final attrs = attributes ?? BlockAttributes();
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
    var style = attrs['1'];
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
                'unknown style for $blockContext block: $style',
                at: reader.cursorAtMark(),
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
          final lstripped = trimLeftAscii(thisLine);
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
                parseAttributes(
                  document,
                  blkAttrs,
                  posattrs: posattrs,
                  subInput: true,
                  into: attrs,
                );
              }
              // Style doesn't have special meaning for media macros.
              if (attrs.containsKey('style')) attrs.remove('style');
              if (target.contains(attrRefHead)) {
                final expandedTarget = subAttributes(document, target);
                if (expandedTarget.isEmpty &&
                    (docAttrs['attribute-missing'] ?? _attributeMissing) ==
                        'drop-line' &&
                    subAttributes(
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
                document.registerImage(target);
                _setOrRemove(attrs, 'imagesdir', docAttrs['imagesdir']);
                // NOTE style is the value of the first positional
                // attribute in the block attribute line.
                if (!attrs.containsKey('alt')) {
                  attrs['alt'] =
                      style ??
                      (attrs['default-alt'] = Helpers.basename(
                        target,
                        dropExtension: true,
                      ).replaceAll('_', ' ').replaceAll('-', ' '));
                }
                final scaledwidth = attrs.remove('scaledwidth');
                if (scaledwidth != null && scaledwidth.isNotEmpty) {
                  // NOTE assume % units if not specified.
                  attrs['scaledwidth'] = trailingDigitsRx.hasMatch(scaledwidth)
                      ? '$scaledwidth%'
                      : scaledwidth;
                }
                if (attrs.containsKey('title')) {
                  blockTitle = attrs.remove('title');
                  block
                    ..title = blockTitle
                    ..assignCaption(attrs.remove('caption'), 'figure');
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
                parseAttributes(
                  document,
                  tocAttrs,
                  posattrs: [],
                  subInput: true,
                  into: attrs,
                );
              }
              break;
            }
            // Port of `Parser.next_block` (lib/asciidoctor/parser.rb:648-679):
            // custom block macros, including the unknown-macro debug probe.
            final macroMatch = customBlockMacroRx.firstMatch(thisLine);
            ProcessorExtension<BlockMacroProcessor>? macroExtension;
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
                'unknown name for block macro: ${macroMatch!.group(1)}',
                at: reader.cursorAtMark(),
              );
            } else if (macroExtension != null) {
              final content = macroMatch!.group(3);
              var target = macroMatch.group(2)!;
              if (target.contains(attrRefHead)) {
                final expandedTarget = subAttributes(document, target);
                if (expandedTarget.isEmpty &&
                    (docAttrs['attribute-missing'] ?? _attributeMissing) ==
                        'drop-line' &&
                    subAttributes(
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
              final extConfig = macroExtension.instance.config;
              if (extConfig.contentModel == 'attributes') {
                if (content != null) {
                  parseAttributes(
                    document,
                    content,
                    posattrs: extConfig.positionalAttrs,
                    subInput: true,
                    into: attrs,
                  );
                }
              } else {
                attrs['text'] = content ?? '';
              }
              extConfig.defaultAttrs.forEach(
                (key, value) => attrs.putIfAbsent(key, () => value),
              );
              final macroBlock = macroExtension.instance.process(
                parent,
                target,
                attrs,
              );
              if (macroBlock != null && !identical(macroBlock, parent)) {
                // The extension result owns the attribute set from here on
                // (the attribute entries carry over).
                final entries = attrs.attributeEntries;
                attrs
                  ..clear()
                  ..addAll(macroBlock.attributes)
                  ..attributeEntries = entries;
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
        block = parseList(reader, 'olist', parent, style);
        if (block.style case final listStyle?) attrs['style'] = listStyle;
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
        final floatTitle = parseSectionTitle(reader, document, attrs['id']);
        if (floatTitle.reftext case final reftext?) attrs['reftext'] = reftext;
        block = (Block(parent, 'floating_title', contentModel: 'empty'))
          ..title = floatTitle.title;
        attrs.remove('title');
        block.id =
            floatTitle.id ??
            (docAttrs.containsKey('sectids')
                ? Section.generateId(block.title ?? '', document)
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
              'unknown style for paragraph: $style',
              at: reader.cursorAtMark(),
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
            lines: lines,
            attributes: attrs,
          );
        } else {
          block = Block(
            parent,
            'literal',
            contentModel: 'verbatim',
            lines: lines,
            attributes: attrs,
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
            lines: lines,
            attributes: attrs,
          );
        } else if (admonitionMatch != null) {
          lines[0] = thisLine.substring(admonitionMatch.end);
          final admonitionStyle = attrs['style'] = admonitionMatch.group(1)!;
          final admonitionName = downcase(admonitionStyle);
          attrs['name'] = admonitionName;
          final caption = attrs.remove('caption');
          _setOrRemove(
            attrs,
            'textlabel',
            caption ?? docAttrs['$admonitionName-caption'],
          );
          block = Block(
            parent,
            'admonition',
            contentModel: 'simple',
            lines: lines,
            attributes: attrs,
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
          // TODO could assume a discrete heading when inside a block context
          // FIXME Reader needs to be created w/ line info
          block = buildBlock(
            'quote',
            'compound',
            null,
            parent,
            Reader(lines),
            attrs,
            readerPrepared: true,
          )!;
          if (creditLine != null) {
            final parts = _splitLimit(block.applySubs(creditLine), ', ', 2);
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
            lines: lines,
            attributes: attrs,
          );
          final parts = _splitLimit(block.applySubs(creditLine), ', ', 2);
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
            lines: lines,
            attributes: attrs,
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
        String? language;
        if (bc != 'source') {
          language = attrs.containsKey('1')
              ? null
              : attrs['2'] ?? docAttrs['source-language'];
        }
        if (bc == 'source' || language != null) {
          if (language != null) {
            // :listing with language
            attrs['style'] = 'source';
            attrs['language'] = language;
            _rekey(attrs, [null, null, 'linenums']);
          } else {
            // :source
            _rekey(attrs, [null, 'language', 'linenums']);
            if (docAttrs['source-language'] case final sourceLanguage?) {
              attrs.putIfAbsent('language', () => sourceLanguage);
            }
            if (cloakedContext != 'listing') {
              attrs['cloaked-context'] = cloakedContext!;
            }
          }
          if (!attrs.containsKey('linenums') &&
              (attrs.containsKey('linenums-option') ||
                  docAttrs.containsKey('source-linenums-option'))) {
            attrs['linenums'] = '';
          }
          if (docAttrs['source-indent'] case final sourceIndent?) {
            attrs.putIfAbsent('indent', () => sourceIndent);
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
              language = info.substring(0, commaIdx).trimAscii();
              if (commaIdx < ll - 4) attrs['linenums'] = '';
            } else if (ll > 4) {
              attrs['linenums'] = '';
            }
          } else {
            language = trimLeftAscii(info);
          }
        }
        if (language == null || language.isEmpty) {
          if (docAttrs['source-language'] case final sourceLanguage?) {
            attrs['language'] = sourceLanguage;
          }
        } else {
          attrs['language'] = language;
        }
        attrs['cloaked-context'] = cloakedContext!;
        if (!attrs.containsKey('linenums') &&
            (attrs.containsKey('linenums-option') ||
                docAttrs.containsKey('source-linenums-option'))) {
          attrs['linenums'] = '';
        }
        if (docAttrs['source-indent'] case final sourceIndent?) {
          attrs.putIfAbsent('indent', () => sourceIndent);
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
            cursorAtMark: true,
          ),
          cursor: blockCursor,
        );
        // NOTE it's very rare that format is set when using a format hint
        // char, so short-circuit.
        if (!terminator!.startsWith('|') && !terminator.startsWith('!')) {
          // NOTE infer dsv once all other format hint chars are ruled out.
          attrs['format'] ??= terminator.startsWith(',') ? 'csv' : 'dsv';
        }
        block = parseTable(tableReader, parent, attrs);
      } else if (bc == 'sidebar') {
        block = buildBlock(bc, 'compound', terminator, parent, reader, attrs);
      } else if (bc == 'admonition') {
        final admonitionName = downcase(style!);
        attrs['name'] = admonitionName;
        final caption = attrs.remove('caption');
        _setOrRemove(
          attrs,
          'textlabel',
          caption ?? docAttrs['$admonitionName-caption'],
        );
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
        if (attrs.containsKey('collapsible-option')) attrs['caption'] = '';
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
              _stemTypeAliases[attrs['2'] ?? docAttrs['stem'] ?? ''] ??
              'asciimath';
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
        ProcessorExtension<BlockProcessor>? blockExtension;
        if (blockExtensions) {
          blockExtension = extensions!.registeredForBlock(bc, cloakedContext!);
        }
        if (blockExtension == null) {
          // This should only happen if there's a misconfiguration.
          throw StateError('Unsupported block type $bc at ${reader.cursor()}');
        }
        final extConfig = blockExtension.instance.config;
        final contentModel = extConfig.contentModel;
        if (contentModel != 'skip') {
          final positionalAttrs = extConfig.positionalAttrs;
          if (positionalAttrs.isNotEmpty) {
            _rekey(attrs, [null, ...positionalAttrs]);
          }
          extConfig.defaultAttrs.forEach(
            (key, value) => attrs.putIfAbsent(key, () => value),
          );
          // QUESTION should we clone the extension for each cloaked
          // context and set in config?
          attrs['cloaked-context'] = cloakedContext!;
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
      result.sourceLocation = reader.cursorAtMark();
    }
    // FIXME title and caption should be assigned when block is constructed
    // (though we need to handle all cases)
    if (attrs.containsKey('title')) {
      result.title = blockTitle = attrs.remove('title');
      if (captionAttributeNames.containsKey(result.context)) {
        result.assignCaption(attrs.remove('caption'));
      }
    }
    // TODO eventually remove the style attribute from the attributes hash
    //block.style = attributes.delete 'style'
    result.style = attrs['style'];
    final blockId = result.id ?? (result.id = attrs['id']);
    if (blockId != null) {
      // Convert title to resolve attributes while in scope.
      if (blockTitle != null
          ? blockTitle.contains(attrRefHead)
          : result.hasTitle) {
        final _ = result.title;
      }
      if (!document.registerRef(blockId, result)) {
        _logger.warn(
          'id assigned to block already in use: $blockId',
          at: reader.cursorAtMark(),
        );
      }
    }
    // FIXME remove the need for this update!
    _applyAttributes(result, attrs);
    result.commitSubs();

    //if doc_attrs.key? :pending_attribute_entries
    //  doc_attrs.delete(:pending_attribute_entries).each do |entry|
    //    entry.save_to block.attributes
    //  end
    //end

    if (result.hasSub('callouts')) {
      // Only simple content-model blocks can carry the callouts sub, so
      // this is always a Block here (lists and tables short-circuit in
      // _commitSubs).
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
    String? breakAtList, {
    bool skipLineComments = false,
    bool skipProcessing = false,
  }) {
    final bool Function(String)? breakCondition;
    if (breakAtList != null) {
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
  /// when it is, else `null`.
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
  /// `null` for a styled paragraph; [readerPrepared] means [reader] holds
  /// exactly the block content. When [extension] is given, its process
  /// method builds the block instead. Returns the block, or `null` for the
  /// `skip` model (or when the extension returns `null` or the parent).
  static AbstractBlock? buildBlock(
    String blockContext,
    String contentModel,
    String? terminator,
    AbstractBlock parent,
    Reader reader,
    BlockAttributes attributes, {
    ProcessorExtension<BlockProcessor>? extension,
    bool readerPrepared = false,
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
    if (terminator == null && !readerPrepared) {
      if (parseAsContentModel == 'verbatim') {
        lines = reader.readLinesUntil(
          breakOnBlankLines: true,
          breakOnListContinuation: true,
        );
      } else {
        if (model == 'compound') model = 'simple';
        // TODO we could also skip processing if we're able to detect
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
        terminator: terminator,
        skipProcessing: skipProcessing,
        context: blockContext,
        cursorAtMark: true,
      );
    } else if (readerPrepared) {
      blockReader = reader;
    } else {
      final blockCursor = reader.cursor();
      blockReader = Reader(
        reader.readLinesUntil(
          terminator: terminator,
          skipProcessing: skipProcessing,
          context: blockContext,
          cursorAtMark: true,
        ),
        cursor: blockCursor,
      );
    }

    if (model == 'verbatim') {
      final tabSize = _toInt(
        attributes['tabsize'] ?? _docOf(parent).attributes['tabsize'],
      );
      final indent = attributes['indent'];
      if (indent != null) {
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
      final extBlock = extension.instance.process(
        parent,
        blockReader ?? Reader(lines ?? const <String>[]),
        attributes,
      );
      if (extBlock == null || identical(extBlock, parent)) return null;
      block = extBlock;
      final entries = attributes.attributeEntries;
      attributes
        ..clear()
        ..addAll(block.attributes)
        ..attributeEntries = entries;
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
        lines: lines,
        attributes: attributes,
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
    BlockAttributes? attributes,
  ]) {
    while (true) {
      final block = nextBlock(reader, parent, attributes: attributes?.copy());
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
    String? style,
  ) {
    final listBlock = ListBlock(parent, listType);
    final listRx = listRxMap[listType]!;

    while (reader.hasMoreLines()) {
      final peeked = reader.peekLine();
      final match = peeked == null ? null : listRx.firstMatch(peeked);
      if (match == null) break;
      // NOTE parseListItem will stop at sibling item or end of list; never
      // sees ancestor items.
      listBlock.blocks.add(
        parseListItem(reader, listBlock, match, match.group(1)!, style).item!,
      );
      if (reader.skipBlankLines() == null) break;
    }

    return listBlock;
  }

  /// Whether [text] has a `<` followed by `!`, `-`, a digit or `.`.
  ///
  /// Every [calloutScanRx] match contains one, so text without it is
  /// skipped without running the (comparatively slow) regex scan.
  static bool _mayContainCallout(String text) {
    final last = text.length - 1;
    for (var i = text.indexOf('<'); i >= 0 && i < last;) {
      final next = text.codeUnitAt(i + 1);
      if (next == 0x21 || // !
          next == 0x2D || // -
          next == 0x2E || // .
          (next >= 0x30 && next <= 0x39)) {
        return true;
      }
      i = text.indexOf('<', i + 1);
    }
    return false;
  }

  /// Catalogs any callouts found in [text], but doesn't process them.
  ///
  /// Port of `Parser.catalog_callouts`. Returns whether callouts were found.
  static bool catalogCallouts(String text, Document document) {
    if (!_mayContainCallout(text)) return false;
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
    AbstractBlock node,
    Cursor? location, [
    Document? doc,
  ]) {
    final document = doc ?? _docOf(node);
    var ref = reftext;
    if (ref != null && ref.contains(attrRefHead)) {
      ref = subAttributes(document, ref);
    }
    if (!document.registerRef(
      id,
      Inline(node, 'anchor', text: ref, type: 'ref', id: id),
    )) {
      _logger.warn('id assigned to anchor already in use: $id', at: location);
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
          reftext = subAttributes(document, reftext);
          if (reftext.isEmpty) continue;
        }
      } else {
        id = match.group(3)!;
        reftext = match.group(4);
        if (reftext != null) {
          if (reftext.contains(']')) {
            reftext = reftext.replaceAll(r'\]', ']');
            if (reftext.contains(attrRefHead)) {
              reftext = subAttributes(document, reftext);
            }
          } else if (reftext.contains(attrRefHead)) {
            reftext = subAttributes(document, reftext);
            if (reftext.isEmpty) reftext = null;
          }
        }
      }
      if (!document.registerRef(
        id,
        Inline(block, 'anchor', text: reftext, type: 'ref', id: id),
      )) {
        final mark = reader.cursorAtMark();
        final pre = text.substring(0, match.start);
        final offset =
            '\n'.allMatches(pre).length +
            (match.group(0)!.startsWith('\n') ? 1 : 0);
        final location = offset > 0
            ? Cursor(mark.file, mark.dir, mark.path, mark.lineno + offset)
            : mark;
        _logger.warn('id assigned to anchor already in use: $id', at: location);
      }
    }
  }

  /// Catalogs the bibliography inline anchor at the start of a list item.
  ///
  /// Port of `Parser.catalog_inline_biblio_anchor`.
  static void catalogInlineBiblioAnchor(
    String id,
    String? reftext,
    AbstractBlock node,
    Reader reader,
  ) {
    // QUESTION should we sub attributes in reftext (like with regular
    // anchors)?
    if (!_docOf(node).registerRef(
      id,
      Inline(
        node,
        'anchor',
        text: reftext == null ? null : '[$reftext]',
        type: 'bibref',
        id: id,
      ),
    )) {
      _logger.warn(
        'id assigned to bibliography anchor already in use: $id',
        at: reader.cursor(),
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
    final first = parseListItem(reader, listBlock, match, siblingPattern);
    var current = DlistEntry([first.term!], first.item);
    listBlock.entries.add(current);

    while (reader.hasMoreLines()) {
      final peeked = reader.peekLine();
      final sibling = peeked == null ? null : siblingPattern.firstMatch(peeked);
      if (sibling == null) break;
      final next = parseListItem(reader, listBlock, sibling, siblingPattern);
      if (current.description != null) {
        current = DlistEntry([next.term!], next.item);
        listBlock.entries.add(current);
      } else {
        current.terms.add(next.term!);
        current.description = next.item;
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
          'callout list item index: expected $nextIndex, got $num',
          at: reader.cursorAtMark(),
        );
      }
      final current = match;
      match = null;
      final listItem = parseListItem(reader, listBlock, current, '<1>').item!;
      listBlock.blocks.add(listItem);
      final coids = callouts.calloutIds(listBlock.items.length);
      if (coids.isEmpty) {
        _logger.warn(
          'no callout found for <${listBlock.items.length}>',
          at: reader.cursorAtMark(),
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
  /// Port of `Parser.parse_list_item`. Returns the next list item; for a
  /// description list, the term and its description (`null` when the term
  /// has none).
  static ({ListItem? term, ListItem? item}) parseListItem(
    Reader reader,
    ListBlock listBlock,
    RegExpMatch match,
    Pattern siblingTrait, [
    String? style,
  ]) {
    var trait = siblingTrait;
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
          termAnchor.group(2) ??
              trimLeftAscii(termText.substring(termAnchor.end)),
          listTerm,
          reader.cursor(),
        );
      }
      final itemText = match.group(3);
      if (itemText != null) hasText = true;
      listItem = ListItem(listBlock, itemText);
      if (_docOf(listBlock).sourcemap) {
        listTerm.sourceLocation = reader.cursor();
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
        listItem.sourceLocation = reader.cursor();
      }
      if (listType == 'ulist') {
        listItem.marker = trait as String;
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
                reader.cursor(),
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
        final ordinal = listBlock.blocks.length;
        final (resolvedMarker, implicitStyle) = resolveOrderedListMarker(
          trait as String,
          ordinal: ordinal,
          validate: true,
          reader: reader,
        );
        trait = resolvedMarker;
        listItem.marker = resolvedMarker;
        if (ordinal == 0 && style == null) {
          // Using list level makes more sense, but we don't track it.
          // Basing style on marker level is compliant with AsciiDoc.py.
          final fallbackIndex = resolvedMarker.length - 1;
          // NOTE the implicit style and the fallback are distinguished; see
          // ListBlock.markerStyle.
          listBlock.style =
              (listBlock.markerStyle = implicitStyle) ??
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
              reader.cursor(),
            );
          }
        }
      } else {
        // 'colist'
        listItem.marker = trait as String;
        if (itemText.startsWith('[[')) {
          final anchorMatch = leadingInlineAnchorRx.firstMatch(itemText);
          if (anchorMatch != null) {
            catalogInlineAnchor(
              anchorMatch.group(1)!,
              anchorMatch.group(2),
              listItem,
              reader.cursor(),
            );
          }
        }
      }
    }

    // First skip the line with the marker / term (it gets put back onto
    // the reader by nextBlock).
    reader.shift();
    final blockCursor = reader.cursor();
    final itemLines = readLinesForListItem(
      reader,
      listType,
      siblingTrait: trait,
      hasText: hasText,
    );
    final listItemReader = Reader(
      itemLines.lines,
      continuationPlaceholders: itemLines.placeholders,
      cursor: blockCursor,
    );
    if (listItemReader.hasMoreLines()) {
      if (sourcemapAssignmentDeferred) {
        listItem.sourceLocation = blockCursor;
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
          // first block (i.e., hasText is null).
          if (!dlist) hasText = false;
        }
      }

      // Reader is confined to boundaries of list, which means only blocks
      // will be found (no sections).
      final firstBlock = nextBlock(
        listItemReader,
        listItem,
        attributes: BlockAttributes(),
        textOnly: !hasText,
        listType: listType,
      );
      if (firstBlock != null) listItem.blocks.add(firstBlock);

      while (listItemReader.hasMoreLines()) {
        final block = nextBlock(
          listItemReader,
          listItem,
          attributes: BlockAttributes(),
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
      return (term: listTerm, item: description);
    }
    return (term: null, item: listItem);
  }

  /// Collects the lines belonging to the current list item, with the
  /// indexes of the empty lines that stand for a consumed list continuation
  /// (for [Reader.nextLineIsContinuationPlaceholder]).
  ///
  /// Port of `Parser.read_lines_for_list_item`.
  static ({List<String> lines, Set<int> placeholders}) readLinesForListItem(
    Reader reader,
    String listType, {
    Pattern? siblingTrait,
    bool hasText = true,
  }) {
    final buffer = <_ItemLine>[];

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
      final placeholder = reader.nextLineIsContinuationPlaceholder;
      final rawLine = reader.readLine();
      if (rawLine == null) break;
      pendingLine = rawLine;

      // If we've arrived at a sibling item in this list, we've captured
      // the complete list item and can begin processing it. The remainder
      // of the method determines whether we've reached the termination
      // of the list.
      if (isSiblingListItem(rawLine, listType, siblingTrait)) break;

      final _ItemLine thisLine;
      if (rawLine == listContinuation) {
        thisLine = _ListContinuation.active;
      } else if (placeholder && rawLine.isEmpty) {
        thisLine = _ListContinuation.placeholder;
      } else {
        thisLine = _TextLine(rawLine);
      }
      final prevLine = buffer.isEmpty ? null : buffer.last;

      if (prevLine is _ListContinuation) {
        if (continuation == 'inactive') {
          continuation = 'active';
          hasText_ = true;
          if (!withinNestedList) {
            buffer[buffer.length - 1] = _ListContinuation.placeholder;
          }
        }

        // Dealing with adjacent list continuations (which is really a
        // syntax error).
        if (thisLine is _ListContinuation) {
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
      final delimitedMatch = thisLine is _TextLine
          ? isDelimitedBlock(thisLine.text)
          : null;
      if (delimitedMatch != null) {
        if (continuation != 'active') break;
        // Grab all the lines in the block, leaving the delimiters in
        // place. We're being more strict here about the terminator, but
        // I think that's a good thing.
        buffer
          ..add(thisLine)
          ..addAll(
            reader
                .readLinesUntil(
                  terminator: delimitedMatch.terminator,
                  readLastLine: true,
                  warnIfUnterminated: false,
                )
                .map(_TextLine.new),
          );
        continuation = 'inactive';
      } else if (dlist &&
          continuation != 'active' &&
          thisLine is _TextLine &&
          thisLine.text.startsWith('[') &&
          blockAttributeLineRx.hasMatch(thisLine.text)) {
        // BlockAttributeLineRx only breaks dlist if ensuing line is not a
        // list item.
        final blockAttributeLines = <String>[thisLine.text];
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
            buffer.addAll(blockAttributeLines.map(_TextLine.new));
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
      } else if (continuation == 'active' && thisLine.text.isNotEmpty) {
        // Literal paragraphs have special considerations (and this is one
        // of two entry points into one). If we don't process it as a
        // whole, then a line in it that looks like a list item will throw
        // off the exit from it.
        if (literalParagraphRx.hasMatch(thisLine.text)) {
          reader.unshiftLine(thisLine.text);
          if (dlist) {
            // We may be in an indented list disguised as a literal
            // paragraph, so we need to make sure we don't slurp up a
            // legitimate sibling.
            buffer.addAll(
              reader
                  .readLinesUntil(
                    preserveLastLine: true,
                    breakOnBlankLines: true,
                    breakOnListContinuation: true,
                    test: (line) =>
                        isSiblingListItem(line, listType, siblingTrait),
                  )
                  .map(_TextLine.new),
            );
          } else {
            buffer.addAll(
              reader
                  .readLinesUntil(
                    preserveLastLine: true,
                    breakOnBlankLines: true,
                    breakOnListContinuation: true,
                  )
                  .map(_TextLine.new),
            );
          }
          continuation = 'inactive';
        } else if (thisLine.text case final text
            when (text.startsWith('.') && blockTitleRx.hasMatch(text)) ||
                (text.startsWith('[') && blockAttributeLineRx.hasMatch(text)) ||
                (text.startsWith(':') && attributeEntryRx.hasMatch(text))) {
          // Let block metadata play out until we find the block.
          buffer.add(thisLine);
        } else {
          final nested = _findNestedList(
            thisLine.text,
            withinNestedList ? const ['dlist'] : _nestableListContexts,
          );
          if (nested != null) {
            withinNestedList = true;
            if (nested.$1 == 'dlist' && nested.$2.group(3).isNullOrEmpty) {
              // Get greedy again.
              hasText_ = false;
            }
          }
          buffer.add(thisLine);
          continuation = 'inactive';
        }
      } else if (prevLine != null && prevLine.text.isEmpty) {
        var current = thisLine.text;
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
          // TODO any way to combine this with the check after skipping
          // blank lines?
          if (isSiblingListItem(current, listType, siblingTrait)) {
            pendingLine = current;
            break;
          }
          final nested = _findNestedList(current, _nestableListContexts);
          if (nested != null) {
            buffer.add(_TextLine(current));
            withinNestedList = true;
            if (nested.$1 == 'dlist' && nested.$2.group(3).isNullOrEmpty) {
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
                reader
                    .readLinesUntil(
                      preserveLastLine: true,
                      breakOnBlankLines: true,
                      breakOnListContinuation: true,
                      test: (line) =>
                          isSiblingListItem(line, listType, siblingTrait),
                    )
                    .map(_TextLine.new),
              );
            } else {
              buffer.addAll(
                reader
                    .readLinesUntil(
                      preserveLastLine: true,
                      breakOnBlankLines: true,
                      breakOnListContinuation: true,
                    )
                    .map(_TextLine.new),
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
          buffer.add(_TextLine(current));
          hasText_ = true;
        }
      } else if (thisLine is _ListContinuation) {
        hasText_ = true;
        buffer.add(thisLine);
      } else {
        final text = thisLine.text;
        if (text.isNotEmpty) {
          hasText_ = true;
          final nested = _findNestedList(
            text,
            withinNestedList ? const ['dlist'] : _nestableListContexts,
          );
          if (nested != null) {
            withinNestedList = true;
            if (nested.$1 == 'dlist' && nested.$2.group(3).isNullOrEmpty) {
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
      if (lastLine is _ListContinuation) {
        // Drop optional trailing continuation.
        buffer.removeLast();
        break;
      } else if (lastLine.text.isEmpty) {
        // Strip trailing blank lines to prevent empty blocks.
        buffer.removeLast();
      } else {
        break;
      }
    }

    return (
      lines: [for (final line in buffer) line.text],
      placeholders: {
        for (var i = 0; i < buffer.length; i++)
          if (identical(buffer[i], _ListContinuation.placeholder)) i,
      },
    );
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
  /// marker in the number series and the implicit list style, if
  /// applicable.
  static (String, String?) resolveOrderedListMarker(
    String marker, {
    int ordinal = 0,
    bool validate = false,
    Reader? reader,
  }) {
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
        expected = (ordinal + 1).toString();
        actual = _toInt(marker).toString(); // remove trailing .
      }
      resolved = '1.';
    } else if (style == 'loweralpha') {
      if (validate) {
        expected = String.fromCharCode(97 + ordinal); // 97 is a
        actual = marker.substring(0, marker.length - 1); // remove .
      }
      resolved = 'a.';
    } else if (style == 'upperalpha') {
      if (validate) {
        expected = String.fromCharCode(65 + ordinal); // 65 is A
        actual = marker.substring(0, marker.length - 1); // remove .
      }
      resolved = 'A.';
    } else if (style == 'lowerroman') {
      if (validate) {
        expected = Helpers.intToRoman(ordinal + 1).toLowerCase();
        actual = marker.substring(0, marker.length - 1); // remove )
      }
      resolved = 'i)';
    } else if (style == 'upperroman') {
      if (validate) {
        expected = Helpers.intToRoman(ordinal + 1);
        actual = marker.substring(0, marker.length - 1); // remove )
      }
      resolved = 'I)';
    }

    if (validate && expected != actual) {
      _logger.warn(
        'list item index: expected $expected, got $actual',
        at: reader!.cursor(),
      );
    }
    return (resolved, style);
  }

  /// Determines whether [line] is a sibling list item.
  ///
  /// Port of `Parser.is_sibling_list_item?`. [siblingTrait] is the list
  /// marker or (for description lists) the sibling pattern.
  static bool isSiblingListItem(
    String line,
    String listType,
    Pattern? siblingTrait,
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
    BlockAttributes attributes,
  ) {
    final table = Table(parent, attributes);

    var explicitColspecs = false;
    if (attributes.containsKey('cols')) {
      final colspecs = parseColspecs(attributes['cols']!);
      if (colspecs.isNotEmpty) {
        table.createColumns(colspecs);
        explicitColspecs = true;
      }
    }

    final skipped = tableReader.skipBlankLines() ?? 0;
    var implicitHeader = false;
    if (attributes.containsKey('header-option')) {
      table.header = TableHeader.explicit;
    } else if (skipped == 0 && !attributes.containsKey('noheader-option')) {
      // NOTE assume table has header until we know otherwise; if it
      // doesn't (undecided), cells in first row get reprocessed.
      table.header = TableHeader.implicit;
      implicitHeader = true;
    }
    final parserCtx = TableParserContext(tableReader, table, attributes);
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
          // If cellspec is not null, we're at a cell boundary.
          if (nextCellspec != null) {
            parserCtx.closeOpenCell(nextCellspec);
            if (implicitHeaderBoundary != null) {
              implicitHeaderBoundary = null;
            }
          } else if (implicitHeaderBoundary != null &&
              implicitHeaderBoundary == loopIdx) {
            // Otherwise, the cell continues from previous line.
            table.header = TableHeader.undecided;
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
            table.header = TableHeader.undecided;
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
            parserCtx.pushCellspec(nextCellspec ?? const CellSpec());
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
                table.header = TableHeader.undecided;
                implicitHeader = false;
                implicitHeaderBoundary = null;
              }
              parserCtx.keepCellOpen();
            } else {
              parserCtx.closeCell(eol: true);
            }
          } else if (format == 'dsv') {
            parserCtx.closeCell(eol: true);
          } else {
            // psv
            parserCtx.keepCellOpen();
          }
          break;
        }
      }

      // NOTE cell may already be closed if table format is csv or dsv.
      if (parserCtx.isCellOpen) {
        if (!tableReader.hasMoreLines()) parserCtx.closeCell(eol: true);
      } else {
        if (tableReader.skipBlankLines() == null) break;
      }
    }

    parserCtx.closeTable();
    final colcount = table.attributes['colcount'] ??= '${table.columns.length}';
    if (colcount != '0' && !explicitColspecs) table.assignColumnWidths();
    if (implicitHeader) table.header = TableHeader.explicit;
    table.partitionHeaderFooter(
      footer: attributes.containsKey('footer-option'),
    );

    return table;
  }

  /// Parses the column specs for a table.
  ///
  /// Port of `Parser.parse_colspecs`.
  static List<ColumnSpec> parseColspecs(String records) {
    var input = records;
    if (input.contains(' ')) input = input.replaceAll(' ', '');
    // Check for deprecated syntax: single number, equal column spread.
    if (input == _toInt(input).toString()) {
      return List.generate(_toInt(input), (_) => const ColumnSpec());
    }

    final specs = <ColumnSpec>[];
    // An empty list (`cols=""`) has no records, so the first row decides.
    if (input.isEmpty) return specs;
    // NOTE Dart split keeps trailing empty records, like split with -1.
    final parts = input.contains(',') ? input.split(',') : input.split(';');
    for (final record in parts) {
      if (record.isEmpty) {
        specs.add(const ColumnSpec());
      } else {
        // TODO might want to use scan rather than this mega-regexp.
        final m = columnSpecRx.firstMatch(record);
        if (m != null) {
          String? halign;
          String? valign;
          if (m.group(2) != null) {
            // Make this an operation.
            final alignParts = splitDropTrailingEmpty(m.group(2)!, '.');
            final colspec = alignParts[0];
            final rowspec = alignParts.length > 1 ? alignParts[1] : null;
            halign = _tableCellHorzAlignments[colspec];
            if (rowspec != null) valign = _tableCellVertAlignments[rowspec];
          }

          final width = m.group(3);
          // to_i will strip the optional %.
          final spec = ColumnSpec(
            width: width == null ? 1 : (width == '~' ? -1 : _toInt(width)),
            halign: halign,
            valign: valign,
            style: _tableCellStyles[m.group(4) ?? ''],
          );

          final repeat = m.group(1);
          if (repeat != null) {
            final count = int.parse(repeat);
            for (var i = 0; i < count; i++) {
              specs.add(spec);
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
  static (CellSpec?, String) parseCellspec(
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
      if (m.group(0)!.isEmpty) return (const CellSpec(), rest);
      return (_cellspecFromMatch(m), rest);
    }
    final m = cellSpecEndRx.firstMatch(line);
    if (m == null) return (const CellSpec(), line);
    // NOTE return the line stripped of trailing whitespace if no cellspec
    // is found in this case.
    if (trimLeftAscii(m.group(0)!).isEmpty) {
      return (const CellSpec(), line.trimRightAscii());
    }
    return (_cellspecFromMatch(m), line.substring(0, m.start));
  }

  /// Builds a cell spec from a cellspec regex match.
  static CellSpec _cellspecFromMatch(RegExpMatch m) {
    int? colspan;
    int? rowspan;
    int? repeat;
    if (m.group(1) != null) {
      final spanParts = splitDropTrailingEmpty(m.group(1)!, '.');
      final colspec = spanParts.isEmpty ? null : spanParts[0];
      final rowspec = spanParts.length > 1 ? spanParts[1] : null;
      final col = colspec.isNullOrEmpty ? 1 : _toInt(colspec);
      final row = rowspec.isNullOrEmpty ? 1 : _toInt(rowspec);
      if (m.group(2) == '+') {
        if (col != 1) colspan = col;
        if (row != 1) rowspan = row;
      } else if (m.group(2) == '*') {
        if (col != 1) repeat = col;
      }
    }

    String? halign;
    String? valign;
    if (m.group(3) != null) {
      final alignParts = splitDropTrailingEmpty(m.group(3)!, '.');
      final colspec = alignParts.isEmpty ? null : alignParts[0];
      final rowspec = alignParts.length > 1 ? alignParts[1] : null;
      if (colspec != null) halign = _tableCellHorzAlignments[colspec];
      if (rowspec != null) valign = _tableCellVertAlignments[rowspec];
    }

    return CellSpec(
      colspan: colspan,
      rowspan: rowspan,
      repeat: repeat,
      halign: halign,
      valign: valign,
      style: _tableCellStyles[m.group(4) ?? ''],
    );
  }

  /// Parses lines of metadata until a line of metadata is not found.
  ///
  /// Port of `Parser.parse_block_metadata_lines`.
  static BlockAttributes parseBlockMetadataLines(
    Reader reader,
    Document document,
    BlockAttributes attributes, {
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
    BlockAttributes attributes, {
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
          // An empty anchor (`[[]]`) clears the id.
          switch (anchorMatch.group(1)) {
            case final id?:
              attributes['id'] = id;
            case null:
              attributes.remove('id');
          }
          final reftext = anchorMatch.group(2);
          if (reftext != null) {
            attributes['reftext'] = reftext.contains(attrRefHead)
                ? subAttributes(document, reftext)
                : reftext;
          }
          return true;
        }
      } else if (nextLine.endsWith(']')) {
        final attrMatch = blockAttributeListRx.firstMatch(nextLine);
        if (attrMatch != null) {
          final currentStyle = attributes['1'];
          // Extract id, role, and options from first positional attribute
          // and remove, if present.
          final parsed = parseAttributes(
            document,
            attrMatch.group(1),
            posattrs: [],
            subInput: true,
            subResult: true,
            into: attributes,
          );
          if (parsed['1'] != null) {
            _setOrRemove(
              attributes,
              '1',
              parseStyleAttribute(attributes, reader) ?? currentStyle,
            );
          }
          return true;
        }
      }
    } else if (normal && nextLine.startsWith('.')) {
      final titleMatch = blockTitleRx.firstMatch(nextLine);
      if (titleMatch != null) {
        // NOTE title doesn't apply to section, but we need to stash it for
        // the first block.
        // TODO should issue an error if this is found above the document
        // title.
        attributes['title'] = titleMatch.group(1)!;
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
    BlockAttributes? attributes,
  ]) {
    reader.skipCommentLines();
    while (processAttributeEntry(reader, document, attributes)) {
      // Discard line just processed.
      reader
        ..shift()
        ..skipCommentLines();
    }
  }

  /// Processes a single attribute entry line.
  ///
  /// Port of `Parser.process_attribute_entry`. Returns whether an entry
  /// was processed.
  static bool processAttributeEntry(
    Reader reader,
    Document? document, [
    BlockAttributes? attributes,
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
      final first = rawValue.substring(0, rawValue.length - 2).trimRightAscii();
      final joined = StringBuffer(first);
      // The accumulator always ends with the last appended line, so the
      // ends-with-break check tracks just that line.
      var endsWithBreak = first.endsWith(_hardLineBreak);
      while (reader.advance()) {
        var nextLine = trimLeftAscii(reader.peekLine() ?? '');
        if (nextLine.isEmpty) break;
        final keepOpen = nextLine.endsWith(con);
        if (keepOpen) {
          nextLine = nextLine
              .substring(0, nextLine.length - 2)
              .trimRightAscii();
        }
        joined
          ..write(endsWithBreak ? lf : ' ')
          ..write(nextLine);
        endsWithBreak = nextLine.endsWith(_hardLineBreak);
        if (!keepOpen) break;
      }
      value = joined.toString();
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
  static (String, String?) storeAttribute(
    String name,
    String? value, [
    Document? doc,
    BlockAttributes? attrs,
  ]) {
    // TODO move processing of attribute value to utility method.
    var resolvedName = name;
    var resolvedValue = value;
    if (resolvedName.endsWith('!')) {
      // A null value signals the attribute should be deleted (unset).
      resolvedName = resolvedName.substring(0, resolvedName.length - 1);
      resolvedValue = null;
    } else if (resolvedName.startsWith('!')) {
      // A null value signals the attribute should be deleted (unset).
      resolvedName = resolvedName.substring(1);
      resolvedValue = null;
    }

    resolvedName = sanitizeAttributeName(resolvedName);
    if (resolvedName == 'numbered') {
      resolvedName = 'sectnums';
    } else if (resolvedName == 'hardbreaks') {
      resolvedName = 'hardbreaks-option';
    } else if (resolvedName == 'showtitle') {
      storeAttribute('notitle', resolvedValue != null ? null : '', doc, attrs);
    }

    if (doc != null) {
      if (resolvedValue != null) {
        var stringValue = resolvedValue;
        if (resolvedName == 'leveloffset') {
          // Support relative leveloffset values.
          if (stringValue.startsWith('+')) {
            stringValue =
                (_toInt(doc.attr('leveloffset', '0')) +
                        _toInt(stringValue.substring(1)))
                    .toString();
          } else if (stringValue.startsWith('-')) {
            stringValue =
                (_toInt(doc.attr('leveloffset', '0')) -
                        _toInt(stringValue.substring(1)))
                    .toString();
          }
        }
        // QUESTION should we set value to locked value if set_attribute
        // returns false?
        final resolved = doc.setAttribute(resolvedName, stringValue);
        if (resolved != null) {
          resolvedValue = resolved;
          attrs?.addEntry(DocumentAttributeEntry(resolvedName, resolved));
        }
      } else if (!doc.attributeLocked(resolvedName)) {
        // Unlocked attributes are always deleted (and the entry recorded),
        // even when absent.
        doc.deleteAttribute(resolvedName);
        attrs?.addEntry(DocumentAttributeEntry(resolvedName, null));
      }
    } else {
      attrs?.addEntry(DocumentAttributeEntry(resolvedName, resolvedValue));
    }

    return (resolvedName, resolvedValue);
  }

  /// Parses the first positional attribute and assigns named attributes.
  ///
  /// Port of `Parser.parse_style_attribute`. Returns the parsed style.
  static String? parseStyleAttribute(
    Map<String, String> attributes, [
    Reader? reader,
  ]) {
    // NOTE spaces are not allowed in shorthand, so if we detect one, this
    // ain't no shorthand.
    final rawStyle = attributes['1'];
    if (rawStyle != null &&
        !rawStyle.contains(' ') &&
        _shorthandPropertySyntax) {
      String? name;
      var accum = '';
      final parsed = _Shorthand();

      for (final rune in rawStyle.runes) {
        final c = String.fromCharCode(rune);
        if (c == '.') {
          parsed.add(name, accum, reader);
          accum = '';
          name = 'role';
        } else if (c == '#') {
          parsed.add(name, accum, reader);
          accum = '';
          name = 'id';
        } else if (c == '%') {
          parsed.add(name, accum, reader);
          accum = '';
          name = 'option';
        } else {
          accum += c;
        }
      }

      // Small optimization if no shorthand is found.
      if (name != null) {
        parsed.add(name, accum, reader);

        final parsedStyle = parsed.style;
        if (parsedStyle != null) attributes['style'] = parsedStyle;

        if (parsed.id case final id?) attributes['id'] = id;

        if (parsed.roles.isNotEmpty) {
          final roles = parsed.roles.join(' ');
          final existingRole = attributes['role'];
          attributes['role'] = existingRole == null || existingRole.isEmpty
              ? roles
              : '$existingRole $roles';
        }

        for (final opt in parsed.options) {
          attributes['$opt-option'] = '';
        }

        return parsedStyle;
      }
    }
    _setOrRemove(attributes, 'style', rawStyle);
    return rawStyle;
  }

  /// Consumes and parses the two header lines (line 1 = author info,
  /// line 2 = revision info).
  ///
  /// Port of `Parser.parse_header_metadata`. When [document] is given,
  /// the metadata is applied to it. Returns the merged metadata map when
  /// [retrieve] is set, else an empty map.
  static Map<String, String> parseHeaderMetadata(
    Reader reader, {
    Document? document,
    bool retrieve = true,
  }) {
    final docAttrs = document?.attributes;
    // NOTE this will discard any comment lines, but not skip blank lines.
    processAttributeEntries(reader, document);

    Map<String, String> implicitAuthorMetadata;
    Map<String, String>? revMetadata;
    Map<String, String>? authorMetadata;
    String? authorcount;
    String? implicitAuthor;
    String? implicitAuthorinitials;
    String? implicitAuthors;
    if (reader.hasMoreLines() && !reader.isNextLineEmpty()) {
      implicitAuthorMetadata = processAuthors(reader.readLine()!);
      authorcount = implicitAuthorMetadata.remove('authorcount');
      if (document != null && docAttrs != null) {
        _setOrRemove(docAttrs, 'authorcount', authorcount);
        if (_toInt(authorcount) > 0) {
          implicitAuthorMetadata.forEach((key, val) {
            // Apply header subs and assign to document; attributes
            // substitution only relevant for email.
            if (!docAttrs.containsKey(key)) {
              docAttrs[key] = document.applyHeaderSubs(val);
            }
          });
          implicitAuthor = docAttrs['author'];
          implicitAuthorinitials = docAttrs['authorinitials'];
          implicitAuthors = docAttrs['authors'];
        }
      }
      _setOrRemove(implicitAuthorMetadata, 'authorcount', authorcount);

      // NOTE this will discard any comment lines, but not skip blank lines.
      processAttributeEntries(reader, document);

      if (reader.hasMoreLines() && !reader.isNextLineEmpty()) {
        final revLine = reader.readLine()!;
        final revMatch = revisionInfoLineRx.firstMatch(revLine);
        if (revMatch != null) {
          revMetadata = <String, String>{};
          if (revMatch.group(1) != null) {
            revMetadata['revnumber'] = revMatch.group(1)!.trimRightAscii();
          }
          final component = revMatch.group(2)!.trimAscii();
          if (component.isNotEmpty) {
            // Version must begin with 'v' if date is absent.
            if (revMatch.group(1) == null && component.startsWith('v')) {
              revMetadata['revnumber'] = component.substring(1);
            } else {
              revMetadata['revdate'] = component;
            }
          }
          if (revMatch.group(3) != null) {
            revMetadata['revremark'] = revMatch.group(3)!.trimRightAscii();
          }
          if (document != null && docAttrs != null && revMetadata.isNotEmpty) {
            // Apply header subs and assign to document.
            revMetadata.forEach((key, val) {
              if (!docAttrs.containsKey(key)) {
                docAttrs[key] = document.applyHeaderSubs(val);
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
      implicitAuthorMetadata = <String, String>{};
    }

    // Process author attribute entries that override (or stand in for)
    // the implicit author line.
    if (document != null && docAttrs != null) {
      if (docAttrs.containsKey('author') &&
          docAttrs['author'] != implicitAuthor) {
        // Do not allow multiple, process as names only.
        authorMetadata = processAuthors(
          docAttrs['author']!,
          namesOnly: true,
          multiple: false,
        );
        if (docAttrs['authorinitials'] != implicitAuthorinitials) {
          authorMetadata.remove('authorinitials');
        }
      } else if (docAttrs.containsKey('authors') &&
          docAttrs['authors'] != implicitAuthors) {
        // Allow multiple, process as names only.
        authorMetadata = processAuthors(docAttrs['authors']!, namesOnly: true);
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
          final authorOverride = docAttrs[authorKey];
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
          authorMetadata = _processAuthorEntries([
            for (final author in authors) author ?? '',
          ], namesOnly: true);
        } else {
          authorMetadata = <String, String>{'authorcount': '0'};
        }
      }

      if (authorMetadata['authorcount'] == '0') {
        if (authorcount != null) {
          authorMetadata = null;
        } else {
          docAttrs['authorcount'] = '0';
        }
      } else {
        docAttrs.addAll(authorMetadata);

        // Special case.
        if (!docAttrs.containsKey('email') && docAttrs.containsKey('email_1')) {
          docAttrs['email'] = docAttrs['email_1']!;
        }
      }
    }

    if (!retrieve) return <String, String>{};
    return <String, String>{
      ...implicitAuthorMetadata,
      ...?revMetadata,
      ...?authorMetadata,
    };
  }

  /// Parses the author line into a map of author metadata.
  ///
  /// Port of `Parser.process_authors`. With [multiple], the line may hold
  /// several authors separated by semicolons. The `authorcount` entry holds
  /// the number of authors.
  static Map<String, String> processAuthors(
    String authorLine, {
    bool namesOnly = false,
    bool multiple = true,
  }) => _processAuthorEntries(
    multiple && authorLine.contains(';')
        ? authorLine.split(authorDelimiterRx)
        : [authorLine],
    namesOnly: namesOnly,
  );

  /// Parses author [entries] (one author each) into author metadata (see
  /// [processAuthors]).
  static Map<String, String> _processAuthorEntries(
    List<String> entries, {
    bool namesOnly = false,
  }) {
    final authorMetadata = <String, String>{};
    var authorIdx = 0;
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
          parts[2] = collapseRuns(parts[2], ' ');
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
        // NOTE segments has 1-3 entries when names_only; missing ones are
        // null.
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
        final fname = collapseRuns(authorEntry, ' ').trimAscii();
        authorMetadata[keyMap['author']!] =
            authorMetadata[keyMap['firstname']!] = fname;
        authorMetadata[keyMap['authorinitials']!] = _firstChar(fname);
      }

      if (authorIdx == 1) {
        authorMetadata['authors'] = authorMetadata[keyMap['author']]!;
      } else {
        // Only assign the _1 attributes once we see the second author.
        if (authorIdx == 2) {
          for (final key in _authorKeys) {
            if (authorMetadata.containsKey(key)) {
              authorMetadata['${key}_1'] = authorMetadata[key]!;
            }
          }
        }
        authorMetadata['authors'] =
            '${authorMetadata['authors']}, ${authorMetadata[keyMap['author']]}';
      }
    }

    authorMetadata['authorcount'] = '$authorIdx';
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
    // present). The indent prefix is ASCII whitespace only, so UTF-16
    // offsets equal character offsets.
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
    // NOTE blockIndent is > 0 if not null.
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
      downcase(name.replaceAll(invalidAttributeNameCharsRx, ''));
}

/// The attributes collected from the shorthand syntax of a first positional
/// attribute (`style#id.role%option`).
final class _Shorthand {
  String? style;
  String? id;
  final List<String> roles = <String>[];
  final List<String> options = <String>[];

  /// Saves the collected [value] for [name] (`id`, `option`, `role`, or
  /// `null` for the style).
  ///
  /// Port of `Parser.yield_buffered_attribute`.
  void add(String? name, String value, Reader? reader) {
    if (name != null) {
      if (value.isEmpty) {
        LoggerManager.logger.warn(
          'invalid empty $name detected in style attribute',
          at: reader?.cursorAtPrevLine(),
        );
      } else if (name == 'id') {
        if (id != null) {
          LoggerManager.logger.warn(
            'multiple ids detected in style attribute',
            at: reader?.cursorAtPrevLine(),
          );
        }
        id = value;
      } else if (name == 'role') {
        roles.add(value);
      } else {
        options.add(value);
      }
    } else if (value.isNotEmpty) {
      style = value;
    }
  }
}
