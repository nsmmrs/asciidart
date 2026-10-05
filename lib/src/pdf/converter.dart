/// The PDF backend (`-b pdf`): converts documents as asciidoctor-pdf
/// 2.3.27 does, with its themes, into libpdf boxes laid out on pages. Text
/// is set by a Prawn-compatible text box ([PrawnTextBox]); blocks, page
/// breaks and running content are libpdf's box tree.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/context.dart';
import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/pdf/fonts.dart';
import 'package:asciidart/src/pdf/markup.dart';
import 'package:asciidart/src/pdf/text_box.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:asciidart/src/section.dart';
import 'package:libpdf/libpdf.dart';

/// The NUL character the gem puts in empty anchors (zero width).
const String _dummyText = '\u0000';

/// Page sizes by name, in points (Prawn's table, the common ones).
const Map<String, (double, double)> _pageSizes = {
  'A0': (2383.94, 3370.39),
  'A1': (1683.78, 2383.94),
  'A2': (1190.55, 1683.78),
  'A3': (841.89, 1190.55),
  'A4': (595.28, 841.89),
  'A5': (419.53, 595.28),
  'A6': (297.64, 419.53),
  'B4': (708.66, 1000.63),
  'B5': (498.9, 708.66),
  'LETTER': (612.0, 792.0),
  'LEGAL': (612.0, 1008.0),
  'TABLOID': (792.0, 1224.0),
  'EXECUTIVE': (521.86, 756.0),
  'FOLIO': (612.0, 936.0),
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
  });

  final String family;
  final String style;
  final double size;
  final ThemeColor? color;
  final double lineHeight;
  final bool kerning;
  final String? transform;

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
  );
}

