/// Citations made from addresses: a passage of a document, given by its
/// address (`Ps 23:1-3`, `552(a)(1)`, `3.1.64-68`), resolved to its units
/// and cited again from them, in the cited document's own forms: its title
/// and attributes, its levels' citation forms, its canon's book names, and
/// the citation styles its schemes declare. Nothing in the citation is
/// copied from the address the author wrote.
library;

import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/scheme.dart';
import 'package:ptome/src/units/template.dart';

/// A passage: the units it starts and ends at (the same for one unit).
final class Passage {
  /// A passage from [start] to [end].
  new(this.start, this.end);

  /// The passage's first unit.
  final Unit start;

  /// The passage's last unit (the same as [start] for one unit).
  final Unit end;

  /// Whether the passage is one unit.
  bool get single => identical(start, end);
}

/// The passage [address] names in [a] (one address, or a range whose end
/// leaves out what it shares with its start), or null.
Passage? resolvePassage(Analysis a, String address) {
  final dash = RegExp('[-–—]').firstMatch(address);
  // A bridge label (`4-5`) is one unit; try the whole first.
  final whole = _resolve(a, address.trim());
  if (whole != null) return Passage(whole, whole);
  if (dash == null) return null;
  final start = _resolve(a, address.substring(0, dash.start).trim());
  if (start == null) return null;
  final right = address.substring(dash.end).trim();
  final s = start.level.scheme;
  // The end inherits the levels above where it starts; it is a unit of the
  // start's level if it can be (`1:1-7` ends at the seventh ayah, not the
  // seventh surah).
  final depth = start.level.depth;
  final readings = parseCompound(s, right, cite: true)
    ..sort((x, y) => (x.end == depth ? 0 : 1) - (y.end == depth ? 0 : 1));
  for (final pp in readings) {
    if (pp.end != depth && pp.start > depth) continue;
    final full = List<Label?>.filled(s.levels.length, null);
    for (var d = 0; d < pp.start; d++) {
      full[d] = d < start.labels.length ? start.labels[d] : null;
    }
    for (final MapEntry(key: d, value: l) in pp.labels.entries) {
      full[d] = l;
    }
    final end = a.index[a.keyOf(s, full.sublist(0, pp.end + 1))];
    if (end != null && end.start.compareTo(start.start) >= 0) {
      return Passage(start, end);
    }
  }
  return null;
}

Unit? _resolve(Analysis a, String address) {
  for (final s in a.config.schemes) {
    // Outermost readings first: `Ps 23` is the chapter, not a verse.
    final parsed = parseCompound(s, address, cite: true)
      ..sort((x, y) => x.start.compareTo(y.start));
    for (final pp in parsed) {
      final full = List<Label?>.filled(s.levels.length, null);
      for (final MapEntry(key: d, value: l) in pp.labels.entries) {
        full[d] = l;
      }
      final u = a.index[a.keyOf(s, full.sublist(0, pp.end + 1))];
      // A range (`1-3`) is not its first unit, unless that is a bridge.
      if (u != null &&
          (pp.labels[pp.end]!.end == null || u.label.end != null)) {
        return u;
      }
    }
  }
  return null;
}

/// A unit's address as citations write it, piece by piece (level, text):
/// each level's citation form and the separator before it; a book by its
/// abbreviation, or with [long] by its name.
List<(int, String)> _pieces(Unit u, Config config, {required bool long}) {
  final out = <(int, String)>[];
  final s = u.level.scheme;
  for (final (d, l) in u.labels.indexed) {
    if (l == null) continue;
    final level = s.levels[d];
    if (level.hidden) continue;
    String text;
    if (level.type case CodeType(:final canon)) {
      final book = canon.byCode[l.text];
      text = book == null
          ? l.text
          : (long ? (book.fields['cite-name'] ?? book.name) : book.abbr);
    } else {
      final bare = level.bare(l);
      final (open, close) = level.cited;
      text = '$open$bare$close';
    }
    out.add((d, out.isEmpty ? text : '${level.sep}$text'));
  }
  return out;
}

