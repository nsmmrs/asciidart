/// Graphics that are drawn into a rectangle: raster images and SVG
/// images alike.
library;

import 'package:plain_pdf/src/drawing/canvas.dart';
import 'package:plain_pdf/src/drawing/geometry.dart';

/// Something with an intrinsic size that is drawn into a rectangle.
abstract interface class Graphic {
  /// The natural width, in points.
  double get intrinsicWidth;

  /// The natural height, in points.
  double get intrinsicHeight;

  /// Draws the graphic into [rect].
  void paint(PdfCanvas canvas, PdfRect rect);
}
