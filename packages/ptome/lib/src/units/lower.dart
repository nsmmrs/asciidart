/// Lowers a document in the dialect to standard AsciiDoc that any
/// Asciidoctor reads: markers become anchors and printed labels, ranges
/// become role spans (split at blocks and markers), notes become footnotes
/// or a unit's entry, references become links, all through the templates
/// the scheme files give.
library;

import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/process.dart' show includePath, includeUnit;
import 'package:ptome/src/units/scheme.dart';
import 'package:ptome/src/units/template.dart';

/// Each source file's lowered lines, by path.
typedef Lowered = Map<String, List<String>>;

/// [quoting]: the text alone, for quoting elsewhere: no notes, no
/// entries.
/// Around what a unit's start prints, when quoting: start, the unit's ID,
/// middle, what it prints, end.
const quoteStart = '\u{E000}';

/// Between a quoted unit's ID and what it prints.
const quoteMid = '\u{E001}';

/// After what a quoted unit prints.
const quoteEnd = '\u{E002}';

/// Renders the analyzed document [a] as AsciiDoc: each source file's lines
/// with its units as anchors and labels, its ranges as role spans, its
/// notes as footnotes or entries and its references as links. [asOf] hides
/// what was not yet in force (or no longer) on that date.
Lowered lower(Analysis a, {String? asOf, bool quoting = false}) =>
    _Lowerer(a, asOf, quoting: quoting).run();

sealed class _Piece;

final class _Text extends _Piece {
  new(this.text);
  final String text;
}

final class _Atom extends _Piece {
  new(this.text, {this.after});
  final String text;

  /// The range a note atom annotates: hidden with it.
  final RangeClose? after;
}

/// A note with an ID: its text the first time it is shown, its ID after.
final class _NoteAtom extends _Piece {
  new(this.id, this.content, {this.after});
  final String id;
  final String? content;
  final RangeClose? after;
}

final class _Open extends _Piece {
  new(this.range);
  final RangeOpen range;
}

final class _Close extends _Piece {
  new(this.range);
  final RangeClose range;
}

final class _Lowerer {
  new(this.a, this.asOf, {this.quoting = false});
  final Analysis a;
  final String? asOf;
  final bool quoting;
  Config get config => a.config;

  /// Replacement lines by file and line (null: dropped).
  final Map<SourceFile, Map<int, List<String>>> _replace = {};

  /// Lines inserted before a line.
  final Map<SourceFile, Map<int, List<String>>> _before = {};

  /// Open ranges, outermost first.
  final List<RangeOpen> _open = [];

  /// Units that print something at their end, waiting for it.
  final List<Unit> _ending = [];

