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

import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/process.dart';

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

/// The canonical model of [a]: what the native engine must reproduce.
Map<String, Object> dump(Analysis a, String root) {
  String where(Unit u) =>
      '${p.relative(u.start.file.path, from: root)}:${u.start.line + 1}';
  return {
    'units': [
      for (final u in a.units)
        {
          'scheme': u.level.scheme.name,
          'level': u.level.name,
          'labels': {
            for (final (d, l) in u.labels.indexed)
              if (l != null) u.level.scheme.levels[d].name: l.text,
          },
          'id': u.id,
          'reftext': u.reftext,
          'ordinal': u.ordinal,
          'zero': u.isZero,
          'start': where(u),
        },
    ],
    'notes': [
      for (final use in a.notes.values)
        {
          'stream': use.stream.name,
          'caller': use.caller,
          'unit': ?use.unit?.id,
          'context': ?use.context?.id,
          'lemma': ?use.note.lemma,
          'body': use.note.body,
          'id': ?use.note.id,
        },
    ],
    'references': [
      for (final ref in a.refs.values)
        {
          'written': ref.xref.content,
          'parts': [
            for (final part in ref.parts)
              switch (part) {
                RefText(:final text) => {'text': text},
                RefLink(:final text, :final id, :final file) => {
                  'text': text,
                  'id': id,
                  'file': ?file,
                },
              },
          ],
        },
    ],
    'terms': {for (final k in (a.terms.keys.toList()..sort())) k: a.terms[k]!},
    'overlays': [
      for (final MapEntry(key: u, value: names) in a.overlays.entries)
        {'unit': u.id, 'names': names},
    ],
    'diagnostics': [
      for (final d in a.diagnostics)
        {
          'error': d.error,
          'at': d.loc == null
              ? ''
              : '${p.relative(d.loc!.file.path, from: root)}:'
                    '${d.loc!.line + 1}:${d.loc!.column + 1}',
          'message': d.message,
        },
    ],
  };
}
