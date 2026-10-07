/// DocBook 5 converter: generates DocBook 5 output from a parsed document.
///
/// Port of `lib/asciidoctor/converter/docbook5.rb`. Per
/// `adr/0001-dart-rewrite-goals.md` (D4) every template method produces
/// output byte-identical to Asciidoctor 2.0.26, including whitespace.
///
/// ## Framework integration
///
/// [BuiltInConverter] dispatches each node to `convertBlock` or
/// `convertInline` below, by its kind; a kind with no conversion here (list
/// items, table cells) warns and produces nothing. The
/// converter registers itself explicitly with `Converter.registerFor`.
///
/// Notes:
///
/// * Role checks use [AbstractNode.includesRole] (membership);
///   [AbstractNode.hasRole] tests equality.
/// * AsciiMath: there is no AsciiMath-to-MathML converter here, so stem and
///   quoted `asciimath` nodes always produce the output Asciidoctor gives
///   when its optional `asciimath` gem is not installed.
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/attribute_list.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/list.dart';
import 'package:asciidart/src/ruby_semantics.dart';
import 'package:asciidart/src/rx.dart';
import 'package:asciidart/src/section.dart';
import 'package:asciidart/src/table.dart';
import 'package:asciidart/src/xml_balance.dart';

/// Renders [value] for interpolation into output: `toString`, except
/// `null` renders as the empty string instead of `'null'`.
String _s(String? value) => value ?? '';

/// Splits a copyright attribute into holder and year (port of `CopyrightRx`;
/// `CC_ANY` is [ccAny], `multiLine` follows `PORTING-REGEXP.md` B9).
///
/// `\d` is spelled `[0-9]`: with `unicode: true`, `\d` would also match
/// non-ASCII decimal digits.
final RegExp _copyrightRx = RegExp(
  '^($ccAny+?)(?: ((?:[0-9]{4}-)?[0-9]{4}))?\$',
  multiLine: true,
);

/// Matches an image-macro reference in a cover-image attribute (port of
/// `ImageMacroRx`; `CC_ANY` is [ccAny], `multiLine` per B9).
final RegExp _imageMacroRx = RegExp(
  '^image::?([^ \\t\\n\\v\\f\\r]|[^ \\t\\n\\v\\f\\r]$ccAny*?[^ \\t\\n\\v\\f\\r])\\[($ccAny+)?\\]\$',
  multiLine: true,
);

/// Section tag names for the manpage doctype (port of
/// `MANPAGE_SECTION_TAGS`).
const Map<String, String> _manpageSectionTags = <String, String>{
  'section': 'refsection',
  'synopsis': 'refsynopsisdiv',
};

/// Processing-instruction names carrying the table width (port of
/// `TABLE_PI_NAMES`).
const List<String> _tablePiNames = <String>['dbhtml', 'dbfo', 'dblatex'];

/// Description-list tags by list style (port of `DLIST_TAGS`).
///
/// The `'glossary'` style has no list tag. Styles missing from this map use
/// [_defaultDlistTags] (the map default).
const Map<String, Map<String, String?>> _dlistTags =
    <String, Map<String, String?>>{
      'qanda': <String, String?>{
        'list': 'qandaset',
        'entry': 'qandaentry',
        'label': 'question',
        'term': 'simpara',
        'item': 'answer',
      },
      'glossary': <String, String?>{
        'list': null,
        'entry': 'glossentry',
        'term': 'glossterm',
        'item': 'glossdef',
      },
    };

/// Default description-list tags (the variablelist; the `DLIST_TAGS`
/// default).
const Map<String, String?> _defaultDlistTags = <String, String?>{
  'list': 'variablelist',
  'entry': 'varlistentry',
  'term': 'term',
  'item': 'listitem',
};

/// Quote tags by quoted-text type (port of `QUOTE_TAGS`).
///
/// Each entry holds the opening tag, the closing tag and whether the tag
/// supports wrapping the role in a phrase element. Lookups miss with
/// [_defaultQuoteTags] (the map default).
const Map<String, (String, String, bool)> _quoteTags =
    <String, (String, String, bool)>{
      'monospaced': ('<literal>', '</literal>', false),
      'emphasis': ('<emphasis>', '</emphasis>', true),
      'strong': ('<emphasis role="strong">', '</emphasis>', true),
      'double': ('<quote>', '</quote>', true),
      'single': ('<quote>', '</quote>', true),
      'mark': ('<emphasis role="marked">', '</emphasis>', false),
      'superscript': ('<superscript>', '</superscript>', false),
      'subscript': ('<subscript>', '</subscript>', false),
    };

/// [xml] (DocBook) as asciidart repairs what Asciidoctor writes invalid
/// there: tags balanced, literals' content as DocBook allows it, and the
/// copyright's year first (the section elements are chosen as they are
/// written).
String repairDocbook(String xml) => _copyright(_literals(balanceXml(xml)));

final RegExp _copyrightTagRx = RegExp(
  r'<copyright>\n<holder>([^<]*)</holder>\n(?:<year>([^<]*)</year>\n)?</copyright>',
);

/// [xml] with the document's copyright as DocBook 5.0 allows it: the
/// year before the holder, and a copyright with no year (which `copyright`
/// can't hold) as a legal notice.
String _copyright(String xml) {
  if (!xml.contains('<copyright>')) return xml;
  return xml.replaceFirstMapped(_copyrightTagRx, (m) {
    final holder = m[1]!;
    return switch (m[2]) {
      final String year =>
        '<copyright>\n<year>$year</year>\n<holder>$holder</holder>\n</copyright>',
      null => '<legalnotice>\n<simpara>$holder</simpara>\n</legalnotice>',
    };
  });
}

/// [xml] with each `<literal>`'s content as DocBook allows it
/// (asciidart's; Asciidoctor nests emphasis and quotes there): an emphasis
/// opened in a literal becomes a phrase with its role, a quote its
/// quotation marks. Literals may nest.
String _literals(String xml) {
  if (!xml.contains('<literal>')) return xml;
  final out = StringBuffer();
  var depth = 0;
  // The elements opened in a literal: true for an emphasis, false for a
  // quote.
  final opened = <bool>[];
  var last = 0;
  var changed = false;
  for (final m in _literalTagRx.allMatches(xml)) {
    final closing = m[1] == '/';
    final name = m[2]!;
    String? replacement;
    switch (name) {
      case 'literal':
        depth += closing ? -1 : 1;
      case 'emphasis' when !closing && depth > 0:
        opened.add(true);
        replacement = '<phrase role="${m[3] ?? 'emphasis'}">';
      case 'quote' when !closing && depth > 0:
        opened.add(false);
        replacement = '&#8220;';
      case 'emphasis' || 'quote'
          when closing &&
              opened.isNotEmpty &&
              opened.last == (name == 'emphasis'):
        opened.removeLast();
        replacement = name == 'emphasis' ? '</phrase>' : '&#8221;';
    }
    if (replacement == null) continue;
    out
      ..write(xml.substring(last, m.start))
      ..write(replacement);
    last = m.end;
    changed = true;
  }
  if (!changed) return xml;
  out.write(xml.substring(last));
  return out.toString();
}

