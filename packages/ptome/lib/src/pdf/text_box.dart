/// Text laid out as Prawn 2.4 lays it out, with asciidoctor-pdf 2.3.27's
/// extensions: fragments wrapped line by line (Prawn's `LineWrap`, with
/// word joiners), each line as tall as its tallest fragment, baselines
/// placed with the leading and the gaps asciidoctor-pdf passes,
/// justification by word spacing, font fallback per glyph. A
/// [TextBox] is libpdf custom content: the layout gives it the room
/// left on the page and it places the lines that fit.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:libpdf/libpdf.dart';
import 'package:meta/meta.dart';
import 'package:ptome/src/cursor.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/markup.dart';
import 'package:ptome/src/pdf/math.dart';
import 'package:ptome/src/pdf/svg_size.dart';
import 'package:ptome/src/pdf/theme.dart';

const String _zwsp = '​';
const String _shy = '­';
const String _nul = '\u0000';

/// The font state text starts from (Prawn's current font, size and
/// color, as `theme_font` sets them).
final class TextState {
  /// The state of [family] in [style] at [size] points, in [color].
  const new({
    required this.family,
    required this.size,
    this.style = 'normal',
    this.color,
    this.kerning = true,
    this.characterSpacing = 0,
    this.features = const {},
  });

  /// The OpenType features the text is set with (the modern engine's:
  /// `onum` for old-style numerals...).
  final Set<String> features;

  /// The space added between characters (Prawn's `character_spacing`).
  final double characterSpacing;

  /// The font family.
  final String family;

  /// The font style.
  final String style;

  /// The size, in points.
  final double size;

  /// The default color of the fragments.
  final ThemeColor? color;

  /// Whether text is kerned.
  final bool kerning;
}

/// How a block of text is laid out (the options asciidoctor-pdf passes to
/// Prawn's `text`).
final class TextLayout {
  /// Text aligned by [align], lines [leading] apart, the first line
  /// [initialGap] below the top, [paddingBottom] below the last line.
  const new({
    this.align = 'left',
    this.leading = 0,
    this.initialGap = 0,
    this.paddingBottom = 0,
    this.finalGap = false,
    this.trailingLineGap = false,
    this.singleLine = false,
    this.shrinkToFit = false,
    this.indentFirstLine = 0,
    this.normalizeLineHeight = false,
    this.forceJustify = false,
    this.orphans = 1,
    this.widows = 1,
    this.wrapIndent,
    this.wrapMarker = false,
    this.at,
    this.skew,
    this.overhang = 0,
    this.capLines = false,
    this.justifyWidest = false,
    this.alignLast,
  });

  /// Where a justified paragraph's lines that aren't justified (its last
  /// line) go: `center` or `right`, as CSS's `text-align-last` (Typst's
  /// alignment of a justified paragraph); left when null.
  final String? alignLast;

  /// Whether justified lines are set to the width of the paragraph's
  /// widest line (overfull lines shrunk to the room) rather than to the
  /// room, as Typst sets a paragraph in a block sized to its content (its
  /// pages' `show par: it => block(it)` rule).
  final bool justifyWidest;

  /// Typst's lines: each line's box from its tallest cap height to its
  /// baseline ([leading] is the space between boxes), the first line's
  /// cap height at the top and the last ending at its baseline.
  final bool capLines;

  /// How far punctuation and dashes at a line's end hang into the margin:
  /// a factor of the fraction of each character's width the line may
  /// stretch into (0, none; 1, Typst's `overhang` amounts).
  final double overhang;

  /// The text sheared as one block about its last baseline (Typst's skew
  /// of a heading): each glyph slanted by this ratio (the tangent of the
  /// angle, positive leaning right), each line shifted right by it times
  /// its height above the last line's baseline.
  final double? skew;

  /// `left`, `center`, `right` or `justify`.
  final String align;

  /// The extra space between lines.
  final double leading;

  /// The space above the first line of each piece.
  final double initialGap;

  /// The space below the last line.
  final double paddingBottom;

  /// Whether the line gap and the leading follow the last line too.
  final bool finalGap;

  /// Whether the line gap alone follows the last line (as prawn-table
  /// measures a cell's text).
  final bool trailingLineGap;

  /// Whether only the first line is laid out (the rest is left over, the
  /// line gap and the leading following the line).
  final bool singleLine;

  /// Whether the font size shrinks (half a point at a time, to 5) until
  /// all the text fits (Prawn's `overflow: :shrink_to_fit`).
  final bool shrinkToFit;

  /// The indent of the first line.
  final double indentFirstLine;

  /// This layout with no gap above the first line.
  TextLayout get withoutInitialGap => TextLayout(
    align: align,
    leading: leading,
    paddingBottom: paddingBottom,
    finalGap: finalGap,
    trailingLineGap: trailingLineGap,
    singleLine: singleLine,
    shrinkToFit: shrinkToFit,
    indentFirstLine: indentFirstLine,
    normalizeLineHeight: normalizeLineHeight,
    forceJustify: forceJustify,
    orphans: orphans,
    widows: widows,
  );

  /// Whether each line is at least as tall as the base font.
  final bool normalizeLineHeight;

  /// Whether the last line is justified too.
  final bool forceJustify;

  /// The fewest lines the text leaves at the bottom of a region when it
  /// goes on in the next (1: no rule).
  final int orphans;

  /// The fewest lines the text takes to the top of the next region when
  /// it goes on there (1: no rule).
  final int widows;

  /// How far past a line's own indentation the lines it wraps onto start
  /// (a hanging indent for code), or null to start them at the left.
  final double? wrapIndent;

  /// Whether a line that wraps is marked with a return arrow past its
  /// end (for code).
  final bool wrapMarker;

  /// Where the text's block starts in the source, for messages.
  final Cursor? at;
}

/// What the text needs from the conversion: fonts, the root font size,
/// fallback fonts, and where messages go.
final class TextContext {
  /// A context.
  new({
    required this.fonts,
    required this.rootSize,
    this.fallbacks = const [],
    this.images,
    this.boundsHeight = double.infinity,
    this.decorationWidth = 1,
    this.lineBreaking = LineBreaking.auto,
    this.typographicScripts = false,
    this.labels,
    LoggerBase? logger,
  }) : logger = logger ?? LoggerManager.logger;

  /// Whether the modern engine sets superscripts and subscripts in the
  /// font's own glyphs for them (its `sups` and `subs` features) at the
  /// text's size, when it has them for every character (as Typst's
  /// `super` and `sub` do), rather than smaller and shifted.
  final bool typographicScripts;

  /// The text of the label of a fragment's key ([Fragment.label]), as the
  /// layout has it now (null keeps the fragment's text).
  final String? Function(String key)? labels;

  /// Reads the inline image at a path in a format, or returns null (with
  /// the reason) when it can't.
  final (Graphic?, String?) Function(String path, String? format)? images;

  /// The height of the content area (the most an inline image may be).
  final double boundsHeight;

  /// The width of underlines and strike-throughs that don't set one (the
  /// theme's `base_text_decoration_width`).
  final double decorationWidth;

  /// How the modern engine breaks lines.
  final LineBreaking lineBreaking;

  /// The fonts.
  final FontCatalog fonts;

  /// The root font size (`rem`).
  final double rootSize;

  /// The fallback font families.
  final List<String> fallbacks;

  /// Where warnings go.
  final LoggerBase logger;

  final Map<int, bool> _warnedMissing = {};
}

/// A fragment ready to wrap: its text and its resolved formatting.
final class _Item {
  new(this.text, this.format, {this.defaultColor = false});

  String text;
  final _Format format;

  /// Whether the fragment's color is the text's (not its own).
  final bool defaultColor;
  bool excludeTrailingWhiteSpace = false;
  bool normalizedSoftHyphen = false;

  _Item copy({String? text}) =>
      _Item(text ?? this.text, format, defaultColor: defaultColor)
        ..excludeTrailingWhiteSpace = excludeTrailingWhiteSpace
        ..normalizedSoftHyphen = normalizedSoftHyphen;
}

/// A fragment's formatting with its font resolved.
final class _Format {
  new(
    this.fragment,
    this.font,
    this.size, {
    this.image,
    this.features = const {},
    this.smallCapitals = false,
    this.typographic = false,
  });

  final Fragment fragment;
  final FontFace font;
  final double size;

  /// Whether a superscript or subscript is set in the font's glyphs for
  /// it (on the baseline, at the text's size).
  final bool typographic;

  /// The OpenType features the text is set with.
  final Set<String> features;

  /// Whether the text is set in capitals, smaller, for small capitals the
  /// font lacks.
  final bool smallCapitals;

  /// The inline image the fragment is, once arranged.
  final _Image? image;

  bool get subscript =>
      fragment.styles?.contains(FragmentStyle.subscript) ?? false;
  bool get superscript =>
      fragment.styles?.contains(FragmentStyle.superscript) ?? false;
}

/// An inline image arranged on a line: the room it takes, the size it is
/// drawn at, and the metrics it gives its line.
final class _Image {
  const new(
    this.graphic, {
    required this.width,
    required this.height,
    required this.drawWidth,
    required this.drawHeight,
    this.ascender,
    this.descender,
    this.lineHeightIncreased = false,
    this.mathDepth,
  });

  final Graphic graphic;
  final double width;
  final double height;
  final double drawWidth;
  final double drawHeight;
  final double? ascender;
  final double? descender;
  final bool lineHeightIncreased;

  /// A formula's depth below the baseline (it stands on the baseline).
  final double? mathDepth;
}

/// A fragment as printed on a line.
final class _Printed {
  new(this.text, this.format, this.width, this.wordSpacing, this.spaces);

  String text;
  final _Format format;
  double width;
  final double wordSpacing;
  final int spaces;
  double left = 0;
  double baseline = 0;

