/// The generator's document model: what a generated document contains,
/// before it is written out as AsciiDoc (`serialize.dart`). Mutators work
/// on this tree, so changes stay structural.
library;

/// A generated document.
final class Doc {
  Doc({
    this.header,
    List<Block>? blocks,
    this.lineEnding = '\n',
    this.bom = false,
  }) : blocks = blocks ?? [];

  Header? header;
  final List<Block> blocks;

  /// `\n`, `\r\n` (or a mix, when a pathology asks for one).
  String lineEnding;
  bool bom;
}

final class Header {
  Header({
    required this.title,
    this.authors = const [],
    this.revision,
    List<AttributeEntry>? attributes,
  }) : attributes = attributes ?? [];

  List<Inline> title;
  List<String> authors;
  String? revision;
  final List<AttributeEntry> attributes;
}

/// Block attributes and metadata that may precede any block.
final class Meta {
  Meta({
    this.id,
    this.title,
    this.style,
    this.roles = const [],
    this.options = const [],
    this.named = const {},
    this.reftext,
  });

  String? id;
  List<Inline>? title;
  String? style;
  List<String> roles;
  List<String> options;
  Map<String, String> named;
  String? reftext;

  bool get isEmpty =>
      id == null &&
      title == null &&
      style == null &&
      roles.isEmpty &&
      options.isEmpty &&
      named.isEmpty &&
      reftext == null;
}

sealed class Block {
  Block({Meta? meta}) : meta = meta ?? Meta();

  Meta meta;
}

final class Section extends Block {
  Section({
    required this.level,
    required this.title,
    List<Block>? blocks,
    this.discrete = false,
    this.markdown = false,
    super.meta,
  }) : blocks = blocks ?? [];

  int level;
  List<Inline> title;
  final List<Block> blocks;

  /// `[discrete]` heading: no section, no nesting.
  bool discrete;

  /// `#` instead of `=` markers.
  bool markdown;
}

final class Paragraph extends Block {
  Paragraph(this.lines, {super.meta, this.indent = 0});

  /// Each line's inline content.
  List<List<Inline>> lines;

  /// Leading spaces (a literal paragraph when nonzero).
  int indent;
}

/// The kinds of delimited block.
enum BlockKind {
  listing('-', verbatim: true),
  literal('.', verbatim: true),
  passthrough('+', verbatim: true),
  comment('/', verbatim: true),
  example('='),
  sidebar('*'),
  quote('_'),
  open('-'),
  fenced('`', verbatim: true);

  const BlockKind(this.char, {this.verbatim = false});

  final String char;
  final bool verbatim;
}

final class Delimited extends Block {
  Delimited(
    this.kind, {
    List<Block>? blocks,
    this.lines = const [],
    this.length = 4,
    this.closeLength,
    this.unterminated = false,
    super.meta,
  }) : blocks = blocks ?? [];

  BlockKind kind;

  /// Content of compound blocks.
  final List<Block> blocks;

  /// Content of verbatim blocks.
  List<String> lines;

  /// Delimiter length (4 for most, 2 for open blocks, 3 for fences).
  int length;

  /// A different closing length (a mismatch pathology), or null.
  int? closeLength;
  bool unterminated;
}

enum ListKind {
  unordered,
  ordered,
  description,
  callout,
  checklist,
  qanda,
  horizontal,
}

final class ListItem {
  ListItem(
    this.text, {
    List<Block>? attached,
    List<ListBlock>? nested,
    this.term,
    this.checked,
    this.marker,
  }) : attached = attached ?? [],
       nested = nested ?? [];

  List<Inline> text;

  /// Blocks attached with `+` continuations.
  final List<Block> attached;
  final List<ListBlock> nested;

  /// Description lists: the term.
  List<Inline>? term;

  /// Checklists: checked or not.
  bool? checked;

  /// An explicit marker (`1.`, `a.`, `iv)`, `<3>`), or null for the default.
  String? marker;
}

final class ListBlock extends Block {
  ListBlock(
    this.kind,
    this.items, {
    this.depth = 1,
    this.separator = '::',
    super.meta,
  });

  ListKind kind;
  final List<ListItem> items;

  /// Marker repetition (`**`, `..`) or description separator depth.
  int depth;
  String separator;
}

enum TableFormat { psv, csv, dsv, tsv }

final class Cell {
  Cell(this.content, {this.spec = '', this.blocks});

