// PNG unfiltering: the per-filter loops give what the specification's
// reconstruction, written plainly, gives; and every PngSuite image decodes
// to the samples (color and alpha) it decoded to at commit 17001e86.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_pdf/src/images/png_decode.dart';
import 'package:test/test.dart';

/// Reconstruction as the specification puts it (9.2), one byte at a time.
Uint8List _reference(Uint8List data, int stride, int rows, int bpp) {
  int paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  final out = Uint8List(stride * rows);
  for (var r = 0; r < rows; r++) {
    final at = r * (stride + 1);
    final row = r * stride;
    for (var i = 0; i < stride; i++) {
      final left = i >= bpp ? out[row + i - bpp] : 0;
      final up = r > 0 ? out[row - stride + i] : 0;
      final upLeft = r > 0 && i >= bpp ? out[row - stride + i - bpp] : 0;
      out[row + i] =
          data[at + 1 + i] +
          switch (data[at]) {
            1 => left,
            2 => up,
            3 => (left + up) >> 1,
            4 => paeth(left, up, upLeft),
            _ => 0,
          };
    }
  }
  return out;
}

void main() {
  test('each filter reconstructs as the specification does', () {
    final random = math.Random(11);
    for (final (width, channels, depth) in [
      (1, 1, 8), (7, 3, 8), (33, 4, 8), (5, 2, 16), (9, 4, 16), //
      (13, 1, 1), (11, 1, 2), (6, 1, 4), (2, 3, 16), (64, 1, 8),
    ]) {
      final layout = PngLayout(width, 9, channels, depth);
      final stride = layout.rowBytes(width);
      for (var trial = 0; trial < 20; trial++) {
        final data = Uint8List.fromList([
          for (var r = 0; r < 9; r++) ...[
            // The first rows try each filter in turn.
            if (r < 5) (r + trial) % 5 else random.nextInt(5),
            for (var i = 0; i < stride; i++)
              if (trial.isEven) random.nextInt(256) else (i * r * 37) & 0xff,
          ],
        ]);
        expect(
          unfilterImage(data, layout, interlaced: false),
          _reference(data, stride, 9, layout.pixelBytes),
          reason: '$width x $channels x $depth bits, trial $trial',
        );
      }
    }
  });

  test('undefined filters and truncated data are rejected', () {
    const layout = PngLayout(2, 2, 1, 8);
    expect(
      () => unfilterImage(
        Uint8List.fromList([0, 1, 2, 5, 3, 4]),
        layout,
        interlaced: false,
      ),
      throwsFormatException,
    );
    expect(
      () => unfilterImage(
        Uint8List.fromList([0, 1, 2, 0, 3]),
        layout,
        interlaced: false,
      ),
      throwsFormatException,
    );
  });

  test('PngSuite decodes to the same samples as before', () {
    final out = BytesBuilder();
    final files =
        Directory('test/images/pngsuite')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png') && !f.path.contains('/x'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final image = PdfImage.parse(file.readAsBytesSync());
      if (image is! PngImage || !image.reencodes) continue;
      final payload = image.encode(const PdfWriterOptions(compress: false));
      out
        ..add(file.uri.pathSegments.last.codeUnits)
        ..add(payload.color)
        ..add(payload.alpha ?? const [0])
        ..addByte(payload.alphaDepth);
    }
    expect(
      md5.convert(out.takeBytes()).toString(),
      '8bb4a8435b75f259474cbc2b97923e1b',
    );
  });
}
