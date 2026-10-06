/// Compares PDF files the asciidart CLI writes with those of the
/// asciidoctor-pdf gem: their text and its geometry, their structure, and
/// their rendered pixels.
///
/// Usage:
///
/// ```sh
/// dart run tool/pdf_parity.dart --exe-a GEM --exe-b ASCIIDART \
///   [--out DIR] [--strict] [--tolerance POINTS] DOC.adoc...
/// dart run tool/pdf_parity.dart A.pdf B.pdf
/// ```
///
/// Each document is converted by both executables (`-b pdf` for
/// asciidart; `SOURCE_DATE_EPOCH=0`, `TZ=UTC`). Then, through poppler and
/// qpdf:
///
/// - pages: the page count;
/// - text: every word of both files (`pdftotext -bbox`), aligned with a
///   diff; the share of words in common;
/// - geometry: of the words in common, the share on the same page within
///   the tolerance (1 point by default) of the same position, and the
///   largest distance;
/// - structure: the outline (titles, levels and pages), the links
///   (annotations: target and rectangle to the point, in any order: the
///   order they're written in isn't seen) and the page labels;
/// - pixels: each page rendered in gray at 36 dpi; the mean difference;
///   colors: rendered in color, the share of pixels that differ clearly.
///
/// One line per document, and with `--out`, a `results.tsv` and, for each
/// document that differs, the word differences. With `--strict`, exits 1
/// unless every document is the same on every count.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A word on a page: its text and box (points, y down from the top).
typedef Word = ({
  int page,
  String text,
  double xMin,
  double yMin,
  double xMax,
  double yMax,
});

/// What is compared of a PDF file.
final class PdfFacts {
  const new({
    required this.pages,
    required this.words,
    required this.outline,
    required this.links,
    required this.labels,
    required this.rasters,
    required this.colors,
  });

  final int pages;
  final List<Word> words;

  /// `level page title` per outline item.
  final List<String> outline;

  /// The link targets, in order.
  final List<String> links;

  /// The page labels, in order.
  final List<String> labels;

  /// Each page in gray at 36 dpi (PGM).
  final List<Uint8List> rasters;

  /// Each page in color at 36 dpi (PPM).
  final List<Uint8List> colors;
}

String _run(String executable, List<String> args, {Encoding? encoding}) {
  final result = Process.runSync(
    executable,
    args,
    stdoutEncoding: encoding ?? utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('$executable ${args.join(' ')}: ${result.stderr}');
  }
  return result.stdout as String;
}