final RegExp _literalTagRx = RegExp(
  '<(/?)(literal|emphasis|quote)(?: role="([^"]*)")?>',
);

/// Default quote tags for unknown quoted-text types.
const (String, String, bool) _defaultQuoteTags = ('', '', true);

/// A built-in [Converter] implementation that generates DocBook 5 output.
///
/// Port of `Asciidoctor::Converter::DocBook5Converter`. Each `convert*`
/// method corresponds to Asciidoctor's `convert_*` method of the same name
/// and is dispatched to by `convertBlock` and `convertInline` below.
class Docbook5Converter extends BuiltInConverter {
  /// Creates a converter for [backend] with constructor options [opts].
  new(super.backend, [super.opts]) {
    backendTraits = BackendTraits(
      basebackend: 'docbook',
      filetype: 'xml',
      outfilesuffix: '.xml',
      supportsTemplates: true,
    );
  }

  @override
  String? convertBlock(AbstractBlock node, ConvertOptions? opts) =>
      switch (node.context) {
        .admonition => convertAdmonition(node as Block),
        .audio => null,
        .colist => convertColist(node as ListBlock),
        .dlist => convertDlist(node as ListBlock),
        .document => repairDocbook(convertDocument(node as Document)),
        .example => convertExample(node as Block),
        .floatingTitle => convertFloatingTitle(node as Block),
        .image => convertImage(node as Block),
        .listing => convertListing(node as Block),
        .literal => convertLiteral(node as Block),
        .olist => convertOlist(node as ListBlock),
        .open => convertOpen(node as Block),
        .pageBreak => convertPageBreak(node as Block),
        .paragraph => convertParagraph(node as Block),
        .pass => contentOnly(node),
        .preamble => convertPreamble(node as Block),
        .quote => convertQuote(node as Block),
        .section => convertSection(node as Section),
        .sidebar => convertSidebar(node as Block),
        .stem => convertStem(node as Block),
        .table => convertTable(node as Table),
        .thematicBreak => convertThematicBreak(node as Block),
        .toc => null,
        .ulist => convertUlist(node as ListBlock),
        .verse => convertVerse(node as Block),
        .video => null,
        .listItem || .tableCell => missing(node.nodeName),
      };

  @override
  bool handlesBlock(BlockContext context) => switch (context) {
    .listItem || .tableCell => false,
    _ => true,
  };

  @override
  String? convertInline(Inline node) => switch (node.context) {
    .anchor => convertInlineAnchor(node),
    .lineBreak => convertInlineBreak(node),
    .button => convertInlineButton(node),
    .callout => convertInlineCallout(node),
    .footnote => convertInlineFootnote(node),
    .image => convertInlineImage(node),
    .indexterm => convertInlineIndexterm(node),
    .kbd => convertInlineKbd(node),
    .menu => convertInlineMenu(node),
    .quoted => convertInlineQuoted(node),
  };

  @override
  Set<String> get transforms => const {'embedded'};

  @override
  String? convertTransform(
    AbstractNode node,
    String transform,
    ConvertOptions? opts,
  ) => switch (transform) {
    'embedded' => repairDocbook(convertEmbedded(node as Document)),
    _ => missing(transform),
  };

  @override
  String get converterName => 'Docbook5Converter';

  /// Registers this converter for [backends]. Called by document
  /// initialization; idempotent.
  static void registerFor([List<String> backends = const ['docbook5']]) {
    Converter.register(Docbook5Converter.new, backends, provided: true);
  }

  /// Converts the [node] document to a standalone DocBook 5 document.
  String convertDocument(Document node) {
    final result = <String>['<?xml version="1.0" encoding="UTF-8"?>'];
    if (node.hasAttr('toc')) {
      result.add(
        node.hasAttr('toclevels')
            ? '<?asciidoc-toc maxdepth="${_s(node.attr('toclevels'))}"?>'
            : '<?asciidoc-toc?>',
      );
    }
    if (node.hasAttr('sectnums')) {
      result.add(
        node.hasAttr('sectnumlevels')
            ? '<?asciidoc-numbered '
                  'maxdepth="${_s(node.attr('sectnumlevels'))}"?>'
            : '<?asciidoc-numbered?>',
      );
    }
    final langAttribute = node.hasAttr('nolang')
        ? ''
        : ' xml:lang="${_s(node.attr('lang', 'en'))}"';
    var rootTagName = _s(node.doctype);
    var manpage = false;
    if (rootTagName == 'manpage') {
      manpage = true;
      rootTagName = 'article';
    }
    final rootTagIdx = result.length;
    final id = node.id;
    final abstract = _findRootAbstract(node);
    if (!node.noheader) {
      result.add(_documentInfoTag(node, abstract));
    }
    if (manpage) {
      result
        ..add('<refentry>')
        ..add('<refmeta>');
      if (node.hasAttr('mantitle')) {
        result.add(
          '<refentrytitle>${node.applyReftextSubs(node.attr('mantitle')!)}</refentrytitle>',
        );
      }
      if (node.hasAttr('manvolnum')) {
        result.add('<manvolnum>${_s(node.attr('manvolnum'))}</manvolnum>');
      }
      result
        ..add(
          '<refmiscinfo class="source">${_s(node.attr('mansource', '&#160;'))}</refmiscinfo>',
        )
        ..add(
          '<refmiscinfo class="manual">${_s(node.attr('manmanual', '&#160;'))}</refmiscinfo>',
        )
        ..add('</refmeta>')
        ..add('<refnamediv>');
      if (node.hasAttr('mannames')) {
        for (final name in node.mannames ?? const <String>[]) {
          result.add('<refname>$name</refname>');
        }
      }
      if (node.hasAttr('manpurpose')) {
        result.add('<refpurpose>${_s(node.attr('manpurpose'))}</refpurpose>');
      }
      result.add('</refnamediv>');
    }
    final headerDocinfo = node.docinfo('header');
    if (headerDocinfo.isNotEmpty) {
      result.add(headerDocinfo);
    }
    AbstractBlock? extracted;
    if (abstract != null) {
      extracted = _extractAbstract(node, abstract);
    }
    if (node.hasBlocks) {
      result.add(node.blocks.map((block) => block.convert()).nonNulls.join(lf));
    }
    if (extracted != null) {
      _restoreAbstract(extracted);
    }
    final footerDocinfo = node.docinfo('footer');
    if (footerDocinfo.isNotEmpty) {
      result.add(footerDocinfo);
    }
    if (manpage) {
      result.add('</refentry>');
    }
    final rootId = node.id;
    if (id == null) {
      node.id = null;
    }
    // Defer adding root tag in case document ID is auto-generated on demand.
    result
      ..insert(
        rootTagIdx,
        '<$rootTagName xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0"$langAttribute${_commonAttributes(rootId)}>',
      )
      ..add('</$rootTagName>');
    return result.join(lf);
  }

