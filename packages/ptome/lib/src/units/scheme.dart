/// Address schemes: the levels a text is cited by (book > chapter > verse;
/// section > (a) > (1); daf > segment), each with a label type that parses,
/// orders and steps its labels, and the templates that turn an address
/// into an ID, a reftext or printed text. Schemes, canons, note streams,
/// ranges and term rules are data, declared in TOML files a document names
/// with `:units:`.
library;

import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/presentation.dart';
import 'package:ptome/src/units/scheme_yaml.dart';
import 'package:ptome/src/units/template.dart';

/// One level's label: what a marker or citation writes (`34`, `(a)`, `2b`,
/// `1094a5`, `EXO`), and a key that orders labels of its type.
final class Label {
  /// A label written [text], ordered by [key], with a [part] letter, a [cited]
  /// form and a bridge's [end].
  const new(this.text, this.key, {this.part, this.cited, this.end});

  /// The last label of a bridge (`5` of `4-5`, `23` of `18-23`): the
  /// unit stands for every label from this one to [end].
  final Label? end;

  /// The label as markers write it (`14`, `(a)`, `1.`, `EXO`).
  final String text;

  /// What orders labels of one type (`[14, 1]` for `14a`).
  final List<int> key;

  /// A part letter (`a` of `14a`).
  final String? part;

  /// The label as citations write it, when that differs (`(1)` for a
  /// paragraph markers write `1.`).
  final String? cited;

  /// The key as text, with any part letter: equal for the same unit.
  String get keyText => '${key.join('.')}${part ?? ''}';

  /// Whether [o] names the same unit.
  bool sameAs(Label o) => keyText == o.keyText;

  /// The whole unit, without its part.
  Label get whole => part == null
      ? this
      : Label(text.substring(0, text.length - part!.length), key, cited: cited);

  /// The label stepping goes on from (a bridge's end).
  Label get last => end ?? this;

  /// Orders this label before (negative) or after (positive) [o].
  int compareTo(Label o) {
    for (var i = 0; i < key.length && i < o.key.length; i++) {
      final c = key[i].compareTo(o.key[i]);
      if (c != 0) return c;
    }
    final c = key.length.compareTo(o.key.length);
    if (c != 0) return c;
    return (part ?? '').compareTo(o.part ?? '');
  }

  @override
  String toString() => text;
}

/// How a level's labels are written, ordered and stepped.
sealed class LabelType {
  const new();

  /// The label of this type at [pos] in [s] (the text inside any wrapper),
  /// and where it ends.
  (Label, int)? matchAt(String s, int pos);

  /// The first label, if the type has a natural one.
  Label? get first;

  /// The label after [label], if the type can step.
  Label? next(Label label);

  /// Every label that may come after [label] (a short page ends early:
  /// 3a may follow 2d); [next] is the first.
  List<Label> successors(Label label) => [?next(label)];
}

/// Numbers (`1`, `14`), with insertion letters (`552a`) or decimals
/// (`123.1`) where a level has them.
final class IntType extends LabelType {
  /// Numbers with [insert] letters, marked at every [every]th.
  const new({this.insert, this.every = 1});

  /// Numbers marked only at every [every]th (an edition's margin: 1, 5,
  /// 10, 15…): the next after n is the next multiple.
  final int every;

  /// Insertion letters after the number: `a` or `A` for one (`552a`,
  /// `1A`), `uk` for the UK's (`3ZA` before `3A`, `1AA` after it).
  final String? insert;

  static final _digits = RegExp(r'\d+');
  static final _ukInsert = RegExp('[A-Z]{1,3}');

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = _digits.matchAsPrefix(s, pos);
    if (m == null) return null;
    final n = int.parse(m[0]!);
    var end = m.end;
    var key = [n, 0];
    if (insert == 'decimal') {
      // Lines an edition inserts between two others: 123.1, 123.2.
      final d = RegExp(r'\.(\d+)').matchAsPrefix(s, end);
      if (d != null) {
        key = [n, int.parse(d[1]!)];
        end = d.end;
      }
    } else if (insert == 'uk') {
      final l = _ukInsert.matchAsPrefix(s, end);
      if (l != null) {
        key = [n, ...ukInsertKey(l[0]!)];
        end = l.end;
      }
    } else if (insert != null && end < s.length) {
      final c = s[end];
      final isLetter = insert == 'a'
          ? RegExp('[a-z]').hasMatch(c)
          : RegExp('[A-Z]').hasMatch(c);
      // An insertion letter is not followed by another letter.
      if (isLetter &&
          (end + 1 >= s.length || !RegExp('[A-Za-z]').hasMatch(s[end + 1]))) {
        key = [n, c.toLowerCase().codeUnitAt(0) - 96];
        end++;
      }
    }
    return (Label(s.substring(pos, end), key), end);
  }

  @override
  Label get first => const Label('1', [1, 0]);

  @override
  Label next(Label label) {
    final n = every > 1
        ? (label.key[0] ~/ every + 1) * every
        : label.key[0] + 1;
    return Label('$n', [n, 0]);
  }
}

