/// Base class for block-level nodes in a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/abstract_block.rb`.
///
/// Child traversal for [AbstractBlock.findBy] lives in [AbstractBlock],
/// which subclasses with non-standard child storage (`Document` header,
/// dlist entries, table rows/cells) override. The [NodeSection] interface
/// below declares the slice of `Section` this file consumes.
library;

import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/core_ext.dart';
import 'package:asciidart/src/cursor.dart';
import 'package:asciidart/src/document.dart' show DocumentAttributeEntry;
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/rx.dart';
import 'package:meta/meta.dart';

/// Maps ordered-list styles to their HTML marker keywords.
///
/// Port of `ORDERED_LIST_KEYWORDS` in `lib/asciidoctor.rb`.
const Map<String, String> orderedListKeywords = <String, String>{
  'loweralpha': 'a',
  'lowerroman': 'i',
  'upperalpha': 'A',
  'upperroman': 'I',
};

/// Maps block contexts to the document attribute holding their caption prefix.
///
/// Port of `CAPTION_ATTRIBUTE_NAMES` in `lib/asciidoctor.rb`. The upstream
/// map also has a `'figure'` entry that block-context lookups never reach,
/// so it is left out here; explicit `'figure'` lookups are handled in
/// `AbstractBlock.assignCaption`.
const Map<String, String> captionAttributeNames = <String, String>{
  'example': 'example-caption',
  'listing': 'listing-caption',
  'table': 'table-caption',
};

/// Controls [AbstractBlock.findBy] traversal from a [FindByFilter].
enum FindByVerdict {
  /// Accept the node and keep traversing its descendants.
  accept,

  /// Skip the node but still visit its descendants.
  skip,

  /// Accept the node but skip its descendants.
  prune,

  /// Skip the node and all its descendants.
  reject,

  /// Abort the whole traversal.
  stop,
}

/// Supplemental filter for [AbstractBlock.findBy]: decides, per node,
/// whether to accept it and whether to descend into it.
typedef FindByFilter = FindByVerdict Function(AbstractBlock node);

/// Raised internally to abort a [AbstractBlock.findBy] traversal.
///
/// Stops a `AbstractBlock.findBy` traversal early.
final class _TraversalStopped implements Exception {
  /// Creates the traversal-stop signal.
  const new();
}

/// The `Section` API surface consumed by blocks.
///
/// Implemented by `Section`. [AbstractBlock.assignNumeral]
/// casts its argument to this interface.
abstract interface class NodeSection {
  /// The 0-based index of the section within its parent.
  int get index;

  /// Assigns the 0-based [index] of the section within its parent.
  set index(int value);

  /// Whether the section is numbered.
  bool get numbered;

  /// Whether a numbered section takes the next chapter number (a level-1
  /// section of a book when `sectnums` is `all`).
  bool get chapterNumbering;

  /// The section name (`'appendix'`, `'chapter'`, `'part'`, `'section'`, ...).
  String? get sectname;
}

/// An abstract base class for block-level nodes of AsciiDoc content.
///
/// Port of `Asciidoctor::AbstractBlock`.
abstract class AbstractBlock extends AbstractNode {
  /// Creates a block with [parent] and [context].
  new(super.parent, super.context, {super.attributes}) {
    if (context == 'document' || context == 'section') {
      level = _nextSectionIndex = 0;
      _nextSectionOrdinal = 1;
    } else if (parent != null) {
      level = parent!.level;
    } else {
      level = null;
    }
  }

  /// The child blocks of this block (compound content model only).
  final List<AbstractBlock> blocks = <AbstractBlock>[];

  /// The type of content this block accepts and how it should be converted:
  /// `'compound'`, `'simple'`, `'verbatim'`, `'raw'` or `'empty'`.
  String contentModel = 'compound';

  /// The level of this section (or of the section this block belongs to).
  int? level;

  /// The numeral of this block (section number or caption number).
  String? numeral;

  /// The location in the AsciiDoc source where this block begins.
  ///
  /// Only tracked when source maps are enabled.
  Cursor? sourceLocation;

  /// The attribute entries (`:name: value` lines) that preceded this block,
  /// replayed against the document when the block is converted.
  List<DocumentAttributeEntry>? attributeEntries;

  /// The style (block type qualifier) of this block.
  String? style;

  /// The substitutions applied to content in this block.
  ///
  /// Reassigned by `commitSubs`.
  List<String> subs = <String>[];

  String? _caption;
  String? _title;
  String? _convertedTitle;
  int _nextSectionIndex = 0;
  int _nextSectionOrdinal = 1;

