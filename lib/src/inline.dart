/// Inline elements in an AsciiDoc block.
///
/// Port of `lib/asciidoctor/inline.rb`.
library;

import 'package:asciidoctor/src/abstract_node.dart';

/// Methods for managing inline elements in an AsciiDoc block.
///
/// Port of `Asciidoctor::Inline`.
class Inline extends AbstractNode {
  /// Creates an inline element with [parent], [context] and [text].
  ///
  /// Dart parameter lists cannot mix optional positional and named
  /// parameters, so [text] is named.
  new(
    super.parent,
    super.context, {
    this.text,
    super.attributes,
    String? id,
    this.type,
    this.target,
    this.keys,
    this.submenus,
    this.terms,
    this.seeAlso,
    this.xmlCommentGuard = false,
  }) : super(nodeName: 'inline_$context') {
    this.id = id;
  }

  /// The keys of a keyboard shortcut (the `kbd` macro).
  final List<String>? keys;

  /// The submenus leading to the menu item (the `menu` macro).
  final List<String>? submenus;

  /// The terms of a concealed index term (primary, secondary, tertiary).
  final List<String>? terms;

  /// The related index terms of an index term (its `see-also` attribute).
  final List<String>? seeAlso;

  /// Whether a callout is guarded by an XML comment (`<!--1-->`) rather
  /// than by the line comment in the `guard` attribute.
  final bool xmlCommentGuard;

  /// The text of this inline element.
  String? text;

  /// The type (qualifier) of this inline element.
  final String? type;

  /// The target (e.g. URI) of this inline element.
  String? target;

  @override
  bool get isBlock => false;

  @override
  bool get isInline => true;

  /// Returns the converted result of this node.
  String convert() => converter.convert(this) ?? '';

  /// The converted alt text for this inline image.
  ///
  /// The value of the `alt` attribute, or the empty string when unset.
  String get alt => attributes['alt'] ?? '';

  /// Whether this node carries reference text.
  ///
  /// For a reference node (`'ref'` or `'bibref'` type), the text is the
  /// reftext (and the `reftext` attribute is not set).
  @override
  bool get hasReftext => text != null && (type == 'ref' || type == 'bibref');

  /// The reference text of this node with substitutions applied.
  ///
  /// For a reference node (`'ref'` or `'bibref'` type), the text is the
  /// reftext (and the `reftext` attribute is not set).
  @override
  String? get reftext {
    final value = text;
    if (value == null) return null;
    return applyReftextSubs(value);
  }

  /// Generates cross reference text that can refer to this inline node.
  ///
  /// Uses the explicit reftext, if specified, else returns nothing.
  /// [xrefstyle] is currently unused.
  String? xreftext([String? xrefstyle]) => reftext;
}
