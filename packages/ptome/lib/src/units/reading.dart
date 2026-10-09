/// How ptome reads a document written in units (`:units:` in its header):
/// the units engine analyzes the document and its includes, then renders
/// each source file's lines, which ptome's reader takes in place of the
/// files' own lines. The parser and every backend then see units as the
/// markup they render to: anchors, labels, roles, notes and links.
library;

import 'package:ptome/src/logging.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/lower.dart';
import 'package:ptome/src/units/parallel.dart';
import 'package:ptome/src/units/process.dart';

/// The document in units at [left] and the one at [right] (in the same
/// scheme: a text and its translation) side by side, unit by unit, matched
/// by address alone: each heading of [left], then a table with a row per
/// unit of the default level. `null` when either is not written in units
/// or they share no unit.
String? parallelText(String left, String right) {
  final Analysis a;
  final Analysis b;
  try {
    a = analyze(left);
    b = analyze(right);
  } on Exception catch (e) {
    LoggerManager.logger.error('units: $e');
    return null;
  }
  if (a.units.isEmpty || !a.units.any((u) => b.byId.containsKey(u.id))) {
    return null;
  }
  final leftTexts = unitTexts(a);
  final rightTexts = unitTexts(b);
  final out = <String>[];
  var open = false;
  void close() {
    if (open) out.addAll(['|===', '']);
    open = false;
  }

  String cell(String? s) => (s ?? '').replaceAll('|', r'\|');
  for (final u in a.units) {
    if (u.heading case final h?) {
      close();
      // A heading that is only a marker (`== @PSA`) shows its unit's name.
      final title = h.title.trim().isEmpty ? u.reftext : h.title;
      out.addAll(['${'=' * (h.depth + 1)} $title', '']);
    }
    if (!u.level.isDefault) continue;
    final l = leftTexts[u.id] ?? '';
    final r = rightTexts[u.id] ?? '';
    if (l.isEmpty && r.isEmpty) continue;
    if (!open) {
      out.addAll(['[cols="1,1",grid=rows,frame=none]', '|===']);
      open = true;
    }
    final label = '^${u.level.bare(u.label)}^{nbsp}';
    out.add('|[[${u.id}]]$label${cell(l)} |$label${cell(r)}');
  }
  close();
  return '${out.join('\n').trimRight()}\n';
}

/// A units document's rendered source files.
final class UnitsReading {
  new _(this._files, this.analysis);

  final Map<String, List<String>> _files;

  /// The document's units, notes and references, as the engine found them.
  final Analysis analysis;

  /// The rendered lines of the source file at [path], or `null` for a file
  /// that is not part of the document (one ptome includes on its own).
  List<String>? linesOf(String path) => _files[p.normalize(p.absolute(path))];

  /// Reads the document at [docfile] when its header names schemes
  /// (`:units:`) or works it quotes by address (`:works:`); `null` for any
  /// other document. [asOf] keeps the text in
  /// force on that date (ISO `YYYY-MM-DD`).
  static UnitsReading? read(String docfile, {String? asOf}) {
    if (!p.isFile(docfile)) return null;
    final header = headerAttributes(docfile);
    // Schemes of its own, or other works it quotes by address.
    if (!header.containsKey('units') && !header.containsKey('works')) {
      return null;
    }
    final Analysis analysis;
    try {
      analysis = analyze(docfile);
    } on Exception catch (e) {
      LoggerManager.logger.error('units: $e');
      return null;
    }
    for (final d in analysis.diagnostics) {
      final where = d.loc == null ? '' : '${d.loc}: ';
      if (d.error) {
        LoggerManager.logger.error('$where${d.message}');
      } else {
        LoggerManager.logger.warn('$where${d.message}');
      }
    }
    final lowered = lower(analysis, asOf: asOf);
    // A rendered line may hold several (a unit's end, a block's
    // attributes before it).
    return UnitsReading._({
      for (final MapEntry(:key, :value) in lowered.entries)
        p.normalize(p.absolute(key)): [
          for (final line in value) ...line.split('\n'),
        ],
    }, analysis);
  }
}
