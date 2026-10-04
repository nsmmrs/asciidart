/// Manpage converter: generates man page (groff) output from a parsed document.
///
/// Port of `lib/asciidoctor/converter/manpage.rb` (complete). Per
/// `adr/0001-dart-rewrite-goals.md` (D4) every template method produces
/// byte-identical output to the Ruby converter, including whitespace.
///
/// ## Framework integration
///
/// Ruby's `convert_<transform>` methods become handler registrations via
/// [ConverterBase.handle] (see `converter.dart`); [ManpageConverter.convert]
/// itself is inherited from [ConverterBase], which warns and returns `null`
/// for unregistered transforms, mirroring Ruby's `NoMethodError` rescue. The
/// converter registers itself with [Converter.register] (explicit
/// registration replaces Ruby's lazy `require`).
///
/// The converter only consumes already-substituted strings (`content`,
/// `title`, `text`, `alt`, `captioned_title`, `xreftext`), so — unlike the
/// html5 port — it needs no TEMP-SHIM from the substitutors wave.
library;

import 'dart:io';

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/table.dart';

/// Renders [value] the way Ruby string interpolation does: `toString`,
/// except `null` (and, via callers, Ruby `nil`) renders as the empty
/// string instead of `'null'`.
String _s(Object? value) => value?.toString() ?? '';

/// Whitespace characters collapsed by `tr_s` (port of `WHITESPACE`).
const String _whitespace = '\n\t ';

/// Tab expansion for preserved whitespace (port of `ET`, `' ' * 8`).
const String _et = '        ';

/// Troff leader marker (port of Ruby's `ESC`, the single ESC character).
final String _esc = String.fromCharCode(27);

/// Escaped backslash: indicates a troff formatting sequence (`ESC_BS`).
final String _escBs = '$_esc\\';

/// Escaped full stop: indicates a troff macro (`ESC_FS`).
final String _escFs = '$_esc.';

/// Matches a literal backslash (port of `LiteralBackslashRx`; `\A` is `^`
/// without `multiLine` per `PORTING-REGEXP.md` B2).
final RegExp _literalBackslashRx = RegExp('^\\\\|($_esc)?\\\\');

/// Matches a leading period (port of `LeadingPeriodRx`).
final RegExp _leadingPeriodRx = RegExp(r'^\.', multiLine: true);

/// Matches an escaped URL/MTO macro line (port of `EscapedMacroRx`;
/// `CC_ANY` is [ccAny]).
final RegExp _escapedMacroRx = RegExp(
  '^(?:$_esc\\\\c\n)?$_esc\\.((?:URL|MTO) "$ccAny*?" "$ccAny*?" )'
  '( |[^\\s]*)($ccAny*?)(?: *$_esc\\\\c)?\$',
  multiLine: true,
);

/// Matches a malformed escaped macro (port of `MalformedEscapedMacroRx`).
final RegExp _malformedEscapedMacroRx = RegExp(
  '($_esc\\\\c) ($_esc\\.(?:URL|MTO) )',
);

/// Matches mock macro boundaries (port of `MockMacroRx`).
final RegExp _mockMacroRx = RegExp('</?($_esc\\\\[^>]+)>');

/// Matches an em-dash character reference (port of `EmDashCharRefRx`).
final RegExp _emDashCharRefRx = RegExp('&#8212;(?:&#8203;)?');

/// Matches an ellipsis character reference (port of `EllipsisCharRefRx`).
final RegExp _ellipsisCharRefRx = RegExp('&#8230;(?:&#8203;)?');

/// Matches wrapped indentation (port of `WrappedIndentRx`; `CG_BLANK` is
/// [cgBlank]).
final RegExp _wrappedIndentRx = RegExp('$cgBlank*\n$cgBlank*');

/// Matches XML markup (port of `XMLMarkupRx`).
final RegExp _xmlMarkupRx = RegExp(r'&#?[a-z\d]+;|</');

/// Splits PCDATA from markup (port of `PCDATAFilterRx`; `.` is [ccAny] per
/// `PORTING-REGEXP.md` W1).
final RegExp _pcdataFilterRx = RegExp(
  '(&#?[a-z\\d]+;|<$_esc\\\\f\\(CR$ccAny*?</$_esc\\\\fP>|<[^>]+>)|([^&<]+)',
);

/// Matches runs of two or more spaces (port of the inline `/(^)?  +/`
/// pattern in `manify`).
final RegExp _preserveSpacesRx = RegExp('(^)?  +', multiLine: true);

/// How [_manify] handles whitespace (port of the `:whitespace` option).
enum _WhitespaceMode {
  /// Collapse adjacent whitespace to a single space (the default).
  collapse,

  /// Remove spaces around newlines.
  normalize,

  /// Preserve spaces (only expanding tabs).
  preserve,
}