  double get ascender => format.fragment.isMarker
      ? 0
      : format.image?.ascender ?? format.font.ascenderAt(format.size);
  double get descender =>
      format.image?.descender ?? format.font.descenderAt(format.size);
  double get yOffset => format.typographic
      ? 0
      : format.subscript
      ? -descender
      : format.superscript
      ? 0.85 * ascender
      : 0;
}

/// A line placed in a piece: its fragments, positioned (x from the left
/// edge, baseline down from the piece's top).
final class _Line {
  new(this.fragments);

  final List<_Printed> fragments;

  /// Whether the line wraps: the text of its line goes on in the next.
  bool wrapped = false;
}

/// Text laid out in lines (Typst's line breaking, or for code one line at
/// a time with a hanging indent), as libpdf custom content.
final class TextBox implements CustomContent {
  /// The text of [fragments] (from the markup) starting from [state],
  /// laid out by [layout].
  factory(
    List<Fragment> fragments,
    TextState state,
    TextLayout layout,
    TextContext context,
  ) {
    final items = <_Item>[];
    for (final fragment in fragments) {
      final defaultColor = fragment.color == null;
      final copy = fragment.copy()..color ??= state.color;
      for (final run in _withFallbacks(copy, state, context)) {
        final format = _resolve(run, state, context);
        var text = format.font.normalize(run.text);
        if (format.smallCapitals) text = text.toUpperCase();
        // One item per line of the fragment (Prawn's `format_array=`).
        for (final m in _linesRx.allMatches(text)) {
          items.add(_Item(m[0]!, format, defaultColor: defaultColor));
        }
      }
    }
    return TextBox._(items, state, layout, context, first: true);
  }

  new _(
    this._items,
    this._state,
    this._layout,
    this._context, {
    required this.first,
    this.continuedIndent,
  });

  final List<_Item> _items;
  final TextState _state;
  final TextLayout _layout;
  final TextContext _context;

  /// The text's style.
  TextState get state => _state;

  /// The text's layout.
  TextLayout get layout => _layout;

  /// Whether this is the first piece of the text (its first line is
  /// indented).
  final bool first;

  /// The indent of the first line when it goes on with a line that
  /// wrapped at the end of the text before (see [TextLayout.wrapIndent]).
  final double? continuedIndent;

  /// Whether there is no text.
  bool get isEmpty => _items.isEmpty;

  /// This (left over) text in [state] and laid out by [layout] (the rest
  /// of a first line set in another style).
  TextBox restyled(TextState state, TextLayout layout) => TextBox._(
    [
      for (final item in _items)
        () {
          final fragment = item.format.fragment.copy();
          if (item.defaultColor) fragment.color = state.color;
          return _Item(
            item.text,
            item.format.image == null
                ? _resolve(fragment, state, _context)
                : item.format,
            defaultColor: item.defaultColor,
          );
        }(),
    ],
    state,
    layout,
    _context,
    first: false,
  );

  /// The format of [fragment] in [state]: its font and size, and in the
  /// modern engine its OpenType features (small capitals the font lacks
  /// set as smaller capitals).
  static _Format _resolve(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    final format = _resolveStyle(fragment, state, context);
    if (context.typographicScripts &&
        (format.superscript || format.subscript)) {
      if (_typographic(format, format.superscript ? 'sups' : 'subs')
          case final typographic?) {
        return typographic;
      }
    }
    final features = {...state.features, ...?fragment.features};
    if (features.isEmpty || format.image != null) return format;
    final font = format.font;
    final hasSmcp = font is TrueTypeFont && font.pdf.font.hasFeature('smcp');
    final fake = features.contains('smcp') && !hasSmcp;
    if (fake) features.remove('smcp');
    return _Format(
      fragment,
      font,
      fake ? format.size * 0.8 : format.size,
      features: features,
      smallCapitals: fake,
    );
  }

  /// [format], a superscript or subscript, in its font's glyphs for it
  /// ([feature]) at the size around it, when the font has one for each
  /// character; else null.
  static _Format? _typographic(_Format format, String feature) {
    final font = format.font;
    if (font is! TrueTypeFont || format.image != null) return null;
    final open = font.pdf.font;
    final substitutions = open.singleSubstitutions(feature);
    if (substitutions.isEmpty) return null;
    for (final rune in format.fragment.text.runes) {
      if (!substitutions.containsKey(open.glyphFor(rune))) return null;
    }
    return _Format(
      format.fragment,
      font,
      format.size / _scriptScale,
      features: {feature},
      typographic: true,
    );
  }

  /// How much smaller a superscript or subscript is set than its text.
  static const _scriptScale = 0.583;

  static _Format _resolveStyle(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    final styles = fragment.styles ?? const {};
    var bold = styles.contains(FragmentStyle.bold);
    var italic = styles.contains(FragmentStyle.italic);
    if (styles.contains(FragmentStyle.emphasis)) {
      // Against its surroundings: the fragment's other styles and the
      // state's.
      bold = bold || state.style.contains('bold');
      italic = !(italic || state.style.contains('italic'));
      final style = bold && italic
          ? 'bold_italic'
          : bold
          ? 'bold'
          : italic
          ? 'italic'
          : 'normal';
      return _Format(
        fragment,
        _font(fragment.font ?? state.family, style, context),
        _sizeOf(fragment, styles, state, context),
      );
    }
    final style = bold && italic
        ? 'bold_italic'
        : bold
        ? 'bold'
        : italic
        ? 'italic'
        : 'normal';
    final FontFace font;
    if (fragment.font != null || style != 'normal') {
      font = _font(fragment.font ?? state.family, style, context);
    } else {
      font = _font(state.family, state.style, context);
    }
    return _Format(fragment, font, _sizeOf(fragment, styles, state, context));
  }

  static double _sizeOf(
    Fragment fragment,
    Set<FragmentStyle> styles,
    TextState state,
    TextContext context,
  ) {
    var size = switch (fragment.size) {
      null => state.size,
      final s => resolveFontSize(s, state.size, context.rootSize),
    };
    if (styles.contains(FragmentStyle.subscript) ||
        styles.contains(FragmentStyle.superscript)) {
      size *= _scriptScale;
    }
    return size;
  }

  static FontFace _font(String family, String style, TextContext context) {
    try {
      return context.fonts.font(family, style);
    } on FontException {
      return context.fonts.font(family);
    }
  }

  /// [fragment] split where its font lacks glyphs a fallback font has
  /// (the gem's `analyze_glyphs_for_fallback_font_support`).
  static List<Fragment> _withFallbacks(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    if (context.fallbacks.isEmpty || fragment.imagePath != null) {
      return [fragment];
    }
    final base = _resolve(fragment, state, context).font;
    final runs = <Fragment>[];
    String? currentFamily;
    final text = StringBuffer();
    var first = true;
    void flush() {
      if (text.isEmpty && !first) return;
      runs.add(
        fragment.copy(text: text.toString())
          ..font = currentFamily ?? fragment.font,
      );
      text.clear();
    }

    for (final rune in fragment.text.runes) {
      String? family;
      if (rune != 0 && !base.hasGlyph(rune) && rune != 10) {
        for (final fallback in context.fallbacks) {
          if (_font(fallback, base.style, context).hasGlyph(rune)) {
            family = fallback;
            break;
          }
        }
        if (family == null && context._warnedMissing[rune] == null) {
          context._warnedMissing[rune] = true;
          context.logger.warn(
            "Could not locate the character `${String.fromCharCode(rune)}' "
            '(\\u${rune.toRadixString(16).padLeft(4, '0')}) in the following '
            'fonts: ${[base.family, ...context.fallbacks].join(', ')}',
          );
        }
      }
      if (!first && family != currentFamily) flush();
      first = false;
      currentFamily = family;
      text.writeCharCode(rune);
    }
    flush();
    return runs.isEmpty ? [fragment] : runs;
  }

  @override
  double minHeight(double width) {
    // The modern engine needs room for the lines the text may leave at
    // the bottom of a region (its orphans), not for all of it; all of a
    // text too short to split (fewer lines than its orphans and widows).
    if (_items.isNotEmpty) {
      _arrangeImages(width);
      // (The same for the same width and labels: kept.)
      final key = (width, _labelState());
      if (_minHeights[key] case final height?) return height;
      return _minHeights[key] = _minHeight(width);
    }
    final placed = place(width, double.infinity, atTop: true);
    if (placed == null) return 0;
    return placed.height;
  }

  final Map<(double, String), double> _minHeights = {};
  final Map<(double, String), int> _lineCounts = {};

  /// The texts of the items whose text is a label (after [_relabel]): what
  /// a layout of the same items at the same width may differ by.
  String _labelState() => _context.labels == null
      ? ''
      : [
          for (final item in _items)
            if (item.format.fragment.label != null) item.text,
        ].join('\u0000');

