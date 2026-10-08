/// The EPUB3 converter: converts a document to an EPUB 3 publication
/// (XHTML chapters, navigation, metadata, stylesheets, fonts), as the
/// asciidoctor-epub3 2.3.0 gem does.
///
/// Port of `lib/asciidoctor-epub3/converter.rb`. A book is split into one
/// XHTML file per chapter (sections up to `epub-chapter-level`, and the
/// preamble); any other document is one chapter. Converting the document
/// builds an [EpubBook]; [Epub3Converter.package] zips it.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:plain_highlighting/plain_highlighting.dart'
    show highlightJsStyles;
import 'package:plain_math/plain_math.dart' show asciimathToMathml;
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/attribute_list.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/callout_links.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/converter.dart';
import 'package:ptome/src/data.g.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/epub3/assets.g.dart';
import 'package:ptome/src/epub3/book.dart';
import 'package:ptome/src/epub3/dates.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/helpers.dart';
import 'package:ptome/src/highlight/highlight.dart' show CssMode;
import 'package:ptome/src/highlight/highlightjs.dart';
import 'package:ptome/src/highlight/syntax_highlighter.dart';
import 'package:ptome/src/index_catalog.dart';
import 'package:ptome/src/inline.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/list.dart';
import 'package:ptome/src/output_template.dart';
import 'package:ptome/src/page_map.dart';
import 'package:ptome/src/parallel.dart';
import 'package:ptome/src/section.dart';
import 'package:ptome/src/table.dart';
import 'package:ptome/src/unbreakable.dart';
import 'package:ptome/src/xml_balance.dart';

String _s(String? value) => value ?? '';

/// The document [node] is in.
Document _doc(AbstractNode node) => node.document! as Document;

const String _lf = '\n';
const String _noBreakSpace = '&#xa0;';
const String _rightAngleQuote = '&#x203a;';

/// The first callout number glyph (circled one); the following ones are
/// the next code points, as Ruby's `String#next` gives them.
const int _calloutStart = 0x2460;

final RegExp _csvDelimitedRx = RegExp(r'\s*,\s*');
final RegExp _imageMacroRx = RegExp(r'^image::?(.*?)\[(.*?)\]$');
final RegExp _imageSrcScanRx = RegExp('<img src="(.+?)"');
final RegExp _svgImgSniffRx = RegExp(r'<img src=".+?\.svg"');
final RegExp _charEntityRx = RegExp(r'&#(\d{2,6});');
final RegExp _xmlElementRx = RegExp('</?.+?>');
final RegExp _trailingPunctRx = RegExp(r'[!-/:-@\[-`{-~]$');
final RegExp _fromHtmlSpecialCharsRx = RegExp('&lt;|&gt;|&amp;');
final RegExp _epubExtensionRx = RegExp(r'\.epub$', caseSensitive: false);

/// The links to the stylesheets in a chapter or navigation document.
const String _stylesheetLinks =
    '<link rel="stylesheet" type="text/css" href="styles/epub3.css"/>\n'
    '<link rel="stylesheet" type="text/css" '
    'href="styles/epub3-css3-only.css" media="(min-device-width: 0px)"/>';

/// The script a chapter has to tell the stylesheets which reading system
/// shows it.
const String _readingSystemScript =
    '<script type="text/javascript"><![CDATA[\n'
    "document.addEventListener('DOMContentLoaded', "
    'function(event, reader) {\n'
    '  if (!(reader = navigator.epubReadingSystem)) {\n'
    "    if (navigator.userAgent.indexOf(' calibre/') >= 0) "
    "reader = { name: 'calibre-desktop' };\n"
    '    else if (window.parent == window || '
    '!(reader = window.parent.navigator.epubReadingSystem)) return;\n'
    '  }\n'
    "  document.body.setAttribute('class', "
    "reader.name.toLowerCase().replace(/ /g, '-'));\n"
    '});\n'
    ']]></script>';

/// The open tag, close tag and whether the open tag is an element (so the
/// id and role go on it) of each kind of formatted text.
const Map<String, (String, String, bool)> _quoteTags = {
  'monospaced': ('<code>', '</code>', true),
  'emphasis': ('<em>', '</em>', true),
  'strong': ('<strong>', '</strong>', true),
  'double': ('“', '”', false),
  'single': ('‘', '’', false),
  'mark': ('<mark>', '</mark>', true),
  'superscript': ('<sup>', '</sup>', true),
  'subscript': ('<sub>', '</sub>', true),
  'asciimath': ('<code>', '</code>', true),
  'latexmath': ('<code>', '</code>', true),
};

/// The table cell an AsciiDoc cell's document is in (the gem's
/// `@epub3_parent_cell`), so its nodes find their chapter.
final Expando<Cell> _parentCell = Expando<Cell>('epub3 parent cell');

/// The EPUB3 converter.
class Epub3Converter extends BuiltInConverter implements FinishingConverter {
  /// Creates the converter for [backend].
  new(super.backend, [super.opts]) {
    backendTraits = BackendTraits(
      basebackend: 'html',
      filetype: 'epub',
      outfilesuffix: '.epub',
      htmlsyntax: 'xml',
      supportsTemplates: true,
    );
  }

  final Set<String> _xrefsSeen = {};
  final Map<String, ({String? path, String mediaType})> _mediaFiles = {};
  final List<Footnote> _footnotes = [];

  /// The icon names used so far (every chapter defines the ones before
  /// it too, as the gem does).
  final List<String> _iconNames = [];

  EpubBook? _book;

  /// The workers the book's files are compressed on, when the conversion
  /// is awaited (the `jobs` attribute: the physical cores by default).
  Parallel? _parallel;

  /// The book's files compressed on other cores, by path.
  Map<String, List<int>> _deflated = const {};

  bool _validate = false;
  bool _extract = false;
  String? _epubcheckPath;

  /// The book the last converted document built.
  EpubBook? get book => _book;

  @override
  String get converterName => 'Epub3Converter';

  @override
  String? convertBlock(AbstractBlock node, ConvertOptions? opts) {
    final out = _convertBlock(node, opts);
    // `%unbreakable` (ADR-0012).
    final marked =
        out != null &&
            node.hasOption('unbreakable') &&
            marksUnbreakable(node.nodeName) &&
            // (A listing is a `coalesce` figure already, as in
            // asciidoctor-epub3.)
            node.context != BlockContext.listing
        ? withUnbreakableClass(out)
        : out;
    return marked == null ? null : _withPageBreaks(node, marked);
  }

  /// The print edition's pages (`epub-page-map`, the PDF's
  /// `pdf-page-map`): their labels, and the pages of each block by where
  /// it starts in the source.
  PageMap? _pageMap;

  /// The last print page marked, and the page list (href, label).
  int _lastPage = 0;
  final List<(String, String)> _pageList = [];

  /// The chapter file being converted.
  String? _chapterFile;

  void _loadPageMap(Document doc) {
    final target = doc.attr('epub-page-map');
    if (target == null || target.isEmpty) return;
    final docdir = _s(doc.attr('docdir', '.'));
    final path = target.startsWith('/')
        ? target
        : _join(docdir.isEmpty ? '.' : docdir, target);
    if (!io.isReadable(path)) {
      logger.warn('epub-page-map: $path not found or not readable');
      return;
    }
    final map = PageMap.parse(utf8.decode(io.readBytes(path)));
    if (map == null) {
      logger.warn('epub-page-map: $path is not a page map');
    }
    _pageMap = map;
  }

  /// [html] (block [node]) with the print pages that start before it
  /// marked before it, and those that start inside it after it
  /// (`epub-page-map`: a block's pages; ADR-0012).
  String _withPageBreaks(AbstractBlock node, String html) {
    final map = _pageMap;
    final at = node.sourceLocation;
    if (map == null ||
        at == null ||
        !marksUnbreakable(node.nodeName) ||
        _chapterFile == null) {
      return html;
    }
    final pages = map.blocks['${at.path ?? at.file ?? ''}:${at.lineno}'];
    if (pages == null) return html;
    final (first, last) = pages;
    String markers(int from, int to) {
      final out = StringBuffer();
      for (var page = from; page <= to; page++) {
        if (page < 1 || page > map.labels.length) continue;
        final label = map.labels[page - 1];
        final id = 'page-${label.replaceAll(RegExp('[^A-Za-z0-9_-]'), '-')}';
        _pageList.add(('$_chapterFile#$id', label));
        out.write(
          '<span epub:type="pagebreak" role="doc-pagebreak" id="$id" '
          'aria-label="$label"></span>',
        );
      }
      return out.toString();
    }

    final before = markers(_lastPage + 1, first);
    _lastPage = math.max(_lastPage, first);
    final after = markers(_lastPage + 1, last);
    _lastPage = math.max(_lastPage, last);
    return '$before$html$after';
  }

  String? _convertBlock(AbstractBlock node, ConvertOptions? opts) =>
      switch (node.context) {
        .admonition => convertAdmonition(node as Block),
        .audio => convertAudio(node as Block),
        .colist => convertColist(node as ListBlock),
        .dlist => convertDlist(node as ListBlock),
        .document => convertDocument(node as Document),
        .example => convertExample(node as Block),
        .floatingTitle => convertFloatingTitle(node as Block),
        .image => convertImage(node as Block),
        .listing => convertListing(node as Block),
        .literal => convertLiteral(node as Block),
        .olist => convertOlist(node as ListBlock),
        .open => convertOpen(node as Block),
        .pageBreak => '<hr epub:type="pagebreak" class="pagebreak"/>',
        .paragraph => convertParagraph(node as Block),
        .pass => convertPass(node as Block),
        .preamble => convertPreamble(node as Block),
        .quote => convertQuote(node as Block),
        .section => convertSection(node as Section),
        .sidebar => convertSidebar(node as Block),
        .stem => convertStem(node as Block),
        .table => convertTable(node as Table),
        .thematicBreak => '<hr class="thematicbreak"/>',
        .ulist => convertUlist(node as ListBlock),
        .verse => convertVerse(node as Block),
        .video => convertVideo(node as Block),
        .toc => convertToc(node as Block),
        .listItem || .tableCell => _missing(node.nodeName),
      };

  @override
  bool handlesBlock(BlockContext context) => switch (context) {
    .listItem || .tableCell => false,
    _ => true,
  };

  @override
  String? convertInline(Inline node) => switch (node.context) {
    .anchor => convertInlineAnchor(node),
    .lineBreak => '${_s(node.text)}<br/>',
    .button => '<b class="button">${_s(node.text)}</b>',
    .callout => convertInlineCallout(node),
    .footnote => convertInlineFootnote(node),
    .image => convertInlineImage(node),
    .indexterm => _indexterm(node),
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
    // An AsciiDoc table cell's document.
    'embedded' => (node as Document).content(),
    _ => _missing(transform),
  };

  String? _missing(String name) {
    logger.warn('conversion missing in backend $backend for $name');
    return null;
  }

  /// The name of the XHTML file [node] is the chapter of (its id), or
  /// `null` when it isn't a chapter.
  String? chapterFilename(AbstractNode node) =>
      _isChapter(node) ? node.id : null;

  /// Whether [node] starts a chapter (a file of its own): the document,
  /// unless it is a book; in a book, the preamble and the sections up to
  /// `epub-chapter-level`.
  static bool _isChapter(AbstractNode node) {
    final document = _doc(node);
    if (document.doctype != 'book') return node is Document;
    if (node is AbstractBlock &&
        node.context == BlockContext.preamble &&
        node.level == 0) {
      return true;
    }
    final chapterLevel = _toInt(document.attr('epub-chapter-level', '1'));
    return node is Section &&
        (node.level ?? 0) <= (chapterLevel < 1 ? 1 : chapterLevel);
  }