/// UK insertion letters in order: Z sorts first (`3ZA` comes before `3A`),
/// then A–Y.
List<int> ukInsertKey(String letters) => [
  for (final c in letters.toUpperCase().codeUnits)
    if (c == 90) 0 else c - 64,
];

/// a…z, then aa, bb… (as US statutes number subsections past z); with
/// [doubled], aa, bb… only (as they number items).
final class AlphaType extends LabelType {
  /// Letters of the given case, [doubled] or with UK [insert] letters.
  const new({this.upper = false, this.doubled = false, this.insert = false});

  /// Capital letters.
  final bool upper;

  /// Doubled letters only (`aa`, `bb`).
  final bool doubled;

  /// A letter and the UK's insertion letters (`ba` between `b` and `c`).
  final bool insert;

  RegExp get _re => upper ? RegExp('[A-Z]+') : RegExp('[a-z]+');

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = _re.matchAsPrefix(s, pos);
    if (m == null) return null;
    final t = m[0]!;
    if (insert) {
      if (t.length > 3) return null;
      final base = t.toLowerCase().codeUnitAt(0) - 96;
      return (
        Label(t, [base, if (t.length > 1) ...ukInsertKey(t.substring(1))]),
        m.end,
      );
    }
    if (t.split('').toSet().length != 1) return null;
    if (doubled && t.length != 2) return null;
    final index = doubled
        ? t.toLowerCase().codeUnitAt(0) - 96
        : (t.length - 1) * 26 + t.toLowerCase().codeUnitAt(0) - 96;
    return (Label(t, [index]), m.end);
  }

  @override
  Label get first =>
      Label(doubled ? (upper ? 'AA' : 'aa') : (upper ? 'A' : 'a'), const [1]);

  @override
  Label next(Label label) {
    final i = label.key[0];
    final letter = String.fromCharCode(96 + i % 26 + 1);
    final t = doubled ? letter * 2 : letter * (i ~/ 26 + 1);
    return Label(upper ? t.toUpperCase() : t, [i + 1]);
  }
}

/// Roman numerals.
final class RomanType extends LabelType {
  /// Roman numerals in capitals when [upper].
  const new({this.upper = false});

  /// Capitals (`XIV`) rather than small letters (`xiv`).
  final bool upper;

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = (upper ? RegExp('[IVXLCDM]+') : RegExp('[ivxlcdm]+'))
        .matchAsPrefix(s, pos);
    if (m == null) return null;
    final n = fromRoman(m[0]!);
    if (n == 0) return null;
    return (Label(m[0]!, [n]), m.end);
  }

  @override
  Label get first => Label(upper ? 'I' : 'i', const [1]);

  @override
  Label next(Label label) {
    final r = toRoman(label.key[0] + 1);
    return Label(upper ? r : r.toLowerCase(), [label.key[0] + 1]);
  }
}

/// A daf and its side: 2a, 2b, 3a… (the Talmud starts at 2a).
final class TalmudType extends LabelType {
  /// The Talmud's daf type.
  const new();

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = RegExp(r'(\d+)([ab])').matchAsPrefix(s, pos);
    if (m == null) return null;
    return (Label(m[0]!, [int.parse(m[1]!), if (m[2] == 'a') 0 else 1]), m.end);
  }

  @override
  Label get first => const Label('2a', [2, 0]);

  @override
  Label next(Label l) => l.key[1] == 0
      ? Label('${l.key[0]}b', [l.key[0], 1])
      : Label('${l.key[0] + 1}a', [l.key[0] + 1, 0]);
}

/// A leaf or page and its side or column: 1094a, 1094b, 1095a (Bekker's
/// pages and columns; a Talmud's daf without its fixed start).
final class FolioType extends LabelType {
  /// The folio type.
  const new();

  @override
  (Label, int)? matchAt(String s, int pos) =>
      const TalmudType().matchAt(s, pos);

  @override
  Label? get first => null;

  @override
  Label next(Label l) => const TalmudType().next(l);
}