  /// Converts the [node] document to embedded DocBook 5 (body only).
  String convertEmbedded(Document node) {
    // NOTE in DocBook 5, the root abstract must be in the info tag and is
    // thus not part of the body.
    AbstractBlock? extracted;
    if (backend == 'docbook5') {
      final abstract = _findRootAbstract(node);
      if (abstract != null) {
        extracted = _extractAbstract(node, abstract);
      }
    }
    final result = node.blocks
        .map((block) => block.convert())
        .nonNulls
        .join(lf);
    if (extracted != null) {
      _restoreAbstract(extracted);
    }
    return result;
  }

  /// Converts the [node] section.
  String convertSection(Section node) {
    final String tagName;
    if ((node.document! as Document).doctype == 'manpage') {
      final sectname = node.sectname;
      tagName =
          (sectname == null ? null : _manpageSectionTags[sectname]) ??
          _s(sectname);
    } else {
      tagName = _sectionTag(node);
    }
    // A book's chapter that holds only a `toc::[]` macro is its contents:
    // DocBook's <toc>, which processors fill in (a chapter with nothing in
    // it isn't valid DocBook).
    if (tagName == 'chapter' &&
        node.parent is Document &&
        node.blocks.length == 1 &&
        node.blocks.first.context == BlockContext.toc) {
      return '<toc${_nodeAttributes(node)}>\n'
          '<title>${_s(node.title)}</title>\n'
          '</toc>';
    }
    final titleEl =
        node.special &&
            (node.hasOption('notitle') || node.hasOption('untitled'))
        ? ''
        : '<title>${_s(node.title)}</title>\n';
    return '<$tagName${_nodeAttributes(node)}>\n'
        '$titleEl${_s(node.content())}\n'
        '</$tagName>';
  }

  /// The DocBook elements a section may be (asciidart's: a section style
  /// with no element of its own, such as `introduction`, gives an element
  /// no DocBook schema allows in Asciidoctor).
  static const Set<String> _sectionTags = {
    'abstract', 'appendix', 'article', 'bibliography', 'chapter', //
    'colophon', 'dedication', 'glossary', 'index', 'part', 'partintro',
    'preface', 'section',
  };

  /// The element of the section [node]: its name, or the chapter or
  /// section it is when DocBook has no such element there.
  static String _sectionTag(Section node) {
    final sectname = _s(node.sectname);
    // A part introduction is one only in a part.
    if (sectname == 'partintro' &&
        !(node.parent is Section && (node.parent! as Section).level == 0)) {
      return 'section';
    }
    if (_sectionTags.contains(sectname)) return sectname;
    final book = (node.document! as Document).doctype == 'book';
    return book && node.level == 1 ? 'chapter' : 'section';
  }

  /// Converts the [node] admonition block.
  String convertAdmonition(Block node) {
    final tagName = _s(node.attr('name'));
    return '<$tagName${_nodeAttributes(node)}>\n'
        '${_titleTag(node)}${_encloseContent(node)}\n'
        '</$tagName>';
  }

  /// Converts the [node] callout list.
  String convertColist(ListBlock node) {
    final result = <String>['<calloutlist${_nodeAttributes(node)}>'];
    if (node.hasTitle) {
      result.add('<title>${_s(node.title)}</title>');
    }
    for (final itemObj in node.items) {
      final item = itemObj;
      result
        ..add('<callout arearefs="${_s(item.attr('coids'))}">')
        ..add('<para>${_s(item.text)}</para>');
      if (item.hasBlocks) {
        result.add(_s(item.content()));
      }
      result.add('</callout>');
    }
    result.add('</calloutlist>');
    return result.join(lf);
  }

  /// Converts the [node] description list.
  String convertDlist(ListBlock node) {
    final result = <String>[];
    if (node.style == 'horizontal') {
      final tagName = node.hasTitle ? 'table' : 'informaltable';
      result.add(
        '<$tagName${_nodeAttributes(node)} '
        'tabstyle="horizontal" frame="none" colsep="0" rowsep="0">\n'
        '${_titleTag(node)}<tgroup cols="2">\n'
        '<colspec colwidth="${_s(node.attr('labelwidth', '15'))}*"/>\n'
        '<colspec colwidth="${_s(node.attr('itemwidth', '85'))}*"/>\n'
        '<tbody valign="top">',
      );
      for (final DlistEntry(:terms, description: dd) in node.entries) {
        result.add('<row>\n<entry>');
        for (final dt in terms) {
          result.add('<simpara>${_s(dt.text)}</simpara>');
        }
        result.add('</entry>\n<entry>');
        if (dd != null) {
          if (dd.hasText) {
            result.add('<simpara>${_s(dd.text)}</simpara>');
          }
          if (dd.hasBlocks) {
            result.add(_s(dd.content()));
          }
        }
        result.add('</entry>\n</row>');
      }
      result.add('</tbody>\n</tgroup>\n</$tagName>');
    } else {
      final tags = _dlistTags[node.style] ?? _defaultDlistTags;
      final listTag = tags['list'];
      final entryTag = tags['entry']!;
      final labelTag = tags['label'];
      final termTag = tags['term']!;
      final itemTag = tags['item']!;
      if (listTag != null) {
        result.add('<$listTag${_nodeAttributes(node)}>');
        if (node.hasTitle) {
          result.add('<title>${_s(node.title)}</title>');
        }
      }
      for (final DlistEntry(:terms, description: dd) in node.entries) {
        result.add('<$entryTag>');
        if (labelTag != null) {
          result.add('<$labelTag>');
        }
        for (final dt in terms) {
          result.add('<$termTag>${_s(dt.text)}</$termTag>');
        }
        if (labelTag != null) {
          result.add('</$labelTag>');
        }
        result.add('<$itemTag>');
        if (dd != null) {
          if (dd.hasText) {
            result.add('<simpara>${_s(dd.text)}</simpara>');
          }
          if (dd.hasBlocks) {
            result.add(_s(dd.content()));
          }
        }
        result
          ..add('</$itemTag>')
          ..add('</$entryTag>');
      }
      if (listTag != null) {
        result.add('</$listTag>');
      }
    }
    return result.join(lf);
  }

  /// Converts the [node] example block.
  String convertExample(Block node) {
    final attrs = _nodeAttributes(node);
    if (node.hasTitle) {
      return '<example$attrs>\n'
          '<title>${_s(node.title)}</title>\n'
          '${_encloseContent(node)}\n'
          '</example>';
    }
    return '<informalexample$attrs>\n'
        '${_encloseContent(node)}\n'
        '</informalexample>';
  }