  /// The title of [node] with its caption or section number.
  String numberedTitle(AbstractBlock node) {
    final docAttrs = _doc(node).attributes;
    final level = node.level ?? 0;
    if (node.caption != null) return node.captionedTitle();
    if (node is Section &&
        node.numbered &&
        level <= _toInt(docAttrs['sectnumlevels'] ?? '3')) {
      if (level < 2 && _doc(node).doctype == 'book') {
        switch (node.sectname) {
          case 'chapter':
            final signifier = docAttrs['chapter-signifier'];
            return '${signifier != null ? '$signifier ' : ''}'
                '${node.sectnum()} ${_s(node.title)}';
          case 'part':
            final signifier = docAttrs['part-signifier'];
            return '${signifier != null ? '$signifier ' : ''}'
                '${node.sectnum('.', ':')} ${_s(node.title)}';
        }
      }
      return '${node.sectnum()} ${_s(node.title)}';
    }
    return _s(node.title);
  }

  /// Converts the document: builds the book.
  String convertDocument(Document node) {
    if (node.parentDocument == null) node.catalog.index.begin(node);
    _loadPageMap(node);
    _validate = node.hasAttr('ebook-validate');
    _extract = node.hasAttr('ebook-extract');
    _epubcheckPath = node.attr('ebook-epubcheck-path');

    final uuid = _s(node.hasAttr('uuid') ? node.attr('uuid') : node.id);
    final isbn = node.attr('isbn')?.replaceAll(RegExp(r'[\s-]'), '');
    // Ptome's `epub-unique-identifier`: which of the book's identifiers
    // is the unique one (`uuid`, the gem's; `isbn`).
    final isbnUnique =
        node.attr('epub-unique-identifier') == 'isbn' &&
        isbn != null &&
        isbn.isNotEmpty;
    _deflated = const {};
    _embedFonts = node.hasAttr('epub-embed-fonts');
    _missingFonts.clear();
    _parallel = workersAwaited
        ? Parallel.forAttribute(node.attr('jobs'))
        : null;
    final book = _book = EpubBook()
      ..language(_s(node.attr('lang', 'en')), id: 'pub-language');
    if (isbnUnique) {
      book.primaryIdentifier('urn:isbn:$isbn', 'pub-identifier', 'isbn');
    } else {
      book.primaryIdentifier(uuid, 'pub-identifier', 'uuid');
    }
    book.addTitle(_sanitizeDoctitle(node, _Spec.plainText), id: 'pub-title');

    final authorcount = _toInt(node.attr('authorcount', '1'));
    for (var idx = 1; idx <= authorcount; idx++) {
      final author = node.attr(idx == 1 ? 'author' : 'author_$idx');
      if (author != null && author.isNotEmpty) book.addCreator(author);
    }
    // Ptome's: an ISBN (`isbn`) besides the uuid, and editors
    // (`editor`, names separated by semicolons).
    if (isbnUnique) {
      book.addIdentifier(uuid, 'pub-uuid', 'uuid');
    } else if (isbn != null && isbn.isNotEmpty) {
      book.addIdentifier('urn:isbn:$isbn', 'pub-isbn', 'isbn');
    }
    for (final editor in (node.attr('editor') ?? '').split(';')) {
      if (editor.trim().isNotEmpty) {
        book.addContributor(_s(editor.trim()), role: 'edt');
      }
    }

    var publisher = node.attr('publisher');
    if (publisher == null || publisher.isEmpty) {
      publisher = node.attr('producer');
    }
    if (publisher != null && publisher.isNotEmpty) {
      book.setText('publisher', publisher);
    }

    if (node.hasAttr('reproducible')) {
      book.lastModified('1970-01-01T00:00:00Z');
    } else {
      final revdate = node.attr('revdate');
      String? date;
      if (revdate != null) {
        date = rubyTimeParseUtc(revdate);
        if (date == null) {
          logger.error(
            '${_basename(_s(node.attr('docfile')))}: failed to parse '
            'revdate: no time information in "$revdate"',
          );
        }
      }
      date ??= rubyTimeParseUtc(_s(node.attr('docdatetime')));
      if (date != null) book.setDate(date);
      final modified = rubyTimeParseUtc(_s(node.attr('localdatetime')));
      if (modified != null) book.lastModified(modified);
    }

    if (node.attr('description') case final description?) {
      book.setText('description', description);
    }
    if (node.attr('source') case final source?) {
      book.setText('source', source);
    }
    if (node.attr('copyright') case final rights?) {
      book.setText('rights', rights);
    }

    for (final keyword in _s(
      node.attr('keywords', ''),
    ).split(_csvDelimitedRx)) {
      if (keyword.isNotEmpty) book.addMetadata('subject', keyword);
    }

    if (node.attr('series-name') case final seriesName?) {
      final volume = _s(node.attr('series-volume', '1'));
      final seriesId = node.attr('series-id');
      final series = book.addMetadata('meta', seriesName, id: 'pub-collection')
        ..refine('group-position', volume);
      series.attributes['property'] = 'belongs-to-collection';
      if (seriesId != null) series.refine('dcterms:identifier', seriesId);
      series.refine('collection-type', 'series');
    }

    final landmarks = <({String type, String href, String title})>[];

    final frontCover = _addCoverPage(node, 'front-cover');
    if (frontCover != null) {
      landmarks.add((
        type: 'cover',
        href: frontCover.href,
        title: 'Front Cover',
      ));
    }

    final frontMatter = _addFrontMatterPage(node);
    if (frontMatter != null) {
      landmarks.add((
        type: 'frontmatter',
        href: frontMatter.href,
        title: 'Front Matter',
      ));
    }

    final navItem = book.addItem('nav.xhtml', id: 'nav')..addProperty('nav');

    final toclevels = _nonNegative(_toInt(node.attr('toclevels', '1')));
    final outlinelevels = _nonNegative(
      _toInt(node.attr('outlinelevels', '$toclevels')),
    );

    EpubItem? tocItem;
    if (node.hasAttr('toc')) {
      tocItem = book.addOrderedItem('toc.xhtml', id: 'toc');
      landmarks.add((type: 'toc', href: tocItem.href, title: _tocTitle(node)));
    }

    final List<AbstractBlock> tocItems;
    if (node.doctype == 'book') {
      tocItems = node.sections;
      node.content();
    } else {
      tocItems = [node];
      _addChapter(node);
    }

    _addCoverPage(node, 'back-cover');

    if (tocItems.isNotEmpty) {
      // The first chapter after the front matter (a dedication, a
      // colophon, a preface...), else the first.
      const front = {
        'abstract',
        'acknowledgments',
        'colophon',
        'dedication',
        'preface',
      };
      final body = tocItems.firstWhere(
        (item) => !front.contains(item is Section ? item.sectname : item.style),
        orElse: () => tocItems[0],
      );
      landmarks.add((
        type: 'bodymatter',
        href: '${_s(chapterFilename(body))}.xhtml',
        title: 'Start of Content',
      ));
    }

    for (final item in tocItems) {
      // (A section left out of the contents is left out here too.)
      if (item.hasOption('notoc')) continue;
      // (A special section by its section name: `[index]`, `[colophon]`;
      // the front and back matter as landmarks too.)
      final style = switch (item) {
        Section(:final sectname?)
            when const {
              'index',
              'colophon',
              'dedication',
              'acknowledgments',
            }.contains(sectname) =>
          sectname,
        _ => item.style,
      };
      if (const [
        'acknowledgments',
        'appendix',
        'bibliography',
        'colophon',
        'dedication',
        'glossary',
        'index',
        'preface',
      ].contains(style)) {
        landmarks.add((
          type: style!,
          href: '${_s(chapterFilename(item))}.xhtml',
          title: _s(item.title),
        ));
      }
    }

    navItem.setText(_navDoc(node, tocItems, landmarks, outlinelevels));
    tocItem?.setText(_navDoc(node, tocItems, const [], toclevels));

    book
        .addItem('toc.ncx', id: 'ncx')
        .setText(_ncxDoc(node, tocItems, outlinelevels));

    var docimagesdir = _chompSlash(_s(node.attr('imagesdir', '.')));
    docimagesdir = docimagesdir == '.' ? '' : '$docimagesdir/';

    for (final MapEntry(key: name, value: file) in _mediaFiles.entries) {
      final path = file.path;
      if (name.startsWith('${docimagesdir}jacket/cover.')) {
        logger.warn(
          'path is reserved for cover artwork: $name; skipping file found '
          'in content',
        );
      } else if (path == null || io.isReadable(path)) {
        final item = book.addItem(
          name,
          mediaType: _mediaTypeFor(name, file.mediaType),
        );
        if (path != null) item.setBytes(io.readBytes(path));
      } else {
        logger.error(
          '${_basename(_s(node.attr('docfile')))}: media file not found or '
          'not readable: $path',
        );
      }
    }

    _addThemeAssets(node);
    if (node.doctype != 'book') {
      final username = node.attr('username');
      _addProfileImages(node, [?username]);
    }
    return '';
  }

  /// The document's title, sanitized as [spec] asks.
  static String _sanitizeDoctitle(Document doc, _Spec spec) =>
      _sanitizeXml(_s(doc.doctitle(useFallback: true)), spec);

  static String _sanitizeXml(String text, _Spec spec) {
    var content = text;
    if (spec != _Spec.pcdata && content.contains('<')) {
      content = content.replaceAll(_xmlElementRx, '').trim();
      if (content.contains(' ')) content = _squeezeSpaces(content);
    }
    switch (spec) {
      case _Spec.attributeCdata:
        if (content.contains('"')) content = content.replaceAll('"', '&quot;');
      case _Spec.cdata || _Spec.pcdata:
        break;
      case _Spec.plainText:
        if (content.contains(';')) {
          if (content.contains('&#')) {
            content = content.replaceAllMapped(
              _charEntityRx,
              (m) => String.fromCharCode(int.parse(m[1]!)),
            );
          }
          content = _fromHtmlSpecialChars(content);
        }
    }
    return content;
  }

