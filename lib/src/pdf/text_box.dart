/// Text laid out as Prawn 2.4 lays it out, with asciidoctor-pdf 2.3.27's
/// extensions: fragments wrapped line by line (Prawn's `LineWrap`, with
/// word joiners), each line as tall as its tallest fragment, baselines
/// placed with the leading and the gaps asciidoctor-pdf passes,
/// justification by word spacing, font fallback per glyph. A
/// [PrawnTextBox] is libpdf custom content: the layout gives it the room
/// left on the page and it places the lines that fit.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:asciidart/src/logging.dart';
import 'package:asciidart/src/pdf/fonts.dart';
import 'package:asciidart/src/pdf/markup.dart';
import 'package:asciidart/src/pdf/svg_size.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:libpdf/libpdf.dart';

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
  });

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
  });

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
  );

  /// Whether each line is at least as tall as the base font.
  final bool normalizeLineHeight;

  /// Whether the last line is justified too.
  final bool forceJustify;
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
    LoggerBase? logger,
  }) : logger = logger ?? LoggerManager.logger;

  /// Reads the inline image at a path in a format, or returns null (with
  /// the reason) when it can't.
  final (Graphic?, String?) Function(String path, String? format)? images;

  /// The height of the content area (the most an inline image may be).
  final double boundsHeight;

  /// The width of underlines and strike-throughs that don't set one (the
  /// theme's `base_text_decoration_width`).
  final double decorationWidth;

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
  new(this.fragment, this.font, this.size, {this.image});

  final Fragment fragment;
  final PrawnFont font;
  final double size;

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
  });

  final Graphic graphic;
  final double width;
  final double height;
  final double drawWidth;
  final double drawHeight;
  final double? ascender;
  final double? descender;
  final bool lineHeightIncreased;
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
  double get yOffset => format.subscript
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
}

