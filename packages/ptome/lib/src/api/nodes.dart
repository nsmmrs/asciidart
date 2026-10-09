part of 'api.dart';

/// The public node for each implementation node, created on first use.
final Expando<Node> _views = Expando('ptome node views');

/// The public view of [node].
Node _view(impl.AbstractNode node) => _views[node] ??= _create(node);

/// The public view of [node], when it is a block.
Block _blockView(impl.AbstractBlock node) => _view(node) as Block;

Node _create(impl.AbstractNode node) {
  if (node is impl.Document) return Document._(node);
  if (node is impl.Inline) return _createInline(node);
  if (node is impl.Section) return Section._(node);
  if (node is impl.ListItem) return ListItem._(node);
  if (node is impl.ListBlock) {
    return switch (node.context) {
      .ulist => UnorderedList._(node),
      .olist => OrderedList._(node),
      .colist => CalloutList._(node),
      _ => DescriptionList._(node),
    };
  }
  if (node is impl.Table) return Table._(node);
  if (node is impl.Cell) return TableCell._(node);
  if (node is impl.AbstractBlock) {
    return switch (node.context) {
      .paragraph => Paragraph._(node),
      .listing => Listing._(node),
      .literal => Literal._(node),
      .admonition => Admonition._(node),
      .example => Example._(node),
      .sidebar => Sidebar._(node),
      .quote => Quote._(node),
      .verse => Verse._(node),
      .open => Open._(node),
      .pass => Passthrough._(node),
      .stem => Stem._(node),
      .image => Image._(node),
      .audio => Audio._(node),
      .video => Video._(node),
      .thematicBreak => ThematicBreak._(node),
      .pageBreak => PageBreak._(node),
      .toc => TableOfContents._(node),
      .preamble => Preamble._(node),
      .floatingTitle => DiscreteHeading._(node),
      // Kinds with their own classes, matched above.
      .document ||
      .section ||
      .listItem ||
      .ulist ||
      .olist ||
      .dlist ||
      .colist ||
      .table ||
      .tableCell => OtherBlock._(node),
    };
  }
  throw StateError('no public view for ${node.runtimeType}');
}

/// Strips HTML tags and decodes the character references Ptome emits.
String _plain(String html) => _decode(html).trim();

/// [html] without tags, with character references decoded.
String _decode(String html) =>
    html.replaceAll(_tag, '').replaceAllMapped(_reference, (m) {
      final name = m[1]!;
      if (name.startsWith('#x') || name.startsWith('#X')) {
        return String.fromCharCode(int.parse(name.substring(2), radix: 16));
      }
      if (name.startsWith('#')) {
        return String.fromCharCode(int.parse(name.substring(1)));
      }
      return _namedReferences[name] ?? m[0]!;
    });

final RegExp _tag = RegExp('<[^>]*>');
final RegExp _reference = RegExp('&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-z]+);');
const Map<String, String> _namedReferences = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

/// A node of a document: the document itself, a block, a list item, a
/// table cell, or an inline element.
///
/// The hierarchy is sealed, so a `switch` over a node can cover every kind.
sealed class Node {
  new _(this._node);

  final impl.AbstractNode _node;

  /// The node containing this one, or `null` for a document.
  Node? get parent {
    final parent = _node.parent;
    return parent == null ? null : _view(parent);
  }

  /// The document this node belongs to.
  Document get document => _view(_node.document! as impl.Document) as Document;

  /// The ID of this node, if it has one.
  String? get id => _node.id;
  set id(String? value) => _node.id = value;

  /// The roles (CSS classes) of this node.
  List<String> get roles => _node.roles;

  /// The attributes of this node.
  Attributes get attributes => Attributes._(_node.attributes);

  /// Whether the `name` option is set (`[%name]` or `options=name`).
  bool hasOption(String name) => _node.hasOption(name);

  /// The text of this node as a reader sees it: converted, with markup
  /// removed and character references decoded.
  String get plainText;