  /// The least height [minHeight] computes (not kept).
  double _minHeight(double width) {
    _Wrap wrapped(int maxLines) => _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
      continuedIndent: continuedIndent,
      maxLines: maxLines,
    );
    final orphans = math.max(1, _layout.orphans);
    final unsplit = math.max(orphans, orphans + _layout.widows - 1);
    final whole = wrapped(unsplit);
    if (whole.run().isEmpty) return 0;
    if (whole.unconsumed.isEmpty || unsplit == orphans) {
      return _layout.initialGap + whole.height;
    }
    final wrap = wrapped(orphans)..run();
    return _layout.initialGap + wrap.height;
  }

  /// The items whose text is a label the layout gives ([Fragment.label]):
  /// their text as it is now.
  void _relabel() {
    final labels = _context.labels;
    if (labels == null) return;
    for (final item in _items) {
      if (item.format.fragment.label case final key?) {
        if (labels(key) case final text?) item.text = text;
      }
    }
  }

  @override
  (double, double) intrinsicWidths() {
    _relabel();
    // The widest unbreakable segment, and the widest line unwrapped.
    var least = 0.0;
    var most = 0.0;
    var line = 0.0;
    for (final item in _items) {
      if (item.text == '\n') {
        most = math.max(most, line);
        line = 0;
        continue;
      }
      // An inline image not yet arranged: as wide as it asks to be (as
      // prawn-table measures a cell), not its placeholder text.
      final image = item.format.image == null
          ? _naturalImageWidth(item.format.fragment.imageWidth)
          : null;
      if (image != null) {
        least = math.max(least, image);
        line += image;
        continue;
      }
      final font = item.format.font;
      final size = item.format.size;
      for (final segment in _tokenize(item.text)) {
        final width = font.widthOf(
          segment,
          size,
          kerning: _state.kerning,
          features: item.format.features,
        );
        if (_strip(segment).isNotEmpty) least = math.max(least, width);
        line += width;
      }
    }
    return (least, math.max(most, line));
  }

  /// The width an inline image of width [spec] (a fragment's: points,
  /// or in a table cell a percentage and its intrinsic width,
  /// `25%153.0`) asks of its column: the points, or the intrinsic width
  /// (the percentage is of the column, as prawn-table measures it); null
  /// for no image or a width relative to the room alone.
  static double? _naturalImageWidth(String? spec) {
    if (spec == null) return null;
    final pct = spec.indexOf('%');
    if (pct < 0) return double.tryParse(spec);
    return double.tryParse(spec.substring(pct + 1));
  }

  bool _imagesArranged = false;

  /// Sizes the inline images for [width] points of room, once (the gem's
  /// `InlineImageArranger`): each becomes a placeholder as wide as the
  /// image, raising its line when the image is taller than the text.
  void _arrangeImages(double width) {
    _relabel();
    if (_imagesArranged) return;
    _imagesArranged = true;
    final images = _context.images;
    if (images == null) return;
    int? last;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final fragment = item.format.fragment;
      final path = fragment.imagePath;
      if (path == null || item.format.image != null) continue;
      final id = fragment.objectId;
      if (id != null && id == last) {
        _items.removeAt(i--);
        continue;
      }
      last = id;
      final (graphic, problem) = images(path, fragment.imageFormat);
      if (graphic == null) {
        _context.logger.warn('could not embed image: $path; $problem');
        continue;
      }
      _items[i] = _arrangeImage(item, graphic, width);
    }
  }

  _Item _arrangeImage(_Item item, Graphic graphic, double available) {
    final fragment = item.format.fragment;
    // A formula: at the text's size, its depth below the baseline, the
    // line as tall as it needs.
    if (graphic case final InlineMath formula) {
      final box = formula.at(item.format.size);
      final lineFont = TextBox._font(_state.family, _state.style, _context);
      return _Item(
        '\u2063',
        _Format(
          fragment,
          item.format.font,
          item.format.size,
          image: _Image(
            graphic,
            width: box.width,
            height: box.height + box.depth,
            drawWidth: box.width,
            drawHeight: box.height + box.depth,
            ascender: math.max(box.height, lineFont.ascenderAt(_state.size)),
            descender: math.max(box.depth, lineFont.descenderAt(_state.size)),
            mathDepth: box.depth,
          ),
        ),
      );
    }
    final spec = fragment.imageWidth ?? '100%';
    double? width;
    double? scale;
    if (spec == 'auto') {
      width = null;
    } else if (spec.startsWith('auto*')) {
      scale = _Wrap._toF(spec.substring(5));
    } else {
      final pct = spec.indexOf('%');
      if (pct >= 0 && pct + 1 < spec.length) {
        width = math.min(
          available,
          _Wrap._toF(spec.substring(0, pct)) /
              100 *
              _Wrap._toF(spec.substring(pct + 1)),
        );
      } else {
        width = math.min(
          available,
          pct >= 0 ? _Wrap._toF(spec) / 100 * available : _Wrap._toF(spec),
        );
      }
    }
    final lineFont = TextBox._font(_state.family, _state.style, _context);
    final lineHeight = lineFont.heightAt(_state.size);
    final boundsHeight = _context.boundsHeight;
    final maxHeight = switch (fragment.imageFit) {
      'line' => math.min(boundsHeight, lineHeight),
      _ => boundsHeight,
    };
    double height;
    double drawWidth;
    double drawHeight;
    if (graphic case final SvgImage svg) {
      var (w, h) = prawnSvgSize(svg, width, null, available, boundsHeight);
      if (h > maxHeight) {
        (w, h) = prawnSvgSize(svg, null, maxHeight, available, boundsHeight);
        width = w;
      } else if (width != null) {
        width = w;
      } else {
        width = w * (scale ?? 1);
        if (width > available) width = available;
      }
      (drawWidth, drawHeight, height) = (w, h, h);
    } else {
      final ratio = graphic.intrinsicHeight / graphic.intrinsicWidth;
      if (width == null) {
        width = graphic.intrinsicWidth * 0.75 * (scale ?? 1);
        if (width > available) width = available;
      }
      height = width * ratio;
      if (height > maxHeight) {
        height = maxHeight;
        width = height / ratio;
      }
      (drawWidth, drawHeight) = (width, height);
    }
    double? ascender;
    double? descender;
    var size = item.format.size;
    var increased = false;
    if (height > lineHeight * 1.5) {
      descender = lineFont.descenderAt(_state.size);
      ascender = height - descender;
      if (height == boundsHeight) {
        ascender -= _layout.leading / 2 + lineFont.lineGapAt(_state.size);
      }
      size = height * (_state.size / lineHeight);
      increased = true;
    }
    return _Item(
      '\u2063',
      _Format(
        fragment,
        item.format.font,
        size,
        image: _Image(
          graphic,
          width: width,
          height: height,
          drawWidth: drawWidth,
          drawHeight: drawHeight,
          ascender: ascender,
          descender: descender,
          lineHeightIncreased: increased,
        ),
      ),
    );
  }

  /// The right edge and the top of the last fragment of the text laid
  /// out [width] wide, relative to the box's left and top, with the top
  /// of its first line; null for no text.
  ({double right, double top, double firstTop})? lastFragment(double width) {
    if (_items.isEmpty) return null;
    _arrangeImages(width);
    final gap = _layout.initialGap;
    final lines = _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
      continuedIndent: continuedIndent,
    ).run();
    final printed = [
      for (final line in lines)
        for (final f in line.fragments)
          if (!f.format.fragment.isMarker) f,
    ];
    if (printed.isEmpty) return null;
    final last = printed.last;
    final head = printed.first;
    return (
      right: last.left + last.width,
      top: gap + last.baseline - last.ascender,
      firstTop: gap + head.baseline - head.ascender,
    );
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!_layout.shrinkToFit) return _place(width, available, atTop: atTop);
    var box = this;
    var size = _state.size;
    while (true) {
      final last = size <= 5;
      final placed = box._place(width, available, atTop: atTop, quiet: !last);
      if (last || (placed != null && placed.rest == null)) return placed;
      size = math.max(size - 0.5, 5);
      box = box.resized(size);
    }
  }

  /// This text at font [size] (the fragments of their own size keep it;
  /// the layout, its leading included, stays as it is).
  TextBox resized(double size) {
    final state = TextState(
      family: _state.family,
      size: size,
      style: _state.style,
      color: _state.color,
      kerning: _state.kerning,
      characterSpacing: _state.characterSpacing,
      features: _state.features,
    );
    return TextBox._(
      [
        for (final item in _items)
          _Item(
            item.text,
            item.format.image == null
                ? _resolve(item.format.fragment, state, _context)
                : item.format,
            defaultColor: item.defaultColor,
          ),
      ],
      state,
      _layout,
      _context,
      first: first,
    );
  }

  /// The fragments of the first line of the text laid out [width] wide,
  /// and the text left over (null when it all fits on the line).
  (List<Fragment>, TextBox?) splitFirstLine(double width) {
    _arrangeImages(width);
    final wrap = _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
      continuedIndent: continuedIndent,
    );
    final lines = wrap.run();
    final fragments = [
      if (lines.isNotEmpty)
        for (final printed in lines.first.fragments)
          printed.format.fragment.copy(text: printed.text),
    ];
    final rest = wrap.unconsumed;
    return (
      fragments,
      rest.isEmpty
          ? null
          : TextBox._(
              rest,
              _state,
              _layout,
              _context,
              first: false,
              continuedIndent: wrap.continuedIndent,
            ),
    );
  }

  CustomPlacement? _place(
    double width,
    double available, {
    required bool atTop,
    bool quiet = false,
  }) {
    if (_items.isEmpty) {
      return CustomPlacement(
        height: _layout.paddingBottom,
        paint: (page, x, top) {},
      );
    }
    _arrangeImages(width);
    final gap = _layout.initialGap;
    var wrap = _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      available - gap,
      firstPiece: first,
      continuedIndent: continuedIndent,
    );
    var lines = wrap.run();
    // Widows and orphans: split no fewer than `orphans` lines here and
    // `widows` there, else fewer lines here, or none.
    if (lines.isNotEmpty &&
        wrap.unconsumed.isNotEmpty &&
        (_layout.orphans > 1 || _layout.widows > 1)) {
      final total = _lineCounts[(width, _labelState())] ??= _wrapOf(
        [for (final item in _items) item.copy()],
        _state,
        _layout,
        _context,
        width,
        double.infinity,
        firstPiece: first,
        continuedIndent: continuedIndent,
      ).run().length;
      final remaining = total - lines.length;
      var keep = lines.length;
      if (remaining < _layout.widows) keep -= _layout.widows - remaining;
      if (keep < _layout.orphans) {
        if (!atTop) return null;
        keep = lines.length;
      }
      if (keep != lines.length) {
        wrap = _wrapOf(
          [for (final item in _items) item.copy()],
          _state,
          _layout,
          _context,
          width,
          available - gap,
          firstPiece: first,
          continuedIndent: continuedIndent,
          maxLines: keep,
        );
        lines = wrap.run();
      }
    }
    if (lines.isEmpty) {
      if (!atTop || quiet) return null;
      // Nothing fits even on a fresh page: the gem reports it and drops
      // the text.
      _context.logger.error(
        'cannot fit formatted text on page: '
        '${_items.map((i) => i.text).join()}',
        at: _layout.at,
      );
      return CustomPlacement(height: 0, paint: (page, x, top) {});
    }
    final rest = wrap.unconsumed;
    final done = rest.isEmpty;
    var height = gap + wrap.height;
    if (_layout.finalGap || (_layout.singleLine && !done)) {
      height += wrap.lineGap + _layout.leading;
    }
    if (_layout.trailingLineGap) height += wrap.lineGap;
    if (done) height += _layout.paddingBottom;
    final anchors = <(String, double, double)>[];
    for (final line in lines) {
      for (final f in line.fragments) {
        final fragment = f.format.fragment;
        if (fragment.isMarker && fragment.name != null) {
          anchors.add((fragment.name!, f.left, gap + f.baseline - f.ascender));
        }
      }
    }
    return CustomPlacement(
      height: height,
      anchors: anchors,
      rest: done
          ? null
          : TextBox._(
              rest,
              _state,
              _layout,
              _context,
              first: false,
              continuedIndent: wrap.continuedIndent,
            ),
      paint: (page, x, top) => _paint(page, lines, x, top - gap, width),
    );
  }

  void _paint(
    PdfPage page,
    List<_Line> lines,
    double x,
    double top,
    double width,
  ) {
    final canvas = page.canvas;
    final skew = _layout.skew;
    final lastBaseline = skew == null
        ? 0.0
        : lines
              .lastWhere(
                (l) => l.fragments.isNotEmpty,
                orElse: () => lines.last,
              )
              .fragments
              .fold<double>(0, (most, f) => math.max(most, f.baseline));
    for (final line in lines) {
      if (line.wrapped) _wrapArrow(canvas, line, x + width, top);
      for (final f in line.fragments) {
        final fragment = f.format.fragment;
        if (fragment.isMarker) continue;
        final left =
            x +
            f.left +
            (skew == null ? 0 : skew * (lastBaseline - f.baseline));
        final baseline = top - f.baseline;
        final y = baseline + f.yOffset;
        final callbacks = fragment.callbacks ?? const [];
        if (callbacks.contains(FragmentCallback.textBackgroundAndBorder)) {
          _background(canvas, fragment, left, y, f);
        }
        var textX = left;
        if (callbacks.contains(FragmentCallback.inlineTextAligner)) {
          final align = fragment.align;
          if (align == 'center' || align == 'right') {
            final natural = f.format.font.widthOf(
              f.text,
              f.format.size,
              kerning: _state.kerning,
              features: f.format.features,
            );
            final gapWidth = fragment.width != null
                ? f.width - natural
                : (fragment.borderOffset ?? 0) * 2;
            if (gapWidth > 0) textX += gapWidth * (align == 'center' ? 0.5 : 1);
          }
        }
        if (f.format.image case final image?) {
          // The gem's `InlineImageRenderer`: centered in the fragment, or
          // standing on the descender of a raised line.
          final top = image.mathDepth != null
              ? baseline - image.mathDepth! + image.height
              : image.lineHeightIncreased
              ? baseline - f.descender + image.height
              : baseline +
                    f.ascender -
                    (f.ascender + f.descender - image.height) / 2;
          final imageLeft = left + (f.width - image.width) / 2;
          final rect = PdfRect(
            imageLeft,
            top - image.drawHeight,
            image.drawWidth,
            image.drawHeight,
          );
          switch (image.graphic) {
            case final PdfImage raster:
              canvas.image(raster, rect);
            case final InlineMath formula:
              // In the text's color; copied as its source.
              canvas
                ..save()
                ..beginMarkedContent('Span', actualText: formula.source);
              if (_pdfColor(fragment.color) case final color?) {
                canvas
                  ..setFillColor(color)
                  ..setStrokeColor(color);
              }
              formula
                  .at(f.format.size)
                  .paintAt(canvas, rect.left, rect.bottom + image.mathDepth!);
              canvas
                ..endMarkedContent()
                ..restore();
            case final other:
              canvas.save();
              other.paint(canvas, rect);
              canvas.restore();
          }
        } else if (f.text.isNotEmpty) {
          canvas.save();
          if (_pdfColor(fragment.color) case final color?) {
            canvas
              ..setFillColor(color)
              ..setStrokeColor(color);
          }
          if (fragment.artifact) {
            canvas.beginMarkedContent('Span', actualText: '');
          }
          canvas
            ..text(
              f.text,
              textX,
              y,
              PdfTextStyle(
                f.format.font.pdf,
                f.format.size,
                wordSpacing: f.wordSpacing,
                characterSpacing: _state.characterSpacing,
                kerning: _state.kerning,
                ligatures: f.format.font.ligates,
                features: f.format.features,
                skew: skew ?? (f.format.font.slanted ? 0.2 : 0),
                embolden: f.format.font.emboldened ? f.format.size / 40 : 0,
              ),
            )
            ..restore();
          if (fragment.artifact) canvas.endMarkedContent();
        }
        final styles = fragment.styles ?? const {};
        if (styles.contains(FragmentStyle.underline) ||
            styles.contains(FragmentStyle.strikethrough)) {
          final lineY = styles.contains(FragmentStyle.underline)
              ? y - 1.25
              : y + f.ascender * 0.3;
          canvas
            ..save()
            ..setLineWidth(
              (fragment.textDecorationWidth ?? _context.decorationWidth)
                  .toDouble(),
            );
          if (_pdfColor(fragment.textDecorationColor ?? fragment.color)
              case final color?) {
            canvas.setStrokeColor(color);
          }
          canvas
            ..moveTo(left, lineY)
            ..lineTo(left + f.width, lineY)
            ..stroke()
            ..restore();
        }
        final box = PdfRect(
          left,
          y - f.descender,
          f.width,
          f.ascender + f.descender,
        );
        if (fragment.link case final link?) {
          page.link(box, LinkTarget.uri(link));
        } else if (fragment.anchor case final anchor?) {
          page.link(box, LinkTarget.named(destinationName(anchor)));
        }
      }
    }
  }

  /// A return arrow just past [right], beside [line] (which wraps), in
  /// the line's text color and size: drawn rather than set in a font, so
  /// that no font needs the glyph and the text extracts unchanged.
  void _wrapArrow(PdfCanvas canvas, _Line line, double right, double top) {
    final printed = [
      for (final f in line.fragments)
        if (!f.format.fragment.isMarker) f,
    ];
    if (printed.isEmpty) return;
    final last = printed.last;
    final size = last.format.size;
    final baseline = top - last.baseline;
    final left = right + size * 0.2;
    final bend = baseline + size * 0.2;
    canvas
      ..save()
      ..setStrokeColor(
        _pdfColor(last.format.fragment.color) ?? const PdfColor.gray(0),
      )
      ..setLineWidth(size * 0.06)
      ..setLineCap(LineCap.round)
      ..setLineJoin(LineJoin.round)
      ..moveTo(left + size * 0.55, baseline + size * 0.6)
      ..lineTo(left + size * 0.55, bend)
      ..lineTo(left + size * 0.05, bend)
      ..moveTo(left + size * 0.25, bend + size * 0.2)
      ..lineTo(left + size * 0.05, bend)
      ..lineTo(left + size * 0.25, bend - size * 0.2)
      ..stroke()
      ..restore();
  }

  void _background(
    PdfCanvas canvas,
    Fragment fragment,
    double left,
    double y,
    _Printed f,
  ) {
    final top = y + f.ascender;
    final offset = fragment.borderOffset?.toDouble();
    final double width;
    final double height;
    final double rectTop;
    if (offset != null) {
      rectTop = top + offset;
      width = f.width;
      height = f.ascender + f.descender + offset * 2;
    } else {
      rectTop = top;
      width = f.width;
      height = f.ascender + f.descender;
    }
    final rect = PdfRect(left, rectTop - height, width, height);
    final radius = (fragment.borderRadius ?? 0).toDouble();
    canvas.save();
    if (_pdfColor(fragment.backgroundColor) case final color?) {
      canvas.setFillColor(color);
      radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
      canvas.fill();
    }
    final borderWidth = fragment.borderWidth;
    if (borderWidth != null && borderWidth > 0) {
      if (_pdfColor(fragment.borderColor) case final color?) {
        canvas
          ..setStrokeColor(color)
          ..setLineWidth(borderWidth.toDouble());
        radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
        canvas.stroke();
      }
    }
    canvas.restore();
  }
}

