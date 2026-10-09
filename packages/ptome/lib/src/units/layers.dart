/// Layers (ADR-0020): notes kept in documents of their own (a
/// commentary), each on a unit's address and the words of it it quotes. A
/// layer is an AsciiDoc document whose description lists hold its notes,
/// `2a:1 "the words quoted":: the note`, in the stream its header names
/// (`:layer-stream: rashi`).
library;

import 'package:ptome/src/context.dart';
import 'package:ptome/src/list.dart';
import 'package:ptome/src/load.dart';
import 'package:ptome/src/options.dart';
import 'package:ptome/src/units/files.dart' as p;

/// A layer's note: on the unit at `address`, at the words `lemma` (if it
/// quotes any), saying `body`.
typedef LayerNote = ({String address, String? lemma, String body});

/// The layer at [path] read with the safe mode [safe]: the stream its notes
/// are in, and its notes in order; `null` when there is no such file.
({String stream, List<LayerNote> notes})? readLayer(String path, int safe) {
  if (!p.isFile(path)) return null;
  final doc = loadFile(path, options: AsciidoctorOptions(safe: safe));
  final term = RegExp(r'^(\S+)(?:\s+"([^"]*)")?$');
  final notes = <LayerNote>[];
  for (final list in doc.findBy(context: BlockContext.dlist)) {
    if (list is! ListBlock) continue;
    for (final entry in list.entries) {
      final m = term.firstMatch(entry.terms.first.sourceText?.trim() ?? '');
      if (m == null) continue;
      notes.add((
        address: m[1]!,
        lemma: m[2],
        body: entry.description?.sourceText ?? '',
      ));
    }
  }
  return (stream: doc.attributes['layer-stream'] ?? 'footnote', notes: notes);
}

/// Hebrew vowel points and cantillation, which a commentary's quotation
/// leaves out.
final _points = RegExp('[\u0591-\u05C7]');

/// Where [lemma] is in [text] from [from], vowel points, punctuation and
/// markup aside: (start, end) in [text]. A lemma of two parts ("from …
/// to …", as Rashi quotes a passage by its first and last words) spans
/// from the first to the second.
(int, int)? findIgnoringPoints(String text, String lemma, int from) {
  final bare = StringBuffer();
  final map = <int>[]; // bare index -> text index
  var space = true;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (_points.hasMatch(c)) continue;
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c)) {
      bare.write(c);
      map.add(i);
      space = false;
    } else if (!space && (c == ' ' || c == '-' || c == '־')) {
      bare.write(' ');
      map.add(i);
      space = true;
    }
  }
  String norm(String s) => s
      .replaceAll(_points, '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final start = map.indexWhere((i) => i >= from);
  if (start < 0) return null;
  final b = bare.toString();
  (int, int)? find(String want, int at) {
    if (want.isEmpty) return null;
    final k = b.indexOf(want, at);
    return k < 0 ? null : (k, k + want.length);
  }

  var hit = find(norm(lemma), start);
  if (hit == null) {
    final parts = lemma
        .split(RegExp("\\.\\s+|\\s+\u05db\u05d5['\u05f3]\\s*"))
        .map(norm)
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final first = find(parts.first, start);
      final last = first == null ? null : find(parts.last, first.$2);
      if (first != null && last != null) hit = (first.$1, last.$2);
    }
  }
  if (hit == null) return null;
  var begin = map[hit.$1];
  var end = map[hit.$2 - 1] + 1;
  // Points after the last letter belong to it.
  while (end < text.length && _points.hasMatch(text[end])) {
    end++;
  }
  // The span takes whole markup: `**word**` in it or out of it.
  for (final mark in const ['**', '__']) {
    if (begin >= 2 && text.substring(begin - 2, begin) == mark) begin -= 2;
    final inside = mark.allMatches(text.substring(begin, end)).length;
    if (inside.isOdd && text.startsWith(mark, end)) end += 2;
  }
  return (begin, end);
}