  @override
  bool get isBlock => true;

  @override
  bool get isInline => false;

  /// The source file where this block starts.
  String? get file => sourceLocation?.file;

  /// The source line number where this block starts.
  int? get lineno => sourceLocation?.lineno;

  /// Returns the converted content of this block, or `null` when the
  /// converter produces nothing for it.
  String? convert() {
    final doc = (document!)..playbackAttributes(this);
    return doc.converter.convert(this);
  }

  /// Returns the converted result of the child blocks, or `null` when the
  /// block has no content (the `empty` content model).
  String? content() => blocks.map((child) => child.convert() ?? '').join(lf);

  /// Appends [child] to this block's list of blocks, reparenting it.
  ///
  /// Port of `AbstractBlock#<<`; chain appends with cascades
  /// (`block..append(a)..append(b)`).
  void append(AbstractBlock child) {
    if (child.parent != this) child.parent = this;
    blocks.add(child);
  }

  /// Whether this block has block content.
  bool get hasBlocks => blocks.isNotEmpty;

  /// Whether this block has any child sections.
  ///
  /// Always `false` here; `Document` and `Section` override it.
  bool get hasSections => false;

  /// Walks the document tree and returns every block-level node matching
  /// the selector ([context], [style], [role] and/or [id]).
  ///
  /// When [filter] is given, it acts as a supplemental filter: a truthy
  /// return accepts the node and traversal continues, while `false` (or
  /// `null`) skips the node but still visits its children.
  /// [FindByVerdict.reject] skips the node and all its descendants,
  /// [FindByVerdict.prune] accepts the node but skips its descendants, and
  /// [FindByVerdict.stop] aborts the traversal. A non-null [id] stops the
  /// traversal after the first match attempt. With no selector or filter,
  /// every block-level node in the tree is returned. [traverseDocuments]
  /// lets table cells descend into nested documents.
  List<AbstractBlock> findBy({
    String? context,
    String? style,
    String? role,
    String? id,
    bool traverseDocuments = false,
    FindByFilter? filter,
  }) {
    final result = <AbstractBlock>[];
    try {
      findByInternal(
        context: context,
        style: style,
        role: role,
        id: id,
        traverseDocuments: traverseDocuments,
        result: result,
        filter: filter,
      );
    } on _TraversalStopped {
      // Fall through with the partial result.
    }
    return result;
  }

  /// Alias of [findBy].
  List<AbstractBlock> query({
    String? context,
    String? style,
    String? role,
    String? id,
    bool traverseDocuments = false,
    FindByFilter? filter,
  }) => findBy(
    context: context,
    style: style,
    role: role,
    id: id,
    traverseDocuments: traverseDocuments,
    filter: filter,
  );

  /// Performs the work for [findBy] without handling [_TraversalStopped].
  ///
  /// Internal: public so subclasses in other libraries (and their traversal
  /// overrides) can recurse into it.
  @internal
  List<AbstractBlock> findByInternal({
    required List<AbstractBlock> result,
    String? context,
    String? style,
    String? role,
    String? id,
    bool traverseDocuments = false,
    FindByFilter? filter,
  }) {
    if ((context == null || context == this.context) &&
        (style == null || style == this.style) &&
        (role == null || includesRole(role)) &&
        (id == null || id == this.id)) {
      if (filter != null) {
        switch (filter(this)) {
          case FindByVerdict.skip:
            if (id != null) throw const _TraversalStopped();
          case FindByVerdict.prune:
            result.add(this);
            if (id != null) throw const _TraversalStopped();
            return result;
          case FindByVerdict.reject:
            if (id != null) throw const _TraversalStopped();
            return result;
          case FindByVerdict.stop:
            throw const _TraversalStopped();
          case FindByVerdict.accept:
            result.add(this);
            if (id != null) throw const _TraversalStopped();
        }
      } else {
        result.add(this);
        if (id != null) throw const _TraversalStopped();
      }
    }
    traverseChildren(
      context: context,
      style: style,
      role: role,
      id: id,
      traverseDocuments: traverseDocuments,
      result: result,
      filter: filter,
    );
    return result;
  }

  /// Recurses [findByInternal] into the children of this block.
  ///
  /// The default implementation traverses [blocks], skipping non-section
  /// subtrees when searching for sections. Subclasses with non-standard
  /// child storage override this: `Document` (document header),
  /// `List` (dlist term/description pairs) and `Table` (rows and cells,
  /// honoring [traverseDocuments]).
  void traverseChildren({
    required List<AbstractBlock> result,
    String? context,
    String? style,
    String? role,
    String? id,
    bool traverseDocuments = false,
    FindByFilter? filter,
  }) {
    for (final child in blocks) {
      // Optimization: sections never hide inside non-section blocks.
      if (context == 'section' && child.context != 'section') continue;
      child.findByInternal(
        context: context,
        style: style,
        role: role,
        id: id,
        traverseDocuments: traverseDocuments,
        result: result,
        filter: filter,
      );
    }
  }

