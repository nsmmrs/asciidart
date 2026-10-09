/// Walks a document's events with a cursor per scheme and computes its
/// units: where each starts and ends, its address, ID and reftext. Checks
/// labels against the sequence their type expects, and resolves
/// references and notes against the result.
library;

import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/scheme.dart';
import 'package:ptome/src/units/template.dart';

/// A problem the engine found: a label out of sequence, a reference not
/// found.
final class Diagnostic {
  /// A diagnostic at [loc] saying [message]; an [error] rather than a warning.
  new(this.loc, this.message, {this.error = false});

  /// Where it was found, if anywhere in particular.
  final Loc? loc;

  /// What was found.
  final String message;

  /// Whether it is an error (a warning otherwise).
  final bool error;

  @override
  String toString() => '${error ? 'error' : 'warning'}: ${loc ?? ''} $message';
}

/// A unit of a level: a verse, a section, a line, with its address.
final class Unit {
  /// A unit of [level] with [labels], starting at [start] (at its [marker] or
  /// [heading], if it has one).
  new(this.level, this.labels, this.start, {this.marker, this.heading});

  /// The unit's level.
  final Level level;

  /// The labels of this level and every level above it (null where a
  /// level has none: a hidden level never cited, or one not started).
  final List<Label?> labels;

  /// Where the unit starts.
  final Loc start;

  /// Where the unit ends (`null` until the engine finds its end, or at the
  /// document's end).
  Loc? end;

  /// The marker that starts the unit, if any.
  final Marker? marker;

  /// The heading that is the unit, if any.
  final HeadingEvent? heading;

  /// The unit's ID, from its level's `id` template.
  late final String id;

  /// The unit's reftext, from its level's `reftext` template.
  late final String reftext;

  /// Its place among the document's units of its level (1-based).
  late final int ordinal;

  /// Notes in this unit, by stream (in order).
  final Map<String, List<NoteUse>> notes = {};

  /// The unit's own label.
  Label get label => labels[level.depth]!;

  /// Text before the first marker under a parent (unit 0).
  bool get isZero => label.key.isNotEmpty && label.key.first == 0 && level.zero;
}

/// A note where it is used: the unit it belongs to (at its stream's reset
/// level) and its caller there.
final class NoteUse {
  /// The use of [note] in [stream], in [unit] as its [index]th note there, at
  /// the innermost open unit [context].
  new(this.note, this.stream, this.unit, this.index, this.context);

  /// The note.
  final Note note;

  /// The note's stream.
  final NoteStream stream;

  /// The unit the note belongs to (at its stream's reset level), if any.
  final Unit? unit;

  /// Its number in its unit's notes of this stream (0-based), in the
  /// order their callers appear.
  int index;

  /// Where its caller goes: before its lemma, or where it is.
  (int, int) get mark => (note.loc.order, note.lemmaStart ?? note.loc.column);

  /// The innermost open unit where the note is.
  final Unit? context;

  /// The note's caller (`a`, `F12`).
  String get caller => stream.callerAt(index);
}

/// A reference where it is used, resolved.
final class RefUse {
  /// The reference [xref], resolved to [parts].
  new(this.xref, this.parts);

  /// The reference as written.
  final Xref xref;

  /// The reference's pieces in order: separators, and each cited
  /// passage with what it links to.
  final List<RefPart> parts;
}

/// A piece of a resolved reference.
sealed class RefPart {
  const new(this.text);

  /// The piece's text, as written.
  final String text;
}

/// A piece that links nowhere: a separator, or a passage not found.
final class RefText extends RefPart {
  /// A piece of [text] alone.
  const new(super.text);
}

/// A cited passage and what it links to.
final class RefLink extends RefPart {
  /// A passage written [text] that links to [id] (in [file], for another
  /// document).
  const new(super.text, this.id, {this.file});

  /// The ID linked to.
  final String id;

  /// The other document it is in (null: this one).
  final String? file;
}

/// A whole document's units, notes and references.
final class Analysis {
  /// The analysis of [document] under the schemes [config] declares.
  new(this.document, this.config);

  /// The document analyzed.
  final Document document;

  /// What the document's scheme files declare.
  final Config config;

  /// Every unit, in document order.
  final List<Unit> units = [];

  /// Every unit by its key (scheme and labels; see [keyOf]).
  final Map<String, Unit> index = {};

  /// Every unit by its ID.
  final Map<String, Unit> byId = {};

  /// The unit each marker starts.
  final Map<Marker, Unit> unitOfMarker = {};

  /// Every unit a labelled marker starts, outermost first (`@(h)(1)`
  /// starts (h) and (1)).
  final Map<Marker, List<Unit>> startedBy = {};

  /// The unit each heading is.
  final Map<HeadingEvent, Unit> unitOfHeading = {};

  /// Units that start at a block or line without a marker of their own
  /// (auto levels, unit 0), by the event they start at.
  final Map<Event, List<Unit>> implicitUnits = {};

  /// Units a marker starts implicitly inside a block: an auto level's
  /// first (an EU paragraph's first subparagraph, a daf's first segment).
  final Map<Marker, List<Unit>> implicitAtMarker = {};

  /// Each note's use.
  final Map<Note, NoteUse> notes = {};

  /// Each reference, resolved.
  final Map<Xref, RefUse> refs = {};