/// A page and its section, a–e (Stephanus: 2a, 327c).
final class StephanusType extends LabelType {
  /// The Stephanus type.
  const new();

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = RegExp(r'(\d+)([a-e])').matchAsPrefix(s, pos);
    if (m == null) return null;
    return (Label(m[0]!, [int.parse(m[1]!), m[2]!.codeUnitAt(0) - 97]), m.end);
  }

  @override
  Label? get first => null;

  @override
  Label next(Label l) => l.key[1] < 4
      ? Label('${l.key[0]}${String.fromCharCode(98 + l.key[1])}', [
          l.key[0],
          l.key[1] + 1,
        ])
      : Label('${l.key[0] + 1}a', [l.key[0] + 1, 0]);

  @override
  List<Label> successors(Label label) => [
    next(label),
    if (label.key[1] < 4) Label('${label.key[0] + 1}a', [label.key[0] + 1, 0]),
  ];
}

/// A page, its column and a line (Bekker: 1094a1); the line may be left
/// out (1094a).
final class BekkerType extends LabelType {
  /// The Bekker type.
  const new();

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = RegExp(r'(\d+)([ab])(\d+)?').matchAsPrefix(s, pos);
    if (m == null) return null;
    return (
      Label(m[0]!, [
        int.parse(m[1]!),
        if (m[2] == 'a') 0 else 1,
        int.tryParse(m[3] ?? '') ?? 0,
      ]),
      m.end,
    );
  }

  @override
  Label? get first => null;

  @override
  Label? next(Label label) => null;
}

/// One of a fixed list (`Q.`, `A.`).
final class EnumType extends LabelType {
  /// One of [values], in order.
  const new(this.values);

  /// The values, in order.
  final List<String> values;

  @override
  (Label, int)? matchAt(String s, int pos) {
    for (final (i, v) in values.indexed) {
      if (s.startsWith(v, pos)) return (Label(v, [i + 1]), pos + v.length);
    }
    return null;
  }

  @override
  Label get first => Label(values.first, const [1]);

  @override
  Label? next(Label l) =>
      l.key[0] < values.length ? Label(values[l.key[0]], [l.key[0] + 1]) : null;
}

/// A book of a canon: markers write its code (`EXO`), citations any of its
/// names (`Exod`, `Exodus`, `Ex`).
final class CodeType extends LabelType {
  /// Books of [canon].
  new(this.canon);

  /// The canon whose books are the labels.
  final Canon canon;

  @override
  (Label, int)? matchAt(String s, int pos) {
    // The longest name that ends at a non-letter.
    CanonBook? best;
    var bestEnd = -1;
    for (final MapEntry(key: name, value: book) in canon.byName.entries) {
      if (!s.startsWith(name, pos)) continue;
      final end = pos + name.length;
      if (end < s.length &&
          RegExp('[A-Za-z0-9]').hasMatch(s[end]) &&
          RegExp('[A-Za-z]').hasMatch(name[name.length - 1])) {
        continue;
      }
      if (end > bestEnd) {
        best = book;
        bestEnd = end;
      }
    }
    if (best == null) return null;
    return (Label(best.code, [best.index]), bestEnd);
  }

  @override
  Label get first => Label(canon.books.first.code, const [0]);

  @override
  Label? next(Label l) => l.key[0] + 1 < canon.books.length
      ? Label(canon.books[l.key[0] + 1].code, [l.key[0] + 1])
      : null;
}

/// One of several types (`(a)` or `(1)`: an EU act's points are lettered,
/// its definitions numbered); a label steps within its own type.
final class UnionType extends LabelType {
  /// One of [types], tried in order.
  const new(this.types);

  /// The types, in order.
  final List<LabelType> types;

  @override
  (Label, int)? matchAt(String s, int pos) {
    for (final (i, t) in types.indexed) {
      final m = t.matchAt(s, pos);
      if (m != null) return (Label(m.$1.text, [i, ...m.$1.key]), m.$2);
    }
    return null;
  }

  @override
  Label? get first => switch (types.first.first) {
    null => null,
    final f => Label(f.text, [0, ...f.key]),
  };

  @override
  Label? next(Label label) {
    final i = label.key.first;
    final n = types[i].next(Label(label.text, label.key.sublist(1)));
    return n == null ? null : Label(n.text, [i, ...n.key]);
  }
}

/// A label written as is (`basic.def`): no order, no stepping.
final class NameType extends LabelType {
  /// The name type.
  const new();

  @override
  (Label, int)? matchAt(String s, int pos) {
    final m = RegExp(r'[A-Za-z][\w.]*\w').matchAsPrefix(s, pos);
    if (m == null) return null;
    return (Label(m[0]!, [m[0]!.hashCode]), m.end);
  }

  @override
  Label? get first => null;

  @override
  Label? next(Label label) => null;
}

/// How a marker of a level lays out: inside the text (`none`), starting a
/// line (`line`), starting a block (`block`), or as a section heading.
enum Break {
  /// A milestone inside the text.
  none,

  /// A line of its own (verse drama, the Psalter).
  line,

