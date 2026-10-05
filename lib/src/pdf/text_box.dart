/// Text laid out as Prawn 2.4 lays it out, with asciidoctor-pdf 2.3.27's
/// extensions: fragments wrapped line by line (Prawn's `LineWrap`, with
/// word joiners), each line as tall as its tallest fragment, baselines
/// placed with the leading and the gaps asciidoctor-pdf passes,
/// justification by word spacing, font fallback per glyph. A
/// [PrawnTextBox] is libpdf custom content: the layout gives it the room
/// left on the page and it places the lines that fit.
library;

import 'dart:math' as math;

import 'package:asciidart/src/logging.dart';
import 'package:asciidart/src/pdf/fonts.dart';
import 'package:asciidart/src/pdf/markup.dart';
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

  /// The indent of the first line.
  final double indentFirstLine;

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
    LoggerBase? logger,
  }) : logger = logger ?? LoggerManager.logger;

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
  new(this.text, this.format);

  String text;
  final _Format format;
  bool excludeTrailingWhiteSpace = false;
  bool normalizedSoftHyphen = false;

  _Item copy({String? text}) => _Item(text ?? this.text, format)
    ..excludeTrailingWhiteSpace = excludeTrailingWhiteSpace
    ..normalizedSoftHyphen = normalizedSoftHyphen;
}

/// A fragment's formatting with its font resolved.
final class _Format {
  new(this.fragment, this.font, this.size);

  final Fragment fragment;
  final PrawnFont font;
  final double size;

  bool get subscript =>
      fragment.styles?.contains(FragmentStyle.subscript) ?? false;
  bool get superscript =>
      fragment.styles?.contains(FragmentStyle.superscript) ?? false;
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

  double get ascender =>
      format.fragment.isMarker ? 0 : format.font.ascenderAt(format.size);
  double get descender => format.font.descenderAt(format.size);
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
      final copy = fragment.copy()..color ??= state.color;
      for (final run in _withFallbacks(copy, state, context)) {
        final format = _resolve(run, state, context);
        // One item per line of the fragment (Prawn's `format_array=`).
        for (final m in RegExp('[^\n]+|\n').allMatches(run.text)) {
          items.add(_Item(m[0]!, format));
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

  /// Whether this is the first piece of the text (its first line is
  /// indented).
  final bool first;

  /// Whether there is no text.
  bool get isEmpty => _items.isEmpty;

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
        if (segment.trim().isNotEmpty) least = math.max(least, width);
        line += width;
      }
    }
    return (least, math.max(most, line));
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (_items.isEmpty) {
      return CustomPlacement(
        height: _layout.paddingBottom,
        paint: (page, x, top) {},
      );
    }
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
      if (!atTop) return null;
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
    if (_layout.finalGap) height += wrap.lineGap + _layout.leading;
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
        if (f.text.isNotEmpty) {
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
            ..setLineWidth((fragment.textDecorationWidth ?? 1).toDouble());
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
          page.link(box, LinkTarget.named(anchor));
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
        fragment.trim().isNotEmpty) {
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
      if (item.text.trim().isEmpty && _consumed.length > 1) {
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
        text = text.trimRight();
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
      _maxLineHeight = math.max(_maxLineHeight, font.heightAt(format.size));
      _maxDescender = math.max(_maxDescender, font.descenderAt(format.size));
      _maxAscender = math.max(
        _maxAscender,
        isMarker ? 0 : font.ascenderAt(format.size),
      );
    }
    _spaceCount = _fragments.fold(0, (sum, f) => sum + f.spaces);
  }

  double _fragmentWidth(String text, _Format format) {
    final fragment = format.fragment;
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

  static String _lstrip(String text) =>
      text.replaceFirst(RegExp(r'^[\s\x00]+'), '');

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
