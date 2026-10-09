// Dumps the units model of documents in units as canonical JSON: the
// oracle the native units engine is checked against (ADR-0020, phase 0).
// It reads the documents with milestone 1's engine (lib/src/units/), which
// this oracle outlives: the dumps are kept, the engine goes.
//
//   dart run tool/units_oracle.dart OUT_DIR CORPUS [DOC...]
//
// Writes OUT_DIR/<doc path>.json for each document (default: every
// `.adoc` under CORPUS whose header names `:units:` or `:works:`).
import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/process.dart';

import 'units_dump.dart';

void main(List<String> args) {
  final out = args[0];
  final corpus = Directory(args[1]).absolute.path;
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
                          .any(
                            (l) =>
                                l.startsWith(':units:') ||
                                l.startsWith(':works:'),
                          ))
                    p.relative(f, from: corpus),
              ]
        ..sort();
  for (final doc in docs) {
    final a = analyze(p.join(corpus, doc));
    File('$out/$doc.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(dump(a, corpus))}\n',
      );
    stdout.writeln(
      '$doc: ${a.units.length} units, ${a.notes.length} notes, '
      '${a.refs.length} references',
    );
  }
}
