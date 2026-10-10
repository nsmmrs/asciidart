/// The canvas pages and forms are drawn on: a typed front for the
/// content-stream operators (ISO 32000-2, 8 and 9), keeping track of the
/// resources the content uses. There is no hidden state beyond what PDF
/// itself keeps (the graphics state stack): text is always drawn at an
/// explicit position.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_pdf/src/byte_writer.dart';
import 'package:plain_pdf/src/drawing/shading.dart';
import 'package:plain_pdf/src/fonts/fonts.dart';
import 'package:plain_pdf/src/images/images.dart';
import 'package:plain_pdf/src/objects.dart';
import 'package:plain_pdf/src/reader/reader.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// What a soft mask takes from its form (ISO 32000-2, 11.6.5.2).
enum SoftMaskKind {
  /// The luminosity of the form's colors.
  luminosity('Luminosity'),

  /// The form's alpha.
  alpha('Alpha');

  new(this.pdfName);

  /// The kind's PDF name.
  final String pdfName;
}

/// A transparency group (ISO 32000-2, 11.6.6): a form painted as one
/// object.
@immutable
final class TransparencyGroup {
  /// A group; [isolated] ones start from a transparent backdrop,
  /// [knockout] ones paint each object over the group's backdrop rather
  /// than over each other.
  const new({this.isolated = false, this.knockout = false});

  /// Whether the group is isolated.
  final bool isolated;

  /// Whether the group is a knockout group.
  final bool knockout;
}

/// A form XObject: content drawn once and painted wherever it is used
/// (ISO 32000-2, 8.10), also the content of soft masks.
final class PdfForm {
  /// A form whose content is in [bbox], drawn by [draw].
  new(
    this.bbox,
    void Function(PdfCanvas canvas) draw, {
    this.group,
    this.matrix,
  }) {
    draw(_canvas);
    if (_canvas._unbalanced case final problem?) throw StateError(problem);
  }

  /// The form's bounding box, in its own space.
  final Rect bbox;

  /// The transparency group the form is, if any.
  final TransparencyGroup? group;

  /// The transformation from form space to the space it is painted in.
  final Matrix? matrix;

  final PdfCanvas _canvas = PdfCanvas._();
}

/// The canvas [form] is drawn on.
@internal
PdfCanvas formCanvas(PdfForm form) => form._canvas;

/// A new, empty canvas (for a page).
@internal
PdfCanvas newCanvas() => PdfCanvas._();

/// [canvas] as the PDF canvas it must be for [what] (a PDF image, form or
/// page, which belong to a PDF's resources) to paint on.
PdfCanvas pdfCanvasOf(Canvas canvas, String what) => switch (canvas) {
  final PdfCanvas pdf => pdf,
  _ => throw ArgumentError.value(
    canvas,
    'canvas',
    '$what paints on a PdfCanvas',
  ),
};

/// [style]'s font, which must be a PDF font to be set on a PDF canvas.
PdfFont _pdfFont(TextStyle style) => switch (style.font) {
  final PdfFont font => font,
  final other => throw ArgumentError.value(
    other,
    'style.font',
    'a PDF canvas sets text in PdfFonts',
  ),
};

/// The resources [canvas]'s content uses, by category (`Font`,
/// `XObject`, `ExtGState`, `ColorSpace`, `Shading`) and name.
@internal
Map<String, Map<String, Resource>> canvasResources(PdfCanvas canvas) =>
    canvas._resources;

/// The content stream of [canvas].
@internal
Uint8List canvasContent(PdfCanvas canvas) => canvas._content.toBytes();

/// Whether [canvas]'s content uses transparency.
@internal
bool canvasUsesTransparency(PdfCanvas canvas) => canvas._usesTransparency;

/// What is left open at the end of [canvas]'s content (a save without its
/// restore, an unpainted path), or null.
@internal
String? canvasUnbalanced(PdfCanvas canvas) => canvas._unbalanced;

/// A resource content refers to by name.
@internal
sealed class Resource {
  const new();
}

/// A font.
@internal
final class FontResource extends Resource {
  /// The resource of [font].
  const new(this.font);

  /// The font.
  final PdfFont font;
}

