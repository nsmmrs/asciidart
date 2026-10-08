// Typst parity (lane EPIC-n7s6v0): the modern PDF engine against Typst's
// own test suite. Each case in test/typst/<name>/ is a test of the suite
// (typst.typ, the test's code), its AsciiDoc twin (doc.adoc) and the theme
// that says what the test's #set rules say (theme.yml, which extends
// test/typst/base-theme.yml). The tool compiles the Typst with the Typst
// CLI under the test runner's defaults (a page 120pt wide, 10pt margins,
// unbounded height, 10pt text; the bundled fonts and the dev assets' only),
// converts the AsciiDoc with Ptome (the same font files), and compares
// the two PDFs line by line: each line's words, its left and right edges,
// the distance from the first line's top to each line's, and the first
// line's top.
//
// Usage: dart run tool/typst_parity.dart [--exe PATH] [--out DIR]
//            [--report FILE] [-v] [CASE...]
//
// -v prints each case's lines, Typst's (T) above Ptome's (A): top,
// left-right, words.
//
// With --report, the results table replaces the one in FILE (such as
// benchmark/TYPST.md) under "## Latest run (date)".
//
// Typst 0.14.2 and its font assets (typst/typst-assets and
// typst/typst-dev-assets at v0.14.2) are fetched into
// ~/.cache/asciidart-work. Needs curl, git, tar and pdftotext.
import 'dart:io';

const _version = '0.14.2';
const _typstRelease =
    'https://github.com/typst/typst/releases/download/v$_version/'
    'typst-x86_64-unknown-linux-musl.tar.xz';

final String _cache = '${Platform.environment['HOME']}/.cache/asciidart-work';

/// The test runner's defaults (tests/src/world.rs), and its `lines`
/// helper: a count of lines numbered in a pattern (`A` by default).
const _preamble =
    '#set page(width: 120pt, height: auto, margin: 10pt)\n'
    '#set text(size: 10pt)\n'
    '#let lines(count, ..pattern) = range(1, count + 1)'
    '.map(n => numbering(pattern.pos().at(0, default: "A"), n))'
    '.join("\\n")\n';

/// A line of text in a PDF: its page, words and box.
typedef _Line = ({
  int page,
  String text,
  double left,
  double right,
  double top,
});

/// What a case's two PDFs have in common.
typedef _Result = ({
  String name,
  int typstLines,
  int ptomeLines,
  int sameLines,
  double edges,
  double pitch,
  double top,
  int typstPages,
  int ptomePages,
  String? error,
});

void main(List<String> args) {
  var exe = 'build/ptome';
  var out = '$_cache/typst-parity';
  String? report;
  var verbose = false;
  final names = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--exe':
        exe = args[++i];
      case '--out':
        out = args[++i];
      case '--report':
        report = args[++i];
      case '-v' || '--verbose':
        verbose = true;
      default:
        names.add(args[i]);
    }
  }
  exe = File(exe).absolute.path;
  final typst = _typst();
  final fonts = _assets('typst-assets');
  final devFonts = _assets('typst-dev-assets');
  final cases =
      Directory('test/typst')
          .listSync()
          .whereType<Directory>()
          .where((d) => File('${d.path}/typst.typ').existsSync())
          .where((d) => names.isEmpty || names.contains(_base(d.path)))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final outDir = Directory(out)..createSync(recursive: true);
  final results = [
    for (final dir in cases)
      _run(dir, exe, typst, fonts, devFonts, outDir.path, verbose: verbose),
  ];
  final table = _table(results);
  stdout.writeln(table);
  if (report != null) _report(File(report), table);
}

String _base(String path) => path.substring(path.lastIndexOf('/') + 1);

