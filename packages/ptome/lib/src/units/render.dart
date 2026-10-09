/// How units print, natively (ADR-0020): once the engine has analyzed a
/// document, the renderer goes through its events in document order and
/// prepares, for each text the parser read, what its substitutions start
/// from: the text with its units syntax replaced. Markers, notes,
/// references and definitions become atoms (placeholders a table of typed
/// [UnitAtom]s resolves once the substitutions are done, so nothing a unit
/// prints is read as markup); the text inside ranges and found by term
/// rules is wrapped, segment by segment, in range marks the substitutions
/// turn into role spans. Headings and blocks that are units get their IDs,
/// reftexts, roles and options on the nodes themselves.
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/document.dart' as ptome;
import 'package:ptome/src/inline.dart';
import 'package:ptome/src/list.dart';
import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/presentation.dart';
import 'package:ptome/src/units/scheme.dart';
import 'package:ptome/src/units/template.dart';

/// Starts an atom placeholder: ``, the atom's index, [markEnd].
const atomMark = '\u{E110}';

/// Ends an atom placeholder or a range mark.
const markEnd = '\u{E111}';

/// Opens a range: ``, the index of its roles, [markEnd].
const rangeOpenMark = '\u{E112}';

/// Closes a range: ``, the index of its roles, [markEnd].
const rangeCloseMark = '\u{E113}';

/// A placeholder or range mark.
final RegExp atomRx = RegExp('$atomMark(\\d+)$markEnd');

/// A range: its roles' index and the text it wraps.
final RegExp rangeRx = RegExp(
  '$rangeOpenMark(\\d+)$markEnd([\\s\\S]*?)$rangeCloseMark\\1$markEnd',
);

/// Something a unit prints, converted once the substitutions are done.
sealed class UnitAtom {
  /// An atom.
  const new();
}

/// An anchor: a unit's start, a defined term.
final class AnchorAtom extends UnitAtom {
  /// An anchor with [id] (and [reftext]).
  const new(this.id, [this.reftext]);

  /// The anchor's ID.
  final String id;

  /// Its reftext, if any.
  final String? reftext;
}

/// What a printed part is, for what a quotation keeps.
enum PartKind {
  /// Text: an end text, a separator.
  text,

  /// A unit's label (and what goes with it).
  label,

  /// A note's caller.
  caller,

  /// An overlay's name.
  overlay,

  /// What goes with a note entry (the text after it).
  entry,
}

/// Where a unit starts in the text (prints nothing): where a passage that
/// starts with it is cut.
final class UnitStartAtom extends UnitAtom {
  /// The start of [unit].
  const new(this.unit);

  /// The unit.
  final Unit unit;
}

/// A printed part: a label, a caller, an overlay's name.
final class PartAtom extends UnitAtom {
  /// [text] set in [style] and [role]; [markup]: text the author wrote
  /// (a term, a lemma), which the inline substitutions apply to; otherwise
  /// text a template printed, as is.
  const new(
    this.text, {
    this.style = PartStyle.plain,
    this.role,
    this.markup = false,
    this.kind = PartKind.text,
    this.unit,
  });

  /// The text printed.
  final String text;

  /// How it is set.
  final PartStyle style;

  /// The role it is set in, if any.
  final String? role;

  /// Whether the author wrote it (the inline substitutions apply).
  final bool markup;

  /// What it is.
  final PartKind kind;

  /// The unit whose label it is, for a label.
  final Unit? unit;
}

/// Atoms in a span with a role (an entry), or none.
final class GroupAtom extends UnitAtom {
  /// [atoms], in a span with [role] if it has one.
  const new(this.atoms, {this.role});

  /// What the group prints.
  final List<UnitAtom> atoms;

  /// The role of its span, if any.
  final String? role;
}

/// Prepared text the substitutions apply to (a note's body): a text with
/// its own atoms.
final class TextAtom extends UnitAtom {
  /// Prepared [text].
  const new(this.text);

  /// The prepared text.
  final String text;
}

/// A line break (an end text on a line of its own).
final class BreakAtom extends UnitAtom {
  /// A line break.
  const new();
}

/// A note shown as a footnote: [content] (prepared text), or, for a note
/// with an [id] written before, a reference to it.
final class FootnoteAtom extends UnitAtom {
  /// A footnote of [content], or a reference to the note [id].
  const new(this.content, {this.id});

