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
  /// parameters, so [text] is named here (Ruby takes it positionally).
  new(
    super.parent,
    super.context, {
    this.text,
    super.attributes,
    String? id,
    this.type,
    this.target,
  }) : super(nodeName: 'inline_$context') {
    this.id = id;
  }

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
  Object? convert() => converter.convert(this);

  /// The converted alt text for this inline image.
  ///
  /// The value of the `alt` attribute, or the empty string when unset.
  Object get alt {
    final value = attr('alt');
    return value == null || value == false ? '' : value;
  }

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
    return applyReftextSubs(value) as String?;
  }

  /// Generates cross reference text that can refer to this inline node.
  ///
  /// Uses the explicit reftext, if specified, else returns nothing.
  /// [xrefstyle] is currently unused.
  String? xreftext([String? xrefstyle]) => reftext;
}