  Lowered run() {
    final events = a.document.events;
    // Tokens by line.
    final byLine = <SourceFile, Map<int, List<Token>>>{};
    for (final e in events) {
      if (e is TokenEvent) {
        ((byLine[e.loc.file] ??= {})[e.loc.line] ??= []).add(e.token);
      }
    }
    BlockStart? block;
    // The last output line of the current block, to add a hard break to.
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
          // Units whose text ends with this block print their ends here.
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
          final offset =
              block?.kind == BlockKind.dlist && block!.loc.line == loc.line
              ? loc.file.lines[loc.line].indexOf('::') + 2
              : 0;
          final text = _line(
            loc.file,
            loc.line,
            offset,
            tokens,
            block,
            lastLine,
          );
          final original = loc.file.lines[loc.line];
          (_replace[loc.file] ??= {})[loc.line] = [
            original.substring(0, offset) + text,
          ];
          lastLine = (loc.file, loc.line);
        case IncludeSelf(:final id, :final loc):
          final found = a.document.blocksById[id];
          if (found == null) {
            a.warn(loc, 'no block #$id to repeat');
            break;
          }
          final (file, start, end) = found;
          (_replace[loc.file] ??= {})[loc.line] = [
            for (var j = start; j <= end; j++)
              file.lines[j]
                  .replaceAll('#$id', '')
                  .replaceAll('[[$id]]', '')
                  .replaceAll('[]', ''),
          ].where((l) => true).toList();
        case IncludeUnit(
          :final target,
          :final address,
          :final cite,
          :final loc,
        ):
          final path = includePath(a, loc.file.path, target);
          final included = includeUnit(path, address, cite: cite);
          if (included == null) a.warn(loc, 'no passage $address in $target');
          (_replace[loc.file] ??= {})[loc.line] =
              included ?? ['// passage $address of $target not found'];
        case TokenEvent():
          break;
      }
    }
    final out = <String, List<String>>{};
    for (final f in a.document.files) {
      final lines = <String>[];
      final rep = _replace[f] ?? const {};
      final bef = _before[f] ?? const {};
      for (var j = 0; j < f.lines.length; j++) {
        if (bef[j] case final b?) lines.addAll(b);
        lines.addAll(rep[j] ?? [f.lines[j]]);
      }
      out[f.path] = lines;
    }
    return out;
  }

  void _insertBefore(Loc loc, List<String> lines) {
    ((_before[loc.file] ??= {})[loc.line] ??= []).addAll(lines);
  }

  // Headings ------------------------------------------------------------

  void _heading(HeadingEvent e, List<Token> tokens) {
    final u =
        a.unitOfHeading[e] ??
        (e.marker == null ? null : a.unitOfMarker[e.marker]);
    final line = e.loc.file.lines[e.loc.line];
    final eq = '=' * (e.depth + 1);
    var title = e.title;
    // References and terms in the title.
    final offset = line.length - e.title.length;
    title = _render(
      _pieces(e.title, offset, [
        for (final t in tokens)
          if (t is! Marker) t,
      ], null),
    );
    // A heading the as-of date hides (an inserted section's) goes.
    if (title.trim().isEmpty && e.title.trim().isNotEmpty) {
      (_replace[e.loc.file] ??= {})[e.loc.line] = [];
      return;
    }
    if (u == null) {
      if (title != e.title) {
        (_replace[e.loc.file] ??= {})[e.loc.line] = ['$eq $title'];
      }
      return;
    }
    final ctx = {
      ...unitContext(u, config, a.document.attributes),
      'id': TText(u.id),
      'reftext': TText(u.reftext),
      '=': TText(eq),
      'title': TText(title),
    };
    final template =
        u.level.templates['heading'] ??
        '[[{{id}},{{reftext}}]]\n{{=}} {{#title}}{{title}}{{/title}}{{^title}}{{label}}{{/title}}';
    (_replace[e.loc.file] ??= {})[e.loc.line] = render(
      template,
      ctx,
    ).split('\n');
  }

  // Units in text ---------------------------------------------------------

  /// What a unit's start prints inline (anchor, label) and, for one that
  /// starts a block, the lines before the block.
  String _unitText(Unit u, {bool startsBlock = false, Loc? loc}) {
    final ctx = _unitCtx(u);
    if (u.level.templates['lower-end'] != null || _hasEndNotes(u)) {
      _ending.add(u);
    }
    if (startsBlock && loc != null) {
      final lines = render(
        u.level.templates['lower-block'] ??
            '[[{{id}},{{reftext}}]]\n[.{{level}}]',
        ctx,
      );
      _pendingBlockLines.addAll(lines.split('\n'));
    }
    final inline =
        u.level.templates['lower'] ??
        (u.level.hidden || startsBlock ? '' : '[[{{id}},{{reftext}}]]');
    final entry = _entries(u);
    final overlays = [
      for (final name in a.overlays[u] ?? const <String>[])
        render(config.settings['overlay'] ?? '[.overlay]##{{name}}## ', {
          ...ctx,
          'name': TText(name),
        }),
    ].join();
    final printed = render(inline, ctx);
    // A quotation leaves out the label of the unit it quotes; it knows
    // which by these marks.
    return overlays +
        (quoting && printed.isNotEmpty
            ? '$quoteStart${u.id}$quoteMid$printed$quoteEnd'
            : printed) +
        entry;
  }

  final List<String> _pendingBlockLines = [];

  /// Note IDs already written (their text goes with the first shown).
  final Set<String> _notesSeen = {};

  /// Each note ID's text, wherever it was written.
  final Map<String, String> _noteTexts = {};

  /// Terms whose definition has its anchor.
  final Set<String> _dfnSeen = {};

  Map<String, TValue> _unitCtx(Unit u) => {
    ...unitContext(u, config, a.document.attributes),
    'id': TText(u.id),
    'reftext': TText(u.reftext),
    'level': TText(u.level.name),
  };

  /// A unit starting at the start of a block or line with no marker of
  /// its own.
  void _prefix(Loc loc, Unit u) {
    final text = _unitText(
      u,
      startsBlock: u.level.breakMode == Break.block,
      loc: loc,
    );
    if (_pendingBlockLines.isNotEmpty) {
      _insertBefore(loc, [..._pendingBlockLines]);
      _pendingBlockLines.clear();
    }
    final key = '${loc.file.path}:${loc.line}';
    _prefixes[key] = (_prefixes[key] ?? '') + text;
  }

  /// What units starting at a line print at its start, by `path:line`.
  final Map<String, String> _prefixes = {};

  bool _hasEndNotes(Unit u) => u.notes.entries.any(
    (e) =>
        config.streams[e.key]?.placement == Placement.end && e.value.isNotEmpty,
  );

  /// What a unit prints at its end: its level's `lower-end`, then its
  /// end-placed notes.
  String _endText(Unit u) =>
      render(u.level.templates['lower-end'] ?? '', _unitCtx(u)) +
      _entries(u, placement: Placement.end);

  /// The entries of a unit's entry-placed note streams (a reference
  /// Bible's center column).
  String _entries(Unit u, {Placement placement = Placement.entry}) {
    if (quoting) return '';
    final out = StringBuffer();
    for (final MapEntry(key: name, value: uses) in u.notes.entries) {
      final stream = config.streams[name];
      if (stream == null || stream.placement != placement || uses.isEmpty) {
        continue;
      }
      final ctx = {
        ..._unitCtx(u),
        'origin': TText(
          render(stream.templates['origin'] ?? '{{label}}', _unitCtx(u)),
        ),
        'notes': TItems([
          for (final (i, use) in uses.indexed)
            {
              'caller': TText(use.caller),
              'body': TText(_body(use)),
              'first': TFlag(value: i == 0),
              'lemma': TText(use.note.lemma ?? ''),
            },
        ]),
      };
      out.write(
        render(
          stream.templates['entry'] ??
              '[.{{stream}}]##{{#notes}}^{{caller}}^ {{body}} {{/notes}}##',
          {...ctx, 'stream': TText(name)},
        ),
      );
    }
    return out.toString();
  }

  String _body(NoteUse use) {
    final n = use.note;
    final tokens = [for (final c in n.children) c];
    final pieces = _pieces(n.body, n.bodyColumn, tokens, null);
    // Notes keep their text as written: a role span inside a macro's
    // brackets would end it.
    return _render(pieces, keepRoles: false, terms: false);
  }

  /// Prints the ends of the units that end before [before] (the next
  /// block; null: the document's end) on [lastLine].
  void _flushEnds((SourceFile, int)? lastLine, {Loc? before}) {
    if (lastLine == null || _ending.isEmpty) return;
    final (f, l) = lastLine;
    final lines = _replace[f]![l]!;
    for (final u in [..._ending]) {
      final end = u.end;
      if (before != null && end != null && end.compareTo(before) > 0) continue;
      if (before != null && end == null) continue;
      lines[lines.length - 1] += _endText(u);
      _ending.remove(u);
    }
  }

  // Lines ---------------------------------------------------------------

  String _line(
    SourceFile f,
    int line,
    int offset,
    List<Token> tokens,
    BlockStart? block,
    (SourceFile, int)? lastLine,
  ) {
    // Units a marker at the line's start ends print their ends on the
    // line before (an ayah's number after it).
    final first = tokens.whereType<Marker>().firstOrNull;
    if (first != null && lastLine != null && _ending.isNotEmpty) {
      final text0 = f.lines[line].substring(offset, first.loc.column);
      final u = a.unitOfMarker[first];
      if (u != null &&
          text0.replaceAll(RegExp(r'\[[\w-]+[^}]*\}'), '').trim().isEmpty) {
        final prev = _replace[lastLine.$1]![lastLine.$2]!;
        for (final e in [..._ending]) {
          if (e.level.scheme == u.level.scheme &&
              e.level.depth >= u.level.depth) {
            prev[prev.length - 1] += _endText(e);
            _ending.remove(e);
          }
        }
      }
    }
    final text = f.lines[line].substring(offset);
    final pieces = _pieces(text, offset, tokens, block);
    final loc = tokens.isEmpty ? null : tokens.first.loc;
    // A marker that breaks the line or the block at the line's start.
    for (final t in tokens) {
      if (t is! Marker) continue;
      final u = a.unitOfMarker[t];
      final lead = text
          .substring(0, t.loc.column - offset)
          .replaceAll(RegExp(r'\[[\w-]+[^}]*\}'), '')
          .trim()
          .isEmpty;
      if (!lead) break;
      final mode =
          u?.level.breakMode ?? (t.op == MarkerOp.close ? Break.block : null);
      if (mode == Break.line &&
          lastLine != null &&
          lastLine.$1 == f &&
          block?.kind != BlockKind.verse) {
        final prev = _replace[f]![lastLine.$2]!;
        if (!prev.last.endsWith(' +')) prev[prev.length - 1] += ' +';
      }
      if (mode == Break.block && lastLine != null) {
        // A block of its own: a blank line before it.
        _insertBefore(t.loc, ['']);
      }
      break;
    }
    final rendered = _render(pieces);
    if (_pendingBlockLines.isNotEmpty && loc != null) {
      _insertBefore(Loc(f, line, 0, loc.order), [..._pendingBlockLines]);
      _pendingBlockLines.clear();
    }
    // A list item's marker stays first (`* `, `. `).
    final prefix = _prefixes.remove('${f.path}:$line') ?? '';
    final item = RegExp(r'^\s*(\*+|-|\.+|\d+\.)\s+').firstMatch(rendered);
    if (prefix.isNotEmpty && item != null) {
      return rendered.substring(0, item.end) +
          prefix +
          rendered.substring(item.end);
    }
    return prefix + rendered;
  }

  /// [text] (which starts at column [offset]) with its tokens as pieces.
  List<_Piece> _pieces(
    String text,
    int offset,
    List<Token> tokens,
    BlockStart? block,
  ) {
    final out = <_Piece>[];
    // Lemma spans lose their `##`.
    final cut = <(int, int)>[];
    for (final t in tokens) {
      if (t is Note && t.lemmaStart != null) {
        cut
          ..add((t.lemmaStart! - offset, t.lemmaStart! - offset + 2))
          ..add((t.loc.column - offset - 2, t.loc.column - offset));
      }
    }
    var pos = 0;
    void textTo(int end) {
      while (pos < end) {
        final c = cut
            .where((x) => x.$1 >= pos && x.$1 < end)
            .fold<(int, int)?>(
              null,
              (best, x) => best == null || x.$1 < best.$1 ? x : best,
            );
        if (c == null) {
          out.add(_Text(text.substring(pos, end)));
          pos = end;
        } else {
          if (c.$1 > pos) out.add(_Text(text.substring(pos, c.$1)));
          // A lemma with an entry note: its caller goes before it.
          for (final t in tokens) {
            if (t is Note && t.lemmaStart == c.$1 + offset) {
              final use = a.notes[t];
              if (use != null &&
                  !quoting &&
                  use.stream.placement != Placement.footnote) {
                out.add(
                  _Atom(
                    render(use.stream.templates['mark'] ?? '^{{caller}}^', {
                      'caller': TText(use.caller),
                    }),
                  ),
                );
              }
            }
          }
          pos = c.$2;
        }
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

  List<_Piece> _token(Token t) {
    switch (t) {
      case Marker():
        final out = <_Piece>[];
        final u = a.unitOfMarker[t];
        // Units ending here print their ends first.
        if (_ending.isNotEmpty && u != null) {
          for (final e in [..._ending]) {
            if (e.level.depth >= u.level.depth) {
              out.add(_Atom(_endText(e)));
              _ending.remove(e);
            }
          }
        }
        if (t.op == MarkerOp.close) {
          final closed = a.closedBy[t] ?? const [];
          if (closed.isNotEmpty) {
            final scheme = closed.last.level.scheme;
            // The block is the nearest level above that is printed.
            var parent = closed.last.level.depth - 1;
            while (parent > 0 && scheme.levels[parent].hidden) {
              parent--;
            }
            if (parent >= 0 &&
                scheme.levels.any((l) => l.breakMode == Break.block)) {
              final level = scheme.levels[parent];
              _pendingBlockLines.add(
                render(
                  level.templates['lower-resume'] ?? '[.{{level}}.resumed]',
                  {'level': TText(level.name)},
                ),
              );
            }
          }
          return out;
        }
        if (u == null) return out; // `@=` and errors print nothing
        // A label of several levels prints each one it starts: (h)(1).
        for (final started in a.startedBy[t] ?? [u]) {
          if (started != u && started.level.templates['lower'] == null) {
            continue;
          }
          final text = _unitText(
            started,
            startsBlock: started == u && u.level.breakMode == Break.block,
            loc: t.loc,
          );
          out.add(_Atom(started == u ? text : text.trimRight()));
        }
        for (final child in a.implicitAtMarker[t] ?? const <Unit>[]) {
          out.add(_Atom(_unitText(child)));
        }
        return out;
      case RangeOpen():
        return [_Open(t)];
      case RangeClose():
        return [_Close(t)];
      case Note():
        final use = a.notes[t];
        if (use == null || quoting) return [];
        final stream = use.stream;
        if (stream.placement != Placement.footnote) {
          // Its caller goes before its lemma (or here, without one).
          if (t.lemmaStart != null) return [];
          return [
            _Atom(
              render(stream.templates['mark'] ?? '^{{caller}}^', {
                'caller': TText(use.caller),
              }),
            ),
          ];
        }
        final owner = use.unit ?? use.context;
        final ctx = {
          if (owner != null) ..._unitCtx(owner),
          'origin': TText(
            owner == null
                ? ''
                : render(stream.templates['origin'] ?? '', _unitCtx(owner)),
          ),
          'lemma': TText(use.note.lemma ?? ''),
          'body': TText(_body(use)),
          'caller': TText(use.caller),
        };
        // A note with an ID is written once and called again by it.
        if (t.id case final id?) {
          final content = t.body.isEmpty
              ? null
              : render(stream.templates['lower'] ?? '{{body}}', ctx);
          if (content != null) _noteTexts[id] = content;
          return [_NoteAtom(id, content, after: t.lemmaRange)];
        }
        final text = render(stream.templates['lower'] ?? '{{body}}', ctx);
        return [_Atom('footnote:[$text]', after: t.lemmaRange)];
      case Xref():
        final ref = a.refs[t];
        if (ref == null) return [_Atom('<<${t.content}>>')];
        return [
          _Atom(
            ref.parts
                .map(
                  (part) => switch (part) {
                    RefText(:final text) => text,
                    RefLink(:final text, :final id, :final file) =>
                      file == null ? '<<$id,$text>>' : 'xref:$file#$id[$text]',
                  },
                )
                .join(),
          ),
        ];
      case Dfn(:final term):
        // The first definition of a term has its anchor.
        final id = 'term-${applyFilter('slug', term)}';
        return [_Atom('${_dfnSeen.add(id) ? '[[$id]]' : ''}[.dfn]#$term#')];
    }
  }

  /// Pieces as AsciiDoc: text inside open ranges and found by term rules
  /// wrapped in role spans, the rest as is.
  /// [keepRoles] false renders a note's body: on its own, with no range
  /// of the text around it.
  String _render(
    List<_Piece> pieces, {
    bool keepRoles = true,
    bool terms = true,
  }) {
    final out = StringBuffer();
    for (final piece in pieces) {
      switch (piece) {
        case _Atom(:final text, :final after):
          if (keepRoles && _hidden) break;
          if (after != null && _hiddenCloses.contains(after)) break;
          out.write(text);
        case _NoteAtom(:final id, :final content, :final after):
          if (keepRoles && _hidden) break;
          if (after != null && _hiddenCloses.contains(after)) break;
          final text = content ?? _noteTexts[id];
          out.write(
            text != null && _notesSeen.add(id)
                ? 'footnote:$id[$text]'
                : 'footnote:$id[]',
          );
        case _Open(:final range):
          if (keepRoles) _open.add(range);
        case _Close(:final range):
          if (keepRoles) {
            if (_hidden) _hiddenCloses.add(range);
            final at = _open.lastIndexWhere((r) => r.name == range.name);
            if (at >= 0) _open.removeAt(at);
          }
        case _Text(:final text):
          if (keepRoles && _hidden) break;
          out.write(_styled(text, terms: terms, roles: keepRoles));
      }
    }
    return out.toString().replaceAll(r'\@', '@');
  }

  /// Ranges the as-of date hid, so their notes go too.
  final Set<RangeClose> _hiddenCloses = {};

  /// Whether text is inside a range the as-of date hides.
  bool get _hidden {
    if (asOf == null) return false;
    for (final r in _open) {
      final from = r.attrs['from'];
      if (from == null) continue;
      final before = asOf!.compareTo(from) < 0;
      if ((r.name == 'ins' || r.name == 'sub') && before) return true;
      if (r.name == 'del' && !before) return true;
    }
    return false;
  }

  String _styled(String text, {bool terms = true, bool roles = true}) {
    final rangeRoles = [
      if (roles)
        for (final r in _open) ?config.ranges[r.name]?.role,
    ];
    // Term rules split the text.
    final segments = <(String, List<String>)>[];
    var pos = 0;
    final hits = <(int, int, TermRule)>[];
    for (final rule in terms ? config.termRules : const <TermRule>[]) {
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
      out.write('${m[1]}[.${rs.join('.')}]##${m[2]}##${m[3]}');
    }
    return out.toString();
  }
}