  /// The note's prepared content, if it is shown here.
  final String? content;

  /// The note's ID, if it has one.
  final String? id;
}

/// A reference: text and links.
final class ReferenceAtom extends UnitAtom {
  /// A reference printing [parts].
  const new(this.parts);

  /// Its text and links.
  final List<RefPart> parts;
}

/// What the renderer prepared for one node.
final class Prepared {
  /// [text] in place of [source].
  const new(this.source, this.text);

  /// The text as the parser read it (what the substitutions are given).
  final String source;

  /// What they start from instead.
  final String text;
}

/// The document's prepared texts, atoms and range roles.
final class Rendering {
  /// The [prepared] texts, [atoms] and range [roles] of a document.
  new(this.prepared, this.atoms, this.roles);

  /// Each node's prepared text.
  final Expando<Prepared> prepared;

  /// The atoms, by index.
  final List<UnitAtom> atoms;

  /// The roles of each range mark, by index.
  final List<String> roles;

  /// Each unit's start: the node it starts in and the index of its
  /// [UnitStartAtom] there (`-1` for a heading that is the unit).
  final Map<Unit, (AbstractNode, int)> starts = Map.identity();

  /// The index of the range mark for [role], added if new.
  int role(String role) {
    final at = roles.indexOf(role);
    if (at >= 0) return at;
    roles.add(role);
    return roles.length - 1;
  }

  /// Adds [atom], returning its placeholder.
  String place(UnitAtom atom) {
    atoms.add(atom);
    return '$atomMark${atoms.length - 1}$markEnd';
  }
}

sealed class _Piece {
  const new();
}

final class _Text extends _Piece {
  const new(this.text);
  final String text;
}

final class _Atom extends _Piece {
  const new(this.atom, {this.after});
  final UnitAtom atom;

  /// The range a note annotates: hidden with it.
  final RangeClose? after;
}

final class _Open extends _Piece {
  const new(this.range);
  final RangeOpen range;
}

final class _Close extends _Piece {
  const new(this.range);
  final RangeClose range;
}

/// Prepares [document]'s texts for the analysis [a]: [textOf]
/// gives the text each node's units were found in.
Rendering renderUnits(
  ptome.Document document,
  Analysis a,
  Map<AbstractNode, SourceFile> textOf,
) => _Renderer(document, a, textOf).run();

final class _Renderer {
  new(this.document, this.a, this.textOf)
    : asOf = document.attributes['units-as-of'],
      nodeOf = {
        for (final MapEntry(:key, :value) in textOf.entries) value: key,
      };

  final ptome.Document document;
  final Analysis a;
  final Map<AbstractNode, SourceFile> textOf;
  final Map<SourceFile, AbstractNode> nodeOf;
  final String? asOf;
  Config get config => a.config;

  final List<UnitAtom> atoms = [];
  final List<String> roles = [];
  final Map<String, int> _roleIndex = {};

  /// Prepared lines, by file and line.
  final Map<SourceFile, List<String>> _lines = {};

  /// Prepared heading titles, by file.
  final Map<SourceFile, String> _titles = {};

  /// Atoms that go in a block of their own after a node (a catechism's
  /// proofs).
  final Map<AbstractNode, List<UnitAtom>> _blocksAfter = Map.identity();

  /// Open ranges, outermost first.
  final List<RangeOpen> _open = [];

  /// Units that print something at their end, waiting for it.
  final List<Unit> _ending = [];

  /// What units starting at a line print at its start, by file and line.
  final Map<(SourceFile, int), List<UnitAtom>> _prefixes = {};

  /// Note IDs already shown, and each one's text.
  final Map<String, String> _noteTexts = {};

  /// Terms whose definition has its anchor.
  final Set<String> _dfnSeen = {};

  /// Ranges the as-of date hid, so their notes go too.
  final Set<RangeClose> _hiddenCloses = {};

  String _place(UnitAtom atom) {
    atoms.add(atom);
    if (atom is UnitStartAtom && _node != null) {
      _starts[atom.unit] = (_node!, atoms.length - 1);
    }
    return '$atomMark${atoms.length - 1}$markEnd';
  }

  final Map<Unit, (AbstractNode, int)> _starts = Map.identity();

  int _role(String role) => _roleIndex.putIfAbsent(role, () {
    roles.add(role);
    return roles.length - 1;
  });

