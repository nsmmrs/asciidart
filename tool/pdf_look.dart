/// Compares how the PDF files of asciidart look with those of the
/// asciidoctor-pdf gem, page image against page image (ADR-0015).
///
/// Usage:
///
/// ```sh
/// dart run tool/pdf_look.dart --gem GEM --exe ASCIIDART --cache DIR \
///   --out DIR [-j N] [--dpi N] [--pairs] DOC.adoc...
/// ```
///
/// The gem's PDF of each document and its pages (gray PGM images at
/// `--dpi`, 50 by default) are made once and kept in `--cache`; a later
/// run converts only with asciidart (`-o FILE DOC`, `SOURCE_DATE_EPOCH=0`,
/// `TZ=UTC`; the wrapper passes `-b pdf`), renders its pages and compares. Both page images are
/// blurred (a 5-pixel box, so a line set a point to the side isn't a
/// difference) and a pixel differs when the blurred grays differ by more
/// than 10%. A page's difference is the share of its pixels that differ;
/// a page one file has and the other hasn't differs completely.
///
/// One line per document: its largest page difference, its mean, and the
/// page counts. In `--out`: `look.tsv` (sorted, largest first), and with
/// `--pairs`, for each document that differs, `NAME-pN.png` for its most
/// different page (the gem's, asciidart's, and the difference in red).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A gray page image.
final class Gray {
  const new(this.width, this.height, this.pixels);

  /// The PGM (binary, 8-bit) image in [bytes].
  factory parse(Uint8List bytes) {
    var at = 0;
    String token() {
      while (true) {
        while (bytes[at] == 0x20 ||
            bytes[at] == 0x0a ||
            bytes[at] == 0x0d ||
            bytes[at] == 0x09) {
          at++;
        }
        if (bytes[at] != 0x23) break;
        while (bytes[at] != 0x0a) {
          at++;
        }
      }
      final start = at;
      while (bytes[at] > 0x20) {
        at++;
      }
      return String.fromCharCodes(bytes, start, at);
    }

    if (token() != 'P5') throw const FormatException('not a binary PGM');
    final width = int.parse(token());
    final height = int.parse(token());
    token(); // maxval
    at++;
    return Gray(width, height, Uint8List.sublistView(bytes, at));
  }

  final int width;
  final int height;
  final Uint8List pixels;

  /// The image blurred by a box of 2 * [radius] + 1 pixels.
  Gray blurred(int radius) {
    final rows = Uint8List(width * height);
    final size = 2 * radius + 1;
    for (var y = 0; y < height; y++) {
      var sum = 0;
      for (var x = -radius; x <= radius; x++) {
        sum += _at(x, y);
      }
      for (var x = 0; x < width; x++) {
        rows[y * width + x] = sum ~/ size;
        sum += _at(x + radius + 1, y) - _at(x - radius, y);
      }
    }
    final out = Uint8List(width * height);
    int rowAt(int x, int y) => rows[y.clamp(0, height - 1) * width + x];
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var y = -radius; y <= radius; y++) {
        sum += rowAt(x, y);
      }
      for (var y = 0; y < height; y++) {
        out[y * width + x] = sum ~/ size;
        sum += rowAt(x, y + radius + 1) - rowAt(x, y - radius);
      }
    }
    return Gray(width, height, out);
  }

  int _at(int x, int y) => pixels[y * width + x.clamp(0, width - 1)];
}

/// The share (0 to 1) of pixels of [a] and [b] (blurred) that differ by
/// more than [threshold]; pages of different sizes are compared over the
/// larger, the missing part white.
double difference(Gray a, Gray b, {int threshold = 26}) {
  final width = math.max(a.width, b.width);
  final height = math.max(a.height, b.height);
  var differ = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pa = x < a.width && y < a.height ? a.pixels[y * a.width + x] : 255;
      final pb = x < b.width && y < b.height ? b.pixels[y * b.width + x] : 255;
      if ((pa - pb).abs() > threshold) differ++;
    }
  }
  return differ / (width * height);
}

/// The result for one document.
typedef Look = ({
  String name,
  int gemPages,
  int pages,
  List<double> differences,
  String? error,
});

extension on Look {
  double get largest => error != null
      ? 1
      : differences.isEmpty
      ? 0
      : differences.reduce(math.max);

  double get mean => error != null
      ? 1
      : differences.isEmpty
      ? 0
      : differences.reduce((a, b) => a + b) / differences.length;

  int get worstPage => differences.indexOf(largest) + 1;
}

Future<String?> _run(
  String executable,
  List<String> args, {
  Map<String, String> env = const {},
}) async {
  final result = await Process.run(
    executable,
    args,
    environment: {'SOURCE_DATE_EPOCH': '0', 'TZ': 'UTC', ...env},
  );
  if (result.exitCode != 0) {
    return '$executable failed (${result.exitCode}): '
        '${'${result.stderr}'.trim().split('\n').take(3).join(' / ')}';
  }
  return null;
}

/// Renders [pdf]'s pages as `DIR/p-N.pgm`, returning them in order.
Future<List<File>> _render(String pdf, String dir, int dpi) async {
  final directory = Directory(dir);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  directory.createSync(recursive: true);
  final error = await _run('pdftoppm', ['-gray', '-r', '$dpi', pdf, '$dir/p']);
  if (error != null) throw ProcessException('pdftoppm', [pdf], error);
  return _pages(dir);
}

/// The page images in [dir], in page order.
List<File> _pages(String dir) {
  if (!Directory(dir).existsSync()) return const [];
  final rx = RegExp(r'^p-(\d+)\.pgm$');
  final pages = [
    for (final file in Directory(dir).listSync().whereType<File>())
      if (rx.firstMatch(file.path.split('/').last) case final m?)
        (int.parse(m[1]!), file),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, file) in pages) file];
}

