/// The PDF backend (`-b pdf`): converts documents as asciidoctor-pdf
/// 2.3.27 does, with its themes, into libpdf boxes laid out on pages. Text
/// is set by a Prawn-compatible text box ([TextBox]); blocks, page
/// breaks and running content are libpdf's box tree.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/attribute_list.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/compat.dart';
import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/cursor.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/index_catalog.dart' show indexHasCategoryHeadings;
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/list.dart';
import 'package:asciidart/src/math/asciimath.dart';
import 'package:asciidart/src/math/latex.dart';
import 'package:asciidart/src/output_template.dart';
import 'package:asciidart/src/page_map.dart';
import 'package:asciidart/src/parallel.dart';
import 'package:asciidart/src/pdf/fonts.dart';
import 'package:asciidart/src/pdf/highlight_style.dart';
import 'package:asciidart/src/pdf/hyphenate.dart';
import 'package:asciidart/src/pdf/icons.dart';
import 'package:asciidart/src/pdf/index.dart';
import 'package:asciidart/src/pdf/markup.dart';
import 'package:asciidart/src/pdf/math.dart';
import 'package:asciidart/src/pdf/svg_size.dart';
import 'package:asciidart/src/pdf/text_box.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:asciidart/src/section.dart';
import 'package:asciidart/src/table.dart';
import 'package:asciidart/src/timings.dart';
import 'package:libpdf/libpdf.dart';
import 'package:meta/meta.dart';

/// The NUL character the gem puts in empty anchors (zero width).
const String _dummyText = '\u0000';

/// Page sizes by name, in points (Prawn's table).
const Map<String, (double, double)> _pageSizes = {
  '4A0': (4767.87, 6740.79),
  '2A0': (3370.39, 4767.87),
  'A0': (2383.94, 3370.39),
  'A1': (1683.78, 2383.94),
  'A2': (1190.55, 1683.78),
  'A3': (841.89, 1190.55),
  'A4': (595.28, 841.89),
  'A5': (419.53, 595.28),
  'A6': (297.64, 419.53),
  'A7': (209.76, 297.64),
  'A8': (147.4, 209.76),
  'A9': (104.88, 147.4),
  'A10': (73.7, 104.88),
  'B0': (2834.65, 4008.19),
  'B1': (2004.09, 2834.65),
  'B2': (1417.32, 2004.09),
  'B3': (1000.63, 1417.32),
  'B4': (708.66, 1000.63),
  'B5': (498.9, 708.66),
  'B6': (354.33, 498.9),
  'B7': (249.45, 354.33),
  'B8': (175.75, 249.45),
  'B9': (124.72, 175.75),
  'B10': (87.87, 124.72),
  'C0': (2599.37, 3676.54),
  'C1': (1836.85, 2599.37),
  'C2': (1298.27, 1836.85),
  'C3': (918.43, 1298.27),
  'C4': (649.13, 918.43),
  'C5': (459.21, 649.13),
  'C6': (323.15, 459.21),
  'C7': (229.61, 323.15),
  'C8': (161.57, 229.61),
  'C9': (113.39, 161.57),
  'C10': (79.37, 113.39),
  'RA0': (2437.8, 3458.27),
  'RA1': (1729.13, 2437.8),
  'RA2': (1218.9, 1729.13),
  'RA3': (864.57, 1218.9),
  'RA4': (609.45, 864.57),
  'SRA0': (2551.18, 3628.35),
  'SRA1': (1814.17, 2551.18),
  'SRA2': (1275.59, 1814.17),
  'SRA3': (907.09, 1275.59),
  'SRA4': (637.8, 907.09),
  'EXECUTIVE': (521.86, 756.0),
  'FOLIO': (612.0, 936.0),
  'LEGAL': (612.0, 1008.0),
  'LETTER': (612.0, 792.0),
  'TABLOID': (792.0, 1224.0),
};

/// The font settings in effect (the gem's `theme_font` state).
final class _FontState {
  const new({
    required this.family,
    required this.style,
    required this.size,
    required this.color,
    required this.lineHeight,
    this.kerning = true,
    this.transform,
    this.leadingKey,
  });

  final String family;
  final String style;
  final double size;
  final ThemeColor? color;
  final double lineHeight;
  final bool kerning;
  final String? transform;

  /// The theme key of the text's Typst leading (`<category>_leading`), when
  /// its category or one it inherits from sets one (else `base_leading`).
  final String? leadingKey;

  _FontState copyWith({
    String? family,
    String? style,
    double? size,
    ThemeColor? color,
    double? lineHeight,
    bool? kerning,
    String? transform,
  }) => _FontState(
    family: family ?? this.family,
    style: style ?? this.style,
    size: size ?? this.size,
    color: color ?? this.color,
    lineHeight: lineHeight ?? this.lineHeight,
    kerning: kerning ?? this.kerning,
    transform: transform ?? this.transform,
    leadingKey: leadingKey,
  );
}

/// The PDF converter.
final class PdfConverter extends BuiltInConverter
    implements FinishingConverter {
  /// The converter for [backend].
  new(super.backend, [super.opts]) {
    backendTraits = BackendTraits(
      basebackend: 'html',
      filetype: 'pdf',
      outfilesuffix: '.pdf',
      htmlsyntax: 'html',
    );
  }

  @override
  String get converterName => 'PdfConverter';

  Uint8List? _bytes;

  late Theme _theme;
  late FontCatalog _fonts;
  late TextContext _text;
  late MarkupTransform _markup;
  _FontState _font = const _FontState(
    family: 'Helvetica',
    style: 'normal',
    size: 12,
    color: null,
    lineHeight: 1,
  );
  late double _rootFontSize;
  late String _baseTextAlign;
  late List<LayoutBox> _out;
  late Document _document;
  final List<(Section, String)> _sections = [];

  /// Saves the converted document (once its work on other cores is
  /// done, or doing it here).
  Uint8List Function()? _save;

  /// The work on other cores the save waits for.
  final List<Future<void>> _awaiting = [];

  /// The workers the converted document's work runs on, when it is
  /// awaited (the `jobs` attribute: the physical cores by default, `1`
  /// for none).
  Parallel? _parallel;

  /// Called (by tools measuring the work, `tool/spike_chunks.dart`) with
  /// the layout and the boxes the walk made, instead of laying them out.
  @internal
  static void Function(FlowLayout layout, List<LayoutBox> content)? onWalked;

  /// The PDF the last converted document made.
  Uint8List? get bytes => _bytes ??= _save?.call();

  @override
  Uint8List? get output => bytes;

  @override
  Future<void> finish() async {
    await Future.wait(_awaiting);
    _awaiting.clear();
    bytes;
  }

  @override
  void write(String path) {
    final bytes = this.bytes;
    if (bytes == null) throw StateError('no document converted');
    io.writeBytes(path, bytes);
  }

  @override
  String? convertBlock(AbstractBlock node, ConvertOptions? opts) {
    if (node is! Document && node is! Section) {
      final above = _marginAbove(node);
      if (above > 0) _out.add(SpacerBox(above));
    }
    switch (node) {
      case final Document document:
        convertDocument(document);
      case final Section section:
        convertSection(section);
      case final ListBlock list when list.context == BlockContext.ulist:
        convertUlist(list);
      case final ListBlock list when list.context == BlockContext.olist:
        convertOlist(list);
      case final ListBlock list when list.context == BlockContext.dlist:
        convertDlist(list);
      case final ListBlock list when list.context == BlockContext.colist:
        convertColist(list);
      case final Table table:
        convertTable(table);
      case final Block block:
        final context = block.context;
        if (context == BlockContext.paragraph) {
          convertParagraph(block);
        } else if (context == BlockContext.admonition) {
          convertAdmonition(block);
        } else if (context == BlockContext.listing ||
            context == BlockContext.literal) {
          convertCode(block);
        } else if (context == BlockContext.preamble) {
          convertPreamble(block);
        } else if (context == BlockContext.open) {
          convertOpen(block);
        } else if (context == BlockContext.example) {
          convertExample(block);
        } else if (context == BlockContext.sidebar) {
          convertSidebar(block);
        } else if (context == BlockContext.quote ||
            context == BlockContext.verse) {
          convertQuote(block);
        } else if (context == BlockContext.thematicBreak) {
          convertThematicBreak(block);
        } else if (context == BlockContext.pageBreak) {
          convertPageBreak(block);
        } else if (context == BlockContext.image) {
          convertImage(block);
        } else if (context == BlockContext.toc) {
          convertToc(block);
        } else if (context == BlockContext.floatingTitle) {
          convertFloatingTitle(block);
        } else if (context == BlockContext.pass) {
          convertPass(block);
        } else if (context == BlockContext.stem) {
          convertStem(block);
        } else if (context == BlockContext.audio ||
            context == BlockContext.video) {
          convertMedia(block);
        }
      // Other blocks aren't converted yet: they are left out.
      default:
        break;
    }
    return '';
  }

  // Theme values.

  String? _s(String key) => _theme.string(key);
  num? _n(String key) => _theme.number(key);

  /// [key] as a length in points: a number, or in the modern engine also
  /// a multiple of [emSize] (`1.5em`) or of the root font size (`2rem`).
  double? _length(String key, double emSize) => switch (_theme.value(key)) {
    ThemeNumber(:final value) => value.toDouble(),
    ThemeString(:final value) => switch (RegExp(
      r'^(\d+(?:\.\d+)?|\.\d+)(r?em)$',
    ).firstMatch(value)) {
      final m? => double.parse(m[1]!) * (m[2] == 'em' ? emSize : _rootFontSize),
      null => null,
    },
    _ => null,
  };
  ThemeColor? _c(String key) => themeColor(_theme.value(key));

  // The document.

  /// Converts [document] to PDF bytes (kept for [write]); returns nothing.
  String convertDocument(Document document) {
    // The gem converts the title for the document information before its
    // PDF state exists (and the title keeps that conversion).
    _document = document;
    document.doctitle();
    _converting = true;
    _promotePreface(document);
    for (final name in const ['outline', 'outline-title', 'pagenums']) {
      if (document.attributeUnspecified(name)) {
        document.attributes[name] = '';
      }
    }
    _phases = document.timings;
    _bytes = _save = null;
    _awaiting.clear();
    _parallel = workersAwaited
        ? Parallel.forAttribute(document.attr('jobs'))
        : null;
    _phase('pdf walk');
    _theme = _prepareTheme(_loadTheme(document));
    _ready = true;
    _fonts = FontCatalog(
      _theme,
      fontsDir: document
          .attr('pdf-fontsdir')
          ?.replaceAll('{docdir}', document.attr('docdir') ?? ''),
      shaping: _shaping,
      synthesizeFaces: true,
      warn: logger.warn,
    );
    _rootFontSize = (_n('base_font_size') ?? 12).toDouble();
    final (_, pageHeight) = _pageSize(document);
    // The inline images (and why some can't be) are kept: titles are
    // converted while the document is parsed, before this.
    _text = TextContext(
      fonts: _fonts,
      rootSize: _rootFontSize,
      fallbacks: _theme.fontFallbacks,
      images: (src, format) =>
          (_inlineGraphics[src], _imageProblems[src] ?? 'not an image'),
      boundsHeight: pageHeight - _pageMargins(document).vertical,
      decorationWidth: (_n('base_text_decoration_width') ?? 1).toDouble(),
      lineBreaking: switch (_choice('base_line_breaking', const [
        'auto',
        'optimal',
        'greedy',
      ])) {
        'optimal' => LineBreaking.optimal,
        'greedy' => LineBreaking.greedy,
        _ => LineBreaking.auto,
      },
      typographicScripts:
          _theme.value('base_typographic_scripts') == const ThemeBool(true),
      labels: (key) => _layoutLabels[key],
      logger: logger,
    );
    _markup = MarkupTransform(
      theme: _theme,
      invertEmphasis: _invertEmphasis,
      keepIndexSpace: true,
    );
    _cjkLineBreaks = document.attr('scripts') == 'cjk';
    _resolveHyphenation(document);
    _reportTags =
        (document.hasAttr('pdf-layout-report') ||
            document.hasAttr('pdf-page-map'))
        ? {}
        : null;
    _baseTextAlign = switch (document.attr('text-align')) {
      final align?
          when const {'justify', 'left', 'center', 'right'}.contains(align) =>
        align,
      _ => _s('base_text_align') ?? 'left',
    };
    _font = _FontState(
      family: _s('base_font_family') ?? 'Helvetica',
      style: _fontStyle(_s('base_font_style')) ?? 'normal',
      size: _rootFontSize,
      color: _c('base_font_color'),
      lineHeight: (_n('base_line_height') ?? 1).toDouble(),
      kerning: _s('base_font_kerning') != 'none',
    );
    _sections.clear();
    _floatGroup = _floatNext = null;
    _hasTitlePage = _frontCover = _backCover = _noCover = false;
    _runningBackgrounds.clear();
    _importedPages.clear();
    _layout = _initialLayout(document);
    _indexSlot = null;
    _renderedFootnotes.clear();
    _bibrefRefs.clear();
    _footnoteLabels.clear();
    _out = [];

    // The document title, on a page of its own or above the content.
    final book = document.doctype == 'book';
    final media = document.attr('media') ?? 'screen';
    _ppbook = media == 'prepress' && book;
    _folio = switch (document.attr('pdf-folio-placement') ??
        (media == 'prepress' ? 'physical' : 'virtual')) {
      'physical' => (physical: true, inverted: false),
      'physical-inverted' => (physical: true, inverted: true),
      'virtual-inverted' => (physical: false, inverted: true),
      _ => (physical: false, inverted: false),
    };
    final titlePage = book || document.hasAttr('title-page');
    _frontCover = _cover('front');
    if (titlePage &&
        document.hasHeader &&
        !document.notitle &&
        _theme['title_page'] is! ThemeBool) {
      if (_ppbook) _out.add(const BreakBox.page(side: PageSide.recto));
      _titlePage(document);
      _out.add(const BreakBox.page());
      _hasTitlePage = true;
    }
    if (!titlePage) _out.add(_bodyMarker());
    if (!titlePage && document.hasHeader && !document.notitle) {
      final title = document.doctitle();
      if (title != null) {
        _heading(
          title,
          level: 1,
          align: _s('heading_h1_text_align') ?? 'center',
        );
      }
    }
    final placement = document.attr('toc-placement');
    final tocAtTop =
        document.hasAttr('toc') &&
        placement != 'macro' &&
        placement != 'preamble' &&
        _sectionsOf(document).isNotEmpty;
    _tocAtTop = tocAtTop;
    _tocDone = false;
    _tocNoHeader = _tocNoFooter = false;
    _notes.clear();
    _layoutLabels.clear();
    // The table of contents and the body, indented by the theme's
    // section indent (the gem's `indent_section`).
    final indented = _collect(() {
      if (tocAtTop) {
        if (_ppbook) _out.add(const BreakBox.page(side: PageSide.recto));
        _addToc(
          'toc',
          breakAfter: titlePage && _s('toc_break_after') != 'auto',
        );
      }
      if (_ppbook && !_firstBlockOf(document).hasOption('nonfacing')) {
        _out
          ..add(
            const CustomBox(
              _Nothing(),
              style: BoxStyle(anchor: _beforeBodyAnchor),
            ),
          )
          ..add(const BreakBox.page(side: PageSide.recto));
      }
      if (titlePage) _out.add(_bodyMarker());
      final columns = (_n('page_columns') ?? 1).toInt();
      _inColumns = !book && columns >= 2;
      if (_inColumns) {
        final body = _collect(() {
          _manNameSection(document);
          _traverse(document);
          _footnotes(document);
        });
        _out.add(
          ColumnsBox(
            body,
            count: columns,
            gap: (_n('page_column_gap') ?? _rootFontSize).toDouble(),
          ),
        );
      } else {
        _manNameSection(document);
        _traverse(document);
        _footnotes(document);
      }
    });
    if (_sectionIndent case (final left, final right)) {
      _out.add(
        BlockBox(
          indented,
          style: BoxStyle(
            margin: EdgeInsets(left: left, right: right),
          ),
        ),
      );
    } else {
      _out.addAll(indented);
    }
    _backCover = false;
    final backCover = _resolveBackgroundImage(
      'back-cover-image',
      themeKey: 'cover_back_image',
      symbols: const ['', '~'],
    );
    if (backCover?.image?.graphic case final ImportedPage page) {
      _importPage(page, advance: false);
      _backCover = true;
    } else if (backCover != null && backCover.symbol != '~') {
      _out.add(const BreakBox.page());
      if (backCover.image case final image?) {
        _out.add(
          CustomBox(
            _Absolute((page) => _drawPageImage(page.canvas, image), fill: true),
          ),
        );
      } else {
        _out.add(CustomBox(_Absolute((_) {}, fill: true)));
      }
      _backCover = true;
    }

    PageTemplate templateFor(String layout) {
      final (width, height) = _layoutSize(document, layout);
      return PageTemplate(
        PdfRect(0, 0, width, height),
        margins: _marginsFor(document, layout),
        header: _header,
        footer: _footer,
        background: _pageBackground,
        foreground: _pageForeground,
        bleed: _bleed,
      );
    }

    final templates = {
      for (final layout in const ['portrait', 'landscape'])
        layout: templateFor(layout),
      for (final MapEntry(:key, value: page) in _importedPages.entries)
        key: PageTemplate(
          PdfRect(0, 0, page.intrinsicWidth, page.intrinsicHeight),
          margins: EdgeInsets.zero,
          background: (canvas, info) => page.paint(canvas, info.template.size),
        ),
    };
    final layout = FlowLayout(
      template: templates[_initialLayout(document)],
      templates: templates,
      keepTemplate: true,
      pageLabel: _pageLabel,
      notes: _notes,
      noteSeparator: _notes.isEmpty ? null : _footnoteSeparator(),
      templateForPage: media == 'prepress'
          ? (template, number) => _sidedTemplate(
              template,
              number,
              sided: _sidedLayouts(document).map((l) => templates[l]!).toSet(),
              cover: number == 1 && _hasTitlePage && !_frontCover && !_noCover,
            )
          : null,
    );
    if (onWalked case final walked?) {
      _phase(null);
      walked(layout, _out);
      return '';
    }
    _phase('pdf layout');
    var result = layout.layout(_out);
    // Where the body, the table of contents and each anchor are, and the
    // front matter they make.
    void measure() {
      _bodyStart = (result.anchors[_bodyAnchor]?.page ?? result.pageCount) + 1;
      _blankBeforeBody = _blankBefore(result);
      _anchorPages = {
        for (final MapEntry(:key, :value) in result.anchors.entries)
          key: value.page + 1,
      };
      _tocPages = switch ((
        result.anchors[_tocStartAnchor],
        result.anchors[_tocEndAnchor],
      )) {
        (final start?, final end?) => (start.page + 1, end.page + 1),
        _ => null,
      };
      _skip = _frontMatter(titlePage: titlePage);
      _openerPages = {
        for (final (section, anchor) in _sections)
          if (_opensPages(section)) ?_anchorPages[anchor],
      };
    }

    measure();
    // The index, once the pages of its terms are known.
    if (_indexSlot case final slot?) {
      _phase('pdf layout (index)');
      _fillIndex(slot);
      // (Laid out again from the top-level box holding the index on.)
      final at = _out.indexWhere(
        (box) => box is BlockBox && identical(box.children, slot),
      );
      result = layout.layout(
        _out,
        reuse: at < 0 ? null : result,
        unchangedBefore: at < 0 ? 0 : at,
      );
      measure();
    }
    // Footnotes numbered on each page: numbered from where their
    // references are, then laid out again until the numbers stay.
    if (_footnoteNumbering == 'page') {
      for (var pass = 0; pass < 3; pass++) {
        final changed = _numberFootnotesByPage(result);
        if (changed.isEmpty) break;
        _phase('pdf layout (footnotes)');
        // Laid out again from the first page with a new number on, the
        // runs of pages without one kept (unless a reference without an
        // anchor has one: where it is isn't known).
        final pages = {
          for (final index in changed) ...[
            ...result.anchorPages('_footnoteref_$index'),
            ...result.anchorPages('_footnotedef_$index'),
          ],
        };
        result = layout.layout(
          _out,
          reuse: result,
          unchangedBefore: result.boundaryBefore(pages.reduce(math.min)),
          changedPages: changed.any(_unanchoredFootnotes.contains)
              ? null
              : pages,
        );
        measure();
      }
    }
    _unanchoredFootnotes.clear();
    // How the document opens (the gem's `PageModes`).
    final (pageMode, nonFullScreen) = switch (document.attr('pdf-page-mode') ??
        _s('page_mode')) {
      'fullscreen' ||
      'fullscreen outline' => (PageMode.fullScreen, PageMode.useOutlines),
      'fullscreen none' => (PageMode.fullScreen, PageMode.useNone),
      'fullscreen thumbs' => (PageMode.fullScreen, PageMode.useThumbs),
      'none' => (PageMode.useNone, null),
      'thumbs' => (PageMode.useThumbs, null),
      _ => (PageMode.useOutlines, null),
    };
    final standard = _pdfStandard(document);
    final info = _info(document);
    final pdf = PdfDocument(
      info: standard == null
          ? info
          : PdfInfo(
              title: info.title,
              author: info.author,
              subject: info.subject,
              keywords: info.keywords,
              creator: info.creator,
              producer: info.producer,
              trapped: false,
              pdfxVersion: 'PDF/X-4',
              identifier: info.identifier,
              contributors: info.contributors,
              rights: info.rights,
            ),
      pageMode: pageMode,
      nonFullScreenPageMode: nonFullScreen,
      displayTitle: true,
      language: document.attr('lang'),
    );
    if (standard != null) pdf.outputIntents.add(standard);
    _phase('pdf render');
    final pages = result.render(pdf, destinationName: destinationName);
    _compressingElsewhere(pages);
    if (standard != null) _preflight(standard);
    _layoutReport(document, result);
    _pageMap(document, result, pages.length);
    logger.info(
      'laid out ${pages.length} ${pages.length == 1 ? 'page' : 'pages'}',
    );
    _outline(pdf, pages, result);
    if (pages.isNotEmpty) {
      final first = pages.first;
      pdf.openAction = switch (_s('page_initial_zoom')) {
        'Fit' => PdfDestination.fit(first),
        'FitV' => PdfDestination.fitHeight(first, left: 0),
        'FitH' => PdfDestination.fitWidth(first, top: pages.last.height),
        _ => null,
      };
    }
    // The same document makes the same bytes: the file identifier comes
    // from the content, the dates from the document's local date and time
    // (SOURCE_DATE_EPOCH, when set), as the gem dates it.
    _phase(null);
    final creationDate = _dateTime(document.attr('localdatetime'));
    _save = () {
      _phase('pdf save');
      final bytes = pdf.save(
        options: _writerOptions(
          nativeZlib: io.hasNativeZlib,
          creationDate: creationDate,
        ),
      );
      _phase(null);
      return bytes;
    };
    return '';
  }

  /// The options the PDF is saved with ([nativeZlib]: the platform's
  /// zlib, as on the Dart VM).
  static PdfWriterOptions _writerOptions({
    required bool nativeZlib,
    DateTime? creationDate,
  }) => PdfWriterOptions(
    deterministic: true,
    creationDate: creationDate,
    zlib: nativeZlib ? const _NativeZlib() : null,
  );

  /// The timings the PDF's phases are recorded in (`--progress`), if any.
  Timings? _phases;
  String? _runningPhase;

  /// Ends the running phase (recording its time) and starts [name], if
  /// given.
  void _phase(String? name) {
    final timings = _phases;
    if (timings == null) return;
    if (_runningPhase case final running?) timings.record(running);
    _runningPhase = name;
    if (name != null) timings.start(name);
  }

  /// [value] (`2026-10-06 04:38:31 +0000`, or `UTC` for the offset) as a
  /// date and time; the current time when it isn't one.
  static DateTime _dateTime(String? value) {
    final m = RegExp(
      r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?: (UTC|[+-]\d{4}))?',
    ).firstMatch(value ?? '');
    if (m == null) return DateTime.now().toUtc();
    final local = DateTime.utc(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
      int.parse(m[6]!),
    );
    final offset = m[7];
    if (offset == null || offset == 'UTC') return local;
    final minutes =
        (int.parse(offset.substring(1, 3)) * 60 +
            int.parse(offset.substring(3))) *
        (offset.startsWith('-') ? -1 : 1);
    return local.subtract(Duration(minutes: minutes));
  }

  /// Makes the titled preamble of a book a preface section (the gem's
  /// `promote_preface_block`).
  static void _promotePreface(Document doc) {
    final blocks = doc.blocks;
    if (doc.doctype != 'book' || blocks.length < 2) return;
    final preamble = blocks[0];
    final next = blocks[1];
    final title = preamble.sourceTitle;
    if (preamble.context != BlockContext.preamble ||
        title == null ||
        title.isEmpty ||
        preamble.blocks.firstOrNull?.style == 'abstract' ||
        next is! Section) {
      return;
    }
    final preface = Section(doc, next.level)
      ..special = true
      ..sectname = 'preface'
      ..title = title;
    preface
      ..setAttr('style', 'preface')
      ..id = Section.generateId(preface.title ?? title, doc);
    final first = preamble.blocks.firstOrNull;
    if (first != null && first.hasOption('notitle')) {
      preface.setOption('notitle');
      if (first.context == BlockContext.paragraph && first.role == null) {
        first.setAttr('role', 'lead');
      }
    }
    [...preamble.blocks].forEach(preface.append);
    blocks[0] = preface;
  }

  /// [theme] with the defaults the converter assumes (the gem's
  /// `prepare_theme`).
  static Theme _prepareTheme(Theme theme) {
    void fallback(String key, ThemeValue value) {
      switch (theme[key]) {
        case null || ThemeNull() || ThemeBool(value: false):
          theme[key] = value;
        case _:
          break;
      }
    }

    if (theme['base_border_color'] case ThemeString(value: 'transparent')) {
      theme['base_border_color'] = const ThemeNull();
    }
    final borderColor = switch (theme['base_border_color']) {
      null || ThemeNull() => const ThemeString('000000'),
      final color => color,
    };
    fallback('base_font_color', const ThemeString('000000'));
    fallback('base_font_family', const ThemeString('Helvetica'));
    fallback('base_font_style', const ThemeString('normal'));
    fallback('page_numbering_start_at', const ThemeString('body'));
    fallback('running_content_start_at', const ThemeString('body'));
    fallback('heading_chapter_break_before', const ThemeString('always'));
    fallback('heading_part_break_before', const ThemeString('always'));
    for (final key in [
      'heading_margin_page_top',
      'heading_margin_top',
      'heading_margin_bottom',
      'prose_text_indent',
      'prose_text_indent_inner',
      'prose_margin_bottom',
      'block_margin_bottom',
      'list_indent',
      'list_item_spacing',
      'description_list_term_spacing',
      'description_list_description_indent',
      'image_border_width',
      'callout_list_margin_top_after_code',
      'footnotes_item_spacing',
      'toc_indent',
      'toc_hanging_indent',
    ]) {
      fallback(key, const ThemeNumber(0));
    }
    fallback('table_border_color', borderColor);
    fallback('table_border_width', const ThemeNumber(0.5));
    fallback('thematic_break_border_color', borderColor);
    fallback('code_linenum_font_color', const ThemeString('999999'));
    fallback('role_unresolved_font_color', const ThemeString('FF0000'));
    fallback('footnotes_margin_top', const ThemeString('auto'));
    fallback('index_columns', const ThemeNumber(2));
    fallback('index_column_gap', theme['base_font_size'] ?? const ThemeNull());
    fallback('kbd_separator', const ThemeString('+'));
    fallback('title_page_authors_delimiter', const ThemeString(', '));
    fallback('title_page_revision_delimiter', const ThemeString(', '));
    return theme;
  }

  /// Draws the logo of the title page, if any, where the theme puts it
  /// (it takes no room; the gem's logo in `ink_title_page`).
  void _titleLogo(Document doc, String titleAlign) {
    if (_s('title_page_logo_display') == 'none') return;
    final fromDocument = doc.attr('title-logo-image');
    final value = fromDocument ?? _s('title_page_logo_image');
    if (value == null) return;
    var target = value;
    var attrs = <String, String>{};
    if (_imageMacroOf(value, const ['alt', 'width', 'height'])
        case (final macroTarget, final macroAttrs)?) {
      target = macroTarget;
      attrs = {...macroAttrs};
    }
    if (fromDocument == null) {
      target = _applySubsDiscretely(
        target,
        const {},
        subs: const [Sub.attributes],
      );
    }
    final format = _imageFormat(target);
    if (format == 'pdf') {
      logger.error(
        'PDF format not supported for title page logo image: $target',
      );
      return;
    }
    const aligns = {'left', 'center', 'right'};
    final align =
        [
          attrs.remove('align'),
          _s('title_page_logo_align'),
          titleAlign,
        ].whereType<String>().where(aligns.contains).firstOrNull ??
        'left';
    final bytes = fromDocument != null
        ? _imageBytes(doc, target)
        : _themeImageBytes(target);
    final (graphic, problem) = bytes == null
        ? (null, null)
        : _graphicOf(bytes, format, path: _lastImagePath);
    if (bytes == null && fromDocument == null) {
      logger.warn(
        'image to embed not found or not readable: '
        '${_themeImagePath(target) ?? target}',
      );
    } else if (graphic == null && problem != null) {
      logger.warn('could not embed image: $target; $problem');
    }
    final topValue = switch (attrs['top']) {
      final top? => ThemeString(top),
      null => _theme['title_page_logo_top'],
    };
    final top = topValue == null ? 0.0 : _titlePageTop(topValue);
    final left = (_n('title_page_logo_margin_left') ?? 0).toDouble();
    final right = (_n('title_page_logo_margin_right') ?? 0).toDouble();
    final (pageWidth, pageHeight) = _pageSize(doc);
    final margins = _pageMargins(doc);
    // An image that can't be embedded: its alt text in its place (the
    // gem's `on_image_error`).
    final CustomContent content;
    if (graphic == null) {
      final path = fromDocument != null
          ? _imagePath(doc, target) ?? target
          : _themeImagePath(target) ?? target;
      final template =
          _s('image_alt_content') ??
          '%{link}[%{alt}]%{/link} | <em>%{target}</em>';
      if (template.isEmpty) return;
      final link = attrs['link'];
      final text = template
          .replaceAll('%{link}', link == null ? '' : '<a href="$link">')
          .replaceAll('%{/link}', link == null ? '' : '</a>')
          .replaceAll('%{alt}', attrs['alt'] ?? '')
          .replaceAll('%{target}', path);
      content = _textBox(
        text,
        _themeFont('image_alt', _font),
        align: align,
        normalize: false,
      );
    } else {
      content = _ImageContent(
        graphic,
        width: _imageWidthOf((name) => attrs[name]),
        align: align,
        pageWidth: pageWidth,
      );
    }
    _out.add(
      CustomBox(
        _Absolute((page) {
          // Scaled down to fit the page below its top, as the gem fits it.
          final placed = content.place(
            pageWidth - margins.horizontal - left - right,
            math.max(0, pageHeight - margins.vertical - top),
            atTop: true,
          );
          placed?.paint(
            page,
            margins.left + left,
            pageHeight - margins.top - top,
          );
        }),
      ),
    );
  }

  /// The distance from the top of the content area that the title page
  /// value [value] gives (the gem's `resolve_top` on a new page).
  double _titlePageTop(ThemeValue value) {
    final (_, pageHeight) = _pageSize(_document);
    final margins = _pageMargins(_document);
    final contentHeight = pageHeight - margins.vertical;
    switch (value) {
      case ThemeNumber(:final value):
        return value.toDouble();
      case final other:
        final text = other.rubyString;
        if (text.endsWith('vh')) {
          final top = pageHeight * (1 - _toF(text) / 100);
          return pageHeight - margins.top - top;
        }
        if (text.endsWith('%')) return contentHeight * _toF(text) / 100;
        return strToPoints(text);
    }
  }

  /// Adds the title page of [doc]: the title, subtitle, authors and
  /// revision (the gem's `ink_title_page`; logos aren't drawn yet).
  void _titlePage(Document doc) {
    final align = _s('title_page_text_align') ?? _baseTextAlign;
    _titleLogo(doc, align);
    final base = _themeFont('title_page', _font);
    var offset = 0.0;
    void gap(double points) {
      if (points != 0) offset += points;
    }

    void prose(String text, String category, {bool normalize = true}) {
      var font = _themeFont(category, base);
      var content = text;
      if (font.transform case final transform? when transform != 'none') {
        content = transformText(content, transform);
      }
      final left = (_n('${category}_margin_left') ?? 0).toDouble();
      final right = (_n('${category}_margin_right') ?? 0).toDouble();
      // The modern engine: the text sheared as a block, by an angle in
      // degrees leaning right (`<category>_skew`, as Typst's skew).
      final degrees = _n('${category}_skew');
      _out.add(
        BlockBox(
          [
            CustomBox(
              _textBox(
                content,
                font,
                align: align,
                normalize: normalize,
                skew: degrees == null
                    ? null
                    : math.tan(degrees.toDouble() * math.pi / 180),
              ),
            ),
          ],
          style: BoxStyle(
            padding: EdgeInsets(top: offset),
            margin: EdgeInsets(left: left, right: right),
          ),
        ),
      );
      offset = 0;
      font = base;
    }

    if (_theme['title_page_title_top'] case final top?) {
      offset = _titlePageTop(top);
    }
    final title = doc.partitionedTitle(separator: doc.attr('title-separator'));
    if (_s('title_page_title_display') != 'none' && title != null) {
      gap((_n('title_page_title_margin_top') ?? 0).toDouble());
      prose(title.main, 'title_page_title');
      gap((_n('title_page_title_margin_bottom') ?? 0).toDouble());
    }
    final subtitle = title?.subtitle;
    if (_s('title_page_subtitle_display') != 'none' && subtitle != null) {
      gap((_n('title_page_subtitle_margin_top') ?? 0).toDouble());
      prose(subtitle, 'title_page_subtitle');
      gap((_n('title_page_subtitle_margin_bottom') ?? 0).toDouble());
    }
    if (_s('title_page_authors_display') != 'none' && doc.hasAttr('authors')) {
      gap((_n('title_page_authors_margin_top') ?? 0).toDouble());
      final generic = _s('title_page_authors_content');
      final templates = {
        'name_only': _s('title_page_authors_content_name_only') ?? generic,
        'with_email': _s('title_page_authors_content_with_email') ?? generic,
        'with_url': _s('title_page_authors_content_with_url') ?? generic,
      };
      // Each author's content, with the author's attributes in effect
      // (the gem's `with_author`): `url` is the email as a mailto: link,
      // or the URL in its place.
      final names = [
        for (final (i, author) in doc.authors.indexed)
          () {
            final attributes = <String, String>{};
            final unset = <String>{'url'};
            String? email;
            if (i == 0) {
              email = doc.attr('email');
            } else {
              for (final (name, value) in [
                ('author', author.name),
                ('authorinitials', author.initials),
                ('firstname', author.firstname),
                ('middlename', author.middlename),
                ('lastname', author.lastname),
                ('email', author.email),
              ]) {
                if (value == null) {
                  unset.add(name);
                } else {
                  attributes[name] = value;
                }
              }
              email = author.email;
            }
            String? url;
            if (email != null) {
              url = email.contains('@') ? 'mailto:$email' : email;
              attributes['url'] = url;
              unset.remove('url');
            }
            final key = url == null
                ? 'name_only'
                : url.startsWith('mailto:')
                ? 'with_email'
                : 'with_url';
            final template = templates[key];
            if (template == null) {
              return i == 0
                  ? doc.attr('author') ?? ''
                  : attributes['author'] ?? '';
            }
            return _applySubsDiscretely(
              template,
              attributes,
              unset: unset,
              dropLines: true,
            );
          }(),
      ];
      prose(
        // The delimiter's spaces as they are (a gap between names in a
        // row; the gem collapses them).
        names.join(
          (_s('title_page_authors_delimiter') ?? ', ').replaceAll(
            RegExp(' (?= )'),
            '&#160;',
          ),
        ),
        'title_page_authors',
      );
      gap((_n('title_page_authors_margin_bottom') ?? 0).toDouble());
    }
    final revision = [
      if (doc.attr('revnumber') case final number?)
        '${doc.attr('version-label') ?? ''} $number',
      ?doc.attr('revdate'),
    ];
    if (_s('title_page_revision_display') != 'none' && revision.isNotEmpty) {
      gap((_n('title_page_revision_margin_top') ?? 0).toDouble());
      var text = revision.join(_s('title_page_revision_delimiter') ?? ', ');
      if (doc.attr('revremark') case final remark?) text = '$text: $remark';
      prose(text, 'title_page_revision', normalize: false);
    }
  }

  /// The floated image the paragraphs after it wrap around, and the
  /// paragraph that goes in it next.
  _FloatGroup? _floatGroup;
  AbstractBlock? _floatNext;

  static const _tocStartAnchor = '__asciidart-toc-start';
  static const _tocEndAnchor = '__asciidart-toc-end';

  /// Whether the table of contents is at the top (after the title).
  bool _tocAtTop = false;

  /// Whether the table of contents has been added (there's only one).
  bool _tocDone = false;

  /// Whether the pages of the table of contents have no header, or no
  /// footer (a toc macro's options).
  bool _tocNoHeader = false;
  bool _tocNoFooter = false;

  /// Adds the table of contents at [anchor] (the gem's `allocate_toc`):
  /// then a page break when [breakAfter], else the block margin.
  void _addToc(String anchor, {required bool breakAfter, bool titled = true}) {
    _tocDone = true;
    _out
      ..add(CustomBox(const _Nothing(), style: BoxStyle(anchor: anchor)))
      ..add(
        const CustomBox(_Nothing(), style: BoxStyle(anchor: _tocStartAnchor)),
      );
    _toc(_document, titled: titled);
    _out.add(
      const CustomBox(_Nothing(), style: BoxStyle(anchor: _tocEndAnchor)),
    );
    if (breakAfter) {
      _out.add(const BreakBox.page());
    } else {
      final margin = (_n('block_margin_bottom') ?? 0).toDouble();
      if (margin > 0) _out.add(SpacerBox(margin));
    }
  }

  /// Converts the toc macro [node], or the table of contents after the
  /// preamble (with [placement] `preamble`), when the document places it
  /// there (the gem's `convert_toc`).
  void convertToc(AbstractBlock node, {String placement = 'macro'}) {
    final doc = _document;
    if (_tocDone ||
        doc.attr('toc-placement') != placement ||
        !doc.hasAttr('toc') ||
        _sectionsOf(doc).isEmpty) {
      return;
    }
    final book = doc.doctype == 'book';
    final macro = placement == 'macro';
    // In the modern engine, a toc macro that opens a section is that
    // section's contents: on its page, under its heading (no title of
    // its own), the section listed as any other (a Contents chapter);
    // unless `toc_macro_in_section` is false.
    final parent = node.parent;
    final ownsSection =
        _theme.value('toc_macro_in_section') != const ThemeBool(false) &&
        macro &&
        parent is Section &&
        parent.blocks.firstOrNull == node;
    if (book && !ownsSection) {
      _out.add(
        BreakBox.page(
          side: _ppbook && !(macro && node.hasOption('nonfacing'))
              ? PageSide.recto
              : null,
        ),
      );
    }
    _addToc(
      macro ? node.id ?? 'toc' : _tocStartAnchor,
      breakAfter: book || doc.hasAttr('title-page'),
      titled: !ownsSection,
    );
    if (macro) {
      _tocNoHeader = node.hasOption('noheader');
      _tocNoFooter = node.hasOption('nofooter');
    }
  }

  /// The page (1-based) of each anchor, once laid out.
  Map<String, int> _anchorPages = const {};

  /// The pages a part or chapter title opens (none has running content
  /// in the modern engine, unless `running_content_on_openers` is true).
  Set<int> _openerPages = const {};

  /// Whether [section] is a part or chapter of a book whose title is set.
  bool _opensPages(Section section) {
    if (_document.doctype != 'book' ||
        !(section.sectname == 'part' || section.level == 1) ||
        section.hasOption('notitle')) {
      return false;
    }
    // A styled role may keep the running content on its first page
    // (section_role_<role>_running_content_on_openers: a foreword set as
    // an ordinary heading).
    final role = _boxedRole(section);
    return role == null ||
        _theme.value('section_role_${role}_running_content_on_openers') !=
            const ThemeBool(true);
  }

  /// The number of levels the table of contents lists (the gem's
  /// `resolve_toclevels`).
  int get _tocLevels {
    final levels = int.tryParse(_document.attr('toclevels') ?? '2') ?? 0;
    if (levels >= 1) return levels;
    return _document.doctype == 'book' &&
            _document.sections.whereType<Section>().any(
              (s) => s.sectname == 'part',
            )
        ? 0
        : 1;
  }

  /// Adds the table of contents of [doc] (the gem's `ink_toc`).
  void _toc(Document doc, {bool titled = true}) {
    final title = doc.attr('toc-title');
    if (titled && title != null && title.isNotEmpty) {
      final font = _themeFont('toc_title', _headingFont(2));
      _heading(
        title,
        level: 2,
        align:
            _s('toc_title_text_align') ??
            _s('heading_h2_text_align') ??
            _s('heading_text_align') ??
            _baseTextAlign,
        font: font,
        outdent: true,
      );
    }
    final levels = _tocLevels;
    if (levels < 0) return;
    final toc = _themeFont('toc', _font);
    var dotStyle = _fontStyle(_s('toc_dot_leader_font_style')) ?? 'normal';
    final dotSize = switch (_theme.value('toc_dot_leader_font_size')) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => resolveFontSize(
        value,
        toc.size,
        _rootFontSize,
      ),
      _ => toc.size,
    };
    final hanging = (_n('toc_hanging_indent') ?? 0).toDouble();
    final dotFont = toc.copyWith(
      style: dotStyle,
      size: dotSize,
      color: _c('toc_dot_leader_font_color') ?? toc.color,
    );
    final dotLevels = switch (_theme['toc_dot_leader_levels']) {
      ThemeString(value: 'none') => const <int>{},
      ThemeString(value: 'all') || null => null,
      final value => {
        for (final part in value.rubyString.split(RegExp(r'\s+')))
          ?int.tryParse(part),
      },
    };
    final dotText = _s('toc_dot_leader_content') ?? '. ';
    final dotPrawn = _fonts.font(dotFont.family, dotFont.style);
    final dotWidth = dotText.isEmpty
        ? 0.0
        : dotPrawn.widthOf(dotText, dotSize, kerning: dotFont.kerning);
    final spacerSize = dotSize * 0.25;
    final spacerWidth = dotPrawn.widthOf(' ', spacerSize, kerning: false);
    dotStyle = dotFont.style;
    final margin = (_n('toc_margin_top') ?? 0).toDouble();
    if (margin > 0) _out.add(SpacerBox(margin));
    final indent = (_n('toc_indent') ?? 0).toDouble();
    // Under Typst's model (base_leading) each entry is a paragraph of its
    // own: the entries the leading apart (toc_entry_spacing).
    final gap = (_n('toc_entry_spacing') ?? _typstLeading(toc) ?? 0).toDouble();
    var first = true;
    void level(List<Section> entries, int levels, double left) {
      for (final entry in entries) {
        // asciidart's `notoc` option: a section left out of the contents.
        if (entry.hasOption('notoc')) continue;
        final entryLevel = (entry.level ?? 0) + 1;
        final entryLevels =
            int.tryParse(entry.attr('toclevels') ?? '') ?? levels;
        if (entryLevels < entryLevel - 1) continue;
        if (entry.hasOption('notitle') &&
            entry == doc.blocks.lastOrNull &&
            entry.blocks.isEmpty) {
          continue;
        }
        // The modern engine's `toc_entry_content` template (ADR-0010):
        // `title`, `numbered-title`, `number`.
        var title = _numberedTitle(entry, formal: false);
        if (_s('toc_entry_content') case final template?) {
          title = _render(template, {
            'title': entry.title,
            'numbered-title': title,
            'number': _isNumbered(entry)
                ? (entry.sectname == 'part' ? entry.numeral : entry.sectnum())
                : null,
          });
        }

        if (title.isEmpty) continue;
        final font = _themeFont('toc_h$entryLevel', toc);
        title = title.replaceAll(RegExp(r'<(?:a\b[^>]*|/a)>'), '');
        if (font.transform case final transform? when transform != 'none') {
          title = transformText(title, transform);
        }
        final anchor = _sectionAnchor(entry);
        final placeholder = _fonts
            .font(font.family, font.style)
            .widthOf('0' * 3, font.size, kerning: font.kerning);
        final showDots =
            dotWidth > 0 &&
            (dotLevels == null || dotLevels.contains(entryLevel - 1));
        _out.add(
          CustomBox(
            _TocEntry(
              hanging: hanging,
              // Prawn's alignment (the gem passes none).
              _textBox(
                title,
                font,
                align: 'left',
                indent: -hanging,
                inherit: (_decoration('toc', entryLevel) ?? Fragment(''))
                  ..anchor = anchor
                  ..color = font.color,
                normalize: false,
                normalizeLineHeight: true,
              ),
              placeholder,
              (width, startDots) {
                final label = anchor == null ? '?' : _anchorLabel(anchor);
                final prawn = _fonts.font(font.family, font.style);
                final labelWidth = prawn.widthOf(
                  label,
                  font.size,
                  kerning: font.kerning,
                );
                // Linked, in the entry's color (not the link color).
                final color = font.color?.rubyString;
                final colored = color == null
                    ? label
                    : '<font color="$color">$label</font>';
                final number = anchor == null
                    ? label
                    : '<a anchor="$anchor">$colored</a>';
                final String markup;
                if (showDots) {
                  final dots = math.max(
                    ((width - startDots - spacerWidth - labelWidth) / dotWidth)
                        .floor(),
                    0,
                  );
                  final dotColor = dotFont.color?.rubyString;
                  markup =
                      '<font name="${dotFont.family}" size="$dotSize"'
                      '${dotColor == null ? '' : ' color="$dotColor"'}>'
                      '${_styled(dotText * dots, dotStyle)}</font>'
                      '<font size="$spacerSize"> </font>'
                      '${_styled(number, font.style)}';
                } else {
                  markup = number;
                }
                return _textBox(markup, font, align: 'right', normalize: false);
              },
            ),
            style: BoxStyle(
              margin: EdgeInsets(left: left, top: first ? 0 : gap),
            ),
          ),
        );
        first = false;
        if (entryLevels >= entryLevel) {
          level(_sectionsOf(entry), entryLevels, left + indent);
        }
      }
    }

    level(_sectionsOf(doc), levels, 0);
  }

  /// [markup] in [style] (as inline markup).
  static String _styled(String markup, String style) => switch (style) {
    'bold' => '<strong>$markup</strong>',
    'italic' => '<em>$markup</em>',
    'bold_italic' => '<strong><em>$markup</em></strong>',
    _ => markup,
  };

  /// The anchor of [section] (its id, or the one made up for it).
  String? _sectionAnchor(Section section) {
    if (section.id case final id?) return id;
    for (final (s, anchor) in _sections) {
      if (s == section) return anchor;
    }
    return '__section-${section.hashCode}';
  }

  /// The page label of [anchor]'s page, or `?`.
  String _anchorLabel(String anchor) {
    final page = _anchorPages[anchor];
    return page == null ? '?' : _pageLabel(page);
  }

  /// The document's title, or its untitled label when it has no header
  /// (the gem's `resolve_doctitle`).
  static String? _resolveDoctitle(Document doc) =>
      doc.hasHeader ? doc.doctitle() : doc.attr('untitled-label');

  /// The information of the PDF (the gem's `build_pdf_info`; the producer
  /// is asciidart unless the document names one).
  PdfInfo _info(Document doc) {
    String? plain(String? text) => text == null ? null : _plain(text);
    final String? author;
    if (doc.attributeLocked('author') && !doc.attributeLocked('authors')) {
      author = doc.attr('author');
    } else {
      author = doc.attr('authors') ?? doc.attr('author');
    }
    return PdfInfo(
      title: plain(_resolveDoctitle(doc)),
      author: plain(author),
      subject: plain(doc.attr('subject')),
      keywords: plain(doc.attr('keywords')),
      creator: plain(doc.attr('publisher') ?? author) ?? '',
      producer: plain(doc.attr('producer')) ?? 'asciidart',
      // The book's ISBN, editors and copyright in the XMP metadata, as
      // the EPUB's OPF has them (modern engine).
      identifier: switch (doc.attr('isbn')) {
        final String isbn when isbn.trim().isNotEmpty =>
          'urn:isbn:${isbn.replaceAll(RegExp(r'[\s-]'), '')}',
        _ => null,
      },
      contributors: [
        for (final editor in (doc.attr('editor') ?? '').split(';'))
          if (editor.trim().isNotEmpty) plain(editor.trim())!,
      ],
      rights: plain(doc.attr('copyright')),
    );
  }

  /// The theme's section indent (left and right), if any.
  (double, double)? get _sectionIndent =>
      switch (_theme.value('section_indent')) {
        ThemeNumber(:final value) when value != 0 => (
          value.toDouble(),
          value.toDouble(),
        ),
        ThemeList(:final values) when values.isNotEmpty => (
          _toPoints(values[0]),
          values.length > 1 ? _toPoints(values[1]) : 0.0,
        ),
        _ => null,
      };

  /// [margin] reaching out over the section indent (the gem's
  /// `outdent_section`).
  EdgeInsets _outdented(EdgeInsets margin) {
    final (left, right) = _sectionIndent ?? (0.0, 0.0);
    return EdgeInsets(
      top: margin.top,
      right: margin.right - right,
      bottom: margin.bottom,
      left: margin.left - left,
    );
  }

  /// Whether the document has a front cover, or a back cover, page.
  bool _frontCover = false;
  bool _backCover = false;

  /// Adds the [face] (`front`) cover, if any: a page of its own with the
  /// cover image (the gem's `ink_cover_page`).
  bool _cover(String face) {
    final cover = _resolveBackgroundImage(
      '$face-cover-image',
      themeKey: 'cover_${face}_image',
      symbols: const ['', '~'],
    );
    if (cover?.symbol == '~') _noCover = true;
    if (cover == null || cover.symbol == '~') return false;
    if (cover.image?.graphic case final ImportedPage page) {
      _importPage(page);
      return true;
    }
    if (cover.image case final image?) {
      _out.add(
        CustomBox(
          _Absolute((page) => _drawPageImage(page.canvas, image), fill: true),
        ),
      );
    } else {
      _out.add(CustomBox(_Absolute((_) {}, fill: true)));
    }
    _out.add(const BreakBox.page(force: true));
    return true;
  }

  /// The page background image of [key] (an attribute, else the theme's
  /// [themeKey]): a symbolic value of [symbols], or the image and how it
  /// sits on the page; null when there's none (the gem's
  /// `resolve_background_image`).
  ({String? symbol, _PageImage? image})? _resolveBackgroundImage(
    String key, {
    String? themeKey,
    List<String> symbols = const [],
  }) {
    final doc = _document;
    final fromDocument = doc.attr(key);
    final value = fromDocument ?? _s(themeKey ?? key.replaceAll('-', '_'));
    if (value == null) return null;
    if (symbols.contains(value)) return (symbol: value, image: null);
    if (value == 'none') return null;
    var target = value;
    var attrs = <String, String>{};
    var relativeToImagesdir = false;
    if (_imageMacroOf(value, const ['alt', 'width'])
        case (final macroTarget, final macroAttrs)?) {
      target = macroTarget;
      attrs = macroAttrs;
      relativeToImagesdir = true;
    }
    target = target.replaceAll('{page-layout}', 'portrait');
    final fromTheme = fromDocument == null;
    if (fromTheme) {
      target = _applySubsDiscretely(
        target,
        const {},
        subs: const [Sub.attributes],
      );
    }
    final format = attrs['format'] ?? _imageFormat(target);
    final List<int>? bytes;
    if (format == 'pdf') {
      // A page of a PDF file: imported as it is, if it exists.
      final path = fromTheme
          ? _themeImagePath(target)
          : relativeToImagesdir
          ? _imagePath(doc, target)
          : doc.normalizeSystemPath(target);
      if (path == null || !io.isFile(path) || !io.isReadable(path)) {
        final name = key.replaceAll(RegExp('[-_]'), ' ');
        logger.warn('$name not found or readable: ${path ?? target}');
        return null;
      }
      final page = _pdfPages(path, target)?.elementAtOrNull(
        math.max((int.tryParse(attrs['page'] ?? '') ?? 1) - 1, 0),
      );
      return page == null
          ? null
          : (
              symbol: null,
              image: _PageImage(
                page,
                fit: 'fill',
                position: 'center',
                vposition: 'center',
              ),
            );
    }
    if (fromTheme) {
      bytes = _themeImageBytes(target);
    } else if (relativeToImagesdir) {
      bytes = _imageBytes(doc, target);
    } else {
      final resolver = doc.pathResolver;
      final path = doc.normalizeSystemPath(target);
      bytes = io.isFile(path) && io.isReadable(path)
          ? io.readBytes(path)
          : null;
      if (bytes != null) _lastImagePath = resolver.posixify(path);
    }
    if (bytes == null) {
      final name = key.replaceAll(RegExp('[-_]'), ' ');
      logger.warn('$name not found or readable: $target');
      return null;
    }
    final (graphic, problem) = _graphicOf(bytes, format, path: _lastImagePath);
    if (graphic == null) {
      final name = key.replaceAll('-', ' ');
      logger.warn('could not embed $name: $target; $problem');
      return null;
    }
    var fit = attrs['fit'] ?? 'contain';
    if (format == 'svg' && fit == 'fill') fit = 'contain';
    var (position, vposition) = ('center', 'center');
    if (attrs['position'] case final value?) {
      if (_backgroundPosition(value) case final resolved?) {
        (position, vposition) = resolved;
      }
    }
    final (pageWidth, _) = _pageSize(doc);
    return (
      symbol: null,
      image: _PageImage(
        graphic,
        fit: fit,
        width: _imageWidthOf(
          (name) => attrs[name],
          fallback: false,
        ).resolve(pageWidth, pageWidth),
        position: position,
        vposition: vposition,
      ),
    );
  }

  /// The horizontal and vertical position of the background position
  /// [value] (`left top`, `center`...), or null (the gem's
  /// `resolve_background_position`).
  static (String, String)? _backgroundPosition(String value) {
    if (value.contains(' ')) {
      String? h;
      String? v;
      var center = false;
      for (final keyword in value.split(' ').take(2)) {
        switch (keyword) {
          case 'left' || 'right':
            h = keyword;
          case 'top' || 'bottom':
            v = keyword;
          case 'center':
            center = true;
        }
      }
      if (center) return (h ?? 'center', v ?? 'center');
      if (h != null && v != null) return (h, v);
      return null;
    }
    return switch (value) {
      'left' || 'right' || 'center' => (value, 'center'),
      'top' || 'bottom' => ('center', value),
      _ => null,
    };
  }

  /// Draws [image] on a page by its fit and position.
  void _drawPageImage(
    PdfCanvas canvas,
    _PageImage image, {
    (double, double)? size,
  }) {
    final (pageWidth, pageHeight) = size ?? _pageSize(_document);
    final graphic = image.graphic;
    final (naturalWidth, naturalHeight) = switch (graphic) {
      final SvgImage svg => prawnSvgSize(
        svg,
        null,
        null,
        pageWidth,
        pageHeight,
      ),
      final other => (other.intrinsicWidth, other.intrinsicHeight),
    };
    final ratio = naturalHeight / naturalWidth;
    (double, double) contain() =>
        naturalWidth / naturalHeight > pageWidth / pageHeight
        ? (pageWidth, pageWidth * ratio)
        : (pageHeight / ratio, pageHeight);
    final (w, h) = switch (image.fit) {
      'none' =>
        image.width == null
            ? (naturalWidth, naturalHeight)
            : (image.width!, image.width! * ratio),
      'scale-down' =>
        naturalWidth > pageWidth || naturalHeight > pageHeight
            ? contain()
            : (naturalWidth, naturalHeight),
      'cover' =>
        pageWidth * ratio < pageHeight
            ? (pageHeight / ratio, pageHeight)
            : (pageWidth, pageWidth * ratio),
      'fill' => (pageWidth, pageHeight),
      _ => contain(),
    };
    final left = switch (image.position) {
      'left' => 0.0,
      'right' => pageWidth - w,
      _ => (pageWidth - w) / 2,
    };
    final top = switch (image.vposition) {
      'top' => pageHeight,
      'bottom' => h,
      _ => pageHeight - (pageHeight - h) / 2,
    };
    final rect = PdfRect(left, top - h, w, h);
    switch (graphic) {
      case final PdfImage raster:
        canvas.image(raster, rect);
      case final other:
        canvas.save();
        other.paint(canvas, rect);
        canvas.restore();
    }
  }

  /// The page background images, by side (`recto`, `verso`).
  late final Map<String, _PageImage?> _pageImages = () {
    final both = _resolveBackgroundImage('page-background-image')?.image;
    final images = <String, _PageImage?>{'recto': both, 'verso': both};
    for (final side in const ['recto', 'verso']) {
      if (_resolveBackgroundImage('page-background-image-$side')
          case final resolved?) {
        images[side] = resolved.image;
      }
    }
    return images;
  }();

  /// The title page's background image, if it has one of its own (the
  /// `none` symbol when it has none, not even the pages' image).
  late final ({String? symbol, _PageImage? image})? _titlePageImage =
      _resolveBackgroundImage(
        'title-page-background-image',
        symbols: const ['none'],
      );

  /// Paints the background of [page]: the page's background color and
  /// image (the title page's own, if any; none on cover pages; the gem's
  /// `init_page`).
  void _pageBackground(PdfCanvas canvas, PageInfo page) {
    final number = page.number;
    if ((_frontCover && number == 1) || (_backCover && number == page.count)) {
      return;
    }
    final titlePageNumber = _frontCover ? 2 : 1;
    final onTitlePage = _hasTitlePage && number == titlePageNumber;
    final background =
        (onTitlePage ? _c('title_page_background_color') : null) ??
        _c('page_background_color');
    final pageWidth = page.template.size.width;
    final pageHeight = page.template.size.height;
    if (background != const HexColor('FFFFFF')) {
      if (_color(background) case final color?) {
        // Into the bleed, when there is one.
        final bleed = page.template.bleed ?? 0;
        canvas
          ..save()
          ..setFillColor(color)
          ..rect(
            PdfRect(
              -bleed,
              -bleed,
              pageWidth + 2 * bleed,
              pageHeight + 2 * bleed,
            ),
          )
          ..fill()
          ..restore();
      }
    }
    final image = onTitlePage && _titlePageImage != null
        ? _titlePageImage.image
        : _pageImages[_sideOf(number)];
    if (image != null) {
      _drawPageImage(canvas, image, size: (pageWidth, pageHeight));
    }
  }

  /// The image over every page but the front cover and the pages of PDF
  /// files (the theme's `page_foreground_image`).
  late final _PageImage? _foregroundImage = _resolveBackgroundImage(
    'page-foreground-image',
  )?.image;

  /// Paints the foreground of [page] (the gem's `stamp_foreground_image`).
  void _pageForeground(PdfCanvas canvas, PageInfo page) {
    if (_frontCover && page.number == 1) return;
    if (_foregroundImage case final image?) {
      _drawPageImage(
        canvas,
        image,
        size: (page.template.size.width, page.template.size.height),
      );
    }
  }

  /// The background images of the running content, by periphery
  /// (`header`, `footer`).
  final Map<String, _PageImage?> _runningBackgrounds = {};

  /// Whether the document has a title page.
  bool _hasTitlePage = false;

  /// Whether the front cover is `~`: none, and the first page takes the
  /// margins of a recto page.
  bool _noCover = false;

  static const _beforeBodyAnchor = '__asciidart-before-body';

  /// Whether a blank page was put before the body to start it on a recto
  /// page (a running content or page numbering start can then be on it).
  bool _blankBeforeBody = false;

  /// Whether [result] has a blank page before the body.
  bool _blankBefore(LayoutResult result) =>
      switch (result.anchors[_beforeBodyAnchor]?.page) {
        final page? => page + 1 < _bodyStart,
        null => false,
      };

  /// Whether the document is a book for print (`media=prepress`): its
  /// title page, table of contents, body, chapters and parts start on
  /// recto pages.
  bool _ppbook = false;

  /// What decides whether a page is a recto or a verso page for its
  /// running content and background: its physical page number or its
  /// page number; and whether the sides are inverted
  /// (`pdf-folio-placement`).
  ({bool physical, bool inverted}) _folio = (physical: false, inverted: false);

  /// The side (`recto`, `verso`) of page [number] by the folio placement.
  String _sideOf(int number) =>
      number.isOdd != _folio.inverted ? 'recto' : 'verso';

  /// The first block of [document], or of its preamble.
  static AbstractBlock _firstBlockOf(Document document) {
    final first = document.blocks.firstOrNull;
    if (first is Block && first.context == BlockContext.preamble) {
      return first.blocks.firstOrNull ?? first;
    }
    return first ?? document;
  }

  /// The layouts whose pages get recto and verso margins: the initial
  /// one, and the other one unless it has margins of its own
  /// (`page_margin_rotated`).
  List<String> _sidedLayouts(Document document) {
    final initial = _initialLayout(document);
    final rotated =
        document.attr('pdf-page-margin-rotated') != null ||
        _theme.value('page_margin_rotated') != null;
    final other = initial == 'portrait' ? 'landscape' : 'portrait';
    return [initial, if (!rotated) other];
  }

  /// [template] for page [number] with `media=prepress`: one of the
  /// [sided] templates gets the theme's inner and outer margins on the
  /// side of the binding and the side away from it (the first page keeps
  /// its margins when it's the [cover], a title page).
  PageTemplate _sidedTemplate(
    PageTemplate template,
    int number, {
    required Set<PageTemplate> sided,
    required bool cover,
  }) {
    if (cover || !sided.contains(template)) return template;
    final outer = _n('page_margin_outer')?.toDouble();
    final inner = _n('page_margin_inner')?.toDouble();
    if (outer == null && inner == null) return template;
    final m = template.margins;
    final recto = number.isOdd;
    return PageTemplate(
      template.size,
      margins: EdgeInsets(
        top: m.top,
        bottom: m.bottom,
        left: (recto ? inner : outer) ?? m.left,
        right: (recto ? outer : inner) ?? m.right,
      ),
      columns: template.columns,
      columnGap: template.columnGap,
      header: template.header,
      footer: template.footer,
      background: template.background,
      foreground: template.foreground,
      bleed: template.bleed,
    );
  }

  /// The output intent of a PDF/X-4 document (`pdf-standard=PDF/X-4`,
  /// with `pdf-output-intent` the ICC profile of the printing condition
  /// and `pdf-output-condition` its identifier), or null for a plain PDF.
  PdfOutputIntent? _pdfStandard(Document document) {
    final standard = document.attr('pdf-standard');
    if (standard == null) return null;
    if (standard.toUpperCase() != 'PDF/X-4') {
      logger.warn(
        'unknown pdf-standard: $standard (PDF/X-4 is available); '
        'writing a plain PDF',
      );
      return null;
    }
    final target = document.attr('pdf-output-intent');
    if (target == null || target.isEmpty) {
      logger.error(
        'PDF/X-4 needs the ICC profile of the printing condition: set '
        'pdf-output-intent to its file; writing a plain PDF',
      );
      return null;
    }
    final path = document.normalizeSystemPath(target);
    if (!io.isFile(path) || !io.isReadable(path)) {
      logger.error(
        'output intent profile not found or not readable: $target; '
        'writing a plain PDF',
      );
      return null;
    }
    final intent = PdfOutputIntent(
      io.readBytes(path),
      identifier: document.attr('pdf-output-condition') ?? 'Custom',
      info: target.split('/').last,
    );
    if (intent.components == null) {
      logger.error('not an ICC profile: $target; writing a plain PDF');
      return null;
    }
    return intent;
  }

  /// Reports what keeps the document from conforming to PDF/X-4 with
  /// [intent]: fonts not embedded, a profile that isn't for output, RGB
  /// colors with a CMYK printing condition.
  void _preflight(PdfOutputIntent intent) {
    for (final font in _fonts.loaded) {
      if (font is AfmFont) {
        logger.error(
          'PDF/X-4 needs every font embedded: ${font.family} is a built-in '
          'PDF font; give the theme a font file for it',
        );
      }
    }
    if (intent.deviceClass != 'prtr') {
      logger.warn(
        'the output intent profile is not an output (printer) profile '
        '(${intent.deviceClass}), as PDF/X-4 asks',
      );
    }
    if (intent.components == 4) {
      logger.warn(
        'the text, lines and images are in RGB and the printing condition '
        'in CMYK: PDF/X-4 asks for colors the output intent can describe; '
        'use an RGB output profile, or convert the PDF',
      );
    }
  }

  /// Writes the layout report (`pdf-layout-report`, a file next to the
  /// PDF): each block that breaks across pages, with where it starts in
  /// the source, for proofreading.
  void _layoutReport(Document document, LayoutResult result) {
    final tags = _reportTags;
    final target = document.attr('pdf-layout-report');
    if (tags == null || target == null) return;
    final lines = <String>[];
    for (final MapEntry(key: tag, value: (block, at)) in tags.entries) {
      final pages = result.tagPages[tag];
      if (pages == null || pages.first == pages.last) continue;
      final where = at == null
          ? ''
          : '${at.path ?? at.file ?? ''}: line ${at.lineno}: ';
      lines.add(
        '$where${block.context.name} on pages ${_pageLabel(pages.first)}'
        '-${_pageLabel(pages.last)}',
      );
    }
    final dir = document.attr('outdir') ?? document.attr('docdir') ?? '.';
    final path = target.startsWith('/') ? target : '$dir/$target';
    io.writeString(path, lines.isEmpty ? '' : '${lines.join('\n')}\n');
    logger.info(
      'layout report: ${lines.length} '
      '${lines.length == 1 ? 'block breaks' : 'blocks break'} across pages '
      '($path)',
    );
  }

  /// Writes the page map (`pdf-page-map`, a JSON file next to the PDF):
  /// the page labels, and for each block, where it starts in the source
  /// and the pages it is on, so an EPUB of the same source can mark the
  /// print edition's pages (`epub-page-map`, ADR-0012).
  void _pageMap(Document document, LayoutResult result, int pageCount) {
    final tags = _reportTags;
    final target = document.attr('pdf-page-map');
    if (tags == null || target == null) return;
    final blocks = <String, (int, int)>{};
    for (final MapEntry(key: tag, value: (_, at)) in tags.entries) {
      final pages = result.tagPages[tag];
      if (pages == null || at == null) continue;
      blocks['${at.path ?? at.file ?? ''}:${at.lineno}'] = (
        pages.first,
        pages.last,
      );
    }
    final map = PageMap(
      labels: [for (var i = 1; i <= pageCount; i++) _pageLabel(i)],
      blocks: blocks,
    );
    final dir = document.attr('outdir') ?? document.attr('docdir') ?? '.';
    final path = target.startsWith('/') ? target : '$dir/$target';
    io.writeString(path, map.toJson());
  }

  /// Tags the box [block] added last (after any caption) after [before],
  /// for the layout report.
  void _tagLast(int before, AbstractBlock block) {
    final tags = _reportTags!;
    for (var i = _out.length - 1; i >= before; i--) {
      final tag = 'b${tags.length}';
      final tagged = switch (_out[i]) {
        BlockBox(:final children, :final style) => BlockBox(
          children,
          style: style.withTag(tag),
        ),
        CustomBox(:final content, :final style) => CustomBox(
          content,
          style: style.withTag(tag),
        ),
        TableBox(:final rows, :final columns, :final style) && final table =>
          TableBox(
            rows,
            columns: columns,
            headerRows: table.headerRows,
            width: table.width,
            shrinkToContent: table.shrinkToContent,
            align: table.align,
            stripes: table.stripes,
            style: style.withTag(tag),
          ),
        _ => null,
      };
      if (tagged == null) continue;
      _out[i] = tagged;
      tags[tag] = (block, block.sourceLocation ?? _at);
      return;
    }
  }

  /// With `pdf-layout-report`, the blocks tagged for the report, and where
  /// each starts in the source.
  Map<String, (AbstractBlock, Cursor?)>? _reportTags;

  /// The OpenType features all text is set with in the modern engine:
  /// the theme's `base_font_variant_numeric` (`oldstyle-nums`...).
  late final Set<String> _baseFeatures = {
    ?fontFeature(_s('base_font_variant_numeric')),
  };

  /// How far the modern engine's sheets run past the page for print
  /// (`page_bleed`): null for no print boxes, unless the document is
  /// PDF/X, which needs them.
  double? get _bleed {
    final bleed = switch (_theme.value('page_bleed')) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => strToPoints(value),
      _ => null,
    };
    return bleed ?? (_document.hasAttr('pdf-standard') ? 0 : null);
  }

  static const _bodyAnchor = '__asciidart-body';

  /// Marks where the body starts (after the title page and the table of
  /// contents of a book).
  static CustomBox _bodyMarker() =>
      const CustomBox(_Nothing(), style: BoxStyle(anchor: _bodyAnchor));

  /// The pages before the running content and the page numbers start
  /// (the gem's `num_front_matter_pages`, without covers).
  (int, int) _frontMatter({required bool titlePage}) {
    final bodyOffset = _bodyStart - 1;
    ThemeValue? startAt(String key) => _theme[key];
    if (!titlePage) {
      int offset(ThemeValue? value) => switch (value) {
        ThemeNumber(:final value) =>
          bodyOffset + math.max(value.toInt() - 1, _blankBeforeBody ? -1 : 0),
        _ => bodyOffset,
      };
      final numbering = startAt('page_numbering_start_at');
      return (
        offset(startAt('running_content_start_at')),
        numbering is ThemeString && numbering.value == 'cover' && _frontCover
            ? 0
            : offset(numbering),
      );
    }
    final hasTitlePage =
        _document.hasHeader &&
        !_document.notitle &&
        _theme['title_page'] is! ThemeBool;
    final zero = _frontCover ? 1 : 0;
    final first = hasTitlePage ? zero + 1 : zero;
    final tocAtTop = _tocAtTop;
    String resolve(ThemeValue? value, void Function(int) integer) {
      switch (value) {
        case ThemeNumber(:final value):
          integer(
            bodyOffset + math.max(value.toInt() - 1, _blankBeforeBody ? -1 : 0),
          );
          return 'body';
        case final other?:
          return switch (other.rubyString) {
            'cover' when _frontCover => 'cover',
            'cover' => hasTitlePage ? 'title' : 'toc',
            'title' when !hasTitlePage => 'toc',
            'toc' when !tocAtTop => 'body',
            'after-toc' => 'body',
            final setting => setting,
          };
        case null:
          return 'body';
      }
    }

    var runningBody = bodyOffset;
    var numberingBody = bodyOffset;
    final running = resolve(
      startAt('running_content_start_at'),
      (v) => runningBody = v,
    );
    final numbering = resolve(
      startAt('page_numbering_start_at'),
      (v) => numberingBody = v,
    );
    if (numbering == 'cover') numberingBody = 0;
    var skips = switch ((running, numbering)) {
      ('title', 'title') => (zero, zero),
      ('title', 'toc') => (zero, first),
      ('title', _) => (zero, numberingBody),
      ('toc', 'title') => (first, zero),
      ('toc', 'toc') => (first, first),
      ('toc', _) => (first, numberingBody),
      (_, 'title') => (runningBody, zero),
      (_, 'toc') => (runningBody, first),
      _ => (runningBody, numberingBody),
    };
    // A table of contents placed elsewhere starts them by its pages.
    if (_tocPages case (final start, final end) when !tocAtTop) {
      String? setting(String key) => startAt(key)?.rubyString;
      int skip(String key, int value) => switch (setting(key)) {
        'toc' => start - 1,
        'after-toc' => _ppbook && end.isOdd ? end + 1 : end,
        _ => value,
      };
      skips = (
        skip('running_content_start_at', skips.$1),
        skip('page_numbering_start_at', skips.$2),
      );
    }
    return skips;
  }

  Theme _loadTheme(Document document) {
    var name = document.attr('pdf-theme');
    final dir = document
        .attr('pdf-themesdir')
        ?.replaceAll('{docdir}', document.attr('docdir') ?? '');
    // The default is asciidart's house theme (ADR-0011); with
    // asciidoctor-compat (ADR-0015), asciidoctor-pdf's.
    if (name == null && !asciidoctorCompat(document, CompatFormat.pdf)) {
      name = 'asciidart';
    } else if (name == null &&
        (document.attr('media') ?? 'screen') != 'screen') {
      name = 'default-for-print';
    }
    Theme theme;
    try {
      theme = ThemeLoader(logger: logger).load(name, dir);
    } on ThemeException catch (error) {
      logger.error(error.message);
      theme = ThemeLoader(logger: logger).load();
    }
    if (asciidoctorCompat(document, CompatFormat.pdf)) {
      for (final MapEntry(:key, :value) in asciidoctorPdfLook.entries) {
        if (theme[key] == null) theme[key] = value;
      }
    }
    return theme;
  }

  /// The modern engine's keys as asciidoctor-pdf sets pages, for
  /// `asciidoctor-compat` (ADR-0015): each one the theme doesn't set.
  static const Map<String, ThemeValue> asciidoctorPdfLook = {
    'block_margin_collapse': ThemeBool(false),
    'base_line_breaking': ThemeString('greedy'),
    'base_hyphens': ThemeBool(false),
    'prose_orphans': ThemeNumber(1),
    'prose_widows': ThemeNumber(1),
    'code_orphans': ThemeNumber(1),
    'code_widows': ThemeNumber(1),
    'footnotes_placement': ThemeString('end'),
    'toc_macro_in_section': ThemeBool(false),
    'running_content_on_openers': ThemeBool(true),
    'running_content_on_blank_pages': ThemeBool(true),
    'base_emphasis_inversion': ThemeBool(false),
  };

  /// The page size of the initial layout (the gem's page size: a named
  /// size, `[w, h]` or `w x h`; turned for landscape).
  (double, double) _pageSize(Document document) =>
      _layoutSize(document, _initialLayout(document));

  /// The initial page layout (`portrait` or `landscape`).
  String _initialLayout(Document document) {
    final layout = document.attr('pdf-page-layout') ?? _s('page_layout');
    return layout == 'landscape' ? 'landscape' : 'portrait';
  }

  static const _measurement = r'\d+(?:\.\d+)?(?:in|cm|mm|p[txc])?';

  /// The page size of [layout].
  (double, double) _layoutSize(Document document, String layout) {
    double? dimension(String text) {
      final match = RegExp(r'^(\d+(?:\.\d+)?)(in|mm|cm|p[txc])?$')
          .firstMatch(text.trim());
      if (match == null) return null;
      final points = strToPoints(text.trim());
      final truncated = (points * 10000).truncate() / 10000;
      return truncated > 0 ? truncated : null;
    }

    (double, double)? size;
    final attr = document.attr('pdf-page-size');
    final match = attr == null
        ? null
        : RegExp(
            '^(?:\\[($_measurement), ?($_measurement)\\]|'
            '($_measurement)(?: x |x)($_measurement)|\\S+)\$',
          ).firstMatch(attr);
    if (match != null) {
      final w = match[1] ?? match[3];
      final h = match[2] ?? match[4];
      if (w != null && h != null) {
        final (dw, dh) = (dimension(w), dimension(h));
        if (dw != null && dh != null) size = (dw, dh);
      } else {
        size = _pageSizes[match[0]!.toUpperCase()];
      }
    } else {
      switch (_theme.value('page_size')) {
        case ThemeList(:final values) when values.isNotEmpty:
          double? of(ThemeValue value) => switch (value) {
            ThemeNumber(:final value) when value > 0 => value.toDouble(),
            final other => dimension(other.rubyString),
          };
          final w = of(values[0]);
          final h = of(values.length > 1 ? values[1] : values[0]);
          if (w != null && h != null) size = (w, h);
        case final ThemeValue value:
          size = _pageSizes[value.rubyString.toUpperCase()];
        case null:
          break;
      }
    }
    final (w, h) = size ?? _pageSizes['A4']!;
    return layout == 'landscape' ? (h, w) : (w, h);
  }

  /// The page margins of [layout]: the theme's (or `pdf-page-margin`),
  /// the rotated margins for the layout that isn't the initial one.
  EdgeInsets _marginsFor(Document document, String layout) {
    if (layout != _initialLayout(document)) {
      final rotated = document.attr('pdf-page-margin-rotated') != null
          ? ThemeString(document.attr('pdf-page-margin-rotated')!)
          : _theme.value('page_margin_rotated');
      if (rotated != null) {
        final values = _edgeValues(rotated);
        return EdgeInsets(
          top: values[0],
          right: values[1],
          bottom: values[2],
          left: values[3],
        );
      }
    }
    return _pageMargins(document);
  }

  EdgeInsets _pageMargins(Document document) {
    final values = _edgeValues(
      document.attr('pdf-page-margin') != null
          ? ThemeString(document.attr('pdf-page-margin')!)
          : _theme.value('page_margin'),
    );
    return EdgeInsets(
      top: values[0],
      right: values[1],
      bottom: values[2],
      left: values[3],
    );
  }

  /// A margin or padding value: one number for all sides, or two, three or
  /// four (CSS order).
  List<double> _edgeValues(ThemeValue? value) {
    final numbers = switch (value) {
      ThemeList(:final values) => [for (final v in values) _toPoints(v)],
      ThemeNumber(:final value) => [value.toDouble()],
      ThemeString(:final value) => [
        for (final part
            in value
                .replaceAll(RegExp(r'[\[\]]'), '')
                .split(RegExp(r'[,\s]+'))
                .where((p) => p.isNotEmpty))
          strToPoints(part),
      ],
      _ => const [36.0],
    };
    return switch (numbers.length) {
      0 => [36, 36, 36, 36],
      1 => [numbers[0], numbers[0], numbers[0], numbers[0]],
      2 => [numbers[0], numbers[1], numbers[0], numbers[1]],
      3 => [numbers[0], numbers[1], numbers[2], numbers[1]],
      _ => numbers.sublist(0, 4),
    };
  }

  static double _toPoints(ThemeValue value) => switch (value) {
    ThemeNumber(:final value) => value.toDouble(),
    final other => strToPoints(other.rubyString),
  };

  static String? _fontStyle(String? style) => switch (style) {
    'normal_italic' => 'italic',
    final s => s,
  };

  // Traversal.

  /// Converts the blocks of [node], or the text of a block without any
  /// (an admonition paragraph, say) as prose.
  void _traverse(AbstractBlock node) {
    if (node.blocks.isNotEmpty) {
      for (final block in node.blocks) {
        final saved = _at;
        _at = block.sourceLocation ?? saved;
        final before = _out.length;
        try {
          block.convert();
        } finally {
          _at = saved;
        }
        if (_reportTags != null && block is! Section) {
          _tagLast(before, block);
        }
      }
    } else if (node is Block && node.contentModel != ContentModel.compound) {
      if (node.content() case final text?) {
        final align = _alignOf(node.roles) ?? _baseTextAlign;
        _out.add(
          CustomBox(_textBox(text, _font, align: align, hyphenate: true)),
        );
      }
    }
  }

  /// The block after [block] in reading order, looking out of the
  /// containers it ends (the gem's `next_enclosed_block`).
  AbstractBlock? _nextEnclosedBlock(AbstractBlock block) {
    final next = _nextEnclosed(block);
    // (Past a paragraph of index terms alone, in the modern engine.)
    if (next != null && _roomless(next)) return _nextEnclosedBlock(next);
    return next;
  }

  AbstractBlock? _nextEnclosed(AbstractBlock block) {
    if (block is Document) return null;
    final parent = block.parent;
    if (parent is! AbstractBlock) return null;
    final siblings =
        block is ListItem &&
            parent is ListBlock &&
            parent.context == BlockContext.dlist
        ? [
            for (final entry in parent.entries) ...[
              ...entry.terms,
              entry.description,
            ],
          ]
        : <AbstractBlock?>[...parent.blocks];
    final index = siblings.indexOf(block);
    // A block made up by the converter, not among its parent's: none.
    if (index < 0) return null;
    if (index < siblings.length - 1) {
      if (block.context == BlockContext.open &&
          block.style == 'table-container') {
        return _nextEnclosedBlock(parent);
      }
      return siblings[index + 1];
    }
    final parentContext = parent.context;
    if (parentContext == BlockContext.listItem ||
        (parentContext == BlockContext.open && parent.style != 'abstract') ||
        (parent is Section &&
            !_isAbstract(parent) &&
            // (A section in a box of its own, its role's: the end of the
            // box ends it.)
            _boxedRole(parent) == null)) {
      return _nextEnclosedBlock(parent);
    }
    // The last item of a nested list: the next block after the item the
    // list is in.
    if (block is ListItem) {
      if (parent.parent case final ListItem grandparent) {
        return _nextEnclosedBlock(grandparent);
      }
    }
    return null;
  }

  /// The bottom margin of a block of [category] followed by [next] (the
  /// gem's `theme_margin`): the block category's margin before a section,
  /// nothing at the end.
  double _themeMargin(String category, String side, AbstractBlock? next) {
    if (next == null) return 0;
    final key = next is Section ? 'block' : category;
    return (_n('${key}_margin_$side') ?? 0).toDouble();
  }

  /// The theme category whose `_margin_top` and `_margin_bottom` keys
  /// space [node] in the modern engine (`code` for a listing, `list` for
  /// a list...).
  static String _spacingCategory(AbstractBlock node) => switch (node.context) {
    BlockContext.paragraph => 'prose',
    BlockContext.listing || BlockContext.literal => 'code',
    BlockContext.image => 'image',
    BlockContext.audio || BlockContext.video => 'media',
    BlockContext.table => 'table',
    BlockContext.quote => 'quote',
    BlockContext.verse => 'verse',
    BlockContext.sidebar => 'sidebar',
    BlockContext.example => 'example',
    BlockContext.admonition => 'admonition',
    BlockContext.ulist || BlockContext.olist => 'list',
    BlockContext.dlist => 'description_list',
    BlockContext.colist => 'callout_list',
    BlockContext.open => 'open',
    BlockContext.thematicBreak => 'thematic_break',
    BlockContext.pass => 'pass',
    BlockContext.stem => 'stem',
    _ => 'block',
  };

  /// The space below [node], followed by [next] (the next enclosed block
  /// by default): the gem's margin ([fallback]'s), or in the modern engine
  /// the block's own `<category>_margin_bottom`, and at least the next
  /// block's `<category>_margin_top` (adjacent margins collapse to the
  /// larger, as in CSS). None at the end of a container.
  double _marginBelow(
    AbstractBlock node, {
    AbstractBlock? next,
    String fallback = 'block',
  }) {
    var following = next ?? _nextEnclosedBlock(node);
    final base = _themeMargin(fallback, 'bottom', following);
    if (!_collapseMargins || following == null) return base;
    // Past images that float out of the flow, to the block that follows
    // in it (a paragraph's space before a heading).
    if (_floatsOut(following) && !_floatsOut(node)) {
      following = _flowNext(following);
      if (following == null) return 0;
    }
    // (A role's `role_<role>_margin_bottom` and `_margin_top` before its
    // category's.)
    double? roleMargin(AbstractBlock block, String side) {
      for (final role in block.roles.reversed) {
        if (_n('role_${role}_margin_$side') case final value?) {
          return value.toDouble();
        }
      }
      return null;
    }

    final own =
        roleMargin(node, 'bottom') ??
        _n('${_spacingCategory(node)}_margin_bottom')?.toDouble() ??
        base;
    // A section's heading: the larger of the two, the heading's margin
    // above taking its part.
    if (following is Section) {
      return math.max(0, own - _sectionMarginTop(following));
    }
    final above =
        roleMargin(following, 'top') ??
        _n('${_spacingCategory(following)}_margin_top') ??
        0;
    return math.max(own, above.toDouble());
  }

  /// The block before [node] in the flow: its previous sibling, past
  /// images that float out of it (`image_placement`, modern engine), as
  /// Typst's floating figures leave a paragraph after a paragraph.
  AbstractBlock? _flowPrevious(AbstractBlock node) {
    var previous = _previousSibling(node);
    while (previous != null && _floatsOut(previous)) {
      previous = _previousSibling(previous);
    }
    return previous;
  }

  /// The block after [node] in the flow: the next enclosed block, past
  /// images that float out of it.
  AbstractBlock? _flowNext(AbstractBlock node) {
    var next = _nextEnclosedBlock(node);
    while (next != null && _floatsOut(next)) {
      next = _nextEnclosedBlock(next);
    }
    return next;
  }

  /// Whether [block] is an image that floats out of the flow
  /// (`image_placement`, modern engine).
  bool _floatsOut(AbstractBlock block) {
    if (block.context != BlockContext.image ||
        !const {
          'auto',
          'top',
          'bottom',
        }.contains(block.attr('placement') ?? _imagePlacement)) {
      return false;
    }
    // (Images float only at the top level: not in a sidebar, a list...)
    final parent = block.parent;
    return parent is Section ||
        parent is Document ||
        parent?.context == BlockContext.preamble;
  }

  /// The space above [section]'s heading (its box's, for a section role
  /// the theme styles).
  double _sectionMarginTop(Section section) {
    if (section.hasOption('notitle')) return 0;
    final level = (section.level ?? 0) + 1;
    if (_boxedRole(section) case final role?) {
      final category = 'section_role_$role';
      return ((_n('${category}_margin_top') ?? 0) +
              (_n('${category}_heading_margin_top') ??
                  _n('heading_h${level}_margin_top') ??
                  _n('heading_margin_top') ??
                  0))
          .toDouble();
    }
    return (_n('heading_h${level}_margin_top') ?? _n('heading_margin_top') ?? 0)
        .toDouble();
  }

  /// The space above [node] in the modern engine (`<category>_margin_top`)
  /// that the block before it hasn't given: none after a block (whose
  /// space below collapses with it) or at the start of a container but a
  /// section, after a heading what its margin below leaves.
  double _marginAbove(AbstractBlock node) {
    if (!_collapseMargins) return 0;
    final above = _n('${_spacingCategory(node)}_margin_top')?.toDouble();
    if (above == null || above <= 0) return 0;
    if (_previousSibling(node) != null) return 0;
    final parent = node.parent;
    if (parent is! Section) return 0;
    final level = (parent.level ?? 0) + 1;
    final heading =
        (_n('heading_h${level}_margin_bottom') ??
                _n('heading_margin_bottom') ??
                0)
            .toDouble();
    return math.max(0, above - heading);
  }

  // Sections.

  /// Converts [section]: its heading, then its blocks.
  void convertSection(Section section) {
    final sectname = section.sectname;
    if (_isAbstract(section)) {
      _abstract(section);
      return;
    }
    // An empty index is left out.
    final indexSection = sectname == 'index';
    if (indexSection && _index.isEmpty) return;
    var title = _headingText(section);
    final separator =
        section.attr('separator') ?? _document.attr('title-separator') ?? '';
    if (separator.isNotEmpty && title.contains('$separator ')) {
      final at = title.lastIndexOf('$separator ');
      title =
          '${title.substring(0, at)}\n<em class="subtitle">'
          '${title.substring(at + separator.length + 1)}</em>';
    }
    final hlevel = (section.level ?? 0) + 1;
    final align =
        _s('heading_h${hlevel}_text_align') ??
        _s('heading_text_align') ??
        _baseTextAlign;
    final anchor = section.id ?? '__section-${section.hashCode}';
    final hidden = section.hasOption('notitle');
    final part = sectname == 'part';
    final chapterlike =
        !part &&
        (sectname == 'chapter' ||
            (_document.doctype == 'book' && section.level == 1));
    var startedNew = false;
    if (part) {
      if (_s('heading_part_break_before') == 'always') startedNew = true;
    } else if (chapterlike) {
      final parent = section.parent;
      final firstOfPart =
          parent is Section &&
          parent.sectname == 'part' &&
          parent.blocks.whereType<Section>().firstOrNull == section;
      final partAfter = _s('heading_part_break_after');
      if ((_s('heading_chapter_break_before') == 'always' &&
              !(partAfter == 'avoid' && firstOfPart)) ||
          (partAfter == 'always' && firstOfPart)) {
        startedNew = true;
      }
    }
    if (startedNew) {
      _out.add(
        BreakBox.page(
          side: _ppbook && !section.hasOption('nonfacing')
              ? PageSide.recto
              : null,
        ),
      );
    }
    // A section with a role the theme styles (`section_role_<role>_*`,
    // modern engine): its heading and content in a box, as a sidebar.
    final boxed = _boxedRole(section);
    void content() {
      if (hidden) {
        // No heading, but the section still names its pages' running
        // content.
        _out.add(
          CustomBox(
            const _Nothing(),
            style: BoxStyle(
              anchor: anchor,
              marks: _sectionMarks(section, part: part),
            ),
          ),
        );
      } else {
        // The modern engine: a section that starts its parent's, its
        // heading right after the parent's, the spaces between them
        // collapse.
        final parent = section.parent;
        final collapse =
            _collapseMargins &&
                !startedNew &&
                parent is Section &&
                parent.blocks.firstOrNull == section &&
                !parent.hasOption('notitle') &&
                _boxedRole(parent) == null
            ? (_n('heading_h${(parent.level ?? 0) + 1}_margin_bottom') ??
                      _n('heading_margin_bottom') ??
                      0)
                  .toDouble()
            : 0.0;
        _heading(
          title,
          level: hlevel,
          align: align,
          anchor: anchor,
          arrange: !startedNew,
          hasContent: section.blocks.isNotEmpty,
          marks: _sectionMarks(section, part: part),
          outdent: true,
          collapse: collapse,
        );
      }
      _sections.add((section, anchor));
      if (indexSection) {
        final slot = _indexSlot = <LayoutBox>[];
        _out.add(
          BlockBox(slot, style: BoxStyle(margin: _outdented(EdgeInsets.zero))),
        );
      } else {
        _traverse(section);
      }
    }

    if (boxed == null) {
      content();
    } else {
      final category = 'section_role_$boxed';
      final saved = _headingRole;
      final savedTheme = _theme;
      _headingRole = category;
      // Inside the section, its role's keys in place of the theme's
      // (section_role_<role>_prose_margin_bottom for prose_margin_bottom).
      _theme = _theme.overlaid('${category}_', '');
      final List<LayoutBox> children;
      try {
        children = _collect(() => _withFont(category, content));
      } finally {
        _headingRole = saved;
        _theme = savedTheme;
      }
      _out.add(
        BlockBox(
          children,
          style: BoxStyle(
            padding: _padding('${category}_padding'),
            cloneEdges: _cloneEdges(category),
            margin: _outdented(
              EdgeInsets(
                top: (_n('${category}_margin_top') ?? 0).toDouble(),
                bottom: _marginBelow(section),
              ),
            ),
            decoration: _blockDecoration(category),
            // In the middle or at the bottom of its page, when it starts
            // the page and fits on it (a dedication).
            verticalAlign: switch (_choice(
              '${category}_vertical_align',
              _alignsV,
            )) {
              'middle' || 'center' => VerticalAlign.middle,
              'bottom' => VerticalAlign.bottom,
              _ => null,
            },
          ),
        ),
      );
    }
    if (chapterlike) _footnotes(section);
  }

  /// The role of [section] the theme styles as a box (it has keys
  /// `section_role_<role>_...`; a hyphen in the role is an underscore
  /// there, as in other theme keys), in the modern engine.
  String? _boxedRole(Section section) {
    for (final role in section.roles) {
      final name = role.replaceAll('-', '_');
      final prefix = 'section_role_${name}_';
      if (_theme.keys.any((key) => key.startsWith(prefix))) return name;
    }
    return null;
  }

  /// The theme category of the boxed section whose heading is being set
  /// (its `<category>_heading_*` keys replace the heading's), if any.
  String? _headingRole;

  /// The text of [section]'s heading: its numbered title, or in the
  /// modern engine the theme's `heading_h<n>_content` template (ADR-0010)
  /// with `title`, `numbered-title`, `number` (`1.2.`, a part's `I`),
  /// `numeral` (`1`, `I`) and `signifier` (`Chapter`, `Part`); a label
  /// on a line of its own, in gray: see doc/pdf.md.
  String _headingText(Section section) {
    final numbered = _numberedTitle(section);
    final level = (section.level ?? 0) + 1;
    final template = _s('heading_h${level}_content');
    if (template == null) return numbered;
    final isNumbered = _isNumbered(section);
    final part = section.sectname == 'part';
    final signifier = !isNumbered || _document.doctype != 'book'
        ? null
        : part
        ? _document.attributes['part-signifier'] ?? 'Part'
        : section.level == 1
        ? _document.attributes['chapter-signifier'] ?? 'Chapter'
        : null;
    return _render(template, {
      'title': section.title ?? '',
      'numbered-title': numbered,
      'number': isNumbered
          ? (part ? section.numeral : section.sectnum())
          : null,
      'numeral': isNumbered ? section.numeral : null,
      'signifier': signifier == null || signifier.isEmpty
          ? null
          : _escapeMarkup(signifier),
    });
  }

  /// Whether [section] shows a number (numbered, no caption of its own,
  /// within `sectnumlevels`).
  bool _isNumbered(Section section) {
    final sectnumlevels =
        int.tryParse(_document.attr('sectnumlevels') ?? '') ?? 3;
    return section.numbered &&
        section.caption == null &&
        (section.level ?? 0) <= sectnumlevels &&
        section.numeral != null;
  }

  /// [text] escaped for the text markup.
  static String _escapeMarkup(String text) =>
      text.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  /// [source], a Mustache template (ADR-0010), rendered with [values]
  /// (an empty value counts as none, for optional parts).
  String _render(String source, Map<String, String?> values) =>
      renderTemplate(source, values);

  /// Whether a part has started (an appendix ends it).
  bool _inPart = false;

  /// The running marks a section's heading sets (for the running
  /// content): a part or chapter of a book, else a section, by the
  /// levels it counts for.
  Map<String, String> _sectionMarks(Section section, {required bool part}) {
    final index = '${_sections.length}';
    final level = section.level ?? 1;
    if (_document.doctype == 'book' && (part || level == 1)) {
      if (part) {
        _inPart = true;
        return {'part': index};
      }
      return {
        'chapter': index,
        if (section.sectname == 'appendix' && _inPart) 'part': '',
      };
    }
    return {for (var k = level; k <= 6; k++) 'section-$k': index};
  }

  /// Converts the discrete heading [node] (the gem's
  /// `convert_floating_title`): a heading kept with what follows it.
  void convertFloatingTitle(Block node) {
    final hlevel = (node.level ?? 0) + 1;
    final align =
        _alignOf(node.roles) ??
        _s('heading_h${hlevel}_text_align') ??
        _s('heading_text_align') ??
        _baseTextAlign;
    final last = node.parent?.blocks.lastOrNull == node;
    _heading(
      node.title ?? '',
      level: hlevel,
      align: align,
      anchor: node.id,
      arrange: !last,
      hasContent: !last,
      outdent: node.parent is Section,
    );
  }

  /// The section title as the gem numbers it (`numbered_title formal:
  /// true`).
  String _numberedTitle(Section section, {bool formal = true}) {
    final title = section.title ?? '';
    final level = section.level ?? 0;
    final doc = _document;
    final sectnumlevels = int.tryParse(doc.attr('sectnumlevels') ?? '') ?? 3;
    if (section.numbered && section.caption == null && level <= sectnumlevels) {
      if (doc.doctype == 'book' && level <= 1) {
        final numbered = level == 0
            ? '${section.sectnum('.', ':')} $title'
            : '${section.sectnum()} $title';
        if (!formal) return numbered;
        final signifier = level == 0
            ? doc.attributes['part-signifier'] ?? 'Part'
            : doc.attributes['chapter-signifier'] ?? 'Chapter';
        return signifier.isEmpty ? numbered : '$signifier $numbered';
      }
      return '${section.sectnum()} $title';
    }
    if (level == 0) return title;
    return section.captionedTitle();
  }

  /// The font of heading level [level] (the gem's `theme_font :heading,
  /// level:`).
  _FontState _headingFont(int level) {
    final role = _headingRole;
    String? h(String key) =>
        (role == null ? null : _s('${role}_heading_$key')) ??
        _s('heading_h${level}_$key') ??
        _s('heading_$key');
    final sizeValue =
        (role == null ? null : _theme.value('${role}_heading_font_size')) ??
        _theme.value('heading_h${level}_font_size') ??
        _theme.value('heading_font_size');
    final size = switch (sizeValue) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => resolveFontSize(
        value,
        _rootFontSize,
        _rootFontSize,
      ),
      _ => _rootFontSize,
    };
    return _FontState(
      family: h('font_family') ?? _s('base_font_family') ?? _font.family,
      style: _fontStyle(h('font_style')) ?? 'normal',
      size: size,
      color:
          (role == null ? null : _c('${role}_heading_font_color')) ??
          _c('heading_h${level}_font_color') ??
          _c('heading_font_color') ??
          _font.color,
      lineHeight:
          (_n('heading_h${level}_line_height') ??
                  _n('heading_line_height') ??
                  _font.lineHeight)
              .toDouble(),
      kerning: switch (h('font_kerning')) {
        'normal' => true,
        'none' => false,
        _ => _font.kerning,
      },
      transform: h('text_transform'),
      // Under Typst's model: the level's leading (heading_h<n>_leading).
      leadingKey: [
        if (role != null) '${role}_heading_h${level}_leading',
        'heading_h${level}_leading',
        'heading_leading',
      ].where((key) => _theme.value(key) != null).firstOrNull,
    );
  }

  /// A heading of [level]: its text box, margins, and the space it needs
  /// below it to stay on its page (the gem's `arrange_heading` with a
  /// numeric `heading_min_height_after`).
  void _heading(
    String title, {
    required int level,
    required String align,
    String? anchor,
    bool arrange = false,
    bool hasContent = false,
    Map<String, String> marks = const {},
    _FontState? font,
    bool outdent = false,
    double collapse = 0,
  }) {
    font ??= _headingFont(level);
    var text = title;
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform);
    }
    final styles = <String>{
      if (font.style == 'bold' || font.style == 'bold_italic') 'bold',
      if (font.style == 'italic' || font.style == 'bold_italic') 'italic',
    };
    final box = _textBox(
      text,
      font,
      align: align,
      inheritedStyles: styles,
      inherit: _decoration('heading', level),
      normalize: false,
    );
    final role = _headingRole;
    // (Right after another heading, the larger of its space below and
    // this one's above: [collapse] is that space below.)
    final marginTop = math.max<double>(
      0,
      ((role == null ? null : _n('${role}_heading_margin_top')) ??
                  _n('heading_h${level}_margin_top') ??
                  _n('heading_margin_top') ??
                  0)
              .toDouble() -
          collapse,
    );
    final marginBottom =
        ((role == null ? null : _n('${role}_heading_margin_bottom')) ??
                _n('heading_h${level}_margin_bottom') ??
                _n('heading_margin_bottom') ??
                0)
            .toDouble();
    CustomContent content = box;
    // The modern engine's `heading_min_height_after: auto`: the heading
    // stays with what starts after it (as much of it as may start a page:
    // a paragraph's first lines), as Typst's sticky headings.
    final sticky =
        arrange &&
        hasContent &&
        _theme.value('heading_min_height_after') == const ThemeString('auto');
    if (arrange) {
      final minAfter = _theme.value('heading_min_height_after');
      var below = switch (minAfter) {
        ThemeNumber(:final value) when hasContent => value.toDouble(),
        _ => 0.0,
      };
      if (below > 0) below += marginBottom;
      content = _NeedsRoom(box, below);
    }
    final pageTop =
        (_n('heading_h${level}_margin_page_top') ??
                _n('heading_margin_page_top') ??
                0)
            .toDouble();
    if (pageTop > 0) content = _PageTopGap(content, pageTop);
    final margin = outdent
        ? _outdented(EdgeInsets(top: marginTop, bottom: marginBottom))
        : EdgeInsets(top: marginTop, bottom: marginBottom);
    // The padding and border of the level (the gem's `pad_box` and
    // `theme_fill_and_stroke_bounds`).
    final category = 'heading_h$level';
    final padding = _theme.value('${category}_padding');
    final border =
        _theme.value('${category}_border_width') != null &&
            (_c('${category}_border_color') ?? _c('base_border_color')) != null
        ? _headingBorder(category)
        : null;
    // Floating images wait for no heading: it follows them (unless
    // `heading_float_barrier` is false: Typst's headings pass floats
    // waiting for the next page).
    final barrier =
        _theme.value('heading_float_barrier') != const ThemeBool(false);
    // In the middle or at the bottom of its page, when it starts the page
    // (a part's title, as Typst's align(horizon) sets it).
    final verticalAlign = switch (_choice(
      '${category}_vertical_align',
      _alignsV,
    )) {
      'middle' || 'center' => VerticalAlign.middle,
      'bottom' => VerticalAlign.bottom,
      _ => null,
    };
    if (padding == null && border == null && verticalAlign == null) {
      _out.add(
        CustomBox(
          content,
          style: BoxStyle(
            margin: margin,
            anchor: anchor,
            marks: marks,
            floatBarrier: barrier,
            keepWithNext: sticky,
          ),
        ),
      );
      return;
    }
    _out.add(
      BlockBox(
        [CustomBox(content)],
        style: BoxStyle(
          margin: margin,
          padding: _padding('${category}_padding'),
          anchor: anchor,
          marks: marks,
          decoration: border,
          floatBarrier: barrier,
          verticalAlign: verticalAlign,
          keepWithNext: sticky,
        ),
      ),
    );
  }

  /// The border of heading theme [category] (`heading_h2`...), around the
  /// heading and its padding.
  BoxDecoration _headingBorder(String category) {
    final widthValue = _theme.value('${category}_border_width');
    final width = switch (widthValue) {
      ThemeNumber(:final value) => value.toDouble(),
      _ => 0.0,
    };
    final widths = _sideWidths(widthValue);
    final color = pdfColorOf(
      _c('${category}_border_color') ?? _c('base_border_color'),
    );
    final style = _s('${category}_border_style');
    final radius = widths == null
        ? (_n('${category}_border_radius') ?? 0).toDouble()
        : 0.0;
    return (page, rect, {required first, required last}) {
      if (color == null || (width <= 0 && widths == null)) return;
      _strokeBounds(
        page.canvas,
        rect,
        color,
        width: width,
        widths: widths,
        style: style,
        radius: radius,
      );
    };
  }

  // The preamble.

  /// Converts the preamble: its first paragraph is the lead (when the
  /// document has sections), and a block margin follows it.
  void convertPreamble(Block node) {
    final blocks = node.blocks;
    if (blocks.isNotEmpty &&
        blocks.first.context == BlockContext.paragraph &&
        _document.sections.isNotEmpty &&
        blocks.first.role == null) {
      blocks.first.setAttr('role', 'lead');
    }
    _traverse(node);
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
    convertToc(node, placement: 'preamble');
  }

  /// The font of theme [category] over [inherited] (the gem's
  /// `theme_font category`).
  _FontState _themeFont(String category, _FontState inherited) {
    final sizeValue = _theme.value('${category}_font_size');
    final size = switch (sizeValue) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => resolveFontSize(
        value,
        inherited.size,
        _rootFontSize,
      ),
      _ => inherited.size,
    };
    return _FontState(
      family: _s('${category}_font_family') ?? inherited.family,
      style: _fontStyle(_s('${category}_font_style')) ?? inherited.style,
      size: size,
      color: _c('${category}_font_color') ?? inherited.color,
      lineHeight: (_n('${category}_line_height') ?? inherited.lineHeight)
          .toDouble(),
      kerning: switch (_s('${category}_font_kerning')) {
        'none' => false,
        'normal' => true,
        _ => inherited.kerning,
      },
      transform: _s('${category}_text_transform') ?? inherited.transform,
      leadingKey: _theme.value('${category}_leading') != null
          ? '${category}_leading'
          : inherited.leadingKey,
    );
  }

  // Paragraphs.

  /// Converts the paragraph [node].
  void convertParagraph(Block node) => _paragraph(node);

  /// Adds the paragraph [node], aligned to [textAlign] unless a role
  /// aligns it, its first line in [firstLine]'s font if given.
  void _paragraph(
    Block node, {
    String? textAlign,
    _FontState? firstLine,
    String? firstLineTransform,
  }) {
    final roles = node.roles;
    String? roleAlign;
    for (final role in roles.reversed) {
      roleAlign = _alignOf([role]) ?? _s('role_${role}_text_align');
      if (roleAlign != null) break;
    }
    final align = roleAlign ?? textAlign ?? _baseTextAlign;
    var font = _font;
    for (final role in roles) {
      font = _themeFont('role_$role', font);
    }
    var indent = 0.0;
    if (align == 'justify' || align == 'left') {
      final textIndent = _length('prose_text_indent', font.size) ?? 0;
      final inner = _length('prose_text_indent_inner', font.size) ?? 0;
      if (textIndent > 0) {
        indent = textIndent;
      } else if (inner > 0 &&
          _flowPrevious(node)?.context == BlockContext.paragraph) {
        indent = inner;
      }
    }
    final next = _flowNext(node);
    final innerMargin = _n('prose_margin_inner');
    var marginBottom =
        innerMargin != null && next?.context == BlockContext.paragraph
        ? innerMargin.toDouble()
        : _marginBelow(node, next: next, fallback: 'prose');
    // The modern engine: a role's indent, and space before the next block,
    // in place of the prose's (`role_<role>_text_indent`,
    // `role_<role>_margin_bottom`).
    for (final role in roles) {
      if (_length('role_${role}_text_indent', font.size) case final value?) {
        indent = value;
      }
      final parent = node.parent;
      final last =
          parent is! AbstractBlock || identical(parent.blocks.last, node);
      if (_n('role_${role}_margin_bottom') case final value? when !last) {
        marginBottom = value.toDouble();
      }
    }

    var content = node.content() ?? '';
    // The modern engine: a paragraph of concealed index terms alone takes
    // no room (their anchors where it is), as Typst's index entries.
    if (!node.hasTitle) {
      final terms = RegExp('<a id="([^"]+)" type="indexterm">$_dummyText</a>')
          .allMatches(content)
          .toList();
      if (terms.isNotEmpty &&
          content
              .replaceAll(
                RegExp('<a id="[^"]+" type="indexterm">$_dummyText</a>'),
                '',
              )
              .trim()
              .isEmpty) {
        // (They go with the block after them, as Typst attaches tags to
        // the content that follows.)
        _out.add(
          BlockBox([
            for (final term in terms)
              CustomBox(const _Nothing(), style: BoxStyle(anchor: term[1])),
          ], style: const BoxStyle(keepWithNext: true)),
        );
        return;
      }
    }
    if (font.transform case final transform? when transform != 'none') {
      content = transformText(content, transform);
    }
    content = _hyphenated(content, align);
    if (node.hasTitle) _caption(node, labeled: false);
    // The modern engine keeps a paragraph's lines together at page
    // breaks: no fewer than prose_orphans at the bottom of a page and
    // prose_widows at the top of the next (2 each by default).
    final box = _textBox(
      content,
      font,
      align: align,
      indent: indent,
      orphans: (_n('prose_orphans') ?? 2).toInt(),
      widows: (_n('prose_widows') ?? 2).toInt(),
    );
    if (_floatGroup case final group? when _floatNext == node) {
      final metrics = _lineMetrics(font);
      final prawnFont = _fonts.font(font.family, font.style);
      final following = _nextEnclosedBlock(node);
      group.paragraphs.add(
        _FloatParagraph(
          box,
          _textBox(content, font, align: align, indent: indent, gaps: false),
          marginBottom: marginBottom,
          blockMargin: _themeMargin('block', 'bottom', following),
          paddingTop: metrics.paddingTop,
          paddingBottom: metrics.paddingBottom,
          lineLength:
              font.lineHeight * font.size +
              metrics.leading +
              metrics.paddingTop,
          descender: prawnFont.descenderAt(font.size),
          anchor: node.id,
        ),
      );
      if (following case final Block block
          when block.context == BlockContext.paragraph) {
        _floatNext = block;
      } else {
        _floatGroup = _floatNext = null;
      }
      return;
    }
    CustomContent text = box;
    if (firstLine != null) {
      text = FirstLineTextBox(
        _textBox(
          content,
          firstLine,
          align: align,
          indent: indent,
          singleLine: true,
        ),
        box.state,
        box.layout,
        transform: firstLineTransform,
      );
    }
    _out.add(
      CustomBox(
        text,
        style: BoxStyle(
          margin: EdgeInsets(bottom: marginBottom),
          anchor: node.id,
        ),
      ),
    );
  }

  /// The text alignment a `text-<align>` role among [roles] selects (the
  /// last one wins).
  static String? _alignOf(List<String> roles) {
    for (final role in roles.reversed) {
      if (role.startsWith('text-') &&
          const {
            'justify',
            'left',
            'center',
            'right',
          }.contains(role.substring(5))) {
        return role.substring(5);
      }
    }
    return null;
  }

  AbstractBlock? _previousSibling(AbstractBlock node) {
    final parent = node.parent;
    if (parent is! AbstractBlock) return null;
    var index = parent.blocks.indexOf(node);
    // (In the modern engine, past paragraphs of index terms alone: they
    // take no room.)
    while (index > 0 && _roomless(parent.blocks[index - 1])) {
      index--;
    }
    return index > 0 ? parent.blocks[index - 1] : null;
  }

  /// Whether [block] is a paragraph of concealed index terms alone, which
  /// the modern engine sets in no room.
  bool _roomless(AbstractBlock block) =>
      block.context == BlockContext.paragraph &&
      !block.hasTitle &&
      block is Block &&
      block.lines.isNotEmpty &&
      block.lines.every(
        (line) => RegExp(r'^\s*(\(\(\(.*?\)\)\)\s*)+$').hasMatch(line),
      );

  // Blocks with a background and a border.

  /// The decoration of a block of theme [category] (the gem's
  /// `theme_fill_and_stroke_block`): its background and border, the
  /// border centered on the block's edge, with a dashed line where a split
  /// block continues; [extra] paints more.
  BoxDecoration? _blockDecoration(
    String category, {
    ThemeColor? background,
    bool noBorder = false,
    BoxDecoration? extra,
  }) {
    final widthValue = noBorder
        ? null
        : _theme.value('${category}_border_width');
    var borderWidth = switch (widthValue) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeList(:final values) when values.isNotEmpty => _toPoints(values[0]),
      _ => 0.0,
    };
    final sideWidths = widthValue is ThemeList;
    var fill = background ?? _c('${category}_background_color');
    if (fill is TransparentColor) fill = null;
    if (borderWidth <= 0 && fill == null) return extra;
    final stroke = _c('${category}_border_color') ?? _c('base_border_color');
    final pageBackground =
        _c('page_background_color') ?? const HexColor('FFFFFF');
    final radius = sideWidths
        ? 0.0
        : (_n('${category}_border_radius') ?? 0).toDouble();
    final dashRadius = radius + borderWidth;
    final PdfColor? gapColor;
    final double shift;
    if (borderWidth > 0) {
      if (stroke == pageBackground) {
        (gapColor, shift) = (pdfColorOf(pageBackground), borderWidth * 0.5);
      } else if (fill != null && fill != stroke) {
        (gapColor, shift) = (pdfColorOf(fill), 0.0);
      } else {
        (gapColor, shift) = (pdfColorOf(pageBackground), 0.0);
      }
    } else {
      borderWidth = 0.5;
      (gapColor, shift) = (pdfColorOf(pageBackground), borderWidth * 0.5);
    }
    final hasStroke = (_n('${category}_border_width') ?? 0) > 0 || sideWidths;
    return (page, rect, {required first, required last}) {
      final canvas = page.canvas..save();
      if (pdfColorOf(fill) case final color?) {
        canvas.setFillColor(color);
        radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
        canvas.fill();
      }
      if (hasStroke) {
        if (pdfColorOf(stroke) case final color?) {
          _strokeBounds(
            canvas,
            rect,
            color,
            width: borderWidth,
            widths: _sideWidths(widthValue),
            style: _s('${category}_border_style'),
            radius: radius,
          );
        }
      }
      // A dashed line where the block continues from or to another page.
      void dashed(double y) {
        if (gapColor == null) return;
        canvas
          ..save()
          ..setStrokeColor(gapColor)
          ..setLineWidth(borderWidth * 1.2)
          ..dash([borderWidth * 1.2 * 4])
          ..moveTo(rect.left + dashRadius, y)
          ..lineTo(rect.right - dashRadius, y)
          ..stroke()
          ..restore();
      }

      if (!first) dashed(rect.top - shift);
      if (!last) dashed(rect.bottom + shift);
      canvas.restore();
      extra?.call(page, rect, first: first, last: last);
    };
  }

  /// The widths of a border's sides (top, right, bottom, left) from theme
  /// [value]: one width for all, or two (top and bottom, then sides), or
  /// four; null for one width for all.
  List<double>? _sideWidths(ThemeValue? value) => switch (value) {
    ThemeList(:final values) => switch ([
      for (final v in values)
        if (v is ThemeNull) 0.0 else _toPoints(v),
    ]) {
      [final a, final b] => [a, b, a, b],
      [final a, final b, final c, final d, ...] => [a, b, c, d],
      [final a, final b, final c] => [a, b, c, b],
      [final a] => [a, a, a, a],
      _ => null,
    },
    _ => null,
  };

  /// Strokes the border of [rect] in [color] (the gem's
  /// `fill_and_stroke_bounds`): [width] all around, or [widths] side by
  /// side (top, right, bottom, left), in [style] (`solid`, `dashed`,
  /// `dotted`, `double`) with corners of [radius].
  static void _strokeBounds(
    PdfCanvas canvas,
    PdfRect rect,
    PdfColor color, {
    double width = 0.5,
    List<double>? widths,
    String? style,
    double radius = 0,
  }) {
    if (widths case [final top, final right, final bottom, final left]) {
      if (top > 0) {
        _horizontalRule(
          canvas,
          color,
          rect.left - left * 0.5,
          rect.right - right * 0.5,
          rect.top,
          top,
          style,
        );
      }
      if (right > 0) {
        _verticalRule(
          canvas,
          color,
          rect.right,
          rect.top + top * 0.5,
          rect.bottom - bottom * 0.5,
          right,
          style,
        );
      }
      if (bottom > 0) {
        _horizontalRule(
          canvas,
          color,
          rect.left - left * 0.5,
          rect.right - right * 0.5,
          rect.bottom,
          bottom,
          style,
        );
      }
      if (left > 0) {
        _verticalRule(
          canvas,
          color,
          rect.left,
          rect.top + top * 0.5,
          rect.bottom - bottom * 0.5,
          left,
          style,
        );
      }
      return;
    }
    void outline(PdfRect r) => _roundedRectangle(canvas, r, radius);
    canvas
      ..save()
      ..setStrokeColor(color);
    switch (style) {
      case 'dashed':
        canvas
          ..setLineWidth(width)
          ..dash([width * 4]);
      case 'dotted':
        canvas
          ..setLineWidth(width)
          ..dash([width]);
      case 'double':
        final single = width / 3;
        final inset = single * 2;
        canvas.setLineWidth(single);
        outline(rect);
        canvas.stroke();
        outline(
          PdfRect(
            rect.left + inset,
            rect.bottom + inset,
            rect.width - inset * 2,
            rect.height - inset * 2,
          ),
        );
        canvas
          ..stroke()
          ..restore();
        return;
      default:
        canvas.setLineWidth(width);
    }
    outline(rect);
    canvas
      ..stroke()
      ..restore();
  }

  /// Adds [rect] with corners of [radius] to [canvas]'s path as Prawn
  /// draws it (`rounded_rectangle`): from the top left corner, clockwise,
  /// so that a dash pattern starts where Prawn's does.
  static void _roundedRectangle(PdfCanvas canvas, PdfRect rect, double radius) {
    const kappa = 4 * (1.4142135623730951 - 1) / 3;
    final points = [
      (rect.left, rect.top),
      (rect.right, rect.top),
      (rect.right, rect.bottom),
      (rect.left, rect.bottom),
    ];
    // The point [distance] before the end [to] of the line from [from].
    (double, double) onLine(
      double distance,
      (double, double) from,
      (double, double) to,
    ) {
      final (x0, y0) = from;
      final (x1, y1) = to;
      final length = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
      final p = length == 0 ? 1.0 : (length - distance) / length;
      return (x0 + p * (x1 - x0), y0 + p * (y1 - y0));
    }

    final (startX, startY) = onLine(radius, points[1], points[0]);
    canvas.moveTo(startX, startY);
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final corner = points[(i + 1) % 4];
      final b = points[(i + 2) % 4];
      final (x1, y1) = onLine(radius, a, corner);
      final (bx1, by1) = onLine(radius - radius * kappa, a, corner);
      final (x2, y2) = onLine(radius, b, corner);
      final (bx2, by2) = onLine(radius - radius * kappa, b, corner);
      canvas
        ..lineTo(x1, y1)
        ..curveTo(bx1, by1, bx2, by2, x2, y2);
    }
    canvas.closePath();
  }

  /// Strokes a horizontal rule from [x1] to [x2] at [y] (the gem's
  /// `stroke_horizontal_rule`).
  static void _horizontalRule(
    PdfCanvas canvas,
    PdfColor color,
    double x1,
    double x2,
    double y,
    double width,
    String? style,
  ) {
    canvas
      ..save()
      ..setStrokeColor(color);
    switch (style) {
      case 'dashed':
        canvas
          ..setLineWidth(width)
          ..dash([width * 4]);
      case 'dotted':
        canvas
          ..setLineWidth(width)
          ..dash([width]);
      case 'double':
        final single = width / 3;
        canvas
          ..setLineWidth(single)
          ..moveTo(x1, y + single)
          ..lineTo(x2, y + single)
          ..stroke()
          ..moveTo(x1, y - single)
          ..lineTo(x2, y - single)
          ..stroke()
          ..restore();
        return;
      default:
        canvas.setLineWidth(width);
    }
    canvas
      ..moveTo(x1, y)
      ..lineTo(x2, y)
      ..stroke()
      ..restore();
  }

  /// Strokes a vertical rule at [x] from [top] to [bottom] (the gem's
  /// `stroke_vertical_rule`).
  static void _verticalRule(
    PdfCanvas canvas,
    PdfColor color,
    double x,
    double top,
    double bottom,
    double width,
    String? style,
  ) {
    canvas
      ..save()
      ..setLineWidth(width)
      ..setStrokeColor(color);
    var at = x;
    switch (style) {
      case 'dashed':
        canvas.dash([width * 4]);
      case 'dotted':
        canvas.dash([width]);
      case 'double':
        canvas
          ..moveTo(at - width, top)
          ..lineTo(at - width, bottom)
          ..stroke();
        at += width;
    }
    canvas
      ..moveTo(at, top)
      ..lineTo(at, bottom)
      ..stroke()
      ..restore();
  }

  /// The padding of theme [key] as edge insets.
  EdgeInsets _padding(String key) {
    final values = _edgeValues(_theme.value(key) ?? const ThemeNumber(0));
    return EdgeInsets(
      top: values[0],
      right: values[1],
      bottom: values[2],
      left: values[3],
    );
  }

  /// Runs [body] with the font of theme [category] in effect.
  void _withFont(String category, void Function() body) {
    final saved = _font;
    _font = _themeFont(category, _font);
    try {
      body();
    } finally {
      _font = saved;
    }
  }

  /// The boxes [body] adds.
  List<LayoutBox> _collect(void Function() body) {
    final saved = _out;
    final boxes = <LayoutBox>[];
    _out = boxes;
    try {
      body();
    } finally {
      _out = saved;
    }
    return boxes;
  }

  /// Whether each piece of a block of theme [category] split across pages
  /// has its padding and border at its top and bottom (the modern
  /// engine's `<category>_box_decoration_break: clone`, as CSS's; Typst's
  /// breakable blocks have their inset so).
  bool _cloneEdges(String category) =>
      _choice('${category}_box_decoration_break', const ['slice', 'clone']) ==
      'clone';

  /// A block of [children] with the padding, the background and the
  /// border of theme [category], [node]'s anchor, and the block margin
  /// below it.
  void _framed(
    AbstractBlock node,
    String category,
    List<LayoutBox> children, {
    bool noBorder = false,
    BoxDecoration? extra,
  }) {
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: _padding('${category}_padding'),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          cloneEdges: _cloneEdges(category),
          anchor: node.id,
          decoration: _blockDecoration(
            category,
            noBorder: noBorder,
            extra: extra,
          ),
        ),
      ),
    );
  }

  /// Converts the open block [node].
  void convertOpen(Block node) {
    if (node.style == 'abstract') {
      _abstract(node);
      return;
    }
    final children = _collect(() {
      if (node.hasTitle) {
        _caption(
          node,
          category: node.style == 'table-container' ? 'table' : null,
          labeled: false,
        );
      }
      _traverse(node);
    });
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Whether [section] is an article's abstract (its first section, named
  /// abstract), which the gem converts as an abstract block.
  bool _isAbstract(Section section) =>
      _document.doctype == 'article' &&
      section.sectname == 'abstract' &&
      _document.sections.whereType<Section>().firstOrNull == section;

  /// Adds the name section of a man page, made from its `manname` and
  /// `manpurpose` (the gem's `generate_manname_section`).
  void _manNameSection(Document doc) {
    if (doc.doctype != 'manpage' || !doc.hasAttr('manpurpose')) return;
    var title = doc.attr('manname-title') ?? 'Name';
    final next = doc.blocks.whereType<Section>().firstOrNull?.title;
    if (next != null && next.toUpperCase() == next) {
      title = title.toUpperCase();
    }
    final section = Section(doc, 1)
      ..sectname = 'section'
      ..id = doc.attr('manname-id')
      ..title = title;
    section.append(
      Block(
        section,
        BlockContext.paragraph,
        source: '${doc.attr('manname')} - ${doc.attr('manpurpose')}',
        subs: const BlockSubs.spec('normal'),
      ),
    );
    convertSection(section);
  }

  /// The sections of [node] (an article's abstract isn't one).
  List<Section> _sectionsOf(AbstractBlock node) => [
    for (final section in node.blocks.whereType<Section>())
      if (!_isAbstract(section)) section,
  ];

  /// Adds the abstract [node] (the gem's `convert_abstract`): its title,
  /// then its paragraphs in the abstract's font, the first line of the
  /// first in the theme's first-line style.
  void _abstract(AbstractBlock node) {
    final children = _collect(() {
      if (node.title case final title? when title.isNotEmpty) {
        final font = _themeFont('abstract_title', _font);
        final lineHeight =
            (_n('heading_line_height') ?? _n('base_line_height') ?? 1)
                .toDouble();
        _out.add(
          CustomBox(
            _textBox(
              title,
              font.copyWith(lineHeight: lineHeight),
              align: _s('abstract_title_text_align') ?? _baseTextAlign,
            ),
            style: BoxStyle(
              margin: EdgeInsets(
                top: (_n('heading_margin_top') ?? 0).toDouble(),
                bottom: (_n('heading_margin_bottom') ?? 0).toDouble(),
              ),
            ),
          ),
        );
      }
      _withFont('abstract', () {
        final align = _s('abstract_text_align') ?? _baseTextAlign;
        _FontState? firstLine;
        final style = _s('abstract_first_line_font_style');
        if (style != null && style != _font.style) {
          final styles = <String>{
            if (style == 'normal_italic') 'italic',
            if (style != 'normal' && style != 'normal_italic') ...{
              ..._stylesOf(_font),
              ..._stylesOf(_font.copyWith(style: style)),
            },
          };
          firstLine = _font.copyWith(
            style: styles.contains('bold')
                ? styles.contains('italic')
                      ? 'bold_italic'
                      : 'bold'
                : styles.contains('italic')
                ? 'italic'
                : 'normal',
          );
        }
        if (_c('abstract_first_line_font_color') case final color?) {
          firstLine = (firstLine ?? _font).copyWith(color: color);
        }
        var transform = _s('abstract_first_line_text_transform');
        if (transform == 'none') transform = null;
        if (transform != null) firstLine ??= _font;
        if (node.blocks.isNotEmpty) {
          for (final child in node.blocks) {
            if (child case final Block block
                when block.context == BlockContext.paragraph) {
              _paragraph(
                block,
                textAlign: align,
                firstLine: firstLine,
                firstLineTransform: transform,
              );
              firstLine = null;
              transform = null;
            } else {
              child.convert();
            }
          }
        } else if (node case final Block block
            when block.contentModel != ContentModel.compound) {
          if (block.content() case final text?) {
            final textAlign = _alignOf(block.roles) ?? align;
            final indent = (textAlign == 'justify' || textAlign == 'left')
                ? (_n('prose_text_indent') ?? 0).toDouble()
                : 0.0;
            final box = _textBox(
              text,
              _font,
              align: textAlign,
              indent: indent,
              hyphenate: true,
            );
            _out.add(
              CustomBox(
                firstLine == null
                    ? box
                    : FirstLineTextBox(
                        _textBox(
                          text,
                          firstLine,
                          align: textAlign,
                          indent: indent,
                          singleLine: true,
                          hyphenate: true,
                        ),
                        box.state,
                        box.layout,
                        transform: transform,
                      ),
              ),
            );
          }
        }
      });
    });
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: _padding('abstract_padding'),
          margin: _outdented(EdgeInsets(bottom: _marginBelow(node))),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Converts the example block [node].
  void convertExample(Block node) {
    final captionBelow = _s('example_caption_end') == 'bottom';
    if (!captionBelow && node.hasTitle) _caption(node, category: 'example');
    final children = _collect(
      () => _withFont('example', () => _traverse(node)),
    );
    if (!captionBelow) {
      _framed(node, 'example', children);
      return;
    }
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: _padding('example_padding'),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
          decoration: _blockDecoration('example'),
        ),
      ),
    );
    if (node.hasTitle) _caption(node, category: 'example');
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
  }

  /// Converts the sidebar [node].
  void convertSidebar(Block node) {
    final children = _collect(() {
      if (node.title case final title? when title.isNotEmpty) {
        final font = _themeFont('sidebar_title', _font);
        final lineHeight =
            (_n('heading_line_height') ?? _n('base_line_height') ?? 1)
                .toDouble();
        var text = title;
        if (font.transform case final transform? when transform != 'none') {
          text = transformText(text, transform);
        }
        _out.add(
          CustomBox(
            _textBox(
              text,
              font.copyWith(lineHeight: lineHeight),
              align:
                  _s('sidebar_title_text_align') ??
                  _s('heading_text_align') ??
                  _baseTextAlign,
            ),
            style: BoxStyle(
              margin: EdgeInsets(
                // The modern engine: the title's own space below first.
                bottom:
                    ((_n('sidebar_title_margin_bottom')) ??
                            _n('heading_margin_bottom') ??
                            0)
                        .toDouble(),
              ),
            ),
          ),
        );
      }
      // (The modern engine: `sidebar_*` keys for the blocks inside it,
      // `sidebar_prose_margin_bottom`...)
      _withFont(
        'sidebar',
        () => _withBaseKeys('sidebar', () => _traverse(node)),
      );
    });
    _framed(node, 'sidebar', children);
  }

  /// Converts the quote or verse block [node].
  void convertQuote(Block node) {
    final category = node.context == BlockContext.quote ? 'quote' : 'verse';
    final leftWidth = (_n('${category}_border_left_width') ?? 0).toDouble();
    final leftColor = leftWidth > 0
        ? _c('${category}_border_color') ?? _c('base_border_color')
        : null;
    final hasLeft = leftWidth > 0 && pdfColorOf(leftColor) != null;
    String? escape(String? text) =>
        text?.replaceAllMapped(RegExp(r'&(?!#?\w+;)'), (_) => '&amp;');
    final attribution = escape(node.attr('attribution'));
    final citeTitle = attribution == null
        ? null
        : escape(node.attr('citetitle'));
    if (node.hasTitle) _caption(node, category: category);
    final children = _collect(() {
      _withFont(category, () {
        if (category == 'quote') {
          _withBaseKeys(category, () => _traverse(node));
        } else {
          _out.add(
            CustomBox(
              _textBox(
                _guardIndentation(node.content() ?? ''),
                _font,
                align: _alignOf(node.roles) ?? 'left',
                normalize: false,
                hyphenate: true,
              ),
            ),
          );
        }
      });
      if (attribution != null) {
        // The modern engine's `<category>_cite_margin_top` and
        // `<category>_cite_text_align`; the gem's block margin, at the left.
        final margin =
            ((_n('${category}_cite_margin_top')) ??
                    _n('block_margin_bottom') ??
                    0)
                .toDouble();
        if (margin > 0) _out.add(SpacerBox(margin));
        _withFont('${category}_cite', () {
          final parts = [attribution, ?citeTitle].join(', ');
          _out.add(
            CustomBox(
              _textBox(
                '— $parts',
                _font,
                align: (_s('${category}_cite_text_align')) ?? 'left',
                normalize: false,
              ),
            ),
          );
        });
      }
    });
    _framed(
      node,
      category,
      children,
      noBorder: hasLeft,
      extra: hasLeft
          ? (page, rect, {required first, required last}) {
              page.canvas
                ..save()
                ..setStrokeColor(pdfColorOf(leftColor)!)
                ..setLineWidth(leftWidth)
                ..moveTo(rect.left + leftWidth * 0.5, rect.top)
                ..lineTo(rect.left + leftWidth * 0.5, rect.bottom)
                ..stroke()
                ..restore();
            }
          : null,
    );
  }

  /// Converts the thematic break [node].
  void convertThematicBreak(Block node) {
    final padding = _edgeValues(
      _theme.value('thematic_break_padding') ??
          ThemeList([
            ThemeNumber(_n('thematic_break_margin_top') ?? 0),
            const ThemeNumber(0),
          ]),
    );
    final color = pdfColorOf(_c('thematic_break_border_color'));
    final width = (_n('thematic_break_border_width') ?? 0.5).toDouble();
    final style = _s('thematic_break_border_style') ?? 'solid';
    _out.add(
      BlockBox(
        const [],
        style: BoxStyle(
          padding: EdgeInsets(
            top: padding[0],
            right: padding[1],
            bottom: padding[2],
            left: padding[3],
          ),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          decoration: color == null
              ? null
              : (page, rect, {required first, required last}) {
                  final y = rect.top - padding[0];
                  final left = rect.left + padding[3];
                  final right = rect.right - padding[1];
                  final canvas = page.canvas
                    ..save()
                    ..setStrokeColor(color);
                  void rule(double at, double lineWidth) => canvas
                    ..setLineWidth(lineWidth)
                    ..moveTo(left, at)
                    ..lineTo(right, at)
                    ..stroke();
                  if (style == 'double') {
                    final single = width / 3;
                    rule(y + single, single);
                    rule(y - single, single);
                  } else {
                    if (style == 'dashed') canvas.dash([width * 4]);
                    if (style == 'dotted') canvas.dash([width]);
                    rule(y, width);
                  }
                  canvas.restore();
                },
        ),
      ),
    );
  }

  /// Converts the page break [node].
  void convertPageBreak(Block node) {
    const layouts = {'portrait', 'landscape'};
    var layout = node.attr('page-layout');
    if (layout == null || layout.isEmpty) {
      layout = node.roles.where(layouts.contains).lastOrNull;
    } else if (!layouts.contains(layout)) {
      layout = null;
    }
    if (_inColumns && node.hasRole('column') && layout == null) {
      _out.add(BreakBox.column(force: node.hasOption('always')));
      return;
    }
    if (layout != null) _layout = layout;
    _out.add(BreakBox.page(template: layout, force: node.hasOption('always')));
  }

  /// The layout of the page being filled (`portrait`, `landscape`).
  String _layout = 'portrait';

  /// The pages of PDF files that are pages of the document, by the key of
  /// the page template they're laid out with.
  final Map<String, ImportedPage> _importedPages = {};

  /// Adds [page] as a page of the document, in place of the current page
  /// when nothing is on it, with [anchor] at its top; with [advance], the
  /// content after it starts a new page in the current layout (the gem's
  /// `import_page`). An imported page has no running content.
  void _importPage(ImportedPage page, {String? anchor, bool advance = true}) {
    final key = 'pdf-page-${_importedPages.length + 1}';
    _importedPages[key] = page;
    _out
      ..add(BreakBox.page(template: key))
      ..add(
        CustomBox(
          _Absolute((_) {}, fill: true),
          style: BoxStyle(anchor: anchor),
        ),
      );
    if (advance) _out.add(BreakBox.page(template: _layout));
  }

  /// The pages of the PDF file at [path] (referred to as [target]), or
  /// null (with a warning) when it isn't a PDF file asciidart can read.
  List<ImportedPage>? _pdfPages(String path, String target) {
    try {
      return PdfFile.parse(Uint8List.fromList(io.readBytes(path))).pages;
    } on PdfFormatException catch (error) {
      logger.warn('could not insert pdf: $target; ${error.message}');
      return null;
    }
  }

  /// Inserts the pages of the PDF file the block image [node] refers to
  /// by [target] (its `page`, or its `pages`: numbers and ranges).
  void _insertPdf(Block node, String target) {
    final path = Helpers.isUriish(target) ? null : _imagePath(node, target);
    if (path == null || !io.isFile(path) || !io.isReadable(path)) {
      logger.warn('pdf to insert not found or not readable: ${path ?? target}');
      return;
    }
    final pages = _pdfPages(path, target) ?? const [];
    final numbers = switch (node.attr('pages')) {
      final value? => [
        for (final entry in value.split(value.contains(',') ? ',' : ';'))
          if (entry.contains('..'))
            for (
              var n = math.max(_rubyInt(entry.split('..').first), 1);
              n <= math.max(_rubyInt(entry.split('..').skip(1).join('..')), 1);
              n++
            )
              n
          else
            _rubyInt(entry),
      ],
      null => [math.max(_rubyInt(node.attr('page') ?? '1'), 1)],
    };
    for (final (i, number) in numbers.indexed) {
      if (pages.elementAtOrNull(number - 1) case final page? when number > 0) {
        _importPage(page, anchor: i == 0 ? node.id : null);
      } else {
        _out.add(BreakBox.page(template: _layout));
      }
    }
  }

  /// [text] as Ruby's `to_i` reads it: the leading integer, else 0.
  static int _rubyInt(String text) =>
      int.tryParse(RegExp(r'^\s*[-+]?\d+').stringMatch(text)?.trim() ?? '') ??
      0;

  /// Whether the body is set in the theme's page columns.
  bool _inColumns = false;

  // Images.

  static final RegExp _dataUri = RegExp(
    r'^data:image/(png|jpe?g|gif|pdf|bmp|tiff|svg\+xml);base64,(.*)$',
  );

  /// The format of the image [target] (its extension, lower case).
  static String _imageFormat(String target) {
    final name = target.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// The bytes of the image [target] of [node], or null (with a warning)
  /// when they can't be read.
  List<int>? _imageBytes(AbstractNode node, String target) {
    _lastImagePath = null;
    final doc = _document;
    final imagesdir = _imagesdir;
    if (_imagePath(node, target) case final path?) return _readImage(path);
    final uri = Helpers.isUriish(target)
        ? target
        : doc.pathResolver.webPath(target, imagesdir);
    if (!doc.hasAttr('allow-uri-read')) {
      logger.warn(
        'cannot embed remote image: $uri '
        '(allow-uri-read attribute not enabled)',
      );
      return null;
    }
    try {
      return doc.fetchUri(uri).body;
    } on Exception catch (error) {
      logger.warn('could not retrieve remote image: $uri; $error');
      return null;
    }
  }

  /// The document's `imagesdir`, unless it's the document's directory.
  String? get _imagesdir => switch (_document.attr('imagesdir')) {
    null || '' || '.' || './' => null,
    final dir => dir,
  };

  /// The path of the image [target] of [node] (relative to the
  /// `imagesdir`), or null when it's a URL.
  String? _imagePath(AbstractNode node, String target) {
    final imagesdir = _imagesdir;
    final resolver = _document.pathResolver;
    final isUrl = Helpers.isUriish(target);
    if (!isUrl && resolver.isAbsolutePath(target)) {
      return resolver.expandPath(resolver.posixify(target));
    }
    if (!isUrl && imagesdir != null && resolver.isAbsolutePath(imagesdir)) {
      return resolver.expandPath('${resolver.posixify(imagesdir)}/$target');
    }
    if (isUrl || (imagesdir != null && Helpers.isUriish(imagesdir))) {
      return null;
    }
    return node.normalizeSystemPath(
      target,
      start: imagesdir,
      targetName: 'image',
    );
  }

  /// The local path of the image read last (SVG images refer to files
  /// relative to it).
  String? _lastImagePath;

  List<int>? _readImage(String path) {
    if (io.isFile(path) && io.isReadable(path)) {
      try {
        final bytes = io.readBytes(path);
        _lastImagePath = path;
        return bytes;
      } on Exception {
        // Reported below.
      }
    }
    logger.warn('image to embed not found or not readable: $path');
    return null;
  }

  static final RegExp _imageMacro = RegExp(r'^image:{1,2}(.*?)\[(.*?)\]$');

  /// The target and the attributes of [value] when it's an image macro
  /// (a theme's logo or running content image).
  static (String, Map<String, String>)? _imageMacroOf(
    String value,
    List<String> positional,
  ) {
    if (!value.contains(':')) return null;
    final match = _imageMacro.firstMatch(value);
    if (match == null) return null;
    return (match[1]!, AttributeList(match[2]!).parse(positional));
  }

  /// [bytes] as an image of [format], or null (with why) when they aren't
  /// one.
  (Graphic?, String?) _graphicOf(
    List<int> bytes,
    String format, {
    String? path,
  }) {
    try {
      return (
        format == 'svg'
            ? SvgImage.parse(
                utf8.decode(bytes, allowMalformed: true),
                pixelSize: 1,
                fonts: _fonts.svgFont,
                defaultFontFamily: 'sans-serif',
                fallbackFontFamily:
                    _s('svg_fallback_font_family') ??
                    _s('svg_font_family') ??
                    _s('base_font_family'),
                images: path == null
                    ? null
                    : (href) => _svgResource(href, path),
              )
            : _encodingElsewhere(Uint8List.fromList(bytes)),
        null,
      );
    } on FormatException catch (error) {
      return (null, error.message);
    } on ImageFormatException catch (error) {
      return (null, error.message);
    }
  }

  /// The image in [bytes], its samples encoded on another core when the
  /// conversion is awaited and writing it encodes them (a PNG with alpha,
  /// say): the worker gets the file's bytes and gives back the streams
  /// the save would make (or nothing, and the save makes them).
  PdfImage _encodingElsewhere(Uint8List bytes) {
    final image = PdfImage.parse(bytes);
    final parallel = _parallel;
    if (parallel == null || image is! PngImage || !image.reencodes) {
      return image;
    }
    _awaiting.add(
      parallel
          .submit(_PngEncoding(bytes, nativeZlib: io.hasNativeZlib))
          .then<void>(
            (payload) => image.payload = payload,
            onError: (Object _) {},
          ),
    );
    return image;
  }

  /// The content streams of [pages] compressed on other cores, when the
  /// conversion is awaited.
  void _compressingElsewhere(List<PdfPage> pages) {
    final parallel = _parallel;
    if (parallel == null) return;
    for (final page in pages) {
      _awaiting.add(
        parallel
            .submit(_StreamEncoding(page.content, nativeZlib: io.hasNativeZlib))
            .then<void>(
              (payload) => page.contentPayload = payload,
              onError: (Object _) {},
            ),
      );
    }
  }

  /// The file an SVG image at [svgPath] refers to by [href]: relative to
  /// the image, inside the document's directory unless the safe mode
  /// allows any (prawn-svg's file requests); a URI with allow-uri-read.
  Uint8List? _svgResource(String href, String svgPath) {
    final doc = _document;
    if (Helpers.isUriish(href) && !href.startsWith('file:')) {
      if (!doc.hasAttr('allow-uri-read')) return null;
      try {
        return Uint8List.fromList(doc.fetchUri(href).body);
      } on Exception {
        return null;
      }
    }
    final resolver = doc.pathResolver;
    var path = href.startsWith('file://') ? href.substring(7) : href;
    final slash = svgPath.lastIndexOf('/');
    final base = slash < 0 ? '.' : svgPath.substring(0, slash);
    path = resolver.isAbsolutePath(path)
        ? resolver.expandPath(path)
        : resolver.expandPath('$base/$path');
    if (doc.safe >= SafeMode.safe) {
      final root = resolver.expandPath(doc.baseDir);
      if (path != root && !path.startsWith('$root/')) return null;
    }
    if (!io.isFile(path) || !io.isReadable(path)) return null;
    try {
      return Uint8List.fromList(io.readBytes(path));
    } on Exception {
      return null;
    }
  }

  /// [path], relative to the theme's directory.
  String? _themeImagePath(String path) {
    final resolver = _document.pathResolver;
    if (resolver.isAbsolutePath(path)) return path;
    final dir = _theme.directory;
    if (dir == null) return null;
    return resolver.expandPath('${resolver.posixify(dir)}/$path');
  }

  /// Reads the image at [path] relative to the theme's directory (the
  /// gem's `resolve_image_path` with the themesdir).
  List<int>? _themeImageBytes(String path) {
    final resolved = _themeImagePath(path);
    if (resolved == null || !io.isFile(resolved) || !io.isReadable(resolved)) {
      return null;
    }
    try {
      final bytes = io.readBytes(resolved);
      _lastImagePath = resolved;
      return bytes;
    } on Exception {
      return null;
    }
  }

  /// Converts the block image [node].
  void convertImage(Block node) {
    final target = node.attr('target') ?? '';
    final data = _dataUri.firstMatch(target);
    final format = data != null
        ? switch (data[1]!) {
            'jpg' => 'jpeg',
            'svg+xml' => 'svg',
            final other => other,
          }
        : node.attr('format') ?? _imageFormat(target);
    const blockAligns = {'left', 'center', 'right'};
    final floatTo = node.attr('float');
    final String align;
    if (floatTo != null && blockAligns.contains(floatTo)) {
      align = floatTo;
    } else if (node.attr('align') case final value?) {
      align = blockAligns.contains(value) ? value : 'left';
    } else {
      align =
          node.roles.reversed.where(blockAligns.contains).firstOrNull ??
          _s('image_align') ??
          'left';
    }
    // A text file (ASCII art) in the modern engine: its text, as it is,
    // in the code font (or `image_text_*`), the block as wide as its
    // longest line and aligned as an image, as Typst sets an asciiart
    // figure.
    if (format == 'txt' && data == null) {
      if (_imageBytes(node, target) case final bytes?) {
        _textImage(node, utf8.decode(bytes, allowMalformed: true), align);
        return;
      }
    }
    List<int>? bytes;
    if (format == 'gif') {
      logger.warn('GIF image format not supported; convert $target to PNG');
    } else if (format == 'pdf' && data == null) {
      _insertPdf(node, target);
      return;
    } else if (data != null) {
      try {
        bytes = base64.decode(data[2]!);
      } on FormatException {
        bytes = null;
      }
    } else {
      bytes = _imageBytes(node, target);
    }
    Graphic? graphic;
    if (bytes != null) {
      final (parsed, problem) = _graphicOf(
        bytes,
        format,
        path: data == null ? _lastImagePath : null,
      );
      graphic = parsed;
      if (problem != null) {
        logger.warn('could not embed image: $target; $problem');
      }
    }
    if (graphic == null) {
      _imageAlt(node, target, align);
      return;
    }
    final captionBottom = (_s('image_caption_end') ?? 'bottom') == 'bottom';
    var caption = node.hasTitle
        ? _captionBox(
            node,
            category: 'image',
            bottom: captionBottom,
            blockAlign: align,
          )
        : null;
    // No wider than the theme's image_caption_max_width says (a floated
    // image's caption is in the float's box, as wide as the image).
    final captionMaxWidth = _s('image_caption_max_width');
    final floated = floatTo == 'left' || floatTo == 'right';
    if (caption != null && captionMaxWidth != null && !floated) {
      final sizing = _ImageContent(
        graphic,
        width: _imageWidth(node),
        align: align,
        pageWidth: _pageSize(_document).$1,
      );
      caption = _fitCaption(
        caption,
        (width) => sizing._size(width, double.infinity).$1,
        setting: captionMaxWidth,
        captionKey: 'image_caption',
        blockAlign: align,
      );
    }
    final next = _nextEnclosedBlock(node);
    var margin = _marginBelow(node, next: next);
    final border = node.hasRole('noborder') ? null : _imageBorder();
    // A floated image followed by a paragraph: the paragraphs after it
    // wrap around it (the gem's `init_float_box`).
    final side = floatTo == 'left' || floatTo == 'right' ? floatTo! : null;
    if (side != null &&
        next is Block &&
        next.context == BlockContext.paragraph) {
      final paragraph = next;
      final gaps = switch (_theme.value('image_float_gap')) {
        ThemeList(:final values) => (
          values.isNotEmpty ? _toPoints(values[0]) : 12.0,
          values.length > 1 ? _toPoints(values[1]) : 6.0,
        ),
        ThemeNumber(:final value) => (value.toDouble(), value.toDouble()),
        _ => (12.0, 6.0),
      };
      final group = _FloatGroup(
        _ImageContent(
          graphic,
          width: _imageWidth(node),
          align: side,
          pageWidth: _pageSize(_document).$1,
          border: border,
          link: node.attr('link'),
        ),
        caption: caption,
        captionBottom: captionBottom,
        side: side,
        gaps: gaps,
      );
      _out.add(CustomBox(group, style: BoxStyle(anchor: node.id)));
      _floatGroup = group;
      _floatNext = paragraph;
      return;
    }
    // `image_placement` (modern engine): the image and its caption float,
    // to the top of the next page when they don't fit, the text after them
    // filling the room; when they fit, to the top or bottom of the page
    // (`top`, `bottom`, `auto`: the nearer), or they stay (`next`).
    // An image in a list, a table or a sidebar stays there.
    final parent = node.parent;
    final topLevel =
        parent is Section ||
        parent is Document ||
        parent?.context == BlockContext.preamble;
    // (The block's own `placement` attribute first: `none` keeps it where
    // it is, as Typst's figure placement.)
    final float = topLevel
        ? switch (node.attr('placement') ?? _imagePlacement) {
            'auto' => FloatPlacement.auto,
            'top' => FloatPlacement.top,
            'bottom' => FloatPlacement.bottom,
            'next' => FloatPlacement.next,
            _ => null,
          }
        : null;
    final shown = graphic;
    // A floating image: no margin of its own, its clearance
    // (`image_float_clearance`) between it and the text instead.
    if (float != null && float != FloatPlacement.next) margin = 0;
    final figure = _collect(() {
      if (caption != null && !captionBottom) _out.add(caption);
      _out.add(
        CustomBox(
          _ImageContent(
            shown,
            width: _imageWidth(node),
            align: align,
            pageWidth: _pageSize(_document).$1,
            caption: captionBottom ? caption : null,
            border: border,
            link: node.attr('link'),
          ),
          style: BoxStyle(
            anchor: node.id,
            margin: EdgeInsets(
              bottom: caption != null && captionBottom ? 0 : margin,
            ),
          ),
        ),
      );
      if (caption != null && captionBottom) {
        _out.add(caption);
        if (margin > 0) _out.add(SpacerBox(margin));
      }
    });
    if (float != null) {
      _out.add(
        BlockBox(
          figure,
          style: BoxStyle(
            keepTogether: true,
            float: float,
            floatClearance: _imageFloatClearance,
          ),
        ),
      );
    } else {
      _out.addAll(figure);
    }
  }

  /// The space between a floating image and the text
  /// (`image_float_clearance`, modern engine).
  double get _imageFloatClearance =>
      _length('image_float_clearance', _font.size) ?? 0;

  /// The image [node] that is the [text] of a text file (see
  /// [convertImage]): kept whole, captioned and floated as an image is.
  void _textImage(Block node, String text, String align) {
    final font = _themeFont('image_text', _themeFont('code', _font));
    // Every line kept, the empty one after a final line break too (as
    // Typst's raw text keeps it).
    final box = _textBox(
      _guardIndentation(text.endsWith('\n') ? '$text\u00a0' : text),
      font,
      align: 'left',
      normalize: false,
      inlineFormat: false,
    );
    final captionBottom = (_s('image_caption_end') ?? 'bottom') == 'bottom';
    final caption = node.hasTitle
        ? _captionBox(
            node,
            category: 'image',
            bottom: captionBottom,
            blockAlign: align,
          )
        : null;
    var margin = _marginBelow(node, next: _nextEnclosedBlock(node));
    final parent = node.parent;
    final topLevel =
        parent is Section ||
        parent is Document ||
        parent?.context == BlockContext.preamble;
    // The block's own `placement` attribute, else the theme's.
    final placement = node.attr('placement') ?? _imagePlacement;
    final float = topLevel
        ? switch (placement) {
            'auto' => FloatPlacement.auto,
            'top' => FloatPlacement.top,
            'bottom' => FloatPlacement.bottom,
            'next' => FloatPlacement.next,
            _ => null,
          }
        : null;
    if (float != null && float != FloatPlacement.next) margin = 0;
    final figure = [
      if (caption != null && !captionBottom) caption,
      CustomBox(
        _Aligned(box, align: align),
        style: BoxStyle(
          anchor: node.id,
          margin: EdgeInsets(
            bottom: caption != null && captionBottom ? 0 : margin,
          ),
        ),
      ),
      if (caption != null && captionBottom) ...[
        caption,
        if (margin > 0) SpacerBox(margin),
      ],
    ];
    _out.add(
      BlockBox(
        figure,
        style: BoxStyle(
          keepTogether: true,
          float: float,
          floatClearance: _imageFloatClearance,
        ),
      ),
    );
  }

  /// [text] as a number, as Ruby's `to_f` reads it (its leading number,
  /// else 0).
  static double _toF(String text) =>
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?')
                .stringMatch(text)
                ?.trim() ??
            '',
      ) ??
      0;

  /// The width [node] asks of its image (the gem's
  /// `resolve_explicit_width`, with the theme's `image_width` fallback).
  _ImageWidth _imageWidth(AbstractNode node, {bool fallback = true}) =>
      _imageWidthOf(node.attr, fallback: fallback);

  _ImageWidth _imageWidthOf(
    String? Function(String name) attr, {
    bool fallback = true,
    bool vw = true,
  }) {
    _ImageWidth percent(String value) => _ImageWidth.percent(_toF(value) / 100);
    if (attr('pdfwidth') case final width?) {
      if (width.endsWith('%')) return percent(width);
      if (width.endsWith('iw')) {
        return _ImageWidth.scale(
          _toF(width.substring(0, width.length - 2)) / 100,
        );
      }
      if (vw && width.endsWith('vw')) {
        return _ImageWidth.viewport(
          _toF(width.substring(0, width.length - 2)) / 100,
        );
      }
      return _ImageWidth.points(strToPoints(width));
    }
    if (attr('scale') case final scale?) {
      return _ImageWidth.scale(_toF(scale) / 100);
    }
    if (attr('scaledwidth') case final width?) {
      return width.endsWith('%')
          ? percent(width)
          : _ImageWidth.points(strToPoints(width));
    }
    switch (fallback ? _theme.value('image_width') : null) {
      case ThemeNumber(:final value):
        return _ImageWidth.points(value.toDouble());
      case final ThemeValue value:
        final width = value.rubyString;
        if (width.endsWith('%')) return percent(width);
        if (width.endsWith('vw')) {
          return _ImageWidth.viewport(
            _toF(width.substring(0, width.length - 2)) / 100,
          );
        }
        return _ImageWidth.points(strToPoints(width));
      case null:
        break;
    }
    if (attr('width') case final width?) {
      if (width.endsWith('%')) {
        return _ImageWidth.percent(_toF(width) / 100, constrain: true);
      }
      if (RegExp(r'^\d+$').hasMatch(width)) {
        return _ImageWidth.points(_toF(width) * 0.75, constrain: true);
      }
    }
    return const _ImageWidth.natural();
  }

  /// The border the theme draws around images, if any.
  _Border? _imageBorder() {
    final widthValue = _theme.value('image_border_width');
    final widths = _sideWidths(widthValue);
    final width = switch (widthValue) {
      ThemeNumber(:final value) => value.toDouble(),
      _ => widths?.fold<double>(0, math.max) ?? 0.0,
    };
    if (width <= 0) return null;
    final color = pdfColorOf(
      _c('image_border_color') ?? _c('base_border_color'),
    );
    if (color == null) return null;
    return _Border(
      width,
      color,
      widths == null ? (_n('image_border_radius') ?? 0).toDouble() : 0,
      widths: widths,
      style: _s('image_border_style'),
      fitWidth: _s('image_border_fit') == 'auto',
    );
  }

  /// The text that stands in for the image [node] that can't be embedded
  /// (the gem's `on_image_error`).
  void _imageAlt(Block node, String target, String align) {
    final template =
        _s('image_alt_content') ??
        '%{link}[%{alt}]%{/link} | <em>%{target}</em>';
    if (template.isNotEmpty) {
      final link = node.attr('link');
      final text = template
          .replaceAll('%{link}', link == null ? '' : '<a href="$link">')
          .replaceAll('%{/link}', link == null ? '' : '</a>')
          .replaceAll('%{alt}', node.attr('alt') ?? '')
          .replaceAll('%{target}', target);
      _withFont('image_alt', () {
        _out.add(
          CustomBox(
            _textBox(text, _font, align: align, normalize: false),
            style: BoxStyle(anchor: node.id),
          ),
        );
      });
      if (node.hasTitle) _caption(node, category: 'image', bottom: true);
      final margin = _marginBelow(node);
      if (margin > 0) _out.add(SpacerBox(margin));
    }
  }

  // Tables.

  /// [value] (a theme value, maybe a list) for each side: top, right,
  /// bottom, left (the gem's `expand_rect_values`).
  static List<ThemeValue?> _rectValues(ThemeValue? value, ThemeValue fallback) {
    if (value is ThemeList && value is! CmykThemeColor) {
      final v = [for (final item in value.values) item];
      ThemeValue at(int i) =>
          i < v.length && v[i] is! ThemeNull ? v[i] : fallback;
      return switch (v.length) {
        1 => [at(0), at(0), at(0), at(0)],
        2 => [at(0), at(1), at(0), at(1)],
        3 => [at(0), at(1), at(2), at(1)],
        _ => [at(0), at(1), at(2), at(3)],
      };
    }
    final one = value ?? fallback;
    return [one, one, one, one];
  }

  /// [value] for rows and columns (the gem's `expand_grid_values`).
  static List<ThemeValue?> _gridValues(ThemeValue? value, ThemeValue fallback) {
    if (value is ThemeList && value is! CmykThemeColor) {
      final v = value.values;
      ThemeValue at(int i) =>
          i < v.length && v[i] is! ThemeNull ? v[i] : fallback;
      return v.length == 1 ? [at(0), at(0)] : [at(0), at(1)];
    }
    final one = value ?? fallback;
    return [one, one];
  }

  static double _width(ThemeValue? value) => switch (value) {
    ThemeNumber(:final value) => value.toDouble(),
    _ => 0,
  };

  /// Converts the table [node] (the gem's `convert_table`, prawn-table's
  /// layout on libpdf's tables).
  void convertTable(Table node) {
    // The modern engine styles a table with a role by the theme's
    // table_role_<role>_* keys, over its table_* keys.
    if (node.roles.isNotEmpty) {
      final saved = _theme;
      for (final role in node.roles) {
        _theme = _theme.overlaid(
          'table_role_${role.replaceAll('-', '_')}_',
          'table_',
        );
      }
      if (!identical(_theme, saved)) {
        try {
          _convertTable(node);
        } finally {
          _theme = saved;
        }
        return;
      }
    }
    _convertTable(node);
  }

  void _convertTable(Table node) {
    final captionTop = (_s('table_caption_end') ?? 'top') == 'top';
    final unbreakable = node.hasOption('unbreakable');
    final outside = _font;
    final boxes = _collect(
      () => _withFont('table', () => _table(node, outside: outside)),
    );
    if (boxes.isEmpty) return;
    var caption = node.hasTitle
        ? _captionBox(
            node,
            category: 'table',
            bottom: !captionTop,
            blockAlign: _tableAlign,
          )
        : null;
    if (caption != null) {
      caption = _fitCaption(
        caption,
        _tableWidth,
        setting: _s('table_caption_max_width') ?? 'fit-content',
        captionKey: 'table_caption',
        blockAlign: _tableAlign,
      );
    }
    final next = _nextEnclosedBlock(node);
    final margin = _marginBelow(node, next: next);
    _out.add(
      BlockBox(
        [if (captionTop) ?caption, ...boxes, if (!captionTop) ?caption],
        style: BoxStyle(
          anchor: node.id,
          keepTogether: unbreakable,
          margin: EdgeInsets(bottom: margin),
        ),
      ),
    );
  }

  /// The width of the table converted last, for the room it's given, and
  /// its alignment (for its caption).
  double Function(double width) _tableWidth = _fullWidth;
  String _tableAlign = 'left';

  static double _fullWidth(double width) => width;

  /// The [caption] of a block as wide as [tableWidth] gives for the room
  /// no wider than [setting] says (`fit-content`, `fit-content(N%)`, a
  /// percentage or a width; the gem's `ink_caption` with a block width);
  /// [captionKey] is its theme category (`table_caption`...), [blockAlign]
  /// the block's alignment.
  CustomBox _fitCaption(
    CustomBox caption,
    double Function(double width) tableWidth, {
    required String? setting,
    required String captionKey,
    required String blockAlign,
  }) {
    if (setting == null || setting == 'none') return caption;
    var align = _s('${captionKey}_align') ?? _s('caption_align');
    if (align == 'inherit') align = blockAlign;
    align ??= _baseTextAlign;
    (double, double) indents(double width) {
      var left = 0.0;
      var right = 0.0;
      double maxWidth;
      var by = blockAlign;
      if (setting.startsWith('fit-content')) {
        final block = tableWidth(width);
        final percent = RegExp(r'^fit-content\((\d+(?:\.\d+)?)%?\)$')
            .firstMatch(setting);
        if (percent != null) {
          final delta = block - block * _toF(percent[1]!) / 100;
          if (delta > 0) {
            switch (align) {
              case 'right':
                left += delta;
              case 'center':
                left += delta / 2;
                right += delta / 2;
              default:
                right += delta;
            }
          }
        }
        maxWidth = block;
      } else if (setting.endsWith('%')) {
        maxWidth = math.min(_toF(setting) / 100 * width, width);
        by = align!;
      } else {
        maxWidth = math.min(_toF(setting), width);
        by = align!;
      }
      final remainder = width - maxWidth;
      if (remainder > 0) {
        switch (by) {
          case 'right':
            left += remainder;
          case 'center':
            left += remainder / 2;
            right += remainder / 2;
          default:
            right += remainder;
        }
      }
      return (left, right);
    }

    return CustomBox(_Indented(caption.content, indents), style: caption.style);
  }

  /// Lays out the table [node] in the table's font; AsciiDoc cells use the
  /// font [outside] the table when the theme's `table_asciidoc_cell_style`
  /// is `initial`.
  void _table(Table node, {required _FontState outside}) {
    final rows = node.rows;
    final numRows = rows.head.length + rows.body.length + rows.foot.length;
    final numCols = node.columns.length;
    ThemeColor? color(String key, [ThemeColor? fallback]) {
      final value = _c(key);
      return value is TransparentColor ? fallback : value ?? fallback;
    }

    final tableBackground = color('table_background_color');
    final headBackground = color(
      'table_head_background_color',
      tableBackground,
    );
    final footBackground = color(
      'table_foot_background_color',
      tableBackground,
    );
    final bodyBackground = color(
      'table_body_background_color',
      tableBackground,
    );
    final stripeBackground = color(
      'table_body_stripe_background_color',
      tableBackground,
    );
    final bodyPadding = _edgeValues(
      _theme.value('table_cell_padding') ?? const ThemeNumber(0),
    );
    final tableFont = _font;

    // The cells, row by row: (row, column, cell data).
    final grid = <List<_TableCellData>>[];
    final headFont = _themeFont('table_head', tableFont);
    if (rows.head.isNotEmpty) {
      final lineHeight =
          (_n('table_head_line_height') ??
                  _n('table_cell_line_height') ??
                  headFont.lineHeight)
              .toDouble();
      final font = headFont.copyWith(lineHeight: lineHeight);
      final metrics = _lineMetrics(font);
      final padding = _theme.value('table_head_cell_padding') == null
          ? [...bodyPadding]
          : _edgeValues(_theme.value('table_head_cell_padding'));
      padding[0] += metrics.paddingTop;
      padding[2] += metrics.paddingBottom;
      final transform = _s('table_head_text_transform');
      for (final row in rows.head) {
        grid.add([
          for (final cell in row)
            _TableCellData(
              text: _hyphenated(
                transform == null || transform == 'none'
                    ? cell.text.trim()
                    : transformText(cell.text.trim(), transform),
                cell.attr('halign') ?? 'left',
              ),
              font: font,
              padding: padding,
              background: headBackground,
              colspan: cell.colspan ?? 1,
              rowspan: 1,
              align: cell.attr('halign') ?? 'left',
              valign: cell.attr('valign') ?? 'top',
            ),
        ]);
      }
    }
    final bodyLineHeight =
        (_n('table_cell_line_height') ?? tableFont.lineHeight).toDouble();
    final bodyFont = tableFont.copyWith(lineHeight: bodyLineHeight);
    for (final row in [...rows.body, ...rows.foot]) {
      final cells = <_TableCellData>[];
      for (final cell in row) {
        var font = bodyFont;
        ThemeColor? background;
        String? transform;
        var inline = true;
        var cellAlign = cell.attr('halign') ?? 'left';
        String? content;
        List<LayoutBox>? blocks;
        switch (cell.style) {
          case 'emphasis':
            font = font.copyWith(style: 'italic');
          case 'strong':
            font = font.copyWith(style: 'bold');
          case 'header':
            final header = _themeFont(
              'table_header_cell',
              _themeFont('table_head', tableFont),
            );
            font = header;
            transform = header.transform;
            background = color(
              'table_header_cell_background_color',
              headBackground,
            );
          case 'monospaced':
            final mono = _themeFont('codespan', tableFont);
            font = mono.copyWith(
              style: tableFont.style,
              lineHeight: tableFont.lineHeight,
            );
          case 'literal':
            content = _guardIndentation(cell.sourceText ?? '');
            inline = false;
            final code = _themeFont('code', tableFont);
            font = code.copyWith(
              style: tableFont.style,
              size: code.size * (bodyFont.size / _rootFontSize),
            );
          case 'asciidoc':
            if (cell.innerDocument case final inner?) {
              // Paragraphs alone follow the cell's alignment.
              final halign = cell.attr('halign');
              final savedAlign = _baseTextAlign;
              if ((halign == 'center' || halign == 'right') &&
                  inner.blocks.isNotEmpty &&
                  inner.blocks.every(
                    (b) => b.context == BlockContext.paragraph,
                  )) {
                _baseTextAlign = halign!;
              }
              final savedFont = _font;
              if (_s('table_asciidoc_cell_style') == 'initial') {
                _font = outside;
              }
              // The modern engine's `table_base_*` keys: the base keys of
              // the cells' blocks (`table_base_text_align_last`...).
              final savedTheme = _theme;
              _theme = _theme.overlaid('table_base_', 'base_');
              // A cell's own alignment comes first.
              if (_s('table_base_text_align') case final align?
                  when _baseTextAlign == savedAlign) {
                _baseTextAlign = align;
              }

              try {
                blocks = _collect(() => _traverse(inner));
              } finally {
                _baseTextAlign = savedAlign;
                _font = savedFont;
                _theme = savedTheme;
              }
            }
        }
        final List<double> padding;
        if (blocks != null) {
          padding = [...bodyPadding];
        } else {
          final metrics = _lineMetrics(font);
          padding = [...bodyPadding];
          padding[0] += metrics.paddingTop;
          padding[2] += metrics.paddingBottom;
        }
        if (content == null && blocks == null) {
          var text = cell.text.trim();
          if (transform != null && transform != 'none') {
            text = transformText(text, transform);
          }
          text = _hyphenated(text, cell.attr('halign') ?? 'left');
          if (_cjkLineBreaks) text = _breakCjk(text);
          content = text;
          // The modern engine styles a cell whose whole text has a role
          // (`[.paid]#Paid#`) by the theme's table_cell_role_<role>_*
          // keys.
          if (_cellRole(text) case final role?) {
            final key = 'table_cell_role_${role.replaceAll('-', '_')}';
            background = _c('${key}_background_color') ?? background;
            font = _themeFont(key, font);
            cellAlign = _s('${key}_text_align') ?? cellAlign;
          }
        }
        cells.add(
          _TableCellData(
            text: content ?? '',
            blocks: blocks,
            font: font,
            padding: padding,
            background: background,
            colspan: cell.colspan ?? 1,
            rowspan: cell.rowspan ?? 1,
            align: cellAlign,
            valign: cell.attr('valign') ?? 'top',
            inlineFormat: inline,
          ),
        );
      }
      grid.add(cells);
    }
    if (grid.isEmpty) {
      logger.warn('no rows found in table');
      grid.add([
        for (var c = 0; c < math.max(numCols, 1); c++)
          // prawn-table's own cell: its default padding.
          _TableCellData(
            text: '',
            font: bodyFont,
            padding: const [5, 5, 5, 5],
            colspan: 1,
            rowspan: 1,
            align: 'left',
            valign: 'top',
          ),
      ]);
    }

    // Borders.
    const transparent = ThemeString('transparent');
    final borderColor = _rectValues(
      _theme.value('table_border_color'),
      transparent,
    );
    final borderStyle = _rectValues(
      _theme.value('table_border_style'),
      const ThemeString('solid'),
    );
    final borderWidth = [
      for (final v in _rectValues(
        _theme.value('table_border_width'),
        const ThemeNumber(0),
      ))
        _width(v),
    ];
    final gridColor = _gridValues(
      _theme.value('table_grid_color') ??
          ThemeList([borderColor[0]!, borderColor[3]!]),
      transparent,
    );
    final gridStyle = _gridValues(
      _theme.value('table_grid_style') ??
          ThemeList([borderStyle[0]!, borderStyle[3]!]),
      const ThemeString('solid'),
    );
    final gridWidth = [
      for (final v in _gridValues(
        _theme.value('table_grid_width') ??
            ThemeList([
              ThemeNumber(borderWidth[0]),
              ThemeNumber(borderWidth[3]),
            ]),
        const ThemeNumber(0),
      ))
        _width(v),
    ];
    final headerSize = rows.head.length;
    final headBottomColor =
        _theme.value('table_head_border_bottom_color') ?? gridColor[0];
    final headBottomStyle =
        _theme.value('table_head_border_bottom_style') ?? gridStyle[0];
    final headBottomWidth =
        (_n('table_head_border_bottom_width') ?? gridWidth[0] * 2.5).toDouble();
    final gridSetting =
        node.attr('grid') ?? _document.attr('table-grid') ?? 'all';
    switch (gridSetting) {
      case 'all':
        break;
      case 'cols':
        gridWidth[0] = 0;
      case 'rows':
        gridWidth[1] = 0;
      default:
        gridWidth[0] = gridWidth[1] = 0;
    }
    final frame = node.attr('frame') ?? _document.attr('table-frame') ?? 'all';
    switch (frame) {
      case 'all':
        break;
      case 'topbot' || 'ends':
        borderWidth[1] = borderWidth[3] = 0;
      case 'sides':
        borderWidth[0] = borderWidth[2] = 0;
      default:
        borderWidth[0] = borderWidth[1] = borderWidth[2] = borderWidth[3] = 0;
    }

    // Each cell's place in the grid, skipping the columns spans take.
    final taken = <(int, int)>{};
    final placed = <(int, int, _TableCellData)>[];
    for (final (r, row) in grid.indexed) {
      var c = 0;
      for (final data in row) {
        while (taken.contains((r, c))) {
          c++;
        }
        placed.add((r, c, data));
        for (var dr = 0; dr < data.rowspan; dr++) {
          for (var dc = 0; dc < data.colspan; dc++) {
            taken.add((r + dr, c + dc));
          }
        }
        c += data.colspan;
      }
    }

    // Stripes (prawn-table's row colors, counted from the first body row).
    final stripes = switch (node.attr('stripes') ??
        _document.attr('table-stripes')) {
      'all' => [stripeBackground],
      'even' => [bodyBackground, stripeBackground],
      'odd' => [stripeBackground, bodyBackground],
      _ => [bodyBackground],
    };
    final footRow = rows.foot.isEmpty ? -1 : numRows - 1;
    final footColor = _c('table_foot_font_color');
    final footSize = _n('table_foot_font_size')?.toDouble();
    final footFamily = _s('table_foot_font_family');
    final footStyle = _s('table_foot_font_style');

    final tableRows = <List<TableCell>>[for (final _ in grid) []];
    for (final (r, c, data) in placed) {
      var font = data.font;
      var background = data.background;
      if (r == footRow) {
        background = footBackground;
        font = font.copyWith(
          color: footColor,
          size: footSize,
          family: footFamily,
          style: footStyle,
        );
      }
      final lastRow = r + data.rowspan - 1;
      final lastCol = c + data.colspan - 1;
      // Grid lines, then the header's bottom border, then the frame.
      final sides = <_Side>[
        _Side(gridWidth[0], gridColor[0], gridStyle[0]),
        _Side(gridWidth[1], gridColor[1], gridStyle[1]),
        _Side(gridWidth[0], gridColor[0], gridStyle[0]),
        _Side(gridWidth[1], gridColor[1], gridStyle[1]),
      ];
      if (gridSetting == 'none' && frame == 'none') {
        for (var i = 0; i < 4; i++) {
          sides[i] = const _Side(0, null, null);
        }
      }
      if (headerSize > 0) {
        final head = _Side(headBottomWidth, headBottomColor, headBottomStyle);
        if (lastRow == headerSize - 1) sides[2] = head;
        if (gridSetting != 'none' || frame != 'none') {
          if (r == headerSize && numRows > headerSize) sides[0] = head;
        }
      }
      if (gridSetting != 'none' || frame != 'none') {
        if (r == 0) {
          sides[0] = _Side(borderWidth[0], borderColor[0], borderStyle[0]);
        }
        if (lastCol == numCols - 1) {
          sides[1] = _Side(borderWidth[1], borderColor[1], borderStyle[1]);
        }
        if (lastRow == numRows - 1) {
          sides[2] = _Side(borderWidth[2], borderColor[2], borderStyle[2]);
        }
        if (c == 0) {
          sides[3] = _Side(borderWidth[3], borderColor[3], borderStyle[3]);
        }
      }
      tableRows[r].add(_tableCell(data, font, background, sides));
    }

    // A column with no width can't hold its text: prawn-table gives up
    // on the table (the gem reports it and leaves the table out).
    if (!node.hasOption('autowidth')) {
      final (pageWidth, _) = _pageSize(_document);
      final contentWidth =
          (pageWidth - _pageMargins(_document).horizontal) * node.pcwidth / 100;
      for (final (_, c, data) in placed) {
        final column = node.columns.elementAtOrNull(c);
        if (column == null || data.colspan != 1 || data.blocks != null) {
          continue;
        }
        // The room for the text (with prawn-table's point of tolerance)
        // and the widest character it must hold.
        final room =
            (column.pcwidth ?? 0) / 100 * contentWidth -
            data.padding[1] -
            data.padding[3] +
            1;
        final font = _fonts.font(data.font.family, data.font.style);
        final widest = [
          for (final rune in _plain(data.text).runes)
            if (rune > 32)
              font.widthOf(String.fromCharCode(rune), data.font.size),
        ].fold<double>(0, math.max);
        if (widest > room) {
          // The modern engine keeps the table, the text set past the
          // column's edge where it must be.
          logger.warn(
            'table column ${c + 1} is too narrow for its text; '
            'the text overflows it',
            at: node.sourceLocation,
          );
          break;
        }
      }
    }

    // Column widths: by the columns' percentages, or (autowidth) by
    // prawn-table's natural widths.
    final List<ColumnWidth> columns;
    final pc = (node.pcwidth) / 100;
    if (node.hasOption('autowidth')) {
      columns = _autoWidths(
        node,
        placed,
        numCols,
        node.hasAttr('width')
            ? pc
            : node.hasRole('stretch')
            ? 1.0
            : null,
      );
    } else {
      columns = [
        for (final column in node.columns)
          ColumnWidth.computed(
            (width) => (column.pcwidth ?? 0) * width * pc / 100,
          ),
      ];
    }
    // The table's width, for its caption.
    _tableWidth = (width) => [
      for (final column in columns)
        switch (column) {
          ComputedColumnWidth(width: final of) => of(width),
          FixedColumnWidth(:final points) => points,
          _ => 0.0,
        },
    ].fold<double>(0, (a, b) => a + b);
    final alignAttr = node.attr('align');
    final align =
        (alignAttr != null &&
                const {'left', 'center', 'right'}.contains(alignAttr)
            ? alignAttr
            : node.roles
                  .where(const {'left', 'center', 'right'}.contains)
                  .lastOrNull) ??
        _s('table_align') ??
        'left';
    _tableAlign = align;
    _out.add(
      TableBox(
        [for (final cells in tableRows) TableRow(cells)],
        columns: columns,
        headerRows: headerSize,
        stripes: [for (final color in stripes) pdfColorOf(color)],
        align: switch (align) {
          'center' => BoxAlign.center,
          'right' => BoxAlign.right,
          _ => BoxAlign.left,
        },
      ),
    );
  }

  /// The libpdf cell of [data] in [font], with prawn-table's borders.
  TableCell _tableCell(
    _TableCellData data,
    _FontState font,
    ThemeColor? background,
    List<_Side> sides,
  ) {
    final padding = EdgeInsets(
      top: data.padding[0],
      right: data.padding[1],
      bottom: data.padding[2],
      left: data.padding[3],
    );
    final List<LayoutBox> content;
    double Function(double, double)? offset;
    if (data.blocks case final blocks?) {
      content = blocks;
      if (data.valign != 'top') {
        offset = (room, height) => switch (data.valign) {
          'middle' => math.max(0, (room - height) / 2),
          _ => math.max(0, room - height),
        };
      }
    } else {
      final box = _textBox(
        data.text,
        font,
        align: data.align,
        normalize: data.inlineFormat && !data.text.contains('\n\n'),
        cell: true,
        inlineFormat: data.inlineFormat,
      );
      content = [CustomBox(_Widened(box, 1))];
      // Prawn aligns the text in a box a point taller than the room (its
      // FPTolerance), by the text's height without the trailing line gap.
      final gap = _fonts.font(font.family, font.style).lineGapAt(font.size);
      offset = switch (data.valign) {
        'middle' => (room, height) => (room + 1 - (height - gap)) / 2,
        'bottom' => (room, height) => room + 1 - (height - gap),
        _ => null,
      };
    }
    return TableCell(
      content,
      colSpan: data.colspan,
      rowSpan: data.rowspan,
      padding: padding,
      background: pdfColorOf(background),
      verticalOffset: offset,
      decoration: (page, rect, {required first, required last}) {
        final canvas = page.canvas;
        void side(_Side side, double x1, double y1, double x2, double y2) {
          final color = pdfColorOf(themeColor(side.color));
          if (side.width <= 0 || color == null) return;
          canvas
            ..save()
            ..setStrokeColor(color)
            ..setLineWidth(side.width);
          switch (side.style?.rubyString) {
            case 'dashed':
              canvas.dash([side.width * 4]);
            case 'dotted':
              canvas.dash([side.width]);
          }
          canvas
            ..moveTo(x1, y1)
            ..lineTo(x2, y2)
            ..stroke()
            ..restore();
        }

        final [top, right, bottom, left] = sides;
        final t = rect.top;
        final b = rect.bottom;
        side(top, rect.left, t, rect.right, t);
        side(bottom, rect.left, b, rect.right, b);
        side(
          left,
          rect.left,
          t + top.width / 2,
          rect.left,
          b - bottom.width / 2,
        );
        side(
          right,
          rect.right,
          t + top.width / 2,
          rect.right,
          b - bottom.width / 2,
        );
      },
    );
  }

  /// prawn-table's column widths for an autowidth table: each column as
  /// wide as its widest text unwrapped, shrunk toward the narrowest the
  /// cells allow when that's too wide ([fraction] of the width asks a
  /// width).
  List<ColumnWidth> _autoWidths(
    Table node,
    List<(int, int, _TableCellData)> placed,
    int numCols,
    double? fraction,
  ) {
    final mWidths = <(String, String, double), double>{};
    double widthOfM(_FontState font) =>
        mWidths[(font.family, font.style, font.size)] ??= _fonts
            .font(font.family, font.style)
            .widthOf('M', font.size, kerning: font.kerning);
    List<double>? cache;
    double? cachedFor;
    List<double> widths(double available) {
      if (cache != null && cachedFor == available) return cache!;
      final naturals = List<double>.filled(numCols, 0);
      final mins = List<double>.filled(numCols, 0);
      for (final (_, c, data) in placed) {
        final padding = data.padding[1] + data.padding[3];
        final double content;
        if (data.blocks != null) {
          content = available - padding;
        } else {
          final box = _textBox(
            data.text,
            data.font,
            align: 'left',
            normalize: data.inlineFormat && !data.text.contains('\n\n'),
            cell: true,
            inlineFormat: data.inlineFormat,
          );
          content = math.min(box.intrinsicWidths().$2, available);
        }
        if (data.colspan == 1) {
          naturals[c] = math.max(naturals[c], padding + content);
          mins[c] = math.max(
            mins[c],
            padding + math.min(content, widthOfM(data.font)),
          );
        }
      }
      final natural = naturals.fold<double>(0, (a, b) => a + b);
      final least = mins.fold<double>(0, (a, b) => a + b);
      final width = fraction != null
          ? available * fraction
          : math.min(natural, available);
      List<double> result;
      if (width < natural - 1e-9 && natural > least) {
        final f = (width - least) / (natural - least);
        result = [
          for (var c = 0; c < numCols; c++)
            f * (naturals[c] - mins[c]) + mins[c],
        ];
      } else if (width > natural + 1e-9) {
        // Grown toward each column's most (the available width).
        final most = available * numCols;
        final f = (width - natural) / (most - natural);
        result = [
          for (var c = 0; c < numCols; c++)
            f * (available - naturals[c]) + naturals[c],
        ];
      } else {
        result = naturals;
      }
      cachedFor = available;
      return cache = result;
    }

    return [
      for (var c = 0; c < numCols; c++)
        ColumnWidth.computed((available) => widths(available)[c]),
    ];
  }

  // Admonitions.

  /// Converts the admonition [node] (with a text label).
  void convertAdmonition(Block node) {
    final type = node.attr('name') ?? 'note';
    final labelAlign = _s('admonition_label_text_align') ?? 'center';
    final minWidth = _n('admonition_label_min_width')?.toDouble();
    var labelFont = _themeFont('admonition_label', _font);
    labelFont = _themeFont('admonition_label_$type', labelFont);
    var label = _plain(node.caption ?? '');
    if (labelFont.transform case final transform? when transform != 'none') {
      label = transformText(label, transform);
    }
    // A font icon in place of the text label.
    final icon = _document.attr('icons') == 'font' && !node.hasAttr('icon')
        ? _admonitionIcon(type)
        : null;
    var labelWidth = icon != null
        ? icon.size * 1.5
        : _fonts
              .font(labelFont.family, labelFont.style)
              .widthOf(label, labelFont.size, kerning: labelFont.kerning);
    if (minWidth != null && minWidth > labelWidth) labelWidth = minWidth;
    final iconColor = icon?.color ?? _font.color;
    final cpad = _padding('admonition_padding');
    final lpad = _theme.value('admonition_label_padding') == null
        ? cpad
        : _padding('admonition_label_padding');
    final ruleWidth = (_n('admonition_column_rule_width') ?? 0).toDouble();
    final ruleColor =
        _c('admonition_column_rule_color') ?? _c('base_border_color');
    final labelText = label.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final labelBox = _textBox(
      labelText,
      labelFont.copyWith(lineHeight: 1),
      align: labelAlign,
      normalize: false,
    );
    // The label shrinks to fit the block (the gem's shrink_to_fit).
    final fittedLabel = _textBox(
      labelText,
      labelFont.copyWith(lineHeight: 1),
      align: labelAlign,
      normalize: false,
      shrinkToFit: true,
    );
    final ruleX = lpad.left + labelWidth + lpad.right;
    // How far down the label is: in the middle, at the top or at the
    // bottom (`admonition_label_vertical_align`).
    final labelValign = _s('admonition_label_vertical_align') ?? 'middle';
    double labelOffset(double room, double height) => switch (labelValign) {
      'top' => 0,
      'bottom' => math.max(0, room - height),
      _ => math.max(0, (room - height) * 0.5),
    };
    void decorate(
      PdfPage page,
      PdfRect rect, {
      required bool first,
      required bool last,
    }) {
      final canvas = page.canvas;
      // On a page the block continues past, the label's room and the
      // rule reach the page's bottom margin, as in the gem (whose label
      // box is as high as the cursor is).
      final bottom = last ? rect.bottom : _pageMargins(_document).bottom;
      final room = rect.top - bottom;
      if (ruleWidth > 0) {
        if (pdfColorOf(ruleColor) case final color?) {
          _verticalRule(
            canvas,
            color,
            rect.left + ruleX,
            rect.top,
            bottom,
            ruleWidth,
            _s('admonition_column_rule_style'),
          );
        }
      }
      if (!first) return;
      if (icon != null) {
        final size = math.min(room, icon.size);
        final glyph = _textBox(
          icon.glyph,
          _FontState(
            family: icon.set,
            style: 'normal',
            size: size,
            color: iconColor,
            lineHeight: 1,
            kerning: _font.kerning,
          ),
          align: labelAlign,
          normalize: false,
          gaps: false,
        ).place(labelWidth, double.infinity, atTop: true);
        final offset = labelOffset(room, size);
        glyph?.paint(page, rect.left + lpad.left, rect.top - offset);
        return;
      }
      final whole = labelBox.place(labelWidth, double.infinity, atTop: true);
      if (whole == null) return;
      final offset = labelOffset(room, whole.height);
      final placed = fittedLabel.place(labelWidth, room - offset, atTop: true);
      placed?.paint(page, rect.left + lpad.left, rect.top - offset);
    }

    final children = _collect(() {
      if (node.hasTitle) {
        _caption(node, category: 'admonition', labeled: false);
      }
      _withFont(
        'admonition',
        () => _withBaseKeys('admonition', () => _traverse(node)),
      );
    });
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: EdgeInsets(
            top: cpad.top,
            right: cpad.right,
            bottom: cpad.bottom,
            left: lpad.left + labelWidth + lpad.right + cpad.left,
          ),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
          decoration: _blockDecoration('admonition', extra: decorate),
        ),
      ),
    );
  }

  /// The admonition icons of the gem, by type: icon, color and size.
  static const Map<String, (String, String, double)> _admonitionIcons = {
    'caution': ('fas-fire', 'BF3400', 24),
    'important': ('fas-exclamation-circle', 'BF0000', 24),
    'note': ('fas-info-circle', '19407C', 24),
    'tip': ('far-lightbulb', '111111', 24),
    'warning': ('fas-exclamation-triangle', 'BF6900', 24),
  };

  /// The font icon of admonitions of [type] (the gem's
  /// `admonition_icon_data`): its set, glyph, color and size.
  ({String set, String glyph, ThemeColor? color, double size})? _admonitionIcon(
    String type,
  ) {
    final defaults = _admonitionIcons[type];
    var name = defaults?.$1;
    ThemeColor? color = switch (defaults?.$2) {
      final hex? => HexColor(hex),
      null => null,
    };
    var size = defaults?.$3 ?? 24;
    if (_theme.value('admonition_icon_$type') case ThemeMap(:final entries)) {
      if (entries['name'] case final value?) {
        name = value.rubyString;
        if (!iconSets.any((set) => name!.startsWith('$set-')) &&
            !name.startsWith('fa-')) {
          name = 'fa-$name';
        }
      }
      if (themeColor(entries['stroke_color']) case final value?) {
        color = value;
      }
      if (entries['size'] case ThemeNumber(:final value)) {
        size = value.toDouble();
      }
    }
    name ??= _admonitionIcons['note']!.$1;
    final (set, _, glyph) = _resolveIcon(name, null);
    if (glyph == null || !_iconsInstalled(set)) return null;
    return (set: set, glyph: glyph, color: color, size: size);
  }

  /// The icon sets whose font was found missing (said once each).
  final Set<String> _missingIcons = {};

  /// Whether the font of icon set [set] is installed; when it isn't, says
  /// so once (its icons are then shown as their text).
  bool _iconsInstalled(String set) {
    if (_fonts.hasIcons(set)) return true;
    if (_missingIcons.add(set)) {
      logger.warn(
        'the $set icon font is not installed: its icons are shown as text '
        '(`asciidart doctor` installs it)',
      );
    }
    return false;
  }

  /// The set, name and glyph of icon [name] (`<set>-<name>`, a name of
  /// the `fa` set, or in [explicitSet]); the glyph is null when there's no
  /// such icon.
  (String, String, String?) _resolveIcon(String name, String? explicitSet) {
    var iconName = name;
    var set = explicitSet ?? _document.attr('icon-set') ?? 'fa';
    final explicit = explicitSet != null;
    String? glyph;
    if (set == 'fa' || !iconSets.contains(set)) {
      set = 'fa';
      final bare = iconName.startsWith('fa-')
          ? iconName.substring(3)
          : iconName;
      if (legacyIcon(bare) case final remapped?) {
        final dash = remapped.indexOf('-');
        set = remapped.substring(0, dash);
        iconName = remapped.substring(dash + 1);
        glyph = iconGlyph(set, iconName);
      } else {
        for (final candidate in fontAwesomeSets) {
          if (iconGlyph(candidate, iconName) case final found?) {
            set = candidate;
            glyph = found;
            break;
          }
        }
      }
    } else {
      glyph = iconGlyph(set, iconName);
    }
    if (glyph == null &&
        !explicit &&
        iconSets.any((prefix) => iconName.startsWith('$prefix-'))) {
      final dash = iconName.indexOf('-');
      set = iconName.substring(0, dash);
      iconName = iconName.substring(dash + 1);
      glyph = iconGlyph(set, iconName);
    }
    return (set, iconName, glyph);
  }

  // Code.

  /// Converts the listing or literal block [node] (without syntax
  /// highlighting).
  void convertCode(Block node) {
    // The modern engine styles a block with a role by the theme's
    // code_role_<role>_* keys, over its code_* keys.
    if (node.roles.isNotEmpty) {
      final saved = _theme;
      for (final role in node.roles) {
        _theme = _theme.overlaid(
          'code_role_${role.replaceAll('-', '_')}_',
          'code_',
        );
      }
      if (!identical(_theme, saved)) {
        try {
          _convertCode(node);
        } finally {
          _theme = saved;
        }
        return;
      }
    }
    _convertCode(node);
  }

  void _convertCode(Block node) {
    final font = _themeFont('code', _font);
    var source = '';
    _withFont('code', () => source = _guardIndentation(node.content() ?? ''));
    // Highlighted by hilite (`source-highlighter=highlight.js`): the
    // modern engine colors the tokens as the `highlightjs-theme` does
    // (github by default); the gem leaves them as text.
    if (source.contains('<span class="hljs-')) {
      // A line's indentation inside a token (a string that runs over
      // lines) kept as well: its first space a no-break one.
      source = source.replaceAllMapped(
        RegExp(r'(^|\n)((?:<[^>]*>)+) '),
        (m) => '${m[1]}${m[2]}\u00a0',
      );
      final theme = _document.attr('highlightjs-theme') ?? 'github';
      if (_highlightStyles.putIfAbsent(theme, () => HighlightStyle.named(theme))
          case final style?) {
        source = style.markup(source);
      }
    }
    final captionBelow = _s('code_caption_end') == 'bottom';
    if (!captionBelow && node.hasTitle) _caption(node, category: 'code');
    // The modern engine splits a listing between lines, leaving at least
    // code_orphans and code_widows lines on either side (2 each), and
    // marks a line that wraps, going on with a hanging indent
    // (code_wrap_indent, 1em; code_wrap_marker: none leaves the arrow
    // out).
    final wrapIndent = _length('code_wrap_indent', font.size) ?? font.size;
    final wrapMarker =
        _choice('code_wrap_marker', const ['arrow', 'none']) != 'none';
    // Without a hanging indent or a marker, a long line wraps as Typst
    // wraps raw text: at the line breaking algorithm's breaks (after a
    // slash too), as many words on a line as fit.
    final plainWrap = wrapIndent == 0 && !wrapMarker;
    if (plainWrap) source = _breakAfterSlashes(source);
    final box = _textBox(
      source,
      font.copyWith(color: _c('code_font_color') ?? font.color),
      align: 'left',
      normalize: false,
      orphans: (_n('code_orphans') ?? 2).toInt(),
      widows: (_n('code_widows') ?? 2).toInt(),
      wrapIndent: plainWrap ? null : wrapIndent,
      wrapMarker: wrapMarker,
    );
    CustomContent content = box;
    if (node.hasOption('autofit') || _document.hasAttr('autofit-option')) {
      final minimum =
          _theme.value('code_font_size_min') ??
          _theme.value('base_font_size_min');
      content = AutofitTextBox(
        box,
        minimum: switch (minimum) {
          ThemeNumber(:final value) => value.toDouble(),
          ThemeString(:final value) => resolveFontSize(
            value,
            font.size,
            _rootFontSize,
          ),
          _ => null,
        },
      );
    }
    _out.add(
      BlockBox(
        [CustomBox(content)],
        style: BoxStyle(
          padding: _padding('code_padding'),
          margin: EdgeInsets(bottom: captionBelow ? 0 : _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
          decoration: _blockDecoration('code'),
        ),
      ),
    );
    if (captionBelow && node.hasTitle) {
      _caption(node, category: 'code');
      final margin = _marginBelow(node);
      if (margin > 0) _out.add(SpacerBox(margin));
    }
  }

  /// The highlight.js themes read, by name.
  final Map<String, HighlightStyle?> _highlightStyles = {};

  /// Converts the passthrough block [node]: its content as code text
  /// (the gem's `convert_pass`).
  void convertPass(Block node) {
    final font = _themeFont(
      'code',
      _font,
    ).copyWith(color: _c('base_font_color'));
    _out.add(
      CustomBox(
        _textBox(
          _guardIndentation(node.content() ?? ''),
          font,
          align: _baseTextAlign,
          normalize: false,
          inlineFormat: false,
        ),
        style: BoxStyle(margin: EdgeInsets(bottom: _marginBelow(node))),
      ),
    );
  }

  /// Converts the STEM block [node]: AsciiMath typeset in display style
  /// (ADR-0014), centered (`stem_text_align`); LaTeX, for now, as its
  /// source in a code block (the gem's `convert_stem` without a math
  /// renderer).
  void convertStem(Block node) {
    final style = node.style ?? node.attr('style');
    if (style == 'asciimath' || style == 'latexmath') {
      final source = _unescapeXml(node.content() ?? '');
      final latex = style == 'latexmath';
      if (_mathOf(source, latex: latex, display: true) case final formula?) {
        if (node.hasTitle) _caption(node, category: 'code');
        final box = _math!.layout(
          formula,
          size: _themeFont('stem', _font).size,
          display: true,
        );
        _out.add(
          CustomBox(
            _DisplayMath(
              box,
              source,
              align: _s('stem_text_align') ?? 'center',
              color: _color(_themeFont('stem', _font).color),
            ),
            style: BoxStyle(
              margin: EdgeInsets(bottom: _marginBelow(node)),
              keepTogether: true,
              anchor: node.id,
            ),
          ),
        );
        return;
      }
    }
    _warnMathAsSource();
    if (node.hasTitle) _caption(node, category: 'code');
    final font = _themeFont('code', _font);
    _out.add(
      BlockBox(
        [
          CustomBox(
            _textBox(
              _guardIndentation(node.content() ?? ''),
              font,
              align: 'left',
              normalize: false,
              inlineFormat: false,
            ),
          ),
        ],
        style: BoxStyle(
          padding: _padding('code_padding'),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
          decoration: _blockDecoration('code'),
        ),
      ),
    );
  }

  bool _warnedMath = false;

  /// The math layout: in the theme's `math_font_family` (a font with an
  /// OpenType `MATH` table), else Noto Sans Math (installed); a character
  /// the font lacks in the base font. Null when no math font loads.
  late final MathLayout? _math = () {
    EmbeddedFont? fontOf(String family) {
      try {
        final face = _fonts.font(family);
        if (face.pdf case final EmbeddedFont font
            when font.font.hasTable('MATH')) {
          return font;
        }
      } on FontException {
        // Reported below.
      }
      return null;
    }

    final family = _s('math_font_family');
    var font = family == null ? null : fontOf(family);
    if (family != null && font == null) {
      logger.warn(
        'theme key math_font_family: $family is not a font with a MATH '
        'table; using Noto Sans Math',
      );
    }
    font ??= _fonts.hasFamily('Noto Sans Math')
        ? fontOf('Noto Sans Math')
        : null;
    if (font == null) {
      if (!_warnedMath) {
        _warnedMath = true;
        logger.warn(
          'math is shown as its source in the PDF: no math font is '
          'installed (`asciidart doctor` installs Noto Sans Math)',
        );
      }
      return null;
    }
    final base = _fonts.font(_font.family, _font.style).pdf;
    return MathLayout(
      font,
      fallbacks: [if (base case final EmbeddedFont text) text],
    );
  }();

  /// The formula of the AsciiMath (or with [latex], LaTeX) [source] (its
  /// MathML), or null when it can't be set (no math font, or MathML the
  /// layout can't read). A LaTeX command it doesn't know is reported.
  MathNode? _mathOf(String source, {bool latex = false, bool display = false}) {
    if (_math == null) return null;
    final unknown = <String>{};
    try {
      final mathml = latex
          ? latexToMathml(_stripDelimiters(source), unknown: unknown)
          : asciimathToMathml(source);
      if (unknown.isNotEmpty) {
        logger.warn(
          'unknown LaTeX math command${unknown.length == 1 ? '' : 's'} '
          '${unknown.join(', ')}, shown as written: $source',
        );
      }
      return parseMathML(mathml);
    } on MathMLException catch (error) {
      logger.warn('could not typeset math: $source ($error)');
      return null;
    }
  }

  /// LaTeX math without the `\(...\)`, `\[...\]` or `$...$` around it
  /// (Asciidoctor keeps them in `latexmath` content).
  static String _stripDelimiters(String source) {
    final text = source.trim();
    for (final (open, close) in const [
      (r'\(', r'\)'),
      (r'\[', r'\]'),
      (r'$$', r'$$'),
      (r'$', r'$'),
    ]) {
      if (text.length >= open.length + close.length &&
          text.startsWith(open) &&
          text.endsWith(close)) {
        return text.substring(open.length, text.length - close.length);
      }
    }
    return text;
  }

  var _mathCount = 0;

  /// The image markup of the inline AsciiMath (or with [latex], LaTeX)
  /// [text] (escaped as the text is), its formula registered as an inline
  /// graphic, or null.
  String? _inlineMath(String text, {bool latex = false}) {
    final source = _unescapeXml(text);
    final formula = _mathOf(source, latex: latex);
    if (formula == null) return null;
    final src = 'math:${_mathCount++}';
    _inlineGraphics[src] = InlineMath(formula, _math!, source: source);
    return '<img src="$src" format="math" alt="${_escapeXml(source)}">';
  }

  static String _unescapeXml(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#8217;', "'")
      .replaceAll('&amp;', '&');

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Says once per document, in the modern engine, that math is set as
  /// its source (ADR-0014: the PDF lays out no math yet).
  void _warnMathAsSource() {
    if (_warnedMath) return;
    _warnedMath = true;
    logger.warn('math is shown as its source in the PDF (not typeset yet)');
  }

  /// Converts the audio or video block [node]: a link to the media (or
  /// the video's poster image), as the gem's `convert_audio` and
  /// `convert_video` do.
  void convertMedia(Block node) {
    final doc = _document;
    final target = node.attr('target') ?? '';
    final audio = node.context == BlockContext.audio;
    String path;
    String type;
    var poster = audio ? null : node.attr('poster');
    switch (poster) {
      case 'youtube':
        path = 'https://www.youtube.com/watch?v=$target';
        poster = doc.hasAttr('allow-uri-read')
            ? 'https://img.youtube.com/vi/$target/maxresdefault.jpg'
            : null;
        type = 'YouTube video';
      case 'vimeo':
        path = 'https://vimeo.com/$target';
        poster = null;
        type = 'Vimeo video';
      default:
        path = node.mediaUri(target);
        type = audio ? 'audio' : 'video';
    }
    if (poster != null && poster.isNotEmpty) {
      final saved = {...node.attributes};
      node.attributes
        ..['target'] = poster
        ..['link'] = path;
      try {
        convertImage(node);
      } finally {
        node.attributes
          ..clear()
          ..addAll(saved);
      }
      return;
    }
    final play = doc.attr('icons') == 'font' && _iconsInstalled('fas')
        ? '<font name="fas">${iconGlyph('fas', 'play') ?? ''}</font>'
        : '►';
    _out.add(
      CustomBox(
        _textBox(
          '$play <a href="$path">$path</a> <em>($type)</em>',
          _font,
          align: _baseTextAlign,
          normalize: false,
        ),
        style: BoxStyle(anchor: node.id),
      ),
    );
    if (node.hasTitle) _caption(node, labeled: false, bottom: true);
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
  }

  /// [text] with its tabs expanded and its indentation kept: a leading
  /// space of each line becomes a no-break space (the gem's
  /// `guard_indentation`).
  static String _guardIndentation(String text) {
    var result = _expandTabs(text);
    if (result.isEmpty) return result;
    if (result.startsWith(' ')) result = '\u00a0${result.substring(1)}';
    return result.replaceAll('\n ', '\n\u00a0');
  }

  /// [text] with tabs expanded to the next multiple of 4 columns (the
  /// gem's `expand_tabs`).
  static String _expandTabs(String text) {
    if (!text.contains('\t')) return text;
    return text
        .split('\n')
        .map((line) {
          if (!line.contains('\t')) return line;
          final out = StringBuffer();
          var column = 0;
          for (final char in line.split('')) {
            if (char == '\t') {
              final spaces = 4 - column % 4;
              out.write(' ' * spaces);
              column += spaces;
            } else {
              out.write(char);
              column++;
            }
          }
          return out.toString();
        })
        .join('\n');
  }

  // Captions.

  /// The caption of [node] (its title; with [labeled], its captioned
  /// title) above it (the gem's `ink_caption`, at the top).
  void _caption(
    AbstractBlock node, {
    String? category,
    bool labeled = true,
    bool bottom = false,
    String? blockAlign,
  }) {
    _out.add(
      _captionBox(
        node,
        category: category,
        labeled: labeled,
        bottom: bottom,
        blockAlign: blockAlign,
      ),
    );
  }

  /// The caption of [node] (see [_caption]), or nothing for a node without
  /// a title.
  CustomBox _captionBox(
    AbstractBlock node, {
    String? category,
    bool labeled = true,
    bool bottom = false,
    String? blockAlign,
  }) {
    final title = labeled ? node.captionedTitle() : node.title;
    if (title == null || title.isEmpty) {
      return const CustomBox(_Nothing());
    }
    final captionKey = category == null ? 'caption' : '${category}_caption';
    final outside =
        (_n('${captionKey}_margin_outside') ??
                _n('caption_margin_outside') ??
                0)
            .toDouble();
    final inside =
        (_n('${captionKey}_margin_inside') ?? _n('caption_margin_inside') ?? 0)
            .toDouble();
    var align =
        _s('${captionKey}_align') ?? _s('caption_align') ?? _baseTextAlign;
    if (align == 'inherit') align = blockAlign ?? _baseTextAlign;
    var textAlign =
        _s('${captionKey}_text_align') ?? _s('caption_text_align') ?? align;
    if (textAlign == 'inherit') textAlign = align;
    var font = _themeFont('caption', _font);
    if (category != null) font = _themeFont(captionKey, font);
    var text = title;
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform);
    }
    // The modern engine's `<category>_caption_indent`: set in from the
    // left (a code block's caption over its padded code, as Typst's
    // figure inset).
    final indent =
        _length('${captionKey}_indent', font.size) ??
        _length('caption_indent', font.size) ??
        0.0;
    // A background behind the text, as wide as the block's room.
    final background = pdfColorOf(
      _c('${captionKey}_background_color') ?? _c('caption_background_color'),
    );
    return CustomBox(
      _textBox(
        text,
        font,
        align: textAlign,
        inherit: _decoration('caption'),
        normalize: false,
        normalizeLineHeight: true,
        hyphenate: true,
      ),
      style: BoxStyle(
        margin: bottom
            ? EdgeInsets(top: inside, bottom: outside, left: indent)
            : EdgeInsets(top: outside, bottom: inside, left: indent),
        // A caption above its block stays with it in the modern engine.
        keepWithNext: !bottom,
        decoration: background == null
            ? null
            : (page, rect, {required first, required last}) => page.canvas
                ..save()
                ..setFillColor(background)
                ..rect(rect)
                ..fill()
                ..restore(),
      ),
    );
  }

  // Lists.

  /// The list markers in effect, innermost last.
  final List<_Numeral?> _listNumerals = [];
  final List<String?> _listBullets = [];

  /// Converts the unordered list [node].
  void convertUlist(ListBlock node) {
    String? bullet;
    if (node.hasOption('checklist')) {
      bullet = 'checkbox';
    } else if (node.style case final style?) {
      bullet = switch (style) {
        'bibliography' => 'square',
        'unstyled' || 'no-bullet' => null,
        'disc' || 'circle' || 'square' || 'none' => style,
        _ => () {
          logger.warn('unknown unordered list style: $style');
          return 'disc';
        }(),
      };
    } else {
      // (`ulist_marker_nesting: ulist`, modern engine: the level among
      // unordered lists alone, as Typst's list markers.)
      final own =
          _choice('ulist_marker_nesting', const ['all', 'ulist']) == 'ulist';
      bullet = switch (_listLevel(
        node,
        only: own ? BlockContext.ulist : null,
      )) {
        1 => 'disc',
        2 => 'circle',
        _ => 'square',
      };
    }
    _listBullets.add(bullet);
    _list(node);
    _listBullets.removeLast();
  }

  /// Converts the ordered list [node].
  void convertOlist(ListBlock node) {
    // The modern engine styles an ordered list with a role by the theme's
    // olist_role_<role>_* keys, over its olist_* keys.
    if (node.roles.isNotEmpty) {
      final saved = _theme;
      for (final role in node.roles) {
        _theme = _theme.overlaid(
          'olist_role_${role.replaceAll('-', '_')}_',
          'olist_',
        );
      }
      if (!identical(_theme, saved)) {
        try {
          _convertOlist(node);
        } finally {
          _theme = saved;
        }
        return;
      }
    }
    _convertOlist(node);
  }

  void _convertOlist(ListBlock node) {
    var numeral = switch (node.style) {
      'loweralpha' => const _Numeral.letters('a'),
      'upperalpha' => const _Numeral.letters('A'),
      'lowerroman' => const _Numeral.roman(1, upper: false),
      'upperroman' => const _Numeral.roman(1, upper: true),
      'lowergreek' => const _Numeral.letters('\u03b1'),
      'unstyled' || 'unnumbered' || 'no-bullet' => null,
      'none' => const _Numeral.none(),
      _ => const _Numeral.decimal(1),
    };
    final start =
        node.attr('start') ??
        (node.hasOption('reversed') ? '${node.items.length}' : null);
    if (numeral case final first?
        when first.kind != _NumeralKind.none && start != null) {
      final value = int.tryParse(start.trim()) ?? 0;
      var current = first;
      if (value > 1) {
        for (var i = 0; i < value - 1; i++) {
          current = current.next;
        }
      } else if (value < 1 && current.kind != _NumeralKind.letters) {
        for (var i = 0; i < (value - 1).abs(); i++) {
          current = current.previous;
        }
      }
      numeral = current;
    }
    _listNumerals.add(numeral);
    _list(node);
    _listNumerals.removeLast();
  }

  /// [node]'s nesting among lists (among lists of context [only]).
  int _listLevel(ListBlock node, {BlockContext? only}) {
    var level = 1;
    var ancestor = node.parent;
    while (ancestor != null) {
      if (ancestor case ListBlock(:final context)
          when only == null
              ? context == BlockContext.ulist || context == BlockContext.olist
              : context == only) {
        level++;
      }
      ancestor = ancestor.parent;
    }
    return level;
  }

  void _list(ListBlock node) {
    if (node.hasTitle) _caption(node, category: 'list', labeled: false);
    String? align;
    for (final role in node.roles) {
      if (role.startsWith('text-') &&
          const {
            'justify',
            'left',
            'center',
            'right',
          }.contains(role.substring(5))) {
        align = role.substring(5);
      }
    }
    if (align == null && node.style == 'bibliography') align = 'left';
    // (An ordered list's own, `olist_text_align`, in the modern engine.)
    if (node.context == BlockContext.olist) {
      align ??= _s('olist_text_align');
    }
    align ??= _s('list_text_align');
    final unmarked =
        (node.context == BlockContext.ulist && _listBullets.last == null) ||
        (node.context == BlockContext.olist && _listNumerals.last == null);
    var indent = (_n('list_indent') ?? 0).toDouble();
    if (unmarked) {
      if (node.style == 'unstyled') {
        indent = 0;
      } else if (indent > 0) {
        final font = _fonts.font(_font.family, _font.style);
        final sample = node.context == BlockContext.ulist ? '\u2022x' : '1.x';
        indent = math.max(indent - font.widthOf(sample, _font.size), 0);
      }
    }
    final saved = _out;
    final items = <LayoutBox>[];
    _out = items;
    // Typst's lists (the modern engine's list_body_indent): the markers at
    // list_indent, the text after the widest marker and the body indent.
    // An ordered list's own (`olist_body_indent`; `olist_marker_width`,
    // its numbers in boxes that wide at their left: Typst's enums).
    final ordered = node.context == BlockContext.olist;
    final bodyIndent =
        (ordered ? _length('olist_body_indent', _font.size) : null) ??
        _length('list_body_indent', _font.size);
    final savedBodyIndent = _listBodyIndent;
    final savedMarkerWidth = _listMarkerWidth;
    final savedMarkerBox = _listMarkerBox;
    _listBodyIndent = bodyIndent;
    _listMarkerWidth = 0;
    _listMarkerBox = ordered ? _length('olist_marker_width', _font.size) : null;
    for (final item in node.items) {
      _listItem(item, node, align);
    }
    if (bodyIndent != null && !unmarked) {
      indent += _listMarkerWidth + bodyIndent;
    }
    _listBodyIndent = savedBodyIndent;
    _listMarkerWidth = savedMarkerWidth;
    _listMarkerBox = savedMarkerBox;
    _out = saved;
    final nested = node.parent is ListItem;
    _out.add(
      BlockBox(
        items,
        style: BoxStyle(
          margin: EdgeInsets(
            left: indent,
            bottom: nested ? 0 : _marginBelow(node, fallback: 'prose'),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  void _listItem(ListItem item, ListBlock list, String? align) {
    String? marker;
    var markerFamily = _font.family;
    var markerSize = _font.size;
    var markerStyle = _font.style;
    var markerColor = _c('list_marker_font_color') ?? _font.color;
    var markerLineHeight = _font.lineHeight;
    // The modern engine's `<prefix>_font_variant_numeric` (old-style
    // figures for an ordered list's numbers).
    final markerFeatures = <String>{};
    void styleFrom(String prefix) {
      if (fontFeature(_s('${prefix}_font_variant_numeric')) case final f?) {
        markerFeatures.add(f);
      }

      markerColor = _c('${prefix}_font_color') ?? markerColor;
      markerFamily = _s('${prefix}_font_family') ?? markerFamily;
      markerSize = (_n('${prefix}_font_size') ?? markerSize).toDouble();
      markerStyle = _fontStyle(_s('${prefix}_font_style')) ?? markerStyle;
      markerLineHeight = (_n('${prefix}_line_height') ?? markerLineHeight)
          .toDouble();
    }

    if (list.context == BlockContext.olist) {
      final index = _listNumerals.removeLast();
      if (index != null) {
        if (index.kind == _NumeralKind.none) {
          marker = '';
          _listNumerals.add(index);
        } else {
          final text = index.text;
          marker =
              list.style == 'decimal' &&
                  index.kind == _NumeralKind.decimal &&
                  index.value.abs() < 10
              ? '${index.value < 0 ? '-' : ''}0${index.value.abs()}.'
              : '$text.';
          _listNumerals.add(
            list.hasOption('reversed') ? index.previous : index.next,
          );
          styleFrom('olist_marker');
        }
      } else {
        _listNumerals.add(null);
      }
    } else if (_listBullets.last case final bullet?) {
      var type = bullet;
      if (bullet == 'checkbox') {
        if (item.hasAttr('checkbox')) {
          type = item.hasAttr('checked') ? 'checked' : 'unchecked';
          marker =
              _s('ulist_marker_${type}_content') ??
              (type == 'checked' ? '\u2611' : '\u2610');
        }
      } else {
        marker =
            _s('ulist_marker_${type}_content') ??
            switch (type) {
              'disc' => '\u2022',
              'circle' => '\u25e6',
              'square' => '\u25aa',
              _ => '',
            };
      }
      if (marker != null) {
        // Theme keys of the marker type win over the generic ones.
        styleFrom('ulist_marker');
        styleFrom('ulist_marker_$type');
      }
    }

    double? marginBottom = 0;
    if (item.isCompound) {
      marginBottom = null;
    } else if (_nextEnclosedBlockDescending(item) != null) {
      marginBottom = (_n('list_item_spacing') ?? 0).toDouble();
    }
    final text = item.text;
    final primary = text == null || text.isEmpty
        ? (item.blocks.isEmpty ? _dummyText : null)
        : text;
    final children = <LayoutBox>[];
    final saved = _out;
    _out = children;
    final markerFont = _FontState(
      family: markerFamily,
      style: markerStyle,
      size: markerSize,
      color: markerColor,
      lineHeight: markerLineHeight,
      kerning: _font.kerning,
    );
    if (primary == null && marker != null && marker.isNotEmpty) {
      // No text: the marker is where the first block starts (the gem
      // floats it at the cursor).
      children.add(
        CustomBox(
          _withMarker(
            const _Nothing(),
            marker,
            markerFont,
            features: markerFeatures,
          ),
        ),
      );
    }
    if (primary != null) {
      // The modern engine keeps an item's text from leaving a lone line on
      // either side of a page break, as a paragraph's (`prose_orphans`,
      // `prose_widows`).
      final box = _textBox(
        primary,
        _font,
        align: align ?? _baseTextAlign,
        normalizeLineHeight: true,
        hyphenate: true,
        orphans: (_n('prose_orphans') ?? 2).toInt(),
        widows: (_n('prose_widows') ?? 2).toInt(),
      );
      final metrics = _lineMetrics(_font);
      final lineHeight = _font.lineHeight * _font.size;
      CustomContent content = _MinRoom(
        box,
        // (Under Typst's model, a line is as tall as its cap height.)
        _typstLeading(_font) != null
            ? _fonts.font(_font.family, _font.style).capHeightAt(_font.size)
            : lineHeight + metrics.leading + metrics.paddingTop,
      );
      if (marker != null && marker.isNotEmpty) {
        content = _withMarker(
          content,
          marker,
          markerFont,
          features: markerFeatures,
        );
      }
      children.add(
        CustomBox(
          content,
          style: BoxStyle(
            margin: EdgeInsets(
              bottom:
                  marginBottom ?? (_n('prose_margin_bottom') ?? 0).toDouble(),
            ),
          ),
        ),
      );
    }
    _traverse(item);
    _out = saved;
    _out.add(BlockBox(children, style: BoxStyle(anchor: item.id)));
  }

  /// Converts the description list [node].
  void convertDlist(ListBlock node) {
    switch (node.style) {
      case 'horizontal':
        _horizontalDlist(node);
      case 'qanda':
        _qanda(node);
      case 'unordered' || 'ordered':
        _dlistAsList(node, ordered: node.style == 'ordered');
      default:
        _withBaseKeys('description_list', () => _dlist(node));
    }
  }

  /// Runs [body] with the modern engine's `<category>_*` keys in place of
  /// the theme's (`quote_base_justify_width: widest`: a block Typst sizes
  /// to its content justifies its lines to the widest; `quote_list_*`
  /// for the lists in a quote), as a section role's.
  void _withBaseKeys(String category, void Function() body) {
    final savedAlign = _baseTextAlign;
    final savedTheme = _theme;
    _theme = _theme.overlaid('${category}_', '');
    if (_s('${category}_base_text_align') case final align?) {
      _baseTextAlign = align;
    }
    try {
      body();
    } finally {
      _baseTextAlign = savedAlign;
      _theme = savedTheme;
    }
  }

  /// The height of a line of text in [font] (the gem's
  /// `height_of_typeset_text`).
  double _typesetHeight(_FontState font) => _textBox(
    'A',
    font,
    align: 'left',
  ).place(1000000, double.infinity, atTop: true)!.height;

  /// The styles [font] gives text (to inherit).
  static Set<String> _stylesOf(_FontState font) => {
    if (font.style == 'bold' || font.style == 'bold_italic') 'bold',
    if (font.style == 'italic' || font.style == 'bold_italic') 'italic',
  };

  /// The text of the description list term [term] in [font].
  CustomContent _term(ListItem term, _FontState font) {
    var text = term.text ?? '';
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform);
    }
    return _textBox(
      text,
      font,
      align: 'left',
      normalizeLineHeight: true,
      inheritedStyles: _stylesOf(font),
    );
  }

  /// Adds the description [desc] of a description list entry: its text,
  /// then its blocks (the gem's `traverse_list_item` for descriptions).
  void _description(ListItem desc) {
    final marginBottom = _nextEnclosedBlockDescending(desc) == null
        ? 0.0
        : (_n('prose_margin_bottom') ?? 0).toDouble();
    final text = desc.text;
    final primary = text == null || text.isEmpty
        ? (desc.blocks.isEmpty ? _dummyText : null)
        : text;
    if (primary != null) {
      _out.add(
        CustomBox(
          _textBox(
            primary,
            _font,
            align: _baseTextAlign,
            normalizeLineHeight: true,
            hyphenate: true,
          ),
          style: BoxStyle(margin: EdgeInsets(bottom: marginBottom)),
        ),
      );
    }
    _traverse(desc);
  }

  void _dlist(ListBlock node) {
    final boxes = _collect(() {
      if (node.hasTitle) {
        _caption(node, category: 'description_list', labeled: false);
      }
      final termSpacing = (_n('description_list_term_spacing') ?? 0).toDouble();
      final termFont = _themeFont('description_list_term', _font);
      final termHeight = _typesetHeight(termFont);
      final proseHeight = _typesetHeight(_font);
      final indent = (_n('description_list_description_indent') ?? 0)
          .toDouble();
      // `description_list_term_display: inline` (modern engine): a term
      // run in before its description, the lines after the first hanging
      // by the description indent.
      final runIn =
          _choice('description_list_term_display', const ['block', 'inline']) ==
          'inline';
      for (final DlistEntry(:terms, description: desc) in node.entries) {
        final hasText = desc != null && desc.hasText;
        if (runIn && hasText && terms.length == 1) {
          _runInEntry(
            terms.single,
            desc,
            termFont,
            indent,
            last: identical(node.entries.last.description, desc),
          );
          continue;
        }
        final lines = terms.length + (hasText ? 1 : 0);
        final need =
            lines * termHeight +
            (lines - 1) * termSpacing +
            (desc != null && !hasText && desc.blocks.isNotEmpty
                ? termSpacing + proseHeight
                : 0);
        for (final (i, term) in terms.indexed) {
          final box = _term(term, termFont);
          _out.add(
            CustomBox(
              i == 0 ? _MinRoom(box, need) : box,
              style: BoxStyle(margin: EdgeInsets(top: i > 0 ? termSpacing : 0)),
            ),
          );
        }
        if (desc == null) continue;
        final children = _collect(() {
          if (termSpacing > 0) _out.add(SpacerBox(termSpacing));
          _description(desc);
        });
        _out.add(
          BlockBox(
            children,
            style: BoxStyle(margin: EdgeInsets(left: indent)),
          ),
        );
      }
    });
    _out.add(
      BlockBox(
        boxes,
        style: BoxStyle(
          margin: EdgeInsets(
            bottom: node.parent is ListItem
                ? 0
                : _marginBelow(node, fallback: 'prose'),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Adds a description list entry with its [term] run in before its
  /// description [desc]: one paragraph whose lines after the first hang
  /// by [hang], then the description's blocks, as far in.
  void _runInEntry(
    ListItem term,
    ListItem desc,
    _FontState termFont,
    double hang, {
    bool last = false,
  }) {
    var text = term.text ?? '';
    if (termFont.transform case final transform? when transform != 'none') {
      text = transformText(text, transform);
    }
    final styles = _stylesOf(termFont);
    if (styles.contains('italic')) text = '<em>$text</em>';
    if (styles.contains('bold')) text = '<strong>$text</strong>';
    if (termFont.family != _font.family) {
      text = '<font name="${termFont.family}">$text</font>';
    }
    final blocks = _collect(() => _traverse(desc));
    // The space after the term: an en space, or as wide as
    // `description_list_term_gap` (0.6em, as Typst's terms separator).
    // (A space, where the line may break, as Typst's weak spacing.)
    final gap = switch (_theme.value('description_list_term_gap')) {
      ThemeNumber(:final value) => '<font width="$value"> </font>',
      ThemeString(:final value) => '<font width="$value"> </font>',
      _ => '&#8194;',
    };
    _out.add(
      CustomBox(
        _textBox(
          '$text$gap${desc.text}',
          _font,
          align: _baseTextAlign,
          indent: -hang,
          normalizeLineHeight: true,
          hyphenate: true,
          // (Kept from leaving a lone line at a page break, as a
          // paragraph.)
          orphans: (_n('prose_orphans') ?? 2).toInt(),
          widows: (_n('prose_widows') ?? 2).toInt(),
        ),
        style: BoxStyle(
          margin: EdgeInsets(
            left: hang,
            bottom: blocks.isEmpty
                ? 0
                : (_n('prose_margin_bottom') ?? 0).toDouble(),
          ),
        ),
      ),
    );
    if (blocks.isNotEmpty) {
      _out.add(
        BlockBox(
          blocks,
          style: BoxStyle(margin: EdgeInsets(left: hang)),
        ),
      );
    }
    // The entries apart as paragraphs (Typst's terms: the paragraph
    // spacing between items).
    if (!last) {
      final spacing = (_n('prose_margin_bottom') ?? 0).toDouble();
      if (spacing > 0) _out.add(SpacerBox(spacing));
    }
  }

  /// A description list with its terms in a column beside the
  /// descriptions.
  void _horizontalDlist(ListBlock node) {
    final boxes = _collect(() {
      if (node.hasTitle) {
        _caption(node, category: 'description_list', labeled: false);
      }
      final termFont = _themeFont('description_list_term', _font);
      final prawnFont = _fonts.font(termFont.family, termFont.style);
      final termHeight = _typesetHeight(termFont);
      final proseHeight = _typesetHeight(_font);
      final termSpacing = (_n('description_list_term_spacing') ?? 0).toDouble();
      const termLeft = 10.0;
      const termRight = 10.0;
      const descLeft = 10.0;
      const descRight = 10.0;
      var widest = 0.0;
      for (final entry in node.entries) {
        for (final term in entry.terms) {
          var text = term.text ?? '';
          if (termFont.transform case final transform?
              when transform != 'none') {
            text = transformText(text, transform);
          }
          final width = prawnFont.widthOf(
            _plain(text),
            termFont.size,
            kerning: termFont.kerning,
          );
          if (width > widest) widest = width;
        }
      }
      final rows = <TableRow>[];
      for (final DlistEntry(:terms, description: desc) in node.entries) {
        final need = math.max(
          (termSpacing + termHeight) * terms.length - termSpacing,
          desc != null ? proseHeight : 0.0,
        );
        final termBoxes = [
          for (final (i, term) in terms.indexed)
            CustomBox(
              i == 0
                  ? _MinRoom(_term(term, termFont), need)
                  : _term(term, termFont),
              style: BoxStyle(margin: EdgeInsets(top: i > 0 ? termSpacing : 0)),
            ),
        ];
        rows.add(
          TableRow([
            TableCell(termBoxes, padding: const EdgeInsets(left: termLeft)),
            TableCell(
              desc == null ? const [] : _collect(() => _description(desc)),
              padding: const EdgeInsets(left: descLeft, right: descRight),
            ),
          ]),
        );
      }
      final termWidth = widest + termLeft + termRight;
      _out.add(
        TableBox(
          rows,
          columns: [
            ColumnWidth.computed(
              (width) =>
                  math.min(termWidth, width * 0.5 - termLeft - termRight),
            ),
            const ColumnWidth.fraction(1),
          ],
        ),
      );
    });
    _out.add(
      BlockBox(
        boxes,
        style: BoxStyle(
          margin: EdgeInsets(
            bottom: node.parent is ListItem
                ? 0
                : _marginBelow(node, fallback: 'prose'),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// The callout glyphs of the theme.
  late final List<String> _conumGlyphs = () {
    final setting = _s('conum_glyphs') ?? 'circled';
    List<String> range(int from, int to) => [
      for (var c = from; c <= to; c++) String.fromCharCode(c),
    ];
    String char(String code) => code.startsWith(r'\u')
        ? String.fromCharCode(int.tryParse(code.substring(2), radix: 16) ?? 0)
        : code;
    return switch (setting) {
      'circled' => range(0x2460, 0x2473),
      'filled' => [...range(0x2776, 0x277f), ...range(0x24eb, 0x24f4)],
      _ => [
        for (final part in setting.split(','))
          ...switch (part.trimLeft().split('-')) {
            [final from, final to, ...] => range(
              char(from).runes.first,
              char(to).runes.first,
            ),
            [final from, ...] => [char(from)],
            _ => const <String>[],
          },
      ],
    };
  }();

  /// The glyph of callout [number] (empty when the theme has none). In
  /// the modern engine, `conum_glyphs` may be a text with `%d` for the
  /// number (`[%d]`), and a callout list's markers have their own
  /// (`callout_list_marker_content`: `%d.`).
  String _conumGlyph(int number, {bool list = false}) {
    if (_conumTemplate(list: list) case final template?) {
      return _render(template, {'number': '$number'});
    }
    return number >= 1 && number <= _conumGlyphs.length
        ? _conumGlyphs[number - 1]
        : '';
  }

  /// The template of callout markers (or of a callout list's markers,
  /// with [list]) in the modern engine (ADR-0010): `conum_glyphs` (or
  /// `callout_list_marker_content`) with `{{number}}`.
  String? _conumTemplate({bool list = false}) {
    final template =
        (list ? _s('callout_list_marker_content') : null) ?? _s('conum_glyphs');
    return template != null && template.contains('{{') ? template : null;
  }

  /// Converts the callout list [node].
  void convertColist(ListBlock node) {
    final previous = _previousSibling(node)?.context;
    final marginTop =
        previous == BlockContext.listing || previous == BlockContext.literal
        ? (_n('callout_list_margin_top_after_code') ?? 0).toDouble()
        : 0.0;
    final spacing =
        (_n('callout_list_item_spacing') ?? _n('list_item_spacing') ?? 0)
            .toDouble();
    final align =
        _alignOf(node.roles) ??
        (_s('callout_list_text_align')) ??
        _s('list_text_align');
    final items = _collect(() {
      _withFont('callout_list', () {
        final conumFont = _themeFont('conum', _font);
        final metrics = _lineMetrics(conumFont);
        final minRoom =
            conumFont.lineHeight * conumFont.size +
            metrics.leading +
            metrics.paddingTop;
        // The modern engine's `callout_list_marker_*` font keys, over the
        // conum's.
        final markerFont = _themeFont('callout_list_marker', conumFont);
        final markerFeatures = {
          ?fontFeature(_s('callout_list_marker_font_variant_numeric')),
        };
        final prawnFont = _fonts.font(conumFont.family, conumFont.style);
        // A marker box as wide as `callout_list_marker_width` (modern
        // engine; Typst's enum numbers in a box 1em wide), its marker
        // aligned in it by `callout_list_marker_text_align`.
        final fixedWidth = _length(
          'callout_list_marker_width',
          markerFont.size,
        );
        final markerAlign = _s('callout_list_marker_text_align') ?? 'center';
        for (final (i, item) in node.items.indexed) {
          final glyph = _conumGlyph(i + 1, list: true);
          final markerWidth =
              fixedWidth ??
              prawnFont.widthOf(
                '${glyph}x',
                conumFont.size,
                kerning: conumFont.kerning,
              );
          // In the modern engine, the item is the destination of its
          // markers, and its glyph links back to the first.
          final coids = (item.attr('coids') ?? '')
              .split(' ')
              .where((id) => id.isNotEmpty)
              .toList();
          var markerMarkup = glyph
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;');
          if (coids.isNotEmpty) {
            if (markerFont.color case final color?) {
              markerMarkup =
                  '<font color="${color.rubyString}">$markerMarkup</font>';
            }
            markerMarkup = '<a anchor="${coids.first}">$markerMarkup</a>';
          }
          final marker = _textBox(
            markerMarkup,
            markerFont,
            align: markerAlign,
            normalize: false,
            features: markerFeatures,
          );
          final last = i == node.items.length - 1;
          final text = item.text;
          var primary = text == null || text.isEmpty
              ? (item.blocks.isEmpty ? _dummyText : null)
              : text;
          // (An item of blocks alone is the destination of its first
          // marker only.)
          if (primary != null && coids.isNotEmpty) {
            final destinations = [
              for (final id in coids)
                '<a id="${_calloutItem(id)}">$_dummyText</a>',
            ];
            primary = '${destinations.join()}$primary';
          }
          final children = _collect(() {
            if (primary != null) {
              final box = _textBox(
                primary,
                _font,
                align: align ?? _baseTextAlign,
                normalizeLineHeight: true,
                hyphenate: true,
                // (No lone line at a page break, as a paragraph's.)
                orphans: (_n('prose_orphans') ?? 2).toInt(),
                widows: (_n('prose_widows') ?? 2).toInt(),
              );
              _out.add(
                CustomBox(
                  _MinRoom(
                    _Marked(box, marker, markerWidth, -markerWidth),
                    // (Under Typst's model, a line is as tall as its cap
                    // height.)
                    _typstLeading(_font) != null
                        ? _fonts
                              .font(_font.family, _font.style)
                              .capHeightAt(_font.size)
                        : minRoom,
                  ),
                  style: BoxStyle(
                    margin: EdgeInsets(bottom: last ? 0 : spacing),
                  ),
                ),
              );
            }
            _traverse(item);
          });
          _out.add(
            BlockBox(
              children,
              style: BoxStyle(
                margin: EdgeInsets(left: markerWidth),
                anchor:
                    item.id ??
                    (primary == null && coids.isNotEmpty
                        ? _calloutItem(coids.first)
                        : null),
              ),
            ),
          );
        }
      });
    });
    _out.add(
      BlockBox(
        items,
        style: BoxStyle(
          margin: EdgeInsets(
            top: marginTop,
            bottom: _marginBelow(node, fallback: 'prose'),
            // (`callout_list_indent`, modern engine.)
            left: _length('callout_list_indent', _font.size) ?? 0,
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// The body indent of the list being converted (Typst's lists), if any.
  double? _listBodyIndent;

  /// The widest marker of the list being converted.
  double _listMarkerWidth = 0;

  /// The width of the boxes the markers of the list being converted are
  /// set in, at their left, if fixed (`olist_marker_width`).
  double? _listMarkerBox;

  /// [content] with [marker] in [markerFont] beside its first line, right
  /// aligned in front of it, a space apart.
  CustomContent _withMarker(
    CustomContent content,
    String marker,
    _FontState markerFont, {
    Set<String> features = const {},
  }) {
    final gap = _fonts.font(_font.family, _font.style).widthOf('x', _font.size);
    final fixed = _listMarkerBox;
    final width =
        fixed ??
        _fonts
            .font(markerFont.family, markerFont.style)
            .widthOf(
              marker,
              markerFont.size,
              kerning: _font.kerning,
              features: {..._baseFeatures, ...features},
            );
    final markerBox = _textBox(
      marker.replaceAll('&', '&amp;').replaceAll('<', '&lt;'),
      markerFont,
      align: fixed == null ? 'right' : 'left',
      normalize: false,
      characterSpacing: fixed == null ? -0.5 : 0,
      features: features,
    );
    if (_listBodyIndent case final bodyIndent?) {
      _listMarkerWidth = math.max(_listMarkerWidth, width);
      return _Marked(content, markerBox, width, -width - bodyIndent);
    }
    return _Marked(content, markerBox, width, -width - gap + 0.5);
  }

  /// Converts the question and answer list [node].
  void _qanda(ListBlock node) {
    final boxes = _collect(() {
      if (node.hasTitle) _caption(node, category: 'list', labeled: false);
      final align = _alignOf(node.roles) ?? _s('list_text_align');
      final termSpacing = (_n('description_list_term_spacing') ?? 0).toDouble();
      final metrics = _lineMetrics(_font);
      final minRoom =
          _font.lineHeight * _font.size + metrics.leading + metrics.paddingTop;
      final markerFont = _font.copyWith(
        color: _c('list_marker_font_color') ?? _font.color,
      );
      for (final (i, DlistEntry(:terms, description: desc))
          in node.entries.indexed) {
        double? descMargin = 0;
        if (desc != null) {
          if (desc.isCompound) {
            descMargin = null;
          } else if (_nextEnclosedBlockDescending(desc) != null) {
            descMargin = (_n('list_item_spacing') ?? 0).toDouble();
          }
        }
        final children = _collect(() {
          for (final (t, term) in terms.indexed) {
            CustomContent box = _textBox(
              '<em>${term.text ?? ''}</em>',
              _font,
              align: align ?? _baseTextAlign,
              normalizeLineHeight: true,
            );
            if (t == 0) {
              box = _MinRoom(
                _withMarker(box, '${i + 1}.', markerFont),
                minRoom,
              );
            }
            _out.add(
              CustomBox(
                box,
                style: BoxStyle(margin: EdgeInsets(bottom: termSpacing)),
              ),
            );
          }
          if (desc == null) return;
          if (desc.text case final text? when desc.hasText) {
            _out.add(
              CustomBox(
                _textBox(
                  text,
                  _font,
                  align: align ?? _baseTextAlign,
                  normalizeLineHeight: true,
                  hyphenate: true,
                ),
                style: BoxStyle(
                  margin: EdgeInsets(
                    bottom:
                        descMargin ??
                        (_n('prose_margin_bottom') ?? 0).toDouble(),
                  ),
                ),
              ),
            );
          }
          _traverse(desc);
        });
        _out.add(BlockBox(children));
      }
    });
    _out.add(
      BlockBox(
        boxes,
        style: BoxStyle(
          margin: EdgeInsets(
            left: (_n('list_indent') ?? 0).toDouble(),
            bottom: node.parent is ListItem
                ? 0
                : _marginBelow(node, fallback: 'prose'),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Converts the description list [node] as an unordered or ordered
  /// list of its terms (in bold) and descriptions.
  void _dlistAsList(ListBlock node, {required bool ordered}) {
    final parent = node.parent;
    if (parent is! AbstractBlock) return;
    final list = ListBlock(
      parent,
      ordered ? BlockContext.olist : BlockContext.ulist,
    );
    final stack = node.hasRole('stack');
    final stop = node.attr('subject-stop') ?? (stack ? null : ':');
    for (final DlistEntry(:terms, description: desc) in node.entries) {
      final subject = terms.first.text ?? '';
      final ListItem item;
      if (desc != null) {
        final punctuated = RegExp(r'[.!?;:]$').hasMatch(_plain(subject));
        final description = desc.hasText
            ? '${stack ? '<br>' : ' '}${desc.text ?? ''}'
            : '';
        item = ListItem(
          list,
          '<strong>$subject${punctuated ? '' : stop ?? ''}</strong>'
          '$description',
        )..subs = [];
        [...desc.blocks].forEach(item.append);
      } else {
        item = ListItem(list, '<strong>$subject</strong>')..subs = [];
      }
      list.append(item);
    }
    if (ordered) {
      _listNumerals.add(const _Numeral.decimal(1));
    } else {
      _listBullets.add('disc');
    }
    final boxes = _collect(() => _list(list));
    if (ordered) {
      _listNumerals.removeLast();
    } else {
      _listBullets.removeLast();
    }
    _out.add(BlockBox(boxes, style: BoxStyle(anchor: node.id)));
  }

  /// The next block, descending into [item] first when it has blocks (the
  /// gem's `next_enclosed_block descend: true`).
  AbstractBlock? _nextEnclosedBlockDescending(ListItem item) =>
      item.blocks.isNotEmpty ? item.blocks.first : _nextEnclosedBlock(item);

  // Text.

  /// A text box of [markup] in [font] (the gem's `typeset_text` with the
  /// line metrics of the font's line height).
  TextBox _textBox(
    String markup,
    _FontState font, {
    required String align,
    double indent = 0,
    Set<String> inheritedStyles = const {},
    Fragment? inherit,
    bool normalize = true,
    bool normalizeLineHeight = false,
    double characterSpacing = 0,
    bool cell = false,
    bool inlineFormat = true,
    bool gaps = true,
    bool singleLine = false,
    bool shrinkToFit = false,
    int orphans = 1,
    int widows = 1,
    double? wrapIndent,
    bool wrapMarker = false,
    bool hyphenate = false,
    Set<String> features = const {},
    double? skew,
  }) {
    var text = hyphenate ? _hyphenated(markup, align) : markup;
    if (normalize) text = text.replaceAll(RegExp('[ \t\n]+'), ' ');
    // The modern engine: variation selectors take no room (they choose a
    // glyph's form, which the fonts here don't vary).
    text = text.replaceAll(RegExp('[\ufe00-\ufe0f]'), '');

    if (_cjkLineBreaks && !cell) text = _breakCjk(text);
    if (text.contains('://')) {
      text = _breakUrls(text, markup: inlineFormat);
    }
    // (Prose: preformatted text, set as it is, keeps its lines.)
    if (normalize && text.contains('/')) {
      text = _breakAfterSlashes(text, markup: inlineFormat);
    }
    final nodes = inlineFormat ? parseMarkup(text) : [MarkupText(text)];
    final List<Fragment> fragments;
    final inherited = inheritedStyles.isEmpty && inherit == null
        ? null
        : ((inherit?.copy() ?? Fragment(''))
            ..styles = {
              ...?inherit?.styles,
              for (final style in inheritedStyles)
                if (style == 'bold')
                  FragmentStyle.bold
                else
                  FragmentStyle.italic,
            });
    if (nodes == null) {
      logger.error(
        'failed to parse formatted text: ${text.replaceAll('­', '')}',
      );
      fragments = [inherited?.copy(text: text) ?? Fragment(text)];
    } else {
      fragments = _markup.apply(nodes, null, inherited);
    }
    final metrics = _lineMetrics(font);
    return TextBox(
      fragments,
      TextState(
        family: font.family,
        style: font.style,
        size: font.size,
        color: font.color,
        kerning: font.kerning,
        characterSpacing: characterSpacing,
        features: {..._baseFeatures, ...features},
      ),
      TextLayout(
        align: align,
        leading: metrics.leading,
        initialGap: cell || !gaps ? 0 : metrics.paddingTop,
        paddingBottom: cell || !gaps ? 0 : metrics.paddingBottom,
        trailingLineGap: cell,
        singleLine: singleLine,
        shrinkToFit: shrinkToFit,
        indentFirstLine: indent,
        normalizeLineHeight: normalizeLineHeight,
        orphans: orphans,
        widows: widows,
        wrapIndent: wrapIndent,
        wrapMarker: wrapMarker,
        at: _at,
        skew: skew,
        overhang: _overhangAmount(),
        capLines: _typstLeading(font) != null,
        justifyWidest:
            _choice('base_justify_width', const ['room', 'widest']) == 'widest',
        alignLast: _choice('base_text_align_last', const [
          'left',
          'center',
          'right',
        ]),
      ),
      _text,
    );
  }

  /// The value of theme key [key] when it is one of [values] (the keys
  /// with a set of values); another value is reported once and read as
  /// unset.
  String? _choice(String key, List<String> values) {
    final value = _s(key);
    if (value == null) return value;
    if (values.contains(value)) return value;
    if (_reportedChoices.add(key)) {
      logger.warn(
        'theme key $key: unknown value $value; expected one of '
        '${values.join(', ')}',
      );
    }
    return null;
  }

  final Set<String> _reportedChoices = {};

  static const _alignsV = ['top', 'middle', 'center', 'bottom'];

  /// The theme's `image_placement`.
  String? get _imagePlacement => _choice('image_placement', const [
    'here',
    'auto',
    'top',
    'bottom',
    'next',
  ]);

  /// How far punctuation hangs into the margin (`base_overhang`): `true`
  /// is 1 (the fractions of each character's width `_overhang` names),
  /// `false` 0, a number scales them.
  double _overhangAmount() => switch (_theme.value('base_overhang')) {
    ThemeBool(:final value) => value ? 1 : 0,
    ThemeNumber(:final value) => math.max(0, value.toDouble()),
    ThemeString(value: 'true') => 1,
    _ => 0,
  };

  /// Where the block being converted starts in the source (with the
  /// sourcemap the PDF backend turns on), for the modern engine's
  /// messages.
  Cursor? _at;

  /// Hyphenates words (soft hyphens where they may break), or null.
  PatternHyphenator? _hyphenator;

  /// Whether every text that may be hyphenated is (the `hyphens`
  /// attribute or the theme's `base_hyphens`), rather than justified text
  /// alone (the modern engine's default).
  bool _hyphenateAll = false;

  /// Sets the hyphenation of [document]: as the gem does when the
  /// `hyphens` attribute (a language, or empty for the document's `lang`)
  /// or, when the attribute is unspecified, the theme's `base_hyphens`
  /// asks for it; in the modern engine, of justified text in the
  /// document's language otherwise, unless `hyphens` is unset.
  void _resolveHyphenation(Document document) {
    _hyphenator = null;
    _hyphenateAll = false;
    final unspecified = document.attributeUnspecified('hyphens');
    var asked = document.attr('hyphens');
    if (asked == null && unspecified) {
      // `base_hyphens: false`: no hyphenation, not even of justified text.
      if (_theme.value('base_hyphens') case ThemeBool(value: false)) return;
      asked = switch (_theme.value('base_hyphens')) {
        ThemeString(:final value) => value,
        ThemeBool(:final value) when value => '',
        _ => null,
      };
    }
    final explicit = asked != null;
    if (!explicit && (!unspecified)) return;
    var language = asked ?? '';
    if (language.isEmpty) language = document.attr('lang') ?? '';
    if (language.isEmpty || language == 'en') language = 'en_us';
    final hyphenator = hyphenatorFor(language);
    if (hyphenator == null) {
      if (explicit) {
        logger.warn('no hyphenation patterns for $language; not hyphenating');
      }
      return;
    }
    _hyphenator = hyphenator;
    _hyphenateAll = explicit;
  }

  /// [markup] with soft hyphens where its words may break, when text set
  /// with [align] is hyphenated (the gem's `hyphenate_text`; the modern
  /// engine leaves code spans whole).
  String _hyphenated(String markup, String align) {
    final hyphenator = _hyphenator;
    if (hyphenator == null || (!_hyphenateAll && align != 'justify')) {
      return markup;
    }
    return hyphenateMarkup(
      markup,
      hyphenator,
      skipCode: true,
      lettersOnly: true,
    );
  }

  /// Whether a line may break before any CJK character (the document's
  /// `scripts` is `cjk`).
  bool _cjkLineBreaks = false;

  /// [text] with a zero width space before each CJK character.
  static String _breakCjk(String text) => text.replaceAllMapped(
    RegExp(
      r'(?=[\u3000\u30a0-\u30ff\u3040-\u309f\p{Script=Han}\uff00-\uffef])',
      unicode: true,
    ),
    (_) => '\u200b',
  );

  /// The underline or strike-through of theme [category] (of heading
  /// [level], when given, before the category's), as a fragment to inherit
  /// from; null when it has none (the gem's `apply_text_decoration`).
  Fragment? _decoration(String category, [int? level]) {
    String key(String name) =>
        level != null && _theme.value('${category}_h${level}_$name') != null
        ? '${category}_h${level}_$name'
        : '${category}_$name';
    final style = switch (_s(key('text_decoration'))) {
      'underline' => FragmentStyle.underline,
      'line-through' => FragmentStyle.strikethrough,
      _ => null,
    };
    if (style == null) return null;
    return Fragment('')
      ..styles = {style}
      ..textDecorationColor = _c(key('text_decoration_color'))
      ..textDecorationWidth = _n(key('text_decoration_width'));
  }

  /// The Typst leading of [font]'s text (`<category>_leading`, else
  /// `base_leading`), in the modern engine.
  double? _typstLeading(_FontState font) =>
      _length(font.leadingKey ?? 'base_leading', font.size);

  /// The gem's `calc_line_metrics`: the leading of the line height, half
  /// of it above the text (plus the font's line gap) and half below.
  ({double leading, double paddingTop, double paddingBottom}) _lineMetrics(
    _FontState font,
  ) {
    final prawnFont = _fonts.font(font.family, font.style);
    // The modern engine with `base_leading`: Typst's model. Each line's box
    // runs from its cap height to its baseline, the leading between boxes;
    // a text's first line has its cap height at the top, its last line
    // ends at its baseline (the space between blocks from baseline to cap
    // height).
    if (_typstLeading(font) case final typst?) {
      // The text box sets the lines on their cap heights (capLines).
      return (leading: typst, paddingTop: 0.0, paddingBottom: 0.0);
    }

    final leading = font.lineHeight * font.size - font.size;
    return (
      leading: leading,
      paddingTop: leading / 2 + prawnFont.lineGapAt(font.size),
      paddingBottom: leading / 2,
    );
  }

  // Running content.

  /// The pages before the running content starts, and before the page
  /// numbers start (the gem's `num_front_matter_pages`).
  (int, int) _skip = (0, 0);

  /// The page the body starts on (1-based).
  int _bodyStart = 1;

  /// The pages of the table of contents (1-based, inclusive), if any.
  (int, int)? _tocPages;

  /// The label of page [number]: its number after the front matter, else
  /// its number in lower-case roman numerals.
  String _pageLabel(int number) {
    final virtual = number - _skip.$2;
    return virtual < 1 ? _roman(number).toLowerCase() : '$virtual';
  }

  List<LayoutBox> _header(PageInfo page) => _running('header', page);

  List<LayoutBox> _footer(PageInfo page) => _running('footer', page);

  /// The four sides of the margin theme value [value], `inherit` taking
  /// [inherit]'s values on the left and right (the gem's
  /// `expand_margin_value`).
  List<double> _trimValues(ThemeValue? value, List<double> inherit) {
    const inherited = [
      ThemeNumber(0),
      ThemeString('inherit'),
      ThemeNumber(0),
      ThemeString('inherit'),
    ];
    final raw = switch (value) {
      ThemeList(:final values) => values,
      null => inherited,
      final one => [one],
    };
    final four = switch (raw.length) {
      1 => [raw[0], raw[0], raw[0], raw[0]],
      2 => [raw[0], raw[1], raw[0], raw[1]],
      3 => [raw[0], raw[1], raw[2], raw[1]],
      _ => raw.sublist(0, 4),
    };
    return [
      for (final (i, v) in four.indexed)
        if (i.isOdd && v is ThemeString && v.value == 'inherit')
          inherit[i]
        else
          _toPoints(v),
    ];
  }

  /// The header or footer ([periphery]) of [page] (the gem's
  /// `ink_running_content`), drawn where the gem draws it.
  List<LayoutBox> _running(String periphery, PageInfo page) {
    final doc = _document;
    if (periphery == 'header' ? doc.noheader : doc.nofooter) return const [];
    final height = (_n('${periphery}_height') ?? 0).toDouble();
    if (height == 0) return const [];
    if (page.count < _bodyStart) return const [];
    final number = page.number;
    if (number <= _skip.$1) return const [];
    if (_backCover && number == page.count) return const [];
    // The modern engine leaves blank pages (before a recto start, say)
    // blank, unless running_content_on_blank_pages is true.
    if (page.isEmpty &&
        _theme.value('running_content_on_blank_pages') !=
            const ThemeBool(true)) {
      return const [];
    }
    if (_tocPages case (final first, final last)
        when number >= first &&
            number <= last &&
            (periphery == 'header' ? _tocNoHeader : _tocNoFooter)) {
      return const [];
    }
    // A page that opens a part or chapter, unless the theme says
    // otherwise; the pages of a part or chapter with the `noheader` or
    // `nofooter` option (as the gem reads it on the toc macro).
    if (_openerPages.contains(number) &&
        _theme.value('running_content_on_openers') != const ThemeBool(true)) {
      return const [];
    }
    if (_pageSection(page)?.hasOption('no$periphery') ?? false) {
      return const [];
    }

    final virtual = number - _skip.$2;
    final label = _pageLabel(number);
    final side = _sideOf(_folio.physical ? number : virtual);
    final pageWidth = page.template.size.width;
    final pageHeight = page.template.size.height;
    final margins = page.template.margins;
    final pageMargin = [
      margins.top,
      margins.right,
      margins.bottom,
      margins.left,
    ];
    final trimMargin = _trimValues(
      _theme.value('${periphery}_${side}_margin') ??
          _theme.value('${periphery}_margin'),
      pageMargin,
    );
    final contentMargin = _trimValues(
      _theme.value('${periphery}_${side}_content_margin') ??
          _theme.value('${periphery}_content_margin'),
      [for (var i = 0; i < 4; i++) pageMargin[i] - trimMargin[i]],
    );
    final paddingValue =
        _theme.value('${periphery}_${side}_padding') ??
        _theme.value('${periphery}_padding');
    final padding = paddingValue == null
        ? contentMargin
        : [
            for (final (i, v) in _edgeValues(paddingValue).indexed)
              v + contentMargin[i],
          ];
    final baseFont = _themeFont(periphery, _font);
    final metrics = _lineMetrics(baseFont);
    final borderWidth = (_n('${periphery}_border_width') ?? 0).toDouble();
    final top = periphery == 'header'
        ? pageHeight - trimMargin[0]
        : height + trimMargin[2];
    final left = trimMargin[3];
    final width = pageWidth - left - trimMargin[1];
    final contentLeft = left + padding[3];
    final contentWidth = width - padding[1] - padding[3];
    final contentHeight = height - padding[0] - padding[2] - borderWidth * 0.5;
    final proseHeight =
        contentHeight - metrics.paddingTop - metrics.paddingBottom;
    final contentOffset = periphery == 'footer' ? borderWidth * 0.5 : 0.0;
    var valign = _s('${periphery}_vertical_align') ?? 'middle';
    if (valign == 'middle') valign = 'center';

    // The columns: their alignment, width and left edge.
    final columns = <String, (String, double, double)>{};
    final spec =
        _theme.value('${periphery}_${side}_columns') ??
        _theme.value('${periphery}_columns');
    if (spec != null) {
      final parts = spec.rubyString.replaceAll(',', ' ').split(RegExp(r'\s+'))
        ..removeWhere((p) => p.isEmpty);
      final specs = switch (parts.length) {
        0 ||
        1 => {'left': '0', 'center': parts.firstOrNull ?? '100', 'right': '0'},
        2 => {'left': parts[0], 'center': '0', 'right': parts[1]},
        _ => {'left': parts[0], 'center': parts[1], 'right': parts[2]},
      };
      var total = 0.0;
      final relative = <String, (String, double)>{};
      for (final MapEntry(key: position, :value) in specs.entries) {
        final first = value.isEmpty ? '' : value[0];
        final (align, amount) = int.tryParse(first) != null
            ? ('left', _toF(value))
            : (
                switch (first) {
                  '=' => 'center',
                  '>' => 'right',
                  _ => 'left',
                },
                _toF(value.substring(1)),
              );
        total += amount;
        relative[position] = (align, amount);
      }
      final widths = {
        for (final MapEntry(key: position, value: (align, amount))
            in relative.entries)
          position: (align, total == 0 ? 0.0 : amount / total * contentWidth),
      };
      final leftWidth = widths['left']!.$2;
      final centerWidth = widths['center']!.$2;
      columns['left'] = (widths['left']!.$1, leftWidth, 0);
      columns['center'] = (widths['center']!.$1, centerWidth, leftWidth);
      columns['right'] = (
        widths['right']!.$1,
        widths['right']!.$2,
        leftWidth + centerWidth,
      );
    } else {
      for (final position in const ['left', 'center', 'right']) {
        columns[position] = (position, contentWidth, 0);
      }
    }

    // The attributes the content refers to.
    final attributes = _runningAttributes(periphery, page, label);
    final pieces = <void Function(PdfPage page)>[];
    final background = _color(_c('${periphery}_background_color'));
    final borderColor = borderWidth > 0
        ? pdfColorOf(_c('${periphery}_border_color') ?? _c('base_border_color'))
        : null;
    if (background != null || (borderWidth > 0 && borderColor != null)) {
      pieces.add((pdfPage) {
        final canvas = pdfPage.canvas;
        if (background != null) {
          canvas
            ..save()
            ..setFillColor(background)
            ..rect(PdfRect(left, top - height, width, height))
            ..fill()
            ..restore();
        }
        if (borderWidth > 0 && borderColor != null) {
          _horizontalRule(
            canvas,
            borderColor,
            left,
            left + width,
            periphery == 'header' ? top - height : top,
            borderWidth,
            _s('${periphery}_border_style'),
          );
        }
      });
    }
    // The background image, in the middle of the running content's area.
    if (_runningBackgrounds.putIfAbsent(
          periphery,
          () => _resolveBackgroundImage('${periphery}_background_image')?.image,
        )
        case final image?) {
      pieces.add((pdfPage) {
        final canvas = pdfPage.canvas
          ..save()
          ..translate(left, top - height);
        _drawPageImage(canvas, image, size: (width, height));
        canvas.restore();
      });
    }
    // Rules between columns, a spacing apart (the gem leaves the spacing
    // out of each column after the first, and half of it out of the
    // first).
    final ruleWidth = (_n('${periphery}_column_rule_width') ?? 0).toDouble();
    final ruleColor = ruleWidth > 0
        ? pdfColorOf(_c('${periphery}_column_rule_color'))
        : null;
    final ruleSpacing = (_n('${periphery}_column_rule_spacing') ?? 0)
        .toDouble();
    final ruleStyle = _s('${periphery}_column_rule_style');
    String? previous;
    for (final position in const ['left', 'center', 'right']) {
      var template = _s('${periphery}_${side}_${position}_content');
      if (template == null || template.isEmpty) continue;
      var (align, columnWidth, x) = columns[position]!;
      if (columnWidth <= 0) continue;
      if (ruleColor != null && columnWidth < contentWidth) {
        if (previous != null) {
          final ruleX = contentLeft + x;
          final ruleTop = top - padding[0] - contentOffset;
          pieces.add(
            (pdfPage) => _verticalRule(
              pdfPage.canvas,
              ruleColor,
              ruleX,
              ruleTop,
              ruleTop - contentHeight,
              ruleWidth,
              ruleStyle,
            ),
          );
          x += ruleSpacing * 0.5;
          columnWidth -= ruleSpacing;
        } else {
          columnWidth -= ruleSpacing * 0.5;
        }
      }
      previous = position;
      if (_imageMacroOf(template, const ['alt', 'width'])
          case (final rawTarget, final attrs)?) {
        final target = _applySubsDiscretely(
          rawTarget,
          const {},
          subs: const [Sub.attributes],
        );
        final format = attrs['format'] ?? _imageFormat(target);
        final bytes = _themeImageBytes(target);
        final graphic = bytes == null
            ? null
            : _graphicOf(bytes, format, path: _lastImagePath).$1;
        if (graphic != null) {
          final boxLeft = contentLeft + x;
          final boxTop = top - padding[0] - contentOffset;
          final imageValign = switch (_s('${periphery}_image_vertical_align')) {
            null => valign,
            'middle' => 'center',
            final other => other,
          };
          pieces.add(
            (pdfPage) => _runningImage(
              pdfPage,
              graphic,
              attrs,
              PdfRect(
                boxLeft,
                boxTop - contentHeight,
                columnWidth,
                contentHeight,
              ),
              align,
              imageValign,
            ),
          );
          continue;
        }
        // Not readable: the macro's text reports it and shows the alt text.
        final attrlist = template.substring(
          template.indexOf('[') + 1,
          template.length - 1,
        );
        template = 'image:$target[$attrlist]';
      }
      final font = _themeFont('${periphery}_${side}_$position', baseFont);
      String? content;
      if (template == '{page-number}') {
        content = doc.hasAttr('pagenums') ? label : null;
      } else {
        // A Mustache template (ADR-0010; optional parts) first, then the
        // gem's attribute references.
        content = _applySubsDiscretely(
          template.contains('{{') ? _render(template, attributes) : template,
          attributes,
          unset: const {
            'part-numeral',
            'chapter-numeral',
          }.difference(attributes.keys.toSet()),
          dropLines: true,
        );
        if (font.transform case final transform? when transform != 'none') {
          content = transformText(content, transform);
        }
      }
      if (content == null || content.isEmpty) continue;
      final prawnFont = _fonts.font(font.family, font.style);
      final box = _textBox(
        content,
        font.copyWith(lineHeight: baseFont.lineHeight),
        align: align,
        gaps: false,
      );
      var y = top - padding[0] - contentOffset;
      if (valign == 'center') y -= prawnFont.descenderAt(font.size) * 0.5;
      final placed = box.place(columnWidth, proseHeight, atTop: true);
      if (placed == null) continue;
      final shift = switch (valign) {
        'center' =>
          (proseHeight - placed.height - prawnFont.descenderAt(font.size)) *
              0.5,
        'bottom' => proseHeight - placed.height,
        _ => 0.0,
      };
      pieces.add(
        (pdfPage) => placed.paint(pdfPage, contentLeft + x, y - shift),
      );
    }
    if (pieces.isEmpty) return const [];
    return [
      CustomBox(
        _Absolute((pdfPage) {
          for (final piece in pieces) {
            piece(pdfPage);
          }
        }),
      ),
    ];
  }

  /// Draws the running content image [graphic] in [box] (its width from
  /// [attrs], else fit to the box), aligned (the gem's image in
  /// `ink_running_content`).
  void _runningImage(
    PdfPage page,
    Graphic graphic,
    Map<String, String> attrs,
    PdfRect box,
    String align,
    String valign,
  ) {
    final width = _imageWidthOf(
      (name) => attrs[name],
      fallback: false,
    ).resolve(box.width, _pageSize(_document).$1);
    final (naturalWidth, naturalHeight) = switch (graphic) {
      final SvgImage svg => prawnSvgSize(
        svg,
        null,
        null,
        box.width,
        box.height,
      ),
      final other => (other.intrinsicWidth, other.intrinsicHeight),
    };
    final ratio = naturalHeight / naturalWidth;
    double w;
    double h;
    if (width != null) {
      (w, h) = (width, width * ratio);
    } else if (naturalWidth / naturalHeight > box.width / box.height) {
      (w, h) = (box.width, box.width * ratio);
    } else {
      (w, h) = (box.height / ratio, box.height);
    }
    final left = switch (align) {
      'center' => box.left + (box.width - w) / 2,
      'right' => box.right - w,
      _ => box.left,
    };
    final top = switch (valign) {
      'center' => box.top - (box.height - h) / 2,
      'bottom' => box.bottom + h,
      _ => box.top,
    };
    final rect = PdfRect(left, top - h, w, h);
    final canvas = page.canvas;
    switch (graphic) {
      case final PdfImage image:
        canvas.image(image, rect);
      case final other:
        canvas.save();
        other.paint(canvas, rect);
        canvas.restore();
    }
    if (attrs['link'] case final link?) {
      page.link(
        rect,
        link.startsWith('#')
            ? LinkTarget.named(destinationName(link.substring(1)))
            : LinkTarget.uri(link),
      );
    }
  }

  static PdfColor? _color(ThemeColor? value) =>
      value is TransparentColor ? null : pdfColorOf(value);

  /// The part or chapter [page] is in (a chapter before the part it is
  /// in), if any.
  Section? _pageSection(PageInfo page) {
    Section? at(String? mark) {
      final index = int.tryParse(mark ?? '');
      return index == null || index >= _sections.length
          ? null
          : _sections[index].$1;
    }

    final part = int.tryParse(page.mark('part') ?? '') ?? -1;
    final chapter = int.tryParse(page.mark('chapter') ?? '') ?? -1;
    return chapter > part ? at(page.mark('chapter')) : at(page.mark('part'));
  }

  /// The attributes the running content of [page] refers to: the
  /// document's, with the page number, the page count and the titles of
  /// the part, chapter and section the page is in.
  Map<String, String> _runningAttributes(
    String periphery,
    PageInfo page,
    String label,
  ) {
    final doc = _document;
    final book = doc.doctype == 'book';
    final attributes = <String, String>{};
    final title = doc.hasHeader
        ? doc.partitionedTitle(separator: doc.attr('title-separator'))
        : DocumentTitle(
            doc.attr('untitled-label') ?? '',
            separator: doc.attr('title-separator'),
          );
    if (title != null) {
      attributes['doctitle'] = title.combined;
      attributes['document-title'] = title.main;
      if (title.subtitle case final subtitle?) {
        attributes['document-subtitle'] = subtitle;
      }
    }
    attributes['page-count'] = '${page.count - _skip.$2}';
    if (doc.hasAttr('pagenums')) attributes['page-number'] = label;
    // `<periphery>_title_style`: `document` (the default) as headings are
    // titled, `toc` as the contents list them, `basic` without numbers.
    final titleStyle = _s('${periphery}_title_style');
    String titleOf(String? mark) {
      final index = int.tryParse(mark ?? '');
      if (index == null || index >= _sections.length) return '';
      final section = _sections[index].$1;
      return switch (titleStyle) {
        'basic' => section.title ?? '',
        'toc' => _numberedTitle(section, formal: false),
        _ => _numberedTitle(section),
      };
    }

    // The numeral of a numbered part or chapter (none for a preface, the
    // table of contents, an unnumbered section).
    String? numeralOf(String? mark) {
      final index = int.tryParse(mark ?? '');
      if (index == null || index >= _sections.length) return null;
      return _sections[index].$1.numeral;
    }

    final sectlevels = (_n('${periphery}_sectlevels') ?? 2).toInt();
    final partMark = page.mark('part');
    var chapterMark = page.mark('chapter');
    var sectionMark = page.mark('section-$sectlevels');
    // A part ends the chapter before it, and a part or a chapter the
    // section before it.
    final partIndex = int.tryParse(partMark ?? '') ?? -1;
    final chapterIndex = int.tryParse(chapterMark ?? '') ?? -1;
    final sectionIndex = int.tryParse(sectionMark ?? '') ?? -1;
    final partStarted = partMark != null && partMark.isNotEmpty;
    if (partStarted && chapterIndex < partIndex) chapterMark = null;
    if (sectionIndex < math.max(partStarted ? partIndex : -1, chapterIndex)) {
      sectionMark = null;
    }
    final part = titleOf(partMark);
    String chapter;
    String? chapterNumeral;
    String section;
    final toc = _tocPages;
    if (toc != null && page.number >= toc.$1 && page.number <= toc.$2) {
      final tocTitle = doc.attr('toc-title') ?? '';
      if (book) {
        chapter = tocTitle;
        section = '';
      } else {
        chapter = '';
        section = sectionMark == null ? tocTitle : titleOf(sectionMark);
      }
    } else if (book && chapterMark == null && !partStarted) {
      chapter = page.number < _bodyStart
          ? doc.doctitle() ?? ''
          : doc.attr('preface-title') ??
                (doc.attributes.containsKey('preface-title') ? '' : 'Preface');
      section = titleOf(sectionMark);
    } else {
      chapter = titleOf(chapterMark);
      chapterNumeral = numeralOf(chapterMark);
      section = titleOf(sectionMark);
    }
    attributes['part-title'] = part;
    if (numeralOf(partMark) case final numeral?) {
      attributes['part-numeral'] = numeral;
    }
    attributes['chapter-title'] = chapter;
    if (chapterNumeral case final numeral?) {
      attributes['chapter-numeral'] = numeral;
    }
    attributes['section-title'] = section;
    attributes['section-or-chapter-title'] = section.isNotEmpty
        ? section
        : chapter;
    // As Typst's headers see it, at the page's top: the last part or
    // chapter that started before the page, else the document's title.
    // (A section without a shown title, a dedication, has no heading.)
    int shown(String? mark) => switch (int.tryParse(mark ?? '')) {
      final index?
          when index < _sections.length &&
              !_sections[index].$1.hasOption('notitle') =>
        index,
      _ => -1,
    };
    final topPart = shown(page.topMark('part'));
    final topChapter = shown(page.topMark('chapter'));
    if (topChapter > topPart) {
      attributes['top-title'] = titleOf('$topChapter');
      if (numeralOf('$topChapter') case final numeral?) {
        attributes['top-numeral'] = numeral;
      }
    } else if (topPart >= 0) {
      attributes['top-title'] = titleOf('$topPart');
    } else {
      attributes['top-title'] = doc.doctitle() ?? '';
    }
    return attributes;
  }

  static final RegExp _attributeReference = RegExp(
    r'(?<!\\)\{(\w+(?:-\w+)*)\}',
  );

  /// [value] with the document's normal substitutions (or [subs]), with
  /// [attributes] set, those of [unset] removed and missing attributes
  /// skipped; with [dropLines], each line with a reference that didn't
  /// resolve is dropped (the gem's `apply_subs_discretely`).
  String _applySubsDiscretely(
    String value,
    Map<String, String> attributes, {
    Set<String> unset = const {},
    List<Sub>? subs,
    bool dropLines = false,
  }) {
    final doc = _document;
    final docAttributes = doc.attributes;
    final saved = <String, String?>{
      for (final key in [...attributes.keys, ...unset, 'attribute-missing'])
        key: docAttributes[key],
    };
    unset.forEach(docAttributes.remove);
    docAttributes
      ..addAll(attributes)
      ..['attribute-missing'] = 'skip';
    final escaped = value.contains(r'\{');
    var text = escaped ? value.replaceAll(r'\{', r'\\\{') : value;
    final before = text;
    try {
      text = subs == null ? doc.applySubs(text) : doc.applySubs(text, subs);
    } finally {
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value == null) {
          docAttributes.remove(key);
        } else {
          docAttributes[key] = value;
        }
      }
    }
    if (dropLines && text.contains('{')) {
      text = text
          .split('\n')
          .where((line) {
            final match = _attributeReference.firstMatch(line);
            return match == null || !before.contains('{${match[1]}}');
          })
          .join('\n');
    }
    return escaped ? text.replaceAll(r'\{', '{') : text;
  }

  // The outline.

  /// The outline (the document title, then the sections to
  /// `outlinelevels`) and the page labels (the gem's `add_outline`).
  void _outline(PdfDocument pdf, List<PdfPage> pages, LayoutResult result) {
    final frontMatter = _skip.$2;
    // The back cover is added after the labels (it continues the last).
    final labeled = _backCover ? pages.length - 1 : pages.length;
    for (var n = 0; n < labeled; n++) {
      pdf.labelPages(
        n,
        PageLabel(
          style: PageNumberStyle.none,
          prefix: n < frontMatter ? _roman(n + 1) : '${n - frontMatter + 1}',
        ),
      );
    }
    if (!_document.hasAttr('outline')) return;
    var levels = _tocLevels;
    var expand = levels;
    final setting = _document.attr('outlinelevels');
    if (setting != null) {
      if (setting.contains(':')) {
        final [count, open] = setting.split(':');
        levels = count.isEmpty ? levels : int.tryParse(count) ?? levels;
        expand = int.tryParse(open) ?? 0;
      } else {
        levels = expand = int.tryParse(setting) ?? levels;
      }
    }
    final anchors = {
      for (final (section, anchor) in _sections) section: anchor,
    };
    PdfDestination? destination(Section section) {
      final anchor = anchors[section];
      final position = anchor == null ? null : result.anchors[anchor];
      if (position == null) return null;
      return PdfDestination.xyz(pages[position.page], left: 0, top: position.y);
    }

    final titlePage = _frontCover ? 1 : 0;
    if (pages.length > titlePage) {
      // An outline title, or the document title for an empty one; none
      // when the attribute is unset.
      var title = _document.attr('outline-title');
      if (title != null && title.isEmpty) {
        title = _resolveDoctitle(_document) ?? '';
      }
      if (title != null && title.isNotEmpty) {
        final page = pages[titlePage];
        pdf.addOutline(
          _plain(title),
          LinkTarget.destination(
            PdfDestination.xyz(page, left: 0, top: page.height),
          ),
        );
      }
    }
    // The table of contents, as a section of its own (the gem's
    // `insert_toc_section`): first, or after the section its macro is in.
    final tocTitle = _document.attr('toc-title') ?? '';
    final tocNode = _document.attr('toc-placement') == 'macro'
        ? _document.findBy(context: BlockContext.toc).firstOrNull
        : null;
    final tocAfter = switch (tocNode?.parent) {
      final Section section => section,
      _ => null,
    };
    void addToc(PdfOutlineItem? parent) {
      final pages_ = _tocPages;
      if (pages_ == null ||
          tocTitle.isEmpty ||
          _sectionsOf(_document).isEmpty ||
          pages_.$1 > pages.length) {
        return;
      }
      final anchor = tocNode == null
          ? null
          : result.anchors[tocNode.id ?? 'toc'];
      final PdfDestination destination;
      if (anchor != null) {
        destination = PdfDestination.xyz(
          pages[anchor.page],
          left: 0,
          top: anchor.y,
        );
      } else {
        final page = pages[pages_.$1 - 1];
        destination = PdfDestination.xyz(page, left: 0, top: page.height);
      }
      final target = LinkTarget.destination(destination);
      if (parent == null) {
        pdf.addOutline(_plain(tocTitle), target);
      } else {
        parent.add(_plain(tocTitle), target);
      }
    }

    void level(
      List<Section> sections,
      int levels,
      int expand,
      PdfOutlineItem? parent,
    ) {
      for (final section in sections) {
        final sectionLevels =
            int.tryParse(section.attr('outlinelevels') ?? '') ?? levels;
        final depth = section.level ?? 1;
        if (sectionLevels < depth) continue;
        if (section.hasOption('notitle') &&
            section == _document.blocks.lastOrNull &&
            section.blocks.isEmpty) {
          continue;
        }
        final title = _plain(_numberedTitle(section));
        if (title.isEmpty) continue;
        final target = switch (destination(section)) {
          final d? => LinkTarget.destination(d),
          null => null,
        };
        final children = _sectionsOf(section);
        final open = depth < sectionLevels && children.isNotEmpty;
        final item = parent == null
            ? pdf.addOutline(title, target, open: open && expand >= 1)
            : parent.add(title, target, open: open && expand >= 1);
        if (open) level(children, sectionLevels, expand - 1, item);
        if (section == tocAfter) addToc(parent);
      }
    }

    if (tocAfter == null) addToc(null);
    level(_sectionsOf(_document), levels, expand, null);
  }

  static String _roman(int number) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const letters = [
      'm',
      'cm',
      'd',
      'cd',
      'c',
      'xc',
      'l',
      'xl',
      'x',
      'ix',
      'v',
      'iv',
      'i',
    ];
    final out = StringBuffer();
    var n = number;
    for (var i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        out.write(letters[i]);
        n -= values[i];
      }
    }
    return out.toString();
  }

  /// [markup] as plain text: tags dropped (with an image's alt text),
  /// character references resolved (unknown named ones as `?`), spaces
  /// trimmed and squeezed (the gem's `sanitize`).
  static String _plain(String markup) {
    var text = markup;
    if (text.contains('<')) text = text.replaceAll(RegExp('<[^>]+>\x00?'), '');
    if (text.contains('&')) {
      text = text.replaceAllMapped(
        RegExp(
          r'&(?:amp;)?(?:([a-z][a-z]+\d{0,2})|#(?:(\d\d\d{0,4})|x([0-9a-fA-F]{2,4})));',
        ),
        (m) {
          if (m[1] case final name?) {
            return switch (name) {
              'amp' => '&',
              'apos' => "'",
              'gt' => '>',
              'lt' => '<',
              'nbsp' => ' ',
              'quot' => '"',
              _ => '?',
            };
          }
          final code = m[2] != null
              ? int.parse(m[2]!)
              : int.parse(m[3]!, radix: 16);
          return String.fromCharCode(code);
        },
      );
    }
    return text.trim().replaceAll(RegExp(' {2,}'), ' ');
  }

  // Inline elements.

  @override
  String? convertInline(Inline node) {
    // Inline content may be converted while the document is parsed (a
    // section title, for its id), before the document is converted: the
    // theme is loaded then (the gem's `load_theme`).
    if (!_ready) {
      if (node.document case final Document doc) {
        _document = doc;
        _theme = _prepareTheme(_loadTheme(doc));
        _fonts = FontCatalog(_theme, shaping: _shaping, warn: logger.warn);
        _markup = MarkupTransform(
          theme: _theme,
          invertEmphasis: _invertEmphasis,
          keepIndexSpace: true,
        );
        _ready = true;
      }
    }
    return _convertInline(node);
  }

  /// Whether the theme (and the state inline conversions use) is loaded.
  bool _ready = false;

  /// Whether adjacent margins collapse to the larger, as in CSS (the
  /// modern engine, unless the theme's `block_margin_collapse` is false),
  /// rather than add, as asciidoctor-pdf's do.
  bool get _collapseMargins => switch (_theme.value('block_margin_collapse')) {
    ThemeBool(:final value) => value,
    ThemeString(value: 'false' || 'none') => false,
    _ => true,
  };

  /// Whether emphasis is set against its surroundings (upright in italic
  /// text): in the modern engine, unless the theme's
  /// `base_emphasis_inversion` is false.
  bool get _invertEmphasis => switch (_theme.value('base_emphasis_inversion')) {
    ThemeBool(:final value) => value,
    ThemeString(value: 'false' || 'none') => false,
    _ => true,
  };

  /// How text becomes glyphs: as OpenType shapes it (GPOS kerning, and
  /// the standard ligatures unless the theme's `base_font_ligatures` is
  /// `none`).
  Shaping get _shaping => _s('base_font_ligatures') == 'none'
      ? Shaping.opentype
      : Shaping.ligatures;

  /// Whether the document is being converted (rather than parsed: inline
  /// content converted for a title's id, which the gem converts before
  /// its PDF state exists).
  bool _converting = false;

  String? _convertInline(Inline node) => switch (node.context) {
    InlineContext.anchor => _inlineAnchor(node),
    InlineContext.lineBreak => '${node.text ?? ''}<br>',
    InlineContext.button =>
      '<button>${(_s('button_content') ?? '%s').replaceFirst('%s', node.text ?? '')}</button>',
    InlineContext.callout => _inlineCallout(node),
    InlineContext.footnote => _inlineFootnote(node),
    InlineContext.image => _inlineImage(node),
    InlineContext.indexterm => _inlineIndexterm(node),
    InlineContext.kbd => _inlineKbd(node),
    InlineContext.menu => _inlineMenu(node),
    InlineContext.quoted => _inlineQuoted(node),
  };

  String _inlineAnchor(Inline node) {
    final doc = _document;
    final target = node.target ?? '';
    switch (node.type) {
      case 'link':
        final anchor = node.id != null
            ? '<a id="${node.id}">$_dummyText</a>'
            : '';
        final role = node.role;
        final classAttr = role != null ? ' class="$role"' : '';
        final media = doc.attr('media') ?? 'screen';
        final text = node.text ?? '';
        var bare = target;
        if (media != 'screen' && target.startsWith('mailto:')) {
          bare = target.substring(7);
          if (bare == text) node.addRole('bare');
          if (!doc.hasAttr('hide-uri-scheme')) bare = target;
        }
        final roles = node.attr('role')?.split(' ') ?? const <String>[];
        if (roles.contains('bare')) {
          return '$anchor<a href="$target"$classAttr>'
              '$text</a>';
        }
        // `show-link-uri=footnote` (modern engine): the URI in a footnote,
        // as print books set it.
        if (doc.attr('show-link-uri') == 'footnote' && _pageFootnotes) {
          if (doc.hasAttr('hide-uri-scheme')) {
            final boundary = bare.indexOf('://');
            if (boundary >= 0) bare = bare.substring(boundary + 3);
          }
          final index = doc.counter('footnote-number');
          doc.registerFootnote(
            Footnote(index, null, '<a href="$target">$bare</a>'),
          );
          return '$anchor<a href="$target"$classAttr>$text</a>'
              '${_footnoteReference(index)}';
        }
        if (doc.hasAttr('show-link-uri') ||
            (media != 'screen' && doc.attributeUnspecified('show-link-uri'))) {
          if (doc.hasAttr('hide-uri-scheme')) {
            final boundary = bare.indexOf('://');
            if (boundary >= 0) bare = bare.substring(boundary + 3);
          }
          return '$anchor<a href="$target"$classAttr>$text</a> '
              '[<font size="0.85em">$bare</font>&#93;';
        }
        return '$anchor<a href="$target"$classAttr>$text</a>';
      case 'xref':
        if (node.attributes['path'] case final path?) {
          return '<a href="$target">${node.text ?? path}</a>';
        }
        if (node.attributes['refid'] case final refid?) {
          var text = node.text;
          String? anchor;
          if (text == null && !_resolvingXref) {
            _resolvingXref = true;
            try {
              final ref = doc.catalog.refs[refid];
              final style = node.attr('xrefstyle', null, 'xrefstyle');
              text = switch (ref) {
                final AbstractBlock block => block.xreftext(style),
                final Inline inline => inline.xreftext(style),
                _ => null,
              };
              if (text != null && text.contains('<a')) {
                text = text.replaceAll(RegExp(r'<(?:a\b[^>]*|/a)>'), '');
              }
              if (ref case final Inline inline
                  when inline.type == 'bibref' && _bibrefRefs.add(refid)) {
                anchor = '<a id="_bibref_ref_$refid">$_dummyText</a>';
              }
            } finally {
              _resolvingXref = false;
            }
          }
          return '${anchor ?? ''}<a anchor="$refid">${text ?? '[$refid]'}</a>'
              .replaceAll(']', '&#93;');
        }
        return '<a anchor="${doc.attr('pdf-anchor') ?? ''}">'
            '${node.text ?? '[^top&#93;'}</a>';
      case 'ref':
        return '<a id="${node.id}">$_dummyText</a>';
      case 'bibref':
        final id = node.id ?? '';
        var reftext = '[${node.reftext ?? id}]';
        if (_bibrefRefs.contains(id)) {
          reftext = '<a anchor="_bibref_ref_$id">$reftext</a>';
        }
        return '<a id="$id">$_dummyText</a>$reftext';
      default:
        logger.warn('unknown anchor type: ${node.type}');
        return '';
    }
  }

  /// Whether an xref's text is being resolved (an xref in a reference's
  /// own text then shows its refid).
  bool _resolvingXref = false;

  /// The bibliography entries referenced (they link back to the first
  /// reference).
  final Set<String> _bibrefRefs = {};

  /// [text] (markup when [markup]) with a zero-width space where each URL
  /// in it may break, as Typst breaks a link (typst-layout's
  /// `linebreak_link`): after its `://`, then where a run of letters or of
  /// digits begins, and between two other characters, but never after an
  /// opening bracket; a run of 16 characters or more anywhere in it. The
  /// modern engine's, in place of the gem's breaks after `/`, `?`, `&`
  /// and `#`.
  static String _breakUrls(String text, {bool markup = true}) {
    final out = StringBuffer();
    // The text between tags only (an href stays whole).
    final pieces = markup
        ? RegExp('<[^>]*>|[^<]+').allMatches(text).map((m) => m[0]!)
        : [text];
    for (final piece in pieces) {
      if (piece.startsWith('<') || !piece.contains('://')) {
        out.write(piece);
        continue;
      }
      out.write(
        piece.replaceAllMapped(_urlRx, (m) {
          final link = m[2]!;
          return '${m[1]}​${_linkBreaks(link)}';
        }),
      );
    }
    return out.toString();
  }

  /// [text] (markup when [markup]) with a zero-width space after each
  /// slash that isn't before a digit, a space or another slash: where the
  /// Unicode line breaking algorithm (UAX #14, a slash's class SY) lets a
  /// line break, as Typst breaks `and/or` and `/contacts/new`; and after
  /// each `?` and `!` before a letter or a digit (class EX, as Typst
  /// breaks `/contacts?rows_only`).
  static String _breakAfterSlashes(String text, {bool markup = true}) {
    final pieces = markup
        ? RegExp('<[^>]*>|[^<]+').allMatches(text).map((m) => m[0]!)
        : [text];
    return pieces
        .map(
          (piece) => piece.startsWith('<') && markup
              ? piece
              : piece
                    .replaceAll(RegExp(r'/(?=[^\s\d/\u200b])'), '/\u200b')
                    .replaceAllMapped(
                      RegExp(r'[?!](?=[\p{L}\p{N}])', unicode: true),
                      (m) => '${m[0]}\u200b',
                    ),
        )
        .join();
  }

  /// A URL's scheme and `://`, then its address (Typst's `link_prefix`:
  /// the characters a link takes, trailing punctuation left out).
  static final RegExp _urlRx = RegExp(
    '([a-zA-Z][a-zA-Z0-9+.-]*://)'
    r"((?:[0-9A-Za-z!#$%*+,\-./:;=?@_~'\[\]()]|&amp;)*"
    r'(?:[0-9A-Za-z#$%*+\-/=@_~\[\]()]|&amp;))',
  );

  /// [link] (the part after `://`) with a zero-width space at each of
  /// Typst's break opportunities.
  static String _linkBreaks(String link) {
    int classOf(String c) => RegExp(r'\p{L}', unicode: true).hasMatch(c)
        ? 0
        : RegExp(r'\p{N}', unicode: true).hasMatch(c)
        ? 1
        : c == '(' || c == '['
        ? 2
        : 3;
    // Entities count as one character.
    final chars = RegExp(
      '&amp;|.',
      dotAll: true,
    ).allMatches(link).map((m) => m[0]!).toList();
    final out = StringBuffer();
    var offset = 0;
    var previous = 3;
    for (var end = 0; end < chars.length; end++) {
      final c = chars[end];
      final current = classOf(c);
      if (end > 0 &&
          previous != 2 &&
          (current == 3 ? previous == 3 : current != previous)) {
        final piece = chars.sublist(offset, end);
        if (piece.join().replaceAll('&amp;', '&').length < 16) {
          out
            ..writeAll(piece)
            ..write('​');
        } else {
          for (final p in piece) {
            out
              ..write(p)
              ..write('​');
          }
        }
        offset = end;
      }
      previous = current;
    }
    out.writeAll(chars.sublist(offset));
    return out.toString();
  }

  String _inlineCallout(Inline node) {
    var glyph = _conumGlyph(int.tryParse(node.text ?? '') ?? 0);
    // A marker as text: in its own style and figures.
    if (_conumTemplate() != null) {
      glyph =
          '<span class="conum-text">${glyph.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</span>';
    }
    final family = _s('conum_font_family');
    // The modern engine leaves the marker out of copied code, and links
    // it to its callout list item (which links back).
    final shown = '<span class="artifact">$glyph</span>';
    var result = family == null || family == _font.family
        ? shown
        : '<font name="$family">$shown</font>';
    // The marker keeps its color as a link (the text's, when the theme
    // gives it none).
    final color =
        _theme.value('conum_font_color')?.rubyString ?? _font.color?.rubyString;
    if (color != null) result = '<font color="$color">$result</font>';
    final id = node.id;
    if (id != null && _document.callouts.explained.contains(id)) {
      result =
          '<a id="$id">$_dummyText</a>'
          '<a anchor="${_calloutItem(id)}">$result</a>';
    }
    return result;
  }

  /// The role of a table cell's text that is a single phrase with one
  /// (`<span class="paid">Paid</span>`), if any.
  static String? _cellRole(String text) {
    final m = RegExp(
      r'^<span class="([\w-]+)">((?:(?!</?span[ >]).)*)</span>$',
      dotAll: true,
    ).firstMatch(text);
    return m?[1];
  }

  /// The destination of the callout list item for the callout [id].
  static String _calloutItem(String id) => '$id-item';

  /// The images inline images refer to, by the `src` of their `<img>`.
  final Map<String, Graphic> _inlineGraphics = {};

  /// The inline image [node] as an `<img>` (the gem's
  /// `convert_inline_image`), or its alt text when it can't be read.
  String _inlineImage(Inline node) {
    final String image;
    if (node.type == 'icon') {
      image = _inlineIcon(node);
    } else {
      final target = node.target ?? '';
      final alt = node.attr('alt') ?? '';
      final data = _dataUri.firstMatch(target);
      final format = data != null
          ? switch (data[1]!) {
              'jpg' => 'jpeg',
              'svg+xml' => 'svg',
              final other => other,
            }
          : node.attr('format') ?? _imageFormat(target);
      List<int>? bytes;
      if (format == 'gif') {
        logger.warn('GIF image format not supported; convert $target to PNG');
      } else if (data != null) {
        try {
          bytes = base64.decode(data[2]!);
        } on FormatException {
          bytes = null;
        }
      } else {
        bytes = _imageBytes(node, target);
      }
      Graphic? graphic;
      String? problem;
      if (bytes != null) {
        (graphic, problem) = _graphicOf(
          bytes,
          format,
          path: data == null ? _lastImagePath : null,
        );
      }
      if (bytes == null) {
        image = '[$alt&#93;';
      } else {
        final src = target.replaceAll('"', '%22');
        if (graphic != null) _inlineGraphics[src] = graphic;
        if (problem != null) _imageProblems[src] = problem;
        final role = node.role;
        final classAttr = role == null ? '' : ' class="$role"';
        final fit = node.attr('fit');
        final fitAttr = fit == null ? '' : ' fit="$fit"';
        final intrinsic = graphic == null ? 0.0 : _intrinsicWidth(graphic);
        final width = _imageWidthOf(node.attr, fallback: false, vw: false);
        String widthValue;
        switch (width.kind) {
          // Converted while the document is parsed (a title, for its id),
          // the gem defers a scale to the arranger, which takes it as a
          // factor rather than a percentage.
          case _ImageWidthKind.scale when !_converting:
            widthValue = '${intrinsic * width.value * 100}';
          case _ImageWidthKind.scale:
            widthValue = '${intrinsic * width.value}';
          case _ImageWidthKind.percent:
            widthValue = '${_rubyFloat(width.value * 100)}%';
            if (node.parent?.context == BlockContext.tableCell) {
              widthValue += '$intrinsic';
            }
          case _ImageWidthKind.natural:
            widthValue = '$intrinsic';
          case _ImageWidthKind.points || _ImageWidthKind.viewport:
            widthValue = '${width.value}';
        }
        final escapedAlt = alt.replaceAll('"', '&quot;');
        image =
            '<img src="$src" format="$format" alt="$escapedAlt" '
            'width="$widthValue"$classAttr$fitAttr>';
      }
    }
    if (node.attr('link') case final link? when link.isNotEmpty) {
      return link.startsWith('#')
          ? '<a anchor="${link.substring(1)}">$image</a>'
          : '<a href="$link">$image</a>';
    }
    return image;
  }

  /// Why the inline images that couldn't be read couldn't, by `src`.
  final Map<String, String> _imageProblems = {};

  /// [value] as Ruby writes a float (`50.0`).
  static String _rubyFloat(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}.0' : '$value';

  /// The width of [graphic] as the gem measures it (pixels at 0.75pt, SVG
  /// by prawn-svg's sizing in the content area).
  double _intrinsicWidth(Graphic graphic) {
    if (graphic case final SvgImage svg) {
      final (width, height) = _pageSize(_document);
      final margins = _pageMargins(_document);
      return prawnSvgSize(
        svg,
        null,
        null,
        width - margins.horizontal,
        height - margins.vertical,
      ).$1;
    }
    return graphic.intrinsicWidth * 0.75;
  }

  /// The index of the document (terms in titles are stored while the
  /// document is parsed).
  final IndexCatalog _index = IndexCatalog();

  IndexName _indexName(String markup) => IndexName(_plain(markup), markup);

  /// The index term [node]: an anchor where it's used (and its text, if
  /// visible), the term stored in the index (the gem's
  /// `convert_inline_indexterm`).
  String _inlineIndexterm(Inline node) {
    final visible = node.type == 'visible';
    final name = _index.nextAnchor();
    final anchor =
        '<a id="$name" type="indexterm"${visible ? ' visible="true"' : ''}>'
        '$_dummyText</a>';
    final see = switch (node.attr('see')) {
      final value? => _indexName(value),
      null => null,
    };
    final seeAlso = [
      for (final term in node.seeAlso ?? const <String>[]) _indexName(term),
    ];
    final names = visible
        ? [_indexName(node.text ?? '')]
        : [for (final term in node.terms ?? const <String>[]) _indexName(term)];
    _index.store(names, name, see: see, seeAlso: seeAlso);
    return visible ? '$anchor${node.text ?? ''}' : anchor;
  }

  /// The boxes of the index section, filled in once the pages of the
  /// terms are known.
  List<LayoutBox>? _indexSlot;

  /// Fills the index section (the gem's `convert_index_section`): the
  /// categories and their terms in the theme's columns.
  void _fillIndex(List<LayoutBox> slot) {
    _index
      ..linkPages((anchor) => _anchorPages[anchor], _pageLabel)
      ..linkAssociations();
    // The modern engine lists each page once unless the document asks
    // otherwise; the gem lists a page for each use.
    final style = _document.attr('index-pagenum-sequence-style') ?? 'page';
    // `index_category_headings: false` leaves out the letter headings.
    final headings = switch (_theme.value('index_category_headings')) {
      ThemeBool(:final value) => value,
      _ => indexHasCategoryHeadings(_document),
    };
    // The modern engine reads the index's font keys (`index_font_family`,
    // `_size`, `_color`, `_style`); the gem has none.
    final saved = _font;
    _font = _themeFont('index', _font);
    final List<LayoutBox> boxes;
    try {
      boxes = _collect(() {
        final termSpacing = (_n('description_list_term_spacing') ?? 0)
            .toDouble();
        final needed = termSpacing + 2 * _typesetHeight(_font);
        final termStyle =
            _fontStyle(_s('description_list_term_font_style')) ?? _font.style;
        final proseMargin = (_n('prose_margin_bottom') ?? 0).toDouble();
        // `index_sort: code-point` (modern engine): every term in one
        // list, keyed by its terms joined with commas, in code point
        // order (as Typst's in-dexter index).
        if ((_choice('index_sort', const ['letter', 'code-point']) ??
                _document.attr('index-sort')) ==
            'code-point') {
          _flatIndex(style);
          return;
        }
        for (final category in _index.categories) {
          final letter = category.name.text;
          if (headings) {
            _out.add(
              CustomBox(
                _MinRoom(
                  _textBox(
                    letter,
                    _font.copyWith(style: termStyle),
                    align: 'left',
                    inlineFormat: false,
                  ),
                  needed,
                ),
                style: BoxStyle(margin: EdgeInsets(bottom: termSpacing)),
              ),
            );
          }
          for (final term in category.terms) {
            _indexTerm(term, style);
          }
          if (proseMargin > 0) _out.add(SpacerBox(proseMargin));
        }
      });
    } finally {
      _font = saved;
    }
    final columns = (_n('index_columns') ?? 1).toInt();
    slot
      ..clear()
      ..addAll(
        columns < 2
            ? boxes
            : [
                ColumnsBox(
                  boxes,
                  count: columns,
                  gap: (_n('index_column_gap') ?? 0).toDouble(),
                ),
              ],
      );
  }

  /// The index as one list (`index_sort: code-point`): each term with an
  /// entry of its own keyed by its terms and its parents' joined with
  /// commas, the keys in code point order; a subterm's entry its terms
  /// after the first, indented (`index_subterm_indent`), under a line
  /// with the first when the entry before has another; each entry
  /// followed by `index_item_spacing`.
  void _flatIndex(String? style) {
    final entries = <(List<IndexName>, IndexTerm)>[];
    void walk(IndexTerm term, List<IndexName> parents) {
      final names = [...parents, term.name];
      if (!term.isContainer) entries.add((names, term));
      for (final subterm in term.terms) {
        walk(subterm, names);
      }
    }

    for (final category in _index.categories) {
      for (final term in category.terms) {
        walk(term, const []);
      }
    }
    String key(List<IndexName> names) => names.map((n) => n.text).join(', ');
    entries.sort((a, b) => key(a.$1).compareTo(key(b.$1)));
    final spacing = _length('index_item_spacing', _font.size) ?? 0;
    final subtermIndent = _length('index_subterm_indent', _font.size) ?? 0;
    String? previous;
    for (final (names, term) in entries) {
      if (names.length > 1 && names.first.text != previous) {
        _indexTerm(term, style, flat: (names.first.markup, 0, false));
        if (spacing > 0) _out.add(SpacerBox(spacing));
      }
      _indexTerm(
        term,
        style,
        flat: names.length == 1
            ? (term.name.markup, 0, true)
            : (
                names.skip(1).map((n) => n.markup).join(', '),
                subtermIndent,
                true,
              ),
      );
      if (spacing > 0) _out.add(SpacerBox(spacing));
      previous = names.first.text;
    }
  }

  /// Adds the entry of index [term] (the gem's `convert_index_term`); in
  /// a flat index ([flat]), with the given name and first line's indent,
  /// and its page numbers if asked (else the name alone), without its
  /// subterms.
  void _indexTerm(
    IndexTerm term,
    String? style, {
    (String, double, bool)? flat,
  }) {
    final markup = StringBuffer();
    // `index_pagenum_text_align: right` (modern engine): the page numbers
    // in a column at the right, in tabular figures, as books set them.
    final column =
        _choice('index_pagenum_text_align', const ['left', 'right']) == 'right';
    String? pagenums;
    final seeAlso = <String>[];
    // Linked only on screen (the gem's `media`).
    final screen = (_document.attr('media') ?? 'screen') == 'screen';
    String link(String anchor, String text) =>
        screen ? '<a anchor="$anchor">$text</a>' : text;
    final pages = flat == null || flat.$3;
    if (!term.isContainer && screen && pages) {
      markup.write('<a id="${term.anchor}">$_dummyText</a>');
    }
    markup.write(flat?.$1 ?? term.name.markup);
    if (!term.isContainer && pages) {
      if (term.see case (final target, final name)) {
        markup
          ..write(' (see ')
          ..write(
            target == null ? name.markup : link(target.anchor, name.markup),
          )
          ..write(')');
      } else {
        final destinations = term.destinations;
        final List<String> numbers;
        switch (style) {
          // (In print, ranges, unless the document asks for each page in
          // the modern engine: `index-pagenum-sequence-style: page`.)
          case _
              when !screen &&
                  _document.attr('index-pagenum-sequence-style') == 'page':
            numbers = [
              ...{for (final d in destinations) d.page!},
            ];
          case _ when !screen:
            numbers = _consolidateRanges([
              ...{for (final d in destinations) d.page!},
            ]);
          case 'page':
            final seen = <String>{};
            numbers = [
              for (final d in destinations)
                if (seen.add(d.page!)) link(d.anchor, d.page!),
            ];
          case 'range':
            final first = <String, String>{};
            for (final d in destinations) {
              first.putIfAbsent(d.page!, () => d.anchor);
            }
            numbers = [
              for (final range in _consolidateRanges(first.keys.toList()))
                link(first[range.split('-').first]!, range),
            ];
          default:
            numbers = [for (final d in destinations) link(d.anchor, d.page!)];
        }
        if (column) {
          pagenums = numbers.join(', ');
        } else {
          for (final number in numbers) {
            markup.write(', $number');
          }
        }
        for (final (target, name) in term.seeAlso) {
          final also = target == null
              ? name.markup
              : link(target.anchor, name.markup);
          seeAlso.add('(see also $also)');
        }
      }
    }
    final indent = (_n('description_list_description_indent') ?? 0).toDouble();
    // (A flat index's lines after the first: `index_hanging_indent`.)
    final hanging = flat == null
        ? indent * 2
        : _length('index_hanging_indent', _font.size) ?? indent * 2;
    final first = flat?.$2 ?? 0;
    void entry(String text, double left, [String? numbers]) {
      final box = _textBox(
        text,
        _font,
        align: 'left',
        normalize: false,
        indent: first - hanging,
      );
      _out.add(
        CustomBox(
          numbers == null
              ? box
              : _IndexRow(
                  box,
                  _textBox(
                    numbers,
                    _font,
                    align: 'right',
                    normalize: false,
                    features: const {'tnum'},
                  ),
                  gap: _font.size,
                ),
          style: BoxStyle(margin: EdgeInsets(left: left + hanging)),
        ),
      );
    }

    entry(markup.toString(), 0, pagenums);
    if (flat != null) {
      for (final item in seeAlso) {
        entry(item, first);
      }
      return;
    }
    if (seeAlso.isEmpty && term.isLeaf) return;
    final nested = _collect(() {
      for (final item in seeAlso) {
        entry(item, 0);
      }
      for (final subterm in term.terms) {
        _indexTerm(subterm, style);
      }
    });
    _out.add(
      BlockBox(
        nested,
        style: BoxStyle(margin: EdgeInsets(left: indent)),
      ),
    );
  }

  /// [numbers] with runs of consecutive numbers joined as ranges (the gem's
  /// `consolidate_ranges`).
  static List<String> _consolidateRanges(List<String> numbers) {
    if (numbers.length < 2) return numbers;
    final ranges = <List<String>>[];
    String? previous;
    for (final number in numbers) {
      if (previous != null &&
          (int.tryParse(previous) ?? 0) + 1 == (int.tryParse(number) ?? 0)) {
        if (ranges.last.length == 1) {
          ranges.last.add(number);
        } else {
          ranges.last[1] = number;
        }
      } else {
        ranges.add([number]);
      }
      previous = number;
    }
    return [for (final range in ranges) range.join('-')];
  }

  String _inlineIcon(Inline node) {
    final icons = _document.attr('icons');
    final alt = node.attr('alt') ?? '';
    if (icons != 'font') {
      if (icons != null) {
        logger.warn('image icons are not supported yet: ${node.target ?? ''}');
        return '[${node.target ?? ''}&#93;';
      }
      return '[$alt&#93;';
    }
    var name = node.target ?? '';
    String? set;
    if (name.contains('@')) {
      final at = name.indexOf('@');
      set = name.substring(at + 1);
      name = name.substring(0, at);
    } else {
      set = node.attr('set');
    }
    final (resolvedSet, iconName, glyph) = _resolveIcon(name, set);
    if (glyph == null) {
      logger.warn(
        '$iconName is not a valid icon name in the $resolvedSet icon set',
      );
      return '[$alt&#93;';
    }
    if (!_iconsInstalled(resolvedSet)) return '[$alt&#93;';
    final size = switch (node.attr('size')) {
      null => '',
      'lg' => ' size="1.333em"',
      'fw' => ' width="1em"',
      final value => ' size="${value.replaceFirst('x', 'em')}"',
    };
    final role = node.role;
    final classAttr = role == null ? '' : ' class="$role"';
    return '<font name="$resolvedSet"$size$classAttr>$glyph</font>';
  }

  String _inlineFootnote(Inline node) {
    final index = node.attr('index');
    final footnote = index == null
        ? null
        : _document.footnotes.where((f) => f.index == index).firstOrNull;
    if (footnote != null) {
      return _footnoteReference(
        index!,
        anchored: node.type != 'xref',
        rendered: _renderedFootnotes.contains(footnote),
      );
    }
    if (node.type == 'xref') {
      final color = _theme.value('role_unresolved_font_color')?.rubyString;
      return '<sup class="wj"><font color="$color">[${node.text ?? ''}]</font></sup>';
    }
    logger.warn('unknown footnote type: ${node.type}');
    return '';
  }

  /// The reference to footnote [index]: its number in brackets, raised,
  /// linked to the footnote ([anchored]: the footnote links back to it).
  String _footnoteReference(
    String index, {
    bool anchored = true,
    bool rendered = false,
  }) {
    final anchor = anchored
        ? '<a id="_footnoteref_$index">$_dummyText</a>'
        : '';
    if (!anchored) _unanchoredFootnotes.add(index);
    final label = _footnoteNumbering == 'document'
        ? index
        : rendered
        ? _footnoteLabels[index] ?? index
        : '${(int.tryParse(index) ?? 0) - _renderedFootnotes.length}';
    // `footnotes_reference_content` (modern engine, ADR-0010), else the
    // document's `footnote-reference-template` (every format's, ADR-0012):
    // `[1]` by default, raised, the number the link.
    final template =
        (_s('footnotes_reference_content') ??
            _document.attr('footnote-reference-template')) ??
        '[{{number}}]';
    final marker = renderNumbered(
      template,
      label,
      (n) =>
          '<a anchor="_footnotedef_$index"${_footnoteLabelKey(index)}>$n</a>',
    );
    return '<sup class="wj">$anchor$marker</sup>';
  }

  /// The label before footnote [index]'s note, numbered [label]:
  /// `footnotes_label_content` (modern engine, ADR-0010), else the
  /// document's `footnote-label-template`, `[1] ` by default, the number a
  /// link back to the reference.
  String _footnoteNoteLabel(String index, String label) => renderNumbered(
    (_s('footnotes_label_content') ??
            _document.attr('footnote-label-template')) ??
        '[{{number}}] ',
    label,
    (n) => '<a anchor="_footnoteref_$index"${_footnoteLabelKey(index)}>$n</a>',
  );

  /// How footnotes are numbered: from 1 in each `chapter` (the gem's),
  /// on each `page` (modern engine, footnotes at the bottom of the page)
  /// or through the `document` (`footnotes_numbering`).
  String get _footnoteNumbering {
    return switch (_choice('footnotes_numbering', const [
      'chapter',
      'page',
      'document',
    ])) {
      'page' when _pageFootnotes => 'page',
      'document' => 'document',
      _ => 'chapter',
    };
  }

  /// The `label` attribute that has the layout number footnote [index]'s
  /// reference and note on their page (when footnotes are numbered so).
  String _footnoteLabelKey(String index) =>
      _footnoteNumbering == 'page' ? ' label="fn$index"' : '';

  /// The texts of the labels the layout gives (a footnote's number on its
  /// page, `fn<index>`), from the layout before.
  final Map<String, String> _layoutLabels = {};

  /// The footnotes with a reference without an anchor (a footnote
  /// referred to again by its id).
  final Set<String> _unanchoredFootnotes = {};

  /// Numbers each page's footnote references from 1, in reading order,
  /// from [result]'s anchors; the footnotes whose numbers changed.
  Set<String> _numberFootnotesByPage(LayoutResult result) {
    final references =
        [
          for (final MapEntry(:key, :value) in result.anchors.entries)
            if (key.startsWith('_footnoteref_'))
              (key.substring('_footnoteref_'.length), value),
        ]..sort((a, b) {
          final (_, p) = a;
          final (_, q) = b;
          if (p.page != q.page) return p.page.compareTo(q.page);
          if ((p.y - q.y).abs() > 0.5) return q.y.compareTo(p.y);
          return p.x.compareTo(q.x);
        });
    final changed = <String>{};
    var page = -1;
    var number = 0;
    for (final (index, position) in references) {
      if (position.page != page) {
        page = position.page;
        number = 0;
      }
      number++;
      final key = 'fn$index';
      if (_layoutLabels[key] != '$number') {
        _layoutLabels[key] = '$number';
        changed.add(index);
      }
    }
    return changed;
  }

  /// The footnotes already rendered (at the end of earlier chapters).
  final List<Footnote> _renderedFootnotes = [];

  /// The labels of footnotes rendered at the end of a chapter, for
  /// references to them later.
  final Map<String, String> _footnoteLabels = {};

  /// The footnotes set at the bottom of the page their reference is on,
  /// by the reference's anchor (modern engine).
  final Map<String, LayoutBox> _notes = {};

  /// Whether footnotes go at the bottom of the page their reference is on
  /// (the modern engine's default, `footnotes_placement: page`), rather
  /// than at the end of the chapter or document (`end`, the gem's).
  bool get _pageFootnotes =>
      (_choice('footnotes_placement', const ['page', 'end']) ?? 'page') ==
      'page';

  /// The rule above the footnotes at the bottom of a page: a third of the
  /// column long (`footnotes_separator_length`), `footnotes_separator_width`
  /// thick, `footnotes_margin_top` below the text.
  LayoutBox _footnoteSeparator() {
    final width = (_n('footnotes_separator_width') ?? 0.5).toDouble();
    final color = pdfColorOf(
      _c('footnotes_separator_color') ?? _c('base_border_color'),
    );
    final length = _s('footnotes_separator_length') ?? '33.33%';
    final spacing = (_n('footnotes_item_spacing') ?? 0).toDouble();
    // Under Typst's model (base_leading) the rule takes no room: drawn
    // on its line, the space above and below it from there.
    final flat = _typstLeading(_font) != null;
    return DrawingBox(
      flat ? 0 : width,
      (canvas, rect) {
        if (color == null || width <= 0) return;
        final long = length.endsWith('%')
            ? rect.width *
                  (double.tryParse(length.replaceAll('%', '')) ?? 0) /
                  100
            : _toPoints(ThemeString(length));
        canvas
          ..save()
          ..setStrokeColor(color)
          ..setLineWidth(width)
          ..moveTo(rect.left, rect.top - (flat ? 0 : width / 2))
          ..lineTo(rect.left + long, rect.top - (flat ? 0 : width / 2))
          ..stroke()
          ..restore();
      },
      style: BoxStyle(
        margin: EdgeInsets(
          top: switch (_n('footnotes_margin_top')) {
            final num margin => margin.toDouble(),
            null => _font.size,
          },
          // (Each note has the item spacing above it.)
          bottom: math.max(spacing, _font.size / 2) - spacing,
        ),
      ),
    );
  }

  /// Adds the footnotes of [node] not yet rendered, at the bottom of the
  /// page by default (the gem's `ink_footnotes`); in the modern engine,
  /// each at the bottom of the page its reference is on.
  void _footnotes(AbstractBlock node) {
    final doc = _document;
    final footnotes = [
      for (final footnote in doc.footnotes)
        if (!_renderedFootnotes.contains(footnote)) footnote,
    ];
    if (footnotes.isEmpty) return;
    if (_pageFootnotes) {
      _withFont('footnotes', () {
        final spacing = (_n('footnotes_item_spacing') ?? 0).toDouble();
        // How far each note's first line is set in (footnotes_indent, an
        // em of the notes' size), and the space after its label
        // (footnotes_label_gap): a no-break space that wide.
        final indent = _length('footnotes_indent', _font.size) ?? 0;
        final gapWidth = _length('footnotes_label_gap', _font.size) ?? 0;
        final space = _fonts
            .font(_font.family, _font.style)
            .widthOf('\u00a0', 1, kerning: false);
        final gap = gapWidth > 0 && space > 0
            ? '<font size="${gapWidth / space}">\u00a0</font>'
            : '';
        final offset = _renderedFootnotes.length;
        final sectionText = node is Section
            ? node.xreftext(doc.attr('xrefstyle'))
            : null;
        for (final footnote in footnotes) {
          final index = footnote.index;
          final label = _footnoteNumbering == 'document'
              ? index
              : '${(int.tryParse(index) ?? 0) - offset}';
          if (sectionText != null) {
            _footnoteLabels[index] = '$label - $sectionText';
          }
          _notes['_footnoteref_$index'] = CustomBox(
            _textBox(
              '<a id="_footnotedef_$index">$_dummyText</a>'
              '${_footnoteNoteLabel(index, label)}$gap${footnote.text}',
              _font,
              align: _baseTextAlign,
              indent: indent,
              hyphenate: true,
            ),
            style: BoxStyle(margin: EdgeInsets(top: spacing)),
          );
        }
      });
      _renderedFootnotes.addAll(footnotes);
      return;
    }
    if (node is Document || node == doc.blocks.lastOrNull) {
      final margin = (_n('block_margin_bottom') ?? 0).toDouble();
      if (margin > 0) _out.add(SpacerBox(margin));
    }
    final bottom = _s('footnotes_margin_top') == 'auto';
    if (!bottom) {
      final margin = (_n('footnotes_margin_top') ?? 0).toDouble();
      if (margin > 0) _out.add(SpacerBox(margin));
    }
    final items = <CustomBox>[];
    _withFont('footnotes', () {
      final saved = _out;
      _out = items;
      if (doc.attr('footnotes-title') case final title?) {
        final font = _themeFont(
          'footnotes_caption',
          _themeFont('caption', _font),
        );
        items.add(
          CustomBox(
            _textBox(title, font, align: _baseTextAlign, normalize: false),
            style: BoxStyle(
              margin: EdgeInsets(
                top:
                    (_n('footnotes_caption_margin_outside') ??
                            _n('caption_margin_outside') ??
                            0)
                        .toDouble(),
                bottom:
                    (_n('footnotes_caption_margin_inside') ??
                            _n('caption_margin_inside') ??
                            0)
                        .toDouble(),
              ),
            ),
          ),
        );
      }
      _out = saved;
      final spacing = (_n('footnotes_item_spacing') ?? 0).toDouble();
      final offset = _renderedFootnotes.length;
      final sectionText = node is Section
          ? node.xreftext(doc.attr('xrefstyle'))
          : null;
      for (final footnote in footnotes) {
        final index = footnote.index;
        final label = _footnoteNumbering == 'document'
            ? index
            : '${(int.tryParse(index) ?? 0) - offset}';
        if (sectionText != null) {
          _footnoteLabels[index] = '$label - $sectionText';
        }
        items.add(
          CustomBox(
            _textBox(
              '<a id="_footnotedef_$index">$_dummyText</a>'
              '${_footnoteNoteLabel(index, label)}${footnote.text}',
              _font,
              align: _baseTextAlign,
              hyphenate: true,
            ),
            style: BoxStyle(margin: EdgeInsets(bottom: spacing)),
          ),
        );
      }
    });
    _renderedFootnotes.addAll(footnotes);
    _out.add(
      CustomBox(
        _Stacked(items, bottom: bottom),
        style: BoxStyle(margin: _outdented(EdgeInsets.zero)),
      ),
    );
  }

  String _inlineKbd(Inline node) {
    final keys = node.keys ?? const [];
    if (keys.length == 1) return '<kbd>${keys.first}</kbd>';
    return keys
        .map((key) => '<kbd>$key</kbd>')
        .join(_s('kbd_separator') ?? '+');
  }

  String _inlineMenu(Inline node) {
    final menu = node.attr('menu') ?? '';
    final caret = _s('menu_caret_content') ?? ' › ';
    final submenus = node.submenus ?? const [];
    final item = node.attr('menuitem');
    if (submenus.isNotEmpty) {
      return '<menu>${[menu, ...submenus, ?item].join(caret)}</menu>';
    }
    if (item != null) return '<menu>$menu$caret$item</menu>';
    return '<menu>$menu</menu>';
  }

  String _inlineQuoted(Inline node) {
    String open;
    String close;
    var isTag = true;
    var quotes = false;
    final quoteChars = switch (_theme.value('quotes')) {
      ThemeList(:final values) => [for (final v in values) v.rubyString],
      _ => const ['&#8220;', '&#8221;', '&#8216;', '&#8217;'],
    };
    if (node.type == 'asciimath' || node.type == 'latexmath') {
      final latex = node.type == 'latexmath';
      if (_inlineMath(node.text ?? '', latex: latex) case final image?) {
        return image;
      }
    }
    switch (node.type) {
      case 'emphasis':
        (open, close) = ('<em>', '</em>');
      case 'strong':
        (open, close) = ('<strong>', '</strong>');
      case 'monospaced' || 'asciimath' || 'latexmath':
        if (node.type != 'monospaced') _warnMathAsSource();
        (open, close) = ('<code>', '</code>');
      case 'superscript':
        (open, close) = ('<sup>', '</sup>');
      case 'subscript':
        (open, close) = ('<sub>', '</sub>');
      case 'double':
        (open, close) = (quoteChars[0], quoteChars[1]);
        isTag = false;
        quotes = true;
      case 'single':
        (open, close) = (quoteChars[2], quoteChars[3]);
        isTag = false;
        quotes = true;
      case 'mark':
        (open, close) = ('<mark>', '</mark>');
      default:
        (open, close) = ('', '');
        isTag = false;
    }
    var inner = node.text ?? '';
    if (quotes &&
        inner.length > 3 &&
        inner.endsWith('...') &&
        !inner.substring(0, inner.length - 3).endsWith(r'\')) {
      inner = '${inner.substring(0, inner.length - 3)}&#8230;';
    }
    final String quoted;
    if (node.role case final roles?) {
      // Spaces kept: each but the last of a run gets a zero width space
      // after it, which isn't collapsed.
      if (node.hasRole('pre-wrap') && inner.contains('  ')) {
        inner = inner.replaceAll(RegExp(' (?= )'), ' \u200b');
      }
      quoted = isTag
          ? '${open.substring(0, open.length - 1)} class="$roles">$inner$close'
          : '<span class="$roles">$open$inner$close</span>';
    } else {
      quoted = '$open$inner$close';
    }
    return node.id != null
        ? '<a id="${node.id}">$_dummyText</a>$quoted'
        : quoted;
  }
}

/// Content that moves to the next region unless [room] points fit below
/// it (a heading kept with what follows).
final class _NeedsRoom implements CustomContent {
  const new(this.content, this.room);

  final CustomContent content;
  final double room;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!atTop) {
      final whole = content.place(width, double.infinity, atTop: true);
      if (whole != null && whole.height + room > available + 0.0001) {
        return null;
      }
    }
    return content.place(width, available, atTop: atTop);
  }

  @override
  double minHeight(double width) => content.minHeight(width) + room;

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

enum _NumeralKind { decimal, letters, roman, none }

/// A list numeral (the gem's numbering: integers, letters by Ruby's
/// `String#next`, roman numerals, or none).
final class _Numeral {
  const new decimal(this.value)
    : kind = _NumeralKind.decimal,
      letters = '',
      upper = false;

  const new letters(this.letters)
    : kind = _NumeralKind.letters,
      value = 0,
      upper = false;

  const new roman(this.value, {required this.upper})
    : kind = _NumeralKind.roman,
      letters = '';

  const new none()
    : kind = _NumeralKind.none,
      value = 0,
      letters = '',
      upper = false;

  final _NumeralKind kind;
  final int value;
  final String letters;
  final bool upper;

  String get text => switch (kind) {
    _NumeralKind.decimal => '$value',
    _NumeralKind.letters => letters,
    _NumeralKind.roman => value < 1 ? '$value' : _romanOf(value, upper: upper),
    _NumeralKind.none => '',
  };

  _Numeral get next => switch (kind) {
    _NumeralKind.decimal => _Numeral.decimal(value + 1),
    _NumeralKind.letters => _Numeral.letters(_succ(letters)),
    _NumeralKind.roman => _Numeral.roman(value + 1, upper: upper),
    _NumeralKind.none => this,
  };

  _Numeral get previous => switch (kind) {
    _NumeralKind.decimal => _Numeral.decimal(value - 1),
    _NumeralKind.roman => _Numeral.roman(value - 1, upper: upper),
    _ => this,
  };

  /// Ruby's `String#succ` for letters (`z` to `aa`) and other characters
  /// (the next code point).
  static String _succ(String text) {
    if (text.isEmpty) return text;
    final runes = text.runes.toList();
    var i = runes.length - 1;
    while (i >= 0) {
      final c = runes[i];
      if (c == 0x7a || c == 0x5a) {
        runes[i] = c - 25;
        i--;
        continue;
      }
      runes[i] = c + 1;
      return String.fromCharCodes(runes);
    }
    final first = text.runes.first;
    return String.fromCharCodes([if (first == 0x7a) 0x61 else 0x41, ...runes]);
  }
}

String _romanOf(int number, {required bool upper}) {
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const letters = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  final out = StringBuffer();
  var n = number;
  for (var i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      out.write(letters[i]);
      n -= values[i];
    }
  }
  return upper ? out.toString() : out.toString().toLowerCase();
}

/// Content that moves to the next region unless [minimum] points are
/// left (the gem's `allocate_space_for_list_item`).
final class _MinRoom implements CustomContent {
  const new(this.content, this.minimum);

  final CustomContent content;
  final double minimum;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!atTop && available < minimum) return null;
    return content.place(width, available, atTop: atTop);
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// Content with a marker drawn beside its first piece: [marker] laid out
/// [markerWidth] wide, [offset] points from the content's left edge.
final class _Marked implements CustomContent {
  const new(this.content, this.marker, this.markerWidth, this.offset);

  final CustomContent content;
  final CustomContent marker;
  final double markerWidth;
  final double offset;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placed = content.place(width, available, atTop: atTop);
    if (placed == null) return null;
    final mark = marker.place(markerWidth, double.infinity, atTop: true);
    return CustomPlacement(
      height: placed.height,
      rest: placed.rest,
      anchors: placed.anchors,
      paint: (page, x, top) {
        mark?.paint(page, x + offset, top);
        placed.paint(page, x, top);
      },
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// Nothing: no room taken, nothing drawn.
final class _Nothing implements CustomContent {
  const new();

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => CustomPlacement(height: 0, paint: (page, x, top) {});

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// How wide an image is asked to be.
enum _ImageWidthKind { natural, points, percent, scale, viewport }

/// The width asked of an image: its own, [value] points, a [value]
/// fraction of the available width or of the page's, or its own scaled by
/// [value]; [constrain]ed to the available width.
final class _ImageWidth {
  const new natural()
    : kind = _ImageWidthKind.natural,
      value = 0,
      constrain = false;

  const new points(this.value, {this.constrain = false})
    : kind = _ImageWidthKind.points;

  const new percent(this.value, {this.constrain = false})
    : kind = _ImageWidthKind.percent;

  const new scale(this.value) : kind = _ImageWidthKind.scale, constrain = false;

  const new viewport(this.value)
    : kind = _ImageWidthKind.viewport,
      constrain = false;

  final _ImageWidthKind kind;
  final double value;
  final bool constrain;

  /// The width in points for [available] points and a page [pageWidth]
  /// wide, or null for the image's own (or a scale).
  double? resolve(double available, double pageWidth) {
    final width = switch (kind) {
      _ImageWidthKind.points => value,
      _ImageWidthKind.percent => value * available,
      _ImageWidthKind.viewport => value * pageWidth,
      _ImageWidthKind.natural || _ImageWidthKind.scale => null,
    };
    return width != null && constrain ? math.min(width, available) : width;
  }
}

/// A border around an image.
final class _Border {
  const new(
    this.width,
    this.color,
    this.radius, {
    required this.fitWidth,
    this.widths,
    this.style,
  });

  final double width;
  final PdfColor color;
  final double radius;

  /// The widths side by side (top, right, bottom, left), if they differ.
  final List<double>? widths;

  /// The line style (`dashed`...).
  final String? style;

  /// Whether the border spans the available width, not the image's.
  final bool fitWidth;
}

/// [content] as wide as it needs (its widest line), at the left, in the
/// middle or at the right of the room ([align]).
final class _Aligned implements CustomContent {
  const new(this.content, {this.align = 'left'});

  final CustomContent content;
  final String align;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final wide = math.min(width, content.intrinsicWidths().$2);
    final placed = content.place(wide, available, atTop: atTop);
    if (placed == null) return null;
    final offset = switch (align) {
      'center' => (width - wide) / 2,
      'right' => width - wide,
      _ => 0.0,
    };
    return CustomPlacement(
      height: placed.height,
      anchors: [
        for (final (name, x, y) in placed.anchors) (name, x + offset, y),
      ],
      rest: placed.rest == null ? null : _Aligned(placed.rest!, align: align),
      paint: (page, x, top) => placed.paint(page, x + offset, top),
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// A block image sized and placed as asciidoctor-pdf places it: no wider
/// than the available width, moved to the next page when it doesn't fit
/// (with its [caption] below it), else shrunk to fit.
final class _ImageContent implements CustomContent {
  const new(
    this.graphic, {
    required this.width,
    required this.align,
    required this.pageWidth,
    this.caption,
    this.border,
    this.link,
  });

  final Graphic graphic;
  final _ImageWidth width;
  final String align;
  final double pageWidth;
  final CustomBox? caption;
  final _Border? border;
  final String? link;

  /// The image's size for [available] points of width (and [height] of
  /// region, for SVG sizes in percent).
  (double, double) _size(double available, double height) {
    final asked = width.resolve(available, pageWidth);
    switch (graphic) {
      case final SvgImage svg:
        var (w, h) = prawnSvgSize(svg, asked, null, available, height);
        if (width.kind == _ImageWidthKind.scale) {
          (w, h) = prawnSvgSize(
            svg,
            math.min(available, w * width.value),
            null,
            available,
            height,
          );
        } else if (asked == null &&
            svg.rootAttribute('width') != null &&
            w > available) {
          (w, h) = prawnSvgSize(svg, available, null, available, height);
        }
        return (w, h);
      case final other:
        final natural = other.intrinsicWidth * 0.75;
        final w =
            asked ??
            (width.kind == _ImageWidthKind.scale
                ? natural * width.value
                : math.min(available, natural));
        return (w, other.intrinsicHeight * w / other.intrinsicWidth);
    }
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final captionHeight = switch (caption) {
      final CustomBox box? =>
        (box.content.place(width, double.infinity, atTop: true)?.height ?? 0) +
            box.style.margin.vertical,
      null => 0.0,
    };
    final regionHeight = available.isFinite ? available : 1000000000.0;
    var (w, h) = _size(width, regionHeight);
    final room = available - captionHeight;
    if (h > room + 1e-6) {
      if (!atTop) return null;
      if (room > 0) {
        if (graphic case final SvgImage svg) {
          (w, h) = prawnSvgSize(svg, null, room, width, regionHeight);
        } else {
          w = w * room / h;
          h = room;
        }
      }
    }
    final left = switch (align) {
      'center' => (width - w) * 0.5,
      'right' => width - w,
      _ => 0.0,
    };
    return CustomPlacement(
      height: h,
      paint: (page, x, top) {
        final rect = PdfRect(x + left, top - h, w, h);
        final canvas = page.canvas;
        switch (graphic) {
          case final PdfImage image:
            canvas.image(image, rect);
          case final other:
            canvas.save();
            other.paint(canvas, rect);
            canvas.restore();
        }
        if (border case final border?) {
          final frame = border.fitWidth ? PdfRect(x, top - h, width, h) : rect;
          PdfConverter._strokeBounds(
            canvas,
            frame,
            border.color,
            width: border.width,
            widths: border.widths,
            style: border.style,
            radius: border.radius,
          );
        }
        if (link case final link?) {
          page.link(
            rect,
            link.startsWith('#')
                ? LinkTarget.named(destinationName(link.substring(1)))
                : LinkTarget.uri(link),
          );
        }
      },
    );
  }

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, graphic.intrinsicWidth);
}

/// A table cell's content and style, before it is laid out.
final class _TableCellData {
  const new({
    required this.text,
    required this.font,
    required this.padding,
    required this.colspan,
    required this.rowspan,
    required this.align,
    required this.valign,
    this.blocks,
    this.background,
    this.inlineFormat = true,
  });

  final String text;
  final List<LayoutBox>? blocks;
  final _FontState font;
  final List<double> padding;
  final ThemeColor? background;
  final int colspan;
  final int rowspan;
  final String align;
  final String valign;
  final bool inlineFormat;
}

/// One side of a table cell's border.
final class _Side {
  const new(this.width, this.color, this.style);

  final double width;
  final ThemeValue? color;
  final ThemeValue? style;
}

/// [content] laid out [extra] points wider than it is given (prawn-table
/// widens a cell's text by its `FPTolerance`, a point).
final class _Widened implements CustomContent {
  const new(this.content, this.extra);

  final CustomContent content;
  final double extra;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => content.place(width + extra, available, atTop: atTop);

  @override
  double minHeight(double width) => content.minHeight(width + extra);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// [content] with a [gap] above it at the top of a page (a heading's
/// `margin_page_top`).
final class _PageTopGap implements CustomContent {
  const new(this.content, this.gap);

  final CustomContent content;
  final double gap;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!atTop) return content.place(width, available, atTop: atTop);
    final placed = content.place(width, available - gap, atTop: true);
    if (placed == null) return null;
    return CustomPlacement(
      height: placed.height + gap,
      rest: placed.rest,
      anchors: [for (final (name, x, y) in placed.anchors) (name, x, y + gap)],
      paint: (page, x, top) => placed.paint(page, x, top - gap),
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// Content drawn where [paint] draws it, taking no room (or, with
/// [fill], the rest of the region: a cover page).
final class _Absolute implements CustomContent {
  const new(this.paint, {this.fill = false});

  final void Function(PdfPage page) paint;
  final bool fill;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => CustomPlacement(
    height: fill && available.isFinite ? available : 0,
    paint: (page, x, top) => paint(page),
  );

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// The platform's zlib (the Dart VM's), faster than libpdf's own.
/// A PNG image's samples encoded as the PDF is saved with
/// ([PngImage.encode]), from the file's [bytes].
final class _PngEncoding extends Job<PngPayload> {
  const new(this.bytes, {required this.nativeZlib});

  final Uint8List bytes;
  final bool nativeZlib;

  @override
  PngPayload run() =>
      PngImage.parse(bytes)
          .encode(PdfConverter._writerOptions(nativeZlib: nativeZlib));
}

/// A stream's [data] encoded as the PDF is saved with ([encodeStream]).
final class _StreamEncoding extends Job<StreamPayload> {
  const new(this.data, {required this.nativeZlib});

  final Uint8List data;
  final bool nativeZlib;

  @override
  StreamPayload run() =>
      encodeStream(data, PdfConverter._writerOptions(nativeZlib: nativeZlib));
}

final class _NativeZlib implements ZlibCodec {
  const new();

  @override
  Uint8List encode(List<int> data, int level) =>
      Uint8List.fromList(io.zlibEncode(data, level));

  @override
  Uint8List decode(List<int> data) => Uint8List.fromList(io.zlibDecode(data));
}

/// A formula set on its own (a STEM block): aligned in the room, scaled
/// down to fit it when wider, copied as its [source].
final class _DisplayMath implements CustomContent {
  const new(this.box, this.source, {required this.align, this.color});

  final MathBox box;
  final String source;
  final String align;
  final PdfColor? color;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final scale = box.width > width ? width / box.width : 1.0;
    final height = (box.height + box.depth) * scale;
    if (height > available + 1e-6 && !atTop) return null;
    final left = switch (align) {
      'left' => 0.0,
      'right' => width - box.width * scale,
      _ => (width - box.width * scale) / 2,
    };
    return CustomPlacement(
      height: height,
      paint: (page, x, top) {
        final canvas = page.canvas
          ..save()
          ..beginMarkedContent('Span', actualText: source);
        if (color case final color?) {
          canvas
            ..setFillColor(color)
            ..setStrokeColor(color);
        }
        box.paint(
          canvas,
          PdfRect(x + left, top - height, box.width * scale, height),
        );
        canvas
          ..endMarkedContent()
          ..restore();
      },
    );
  }

  @override
  double minHeight(double width) =>
      (box.height + box.depth) * (box.width > width ? width / box.width : 1.0);

  @override
  (double, double) intrinsicWidths() => (box.width, box.width);
}

/// An entry of the table of contents: its title (as wide as the room
/// less a [placeholder] for the page number), then a dot leader and the
/// page number on its last line, made by [leader] for the width and where
/// the dots start.
final class _TocEntry implements CustomContent {
  const new(this.title, this.placeholder, this.leader, {this.hanging = 0});

  final TextBox title;
  final double placeholder;
  final CustomContent Function(double width, double startDots) leader;

  /// How much the lines after the first are indented (the title is set
  /// that much in, its first line as much out).
  final double hanging;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final room = width - placeholder - hanging;
    final placed = title.place(room, available, atTop: atTop);
    if (placed == null) return null;
    if (placed.rest case final TextBox rest) {
      return CustomPlacement(
        height: placed.height,
        anchors: placed.anchors,
        rest: _TocEntry(rest, placeholder, leader, hanging: hanging),
        paint: (page, x, top) => placed.paint(page, x + hanging, top),
      );
    }
    final last = title.lastFragment(room);
    return CustomPlacement(
      height: placed.height,
      anchors: placed.anchors,
      paint: (page, x, top) {
        placed.paint(page, x + hanging, top);
        if (last == null) return;
        final dots = leader(width, last.right + hanging);
        final line = dots.place(width, double.infinity, atTop: true);
        if (line == null) return;
        // On the title's last line: the same line as its first, or the
        // top of its last fragment.
        final multiline = last.top - last.firstTop > 1;
        final offset = multiline ? last.top - last.firstTop : 0.0;
        line.paint(page, x, top - offset);
      },
    );
  }

  @override
  double minHeight(double width) => title.minHeight(width - placeholder);

  @override
  (double, double) intrinsicWidths() => title.intrinsicWidths();
}

/// An index entry with its page numbers in a column: the [term] at the
/// left, the [numbers] right-aligned at the right (as wide as they are,
/// up to half the width), [gap] apart, both from the top.
final class _IndexRow implements CustomContent {
  const new(this.term, this.numbers, {required this.gap});

  final TextBox term;
  final TextBox numbers;
  final double gap;

  double _numbersWidth(double width) =>
      math.min(numbers.intrinsicWidths().$2, width / 2);

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final numbersWidth = _numbersWidth(width);
    final room = atTop ? double.infinity : available;
    final left = term.place(width - numbersWidth - gap, room, atTop: atTop);
    final right = numbers.place(numbersWidth, room, atTop: atTop);
    // An entry isn't split: it moves on whole.
    if (left == null || right == null) return null;
    if (left.rest != null || right.rest != null) return null;
    final height = math.max(left.height, right.height);
    if (!atTop && height > available) return null;
    final offset = width - numbersWidth;
    return CustomPlacement(
      height: height,
      anchors: [
        ...left.anchors,
        for (final (name, ax, ay) in right.anchors) (name, ax + offset, ay),
      ],
      paint: (page, x, top) {
        left.paint(page, x, top);
        right.paint(page, x + offset, top);
      },
    );
  }

  @override
  double minHeight(double width) {
    final numbersWidth = _numbersWidth(width);
    return math.max(
      term.minHeight(width - numbersWidth - gap),
      numbers.minHeight(numbersWidth),
    );
  }

  @override
  (double, double) intrinsicWidths() {
    final (termMin, termMax) = term.intrinsicWidths();
    final (numbersMin, numbersMax) = numbers.intrinsicWidths();
    return (termMin + gap + numbersMin, termMax + gap + numbersMax);
  }
}

/// [items] one below the other, at the bottom of the region when
/// [bottom] and they fit there (footnotes), else flowing on (an item that
/// doesn't fit split where it breaks).
final class _Stacked implements CustomContent {
  const new(this.items, {required this.bottom});

  final List<CustomBox> items;
  final bool bottom;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placements = <(CustomPlacement, double, double)>[];
    var height = 0.0;
    List<CustomBox>? rest;
    for (final (i, item) in items.indexed) {
      final margin = item.style.margin;
      final fresh = atTop && height == 0;
      final top = fresh ? 0.0 : margin.top;
      final placed = item.content.place(
        width - margin.horizontal,
        available - height - top,
        atTop: fresh,
      );
      if (placed == null) {
        rest = items.sublist(i);
        break;
      }
      placements.add((placed, height + top, margin.left));
      if (placed.rest case final more?) {
        height += top + placed.height;
        rest = [
          CustomBox(
            more,
            style: BoxStyle(margin: EdgeInsets(bottom: margin.bottom)),
          ),
          ...items.sublist(i + 1),
        ];
        break;
      }
      height += top + placed.height + margin.bottom;
    }
    if (placements.isEmpty && !atTop) return null;
    final shift = rest == null && bottom && available.isFinite
        ? math.max(0, available - height - 0.0001)
        : 0.0;
    return CustomPlacement(
      height: height + shift,
      anchors: [
        for (final (placed, y, x) in placements)
          for (final (name, ax, ay) in placed.anchors)
            (name, ax + x, ay + y + shift),
      ],
      rest: rest == null || rest.isEmpty ? null : _Stacked(rest, bottom: false),
      paint: (page, x, top) {
        for (final (placed, y, left) in placements) {
          placed.paint(page, x + left, top - shift - y);
        }
      },
    );
  }

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// A paragraph after a floated image: its text as it flows, and as it is
/// set beside the image (no gaps above and below), with what the gem
/// measures it by.
final class _FloatParagraph {
  const new(
    this.text,
    this.boxText, {
    required this.marginBottom,
    required this.blockMargin,
    required this.paddingTop,
    required this.paddingBottom,
    required this.lineLength,
    required this.descender,
    this.anchor,
  });

  final TextBox text;
  final TextBox boxText;
  final double marginBottom;
  final double blockMargin;
  final double paddingTop;
  final double paddingBottom;
  final double lineLength;
  final double descender;
  final String? anchor;
}

/// A floated image and the paragraphs after it, which wrap around it
/// while they start beside it (the gem's `init_float_box` and
/// `ink_paragraph_in_float_box`), then flow on below.
final class _FloatGroup implements CustomContent {
  new(
    this.image, {
    required this.side,
    required this.gaps,
    this.caption,
    this.captionBottom = true,
  });

  final _ImageContent image;
  final CustomBox? caption;
  final bool captionBottom;
  final String side;
  final (double, double) gaps;
  final List<_FloatParagraph> paragraphs = [];

  CustomBox _flowing(_FloatParagraph paragraph) => CustomBox(
    paragraph.text,
    style: BoxStyle(
      margin: EdgeInsets(bottom: paragraph.marginBottom),
      anchor: paragraph.anchor,
    ),
  );

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final regionHeight = available.isFinite ? available : 1000000000.0;
    final (imageWidth, _) = image._size(width, regionHeight);
    // The image (with its caption) as it's drawn.
    final pieces = <(CustomPlacement, double, double)>[];
    var blockHeight = 0.0;
    void addCaption() {
      final box = caption;
      if (box == null) return;
      final margin = box.style.margin;
      final placed = box.content.place(
        imageWidth,
        double.infinity,
        atTop: true,
      );
      if (placed == null) return;
      final x = side == 'right' ? width - imageWidth : 0.0;
      pieces.add((placed, blockHeight + margin.top, x));
      blockHeight += margin.top + placed.height + margin.bottom;
    }

    if (!captionBottom) addCaption();
    final placedImage = image.place(
      width,
      available - blockHeight,
      atTop: atTop,
    );
    if (placedImage == null) return null;
    pieces.add((placedImage, blockHeight, 0));
    blockHeight += placedImage.height;
    if (captionBottom) addCaption();
    final anchors = <(String, double, double)>[];
    var cursor = 0.0;
    var queue = <CustomBox>[];
    var index = 0;
    if (imageWidth < width) {
      final (gapX, gapY) = gaps;
      final boxLeft = side == 'right' ? 0.0 : imageWidth + gapX;
      final boxWidth = width - imageWidth - gapX;
      final boxHeight = math.min(regionHeight, blockHeight + gapY);
      var inFloat = true;
      while (inFloat && index < paragraphs.length) {
        final paragraph = paragraphs[index++];
        final start = cursor;
        final limit = math.min(
          regionHeight - start,
          boxHeight - start + paragraph.lineLength,
        );
        final placed = paragraph.boxText.place(
          boxWidth,
          limit - paragraph.paddingTop,
          atTop: false,
        );
        final printed = placed != null && placed.height > 0;
        if (paragraph.anchor case final id?) anchors.add((id, boxLeft, start));
        var end = start;
        if (printed) {
          pieces.add((placed, start + paragraph.paddingTop, boxLeft));
          end =
              start +
              paragraph.paddingTop +
              placed.height +
              paragraph.paddingBottom;
        }
        final overflow = placed == null ? paragraph.boxText : placed.rest;
        final moreParagraphs = index < paragraphs.length;
        if (overflow == null) {
          if (moreParagraphs) {
            cursor = end + paragraph.marginBottom;
            inFloat = cursor < start + limit;
          } else if (end < blockHeight) {
            cursor = blockHeight + paragraph.blockMargin;
            inFloat = false;
          } else {
            cursor = end + paragraph.marginBottom;
            inFloat = false;
          }
        } else {
          if (!printed && start < boxHeight) end = boxHeight;
          cursor = end;
          final text = overflow is TextBox
              ? overflow.restyled(paragraph.text.state, paragraph.text.layout)
              : overflow;
          queue.add(
            CustomBox(
              text,
              style: BoxStyle(
                margin: EdgeInsets(bottom: paragraph.marginBottom),
              ),
            ),
          );
          inFloat = false;
        }
      }
    }
    queue = [...queue, for (final p in paragraphs.skip(index)) _flowing(p)];
    if (imageWidth >= width) cursor = blockHeight;
    CustomContent? rest;
    if (queue.isNotEmpty) {
      final flow = _Stacked(
        queue,
        bottom: false,
      ).place(width, available - cursor, atTop: false);
      if (flow == null) {
        rest = _Stacked(queue, bottom: false);
      } else {
        pieces.add((flow, cursor, 0));
        cursor += flow.height;
        rest = flow.rest;
      }
    }
    final height = math.max(cursor, imageWidth >= width ? blockHeight : 0.0);
    return CustomPlacement(
      height: height,
      anchors: [
        ...anchors,
        for (final (placed, y, x) in pieces)
          for (final (name, ax, ay) in placed.anchors) (name, ax + x, ay + y),
      ],
      rest: rest,
      paint: (page, x, top) {
        for (final (placed, y, left) in pieces) {
          placed.paint(page, x + left, top - y);
        }
      },
    );
  }

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// A page-sized image: how it fits the page and where it sits.
final class _PageImage {
  const new(
    this.graphic, {
    required this.fit,
    required this.position,
    required this.vposition,
    this.width,
  });

  final Graphic graphic;
  final String fit;
  final double? width;
  final String position;
  final String vposition;
}

/// [content] indented by [indents] (left and right) for the width it's
/// given.
final class _Indented implements CustomContent {
  const new(this.content, this.indents);

  final CustomContent content;
  final (double, double) Function(double width) indents;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final (left, right) = indents(width);
    final placed = content.place(width - left - right, available, atTop: atTop);
    if (placed == null) return null;
    return CustomPlacement(
      height: placed.height,
      rest: placed.rest,
      anchors: [for (final (name, x, y) in placed.anchors) (name, x + left, y)],
      paint: (page, x, top) => placed.paint(page, x + left, top),
    );
  }

  @override
  double minHeight(double width) {
    final (left, right) = indents(width);
    return content.minHeight(width - left - right);
  }

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}