  @override
  String toString() => 'Node(${_node.contextName})';
}

/// A block: a section, paragraph, list, table, delimited block, and so on.
///
/// Blocks nest: [blocks] are the blocks directly inside this one.
sealed class Block extends Node {
  new _(impl.AbstractBlock super._node) : super._();

  impl.AbstractBlock get _block => _node as impl.AbstractBlock;

  /// The title of this block (`.Title` above it, or a section's title), with
  /// inline markup converted; `null` when it has none.
  String? get title => _block.title;
  set title(String? value) => _block.title = value;

  /// The title of this block as written in the source; `null` when it has
  /// none.
  String? get sourceTitle => _block.sourceTitle;

  /// The style of this block (the first positional attribute, such as
  /// `source` or `quote`), if any.
  String? get style => _block.style;

  /// Where the block starts in the source.
  SourceLocation? get location => SourceLocation._of(_block.sourceLocation);

  /// The blocks directly inside this one.
  List<Block> get blocks => [for (final b in _block.blocks) _blockView(b)];

  /// Adds [block] as the last block inside this one.
  void append(Block block) {
    _block.append(block._block);
  }

  /// Removes this block from its parent.
  void remove() {
    final parent = _block.parent;
    if (parent != null) parent.blocks.remove(_block);
  }

  /// Every node of type [T] inside this block (not including itself), in
  /// document order: nested blocks, list items, description list terms and
  /// descriptions, and table cells.
  Iterable<T> descendants<T extends Node>() sync* {
    for (final child in _children()) {
      if (child is T) yield child;
      if (child is Block) yield* child.descendants<T>();
    }
  }

  Iterable<Node> _children() => blocks;

  /// This block converted to the document's output format.
  String convert() => document._run(() => _block.convert() ?? '');

  /// The block's title as inline content (see [InlineContent]); empty
  /// without a title. Applies the title substitutions.
  List<InlineContent> get titleInlines =>
      document._run(() => _inlineContent(_block.titleInlines()));

  @override
  String get plainText => document._run(
    () =>
        [for (final b in blocks) b.plainText]
            .where((t) => t.isNotEmpty)
            .join('\n\n'),
  );
}

/// A block whose content is its own text (a paragraph, a literal block,
/// ...), as opposed to child blocks.
mixin _Text on Block {
  impl.Block get _textBlock => _node as impl.Block;

  /// The text of the block as written in the source.
  String get source => _textBlock.source();

  /// The converted text: inline markup applied for prose, special
  /// characters escaped for verbatim text.
  String get content => document._run(() => _textBlock.content() ?? '');

  /// The text as inline content (see [InlineContent]): text and the inline
  /// elements in it, nested. Applies the substitutions, as [content] does.
  List<InlineContent> get inlines =>
      document._run(() => _inlineContent(_textBlock.contentInlines()));

  @override
  String get plainText => _plain(content);
}

/// A parsed AsciiDoc document.
final class Document extends Block {
  new _(impl.Document super._node) : super._();

  impl.Document get _doc => _node as impl.Document;

  _Collector? _collector;

  /// The source this document was parsed from, and how to parse an edited
  /// version of it the same way.
  ({String source, Document Function(String source) parse})? _origin;

  ({String source, Document Function(String source) parse}) get _edits =>
      _origin ??
      (throw StateError(
        'only a document returned by parse, parseHeader or parseAsync can '
        'be edited',
      ));

  R _run<R>(R Function() body) {
    final parentDocument = _doc.parentDocument;
    if (parentDocument != null) {
      return (_view(parentDocument) as Document)._run(body);
    }
    final collector = _collector;
    return _guard(() => collector == null ? body() : collector.run(body));
  }

  @override
  Document get document => this;

  /// The document title (the level-0 heading or the `title` attribute),
  /// with inline markup converted; `null` when it has none.
  @override
  String? get title => _run(_doc.doctitle);

