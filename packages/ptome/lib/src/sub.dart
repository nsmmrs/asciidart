/// Substitutions: the passes applied to inline text.
library;

/// A substitution: one pass over inline text, in the order a block's
/// substitution list gives.
enum Sub {
  /// Escapes `<`, `>` and `&`.
  specialcharacters,

  /// Formatted text (`*strong*`, `_emphasis_`, ...).
  quotes,

  /// Attribute references (`{name}`).
  attributes,

  /// Typographic replacements (`--`, `(C)`, ...).
  replacements,

  /// Macros, links and cross references.
  macros,

  /// Syntax highlighting (source blocks; never written by documents).
  highlight,

  /// Callout marks in verbatim blocks.
  callouts,

  /// Hard line breaks.
  postReplacements('post_replacements');

  new([this._asciidoc]);

  final String? _asciidoc;

  /// The name documents use for this substitution.
  String get asciidoc => _asciidoc ?? name;

  static final Map<String, Sub> _byName = {
    for (final sub in values) sub.asciidoc: sub,
  };

  /// The substitution documents name [name], if any.
  static Sub? tryParse(String name) => _byName[name];
}

/// Where a substitution list is written: on a block (`subs` attribute) or
/// in an inline passthrough (`pass:q[]`).
enum SubsScope {
  /// A block's `subs` attribute; callouts are allowed.
  block,

  /// A passthrough macro; callouts are not.
  inline;

  /// Whether documents may name [sub] here. Port of `SUB_OPTIONS`.
  bool allows(Sub sub) => switch (sub) {
    .highlight => false,
    .callouts => this == block,
    _ => true,
  };
}

/// What a reference to an attribute that is not set turns into (the
/// `attribute-missing` attribute).
enum AttributeMissing {
  /// The reference is left as written (the default).
  skip,

  /// The reference is removed.
  drop,

  /// The line containing the reference is removed.
  dropLine('drop-line'),

  /// The reference is left as written, with a warning.
  warn;

  new([this._asciidoc]);

  final String? _asciidoc;

  /// The value of the `attribute-missing` attribute that selects this mode.
  String get asciidoc => _asciidoc ?? name;

  /// The mode [value] selects: [skip] for anything unrecognized, as
  /// Asciidoctor.
  static AttributeMissing parse(String? value) => switch (value) {
    'drop' => drop,
    'drop-line' => dropLine,
    'warn' => warn,
    _ => skip,
  };
}
