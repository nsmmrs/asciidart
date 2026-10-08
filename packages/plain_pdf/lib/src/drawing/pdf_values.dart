/// plain_typesetting's values as PDF objects and names.
library;

import 'package:plain_pdf/src/objects.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// A rectangle as a PDF array.
extension RectToPdf on Rect {
  /// The rectangle as a PDF array: `[left bottom right top]`.
  PdfArray toArray() => PdfArray.numbers([left, bottom, right, top]);
}

/// A matrix as a PDF array.
extension MatrixToPdf on Matrix {
  /// The matrix as a PDF array: `[a b c d e f]`.
  PdfArray toArray() => PdfArray.numbers([a, b, c, d, e, f]);
}

/// A blend mode's PDF name.
extension BlendModeToPdf on BlendMode {
  /// The blend mode's PDF name (ISO 32000-2, 11.3.5): `Normal`,
  /// `ColorDodge`...
  String get pdfName => '${name[0].toUpperCase()}${name.substring(1)}';
}