  /// Returns the next adjacent block in document order.
  ///
  /// When this block is the last item of its parent, the search continues
  /// with the following sibling of the parent, and so on. A description
  /// list item advances to the first term of the next entry. Returns `null`
  /// at the end of the document.
  AbstractBlock? nextAdjacentBlock() {
    if (context == 'document') return null;
    final p = parent;
    if (p == null) {
      throw StateError('Cannot find the adjacent block of a detached node.');
    }
    if (p.context == 'dlist' && context == 'list_item') {
      return p.nextAdjacentDlistBlock(this) ?? p.nextAdjacentBlock();
    }
    final siblings = p.blocks;
    final index = siblings.indexOf(this);
    if (index < 0) {
      throw StateError('Block is not a child of its parent.');
    }
    final next = index + 1;
    return next < siblings.length ? siblings[next] : p.nextAdjacentBlock();
  }

  /// Returns the block following dlist item [item] within this list.
  ///
  /// `ListBlock` overrides this to walk its entries (returning the first
  /// term of the next entry, or `null` for the last one so the search
  /// continues past the list). Other blocks throw [UnsupportedError].
  AbstractBlock? nextAdjacentDlistBlock(AbstractBlock item) =>
      throw UnsupportedError(
        'nextAdjacentDlistBlock is only defined for description lists',
      );

  /// The child sections of this block.
  List<AbstractBlock> get sections =>
      blocks.where((child) => child.context == 'section').toList();

  /// The converted alt text for this block image.
  ///
  /// The value of the `alt` attribute with XML special character and
  /// replacement substitutions applied (special characters only when it
  /// equals the default alt text), or the empty string when unset.
  String get alt {
    final source = attributes['alt'];
    if (source == null) return '';
    if (source == attributes['default-alt']) return subSpecialchars(source);
    final converted = subSpecialchars(source);
    return _hasReplaceableText(converted)
        ? subReplacements(converted)
        : converted;
  }

  /// Whether [text] contains text that replacement substitutions would
  /// rewrite (mirrors the `ReplaceableTextRx` check).
  static bool _hasReplaceableText(String text) =>
      replaceableTextRx.hasMatch(text);

  /// The caption of this block.
  ///
  /// On admonition blocks this routes to the `textlabel` attribute.
  String? get caption =>
      context == 'admonition' ? attributes['textlabel'] : _caption;

  /// Sets the caption of this block.
  set caption(String? value) {
    _caption = value;
  }

  /// The title of this block with the caption prepended.
  String captionedTitle() => '${_caption ?? ''}${title ?? ''}';

  /// Returns the list marker keyword for [listType] (default [style]).
  ///
  /// Used for the HTML type attribute.
  String? listMarkerKeyword([String? listType]) =>
      orderedListKeywords[listType ?? style];

  /// The title of this block with title substitutions applied.
  ///
  /// `null` when no source title is set. Converted titles are memoized so
  /// substitutions are never applied twice.
  String? get title {
    final source = _title;
    return _convertedTitle ??= source == null ? null : applyTitleSubs(source);
  }

  /// Whether this block has a title.
  bool get hasTitle => _title != null;

  /// The raw source title of this block, if set ([title] returns the
  /// converted title).
  ///
  /// Internal: `Section` renders it from another library.
  String? get sourceTitle => _title;

  /// Sets the block title, clearing the memoized converted title.
  set title(String? value) {
    _convertedTitle = null;
    _title = value;
  }

  /// Whether the substitution [name] is enabled for this block.
  bool hasSub(String name) => subs.contains(name);

  /// Removes the substitution [sub] from this block.
  void removeSub(String sub) {
    subs.remove(sub);
  }