  /// Converts the [node] floating title.
  String convertFloatingTitle(Block node) =>
      '<bridgehead${_nodeAttributes(node)} renderas="sect${node.level}">${_s(node.title)}</bridgehead>';

  /// Converts the [node] image block.
  String convertImage(Block node) {
    final alignAttribute = node.hasAttr('align')
        ? ' align="${_s(node.attr('align'))}"'
        : '';
    // A text file (ASCII art): its text, in the media object's text
    // object (asciidart's own output).
    final text = _textImage(node);
    final mediaobject = text != null
        ? '<mediaobject>\n'
              '<textobject><literallayout class="monospaced">$text'
              '</literallayout></textobject>\n'
              '</mediaobject>'
        : '<mediaobject>\n'
              '<imageobject>\n'
              '<imagedata fileref="${node.imageUri(node.attr('target')!)}"${_imageSizeAttributes(node.attributes)}$alignAttribute/>\n'
              '</imageobject>\n'
              '<textobject><phrase>${_s(node.alt)}</phrase></textobject>\n'
              '</mediaobject>';
    // An image's placement (asciidart's `placement` attribute) as DocBook
    // XSL's floatstyle: at the top of a page, or never floated.
    final floatstyle = switch (node.attr('placement')) {
      'top' || 'auto' => ' floatstyle="before"',
      'none' || 'here' => ' floatstyle="none"',
      _ => '',
    };
    if (node.hasTitle) {
      return '<figure${_nodeAttributes(node)}$floatstyle>\n'
          '<title>${_s(node.title)}</title>\n'
          '$mediaobject\n'
          '</figure>';
    }
    return '<informalfigure${_nodeAttributes(node)}$floatstyle>\n'
        '$mediaobject\n'
        '</informalfigure>';
  }

