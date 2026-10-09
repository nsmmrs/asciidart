/// The kinds of nodes: what Asciidoctor calls their context.
///
/// Each kind keeps the name Asciidoctor gives it (`'list_item'`), which is
/// what templates, extensions and the convert transforms see.
library;

/// The kind of a block.
enum BlockContext {
  /// An admonition (`NOTE:`, `[TIP]`).
  admonition,

  /// An audio player (`audio::`).
  audio,

  /// A callout list.
  colist,

  /// A description list.
  dlist,

  /// The document.
  document,

  /// An example block (`====`).
  example,

  /// A discrete heading (`[discrete]`).
  floatingTitle('floating_title'),

  /// A block image (`image::`).
  image,

  /// An item of an ordered, unordered or callout list, or a description.
  listItem('list_item'),

  /// A listing or source block (`----`).
  listing,

  /// A literal block (`....`, indented text).
  literal,

  /// An ordered list.
  olist,

  /// An open block (`--`).
  open,

  /// A page break (`<<<`).
  pageBreak('page_break'),

  /// A paragraph.
  paragraph,

  /// A passthrough block (`++++`).
  pass,

  /// The content before the first section.
  preamble,

  /// A quote block (`____`).
  quote,

  /// A section.
  section,

  /// A sidebar (`****`).
  sidebar,

  /// A math block.
  stem,

  /// A table.
  table,

  /// A table cell.
  tableCell('table_cell'),

  /// A thematic break (`'''`).
  thematicBreak('thematic_break'),

  /// A table of contents (`toc::[]`).
  toc,

  /// An unordered list.
  ulist,

  /// A unit that is blocks (ADR-0020): a statute's provision, a
  /// catechism's question, a stanza; its blocks are its children.
  unit,

  /// A verse block.
  verse,

  /// A video player (`video::`).
  video;

  new([this._asciidoc]);

  final String? _asciidoc;

  /// The name Asciidoctor uses for this context (`'list_item'`).
  String get asciidoc => _asciidoc ?? name;

  /// Whether this is a list (`ulist`, `olist`, `dlist` or `colist`).
  bool get isList => switch (this) {
    ulist || olist || dlist || colist => true,
    _ => false,
  };

  static final Map<String, BlockContext> _byName = {
    for (final c in values) c.asciidoc: c,
  };

  /// The context Asciidoctor names [name], if any.
  static BlockContext? tryParse(String name) => _byName[name];

  /// The context Asciidoctor names [name].
  static BlockContext parse(String name) =>
      tryParse(name) ?? (throw ArgumentError.value(name, 'name', 'no block'));
}

/// The kind of an inline element.
enum InlineContext {
  /// A link, cross reference or anchor.
  anchor,

  /// A hard line break.
  lineBreak('break'),

  /// A UI button (`btn:[]`).
  button,

  /// A callout mark in a listing.
  callout,

  /// A footnote reference.
  footnote,

  /// An inline image or icon.
  image,

  /// An index term.
  indexterm,

  /// A keyboard shortcut (`kbd:[]`).
  kbd,

  /// A menu path (`menu:[]`).
  menu,

  /// Where a unit starts (`type` `start`) or what it prints at its end
  /// (`end`), in a text (ADR-0020): its anchor and label.
  unit,

  /// A note of a note stream (ADR-0020): its caller in the text (`type`
  /// `call`) or the entry its unit's notes are gathered in (`entry`).
  note,

  /// Formatted text (strong, emphasis, ...) or inline math.
  quoted;

  new([this._asciidoc]);

  final String? _asciidoc;

  /// The name Asciidoctor uses for this context (`'break'`).
  String get asciidoc => _asciidoc ?? name;

  /// The node name, and convert transform, of inline elements of this
  /// context (`'inline_break'`).
  String get nodeName => 'inline_$asciidoc';

  static final Map<String, InlineContext> _byName = {
    for (final c in values) c.asciidoc: c,
  };

  /// The context Asciidoctor names [name], if any.
  static InlineContext? tryParse(String name) => _byName[name];

  /// The context Asciidoctor names [name].
  static InlineContext parse(String name) =>
      tryParse(name) ??
      (throw ArgumentError.value(name, 'name', 'no inline context'));
}

/// How a block's lines are processed and converted.
enum ContentModel {
  /// Child blocks.
  compound,

  /// Paragraph text, with normal substitutions.
  simple,

  /// Preformatted text (listings, literals).
  verbatim,

  /// Text passed through without substitutions by default (`pass`, `stem`).
  raw,

  /// No content (images, breaks, video).
  empty,

  /// Content that is parsed but not kept (comment blocks).
  skip;

  /// The content model Asciidoctor names [name].
  static ContentModel parse(String name) => values.byName(name);
}
