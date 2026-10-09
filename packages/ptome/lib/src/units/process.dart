/// Reads, analyzes and lowers documents: finds a document's scheme files
/// (`:units:`, looked up in the nearest `schemes/` directory above it), the
/// other works it cites (`:works: bible=../bible/kjv/kjv.adoc`), and runs
/// the engine.
library;

import 'package:ptome/src/units/citation.dart';
import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/lower.dart';
import 'package:ptome/src/units/scheme.dart';

/// The header attributes of [path] (before reading the whole document).
Map<String, String> headerAttributes(String path) {
  final out = <String, String>{};
  var seenTitle = false;
  for (final line in p.readLines(path)) {
    if (!seenTitle) {
      if (line.startsWith('= ')) {
        seenTitle = true;
        continue;
      }
      // A header with no title: attribute entries at the top.
      if (!line.startsWith(':')) continue;
      seenTitle = true;
    }
    if (line.trim().isEmpty) break;
    final m = RegExp(r'^:([\w-]+!?):\s*(.*)$').firstMatch(line);
    if (m != null) out[m[1]!] = m[2]!;
  }
  return out;
}

/// The `schemes/` directory nearest above [path].
String? schemesDir(String path) {
  var dir = p.dirname(p.absolute(path));
  while (true) {
    final candidate = p.join(dir, 'schemes');
    if (p.isDirectory(candidate)) return candidate;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

final _cache = <String, Analysis>{};

/// [path] analyzed (once per run).
Analysis analyze(String path, {bool fresh = false}) {
  final key = p.normalize(p.absolute(path));
  if (!fresh) {
    if (_cache[key] case final a?) return a;
  }
  final attrs = headerAttributes(key);
  final units = attrs['units'];
  final config = units == null
      ? Config.empty()
      : Config.load(
          units.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList(),
          schemesDir(key) ??
              (throw StateError('no schemes/ directory above $path')),
        );
  final doc = readDocument(
    key,
    rangeNames: config.ranges.keys.toSet(),
    active: units != null,
  );
  final works = <String, Analysis>{};
  for (final entry
      in (attrs['works'] ?? '')
          .split(RegExp(r'\s*;\s*'))
          .where((s) => s.contains('='))) {
    final eq = entry.indexOf('=');
    final names = entry.substring(0, eq).split('|').map((n) => n.trim());
    final other = analyze(
      p.join(p.dirname(key), entry.substring(eq + 1).trim()),
    );
    for (final n in names) {
      works[n] = other;
    }
  }
  var a = Engine(doc, config, works: works).run();
  // Layers: notes kept in other files (a commentary), each on an address
  // and the words it quotes, woven into the text where those words are.
  final layers = (attrs['layers'] ?? '')
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (layers.isNotEmpty) {
    final overrides = weaveLayers(a, [
      for (final l in layers) p.join(p.dirname(key), l),
    ]);
    final woven = readDocument(
      key,
      rangeNames: config.ranges.keys.toSet(),
      active: units != null,
      overrides: overrides,
    );
    a = Engine(woven, config, works: works).run();
  }
  _cache[key] = a;
  _checkIncludes(a);
  return a;
}

/// Every passage [a] includes is there, and every citation style it asks
/// for is declared.
void _checkIncludes(Analysis a) {
  for (final e in a.document.events) {
    if (e is! IncludeUnit) continue;
    final path = includePath(a, e.loc.file.path, e.target);
    if (!p.isFile(path)) {
      a.error(e.loc, 'no document ${e.target} to include from');
      continue;
    }
    final target = analyze(path);
    if (resolvePassage(target, e.address) == null) {
      a.error(e.loc, 'no passage ${e.address} in ${e.target}');
    } else if (e.cite case final style?
        when style != 'none' && !target.config.citations.containsKey(style)) {
      a.warn(e.loc, '${e.target} declares no citation style $style');
    }
  }
}

/// Hebrew vowel points and cantillation, which a commentary's quotation
/// leaves out.
final _points = RegExp('[\u0591-\u05C7]');

/// The [layers]' notes as `##lemma##note:STREAM[…]` inserted into [a]'s
/// lines: by file, the lines with the notes in.
Map<String, List<String>> weaveLayers(Analysis a, List<String> layers) {
  final out = <String, List<String>>{
    for (final f in a.document.files) f.path: [...f.lines],
  };
  // Insertions by file and line: (column, end of lemma or null, text).
  final inserts = <String, Map<int, List<(int, int?, String)>>>{};
  for (final layer in layers) {
    final lines = p.readLines(layer);
    final attrs = headerAttributes(layer);
    final stream = attrs['layer-stream'] ?? 'footnote';
    // Where the last note of a unit went, so the next looks after it.
    final after = <Unit, (int, int)>{};
    for (final line in lines) {
      final m = RegExp(r'^(\S+)(?:\s+"([^"]*)")?::\s+(.*)$').firstMatch(line);
      if (m == null) continue;
      final address = m[1]!;
      final lemma = m[2];
      final body = m[3]!.replaceAll(']', r'\]');
      final unit = _resolve(a, address);
      if (unit == null) {
        a.warn(null, '${p.basename(layer)}: $address not found');
        continue;
      }
      // The unit's lines, from its start to its end (or the end of its
      // block).
      final file = unit.start.file;
      final startLine = unit.start.line;
      final endLine = unit.end != null && unit.end!.file == file
          ? unit.end!.line
          : file.lines.length - 1;
      var placed = false;
      final from = after[unit] ?? (startLine, unit.start.column);
      for (var ln = from.$1; ln <= endLine && !placed; ln++) {
        final text = out[file.path]![ln];
        if (ln > startLine && text.trim().isEmpty) break;
        final startCol = ln == from.$1 ? from.$2 : 0;
        if (lemma == null || lemma.isEmpty) {
          ((inserts[file.path] ??= {})[startLine] ??= []).add((
            file.lines[startLine].length,
            null,
            'note:$stream[$body]',
          ));
          placed = true;
          break;
        }
        final hit = _findIgnoringPoints(text, lemma, startCol);
        if (hit != null) {
          ((inserts[file.path] ??= {})[ln] ??= []).add((
            hit.$1,
            hit.$2,
            'note:$stream[$body]',
          ));
          after[unit] = (ln, hit.$2);
          placed = true;
        }
      }
      if (!placed) {
        // Not found as quoted: at the end of the unit's first line.
        ((inserts[file.path] ??= {})[startLine] ??= []).add((
          file.lines[startLine].length,
          null,
          'note:$stream[${lemma == null ? '' : '__${lemma}__ – '}$body]',
        ));
      }
    }
  }
  for (final MapEntry(key: path, value: byLine) in inserts.entries) {
    for (final MapEntry(key: ln, value: list) in byLine.entries) {
      var text = out[path]![ln];
      // From the end, so earlier columns stay put.
      list.sort((x, y) => (y.$2 ?? y.$1).compareTo(x.$2 ?? x.$1));
      for (final (start, end, note) in list) {
        if (end == null) {
          text = '${text.substring(0, start)}$note${text.substring(start)}';
        } else {
          final lemma = text.substring(start, end);
          text =
              '${text.substring(0, start)}##$lemma##$note'
              '${text.substring(end)}';
        }
      }
      out[path]![ln] = text;
    }
  }
  return out;
}

Unit? _resolve(Analysis a, String address) {
  for (final s in a.config.schemes) {
    for (final pp in parseCompound(s, address, cite: true)) {
      final full = List<Label?>.filled(s.levels.length, null);
      for (final MapEntry(key: d, value: l) in pp.labels.entries) {
        full[d] = l;
      }
      final u = a.index[a.keyOf(s, full.sublist(0, pp.end + 1))];
      if (u != null) return u;
    }
  }
  return null;
}

/// Where [lemma] is in [text] from [from], vowel points, punctuation and
/// markup aside: (start, end) in [text]. A lemma of two parts ("from …
/// to …", as Rashi quotes a passage by its first and last words) spans
/// from the first to the second.
(int, int)? _findIgnoringPoints(String text, String lemma, int from) {
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

final _loweredCache = <String, Lowered>{};
final _quotedCache = <String, Lowered>{};

/// The document an include's [target] names, seen from [from] (the file
/// the include is in) in [a]: a work [a] cites (`bible`), or a path.
String includePath(Analysis a, String from, String target) {
  for (final entry
      in (a.document.attributes['works'] ?? '')
          .split(RegExp(r'\s*;\s*'))
          .where((s) => s.contains('='))) {
    final eq = entry.indexOf('=');
    if (entry.substring(0, eq).split('|').any((n) => n.trim() == target)) {
      return p.normalize(
        p.join(p.dirname(a.document.root.path), entry.substring(eq + 1).trim()),
      );
    }
  }
  return p.normalize(p.join(p.dirname(from), target));
}

/// The lowered lines of the passage at [address] in the document at
/// [path]: spliced as they are (with [cite] `none`), or quoted, without
/// anchors, headings or notes, in a block that cites the passage as that
/// document's citation style [cite] (its `default` without one) does.
List<String>? includeUnit(String path, String address, {String? cite}) {
  final target = analyze(path);
  final passage = resolvePassage(target, address);
  if (passage == null) return null;
  final splice = cite == 'none';
  final lowered = splice
      ? (_loweredCache[path] ??= lower(target))
      : (_quotedCache[path] ??= lower(target, quoting: true));
  final lines = lowered[passage.start.start.file.path];
  if (lines == null) return null;
  bool anchors(String l, Unit u) =>
      l.contains('[[${u.id},') || l.contains('[[${u.id}]]');
  final from = lines.indexWhere((l) => anchors(l, passage.start));
  if (from < 0) return null;
  // To the next unit of the end's level or above that prints an anchor
  // (a Bekker page prints none; its first line does).
  final end = passage.end;
  final next = [
    for (final u in target.units.skip(target.units.indexOf(end) + 1))
      if (u.level.scheme == end.level.scheme &&
          u.level.depth <= end.level.depth &&
          !u.isZero)
        u,
  ];
  if (splice) {
    var to = lines.length;
    for (final u in next) {
      final i = lines.indexWhere((l) => anchors(l, u), from + 1);
      if (i >= 0) {
        to = i;
        break;
      }
    }
    // Not the next unit's heading attributes or overlay marks.
    while (to > from + 1 &&
        (RegExp(r'^\[[^\[]').hasMatch(lines[to - 1]) ||
            lines[to - 1].trim().isEmpty)) {
      to--;
    }
    return lines.sublist(from, to);
  }
  // A quotation is cut where its units start and end, within a line where
  // they do (a Bekker line, a Stephanus section): from the start's mark (a
  // block's prefix kept: a speaker, a bullet) to the next unit's.
  final rest = lines.sublist(from).join('\n');
  int at(Unit u, [int after = 0]) {
    final marked = rest.indexOf('$quoteStart${u.id}$quoteMid', after);
    if (marked >= 0) return marked;
    final i = rest.indexOf('[[${u.id},', after);
    return i >= 0 ? i : rest.indexOf('[[${u.id}]]', after);
  }

  final start = at(passage.start);
  var stop = rest.length;
  for (final u in next) {
    final i = at(u, start + 1);
    if (i >= 0) {
      stop = i;
      break;
    }
  }
  final lineStart = rest.lastIndexOf('\n', start) + 1;
  final prefix = rest.substring(lineStart, start);
  final kept = RegExp(r'^(\S[^:]*::\s+|[*.]+\s+|\[\.[\w-]+\]#[^#]*#\s*)?')
      .firstMatch(prefix)![0]!;
  final cut = (kept + rest.substring(start, stop)).split('\n');
  while (cut.length > 1 &&
      (RegExp(r'^\[[^\[]').hasMatch(cut.last) || cut.last.trim().isEmpty)) {
    cut.removeLast();
  }
  cut.last = cut.last.trimRight();
  // A passage that starts within a block keeps the block's attributes
  // (a psalm's line breaks).
  var para = from;
  while (para > 0 && lines[para - 1].trim().isNotEmpty) {
    para--;
  }
  final body = [
    for (var i = para; i < from; i++)
      if (RegExp(r'^\[[^\[].*\]$').hasMatch(lines[i])) lines[i],
    ...cut,
  ];
  return _quote(target, passage, body, cite ?? 'default');
}

final _listLike = RegExp(
  r'^\s*(\d+\.|[A-Za-z]\.|[ivxIVX]+\)|\*+|\.+|-|<\d+>)\s',
);

/// [body] as a quotation of [passage] of [a], cited.
List<String> _quote(
  Analysis a,
  Passage passage,
  List<String> body,
  String style,
) {
  final (attribution, title, block, labels) = citation(
    a,
    passage,
    style: style,
  );
  final mark = RegExp(
    '$quoteStart([^$quoteMid]*)$quoteMid([^$quoteEnd]*)$quoteEnd',
  );
  final text = <String>[];
  for (var i = 0; i < body.length; i++) {
    final line = body[i];
    // Headings, and the attribute lines that go with them, are the cited
    // document's, not the quotation's.
    if (RegExp('^=+ ').hasMatch(line)) {
      while (text.isNotEmpty && RegExp(r'^\[.*\]$').hasMatch(text.last)) {
        text.removeLast();
      }
      continue;
    }
    final bare = line
        .replaceAllMapped(
          mark,
          (m) => switch (labels) {
            QuoteLabels.none => '',
            QuoteLabels.inner when passage.single && m[1] == passage.start.id =>
              '',
            _ => m[2]!,
          },
        )
        // An anchor's reftext may have brackets of its own
        // (`[[basic.pre-3,[basic.pre]/3]]`).
        .replaceAll(RegExp(r'\[\[[^\s,\[\]]+(?:,.*?)?\]\](?!\])'), '')
        .replaceAllMapped(RegExp('<<[^,>]+,([^>]+)>>'), (m) => m[1]!)
        .replaceAllMapped(RegExp('<<([^,>]+)>>'), (m) => m[1]!);
    if (bare.trim().isEmpty && line.trim().isNotEmpty) continue;
    // A label the anchor came before reads as list markup once alone at
    // the start of the line (`2. Member States`).
    if (_listLike.hasMatch(bare) && !_listLike.hasMatch(line)) {
      text.add('{empty}$bare');
      continue;
    }
    if (bare.trim().isEmpty && (text.isEmpty || text.last.trim().isEmpty)) {
      continue;
    }
    text.add(bare);
  }
  while (text.isNotEmpty &&
      (text.last.trim().isEmpty || RegExp(r'^\[.*\]$').hasMatch(text.last))) {
    text.removeLast();
  }
  // Blocks the cited document's settings leave out of quotations (a
  // Bible's parallel-passage references), and line breaks at the end of
  // a paragraph.
  final unquoted = {...?a.config.settings['unquoted']?.split(RegExp(r'[\s,]+'))}
    ..remove('');
  for (var i = 0; i < text.length; i++) {
    final roles = RegExp(r'^\[[^\]]*\]$').hasMatch(text[i])
        ? RegExp(r'\.([\w-]+)').allMatches(text[i]).map((m) => m[1]!)
        : const <String>[];
    if (roles.any(unquoted.contains)) {
      var j = i;
      while (j < text.length && text[j].trim().isNotEmpty) {
        j++;
      }
      while (j < text.length && text[j].trim().isEmpty) {
        j++;
      }
      text.removeRange(i, j);
      i--;
      continue;
    }
    if ((i + 1 == text.length || text[i + 1].trim().isEmpty) &&
        text[i].endsWith(' +')) {
      text[i] = text[i].substring(0, text[i].length - 2);
    }
  }
  while (text.isNotEmpty && text.last.trim().isEmpty) {
    text.removeLast();
  }
  String attr(String v) => '"${v.replaceAll('"', '&quot;')}"';
  // A delimiter longer than any the quotation has.
  var delimiter = '____';
  for (final l in text) {
    if (RegExp(r'^_{4,}$').hasMatch(l) && l.length >= delimiter.length) {
      delimiter = '_' * (l.length + 1);
    }
  }
  final citationAttrs = attribution.isEmpty && title.isEmpty
      ? ''
      : ',${attr(attribution)}${title.isEmpty ? '' : ',${attr(title)}'}';
  return ['[$block$citationAttrs]', delimiter, ...text, delimiter];
}