  /// The text of image [node] when its target is a text file
  /// (`image::diagram.txt[]`, or `format=txt`), escaped; else null.
  String? _textImage(Block node) {
    final target = _s(node.attr('target'));
    final isText =
        node.attr('format') == 'txt' ||
        (!node.hasAttr('format') && target.toLowerCase().endsWith('.txt'));
    if (!isText || node.document!.safe >= SafeMode.secure) return null;
    return node
        .readContents(
          target,
          start: node.document!.attr('imagesdir'),
          label: 'text image',
        )
        ?.replaceAll(RegExp(r'\r?\n$'), '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Converts the [node] listing block.
  String convertListing(Block node) {
    final informal = !node.hasTitle;
    final commonAttrs = _nodeAttributes(node);
    final String wrappedContent;
    if (node.style == 'source') {
      final attrs = node.attributes;
      final String numberingAttrs;
      if (attrs.containsKey('linenums')) {
        numberingAttrs = attrs.containsKey('start')
            ? ' linenumbering="numbered" '
                  'startinglinenumber="${parseLeadingInt(attrs['start'])}"'
            : ' linenumbering="numbered"';
      } else {
        numberingAttrs = ' linenumbering="unnumbered"';
      }
      if (attrs.containsKey('language')) {
        wrappedContent =
            '<programlisting${informal ? commonAttrs : ''} language="${_s(attrs['language'])}"$numberingAttrs>${_s(node.content())}</programlisting>';
      } else {
        wrappedContent =
            '<screen${informal ? commonAttrs : ''}$numberingAttrs>${_s(node.content())}</screen>';
      }
    } else {
      wrappedContent =
          '<screen${informal ? commonAttrs : ''}>${_s(node.content())}</screen>';
    }
    if (informal) {
      return wrappedContent;
    }
    return '<formalpara$commonAttrs>\n'
        '<title>${_s(node.title)}</title>\n'
        '<para>\n'
        '$wrappedContent\n'
        '</para>\n'
        '</formalpara>';
  }

  /// Converts the [node] literal block.
  String convertLiteral(Block node) {
    if (node.hasTitle) {
      return '<formalpara${_nodeAttributes(node)}>\n'
          '<title>${_s(node.title)}</title>\n'
          '<para>\n'
          '<literallayout class="monospaced">${_s(node.content())}</literallayout>\n'
          '</para>\n'
          '</formalpara>';
    }
    return '<literallayout${_nodeAttributes(node)} class="monospaced">${_s(node.content())}</literallayout>';
  }

  /// Converts the [node] stem block.
  String convertStem(Block node) {
    final idx = node.subs.indexOf(Sub.specialcharacters);
    final String equation;
    if (idx != -1) {
      node.subs.removeAt(idx);
      equation = _s(node.content());
      node.subs.insert(idx, Sub.specialcharacters);
    } else {
      equation = _s(node.content());
    }
    final String equationData;
    if (node.style == 'asciimath') {
      // NOTE fop requires jeuclid to process mathml markup. There is no
      // AsciiMath-to-MathML converter here, so this always produces what
      // Asciidoctor emits without its optional asciimath gem.
      _warnAsciimathUnavailable();
      equationData = '<mathphrase><![CDATA[$equation]]></mathphrase>';
    } else {
      // Unhandled math; pass source to alt and required mathphrase element;
      // dblatex will process alt as LaTeX math.
      equationData =
          '<alt><![CDATA[$equation]]></alt>\n<mathphrase><![CDATA[$equation]]></mathphrase>';
    }
    if (node.hasTitle) {
      return '<equation${_nodeAttributes(node)}>'
          '\n'
          '<title>${_s(node.title)}</title>\n'
          '$equationData\n'
          '</equation>';
    }
    // WARNING dblatex displays the <informalequation> element inline instead
    // of block as documented (except w/ mathml).
    return '<informalequation${_nodeAttributes(node)}>\n'
        '$equationData\n'
        '</informalequation>';
  }

  /// Converts the [node] ordered list.
  String convertOlist(ListBlock node) {
    final result = <String>[];
    final numAttribute = node.style != null
        ? ' numeration="${node.style}"'
        : '';
    final startAttribute = node.hasAttr('start')
        ? ' startingnumber="${_s(node.attr('start'))}"'
        : '';
    result.add(
      '<orderedlist${_nodeAttributes(node)}$numAttribute$startAttribute>',
    );
    if (node.hasTitle) {
      result.add('<title>${_s(node.title)}</title>');
    }
    for (final itemObj in node.items) {
      final item = itemObj;
      result
        ..add('<listitem${_commonAttributes(item.id, item.role)}>')
        ..add('<simpara>${_s(item.text)}</simpara>');
      if (item.hasBlocks) {
        result.add(_s(item.content()));
      }
      result.add('</listitem>');
    }
    result.add('</orderedlist>');
    return result.join(lf);
  }

  /// Converts the [node] open block.
  String convertOpen(Block node) {
    switch (node.style) {
      case 'abstract':
        final doc = node.document! as Document;
        final parent = node.parent;
        if (parent == doc && doc.doctype == 'book') {
          logger.warn(
            'abstract block cannot be used in a document without a doctitle '
            'when doctype is book. Excluding block content.',
          );
          return '';
        }
        var result =
            '<abstract>\n${_titleTag(node)}${_encloseContent(node)}\n</abstract>';
        if (backend == 'docbook5' &&
            !node.hasOption('root') &&
            (parent!.context == BlockContext.open
                ? parent.style == 'partintro'
                : parent.context == BlockContext.section &&
                      (parent as Section).sectname == 'partintro') &&
            node == parent.blocks[0]) {
          result = '<info>\n$result\n</info>';
        }
        return result;
      case 'partintro':
        final doc = node.document! as Document;
        if (node.level == 0 &&
            node.parent!.context == BlockContext.section &&
            doc.doctype == 'book') {
          return '<partintro${_nodeAttributes(node)}>\n'
              '${_titleTag(node)}${_encloseContent(node)}\n'
              '</partintro>';
        }
        logger.error(
          'partintro block can only be used when doctype is book and must be '
          'a child of a book part. Excluding block content.',
        );
        return '';
      default:
        final id = node.id;
        final reftext = id != null ? node.reftext : null;
        final role = node.role;
        if (node.hasTitle) {
          final spacer = node.contentModel == ContentModel.compound ? lf : '';
          return '<formalpara${_commonAttributes(id, role, reftext)}>\n'
              '<title>${_s(node.title)}</title>\n'
              '<para>$spacer${_s(node.content())}$spacer</para>\n'
              '</formalpara>';
        } else if (id != null || role != null) {
          if (node.contentModel == ContentModel.compound) {
            return '<para${_commonAttributes(id, role, reftext)}>\n'
                '${_s(node.content())}\n'
                '</para>';
          }
          return '<simpara${_commonAttributes(id, role, reftext)}>${_s(node.content())}</simpara>';
        }
        return _encloseContent(node);
    }
  }

  /// Converts the [node] page break.
  String convertPageBreak(Block node) =>
      '<simpara><?asciidoc-pagebreak?></simpara>';

  /// Converts the [node] paragraph.
  String convertParagraph(Block node) {
    if (node.hasTitle) {
      return '<formalpara${_nodeAttributes(node)}>\n'
          '<title>${_s(node.title)}</title>\n'
          '<para>${_s(node.content())}</para>\n'
          '</formalpara>';
    }
    return '<simpara${_nodeAttributes(node)}>${_s(node.content())}</simpara>';
  }

  /// Converts the [node] preamble.
  String convertPreamble(Block node) {
    if ((node.document! as Document).doctype == 'book') {
      return '<preface${_nodeAttributes(node)}>\n'
          '${_titleTag(node, false)}${_s(node.content())}\n'
          '</preface>';
    }
    return _s(node.content());
  }

  /// Converts the [node] quote block.
  String convertQuote(Block node) => _blockquoteTag(
    node,
    node.includesRole('epigraph') ? 'epigraph' : null,
    () => _encloseContent(node),
  );

  /// Converts the [node] thematic break.
  String convertThematicBreak(Block node) =>
      '<simpara><?asciidoc-hr?></simpara>';

  /// Converts the [node] sidebar block.
  String convertSidebar(Block node) =>
      '<sidebar${_nodeAttributes(node)}>\n'
      '${_titleTag(node)}${_encloseContent(node)}\n'
      '</sidebar>';

  /// Converts the [node] table.
  String convertTable(Table node) {
    var hasBody = false;
    final result = <String>[];
    final pgwideAttribute = node.hasOption('pgwide') ? ' pgwide="1"' : '';
    var frame = _s(node.attr('frame', 'all', 'table-frame'));
    if (frame == 'ends') {
      frame = 'topbot';
    }
    final grid = _s(node.attr('grid', null, 'table-grid'));
    final tagName = node.hasTitle ? 'table' : 'informaltable';
    final rowsep = grid == 'none' || grid == 'cols' ? 0 : 1;
    final colsep = grid == 'none' || grid == 'rows' ? 0 : 1;
    final orientAttribute =
        node.hasAttr('orientation', 'landscape', 'table-orientation')
        ? ' orient="land"'
        : '';
    result.add(
      '<$tagName${_nodeAttributes(node)}$pgwideAttribute frame="$frame" '
      'rowsep="$rowsep" colsep="$colsep"$orientAttribute>',
    );
    if (node.hasOption('unbreakable')) {
      result.add('<?dbfo keep-together="always"?>');
    } else if (node.hasOption('breakable')) {
      result.add('<?dbfo keep-together="auto"?>');
    }
    if (tagName == 'table') {
      result.add('<title>${_s(node.title)}</title>');
    }
    final String colWidthKey;
    if (node.hasAttr('width')) {
      final width = _s(node.attr('width'));
      for (final piName in _tablePiNames) {
        result.add('<?$piName table-width="$width"?>');
      }
      colWidthKey = 'colabswidth';
    } else {
      colWidthKey = 'colpcwidth';
    }
    result.add('<tgroup cols="${_s(node.attr('colcount'))}">');
    for (final col in node.columns) {
      result.add(
        '<colspec colname="col_${_s(col.attr('colnumber'))}" colwidth="${_s(col.attr(colWidthKey))}*"/>',
      );
    }
    for (final section in node.rows.toMap().entries) {
      final tsec = section.key;
      final rows = section.value;
      if (rows.isEmpty) {
        continue;
      }
      if (tsec == 'body') {
        hasBody = true;
      }
      result.add('<t$tsec>');
      for (final row in rows) {
        result.add('<row>');
        for (final cell in row) {
          final String colspanAttribute;
          final colspan = cell.colspan;
          if (colspan != null) {
            final colnum = parseLeadingInt(cell.column!.attr('colnumber'));
            colspanAttribute =
                ' namest="col_$colnum" '
                'nameend="col_${colnum + colspan - 1}"';
          } else {
            colspanAttribute = '';
          }
          final rowspan = cell.rowspan;
          final rowspanAttribute = rowspan != null
              ? ' morerows="${rowspan - 1}"'
              : '';
          // NOTE <entry> may not have whitespace (e.g., line breaks) as a
          // direct descendant according to DocBook rules.
          final entryStart =
              '<entry align="${_s(cell.attr('halign'))}" '
              'valign="${_s(cell.attr('valign'))}"'
              '$colspanAttribute$rowspanAttribute>';
          final String cellContent;
          if (tsec == 'head') {
            cellContent = _s(cell.text);
          } else {
            switch (cell.style) {
              case 'asciidoc':
                cellContent = _s(cell.content());
              case 'literal':
                cellContent =
                    '<literallayout class="monospaced">${_s(cell.text)}</literallayout>';
              case 'header':
                final paragraphs = cell.paragraphs;
                cellContent = paragraphs.isEmpty
                    ? ''
                    : '<simpara><emphasis role="strong">${paragraphs.join('</emphasis></simpara><simpara><emphasis role="strong">')}</emphasis></simpara>';
              default:
                final paragraphs = cell.paragraphs;
                cellContent = paragraphs.isEmpty
                    ? ''
                    : '<simpara>${paragraphs.join('</simpara><simpara>')}</simpara>';
            }
          }
          final entryEnd = (node.document! as Document).hasAttr('cellbgcolor')
              ? '<?dbfo bgcolor="${_s((node.document! as Document).attr('cellbgcolor'))}"?></entry>'
              : '</entry>';
          result.add('$entryStart$cellContent$entryEnd');
        }
        result.add('</row>');
      }
      result.add('</t$tsec>');
    }
    result
      ..add('</tgroup>')
      ..add('</$tagName>');

    if (!hasBody) {
      logger.warn('tables must have at least one body row');
    }
    return result.join(lf);
  }

  /// Converts the [node] unordered list.
  String convertUlist(ListBlock node) {
    final result = <String>[];
    if (node.style == 'bibliography') {
      result.add('<bibliodiv${_nodeAttributes(node)}>');
      if (node.hasTitle) {
        result.add('<title>${_s(node.title)}</title>');
      }
      for (final itemObj in node.items) {
        final item = itemObj;
        result
          ..add('<bibliomixed>')
          ..add('<bibliomisc>${_s(item.text)}</bibliomisc>');
        if (item.hasBlocks) {
          result.add(_s(item.content()));
        }
        result.add('</bibliomixed>');
      }
      result.add('</bibliodiv>');
    } else {
      final checklist = node.hasOption('checklist');
      final markType = checklist ? 'none' : node.style;
      final markAttribute = markType != null ? ' mark="$markType"' : '';
      result.add('<itemizedlist${_nodeAttributes(node)}$markAttribute>');
      if (node.hasTitle) {
        result.add('<title>${_s(node.title)}</title>');
      }
      for (final itemObj in node.items) {
        final item = itemObj;
        final textMarker = checklist && item.hasAttr('checkbox')
            ? (item.hasAttr('checked') ? '&#10003; ' : '&#10063; ')
            : null;
        result
          ..add('<listitem${_commonAttributes(item.id, item.role)}>')
          ..add('<simpara>${textMarker ?? ''}${_s(item.text)}</simpara>');
        if (item.hasBlocks) {
          result.add(_s(item.content()));
        }
        result.add('</listitem>');
      }
      result.add('</itemizedlist>');
    }
    return result.join(lf);
  }

  /// Converts the [node] verse block.
  String convertVerse(Block node) => _blockquoteTag(
    node,
    node.includesRole('epigraph') ? 'epigraph' : null,
    () => '<literallayout>${_s(node.content())}</literallayout>',
  );

  /// Converts the [node] inline anchor.
  String? convertInlineAnchor(Inline node) {
    switch (node.type) {
      case 'ref':
        final id = node.id;
        return '<anchor${_commonAttributes(id, null, node.reftext ?? '[${_s(id)}]')}/>';
      case 'xref':
        final path = node.attributes['path'];
        if (path != null) {
          return '<link xl:href="${_s(node.target)}">${node.text ?? _s(path)}</link>';
        }
        var linkend = node.attributes['refid'];
        if (linkend == null || linkend.isEmpty) {
          final rootDoc = _getRootDocument(node);
          linkend = rootDoc.id ??= _generateDocumentId(rootDoc);
        }
        final text = node.text;
        // NOTE the xref tag in DocBook does not support explicit link text,
        // so the link tag must be used instead.
        return text != null
            ? '<link linkend="$linkend">$text</link>'
            : '<xref linkend="$linkend"/>';
      case 'link':
        return '<link xl:href="${_s(node.target)}">${_s(node.text)}</link>';
      case 'bibref':
        final text = '[${node.reftext ?? _s(node.id)}]';
        return '<anchor${_commonAttributes(node.id, null, text)}/>$text';
      default:
        logger.warn('unknown anchor type: :${node.type}');
        return null;
    }
  }

  /// Converts the [node] inline line break.
  String convertInlineBreak(Inline node) => '${_s(node.text)}<?asciidoc-br?>';

  /// Converts the [node] inline button.
  String convertInlineButton(Inline node) =>
      '<guibutton>${_s(node.text)}</guibutton>';

  /// Converts the [node] inline callout.
  String convertInlineCallout(Inline node) =>
      '<co${_commonAttributes(node.id)}/>';

  /// Converts the [node] inline footnote.
  String convertInlineFootnote(Inline node) => node.type == 'xref'
      ? '<footnoteref linkend="${_s(node.target)}"/>'
      : '<footnote${_commonAttributes(node.id)}><simpara>${_s(node.text)}</simpara></footnote>';

  /// Converts the [node] inline image.
  String convertInlineImage(Inline node) {
    final String? fileref;
    final String uri;
    if (node.type == 'icon') {
      fileref = null;
      uri = node.iconUri(node.target!);
    } else {
      fileref = node.imageUri(node.target!);
      uri = fileref;
    }
    final img =
        '<inlinemediaobject${_commonAttributes(null, node.role)}>\n'
        '<imageobject>\n'
        '<imagedata fileref="$uri"${_imageSizeAttributes(node.attributes)}/>\n'
        '</imageobject>\n'
        '<textobject><phrase>${_s(node.alt)}</phrase></textobject>\n'
        '</inlinemediaobject>';
    final linkHref = node.hasAttr('link') ? node.attr('link') : null;
    if (fileref != null && linkHref != null) {
      return '<link xl:href="${_s(linkHref)}">$img</link>';
    }
    return img;
  }

  /// Converts the [node] inline index term.
  String convertInlineIndexterm(Inline node) {
    final see = node.attr('see');
    final String rel;
    if (see != null) {
      rel = '\n<see>${_s(see)}</see>';
    } else {
      final seeAlsoList = node.seeAlso;
      rel = seeAlsoList != null
          ? seeAlsoList.map((seeAlso) => '\n<seealso>$seeAlso</seealso>').join()
          : '';
    }
    if (node.type == 'visible') {
      return '<indexterm>\n<primary>${_s(node.text)}</primary>$rel\n</indexterm>${_s(node.text)}';
    }
    final terms = node.terms!;
    final promotion = (node.document! as Document).hasOption(
      'indexterm-promotion',
    );
    if (terms.length > 2) {
      return '<indexterm>\n<primary>${terms[0]}</primary><secondary>${terms[1]}</secondary><tertiary>${terms[2]}</tertiary>$rel\n</indexterm>${promotion ? '\n<indexterm>\n<primary>${terms[1]}</primary><secondary>${terms[2]}</secondary>\n</indexterm>\n<indexterm>\n<primary>${terms[2]}</primary>\n</indexterm>' : ''}';
    } else if (terms.length > 1) {
      return '<indexterm>\n<primary>${terms[0]}</primary><secondary>${terms[1]}</secondary>$rel\n</indexterm>${promotion ? '\n<indexterm>\n<primary>${terms[1]}</primary>\n</indexterm>' : ''}';
    }
    return '<indexterm>\n<primary>${terms[0]}</primary>$rel\n</indexterm>';
  }

  /// Converts the [node] inline keyboard shortcut.
  String convertInlineKbd(Inline node) {
    final keys = node.keys!;
    if (keys.length == 1) return '<keycap>${keys[0]}</keycap>';
    return '<keycombo><keycap>${keys.join('</keycap><keycap>')}</keycap></keycombo>';
  }

  /// Converts the [node] inline menu reference.
  String convertInlineMenu(Inline node) {
    final menu = _s(node.attr('menu'));
    final submenus = node.submenus!;
    if (submenus.isEmpty) {
      final menuitem = node.attr('menuitem');
      if (menuitem != null) {
        return '<menuchoice><guimenu>$menu</guimenu> <guimenuitem>${_s(menuitem)}</guimenuitem></menuchoice>';
      }
      return '<guimenu>$menu</guimenu>';
    }
    return '<menuchoice><guimenu>$menu</guimenu> <guisubmenu>${submenus.join('</guisubmenu> <guisubmenu>')}</guisubmenu> <guimenuitem>${_s(node.attr('menuitem'))}</guimenuitem></menuchoice>';
  }

  bool _asciimathWarned = false;

  /// Warns, once per converter (so once per document), that AsciiMath is
  /// left as text, as Asciidoctor does when it cannot convert AsciiMath.
  void _warnAsciimathUnavailable() {
    if (_asciimathWarned) return;
    _asciimathWarned = true;
    logger.warn(
      'AsciiMath to MathML conversion is not available. '
      'Functionality disabled.',
    );
  }

  /// Converts the [node] inline quoted text.
  String convertInlineQuoted(Inline node) {
    final type = node.type;
    if (type == 'asciimath') {
      // NOTE fop requires jeuclid to process mathml markup. There is no
      // AsciiMath-to-MathML converter here, so this always produces what
      // Asciidoctor emits without its optional asciimath gem.
      _warnAsciimathUnavailable();
      return '<inlineequation><mathphrase><![CDATA[${_s(node.text)}]]></mathphrase></inlineequation>';
    } else if (type == 'latexmath') {
      // Unhandled math; pass source to alt and required mathphrase element;
      // dblatex will process alt as LaTeX math.
      final equation = _s(node.text);
      return '<inlineequation><alt><![CDATA[$equation]]></alt><mathphrase><![CDATA[$equation]]></mathphrase></inlineequation>';
    }
    final (open, close, supportsPhrase) = _quoteTags[type] ?? _defaultQuoteTags;
    final text = _s(node.text);
    final String quotedText;
    final role = node.role;
    if (role != null) {
      if (supportsPhrase) {
        quotedText = '$open<phrase role="${_s(role)}">$text</phrase>$close';
      } else {
        quotedText =
            '${open.substring(0, open.length - 1)} '
            'role="${_s(role)}">$text$close';
      }
    } else {
      quotedText = '$open$text$close';
    }
    return node.id != null
        ? '<anchor${_commonAttributes(node.id)}/>$quotedText'
        : quotedText;
  }

  /// [_commonAttributes] for [node]'s own id, role and reftext.
  String _nodeAttributes(AbstractNode node) =>
      _commonAttributes(node.id, node.role, node.reftext);

  /// The `xml:id`, `role` and `xreflabel` attributes shared by most elements.
  String _commonAttributes(String? id, [String? role, String? reftext]) {
    final String attrs;
    if (id != null) {
      attrs = ' xml:id="$id"${role != null ? ' role="${_s(role)}"' : ''}';
    } else if (role != null) {
      attrs = ' role="${_s(role)}"';
    } else {
      attrs = '';
    }
    if (reftext != null) {
      var label = reftext;
      if (label.contains('<')) {
        label = label.replaceAll(xmlSanitizeRx, '');
        if (label.contains(' ')) {
          label = collapseRuns(label, ' ').trimAscii();
        }
      }
      if (label.contains('"')) {
        label = label.replaceAll('"', '&quot;');
      }
      return '$attrs xreflabel="$label"';
    }
    return attrs;
  }

  /// The size attributes of an image (`width`/`scale`/`contentwidth`/...).
  String _imageSizeAttributes(Map<String, String> attributes) {
    // NOTE according to the DocBook spec, content area, scaling, and scaling
    // to fit are mutually exclusive. See
    // http://tdg.docbook.org/tdg/4.5/imagedata-x.html#d0e79635
    if (attributes.containsKey('scaledwidth')) {
      return ' width="${_s(attributes['scaledwidth'])}"';
    } else if (attributes.containsKey('scale')) {
      return ' scale="${_s(attributes['scale'])}"';
    }
    final widthAttribute = attributes.containsKey('width')
        ? ' contentwidth="${_s(attributes['width'])}"'
        : '';
    final depthAttribute = attributes.containsKey('height')
        ? ' contentdepth="${_s(attributes['height'])}"'
        : '';
    return '$widthAttribute$depthAttribute';
  }

  /// The `<author>` element for [author] in the document info tag.
  String _authorTag(Document doc, DocumentAuthor author) {
    final result = (<String>[])
      ..add('<author>')
      ..add('<personname>');
    if (author.firstname != null) {
      result.add(
        '<firstname>${doc.subReplacements(author.firstname!)}</firstname>',
      );
    }
    if (author.middlename != null) {
      result.add(
        '<othername>${doc.subReplacements(author.middlename!)}</othername>',
      );
    }
    if (author.lastname != null) {
      result.add('<surname>${doc.subReplacements(author.lastname!)}</surname>');
    }
    result.add('</personname>');
    if (author.email != null) {
      result.add('<email>${author.email}</email>');
    }
    result.add('</author>');
    return result.join(lf);
  }

  /// The `<info>` element of the [doc] document.
  String _documentInfoTag(Document doc, AbstractBlock? abstract) {
    final result = <String>['<info>'];
    if (!doc.notitle) {
      final title = doc.partitionedTitle(useFallback: true)!;
      if (title.hasSubtitle) {
        result.add(
          '<title>${title.main}</title>\n<subtitle>${title.subtitle}</subtitle>',
        );
      } else {
        result.add('<title>$title</title>');
      }
    }
    final date = doc.hasAttr('revdate')
        ? doc.attr('revdate')
        : (doc.hasAttr('reproducible') ? null : doc.attr('docdate'));
    if (date != null) {
      result.add('<date>${_s(date)}</date>');
    }
    if (doc.hasAttr('copyright')) {
      final match = _copyrightRx.firstMatch(doc.attr('copyright')!);
      result
        ..add('<copyright>')
        ..add('<holder>${match?.group(1) ?? ''}</holder>');
      final year = match?.group(2);
      if (year != null) {
        result.add('<year>$year</year>');
      }
      result.add('</copyright>');
    }
    if (doc.hasHeader) {
      final authors = doc.authors;
      if (authors.isNotEmpty) {
        if (authors.length > 1) {
          result.add('<authorgroup>');
          for (final author in authors) {
            result.add(_authorTag(doc, author));
          }
          result.add('</authorgroup>');
        } else {
          final author = authors[0];
          result.add(_authorTag(doc, author));
          if (author.initials != null) {
            result.add('<authorinitials>${author.initials}</authorinitials>');
          }
        }
      }
      if (doc.hasAttr('revdate') &&
          (doc.hasAttr('revnumber') || doc.hasAttr('revremark'))) {
        result.add('<revhistory>\n<revision>');
        if (doc.hasAttr('revnumber')) {
          result.add('<revnumber>${_s(doc.attr('revnumber'))}</revnumber>');
        }
        if (doc.hasAttr('revdate')) {
          result.add('<date>${_s(doc.attr('revdate'))}</date>');
        }
        if (doc.hasAttr('authorinitials')) {
          result.add(
            '<authorinitials>${_s(doc.attr('authorinitials'))}</authorinitials>',
          );
        }
        if (doc.hasAttr('revremark')) {
          result.add('<revremark>${_s(doc.attr('revremark'))}</revremark>');
        }
        result.add('</revision>\n</revhistory>');
      }
      if (doc.hasAttr('front-cover-image') || doc.hasAttr('back-cover-image')) {
        final backCoverTag = _coverTag(doc, 'back');
        if (backCoverTag != null) {
          result
            ..add(_coverTag(doc, 'front', true)!)
            ..add(backCoverTag);
        } else {
          final frontCoverTag = _coverTag(doc, 'front');
          if (frontCoverTag != null) {
            result.add(frontCoverTag);
          }
        }
      }
      if (doc.hasAttr('orgname')) {
        result.add('<orgname>${_s(doc.attr('orgname'))}</orgname>');
      }
      final docinfoContent = doc.docinfo();
      if (docinfoContent.isNotEmpty) {
        result.add(docinfoContent);
      }
    }
    if (abstract != null) {
      abstract.setOption('root');
      result.add(_s(convert(abstract, abstract.nodeName)));
      abstract.removeAttr('root-option');
    }
    result.add('</info>');
    return result.join(lf);
  }

  /// The root abstract of [doc], if the first block qualifies.
  AbstractBlock? _findRootAbstract(Document doc) {
    if (!doc.hasBlocks) return null;
    var firstBlock = doc.blocks[0];
    if (firstBlock.context == BlockContext.preamble) {
      if (firstBlock.blocks.isEmpty) return null;
      firstBlock = firstBlock.blocks[0];
    } else if (firstBlock.context == BlockContext.section) {
      final sect = firstBlock as Section;
      if (sect.sectname == 'abstract') return firstBlock;
      if (sect.sectname != 'preface' || firstBlock.blocks.isEmpty) {
        return null;
      }
      firstBlock = firstBlock.blocks[0];
    }
    return firstBlock.style == 'abstract' &&
            firstBlock.context == BlockContext.open
        ? firstBlock
        : null;
  }

  /// Removes the topmost single-child container of [abstract] from
  /// [document], returning the removed block for [_restoreAbstract].
  AbstractBlock _extractAbstract(Document document, AbstractBlock abstract) {
    var parent = abstract.parent!;
    while (parent != document && parent.blocks.length == 1) {
      parent = parent.parent!;
    }
    return parent.blocks.removeAt(0);
  }

  /// Reinserts a block removed by [_extractAbstract].
  void _restoreAbstract(AbstractBlock abstract) {
    abstract.parent!.blocks.insert(0, abstract);
  }

  /// The outermost document [node] belongs to.
  Document _getRootDocument(Inline node) {
    var doc = node.document! as Document;
    while (doc.nested()) {
      doc = doc.parentDocument!;
    }
    return doc;
  }

  /// The on-demand ID generated for a document without one.
  String _generateDocumentId(Document doc) => '__${_s(doc.doctype)}-root__';

  // FIXME this should be handled through a template mechanism
  /// The converted content of [node], wrapped in `<simpara>` unless the
  /// content model is compound.
  String _encloseContent(Block node) =>
      node.contentModel == ContentModel.compound
      ? _s(node.content())
      : '<simpara>${_s(node.content())}</simpara>';

  /// The `<title>` element of [node] (`''` when [optional] and untitled).
  String _titleTag(AbstractBlock node, [bool optional = true]) =>
      !optional || node.hasTitle ? '<title>${_s(node.title)}</title>\n' : '';

  /// The `<cover>` element for the [face] cover image of [doc].
  String? _coverTag(Document doc, String face, [bool usePlaceholder = false]) {
    final coverAttr = doc.attr('$face-cover-image');
    if (coverAttr != null) {
      var coverImage = coverAttr;
      var sizeAttrs = '';
      if (coverImage.contains(':')) {
        final match = _imageMacroRx.firstMatch(coverImage);
        if (match != null) {
          final target = match.group(1)!;
          final attrlist = match.group(2);
          coverImage = doc.imageUri(target);
          if (attrlist != null) {
            // NOTE scalefit="1" is the default for a cover image.
            sizeAttrs = _imageSizeAttributes(
              AttributeList(attrlist).parse(const ['alt', 'width', 'height']),
            );
          }
        }
      }
      return '<cover role="$face">\n'
          '<mediaobject>\n'
          '<imageobject>\n'
          '<imagedata fileref="$coverImage"$sizeAttrs/>\n'
          '</imageobject>\n'
          '</mediaobject>\n'
          '</cover>';
    } else if (usePlaceholder) {
      return '<cover role="$face"/>';
    }
    return null;
  }

  /// The `<blockquote>` (or [tagName]) element wrapping [content].
  String _blockquoteTag(
    Block node,
    String? tagName,
    String Function() content,
  ) {
    final String startTag;
    final String endTag;
    if (tagName != null) {
      startTag = '<$tagName';
      endTag = '</$tagName>';
    } else {
      startTag = '<blockquote';
      endTag = '</blockquote>';
    }
    final result = <String>['$startTag${_nodeAttributes(node)}>'];
    if (node.hasTitle) {
      result.add('<title>${_s(node.title)}</title>');
    }
    if (node.hasAttr('attribution') || node.hasAttr('citetitle')) {
      result.add('<attribution>');
      if (node.hasAttr('attribution')) {
        result.add(_s(node.attr('attribution')));
      }
      if (node.hasAttr('citetitle')) {
        result.add('<citetitle>${_s(node.attr('citetitle'))}</citetitle>');
      }
      result.add('</attribution>');
    }
    result
      ..add(content())
      ..add(endTag);
    return result.join(lf);
  }
}