/// [color] for drawing (null for none or transparent).
PdfColor? _pdfColor(ThemeColor? color) => switch (color) {
  null || TransparentColor() => null,
  HexColor(:final hex) => PdfColor.hex(hex),
  CmykThemeColor(:final components) => PdfColor.cmyk(
    components[0] / 100,
    components[1] / 100,
    components[2] / 100,
    components[3] / 100,
  ),
};

/// [color] as libpdf draws it, for the converter.
PdfColor? pdfColorOf(ThemeColor? color) => _pdfColor(color);

/// The break characters of Prawn's line wrapping: whitespace (with the
/// zero width space), the soft hyphen and the hyphen.
const String _breakChars = ' \t$_zwsp$_shy-';

final RegExp _wordDivision = RegExp('[\t\n\v\r $_zwsp$_shy-]');

/// [text]'s tokens (scanned by hand: line breaking tokenizes every piece
/// of text, often): a word (a run without [_breakChars]) with the soft
/// hyphen or the hyphens after it, a run of spaces, tabs and zero width
/// spaces, hyphens with the word after them, a soft hyphen.
List<String> _tokenize(String text) {
  final tokens = <String>[];
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    final start = i;
    if (c == _shyUnit) {
      i++;
    } else if (c == 0x20 || c == 0x09 || c == _zwspUnit) {
      while (i < n && _isSpaceUnit(text.codeUnitAt(i))) {
        i++;
      }
    } else if (c == 0x2d) {
      while (i < n && text.codeUnitAt(i) == 0x2d) {
        i++;
      }
      while (i < n && !_isBreakUnit(text.codeUnitAt(i))) {
        i++;
      }
    } else {
      while (i < n && !_isBreakUnit(text.codeUnitAt(i))) {
        i++;
      }
      if (i < n && text.codeUnitAt(i) == _shyUnit) {
        i++;
      } else {
        while (i < n && text.codeUnitAt(i) == 0x2d) {
          i++;
        }
      }
    }
    tokens.add(text.substring(start, i));
  }
  return tokens;
}

