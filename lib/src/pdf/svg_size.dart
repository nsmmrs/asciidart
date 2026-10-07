/// The size prawn-svg (0.34) gives an SVG image, which the PDF backend
/// sizes images by.
library;

import 'package:libpdf/libpdf.dart';

/// The size prawn-svg gives [svg] (its `DocumentSizing`): the root's
/// width and height (user units are points), the [requestedWidth] or
/// [requestedHeight] scaling it.
(double, double) prawnSvgSize(
  SvgImage svg,
  double? requestedWidth,
  double? requestedHeight,
  double boundsWidth,
  double boundsHeight,
) {
  final containerWidth = requestedWidth ?? boundsWidth;
  final containerHeight = requestedHeight ?? boundsHeight;
  double? pixels(String? value, double axis) {
    if (value == null) return null;
    final number =
        double.tryParse(
          RegExp(r'^\s*[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')
                  .stringMatch(value)
                  ?.trim() ??
              '',
        ) ??
        0;
    final unit = RegExp(r'\d(em|ex|pc|cm|mm|in)$').firstMatch(value)?[1];
    return switch (unit) {
      'em' => number * 16,
      'ex' => number * 8,
      'pc' => number * 15,
      'cm' => number / 2.54 * 72,
      'mm' => number / 25.4 * 72,
      'in' => number * 72,
      _ => value.endsWith('%') ? number * axis / 100 : number,
    };
  }

  var outputWidth =
      pixels(svg.rootAttribute('width'), containerWidth) ?? requestedWidth;
  var outputHeight =
      pixels(svg.rootAttribute('height'), containerHeight) ?? requestedHeight;
  final viewBox = svg
      .rootAttribute('viewBox')
      ?.trim()
      .split(RegExp(r'(?:\s+,?\s*|,\s*)'))
      .map((v) => double.tryParse(v) ?? 0)
      .toList();
  if (viewBox != null &&
      viewBox.length >= 4 &&
      viewBox[2] > 0 &&
      viewBox[3] > 0) {
    if (outputWidth == null && outputHeight == null) {
      outputWidth = containerWidth;
    }
    outputWidth ??= outputHeight! * viewBox[2] / viewBox[3];
    outputHeight ??= outputWidth * viewBox[3] / viewBox[2];
  } else {
    outputWidth ??= containerWidth;
    outputHeight ??= containerHeight;
  }
  if (requestedWidth != null && outputWidth > 0) {
    outputHeight *= requestedWidth / outputWidth;
    outputWidth = requestedWidth;
  } else if (requestedHeight != null && outputHeight > 0) {
    outputWidth *= requestedHeight / outputHeight;
    outputHeight = requestedHeight;
  }
  return (outputWidth, outputHeight);
}
