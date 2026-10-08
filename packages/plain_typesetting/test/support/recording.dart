// A canvas, a page and a document that record what is drawn on them, as
// text, for tests to check layouts without a backend.
import 'package:plain_typesetting/plain_typesetting.dart';

String _n(double v) => v.toStringAsFixed(2);

String _ns(List<double> values) => values.map(_n).join(' ');

String _color(Color color) => switch (color) {
  GrayColor(:final level) => 'gray ${_n(level)}',
  RgbColor(:final red, :final green, :final blue) =>
    'rgb ${_n(red)} ${_n(green)} ${_n(blue)}',
  CmykColor(:final cyan, :final magenta, :final yellow, :final black) =>
    'cmyk ${_n(cyan)} ${_n(magenta)} ${_n(yellow)} ${_n(black)}',
  SpotColor(:final name, :final tint) => 'spot $name ${_n(tint)}',
};

/// A canvas that records each call as a line.
final class RecordingCanvas implements Canvas {
  /// What was drawn, a call a line.
  final List<String> calls = [];

  void _add(String call) => calls.add(call);

  @override
  void save() => _add('save');

  @override
  void restore() => _add('restore');

  @override
  void saved(void Function() draw) {
    save();
    draw();
    restore();
  }

  @override
  void transform(Matrix matrix) => _add(
    'transform '
    '${_ns([matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f])}',
  );

  @override
  void translate(double x, double y) => transform(Matrix.translation(x, y));

  @override
  void scale(double x, [double? y]) => transform(Matrix.scaling(x, y ?? x));

  @override
  void rotate(double degrees) => _add('rotate ${_n(degrees)}');

  @override
  void setLineWidth(double width) => _add('lineWidth ${_n(width)}');

  @override
  void setLineCap(LineCap cap) => _add('lineCap ${cap.name}');

  @override
  void setLineJoin(LineJoin join) => _add('lineJoin ${join.name}');

  @override
  void setMiterLimit(double limit) => _add('miterLimit ${_n(limit)}');

  @override
  void dash(List<double> pattern, [double phase = 0]) =>
      _add('dash ${pattern.map(_n).join(' ')} ${_n(phase)}');

  @override
  void setFillColor(Color color) => _add('fill color ${_color(color)}');

  @override
  void setStrokeColor(Color color) => _add('stroke color ${_color(color)}');

  @override
  void opacity({double? fill, double? stroke}) => _add('opacity $fill $stroke');

  @override
  void setBlendMode(BlendMode mode) => _add('blend ${mode.name}');

  @override
  void moveTo(double x, double y) => _add('moveTo ${_n(x)} ${_n(y)}');

  @override
  void lineTo(double x, double y) => _add('lineTo ${_n(x)} ${_n(y)}');

  @override
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => _add('curveTo ${[x1, y1, x2, y2, x3, y3].map(_n).join(' ')}');

  @override
  void closePath() => _add('closePath');

  @override
  void rect(Rect rect) =>
      _add('rect ${_ns([rect.left, rect.bottom, rect.width, rect.height])}');

  @override
  void roundedRect(Rect rect, double radius) => _add(
    'roundedRect '
    '${_ns([rect.left, rect.bottom, rect.width, rect.height, radius])}',
  );

  @override
  void ellipse(double cx, double cy, double rx, double ry) =>
      _add('ellipse ${[cx, cy, rx, ry].map(_n).join(' ')}');

  @override
  void circle(double cx, double cy, double radius) =>
      ellipse(cx, cy, radius, radius);

  @override
  void fill({bool evenOdd = false}) => _add(evenOdd ? 'fill evenOdd' : 'fill');

  @override
  void stroke() => _add('stroke');

  @override
  void fillAndStroke({bool evenOdd = false}) => _add('fillAndStroke');

  @override
  void clip({bool evenOdd = false}) => _add('clip');

  @override
  void endPath() => _add('endPath');

  @override
  void beginMarkedContent(String tag, {String? actualText}) =>
      _add('begin $tag ${actualText ?? ''}'.trimRight());

  @override
  void endMarkedContent() => _add('end');

  @override
  double text(String text, double x, double y, TextStyle style) =>
      glyphs(style.shape(text), x, y, style);

  @override
  double glyphs(List<ShapedGlyph> glyphs, double x, double y, TextStyle style) {
    _add(
      'glyphs "${glyphs.map((g) => g.text).join()}" at ${_n(x)} ${_n(y)} '
      '${style.font.name} ${_n(style.size)}',
    );
    return style.widthOf(glyphs);
  }
}

/// A page that records what is drawn on it and its links.
final class RecordingPage implements LayoutPage {
  /// A page that is [box].
  new(this.box);

  /// The page's extent.
  final Rect box;

  @override
  final RecordingCanvas canvas = RecordingCanvas();

  /// The links made, as `left bottom width height -> target`.
  final List<String> links = [];

  @override
  void link(Rect rect, LinkTarget target) => links.add(
    '${[rect.left, rect.bottom, rect.width, rect.height].map(_n).join(' ')} '
    '-> ${switch (target) {
      UriTarget(:final uri) => uri,
      NamedTarget(:final name) => '#$name',
      _ => '$target',
    }}',
  );

  /// The text drawn on the page, a run a line.
  List<String> get texts => [
    for (final call in canvas.calls)
      if (call.startsWith('glyphs "')) call.substring(8, call.indexOf('" at')),
  ];
}

/// A document of [RecordingPage]s, recording its anchors.
final class RecordingDocument implements LayoutDocument<RecordingPage> {
  /// The pages, in order.
  final List<RecordingPage> pages = [];

  /// The anchors, by name: the page's index and the point.
  final Map<String, (int, double, double)> anchors = {};

  @override
  RecordingPage addPage(Rect mediaBox, {Rect? bleedBox, Rect? trimBox}) {
    final page = RecordingPage(mediaBox);
    pages.add(page);
    return page;
  }

  @override
  void addAnchor(String name, RecordingPage page, double left, double top) =>
      anchors[name] = (pages.indexOf(page), left, top);
}