  /// The document title as written in the header (`= Title`), before
  /// substitutions; `null` when the header has no title.
  @override
  String? get sourceTitle => _doc.header?.sourceTitle;

  /// The document title as inline content (see [InlineContent]); empty
  /// without a title.
  @override
  List<InlineContent> get titleInlines =>
      _run(() => _inlineContent(_doc.header?.titleInlines() ?? []));

  /// The attributes the document header sets, in source order: name to
  /// value, or to `null` for an attribute it unsets (`:name!:`). Unlike
  /// [attributes], this leaves out the built-in attributes and those given
  /// through the API.
  Map<String, String?> get headerAttributes => {
    for (final entry
        in _doc.headerAttributeEntries ?? const <impl.DocumentAttributeEntry>[])
      entry.name: entry.negate ? null : entry.value,
  };

  /// The source this document was parsed from.
  String get source => _edits.source;

  /// This document with the header attribute [name] set to [value]: its
  /// [source] rewrites only the attribute entry that sets [name] last (or,
  /// when the header has none, adds one at the end of the header) and
  /// keeps every other byte as written; the result is that source, parsed
  /// with the same settings as this document. An unset entry (`:name!:`)
  /// becomes a set one.
  ///
  /// Throws an [PtomeException], and edits nothing, when the source
  /// alone can't make the edit: the header sets [name] in an include or
  /// under a preprocessor conditional, or ends inside an include. Throws an
  /// [ArgumentError] for a [value] of more than one line.
  Document withAttribute(String name, String value) {
    final (:source, :parse) = _edits;
    final edited = _guard(
      () => impl.setHeaderAttribute(_doc, source, name, value),
    );
    return identical(edited, source) ? this : parse(edited);
  }

  /// This document without the header attribute entries for [name]: its
  /// [source] drops only their lines. See [withAttribute].
  Document withoutAttribute(String name) {
    final (:source, :parse) = _edits;
    final edited = _guard(() => impl.removeHeaderAttribute(_doc, source, name));
    return identical(edited, source) ? this : parse(edited);
  }

  /// The authors from the document header.
  List<Author> get authors => [
    for (final a in _doc.authors)
      Author._(a.name, a.email, a.firstname, a.middlename, a.lastname),
  ];

  /// The document type.
  Doctype get doctype =>
      Doctype.values.asNameMap()[_doc.doctype] ?? Doctype.article;

  /// The document's numbered units (`:units:` in its header; see
  /// `doc/units.md`), in document order: books, chapters and verses;
  /// sections and their subdivisions. Empty for a document not written in
  /// units.
  List<Unit> get units {
    final analysis = _doc.unitsSession?.analysis;
    if (analysis == null) return const [];
    return [
      for (final u in [
        ...analysis.units,
      ]..sort((a, b) => a.start.compareTo(b.start)))
        _unit(analysis, u),
    ];
  }

  /// The unit with the ID [idOrAddress] (`v-exo-34-6`), or the first unit
  /// of the passage at that address, as the document's schemes cite it
  /// (`Exod 34:6`, `Exodus 34:6-8`). `null` when there is no such unit or
  /// the document is not written in units.
  Unit? unit(String idOrAddress) {
    final analysis = _doc.unitsSession?.analysis;
    if (analysis == null) return null;
    final found =
        analysis.byId[idOrAddress] ??
        impl.resolvePassage(analysis, idOrAddress)?.start;
    return found == null ? null : _unit(analysis, found);
  }

  /// The messages reported while parsing and converting this document.
  List<Diagnostic> get diagnostics =>
      List.unmodifiable(_collector?.diagnostics ?? const <Diagnostic>[]);

  /// The document converted to its output format: the body only, or a
  /// complete page when [standalone] is `true` (default: as parsed).
  @override
  String convert({bool? standalone}) =>
      _run(() => _doc.convert(standalone: standalone));

