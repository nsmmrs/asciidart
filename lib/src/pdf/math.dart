/// Math in the PDF (ADR-0014): AsciiMath converted to MathML, set by
/// libpdf's math layout in a font with an OpenType `MATH` table.
library;

import 'package:libpdf/libpdf.dart';

/// A formula in a line of text: laid out at the text's size when the
/// line is ([at]), standing on the baseline with its depth below it.
final class InlineMath implements Graphic {
  /// The formula [node], set by [layout]; [source] is what it copies as.
  new(this.node, this.layout, {required this.source});

  /// The formula.
  final MathNode node;

  /// The layout that sets it.
  final MathLayout layout;

  /// Its source (AsciiMath), the text a reader copies.
  final String source;

  final Map<double, MathBox> _boxes = {};

  /// The formula laid out at [size] points.
  MathBox at(double size) =>
      _boxes[size] ??= layout.layout(node, size: size);

  @override
  double get intrinsicWidth => at(10).width;

  @override
  double get intrinsicHeight => at(10).intrinsicHeight;

  @override
  void paint(PdfCanvas canvas, PdfRect rect) => at(10).paint(canvas, rect);
}