  /// Adds the chapter file for [node] (a document or chapter section) to
  /// the book; returns `null` when [node] isn't a chapter.
  EpubItem? _addChapter(AbstractBlock node) {
    final filename = chapterFilename(node);
    if (filename == null) return null;
    final book = _book!;
    final chapterItem = book.addOrderedItem('$filename.xhtml');

    final document = _doc(node);
    final doctitle = document.partitionedTitle(useFallback: true);
    var chapterTitle = doctitle?.combined ?? '';

    String? title;
    String? subtitle;
    if (node is Document && (doctitle?.hasSubtitle ?? false)) {
      title = '${doctitle!.main} ';
      subtitle = doctitle.subtitle;
    } else if (node.title != null) {
      title = '';
      subtitle = numberedTitle(node);
      chapterTitle = subtitle;
    }

    final String byline;
    if (document.doctype == 'book') {
      byline = '';
    } else {
      final author = node.attr('author');
      final username = _s(node.attr('username', 'default'));
      var imagesdir = _chompSlash(_s(document.attr('imagesdir', '.')));
      imagesdir = imagesdir == '.' ? '' : '$imagesdir/';
      byline =
          '<p class="byline"><img src="${imagesdir}avatars/$username.jpg"/> '
          '<b class="author">${_s(author)}</b></p>$_lf';
    }

    if (document.doctype != 'book') _markLastParagraph(node);

    _xrefsSeen.clear();
    final savedChapter = _chapterFile;
    _chapterFile = '$filename.xhtml';
    var content = _s(node.content());
    _chapterFile = savedChapter;
    if (node is Section) content = _withIndex(node, content, node);

    final String iconCssHead;
    if (_iconNames.isEmpty) {
      iconCssHead = '';
    } else {
      final defs = [
        for (final name in _iconNames)
          '.i-$name::before { content: "${_iconContent(name)}"; }',
      ].join(_lf);
      iconCssHead = '<style>\n$defs\n</style>\n';
    }

    final small = subtitle != null
        ? '<small class="subtitle">$subtitle</small>'
        : '';
    final header = title != null || subtitle != null
        ? '<header class="chapter-header">\n'
              '$byline<h1 class="chapter-title">${_s(title)}$small'
              '</h1>\n</header>'
        : '';

    // The index's anchors in the title belong to the heading alone (the
    // title element allows no markup; an id must be unique).
    chapterTitle = chapterTitle.replaceAll(_indexAnchorRx, '');
    final lang = _s(document.attr('lang', 'en'));
    final head =
        "<?xml version='1.0' encoding='utf-8'?>\n"
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" '
        'xmlns:mml="http://www.w3.org/1998/Math/MathML" '
        'xml:lang="$lang" lang="$lang">\n'
        '<head>\n'
        '<title>$chapterTitle</title>\n'
        '$_stylesheetLinks\n'
        '$iconCssHead${_codeOverflowCss(document)}'
        '${_hyphensCss(document)}$_readingSystemScript';
    final lines = <String>[head];

    final syntaxHl = document.syntaxHighlighter;
    if (syntaxHl is HighlightJsHighlighter) {
      // highlight.js: the code highlighted already, its theme's stylesheet
      // in the EPUB (Ptome's; the gem links them outside it).
      if (syntaxHl.canHighlight) {
        lines.add(
          '<link rel="stylesheet" type="text/css" '
          'href="styles/highlightjs.css"/>',
        );
      }
    } else if (syntaxHl != null && syntaxHl.hasDocinfo('head')) {
      lines.add(
        syntaxHl.docinfo(
          'head',
          document,
          cdnBaseUrl: _cdnBaseUrl(document),
          linkcss: true,
          selfClosingTagSlash: '/',
        ),
      );
    }
    final headDocinfo = document.docinfo('head', '-epub.html');
    if (headDocinfo.isNotEmpty) lines.add(headDocinfo);

    lines.add('</head>\n<body>\n');

    final headerDocinfo = document.docinfo('header', '-epub.html');
    if (headerDocinfo.isNotEmpty) lines.add(headerDocinfo);

    lines.add(
      '\n<section class="chapter" title=${_xmlAttr(chapterTitle)} '
      'id="$filename">\n'
      '$header\n'
      '        $content',
    );

    final footnotes = [
      for (final footnote in document.footnotes)
        if (!_footnotes.contains(footnote)) footnote,
    ];
    if (footnotes.isNotEmpty) {
      _footnotes.addAll(footnotes);
      lines.add('<footer class="chapter-footer">\n<div class="footnotes">');
      for (final footnote in footnotes) {
        lines.add(
          '<aside id="note-${footnote.index}" epub:type="footnote">\n'
          '<p>${_noteLabel(document, footnote)}${footnote.text}</p>\n'
          '</aside>',
        );
      }
      lines.add('</div>\n</footer>');
    }

    lines.add('</section>');

    if (syntaxHl != null &&
        syntaxHl is! HighlightJsHighlighter &&
        syntaxHl.hasDocinfo('footer')) {
      lines.add(
        syntaxHl.docinfo(
          'footer',
          document,
          cdnBaseUrl: _cdnBaseUrl(document),
          linkcss: true,
          selfClosingTagSlash: '/',
        ),
      );
    }
    final footerDocinfo = document.docinfo('footer', '-epub.html');
    if (footerDocinfo.isNotEmpty) lines.add(footerDocinfo);

    lines.add('</body>\n</html>');

    // Well-formed, where AsciiDoc markup leaves it broken (Ptome's).
    final text = balanceXml(lines.join(_lf));
    chapterItem.setText(text);
    // MathML in a content document is declared (EPUB 3; the gem doesn't,
    // and EPUBCheck reports it).
    if (text.contains('<mml:math')) chapterItem.addProperty('mathml');
    if (_epubProperties[node]?.contains('svg') ?? false) {
      chapterItem.addProperty('svg');
    }
    return chapterItem;
  }

  static String _cdnBaseUrl(Document document) {
    final scheme = _s(document.attr('asset-uri-scheme', 'https'));
    return '${scheme.isEmpty ? '' : '$scheme:'}//cdnjs.cloudflare.com/ajax/libs';
  }

  /// The `epub-properties` the gem records on a chapter (the chapter has
  /// SVG images).
  final Expando<List<String>> _epubProperties = Expando<List<String>>();

  /// Converts [node]: adds its chapter, or returns its markup inside the
  /// chapter of a section above it.
  String convertSection(Section node) {
    if (_addChapter(node) != null) return '';
    final level = node.level ?? 0;
    final hlevel = level.clamp(1, 6);
    final sectname = node.sectname;
    final epubTypeAttr = sectname == 'section'
        ? ''
        : ' epub:type="${_s(sectname)}"';
    final divClasses = ['sect$level', ?node.role];
    final title = numberedTitle(node);
    final content = _withIndex(
      node,
      _s(node.content()),
      _enclosingChapter(node),
    );
    return '<section class="${divClasses.join(' ')}" title=${_xmlAttr(title)}'
        '$epubTypeAttr>\n'
        '<h$hlevel id="${_s(node.id)}">$title</h$hlevel>'
        '${content.isEmpty ? '' : '\n          $content'}\n'
        '</section>';
  }

  /// Converts the preamble: its chapter, or its abstract.
  String convertPreamble(Block node) {
    if (_addChapter(node) != null) return '';
    final blocks = node.blocks;
    final first = blocks.isEmpty ? null : blocks[0];
    if (first != null && (first.style == 'abstract' || blocks.length == 1)) {
      return convertAbstract(first);
    }
    return _s(node.content());
  }

  /// Converts the [node] open block.
  String convertOpen(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : null;
    final classAttr = node.role != null ? ' class="${node.role}"' : null;
    if (idAttr != null || classAttr != null) {
      return '<div${_s(idAttr)}${_s(classAttr)}>\n${_outputContent(node)}\n</div>';
    }
    return _outputContent(node);
  }

  /// Converts the [node] abstract.
  String convertAbstract(AbstractBlock node) =>
      '<div class="abstract" epub:type="preamble">\n'
      '${_outputContent(node)}\n'
      '</div>';

  /// Converts the [node] paragraph block.
  String convertParagraph(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final role = node.role;
    final headStop = node.attr(
      'head-stop',
      role != null && node.hasRole('stack-head') ? null : '.',
    );
    var head = '';
    if (node.hasTitle) {
      final title = _s(node.title);
      final stop = headStop != null && !_trailingPunctRx.hasMatch(title)
          ? headStop
          : '';
      head = '<strong class="head">$title$stop</strong> ';
    }
    if (role != null) {
      if (node.hasRole('signature')) node.setOption('hardbreaks');
      return '<p$idAttr class="$role">$head${_s(node.content())}</p>';
    }
    return '<p$idAttr>$head${_s(node.content())}</p>';
  }

  /// Converts the [node] pass block.
  String convertPass(Block node) {
    final content = _s(node.content());
    return content == '<?hard-pagebreak?>'
        ? '<hr epub:type="pagebreak" class="pagebreak"/>'
        : content;
  }

  /// Converts the [node] admonition block.
  String convertAdmonition(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final String titleAttr;
    final String titleEl;
    if (node.hasTitle) {
      final title = _s(node.title);
      titleAttr = ' title="${_s(node.caption)}: ${_xmlSanitize(title)}"';
      titleEl = '<h2>$title</h2>\n';
    } else {
      titleAttr = ' title="${_s(node.caption)}"';
      titleEl = '';
    }
    final type = node.attr('name');
    final String epubType;
    switch (type) {
      case 'tip':
        epubType = 'tip';
      case 'important' || 'warning' || 'caution' || 'note':
        epubType = 'notice';
      default:
        logger.warn('unknown admonition type: ${_s(type)}');
        epubType = 'notice';
    }
    final role = node.role;
    return '<aside$idAttr class="admonition ${_s(type)}'
        '${role != null ? ' $role' : ''}"$titleAttr epub:type="$epubType">\n'
        '$titleEl<div class="content">\n'
        '${_outputContent(node)}\n'
        '</div>\n'
        '</aside>';
  }

