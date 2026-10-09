/// Parallel texts: two documents in one scheme (the Pali and its English,
/// the Arabic and Pickthall) set side by side, unit by unit, matched by
/// address alone: nothing in either document points at the other.
library;

import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/engine.dart';

/// Each default-level unit's text in [a]: from its marker to the next
/// marker or the end of its block, as written.
Map<String, String> unitTexts(Analysis a) {
  final markersByLine = <(SourceFile, int), List<Marker>>{};
  for (final e in a.document.events) {
    if (e case TokenEvent(token: final Marker m)) {
      (markersByLine[(m.loc.file, m.loc.line)] ??= []).add(m);
    }
  }
  final out = <String, String>{};
  String? current;
  final buffer = StringBuffer();
  void flush() {
    if (current != null) {
      out[current!] = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    current = null;
    buffer.clear();
  }

  for (final e in a.document.events) {
    switch (e) {
      case HeadingEvent(:final marker, :final title):
        flush();
        // A heading that is a unit's text (a sutta's title).
        final u = marker == null ? null : a.unitOfMarker[marker];
        if (u != null && u.level.isDefault) out[u.id] = title;
      case BlockEnd():
        flush();
      case LineStart(:final loc):
        final source = loc.file.lines[loc.line];
        var pos = 0;
        for (final m
            in markersByLine[(loc.file, loc.line)] ?? const <Marker>[]) {
          buffer.write(source.substring(pos, m.loc.column));
          final u = a.unitOfMarker[m];
          if (u != null && u.level.isDefault) {
            flush();
            current = u.id;
          }
          pos = m.end;
        }
        buffer.write(' ${source.substring(pos)}');
      default:
        break;
    }
  }
  flush();
  return out;
}
