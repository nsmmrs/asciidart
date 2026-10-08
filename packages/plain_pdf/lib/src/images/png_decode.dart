/// PNG scanline filtering (ISO/IEC 15948, 9) and Adam7 interlacing (8.2):
/// from the inflated image data to packed rows, and from packed rows back
/// to filtered data for a FlateDecode stream with a PNG predictor.
library;

import 'dart:typed_data';

/// The geometry of a PNG image's samples.
final class PngLayout {
  /// An image [width] by [height] pixels of [channels] samples, each
  /// [bitDepth] bits.
  const new(this.width, this.height, this.channels, this.bitDepth);

  /// The width, in pixels.
  final int width;

  /// The height, in pixels.
  final int height;

  /// The samples per pixel.
  final int channels;

  /// The bits per sample.
  final int bitDepth;

  /// The bytes of a packed row of [pixels] pixels.
  int rowBytes(int pixels) => (pixels * channels * bitDepth + 7) >> 3;

  /// The bytes per complete pixel (at least 1), the distance filters
  /// look back.
  int get pixelBytes => (channels * bitDepth + 7) >> 3;
}

/// The packed rows (no filter bytes) of an image laid out as [layout],
/// from its inflated, filtered [data].
Uint8List unfilterImage(
  Uint8List data,
  PngLayout layout, {
  required bool interlaced,
}) {
  if (!interlaced) {
    return _unfilter(
      data,
      0,
      layout.rowBytes(layout.width),
      layout.height,
      layout.pixelBytes,
    ).$1;
  }
  final stride = layout.rowBytes(layout.width);
  final image = Uint8List(stride * layout.height);
  var offset = 0;
  for (final (x0, y0, dx, dy) in _adam7) {
    final columns = (layout.width - x0 + dx - 1) ~/ dx;
    final rows = (layout.height - y0 + dy - 1) ~/ dy;
    if (columns <= 0 || rows <= 0) continue;
    final passStride = layout.rowBytes(columns);
    final (pass, end) = _unfilter(
      data,
      offset,
      passStride,
      rows,
      layout.pixelBytes,
    );
    offset = end;
    for (var r = 0; r < rows; r++) {
      final y = y0 + r * dy;
      for (var c = 0; c < columns; c++) {
        _copyPixel(
          pass,
          r * passStride,
          c,
          image,
          y * stride,
          x0 + c * dx,
          layout,
        );
      }
    }
  }
  return image;
}