  /// A block of its own (law, stanzas).
  block,

  /// A section heading.
  heading,
}

/// What advances a level with no marker: nothing, every block, every
/// paragraph, every list item.
enum Auto {
  /// Only markers advance it.
  never,

  /// Every block.
  block,

  /// Every paragraph.
  paragraph,

  /// Every list item.
  item,
}

/// A level of a scheme: book, chapter, verse; section, (a), (1).
final class Level {
  /// A level named [name] with labels of [type] laid out by [breakMode].
  new({
    required this.name,
    required this.type,
    required this.breakMode,
    this.heading,
    this.sep = '',
    this.wrap = ('', ''),
    this.citeWrap,
    this.citeRangeWrap,
    this.stepping = true,
    this.auto = Auto.never,
    this.hidden = false,
    this.zero = false,
    this.parts = false,
    this.bridges = false,
    this.isDefault = false,
    this.gaps = false,
    this.templates = const {},
    LevelLook? look,
  }) : look = look ?? LevelLook(const SchemeMap({}));

  /// How the level's units look (scheme format v2).
  LevelLook look;

  /// Labels may skip ahead without a warning (a statute's repealed
  /// provisions leave gaps).
  final bool gaps;

  /// The level's name (`verse`), as templates and citations write it.
  final String name;

  /// How the level's labels are written, ordered and stepped.
  final LabelType type;

  /// How a marker of this level lays out.
  final Break breakMode;

  /// The section depth this level's headings have (`==` is 1).
  final int? heading;

  /// What comes before this level's label in a citation (`:` before a
  /// verse, ` ` before a chapter, nothing before `(a)`).
  final String sep;

  /// What surrounds a label in markers (`(`, `)` for `(a)`; ``, `.` for
  /// `1.`), and in citations if [citeWrap] differs (`(1)` for `1.`).
  final (String, String) wrap;

  /// What surrounds a label in citations, when it differs from [wrap].
  final (String, String)? citeWrap;

  /// How a range of this level's units is cited, when [citeWrap] names
  /// one unit with a word: `Articles %` for `Articles 6–7`.
  final (String, String)? citeRangeWrap;

  /// Whether a bare marker may step this level.
  final bool stepping;

  /// What advances the level with no marker.
  final Auto auto;

  /// Not printed or cited (the EU's subparagraphs: addressed by ordinal).
  final bool hidden;

  /// Text before the first marker under a parent is unit 0 (Psalm titles).
  final bool zero;

  /// Part letters allowed (`14a`, `14b`).
  final bool parts;

  /// Bridges allowed (`4-5`).
  final bool bridges;

  /// The level a bare `@` steps.
  final bool isDefault;

  /// `id`, `reftext`, `lower`, `heading`… by name.
  final Map<String, String> templates;

  /// The scheme the level belongs to.
  late final Scheme scheme;

  /// The level's depth in its scheme (0 for the outermost).
  late final int depth;

  /// What surrounds a label in citations.
  (String, String) get cited => citeWrap ?? wrap;

  /// A label of this level at [pos] in [s], in marker or citation form.
  (Label, int)? matchAt(String s, int pos, {bool cite = false}) {
    final forms = cite ? {cited, wrap} : {wrap};
    for (final (open, close) in forms) {
      if (!s.startsWith(open, pos)) continue;
      final inner = type.matchAt(s, pos + open.length);
      if (inner == null) continue;
      var (label, end) = inner;
      String? part;
      if (parts &&
          end < s.length &&
          RegExp('[a-z]').hasMatch(s[end]) &&
          (end + 1 >= s.length || !RegExp('[A-Za-z]').hasMatch(s[end + 1]))) {
        part = s[end];
        end++;
      }
      if (!s.startsWith(close, end)) continue;
      end += close.length;
      final core = label.text + (part ?? '');
      // A bridge: `4-5`, `18-23`.
      Label? last;
      var text = core;
      if (bridges && end < s.length && '-–'.contains(s[end])) {
        final m2 = matchAt(s, end + 1, cite: cite);
        if (m2 != null &&
            m2.$1.end == null &&
            m2.$1.compareTo(Label(core, label.key)) > 0) {
          last = m2.$1;
          text = '$core${s[end]}${bare(last)}';
          end = m2.$2;
        }
      }
      return (
        Label(
          '${wrap.$1}$text${wrap.$2}',
          label.key,
          part: part,
          cited: '${cited.$1}$text${cited.$2}',
          end: last,
        ),
        end,
      );
    }
    return null;
  }

  /// [inner] (a label without its wrapper) wrapped as this level writes it.
  Label wrapLabel(Label inner) => Label(
    '${wrap.$1}${inner.text}${wrap.$2}',
    inner.key,
    part: inner.part,
    cited: '${cited.$1}${inner.text}${cited.$2}',
  );