  /// Converts the [node] example block.
  String convertExample(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final titleDiv = node.hasTitle
        ? '<div class="example-title">${node.captionedTitle()}</div>'
        : '';
    return '<div$idAttr class="example">\n'
        '$titleDiv<div class="example-content">\n'
        '${_outputContent(node)}\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] floating title block.
  String convertFloatingTitle(Block node) {
    final tagName = 'h${(node.level ?? 0) + 1}';
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = ['discrete', ?node.role].join(' ');
    return '<$tagName$idAttribute class="$classes">'
        '${_s(node.title)}</$tagName>';
  }

  /// Converts the [node] listing block.
  String convertListing(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final document = _doc(node);
    final nowrap = node.hasOption('nowrap') || !document.hasAttr('prewrap');
    String? lang;
    SyntaxHighlighterBase? syntaxHl;
    var opts = const FormatOptions();
    var preOpen = '';
    var preClose = '';
    if (node.style == 'source') {
      lang = node.attr('language');
      syntaxHl = document.syntaxHighlighter;
      if (syntaxHl != null) {
        final docAttrs = document.attributes;
        opts = syntaxHl.canHighlight
            ? FormatOptions(
                nowrap: nowrap,
                cssMode: docAttrs['${syntaxHl.name}-css'] == 'style'
                    ? CssMode.inline
                    : CssMode.classes,
                style: docAttrs['${syntaxHl.name}-style'],
              )
            : FormatOptions(nowrap: nowrap);
      } else {
        final langAttrs = lang != null
            ? ' class="language-$lang" data-lang="$lang"'
            : '';
        preOpen =
            '<pre class="highlight${nowrap ? ' nowrap' : ''}"><code$langAttrs>';
        preClose = '</code></pre>';
      }
    } else {
      preOpen = '<pre${nowrap ? ' class="nowrap"' : ''}>';
      preClose = '</pre>';
    }
    final figureClasses = [
      'listing',
      if (node.hasOption('unbreakable')) 'coalesce',
    ];
    final titleDiv = node.hasTitle
        ? '<figcaption>${node.captionedTitle()}</figcaption>'
        : '';
    final body = syntaxHl != null
        ? syntaxHl.format(node, lang, opts)
        : '$preOpen${_s(node.content())}$preClose';
    return '<figure$idAttribute class="${figureClasses.join(' ')}">$titleDiv\n'
        '        $body\n'
        '</figure>';
  }

  /// A STEM block: AsciiMath as MathML (Ptome's port of the
  /// asciimath gem, ADR-0014, as the gem writes it with asciimath
  /// installed), other math as a listing.
  String convertStem(Block node) {
    if (node.style != 'asciimath') return convertListing(node);
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<figcaption>${node.captionedTitle()}</figcaption>'
        : '';
    return '<figure$idAttr class="${_prependSpace(node.role)}">\n'
        '$titleElement\n'
        '<div class="content">\n'
        '${asciimathToMathml(_s(node.content()), prefix: 'mml:')}\n'
        '</div>\n'
        '</figure>';
  }

  /// Converts the [node] literal block.
  String convertLiteral(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<figcaption>${node.captionedTitle()}</figcaption>'
        : '';
    final role = _prependSpace(node.role);
    return '<figure$idAttribute class="literalblock$role">\n'
        '$titleElement\n'
        '<div class="content"><pre class="screen">${_s(node.content())}</pre></div>\n'
        '</figure>';
  }

  /// Converts the [node] quote block.
  String convertQuote(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final role = node.role;
    final classAttr = role != null
        ? ' class="blockquote $role"'
        : ' class="blockquote"';
    final footerContent = <String>[];
    if (node.attr('attribution') case final attribution?) {
      footerContent.add(attribution);
    }
    if (node.attr('citetitle') case final citetitle?) {
      footerContent.add(
        '<cite title="${_xmlSanitize(citetitle)}">$citetitle</cite>',
      );
    }
    if (node.hasTitle) {
      footerContent.add('<span class="context">${_s(node.title)}</span>');
    }
    final footerTag = footerContent.isEmpty
        ? ''
        : '\n<footer>~ ${footerContent.join(' ')}</footer>';
    final content = _outputContent(node).trim();
    return '<div$idAttr$classAttr>\n'
        '<blockquote>\n'
        '$content$footerTag\n'
        '</blockquote>\n'
        '</div>';
  }

  /// Converts the [node] verse block.
  String convertVerse(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final role = node.role;
    final classAttr = role != null ? ' class="verse $role"' : ' class="verse"';
    final footerContent = <String>[];
    if (node.attr('attribution') case final attribution?) {
      footerContent.add(attribution);
    }
    if (node.attr('citetitle') case final citetitle?) {
      footerContent.add(
        '<cite title="${_xmlSanitize(citetitle)}">$citetitle</cite>',
      );
    }
    final footerTag = footerContent.isEmpty
        ? ''
        : '\n<span class="attribution">~ ${footerContent.join(', ')}</span>';
    return '<div$idAttr$classAttr>\n'
        '<pre>${_s(node.content())}$footerTag</pre>\n'
        '</div>';
  }

  /// Converts the [node] sidebar block.
  String convertSidebar(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = ['sidebar'];
    var titleAttr = '';
    var titleEl = '';
    if (node.hasTitle) {
      classes.add('titled');
      final title = _s(node.title);
      titleAttr = ' title="${_xmlSanitize(title)}"';
      titleEl = '<h2>$title</h2>\n';
    }
    return '<aside$idAttribute class="${classes.join(' ')}"$titleAttr '
        'epub:type="sidebar">\n'
        '$titleEl<div class="content">\n'
        '${_outputContent(node)}\n'
        '</div>\n'
        '</aside>';
  }

  /// Converts the [node] table.
  String convertTable(Table node) {
    final lines = <String>['<div class="table">', '<div class="content">'];
    final tableIdAttr = node.id != null ? ' id="${node.id}"' : '';
    final tableClasses = [
      'table',
      'table-framed-${_s(node.attr('frame', 'rows', 'table-frame'))}',
      'table-grid-${_s(node.attr('grid', 'rows', 'table-grid'))}',
      ?node.role,
      ?node.attr('float'),
    ];
    final tableStyles = <String>[];
    final autowidth = node.hasOption('autowidth');
    if (autowidth && !node.hasAttr('width')) {
      tableClasses.add('fit-content');
    } else {
      tableStyles.add('width: ${_s(node.attr('tablepcwidth'))}%;');
    }
    final tableClassAttr = ' class="${tableClasses.join(' ')}"';
    final tableStyleAttr = tableStyles.isEmpty
        ? ''
        : ' style="${tableStyles.join('; ')}"';

    lines.add('<table$tableIdAttr$tableClassAttr$tableStyleAttr>');
    if (node.hasTitle) {
      lines.add('<caption>${node.captionedTitle()}</caption>');
    }
    if (_toInt(_s(node.attr('rowcount'))) > 0) {
      lines.add('<colgroup>');
      if (autowidth) {
        lines.addAll(List.filled(node.columns.length, '<col/>'));
      } else {
        for (final col in node.columns) {
          lines.add(
            col.hasOption('autowidth')
                ? '<col/>'
                : '<col style="width: ${_s(col.attr('colpcwidth'))}%;" />',
          );
        }
      }
      lines.add('</colgroup>');
      final document = _doc(node);
      for (final (tsec, rows) in [
        ('head', node.rows.head),
        ('body', node.rows.body),
        ('foot', node.rows.foot),
      ]) {
        if (rows.isEmpty) continue;
        lines.add('<t$tsec>');
        for (final row in rows) {
          lines.add('<tr>');
          for (final cell in row) {
            final String cellContent;
            if (tsec == 'head') {
              cellContent = _s(cell.text);
            } else {
              switch (cell.style) {
                case 'asciidoc':
                  if (cell.innerDocument case final inner?) {
                    _parentCell[inner] = cell;
                  }
                  cellContent =
                      '<div class="embed">${_s(cell.content())}</div>';
                case 'verse':
                  cellContent = '<div class="verse">${_s(cell.text)}</div>';
                case 'literal':
                  cellContent =
                      '<div class="literal"><pre>${_s(cell.text)}</pre></div>';
                default:
                  cellContent = [
                    for (final text in cell.paragraphs)
                      '<p class="tableblock">$text</p>',
                  ].join();
              }
            }
            final cellTagName = tsec == 'head' || cell.style == 'header'
                ? 'th'
                : 'td';
            final cellClassAttr =
                ' class="halign-${_s(cell.attr('halign'))} '
                'valign-${_s(cell.attr('valign'))}"';
            final colspanAttr = cell.colspan != null
                ? ' colspan="${cell.colspan}"'
                : '';
            final rowspanAttr = cell.rowspan != null
                ? ' rowspan="${cell.rowspan}"'
                : '';
            final styleAttr = document.hasAttr('cellbgcolor')
                ? ' style="background-color: ${document.attr('cellbgcolor')}"'
                : '';
            lines.add(
              '<$cellTagName$cellClassAttr$colspanAttr$rowspanAttr$styleAttr>'
              '$cellContent</$cellTagName>',
            );
          }
          lines.add('</tr>');
        }
        lines.add('</t$tsec>');
      }
    }
    lines.add('</table>\n</div>\n</div>');
    return lines.join(_lf);
  }

  /// Converts the [node] colist.
  String convertColist(ListBlock node) {
    final lines = <String>['<div class="callout-list">\n<ol>'];
    var num = _calloutStart;
    var i = 0;
    for (final item in node.items) {
      lines.add(
        '<li>${calloutBack(item, '<i class="conum" data-value="${i + 1}">'
        '${String.fromCharCode(num)}</i>')} '
        '${calloutItemAnchors(item)}${_s(item.text)}'
        '${item.hasBlocks ? _s(item.content()) : ''}</li>',
      );
      num += 1;
      i += 1;
    }
    lines.add('</ol>\n</div>');
    // The gem returns the array of lines, which the content around it
    // flattens with newlines.
    return lines.join(_lf);
  }

  /// Converts the [node] dlist.
  String convertDlist(ListBlock node) {
    final lines = <String>[];
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final style = node.style;
    final classes = switch (style) {
      'horizontal' => ['hdlist', ?node.role],
      'itemized' || 'ordered' => ['dlist', '$style-list', ?node.role],
      _ => ['description-list'],
    };
    lines.add('<div$idAttribute class="${classes.join(' ')}">');
    if (node.hasTitle) {
      lines.add('<div class="list-heading">${_s(node.title)}</div>');
    }

    switch (style) {
      case 'itemized' || 'ordered':
        final listTagName = style == 'itemized' ? 'ul' : 'ol';
        final role = node.role;
        final subjectStop = node.attr(
          'subject-stop',
          role != null && node.hasRole('stack') ? null : ':',
        );
        final listClassAttr = node.hasOption('brief') ? ' class="brief"' : '';
        final reversedAttr = listTagName == 'ol' && node.hasOption('reversed')
            ? ' reversed="reversed"'
            : '';
        lines.add('<$listTagName$listClassAttr$reversedAttr>');
        for (final DlistEntry(:terms, description: dd) in node.entries) {
          final subject = _s(terms.first.text);
          final subjectPlain = _xmlSanitize(subject, _Target.plain);
          final stop =
              subjectStop != null && !_trailingPunctRx.hasMatch(subjectPlain)
              ? subjectStop
              : '';
          final subjectElement =
              '<strong class="subject">$subject$stop</strong>';
          lines.add('<li>');
          if (dd != null) {
            final supporting = dd.hasText
                ? ' <span class="supporting">${_s(dd.text)}</span>'
                : '';
            lines.add(
              '<span class="principal">$subjectElement$supporting</span>',
            );
            if (dd.hasBlocks) lines.add(_s(dd.content()));
          } else {
            lines.add('<span class="principal">$subjectElement</span>');
          }
          lines.add('</li>');
        }
        lines.add('</$listTagName>');
      case 'horizontal':
        lines.add('<table>');
        if (node.hasAttr('labelwidth') || node.hasAttr('itemwidth')) {
          lines.add('<colgroup>');
          String widthStyle(String name) => node.hasAttr(name)
              ? ' style="width: ${_chompPercent(_s(node.attr(name)))}%;"'
              : '';
          final labelwidth = widthStyle('labelwidth');
          lines.add('<col$labelwidth />');
          final itemwidth = widthStyle('itemwidth');
          lines
            ..add('<col$itemwidth />')
            ..add('</colgroup>');
        }
        for (final DlistEntry(:terms, description: dd) in node.entries) {
          lines
            ..add('<tr>')
            ..add(
              '<td class="hdlist1'
              '${node.hasOption('strong') ? ' strong' : ''}">',
            );
          var firstTerm = true;
          for (final dt in terms) {
            if (!firstTerm) lines.add('<br />');
            lines
              ..add('<p>')
              ..add(_s(dt.text))
              ..add('</p>');
            firstTerm = false;
          }
          lines
            ..add('</td>')
            ..add('<td class="hdlist2">');
          if (dd != null) {
            if (dd.hasText) lines.add('<p>${_s(dd.text)}</p>');
            if (dd.hasBlocks) lines.add(_s(dd.content()));
          }
          lines
            ..add('</td>')
            ..add('</tr>');
        }
        lines.add('</table>');
      default:
        lines.add('<dl>');
        for (final DlistEntry(:terms, description: dd) in node.entries) {
          for (final dt in terms) {
            lines.add('<dt>\n<span class="term">${_s(dt.text)}</span>\n</dt>');
          }
          if (dd == null) continue;
          lines.add('<dd>');
          if (dd.hasBlocks) {
            if (dd.hasText) {
              lines.add('<span class="principal">${_s(dd.text)}</span>');
            }
            lines.add(_s(dd.content()));
          } else {
            lines.add('<span class="principal">${_s(dd.text)}</span>');
          }
          lines.add('</dd>');
        }
        lines.add('</dl>');
    }
    lines.add('</div>');
    return lines.join(_lf);
  }

  /// Converts the [node] olist.
  String convertOlist(ListBlock node) =>
      _convertList(node, 'ordered-list', 'ol');

  /// Converts the [node] ulist.
  String convertUlist(ListBlock node) =>
      _convertList(node, 'itemized-list', 'ul');

  String _convertList(ListBlock node, String divClass, String tag) {
    var complex = false;
    final divClasses = [divClass, ?node.style, ?node.role];
    final listClasses = [?node.style, if (node.hasOption('brief')) 'brief'];
    final listClassAttr = listClasses.isEmpty
        ? ''
        : ' class="${listClasses.join(' ')}"';
    final startAttr = tag == 'ol' && node.hasAttr('start')
        ? ' start="${node.attr('start')}"'
        : '';
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final lines = <String>['<div$idAttribute class="${divClasses.join(' ')}">'];
    if (node.hasTitle) {
      lines.add('<div class="list-heading">${_s(node.title)}</div>');
    }
    final reversedAttr = tag == 'ol' && node.hasOption('reversed')
        ? ' reversed="reversed"'
        : '';
    lines.add('<$tag$listClassAttr$startAttr$reversedAttr>');
    for (final item in node.items) {
      final liClassAttr = item.role != null ? ' class="${item.role}"' : '';
      lines.add(
        '<li$liClassAttr>\n<span class="principal">${_s(item.text)}</span>',
      );
      if (item.hasBlocks) {
        lines.add(_s(item.content()));
        if (!(item.blocks.length == 1 && item.blocks[0] is ListBlock)) {
          complex = true;
        }
      }
      lines.add('</li>');
    }
    if (complex) {
      divClasses.add('complex');
      lines[0] = '<div class="${divClasses.join(' ')}">';
    }
    lines.add('</$tag>\n</div>');
    return lines.join(_lf);
  }

  /// Records the media file [target] of [node] for the manifest.
  void _registerMediaFile(AbstractNode node, String target, String mediaType) {
    if (target.endsWith('.svg') || target.startsWith('data:image/svg+xml')) {
      final chapter = _enclosingChapter(node);
      if (chapter != null) {
        final properties = _epubProperties[chapter] ??= [];
        if (!properties.contains('svg')) properties.add('svg');
      }
    }
    if (target.startsWith('data:')) return;
    String? fsPath;
    if (!Helpers.isUriish(target)) {
      final outDir = node.attr('outdir', null, 'outdir') ?? _toDir(_doc(node));
      fsPath = _join(_s(outDir), target);
      if (!io.exists(fsPath)) {
        fsPath = _join(_rootDocument(_doc(node)).baseDir, target);
      }
    }
    _mediaFiles.putIfAbsent(target, () => (path: fsPath, mediaType: mediaType));
  }

  static String? _toDir(Document document) {
    for (Document? doc = document; doc != null; doc = doc.parentDocument) {
      final value = doc.options.toDir;
      if (value != null) return value;
    }
    return null;
  }

  static Document _rootDocument(Document document) {
    var doc = document;
    for (var parent = doc.parentDocument; parent != null;) {
      doc = parent;
      parent = doc.parentDocument;
    }
    return doc;
  }

  /// The attributes of an image: `alt`, and the width as a style for a
  /// scaled or percent width.
  List<String> _imageAttrs(AbstractNode node, String alt) {
    final attrs = <String>[];
    final encodedAlt = alt.replaceAll('"', '&quot;');
    if (encodedAlt.isNotEmpty) attrs.add('alt="$encodedAlt"');
    if (node.attr('scaledwidth') case final scaledwidth?) {
      attrs.add('style="width: $scaledwidth"');
    } else if (node.attr('width') case final width?) {
      // XHTML takes a number of pixels (Ptome leaves out any other
      // value, which the gem writes and EPUBCheck rejects).
      if (RegExp(r'^\d+%$').hasMatch(width)) {
        attrs.add('style="width: $width"');
      } else if (RegExp(r'^\d+$').hasMatch(width)) {
        attrs.add('width="$width"');
      }
    }
    return attrs;
  }

  String _timeAnchor(AbstractNode node) {
    final start = node.attr('start');
    final end = node.attr('end');
    if (start == null && end == null) return '';
    return '#t=${_s(start)}${end != null ? ',$end' : ''}';
  }

  /// Converts the [node] audio block.
  String convertAudio(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final target = node.mediaUri(_s(node.attr('target')));
    _registerMediaFile(node, target, 'audio');
    final titleElement = node.hasTitle
        ? '\n<figcaption>${node.captionedTitle()}</figcaption>'
        : '';
    final autoplay = node.hasOption('autoplay') ? ' autoplay="autoplay"' : '';
    final controls = node.hasOption('nocontrols') ? '' : ' controls="controls"';
    final loop = node.hasOption('loop') ? ' loop="loop"' : '';
    return '<figure$idAttr class="audioblock${_prependSpace(node.role)}">'
        '$titleElement\n'
        '<div class="content">\n'
        '<audio src="$target${_timeAnchor(node)}"$autoplay$controls$loop>\n'
        '<div>Your Reading System does not support (this) audio.</div>\n'
        '</audio>\n'
        '</div>\n'
        '</figure>';
  }

  /// Converts the [node] video block.
  String convertVideo(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final target = node.mediaUri(_s(node.attr('target')));
    _registerMediaFile(node, target, 'video');
    final titleElement = node.hasTitle
        ? '\n<figcaption>${node.captionedTitle()}</figcaption>'
        : '';
    final width = node.hasAttr('width') ? ' width="${node.attr('width')}"' : '';
    final height = node.hasAttr('height')
        ? ' height="${node.attr('height')}"'
        : '';
    final autoplay = node.hasOption('autoplay') ? ' autoplay="autoplay"' : '';
    final controls = node.hasOption('nocontrols') ? '' : ' controls="controls"';
    final loop = node.hasOption('loop') ? ' loop="loop"' : '';
    var posterAttr = '';
    final poster = node.attr('poster');
    if (poster != null && poster.isNotEmpty) {
      final posterUri = node.mediaUri(poster);
      _registerMediaFile(node, posterUri, 'image');
      posterAttr = ' poster="$posterUri"';
    }
    return '<figure$idAttr class="video${_prependSpace(node.role)}'
        '${_prependSpace(node.attr('float'))}">$titleElement\n'
        '<div class="content">\n'
        '<video src="$target${_timeAnchor(node)}"$width$height$autoplay'
        '$posterAttr$controls$loop>\n'
        '<div>Your Reading System does not support (this) video.</div>\n'
        '</video>\n'
        '</div>\n'
        '</figure>';
  }

  /// Converts the [node] image block.
  String convertImage(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '\n<figcaption>${node.captionedTitle()}</figcaption>'
        : '';
    // A text file (ASCII art) as its text, not an image a reader can't
    // show (Ptome's own output; the file isn't packed).
    if (_textImage(node) case final text?) {
      return '<figure$idAttr class="image text${_prependSpace(node.role)}'
          '${_prependSpace(node.attr('float'))}">\n'
          '<div class="content">\n'
          '<pre>$text</pre>\n'
          '</div>$titleElement\n'
          '</figure>';
    }
    final target = node.imageUri(_s(node.attr('target')));
    _registerMediaFile(node, target, 'image');
    final imgAttrs = _imageAttrs(node, node.alt);
    return '<figure$idAttr class="image${_prependSpace(node.role)}'
        '${_prependSpace(node.attr('float'))}">\n'
        '<div class="content">\n'
        '<img src="$target"${_prependSpace(imgAttrs.join(' '))} />\n'
        '</div>$titleElement\n'
        '</figure>';
  }

  /// A `toc::[]` macro (Ptome's): the book's contents where it is, as
  /// the navigation document lists them (to `toclevels`, or the macro's
  /// `levels`), linked to the chapters.
  String convertToc(Block node) {
    final doc = _doc(node);
    final levels = _nonNegative(
      _toInt(node.attr('levels') ?? doc.attr('toclevels', '1')),
    );
    final items = doc.doctype == 'book' ? doc.sections : <AbstractBlock>[doc];
    final list = _navLevel(items, levels, _NavState());
    if (list.isEmpty) return '';
    return '<nav class="toc"${node.id == null ? '' : ' id="${node.id}"'}>\n'
        '$list\n'
        '</nav>';
  }

  /// The text of image [node] when its target is a text file
  /// (`image::diagram.txt[]`, or `format=txt`), escaped; else null.
  String? _textImage(Block node) {
    final target = _s(node.attr('target'));
    final isText =
        node.attr('format') == 'txt' ||
        (!node.hasAttr('format') && target.toLowerCase().endsWith('.txt'));
    if (!isText) return null;
    final text = node.readContents(
      target,
      start: node.document!.attr('imagesdir'),
      label: 'text image',
    );
    return text
        ?.replaceAll(RegExp(r'\r?\n$'), '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// With `:hyphens:` (as the PDF reads it), the text hyphenated by the
  /// reading system, in the book's language.
  static String _hyphensCss(Document document) => document.hasAttr('hyphens')
      ? '<style>\nbody p, li, dd { -webkit-hyphens: auto; hyphens: auto; }\n'
            '</style>\n'
      : '';

  /// With `ebook-code-overflow=scroll` (Ptome's), code lines keep
  /// their length and scroll sideways rather than wrap (the stylesheet's
  /// default).
  static String _codeOverflowCss(Document document) =>
      document.attr('ebook-code-overflow') == 'scroll'
      ? '<style>\npre { white-space: pre; overflow-wrap: normal; '
            'overflow-x: auto; }\n</style>\n'
      : '';

  /// The title of the table of contents: `toc-title`, or Asciidoctor's
  /// default when the document empties it (an empty heading and landmark
  /// aren't valid EPUB).
  static String _tocTitle(Document document) =>
      switch (document.attr('toc-title')) {
        final String title when title.isNotEmpty => title,
        _ => 'Table of Contents',
      };

  /// An index term: its text when visible, and where the document has an
  /// index, an anchor the index links to.
  String _indexterm(Inline node) {
    final visible = node.type == 'visible';
    final anchor = _doc(node).catalog.index
        .add(node, visible ? [_s(node.text)] : node.terms ?? const []);
    final target = anchor == null ? '' : '<a id="$anchor"></a>';
    return visible ? '$target${_s(node.text)}' : target;
  }

  /// [content] of the section [node], followed by the document's index
  /// when [node] is its index section (in the chapter [chapter]).
  String _withIndex(Section node, String content, AbstractNode? chapter) {
    final document = _doc(node);
    final index = document.catalog.index;
    if (node.sectname != 'index' || !index.isActive) return content;
    final here = chapter == null ? null : chapterFilename(chapter);
    final html = indexHtml(
      index,
      level: node.level ?? 1,
      epub: true,
      codePoint: indexInCodePointOrder(document),
      headings: indexHasCategoryHeadings(document),
      label: (section) => indexUseLabel(section, document),
      href: (use) {
        final file = switch (_enclosingChapter(use.node)) {
          final AbstractNode chapter => chapterFilename(chapter),
          null => null,
        };
        return file == null || file == here
            ? '#${use.anchor}'
            : '$file.xhtml#${use.anchor}';
      },
    );
    return content.isEmpty ? html : '$content\n$html';
  }

  /// The chapter [start] is in (through the table cell an AsciiDoc cell's
  /// document is in).
  AbstractNode? _enclosingChapter(AbstractNode? start) {
    var node = start;
    while (node != null) {
      if (chapterFilename(node) != null) return node;
      final cell = node is Document ? _parentCell[node] : null;
      node = cell ?? node.parent;
    }
    return null;
  }

  /// Converts the [node] inline anchor.
  String? convertInlineAnchor(Inline node) {
    switch (node.type) {
      case 'xref':
        final doc = _doc(node);
        final refid = node.attr('refid');
        var target = node.target;
        var text = node.text;
        var idAttr = '';
        final path = node.attributes['path'];
        if (path != null) {
          text = node.text ?? path;
        } else if (refid == '#') {
          logger.warn(
            '${_basename(_s(doc.attr('docfile')))}: <<chapter#>> xref syntax '
            "isn't supported anymore. Use either <<chapter>> or "
            '<<chapter#anchor>>',
          );
        } else if (refid != null) {
          final ref = doc.catalog.refs[refid];
          final ourChapter = _enclosingChapter(node);
          final refChapter = _enclosingChapter(ref);
          if (refChapter != null) {
            final refDocname = chapterFilename(refChapter);
            if (identical(refChapter, ourChapter)) {
              idAttr = ' id="xref-$refid"';
              target = '#$refid';
            } else if (refid == refDocname) {
              idAttr = ' id="xref--$refid"';
              target = '$refid.xhtml';
            } else {
              idAttr = ' id="xref--$refDocname--$refid"';
              target = '$refDocname.xhtml#$refid';
            }
            if (!_xrefsSeen.add(refid)) idAttr = '';
            text ??= switch (ref) {
              final AbstractBlock block => block.xreftext(
                node.attr('xrefstyle', null, 'xrefstyle'),
              ),
              final Inline inline => inline.xreftext(
                node.attr('xrefstyle', null, 'xrefstyle'),
              ),
              _ => null,
            };
          } else {
            logger.warn(
              '${_basename(_s(doc.attr('docfile')))}: invalid reference to '
              'unknown anchor: $refid',
            );
          }
        }
        return '<a$idAttr href="${_s(target)}" class="xref">'
            '${text ?? '[${_s(refid)}]'}</a>';
      case 'ref':
        return '<a id="${_s(node.target ?? node.id)}"></a>';
      case 'link':
        final target = _s(node.target);
        // A path from a website's root (`/chapter/#id`) means nothing in
        // the book: it goes to the id when the book has it, else it is
        // text (Ptome's; the gem's link leaves the container).
        if (target.startsWith('/') && !target.startsWith('//')) {
          final hash = target.indexOf('#');
          final id = hash < 0 ? null : target.substring(hash + 1);
          final ref = id == null ? null : _doc(node).catalog.refs[id];
          final chapter = ref == null ? null : _enclosingChapter(ref);
          final file = chapter == null ? null : chapterFilename(chapter);
          if (file == null) return _s(node.text);
          return '<a href="$file.xhtml#$id" class="link">${_s(node.text)}</a>';
        }
        return '<a href="$target" class="link">${_s(node.text)}</a>';
      case 'bibref':
        var reftext = node.reftext;
        if (reftext != null) {
          if (!reftext.startsWith('[')) reftext = '[$reftext]';
        } else {
          reftext = '[${_s(node.target ?? node.id)}]';
        }
        return '<a id="${_s(node.target ?? node.id)}"></a>$reftext';
      default:
        logger.warn('unknown anchor type: :${_s(node.type)}');
        return null;
    }
  }

  /// Converts the [node] inline callout.
  String convertInlineCallout(Inline node) {
    final number = _toInt(_s(node.text));
    return calloutLink(
      node,
      '<i class="conum" data-value="$number">'
      '${String.fromCharCode(_calloutStart + number - 1)}</i>',
    );
  }

  /// The label before footnote [footnote]'s text: `footnote-label-template`
  /// (ADR-0010) when [document] sets it, none by default (as the gem).
  static String _noteLabel(Document document, Footnote footnote) =>
      switch (document.attr('footnote-label-template')) {
        final template? => renderNumbered(template, footnote.index, (n) => n),
        null => '',
      };

  /// Converts the [node] inline footnote.
  String? convertInlineFootnote(Inline node) {
    final index = node.attr('index');
    if (index != null) {
      final idAttr = node.id != null ? ' id="${node.id}"' : '';
      // `footnote-reference-template` (ADR-0010), `[1]` by default.
      final marker = renderNumbered(
        node.document?.attr('footnote-reference-template') ?? '[{{number}}]',
        index,
        (n) => '<a$idAttr href="#note-$index" epub:type="noteref">$n</a>',
      );
      return '<sup class="noteref">$marker</sup>';
    }
    if (node.type == 'xref') {
      return '<mark class="noteref" title="Unresolved note reference">'
          '${_s(node.text)}</mark>';
    }
    return null;
  }

  /// Converts the [node] inline image.
  String convertInlineImage(Inline node) {
    if (node.type == 'icon') {
      final iconName = _s(node.target);
      _iconNames.add(iconName);
      final classes = [
        'icon',
        'i-$iconName',
        if (node.attr('size') case final size?) 'icon-$size',
        if (node.attr('flip') case final flip? when flip.isNotEmpty)
          'icon-flip-${flip[0]}',
        if (node.attr('rotate') case final rotate?) 'icon-rotate-$rotate',
        ?node.role,
        ?node.attr('float'),
      ];
      return '<i class="${classes.join(' ')}"></i>';
    }
    final target = node.imageUri(_s(node.target));
    _registerMediaFile(node, target, 'image');
    final imgAttrs = _imageAttrs(node, node.alt)
      ..add(
        'class="inline${_prependSpace(node.role)}'
        '${_prependSpace(node.attr('float'))}"',
      );
    return '<img src="$target"${_prependSpace(imgAttrs.join(' '))}/>';
  }

  /// Converts the [node] inline kbd.
  String convertInlineKbd(Inline node) {
    final keys = node.keys ?? const <String>[];
    if (keys.length == 1) return '<kbd>${keys[0]}</kbd>';
    return '<span class="keyseq">'
        '${[for (final key in keys) '<kbd>$key</kbd>'].join('+')}</span>';
  }

  /// Converts the [node] inline menu.
  String convertInlineMenu(Inline node) {
    final menu = _s(node.attr('menu'));
    const caret = '$_noBreakSpace<span class="caret">$_rightAngleQuote</span> ';
    final submenus = node.submenus ?? const <String>[];
    if (submenus.isNotEmpty) {
      final path = [
        for (final submenu in submenus)
          '<span class="submenu">$submenu</span>$caret',
      ].join();
      final submenuPath = path.substring(0, path.length - 1);
      return '<span class="menuseq"><span class="menu">$menu</span>$caret'
          '$submenuPath <span class="menuitem">'
          '${_s(node.attr('menuitem'))}</span></span>';
    }
    if (node.attr('menuitem') case final menuitem?) {
      return '<span class="menuseq"><span class="menu">$menu</span>$caret'
          '<span class="menuitem">$menuitem</span></span>';
    }
    return '<span class="menu">$menu</span>';
  }

  /// Converts the [node] inline quoted.
  String convertInlineQuoted(Inline node) {
    final type = _s(node.type);
    final (open, close, isTag) = _quoteTags[type] ?? ('', '', false);
    final content = type == 'asciimath'
        ? asciimathToMathml(_s(node.text), prefix: 'mml:')
        : _s(node.text);
    if (type == 'monospaced' || type == 'asciimath' || type == 'latexmath') {
      node.addRole('literal');
    }
    final role = node.role;
    final classAttr = role != null ? ' class="$role"' : '';
    if (node.id != null) {
      if (isTag) {
        return '${open.substring(0, open.length - 1)} id="${node.id}"'
            '$classAttr>$content$close';
      }
      return '<span id="${node.id}"$classAttr>$open$content$close</span>';
    }
    if (role != null) {
      if (isTag) {
        return '${open.substring(0, open.length - 1)}$classAttr>$content$close';
      }
      return '<span$classAttr>$open$content$close</span>';
    }
    return '$open$content$close';
  }

  /// The content of [node], in a paragraph for simple content. A list's
  /// content is its markup: the gem interpolates a Ruby list's items
  /// (`List#content` is its array of items) and writes their object dump.
  String _outputContent(AbstractBlock node) {
    if (node is ListBlock) return _s(node.convert());
    return node.contentModel == ContentModel.simple
        ? '<p>${_s(node.content())}</p>'
        : _s(node.content());
  }

  /// Marks the last paragraph of [root] (through trailing sections) with
  /// the `last` role.
  static void _markLastParagraph(AbstractBlock root) {
    if (root.blocks.isEmpty) return;
    var last = root.blocks.last;
    while (last.context == BlockContext.section && last.blocks.isNotEmpty) {
      last = last.blocks.last;
    }
    if (last.context == BlockContext.paragraph) {
      final role = last.role;
      last.attributes['role'] = role != null ? '$role last' : 'last';
    }
  }

  void _addThemeAssets(Document doc) {
    final book = _book!;
    if (doc.attr('epub3-stylesdir') case final stylesdir?) {
      // Stylesheets of a custom theme are read as CSS: the gem compiles
      // SCSS when it converts, which needs a Sass compiler.
      final docdir = _s(doc.attr('docdir', '.'));
      final dir = stylesdir.startsWith('/')
          ? stylesdir
          : _join(docdir.isEmpty ? '.' : docdir, stylesdir);
      for (final name in ['epub3', 'epub3-css3-only']) {
        final css = _join(dir, '$name.css');
        if (io.isReadable(css)) {
          book.addItem('styles/$name.css').setBytes(io.readBytes(css));
        } else {
          logger.error(
            'epub3-stylesdir: $css not found or not readable (the stylesheets '
            'of a custom theme must be compiled to CSS)',
          );
          book.addItem('styles/$name.css').setText(_asset('styles/$name.css'));
        }
      }
    } else {
      // asciidoctor-epub3's stylesheet, then Ptome's house rules
      // (ADR-0011), unless the document asks for asciidoctor-epub3's alone
      // (`epub3-stylesheet=asciidoctor-epub3`).
      final classic =
          doc.attr('epub3-stylesheet') == 'asciidoctor-epub3' ||
          asciidoctorCompat(doc, CompatFormat.epub);
      for (final name in ['epub3', 'epub3-css3-only']) {
        final css = _asset('styles/$name.css');
        book
            .addItem('styles/$name.css')
            .setText(
              [
                css,
                if (name == 'epub3' && !classic) _houseRules,
                if (!_embedFonts) _withoutIconFonts[name],
              ].nonNulls.join('\n'),
            );
      }
    }

    if (doc.syntaxHighlighter case final HighlightJsHighlighter highlighter
        when highlighter.canHighlight) {
      book
          .addItem('styles/highlightjs.css')
          .setText(
            highlightJsStyles[doc.attr('highlightjs-theme')] ??
                highlightJsStyles['github']!,
          );
    }

    var fontCss = _asset('styles/epub3-fonts.css');
    final scripts = _s(doc.attr('scripts', 'latin'));
    if (scripts != 'latin') {
      fontCss = fontCss.replaceAll(RegExp(r'(?<=-)latin(?=\.ttf\))'), scripts);
    }
    if (!_embedFonts) {
      // The reader's fonts (`epub-embed-fonts` embeds the stylesheet's).
      book.addItem('styles/epub3-fonts.css').setText(_noFontsCss);
      return;
    }
    final (css, fontFiles) = _embeddableFonts(fontCss);
    book.addItem('styles/epub3-fonts.css').setText(css);
    if (fontFiles.isNotEmpty) {
      book.addOptionalFile(
        'META-INF/com.apple.ibooks.display-options.xml',
        '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<display_options>\n'
            '<platform name="*">\n'
            '<option name="specified-fonts">true</option>\n'
            '</platform>\n'
            '</display_options>',
      );
      final fonts = Fonts.current;
      for (final (name, path) in fontFiles) {
        book.addItem(name).setBytes(fonts.fontBytes(path));
      }
    }
  }

  /// Whether the stylesheet's fonts are embedded (`epub-embed-fonts`):
  /// otherwise the book names fonts and the reading system chooses.
  bool _embedFonts = false;

  /// The stylesheet of the fonts when none is embedded.
  static const String _noFontsCss =
      "/* No fonts are embedded: the reading system's apply (the "
      'epub-embed-fonts attribute embeds them). */\n';

  /// What shows icon [name]: its glyph (a CSS escape) when the icon font
  /// is embedded, else its name in brackets.
  String _iconContent(String name) =>
      _embedFonts ? _iconUnicode(name) : '[$name]';

  /// Rules that show the stylesheet's font icons as text when no icon font
  /// is embedded (a box would show in their place): no admonition or
  /// end-of-chapter icon, a quotation mark and a caret in the text's font.
  static const Map<String, String> _withoutIconFonts = {
    'epub3':
        '/* No icon font is embedded. */\n'
        'aside.admonition::before,p.last::after{content:none}'
        'blockquote>p:first-of-type::before{font-family:inherit;'
        r'content:"\201C"}'
        r'.menuseq .caret::before{font-family:inherit;content:"\203A"}',
    'epub3-css3-only':
        '/* No icon font is embedded. */\n'
        '.icon{font-family:inherit !important}',
  };

  /// Families the stylesheet names whose fonts may be installed under
  /// other names (M+ 1mn's successor M PLUS 1 Code; Font Awesome 5's solid
  /// style for 6's).
  static const Map<String, List<(String, bool)>> _fontAliases = {
    'm+ 1p': [('M PLUS 1p', false)],
    'm+ 1p light': [('M+ 1p', false), ('M PLUS 1p', false)],
    'm+ 1p bold': [('M+ 1p', true), ('M PLUS 1p', true)],
    'm+ 1mn': [('M PLUS 1 Code', false)],
    'font awesome 6 free solid': [
      ('Font Awesome 6 Free', true),
      ('Font Awesome 5 Free', true),
    ],
    'fonticons': [('Font Awesome 6 Free', true), ('Font Awesome 5 Free', true)],
  };

  /// The rules of [css] (`@font-face` rules) whose fonts are installed,
  /// and each embedded file's name in the book and installed path: by the
  /// file's name, then by the rule's family and style. A rule whose font
  /// isn't installed is left out, said once.
  (String, List<(String, String)>) _embeddableFonts(String css) {
    final installed = Fonts.current;
    final kept = <String>[];
    final files = <(String, String)>[];
    for (final rule in RegExp(r'@font-face\{[^}]*\}').allMatches(css)) {
      final text = rule[0]!;
      final url = RegExp(r'url\(\.\./([^)]+)\)').firstMatch(text)?[1];
      final family = RegExp('font-family:"([^"]+)"').firstMatch(text)?[1];
      if (url == null || family == null) continue;
      final bold = RegExp('font-weight:(bold|[6-9]00)').hasMatch(text);
      final italic = text.contains('font-style:italic');
      final name = url.substring(url.lastIndexOf('/') + 1);
      var path = installed.fileNamed(name);
      for (final (alias, aliasBold) in [
        (family, bold),
        ...?_fontAliases[family.toLowerCase()],
      ]) {
        if (path != null) break;
        final font = installed.find(
          alias,
          bold: aliasBold || bold,
          italic: italic,
        );
        if (font != null && font.italic == italic) path = font.path;
      }
      if (path == null) {
        if (_missingFonts.add(family)) {
          logger.warn(
            'font $family is not installed: not embedded in the EPUB '
            "(`ptome doctor` installs the default themes' fonts)",
          );
        }
        continue;
      }
      kept.add(text);
      files.add((url, path));
    }
    return (kept.join(), files);
  }

  /// The families found missing (said once each).
  final Set<String> _missingFonts = {};

  static String _asset(String path) => Epub3Assets.text(path) ?? '';

  /// Ptome's house rules for the EPUB (doc/style.md).
  static String get _houseRules =>
      EmbeddedData.file('stylesheets/ptome-epub3-house.css');

  /// Adds the cover page [name] (`front-cover`, `back-cover`) for the
  /// `<name>-image` attribute.
  EpubItem? _addCoverPage(Document doc, String name) {
    final imageAttrName = '$name-image';
    var imagePath = doc.attr(imageAttrName);
    if (imagePath == null) return null;
    var imagesdir = _chompSlash(_s(doc.attr('imagesdir', '.')));
    imagesdir = imagesdir == '.' ? '' : '$imagesdir/';

    final imageAttrs = <String, String>{};
    if (imagePath.contains(':')) {
      if (_imageMacroRx.firstMatch(imagePath) case final match?) {
        if (imagePath.startsWith('image::')) {
          logger.warn(
            'deprecated block macro syntax detected in :$imageAttrName: '
            'attribute',
          );
        }
        imagePath = '$imagesdir${match[1]}';
        if (match[2]!.isNotEmpty) {
          AttributeList(match[2]!)
              .parseInto(imageAttrs, ['alt', 'width', 'height']);
        }
      }
    }

    final imageHref = '${imagesdir}jacket/$name${_extnameOf(imagePath)}';
    var workdir = _s(doc.attr('docdir'));
    if (workdir.isEmpty) workdir = '.';
    final file = imagePath.startsWith('/')
        ? imagePath
        : _join(workdir, imagePath);
    final book = _book!;
    if (!io.isReadable(file)) {
      logger.error(
        '${_basename(_s(doc.attr('docfile')))}: error adding cover image. '
        'Make sure that :$imageAttrName: attribute points to a valid image '
        'file. No such file or directory @ rb_sysopen - $file',
      );
      return null;
    }
    book.addItem(imageHref)
      ..setBytes(io.readBytes(file))
      ..addProperty('cover-image');

    var width = imageAttrs['width'];
    var height = imageAttrs['height'];
    if (imageAttrs.isEmpty || width == null || height == null) {
      width = '1050';
      height = '1600';
    }

    final content =
        "<?xml version='1.0' encoding='utf-8'?>\n"
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">\n'
        '<head>\n'
        '<title>${_sanitizeDoctitle(doc, _Spec.cdata)}</title>\n'
        '<style type="text/css">\n'
        '@page {\n'
        '  margin: 0;\n'
        '}\n'
        'html {\n'
        '  margin: 0 !important;\n'
        '  padding: 0 !important;\n'
        '}\n'
        'body {\n'
        '  margin: 0;\n'
        '  padding: 0 !important;\n'
        '  text-align: center;\n'
        '}\n'
        'body > svg {\n'
        '  /* prevent bleed onto second page (removes descender space) */\n'
        '  display: block;\n'
        '}\n'
        '</style>\n'
        '</head>\n'
        '<body epub:type="cover"><svg version="1.1" '
        'xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink"\n'
        '  width="100%" height="100%" viewBox="0 0 $width $height" '
        'preserveAspectRatio="xMidYMid meet">\n'
        '<image width="$width" height="$height" xlink:href="$imageHref"/>\n'
        '</svg></body>\n'
        '</html>';

    book.prefixes['calibre'] = 'https://calibre-ebook.com';
    return book.addOrderedItem('$name.xhtml', id: name)
      ..setText(content)
      ..addProperty('calibre:title-page');
  }

  List<String> _frontMatterFiles(Document doc, String workdir) {
    if (doc.attr('epub3-frontmatterdir') case final fmdir?) {
      final dir = _join(workdir, fmdir);
      if (!io.isDirectory(dir)) {
        logger.warn(
          "${_basename(_s(doc.attr('docfile')))}: directory specified by "
          "'epub3-frontmattderdir' doesn't exist! Ignoring ...",
        );
        return [];
      }
      final names = [
        for (final entry in io.listDirectory(dir))
          if (RegExp(r'front-matter.*\.html').hasMatch(entry.name)) entry.name,
      ]..sort();
      if (names.isEmpty) {
        logger.warn(
          "${_basename(_s(doc.attr('docfile')))}: directory specified by "
          "'epub3-frontmattderdir' contains no suitable files! Ignoring ...",
        );
        return [];
      }
      return [for (final name in names) _join(dir, name)];
    }
    final single = _join(workdir, 'front-matter.html');
    return io.exists(single) ? [single] : [];
  }

  EpubItem? _addFrontMatterPage(Document doc) {
    var workdir = _s(doc.attr('docdir'));
    if (workdir.isEmpty) workdir = '.';
    EpubItem? result;
    final book = _book!;
    for (final frontMatter in _frontMatterFiles(doc, workdir)) {
      final content = utf8.decode(io.readBytes(frontMatter));
      final name = _basename(frontMatter).replaceFirst(RegExp(r'\.html$'), '');
      final item = book.addOrderedItem('$name.xhtml')..setText(content);
      if (_svgImgSniffRx.hasMatch(content)) item.addProperty('svg');
      result ??= item;
      for (final match in _imageSrcScanRx.allMatches(content)) {
        final src = match[1]!;
        final path = _join(_dirname(frontMatter), src);
        final image = book.addItem(src);
        if (io.isReadable(path)) image.setBytes(io.readBytes(path));
      }
    }
    return result;
  }

  void _addProfileImages(Document doc, List<String> usernames) {
    var imagesdir = _chompSlash(_s(doc.attr('imagesdir', '.')));
    imagesdir = imagesdir == '.' ? '' : '$imagesdir/';
    final book = _book!;
    final defaultAvatar = Epub3Assets.bytes('images/default-avatar.jpg')!;
    final defaultHeadshot = Epub3Assets.bytes('images/default-headshot.jpg')!;
    book
      ..addItem('${imagesdir}avatars/default.jpg').setBytes(defaultAvatar)
      ..addItem('${imagesdir}headshots/default.jpg').setBytes(defaultHeadshot);

    var workdir = _s(doc.attr('docdir'));
    if (workdir.isEmpty) workdir = '.';
    for (final username in usernames) {
      final avatar = '${imagesdir}avatars/$username.jpg';
      final resolvedAvatar = _join(workdir, avatar);
      if (io.isReadable(resolvedAvatar)) {
        book.addItem(avatar).setBytes(io.readBytes(resolvedAvatar));
      } else {
        logger.error(
          'avatar for $username not found or readable: $avatar; falling back '
          'to default avatar',
        );
        book.addItem(avatar).setBytes(defaultAvatar);
      }
      final headshot = '${imagesdir}headshots/$username.jpg';
      final resolvedHeadshot = _join(workdir, headshot);
      if (io.isReadable(resolvedHeadshot)) {
        book.addItem(headshot).setBytes(io.readBytes(resolvedHeadshot));
      } else if (doc.hasAttr('builder', 'editions')) {
        logger.error(
          'headshot for $username not found or readable: $headshot; falling '
          'back to default headshot',
        );
        book.addItem(headshot).setBytes(defaultHeadshot);
      }
    }
  }

  String _navDoc(
    Document doc,
    List<AbstractBlock> items,
    List<({String type, String href, String title})> landmarks,
    int levels,
  ) {
    final lang = _s(doc.attr('lang', 'en'));
    final head =
        "<?xml version='1.0' encoding='utf-8'?>\n"
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$lang" '
        'lang="$lang">\n'
        '<head>\n'
        '<title>${_sanitizeDoctitle(doc, _Spec.cdata)}</title>\n'
        '$_stylesheetLinks\n'
        '</head>\n'
        '<body>\n'
        '<section class="chapter">\n'
        '<header class="chapter-header">\n'
        '<h1 class="chapter-title"><small class="subtitle">'
        '${_tocTitle(doc)}</small></h1>\n'
        '</header>\n'
        '<nav epub:type="toc" id="toc">';
    final lines = <String>[
      head,
      _navLevel(items, levels, _NavState()),
      '</nav>',
    ];
    if (landmarks.isNotEmpty) {
      lines.add(
        '\n<nav epub:type="landmarks" id="landmarks" hidden="hidden">\n<ol>',
      );
      for (final landmark in landmarks) {
        lines.add(
          '<li><a epub:type="${landmark.type}" href="${landmark.href}">'
          '${landmark.title}</a></li>',
        );
      }
      lines.add('\n</ol>\n</nav>');
      // The print edition's pages (`epub-page-map`).
      if (_pageList.isNotEmpty) {
        lines.add(
          '\n<nav epub:type="page-list" id="page-list" hidden="hidden">\n<ol>',
        );
        for (final (href, label) in _pageList) {
          lines.add('<li><a href="$href">$label</a></li>');
        }
        lines.add('\n</ol>\n</nav>');
      }
    }
    lines.add('\n</section>\n</body>\n</html>');
    return lines.join(_lf);
  }

  String _navLevel(List<AbstractBlock> items, int levels, _NavState state) {
    var lines = <String>[];
    for (final item in items) {
      if ((item.level ?? 0) > levels) continue;
      // Ptome's `notoc` option: a section left out of the contents.
      if (item.hasOption('notoc')) continue;
      final chapterFile = chapterFilename(item);
      final String itemLabel;
      final String itemHref;
      if (chapterFile == null) {
        itemLabel = _sanitizeXml(numberedTitle(item), _Spec.pcdata);
        itemHref = '${_s(state.contentDocHref)}#${_s(item.id)}';
      } else {
        itemLabel = item is Document
            ? _sanitizeDoctitle(item, _Spec.cdata)
            : _sanitizeXml(numberedTitle(item), _Spec.cdata);
        itemHref = state.contentDocHref = '$chapterFile.xhtml';
      }
      lines.add('<li><a href="$itemHref">$itemLabel</a>');
      final children = item.sections;
      if (children.isEmpty) {
        lines.last = '${lines.last}</li>';
      } else {
        lines
          ..add(_navLevel(children, levels, state))
          ..add('</li>');
      }
      if (chapterFile != null) state.contentDocHref = null;
    }
    if (lines.isNotEmpty) lines = ['<ol>', ...lines, '</ol>'];
    return lines.join(_lf);
  }

  String _ncxDoc(Document doc, List<AbstractBlock> items, int levels) {
    final state = _NavState();
    final level = _ncxLevel(items, levels, state);
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" '
        'xml:lang="${_s(doc.attr('lang', 'en'))}">\n'
        '<head>\n'
        '<meta name="dtb:uid" content="${_s(_book!.identifier)}"/>\n'
        '<meta name="dtb:depth" content="${state.maxDepth}"/>\n'
        '<meta name="dtb:totalPageCount" content="0"/>\n'
        '<meta name="dtb:maxPageNumber" content="0"/>\n'
        '</head>\n'
        '<docTitle><text>${_sanitizeDoctitle(doc, _Spec.cdata)}</text></docTitle>\n'
        '<navMap>\n'
        '$level\n'
        '</navMap>\n'
        '</ncx>';
  }

  String _ncxLevel(List<AbstractBlock> items, int levels, _NavState state) {
    final lines = <String>[];
    state.maxDepth += 1;
    for (final item in items) {
      if ((item.level ?? 0) > levels) continue;
      final index = state.index += 1;
      final chapterFile = chapterFilename(item);
      final String itemLabel;
      final String itemHref;
      if (chapterFile == null) {
        itemLabel = _sanitizeXml(numberedTitle(item), _Spec.cdata);
        itemHref = '${_s(state.contentDocHref)}#${_s(item.id)}';
      } else {
        itemLabel = item is Document
            ? _sanitizeDoctitle(item, _Spec.cdata)
            : _sanitizeXml(numberedTitle(item), _Spec.cdata);
        itemHref = state.contentDocHref = '$chapterFile.xhtml';
      }
      lines
        ..add('<navPoint id="nav_$index" playOrder="$index">')
        ..add('<navLabel><text>$itemLabel</text></navLabel>')
        ..add('<content src="$itemHref"/>');
      final children = item.sections;
      if (children.isNotEmpty) lines.add(_ncxLevel(children, levels, state));
      lines.add('</navPoint>');
      if (chapterFile != null) state.contentDocHref = null;
    }
    return lines.join(_lf);
  }

  @override
  Uint8List? get output => _book == null ? null : Uint8List.fromList(package());

  /// The EPUB file for the last converted document.
  List<int> package() => (_book ?? (throw StateError('no document converted')))
      .zip(deflate: io.deflateRaw, deflated: _deflated);

  /// Compresses the book's files on other cores, when the conversion is
  /// awaited.
  @override
  Future<void> finish() async {
    final book = _book;
    final parallel = _parallel;
    if (book == null || parallel == null) return;
    final files = book.files();
    final deflated = <String, List<int>>{};
    await Future.wait([
      for (final MapEntry(key: path, value: bytes) in files.entries)
        if (path != 'mimetype')
          parallel
              .submit(_Deflate(Uint8List.fromList(bytes)))
              .then<void>(
                (result) => deflated[path] = result,
                // (Compressed when packaged, then.)
                onError: (Object _) {},
              ),
    ]);
    _deflated = deflated;
  }

  /// Writes the EPUB to [path] (see [package]); also extracts it next to
  /// [path] with `ebook-extract`, and checks it with EPUBCheck with
  /// `ebook-validate`.
  @override
  void write(String path) {
    io.writeBytes(path, package());
    if (_extract) {
      final dir = path.replaceFirst(_epubExtensionRx, '');
      for (final MapEntry(key: name, value: bytes) in _book!.files().entries) {
        final file = _join(dir, name);
        io.createDirectories(_dirname(file));
        io.writeBytes(file, bytes);
      }
    }
    if (_validate) _validateEpub(path);
  }

  void _validateEpub(String path) {
    final command =
        _epubcheckPath ?? io.environment['EPUBCHECK'] ?? 'epubcheck';
    final output = io.commandOutput(command, ['-w', path]);
    if (output == null) {
      logger.error(
        'EPUB validation failed: unable to run EPUBCheck ($command); put '
        'epubcheck on the PATH, set the EPUBCHECK environment variable or the '
        'ebook-epubcheck-path attribute',
      );
      return;
    }
    for (final line in const LineSplitter().convert(output)) {
      final text = line.trim();
      if (RegExp('^fatal', caseSensitive: false).hasMatch(text)) {
        logger.fatal(text);
      } else if (RegExp('^error', caseSensitive: false).hasMatch(text)) {
        logger.error(text);
      } else if (RegExp('^warning', caseSensitive: false).hasMatch(text)) {
        logger.warn(text);
      } else if (text.isNotEmpty) {
        logger.info(text);
      }
    }
  }
}

/// Where a navigation list is: the chapter file of the items, the next
/// play order and the depth reached.
final class _NavState {
  String? contentDocHref;
  int index = 0;
  int maxDepth = 0;
}

enum _Spec { attributeCdata, cdata, pcdata, plainText }

enum _Target { attribute, plain }

/// [value] without markup, for an attribute ([_Target.attribute]: quotes
/// escaped) or as plain text ([_Target.plain]: character references
/// resolved).
String _xmlSanitize(String value, [_Target target = _Target.attribute]) {
  var sanitized = value.contains('<')
      ? _squeezeSpaces(value.replaceAll(_xmlElementRx, '').trim())
      : value;
  if (target == _Target.plain && sanitized.contains(';')) {
    if (sanitized.contains('&#')) {
      sanitized = sanitized.replaceAllMapped(
        _charEntityRx,
        (m) => String.fromCharCode(int.parse(m[1]!)),
      );
    }
    sanitized = _fromHtmlSpecialChars(sanitized);
  } else if (target == _Target.attribute && sanitized.contains('"')) {
    sanitized = sanitized.replaceAll('"', '&quot;');
  }
  return sanitized;
}

String _fromHtmlSpecialChars(String value) =>
    value.replaceAllMapped(_fromHtmlSpecialCharsRx, (m) {
      return switch (m[0]) {
        '&lt;' => '<',
        '&gt;' => '>',
        _ => '&',
      };
    });

/// An anchor the index links to, in converted text.
final RegExp _indexAnchorRx = RegExp(r'<a id="_indexterm_\d+"></a>');

/// [value] as a quoted XML attribute value (Ruby's `encode xml: :attr`).
String _xmlAttr(String value) {
  final escaped = value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  return '"$escaped"';
}

/// [value] with runs of spaces squeezed (Ruby's `tr_s ' ', ' '`).
String _squeezeSpaces(String value) => value.replaceAll(RegExp(' {2,}'), ' ');

String _prependSpace(String? value) =>
    value == null || value.isEmpty ? '' : ' $value';

String _chompSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;

String _chompPercent(String value) =>
    value.endsWith('%') ? value.substring(0, value.length - 1) : value;

int _toInt(String? value) =>
    int.tryParse(
      RegExp(r'^\s*[-+]?\d+').stringMatch(value ?? '')?.trim() ?? '',
    ) ??
    0;

int _nonNegative(int value) => value < 0 ? 0 : value;

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  if (slash < 0) return '.';
  return slash == 0 ? '/' : path.substring(0, slash);
}

