/// Reads a document in the dialect: follows its includes, finds its blocks
/// (headings, paragraphs, list items, description-list entries, verse
/// blocks) and, in their text, the dialect's tokens — unit markers `@…`,
/// ranges `[name}…{name]`, notes `note:stream[…]`, references `<<…>>` and
/// defined terms `[.dfn]#…#`. Everything else is AsciiDoc and passes
/// through untouched.
library;

import 'package:ptome/src/cursor.dart';
import 'package:ptome/src/units/files.dart' as p;

/// A source file of the document: the root or one it includes.
final class SourceFile {
  /// The file at [path] with its [lines]; [origins], when given, say where
  /// each line was read (a text ptome's parser read: a block's lines).
  new(this.path, this.lines, {this.origins});

  /// The file's path.
  final String path;

  /// The file's lines, without terminators.
  final List<String> lines;

  /// Where each line was read, aligned with [lines], for a text ptome's
  /// parser read (positions then point into the source as written).
  final List<LineOrigin>? origins;

  /// Where line [line] (0-based) was read, if known.
  LineOrigin? originOf(int line) {
    final o = origins;
    return o == null || line >= o.length ? null : o[line];
  }
}

/// A place in a source file: line and column (0-based).
final class Loc implements Comparable<Loc> {
  /// The place in [file] at [line] and [column]; [order] ranks it across
  /// files in reading order.
  const new(this.file, this.line, this.column, this.order);

  /// The file.
  final SourceFile file;

  /// The line (0-based).
  final int line;

  /// The column (0-based).
  final int column;

  /// Position in reading order across all files.
  final int order;

  @override
  int compareTo(Loc o) =>
      order != o.order ? order.compareTo(o.order) : column.compareTo(o.column);

  @override
  String toString() {
    if (file.originOf(line) case final o?) {
      return '${p.basename(o.path)}:${o.line}:${o.column + column + 1}';
    }
    return '${p.basename(file.path)}:${line + 1}:${column + 1}';
  }
}

/// Something the units syntax writes in a line of text.
sealed class Token {
  new(this.loc, this.end);

  /// Where the token starts.
  final Loc loc;

  /// The column just after the token.
  final int end;
}

/// What a marker does: start the unit with a label (`@6`), step to the
/// next unit (`@`, `@@`), or close the innermost unit (`@^`).
enum MarkerOp {
  /// Start the unit with a label (`@6`, `@(a)`).
  label,

  /// Step to the next unit (`@`, `@@`).
  step,

  /// Close the innermost unit (`@^`).
  close,
}

/// `@`, `@@`, `@6`, `@(a)(1)`, `@18-23.1`, `@^`, `@[recital]`, `@[part=F]`.
final class Marker extends Token {
  /// A marker at [loc] doing [op] with [label] and [attrs].
  new(
    super.loc,
    super.end,
    this.op,
    this.label,
    this.attrs, {
    this.inHeading = false,
    this.up = 0,
  });

  /// What the marker does.
  final MarkerOp op;

  /// For a bare marker, how many levels above the default it steps
  /// (`@@`: 1, the next section or chapter, its first segment or verse).
  final int up;

  /// The label (for [MarkerOp.label]).
  final String label;

  /// The marker's attributes (`@[part=F]`, `@[recital]`).
  final Attrs attrs;

  /// Whether the marker is in a heading (`=== @34`).
  final bool inHeading;

  /// Set by the engine: whether it starts a block or a line in lowering.
  bool startsLine = false;
}

/// `[name}`, `[name#id attr=value}`: a range opens.
final class RangeOpen extends Token {
  /// A range named [name] opening at [loc], with [id] and [attrs].
  new(super.loc, super.end, this.name, this.id, this.attrs);

  /// The range's name, which a scheme declares.
  final String name;

  /// The range's ID, if written (`[ins#F1}`).
  final String? id;

  /// The range's attributes (`from=2023-06-01`).
  final Map<String, String> attrs;
}

/// `{name]`: a range closes.
final class RangeClose extends Token {
  /// The close of the range named [name] (and [id]) at [loc].
  new(super.loc, super.end, this.name, this.id);

  /// The range's name.
  final String name;

  /// The range's ID, if written.
  final String? id;
}

/// `note:x[…]` or `footnote:[…]`; [lemma] is the `##span##` or the range
/// right before it.
final class Note extends Token {
  /// A note in [stream] with [body], at [loc].
  new(
    super.loc,
    super.end,
    this.stream,
    this.body,
    this.bodyColumn,
    this.children, {
    this.lemma,
    this.lemmaStart,
    this.lemmaRange,
    this.id,
    this.woven = false,
  });

  /// Whether a layer wove the note in (ADR-0020): it is in no text, and
  /// its lemma has no markup there.
  final bool woven;

  /// The note stream (`x`, `tn`, `F`), which a scheme declares.
  final String stream;

  /// The note's text, as written.
  final String body;

  /// A note's ID (`note:F#c123[…]`): `note:F#c123[]` uses it again.
  final String? id;