  /// The level's first label, if its type has a natural one.
  Label? get first => switch (type.first) {
    null => null,
    final f => wrapLabel(f),
  };

  /// The label after [l], if the type can step.
  Label? next(Label l) {
    final from = l.last;
    final inner = type.next(Label(_unwrap(from.whole.text), from.key));
    return inner == null ? null : wrapLabel(inner);
  }

  /// Every label that may come after [l]; [next] is the first.
  List<Label> successors(Label l) {
    final from = l.last;
    return [
      for (final s in type.successors(
        Label(_unwrap(from.whole.text), from.key),
      ))
        wrapLabel(s),
    ];
  }

  String _unwrap(String t) {
    var s = t;
    if (wrap.$1.isNotEmpty && s.startsWith(wrap.$1)) {
      s = s.substring(wrap.$1.length);
    }
    if (wrap.$2.isNotEmpty && s.endsWith(wrap.$2)) {
      s = s.substring(0, s.length - wrap.$2.length);
    }
    return s;
  }

  /// The label's text without its wrapper (`a` for `(a)`).
  String bare(Label l) => _unwrap(l.text);

  @override
  String toString() => '${scheme.name}.$name';
}

/// An address scheme: its levels, outermost first.
final class Scheme {
  /// The scheme [name] with [levels], cited by [citeTemplate].
  new(
    this.name,
    this.levels, {
    this.citeTemplate,
    this.works = const [],
    this.absolute = false,
  }) {
    for (final (i, l) in levels.indexed) {
      l
        ..scheme = this
        ..depth = i;
    }
  }

  /// The scheme's name (`bible`).
  final String name;

  /// The scheme's levels, outermost first.
  final List<Level> levels;

  /// How a full citation of a unit is printed
  /// (`{{book.abbr}} {{chapter}}:{{verse}}`).
  final String? citeTemplate;

  /// Names citations use for this document as a work (`Euthyphro`, `5 U.S.C.`).
  final List<String> works;

  /// Labels with several levels name them from the top (`1.30.0` is
  /// part, section, segment), as SuttaCentral's segment IDs do.
  final bool absolute;

  /// The level a bare `@` steps, if the scheme has one.
  Level? get defaultLevel {
    for (final l in levels) {
      if (l.isDefault) return l;
    }
    return null;
  }

  /// The level named [name], if any.
  Level? level(String name) {
    for (final l in levels) {
      if (l.name == name) return l;
    }
    return null;
  }
}

/// A book of a canon.
final class CanonBook {
  /// A book at [index] with its [code], [name], [abbr] and other [names].
  new({
    required this.index,
    required this.code,
    required this.name,
    required this.abbr,
    required this.names,
    this.chapterLabel = 'Chapter',
    this.fields = const {},
  });

  /// The book's place in the canon (0-based).
  final int index;

  /// The code markers write (`EXO`).
  final String code;

  /// The book's name (`Exodus`).
  final String name;

  /// The abbreviation citations print (`Exod`).
  final String abbr;

  /// Every name citations may use (with [code], [name] and [abbr]).
  final List<String> names;

  /// What a chapter of the book is called (`Psalm` in the Psalms).
  final String chapterLabel;

  /// Anything else the canon file gives (`osis`, `testament`, `file`).
  final Map<String, String> fields;

  /// The book as a template value: its code, with its fields.
  TRecord get value => TRecord({
    'code': TText(code),
    'name': TText(name),
    'abbr': TText(abbr),
    'chapter-label': TText(chapterLabel),
    for (final MapEntry(:key, :value) in fields.entries) key: TText(value),
  }, text: code);
}

/// A canon: its books in order, and every name citations may use.
final class Canon {
  /// A canon of [books].
  new(this.books)
    : byName = {
        for (final b in books)
          for (final n in {b.code, b.name, b.abbr, ...b.names}) n: b,
      },
      byCode = {for (final b in books) b.code: b};

  /// The books, in order.
  final List<CanonBook> books;

  /// Each book by every name citations may use.
  final Map<String, CanonBook> byName;

  /// Each book by its code.
  final Map<String, CanonBook> byCode;
}

/// Where a note stream's notes go when lowered: at the foot of the page
/// (`footnote:`), or gathered into an entry after the unit's marker (a
/// reference Bible's center column).
/// Where a note stream's notes go when lowered: at the foot of the page
/// (`footnote:`), gathered after the unit's marker (`entry`: a reference
/// Bible's center column), or after the unit's end (`end`: a catechism's
/// proof texts).
enum Placement {
  /// At the foot of the page.
  footnote,

  /// Gathered after the unit's marker.
  entry,

