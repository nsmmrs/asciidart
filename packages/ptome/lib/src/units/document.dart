/// Reads a document in the dialect: follows its includes, finds its blocks
/// (headings, paragraphs, list items, description-list entries, verse
/// blocks) and, in their text, the dialect's tokens — unit markers `@…`,
/// ranges `[name}…{name]`, notes `note:stream[…]`, references `<<…>>` and
/// defined terms `[.dfn]#…#`. Everything else is AsciiDoc and passes
/// through untouched.
library;

import 'package:ptome/src/units/files.dart' as p;

/// A source file of the document: the root or one it includes.
final class SourceFile {
  /// The file at [path] with its [lines].
  new(this.path, this.lines);

  /// The file's path.
  final String path;

  /// The file's lines, without terminators.
  final List<String> lines;
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
  String toString() => '${p.basename(file.path)}:${line + 1}:${column + 1}';
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
  });

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

/// `include::#id[]`: a block of this document repeated.
final class IncludeSelf extends Event {
  /// The repeat at [loc] of the block with [id].
  new(super.loc, this.id);

  /// The ID of the block to repeat.
  final String id;
}

/// `include::psalter.adoc[unit=95]`, `include::bible[unit="Ps 23:1-3"]`:
/// a passage of another document (a file, or a work the document cites),
/// by its address, rather than a copy of it; cited as that document cites
/// itself (`cite=STYLE`), or spliced in uncited (`cite=none`).
final class IncludeUnit extends Event {
  /// The include at [loc] of the passage at [address] of [target], cited in
  /// the [cite] style.
  new(super.loc, this.target, this.address, {this.cite});

  /// The document quoted: a path, or a work the document cites.
  final String target;

  /// The passage's address (`Ps 23:1-3`).
  final String address;

  /// The citation style (`bcp`), or `none` to splice the passage in uncited.
  final String? cite;
}

/// A whole document read: its files and events in reading order.
final class Document {
  /// The document read from [root] and its [files], with its [events], header
  /// [attributes] and delimited blocks by ID.
  new(this.root, this.files, this.events, this.attributes, this.blocksById);

  /// The root document's file.
  final SourceFile root;

  /// Every file read, the root first, in reading order.
  final List<SourceFile> files;

  /// Everything met, in reading order.
  final List<Event> events;

  /// The header's attribute entries.
  final Map<String, String> attributes;

  /// Delimited blocks with an ID: their file, first line (with their
  /// attributes) and last line.
  final Map<String, (SourceFile, int, int)> blocksById;
}

final _delimiter = RegExp(
  r'^(-{4,}|\.{4,}|\+{4,}|/{4,}|_{4,}|={4,}|\*{4,}|--|\|===)\s*$',
);
final _heading = RegExp(r'^(=+)\s+(.*)$');
final _attrLine = RegExp(r'^\[(.*)\]\s*$');
final _attrEntry = RegExp(r'^:([\w-]+!?):\s*(.*)$');
final _include = RegExp(r'^include::([^\[]+)\[(.*)\]\s*$');
final _conditional = RegExp('^(ifdef|ifndef|ifeval|endif)::');
final _listItem = RegExp(r'^\s*(\*+|-|\.+|\d+\.|[a-z]\.)\s+\S');
final _dlistItem = RegExp(r'^([^\[<\s][^\[<]*?)::(?:\s+|$)');
final _blockTitle = RegExp(r'^\.[^\s.]');
final _blockMacro = RegExp(r'^[a-z][\w-]*::\S*\[.*\]\s*$');