/// A built-in [Converter] implementation that generates the man page
/// (groff) format.
///
/// Port of `Asciidoctor::Converter::ManPageConverter`. Each `convert*`
/// method mirrors its Ruby `convert_*` namesake; template selection that
/// Ruby performs by method dispatch is expressed as [handle] registrations
/// below (see the library docs).
class ManpageConverter extends ConverterBase {
  /// Creates a converter for [backend] with constructor options [opts].
  ManpageConverter(super.backend, [super.opts]) {
    initBackendTraits(<String, Object?>{
      'basebackend': 'manpage',
      'filetype': 'man',
      'outfilesuffix': '.man',
      'supports_templates': true,
    });
    handle('document', (node, [opts]) => convertDocument(node as Document));
    handle('embedded', (node, [opts]) => convertEmbedded(node as Document));
    handle('section', (node, [opts]) => convertSection(node as Section));
    handle('admonition', (node, [opts]) => convertAdmonition(node as Block));
    handle('colist', (node, [opts]) => convertColist(node as ListBlock));
    handle('dlist', (node, [opts]) => convertDlist(node as ListBlock));
    handle('example', (node, [opts]) => convertExample(node as Block));
    handle(
      'floating_title',
      (node, [opts]) => convertFloatingTitle(node as Block),
    );
    handle('image', (node, [opts]) => convertImage(node as Block));
    handle('listing', (node, [opts]) => convertListing(node as Block));
    handle('literal', (node, [opts]) => convertLiteral(node as Block));
    handle('sidebar', (node, [opts]) => convertSidebar(node as Block));
    handle('olist', (node, [opts]) => convertOlist(node as ListBlock));
    handle('open', (node, [opts]) => convertOpen(node as Block));
    handle('page_break', (node, [opts]) => convertPageBreak(node as Block));
    handle('paragraph', (node, [opts]) => convertParagraph(node as Block));
    handle('pass', (node, [opts]) => contentOnly(node));
    handle('preamble', (node, [opts]) => contentOnly(node));
    handle('quote', (node, [opts]) => convertQuote(node as Block));
    handle('stem', (node, [opts]) => convertStem(node as Block));
    handle('table', (node, [opts]) => convertTable(node as Table));
    handle(
      'thematic_break',
      (node, [opts]) => convertThematicBreak(node as Block),
    );
    handle('toc', (node, [opts]) => skip(node));
    handle('ulist', (node, [opts]) => convertUlist(node as ListBlock));
    handle('verse', (node, [opts]) => convertVerse(node as Block));
    handle('video', (node, [opts]) => convertVideo(node as Block));
    handle(
      'inline_anchor',
      (node, [opts]) => convertInlineAnchor(node as Inline),
    );
    handle(
      'inline_break',
      (node, [opts]) => convertInlineBreak(node as Inline),
    );
    handle(
      'inline_button',
      (node, [opts]) => convertInlineButton(node as Inline),
    );
    handle(
      'inline_callout',
      (node, [opts]) => convertInlineCallout(node as Inline),
    );
    handle(
      'inline_footnote',
      (node, [opts]) => convertInlineFootnote(node as Inline),
    );
    handle(
      'inline_image',
      (node, [opts]) => convertInlineImage(node as Inline),
    );
    handle(
      'inline_indexterm',
      (node, [opts]) => convertInlineIndexterm(node as Inline),
    );
    handle('inline_kbd', (node, [opts]) => convertInlineKbd(node as Inline));
    handle('inline_menu', (node, [opts]) => convertInlineMenu(node as Inline));
    handle(
      'inline_quoted',
      (node, [opts]) => convertInlineQuoted(node as Inline),
    );
  }

  /// Memoized document refs catalog (port of `@refs`).
  Map<String, Object?>? _refs;

  /// Whether an xref is currently being resolved (port of
  /// `@resolving_xref`; guards against recursive xrefs).
  bool _resolvingXref = false;

  /// Registers this converter for [backends]. Called by document
  /// initialization; idempotent.
  static void registerFor([List<String> backends = const ['manpage']]) {
    Converter.register(ManpageConverter.new, backends, provided: true);
  }

