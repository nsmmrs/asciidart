/// Page images of PDFs, compared pixel for pixel: how ptome's PDF is
/// checked against a golden one (another profile's), since the bytes of
/// two PDF writers never agree but their pages can.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// The resolution pages are compared at, in dots per inch.
const pixelsDpi = 50;

/// The gray page images of the PDF in [pdf] (`pdftoppm -gray`), rendered
/// once into [dir].
List<Uint8List> pageImages(String pdf, String dir) {
  final done = File(p.join(dir, 'done'));
  if (!done.existsSync()) {
    Directory(dir).createSync(recursive: true);
    final result = Process.runSync('pdftoppm', [
      '-r',
      '$pixelsDpi',
      '-gray',
      pdf,
      p.join(dir, 'p'),
    ]);
    if (result.exitCode != 0) {
      throw StateError('pdftoppm $pdf: ${result.stderr}');
    }
    done.writeAsStringSync('');
  }
  final pages =
      Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pgm'))
          .toList()
        ..sort((a, b) => _number(a.path).compareTo(_number(b.path)));
  return [for (final page in pages) page.readAsBytesSync()];
}

int _number(String path) =>
    int.parse(RegExp(r'(\d+)\.pgm$').firstMatch(path)![1]!);

/// How the pages of [a] and [b] differ: `identical`, or the first page
/// that differs and the share of its pixels that do (`page 2: 0.031%`),
/// or the page counts when they differ.
String comparePages(List<Uint8List> a, List<Uint8List> b) {
  if (a.length != b.length) return 'pages: ${b.length}, not ${a.length}';
  for (var i = 0; i < a.length; i++) {
    final share = _differing(a[i], b[i]);
    if (share > 0) {
      return 'page ${i + 1}: ${(share * 100).toStringAsFixed(3)}%';
    }
  }
  return 'identical';
}

/// The share of pixels that differ between two PGM images (1 when their
/// sizes do).
double _differing(Uint8List a, Uint8List b) {
  if (a.length != b.length) return 1;
  var differ = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) differ++;
  }
  return differ / a.length;
}