/// The facts of [pdf], rasters written under [scratch].
PdfFacts facts(String pdf, Directory scratch) {
  final info = _run('pdfinfo', [pdf]);
  final pages = int.parse(
    RegExp(r'Pages:\s+(\d+)').firstMatch(info)?.group(1) ?? '0',
  );
  final words = <Word>[];
  var page = 0;
  final word = RegExp(
    r'<word xMin="(-?[\d.]+)" yMin="(-?[\d.]+)" xMax="(-?[\d.]+)" '
    r'yMax="(-?[\d.]+)">([^<]*)</word>',
  );
  for (final line in _run('pdftotext', ['-bbox', pdf, '-']).split('\n')) {
    if (line.contains('<page ')) page++;
    final m = word.firstMatch(line);
    if (m == null) continue;
    words.add((
      page: page,
      text: _unescape(m[5]!),
      xMin: double.parse(m[1]!),
      yMin: double.parse(m[2]!),
      xMax: double.parse(m[3]!),
      yMax: double.parse(m[4]!),
    ));
  }
  final xml = _run('pdftohtml', ['-xml', '-i', '-stdout', '-q', pdf]);
  final outline = <String>[];
  var level = 0;
  for (final m in RegExp(
    r'<outline>|</outline>|<item page="(\d+)">([^<]*)</item>',
  ).allMatches(xml)) {
    switch (m[0]) {
      case '<outline>':
        level++;
      case '</outline>':
        level--;
      default:
        outline.add('$level ${m[1]} ${_unescape(m[2]!)}');
    }
  }
  // The link annotations: each one's page, target and rectangle (to the
  // point), from the file's objects (pdftohtml repeats a link for each
  // run of text it covers).
  final qdf = _run('qpdf', [
    '--qdf',
    '--object-streams=disable',
    pdf,
    '-',
  ], encoding: latin1);
  final links = <String>[];
  for (final m in RegExp(
    r'\d+ 0 obj\n(.*?)\nendobj',
    dotAll: true,
  ).allMatches(qdf)) {
    final body = m[1]!;
    if (!body.contains('/Subtype /Link')) continue;
    final target =
        RegExp(r'/URI \((.*?)\)').firstMatch(body)?[1] ??
        RegExp(r'/Dest \((.*?)\)').firstMatch(body)?[1] ??
        RegExp(r'/D \((.*?)\)').firstMatch(body)?[1] ??
        '?';
    final rect = RegExp(r'/Rect \[([^\]]*)\]').firstMatch(body)?[1] ?? '';
    final corners = [
      for (final n in rect.trim().split(RegExp(r'\s+')))
        if (double.tryParse(n) case final v?) v.toStringAsFixed(2),
    ];
    links.add('$target ${corners.join(' ')}');
  }
  final json = _run('qpdf', ['--json', '--json-key=pages', pdf]);
  final labels = [
    for (final m in RegExp(r'"label": (\{[^}]*\}|null)').allMatches(json))
      m[1]!.replaceAll(RegExp(r'\s+'), ' '),
  ];
  final rasters = <Uint8List>[];
  final colors = <Uint8List>[];
  for (var p = 1; p <= pages; p++) {
    final out = '${scratch.path}/${pdf.hashCode}-$p';
    _run('pdftoppm', [
      '-gray',
      '-r',
      '36',
      '-f',
      '$p',
      '-l',
      '$p',
      '-singlefile',
      pdf,
      out,
    ]);
    rasters.add(File('$out.pgm').readAsBytesSync());
    _run('pdftoppm', [
      '-r',
      '36',
      '-f',
      '$p',
      '-l',
      '$p',
      '-singlefile',
      pdf,
      out,
    ]);
    colors.add(File('$out.ppm').readAsBytesSync());
  }
  return PdfFacts(
    pages: pages,
    words: words,
    outline: outline,
    links: links,
    labels: labels,
    rasters: rasters,
    colors: colors,
  );
}

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// The pairs of indices of equal elements of [a] and [b] along a
/// shortest edit script (Myers' algorithm).
List<(int, int)> commonPairs(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final max = n + m;
  final offset = max + 1;
  var v = List<int>.filled(2 * max + 3, 0);
  final trace = <List<int>>[];
  outer:
  for (var d = 0; d <= max; d++) {
    trace.add(List.of(v));
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
          ? v[offset + k + 1]
          : v[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        trace.add(List.of(v));
        break outer;
      }
    }
  }
  // Walk the trace back to collect the diagonal moves.
  final pairs = <(int, int)>[];
  var x = n;
  var y = m;
  for (var d = trace.length - 2; d >= 0 && (x > 0 || y > 0); d--) {
    v = trace[d];
    final k = x - y;
    final previousK =
        k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
        ? k + 1
        : k - 1;
    final previousX = d == 0 ? 0 : v[offset + previousK];
    final previousY = previousX - previousK;
    while (x > previousX && y > previousY) {
      x--;
      y--;
      pairs.add((x, y));
    }
    if (d > 0) {
      x = previousX;
      y = previousY;
    }
  }
  return pairs.reversed.toList();
}

/// How two PDF files compare.
final class Comparison {
  new(this.a, this.b, {this.tolerance = 1});

  final PdfFacts a;
  final PdfFacts b;
  final double tolerance;

  late final List<(int, int)> _pairs = commonPairs(
    [for (final w in a.words) w.text],
    [for (final w in b.words) w.text],
  );

  /// The share of words both files have, in order.
  double get text {
    final total = a.words.length + b.words.length;
    return total == 0 ? 1 : 2 * _pairs.length / total;
  }

  /// The share of common words at the same place, and the largest
  /// distance of any common word on the same page.
  (double, double) get geometry {
    if (_pairs.isEmpty) return (a.words.isEmpty && b.words.isEmpty ? 1 : 0, 0);
    var close = 0;
    var worst = 0.0;
    for (final (i, j) in _pairs) {
      final wa = a.words[i];
      final wb = b.words[j];
      if (wa.page != wb.page) continue;
      final distance = math.max(
        (wa.xMin - wb.xMin).abs(),
        (wa.yMax - wb.yMax).abs(),
      );
      worst = math.max(worst, distance);
      if (distance <= tolerance) close++;
    }
    return (close / _pairs.length, worst);
  }