  List<Inline> content;

  /// `2+`, `.3+`, `2.2+`, `3*`, alignment and style (`^.>a`), or empty.
  String spec;

  /// AsciiDoc cells (`a` style): nested blocks.
  List<Block>? blocks;
}

final class Table extends Block {
  Table(
    this.rows, {
    this.format = TableFormat.psv,
    this.cols,
    this.header = false,
    this.footer = false,
    this.nested = false,
    this.separator,
    super.meta,
  });

  final List<List<Cell>> rows;
  TableFormat format;

  /// The `cols` attribute, or null.
  String? cols;
  bool header;
  bool footer;

  /// Inside an AsciiDoc cell: `!===` and `!`.
  bool nested;

  /// A custom separator, or null.
  String? separator;
}

enum AdmonitionKind { note, tip, important, warning, caution }

final class Admonition extends Block {
  Admonition(this.kind, this.content, {super.meta});

  AdmonitionKind kind;

  /// A paragraph admonition (`NOTE: ...`) or a delimited one (`[NOTE]`).
  Block content;
}

final class BlockMacro extends Block {
  BlockMacro(this.name, this.target, {this.attributes = '', super.meta});

  /// `image`, `video`, `audio`, `toc`.
  String name;
  String target;
  String attributes;
}

final class AttributeEntry extends Block {
  AttributeEntry(
    this.name,
    this.value, {
    this.unset = false,
    this.continuation = const [],
  });

  String name;
  String value;
  bool unset;

  /// Further value lines (soft wrapped with ` \`).
  List<String> continuation;
}

final class Conditional extends Block {
  Conditional(
    this.directive,
    this.expression, {
    List<Block>? blocks,
    this.singleLine,
  }) : blocks = blocks ?? [];

  /// `ifdef`, `ifndef` or `ifeval`.
  String directive;

  /// Attribute names (`a,b`, `a+b`) or an ifeval expression.
  String expression;
  final List<Block> blocks;

  /// `ifdef::name[content]` on one line, or null.
  String? singleLine;
}

final class Include extends Block {
  Include(this.target, {this.attributes = ''});

  String target;
  String attributes;
}

final class CommentLine extends Block {
  CommentLine(this.text);

  String text;
}

final class Break extends Block {
  Break({this.page = false});

  /// `<<<` instead of `'''`.
  bool page;
}

/// Lines written as they are (a pathology may insert anything).
final class Raw extends Block {
  Raw(this.lines);

  List<String> lines;
}

sealed class Inline {}

final class Text extends Inline {
  Text(this.text);

  String text;
}

enum Mark {
  strong('*'),
  emphasis('_'),
  monospace('`'),
  mark('#'),
  superscript('^'),
  subscript('~');

  const Mark(this.char);

  final String char;
}

final class Formatted extends Inline {
  Formatted(
    this.mark,
    this.children, {
    this.constrained = true,
    this.role,
    this.unbalanced = false,
  });

  Mark mark;
  List<Inline> children;
  bool constrained;

  /// `[.role]` before the mark, or null.
  String? role;

  /// Leave off the closing mark.
  bool unbalanced;
}

final class Passthrough extends Inline {
  Passthrough(this.kind, this.text);

  /// `+`, `++`, `+++`, `$$`, `pass:[]`, `pass:q[]`.
  String kind;
  String text;
}

final class AttributeReference extends Inline {
  AttributeReference(this.name, {this.escaped = false});

  String name;
  bool escaped;
}

final class Macro extends Inline {
  Macro(this.name, this.target, this.attributes);

  /// `link`, `xref`, `footnote`, `image`, `kbd`, `btn`, `menu`, `indexterm`,
  /// `anchor`, `stem`, `mailto`, `icon`, or a URL scheme.
  String name;
  String target;
  String attributes;
}

final class Xref extends Inline {
  Xref(this.target, {this.text});

  String target;
  List<Inline>? text;
}

final class InlineAnchor extends Inline {
  InlineAnchor(this.id, {this.reftext});

  String id;
  String? reftext;
}

final class IndexTerm extends Inline {
  IndexTerm(this.terms, {this.visible = true});

  List<String> terms;
  bool visible;
}

/// Characters written as they are: replacements (`--`, `(C)`, `...`),
/// special characters, escapes, curved quotes, hard breaks.
final class Symbol extends Inline {
  Symbol(this.text);

  String text;
}