  /// After the unit's end.
  end,
}

/// A note stream: its callers, when they restart, and where its notes go.
final class NoteStream {
  /// A stream named [name] with [caller]s restarting at [reset] and its notes
  /// placed at [placement].
  new({
    required this.name,
    this.caller = '',
    this.reset,
    this.placement = Placement.footnote,
    this.templates = const {},
    StreamLook? look,
  }) : look = look ?? StreamLook(const SchemeMap({}));

  /// How the stream's notes look (scheme format v2).
  final StreamLook look;

  /// The stream's name, as `note:NAME[…]` writes it.
  final String name;

  /// The first caller (`a`, `1`, `F1`, `*`) or nothing.
  final String caller;

  /// The level whose units restart the callers (null: never).
  final String? reset;

  /// Where the stream's notes go.
  final Placement placement;

  /// The stream's templates (`mark`, `origin`, `entry`, `lower`).
  final Map<String, String> templates;

  /// The [n]th caller (0-based).
  String callerAt(int n) {
    if (caller.isEmpty) return '';
    final m = RegExp(r'^(\D*)(\d+)$').firstMatch(caller);
    if (m != null) return '${m[1]}${int.parse(m[2]!) + n}';
    if (RegExp(r'^[a-z]$').hasMatch(caller)) {
      const letters = 'abcdefghijklmnopqrstuvwxyz';
      final i = letters.indexOf(caller) + n;
      return i < 26 ? letters[i] : letters[i % 26] * (i ~/ 26 + 1);
    }
    return caller;
  }
}

/// A kind of range, as a scheme declares it.
final class RangeKind {
  /// A range kind named [name], set with [role].
  new(this.name, {this.role, this.templates = const {}});

  /// The range's name, as `[name}` writes it.
  final String name;

  /// The role of the text the range spans, if any.
  final String? role;

  /// The range's templates.
  final Map<String, String> templates;
}

/// Text a pattern finds gets a role (and a filter on its text): `LORD`
/// in capitals is the divine name, in small capitals as `Lord`.
final class TermRule {
  /// A rule named [name]: text [pattern] finds gets [role], and [transform].
  new(this.name, this.pattern, this.role, {this.transform});

  /// The rule's name.
  final String name;

  /// What the rule finds.
  final RegExp pattern;

  /// The role the text found gets.
  final String role;

  /// A filter applied to the text found (`titlecase`), if any.
  final String? transform;
}

/// Everything a document's `:units:` files declare.
final class Config {
  /// The declarations of a document's scheme files.
  new({
    required this.schemes,
    required this.streams,
    required this.ranges,
    required this.termRules,
    this.canon,
    this.versification,
    this.settings = const {},
    this.citations = const {},
  });

  /// A config that declares nothing.
  factory empty() => Config(
    schemes: const [],
    streams: const {},
    ranges: const {},
    termRules: const [],
  );

