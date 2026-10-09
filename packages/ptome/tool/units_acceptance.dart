// The units acceptance gate (ADR-0019, milestone 1): for every document of
// a corpus in the units syntax, ptome's output for the document itself
// must be byte-identical to ptome's output for the oracle's rendering of
// it (loci's lowering), in HTML5, DocBook 5 and PDF.
//
//   dart run tool/units_acceptance.dart --exe PTOME --corpus DIR \
//       --oracle DIR --out DIR [--backends html5,docbook5,pdf] [DOC...]
//
// The corpus holds the documents with their `schemes/` as YAML (and
// `themes/` for the PDFs); the oracle holds each document's lowering in a
// directory named after it (`bible/kjv/kjv` for `bible/kjv/kjv.adoc`).
import 'dart:io';

void main(List<String> args) {
  String? opt(String name) {
    final i = args.indexOf(name);
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  final exe = opt('--exe') ?? 'ptome';
  final corpus = opt('--corpus') ?? (throw ArgumentError('--corpus'));
  final oracle = opt('--oracle') ?? (throw ArgumentError('--oracle'));
  final out = opt('--out') ?? (throw ArgumentError('--out'));
  final backends = (opt('--backends') ?? 'html5,docbook5,pdf').split(',');
  final named = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      i++;
    } else {
      named.add(args[i]);
    }
  }
  final docs = named.isNotEmpty ? named : _documents(corpus);
  var failed = 0;
  final rows = <String>[];
  for (final entry in docs) {
    // `DOC@DATE`: the document as in force on DATE (`units-as-of`), against
    // the oracle's lowering at that date (in `STEM@DATE`).
    final at = entry.indexOf('@');
    final doc = at < 0 ? entry : entry.substring(0, at);
    final asOf = at < 0 ? null : entry.substring(at + 1);
    final base = doc.replaceAll(RegExp(r'\.adoc$'), '');
    final stem = asOf == null ? base : '$base@$asOf';
    final lowered = File('$oracle/$stem/${base.split('/').last}.adoc');
    if (!lowered.existsSync()) {
      rows.add('| $entry | (no oracle) | | |');
      continue;
    }
    final cells = <String>[];
    for (final backend in backends) {
      final ext = switch (backend) {
        'pdf' => 'pdf',
        'docbook5' => 'xml',
        _ => 'html',
      };
      final dir = '$out/$stem';
      Directory(dir).createSync(recursive: true);
      final extra = [
        if (backend == 'pdf' && doc.startsWith('bible/')) ...[
          '-d',
          'article',
          '-a',
          'pdf-theme=${File('$corpus/themes/kjv-theme.yml').absolute.path}',
        ],
      ];
      final watch = Stopwatch()..start();
      final native = _run(exe, backend, '$corpus/$doc', '$dir/native.$ext', [
        ...extra,
        if (asOf != null) ...['-a', 'units-as-of=$asOf'],
      ]);
      final nativeMs = watch.elapsedMilliseconds;
      final reference = _run(
        exe,
        backend,
        lowered.path,
        '$dir/oracle.$ext',
        // The oracle is standard AsciiDoc that keeps its `:units:` entry.
        [...extra, '-a', 'units!'],
      );
      final same =
          native &&
          reference &&
          _sameBytes('$dir/native.$ext', '$dir/oracle.$ext');
      if (!same) failed++;
      cells.add('${same ? 'pass' : 'FAIL'} ($nativeMs ms)');
    }
    rows.add('| $entry | ${cells.join(' | ')} |');
    stdout.writeln(rows.last);
  }
  stdout
    ..writeln()
    ..writeln('| Document | ${backends.join(' | ')} |')
    ..writeln('|---|${backends.map((_) => '---').join('|')}|')
    ..writeln(rows.join('\n'))
    ..writeln()
    ..writeln(
      failed == 0
          ? 'units acceptance: all pass'
          : 'units acceptance: $failed fail',
    );
  exit(failed == 0 ? 0 : 1);
}

List<String> _documents(String corpus) {
  final root = Directory(corpus).absolute.path;
  return [
    for (final f in Directory(root).listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.adoc') &&
          !f.path.contains('/schemes/') &&
          f
              .readAsLinesSync()
              .take(30)
              .any((l) => l.startsWith(':units:') || l.startsWith(':works:')))
        f.path.substring(root.length + 1),
  ]..sort();
}

bool _run(
  String exe,
  String backend,
  String input,
  String output,
  List<String> extra,
) {
  final r = Process.runSync(
    exe,
    [
      '-b',
      backend,
      '-S',
      'unsafe',
      '-a',
      'reproducible',
      ...extra,
      '-o',
      output,
      input,
    ],
    environment: {'SOURCE_DATE_EPOCH': '0'},
  );
  File('$output.log').writeAsStringSync('${r.stdout}${r.stderr}');
  return r.exitCode == 0 && File(output).existsSync();
}

bool _sameBytes(String a, String b) {
  final x = File(a).readAsBytesSync();
  final y = File(b).readAsBytesSync();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
