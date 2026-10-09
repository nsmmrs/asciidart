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
import 'package:ptome/src/units/process.dart';

/// A units document's rendered source files.
final class UnitsReading {
  new _(this._files);

  final Map<String, List<String>> _files;

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
    });
  }
}