  /// The mean gray difference over the pages both files have (and 255 for
  /// each page one lacks).
  double get pixels {
    var sum = 0.0;
    var count = 0;
    for (var p = 0; p < math.max(a.rasters.length, b.rasters.length); p++) {
      if (p >= a.rasters.length || p >= b.rasters.length) {
        sum += 255;
        count++;
        continue;
      }
      final (wa, ha, sa) = _samples(a.rasters[p]);
      final (wb, hb, sb) = _samples(b.rasters[p]);
      if (wa != wb || ha != hb) {
        sum += 255;
        count++;
        continue;
      }
      var total = 0;
      for (var i = 0; i < sa.length; i++) {
        total += (sa[i] - sb[i]).abs();
      }
      sum += total / sa.length;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  /// The share of pixels whose color differs clearly (by more than 64 in
  /// a channel from each pixel around it) on the page where it's largest
  /// (all of a page one file lacks): what the mean gray difference
  /// misses, like text in another color.
  double get colors {
    var worst = 0.0;
    for (var p = 0; p < math.max(a.colors.length, b.colors.length); p++) {
      if (p >= a.colors.length || p >= b.colors.length) return 1;
      final (wa, ha, sa) = _samples(a.colors[p], channels: 3);
      final (wb, hb, sb) = _samples(b.colors[p], channels: 3);
      if (wa != wb || ha != hb) return 1;
      // A pixel changed when no pixel next to it (or itself) in the other
      // rendering has its color: edges a fraction of a point apart don't
      // count.
      bool near(Uint8List x, Uint8List y, int px, int py) {
        final i = (py * wa + px) * 3;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final qx = px + dx;
            final qy = py + dy;
            if (qx < 0 || qy < 0 || qx >= wa || qy >= ha) continue;
            final j = (qy * wa + qx) * 3;
            if ((x[i] - y[j]).abs() <= 64 &&
                (x[i + 1] - y[j + 1]).abs() <= 64 &&
                (x[i + 2] - y[j + 2]).abs() <= 64) {
              return true;
            }
          }
        }
        return false;
      }

      // The last row and column are partly off the page, where clipping
      // blends them differently: left out.
      var changed = 0;
      for (var py = 0; py < ha - 1; py++) {
        for (var px = 0; px < wa - 1; px++) {
          if (!near(sa, sb, px, py) || !near(sb, sa, px, py)) changed++;
        }
      }
      worst = math.max(worst, changed / (wa * ha));
    }
    return worst;
  }

  bool get sameOutline => _same(a.outline, b.outline);

  /// Whether the links are the same, in any order, their rectangles
  /// within a point.
  bool get sameLinks {
    if (a.links.length != b.links.length) return false;
    (String, List<double>) split(String link) {
      final parts = link.split(' ');
      final count = parts.length >= 5 ? 4 : 0;
      return (
        parts.sublist(0, parts.length - count).join(' '),
        [for (final n in parts.sublist(parts.length - count)) double.parse(n)],
      );
    }

    int order((String, List<double>) x, (String, List<double>) y) {
      final byTarget = x.$1.compareTo(y.$1);
      if (byTarget != 0) return byTarget;
      for (var i = 0; i < x.$2.length && i < y.$2.length; i++) {
        final c = x.$2[i].compareTo(y.$2[i]);
        if (c != 0) return c;
      }
      return 0;
    }

    final xs = a.links.map(split).toList()..sort(order);
    final ys = b.links.map(split).toList()..sort(order);
    for (var i = 0; i < xs.length; i++) {
      if (xs[i].$1 != ys[i].$1 || xs[i].$2.length != ys[i].$2.length) {
        return false;
      }
      for (var k = 0; k < xs[i].$2.length; k++) {
        if ((xs[i].$2[k] - ys[i].$2[k]).abs() > 1) return false;
      }
    }
    return true;
  }

  bool get sameLabels => _same(a.labels, b.labels);

  static bool _same(List<String> x, List<String> y) =>
      x.length == y.length &&
      [for (var i = 0; i < x.length; i++) i].every((i) => x[i] == y[i]);

  /// Whether the files are the same on every count.
  bool get same =>
      a.pages == b.pages &&
      text == 1 &&
      geometry.$1 == 1 &&
      sameOutline &&
      sameLinks &&
      sameLabels &&
      pixels < 1 &&
      colors < 0.001;

  /// The word differences, as a unified-style listing.
  String wordDiff() {
    final out = StringBuffer();
    var i = 0;
    var j = 0;
    void line(String mark, Word w) => out.writeln(
      '$mark p${w.page} ${w.xMin.toStringAsFixed(1)},'
      '${w.yMax.toStringAsFixed(1)} ${w.text}',
    );
    for (final (pi, pj) in [..._pairs, (a.words.length, b.words.length)]) {
      while (i < pi) {
        line('-', a.words[i++]);
      }
      while (j < pj) {
        line('+', b.words[j++]);
      }
      if (pi < a.words.length) {
        final wa = a.words[i];
        final wb = b.words[j];
        final moved =
            wa.page != wb.page ||
            (wa.xMin - wb.xMin).abs() > tolerance ||
            (wa.yMax - wb.yMax).abs() > tolerance;
        if (moved) {
          out.writeln(
            '~ p${wa.page}→p${wb.page} '
            '${wa.xMin.toStringAsFixed(1)},${wa.yMax.toStringAsFixed(1)}→'
            '${wb.xMin.toStringAsFixed(1)},${wb.yMax.toStringAsFixed(1)} '
            '${wa.text}',
          );
        }
        i++;
        j++;
      }
    }
    return out.toString();
  }