/// [dir] and [path] joined with one separator (Ruby's `File.join`).
String _join(String dir, String path) {
  var head = dir;
  while (head.length > 1 && head.endsWith('/')) {
    head = head.substring(0, head.length - 1);
  }
  final tail = path.replaceFirst(RegExp('^/+'), '');
  return head == '/' ? '/$tail' : '$head/$tail';
}

String _extnameOf(String path) => extname(path);

/// The media type of a media file of the [mediaType] kind (`image`,
/// `audio`, `video`) named [name], as the mime-types gem gives it; `null`
/// lets the package guess.
String? _mediaTypeFor(String name, String mediaType) {
  final ext = _extnameOf(name).toLowerCase().replaceFirst('.', '');
  final types = _mimeTypes[ext];
  if (types == null) return null;
  for (final type in types) {
    if (type.startsWith('$mediaType/')) return type;
  }
  return null;
}

/// The media types the mime-types gem lists first for the extensions a
/// book's media files have.
const Map<String, List<String>> _mimeTypes = {
  'apng': ['image/apng'],
  'avif': ['image/avif'],
  'bmp': ['image/bmp'],
  'gif': ['image/gif'],
  'ico': ['image/vnd.microsoft.icon'],
  'jpe': ['image/jpeg'],
  'jpeg': ['image/jpeg'],
  'jpg': ['image/jpeg'],
  'png': ['image/png'],
  'svg': ['image/svg+xml'],
  'tif': ['image/tiff'],
  'tiff': ['image/tiff'],
  'webp': ['image/webp'],
  'aac': ['audio/aac'],
  'flac': ['audio/flac'],
  'm4a': ['audio/mp4'],
  'mp3': ['audio/mpeg'],
  'oga': ['audio/ogg'],
  'ogg': ['audio/ogg', 'video/ogg'],
  'opus': ['audio/ogg'],
  'wav': ['audio/wav'],
  'm4v': ['video/mp4'],
  'mov': ['video/quicktime'],
  'mp4': ['video/mp4', 'audio/mp4'],
  'ogv': ['video/ogg'],
  'webm': ['video/webm', 'audio/webm'],
};

/// The Font Awesome code point for [name], as a CSS escape (`\f09b`).
String _iconUnicode(String name) {
  final map = _iconMap;
  final target = map.shims[name] ?? name;
  final code = map.icons[target];
  return code == null ? '' : '\\$code';
}

/// The Font Awesome icons (name to code point) and renamed icons (old name
/// to new), from `icons.tsv`.
final ({Map<String, String> icons, Map<String, String> shims}) _iconMap = () {
  final icons = <String, String>{};
  final shims = <String, String>{};
  final text = Epub3Assets.text('fonts/awesome/icons.tsv')!;
  for (final line in const LineSplitter().convert(text)) {
    switch (line.split('\t')) {
      case ['icon', final name, final code]:
        icons[name] = code;
      case ['shim', final name, final target]:
        shims[name] = target;
    }
  }
  return (icons: icons, shims: shims);
}();

/// Raw DEFLATE of [bytes], as the book's files are compressed.
final class _Deflate extends Job<List<int>> {
  const new(this.bytes);

  final Uint8List bytes;

  @override
  List<int> run() => io.deflateRaw(bytes);
}
