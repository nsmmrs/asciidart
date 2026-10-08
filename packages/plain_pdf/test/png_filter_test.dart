// PNG filtering for image streams: the fast filter chooser gives what the
// specification's heuristic, written plainly, gives.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:plain_pdf/src/images/png_decode.dart';
import 'package:test/test.dart';

/// The heuristic as the specification puts it (12.8): each filter's
/// residuals, the one with the smallest sum of absolute values (the first
/// of equal ones).
Uint8List _reference(Uint8List image, int stride, int bpp) {
  final rows = stride == 0 ? 0 : image.length ~/ stride;
  final out = Uint8List(rows * (stride + 1));
  int paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  for (var r = 0; r < rows; r++) {
    final row = r * stride;
    List<int>? best;
    var bestScore = 0;
    for (var filter = 0; filter <= 4; filter++) {
      final residuals = [
        for (var i = 0; i < stride; i++)
          (image[row + i] -
                  switch (filter) {
                    1 => i >= bpp ? image[row + i - bpp] : 0,
                    2 => r > 0 ? image[row - stride + i] : 0,
                    3 =>
                      ((i >= bpp ? image[row + i - bpp] : 0) +
                              (r > 0 ? image[row - stride + i] : 0)) >>
                          1,
                    4 => paeth(
                      i >= bpp ? image[row + i - bpp] : 0,
                      r > 0 ? image[row - stride + i] : 0,
                      r > 0 && i >= bpp ? image[row - stride + i - bpp] : 0,
                    ),
                    _ => 0,
                  }) &
              0xff,
      ];
      final score = residuals.fold(0, (s, v) => s + (v < 128 ? v : 256 - v));
      if (best == null || score < bestScore) {
        best = [filter, ...residuals];
        bestScore = score;
      }
    }
    out.setAll(r * (stride + 1), best!);
  }
  return out;
}

void main() {
  test('each row gets the filter the heuristic chooses', () {
    final random = math.Random(7);
    for (final (width, bpp) in [(1, 1), (5, 3), (17, 4), (64, 1), (9, 8)]) {
      final stride = width * bpp;
      for (final kind in ['noise', 'flat', 'gradient', 'stripes']) {
        final image = Uint8List.fromList([
          for (var y = 0; y < 12; y++)
            for (var i = 0; i < stride; i++)
              switch (kind) {
                'noise' => random.nextInt(256),
                'flat' => 200,
                'gradient' => (y * 7 + i * 3) & 0xff,
                _ => (i ~/ bpp).isEven ? 0 : 255,
              },
        ]);
        expect(
          filterImage(image, stride, bpp),
          _reference(image, stride, bpp),
          reason: '$kind, $width pixels of $bpp bytes',
        );
      }
    }
  });
}