const int _shyUnit = 0xad;
const int _zwspUnit = 0x200b;

bool _isSpaceUnit(int c) => c == 0x20 || c == 0x09 || c == _zwspUnit;

bool _isBreakUnit(int c) => _isSpaceUnit(c) || c == _shyUnit || c == 0x2d;

/// Whether [text] is nothing but spaces, tabs and zero width spaces (and
/// not empty).
bool _isBlank(String text) {
  if (text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (!_isSpaceUnit(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// Whether [text] is nothing but spaces and tabs (and not empty).
bool _isSpaces(String text) {
  if (text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) return false;
  }
  return true;
}

/// The wrap of [items] for [context]'s engine: the modern engine's (whole
/// words, Typst's breaking), else Prawn's (also for code, whose wrapped
/// lines go on with a hanging indent).
_Wrap _wrapOf(
  List<_Item> items,
  TextState state,
  TextLayout layout,
  TextContext context,
  double width,
  double height, {
  required bool firstPiece,
  double? continuedIndent,
  int? maxLines,
}) => layout.wrapIndent == null
    ? _OptimalWrap(
        items,
        state,
        layout,
        context,
        width,
        height,
        firstPiece: firstPiece,
        maxLines: maxLines,
      )
    : _Wrap(
        items,
        state,
        layout,
        context,
        width,
        height,
        firstPiece: firstPiece,
        continuedIndent: continuedIndent,
        maxLines: maxLines,
      );

/// How the modern engine breaks a paragraph's lines (`base_line_breaking`).
enum LineBreaking {
  /// Optimally when justified, else one line at a time (as Typst does).
  auto,

  /// Where the lines' costs are least (Typst's optimizer), however the
  /// text is aligned.
  optimal,

  /// One line at a time, each as full as it goes.
  greedy,
}

/// Prawn's `LineWrap`, `Arranger` and `Wrap` over the items of one piece.
base class _Wrap {
  new(
    this._unconsumed,
    this._state,
    this._layout,
    this._context,
    this._width,
    this._height, {
    required this.firstPiece,
    this.continuedIndent,
    this.maxLines,
  });

  /// The most lines to set (all that fit when null).
  final int? maxLines;

  /// The indent of lines that go on with a line that wrapped (see
  /// [TextLayout.wrapIndent]): from the start when the text goes on with
  /// one, else null; after [run], for the text left over.
  double? continuedIndent;

  final List<_Item> _unconsumed;
  final TextState _state;
  final TextLayout _layout;
  final TextContext _context;
  final double _width;
  final double _height;
  final bool firstPiece;

  // Arranger state.
  List<_Item> _consumed = [];
  _Format? _currentFormat;
  List<_Printed> _fragments = [];
  double _maxLineHeight = 0;
  double _maxDescender = 0;
  double _maxAscender = 0;

  // Line wrap state.
  double _accumulated = 0;
  bool _lineEmpty = true;
  bool _moreThanOneWord = false;
  bool _newline = false;
  bool _lineFull = false;
  String _output = '';
  String _previousFragment = '';
  bool _previousEndedWithBreakable = false;
  String _previousWithoutLastWord = '';
  int _spaceCount = 0;

  // Box state.
  double _baseline = 0;
  double _lineHeight = 0;
  double _descender = 0;
  double _ascender = 0;
  final List<_Line> _lines = [];

  List<_Item> get unconsumed => _unconsumed;

  /// The height of the lines placed.
  double get height => _lines.isEmpty ? 0 : (_baseline.abs() + _descender);

  /// The line gap of the last line.
  double get lineGap => _lineHeight - (_ascender + _descender);

  double _widthOf(String given, _Format? format) {
    // The modern engine: an anchor's placeholder takes no room (some fonts
    // give their .notdef glyph a width).
    final text = given.replaceAll(_nul, '');
    if (text.isEmpty && given.isNotEmpty) return 0;
    final font = format?.font ?? _baseFont;
    final size = format?.size ?? _state.size;
    final width = font.widthOf(
      text,
      size,
      kerning: _state.kerning,
      features: format?.features ?? _state.features,
    );
    // Prawn 2.4 adds the character spacing between characters.
    final count = text.runes.length;
    return count > 1 ? width + _state.characterSpacing * (count - 1) : width;
  }

  late final FontFace _baseFont = TextBox._font(
    _state.family,
    _state.style,
    _context,
  );

  List<_Line> run() {
    var stop = false;
    var lineNumber = 0;
    while (!stop) {
      if (maxLines case final most? when lineNumber >= most) break;
      final indent = lineNumber == 0 && firstPiece
          ? _layout.indentFirstLine
          : continuedIndent ?? 0.0;
      try {
        _wrapLine(_width - indent);
      } on _CannotFit {
        // Prawn prints nothing more when a character doesn't fit the width.
        _unconsumed.insertAll(0, _consumed);
        break;
      }
      if (_enoughHeight()) {
        _moveBaselineDown();
        _printLine(indent);
        _markWrap(indent);
        lineNumber++;
        if (_layout.singleLine) stop = true;
      } else {
        stop = true;
      }
      stop = stop || _unconsumed.isEmpty;
    }
    return _lines;
  }

  /// Marks the line just printed when it wraps (its text goes on in the
  /// next), and sets the indent of the lines it wraps onto: the line's
  /// own indentation (its leading no-break spaces) and the layout's
  /// [TextLayout.wrapIndent], at most half the width.
  void _markWrap(double indent) {
    final wrapIndent = _layout.wrapIndent;
    if (wrapIndent == null && !_layout.wrapMarker) return;
    if (_paragraphFinished) {
      continuedIndent = null;
      return;
    }
    _lines.last.wrapped = _layout.wrapMarker;
    if (wrapIndent == null || continuedIndent != null) return;
    var own = 0.0;
    if (_lines.last.fragments.firstOrNull case final first?) {
      final leading = _leadingSpacesRx.stringMatch(first.text) ?? '';
      if (leading.isNotEmpty) own = _widthOf(leading, first.format);
    }
    continuedIndent = math.min(indent + own + wrapIndent, _width / 2);
  }

  // LineWrap.

  void _wrapLine(double width) {
    _accumulated = 0;
    _lineEmpty = true;
    _moreThanOneWord = false;
    _newline = false;
    _lineFull = false;
    _consumed = [];
    _fragments = [];
    _maxLineHeight = 0;
    _maxDescender = 0;
    _maxAscender = 0;
    while (true) {
      final item = _nextString();
      if (item == null) break;
      _output = '';
      if (_lineEmptyNow && item.text != '\n' && item.text != _nul) {
        item.text = _lstrip(item.text);
      }
      if (_lineEmptyNow && item.text.isEmpty && _nextIsNewline) {
        _updateLastString('', '', normalized: true);
        continue;
      }
      if (!_addFragment(item, width)) break;
    }
    _finalizeLine();
  }

  bool get _lineEmptyNow => _lineEmpty && _accumulated == 0;

  bool get _nextIsNewline =>
      _unconsumed.isNotEmpty && _unconsumed.first.text == '\n';

  bool get _paragraphFinished =>
      _newline || _nextIsNewline || _unconsumed.isEmpty;

  _Item? _nextString() {
    if (_unconsumed.isEmpty) return null;
    final item = _unconsumed.removeAt(0);
    _consumed.add(item);
    _currentFormat = item.format;
    return item;
  }

  /// The text of the word-joined items after the next one (the gem's
  /// `preview_joined_string`).
  String? _previewJoined() {
    if (_unconsumed.isEmpty) return null;
    final next = _unconsumed.first;
    if (!next.format.fragment.wj ||
        (_consumed.isNotEmpty && _consumed.last.format.fragment.wj)) {
      return null;
    }
    var text = next.text == _nul ? '' : next.text;
    for (var i = 1; i < _unconsumed.length; i++) {
      final item = _unconsumed[i];
      if (!item.format.fragment.wj) break;
      if (item.text != _nul) text += item.text;
    }
    return text.isEmpty ? null : text;
  }

  bool _addFragment(_Item item, double width) {
    final fragment = item.text;
    if (fragment.isEmpty) return true;
    if (fragment == '\n') {
      _newline = true;
      return false;
    }
    final joined = _previewJoined();
    final joinedWidth = joined == null
        ? 0.0
        : _widthOf(_tokenize(joined).firstOrNull ?? '', item.format);
    final segments = _tokenize(fragment);
    for (final (index, segment) in segments.indexed) {
      double segmentWidth;
      double effective;
      if (segment == _zwsp) {
        segmentWidth = effective = 0;
      } else {
        segmentWidth = effective = _widthOf(segment, item.format);
        if (index == segments.length - 1) effective += joinedWidth;
      }
      if (_accumulated + effective <= width) {
        _accumulated += segmentWidth;
        if (segment.endsWith(_shy)) {
          _accumulated -= _widthOf(_shy, item.format);
        }
        _output += segment;
      } else {
        if (_accumulated == 0 && _moreThanOneWord) _moreThanOneWord = false;
        _endOfLineReached(segment, item.format, width);
        _fragmentFinished(item);
        return false;
      }
    }
    _fragmentFinished(item);
    return true;
  }

  void _endOfLineReached(String segment, _Format format, double width) {
    _updateLineStatus();
    if (!_moreThanOneWord) {
      // Wrap by character.
      for (final rune in segment.runes) {
        final char = String.fromCharCode(rune);
        final charWidth = format.font.widthOf(
          char,
          format.size,
          kerning: false,
        );
        if (_accumulated + charWidth <= width) {
          _accumulated += charWidth;
          _output += char;
        } else {
          break;
        }
      }
      // Prawn drops the rest of the text when not even a character fits
      // the line; the modern engine sets one anyway, past the edge.
      if (_output.isEmpty && _lineEmptyNow && segment.isNotEmpty) {
        final char = String.fromCharCode(segment.runes.first);
        _accumulated += format.font.widthOf(char, format.size, kerning: false);
        _output = char;
      }
    }
    _lineFull = true;
  }

  void _fragmentFinished(_Item item) {
    if (item.text == '\n') {
      _newline = true;
      _lineEmpty = false;
    } else {
      _updateOutput(item.text);
      _updateLineStatus();
      _pullPrecedingFragment(item.text);
    }
    _rememberFragment();
  }

  void _updateOutput(String fragment) {
    final remaining = fragment.length > _output.length
        ? fragment.substring(_output.length)
        : '';
    if ((_lineFull || _paragraphFinished) &&
        _lineEmptyNow &&
        _output.isEmpty &&
        _strip(fragment).isNotEmpty) {
      throw const _CannotFit();
    }
    _updateLastString(_output, remaining, normalized: true);
  }

  void _updateLineStatus() {
    if (_wordDivision.hasMatch(_output)) _moreThanOneWord = true;
  }

  void _pullPrecedingFragment(String current) {
    if (_output.isEmpty &&
        current.isNotEmpty &&
        _moreThanOneWord &&
        !(_previousEndedWithBreakable || _breakChars.contains(current[0]))) {
      _output = _previousWithoutLastWord;
      _updateOutput(_previousFragment);
    }
  }

  void _rememberFragment() {
    _previousFragment = _output;
    _previousEndedWithBreakable =
        _previousFragment.isNotEmpty &&
        _breakChars.contains(_previousFragment[_previousFragment.length - 1]);
    final lastWord = _trailingWordRx.stringMatch(_previousFragment) ?? '';
    _previousWithoutLastWord = _previousFragment.substring(
      0,
      _previousFragment.length - lastWord.length,
    );
  }

  /// The arranger's `update_last_string`.
  void _updateLastString(
    String printed,
    String unprinted, {
    required bool normalized,
  }) {
    if (printed.isEmpty) {
      if (_consumed.isNotEmpty) _consumed.removeLast();
    } else {
      _consumed.last
        ..text = printed
        ..normalizedSoftHyphen = normalized;
    }
    if (unprinted.isNotEmpty) {
      _unconsumed.insert(0, _Item(unprinted, _currentFormat!));
    }
    if (printed.isEmpty) {
      _currentFormat = _consumed.isEmpty ? null : _consumed.last.format;
    }
  }

  void _finalizeLine() {
    if (_layout.normalizeLineHeight) {
      _consumed.insert(
        0,
        _Item(_zwsp, _Format(Fragment(_zwsp), _baseFont, _state.size)),
      );
    }
    // Omit trailing whitespace from the line width.
    for (final item in _consumed.reversed) {
      if (item.text == '\n') break;
      if (_strip(item.text).isEmpty && _consumed.length > 1) {
        item.excludeTrailingWhiteSpace = true;
      } else {
        item.excludeTrailingWhiteSpace = true;
        break;
      }
    }
    _fragments = [];
    var blankTop = 0.0;
    for (final item in _consumed) {
      var text = item.text.replaceAll(_zwsp, '');
      if (item.excludeTrailingWhiteSpace) {
        text = _rstrip(text);
        if (item.normalizedSoftHyphen && text.isNotEmpty) {
          text =
              text.substring(0, text.length - 1).replaceAll(_shy, '') +
              text.substring(text.length - 1);
        }
      } else if (item.normalizedSoftHyphen && text.isNotEmpty) {
        text = text.replaceAll(_shy, '');
      }
      final format = item.format;
      final isMarker = format.fragment.isMarker;
      final width = isMarker ? 0.0 : _fragmentWidth(text, format);
      final printed = _Printed(
        isMarker ? '' : text,
        format,
        width,
        0,
        // (A fragment as wide as it says, a fixed space: not stretched.)
        format.fragment.width != null ? 0 : ' '.allMatches(text).length,
      );
      _fragments.add(printed);
      final font = format.font;
      final image = format.image;
      if (_layout.capLines) {
        // (A line break or spaces count only on a line without other
        // text: an empty line is as tall as its font's cap height, as
        // Typst's.)
        if (!isMarker && image == null && text.trim().isEmpty) {
          blankTop = math.max(blankTop, font.capHeightAt(format.size));
          continue;
        }
        final top = isMarker
            ? 0.0
            : image?.ascender ?? font.capHeightAt(format.size);
        _maxLineHeight = math.max(_maxLineHeight, top);
        _maxAscender = math.max(_maxAscender, top);
      } else {
        _maxLineHeight = math.max(_maxLineHeight, font.heightAt(format.size));
        _maxDescender = math.max(
          _maxDescender,
          image?.descender ?? font.descenderAt(format.size),
        );
        _maxAscender = math.max(
          _maxAscender,
          isMarker ? 0 : image?.ascender ?? font.ascenderAt(format.size),
        );
      }
    }
    if (_layout.capLines && _maxLineHeight == 0 && blankTop > 0) {
      _maxLineHeight = _maxAscender = blankTop;
    }
    _spaceCount = _fragments.fold(0, (sum, f) => sum + f.spaces);
  }

  double _fragmentWidth(String text, _Format format) {
    final fragment = format.fragment;
    if (format.image case final image?) return image.width;
    var width = switch (fragment.width) {
      final String fixed when fixed.endsWith('em') => _toF(fixed) * format.size,
      final String fixed => strToPoints(fixed),
      null => _widthOf(text, format),
    };
    if (fragment.borderOffset case final offset?) width += offset * 2;
    return width;
  }

  static double _toF(String text) =>
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)').stringMatch(text) ?? '',
      ) ??
      0;

  // Wrap.

  bool _enoughHeight() {
    _lineHeight = _maxLineHeight;
    _descender = _maxDescender;
    _ascender = _maxAscender;
    final diff = _baseline == 0
        ? _ascender + _descender
        : _descender + _lineHeight + _layout.leading;
    if (_baseline.abs() + diff > _height + 0.0001) {
      // Repack the fragments of this line.
      final repacked = <_Item>[
        for (final item in _consumed)
          item.copy()..excludeTrailingWhiteSpace = false,
      ];
      _unconsumed.insertAll(0, repacked);
      return false;
    }
    return true;
  }

  void _moveBaselineDown() {
    if (_baseline == 0) {
      _baseline = -_ascender;
    } else {
      _baseline -= _lineHeight + _layout.leading;
    }
  }

  /// The width justified lines are set to, when not the room
  /// ([TextLayout.justifyWidest]).
  double? _justifyTo;

  /// How far the line's last character may hang past its end (Typst's
  /// amounts: of the character's width, 0.55 for a hyphen, 0.2 for an en
  /// or em dash, 0.8 for a period or comma, 0.3 for a colon or semicolon).
  double _overhang() {
    for (final f in _fragments.reversed) {
      final text = f.text.trimRight();
      if (text.isEmpty || text == '\n') continue;
      final char = String.fromCharCode(text.runes.last);
      final factor = switch (char) {
        '\u2013' || '\u2014' => 0.2,
        '-' || '\u00ad' => 0.55,
        '.' || ',' => 0.8,
        ':' || ';' => 0.3,
        _ => 0.0,
      };
      if (factor == 0) return 0;
      return factor * f.format.font.widthOf(char, f.format.size);
    }
    return 0;
  }

  void _printLine(double indent) {
    // Justified, but not the last line of a paragraph, unless it is
    // wider than the room (the optimal wrap shrinks spaces to fit a line;
    // Prawn's wrap never fills a line past the room).
    final justify =
        _layout.align == 'justify' &&
        _spaceCount > 0 &&
        (_layout.forceJustify ||
            !_paragraphFinished ||
            _accumulatedWidth > _width - indent + 0.0001);
    final hang = _layout.overhang > 0 ? _layout.overhang * _overhang() : 0.0;
    final measure = math.min(_justifyTo ?? _width, _width);
    var wordSpacing = justify
        ? (measure - indent + hang - _accumulatedWidth) / _spaceCount
        : 0.0;
    // A last line justified for being too wide only shrinks (as Typst's:
    // with what hangs past the room it may fit as it is).
    if (justify &&
        !_layout.forceJustify &&
        _paragraphFinished &&
        wordSpacing > 0) {
      wordSpacing = 0;
    }
    final printed = <_Printed>[];
    for (final f in _fragments) {
      if (f.text == '\n') break;
      printed.add(
        _Printed(
          f.text,
          f.format,
          f.width + wordSpacing * f.spaces,
          wordSpacing,
          f.spaces,
        ),
      );
    }
    final lineWidth = printed.fold<double>(0, (sum, f) => sum + f.width);
    final available = _width - indent + hang;
    final offset = switch (justify ? 'justify' : _lineAlign) {
      'center' => available * 0.5 - lineWidth * 0.5,
      'right' => available - lineWidth,
      _ => 0.0,
    };
    var x = indent + offset;
    for (final f in printed) {
      f
        ..left = x
        ..baseline = -_baseline;
      x += f.width;
    }
    _lines.add(_Line(printed));
    _fragments = [];
  }

  double get _accumulatedWidth => _fragments.fold(0, (sum, f) => sum + f.width);

  /// The alignment of a line set unjustified.
  String get _lineAlign =>
      _layout.align == 'justify' ? _layout.alignLast ?? 'left' : _layout.align;
}

/// A character wider than the line (Prawn's `CannotFit`).
final class _CannotFit implements Exception {
  const new();
}

// Ruby's whitespace (for strip and its kin): ASCII whitespace and NUL,
// never a no-break space.

/// [text] without the ASCII whitespace and NULs at its start.
String _lstrip(String text) {
  var start = 0;
  while (start < text.length && _isStripUnit(text.codeUnitAt(start))) {
    start++;
  }
  return start == 0 ? text : text.substring(start);
}

/// [text] without the ASCII whitespace and NULs at its end.
String _rstrip(String text) {
  var end = text.length;
  while (end > 0 && _isStripUnit(text.codeUnitAt(end - 1))) {
    end--;
  }
  return end == text.length ? text : text.substring(0, end);
}

bool _isStripUnit(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0d) || c == 0;

String _strip(String text) => _lstrip(_rstrip(text));

/// Text whose first line is set in another style (the gem's
/// `text_with_formatted_first_line`): the first line laid out alone, the
/// rest after it without another gap above.
final class FirstLineTextBox implements CustomContent {
  /// [first] (laid out with a single line) followed by its rest in
  /// [state], laid out by [layout] (without the initial gap right after
  /// the first line, with it on later pages).
  const new(this.first, this.state, this.layout, {this.transform});

  /// The text in the first line's style, laid out a single line.
  final TextBox first;

  /// The text transform of the first line, applied once the line is
  /// broken (the line then shrinks to fit), if any.
  final String? transform;

  /// The style of the lines after the first.
  final TextState state;

  /// The layout of the lines after the first.
  final TextLayout layout;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final head = transform == null
        ? first.place(width, available, atTop: atTop)
        : _transformedFirstLine(width, available, atTop: atTop);
    if (head == null) return null;
    final rest = head.rest;
    if (rest is! TextBox) return head;
    final tail = rest.restyled(state, layout.withoutInitialGap);
    final body = tail.place(width, available - head.height, atTop: false);
    if (body == null) {
      return CustomPlacement(
        height: head.height,
        anchors: head.anchors,
        rest: tail,
        paint: head.paint,
      );
    }
    final next = body.rest;
    return CustomPlacement(
      height: head.height + body.height,
      anchors: [
        ...head.anchors,
        for (final (name, x, y) in body.anchors) (name, x, y + head.height),
      ],
      rest: next is TextBox ? next.restyled(state, layout) : next,
      paint: (page, x, top) {
        head.paint(page, x, top);
        body.paint(page, x, top - head.height);
      },
    );
  }

  /// The first line with its text transformed: broken as it is, then
  /// shrunk to fit (justified when more follows and the text justifies).
  CustomPlacement? _transformedFirstLine(
    double width,
    double available, {
    required bool atTop,
  }) {
    final (fragments, rest) = first.splitFirstLine(width);
    final line = first.layout;
    final more = rest != null;
    final box = TextBox(
      [
        for (final fragment in fragments)
          fragment.copy(text: transformText(fragment.text, transform!)),
      ],
      first.state,
      TextLayout(
        align: line.align,
        leading: line.leading,
        initialGap: line.initialGap,
        paddingBottom: more ? 0 : line.paddingBottom,
        finalGap: more || line.finalGap,
        singleLine: true,
        shrinkToFit: true,
        indentFirstLine: line.indentFirstLine,
        normalizeLineHeight: line.normalizeLineHeight,
        forceJustify:
            more &&
            line.align == 'justify' &&
            fragments.lastOrNull?.text != '\n',
      ),
      first._context,
    );
    final placed = box.place(width, available, atTop: atTop);
    if (placed == null || !more) return placed;
    return CustomPlacement(
      height: placed.height,
      anchors: placed.anchors,
      rest: rest,
      paint: placed.paint,
    );
  }

  @override
  double minHeight(double width) => first.minHeight(width);

  @override
  (double, double) intrinsicWidths() => first.intrinsicWidths();
}