  /// The document converted to HTML; see [convert].
  ///
  /// Throws a [StateError] when the document was parsed for another
  /// backend.
  String toHtml({bool? standalone}) {
    final basebackend = _doc.attributes['basebackend'];
    if (basebackend != 'html') {
      throw StateError(
        'the document was parsed for the ${_doc.attributes['backend']} '
        'backend; parse it with Backend.html5 to get HTML',
      );
    }
    return convert(standalone: standalone);
  }

  /// The document's index: the terms its index terms (`(((...)))`,
  /// `((...))`, `indexterm:[]`, `indexterm2:[]`) name, by letter, each
  /// with where it is used, whether or not the document has an `[index]`
  /// section. Collected by converting the document (its messages are left
  /// out of [diagnostics]).
  ///
  /// Throws a [StateError] when the document was parsed for a backend
  /// other than HTML.
  List<IndexLetter> get index {
    if (_doc.attributes['basebackend'] != 'html') {
      throw StateError(
        'the document was parsed for the ${_doc.attributes['backend']} '
        'backend; parse it with Backend.html5 to get its index',
      );
    }
    final catalog = impl.IndexCatalog(always: true);
    final saved = _doc.catalog.index;
    _doc.catalog.index = catalog;
    try {
      _guard(
        () => impl.LoggerManager.scoped(
          impl.NullLogger(),
          () => _doc.convert(standalone: false),
        ),
      );
    } finally {
      _doc.catalog.index = saved;
    }
    IndexEntry entry(impl.IndexEntry source) => IndexEntry._(
      source.text,
      [
        for (final use in source.uses)
          if (use.node case final impl.AbstractBlock block) _blockView(block),
      ],
      source.see,
      List.unmodifiable(source.seeAlso),
      [for (final sub in source.subentries) entry(sub)],
    );
    return [
      for (final letter in catalog.letters)
        IndexLetter._(letter.letter, [
          for (final source in letter.entries) entry(source),
        ]),
    ];
  }

  @override
  Attributes get attributes => Attributes._(_doc.attributes);
}

/// The terms of a document's index under one letter (see
/// [Document.index]).
final class IndexLetter {
  const new _(this.letter, this.entries);

  /// The letter, upper case; `@` for terms that don't start with a letter.
  final String letter;

  /// The terms, in index order: case-insensitively, then by character.
  final List<IndexEntry> entries;
}

/// A term of a document's index (see [Document.index]).
final class IndexEntry {
  const new _(this.term, this.uses, this.see, this.seeAlso, this.subentries);

  /// The term, as plain text.
  final String term;

  /// The blocks the term is used in (the paragraph, list item, table
  /// cell or section whose text names it), in document order, once per
  /// use; empty for a term that only groups its subterms.
  final List<Block> uses;

  /// The term it refers to instead (`see`), if any.
  final String? see;

  /// The terms it refers to as well (`see-also`).
  final List<String> seeAlso;

  /// Its subterms (secondary under a primary term, tertiary under a
  /// secondary one), in index order.
  final List<IndexEntry> subentries;
}

/// An author named in a document header.
final class Author {
  const new _(
    this.name,
    this.email,
    this.firstName,
    this.middleName,
    this.lastName,
  );

  /// The full name.
  final String? name;

  /// The email address.
  final String? email;

  /// The first name.
  final String? firstName;

  /// The middle name.
  final String? middleName;

  /// The last name.
  final String? lastName;

  @override
  String toString() => name ?? '';
}

/// The kinds of AsciiDoc document.
enum Doctype {
  /// A single article (the default).
  article,

  /// A book: parts, chapters, appendixes.
  book,

  /// A man page.
  manpage,

  /// A single paragraph or block, converted without any wrapper.
  inline,
}

/// A section.
final class Section extends Block {
  new _(impl.Section super._node) : super._();

  impl.Section get _section => _node as impl.Section;

  /// The section level: 0 for a book part, 1 for `==`, and so on.
  int get level => _section.level ?? 1;