/// Reads [path] and everything it includes. [rangeNames] are the declared
/// range names; [active] is false when the document declares no scheme
/// (then markers are plain text).
Document readDocument(
  String path, {
  Set<String> rangeNames = const {},
  bool active = true,
  Map<String, List<String>> overrides = const {},
}) {
  final files = <SourceFile>[];
  final events = <Event>[];
  final attributes = <String, String>{};
  final blocksById = <String, (SourceFile, int, int)>{};
  var order = 0;
  final scanner = _InlineScanner(rangeNames, active: active);

  void readFile(String filePath, {required bool isRoot}) {
    // A file's lines as given (layers woven in), else as on disk.
    final file = SourceFile(
      filePath,
      overrides[filePath] ?? p.readLines(filePath),
    );
    files.add(file);
    final lines = file.lines;
    var inHeader = isRoot;
    var headerSeen = false;
    final delims = <String>[];
    String? verbatim; // the delimiter of the verbatim block we are in
    BlockStart? block;
    BlockKind? blockKind;
    // Pending block attributes for the next block.
    String? style;
    var roles = <String>[];
    String? id;
    int? attrStart;
    final idStack = <(String, int, int)>[];
    final enclosing = <List<String>>[]; // the roles of each open delimited block // (id, depth, first line) of delimited blocks being read
    var lineInBlock = 0;

    Loc loc(int line, int col) => Loc(file, line, col, order);

    void endBlock(int line) {
      if (block != null) {
        events.add(BlockEnd(loc(line, 0)));
        block = null;
        blockKind = null;
      }
    }

    void clearPending() {
      style = null;
      roles = [];
      id = null;
      attrStart = null;
    }

    void startBlock(int line, BlockKind kind) {
      // A block inside a delimited one takes its roles too (a paragraph of
      // a note is the note's).
      block = BlockStart(loc(line, 0), kind, style, [
        ...roles,
        for (final r in enclosing) ...r,
      ], id);
      blockKind = kind;
      events.add(block!);
      clearPending();
      lineInBlock = 0;
    }

    void textLine(int i, String text, int offset) {
      final first = lineInBlock == 0;
      events.add(LineStart(loc(i, 0), blockKind!, first: first));
      final tokens = scanner.scan(text, (col) => loc(i, col + offset), offset);
      if (first) {
        // Leading markers: only whitespace and range openers before them.
        var at = 0;
        for (final t in tokens) {
          final gap = text.substring(at, t.loc.column - offset);
          if (gap.trim().isNotEmpty) break;
          if (t is Marker) {
            block!.leading.add(t);
          } else if (t is! RangeOpen) {
            break;
          }
          at = t.end - offset;
        }
      }
      for (final t in tokens) {
        events.add(TokenEvent(t));
      }
      lineInBlock++;
    }

    for (var i = 0; i < lines.length; i++) {
      order++;
      final line = lines[i];
      if (verbatim != null) {
        if (line.trimRight() == verbatim) verbatim = null;
        continue;
      }
      if (inHeader) {
        if (!headerSeen && line.startsWith('= ')) {
          headerSeen = true;
          if (isRoot) attributes['doctitle'] = line.substring(2).trim();
          continue;
        }
        // A header with no title: attribute entries at the top.
        if (!headerSeen && _attrEntry.hasMatch(line)) headerSeen = true;
        if (line.trim().isEmpty) {
          if (headerSeen) inHeader = false;
          continue;
        }
        final m = _attrEntry.firstMatch(line);
        if (m != null) {
          attributes[m[1]!] = m[2]!;
          continue;
        }
        if (line.startsWith('//')) continue;
        if (headerSeen) continue; // author/revision lines
        inHeader = false;
      }
      if (line.trim().isEmpty) {
        if (blockKind != BlockKind.verse) endBlock(i);
        continue;
      }
      if (line.startsWith('//') && !line.startsWith('////')) continue;
      final delim = _delimiter.firstMatch(line);
      if (delim != null) {
        final d = delim[1]!;
        if (delims.isNotEmpty && delims.last == d) {
          // Closing.
          delims.removeLast();
          if (enclosing.isNotEmpty) enclosing.removeLast();
          endBlock(i);
          if (idStack.isNotEmpty && idStack.last.$2 == delims.length) {
            final (bid, _, start) = idStack.removeLast();
            blocksById[bid] = (file, start, i);
          }
          continue;
        }
        endBlock(i);
        if (d.startsWith('-') && d != '--' ||
            d.startsWith('.') ||
            d.startsWith('+') ||
            d.startsWith('/')) {
          if (id != null) blocksById[id!] = (file, attrStart ?? i, -1);
          verbatim = d;
          clearPending();
          continue;
        }
        if (id != null) idStack.add((id!, delims.length, attrStart ?? i));
        delims.add(d);
        enclosing.add([...roles]);
        if (d.startsWith('_') && style == 'verse') {
          startBlock(i + 1, BlockKind.verse);
        } else {
          clearPending();
        }
        continue;
      }
      if (blockKind == BlockKind.verse) {
        textLine(i, line, 0);
        continue;
      }
      if (block == null) {
        final a = _attrLine.firstMatch(line);
        if (a != null && !line.startsWith('[[') ||
            (a != null && RegExp(r'^\[\[[^\]]+\]\]$').hasMatch(line.trim()))) {
          attrStart ??= i;
          final body = a[1]!;
          if (body.startsWith('[') && body.endsWith(']')) {
            id = body.substring(1, body.length - 1).split(',').first;
          } else {
            final attrs = Attrs.parse(body);
            if (attrs.positional.isNotEmpty) {
              var first = attrs.positional.first;
              final idm = RegExp(r'#([\w-]+)').firstMatch(first);
              if (idm != null) id = idm[1];
              final rm = RegExp(r'\.([\w-]+)')
                  .allMatches(first)
                  .map((m) => m[1]!)
                  .toList();
              roles.addAll(rm);
              first = first.replaceAll(RegExp(r'[#.%].*$'), '');
              if (first.isNotEmpty) style = first;
            }
            if (attrs.named['role'] case final r?) roles.addAll(r.split(' '));
            if (attrs.named['id'] case final x?) id = x;
          }
          continue;
        }
        if (_blockTitle.hasMatch(line)) continue;
        final h = _heading.firstMatch(line);
        if (h != null) {
          final depth = h[1]!.length - 1;
          var title = h[2]!;
          Marker? marker;
          final ms = scanner.scan(
            title,
            (col) => loc(i, col + depth + 2),
            depth + 2,
          );
          if (ms.isNotEmpty &&
              ms.first is Marker &&
              ms.first.loc.column == depth + 2) {
            final m0 = ms.first as Marker;
            marker = Marker(
              m0.loc,
              m0.end,
              m0.op,
              m0.label,
              m0.attrs,
              inHeading: true,
              up: m0.up,
            );
            title = title.substring(m0.end - depth - 2).trimLeft();
          }
          events.add(
            HeadingEvent(
              loc(i, 0),
              depth,
              title,
              marker,
              style,
              discrete: style == 'discrete' || style == 'float',
            ),
          );
          for (final t in ms.skip(marker == null ? 0 : 1)) {
            events.add(TokenEvent(t));
          }
          clearPending();
          continue;
        }
        final ae = _attrEntry.firstMatch(line);
        if (ae != null) {
          attributes.putIfAbsent(ae[1]!, () => ae[2]!);
          continue;
        }
        final inc = _include.firstMatch(line);
        if (inc != null) {
          final target = inc[1]!;
          final named = {
            for (final m in RegExp(
              r'([\w-]+)=(?:"([^"]*)"|([^,]*))',
            ).allMatches(inc[2]!))
              m[1]!: (m[2] ?? m[3]!).trim(),
          };
          if (target.startsWith('#')) {
            events.add(IncludeSelf(loc(i, 0), target.substring(1)));
          } else if (named['unit'] case final unit?) {
            events.add(
              IncludeUnit(loc(i, 0), target, unit, cite: named['cite']),
            );
          } else {
            final path = p.normalize(p.join(p.dirname(filePath), target));
            if (p.isFile(path) && path.endsWith('.adoc')) {
              readFile(path, isRoot: false);
            }
          }
          clearPending();
          continue;
        }
        if (_conditional.hasMatch(line)) continue;
        // A block macro (`image::…[]`, `toc::[]`) is not text.
        if (_blockMacro.hasMatch(line)) {
          clearPending();
          continue;
        }
      }
      // List items and description-list entries start new blocks.
      final dl = _dlistItem.firstMatch(line);
      if (dl != null &&
          !line.contains('::[') &&
          blockKind != BlockKind.paragraph) {
        endBlock(i);
        startBlock(i, BlockKind.dlist);
        block!.term = dl[1]!.trim();
        final rest = line.substring(dl.end);
        if (rest.trim().isNotEmpty) textLine(i, rest, dl.end);
        continue;
      }
      if (_listItem.hasMatch(line) &&
          (block == null || blockKind == BlockKind.item)) {
        endBlock(i);
        startBlock(i, BlockKind.item);
        textLine(i, line, 0);
        continue;
      }
      if (block == null) {
        startBlock(i, BlockKind.paragraph);
      }
      textLine(i, line, 0);
    }
    endBlock(lines.length);
  }

  readFile(path, isRoot: true);
  return Document(files.first, files, events, attributes, blocksById);
}

final class _InlineScanner {
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