  /// Each defined term's anchor ID, by term.
  final Map<String, String> terms = {};

  /// The IDs the document writes itself, which units must not take.
  final Set<String> explicitIds = {};

  /// The problems found, in the order found.
  final List<Diagnostic> diagnostics = [];

  /// Named ranges over the address tree (a juz, a day's psalms), by the
  /// unit each starts at.
  final Map<Unit, List<String>> overlays = {};

  /// The units each marker closes (`@^`).
  final Map<Marker, List<Unit>> closedBy = {};

  /// For each block start, the innermost open unit of each scheme at its
  /// first line (after its leading markers).
  final Map<Token, List<Unit>> openAt = {};

  /// The innermost open unit of the primary scheme where each token is.
  final Map<Token, Unit?> contextOf = {};

  /// The key of the unit of scheme [s] with [labels]: the scheme's name and
  /// each cited label.
  String keyOf(Scheme s, List<Label?> labels) {
    final b = StringBuffer(s.name);
    for (final (d, l) in labels.indexed) {
      // Hidden levels are not cited, but a hidden unit has its own key.
      if (s.levels[d].hidden && d != labels.length - 1) continue;
      b.write('|${l?.keyText ?? ''}');
    }
    return b.toString();
  }

  /// Records a warning [m] at [loc].
  void warn(Loc? loc, String m) => diagnostics.add(Diagnostic(loc, m));

  /// Records an error [m] at [loc].
  void error(Loc? loc, String m) =>
      diagnostics.add(Diagnostic(loc, m, error: true));
}

final class _Cursor {
  new(this.scheme)
    : labels = List.filled(scheme.levels.length, null),
      units = List.filled(scheme.levels.length, null),
      pendingZero = List.filled(scheme.levels.length, false),
      headingOpened = List.filled(scheme.levels.length, false);
  final Scheme scheme;

  /// Auto levels a heading's unit sits in, which the next block goes on in.
  final List<bool> headingOpened;
  final List<Label?> labels;
  final List<Unit?> units;
  final List<bool> pendingZero;

  /// The deepest level with an open unit.
  int get deepestOpen {
    for (var d = labels.length - 1; d >= 0; d--) {
      if (units[d] != null) return d;
    }
    return -1;
  }
}

/// A label parse: where it starts and its labels by depth, and a bridge's
/// end.
final class Parsed {
  /// A parse starting at level [start] with [labels] by depth.
  new(this.start, this.labels);

  /// The depth of the first level the parse has a label for.
  final int start;

  /// The labels parsed, by depth.
  final Map<int, Label> labels;

  /// The depth of the last level the parse has a label for.
  int get end => labels.keys.reduce((a, b) => a > b ? a : b);
}

