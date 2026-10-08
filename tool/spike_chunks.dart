/// Spike (TASK-3bbbw3, ADR-0016): how chapter-chunk workers scale on the
/// Hypermedia Systems book, as isolates of one process and as processes.
///
/// ```sh
/// dart compile exe tool/spike_chunks.dart -o build/spike_chunks
/// build/spike_chunks [--workers 1,2,4,6,8,12] [--runs 3]
/// ```
///
/// Each worker does what a chunk worker's first phase would: it loads the
/// book, walks it (the PDF converter's boxes), and lays out its share of
/// the chunks (the runs of top-level boxes between page breaks, dealt in
/// turn); it reports its times and its peak memory. The tool prints, by
/// worker count, the wall time and peak memory of N isolates in one
/// process and of N processes (the executable run as a worker).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:libpdf/libpdf.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';

import 'vendored_fonts.dart';

final String _home = Platform.environment['HOME'] ?? '';
final String _port = '$_home/Work/ports/hypermedia-systems-ptome';
final String _fonts = '$_home/.cache/asciidart-work/hs-golden/fonts';

/// The vendored fonts' folders, separated as `PATH` is.
String _fontPath = '';

/// A worker's report: milliseconds to the end of the walk and in all, the
/// pages it laid out and its peak resident memory in MB.
typedef Report = ({int walk, int total, int pages, int rss});

Future<void> main(List<String> args) async {
  // (The vendored fonts, found from the repository, before moving to the
  // book's folder.)
  _fontPath = withVendoredFonts()['PTOME_FONT_PATH']!;
  Directory.current = _port;
  if (args case ['worker', final index, final count]) {
    final report = work(int.parse(index), int.parse(count));
    stdout.writeln(
      '${report.walk} ${report.total} ${report.pages} ${report.rss}',
    );
    return;
  }
  var counts = [1, 2, 4, 6, 8, 12];
  var runs = 3;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--workers':
        counts = [for (final n in args[++i].split(',')) int.parse(n)];
      case '--runs':
        runs = int.parse(args[++i]);
    }
  }
  stdout.writeln(
    'workers  isolates: wall  peak MB  walk  |  processes: wall  peak MB '
    '(sum)  walk',
  );
  for (final count in counts) {
    final isolates = <(int, int, int)>[];
    final processes = <(int, int, int)>[];
    for (var r = 0; r < runs; r++) {
      isolates.add(await _isolates(count));
      processes.add(await _processes(count));
    }
    String cell((int, int, int) row, int width) {
      final (wall, rss, walk) = row;
      return '${'$wall'.padLeft(width)} ${'$rss'.padLeft(8)} '
          '${'$walk'.padLeft(5)}';
    }

    stdout.writeln(
      '${'$count'.padLeft(7)}  ${cell(_median(isolates), 14)}  |  '
      '${cell(_median(processes), 15)}',
    );
  }
}

/// The run with the median wall time.
(int, int, int) _median(List<(int, int, int)> rows) =>
    (rows.toList()..sort((a, b) => a.$1.compareTo(b.$1)))[rows.length ~/ 2];

/// [count] workers as isolates: the wall time, the process's peak memory
/// and the slowest walk.
Future<(int, int, int)> _isolates(int count) async {
  // (Isolates start with their own globals: the font path goes along.)
  final fontPath = _fontPath;
  final watch = Stopwatch()..start();
  final reports = await Future.wait([
    for (var i = 0; i < count; i++) Isolate.run(() => work(i, count, fontPath)),
  ]);
  return (
    watch.elapsedMilliseconds,
    ProcessInfo.maxRss ~/ 1000000,
    reports.map((r) => r.walk).reduce((a, b) => a > b ? a : b),
  );
}

/// [count] workers as processes: the wall time, the sum of their peak
/// memory and the slowest walk.
Future<(int, int, int)> _processes(int count) async {
  final watch = Stopwatch()..start();
  final results = await Future.wait([
    for (var i = 0; i < count; i++)
      Process.run(
        Platform.resolvedExecutable,
        ['worker', '$i', '$count'],
        environment: {'PTOME_FONT_PATH': _fontPath},
      ),
  ]);
  final reports = [
    for (final result in results)
      switch ('${result.stdout}'.trim().split(' ')) {
        [final walk, final total, final pages, final rss] => (
          walk: int.parse(walk),
          total: int.parse(total),
          pages: int.parse(pages),
          rss: int.parse(rss),
        ),
        _ => throw StateError('worker failed: ${result.stderr}'),
      },
  ];
  return (
    watch.elapsedMilliseconds,
    reports.map((r) => r.rss).reduce((a, b) => a + b),
    reports.map((r) => r.walk).reduce((a, b) => a > b ? a : b),
  );
}

/// Worker [index] of [count]: loads and walks the book, then lays out
/// every [count]th chunk from [index].
Report work(int index, int count, [String? fontPath]) {
  final watch = Stopwatch()..start();
  final path = fontPath ?? _fontPath;
  Fonts.extraDirectories = path.isEmpty
      ? Fonts.fontPath
      : path.split(Platform.isWindows ? ';' : ':');
  registerPdf();
  FlowLayout? flow;
  var content = const <LayoutBox>[];
  PdfConverter.onWalked = (layout, boxes) {
    flow = layout;
    content = boxes;
  };
  loadFile(
    'HypermediaSystems.adoc',
    options: AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      standalone: true,
      attributes: {
        'pdf-theme': 'hs-golden',
        'pdf-fontsdir': '$_fonts;$_port/fonts;GEM_FONTS_DIR',
      },
    ),
  ).convert();
  final walk = watch.elapsedMilliseconds;
  final starts = [
    0,
    for (final (i, box) in content.indexed)
      if (box case BreakBox(kind: BreakKind.page)) i + 1,
  ];
  var pages = 0;
  for (var c = index; c < starts.length; c += count) {
    final end = c + 1 < starts.length ? starts[c + 1] : content.length;
    if (end > starts[c]) {
      pages += flow!.layout(content.sublist(starts[c], end)).pageCount;
    }
  }
  return (
    walk: walk,
    total: watch.elapsedMilliseconds,
    pages: pages,
    rss: ProcessInfo.maxRss ~/ 1000000,
  );
}