  /// Generates cross reference text that can refer to this block.
  ///
  /// Uses the explicit reftext when present and non-empty. Otherwise, for a
  /// captioned block (title plus caption or number), [xrefstyle] selects the
  /// format: `'full'` (prefix, numeral and quoted title), `'short'` (prefix
  /// and numeral, or bare caption) or anything else for the plain title
  /// (`'basic'`). Without a caption style, returns the title, if any.
  String? xreftext([String? xrefstyle]) {
    final reftextValue = reftext;
    if (reftextValue != null && reftextValue.isNotEmpty) return reftextValue;
    // NOTE xrefstyle only applies to blocks with a title and a caption or
    // number.
    if (xrefstyle != null && _title != null && !_caption.isNullOrEmpty) {
      switch (xrefstyle) {
        case 'full':
          final quotedTitle = subPlaceholder(
            subQuotes(document!.compatMode ? "``%s''" : '"`%s`"'),
            title!,
          );
          final fullPrefix = _captionPrefix();
          if (fullPrefix != null) {
            return '$fullPrefix, $quotedTitle';
          }
          return '${_chompDotSpace(_caption!)}, $quotedTitle';
        case 'short':
          final shortPrefix = _captionPrefix();
          if (shortPrefix != null) return shortPrefix;
          return _chompDotSpace(_caption!);
        default: // 'basic'
          return title;
      }
    }
    return title;
  }

  /// Returns `'<prefix> <numeral>'` when this block has a numeral and its
  /// context resolves a caption prefix on the document, else `null`.
  String? _captionPrefix() {
    final number = numeral;
    if (number == null) return null;
    final attrName = captionAttributeNames[context];
    if (attrName == null) return null;
    final prefix = document!.attributes[attrName];
    if (prefix == null) return null;
    return '$prefix $number';
  }

  /// Removes one trailing `'. '` from [caption], if present.
  ///
  /// Removes one trailing `'. '`.
  static String _chompDotSpace(String caption) => caption.endsWith('. ')
      ? caption.substring(0, caption.length - 2)
      : caption;

  /// Generates and assigns a caption to this block, unless already assigned.
  ///
  /// When [value] (or the document's `caption` attribute) is set, it becomes
  /// the caption. Otherwise, when the [captionContext] (default [context])
  /// resolves a caption prefix on the document, a `'<prefix> <number>. '`
  /// caption is built and the block takes the next `<context>-number`.
  void assignCaption(String? value, [String? captionContext]) {
    final targetContext = captionContext ?? context;
    if (_caption != null || _title == null) return;
    final assigned = value ?? document!.attributes['caption'];
    if (assigned != null) {
      _caption = assigned;
      return;
    }
    // NOTE the caption stays null, so assignment remains re-runnable.
    //
    // Only an explicitly passed 'figure' caption context (the parser passes
    // it for titled images) uses the figure caption; a block whose context
    // merely is 'figure' does not, as in Asciidoctor.
    final attrName = targetContext == 'figure' && captionContext != null
        ? 'figure-caption'
        : captionAttributeNames[targetContext];
    final prefix = attrName == null ? null : document!.attributes[attrName];
    if (attrName != null && prefix != null) {
      numeral = document!.incrementAndStoreCounter(
        '$targetContext-number',
        this,
      );
      _caption = '$prefix $numeral. ';
    }
  }

  /// Assigns the next index (0-based) and numeral to [section].
  ///
  /// Appendix numerals are letters starting with `A` (with the appendix
  /// caption assigned too), chapters take the next chapter number, parts
  /// take roman numerals, and other numbered sections take the next ordinal.
  /// [section] must implement [NodeSection].
  @internal
  void assignNumeral(AbstractBlock section) {
    final target = (section as NodeSection)..index = _nextSectionIndex;
    _nextSectionIndex = target.index + 1;
    if (!target.numbered) return;
    final sectname = target.sectname;
    if (sectname == 'appendix') {
      section.numeral = document!.counter('appendix-number', 'A');
      final caption = document!.attributes['appendix-caption'];
      section.caption = caption == null
          ? '${section.numeral}. '
          : '$caption ${section.numeral}: ';
    } else if (sectname == 'chapter' || target.chapterNumbering) {
      section.numeral = document!.counter('chapter-number', '1');
    } else {
      section.numeral = sectname == 'part'
          ? Helpers.intToRoman(_nextSectionOrdinal)
          : _nextSectionOrdinal.toString();
      _nextSectionOrdinal += 1;
    }
  }

  /// The next 0-based section index within this block.
  ///
  /// Internal: `Section` reads it from another library for `hasSections`. Only meaningful on document/section nodes.
  int get nextSectionIndex => _nextSectionIndex;

  /// Reassigns section indexes by walking the descendants in document order.
  ///
  /// Invoke this on a node after removing child sections, or the internal
  /// counters will be off.
  @internal
  void reindexSections() {
    _nextSectionIndex = 0;
    _nextSectionOrdinal = 1;
    for (final child in blocks) {
      if (child.context == 'section') {
        assignNumeral(child);
        child.reindexSections();
      }
    }
  }
}