  /// Where [body] starts in the line.
  final int bodyColumn;

  /// References inside the body.
  final List<Token> children;

  /// The text the note annotates: a `##span##` or the range right before it.
  final String? lemma;

  /// Where a `##span##` lemma starts (its markup is dropped in lowering).
  final int? lemmaStart;

  /// The range a note right after `{name]` annotates.
  final RangeClose? lemmaRange;
}

/// `<<…>>`.
final class Xref extends Token {
  /// A reference at [loc] whose brackets hold [content].
  new(super.loc, super.end, this.content);

  /// What the brackets hold: an ID, an address or a list of them.
  final String content;
}

/// `[.dfn]#term#`.
final class Dfn extends Token {
  /// A term defined at [loc].
  new(super.loc, super.end, this.term);

  /// The term.
  final String term;
}

/// An attribute list: positional values and named ones.
final class Attrs {
  /// An attribute list of [positional] and [named] values.
  const new(this.positional, this.named);

  /// The attribute list [s] (`recital`, `part=F, from="2023"`) parsed.
  factory parse(String? s) {
    if (s == null || s.isEmpty) return empty;
    final pos = <String>[];
    final named = <String, String>{};
    for (final part in s.split(',')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final eq = t.indexOf('=');
      if (eq > 0) {
        named[t.substring(0, eq).trim()] = t
            .substring(eq + 1)
            .trim()
            .replaceAll('"', '');
      } else {
        pos.add(t);
      }
    }
    return Attrs(pos, named);
  }

  /// No attributes.
  static const empty = Attrs([], {});

  /// The positional values, in order.
  final List<String> positional;

  /// The named values.
  final Map<String, String> named;
}

/// The kinds of block whose text holds units.
enum BlockKind {
  /// A paragraph.
  paragraph,

  /// A list item.
  item,

  /// A description-list entry.
  dlist,

  /// A verse or literal block.
  verse,
}

/// Something reading a document meets, in reading order.
sealed class Event {
  new(this.loc);

  /// Where it is met.
  final Loc loc;
}

/// A section title.
final class HeadingEvent extends Event {
  /// A heading at [loc] of [depth], with its [title], [marker] and [style].
  new(
    super.loc,
    this.depth,
    this.title,
    this.marker,
    this.style, {
    required this.discrete,
  });

  /// The section depth (`==` is 1).
  final int depth;

  /// Whether the heading is discrete (`[discrete]`).
  final bool discrete;

  /// The title after any marker.
  final String title;

  /// The heading's marker (`== @EXO`), if any.
  final Marker? marker;

  /// The heading's block style, if any.
  final String? style;
}

/// A block of text starts.
final class BlockStart extends Event {
  /// A block of [kind] at [loc] with its [style], [roles] and [id].
  new(super.loc, this.kind, this.style, this.roles, this.id);

  /// The kind of block.
  final BlockKind kind;

  /// The block's style (`verse`, `annotations`), if any.
  final String? style;

  /// The block's roles.
  final List<String> roles;

  /// The block's ID, if any.
  final String? id;

  /// The markers at the very start of the block's text.
  final List<Marker> leading = [];

  /// For a description-list entry: the term.
  String? term;
}

/// A block of text ends.
final class BlockEnd extends Event {
  /// The end of a block at [loc].
  new(super.loc);
}

/// A text line starts (inside a block).
final class LineStart extends Event {
  /// A line of a block of [kind] starts at [loc]; [first] for its first line.
  new(super.loc, this.kind, {this.first = false});

  /// The kind of block the line is in.
  final BlockKind kind;

  /// Whether the line is the block's first.
  final bool first;
}

/// A token met in a line.
final class TokenEvent extends Event {
  /// The [token], met where it starts.
  new(this.token) : super(token.loc);

  /// The token.
  final Token token;
}

/// A whole document read: its files and events in reading order.
final class Document {
  /// The document read from [root] and its [files], with its [events] and
  /// header [attributes].
  new(this.root, this.files, this.events, this.attributes);

  /// The root document's file.
  final SourceFile root;

  /// Every file read, the root first, in reading order.
  final List<SourceFile> files;

  /// Everything met, in reading order.
  final List<Event> events;

  /// The header's attribute entries.
  final Map<String, String> attributes;
}

/// Finds the units syntax in a line: markers, ranges, notes, references by
/// address and defined terms.
final class InlineScanner {
  /// A scanner of the ranges named [rangeNames]; markers are units only when
  /// [active] (a document that names schemes).
  new(Set<String> rangeNames, {required this.active})
    : _open = rangeNames.isEmpty
          ? null
          : RegExp(
              '\\[(${rangeNames.map(RegExp.escape).join('|')})(#[\\w-]+)?((?:\\s+[\\w-]+=[^\\s}\\]]*)*)\\}',
            ),
      _close = rangeNames.isEmpty
          ? null
          : RegExp(
              '\\{(${rangeNames.map(RegExp.escape).join('|')})(#[\\w-]+)?\\]',
            );

