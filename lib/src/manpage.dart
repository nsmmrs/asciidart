/// Manpage converter: generates man page (groff) output from a parsed document.
///
/// Port of `lib/asciidoctor/converter/manpage.rb` (complete). Per
/// `adr/0001-dart-rewrite-goals.md` (D4) every template method produces
/// output byte-identical to Asciidoctor 2.0.26, including whitespace.
///
/// ## Framework integration
///
/// Each transform is a handler registered with [ConverterBase.handle] (see
/// `converter.dart`); [ManpageConverter.convert] itself is inherited from
/// [ConverterBase], which warns and returns `null` for unregistered
/// transforms. The converter registers itself explicitly with
/// [Converter.register].
///
/// The converter only consumes already-substituted strings (`content`,
/// `title`, `text`, `alt`, `captioned_title`, `xreftext`).
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

/// Renders [value] for interpolation into output: `toString`, except
/// `null` renders as the empty string instead of `'null'`.
String _s(String? value) => value ?? '';

/// Whitespace characters collapsed by `tr_s` (port of `WHITESPACE`).
const String _whitespace = '\n\t ';

/// Tab expansion for preserved whitespace (port of `ET`, `' ' * 8`).
const String _et = '        ';

/// Troff leader marker (the single ESC character).
final String _esc = String.fromCharCode(27);

/// Escaped backslash: indicates a troff formatting sequence (`ESC_BS`).
final String _escBs = '$_esc\\';

/// Escaped full stop: indicates a troff macro (`ESC_FS`).
final String _escFs = '$_esc.';

/// Matches a literal backslash (port of `LiteralBackslashRx`; `\A` is `^`
/// without `multiLine` per `PORTING-REGEXP.md` B2).
final RegExp _literalBackslashRx = RegExp('^\\\\|($_esc)?\\\\');

/// Whether a line of [text] starts with [char], where a line starts
/// wherever a `multiLine` `^` matches: at the start of [text] and after
/// each `\n`, `\r`, `\u2028` and `\u2029`.
bool _hasLineStartingWith(String text, String char) {
  for (var i = text.indexOf(char); i >= 0; i = text.indexOf(char, i + 1)) {
    if (i == 0) return true;
    final previous = text.codeUnitAt(i - 1);
    if (previous == 0x0A ||
        previous == 0x0D ||
        previous == 0x2028 ||
        previous == 0x2029) {
      return true;
    }
  }
  return false;
}

/// Troff replacements for the character references `manify` rewrites, in
/// Asciidoctor's order. `&#8212;` (em dash) is handled in [_replaceCharRefs]
/// because it absorbs a trailing `&#8203;` (port of `EmDashCharRefRx`).
const Map<String, String> _charRefReplacements = {
  '&lt;': '<',
  '&gt;': '>',
  // plus sign; alternately could use (pl
  '&#43;': '+',
  // non-breaking space
  '&#160;': r'\~',
  // copyright sign
  '&#169;': r'\(co',
  // registered sign
  '&#174;': r'\(rg',
  // trademark sign
  '&#8482;': r'\(tm',
  // degree sign
  '&#176;': r'\(de',
  // thin space
  '&#8201;': ' ',
  // en dash
  '&#8211;': r'\(en',
  // em dash
  '&#8212;': r'\(em',
  // left single quotation mark
  '&#8216;': r'\(oq',
  // right single quotation mark
  '&#8217;': r'\(cq',
  // left double quotation mark
  '&#8220;': r'\(lq',
  // right double quotation mark
  '&#8221;': r'\(rq',
  // leftwards arrow
  '&#8592;': r'\(<-',
  // rightwards arrow
  '&#8594;': r'\(->',
  // leftwards double arrow
  '&#8656;': r'\(lA',
  // rightwards double arrow
  '&#8658;': r'\(rA',
  // zero width space
  '&#8203;': r'\:',
  // literal ampersand
  '&amp;': '&',
};

/// The longest key of [_charRefReplacements].
const int _maxCharRefLength = 7;