/// An image.
@internal
final class ImageResource extends Resource {
  /// The resource of [image].
  const new(this.image);

  /// The image.
  final PdfImage image;
}

/// A form.
@internal
final class FormResource extends Resource {
  /// The resource of [form].
  const new(this.form);

  /// The form.
  final PdfForm form;
}

/// A page of another file.
@internal
final class ImportedPageResource extends Resource {
  /// The resource of [page].
  const new(this.page);

  /// The page.
  final ImportedPage page;
}

/// A spot color's Separation color space.
@internal
final class SeparationResource extends Resource {
  /// The color space of [name], approximated by [alternate].
  const new(this.name, this.alternate);

  /// The colorant.
  final String name;

  /// Its CMYK alternate.
  final CmykColor alternate;
}

/// A shading.
@internal
final class ShadingResource extends Resource {
  /// The resource of [shading].
  const new(this.shading);

  /// The shading.
  final PdfShading shading;
}

/// Graphics state parameters (an ExtGState dictionary).
@internal
final class GraphicsStateResource extends Resource {
  /// The parameters: opacity, blend mode, soft mask.
  const new({
    this.fillOpacity,
    this.strokeOpacity,
    this.blendMode,
    this.softMask,
    this.clearSoftMask = false,
  });

  /// The fill opacity (`ca`).
  final double? fillOpacity;

  /// The stroke opacity (`CA`).
  final double? strokeOpacity;

  /// The blend mode (`BM`).
  final BlendMode? blendMode;

  /// The soft mask (`SMask`): its form and kind.
  final (PdfForm, SoftMaskKind)? softMask;

  /// Whether the parameters remove the soft mask (`/SMask /None`).
  final bool clearSoftMask;
}

/// A page's or form's content: operators appended in order.
final class PdfCanvas implements Canvas {
  new _();

  final ByteWriter _content = ByteWriter();

  final Map<String, Map<String, Resource>> _resources = {};

  final Map<Object, String> _names = {};

  int _depth = 0;
  bool _path = false;

  bool _usesTransparency = false;

  String? get _unbalanced => _depth != 0
      ? '$_depth save() calls without restore()'
      : _path
      ? 'a path was left without painting it'
      : null;

  // Each operator is written straight to bytes, its operands formatted as
  // formatNumber formats them.

  void _op(String operator) => _content.operator(operator);