  /// Whether markers are units (the document names schemes).
  final bool active;
  final RegExp? _open;
  final RegExp? _close;

  static final _marker = RegExp(
    r'(?<![\p{L}\p{N}_@\\])(@+)(\^\S*|[^\s\[\]@]*)(\[[^\]\n]*\])?(?=\s|$)',
    unicode: true,
  );
  static final _noteStart = RegExp(
    r'(?:note:([A-Za-z][\w-]*)(?:#([\w-]+))?|footnote:)\[',
  );
  static final _xref = RegExp('<<([^<>]+?)>>');
  static final _dfn = RegExp(r'\[\.dfn\]#([^#]+)#');

  /// The tokens in [text] (which starts at column [offset] of its line).
  List<Token> scan(String text, Loc Function(int col) loc, int offset) {
    final tokens = <Token>[];
    // Notes first: their bodies hold references but no other tokens.
    final bodies = <(int, int)>[];
    for (final m in _noteStart.allMatches(text)) {
      if (bodies.any((b) => m.start >= b.$1 && m.start < b.$2)) continue;
      final bodyStart = m.end;
      var depth = 1;
      var j = bodyStart;
      for (; j < text.length; j++) {
        if (text[j] == r'\') {
          j++;
          continue;
        }
        if (text[j] == '[') depth++;
        if (text[j] == ']') {
          depth--;
          if (depth == 0) break;
        }
      }
      if (j >= text.length) continue; // unclosed: not a note
      final body = text.substring(bodyStart, j);
      final children = <Token>[
        for (final x in _xref.allMatches(body))
          Xref(loc(bodyStart + x.start), bodyStart + x.end + offset, x[1]!),
      ];
      // A `##span##` right before is the lemma.
      String? lemma;
      int? lemmaStart;
      if (m.start >= 4 && text.substring(0, m.start).endsWith('##')) {
        final open = text.lastIndexOf('##', m.start - 3);
        if (open >= 0) {
          lemma = text.substring(open + 2, m.start - 2);
          lemmaStart = open + offset;
        }
      }
      tokens.add(
        Note(
          loc(m.start),
          j + 1 + offset,
          m[1] ?? 'footnote',
          body,
          bodyStart + offset,
          children,
          lemma: lemma,
          lemmaStart: lemmaStart,
          id: m[2],
        ),
      );
      bodies.add((m.start, j + 1));
    }
    bool inBody(int i) => bodies.any((b) => i >= b.$1 && i < b.$2);
    if (active) {
      for (final m in _marker.allMatches(text)) {
        if (inBody(m.start)) continue;
        final g = m[2]!;
        final up = m[1]!.length - 1;
        if (up > 0 && g.isNotEmpty) continue; // `@@` takes no label
        // `@^` closes; `@^` with anything after it is not a marker.
        if (g.startsWith('^') && g.length > 1) continue;
        final (op, label) = g.isEmpty
            ? (MarkerOp.step, '')
            : g == '^'
            ? (MarkerOp.close, '')
            : (MarkerOp.label, g);
        final attrs = m[3] == null
            ? Attrs.empty
            : Attrs.parse(m[3]!.substring(1, m[3]!.length - 1));
        tokens.add(
          Marker(loc(m.start), m.end + offset, op, label, attrs, up: up),
        );
      }
    }
    if (_open != null) {
      for (final m in _open.allMatches(text)) {
        if (inBody(m.start)) continue;
        final attrs = <String, String>{
          for (final a in RegExp(
            r'([\w-]+)=([^\s}\]]*)',
          ).allMatches(m[3] ?? ''))
            a[1]!: a[2]!,
        };
        tokens.add(
          RangeOpen(
            loc(m.start),
            m.end + offset,
            m[1]!,
            m[2]?.substring(1),
            attrs,
          ),
        );
      }
      for (final m in _close!.allMatches(text)) {
        if (inBody(m.start)) continue;
        tokens.add(
          RangeClose(loc(m.start), m.end + offset, m[1]!, m[2]?.substring(1)),
        );
      }
    }
    for (final m in _xref.allMatches(text)) {
      if (inBody(m.start)) continue;
      tokens.add(Xref(loc(m.start), m.end + offset, m[1]!));
    }
    for (final m in _dfn.allMatches(text)) {
      if (inBody(m.start)) continue;
      tokens.add(Dfn(loc(m.start), m.end + offset, m[1]!));
    }
    tokens.sort((a, b) => a.loc.column.compareTo(b.loc.column));
    // A note right after a range's close annotates the range.
    for (var k = 1; k < tokens.length; k++) {
      final t = tokens[k];
      final prev = tokens[k - 1];
      if (t is Note && prev is RangeClose && prev.end == t.loc.column) {
        tokens[k] = Note(
          t.loc,
          t.end,
          t.stream,
          t.body,
          t.bodyColumn,
          t.children,
          lemmaRange: prev,
          id: t.id,
        );
      }
    }
    return tokens;
  }
}