/// Replaces the character references in [text] per [_charRefReplacements]
/// in a single left-to-right pass.
///
/// Equivalent to replacing each reference in turn (ending with `&amp;`): every
/// reference starts with `&`, no replacement contains `&` or starts with a
/// character that could continue a reference, and no reference is a prefix of
/// another, so no replacement creates or hides a later match.
String _replaceCharRefs(String text) {
  var amp = text.indexOf('&');
  if (amp < 0) return text;
  final buffer = StringBuffer();
  var copied = 0;
  while (amp >= 0) {
    final semi = text.indexOf(';', amp + 1);
    if (semi < 0) break;
    var end = semi + 1;
    final replacement = end - amp <= _maxCharRefLength
        ? _charRefReplacements[text.substring(amp, end)]
        : null;
    if (replacement == null) {
      amp = text.indexOf('&', amp + 1);
      continue;
    }
    if (replacement == r'\(em' && text.startsWith('&#8203;', end)) {
      end += '&#8203;'.length;
    }
    buffer
      ..write(text.substring(copied, amp))
      ..write(replacement);
    copied = end;
    amp = text.indexOf('&', end);
  }
  if (copied == 0) return text;
  buffer.write(text.substring(copied));
  return buffer.toString();
}

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

/// How `_manify` handles whitespace (port of the `:whitespace` option).
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
/// method corresponds to Asciidoctor's `convert_*` method of the same name
/// and is registered with [handle] below (see the library docs).
class ManpageConverter extends ConverterBase {
  /// Creates a converter for [backend] with constructor options [opts].
  new(super.backend, [super.opts]) {
    backendTraits = BackendTraits(
      basebackend: 'manpage',
      filetype: 'man',
      outfilesuffix: '.man',
      supportsTemplates: true,
    );
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
  Map<String, AbstractNode>? _refs;

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
    final mantitle = node
        .attr('mantitle')!
        .replaceAll(invalidSectionIdCharsRx, '');
    final manvolnum = node.attr('manvolnum', '1');
    final manname = node.attr('manname', mantitle)!;
    final manmanual = node.attr('manmanual');
    final mansource = node.attr('mansource');
    final docdate = node.hasAttr('reproducible') ? null : node.attr('docdate');
    // NOTE the first line enables the table (tbl) preprocessor, necessary
    // for non-Linux systems
    final result = <String>[
      '\'\\" t\n.\\"     Title: $mantitle\n.\\"    Author: ${node.hasAttr('authors') ? _s(node.attr('authors')) : '[see the "AUTHOR(S)" section]'}\n.\\" Generator: Asciidoctor ${_s(node.attr('asciidoctor-version'))}',
    ];
    if (docdate != null) {
      result.add('.\\"      Date: ${_s(docdate)}');
    }
    // TODO add document-level setting to disable capitalization of manname
    // define portability settings
    // see http://bugs.debian.org/507673
    // see http://lists.gnu.org/archive/html/groff/2009-02/msg00013.html
    // set sentence_space_size to 0 to prevent extra space between sentences
    // separated by a newline
    // the alternative is to add \& at the end of the line
    // disable hyphenation
    // disable justification (adjust text to left margin only)
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
    result
      ..add(
        '.\\"    Manual: ${manmanual != null ? transliterateSqueeze(manmanual, _whitespace, ' ') : r'\ \&'}\n'
        '.\\"    Source: ${mansource != null ? transliterateSqueeze(mansource, _whitespace, ' ') : r'\ \&'}\n'
        '.\\"  Language: English\n'
        r'.\"',
      )
      ..add(
        '.TH "${_manify(manname.toUpperCase())}" '
        '"${_s(manvolnum)}" "${_s(docdate)}" '
        '"${mansource != null ? _manify(mansource) : r'\ \&'}" '
        '"${manmanual != null ? _manify(manmanual) : r'\ \&'}"',
      )
      ..add(r'.ie \n(.g .ds Aq \(aq')
      ..add(".el       .ds Aq '")
      ..add(r'.ss \n[.ss] 0')
      ..add('.nh')
      ..add('.ad l')
      ..add(
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
      )
      ..add('.  LINKSTYLE ${_s(node.attr('man-linkstyle', 'blue R < >'))}')
      ..add(r'.\}');

    if (!node.noheader) {
      if (node.hasAttr('manpurpose')) {
        final mannames = node.mannames ?? <String>[manname];
        result.add(
          '.SH '
          '"${node.attr('manname-title', 'NAME')!.toUpperCase()}"\n'
          '${mannames.map((n) => _manify(n).replaceAll(r'\-', '-')).join(', ')} \\- ${_manify(node.attr('manpurpose')!, whitespace: _WhitespaceMode.normalize)}',
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
    final label = _s(node.attr('textlabel'));
    final titleSuffix = node.hasTitle ? '\\fP: ${_manify(node.title!)}' : '';
    return '.if n .sp\n'
        '.RS 4\n'
        '.it 1 an-trap\n'
        '.nr an-no-space-flag 1\n'
        '.nr an-break-flag 1\n'
        '.br\n'
        '.ps +1\n'
        '.B $label$titleSuffix\n'
        '.ps -1\n'
        '.br\n'
        '${_encloseContent(node)}\n'
        '.sp .5v\n'
        '.RE';
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
      final listItem = item;
      result
        ..add("\\fB(${num += 1})\\fP\\h'-2n':T{")
        ..add(_manify(listItem.text!, whitespace: _WhitespaceMode.normalize));
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
  // TODO implement horizontal (if it makes sense)
  String convertDlist(ListBlock node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }
    var counter = 0;
    for (final DlistEntry(:terms, description: dd) in node.entries) {
      counter += 1;
      if (node.style == 'qanda') {
        result.add(
          '.sp\n$counter. '
          '${_manify(terms.map((dt) => _s(dt.text)).join(' '))}\n.RS 4',
        );
      } else {
        final termText = _manify(
          terms.map((dt) => _s(dt.text)).join(', '),
          whitespace: _WhitespaceMode.normalize,
        );
        result.add('.sp\n$termText\n.RS 4');
      }
      if (dd != null) {
        if (dd.hasText) {
          result.add(_manify(dd.text!, whitespace: _WhitespaceMode.normalize));
        }
        if (dd.hasBlocks) {
          result.add(dd.content() ?? '');
        }
      }
      result.add('.RE');
    }
    return result.join('\n');
  }

  /// Converts the [node] example block.
  String convertExample(Block node) {
    final result = (<String>[])
      ..add(
        node.hasTitle
            ? '.sp\n.B ${_manify(node.captionedTitle())}\n.br'
            : '.sp',
      )
      ..add('.RS 4\n${_encloseContent(node)}\n.RE');
    return result.join('\n');
  }

  /// Converts the [node] floating title.
  String convertFloatingTitle(Block node) => '.SS "${_manify(node.title!)}"';

  /// Converts the [node] image block.
  String convertImage(Block node) {
    final result = (<String>[])
      ..add(
        node.hasTitle
            ? '.sp\n.B ${_manify(node.captionedTitle())}\n.br'
            : '.sp',
      )
      ..add('[${_manify(node.alt)}]');
    return result.join('\n');
  }

  /// Converts the [node] listing block.
  String convertListing(Block node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.captionedTitle())}\n.br');
    }
    result.add(
      '.sp\n.if n .RS 4\n.nf\n.fam '
      'C\n'
      '${_manify(node.content()!, whitespace: _WhitespaceMode.preserve)}\n.fam'
      '\n.fi\n.if n .RE',
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
      '.sp\n.if n .RS 4\n.nf\n.fam '
      'C\n'
      '${_manify(node.content()!, whitespace: _WhitespaceMode.preserve)}\n.fam'
      '\n.fi\n.if n .RE',
    );
    return result.join('\n');
  }

