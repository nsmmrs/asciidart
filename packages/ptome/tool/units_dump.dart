// The canonical units model of an analysis, as JSON: what
// tool/units_oracle.dart records from milestone 1 and
// tool/units_model_check.dart compares the native model with (ADR-0020).
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;

/// The canonical model of [a]: what the native engine must reproduce.
Map<String, Object> dump(Analysis a, String root) {
  String where(Unit u) {
    if (u.start.file.originOf(u.start.line) case final o?) {
      return '${p.relative(o.file ?? o.path, from: root)}:${o.line}';
    }
    return '${p.relative(u.start.file.path, from: root)}:${u.start.line + 1}';
  }

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
          'at': d.loc == null ? '' : d.loc.toString(),
          'message': d.message,
        },
    ],
  };
}