  /// The config the [names] files in [dir] declare (later files add to
  /// and override earlier ones).
  factory load(List<String> names, String dir) {
    final tables = <SchemeMap>[];
    for (final name in names) {
      final file = p.join(dir, _yamlName(name));
      if (!p.isFile(file)) {
        throw UnitsException('scheme file not found: $file');
      }
      tables.add(readSchemeFile(file));
    }
    Canon? canon;
    Versification? versification;
    final settings = <String, String>{};
    for (final t in tables) {
      if (t.string('canon') case final name?) {
        canon = _loadCanon(p.join(dir, _yamlName(name)));
      }
      if (t.string('versification') case final name?) {
        versification = Versification.load(p.join(dir, name));
      }
      for (final MapEntry(:key, :value)
          in t.map('settings')?.entries.entries ??
              const <MapEntry<String, SchemeNode>>[]) {
        if (value.text case final text?) settings[key] = text;
      }
    }
    // Level settings later files change:
    // `level: {bekker: {line: {every: 20}}}`.
    final overrides = <String, SchemeMap>{};
    for (final t in tables) {
      for (final (scheme, levels)
          in t.map('level')?.maps ?? const <(String, SchemeMap)>[]) {
        for (final (level, settings) in levels.maps) {
          final key = '$scheme.$level';
          overrides[key] = (overrides[key] ?? const SchemeMap({})).merged(
            settings,
          );
        }
      }
    }
    final schemes = <String, Scheme>{};
    final streams = <String, NoteStream>{};
    final ranges = <String, RangeKind>{};
    final rules = <TermRule>[];
    for (final t in tables) {
      for (final (name, m)
          in t.map('scheme')?.maps ?? const <(String, SchemeMap)>[]) {
        schemes[name] = _scheme(name, m, canon, overrides);
      }
      for (final (name, m)
          in t.map('stream')?.maps ?? const <(String, SchemeMap)>[]) {
        streams[name] = NoteStream(
          name: name,
          caller: m.string('caller') ?? '',
          reset: m.string('reset'),
          placement: Placement.values.byName(
            m.string('placement') ?? 'footnote',
          ),
          templates: m.templates,
          look: StreamLook(m),
        );
      }
      for (final (name, m)
          in t.map('range')?.maps ?? const <(String, SchemeMap)>[]) {
        ranges[name] = RangeKind(
          name,
          role: m.string('role'),
          templates: m.templates,
        );
      }
      for (final (name, m)
          in t.map('term')?.maps ?? const <(String, SchemeMap)>[]) {
        rules.add(
          TermRule(
            name,
            RegExp(
              m.string('pattern') ??
                  (throw FormatException('term $name: no pattern')),
            ),
            m.string('role') ?? (throw FormatException('term $name: no role')),
            transform: m.string('transform'),
          ),
        );
      }
    }
    // Templates later files add to a scheme's levels:
    // `templates: {bible: {verse: {lower: "…"}}}`.
    for (final t in tables) {
      for (final (sname, levels)
          in t.map('templates')?.maps ?? const <(String, SchemeMap)>[]) {
        final scheme = schemes[sname];
        if (scheme == null) {
          throw FormatException('templates for unknown scheme $sname');
        }
        for (final (lname, m) in levels.maps) {
          final level =
              scheme.level(lname) ??
              (throw FormatException(
                'templates for unknown level $sname.$lname',
              ));
          level.templates.addAll(m.templates);
        }
      }
      // And how they look (v2): `level-presentation: {bible: {verse: …}}`.
      for (final (sname, levels)
          in t.map('level-presentation')?.maps ??
              const <(String, SchemeMap)>[]) {
        final scheme =
            schemes[sname] ??
            (throw FormatException('presentation for unknown scheme $sname'));
        for (final (lname, m) in levels.maps) {
          final level =
              scheme.level(lname) ??
              (throw FormatException(
                'presentation for unknown level $sname.$lname',
              ));
          level
            ..look = level.look.merged(m)
            ..templates.addAll(m.templates);
        }
      }
    }
    final citations = <String, Map<String, String>>{};
    for (final t in tables) {
      for (final (name, m)
          in t.map('citation')?.maps ?? const <(String, SchemeMap)>[]) {
        (citations[name] ??= {}).addAll(m.templates);
      }
    }
    return Config(
      citations: citations,
      schemes: schemes.values.toList(),
      streams: streams,
      ranges: ranges,
      termRules: rules,
      canon: canon,
      versification: versification,
      settings: settings,
    );
  }

  /// How a passage of a document in these schemes is cited when another
  /// document quotes it, by style name (`default`, `bcp`): `attribution`,
  /// `title` and `block` templates.
  final Map<String, Map<String, String>> citations;

  /// The schemes, the primary first.
  final List<Scheme> schemes;

  /// The note streams by name.
  final Map<String, NoteStream> streams;

  /// The range kinds by name.
  final Map<String, RangeKind> ranges;

  /// The term rules, in order.
  final List<TermRule> termRules;

  /// The canon the schemes' book labels come from, if any.
  final Canon? canon;

  /// The versification an edition follows, if any.
  final Versification? versification;

  /// Other top-level settings (`dialogue = true`).
  final Map<String, String> settings;

  /// The scheme named [name], if any.
  Scheme? scheme(String name) {
    for (final s in schemes) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// The primary scheme: the first declared.
  Scheme? get primary => schemes.isEmpty ? null : schemes.first;
}

/// A scheme file's name with its extension (`bible` is `bible.yml`).
String _yamlName(String name) =>
    name.endsWith('.yml') || name.endsWith('.yaml') ? name : '$name.yml';

/// A problem with a document's scheme files.
final class UnitsException implements Exception {
  /// A problem with scheme files, described by [message].
  new(this.message);

