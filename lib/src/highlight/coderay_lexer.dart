/// Real CodeRay lexing backend behind the [SourceLexer] seam.
///
/// [CodeRaySourceLexer] replicates `CodeRay::Duo[lang, :html, opts]` end to
/// end for the languages it supports: input normalization, scanner
/// dispatch, token scanning ([scanRubyTokens] / the plain-text fallback)
/// and HTML encoding ([CoderayHtmlEncoder]).
///
/// ## Language dispatch
///
/// The adapter resolves the block language like Asciidoctor's CodeRay
/// adapter (verified against CodeRay
/// 1.1.3, whose plugin lookup downcases through its default proc and falls
/// back to the `:text` scanner for unknown ids):
///
/// * Absent, empty and unknown languages scan as plain text (the `:text`
///   scanner emits the whole input as one `:plain` token).
/// * The `_languageAliases` map (port of `scanners/_map.rb`, matched
///   case-sensitively) redirects to the mapped scanner.
/// * Anything else that is all word characters resolves case-insensitively
///   to a scanner file stem; anything else scans as plain text.
/// * The `scanner` stem raises, mirroring the unrescued
///   `PluginNotFound` the oracle throws for `[source,scanner]` (a
///   load error, which Asciidoctor's adapter does not catch).
///
/// ## Supported languages
///
/// `ruby` (including the `irb` alias) and `text` (including the `plain`
/// and `plaintext` aliases) highlight byte-identically to the oracle.
/// Every other shipped CodeRay scanner (`c`, `cpp`, `clojure`, `css`,
/// `debug`, `delphi`, `diff`, `erb`, `go`, `groovy`, `haml`, `html`,
/// `java`, `java_script`, `json`, `lua`, `php`, `python`, `raydebug`,
/// `sass`, `sql`, `taskpaper`, `xml`, `yaml`) throws [UnimplementedError]
/// from [CodeRaySourceLexer.highlight]: porting those scanners is future
/// work, and silently degrading them to plain text would fake oracle
/// output (the oracle really highlights them).
library;

import 'package:asciidoctor/src/highlight/coderay_html.dart';
import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:asciidoctor/src/highlight/ruby_scanner.dart';

/// A real CodeRay [SourceLexer] backend for Ruby and plain text.
///
/// CodeRay uses only [highlight] (its stylesheet is a static asset), so
/// the style members throw [UnimplementedError] — the seam contract
/// explicitly allows this, and the adapter never calls them.
class CodeRaySourceLexer implements SourceLexer {
  /// Creates a CodeRay lexing backend.
  const new();

  @override
  String get name => 'coderay';

  @override
  String? highlight(HighlightRequest request) {
    final lang = _resolveLanguage(request.language);
    final encoder = CoderayHtmlEncoder(
      css: request.cssMode,
      lineNumbers: request.numberLines,
      startLine: request.startLineNumber ?? 1,
      highlightLines: request.highlightLines,
    );
    final source = _normalize(request.source);
    if (lang == 'ruby') {
      scanRubyTokens(source, encoder);
    } else {
      // Port of the `:text` scanner: one `:plain` token over the whole
      // input (which the encoder emits escaped but otherwise bare).
      encoder.textToken(source, 'plain');
    }
    return encoder.finish();
  }

  @override
  bool styleAvailable(String style) => throw UnimplementedError(
    'CodeRay has no named styles; its stylesheet is a static asset.',
  );

  @override
  String? baseStyle(String style) => throw UnimplementedError(
    'CodeRay has no named styles; its stylesheet is a static asset.',
  );

  @override
  String? stylesheet(String style) => throw UnimplementedError(
    'CodeRay has no named styles; its stylesheet is a static asset.',
  );
}

/// Normalizes newlines (port of `Scanner.normalize`'s `to_unix`, which is
/// all that applies once encoding is known-Unicode as in Dart).
String _normalize(String source) =>
    source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Resolves a block language to a supported scanner id (`ruby` or `text`).
///
/// Throws [UnimplementedError] for shipped CodeRay scanners that have no
/// Dart port yet, and [StateError] for the `scanner` stem (mirroring the
/// oracle's unrescued `PluginNotFound`).
String _resolveLanguage(String? language) {
  if (language == null || language.isEmpty) return 'text';
  final mapped = _languageAliases[language];
  if (mapped != null) return _resolveStem(mapped, language);
  if (!_wordChars.hasMatch(language)) return 'text';
  return _resolveStem(language.toLowerCase(), language);
}

/// Resolves a lowercased scanner stem (or exact alias target) to a
/// supported scanner id.
String _resolveStem(String stem, String language) {
  if (stem == 'ruby' || stem == 'text') return stem;
  if (stem == 'scanner') {
    throw StateError(
      'No CodeRay::Scanners plugin for "$language" '
      '(mirrors the oracle PluginNotFound).',
    );
  }
  if (_knownStems.contains(stem)) {
    throw UnimplementedError(
      'CodeRay highlighting for language "$language" needs its scanner '
      'port; only ruby and text are implemented.',
    );
  }
  return 'text';
}

/// Matches languages made only of word characters (port of the
/// `id[/\w+/] == id` check in plugin validation; `\w` is ASCII-only in
/// both engines).
final RegExp _wordChars = RegExp(r'^\w+$', unicode: true);

/// Scanner id aliases (port of `scanners/_map.rb`, matched
/// case-sensitively like the original).
const Map<String, String> _languageAliases = <String, String>{
  'c++': 'cpp',
  'cplusplus': 'cpp',
  'ecmascript': 'java_script',
  'ecma_script': 'java_script',
  'rhtml': 'erb',
  'eruby': 'erb',
  'irb': 'ruby',
  'javascript': 'java_script',
  'js': 'java_script',
  'pascal': 'delphi',
  'patch': 'diff',
  'plain': 'text',
  'plaintext': 'text',
  'xhtml': 'html',
  'yml': 'yaml',
};

/// Lowercased scanner file stems shipped by CodeRay 1.1.3 (every id whose
/// plugin file exists and registers a scanner; `ruby` and `text` are
/// ported, `scanner` raises, the rest are future ports).
const Set<String> _knownStems = <String>{
  'c',
  'clojure',
  'cpp',
  'css',
  'debug',
  'delphi',
  'diff',
  'erb',
  'go',
  'groovy',
  'haml',
  'html',
  'java',
  'java_script',
  'json',
  'lua',
  'php',
  'python',
  'raydebug',
  'ruby',
  'sass',
  'sql',
  'taskpaper',
  'text',
  'xml',
  'yaml',
};