/// Text laid out as Prawn does, as libpdf custom content.
final class PrawnTextBox implements CustomContent {
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
        final text = format.font.normalize(run.text);
        // One item per line of the fragment (Prawn's `format_array=`).
        for (final m in RegExp('[^\n]+|\n').allMatches(text)) {
          items.add(_Item(m[0]!, format, defaultColor: defaultColor));
        }
      }
    }
    return PrawnTextBox._(items, state, layout, context, first: true);
  }

  new _(
    this._items,
    this._state,
    this._layout,
    this._context, {
    required this.first,
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

  /// Whether there is no text.
  bool get isEmpty => _items.isEmpty;

  /// This (left over) text in [state] and laid out by [layout] (the rest
  /// of a first line set in another style).
  PrawnTextBox restyled(TextState state, TextLayout layout) => PrawnTextBox._(
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

  static _Format _resolve(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    final styles = fragment.styles ?? const {};
    final bold = styles.contains(FragmentStyle.bold);
    final italic = styles.contains(FragmentStyle.italic);
    final style = bold && italic
        ? 'bold_italic'
        : bold
        ? 'bold'
        : italic
        ? 'italic'
        : 'normal';
    final PrawnFont font;
    if (fragment.font != null || style != 'normal') {
      font = _font(fragment.font ?? state.family, style, context);
    } else {
      font = _font(state.family, state.style, context);
    }
    var size = switch (fragment.size) {
      null => state.size,
      final s => resolveFontSize(s, state.size, context.rootSize),
    };
    if (styles.contains(FragmentStyle.subscript) ||
        styles.contains(FragmentStyle.superscript)) {
      size *= 0.583;
    }
    return _Format(fragment, font, size);
  }

  static PrawnFont _font(String family, String style, TextContext context) {
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
    final placed = place(width, double.infinity, atTop: true);
    if (placed == null) return 0;
    return placed.height;
  }

  @override
  (double, double) intrinsicWidths() {
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
      final font = item.format.font;
      final size = item.format.size;
      for (final segment in _tokenize(item.text)) {
        final width = font.widthOf(segment, size, kerning: _state.kerning);
        if (_strip(segment).isNotEmpty) least = math.max(least, width);
        line += width;
      }
    }
    return (least, math.max(most, line));
  }

  bool _imagesArranged = false;

  /// Sizes the inline images for [width] points of room, once (the gem's
  /// `InlineImageArranger`): each becomes a placeholder as wide as the
  /// image, raising its line when the image is taller than the text.
  void _arrangeImages(double width) {
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
    final lineFont = PrawnTextBox._font(_state.family, _state.style, _context);
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
    final lines = _Wrap(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
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
  PrawnTextBox resized(double size) {
    final state = TextState(
      family: _state.family,
      size: size,
      style: _state.style,
      color: _state.color,
      kerning: _state.kerning,
      characterSpacing: _state.characterSpacing,
    );
    return PrawnTextBox._(
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
  (List<Fragment>, PrawnTextBox?) splitFirstLine(double width) {
    _arrangeImages(width);
    final wrap = _Wrap(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
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
          : PrawnTextBox._(rest, _state, _layout, _context, first: false),
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
    final wrap = _Wrap(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      available - gap,
      firstPiece: first,
    );
    final lines = wrap.run();
    if (lines.isEmpty) {
      if (!atTop || quiet) return null;
      // Nothing fits even on a fresh page: the gem reports it and drops
      // the text.
      _context.logger.error(
        'cannot fit formatted text on page: '
        '${_items.map((i) => i.text).join()}',
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
          : PrawnTextBox._(rest, _state, _layout, _context, first: false),
      paint: (page, x, top) => _paint(page, lines, x, top - gap),
    );
  }

  void _paint(PdfPage page, List<_Line> lines, double x, double top) {
    final canvas = page.canvas;
    for (final line in lines) {
      for (final f in line.fragments) {
        final fragment = f.format.fragment;
        if (fragment.isMarker) continue;
        final left = x + f.left;
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
          final top = image.lineHeightIncreased
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
              ),
            )
            ..restore();
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

final RegExp _tokens = RegExp(
  '[^$_breakChars]+$_shy|[^$_breakChars]+-+|[^$_breakChars]+|'
  '[ \t$_zwsp]+|-+[^$_breakChars]*|$_shy',
);

final RegExp _wordDivision = RegExp('[\t\n\v\r $_zwsp$_shy-]');

List<String> _tokenize(String text) => [
  for (final m in _tokens.allMatches(text)) m[0]!,
];

/// Prawn's `LineWrap`, `Arranger` and `Wrap` over the items of one piece.
final class _Wrap {
  new(
    this._unconsumed,
    this._state,
    this._layout,
    this._context,
    this._width,
    this._height, {
    required this.firstPiece,
  });

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

  double _widthOf(String text, _Format? format) {
    final font = format?.font ?? _baseFont;
    final size = format?.size ?? _state.size;
    final width = font.widthOf(text, size, kerning: _state.kerning);
    // Prawn 2.4 adds the character spacing between characters.
    final count = text.runes.length;
    return count > 1 ? width + _state.characterSpacing * (count - 1) : width;
  }

  late final PrawnFont _baseFont = PrawnTextBox._font(
    _state.family,
    _state.style,
    _context,
  );

  List<_Line> run() {
    var stop = false;
    var lineNumber = 0;
    while (!stop) {
      final indent = lineNumber == 0 && firstPiece
          ? _layout.indentFirstLine
          : 0.0;
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
        lineNumber++;
        if (_layout.singleLine) stop = true;
      } else {
        stop = true;
      }
      stop = stop || _unconsumed.isEmpty;
    }
    return _lines;
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
    final lastWord =
        RegExp('[^$_breakChars]*\$').stringMatch(_previousFragment) ?? '';
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
        ' '.allMatches(text).length,
      );
      _fragments.add(printed);
      final font = format.font;
      final image = format.image;
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

  void _printLine(double indent) {
    final justify =
        _layout.align == 'justify' &&
        _spaceCount > 0 &&
        (_layout.forceJustify || !_paragraphFinished);
    final wordSpacing = justify
        ? (_width - indent - _accumulatedWidth) / _spaceCount
        : 0.0;
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
    final available = _width - indent;
    final offset = switch (_layout.align) {
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
}

/// A character wider than the line (Prawn's `CannotFit`).
final class _CannotFit implements Exception {
  const new();
}

// Ruby's whitespace (for strip and its kin): ASCII whitespace and NUL,
// never a no-break space.
final RegExp _leadingSpace = RegExp(r'^[\t\n\v\f\r \x00]+');
final RegExp _trailingSpace = RegExp(r'[\t\n\v\f\r \x00]+$');

String _lstrip(String text) => text.replaceFirst(_leadingSpace, '');

String _rstrip(String text) => text.replaceFirst(_trailingSpace, '');

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
  final PrawnTextBox first;

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
    if (rest is! PrawnTextBox) return head;
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
      rest: next is PrawnTextBox ? next.restyled(state, layout) : next,
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
    final box = PrawnTextBox(
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
  final PrawnTextBox text;

  /// The least font size, if any.
  final double? minimum;

  PrawnTextBox _fitted(double width) {
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