  /// Converts the [node] document to a standalone man page.
  String convertDocument(Document node) {
    if (!node.hasAttr('mantitle')) {
      throw StateError(
        'asciidoctor: ERROR: doctype must be set to manpage when using '
        'manpage backend',
      );
    }
    final mantitle = (node.attr('mantitle') as String).replaceAll(
      invalidSectionIdCharsRx,
      '',
    );
    final manvolnum = node.attr('manvolnum', '1');
    final manname = node.attr('manname', mantitle);
    final manmanual = node.attr('manmanual');
    final mansource = node.attr('mansource');
    final docdate = node.hasAttr('reproducible') ? null : node.attr('docdate');
    // NOTE the first line enables the table (tbl) preprocessor, necessary
    // for non-Linux systems
    final result = <String>[
      '\'\\" t\n.\\"     Title: $mantitle\n.\\"    Author: ${node.hasAttr('authors') ? _s(node.attr('authors')) : '[see the "AUTHOR(S)" section]'}\n.\\" Generator: Asciidoctor ${_s(node.attr('asciidoctor-version'))}',
    ];
    if (isTruthy(docdate)) {
      result.add('.\\"      Date: ${_s(docdate)}');
    }
    result.add(
      '.\\"    Manual: ${isTruthy(manmanual) ? transliterateSqueeze(manmanual as String, _whitespace, ' ') : r'\ \&'}\n'
      '.\\"    Source: ${isTruthy(mansource) ? transliterateSqueeze(mansource as String, _whitespace, ' ') : r'\ \&'}\n'
      '.\\"  Language: English\n'
      r'.\"',
    );
    // TODOadd document-level setting to disable capitalization of manname
    result.add(
      '.TH "${_manify((manname as String).toUpperCase())}" "${_s(manvolnum)}" "${_s(docdate)}" '
      '"${isTruthy(mansource) ? _manify(mansource as String) : r'\ \&'}" '
      '"${isTruthy(manmanual) ? _manify(manmanual as String) : r'\ \&'}"',
    );
    // define portability settings
    // see http://bugs.debian.org/507673
    // see http://lists.gnu.org/archive/html/groff/2009-02/msg00013.html
    result.add(r'.ie \n(.g .ds Aq \(aq');
    result.add(".el       .ds Aq '");
    // set sentence_space_size to 0 to prevent extra space between sentences
    // separated by a newline
    // the alternative is to add \& at the end of the line
    result.add(r'.ss \n[.ss] 0');
    // disable hyphenation
    result.add('.nh');
    // disable justification (adjust text to left margin only)
    result.add('.ad l');
    // define URL macro for portability
    // see http://web.archive.org/web/20060102165607/http://people.debian.org/~branden/talks/wtfm/wtfm.pdf
    //
    // Usage
    //
    // .URL "http://www.debian.org" "Debian" "."
    //
    // * First argument: the URL
    // * Second argument: text to be hyperlinked
    // * Third (optional) argument: text that needs to immediately trail the
    //   hyperlink without intervening whitespace
    result.add(
      '.de URL\n'
      '\\fI\\\\\$2\\fP <\\\\\$1>\\\\\$3\n'
      '..\n'
      '.als MTO URL\n'
      '.if \\n[.g] \\{\\\n'
      '.  mso www.tmac\n'
      '.  am URL\n'
      '.    ad l\n'
      '.  .\n'
      '.  am MTO\n'
      '.    ad l\n'
      '.  .',
    );
    result.add('.  LINKSTYLE ${_s(node.attr('man-linkstyle', 'blue R < >'))}');
    result.add(r'.\}');

    if (!node.noheader) {
      if (node.hasAttr('manpurpose')) {
        final mannames =
            node.attr('mannames', <Object?>[manname]) as List<Object?>;
        result.add(
          '.SH "${(node.attr('manname-title', 'NAME') as String).toUpperCase()}"\n'
          '${mannames.map((n) => _manify(n as String).replaceAll(r'\-', '-')).join(', ')} \\- ${_manify(node.attr('manpurpose') as String, whitespace: _WhitespaceMode.normalize)}',
        );
      }
    }

    result.add(_s(node.content()));

    // QUESTION should NOTES come after AUTHOR(S)?
    _appendFootnotes(result, node);

    final authors = node.authors;
    if (authors.isNotEmpty) {
      if (authors.length > 1) {
        result.add('.SH "AUTHORS"');
        for (final author in authors) {
          result.add('.sp\n${_s(author.name)}');
        }
      } else {
        result.add('.SH "AUTHOR"\n.sp\n${_s(authors[0].name)}');
      }
    }

    return result.join('\n');
  }

  /// Converts the [node] embedded document.
  ///
  /// NOTE embedded doesn't really make sense in the manpage backend.
  String convertEmbedded(Document node) {
    final result = <String>[_s(node.content())];

    _appendFootnotes(result, node);

    // QUESTION should we add an AUTHOR(S) section?

    return result.join('\n');
  }

  /// Converts the [node] section.
  String convertSection(Section node) {
    final String macro;
    final String stitle;
    if (node.level! > 1) {
      macro = 'SS';
      // QUESTION why captioned title? why not when level == 1?
      stitle = node.captionedTitle();
    } else {
      macro = 'SH';
      stitle = _uppercasePcdata(node.title!);
    }
    return '.$macro "${_manify(stitle)}"\n${_s(node.content())}';
  }

  /// Converts the [node] admonition block.
  String convertAdmonition(Block node) {
    return '.if n .sp\n.RS 4\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag 1\n.br\n.ps +1\n'
        '.B ${_s(node.attr('textlabel'))}${node.hasTitle ? '\\fP: ${_manify(node.title!)}' : ''}\n.ps -1\n.br\n'
        '${_encloseContent(node)}\n.sp .5v\n.RE';
  }

  /// Converts the [node] callout list.
  String convertColist(ListBlock node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }
    result.add('.TS\ntab(:);\nr lw(\\n(.lu*75u/100u).');