  @override
  String get title => _section.title ?? '';

  /// The section number (`1.2`), when sections are numbered.
  String? get number =>
      _section.numbered ? document._run(() => _section.sectnum('.', '')) : null;

  /// The kind of section (`section`, `chapter`, `appendix`, `part`,
  /// `preface`, `abstract`, `colophon`, `glossary`, ...).
  String get sectionName => _section.sectname ?? 'section';

  /// Whether this is a special section (appendix, glossary, ...).
  bool get isSpecial => _section.special;
}

/// The content of a document before its first section.
final class Preamble extends Block {
  new _(super._node) : super._();
}

/// A paragraph.
final class Paragraph extends Block with _Text {
  new _(super._node) : super._();
}

/// A listing block (`----`), including source code blocks.
final class Listing extends Block with _Text {
  new _(super._node) : super._();

  /// The source language, for a source block.
  String? get language => _node.attributes['language'];
}

/// A literal block (`....` or indented text).
final class Literal extends Block with _Text {
  new _(super._node) : super._();
}

/// The kinds of admonition.
enum AdmonitionKind {
  /// `NOTE`
  note,

  /// `TIP`
  tip,

  /// `IMPORTANT`
  important,

  /// `CAUTION`
  caution,

  /// `WARNING`
  warning,
}

/// An admonition: a `NOTE:` paragraph or a `[NOTE]` block.
final class Admonition extends Block {
  new _(super._node) : super._();

  /// The kind of admonition.
  AdmonitionKind get kind =>
      AdmonitionKind.values.asNameMap()[_node.attributes['name']] ??
      AdmonitionKind.note;

  /// The converted content: the paragraph text for an admonition paragraph,
  /// the converted child blocks for an admonition block.
  String get content =>
      document._run(() => (_node as impl.AbstractBlock).content() ?? '');

  /// The paragraph text of an admonition paragraph as inline content (see
  /// [InlineContent]); empty for an admonition block. Applies the
  /// substitutions, as [content] does.
  List<InlineContent> get inlines => switch (_node) {
    final impl.Block block => document._run(
      () => _inlineContent(block.contentInlines()),
    ),
    _ => const [],
  };

  @override
  String get plainText => blocks.isEmpty ? _plain(content) : super.plainText;
}

/// An example block (`====`).
final class Example extends Block {
  new _(super._node) : super._();
}

/// A sidebar (`****`).
final class Sidebar extends Block {
  new _(super._node) : super._();
}

/// A quote block (`____`, or `[quote]`).
final class Quote extends Block {
  new _(super._node) : super._();

  /// Who the quote is attributed to.
  String? get attribution => _node.attributes['attribution'];

  /// The work the quote is from.
  String? get citation => _node.attributes['citetitle'];

  @override
  String get plainText => blocks.isEmpty
      ? _plain(document._run(() => (_node as impl.Block).content() ?? ''))
      : super.plainText;
}

/// A verse block (`[verse]`).
final class Verse extends Block with _Text {
  new _(super._node) : super._();

  /// Who the verse is attributed to.
  String? get attribution => _node.attributes['attribution'];

  /// The work the verse is from.
  String? get citation => _node.attributes['citetitle'];
}

/// An open block (`--`).
final class Open extends Block {
  new _(super._node) : super._();
}

/// A passthrough block (`++++`): output as written.
final class Passthrough extends Block with _Text {
  new _(super._node) : super._();
}

/// The math notations.
enum StemNotation {
  /// LaTeX math.
  latexmath,

  /// AsciiMath.
  asciimath,
}

/// A math block (`[stem]`).
final class Stem extends Block with _Text {
  new _(super._node) : super._();

  /// The notation of the math.
  StemNotation get notation =>
      style == 'asciimath' ? StemNotation.asciimath : StemNotation.latexmath;
}

/// An image block (`image::target[]`).
final class Image extends Block {
  new _(super._node) : super._();

