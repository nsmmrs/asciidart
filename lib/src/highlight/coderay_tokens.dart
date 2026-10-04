/// Token vocabulary shared by the CodeRay scanner and HTML encoder ports.
///
/// Dart port of `CodeRay::TokenKinds` (`token_kinds.rb` in CodeRay 1.1.3):
/// the map from token kind to CSS class. Kinds mapped to `null`
/// (`:ident`, `:operator`, `:space`, `:plain`) emit no span.
///
/// Token kinds are plain strings (CodeRay's kind names) so scanners stay
/// decoupled from the encoder; [CoderayTokenSink] is the streaming interface
/// scanners write to (the `text_token` / `begin_group` / `end_group` side of
/// `CodeRay::Encoders::Encoder`, which is also the `:tokens` object the
/// scanner writes into — see `Encoder#encode`).
library;

/// Receives the token stream produced by a CodeRay scanner port.
///
/// Mirrors the encoder half of `CodeRay::Encoders::Encoder#token`: plain
/// [textToken] events plus group open/close events. (CodeRay also supports
/// line events, but the scanners here never emit them.)
abstract interface class CoderayTokenSink {
  /// Records [text] of token kind [kind] (a kind name such as
  /// `'string'`, `'keyword'` or `'space'`).
  void textToken(String text, String kind);

  /// Opens a token group of kind [kind] (for example a string whose
  /// delimiters and content arrive as separate tokens).
  void beginGroup(String kind);

  /// Closes the innermost open token group, which must be [kind].
  void endGroup(String kind);
}

/// Maps a CodeRay token kind to its CSS class (port of `TokenKinds`).
///
/// Returns `null` for the transparent kinds (`ident`, `operator`, `space`,
/// `plain`, `unknown`) and for unknown kinds.
String? coderayTokenClass(String kind) => _coderayTokenClasses[kind];

/// Port of the `TokenKinds.update(...)` table plus the `:method` and
/// `:unknown` aliases.
const Map<String, String> _coderayTokenClasses = <String, String>{
  'debug': 'debug',
  'annotation': 'annotation',
  'attribute_name': 'attribute-name',
  'attribute_value': 'attribute-value',
  'binary': 'binary',
  'char': 'char',
  'class': 'class',
  'class_variable': 'class-variable',
  'color': 'color',
  'comment': 'comment',
  'constant': 'constant',
  'content': 'content',
  'decorator': 'decorator',
  'definition': 'definition',
  'delimiter': 'delimiter',
  'directive': 'directive',
  'doctype': 'doctype',
  'docstring': 'docstring',
  'done': 'done',
  'entity': 'entity',
  'error': 'error',
  'escape': 'escape',
  'exception': 'exception',
  'filename': 'filename',
  'float': 'float',
  'function': 'function',
  'global_variable': 'global-variable',
  'hex': 'hex',
  'id': 'id',
  'imaginary': 'imaginary',
  'important': 'important',
  'include': 'include',
  'inline': 'inline',
  'inline_delimiter': 'inline-delimiter',
  'instance_variable': 'instance-variable',
  'integer': 'integer',
  'key': 'key',
  'keyword': 'keyword',
  'label': 'label',
  'local_variable': 'local-variable',
  'map': 'map',
  'method': 'function',
  'modifier': 'modifier',
  'namespace': 'namespace',
  'octal': 'octal',
  'predefined': 'predefined',
  'predefined_constant': 'predefined-constant',
  'predefined_type': 'predefined-type',
  'preprocessor': 'preprocessor',
  'pseudo_class': 'pseudo-class',
  'regexp': 'regexp',
  'reserved': 'reserved',
  'shell': 'shell',
  'string': 'string',
  'symbol': 'symbol',
  'tag': 'tag',
  'type': 'type',
  'value': 'value',
  'variable': 'variable',
  'change': 'change',
  'delete': 'delete',
  'head': 'head',
  'insert': 'insert',
  'eyecatcher': 'eyecatcher',
};
