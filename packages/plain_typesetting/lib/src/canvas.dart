/// The canvas typesetting draws on, whatever the output: an interface a
/// backend implements (plain_pdf's `Canvas` writes PDF content
/// streams), with the line, color, text and blending settings and the
/// text style it takes.
library;

import 'package:meta/meta.dart';
import 'package:plain_typesetting/src/color.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/geometry.dart';

/// The shape at the ends of stroked open lines.
enum LineCap {
  /// Squared off at the end.
  butt,

  /// A semicircle around the end.
  round,

  /// Squared off half the line width past the end.
  projectingSquare,
}

/// The shape of corners of stroked lines.
enum LineJoin {
  /// A pointed corner, beveled past the miter limit.
  miter,

  /// A rounded corner.
  round,

  /// A beveled corner.
  bevel,
}

/// How text is painted (ISO 32000-2, 9.3.6).
enum TextRenderMode {
  /// Filled.
  fill,

  /// Stroked.
  stroke,

  /// Filled, then stroked.
  fillStroke,

  /// Neither (invisible, still selectable).
  invisible,

  /// Filled, and added to the clipping path.
  fillClip,

  /// Stroked, and added to the clipping path.
  strokeClip,

  /// Filled, stroked, and added to the clipping path.
  fillStrokeClip,

  /// Added to the clipping path.
  clip,
}

/// How colors painted over others combine (ISO 32000-2, 11.3.5).
enum BlendMode {
  /// The source color.
  normal,

  /// Multiplied.
  multiply,

  /// Screened.
  screen,

  /// Multiply or screen, by the backdrop.
  overlay,

  /// The darker.
  darken,

  /// The lighter.
  lighten,

  /// Backdrop brightened.
  colorDodge,

  /// Backdrop darkened.
  colorBurn,

  /// Multiply or screen, by the source.
  hardLight,

  /// Darken or lighten, by the source.
  softLight,

  /// The difference.
  difference,

  /// Like difference, lower in contrast.
  exclusion,
}

/// How text is set: the font and size, and the text state parameters.
@immutable
final class TextStyle {
  /// Text in [font] at [size] points.
  const new(
    this.font,
    this.size, {
    this.characterSpacing = 0,
    this.wordSpacing = 0,
    this.rise = 0,
    this.horizontalScaling = 100,
    this.renderMode = TextRenderMode.fill,
    this.kerning = true,
    this.ligatures = false,
    this.features = const {},
    this.skew = 0,
    this.embolden = 0,
  });

  /// The font.
  final Font font;

  /// The size, in points.
  final double size;

  /// Extra space after each glyph, in points.
  final double characterSpacing;

  /// Extra space after each space, in points.
  final double wordSpacing;

  /// The baseline's shift up, in points.
  final double rise;

  /// The horizontal scaling, in percent.
  final double horizontalScaling;

  /// How the glyphs are painted.
  final TextRenderMode renderMode;

  /// Whether the font's kerning applies.
  final bool kerning;

  /// Whether the font's ligatures apply (embedded fonts).
  final bool ligatures;

  /// The OpenType features whose single substitutions apply (embedded
  /// fonts that have them: `onum` old-style numerals, `smcp` small
  /// capitals...).
  final Set<String> features;

  /// How far the glyphs slant: the tangent of the angle (0.2, about 11
  /// degrees, for an oblique face made from an upright one).
  final double skew;

  /// The width of a stroke around the glyphs, in points, in the current
  /// stroke color (a bold face made from a regular one; set the stroke
  /// color to the fill color).
  final double embolden;

  /// This style with the values given changed.
  TextStyle copyWith({
    Font? font,
    double? size,
    double? characterSpacing,
    double? wordSpacing,
    double? rise,
    double? horizontalScaling,
    TextRenderMode? renderMode,
    bool? kerning,
    bool? ligatures,
    Set<String>? features,
    double? skew,
    double? embolden,
  }) => TextStyle(
    font ?? this.font,
    size ?? this.size,
    characterSpacing: characterSpacing ?? this.characterSpacing,
    wordSpacing: wordSpacing ?? this.wordSpacing,
    rise: rise ?? this.rise,
    horizontalScaling: horizontalScaling ?? this.horizontalScaling,
    renderMode: renderMode ?? this.renderMode,
    kerning: kerning ?? this.kerning,
    ligatures: ligatures ?? this.ligatures,
    features: features ?? this.features,
    skew: skew ?? this.skew,
    embolden: embolden ?? this.embolden,
  );

  @override
  bool operator ==(Object other) =>
      other is TextStyle &&
      other.font == font &&
      other.size == size &&
      other.characterSpacing == characterSpacing &&
      other.wordSpacing == wordSpacing &&
      other.rise == rise &&
      other.horizontalScaling == horizontalScaling &&
      other.renderMode == renderMode &&
      other.kerning == kerning &&
      other.ligatures == ligatures &&
      other.skew == skew &&
      other.embolden == embolden &&
      other.features.length == features.length &&
      other.features.containsAll(features);