  /// Converts the [node] sidebar block.
  String convertSidebar(Block node) {
    final result = (<String>[])
      ..add(node.hasTitle ? '.sp\n.B ${_manify(node.title!)}\n.br' : '.sp')
      ..add('.RS 4\n${_encloseContent(node)}\n.RE');
    return result.join('\n');
  }

  /// Converts the [node] ordered list.
  String convertOlist(ListBlock node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.B ${_manify(node.title!)}\n.br');
    }

    final start = parseLeadingInt(node.attr('start', '1'));
    var idx = 0;
    for (final item in node.items) {
      final listItem = item;
      final numeral = idx + start;
      idx += 1;
      final listText = _manify(
        listItem.text!,
        whitespace: _WhitespaceMode.normalize,
      );
      result.add(
        '.sp\n.RS 4\n.ie n \\{\\\n\\h\'-04\' $numeral.\\h\'+01\'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP " $numeral." 4.2\n.\\}'
        '\n$listText',
      );
      if (listItem.hasBlocks) {
        result.add(listItem.content() ?? '');
      }
      result.add('.RE');
    }
    return result.join('\n');
  }

  /// Converts the [node] open block.
  String? convertOpen(Block node) {
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
      return '.sp\n.B '
          '${_manify(node.title!)}\n.br\n'
          '${_manify(node.content()!, whitespace: _WhitespaceMode.normalize)}';
    }
    return '.sp\n'
        '${_manify(node.content()!, whitespace: _WhitespaceMode.normalize)}';
  }

  /// Converts the [node] quote block.
  String convertQuote(Block node) {
    final result = <String>[];
    if (node.hasTitle) {
      result.add('.sp\n.RS 3\n.B ${_manify(node.title!)}\n.br\n.RE');
    }
    var attributionLine = node.hasAttr('citetitle')
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
    final result = (<String>[])
      ..add(node.hasTitle ? '.sp\n.B ${_manify(node.title!)}\n.br' : '.sp');
    final delimiters = blockMathDelimiters[node.style]!;
    final open = delimiters[0];
    final close = delimiters[1];
    var equation = node.content()!;
    if (equation.startsWith(open) && equation.endsWith(close)) {
      equation = equation.substring(
        open.length,
        equation.length - close.length,
      );
    }
    result.add(
      '${_manify(equation, whitespace: _WhitespaceMode.preserve)} '
      '(${_s(node.style)})',
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
        '.sp\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag '
        '1\n.br\n.B ${_manify(node.captionedTitle())}\n',
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
            textRow.add('T{\n.sp\nT}:');
          }
          textRow.add('T{\n.sp\n');
          final halignValue = cell.attr('halign', 'left')!;
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
                final text = _manify(
                  cell.text,
                  whitespace: _WhitespaceMode.preserve,
                );
                cellContent = '.nf\n$text\n.fi';
              default:
                cellContent = cell.paragraphs
                    .map(
                      (p) => _manify(p, whitespace: _WhitespaceMode.normalize),
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
              '${_manify(cell.text, whitespace: _WhitespaceMode.normalize)}\n',
            );
          }
          final colspan = cell.colspan ?? 1;
          if (colspan > 1) {
            for (var i = 0; i < colspan - 1; i++) {
              if (headerRow.isEmpty || headerRow[cellIndex]!.isEmpty) {
                headerRow[cellIndex + i]!.add('st');
              } else {
                _headerCellAt(headerRow, cellIndex + 1 + i).add('st');
              }
            }
          }
          final rowspan = cell.rowspan ?? 1;
          if (rowspan > 1) {
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
    if ((node.header == TableHeader.explicit ||
            node.header == TableHeader.implicit) &&
        headerRowText != null) {
      result
        ..add(
          '\n${rowHeader[0]!.map((cell) => cell?.join(' ') ?? '').join(' ')}.',
        )
        ..add('\n${headerRowText.join()}')
        ..add('.T&');
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
      final listItem = item;
      final listText = _manify(
        listItem.text!,
        whitespace: _WhitespaceMode.normalize,
      );
      result.add(
        ".sp\n.RS 4\n.ie n \\{\\\n\\h'-04'\\(bu\\h'+03'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP \\(bu 2.3\n.\\}"
        '\n$listText',
      );
      if (listItem.hasBlocks) {
        result.add(listItem.content() ?? '');
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
    var attributionLine = node.hasAttr('citetitle')
        ? '${_s(node.attr('citetitle'))} '
        : null;
    attributionLine = node.hasAttr('attribution')
        ? '${_s(attributionLine)}\\(em ${_s(node.attr('attribution'))}'
        : null;
    result.add(
      '.sp\n.nf\n'
      '${_manify(node.content()!, whitespace: _WhitespaceMode.preserve)}\n'
      '.fi\n.br',
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
    final titleLine = node.hasTitle
        ? '.sp\n.B ${_manify(node.title!)}\n.br'
        : '.sp';
    final target = node.mediaUri(node.attr('target')!);
    return '$titleLine\n<$target$startParam$endParam> (video)';
  }

  /// Converts the [node] inline anchor.
  String? convertInlineAnchor(Inline node) {
    switch (node.type) {
      case 'link':
        final String macro;
        var linkTarget = node.target!;
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
          final refs = _refs ??= node.document!.catalog.refs;
          final refid = node.attributes['refid'];
          Document? top;
          final ref =
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
                  node.attr('xrefstyle', null, 'xrefstyle'),
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
    if (index != null) return '[$index]';
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
    final keys = node.keys!;
    final rendered = keys.length == 1
        ? keys[0]
        : keys.join('${_escBs}0+${_escBs}0');
    return '<${_escBs}f(CR>$rendered</${_escBs}fP>';
  }

  /// Converts the [node] inline menu reference.
  String convertInlineMenu(Inline node) {
    final caret = '${_escBs}0$_escBs(fc${_escBs}0';
    final menu = _s(node.attr('menu'));
    final submenus = node.submenus!;
    if (submenus.isNotEmpty) {
      final submenuPath = submenus
          .map((item) => '<${_escBs}fI>$item</${_escBs}fP>')
          .join(caret);
      return '<${_escBs}fI>$menu</${_escBs}fP>$caret$submenuPath$caret<${_escBs}fI>${_s(node.attr('menuitem'))}</${_escBs}fP>';
    }
    final menuitem = node.attr('menuitem');
    if (menuitem != null) {
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
  /// [mannames] holds at least two names.
  static void writeAlternatePages(
    List<String>? mannames,
    String? manvolnum,
    String target,
  ) {
    if (mannames == null || mannames.length < 2) return;
    final manvolext = '.${_s(manvolnum)}';
    final (dir, basename) = _splitPath(target);
    for (final manname in mannames.skip(1)) {
      File(_joinPath(dir, '$manname$manvolext'))
          .writeAsStringSync('.so $basename');
    }
  }

  /// Appends the footnotes section for [node] to [result], unless suppressed.
  void _appendFootnotes(List<String> result, Document node) {
    if (!node.hasFootnotes || node.hasAttr('nofootnotes')) return;
    result.add('.SH "NOTES"');
    for (final fn in node.footnotes) {
      result.add('.IP [${fn.index}]');
      // NOTE restore newline in escaped macro that gets removed by
      // normalize_text in substitutor
      final rawText = fn.text;
      if (rawText.contains('$_esc\\c $_esc.')) {
        final restored = rawText.replaceAllMapped(
          _malformedEscapedMacroRx,
          (match) => '${match.group(1)}\n${match.group(2)}',
        );
        result.add(
          removeSuffix(
            _manify('$restored ', whitespace: _WhitespaceMode.normalize),
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
  /// [whitespace] selects how whitespace is handled:
  /// [collapse][_WhitespaceMode.collapse] collapses adjacent whitespace to
  /// a single space (default),
  /// [normalize][_WhitespaceMode.normalize] normalizes whitespace (removes
  /// spaces around newlines), [preserve][_WhitespaceMode.preserve] preserves
  /// spaces (only expanding tabs). When [appendNewline] is set, a newline is
  /// appended to the result.
  String _manify(
    String str, {
    _WhitespaceMode whitespace = _WhitespaceMode.collapse,
    bool appendNewline = false,
  }) {
    var result = str;
    switch (whitespace) {
      case _WhitespaceMode.preserve:
        // NOTE Dart reports the zero-width `(^)?` group as non-participating
        // even at a line start (verified by probe), so the group test
        // becomes an explicit line-start check (exactly equivalent:
        // the run matches either way; only the branch differs).
        final expanded = result.replaceAll(tab, _et);
        result = !expanded.contains('  ')
            ? expanded
            : expanded.replaceAllMapped(_preserveSpacesRx, (match) {
                final start = match.start;
                if (start == 0 || expanded[start - 1] == '\n') {
                  return match.group(0)!;
                }
                return '$_escBs&${match.group(0)}';
              });
      case _WhitespaceMode.normalize:
        result = result.replaceAll(_wrappedIndentRx, '\n');
      case _WhitespaceMode.collapse:
        result = transliterateSqueeze(result, _whitespace, ' ');
    }
    // NOTE each regex pass below is skipped when the text lacks a literal
    // every match contains; the result is identical either way.
    // literal backslash (not a troff escape sequence)
    if (result.contains(r'\')) {
      result = result.replaceAllMapped(
        _literalBackslashRx,
        (match) => match.group(1) != null ? match.group(0)! : r'\(rs',
      );
    }
    // horizontal ellipsis (emulate appearance)
    if (result.contains('&#8230;')) {
      result = result.replaceAll(_ellipsisCharRefRx, r'.\|.\|.');
    }
    // leading . is used in troff for macro call or other formatting;
    // replace with \&.
    if (_hasLineStartingWith(result, '.')) {
      result = result.replaceAll(_leadingPeriodRx, r'\&.');
    }
    // drop orphaned \c escape lines, unescape troff macro, quote adjacent
    // character, isolate macro line
    if (result.contains(_escFs)) {
      result = result.replaceAllMapped(_escapedMacroRx, (match) {
        final rest = trimLeftAscii(match.group(3)!);
        if (rest.isEmpty) {
          return '.${match.group(1)}"${match.group(2)}"';
        }
        return '.${match.group(1)}"${match.group(2)!.trimRightAscii()}"\n$rest';
      });
    }
    result = result.replaceAll('-', r'\-');
    // character references (named, numeric and the literal ampersand)
    result = _replaceCharRefs(result);
    // apostrophe / neutral single quote
    result = result.replaceAll("'", r'\*(Aq');
    // mock boundary (NOTE Dart's replaceAll takes the replacement
    // literally — `$1` would not interpolate — so this uses
    // replaceAllMapped; verified by probe)
    if (result.contains(_escBs)) {
      result = result.replaceAllMapped(
        _mockMacroRx,
        (match) => match.group(1)!,
      );
    }
    // unescape troff backslash (NOTE update if more escapes are added)
    result = result.replaceAll(_escBs, r'\');
    // unescape full stop in troff commands (NOTE must take place after
    // the leading-period replacement)
    result = result.replaceAll(_escFs, '.');
    // strip trailing space
    result = result.trimRightAscii();
    return appendNewline ? '$result\n' : result;
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
    return '.sp\n'
        '${_manify(node.content()!, whitespace: _WhitespaceMode.normalize)}';
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
  String? _xreftextOf(AbstractNode ref, String? xrefstyle) => switch (ref) {
    AbstractBlock() => ref.xreftext(xrefstyle),
    Inline() => ref.xreftext(xrefstyle),
    _ => null,
  };

  /// Returns the header cells of row [index], creating rows up to it.
  ///
  /// Grows [rows] as needed.
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
  /// Grows [rows] as needed.
  static List<String> _rowTextAt(List<List<String>?> rows, int index) {
    while (rows.length <= index) {
      rows.add(null);
    }
    return rows[index] ??= <String>[];
  }

  /// Returns the header entry of cell [index], creating cells up to it.
  ///
  /// Grows [row] as needed.
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