  Rendering run() {
    final events = a.document.events;
    final byLine = <SourceFile, Map<int, List<Token>>>{};
    for (final e in events) {
      if (e is TokenEvent) {
        ((byLine[e.loc.file] ??= {})[e.loc.line] ??= []).add(e.token);
      }
    }
    for (final f in a.document.files) {
      _lines[f] = [...f.lines];
    }
    BlockStart? block;
    (SourceFile, int)? lastLine;
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      switch (e) {
        case HeadingEvent():
          _heading(e, byLine[e.loc.file]?[e.loc.line] ?? const []);
        case BlockStart():
          block = e;
          for (final u in a.implicitUnits[e] ?? const <Unit>[]) {
            _prefix(e.loc, u);
          }
        case BlockEnd():
          var next = i + 1;
          while (next < events.length &&
              events[next] is! BlockStart &&
              events[next] is! HeadingEvent) {
            next++;
          }
          _flushEnds(
            lastLine,
            before: next < events.length ? events[next].loc : null,
          );
          block = null;
          lastLine = null;
        case LineStart(:final loc):
          final tokens = byLine[loc.file]?[loc.line] ?? const <Token>[];
          for (final u in a.implicitUnits[e] ?? const <Unit>[]) {
            _prefix(loc, u);
          }
          _lines[loc.file]![loc.line] = _line(
            loc.file,
            loc.line,
            tokens,
            block,
            lastLine,
          );
          lastLine = (loc.file, loc.line);
        case _:
          break;
      }
    }
    _flushEnds(lastLine);
    final prepared = Expando<Prepared>('units prepared');
    for (final MapEntry(key: node, value: file) in textOf.entries) {
      if (_titles[file] case final title?) {
        final source = file.lines.first;
        if (title != source && node is AbstractBlock) {
          prepared[node] = Prepared(source, title);
          // The title converted while the parser made its ID goes.
          node.title = source;
        }
        continue;
      }
      final source = file.lines.join('\n');
      // A line of markers alone prints nothing, not an empty line.
      final text = [
        for (final (i, line) in _lines[file]!.indexed)
          if (line.isNotEmpty || file.lines[i].isEmpty) line,
      ].join('\n');
      if (text != source) prepared[node] = Prepared(source, text);
    }
    _moveAnchorsOnly(prepared);
    _insertBlocks(prepared);
    return Rendering(prepared, atoms, roles)..starts.addAll(_starts);
  }

  // Headings --------------------------------------------------------------

  void _heading(HeadingEvent e, List<Token> tokens) {
    final node = _node = nodeOf[e.loc.file];
    final u =
        a.unitOfHeading[e] ??
        (e.marker == null ? null : a.unitOfMarker[e.marker]);
    final line = e.loc.file.lines[e.loc.line];
    final offset = line.length - e.title.length;
    final title = _text(
      _pieces(e.title, offset, [
        for (final t in tokens)
          if (t is! Marker) t,
      ]),
    );
    if (u == null || node is! AbstractBlock) {
      _titles[e.loc.file] = title;
      return;
    }
    final look = u.level.look;
    final ctx = {..._unitCtx(u), 'title': TText(title)};
    _titles[e.loc.file] = render(
      look.title ??
          '{{#title}}{{title}}{{/title}}{{^title}}{{label}}{{/title}}',
      ctx,
    ).trim();
    _starts[u] = (node, -1);
    _identify(node, u.id, u.reftext);
    if (look.role case final role?) node.addRole(role);
    for (final MapEntry(:key, :value) in look.attributes.entries) {
      node.attributes[key] = render(value, ctx);
    }
    for (final atom in _entries(u)) {
      _titles[e.loc.file] = '${_titles[e.loc.file]}${_place(atom)}';
    }
    if (look.end != null || _hasEndNotes(u)) _ending.add(u);
  }

  /// Gives [node] the unit ID [id] (and [reftext]): a generated ID gives
  /// way to it; one the document wrote stays, with [id] registered for
  /// the node too.
  void _identify(AbstractNode node, String id, String reftext) {
    final refs = document.catalog.refs;
    final old = node.id;
    if (old == null || (node is AbstractBlock && node.idGenerated)) {
      if (old != null && identical(refs[old], node)) refs.remove(old);
      node.id = id;
    }
    node.attributes['reftext'] = reftext;
    refs[id] = node;
  }

  // Units in text ---------------------------------------------------------

  Map<String, TValue> _unitCtx(Unit u) => {
    ...unitContext(u, config, a.document.attributes),
    'id': TText(u.id),
    'reftext': TText(u.reftext),
    'level': TText(u.level.name),
  };

  /// What a unit's start prints; for one that starts a block ([node]), the
  /// block becomes the unit's (its ID, role and options).
  List<UnitAtom> _unitAtoms(
    Unit u, {
    AbstractNode? node,
    bool startsBlock = false,
    bool keepAfter = true,
  }) {
    final look = u.level.look;
    if (look.end != null || _hasEndNotes(u)) _ending.add(u);
    final out = <UnitAtom>[UnitStartAtom(u)];
    for (final name in a.overlays[u] ?? const <String>[]) {
      out.add(
        PartAtom(
          name,
          role: config.settings['overlay-role'] ?? 'overlay',
          kind: PartKind.overlay,
        ),
      );
      final after = config.settings['overlay-after'] ?? ' ';
      if (after.isNotEmpty) {
        out.add(PartAtom(after, kind: PartKind.overlay));
      }
    }
    var anchored = false;
    if (startsBlock && node != null) {
      if (node.id == null) {
        node.id = u.id;
        node.attributes['reftext'] = u.reftext;
        document.catalog.refs[u.id] = node;
        anchored = true;
      }
      node.addRole(look.blockRole ?? u.level.name);
      look.blockOptions.forEach(node.setOption);
    }
    final ctx = _unitCtx(u);
    final hidden =
        u.level.hidden && look.label == null && look.map.flag('anchor') == null;
    if (!hidden && !anchored && look.anchor) {
      out.add(AnchorAtom(u.id, u.reftext));
      _register(node, u.id, u.reftext);
    }
    for (final extra in look.anchors) {
      final id = render(extra, ctx);
      out.add(AnchorAtom(id));
      _register(node, id, null);
    }
    if (look.label case final label?) {
      final text = render(label, ctx);
      if (text.isNotEmpty) {
        if (look.labelBefore.isNotEmpty) {
          out.add(PartAtom(look.labelBefore, kind: PartKind.label, unit: u));
        }
        out.add(
          PartAtom(
            text,
            style: look.labelStyle,
            role: look.labelRole,
            kind: PartKind.label,
            unit: u,
          ),
        );
        if (keepAfter && look.labelAfter.isNotEmpty) {
          out.add(PartAtom(look.labelAfter, kind: PartKind.label, unit: u));
        }
      }
    }
    if (look.indent case final indent?) {
      final text = render(indent, ctx);
      if (text.isNotEmpty) {
        out.add(PartAtom(text, kind: PartKind.label, unit: u));
      }
    }
    out.addAll(_entries(u));
    return out;
  }

  void _register(AbstractNode? node, String id, String? reftext) {
    if (node is! AbstractBlock) return;
    document.catalog.refs.putIfAbsent(
      id,
      () => Inline(
        node,
        InlineContext.anchor,
        text: reftext,
        type: 'ref',
        id: id,
      ),
    );
  }

  /// A unit starting at the start of a block or line with no marker of
  /// its own.
  void _prefix(Loc loc, Unit u) {
    final node = _node = nodeOf[loc.file];
    final atoms = _unitAtoms(
      u,
      node: node,
      startsBlock: u.level.breakMode == Break.block,
    );
    (_prefixes[(loc.file, loc.line)] ??= []).addAll(atoms);
  }

  bool _hasEndNotes(Unit u) => u.notes.entries.any(
    (e) =>
        config.streams[e.key]?.placement == Placement.end && e.value.isNotEmpty,
  );

  /// What a unit prints at its end: its level's end text, then its
  /// end-placed notes. Entries that are blocks of their own go after
  /// [node].
  List<UnitAtom> _endAtoms(Unit u, AbstractNode? node) {
    final look = u.level.look;
    final out = <UnitAtom>[];
    if (look.end case final end?) {
      final text = render(end, _unitCtx(u));
      if (text.isNotEmpty) {
        if (look.endBreak) {
          out.add(const BreakAtom());
        } else if (look.endBefore.isNotEmpty) {
          out.add(PartAtom(look.endBefore));
        }
        out.add(PartAtom(text, role: look.endRole));
      }
    }
    for (final entry in _entries(u, placement: Placement.end)) {
      if (entry case GroupAtom(:final role?)
          when config.streams.values.any(
            (s) => s.look.entryBlock && s.look.entryRole == role,
          )) {
        if (node != null) (_blocksAfter[node] ??= []).add(entry);
      } else {
        out.add(entry);
      }
    }
    return out;
  }

  /// The entries of [u]'s note streams placed at [placement].
  List<UnitAtom> _entries(Unit u, {Placement placement = Placement.entry}) {
    final out = <UnitAtom>[];
    for (final MapEntry(key: name, value: uses) in u.notes.entries) {
      final stream = config.streams[name];
      if (stream == null || stream.placement != placement || uses.isEmpty) {
        continue;
      }
      final look = stream.look;
      final parts = <UnitAtom>[];
      if (stream.templates['origin'] case final origin?) {
        final text = render(origin, _unitCtx(u));
        if (text.isNotEmpty) {
          parts
            ..add(PartAtom(text, style: look.originStyle))
            ..add(const PartAtom(' '));
        }
      }
      for (final (i, use) in uses.indexed) {
        if (i > 0) parts.add(PartAtom(look.noteSeparator));
        parts.add(PartAtom(use.caller, style: look.callerStyle));
        if (look.callerAfter.isNotEmpty) parts.add(PartAtom(look.callerAfter));
        parts.add(TextAtom(_body(use)));
      }
      out.add(GroupAtom(parts, role: look.entryRole ?? name));
      if (look.entryAfter.isNotEmpty && !look.entryBlock) {
        out.add(PartAtom(look.entryAfter, kind: PartKind.entry));
      }
    }
    return out;
  }

  /// A note's body, prepared (its own references and terms as atoms).
  String _body(NoteUse use) {
    final n = use.note;
    return _text(_pieces(n.body, n.bodyColumn, n.children), roles: false);
  }

  /// A footnote's content: its stream's prefix, origin and lemma, then the
  /// body.
  String _footnoteContent(NoteUse use) {
    final look = use.stream.look;
    final out = StringBuffer();
    if (look.prefix.isNotEmpty) out.write(_place(PartAtom(look.prefix)));
    final owner = use.unit ?? use.context;
    if (owner != null) {
      if (use.stream.templates['origin'] case final origin?) {
        final text = render(origin, _unitCtx(owner));
        if (text.isNotEmpty) {
          out
            ..write(_place(PartAtom(text, style: look.originStyle)))
            ..write(' ');
        }
      }
    }
    if (use.note.lemma case final lemma? when lemma.isNotEmpty) {
      out.write(_place(PartAtom(lemma, style: look.lemmaStyle, markup: true)));
      if (look.lemmaAfter.isNotEmpty) {
        out.write(_place(PartAtom(look.lemmaAfter)));
      }
    }
    out.write(_body(use));
    return out.toString();
  }

  /// Prints the ends of the units that end before [before] (the next
  /// block; null: the document's end) at the end of [lastLine].
  void _flushEnds((SourceFile, int)? lastLine, {Loc? before}) {
    if (lastLine == null || _ending.isEmpty) return;
    final (f, l) = lastLine;
    final node = nodeOf[f];
    for (final u in [..._ending]) {
      final end = u.end;
      if (before != null && (end == null || end.compareTo(before) > 0)) {
        continue;
      }
      _lines[f]![l] += _endAtoms(u, node).map(_place).join();
      _ending.remove(u);
    }
  }

  // Lines -----------------------------------------------------------------

  /// Whether [text] is only whitespace and range openers.
  static bool _leading(String text) =>
      text.replaceAll(RegExp(r'\[[\w-]+[^}]*\}'), '').trim().isEmpty;

  String _line(
    SourceFile f,
    int line,
    List<Token> tokens,
    BlockStart? block,
    (SourceFile, int)? lastLine,
  ) {
    final text = f.lines[line];
    final node = nodeOf[f];
    // Units a marker at the line's start ends print their ends on the
    // line before (an ayah's number after it).
    final first = tokens.whereType<Marker>().firstOrNull;
    if (first != null && lastLine != null && _ending.isNotEmpty) {
      final u = a.unitOfMarker[first];
      if (u != null && _leading(text.substring(0, first.loc.column))) {
        final (lf, ll) = lastLine;
        for (final e in [..._ending]) {
          if (e.level.scheme == u.level.scheme &&
              e.level.depth >= u.level.depth) {
            _lines[lf]![ll] += _endAtoms(e, nodeOf[lf]).map(_place).join();
            _ending.remove(e);
          }
        }
      }
    }
    // A marker that breaks the line at the line's start.
    for (final t in tokens) {
      if (t is! Marker) continue;
      if (!_leading(text.substring(0, t.loc.column))) break;
      final mode = a.unitOfMarker[t]?.level.breakMode;
      if (mode == Break.line &&
          lastLine != null &&
          lastLine.$1 == f &&
          block?.kind != BlockKind.verse) {
        final prev = _lines[f]![lastLine.$2];
        if (!prev.endsWith(' +')) _lines[f]![lastLine.$2] = '$prev +';
      }
      break;
    }
    _node = node;
    final rendered = _text(_pieces(text, 0, tokens));
    final prefix = _prefixes.remove((f, line));
    return prefix == null ? rendered : prefix.map(_place).join() + rendered;
  }

  /// The node whose text is being prepared.
  AbstractNode? _node;

  /// [text] (which starts at column [offset]) with its tokens as pieces.
  List<_Piece> _pieces(String text, int offset, List<Token> tokens) {
    final out = <_Piece>[];
    // Lemma spans lose their `##`.
    final cut = <(int, int)>[];
    for (final t in tokens) {
      if (t is Note && t.lemmaStart != null && !t.woven) {
        cut
          ..add((t.lemmaStart! - offset, t.lemmaStart! - offset + 2))
          ..add((t.loc.column - offset - 2, t.loc.column - offset));
      }
    }
    var pos = 0;
    void textTo(int end) {
      while (pos < end) {
        (int, int)? c;
        for (final x in cut) {
          if (x.$1 >= pos && x.$1 < end && (c == null || x.$1 < c.$1)) c = x;
        }
        if (c == null) {
          out.add(_Text(text.substring(pos, end)));
          pos = end;
          continue;
        }
        if (c.$1 > pos) out.add(_Text(text.substring(pos, c.$1)));
        // A lemma with an entry note: its caller goes before it.
        for (final t in tokens) {
          if (t is Note && t.lemmaStart == c.$1 + offset) {
            final use = a.notes[t];
            if (use != null && use.stream.placement != Placement.footnote) {
              out.add(_Atom(_caller(use)));
            }
          }
        }
        pos = c.$2;
      }
    }

    for (final t in tokens) {
      final start = t.loc.column - offset;
      if (start < pos) continue;
      textTo(start);
      out.addAll(_token(t));
      pos = t.end - offset;
      // A marker's space goes with it.
      if (t is Marker && pos < text.length && text[pos] == ' ') pos++;
    }
    textTo(text.length);
    return out;
  }

  UnitAtom _caller(NoteUse use) => PartAtom(
    use.caller,
    style: use.stream.look.callerStyle,
    role: use.stream.look.callerRole,
    kind: PartKind.caller,
  );

  List<_Piece> _token(Token t) {
    switch (t) {
      case Marker():
        final out = <_Piece>[];
        final u = a.unitOfMarker[t];
        // Units ending here print their ends first.
        if (_ending.isNotEmpty && u != null) {
          for (final e in [..._ending]) {
            if (e.level.depth >= u.level.depth) {
              out.addAll(_endAtoms(e, _node).map(_Atom.new));
              _ending.remove(e);
            }
          }
        }
        if (t.op == MarkerOp.close) {
          final closed = a.closedBy[t] ?? const [];
          if (closed.isNotEmpty && _node != null) {
            final scheme = closed.last.level.scheme;
            // The block is the nearest level above that is printed.
            var parent = closed.last.level.depth - 1;
            while (parent > 0 && scheme.levels[parent].hidden) {
              parent--;
            }
            if (parent >= 0 &&
                scheme.levels.any((l) => l.breakMode == Break.block)) {
              final level = scheme.levels[parent];
              _node!
                ..addRole(level.look.blockRole ?? level.name)
                ..addRole('resumed');
            }
          }
          return out;
        }
        if (u == null) return out; // `@=` and errors print nothing
        // A label of several levels prints each one it starts: (h)(1).
        for (final started in a.startedBy[t] ?? [u]) {
          if (started != u && started.level.look.label == null) continue;
          out.addAll(
            _unitAtoms(
              started,
              node: _node,
              startsBlock: started == u && u.level.breakMode == Break.block,
              keepAfter: started == u,
            ).map(_Atom.new),
          );
        }
        for (final child in a.implicitAtMarker[t] ?? const <Unit>[]) {
          out.addAll(_unitAtoms(child, node: _node).map(_Atom.new));
        }
        return out;
      case RangeOpen():
        return [_Open(t)];
      case RangeClose():
        return [_Close(t)];
      case Note():
        final use = a.notes[t];
        if (use == null) return [];
        if (use.stream.placement != Placement.footnote) {
          // Its caller goes before its lemma (or here, without one).
          if (t.lemmaStart != null) return [];
          return [_Atom(_caller(use))];
        }
        // A note with an ID is written once and called again by it.
        if (t.id case final id?) {
          final content = t.body.isEmpty
              ? _noteTexts[id]
              : (_noteTexts[id] = _footnoteContent(use));
          return [_Atom(FootnoteAtom(content, id: id), after: t.lemmaRange)];
        }
        return [
          _Atom(FootnoteAtom(_footnoteContent(use)), after: t.lemmaRange),
        ];
      case Xref():
        final ref = a.refs[t];
        if (ref == null) return [_Text('<<${t.content}>>')];
        return [_Atom(ReferenceAtom(ref.parts))];
      case Dfn(:final term):
        // The first definition of a term has its anchor.
        final id = 'term-${applyFilter('slug', term)}';
        return [
          if (_dfnSeen.add(id)) _Atom(AnchorAtom(id)),
          _Atom(PartAtom(term, role: 'dfn', markup: true)),
        ];
    }
  }

  /// The pieces as prepared text: text inside open ranges and found by
  /// term rules in range marks, atoms as placeholders. [roles] false
  /// prepares a note's body: on its own, with no range of the text around
  /// it, and no term rules.
  String _text(List<_Piece> pieces, {bool roles = true}) {
    final out = StringBuffer();
    for (final piece in pieces) {
      switch (piece) {
        case _Atom(:final atom, :final after):
          if (roles && _hidden) break;
          if (after != null && _hiddenCloses.contains(after)) break;
          out.write(_place(atom));
        case _Open(:final range):
          if (roles) _open.add(range);
        case _Close(:final range):
          if (roles) {
            if (_hidden) _hiddenCloses.add(range);
            final at = _open.lastIndexWhere((r) => r.name == range.name);
            if (at >= 0) _open.removeAt(at);
          }
        case _Text(:final text):
          if (roles && _hidden) break;
          out.write(_styled(text.replaceAll(r'\@', '@'), roles: roles));
      }
    }
    return out.toString();
  }

  /// Whether text is inside a range the as-of date hides.
  bool get _hidden {
    final asOf = this.asOf;
    if (asOf == null) return false;
    for (final r in _open) {
      final from = r.attrs['from'];
      if (from == null) continue;
      final before = asOf.compareTo(from) < 0;
      if ((r.name == 'ins' || r.name == 'sub') && before) return true;
      if (r.name == 'del' && !before) return true;
    }
    return false;
  }

  /// [text] with the roles of the open ranges and of the term rules that
  /// find text in it, as range marks around each segment (whitespace at
  /// either end stays outside).
  String _styled(String text, {bool roles = true}) {
    final rangeRoles = [
      if (roles)
        for (final r in _open) ?config.ranges[r.name]?.role,
    ];
    final segments = <(String, List<String>)>[];
    var pos = 0;
    final hits = <(int, int, TermRule)>[];
    for (final rule in roles ? config.termRules : const <TermRule>[]) {
      for (final m in rule.pattern.allMatches(text)) {
        if (hits.any((h) => m.start < h.$2 && m.end > h.$1)) continue;
        hits.add((m.start, m.end, rule));
      }
    }
    hits.sort((x, y) => x.$1.compareTo(y.$1));
    for (final (s, e, rule) in hits) {
      if (s > pos) segments.add((text.substring(pos, s), rangeRoles));
      final t = text.substring(s, e);
      segments.add((
        rule.transform == null ? t : applyFilter(rule.transform!, t),
        [...rangeRoles, rule.role],
      ));
      pos = e;
    }
    if (pos < text.length) segments.add((text.substring(pos), rangeRoles));
    final out = StringBuffer();
    for (final (t, rs) in segments) {
      if (rs.isEmpty) {
        out.write(t);
        continue;
      }
      final m = RegExp(r'^(\s*)(.*?)(\s*)$', dotAll: true).firstMatch(t)!;
      if (m[2]!.isEmpty) {
        out.write(t);
        continue;
      }
      final k = _role(rs.join(' '));
      out
        ..write('${m[1]}$rangeOpenMark$k$markEnd')
        ..write('${m[2]}$rangeCloseMark$k$markEnd${m[3]}');
    }
    return out.toString();
  }

  /// Paragraphs of empty units (markers alone) print only anchors: the
  /// anchors go to the start of the next paragraph (or, with none next, the
  /// end of the one before), and the paragraph goes.
  void _moveAnchorsOnly(Expando<Prepared> prepared) {
    final only = RegExp('^(?:\\s|$atomMark\\d+$markEnd)+\$');
    bool isParagraph(AbstractBlock? b) =>
        b is Block &&
        b.context == BlockContext.paragraph &&
        textOf.containsKey(b);
    String currentText(Block b) => prepared[b]?.text ?? b.lines.join('\n');
    void set(Block b, String text) =>
        prepared[b] = Prepared(b.lines.join('\n'), text);
    String? carried;
    for (final node in [...textOf.keys]) {
      if (node is! Block || node.context != BlockContext.paragraph) {
        continue;
      }
      if (carried != null) {
        set(node, carried + currentText(node));
        carried = null;
      }
      final text = currentText(node);
      if (!only.hasMatch(text) ||
          atomRx
              .allMatches(text)
              .any(
                (m) => switch (atoms[int.parse(m[1]!)]) {
                  AnchorAtom() || UnitStartAtom() => false,
                  _ => true,
                },
              )) {
        continue;
      }
      final next = _sibling(node, 1);
      final previous = _sibling(node, -1);
      if (!isParagraph(next) && !isParagraph(previous)) continue;
      var anchors = text.replaceAll(RegExp(r'\s'), '');
      if (node.id case final id?) {
        final reftext = node.attributes['reftext'];
        anchors = _place(AnchorAtom(id, reftext)) + anchors;
        document.catalog.refs.remove(id);
        _register(isParagraph(next) ? next : previous, id, reftext);
      }
      final target = isParagraph(next) ? next! : previous!;
      // The units that start here start there.
      for (final m in atomRx.allMatches(anchors)) {
        if (atoms[int.parse(m[1]!)] case UnitStartAtom(:final unit)) {
          _starts[unit] = (target, int.parse(m[1]!));
        }
      }
      if (isParagraph(next)) {
        carried = anchors;
      } else {
        final before = previous! as Block;
        set(before, currentText(before) + anchors);
      }
      node.parent!.blocks.remove(node);
    }
  }

  static AbstractBlock? _sibling(AbstractBlock node, int offset) {
    if (node.parent case final AbstractBlock parent) {
      final at = parent.blocks.indexOf(node) + offset;
      if (at >= 0 && at < parent.blocks.length) return parent.blocks[at];
    }
    return null;
  }

  // Blocks of their own -----------------------------------------------------

  /// Adds the entries that are blocks of their own after their nodes.
  void _insertBlocks(Expando<Prepared> prepared) {
    for (final MapEntry(key: node, value: entries) in _blocksAfter.entries) {
      final AbstractBlock parent;
      int at;
      if (node is ListItem) {
        parent = node;
        at = node.blocks.length;
      } else if (node.parent case final AbstractBlock p
          when p.blocks.contains(node)) {
        parent = p;
        at = p.blocks.indexOf(node as AbstractBlock) + 1;
      } else {
        continue;
      }
      for (final entry in entries) {
        final text = _place(entry);
        final block = Block(parent, BlockContext.paragraph, source: text);
        if (entry case GroupAtom(:final role?)) block.addRole(role);
        block.commitSubs();
        // The entry's own span would repeat the block's role.
        atoms[atoms.length - 1] = switch (entry) {
          GroupAtom(:final atoms) => GroupAtom(atoms),
          _ => entry,
        };
        parent.blocks.insert(at++, block);
      }
    }
  }
}