  void _op1(double a, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op2(double a, double b, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op3(double a, double b, double c, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..number(c, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op4(double a, double b, double c, double d, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..number(c, 5)
    ..byte(0x20)
    ..number(d, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op6(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
    String operator,
  ) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..number(c, 5)
    ..byte(0x20)
    ..number(d, 5)
    ..byte(0x20)
    ..number(e, 5)
    ..byte(0x20)
    ..number(f, 5)
    ..byte(0x20)
    ..operator(operator);

  void _opInt(int a, String operator) => _content
    ..numeric(a)
    ..byte(0x20)
    ..operator(operator);

  void _named(String operator, String name) => _content
    ..name(name)
    ..byte(0x20)
    ..operator(operator);

  /// The name [resource] has in [category], given by its first use.
  String _use(String category, Object key, Resource resource, String prefix) {
    final name = _names[key] ??= '$prefix${_names.length + 1}';
    (_resources[category] ??= {})[name] = resource;
    return name;
  }

  void _noPath(String what) {
    if (_path) throw StateError('$what inside a path: paint it first');
  }

  // Graphics state.

  /// Saves the graphics state (`q`).
  @override
  void save() {
    _noPath('save()');
    _depth += 1;
    _op('q');
  }

  /// Restores the graphics state saved last (`Q`).
  @override
  void restore() {
    _noPath('restore()');
    if (_depth == 0) throw StateError('restore() without save()');
    _depth -= 1;
    _op('Q');
  }

  /// Runs [draw] between [save] and [restore].
  @override
  void saved(void Function() draw) {
    save();
    draw();
    restore();
  }

  /// Transforms the coordinate system by [matrix] (`cm`).
  @override
  void transform(Matrix matrix) {
    _noPath('transform()');
    _op6(matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f, 'cm');
  }

  /// Moves the origin to ([x], [y]).
  @override
  void translate(double x, double y) => transform(Matrix.translation(x, y));

  /// Scales by [x] horizontally and [y] (default [x]) vertically.
  @override
  void scale(double x, [double? y]) => transform(Matrix.scaling(x, y ?? x));

  /// Rotates counterclockwise by [degrees].
  @override
  void rotate(double degrees) =>
      transform(Matrix.rotation(degrees * math.pi / 180));

  /// The width of stroked lines (`w`).
  @override
  void setLineWidth(double width) => _op1(width, 'w');

  /// The shape of line ends (`J`).
  @override
  void setLineCap(LineCap cap) => _opInt(cap.index, 'J');

  /// The shape of corners (`j`).
  @override
  void setLineJoin(LineJoin join) => _opInt(join.index, 'j');

  /// The miter limit (`M`).
  @override
  void setMiterLimit(double limit) => _op1(limit, 'M');

  /// The dash pattern (`d`): alternating dash and gap lengths starting at
  /// [phase]; empty for solid lines.
  @override
  void dash(List<double> pattern, [double phase = 0]) {
    // The array as PdfArray writes it (on the web, its whole numbers are
    // PdfInts, and -0.0 is written as 0).
    _content
      ..bytes(PdfArray.numbers(pattern).toBytes())
      ..commit()
      ..byte(0x20)
      ..number(phase, 5)
      ..operator(' d');
  }

  /// The color of fills, text included.
  @override
  void setFillColor(Color color) => _color(color, stroke: false);

  /// The color of strokes.
  @override
  void setStrokeColor(Color color) => _color(color, stroke: true);

  void _color(Color color, {required bool stroke}) {
    switch (color) {
      case GrayColor(:final level):
        _op1(level, stroke ? 'G' : 'g');
      case RgbColor(:final red, :final green, :final blue):
        _op3(red, green, blue, stroke ? 'RG' : 'rg');
      case CmykColor(:final cyan, :final magenta, :final yellow, :final black):
        _op4(cyan, magenta, yellow, black, stroke ? 'K' : 'k');
      case SpotColor(:final name, :final alternate, :final tint):
        final space = _use(
          'ColorSpace',
          ('separation', name, alternate),
          SeparationResource(name, alternate),
          'CS',
        );
        _named(stroke ? 'CS' : 'cs', space);
        _op1(tint, stroke ? 'SCN' : 'scn');
    }
  }

  void _graphicsState(Object key, GraphicsStateResource state) {
    _noPath('a graphics state change');
    _usesTransparency = true;
    _named('gs', _use('ExtGState', key, state, 'GS'));
  }

  /// The opacity of fills and of strokes (0 transparent, 1 opaque).
  @override
  void opacity({double? fill, double? stroke}) => _graphicsState((
    'opacity',
    fill,
    stroke,
  ), GraphicsStateResource(fillOpacity: fill, strokeOpacity: stroke));

  /// The blend mode.
  @override
  void setBlendMode(BlendMode mode) =>
      _graphicsState(('blend', mode), GraphicsStateResource(blendMode: mode));

  /// Masks what is painted next by [mask] (a form with a transparency
  /// group), until the state is restored or [clearSoftMask] is called.
  void softMask(PdfForm mask, {SoftMaskKind kind = SoftMaskKind.luminosity}) {
    if (mask.group == null) {
      throw ArgumentError.value(
        mask,
        'mask',
        'a soft mask must be a form with a transparency group',
      );
    }
    _graphicsState((
      'softMask',
      mask,
      kind,
    ), GraphicsStateResource(softMask: (mask, kind)));
  }

  /// Removes the soft mask.
  void clearSoftMask() => _graphicsState(
    'clearSoftMask',
    const GraphicsStateResource(clearSoftMask: true),
  );

  // Paths.

  /// Starts a subpath at ([x], [y]) (`m`).
  @override
  void moveTo(double x, double y) {
    _path = true;
    _op2(x, y, 'm');
  }

  /// A line to ([x], [y]) (`l`).
  @override
  void lineTo(double x, double y) {
    _needPath('lineTo()');
    _op2(x, y, 'l');
  }

  /// A cubic Bézier curve to ([x3], [y3]) with control points ([x1],
  /// [y1]) and ([x2], [y2]) (`c`).
  @override
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _needPath('curveTo()');
    _op6(x1, y1, x2, y2, x3, y3, 'c');
  }

  /// Closes the subpath (`h`).
  @override
  void closePath() {
    _needPath('closePath()');
    _op('h');
  }

  void _needPath(String what) {
    if (!_path) throw StateError('$what needs a current point: moveTo() first');
  }

  /// A rectangle (`re`).
  @override
  void rect(Rect rect) {
    _path = true;
    _op4(rect.left, rect.bottom, rect.width, rect.height, 're');
  }

  /// A rectangle with corners rounded to [radius].
  @override
  void roundedRect(Rect rect, double radius) {
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    if (r <= 0) return this.rect(rect);
    final k = r * _kappa;
    final Rect(:left, :bottom, :right, :top) = rect;
    moveTo(left + r, bottom);
    lineTo(right - r, bottom);
    curveTo(right - r + k, bottom, right, bottom + r - k, right, bottom + r);
    lineTo(right, top - r);
    curveTo(right, top - r + k, right - r + k, top, right - r, top);
    lineTo(left + r, top);
    curveTo(left + r - k, top, left, top - r + k, left, top - r);
    lineTo(left, bottom + r);
    curveTo(left, bottom + r - k, left + r - k, bottom, left + r, bottom);
    closePath();
  }

  /// An ellipse centered on ([cx], [cy]) with radii [rx] and [ry], as four
  /// Bézier curves.
  @override
  void ellipse(double cx, double cy, double rx, double ry) {
    final kx = rx * _kappa;
    final ky = ry * _kappa;
    moveTo(cx + rx, cy);
    curveTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
    curveTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
    curveTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
    curveTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
    closePath();
  }

  /// A circle centered on ([cx], [cy]) of [radius].
  @override
  void circle(double cx, double cy, double radius) =>
      ellipse(cx, cy, radius, radius);

  /// The control point distance of a quarter circle of radius 1.
  static final double _kappa = 4 * (math.sqrt(2) - 1) / 3;

  void _paint(String operator) {
    _needPath('painting');
    _path = false;
    _op(operator);
  }

  /// Fills the path (`f`, or `f*` with the even-odd rule).
  @override
  void fill({bool evenOdd = false}) => _paint(evenOdd ? 'f*' : 'f');

  /// Strokes the path (`S`).
  @override
  void stroke() => _paint('S');

  /// Fills, then strokes the path (`B`, or `B*`).
  @override
  void fillAndStroke({bool evenOdd = false}) => _paint(evenOdd ? 'B*' : 'B');

  /// Intersects the clipping path with the path, without painting it
  /// (`W n`, or `W* n`).
  @override
  void clip({bool evenOdd = false}) {
    _needPath('clip()');
    _op(evenOdd ? 'W*' : 'W');
    _paint('n');
  }

  /// Ends the path without painting it (`n`).
  @override
  void endPath() => _paint('n');

  /// Paints [shading] over the clipping region (`sh`): clip to a path
  /// first to fill it with a gradient.
  void shade(PdfShading shading) {
    _noPath('shade()');
    _named('sh', _use('Shading', shading, ShadingResource(shading), 'Sh'));
  }

  // Images and forms.

  /// Paints [image] into [rect].
  void image(PdfImage image, Rect rect) {
    _noPath('image()');
    final name = _use('XObject', image, ImageResource(image), 'Im');
    _op('q');
    _op6(rect.width, 0, 0, rect.height, rect.left, rect.bottom, 'cm');
    _named('Do', name);
    _op('Q');
  }

  /// Paints [page], a page of another file, into [rect].
  void page(ImportedPage page, Rect rect) {
    _noPath('page()');
    if (page.group != null) _usesTransparency = true;
    final name = _use('XObject', page, ImportedPageResource(page), 'Pg');
    final m = page.placement(rect);
    _op('q');
    _op6(m.a, m.b, m.c, m.d, m.e, m.f, 'cm');
    _named('Do', name);
    _op('Q');
  }

  /// Paints [form] (`Do`).
  void form(PdfForm form) {
    _noPath('form()');
    if (form.group != null || form._canvas._usesTransparency) {
      _usesTransparency = true;
    }
    _named('Do', _use('XObject', form, FormResource(form), 'Fm'));
  }

  // Marked content.

  /// Begins a marked-content sequence tagged [tag] (ISO 32000-2, 14.6),
  /// to end with [endMarkedContent]. With [actualText], the sequence's
  /// content reads as that text when text is extracted, copied or read
  /// aloud (14.9.4): an empty one leaves decorative glyphs out.
  @override
  void beginMarkedContent(String tag, {String? actualText}) {
    _noPath('marked content');
    _content.name(tag);
    if (actualText != null) {
      _content
        ..byte(0x20)
        ..bytes(PdfDict({'ActualText': PdfString.text(actualText)}).toBytes())
        ..operator(' BDC');
    } else {
      _content.operator(' BMC');
    }
  }

  /// Ends the marked-content sequence [beginMarkedContent] began.
  @override
  void endMarkedContent() => _op('EMC');

  // Text.

  /// Draws [text] in [style] with its baseline starting at ([x], [y]);
  /// returns its width.
  @override
  double text(String text, double x, double y, TextStyle style) =>
      glyphs(style.shape(text), x, y, style);

  /// Draws shaped [glyphs] of [style]'s font with the baseline starting
  /// at ([x], [y]); returns their width.
  @override
  double glyphs(List<ShapedGlyph> glyphs, double x, double y, TextStyle style) {
    _noPath('text');
    final font = _pdfFont(style);
    final fontName = _use('Font', font, FontResource(font), 'F');
    final embolden = style.embolden > 0;
    // The stroke's width stays with the text.
    if (embolden) _op('q');
    _op('BT');
    _content
      ..name(fontName)
      ..commit()
      ..byte(0x20)
      ..number(style.size, 5)
      ..operator(' Tf');
    if (style.characterSpacing != 0) _op1(style.characterSpacing, 'Tc');
    if (style.rise != 0) _op1(style.rise, 'Ts');
    if (style.horizontalScaling != 100) _op1(style.horizontalScaling, 'Tz');
    if (embolden) {
      _op1(style.embolden, 'w');
      _opInt(TextRenderMode.fillStroke.index, 'Tr');
    } else if (style.renderMode != TextRenderMode.fill) {
      _opInt(style.renderMode.index, 'Tr');
    }
    if (style.skew != 0) {
      _op6(1, 0, style.skew, 1, x, y, 'Tm');
    } else {
      _op2(x, y, 'Td');
    }
    _showText(glyphs, style);
    _op('ET');
    if (embolden) _op('Q');
    return style.widthOf(glyphs);
  }

  /// The `TJ` operator showing [glyphs]: runs of glyph codes, with the
  /// kerning and the word spacing between them as adjustments.
  void _showText(List<ShapedGlyph> glyphs, TextStyle style) {
    final font = _pdfFont(style);
    final codes = font.encode(glyphs);
    final width = switch (font) {
      StandardFont() => 1,
      EmbeddedFont() => 2,
    };
    final hex = font is EmbeddedFont;
    // (The word spacing to a hundred-thousandth of a point, as a `Tw`
    // operand would give it, in thousandths of the size.)
    final wordSpacing = style.wordSpacing != 0
        ? (style.wordSpacing * 1e5).round() / 1e5 * 1000 / style.size
        : 0.0;
    final out = _content..byte(0x5b); // [
    final last = glyphs.length - 1;
    var start = 0;
    for (var i = 0; i <= last; i++) {
      final glyph = glyphs[i];
      var adjustment = 0.0;
      if (i < last) adjustment -= glyph.kerning;
      if (wordSpacing != 0 && glyph.text == ' ') adjustment -= wordSpacing;
      if (adjustment != 0) {
        final end = (i + 1) * width;
        if (end != start) out.string(codes, start, end, hex: hex);
        start = end;
        out
          ..byte(0x20)
          ..number(adjustment, 5)
          ..byte(0x20);
      }
    }
    final end = glyphs.length * width;
    if (end != start) out.string(codes, start, end, hex: hex);
    out.operator('] TJ');
  }
}
