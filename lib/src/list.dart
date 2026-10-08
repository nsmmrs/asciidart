/// Structural document model: lists and list items.
///
/// Port of `lib/asciidoctor/list.rb` (complete).
library;

import 'package:meta/meta.dart';
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/inline_tree.dart';
import 'package:ptome/src/ruby_semantics.dart';
import 'package:ptome/src/substitutors.dart';

/// Methods for managing AsciiDoc lists (ordered, unordered and description
/// lists).
///
/// Port of `Asciidoctor::List` (renamed: a top-level `List` would collide
/// with `dart:core` in every importer).
class ListBlock extends AbstractBlock {
  /// Creates a list with [parent] and [context] (`'ulist'`, `'olist'`,
  /// `'dlist'` or `'colist'`).
  new(super.parent, super.context, {super.attributes});

  /// The entries of a description list (empty for other lists).
  ///
  /// Description lists keep their items here rather than in
  /// [AbstractBlock.blocks], since each entry groups one or more terms with
  /// an optional description.
  final List<DlistEntry> entries = <DlistEntry>[];

  /// The items in this list (empty for a description list, whose items are
  /// [entries]).
  List<ListItem> get items => blocks.cast<ListItem>();

  /// Whether this list has items (or, for a description list, entries).
  bool get hasItems => blocks.isNotEmpty || entries.isNotEmpty;

  /// Whether this list is an outline list (unordered or ordered).
  bool get isOutline =>
      context == BlockContext.ulist || context == BlockContext.olist;

  /// The style the parser derived from the first ordered list marker, if
  /// any.
  ///
  /// Asciidoctor finds no list marker keyword for a marker-derived style, so
  /// the HTML `type` attribute is omitted for it (an explicit style does
  /// get one). This field records the value to reproduce that.
  String? markerStyle;

  @override
  String? listMarkerKeyword([String? listType]) =>
      listType == null && style != null && style == markerStyle
      ? null
      : super.listMarkerKeyword(listType);

  /// Converts this list, advancing the document callouts catalog past a
  /// callout list.
  ///
  /// Port of `Asciidoctor::List#convert`.
  @override
  String? convert() {
    if (context == BlockContext.colist) {
      final result = super.convert();
      document!.callouts.nextList();
      return result;
    }
    return super.convert();
  }

  /// Returns the first term of the entry following dlist item [item]
  /// within this list, or `null` for the last entry (so the search
  /// continues past the list).
  @override
  AbstractBlock? nextAdjacentDlistBlock(AbstractBlock item) {
    final index = entries.indexWhere(
      (entry) => entry.terms.contains(item) || entry.description == item,
    );
    if (index == -1) {
      // The item must belong to this list.
      throw StateError(
        'nextAdjacentBlock: node is not a member of its dlist parent',
      );
    }
    return index + 1 < entries.length ? entries[index + 1].terms.first : null;
  }

  @override
  String toString() =>
      'ListBlock(context: ${context.asciidoc}, style: ${debugQuote(style)}, '
      'items: ${context == .dlist ? entries.length : blocks.length})';
}

/// One entry of a description list: one or more terms and an optional
/// description.
class DlistEntry {
  /// Creates an entry with [terms] and an optional [description].
  new(this.terms, [this.description]);

  /// The terms (at least one).
  final List<ListItem> terms;

  /// The description, if any.
  ListItem? description;
}

/// Methods for managing items of AsciiDoc olists, ulists and dlists.
///
/// In a description list the items are grouped into the list's
/// [ListBlock.entries].
///
/// Port of `Asciidoctor::ListItem`.
class ListItem extends AbstractBlock {
  /// Creates a list item with [parent] (the [ListBlock]) and [text].
  new(AbstractBlock parent, [String? text])
    : _text = text,
      super(parent, BlockContext.listItem) {
    level = parent.level;
    subs = List<Sub>.of(normalSubs);
  }
  String? _text;

  /// A contextual alias for the list parent node (mirrors
  /// `alias list parent`).
  AbstractBlock? get list => parent;

  /// The marker used for this list item (e.g. `'*'`).
  String? marker;

  /// Whether the text of this list item is not blank.
  bool get hasText => _text != null && _text!.isNotEmpty;

  /// The text of this list item as written, before substitutions.
  @internal
  String? get sourceText => _text;

  /// The text of this list item with substitutions applied.
  ///
  /// By default the normal substitutions are applied; altering [subs]
  /// changes them. (The writer mirrors `attr_writer :text`.)
  String? get text {
    final t = _text;
    // NOTE `this.` is load-bearing: without it the call binds the
    // top-level `substitutors.applySubs` (import scope wins over the
    // inherited member here) and fails to compile.
    return t == null ? null : this.applySubs(t, subs);
  }

  set text(String? value) {
    _text = value;
  }

  /// The inline content of the text of this list item (see
  /// [applySubsTree]). Applies the substitutions, as [text] does.
  List<InlineContent> textInlines() {
    final t = _text;
    return t == null ? [] : applySubsTree(this, t, subs);
  }

  /// Whether this list item has simple content: no nested blocks, or a
  /// single nested outline list.
  bool get isSimple =>
      blocks.isEmpty ||
      (blocks.length == 1 &&
          blocks[0] is ListBlock &&
          (blocks[0] as ListBlock).isOutline);

  /// Whether this list item has compound content (anything but [isSimple]).
  bool get isCompound => !isSimple;

  /// Folds the adjacent paragraph block into the list item text.
  ///
  /// Port of `Asciidoctor::ListItem#fold_first`.
  @internal
  void foldFirst() {
    if (_text == null || _text!.isEmpty) {
      _text = (blocks.removeAt(0) as Block).source();
    } else {
      _text = '$_text$lf${(blocks.removeAt(0) as Block).source()}';
    }
  }

  @override
  String toString() =>
      'ListItem(listContext: ${parent!.contextName}, '
      'text: ${debugQuote(_text)}, blocks: ${blocks.length})';
}