  /// What is wrong.
  final String message;
  @override
  String toString() => message;
}

Scheme _scheme(
  String name,
  SchemeMap m,
  Canon? canon,
  Map<String, SchemeMap> overrides,
) {
  final levels = <Level>[];
  for (final raw in m.list('level')) {
    if (raw is! SchemeMap) {
      throw FormatException('scheme $name: a level is a mapping');
    }
    final l = raw.merged(overrides['$name.${raw.string('name')}']);
    final typeName = l.string('type') ?? 'int';
    LabelType typeOf(String typeName) => switch (typeName) {
      'int' => IntType(
        insert: l.string('insert'),
        every: l.integer('every') ?? 1,
      ),
      'alpha' => const AlphaType(),
      'alpha2' => const AlphaType(doubled: true),
      'alpha-uk' => const AlphaType(insert: true),
      'ALPHA' => const AlphaType(upper: true),
      'roman' => const RomanType(),
      'ROMAN' => const RomanType(upper: true),
      'talmud' => const TalmudType(),
      'stephanus' => const StephanusType(),
      'folio' => const FolioType(),
      'bekker' => const BekkerType(),
      'enum' => EnumType(l.strings('values')),
      'code' => CodeType(
        canon ?? (throw StateError('scheme $name: type code needs a canon')),
      ),
      'name' => const NameType(),
      _ when typeName.contains('|') => UnionType([
        for (final t in typeName.split('|')) typeOf(t),
      ]),
      _ => throw FormatException('scheme $name: unknown label type $typeName'),
    };
    final type = typeOf(typeName);
    (String, String) wrapOf(String? w) {
      if (w == null || w.isEmpty) return ('', '');
      final i = w.indexOf('%');
      return (w.substring(0, i), w.substring(i + 1));
    }

    levels.add(
      Level(
        name:
            l.string('name') ??
            (throw FormatException('scheme $name: a level has no name')),
        type: type,
        breakMode: Break.values.byName(l.string('break') ?? 'none'),
        heading: l.integer('depth'),
        sep: l.string('sep') ?? '',
        wrap: wrapOf(l.string('wrap')),
        citeWrap: l.string('cite-wrap') == null
            ? null
            : wrapOf(l.string('cite-wrap')),
        citeRangeWrap: l.string('cite-range-wrap') == null
            ? null
            : wrapOf(l.string('cite-range-wrap')),
        stepping: l.flag('stepping') ?? true,
        auto: Auto.values.byName(l.string('auto') ?? 'never'),
        hidden: l.flag('hidden') ?? false,
        zero: l.flag('zero') ?? false,
        parts: l.flag('parts') ?? false,
        bridges: l.flag('bridges') ?? false,
        isDefault: l.flag('default') ?? false,
        gaps: l.flag('gaps') ?? false,
        templates: {...l.templates},
        look: LevelLook(l),
      ),
    );
  }
  return Scheme(
    name,
    levels,
    citeTemplate: m.string('cite'),
    absolute: m.flag('absolute') ?? false,
    works: m.strings('works'),
  );
}

Canon _loadCanon(String path) {
  final m = readSchemeFile(path);
  final books = <CanonBook>[];
  for (final (i, raw) in m.list('book').indexed) {
    if (raw is! SchemeMap) throw FormatException('$path: a book is a mapping');
    final name =
        raw.string('name') ??
        (throw FormatException('$path: book $i has no name'));
    books.add(
      CanonBook(
        index: i,
        code:
            raw.string('code') ??
            (throw FormatException('$path: book $i has no code')),
        name: name,
        abbr: raw.string('abbr') ?? name,
        names: raw.strings('names'),
        chapterLabel: raw.string('chapter-label') ?? 'Chapter',
        fields: {
          for (final MapEntry(:key, :value) in raw.templates.entries)
            if (!const {'code', 'name', 'abbr', 'chapter-label'}.contains(key))
              key: value,
        },
      ),
    );
  }
  return Canon(books);
}

/// A versification: how many verses each chapter has and which verses an
/// edition leaves out (the Copenhagen Alliance's `maxVerses` and
/// `excludedVerses`).
final class Versification {
  /// A versification with [maxVerses] per chapter and [excluded] verses.
  new(this.maxVerses, this.excluded);

  /// The versification in the Copenhagen Alliance JSON file at [path].
  factory load(String path) {
    final text = p.readText(path);
    final max = <String, int>{};
    final excluded = <String>{};
    // The Copenhagen JSON: {"maxVerses": {"GEN": ["31", "25", …]},
    // "excludedVerses": ["ACT 8:37"]}.
    for (final m in RegExp(
      r'"([1-4A-Z]{3})"\s*:\s*\[([^\]]*)\]',
    ).allMatches(text)) {
      final counts = RegExp(r'"(\d+)"')
          .allMatches(m[2]!)
          .map((x) => int.parse(x[1]!))
          .toList();
      for (final (i, n) in counts.indexed) {
        max['${m[1]} ${i + 1}'] = n;
      }
    }
    final ex = RegExp(r'"excludedVerses"\s*:\s*\[([^\]]*)\]').firstMatch(text);
    if (ex != null) {
      for (final v in RegExp('"([^"]+)"').allMatches(ex[1]!)) {
        excluded.add(v[1]!);
      }
    }
    return Versification(max, excluded);
  }

  /// `GEN 1` → 31.
  final Map<String, int> maxVerses;

  /// `ACT 8:37`.
  final Set<String> excluded;
}