/// Text set smaller when its longest line is wider than the room (the
/// gem's `autofit` option: `compute_autofit_font_size`), no smaller than
/// [minimum].
final class AutofitTextBox implements CustomContent {
  /// [text], shrunk to fit.
  const new(this.text, {this.minimum});

  /// The text at its own size.
  final TextBox text;

  /// The least font size, if any.
  final double? minimum;

  TextBox _fitted(double width) {
    final widest = text.intrinsicWidths().$2;
    if (widest <= width) return text;
    var size = (width * text.state.size / widest * 10000).truncate() / 10000;
    if (minimum case final least? when size < least) size = least;
    return text.resized(size);
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => _fitted(width).place(width, available, atTop: atTop);

  @override
  double minHeight(double width) => _fitted(width).minHeight(width);

  @override
  (double, double) intrinsicWidths() => text.intrinsicWidths();
}

/// The name of the PDF destination of [anchor]: the anchor itself when
/// it's ASCII, else `0x` and its UTF-8 bytes in hexadecimal (the gem's
/// `derive_anchor_from_id`).
String destinationName(String anchor) {
  if (anchor.codeUnits.every((unit) => unit < 0x80)) return anchor;
  final hex = [
    for (final byte in utf8.encode(anchor))
      byte.toRadixString(16).padLeft(2, '0'),
  ];
  return '0x${hex.join()}';
}

/// The modern engine's wrap: the breaks Typst's optimizer would choose
/// (libpdf's TypstLineBreaker: the lines' costs, as Knuth and Plass's total
/// fit), over the same items, and the lines then set as Prawn's wrap sets
/// them (justified by word spacing when justified).
final class _OptimalWrap extends _Wrap {
  new(
    super._unconsumed,
    super._state,
    super._layout,
    super._context,
    super._width,
    super._height, {
    required super.firstPiece,
    super.maxLines,
  });

