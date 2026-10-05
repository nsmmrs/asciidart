part of 'api.dart';

Inline _createInline(impl.Inline node) => switch ((node.context, node.type)) {
  (.anchor, 'xref') => CrossReference._(node),
  (.anchor, 'ref') => InlineAnchor._(node),
  (.anchor, 'bibref') => BibliographyAnchor._(node),
  (.anchor, _) => Link._(node),
  (.quoted, 'asciimath' || 'latexmath') => InlineStem._(node),
  (.quoted, _) => Formatted._(node),
  (.footnote, _) => Footnote._(node),
  (.image, 'icon') => Icon._(node),
  (.image, _) => InlineImage._(node),
  (.kbd, _) => Keyboard._(node),
  (.button, _) => Button._(node),
  (.menu, _) => Menu._(node),
  (.lineBreak, _) => LineBreak._(node),
  (.callout, _) => Callout._(node),
  (.indexterm, _) => IndexTerm._(node),
};

/// An inline element: formatted text, a link, an inline image, and so on.
///
/// Inline elements reach code through output overrides and macro
/// extensions. Their [text] is already converted.
sealed class Inline extends Node {
  new _(impl.Inline super._node) : super._();

  impl.Inline get _inline => _node as impl.Inline;

  /// The converted text of the element, if it has text.
  String? get text => _inline.text;

  @override
  String get plainText => _plain(text ?? '');
}

/// A link to a URL (`https://...`, `link:target[text]`, an email address).
final class Link extends Inline {
  new _(super._node) : super._();

  /// The URL.
  String get target => _inline.target ?? '';
}

/// A cross reference (`<<id>>`, `xref:id[]`).
final class CrossReference extends Inline {
  new _(super._node) : super._();

  /// The ID referred to (including a document path for an inter-document
  /// reference, `other.adoc#id`).
  String get refid => _node.attributes['refid'] ?? '';

  /// The document path of an inter-document reference, if any.
  String? get path => _node.attributes['path'];

  /// The URL the reference links to.
  String get target => _inline.target ?? '';
}

/// An inline anchor (`[[id]]`, `anchor:id[]`).
final class InlineAnchor extends Inline {
  new _(super._node) : super._();

  /// The ID of the anchor.
  String get anchorId => _inline.target ?? id ?? '';
}

/// A bibliography anchor (`[[[id]]]`).
final class BibliographyAnchor extends Inline {
  new _(super._node) : super._();

  /// The ID of the anchor.
  String get anchorId => _inline.id ?? _inline.target ?? '';
}

/// The kinds of formatted text.
enum FormattedKind {
  /// `*strong*`
  strong,

  /// `_emphasis_`
  emphasis,

  /// `` `monospace` ``
  monospace,

  /// `#mark#`
  mark,

  /// `^superscript^`
  superscript,

  /// `~subscript~`
  subscript,

  /// `"`double quotes`"`
  doubleQuoted,

  /// `'`single quotes`'`
  singleQuoted,

  /// `[.role]#text#`: text with a role and no other formatting.
  unquoted,
}

/// Formatted text.
final class Formatted extends Inline {
  new _(super._node) : super._();

  /// The kind of formatting.
  FormattedKind get kind => switch (_inline.type) {
    'strong' => FormattedKind.strong,
    'emphasis' => FormattedKind.emphasis,
    'monospaced' => FormattedKind.monospace,
    'mark' => FormattedKind.mark,
    'superscript' => FormattedKind.superscript,
    'subscript' => FormattedKind.subscript,
    'double' => FormattedKind.doubleQuoted,
    'single' => FormattedKind.singleQuoted,
    _ => FormattedKind.unquoted,
  };
}

/// Inline math (`stem:[...]`, `latexmath:[...]`, `asciimath:[...]`).
final class InlineStem extends Inline {
  new _(super._node) : super._();

  /// The notation of the math.
  StemNotation get notation => _inline.type == 'asciimath'
      ? StemNotation.asciimath
      : StemNotation.latexmath;
}

/// A footnote (`footnote:[text]`), or a reference to one
/// (`footnote:id[]`).
final class Footnote extends Inline {
  new _(super._node) : super._();

  /// The footnote number.
  int? get number => int.tryParse(_node.attributes['index'] ?? '');

  /// Whether this refers to a footnote defined elsewhere.
  bool get isReference => _inline.type == 'xref';
}

/// An inline image (`image:target[]`).
final class InlineImage extends Inline {
  new _(super._node) : super._();

  /// The image path or URL as written.
  String get target => _inline.target ?? '';

  /// The alternative text.
  String get alt => _inline.alt;

  @override
  String get plainText => alt;
}

/// An icon (`icon:name[]`).
final class Icon extends Inline {
  new _(super._node) : super._();

  /// The icon name.
  String get name => _inline.target ?? '';
}

/// A keyboard shortcut (`kbd:[Ctrl+T]`).
final class Keyboard extends Inline {
  new _(super._node) : super._();

  /// The keys.
  List<String> get keys => _inline.keys ?? const [];

  @override
  String get plainText => keys.join('+');
}

/// A UI button (`btn:[Save]`).
final class Button extends Inline {
  new _(super._node) : super._();
}

/// A menu selection (`menu:File[Save]`).
final class Menu extends Inline {
  new _(super._node) : super._();

  /// The top-level menu.
  String get menu => _node.attributes['menu'] ?? '';

  /// The submenus leading to the item.
  List<String> get submenus => _inline.submenus ?? const [];

  /// The menu item, if any.
  String? get item => _node.attributes['menuitem'];

  @override
  String get plainText => [menu, ...submenus, ?item].join(' > ');
}

/// A forced line break (` +` at the end of a line).
final class LineBreak extends Inline {
  new _(super._node) : super._();
}

/// A callout in a listing (`<1>`).
final class Callout extends Inline {
  new _(super._node) : super._();

  /// The callout number.
  int get number => int.tryParse(_inline.text ?? '') ?? 0;
}

/// An index term (`indexterm:[...]`, `((term))`).
final class IndexTerm extends Inline {
  new _(super._node) : super._();

  /// The terms: primary, then secondary and tertiary, if any.
  List<String> get terms => _inline.terms ?? [?_inline.text];

  /// Whether the term also appears in the text (`((term))`).
  bool get isVisible => _inline.type == 'visible';
}

/// An inline element of a kind asciidart does not define, created by an
/// extension.
final class OtherInline extends Inline {
  new _(super._node) : super._();

  /// The element's context, as the extension named it.
  String get context => _node.contextName;
}
