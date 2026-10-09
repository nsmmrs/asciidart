// Checks ptome's port of the units engine against loci's: lowers every
// document of a corpus (loci's documents with the schemes as YAML) and
// compares each lowered file with loci's own lowering.
//
//   dart run tool/units_port_check.dart CORPUS ORACLE [DOC...]
import 'dart:io';

import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/lower.dart';
import 'package:ptome/src/units/process.dart';

void main(List<String> args) {
  final corpus = args[0];
  final oracle = args[1];
  final docs =
      args.length > 2
            ? args.sublist(2)
            : [
                for (final f in p.listFiles(corpus))
                  if (f.endsWith('.adoc') &&
                      !f.contains('/schemes/') &&
                      File(f)
                          .readAsLinesSync()
                          .take(30)
                          .any((l) => l.startsWith(':units:')))
                    p.relative(f, from: corpus),
              ]
        ..sort();
  var failed = 0;
  for (final doc in docs) {
    final path = p.join(corpus, doc);
    final outDir = p.join(oracle, doc.replaceAll(RegExp(r'\.adoc$'), ''));
    if (!Directory(outDir).existsSync()) {
      stdout.writeln('skip $doc (no oracle)');
      continue;
    }
    final watch = Stopwatch()..start();
    final a = analyze(path);
    final lowered = lower(a);
    final root = p.dirname(a.document.root.path);
    var same = 0;
    var differ = 0;
    for (final MapEntry(key: file, value: lines) in lowered.entries) {
      final want = File(p.join(outDir, p.relative(file, from: root)));
      final got = '${lines.join('\n')}\n';
      if (want.existsSync() && want.readAsStringSync() == got) {
        same++;
      } else {
        differ++;
        if (differ <= 3) {
          stdout.writeln('  differs: ${p.relative(file, from: root)}');
        }
      }
    }
    if (differ > 0) failed++;
    stdout.writeln(
      '${differ == 0 ? 'ok  ' : 'FAIL'} $doc: $same same, $differ differ '
      '(${watch.elapsedMilliseconds} ms)',
    );
  }
  exit(failed == 0 ? 0 : 1);
}
