/// Checks that asciidart's output doesn't depend on its worker count
/// (ADR-0016), and times it.
///
/// ```sh
/// dart run tool/jobs_check.dart --exe build/asciidart [--jobs 1,2,6,12]
///     [--shuffle] [--backend pdf,html5,epub3] [--runs N] [--only NAME]
/// ```
///
/// Each document is converted with `-a jobs=1` (the serial reference) and
/// with every other count of `--jobs`, `SOURCE_DATE_EPOCH=0`; with
/// `--shuffle`, also with `ASCIIDART_JOBS_SHUFFLE=1`, which makes the pool
/// hand results back in a random order. Every output must be the same, byte
/// for byte, as the reference; the tool prints each document's times by
/// worker count (the median of `--runs`) and exits 1 on any difference.
///
/// The documents: the Hypermedia Systems book (its golden build, when the
/// port and its fonts are in their usual places under the home directory),
/// the PDF fixtures (`test/pdf/fixtures`) and asciidoctor-pdf's examples.
/// Run heavy checks in a memory-capped unit (`systemd-run --scope -p
/// MemoryMax=... -p MemorySwapMax=0`).
library;

import 'dart:io';

/// A document to convert: a name, its directory, its arguments.
typedef Doc = ({String name, String dir, List<String> args});

Future<void> main(List<String> args) async {
  var exe = 'build/asciidart';
  var jobs = [1, 2, 6, 12];
  var shuffle = false;
  var backends = ['pdf'];
  var runs = 1;
  String? only;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--exe':
        exe = args[++i];
      case '--jobs':
        jobs = [for (final n in args[++i].split(',')) int.parse(n)];
      case '--shuffle':
        shuffle = true;
      case '--backend':
        backends = args[++i].split(',');
      case '--runs':
        runs = int.parse(args[++i]);
      case '--only':
        only = args[++i];
      default:
        stderr.writeln('jobs_check: unknown argument ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  exe = File(exe).absolute.path;
  if (!jobs.contains(1)) jobs = [1, ...jobs];
  final out = Directory.systemTemp.createTempSync('jobs_check.');
  final docs = [
    ..._book(),
    for (final file in _adocs('test/pdf/fixtures'))
      (
        name: 'fixture ${_base(file)}',
        dir: File(file).parent.path,
        args: [file],
      ),
    for (final file in _adocs('vendor/asciidoctor-pdf/test/examples'))
      (
        name: 'example ${_base(file)}',
        dir: File(file).parent.path,
        args: [file],
      ),
  ].where((doc) => only == null || doc.name.contains(only)).toList();

  var failures = 0;
  final header = [
    'document'.padRight(32),
    for (final n in jobs) '-j$n'.padLeft(9),
    if (shuffle) 'shuffled'.padLeft(9),
  ].join();
  for (final backend in backends) {
    stdout
      ..writeln('\n== $backend')
      ..writeln(header);
    for (final doc in docs) {
      String? reference;
      final cells = <String>[];
      Future<void> check(int n, {bool shuffled = false}) async {
        final times = <double>[];
        String? digest;
        for (var r = 0; r < runs; r++) {
          final target =
              '${out.path}/${doc.name.replaceAll(RegExp(r'\W'), '_')}'
              '-$backend-$n${shuffled ? 's' : ''}.out';
          final watch = Stopwatch()..start();
          final result = await Process.run(
            exe,
            ['-b', backend, '-a', 'jobs=$n', '-o', target, ...doc.args],
            workingDirectory: doc.dir,
            environment: {
              'SOURCE_DATE_EPOCH': '0',
              if (shuffled) 'ASCIIDART_JOBS_SHUFFLE': '1',
            },
          );
          times.add(watch.elapsedMicroseconds / 1e6);
          final file = File(target);
          if (result.exitCode != 0 || !file.existsSync()) {
            digest =
                'failed (${result.exitCode}): '
                '${'${result.stderr}'.trim().split('\n').last}';
            break;
          }
          final run = _digest(file);
          if (digest != null && run != digest) {
            digest = 'differs between runs';
            break;
          }
          digest = run;
        }
        times.sort();
        final median = times[times.length ~/ 2];
        var mark = '';
        if (n == 1 && !shuffled) {
          reference = digest;
        } else if (digest != reference) {
          mark = '!';
          failures++;
          stderr.writeln(
            '${doc.name} ($backend, -j$n${shuffled ? ', shuffled' : ''}): '
            '${(digest?.length ?? 0) < 200 ? digest : 'different bytes'}',
          );
        }
        cells.add('${median.toStringAsFixed(2)}s$mark'.padLeft(9));
      }

      for (final n in jobs) {
        await check(n);
      }
      if (shuffle) await check(jobs.last, shuffled: true);
      stdout.writeln('${doc.name.padRight(32)}${cells.join()}');
    }
  }
  out.deleteSync(recursive: true);
  stdout.writeln(
    failures == 0
        ? '\njobs_check: every output the same at every worker count'
        : '\njobs_check: $failures outputs differ',
  );
  if (failures > 0) exitCode = 1;
}

/// The Hypermedia Systems book's golden build, when it's here.
List<Doc> _book() {
  final home = Platform.environment['HOME'] ?? '';
  final port = '$home/Work/ports/hypermedia-systems-asciidart';
  final golden = '$home/.cache/asciidart-work/hs-golden/fonts';
  if (!File('$port/HypermediaSystems.adoc').existsSync()) return const [];
  final goldenBuild = Directory(golden).existsSync();
  return [
    (
      name: 'Hypermedia Systems',
      dir: port,
      args: [
        if (goldenBuild) ...[
          '-a',
          'pdf-theme=hs-golden',
          '-a',
          'pdf-fontsdir=$golden;$port/fonts;GEM_FONTS_DIR',
        ],
        'HypermediaSystems.adoc',
      ],
    ),
  ];
}

List<String> _adocs(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return const [];
  return [
    for (final file in directory.listSync())
      if (file is File && file.path.endsWith('.adoc')) file.absolute.path,
  ]..sort();
}

String _base(String path) => path.split('/').last.replaceAll('.adoc', '');

/// [file]'s contents as a comparable string (bytes, as Latin-1).
String _digest(File file) => String.fromCharCodes(file.readAsBytesSync());