  /// The image path or URL as written.
  String get target => _node.attributes['target'] ?? '';
  set target(String value) => _node.attributes['target'] = value;

  /// The alternative text.
  String get alt => _node.attributes['alt'] ?? '';

  /// The width, if given.
  String? get width => _node.attributes['width'];

  /// The height, if given.
  String? get height => _node.attributes['height'];

  /// The link target, if the image links somewhere.
  String? get link => _node.attributes['link'];

  @override
  String get plainText => alt;
}

/// An audio block (`audio::target[]`).
final class Audio extends Block {
  new _(super._node) : super._();

  /// The audio path or URL as written.
  String get target => _node.attributes['target'] ?? '';
  set target(String value) => _node.attributes['target'] = value;
}

/// A video block (`video::target[]`).
final class Video extends Block {
  new _(super._node) : super._();

  /// The video path, URL or ID as written.
  String get target => _node.attributes['target'] ?? '';
  set target(String value) => _node.attributes['target'] = value;

  /// The hosting service (`youtube`, `vimeo`), or `null` for a file.
  String? get service =>
      _node.attributes['poster'] == 'youtube' ||
          _node.attributes['poster'] == 'vimeo'
      ? _node.attributes['poster']
      : null;
}

/// A thematic break (`'''`).
final class ThematicBreak extends Block {
  new _(super._node) : super._();
}

/// A page break (`<<<`).
final class PageBreak extends Block {
  new _(super._node) : super._();
}

/// A table of contents placed with the `toc::[]` macro.
final class TableOfContents extends Block {
  new _(super._node) : super._();
}

/// A discrete heading (`[discrete]`): looks like a section title, but
/// starts no section.
final class DiscreteHeading extends Block {
  new _(super._node) : super._();

  /// The heading level, as for a [Section].
  int get level => _block.level ?? 1;

  @override
  String get title => _block.title ?? '';

  @override
  String get plainText => _plain(title);
}

/// A block of a kind Ptome does not define, created by an extension.
final class OtherBlock extends Block {
  new _(super._node) : super._();

  /// The block's context, as the extension named it.
  String get context => _node.contextName;
}

/// An unordered (`*`) list, including checklists.
final class UnorderedList extends Block {
  new _(impl.ListBlock super._node) : super._();

  @override
  String get plainText => items.map((i) => i.plainText).join('\n');

  /// The items.
  List<ListItem> get items => [
    for (final i in (_node as impl.ListBlock).items) _view(i) as ListItem,
  ];

  /// Whether this is a checklist (`* [x] done`).
  bool get isChecklist => hasOption('checklist');
}

/// An ordered (`.` or `1.`) list.
final class OrderedList extends Block {
  new _(impl.ListBlock super._node) : super._();

  @override
  String get plainText => items.map((i) => i.plainText).join('\n');

  /// The items.
  List<ListItem> get items => [
    for (final i in (_node as impl.ListBlock).items) _view(i) as ListItem,
  ];

  /// The number of the first item.
  int get start => int.tryParse(_node.attributes['start'] ?? '') ?? 1;
}

/// A callout list (`<1> ...`) explaining the callouts of a listing.
final class CalloutList extends Block {
  new _(impl.ListBlock super._node) : super._();

  @override
  String get plainText => items.map((i) => i.plainText).join('\n');

  /// The items.
  List<ListItem> get items => [
    for (final i in (_node as impl.ListBlock).items) _view(i) as ListItem,
  ];
}

/// A description list (`term:: description`).
final class DescriptionList extends Block {
  new _(impl.ListBlock super._node) : super._();

  /// The entries: one or more terms with an optional description.
  List<DescriptionListEntry> get entries => [
    for (final e in (_node as impl.ListBlock).entries)
      DescriptionListEntry._([
        for (final t in e.terms) _view(t) as ListItem,
      ], e.description == null ? null : _view(e.description!) as ListItem),
  ];