Future<Look> _look(
  String doc, {
  required String gem,
  required String exe,
  required String cache,
  required String out,
  required int dpi,
}) async {
  final name = doc.split('/').last.replaceAll(RegExp(r'\.adoc$'), '');
  Look failed(String error) =>
      (name: name, gemPages: 0, pages: 0, differences: [], error: error);
  final gemPdf = '$cache/$name.pdf';
  final gemDir = '$cache/$name';
  var gemPages = _pages(gemDir);
  if (!File(gemPdf).existsSync() || gemPages.isEmpty) {
    final error = await _run(gem, ['-o', gemPdf, doc]);
    if (error != null || !File(gemPdf).existsSync()) {
      return failed('the gem: ${error ?? 'no PDF'}');
    }
    try {
      gemPages = await _render(gemPdf, gemDir, dpi);
    } on ProcessException catch (error) {
      return failed('the gem: ${error.message}');
    }
  }
  final pdf = '$out/pdf/$name.pdf';
  final error = await _run(exe, ['-o', pdf, doc]);
  if (error != null || !File(pdf).existsSync()) {
    return failed('asciidart: ${error ?? 'no PDF'}');
  }
  final List<File> pages;
  try {
    pages = await _render(pdf, '$out/png/$name', dpi);
  } on ProcessException catch (error) {
    return failed('asciidart: ${error.message}');
  }
  final count = math.max(gemPages.length, pages.length);
  final differences = <double>[
    for (var i = 0; i < count; i++)
      if (i < gemPages.length && i < pages.length)
        difference(
          Gray.parse(gemPages[i].readAsBytesSync()).blurred(2),
          Gray.parse(pages[i].readAsBytesSync()).blurred(2),
        )
      else
        1,
  ];
  return (
    name: name,
    gemPages: gemPages.length,
    pages: pages.length,
    differences: differences,
    error: null,
  );
}

/// Writes `NAME-pN.png` in [out]: the gem's page, asciidart's, and the
/// difference.
Future<void> _pair(Look look, String cache, String out) async {
  final page = look.worstPage;
  final gem = _pages('$cache/${look.name}');
  final ours = _pages('$out/png/${look.name}');
  final a = page <= gem.length ? gem[page - 1].path : 'xc:white';
  final b = page <= ours.length ? ours[page - 1].path : 'xc:white';
  await Process.run('magick', [
    a,
    b,
    '(',
    a,
    b,
    '-compose',
    'difference',
    '-composite',
    '-negate',
    '-threshold',
    '90%',
    '+level-colors',
    'red,white',
    ')',
    '+append',
    '$out/${look.name}-p$page.png',
  ]);
}

Future<void> main(List<String> args) async {
  String? gem;
  String? exe;
  String? cache;
  String? out;
  var jobs = Platform.numberOfProcessors;
  var dpi = 50;
  var pairs = false;
  final docs = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--gem':
        gem = args[++i];
      case '--exe':
        exe = args[++i];
      case '--cache':
        cache = args[++i];
      case '--out':
        out = args[++i];
      case '-j':
        jobs = int.parse(args[++i]);
      case '--dpi':
        dpi = int.parse(args[++i]);
      case '--pairs':
        pairs = true;
      default:
        docs.add(args[i]);
    }
  }
  if (gem == null || exe == null || cache == null || out == null) {
    stderr.writeln(
      'usage: pdf_look.dart --gem GEM --exe ASCIIDART --cache DIR --out DIR '
      '[-j N] [--dpi N] [--pairs] DOC.adoc...',
    );
    exitCode = 64;
    return;
  }
  final (gemExe, ourExe, cacheDir, outDir) = (gem, exe, cache, out);
  for (final dir in [cache, '$out/pdf', '$out/png']) {
    Directory(dir).createSync(recursive: true);
  }
  final results = <Look>[];
  var next = 0;
  Future<void> worker() async {
    while (next < docs.length) {
      final doc = docs[next++];
      final look = await _look(
        doc,
        gem: gemExe,
        exe: ourExe,
        cache: cacheDir,
        out: outDir,
        dpi: dpi,
      );
      results.add(look);
      final pct = (look.largest * 100).toStringAsFixed(2);
      stdout.writeln(
        '${look.name}\t$pct%\t${look.gemPages}/${look.pages}'
        '${look.error == null ? '' : '\t${look.error}'}',
      );
      if (pairs && look.error == null && look.largest > 0.005) {
        await _pair(look, cacheDir, outDir);
      }
    }
  }

  await Future.wait([for (var i = 0; i < jobs; i++) worker()]);
  results.sort((a, b) => b.largest.compareTo(a.largest));
  final tsv = StringBuffer(
    'name\tlargest\tmean\tpage\tgem_pages\tpages\terror\n',
  );
  for (final look in results) {
    tsv.writeln(
      [
        look.name,
        (look.largest * 100).toStringAsFixed(3),
        (look.mean * 100).toStringAsFixed(3),
        look.worstPage,
        look.gemPages,
        look.pages,
        look.error ?? '',
      ].join('\t'),
    );
  }
  File('$out/look.tsv').writeAsStringSync('$tsv');
  int under(double share) =>
      results.where((look) => look.largest <= share).length;
  final samePages = results
      .where((look) => look.error == null && look.gemPages == look.pages)
      .length;
  stdout.writeln(
    'pdf_look: ${results.length} documents; largest page difference '
    '<= 0.5%: ${under(0.005)}, <= 1%: ${under(0.01)}, <= 2%: '
    '${under(0.02)}, <= 5%: ${under(0.05)}; same page count: $samePages; '
    'failed: ${results.where((look) => look.error != null).length}',
  );
}