/// The seven Adam7 passes: first column, first row, column step, row
/// step.
const List<(int, int, int, int)> _adam7 = [
  (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), //
  (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
];

void _copyPixel(
  Uint8List from,
  int fromRow,
  int fromX,
  Uint8List to,
  int toRow,
  int toX,
  PngLayout layout,
) {
  final bits = layout.channels * layout.bitDepth;
  if (bits >= 8) {
    final bytes = bits >> 3;
    to.setRange(
      toRow + toX * bytes,
      toRow + (toX + 1) * bytes,
      from,
      fromRow + fromX * bytes,
    );
    return;
  }
  // 1, 2 or 4 bits per pixel (one channel): move the sample's bits.
  final mask = (1 << bits) - 1;
  final fromBit = fromX * bits;
  final sample =
      (from[fromRow + (fromBit >> 3)] >> (8 - bits - (fromBit & 7))) & mask;
  final toBit = toX * bits;
  final shift = 8 - bits - (toBit & 7);
  final index = toRow + (toBit >> 3);
  to[index] = (to[index] & ~(mask << shift)) | (sample << shift);
}

/// Unfilters [rows] rows of [stride] bytes starting at [offset] in
/// [data]; returns the packed rows and the offset after them.
///
/// Each filter has its own loop, the first [bpp] bytes of a row (which
/// have nothing to their left) and the first row (nothing above) apart.
(Uint8List, int) _unfilter(
  Uint8List data,
  int offset,
  int stride,
  int rows,
  int bpp,
) {
  final out = Uint8List(stride * rows);
  // The bytes of a row with no left neighbor.
  final lead = bpp < stride ? bpp : stride;
  var at = offset;
  for (var r = 0; r < rows; r++) {
    if (at + 1 + stride > data.length) {
      throw const FormatException('PNG image data is truncated');
    }
    final filter = data[at];
    final from = at + 1;
    final row = r * stride;
    final up = row - stride;
    switch (filter) {
      case 0:
        out.setRange(row, row + stride, data, from);
      case 1: // Sub
        out.setRange(row, row + lead, data, from);
        for (var i = lead; i < stride; i++) {
          out[row + i] = data[from + i] + out[row + i - bpp];
        }
      case 2 when r == 0: // Up, from a row of zeros
        out.setRange(row, row + stride, data, from);
      case 2:
        for (var i = 0; i < stride; i++) {
          out[row + i] = data[from + i] + out[up + i];
        }
      case 3 when r == 0: // Average
        out.setRange(row, row + lead, data, from);
        for (var i = lead; i < stride; i++) {
          out[row + i] = data[from + i] + (out[row + i - bpp] >> 1);
        }
      case 3:
        for (var i = 0; i < lead; i++) {
          out[row + i] = data[from + i] + (out[up + i] >> 1);
        }
        for (var i = lead; i < stride; i++) {
          out[row + i] =
              data[from + i] + ((out[row + i - bpp] + out[up + i]) >> 1);
        }
      case 4 when r == 0: // Paeth, from zeros above: the left byte
        out.setRange(row, row + lead, data, from);
        for (var i = lead; i < stride; i++) {
          out[row + i] = data[from + i] + out[row + i - bpp];
        }
      case 4:
        // Nothing to the left: the byte above.
        for (var i = 0; i < lead; i++) {
          out[row + i] = data[from + i] + out[up + i];
        }
        for (var i = lead; i < stride; i++) {
          out[row + i] =
              data[from + i] +
              _paethOf(out[row + i - bpp], out[up + i], out[up + i - bpp]);
        }
      default:
        if (stride > 0) {
          throw FormatException('PNG filter type $filter is not defined');
        }
    }
    at += 1 + stride;
  }
  return (out, at);
}

/// [image]'s packed rows of [stride] bytes filtered again, each row with
/// the filter that leaves the smallest sum of absolute differences (the
/// heuristic of the PNG specification, 12.8; the first of equal ones),
/// for a FlateDecode stream with predictor 15.
Uint8List filterImage(Uint8List image, int stride, int bpp) {
  final rows = stride == 0 ? 0 : image.length ~/ stride;
  final out = Uint8List(rows * (stride + 1));
  // The row above the first: zeros.
  final zeros = Uint8List(stride);
  for (var r = 0; r < rows; r++) {
    final row = r * stride;
    final above = r == 0 ? zeros : image;
    final up = r == 0 ? 0 : row - stride;
    var bestFilter = 0;
    var bestScore = _score(
      image,
      row,
      above,
      up,
      stride,
      bpp,
      0,
      stride * 128 + 1,
    );
    for (var filter = 1; filter <= 4; filter++) {
      final score = _score(
        image,
        row,
        above,
        up,
        stride,
        bpp,
        filter,
        bestScore,
      );
      if (score < bestScore) {
        bestScore = score;
        bestFilter = filter;
      }
    }
    final at = r * (stride + 1);
    out[at] = bestFilter;
    _filterRow(image, row, above, up, stride, bpp, bestFilter, out, at + 1);
  }
  return out;
}

/// The sum of the absolute differences of [filter]'s residuals for the
/// row of [image] at [row] (the row above it in [above] at [up]), or
/// [limit] or more once it reaches it.
int _score(
  Uint8List image,
  int row,
  Uint8List above,
  int up,
  int stride,
  int bpp,
  int filter,
  int limit,
) {
  var score = 0;
  switch (filter) {
    case 0:
      for (var i = 0; i < stride; i++) {
        final v = image[row + i];
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    case 1:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        final v = (image[row + i] - left) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    case 2:
      for (var i = 0; i < stride; i++) {
        final v = (image[row + i] - above[up + i]) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    case 3:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        final v = (image[row + i] - ((left + above[up + i]) >> 1)) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    default:
      for (var i = 0; i < stride; i++) {
        final a = i >= bpp ? image[row + i - bpp] : 0;
        final b = above[up + i];
        final c = i >= bpp ? above[up + i - bpp] : 0;
        final v = (image[row + i] - _paethOf(a, b, c)) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
  }
  return score;
}

/// Writes [filter]'s residuals for the row of [image] at [row] (the row
/// above it in [above] at [up]) to [out] at [at].
void _filterRow(
  Uint8List image,
  int row,
  Uint8List above,
  int up,
  int stride,
  int bpp,
  int filter,
  Uint8List out,
  int at,
) {
  switch (filter) {
    case 0:
      out.setRange(at, at + stride, image, row);
    case 1:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        out[at + i] = image[row + i] - left;
      }
    case 2:
      for (var i = 0; i < stride; i++) {
        out[at + i] = image[row + i] - above[up + i];
      }
    case 3:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        out[at + i] = image[row + i] - ((left + above[up + i]) >> 1);
      }
    default:
      for (var i = 0; i < stride; i++) {
        final a = i >= bpp ? image[row + i - bpp] : 0;
        final b = above[up + i];
        final c = i >= bpp ? above[up + i - bpp] : 0;
        out[at + i] = image[row + i] - _paethOf(a, b, c);
      }
  }
}

/// The Paeth predictor of left [a], above [b] and upper left [c] (the
/// one of them nearest `a + b - c`, in that order on ties), with the
/// absolute values inline.
@pragma('vm:prefer-inline')
int _paethOf(int a, int b, int c) {
  final p = a + b - c;
  var pa = p - a;
  if (pa < 0) pa = -pa;
  var pb = p - b;
  if (pb < 0) pb = -pb;
  var pc = p - c;
  if (pc < 0) pc = -pc;
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