/// The PDF converter.
final class PdfConverter extends BuiltInConverter
    implements PackagingConverter {
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
  late _FontState _font;
  late double _rootFontSize;
  late String _baseTextAlign;
  late List<LayoutBox> _out;
  late Document _document;
  final List<(Section, String)> _sections = [];

  /// The PDF the last converted document made.
  Uint8List? get bytes => _bytes;

  @override
  void write(String path) {
    final bytes = _bytes;
    if (bytes == null) throw StateError('no document converted');
    io.writeBytes(path, bytes);
  }

  @override
  String? convertBlock(AbstractBlock node, ConvertOptions? opts) {
    switch (node) {
      case final Document document:
        convertDocument(document);
      case final Section section:
        convertSection(section);
      case final Block block:
        final context = block.context;
        if (context == BlockContext.paragraph) {
          convertParagraph(block);
        } else if (context == BlockContext.preamble) {
          convertPreamble(block);
        } else if (context == BlockContext.open) {
          _traverse(block);
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
  ThemeColor? _c(String key) => themeColor(_theme.value(key));

  // The document.

  /// Converts [document] to PDF bytes (kept for [write]); returns nothing.
  String convertDocument(Document document) {
    _document = document;
    _theme = _loadTheme(document);
    _fonts = FontCatalog(
      _theme,
      fontsDir: document
          .attr('pdf-fontsdir')
          ?.replaceAll('{docdir}', document.attr('docdir') ?? ''),
    );
    _rootFontSize = (_n('base_font_size') ?? 12).toDouble();
    _text = TextContext(
      fonts: _fonts,
      rootSize: _rootFontSize,
      fallbacks: _theme.fontFallbacks,
      logger: logger,
    );
    _markup = MarkupTransform(_theme);
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
    _out = [];

    // The document title, unless the title is a page of its own.
    final book = document.doctype == 'book';
    final titlePage = book || document.hasAttr('title-page');
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
    _traverse(document);

    final (width, height) = _pageSize(document);
    final margins = _pageMargins(document);
    final template = PageTemplate(
      PdfRect(0, 0, width, height),
      margins: margins,
      footer: _footer,
    );
    final layout = FlowLayout(template: template);
    final result = layout.layout(_out);
    final pdf = PdfDocument(
      info: PdfInfo(
        title: document.doctitle(sanitize: true),
        author: document.attr('authors'),
        subject: document.attr('subject'),
        keywords: document.attr('keywords'),
        creator: document.attr('authors'),
        producer: 'asciidart',
      ),
      pageMode: PageMode.useOutlines,
      displayTitle: true,
      language: document.attr('lang'),
    );
    final pages = result.render(pdf);
    _outline(pdf, pages, result);
    _bytes = pdf.save();
    return '';
  }

  Theme _loadTheme(Document document) {
    final name = document.attr('pdf-theme');
    final dir = document
        .attr('pdf-themesdir')
        ?.replaceAll('{docdir}', document.attr('docdir') ?? '');
    try {
      return ThemeLoader(logger: logger).load(name, dir);
    } on ThemeException catch (error) {
      logger.error(error.message);
      return ThemeLoader(logger: logger).load();
    }
  }

  (double, double) _pageSize(Document document) {
    final value = document.attr('pdf-page-size') ?? _s('page_size') ?? 'A4';
    var (w, h) = _pageSizes[value.toUpperCase()] ?? _pageSizes['A4']!;
    final custom = RegExp(
      r'^\[?\s*([\d.]+(?:in|cm|mm|p[txc])?)\s*,\s*([\d.]+(?:in|cm|mm|p[txc])?)\s*\]?$',
    ).firstMatch(value);
    if (custom != null) {
      w = strToPoints(custom[1]!);
      h = strToPoints(custom[2]!);
    }
    final layout = document.attr('pdf-page-layout') ?? _s('page_layout');
    if (layout == 'landscape') return (math.max(w, h), math.min(w, h));
    return (w, h);
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

  void _traverse(AbstractBlock node) {
    for (final block in node.blocks) {
      block.convert();
    }
  }

  /// The block after [block] in reading order, looking out of the
  /// containers it ends (the gem's `next_enclosed_block`).
  AbstractBlock? _nextEnclosedBlock(AbstractBlock block) {
    if (block is Document) return null;
    final parent = block.parent;
    if (parent is! AbstractBlock) return null;
    final siblings = parent.blocks;
    final index = siblings.indexOf(block);
    if (index >= 0 && index < siblings.length - 1) return siblings[index + 1];
    final parentContext = parent.context;
    if (parentContext == BlockContext.listItem ||
        (parentContext == BlockContext.open && parent.style != 'abstract') ||
        parentContext == BlockContext.section) {
      return _nextEnclosedBlock(parent);
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

  // Sections.

  /// Converts [section]: its heading, then its blocks.
  void convertSection(Section section) {
    final title = _numberedTitle(section);
    final hlevel = (section.level ?? 0) + 1;
    final align =
        _s('heading_h${hlevel}_text_align') ??
        _s('heading_text_align') ??
        _baseTextAlign;
    final anchor = section.id;
    final hidden = section.hasOption('notitle');
    if (!hidden) {
      _heading(
        title,
        level: hlevel,
        align: align,
        anchor: anchor,
        arrange: true,
        hasContent: section.blocks.isNotEmpty,
      );
    }
    if (anchor != null) _sections.add((section, anchor));
    _traverse(section);
  }

  /// The section title as the gem numbers it (`numbered_title formal:
  /// true`).
  String _numberedTitle(Section section) {
    final title = section.title ?? '';
    final level = section.level ?? 0;
    final doc = _document;
    final sectnumlevels = int.tryParse(doc.attr('sectnumlevels') ?? '') ?? 3;
    if (section.numbered && section.caption == null && level <= sectnumlevels) {
      if (doc.doctype == 'book' && level <= 1) {
        final numbered = level == 0
            ? '${section.sectnum('.', ':')} $title'
            : '${section.sectnum()} $title';
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
    String? h(String key) => _s('heading_h${level}_$key') ?? _s('heading_$key');
    final sizeValue =
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
          _c('heading_h${level}_font_color') ??
          _c('heading_font_color') ??
          _font.color,
      lineHeight:
          (_n('heading_h${level}_line_height') ??
                  _n('heading_line_height') ??
                  _font.lineHeight)
              .toDouble(),
      kerning: _font.kerning,
      transform: h('text_transform'),
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
  }) {
    final font = _headingFont(level);
    var text = title;
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform);
    }
    final styles = <String>{
      if (font.style == 'bold' || font.style == 'bold_italic') 'bold',
      if (font.style == 'italic' || font.style == 'bold_italic') 'italic',
    };
    final box = _textBox(text, font, align: align, inheritedStyles: styles);
    final marginTop =
        (_n('heading_h${level}_margin_top') ?? _n('heading_margin_top') ?? 0)
            .toDouble();
    final marginBottom =
        (_n('heading_h${level}_margin_bottom') ??
                _n('heading_margin_bottom') ??
                0)
            .toDouble();
    CustomContent content = box;
    if (arrange) {
      final minAfter = _theme.value('heading_min_height_after');
      var below = switch (minAfter) {
        ThemeNumber(:final value) when hasContent => value.toDouble(),
        _ => 0.0,
      };
      if (below > 0) below += marginBottom;
      content = _NeedsRoom(box, below);
    }
    _out.add(
      CustomBox(
        content,
        style: BoxStyle(
          margin: EdgeInsets(top: marginTop, bottom: marginBottom),
          anchor: anchor,
        ),
      ),
    );
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
    final margin = _themeMargin('block', 'bottom', _nextEnclosedBlock(node));
    if (margin > 0) _out.add(SpacerBox(margin));
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
    );
  }

  // Paragraphs.

  /// Converts the paragraph [node].
  void convertParagraph(Block node) {
    final roles = node.roles;
    var align = _baseTextAlign;
    for (final role in roles) {
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
    var indent = 0.0;
    if (align == 'justify' || align == 'left') {
      final textIndent = (_n('prose_text_indent') ?? 0).toDouble();
      final inner = (_n('prose_text_indent_inner') ?? 0).toDouble();
      if (textIndent > 0) {
        indent = textIndent;
      } else if (inner > 0 &&
          _previousSibling(node)?.context == BlockContext.paragraph) {
        indent = inner;
      }
    }
    final next = _nextEnclosedBlock(node);
    final innerMargin = _n('prose_margin_inner');
    final marginBottom =
        innerMargin != null && next?.context == BlockContext.paragraph
        ? innerMargin.toDouble()
        : _themeMargin('prose', 'bottom', next);
    var font = _font;
    for (final role in roles) {
      font = _themeFont('role_$role', font);
    }
    var content = node.content() ?? '';
    if (font.transform case final transform? when transform != 'none') {
      content = transformText(content, transform);
    }
    final box = _textBox(content, font, align: align, indent: indent);
    _out.add(
      CustomBox(
        box,
        style: BoxStyle(
          margin: EdgeInsets(bottom: marginBottom),
          anchor: node.id,
        ),
      ),
    );
  }

  AbstractBlock? _previousSibling(AbstractBlock node) {
    final parent = node.parent;
    if (parent is! AbstractBlock) return null;
    final index = parent.blocks.indexOf(node);
    return index > 0 ? parent.blocks[index - 1] : null;
  }

  // Text.

  /// A text box of [markup] in [font] (the gem's `typeset_text` with the
  /// line metrics of the font's line height).
  PrawnTextBox _textBox(
    String markup,
    _FontState font, {
    required String align,
    double indent = 0,
    Set<String> inheritedStyles = const {},
    bool normalize = true,
  }) {
    var text = markup;
    if (normalize) text = text.replaceAll(RegExp('[ \t\n]+'), ' ');
    final nodes = parseMarkup(text);
    final List<Fragment> fragments;
    final inherited = inheritedStyles.isEmpty
        ? null
        : (Fragment('')
            ..styles = {
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
    return PrawnTextBox(
      fragments,
      TextState(
        family: font.family,
        style: font.style,
        size: font.size,
        color: font.color,
        kerning: font.kerning,
      ),
      TextLayout(
        align: align,
        leading: metrics.leading,
        initialGap: metrics.paddingTop,
        paddingBottom: metrics.paddingBottom,
        indentFirstLine: indent,
      ),
      _text,
    );
  }

  /// The gem's `calc_line_metrics`: the leading of the line height, half
  /// of it above the text (plus the font's line gap) and half below.
  ({double leading, double paddingTop, double paddingBottom}) _lineMetrics(
    _FontState font,
  ) {
    final prawnFont = _fonts.font(font.family, font.style);
    final leading = font.lineHeight * font.size - font.size;
    return (
      leading: leading,
      paddingTop: leading / 2 + prawnFont.lineGapAt(font.size),
      paddingBottom: leading / 2,
    );
  }

  // Running content.

  List<LayoutBox> _footer(PageInfo page) {
    final side = page.number.isOdd ? 'recto' : 'verso';
    final height = (_n('footer_height') ?? 0).toDouble();
    if (height == 0) return const [];
    final columns = <(String, String)>[
      for (final position in ['left', 'center', 'right'])
        if (_s('footer_${side}_${position}_content') case final content?)
          (position, content),
    ];
    if (columns.isEmpty) return const [];
    final size = (_n('footer_font_size') ?? _rootFontSize).toDouble();
    final font = _font.copyWith(
      size: size,
      color: _c('footer_font_color') ?? _font.color,
      lineHeight: (_n('footer_line_height') ?? 1).toDouble(),
    );
    final padding = _edgeValues(_theme.value('footer_padding'));
    final boxes = <LayoutBox>[];
    for (final (position, content) in columns) {
      final text = content
          .replaceAll('{page-number}', page.label)
          .replaceAll('{page-count}', '${page.count}');
      boxes.add(
        CustomBox(
          _textBox(text, font, align: position),
          style: BoxStyle(
            margin: EdgeInsets(left: padding[3], right: padding[1]),
          ),
        ),
      );
    }
    final margins = _pageMargins(_document);
    return [
      SpacerBox(margins.bottom - height + padding[0]),
      ColumnsBox(boxes, count: 1, gap: 0),
    ];
  }

  // The outline.

  /// The outline (the document title, then the sections to
  /// `outlinelevels`) and the page labels (the gem's `add_outline`).
  void _outline(PdfDocument pdf, List<PdfPage> pages, LayoutResult result) {
    const frontMatter = 0;
    for (var n = 0; n < pages.length; n++) {
      pdf.labelPages(
        n,
        PageLabel(
          style: PageNumberStyle.none,
          prefix: n < frontMatter ? _roman(n + 1) : '${n - frontMatter + 1}',
        ),
      );
    }
    if (!_document.hasAttr('outline') && !_outlineDefault) return;
    var levels = int.tryParse(_document.attr('toclevels') ?? '') ?? 2;
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

    if (pages.isNotEmpty) {
      var title = _document.attr('outline-title') ?? '';
      if (title.isEmpty) title = _document.doctitle(sanitize: true) ?? '';
      if (title.isNotEmpty) {
        pdf.addOutline(
          _plain(title),
          LinkTarget.destination(
            PdfDestination.xyz(pages.first, left: 0, top: pages.first.height),
          ),
        );
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
        final title = _plain(_numberedTitle(section));
        if (title.isEmpty) continue;
        final target = switch (destination(section)) {
          final d? => LinkTarget.destination(d),
          null => null,
        };
        final children = section.sections.whereType<Section>().toList();
        final open = depth < sectionLevels && children.isNotEmpty;
        final item = parent == null
            ? pdf.addOutline(title, target, open: open && expand >= 1)
            : parent.add(title, target, open: open && expand >= 1);
        if (open) level(children, sectionLevels, expand - 1, item);
      }
    }

    level(
      _document.sections.whereType<Section>().toList(),
      levels,
      expand,
      null,
    );
  }

  /// Whether the outline is on when the document doesn't say (it is).
  bool get _outlineDefault => true;

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

  /// [markup] as plain text (tags dropped, references resolved).
  String _plain(String markup) {
    final nodes = parseMarkup(markup);
    if (nodes == null) return markup;
    return _markup.apply(nodes).map((f) => f.text).join();
  }

  // Inline elements.

  @override
  String? convertInline(Inline node) => switch (node.context) {
    InlineContext.anchor => _inlineAnchor(node),
    InlineContext.lineBreak => '${node.text ?? ''}<br>',
    InlineContext.button =>
      '<button>${(_s('button_content') ?? '%s').replaceFirst('%s', node.text ?? '')}</button>',
    InlineContext.callout => node.text ?? '',
    InlineContext.footnote => _inlineFootnote(node),
    InlineContext.image => '[${node.alt}&#93;',
    InlineContext.indexterm => node.type == 'visible' ? node.text ?? '' : '',
    InlineContext.kbd => _inlineKbd(node),
    InlineContext.menu => _inlineMenu(node),
    InlineContext.quoted => _inlineQuoted(node),
  };

  String _inlineAnchor(Inline node) {
    final target = node.target ?? '';
    switch (node.type) {
      case 'link':
        final anchor = node.id != null
            ? '<a id="${node.id}">$_dummyText</a>'
            : '';
        final role = node.role;
        final classAttr = role != null ? ' class="$role"' : '';
        return '$anchor<a href="$target"$classAttr>${node.text ?? ''}</a>';
      case 'xref':
        if (node.attributes['path'] case final path?) {
          return '<a href="$target">${node.text ?? path}</a>';
        }
        if (node.attributes['refid'] case final refid?) {
          var text = node.text;
          if (text == null) {
            text = switch (_document.catalog.refs[refid]) {
              final AbstractBlock block => block.xreftext(
                node.attr('xrefstyle'),
              ),
              final Inline inline => inline.xreftext(node.attr('xrefstyle')),
              _ => null,
            };
            if (text != null && text.contains('<a')) {
              text = text.replaceAll(RegExp(r'<(?:a\b[^>]*|/a)>'), '');
            }
          }
          return '<a anchor="$refid">${text ?? '[$refid]'}</a>'.replaceAll(
            ']',
            '&#93;',
          );
        }
        return '<a anchor="${_document.attr('pdf-anchor') ?? ''}">'
            '${node.text ?? '[^top&#93;'}</a>';
      case 'ref':
        return '<a id="${node.id}">$_dummyText</a>';
      case 'bibref':
        final id = node.id;
        final reftext = '[${node.reftext ?? id}]';
        return '<a id="$id">$_dummyText</a>$reftext';
      default:
        logger.warn('unknown anchor type: ${node.type}');
        return '';
    }
  }

  String _inlineFootnote(Inline node) {
    final index = node.attr('index');
    if (index != null) {
      final anchor = node.type == 'xref'
          ? ''
          : '<a id="_footnoteref_$index">$_dummyText</a>';
      return '<sup class="wj">$anchor[<a anchor="_footnotedef_$index">$index</a>]</sup>';
    }
    return '<sup class="wj">[${node.text ?? ''}]</sup>';
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
    switch (node.type) {
      case 'emphasis':
        (open, close) = ('<em>', '</em>');
      case 'strong':
        (open, close) = ('<strong>', '</strong>');
      case 'monospaced' || 'asciimath' || 'latexmath':
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