  @override
  Iterable<Node> _children() => [
    for (final entry in entries) ...[...entry.terms, ?entry.description],
  ];

  @override
  String get plainText => [
    for (final entry in entries)
      [
        for (final term in entry.terms) term.plainText,
        if (entry.description case final description?) description.plainText,
      ].join('\n'),
  ].join('\n\n');
}

/// One entry of a [DescriptionList].
final class DescriptionListEntry {
  const new _(this.terms, this.description);

  /// The terms (at least one).
  final List<ListItem> terms;

  /// The description, if any.
  final ListItem? description;
}

/// An item of a list, or a term or description of a description list.
final class ListItem extends Block {
  new _(impl.ListItem super._node) : super._();

  impl.ListItem get _item => _node as impl.ListItem;

  /// The text of the item as written in the source.
  String get source => _item.sourceText ?? '';

  /// The text of the item with inline markup converted.
  String get content => document._run(() => _item.text ?? '');

  /// The text of the item as inline content (see [InlineContent]).
  /// Applies the substitutions, as [content] does.
  List<InlineContent> get inlines =>
      document._run(() => _inlineContent(_item.textInlines()));

  /// For a checklist item, whether it is checked; otherwise `null`.
  bool? get checked => _node.attributes.containsKey('checkbox')
      ? _node.attributes.containsKey('checked')
      : null;

  @override
  String get plainText => [
    _plain(content),
    for (final b in blocks) b.plainText,
  ].where((t) => t.isNotEmpty).join('\n');

  @override
  Iterable<Node> _children() => blocks;
}

/// A table.
final class Table extends Block {
  new _(impl.Table super._node) : super._();

  impl.Table get _table => _node as impl.Table;

  List<List<TableCell>> _rows(List<List<impl.Cell>> rows) => [
    for (final row in rows) [for (final c in row) _view(c) as TableCell],
  ];

  /// The header rows.
  List<List<TableCell>> get head => _rows(_table.rows.head);

  /// The body rows.
  List<List<TableCell>> get body => _rows(_table.rows.body);

  /// The footer rows.
  List<List<TableCell>> get foot => _rows(_table.rows.foot);

  /// The columns.
  List<TableColumn> get columns => [
    for (final c in _table.columns)
      TableColumn._(c.colnumber, c.attributes['colpcwidth'], c.style),
  ];

  @override
  Iterable<Node> _children() => [
    for (final row in [...head, ...body, ...foot]) ...row,
  ];

  @override
  String get plainText => [
    for (final row in [...head, ...body, ...foot])
      row.map((c) => c.plainText).join('\t'),
  ].join('\n');
}

/// A column of a [Table].
final class TableColumn {
  const new _(this.number, this._width, this.style);

  /// The 1-based column number.
  final int number;

  final String? _width;

  /// The width as a percentage of the table width.
  num? get width => _width == null ? null : num.tryParse(_width);

  /// The column style (`asciidoc`, `literal`, `header`, ...), if any.
  final String? style;
}

/// A cell of a [Table].
final class TableCell extends Block {
  new _(impl.Cell super._node) : super._();

  impl.Cell get _cell => _node as impl.Cell;

  /// The text of the cell as written in the source.
  String get source => _cell.source() ?? '';

  /// The converted text of the cell (for an AsciiDoc cell, the converted
  /// blocks).
  String get content => document._run(() => _cell.convert() ?? '');

  /// How many columns the cell spans.
  int get colspan => _cell.colspan ?? 1;

  /// How many rows the cell spans.
  int get rowspan => _cell.rowspan ?? 1;

  /// The blocks of an AsciiDoc cell (`a|`); empty for other cells.
  @override
  List<Block> get blocks {
    final inner = _cell.innerDocument;
    return inner == null
        ? const []
        : [for (final b in inner.blocks) _blockView(b)];
  }

  @override
  String get plainText => _cell.innerDocument == null
      ? _plain(document._run(() => _cell.text))
      : super.plainText;
}