  @override
  int get hashCode => Object.hash(
    font,
    size,
    characterSpacing,
    wordSpacing,
    rise,
    horizontalScaling,
    renderMode,
    kerning,
    ligatures,
    Object.hashAllUnordered(features),
    skew,
    embolden,
  );

  /// The width of [glyphs] set in this style, in points.
  double widthOf(List<ShapedGlyph> glyphs) {
    var width = 0.0;
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      width += glyph.advance * size / 1000 + characterSpacing;
      if (glyph.text == ' ') width += wordSpacing;
      if (i < glyphs.length - 1) width += glyph.kerning * size / 1000;
    }
    return width * horizontalScaling / 100;
  }

  /// The width of [text] set in this style, in points.
  double measure(String text) => widthOf(shape(text));

  /// [text] as glyphs of this style's font.
  List<ShapedGlyph> shape(String text) => font.shape(
    text,
    kerning: kerning,
    ligatures: ligatures,
    features: features,
  );
}

/// Something to draw on: paths, painted or clipping, text, and the
/// graphics state (a stack, as in PDF and PostScript), in points with y up.
///
/// Fonts and images belong to a backend: a canvas sets the text of the
/// fonts its backend made, and a backend's graphics paint only on its own
/// canvas.
abstract interface class Canvas {
  // Graphics state.

  /// Saves the graphics state.
  void save();

  /// Restores the graphics state saved last.
  void restore();

  /// Runs [draw] between [save] and [restore].
  void saved(void Function() draw);

  /// Transforms the coordinate system by [matrix].
  void transform(Matrix matrix);

  /// Moves the origin to ([x], [y]).
  void translate(double x, double y);

  /// Scales by [x] horizontally and [y] (default [x]) vertically.
  void scale(double x, [double? y]);

  /// Rotates counterclockwise by [degrees].
  void rotate(double degrees);

  /// The width of stroked lines.
  void setLineWidth(double width);

  /// The shape of line ends.
  void setLineCap(LineCap cap);

  /// The shape of corners.
  void setLineJoin(LineJoin join);

  /// The miter limit.
  void setMiterLimit(double limit);

  /// The dash pattern: alternating dash and gap lengths starting at
  /// [phase]; empty for solid lines.
  void dash(List<double> pattern, [double phase = 0]);

  /// The color of fills, text included.
  void setFillColor(Color color);

  /// The color of strokes.
  void setStrokeColor(Color color);

  /// The opacity of fills and of strokes (0 transparent, 1 opaque).
  void opacity({double? fill, double? stroke});

  /// The blend mode.
  void setBlendMode(BlendMode mode);

  // Paths.

  /// Starts a subpath at ([x], [y]).
  void moveTo(double x, double y);

  /// A line to ([x], [y]).
  void lineTo(double x, double y);

  /// A cubic Bézier curve to ([x3], [y3]) with control points ([x1],
  /// [y1]) and ([x2], [y2]).
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  );

  /// Closes the subpath.
  void closePath();

  /// A rectangle.
  void rect(Rect rect);

  /// A rectangle with corners rounded to [radius].
  void roundedRect(Rect rect, double radius);

  /// An ellipse centered on ([cx], [cy]) with radii [rx] and [ry].
  void ellipse(double cx, double cy, double rx, double ry);

  /// A circle centered on ([cx], [cy]) of [radius].
  void circle(double cx, double cy, double radius);

  /// Fills the path (with the even-odd rule when [evenOdd]).
  void fill({bool evenOdd = false});

  /// Strokes the path.
  void stroke();

  /// Fills, then strokes the path.
  void fillAndStroke({bool evenOdd = false});

  /// Intersects the clipping path with the path, without painting it.
  void clip({bool evenOdd = false});

  /// Ends the path without painting it.
  void endPath();

  // Marked content.

  /// Begins a sequence of content tagged [tag] (as PDF's marked content),
  /// to end with [endMarkedContent]. With [actualText], the sequence reads
  /// as that text when text is extracted, copied or read aloud: an empty
  /// one leaves decorative glyphs out.
  void beginMarkedContent(String tag, {String? actualText});

  /// Ends the sequence [beginMarkedContent] began.
  void endMarkedContent();

  // Text.

  /// Draws [text] in [style] with its baseline starting at ([x], [y]);
  /// returns its width.
  double text(String text, double x, double y, TextStyle style);

  /// Draws shaped [glyphs] of [style]'s font with the baseline starting
  /// at ([x], [y]); returns their width.
  double glyphs(List<ShapedGlyph> glyphs, double x, double y, TextStyle style);
}