  String summary() {
    final (close, worst) = geometry;
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    return 'pages ${a.pages}/${b.pages}, text ${pct(text)}, '
        'geometry ${pct(close)} (max ${worst.toStringAsFixed(1)}pt), '
        'outline ${sameOutline ? 'same' : 'differs'}, '
        'links ${sameLinks ? 'same' : 'differs'}, '
        'labels ${sameLabels ? 'same' : 'differs'}, '
        'pixels ${pixels.toStringAsFixed(2)}, '
        'colors ${pct(colors)}';
  }
}

(int, int, Uint8List) _samples(Uint8List image, {int channels = 1}) {
  final header = latin1.decode(image.sublist(0, 20)).split(RegExp(r'\s+'));
  final width = int.parse(header[1]);
  final height = int.parse(header[2]);
  return (
    width,
    height,
    Uint8List.sublistView(image, image.length - width * height * channels),
  );
}

void main(List<String> args) {
  String? exeA;
  String? exeB;
  String? outDir;
  var strict = false;
  var tolerance = 1.0;
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--exe-a':
        exeA = args[++i];
      case '--exe-b':
        exeB = args[++i];
      case '--out':
        outDir = args[++i];
      case '--strict':
        strict = true;
      case '--tolerance':
        tolerance = double.parse(args[++i]);
      default:
        inputs.add(args[i]);
    }
  }
  final scratch = Directory.systemTemp.createTempSync('pdf_parity.');
  final out = outDir == null
      ? null
      : (Directory(outDir)..createSync(recursive: true));
  final results = StringBuffer(
    'document\tpages_a\tpages_b\ttext\tgeometry\tmax_pt\toutline\tlinks\t'
    'labels\tpixels\tcolors\n',
  );
  var allSame = true;
  try {
    final pairs = <(String, String, String)>[];
    if (exeA == null || exeB == null) {
      if (inputs.length != 2) {
        stderr.writeln(
          'usage: pdf_parity.dart --exe-a GEM --exe-b ASCIIDART DOC.adoc... '
          '| A.pdf B.pdf',
        );
        exit(2);
      }
      pairs.add((inputs[1], inputs[0], inputs[1]));
    } else {
      for (final (n, input) in inputs.indexed) {
        final a = '${scratch.path}/$n-a.pdf';
        final b = '${scratch.path}/$n-b.pdf';
        final env = {'SOURCE_DATE_EPOCH': '0', 'TZ': 'UTC'};
        for (final (exe, target, backend) in [
          (exeA, a, <String>[]),
          (exeB, b, ['-b', 'pdf']),
        ]) {
          final result = Process.runSync(exe, [
            ...backend,
            '-o',
            target,
            input,
          ], environment: env);
          if (result.exitCode != 0 || !File(target).existsSync()) {
            stderr.writeln('$exe failed on $input: ${result.stderr}');
          }
        }
        pairs.add((input, a, b));
      }
    }
    for (final (name, a, b) in pairs) {
      if (!File(a).existsSync() || !File(b).existsSync()) {
        stdout.writeln('$name: not converted by both');
        allSame = false;
        continue;
      }
      final comparison = Comparison(
        facts(a, scratch),
        facts(b, scratch),
        tolerance: tolerance,
      );
      stdout.writeln('$name: ${comparison.summary()}');
      final (close, worst) = comparison.geometry;
      results.writeln(
        [
          name,
          comparison.a.pages,
          comparison.b.pages,
          comparison.text.toStringAsFixed(4),
          close.toStringAsFixed(4),
          worst.toStringAsFixed(1),
          comparison.sameOutline,
          comparison.sameLinks,
          comparison.sameLabels,
          comparison.pixels.toStringAsFixed(2),
          comparison.colors.toStringAsFixed(4),
        ].join('\t'),
      );
      if (!comparison.same) {
        allSame = false;
        if (out != null) {
          final safe = name.replaceAll(RegExp(r'[^\w.-]+'), '_');
          File('${out.path}/$safe.diff')
              .writeAsStringSync(comparison.wordDiff());
        }
      }
    }
    if (out != null) {
      File('${out.path}/results.tsv').writeAsStringSync(results.toString());
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }
  stdout.writeln('pdf_parity: ${allSame ? 'all the same' : 'differences'}');
  if (strict && !allSame) exit(1);
}
