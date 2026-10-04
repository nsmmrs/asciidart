/// Structural document model: lists and list items.
///
/// Port of `lib/asciidoctor/list.rb` (complete).
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/substitutors.dart';

/// Methods for managing AsciiDoc lists (ordered, unordered and description
/// lists).
///
/// Port of `Asciidoctor::List` (renamed: a top-level `List` would collide
/// with `dart:core` in every importer).
class ListBlock extends AbstractBlock {
  /// Creates a list with [parent] and [context] (`'ulist'`, `'olist'`,
  /// `'dlist'` or `'colist'`).
  new(super.parent, super.context, {super.attributes}) {
    if (context == 'dlist') _pairs = <Object?>[];
  }

  /// The `[terms, description]` pairs of a description list.
  ///
  /// Ruby pushes the pairs straight into the blocks array, but the port
  /// types [AbstractBlock.blocks] as `List<AbstractBlock>`, so description
  /// lists keep their pairs here instead (`terms` is a `List<ListItem>`,
  /// `description` a [ListItem], or `null` when unset). `null` unless the
  /// context is `'dlist'`.
  List<Object?>? _pairs;

  /// The items in this list (the description pairs for a `'dlist'`, else an
  /// alias of [AbstractBlock.blocks], mirroring `alias items blocks`).
  List<Object?> get items => _pairs ?? blocks;

  /// The items in this list (mirrors `alias content blocks`).
  @override
  Object? content() => _pairs ?? blocks;

  /// Whether this list has items (mirrors `alias items? blocks?`).
  bool get hasItems => items.isNotEmpty;

  /// Whether this list is an outline list (unordered or ordered).
  bool get isOutline => context == 'ulist' || context == 'olist';

  /// Converts this list, advancing the document callouts catalog past a
  /// callout list.
  ///
  /// Port of `Asciidoctor::List#convert`.
  @override
  dynamic convert() {
    if (context == 'colist') {
      final result = super.convert();
      document!.callouts.nextList();
      return result;
    }
    return super.convert();
  }

  /// Returns the `[terms, description]` pair following dlist item [item]
  /// within this list, or `null` for the last pair (so the search continues
  /// past the list).
  ///
  /// Port of the description-list path of
  /// `Asciidoctor::AbstractBlock#next_adjacent_block` (which returns the
  /// pair array itself).
  @override
  Object? nextAdjacentDlistBlock(AbstractBlock item) {
    final pairs = items;
    final index = pairs.indexWhere((pair) {
      final parts = pair! as List<Object?>;
      return (parts[0]! as List<Object?>).contains(item) || parts[1] == item;
    });
    if (index == -1) {
      // Ruby raises NoMethodError on `nil + 1` here.
      throw StateError(
        'nextAdjacentBlock: node is not a member of its dlist parent',
      );
    }
    return index + 1 < pairs.length ? pairs[index + 1] : null;
  }

  @override
  String toString() =>
      // Contexts render with a `:` prefix to mimic Ruby's Symbol#inspect.
      '#ListBlock@${identityHashCode(this)} {context: :$context, '
      'style: ${inspectString(style)}, items: ${items.length}}';
}

/// Methods for managing items of AsciiDoc olists, ulists and dlists.
///
/// In a description list each item is a `[terms, description]` pair stored
/// in the list's [ListBlock.items] (see [ListBlock]): `terms` is a
/// `List<ListItem>` and `description` a [ListItem] (or `null` when unset).
///
/// Port of `Asciidoctor::ListItem`.
class ListItem extends AbstractBlock {
  /// Creates a list item with [parent] (the [ListBlock]) and [text].
  new(AbstractBlock parent, [String? text])
    : _text = text,
      super(parent, 'list_item') {
    level = parent.level;
    subs = List<String>.of(normalSubs);
  }
  String? _text;

  /// A contextual alias for the list parent node (mirrors
  /// `alias list parent`).
  AbstractBlock? get list => parent;

  /// The marker used for this list item (e.g. `'*'`).
  String? marker;

  /// Whether the text of this list item is not blank.
  bool get hasText => _text != null && _text!.isNotEmpty;

  /// The text of this list item with substitutions applied.
  ///
  /// By default the normal substitutions are applied; altering [subs]
  /// changes them. (The writer mirrors `attr_writer :text`.)
  String? get text {
    final t = _text;
    // NOTE `this.` is load-bearing: without it the call binds the
    // top-level `substitutors.applySubs` (import scope wins over the
    // inherited member here) and fails to compile.
    return t == null ? null : this.applySubs(t, subs) as String?;
  }

  set text(String? value) {
    _text = value;
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
  void foldFirst() {
    if (_text == null || _text!.isEmpty) {
      _text = (blocks.removeAt(0) as Block).source();
    } else {
      _text = '$_text$lf${(blocks.removeAt(0) as Block).source()}';
    }
  }

  @override
  String toString() =>
      // Contexts render with a `:` prefix to mimic Ruby's Symbol#inspect.
      '#ListItem@${identityHashCode(this)} '
      '{list_context: :${(parent!).context}, '
      'text: ${inspectString(_text)}, blocks: ${blocks.length}}';
}