_Result _run(
  Directory dir,
  String exe,
  String typst,
  String fonts,
  String devFonts,
  String out, {
  bool verbose = false,
}) {
  final name = _base(dir.path);
  _Result failed(String error) => (
    name: name,
    typstLines: 0,
    ptomeLines: 0,
    sameLines: 0,
    edges: 0,
    pitch: 0,
    top: 0,
    typstPages: 0,
    ptomePages: 0,
    error: error,
  );
  final source = File('$out/$name.typ')
    ..writeAsStringSync(
      _preamble + File('${dir.path}/typst.typ').readAsStringSync(),
    );
  final typstPdf = '$out/$name-typst.pdf';
  final compiled = Process.runSync(typst, [
    'compile',
    '--ignore-system-fonts',
    '--font-path',
    devFonts,
    source.path,
    typstPdf,
  ]);
  if (compiled.exitCode != 0) return failed('typst: ${compiled.stderr}');
  final ptomePdf = '$out/$name-ptome.pdf';
  final converted = Process.runSync(exe, [
    '-b',
    'pdf',
    '-a',
    'pdf-theme=${File('${dir.path}/theme.yml').absolute.path}',
    '-a',
    'pdf-fontsdir=$fonts',
    '-a',
    'reproducible',
    '-o',
    ptomePdf,
    '${dir.path}/doc.adoc',
  ]);
  if (converted.exitCode != 0 ||
      (converted.stderr as String).contains('ERROR')) {
    return failed('ptome: ${converted.stderr}');
  }
  final a = _lines(typstPdf);
  final b = _lines(ptomePdf);
  if (verbose) {
    String show(_Line? l) => l == null
        ? '-'
        : '${l.top.toStringAsFixed(2)} ${l.left.toStringAsFixed(2)}-'
              '${l.right.toStringAsFixed(2)} ${l.text}';
    stdout.writeln('== $name');
    for (var i = 0; i < a.length || i < b.length; i++) {
      stdout
        ..writeln('  T ${show(i < a.length ? a[i] : null)}')
        ..writeln('  A ${show(i < b.length ? b[i] : null)}');
    }
  }
  var same = 0;
  var edges = 0.0;
  var pitch = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i].text == b[i].text) same++;
    edges = [
      edges,
      (a[i].left - b[i].left).abs(),
      (a[i].right - b[i].right).abs(),
    ].reduce((x, y) => x > y ? x : y);
    if (a[i].page == a[0].page && b[i].page == b[0].page) {
      final d = ((a[i].top - a[0].top) - (b[i].top - b[0].top)).abs();
      if (d > pitch) pitch = d;
    }
  }
  return (
    name: name,
    typstLines: a.length,
    ptomeLines: b.length,
    sameLines: same,
    edges: edges,
    pitch: pitch,
    top: a.isEmpty || b.isEmpty ? 0 : b[0].top - a[0].top,
    typstPages: _pages(typstPdf),
    ptomePages: _pages(ptomePdf),
    error: null,
  );
}

/// The lines of [pdf], in reading order.
List<_Line> _lines(String pdf) {
  final xml =
      Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout as String;
  final lines = <_Line>[];
  var page = -1;
  for (final m in RegExp(
    r'<page |<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
    r'yMax="[\d.]+">([\s\S]*?)</line>',
  ).allMatches(xml)) {
    if (m[0] == '<page ') {
      page++;
      continue;
    }
    final words = [
      for (final w in RegExp('<word[^>]*>([^<]*)</word>').allMatches(m[4]!))
        w[1]!,
    ];
    lines.add((
      page: page,
      text: words.join(' '),
      left: double.parse(m[1]!),
      right: double.parse(m[3]!),
      top: double.parse(m[2]!),
    ));
  }
  return lines;
}

int _pages(String pdf) {
  final info = Process.runSync('pdfinfo', [pdf]).stdout as String;
  return int.parse(RegExp(r'Pages:\s+(\d+)').firstMatch(info)![1]!);
}

String _table(List<_Result> results) {
  String n(double d) => d.toStringAsFixed(2);
  String row(_Result r) => switch (r.error) {
    final error? => '| ${r.name} | ${error.trim().split('\n').first} |||||| ',
    null =>
      '| ${r.name} | ${r.typstLines}, ${r.ptomeLines} | '
          '${r.sameLines} of ${r.typstLines} | ${n(r.edges)} | '
          '${n(r.pitch)} | ${r.top >= 0 ? '+' : ''}${n(r.top)} | '
          '${r.typstPages}, ${r.ptomePages} |',
  };
  const header =
      '| Case | Lines (Typst, ptome) | Broken alike | Edges | '
      'Line tops | First line | Pages |';
  return [
    header,
    '| --- | --- | --- | --- | --- | --- | --- |',
    for (final r in results) row(r),
  ].join('\n');
}

void _report(File file, String table) {
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final section = '## Latest run ($date)\n\n$table\n';
  final text = file.existsSync() ? file.readAsStringSync() : '';
  final at = text.indexOf('## Latest run');
  if (at < 0) {
    file.writeAsStringSync('${text.trimRight()}\n\n$section');
    return;
  }
  final next = text.indexOf('\n## ', at + 1);
  file.writeAsStringSync(
    text.substring(0, at) + section + (next < 0 ? '' : text.substring(next)),
  );
}

/// The Typst CLI, fetched once.
String _typst() {
  final dir = '$_cache/tools/typst-$_version';
  final exe = '$dir/typst';
  if (!File(exe).existsSync()) {
    Directory(dir).createSync(recursive: true);
    final archive = '$dir.tar.xz';
    _check(Process.runSync('curl', ['-sSL', '-o', archive, _typstRelease]));
    _check(
      Process.runSync('tar', [
        '-xJf',
        archive,
        '-C',
        dir,
        '--strip-components=1',
      ]),
    );
  }
  return exe;
}

/// The fonts of a Typst assets repository, cloned once.
String _assets(String repository) {
  final dir = '$_cache/$repository';
  if (!Directory(dir).existsSync()) {
    _check(
      Process.runSync('git', [
        'clone',
        '-q',
        '-c',
        'advice.detachedHead=false',
        '--depth',
        '1',
        '--branch',
        'v$_version',
        'https://github.com/typst/$repository.git',
        dir,
      ]),
    );
  }
  return '$dir/files/fonts';
}

void _check(ProcessResult result) {
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exit(1);
  }
}