/// Every way [text] reads as a compound label of [s] (`53:1`, `(a)(1)`,
/// `Ps 86:15`, `18-23.1`).
List<Parsed> parseCompound(Scheme s, String text, {bool cite = false}) {
  final left = text;
  final out = <Parsed>[];
  for (var start = 0; start < s.levels.length; start++) {
    if (s.levels[start].hidden) continue;
    var pos = 0;
    final labels = <int, Label>{};
    for (var d = start; d < s.levels.length; d++) {
      final level = s.levels[d];
      if (level.hidden) continue;
      if (labels.isNotEmpty && level.sep.isNotEmpty) {
        if (!left.startsWith(level.sep, pos)) break;
        pos += level.sep.length;
      }
      final m = level.matchAt(left, pos, cite: cite);
      // Self-delimiting labels may skip a level: `551(1)`, a section of
      // paragraphs.
      if (m == null &&
          labels.isNotEmpty &&
          level.sep.isEmpty &&
          d + 1 < s.levels.length &&
          s.levels[d + 1].sep.isEmpty) {
        continue;
      }
      if (m == null) break;
      labels[d] = m.$1;
      pos = m.$2;
      if (pos == left.length) {
        out.add(Parsed(start, Map.of(labels)));
        break;
      }
    }
  }
  return out;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// [text] up to a range's dash (`1:1` of `1:1-2:3`), if it has one.
String? rangeStart(String text) {
  final dash = RegExp('[-–—]').firstMatch(text);
  return dash == null ? null : text.substring(0, dash.start);
}

/// Computes a document's units, notes and references (see [run]).
final class Engine {
  /// An engine for [doc] under [config], which may cite [works].
  new(this.doc, this.config, {this.works = const {}, this.knownIds = const {}});

  /// The document.
  final Document doc;

  /// What its scheme files declare.
  final Config config;

  /// Other documents references may cite, by work name.
  final Map<String, Analysis> works;

  /// IDs the document gives its own nodes (ptome's catalog, for a document
  /// its parser read), which a reference names rather than an address.
  final Set<String> knownIds;

  /// The analysis [run] fills.
  late final Analysis a = Analysis(doc, config);

  /// A cursor per scheme: the labels and units open at each depth.
  late final List<_Cursor> _cursors = [
    for (final s in config.schemes) _Cursor(s),
  ];
  final Set<Marker> _applied = {};
  Set<String> get _apparatus => {
    ...?config.settings['apparatus']?.split(RegExp(r'[\s,]+')),
  };

  /// Walks the document's events and returns its analysis.
  Analysis run() {
    a.explicitIds.addAll(knownIds);
    final idPattern = RegExp(
      r'\[\[([\w:.-]+)(?:,[^\]]*)?\]\]|\[#([\w:-]+)|\bid=([\w:.-]+)',
    );
    for (final f in doc.files) {
      for (final l in f.lines) {
        for (final m in idPattern.allMatches(l)) {
          a.explicitIds.add(m[1] ?? m[2] ?? m[3]!);
        }
      }
    }
    var inApparatus = false;
    BlockStart? block;
    final ranges = <RangeOpen>[];
    for (var i = 0; i < doc.events.length; i++) {
      final e = doc.events[i];
      switch (e) {
        case HeadingEvent():
          _heading(e);
        case BlockStart():
          block = e;
          inApparatus = e.roles.any(_apparatus.contains);
          if (!inApparatus) _beginBlock(e, e.leading, e.kind);
        case BlockEnd():
          block = null;
          inApparatus = false;
        case LineStart(:final kind, :final first):
          if (inApparatus || first) break;
          // A block-breaking marker at the start of a line starts a
          // block of its own; a line-breaking one a line.
          final next = i + 1 < doc.events.length ? doc.events[i + 1] : null;
          final lead =
              next is TokenEvent &&
                  next.token is Marker &&
                  next.token.loc.line == e.loc.line &&
                  _isLeading(next.token as Marker)
              ? next.token as Marker
              : null;
          if (lead != null && _breakOf(lead) == Break.block) {
            _beginBlock(e, [lead], kind);
          }
        case TokenEvent(:final token):
          switch (token) {
            case Marker():
              if (!inApparatus) _marker(token);
            case RangeOpen():
              ranges.add(token);
            case RangeClose():
              final at = ranges.lastIndexWhere(
                (r) =>
                    r.name == token.name &&
                    (token.id == null || r.id == token.id),
              );
              if (at < 0) {
                a.error(token.loc, 'range {${token.name}] closes nothing');
              } else {
                ranges.removeAt(at);
              }
            case Note():
              _note(token);
            case Xref():
              a.contextOf[token] = _innermost();
            case Dfn():
              a.terms[token.term.toLowerCase()] =
                  'term-${applyFilter('slug', token.term)}';
          }
        case IncludeSelf() || IncludeUnit():
          break;
      }
      if (block != null && e is TokenEvent) a.contextOf[e.token] = _innermost();
    }
    for (final r in ranges) {
      a.error(r.loc, 'range [${r.name}} is never closed');
    }
    // Callers go in the order they appear in the text (a lemma's caller
    // is at the lemma's start).
    for (final u in a.units) {
      for (final uses in u.notes.values) {
        uses.sort(
          (x, y) => x.mark.$1 != y.mark.$1
              ? x.mark.$1.compareTo(y.mark.$1)
              : x.mark.$2.compareTo(y.mark.$2),
        );
        for (final (i, use) in uses.indexed) {
          use.index = i;
        }
      }
    }
    _resolveRefs();
    _overlays();
    return a;
  }

  bool _isLeading(Marker m) =>
      m.loc.column == 0 ||
      doc.files.isEmpty ||
      m.loc.file.lines[m.loc.line]
          .substring(0, m.loc.column)
          .replaceAll(RegExp(r'\[[\w-]+[^}]*\}'), '')
          .trim()
          .isEmpty;

  _Cursor _cursorFor(Marker m) {
    if (m.attrs.positional.isNotEmpty) {
      for (final c in _cursors) {
        if (c.scheme.name == m.attrs.positional.first) return c;
      }
    }
    return _cursors.first;
  }

  Break? _breakOf(Marker m) {
    if (_cursors.isEmpty) return null;
    final c = _cursorFor(m);
    final level = switch (m.op) {
      MarkerOp.step => c.scheme.defaultLevel?.let(
        (l) => l.depth >= m.up ? c.scheme.levels[l.depth - m.up] : null,
      ),
      MarkerOp.close => null,
      MarkerOp.label => _choose(
        c,
        m,
        peek: true,
      )?.let((pp) => c.scheme.levels[pp.end]),
    };
    if (m.op == MarkerOp.close) {
      // Closing in a block-structured scheme starts a block of the parent.
      return c.scheme.levels.any((l) => l.breakMode == Break.block)
          ? Break.block
          : null;
    }
    return level?.breakMode;
  }

  Unit? _innermost() {
    if (_cursors.isEmpty) return null;
    final c = _cursors.first;
    final d = c.deepestOpen;
    return d < 0 ? null : c.units[d];
  }

  // Units ---------------------------------------------------------------

  Unit _start(
    _Cursor c,
    int depth,
    Label label,
    Loc loc, {
    Marker? marker,
    HeadingEvent? heading,
    Event? at,
  }) {
    final level = c.scheme.levels[depth];
    // Everything deeper ends; this level's previous unit ends.
    for (var d = c.labels.length - 1; d >= depth; d--) {
      c.units[d]?.end ??= loc;
      if (d > depth) {
        c.units[d] = null;
        c.labels[d] = null;
        c.pendingZero[d] = false;
      }
    }
    c.pendingZero[depth] = false;
    c.labels[depth] = label;
    final unit = Unit(
      level,
      [...c.labels.sublist(0, depth), label],
      loc,
      marker: marker,
      heading: heading,
    );
    c.units[depth] = unit;
    _register(unit);
    if (marker != null) a.unitOfMarker[marker] = unit;
    if (heading != null) a.unitOfHeading[heading] = unit;
    if (at != null) (a.implicitUnits[at] ??= []).add(unit);
    // A level under it: auto levels start again (at once when inside a
    // block, at the next block otherwise); unit 0 waits for text.
    for (var d = depth + 1; d < c.labels.length; d++) {
      final l = c.scheme.levels[d];
      // (Only levels that step with blocks: list items start their own.)
      if ((l.auto == Auto.block || l.auto == Auto.paragraph) &&
          d == depth + 1 &&
          marker != null &&
          !marker.inHeading) {
        final f = l.first;
        if (f != null) {
          final child = _start(c, d, f, loc, at: at);
          if (at == null) (a.implicitAtMarker[marker] ??= []).add(child);
        }
        break;
      }
      if (l.zero && d == depth + 1) c.pendingZero[d] = true;
      if (l.breakMode != Break.heading && !l.hidden) break;
    }
    return unit;
  }

  final Map<Level, int> _ordinals = {};

  void _register(Unit u) {
    final s = u.level.scheme;
    u.ordinal = _ordinals[u.level] = (_ordinals[u.level] ?? 0) + 1;
    final ctx = _context(u);
    u.id = render(u.level.templates['id'] ?? _defaultId(u), ctx);
    u.reftext = render(
      u.level.templates['reftext'] ?? s.citeTemplate ?? u.label.text,
      ctx,
    );
    a.units.add(u);
    // Versions of one provision (by extent, by date) share its address.
    final version = u.marker?.attrs.named['version'];
    final key = a.keyOf(s, u.labels) + (version == null ? '' : '@$version');
    if (a.index.containsKey(key) && !u.isZero) {
      a.warn(
        u.start,
        '${u.level.name} ${u.label} again (first at ${a.index[key]!.start})',
      );
    }
    a.index[key] = u;
    if (u.label.end case final end?) {
      // Every address a bridge covers.
      var l = Label(u.label.text, u.label.key);
      while (l.compareTo(end) < 0) {
        final n = u.level.next(l);
        if (n == null) break;
        l = n;
        a.index[a.keyOf(s, [...u.labels.sublist(0, u.level.depth), l])] = u;
      }
    }
    if (a.byId.containsKey(u.id)) {
      a.warn(u.start, 'ID ${u.id} again');
    }
    a.byId[u.id] = u;
  }

  String _defaultId(Unit u) {
    final parts = <String>[u.level.scheme.name];
    for (final (d, l) in u.labels.indexed) {
      if (l == null || u.level.scheme.levels[d].hidden) continue;
      parts.add(applyFilter('slug', u.level.scheme.levels[d].bare(l)));
    }
    return parts.join('-');
  }

  // Events -------------------------------------------------------------

  void _heading(HeadingEvent e) {
    var consumed = false;
    for (final c in _cursors) {
      for (final (d, level) in c.scheme.levels.indexed) {
        if (level.heading != e.depth) continue;
        final m = e.marker;
        consumed = consumed || m != null;
        if (m != null && m.op == MarkerOp.label) {
          final parsed = parseCompound(
            c.scheme,
            m.label,
          ).where((pp) => pp.end == d).firstOrNull;
          if (parsed == null) {
            a.error(m.loc, '"${m.label}" is not a ${level.name} label');
            continue;
          }
          _check(c, d, parsed.labels[d]!, m.loc);
          for (final MapEntry(key: dd, value: l) in parsed.labels.entries) {
            if (c.labels[dd]?.sameAs(l) ?? false) continue;
            _start(
              c,
              dd,
              l,
              m.loc,
              marker: dd == d ? m : null,
              heading: dd == d ? e : null,
            );
          }
        } else if (!e.discrete && m?.op == MarkerOp.step) {
          final label = _stepLabel(c, d);
          if (label == null) {
            a.error(e.loc, 'no ${level.name} label to step to');
            continue;
          }
          _start(c, d, label, e.loc, heading: e, marker: m);
        }
      }
    }
    // A heading level bound to no depth takes a heading whose label is
    // its (an EU act's articles, under chapters with sections or without).
    final m = e.marker;
    if (!consumed && m != null && m.op == MarkerOp.label) {
      for (final c in _cursors) {
        final parsed = parseCompound(c.scheme, m.label).where((pp) {
          final l = c.scheme.levels[pp.end];
          return l.breakMode == Break.heading && l.heading == null;
        }).firstOrNull;
        if (parsed == null) continue;
        _checkCompound(c, parsed, m.loc);
        for (final MapEntry(key: d, value: l) in parsed.labels.entries) {
          _start(
            c,
            d,
            l,
            m.loc,
            marker: d == parsed.end ? m : null,
            heading: d == parsed.end ? e : null,
          );
        }
        consumed = true;
      }
    }
    // A marker of a level no heading is bound to: the heading's text is
    // that unit's (a sutta's headings are segments).
    if (!consumed && m != null) _marker(m, heading: e);
  }

  Label? _stepLabel(_Cursor c, int d) {
    final level = c.scheme.levels[d];
    final cur = c.labels[d];
    return cur == null ? level.first : level.next(cur);
  }

  /// A block (or a block-breaking marker's line) begins: unit 0 waits no
  /// longer, auto levels step.
  void _beginBlock(Event at, List<Marker> leading, BlockKind kind) {
    for (final m in leading) {
      if (m.op == MarkerOp.close) _close(m);
    }
    for (final c in _cursors) {
      final touched = <int>{};
      var deeperBlock = -1;
      for (final m in leading) {
        if (_cursorFor(m) != c || m.op == MarkerOp.close) continue;
        final depth = switch (m.op) {
          MarkerOp.label => _choose(c, m, peek: true)?.start,
          _ => c.scheme.defaultLevel?.let(
            (l) => l.depth >= m.up ? l.depth - m.up : null,
          ),
        };
        if (depth == null) continue;
        touched.add(depth);
        final pp = m.op == MarkerOp.label ? _choose(c, m, peek: true) : null;
        final endLevel = pp == null
            ? c.scheme.levels[depth]
            : c.scheme.levels[pp.end];
        if (endLevel.breakMode == Break.block) {
          deeperBlock = deeperBlock < endLevel.depth
              ? endLevel.depth
              : deeperBlock;
        }
      }
      for (final (d, level) in c.scheme.levels.indexed) {
        if (c.pendingZero[d] && !touched.any((t) => t <= d)) {
          c.pendingZero[d] = false;
          _start(
            c,
            d,
            level.wrapLabel(const Label('0', [0, 0])),
            at.loc,
            at: at,
          );
        }
        final applies = switch (level.auto) {
          Auto.never => false,
          Auto.block => true,
          Auto.paragraph => kind == BlockKind.paragraph,
          Auto.item => kind == BlockKind.item,
        };
        if (!applies) continue;
        final opened = c.headingOpened[d];
        c.headingOpened[d] = false;
        if (touched.any((t) => t <= d)) continue;
        if (deeperBlock > d) continue;
        if (opened) continue;
        // Something above must be open (or the level is the outermost).
        if (d > 0 && !c.labels.take(d).any((l) => l != null)) continue;
        final label = _stepLabel(c, d);
        if (label == null) {
          a.warn(at.loc, 'no ${level.name} after ${c.labels[d]}');
          continue;
        }
        _start(c, d, label, at.loc, at: at);
      }
    }
  }

  void _close(Marker m) {
    if (!_applied.add(m)) return;
    final c = _cursorFor(m);
    var target = -1; // close every level deeper than this
    // The innermost open unit of a level that has markers.
    for (var d = c.labels.length - 1; d >= 0; d--) {
      final l = c.scheme.levels[d];
      if (c.units[d] != null &&
          l.breakMode != Break.heading &&
          !l.hidden &&
          l.auto == Auto.never) {
        target = d - 1;
        break;
      }
    }
    final closed = <Unit>[];
    for (var d = c.labels.length - 1; d > target; d--) {
      final u = c.units[d];
      if (u == null) continue;
      if (c.scheme.levels[d].breakMode == Break.heading) break;
      u.end ??= m.loc;
      closed.add(u);
      c.units[d] = null;
    }
    a.closedBy[m] = closed;
  }

  /// The parse of a labelled marker that fits where it is.
  Parsed? _choose(_Cursor c, Marker m, {bool peek = false}) {
    final top = c.scheme.levels.indexWhere(
      (l) => l.breakMode != Break.heading && !l.hidden,
    );
    final candidates = parseCompound(c.scheme, m.label).where((pp) {
      // Dotted labels name levels from the top (`1.30.0`).
      if (c.scheme.absolute && pp.start != top) return false;
      final end = c.scheme.levels[pp.end];
      // Inline markers set marker levels; heading levels only as part of
      // a compound (`53:1`).
      if (end.breakMode == Break.heading) return false;
      return true;
    }).toList();
    if (candidates.isEmpty) {
      if (!peek) a.error(m.loc, '"${m.label}" is not a label here');
      return null;
    }
    int score(Parsed pp) {
      var s = 0;
      for (final MapEntry(key: d, value: l) in pp.labels.entries) {
        final cur = c.labels[d];
        final level = c.scheme.levels[d];
        final expected = cur == null ? level.first : level.next(cur);
        if (expected != null &&
            (expected.sameAs(l.whole) ||
                l.part != null && expected.sameAs(l))) {
          s += 2;
        }
        if (cur != null && cur.sameAs(l.whole)) s += 2;
        if (cur != null &&
            l.key.first == cur.key.first &&
            l.key.length > 1 &&
            l.key[1] > 0) {
          s += 1; // an insertion
        }
      }
      if (c.scheme.levels[pp.end].isDefault &&
          c.scheme.levels[pp.end].stepping) {
        s += 1;
      }
      // A list starting under the innermost open provision is likelier
      // than a sibling of one above it: after (4)(A)—, (i) is a clause.
      final deepest = c.deepestOpen;
      final firstOf = c.scheme.levels[pp.start].first;
      if (pp.start == deepest + 1 &&
          firstOf != null &&
          pp.labels[pp.start]!.sameAs(firstOf)) {
        s += 3;
      }
      // A level may be skipped (a section of paragraphs), but a label
      // under one that is there fits better.
      final parent = pp.start - 1;
      if (parent < 0 ||
          c.labels[parent] != null ||
          c.scheme.levels[parent].breakMode == Break.heading) {
        s += 1;
      }
      return s;
    }

    // Equally likely: go on in the innermost list (a deeper start).
    candidates.sort(
      (x, y) => score(y) != score(x)
          ? score(y).compareTo(score(x))
          : y.start.compareTo(x.start),
    );
    return candidates.first;
  }

  void _marker(Marker m, {HeadingEvent? heading}) {
    if (_cursors.isEmpty) return;
    if (m.inHeading && heading == null) return;
    final c = _cursorFor(m);

    switch (m.op) {
      case MarkerOp.close:
        _close(m);
      case MarkerOp.step:
        final base = c.scheme.defaultLevel;
        final level = base == null || base.depth < m.up
            ? null
            : c.scheme.levels[base.depth - m.up];
        if (level == null || !level.stepping) {
          a.error(
            m.loc,
            'a bare @ needs a label here '
            '(${level?.name ?? c.scheme.name} does not step)',
          );
          return;
        }
        final label = _stepLabel(c, level.depth);
        if (label == null) {
          a.error(
            m.loc,
            'nothing comes after ${level.name} ${c.labels[level.depth]}',
          );
          return;
        }
        // `@@` starts the level above and its first unit at the default
        // level: the next section's first segment.
        _start(
          c,
          level.depth,
          label,
          m.loc,
          marker: m.up == 0 ? m : null,
          heading: heading,
        );
        for (var d = level.depth + 1; d <= base!.depth; d++) {
          final l = c.scheme.levels[d];
          // In a heading, the default level starts at 0 if it can: a
          // heading is its unit's unit 0, as a Psalm's title is verse 0.
          final f = heading != null && d == base.depth && l.zero
              ? l.wrapLabel(const Label('0', [0, 0]))
              : l.first;
          if (f != null && c.units[d] == null) {
            _start(
              c,
              d,
              f,
              m.loc,
              marker: d == base.depth ? m : null,
              heading: d == base.depth ? heading : null,
            );
          }
        }
      case MarkerOp.label:
        final pp = _choose(c, m);
        if (pp == null) return;
        _checkCompound(
          c,
          pp,
          m.loc,
          version: m.attrs.named.containsKey('version'),
        );
        final before = [...c.units];
        for (final MapEntry(key: d, value: l) in pp.labels.entries) {
          final isEnd = d == pp.end;
          if (!isEnd &&
              c.labels[d] != null &&
              c.labels[d]!.sameAs(l) &&
              c.units[d] != null) {
            continue;
          }
          final u = _start(
            c,
            d,
            l,
            m.loc,
            marker: isEnd ? m : null,
            heading: isEnd ? heading : null,
          );
          (a.startedBy[m] ??= []).add(u);
        }
        // A heading that opens a unit of an auto level with a deeper one
        // (a sutta's `6.0` opens section 6): the next block goes on in it.
        if (heading != null) {
          for (final l in c.scheme.levels) {
            if (l.auto != Auto.never &&
                l.depth < pp.end &&
                !identical(before[l.depth], c.units[l.depth])) {
              c.headingOpened[l.depth] = true;
            }
          }
        }
    }
  }

  /// Checks each level a compound label sets, outermost first: a level
  /// under one that changes starts again.
  void _checkCompound(_Cursor c, Parsed pp, Loc loc, {bool version = false}) {
    var changed = false;
    for (final d in pp.labels.keys.toList()..sort()) {
      final l = pp.labels[d]!;
      final cur = changed ? null : c.labels[d];
      if (!changed &&
          cur != null &&
          cur.sameAs(l) &&
          c.units[d] != null &&
          d != pp.end) {
        continue;
      }
      _checkLabel(c, d, cur, l, loc, version: version && d == pp.end);
      changed = true;
    }
  }

  void _check(_Cursor c, int depth, Label label, Loc loc) =>
      _checkLabel(c, depth, c.labels[depth], label, loc);

  /// Warns when [label] is not what comes after [cur] at [depth] (unless
  /// the versification leaves the skipped labels out).
  void _checkLabel(
    _Cursor c,
    int depth,
    Label? cur,
    Label label,
    Loc loc, {
    bool version = false,
  }) {
    if (version && cur != null && cur.sameAs(label)) return;
    final level = c.scheme.levels[depth];
    // An excerpt starts and skips where it likes above its innermost level.
    if (doc.attributes.containsKey('excerpt') &&
        (level.breakMode == Break.heading || cur == null)) {
      return;
    }
    if (level.gaps && (cur == null || label.compareTo(cur) > 0)) return;
    if (cur == null) {
      final f = level.first;
      if (f != null &&
          !f.sameAs(label.whole) &&
          level.type is! BekkerType &&
          !level.zero) {
        a.warn(loc, '${level.name} starts at $label, not ${f.text}');
      }
      return;
    }
    if (label.part != null && cur.sameAs(label.whole)) return; // 14b after 14a
    if (cur.part != null && cur.whole.sameAs(label.whole)) return;
    final next = level.next(cur.whole);
    if (next == null ||
        level.successors(cur.whole).any((n) => n.sameAs(label.whole))) {
      return;
    }
    if (label.key.length > 1 &&
        label.key[0] == cur.key[0] &&
        label.key[1] > (cur.key.length > 1 ? cur.key[1] : 0)) {
      return; // insertion
    }
    if (level.type is IntType &&
        label.key.length > 1 &&
        label.key[1] > 0 &&
        label.key[0] == cur.key[0]) {
      return;
    }
    // Left out by the versification?
    final v = config.versification;
    if (v != null && level.type is IntType && label.key[0] > cur.key[0]) {
      final book = c.labels.first?.text;
      final chapter = depth >= 1 ? c.labels[depth - 1]?.text : null;
      final skipped = [
        for (var n = cur.key[0] + 1; n < label.key[0]; n++) '$book $chapter:$n',
      ];
      if (skipped.isNotEmpty && skipped.every(v.excluded.contains)) return;
    }
    a.warn(loc, '${level.name} $label after $cur (expected ${next.text})');
  }

  void _note(Note n) {
    final stream =
        config.streams[n.stream] ??
        (n.stream == 'footnote' ? NoteStream(name: 'footnote') : null);
    if (stream == null) {
      a.error(n.loc, 'no note stream "${n.stream}"');
      return;
    }
    Unit? owner;
    if (stream.reset != null && _cursors.isNotEmpty) {
      for (final c in _cursors) {
        final l = c.scheme.level(stream.reset!);
        if (l != null) owner = c.units[l.depth];
      }
    }
    final list = owner == null
        ? (_unowned[stream.name] ??= [])
        : (owner.notes[stream.name] ??= []);
    final use = NoteUse(n, stream, owner, list.length, _innermost());
    list.add(use);
    a.notes[n] = use;
    a.contextOf[n] = _innermost();
    for (final x in n.children) {
      if (x is Xref) a.contextOf[x] = _innermost();
    }
  }

  final Map<String, List<NoteUse>> _unowned = {};

  /// The `:overlays:` files: description lists of names and the ranges
  /// they name (`Juz 2:: 2:142–2:252`).
  void _overlays() {
    for (final name
        in (doc.attributes['overlays'] ?? '')
            .split(RegExp(r'[\s,]+'))
            .where((n) => n.isNotEmpty)) {
      final file = p.join(p.dirname(doc.root.path), name);
      if (!p.isFile(file)) {
        a.error(null, 'overlay file $name not found');
        continue;
      }
      for (final (i, line) in p.readLines(file).indexed) {
        final m = RegExp(r'^(.+?)::\s+(.+)$').firstMatch(line);
        if (m == null) continue;
        final parts = resolveRef(m[2]!.trim(), null) ?? const [];
        final link = parts.whereType<RefLink>().firstOrNull;
        final unit = link == null ? null : a.byId[link.id];
        if (unit == null) {
          a.warn(null, '$name:${i + 1}: "${m[2]}" not found');
          continue;
        }
        (a.overlays[unit] ??= []).add(m[1]!.trim());
      }
    }
  }

  // References -----------------------------------------------------------

  void _resolveRefs() {
    final xrefs = <Xref>[
      for (final e in doc.events)
        if (e is TokenEvent)
          ...switch (e.token) {
            final Xref x => [x],
            final Note n => n.children.whereType<Xref>(),
            _ => const <Xref>[],
          },
    ];
    for (final x in xrefs) {
      final parts = resolveRef(x.content, a.contextOf[x]);
      if (parts == null) continue; // an ordinary xref
      a.refs[x] = RefUse(x, parts);
      for (final part in parts) {
        if (part is RefText &&
            part.text.trim().isNotEmpty &&
            !RegExp(r'^[\s;,]+$').hasMatch(part.text)) {
          a.warn(x.loc, 'reference "${part.text.trim()}" not found');
        }
      }
    }
  }

  /// The pieces of reference [content] seen from [context]; null when it
  /// is an ordinary xref to an ID.
  List<RefPart>? resolveRef(String content, Unit? context) {
    final firstComma = content.indexOf(',');
    final target = firstComma < 0 ? content : content.substring(0, firstComma);
    if (a.explicitIds.contains(target.trim())) return null;
    if (content.startsWith('"') && content.endsWith('"')) {
      final term = content.substring(1, content.length - 1);
      final id = a.terms[term.toLowerCase()];
      return [if (id == null) RefText(term) else RefLink(term, id)];
    }
    // `target,text`: one address shown as other text (`<<(c)(5),paragraph
    // (5)>>`, as a statute cites inner to outer).
    final comma = content.indexOf(',');
    if (comma > 0) {
      final whole = _resolveItems(content, context);
      if (whole.any(
        (part) => part is RefText && !RegExp(r'^[\s;,]*$').hasMatch(part.text),
      )) {
        final first = _resolveItems(content.substring(0, comma), context);
        if (first.length == 1 && first.single is RefLink) {
          final link = first.single as RefLink;
          return [
            RefLink(
              content.substring(comma + 1).trim(),
              link.id,
              file: link.file,
            ),
          ];
        }
      }
      return whole;
    }
    return _resolveItems(content, context);
  }

  List<RefPart> _resolveItems(String content, Unit? context) {
    final out = <RefPart>[];
    // Items, each with the separator before it.
    final items = <(String, String)>[];
    var sep = '';
    var startAt = 0;
    for (final m in RegExp(r'\s*[;,]\s*').allMatches(content)) {
      items.add((sep, content.substring(startAt, m.start)));
      sep = m[0]!;
      startAt = m.end;
    }
    items.add((sep, content.substring(startAt)));
    List<Label?>? previous;
    Scheme? previousScheme;
    Analysis? previousWork;
    for (final (separator, raw) in items) {
      if (separator.isNotEmpty) out.add(RefText(separator));
      final text = raw.trim();
      // Another work?
      var work = previousWork;
      var body = text;
      var workPrefix = '';
      for (final MapEntry(key: name, value: other) in works.entries) {
        if (text.startsWith('$name ')) {
          work = other;
          workPrefix = '$name ';
          body = text.substring(name.length + 1);
        }
      }
      Unit? found;
      List<Label?>? labels;
      Scheme? scheme;
      // This document first; then, unnamed, the works it cites (a
      // catechism's proof texts in the Bible).
      final targets = work != null ? [work] : [a, ...works.values.toSet()];
      for (final target in targets) {
        for (final s in target.config.schemes) {
          // A range links to where it starts (`1:1-2:3`, `Psalms 1—41`).
          var parsed = parseCompound(s, body, cite: true);
          final start = rangeStart(body);
          if (parsed.isEmpty && start != null) {
            parsed = parseCompound(s, start, cite: true);
          }
          // After a comma, prefer the level the last item ended at; after a
          // semicolon, the outermost; for the first, any that resolves.
          final ordered = [...parsed]
            ..sort((x, y) {
              if (separator.contains(',') && previous != null) {
                final last = previous.lastIndexWhere((l) => l != null);
                return (y.start == last ? 1 : 0).compareTo(
                  x.start == last ? 1 : 0,
                );
              }
              return x.start.compareTo(y.start);
            });
          for (final pp in ordered) {
            final ctx = s == previousScheme && previous != null
                ? previous
                : (work == null && context != null && context.level.scheme == s
                      ? context.labels
                      : null);
            final full = List<Label?>.filled(s.levels.length, null);
            for (var d = 0; d < pp.start; d++) {
              full[d] = ctx != null && d < ctx.length ? ctx[d] : null;
            }
            for (final MapEntry(key: d, value: l) in pp.labels.entries) {
              full[d] = l;
            }
            final depth = pp.end;
            final key = target.keyOf(s, full.sublist(0, depth + 1));
            final u =
                target.index[key] ?? _searchHidden(target, s, full, depth);
            if (u != null) {
              found = u;
              labels = full.sublist(0, depth + 1);
              scheme = s;
              if (target != a) work = target;
              break;
            }
          }
          if (found != null) break;
        }
        if (found != null) break;
      }
      if (found == null) {
        out.add(RefText(raw));
        continue;
      }
      previous = labels;
      previousScheme = scheme;
      previousWork = work;
      final lead = raw.substring(0, raw.indexOf(text));
      if (lead.isNotEmpty) out.add(RefText(lead));
      out.add(
        RefLink(
          workPrefix + body,
          found.id,
          file: work == null
              ? null
              : p.relative(
                  work.document.root.path,
                  from: p.dirname(a.document.root.path),
                ),
        ),
      );
    }
    return out;
  }

  /// A unit whose address has hidden levels the citation leaves out.
  Unit? _searchHidden(Analysis target, Scheme s, List<Label?> full, int depth) {
    if (!s.levels.take(depth + 1).any((l) => l.hidden)) return null;
    for (final u in target.units) {
      if (u.level.scheme != s || u.level.depth != depth) continue;
      var ok = true;
      for (var d = 0; d <= depth; d++) {
        if (s.levels[d].hidden) continue;
        final want = full[d];
        final have = u.labels[d];
        if (want == null || have == null || !want.sameAs(have)) {
          ok = false;
          break;
        }
      }
      if (ok) return u;
    }
    return null;
  }

  Map<String, TValue> _context(Unit u) =>
      unitContext(u, config, doc.attributes);
}

/// What templates see for [u]: each level's label by name (a canon book
/// as a record), `label`, `n`, `part`, `first`, `id` once known.
Map<String, TValue> unitContext(
  Unit u,
  Config config, [
  Map<String, String> attributes = const {},
]) {
  final s = u.level.scheme;
  final ctx = <String, TValue>{
    'doc': TRecord({
      for (final MapEntry(:key, :value) in attributes.entries)
        key: TText(value),
    }),
  };
  for (final (d, l) in u.labels.indexed) {
    if (l == null) continue;
    final level = s.levels[d];
    if (level.type is CodeType) {
      final book = config.canon!.byCode[l.text];
      if (book != null) ctx[level.name] = book.value;
    } else {
      ctx[level.name] = TText(level.bare(l));
    }
  }
  final l = u.label;
  ctx['label'] = TText(l.text);
  ctx['n'] = TText(u.level.bare(l));
  ctx['cited'] = TText(l.cited ?? l.text);
  if (l.part != null) ctx['part'] = TText(l.part!);
  ctx['first'] = TFlag(value: u.level.first?.sameAs(l) ?? false);
  if (u.marker?.attrs.named['version'] case final v?) ctx['version'] = TText(v);
  // A marker's named attributes (`@[part=F]`), and the unit's ordinal
  // among its level's units in the document (a through-line number).
  ctx['attr'] = TRecord({
    for (final MapEntry(:key, :value)
        in u.marker?.attrs.named.entries ?? const <MapEntry<String, String>>[])
      key: TText(value),
  });
  ctx['ordinal'] = TText('${u.ordinal}');
  ctx['zero'] = TFlag(value: u.isZero);
  return ctx;
}