/// [p] as a citation's passage: the start whole, the end without what it
/// shares with it (`Ps 23:1–3`, `3.1.64–68`, `552(a)(1)–(3)`,
/// `1094a1–1094b5`).
String passageText(Passage p, Config config, {bool long = false}) {
  final start = _pieces(p.start, config, long: long);
  if (p.single) return start.map((x) => x.$2).join();
  final end = _pieces(p.end, config, long: long);
  var shared = 0;
  while (shared < start.length &&
      shared < end.length &&
      start[shared] == end[shared]) {
    shared++;
  }
  if (shared == end.length) return start.map((x) => x.$2).join();
  // An end of more than one piece leaves out what it shares with the
  // start only where it could not be read from the top: `Ps 23:6–24:2`
  // (`24:2` is no book), but `3.1.89–3.2.4` (`2.4` would be act 2,
  // scene 4). One piece always does: `3.1.64–68`, `1:1–7`.
  if (end.length - shared > 1) {
    final s = p.end.level.scheme;
    final compact = _pieces(p.end, config, long: false).sublist(shared);
    final sep = s.levels[compact.first.$1].sep;
    final text = compact.map((x) => x.$2).join();
    final top = s.levels.indexWhere((l) => !l.hidden);
    if (parseCompound(
      s,
      text.startsWith(sep) ? text.substring(sep.length) : text,
      cite: true,
    ).any((pp) => pp.start == top)) {
      shared = 0;
    }
  }
  final rest = end.sublist(shared);
  // A range of units cited with a word, in its plural: `Articles 6–7`.
  final from = p.start.level.scheme.levels[rest.first.$1];
  final l = p.start.labels[rest.first.$1];
  if ((from.citeWrap, from.citeRangeWrap, l)
      case (
        (final one, final oneClose),
        (final many, final manyClose),
        final l?,
      )
      when shared < start.length && start[shared].$1 == rest.first.$1) {
    final piece = start[shared].$2;
    final bare = from.bare(l);
    final at = piece.indexOf('$one$bare$oneClose');
    if (at >= 0) {
      start[shared] = (
        start[shared].$1,
        piece.replaceRange(
          at,
          at + one.length + bare.length + oneClose.length,
          '$many$bare$manyClose',
        ),
      );
    }
  }
  final first = start.map((x) => x.$2).join();
  // The end's first piece without the separator it had after a shared one.
  final level = p.end.level.scheme.levels[rest.first.$1];
  var head = rest.first.$2.startsWith(level.sep)
      ? rest.first.$2.substring(level.sep.length)
      : rest.first.$2;
  // A level cited with a word (`Article 6`, `s. 1`) drops it after the
  // dash: `Article 6–7`, not `Article 6–Article 7`.
  if (level.citeWrap case (final open, _)
      when open.endsWith(' ') && head.startsWith(open)) {
    head = head.substring(open.length);
  }
  return '$first–$head${rest.skip(1).map((x) => x.$2).join()}';
}

/// What citation templates see for [p] in [a]: `passage`, `passage-long`,
/// `title` (the document's), the document's attributes (`doc.*`), the
/// start's and end's labels (`start.*`, `end.*`), `single`.
Map<String, TValue> citationContext(Analysis a, Passage p) {
  Map<String, TValue> labels(Unit u) => {
    for (final (d, l) in u.labels.indexed)
      if (l != null)
        u.level.scheme.levels[d].name: TText(u.level.scheme.levels[d].bare(l)),
  };
  return {
    'passage': TText(passageText(p, a.config)),
    'passage-long': TText(passageText(p, a.config, long: true)),
    'title': TText(a.document.attributes['doctitle'] ?? ''),
    'doc': TRecord({
      for (final MapEntry(:key, :value) in a.document.attributes.entries)
        key: TText(value),
    }),
    'start': TRecord(labels(p.start)),
    'end': TRecord(labels(p.end)),
    'single': TFlag(value: p.single),
  };
}

/// Which of a passage's printed labels a quotation keeps: every one (a
/// catechism's `Q. 1.`), every one but a single unit's own, which its
/// citation gives (`inner`, the default: a statute's `(a)` and `(b)` in
/// `6(1)(a)–(b)`, none in `6(1)(a)`), or none (a play's line numbers).
enum QuoteLabels {
  /// Every label.
  all,

  /// Every label but the first.
  inner,

  /// No labels.
  none,
}

/// The citation of [p] in [a]'s style [style]: (attribution, title, block
/// style, labels kept). Without a declared style: the passage, and the
/// document's title.
(String, String, String, QuoteLabels) citation(
  Analysis a,
  Passage p, {
  String style = 'default',
}) {
  final templates =
      a.config.citations[style] ?? a.config.citations['default'] ?? const {};
  final ctx = citationContext(a, p);
  return (
    render(templates['attribution'] ?? '{{passage}}', ctx).trim(),
    render(templates['title'] ?? '{{title}}', ctx).trim(),
    templates['block'] ?? 'quote',
    QuoteLabels.values.byName(templates['labels'] ?? 'inner'),
  );
}