  /// A stand-in for the content of the breaker's items (it reads only
  /// their widths).
  static final TextRun _content = TextRun(
    '',
    PdfTextStyle(StandardFont.helvetica, 10),
  );

  /// Splits into characters a word longer than a line that runs across
  /// items ([pieces], with index terms' anchors or style changes between
  /// its parts), as a word in one item is split: the line may break
  /// before any of its characters ([charBreaks], at a cost).
  void _splitLongRuns(List<(int, String)> pieces, Set<int> charBreaks) {
    bool isSpace((int, String) piece) => piece.$2 == '\n' || _isBlank(piece.$2);
    bool isMarker((int, String) piece) =>
        _unconsumed[piece.$1].format.fragment.isMarker;
    final split = <(int, String)>[];
    final breaks = <int>{};
    var p = 0;
    while (p < pieces.length) {
      var q = p;
      var width = 0.0;
      while (q < pieces.length && !isSpace(pieces[q])) {
        if (!isMarker(pieces[q])) {
          final (i, text) = pieces[q];
          width += _widthOf(text, _unconsumed[i].format);
        }
        q++;
      }
      final long = q - p > 1 && width > _width;
      if (q == p) q++;
      for (var r = p; r < q; r++) {
        final piece = pieces[r];
        if (long && !isMarker(piece) && piece.$2.runes.length > 1) {
          for (final (k, rune) in piece.$2.runes.indexed) {
            if (k > 0 || r > p) breaks.add(split.length);
            split.add((piece.$1, String.fromCharCode(rune)));
          }
        } else {
          if (charBreaks.contains(r) || (long && r > p && !isMarker(piece))) {
            breaks.add(split.length);
          }
          split.add(piece);
        }
      }
      p = q;
    }
    pieces
      ..clear()
      ..addAll(split);
    charBreaks
      ..clear()
      ..addAll(breaks);
  }