    var num = 0;
    for (final item in node.items) {
      final listItem = item as ListItem;
      result.add("\\fB(${num += 1})\\fP\\h'-2n':T{");
      result.add(
        _manify(listItem.text as String, whitespace: _WhitespaceMode.normalize),
      );
      if (listItem.hasBlocks) {
        result.add(_s(listItem.content()));
      }
      result.add('T}');
    }
    result.add('.TE');
    return result.join('\n');
  }

  /// Converts the [node] description list.
  ///
  // TODOimplement horizontal (if it makes sense)
  String convertDlist(ListBlock node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }
    var counter = 0;
    for (final pair in node.items) {
      final parts = pair as List<Object?>;
      final terms = (parts[0] as List<Object?>).cast<ListItem>();
      final dd = parts[1] as ListItem?;
      counter += 1;
      if (node.style == 'qanda') {
        result.add(
          '.sp\n$counter. ${_manify(terms.map((dt) => _s(dt.text)).join(' '))}\n.RS 4',
        );
      } else {
        result.add(
          '.sp\n${_manify(terms.map((dt) => _s(dt.text)).join(', '), whitespace: _WhitespaceMode.normalize)}\n.RS 4',
        );
      }
      if (dd != null) {
        final hasText = dd.hasText;
        if (hasText) {
          result.add(
            _manify(dd.text as String, whitespace: _WhitespaceMode.normalize),
          );
        }
        if (dd.hasBlocks) {
          var ddContent = dd.content() as String;
          if (!hasText && ddContent.startsWith('.sp\n')) {
            ddContent = ddContent.substring(4);
          }
          result.add(ddContent);
        }
      }
      result.add('.RE');
    }
    return result.join('\n');
  }

  /// Converts the [node] example block.
  String convertExample(Block node) {
    final result = <String>[];
    result.add(
      node.hasTitle ? '.sp\n.B ${_manify(node.captionedTitle())}\n.br' : '.sp',
    );
    result.add('.RS 4\n${_encloseContent(node)}\n.RE');
    return result.join('\n');
  }

  /// Converts the [node] floating title.
  String convertFloatingTitle(Block node) => '.SS "${_manify(node.title!)}"';

  /// Converts the [node] image block.
  String convertImage(Block node) {
    final result = <String>[];
    result.add(
      node.hasTitle ? '.sp\n.B ${_manify(node.captionedTitle())}\n.br' : '.sp',
    );
    result.add('[${_manify(node.alt)}]');
    return result.join('\n');
  }

  /// Converts the [node] listing block.
  String convertListing(Block node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.captionedTitle())}\n.br');
    }
    result.add(
      '.sp\n.if n .RS 4\n.nf\n.fam C\n${_manify(node.content() as String, whitespace: _WhitespaceMode.preserve)}\n.fam\n.fi\n.if n .RE',
    );
    return result.join('\n');
  }

  /// Converts the [node] literal block.
  String convertLiteral(Block node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }
    result.add(
      '.sp\n.if n .RS 4\n.nf\n.fam C\n${_manify(node.content() as String, whitespace: _WhitespaceMode.preserve)}\n.fam\n.fi\n.if n .RE',
    );
    return result.join('\n');
  }

  /// Converts the [node] sidebar block.
  String convertSidebar(Block node) {
    final result = <String>[];
    result.add(node.hasTitle ? '.sp\n.B ${_manify(node.title!)}\n.br' : '.sp');
    result.add('.RS 4\n${_encloseContent(node)}\n.RE');
    return result.join('\n');
  }

  /// Converts the [node] ordered list.
  String convertOlist(ListBlock node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }

    final start = rubyToInteger(node.attr('start', 1));
    var idx = 0;
    for (final item in node.items) {
      final listItem = item as ListItem;
      final numeral = idx + start;
      idx += 1;
      final listText = _manify(
        listItem.text as String,
        whitespace: _WhitespaceMode.normalize,
      );
      result.add(
        '.sp\n.RS 4\n.ie n \\{\\\n\\h\'-04\' $numeral.\\h\'+01\'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP " $numeral." 4.2\n.\\}'
        '${listText.isEmpty ? '' : '\n$listText'}',
      );
      if (listItem.hasBlocks) {
        var itemContent = listItem.content() as String;
        if (listText.isEmpty && itemContent.startsWith('.sp\n')) {
          itemContent = itemContent.substring(4);
        }
        result.add(itemContent);
      }
      result.add('.RE');
    }
    return result.join('\n');
  }

  /// Converts the [node] open block.
  Object? convertOpen(Block node) {
    switch (node.style) {
      case 'abstract':
      case 'partintro':
        return _encloseContent(node);
      default:
        return node.content();
    }
  }

  /// Converts the [node] page break.
  String convertPageBreak(Block node) => '.bp';

  /// Converts the [node] paragraph.
  String convertParagraph(Block node) {
    if (node.hasTitle) {
      return '.sp\n.B ${_manify(node.title!)}\n.br\n${_manify(node.content() as String, whitespace: _WhitespaceMode.normalize)}';
    }
    return '.sp\n${_manify(node.content() as String, whitespace: _WhitespaceMode.normalize)}';
  }

  /// Converts the [node] quote block.
  String convertQuote(Block node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.RS 3\n.B ${_manify(node.title!)}\n.br\n.RE');
    }
    String? attributionLine = node.hasAttr('citetitle')
        ? '${_s(node.attr('citetitle'))} '
        : null;
    attributionLine = node.hasAttr('attribution')
        ? '${_s(attributionLine)}\\(em ${_s(node.attr('attribution'))}'
        : null;
    result.add('.RS 3\n.ll -.6i\n${_encloseContent(node)}\n.br\n.RE\n.ll');
    if (attributionLine != null) {
      result.add('.RS 5\n.ll -.10i\n$attributionLine\n.RE\n.ll');
    }
    return result.join('\n');
  }

  /// Converts the [node] stem block.
  String convertStem(Block node) {
    final result = <String>[];
    result.add(node.hasTitle ? '.sp\n.B ${_manify(node.title!)}\n.br' : '.sp');
    final delimiters = blockMathDelimiters[node.style]!;
    final open = delimiters[0];
    final close = delimiters[1];
    var equation = node.content() as String;
    if (equation.startsWith(open) && equation.endsWith(close)) {
      equation = equation.substring(
        open.length,
        equation.length - close.length,
      );
    }
    result.add(
      '${_manify(equation, whitespace: _WhitespaceMode.preserve)} (${_s(node.style)})',
    );
    return result.join('\n');
  }

  /// Converts the [node] table.
  ///
  /// NOTE This handler inserts empty cells to account for colspans and
  /// rowspans. In order to support colspans and rowspans properly, that
  /// information must be computed up front and consulted when rendering the
  /// cell as this information is not available on the cell itself.
  String convertTable(Table node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add(
        '.sp\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag 1\n.br\n.B ${_manify(node.captionedTitle())}\n',
      );
    }
    result.add('.TS\nallbox tab(:);');
    final rowHeader = <List<List<String>?>?>[];
    final rowText = <List<String>?>[];
    var rowIndex = 0;
    for (final section in node.rows.toMap().entries) {
      final tsec = section.key;
      final rows = section.value;
      if (rows.isEmpty) continue;
      for (final row in rows) {
        final headerRow = _rowHeaderAt(rowHeader, rowIndex);
        final textRow = _rowTextAt(rowText, rowIndex);
        var remainingCells = row.length;
        var cellIndex = 0;
        for (final cell in row) {
          remainingCells -= 1;
          final headerCell = _headerCellAt(headerRow, cellIndex);
          // add an empty cell as a placeholder if this is a rowspan cell
          if (headerCell.length == 1 && headerCell[0] == '^t') {
            textRow.add('T{\nT}:');
          }
          textRow.add('T{\n');
          final halignValue = cell.attr('halign', 'left') as String;
          final cellHalign = halignValue.isEmpty ? '' : halignValue[0];
          if (tsec == 'body') {
            if (headerRow.isEmpty || headerRow[cellIndex]!.isEmpty) {
              headerRow[cellIndex]!.add('${cellHalign}t');
            } else {
              _headerCellAt(headerRow, cellIndex + 1).add('${cellHalign}t');
            }
            final String cellContent;
            switch (cell.style) {
              case 'asciidoc':
                cellContent = _s(cell.content());
              case 'literal':
                cellContent =
                    '.nf\n${_manify(cell.text as String, whitespace: _WhitespaceMode.preserve)}\n.fi';
              default:
                cellContent = (cell.content() as List<Object?>)
                    .map(
                      (p) => _manify(
                        p as String,
                        whitespace: _WhitespaceMode.normalize,
                      ),
                    )
                    .join('\n.sp\n');
            }
            textRow.add('$cellContent\n');
          } else {
            // tsec == 'head' || tsec == 'foot'
            if (headerRow.isEmpty || headerRow[cellIndex]!.isEmpty) {
              headerRow[cellIndex]!.add('${cellHalign}tB');
            } else {
              _headerCellAt(headerRow, cellIndex + 1).add('${cellHalign}tB');
            }
            textRow.add(
              '${_manify(cell.text as String, whitespace: _WhitespaceMode.normalize)}\n',
            );
          }
          final colspan = cell.colspan;
          if (isTruthy(colspan) && (colspan as int) > 1) {
            for (var i = 0; i < colspan - 1; i++) {
              if (headerRow.isEmpty || headerRow[cellIndex]!.isEmpty) {
                headerRow[cellIndex + i]!.add('st');
              } else {
                _headerCellAt(headerRow, cellIndex + 1 + i).add('st');
              }
            }
          }
          final rowspan = cell.rowspan;
          if (isTruthy(rowspan) && (rowspan as int) > 1) {
            for (var i = 0; i < rowspan - 1; i++) {
              final futureRow = _rowHeaderAt(rowHeader, rowIndex + 1 + i);
              final existing = cellIndex < futureRow.length
                  ? futureRow[cellIndex]
                  : null;
              if (futureRow.isEmpty || existing!.isEmpty) {
                _headerCellAt(futureRow, cellIndex).add('^t');
              } else {
                _headerCellAt(futureRow, cellIndex + 1).add('^t');
              }
            }
          }
          if (remainingCells >= 1) {
            textRow.add('T}:');
          } else {
            textRow.add('T}\n');
          }
          cellIndex += 1;
        }
        rowIndex += 1;
      }
    }

    var bodyTextRows = rowText;
    final headerRowText = rowText.isNotEmpty ? rowText[0] : null;
    if (isTruthy(node.hasHeaderOption) && headerRowText != null) {
      result.add(
        '\n${rowHeader[0]!.map((cell) => cell?.join(' ') ?? '').join(' ')}.',
      );
      result.add('\n${headerRowText.join()}');
      result.add('.T&');
      bodyTextRows = rowText.sublist(1);
    }
    result.add(
      '\n${List<String>.filled(rowHeader[0]!.length, 'lt').join(' ')}.\n',
    );
    for (final textRow in bodyTextRows) {
      result.add(textRow!.join());
    }
    result.add('.TE\n.sp');
    return result.join();
  }

  /// Converts the [node] thematic break.
  String convertThematicBreak(Block node) =>
      ".sp\n.ce\n\\l'\\n(.lu*25u/100u\\(ap'";

  /// Converts the [node] unordered list.
  String convertUlist(ListBlock node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }
    for (final item in node.items) {
      final listItem = item as ListItem;
      final listText = _manify(
        listItem.text as String,
        whitespace: _WhitespaceMode.normalize,
      );
      result.add(
        ".sp\n.RS 4\n.ie n \\{\\\n\\h'-04'\\(bu\\h'+03'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP \\(bu 2.3\n.\\}"
        '${listText.isEmpty ? '' : '\n$listText'}',
      );
      if (listItem.hasBlocks) {
        var itemContent = listItem.content() as String;
        if (listText.isEmpty && itemContent.startsWith('.sp\n')) {
          itemContent = itemContent.substring(4);
        }
        result.add(itemContent);
      }
      result.add('.RE');
    }
    return result.join('\n');
  }

  /// Converts the [node] verse block.
  String convertVerse(Block node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }
    String? attributionLine = node.hasAttr('citetitle')
        ? '${_s(node.attr('citetitle'))} '
        : null;
    attributionLine = node.hasAttr('attribution')
        ? '${_s(attributionLine)}\\(em ${_s(node.attr('attribution'))}'
        : null;
    result.add(
      '.sp\n.nf\n${_manify(node.content() as String, whitespace: _WhitespaceMode.preserve)}\n.fi\n.br',
    );
    if (attributionLine != null) {
      result.add('.in +.5i\n.ll -.5i\n$attributionLine\n.in\n.ll');
    }
    return result.join('\n');
  }

  /// Converts the [node] video block.
  String convertVideo(Block node) {
    final startParam = node.hasAttr('start')
        ? '&start=${_s(node.attr('start'))}'
        : '';
    final endParam = node.hasAttr('end') ? '&end=${_s(node.attr('end'))}' : '';
    final result = <String>[];
    result.add(node.hasTitle ? '.sp\n.B ${_manify(node.title!)}\n.br' : '.sp');
    result.add(
      '<${node.mediaUri(node.attr('target') as String)}$startParam$endParam> (video)',
    );
    return result.join('\n');
  }

  /// Converts the [node] inline anchor.
  String? convertInlineAnchor(Inline node) {
    switch (node.type) {
      case 'link':
        final String macro;
        var linkTarget = node.target as String;
        if (linkTarget.startsWith('mailto:')) {
          macro = 'MTO';
          linkTarget = linkTarget.substring(7);
        } else {
          macro = 'URL';
        }
        final rawText = node.text;
        final String text;
        if (rawText == linkTarget) {
          text = '';
        } else {
          text = rawText!.replaceAll('"', '$_escBs(dq');
        }
        if (macro == 'MTO') {
          linkTarget = linkTarget.replaceFirst('@', '$_escBs(at');
        }
        return '${_escBs}c\n$_escFs$macro "$linkTarget" "$text" ';
      case 'xref':
        var text = node.text;
        if (text == null) {
          final refs = _refs ??=
              node.document!.catalog['refs'] as Map<String, Object?>;
          final refid = node.attributes['refid'] as String?;
          Document? top;
          final Object? ref =
              refs[refid] ??
              ((refid == null || refid.isEmpty)
                  ? top = _getRootDocument(node)
                  : null);
          if (ref is AbstractNode) {
            // Guards against recursive xrefs (port of the
            // `@resolving_xref ||= (outer = true)` idiom).
            final outer = !_resolvingXref;
            String? resolved;
            if (outer) {
              _resolvingXref = true;
              try {
                resolved = _xreftextOf(
                  ref,
                  node.attr('xrefstyle', null, true) as String?,
                );
              } finally {
                _resolvingXref = false;
              }
            }
            if (outer && resolved != null) {
              text = resolved;
              if (ref is AbstractBlock &&
                  ref.context == 'section' &&
                  ref.level! < 2 &&
                  text == ref.title) {
                text = _uppercasePcdata(text);
              }
            } else {
              text = top != null ? '[^top]' : '[${_s(refid)}]';
            }
          } else {
            text = '[${_s(refid)}]';
          }
        }
        return text;
      case 'ref':
      case 'bibref':
        // These are anchor points, which shouldn't be visible
        return '';
      default:
        logger.warn('unknown anchor type: :${node.type}');
        return null;
    }
  }

  /// Converts the [node] inline line break.
  String convertInlineBreak(Inline node) => '${_s(node.text)}\n${_escFs}br';

  /// Converts the [node] inline button.
  String convertInlineButton(Inline node) =>
      '<${_escBs}fB>[${_escBs}0${_s(node.text)}${_escBs}0]</${_escBs}fP>';

  /// Converts the [node] inline callout.
  String convertInlineCallout(Inline node) =>
      '<${_escBs}fB>(${_s(node.text)})</${_escBs}fP>';

  /// Converts the [node] inline footnote.
  String? convertInlineFootnote(Inline node) {
    final index = node.attr('index');
    if (isTruthy(index)) return '[${_s(index)}]';
    if (node.type == 'xref') return '[${_s(node.text)}]';
    return null;
  }

  /// Converts the [node] inline image.
  String convertInlineImage(Inline node) => node.hasAttr('link')
      ? '[${_s(node.alt)}] <${_s(node.attr('link'))}>'
      : '[${_s(node.alt)}]';

  /// Converts the [node] inline index term.
  String? convertInlineIndexterm(Inline node) =>
      node.type == 'visible' ? node.text : '';

  /// Converts the [node] inline keyboard shortcut.
  String convertInlineKbd(Inline node) {
    final keys = node.attr('keys') as List<Object?>;
    final rendered = keys.length == 1
        ? _s(keys[0])
        : keys.map(_s).join('${_escBs}0+${_escBs}0');
    return '<${_escBs}f(CR>$rendered</${_escBs}fP>';
  }

  /// Converts the [node] inline menu reference.
  String convertInlineMenu(Inline node) {
    final caret = '${_escBs}0$_escBs(fc${_escBs}0';
    final menu = _s(node.attr('menu'));
    final submenus = node.attr('submenus') as List<Object?>;
    if (submenus.isNotEmpty) {
      final submenuPath = submenus
          .map((item) => '<${_escBs}fI>${_s(item)}</${_escBs}fP>')
          .join(caret);
      return '<${_escBs}fI>$menu</${_escBs}fP>$caret$submenuPath$caret<${_escBs}fI>${_s(node.attr('menuitem'))}</${_escBs}fP>';
    }
    final menuitem = node.attr('menuitem');
    if (isTruthy(menuitem)) {
      return '<${_escBs}fI>$menu$caret${_s(menuitem)}</${_escBs}fP>';
    }
    return '<${_escBs}fI>$menu</${_escBs}fP>';
  }

  /// Converts the [node] inline quoted text.
  ///
  /// NOTE use fake XML elements to prevent creating artificial word
  /// boundaries
  String? convertInlineQuoted(Inline node) {
    switch (node.type) {
      case 'emphasis':
        return '<${_escBs}fI>${_s(node.text)}</${_escBs}fP>';
      case 'strong':
        return '<${_escBs}fB>${_s(node.text)}</${_escBs}fP>';
      case 'monospaced':
        return '<${_escBs}f(CR>${_s(node.text)}</${_escBs}fP>';
      case 'single':
        return '<$_escBs(oq>${_s(node.text)}</$_escBs(cq>';
      case 'double':
        return '<$_escBs(lq>${_s(node.text)}</$_escBs(rq>';
      default:
        return node.text;
    }
  }

  /// Writes stub (`.so`) pages for the alternate [mannames].
  ///
  /// The first name is the primary page (already written to [target]); every
  /// remaining name gets a stub page pointing at it. Does nothing unless
  /// [mannames] holds at least two names. Mirrors Ruby, which drops the
  /// primary name from the passed list (`Array#shift`).
  static void writeAlternatePages(
    List<Object?>? mannames,
    Object? manvolnum,
    String target,
  ) {
    if (mannames == null || mannames.length < 2) return;
    mannames.removeAt(0);
    final manvolext = '.${_s(manvolnum)}';
    final (dir, basename) = _splitPath(target);
    for (final manname in mannames) {
      File(_joinPath(dir, '${_s(manname)}$manvolext'))
          .writeAsStringSync('.so $basename');
    }
  }

  /// Appends the footnotes section for [node] to [result], unless suppressed.
  void _appendFootnotes(List<String> result, Document node) {
    if (!node.hasFootnotes || node.hasAttr('nofootnotes')) return;
    result.add('.SH "NOTES"');
    for (final fn in node.footnotes) {
      result.add('.IP [${_s(fn.index)}]');
      // NOTE restore newline in escaped macro that gets removed by
      // normalize_text in substitutor
      final rawText = fn.text as String;
      if (rawText.contains('$_esc\\c $_esc.')) {
        result.add(
          chompSuffix(
            _manify(
              '${rawText.replaceAllMapped(_malformedEscapedMacroRx, (match) => '${match.group(1)}\n${match.group(2)}')} ',
              whitespace: _WhitespaceMode.normalize,
            ),
            ' ',
          ),
        );
      } else {
        result.add(_manify(rawText, whitespace: _WhitespaceMode.normalize));
      }
    }
  }

  /// Converts HTML entity references back to their original form, escapes
  /// special man characters and strips trailing whitespace.
  ///
  /// It's crucial that text only ever pass through manify once.
  ///
  /// [whitespace] selects how whitespace is handled: [collapse][_WhitespaceMode.collapse]
  /// collapses adjacent whitespace to a single space (default),
  /// [normalize][_WhitespaceMode.normalize] normalizes whitespace (removes
  /// spaces around newlines), [preserve][_WhitespaceMode.preserve] preserves
  /// spaces (only expanding tabs). When [appendNewline] is set, a newline is
  /// appended to the result.
  String _manify(
    String str, {
    _WhitespaceMode whitespace = _WhitespaceMode.collapse,
    bool appendNewline = false,
  }) {
    switch (whitespace) {
      case _WhitespaceMode.preserve:
        // NOTE Dart reports the zero-width `(^)?` group as non-participating
        // even at a line start (verified by probe), so Ruby's `$1 ? ...`
        // test becomes an explicit line-start check (exactly equivalent:
        // the run matches either way; only the branch differs).
        final expanded = str.replaceAll(tab, _et);
        str = expanded.replaceAllMapped(_preserveSpacesRx, (match) {
          final start = match.start;
          if (start == 0 || expanded[start - 1] == '\n') {
            return match.group(0)!;
          }
          return '$_escBs&${match.group(0)}';
        });
      case _WhitespaceMode.normalize:
        str = str.replaceAll(_wrappedIndentRx, '\n');
      case _WhitespaceMode.collapse:
        str = transliterateSqueeze(str, _whitespace, ' ');
    }
    // literal backslash (not a troff escape sequence)
    str = str.replaceAllMapped(
      _literalBackslashRx,
      (match) => match.group(1) != null ? match.group(0)! : r'\(rs',
    );
    // horizontal ellipsis (emulate appearance)
    str = str.replaceAll(_ellipsisCharRefRx, r'.\|.\|.');
    // leading . is used in troff for macro call or other formatting;
    // replace with \&.
    str = str.replaceAll(_leadingPeriodRx, r'\&.');
    // drop orphaned \c escape lines, unescape troff macro, quote adjacent
    // character, isolate macro line
    str = str.replaceAllMapped(_escapedMacroRx, (match) {
      final rest = lstrip(match.group(3)!);
      if (rest.isEmpty) {
        return '.${match.group(1)}"${match.group(2)}"';
      }
      return '.${match.group(1)}"${match.group(2)!.rstrip()}"\n$rest';
    });
    str = str.replaceAll('-', r'\-');
    str = str.replaceAll('&lt;', '<');
    str = str.replaceAll('&gt;', '>');
    // plus sign; alternately could use (pl
    str = str.replaceAll('&#43;', '+');
    // non-breaking space
    str = str.replaceAll('&#160;', r'\~');
    // copyright sign
    str = str.replaceAll('&#169;', r'\(co');
    // registered sign
    str = str.replaceAll('&#174;', r'\(rg');
    // trademark sign
    str = str.replaceAll('&#8482;', r'\(tm');
    // degree sign
    str = str.replaceAll('&#176;', r'\(de');
    // thin space
    str = str.replaceAll('&#8201;', ' ');
    // en dash
    str = str.replaceAll('&#8211;', r'\(en');
    // em dash
    str = str.replaceAll(_emDashCharRefRx, r'\(em');
    // left single quotation mark
    str = str.replaceAll('&#8216;', r'\(oq');
    // right single quotation mark
    str = str.replaceAll('&#8217;', r'\(cq');
    // left double quotation mark
    str = str.replaceAll('&#8220;', r'\(lq');
    // right double quotation mark
    str = str.replaceAll('&#8221;', r'\(rq');
    // leftwards arrow
    str = str.replaceAll('&#8592;', r'\(<-');
    // rightwards arrow
    str = str.replaceAll('&#8594;', r'\(->');
    // leftwards double arrow
    str = str.replaceAll('&#8656;', r'\(lA');
    // rightwards double arrow
    str = str.replaceAll('&#8658;', r'\(rA');
    // zero width space
    str = str.replaceAll('&#8203;', r'\:');
    // literal ampersand (NOTE must take place after any other replacement
    // that includes &)
    str = str.replaceAll('&amp;', '&');
    // apostrophe / neutral single quote
    str = str.replaceAll("'", r'\*(Aq');
    // mock boundary (NOTE Dart's replaceAll takes the replacement
    // literally — `$1` would not interpolate — so this uses
    // replaceAllMapped; verified by probe)
    str = str.replaceAllMapped(_mockMacroRx, (match) => match.group(1)!);
    // unescape troff backslash (NOTE update if more escapes are added)
    str = str.replaceAll(_escBs, r'\');
    // unescape full stop in troff commands (NOTE must take place after
    // the leading-period replacement)
    str = str.replaceAll(_escFs, '.');
    // strip trailing space
    str = str.rstrip();
    return appendNewline ? '$str\n' : str;
  }

  /// Uppercases the PCDATA in [string], leaving markup untouched.
  String _uppercasePcdata(String string) {
    if (!_xmlMarkupRx.hasMatch(string)) return string.toUpperCase();
    return string.replaceAllMapped(_pcdataFilterRx, (match) {
      final pcdata = match.group(2);
      return pcdata != null ? pcdata.toUpperCase() : match.group(1)!;
    });
  }

  /// Returns the converted content of [node], enclosing simple content in
  /// a `.sp` paragraph.
  String _encloseContent(Block node) {
    if (node.contentModel == 'compound') return _s(node.content());
    return '.sp\n${_manify(node.content() as String, whitespace: _WhitespaceMode.normalize)}';
  }

  /// Returns the root document of [node]'s document tree.
  Document _getRootDocument(AbstractNode node) {
    var doc = node.document! as Document;
    while (doc.nested()) {
      doc = doc.parentDocument!;
    }
    return doc;
  }

  /// Returns the cross-reference text for [ref], which is either a block
  /// or an inline node (`xreftext` lives on both classes).
  String? _xreftextOf(Object? ref, String? xrefstyle) {
    if (ref is AbstractBlock) {
      return ref.xreftext(xrefstyle);
    }
    if (ref is Inline) {
      return ref.xreftext(xrefstyle);
    }
    return null;
  }

  /// Returns the header cells of row [index], creating rows up to it.
  ///
  /// Mirrors Ruby's auto-extending `Array#[]=` (`row_header[i] ||= []`).
  static List<List<String>?> _rowHeaderAt(
    List<List<List<String>?>?> rows,
    int index,
  ) {
    while (rows.length <= index) {
      rows.add(null);
    }
    return rows[index] ??= <List<String>?>[];
  }

  /// Returns the text cells of row [index], creating rows up to it.
  ///
  /// Mirrors Ruby's auto-extending `Array#[]=` (`row_text[i] ||= []`).
  static List<String> _rowTextAt(List<List<String>?> rows, int index) {
    while (rows.length <= index) {
      rows.add(null);
    }
    return rows[index] ??= <String>[];
  }

  /// Returns the header entry of cell [index], creating cells up to it.
  ///
  /// Mirrors Ruby's auto-extending `Array#[]=` (`row[i] ||= []`).
  static List<String> _headerCellAt(List<List<String>?> row, int index) {
    while (row.length <= index) {
      row.add(null);
    }
    return row[index] ??= <String>[];
  }

  /// Splits [target] into its directory and basename (port of
  /// `File.split` for `/`-separated paths).
  static (String, String) _splitPath(String target) {
    final idx = target.lastIndexOf('/');
    if (idx == -1) return ('.', target);
    if (idx == 0) return ('/', target.substring(1));
    return (target.substring(0, idx), target.substring(idx + 1));
  }

  /// Joins [dir] and [basename] with `/` (port of `File.join` for two
  /// path segments).
  static String _joinPath(String dir, String basename) =>
      dir.endsWith('/') ? '$dir$basename' : '$dir/$basename';
}