  @override
  List<_Line> run() {
    _source = [..._unconsumed];
    // The pieces: the items' tokens (newlines are items of their own).
    // Spaces at the start of a line are left out, also after zero-width
    // markers (an index term's anchor before the first word).
    final pieces = <(int, String)>[];
    // The pieces a word longer than a line may break before.
    final charBreaks = <int>{};
    var lineStart = true;
    for (final (i, item) in _unconsumed.indexed) {
      if (item.text == '\n') {
        pieces.add((i, '\n'));
        lineStart = true;
      } else {
        for (final token in _tokenize(item.text)) {
          if (_isSpaces(token)) {
            if (lineStart) continue;
          } else if (!item.format.fragment.isMarker) {
            lineStart = false;
          }
          // A word longer than a line: a piece per character, so that the
          // line can break between them (at a cost).
          final word = token.endsWith(_shy)
              ? token.substring(0, token.length - 1)
              : token;
          if (!item.format.fragment.isMarker &&
              word.runes.length > 1 &&
              !_isBlank(word) &&
              _widthOf(word, item.format) > _width) {
            for (final (k, rune) in token.runes.indexed) {
              if (k > 0) charBreaks.add(pieces.length);
              pieces.add((i, String.fromCharCode(rune)));
            }
            continue;
          }
          pieces.add((i, token));
        }
      }
    }
    _splitLongRuns(pieces, charBreaks);
    final indent = firstPiece ? _layout.indentFirstLine : 0.0;
    double widthOf(int line) => line == 0 ? _width - indent : _width;
    // The breaker's items, and the piece each comes from.
    final items = <LineItem>[];
    final from = <int>[];
    void add(LineItem item, int piece) {
      items.add(item);
      from.add(piece);
    }

    // The word the pieces so far belong to, and its format.
    var wordSoFar = '';
    _Format? wordFormat;
    for (final (p, (i, token)) in pieces.indexed) {
      final format = _unconsumed[i].format;
      if (token == '\n') {
        wordSoFar = '';
        add(const GlueItem.fill(), p);
        add(const PenaltyItem(0, PenaltyItem.forced), p);
        continue;
      }
      if (_isBlank(token)) {
        wordSoFar = '';
        final spaces = token.replaceAll(_zwsp, '');
        if (spaces.isEmpty) {
          add(const PenaltyItem(0, 0), p);
        } else if (format.fragment.width != null) {
          // A space as wide as it says (a term's gap): a break that
          // neither stretches nor shrinks.
          final width = _fragmentWidth(spaces, format);
          add(GlueItem(null, spaces, width, 0, 0), p);
        } else {
          final width = _widthOf(spaces, format);
          // No break after an opening bracket or before a closing one or
          // other punctuation, spaces between or not (UAX #14's LB14 and
          // LB13, as Typst breaks: `{{ x }}` stays whole).
          final before = p > 0 ? pieces[p - 1].$2 : '';
          final after = p + 1 < pieces.length ? pieces[p + 1].$2 : '';
          if ((before.isNotEmpty &&
                  '([{'.contains(before[before.length - 1])) ||
              (after.isNotEmpty && ')]}!?,.:;/'.contains(after[0]))) {
            add(const PenaltyItem(0, PenaltyItem.never), p);
          }
          add(GlueItem(null, spaces, width, width / 2, width / 3), p);
        }
        continue;
      }
      final shy = token.endsWith(_shy);
      final word = shy ? token.substring(0, token.length - 1) : token;
      // A character of a word longer than a line: a costly break before
      // it (see the pieces).
      if (charBreaks.contains(p)) add(const PenaltyItem(0, 900), p);
      if (word.isNotEmpty) {
        // A piece of a word broken into pieces (at its hyphenation
        // points): its width within the word, kerning to the piece before
        // it included, so the pieces add up to the word.
        final double width;
        if (format.fragment.isMarker) {
          width = 0;
        } else if (identical(wordFormat, format) && wordSoFar.isNotEmpty) {
          width =
              _widthOf('$wordSoFar$word', format) - _widthOf(wordSoFar, format);
        } else {
          width = word == _unconsumed[i].text
              ? _fragmentWidth(word, format)
              : _widthOf(word, format);
        }
        if (!identical(wordFormat, format)) wordSoFar = '';
        wordSoFar += word;
        wordFormat = format;
        add(BoxItem(_content, word, width), p);
      }
      if (shy) {
        add(PenaltyItem(_widthOf('-', format), 50, flagged: true), p);
      } else if (word.endsWith('-')) {
        // After a hyphen of the text: an ordinary break, as Typst has it
        // (the breaker counts the dash for two lines ending in one).
        add(const PenaltyItem(0, 0), p);
      }
    }
    add(const GlueItem.fill(), pieces.length);
    add(const PenaltyItem(0, PenaltyItem.forced), pieces.length);
    // Typst's breaking: optimal (its costs; ragged lines that don't
    // shrink) or one line at a time.
    final justify = _layout.align == 'justify';
    final breaker = switch (_context.lineBreaking) {
      LineBreaking.optimal => TypstLineBreaker(
        justify: justify,
        fontSize: _state.size,
      ),
      LineBreaking.auto when justify => TypstLineBreaker(fontSize: _state.size),
      _ => const FirstFitLineBreaker(),
    };
    // The same paragraph is broken at the same width again and again (as
    // pages are tried and the book laid out again): its breaks are kept.
    final key = _BreakKey(breaker, widthOf(0), widthOf(1), items);
    final breaks = _breaks[key] ??= breaker.breakItems(items, widthOf);

    // The pieces of each line: up to the piece its break is in (a space
    // or a newline ends the line it breaks), then on from the next.
    final lines = <(int, int)>[];
    var start = 0;
    for (final at in breaks) {
      final item = items[at];
      final piece = from[at];
      final end = switch (item) {
        // A break at a space or a newline: the line takes it (trailing
        // spaces are left out of its width; a newline is its end).
        GlueItem() || PenaltyItem() when piece < pieces.length => piece + 1,
        _ => math.min(piece + 1, pieces.length),
      };
      if (end > start || lines.isEmpty) lines.add((start, end));
      start = end;
    }

    // Justified to the widest line: each line's natural width (without
    // the spaces it ends with, with a hyphen it adds).
    if (_layout.justifyWidest) {
      var widest = 0.0;
      var start = 0;
      for (final (n, at) in breaks.indexed) {
        var end = at;
        while (end > start && items[end - 1] is GlueItem) {
          end--;
        }
        var natural = n == 0 ? indent : 0.0;
        for (var k = start; k < end; k++) {
          if (items[k] is! PenaltyItem) natural += items[k].width;
        }
        if (items[at] case PenaltyItem(flagged: true, :final width)) {
          natural += width;
        }
        widest = math.max(widest, natural);
        start = at + 1;
        while (start < items.length &&
            (items[start] is GlueItem ||
                (items[start] is PenaltyItem &&
                    !(items[start] as PenaltyItem).isForced))) {
          start++;
        }
      }
      _justifyTo = widest;
    }

    // Each line set as Prawn's wrap sets it.
    var lineNumber = 0;
    for (final (first, end) in lines) {
      if (maxLines case final most? when lineNumber >= most) break;
      _consumed = _items(pieces, first, end);
      final rest = _items(pieces, end, pieces.length);
      _unconsumed
        ..clear()
        ..addAll(rest);
      _newline = end > first && pieces[end - 1].$2 == '\n';
      _accumulated = 0;
      _fragments = [];
      _maxLineHeight = 0;
      _maxDescender = 0;
      _maxAscender = 0;
      _finalizeLine();
      if (!_enoughHeight()) break;
      _moveBaselineDown();
      _printLine(lineNumber == 0 ? indent : 0);
      lineNumber++;
      if (_layout.singleLine) break;
    }
    if (lineNumber == lines.length) _unconsumed.clear();
    return _lines;
  }

  /// The pieces [first] to [end] (exclusive) as items: consecutive pieces
  /// of an item make one, with the item's formatting.
  List<_Item> _items(List<(int, String)> pieces, int first, int end) {
    final result = <_Item>[];
    int? current;
    final text = StringBuffer();
    void flush() {
      if (current == null) return;
      result.add(
        _source[current].copy(text: text.toString())
          ..normalizedSoftHyphen = true,
      );
      text.clear();
    }

    for (var p = first; p < end; p++) {
      final (i, token) = pieces[p];
      if (i != current) {
        flush();
        current = i;
      }
      text.write(token);
    }
    flush();
    return result;
  }

  /// The items as they were before the wrap (its list changes).
  List<_Item> _source = const [];
}

// Patterns the line wrapping uses for every piece of text, built once.
final RegExp _linesRx = RegExp('[^\n]+|\n');
final RegExp _leadingSpacesRx = RegExp('^[\u00a0 ]*');
final RegExp _trailingWordRx = RegExp('[^$_breakChars]*\$');

/// The breaks found for each paragraph's items, by breaker and widths.
final Map<_BreakKey, List<int>> _breaks = {};

/// A line item as a break key compares it: its kind (0 a box, 1 glue, 2
/// a penalty), text and measures (a penalty's cost as its second).
typedef _ItemKey = (
  int kind,
  String text,
  double width,
  double stretch,
  double shrink,
  bool flagged,
);

/// What a paragraph's line breaks depend on: the breaker and its costs,
/// the first line's width and the others', and each item (its kind, text
/// and measures).
@immutable
final class _BreakKey {
  new(ItemLineBreaker breaker, double first, double rest, List<LineItem> items)
    : this._(
        switch (breaker) {
          TypstLineBreaker(
            :final justify,
            :final fontSize,
            :final hyphenationCost,
            :final runtCost,
          ) =>
            'typst $justify $fontSize $hyphenationCost $runtCost',
          _ => breaker.runtimeType.toString(),
        },
        first,
        rest,
        [
          for (final item in items)
            switch (item) {
              BoxItem(:final text, :final width) => (
                0,
                text,
                width,
                0,
                0,
                false,
              ),
              GlueItem(
                :final text,
                :final width,
                :final stretch,
                :final shrink,
              ) =>
                (1, text, width, stretch, shrink, false),
              PenaltyItem(:final width, :final penalty, :final flagged) => (
                2,
                '',
                width,
                penalty,
                0,
                flagged,
              ),
            },
        ],
      );

  new _(this._breaker, this._first, this._rest, this._items)
    : _hash = Object.hash(_breaker, _first, _rest, Object.hashAll(_items));

  final String _breaker;
  final double _first;
  final double _rest;
  final List<_ItemKey> _items;
  final int _hash;

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (other is! _BreakKey ||
        other._hash != _hash ||
        other._breaker != _breaker ||
        other._first != _first ||
        other._rest != _rest ||
        other._items.length != _items.length) {
      return false;
    }
    for (var i = 0; i < _items.length; i++) {
      if (other._items[i] != _items[i]) return false;
    }
    return true;
  }
}
