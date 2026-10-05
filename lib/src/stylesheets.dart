/// A utility class for working with the built-in stylesheets.
///
/// Dart port of `lib/asciidoctor/stylesheets.rb`.
///
/// Stylesheet data comes from the compile-time
/// embedded data in [EmbeddedData] (see `tool/embed_data.dart`). The returned
/// strings are identical: file contents with trailing whitespace stripped.
library;

import 'package:asciidart/src/data.g.dart';
import 'package:asciidart/src/io.dart' as io;

/// A utility class for working with the built-in stylesheets.
///
/// See the library documentation for an overview.
class Stylesheets {
  /// Creates a stylesheets helper. Prefer [Stylesheets.instance].
  new();

  /// File name of the default Asciidoctor stylesheet.
  static const String defaultStylesheetName = 'asciidoctor.css';

  /// File name of the default CodeRay stylesheet.
  ///
  /// Mirrors `SyntaxHighlighter::CodeRay.stylesheet_basename`.
  static const String defaultCoderayStylesheetName = 'coderay-asciidoctor.css';

  /// Default Pygments style name.
  ///
  /// Mirrors `SyntaxHighlighter::Pygments::DEFAULT_STYLE`.
  static const String pygmentsDefaultStyle = 'default';

  /// Fallback returned when the Pygments stylesheet cannot be generated.
  ///
  /// What Asciidoctor emits when the Pygments library is unavailable. The
  /// syntax-highlighter port owns the live Pygments CSS strategy; until it
  /// lands, the library is always unavailable in the Dart port.
  static const String pygmentsUnavailableStylesheet =
      '/* Pygments CSS disabled because Pygments is not available. */';

  /// The shared [Stylesheets] instance (created lazily on first access).
  static final Stylesheets instance = Stylesheets();

  String? _primaryStylesheetData;
  String? _coderayStylesheetData;

  /// The file name of the primary stylesheet.
  String get primaryStylesheetName => defaultStylesheetName;

  /// Reads the contents of the default Asciidoctor stylesheet.
  String get primaryStylesheetData => _primaryStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-default.css'),
  );

  /// Writes the primary stylesheet to [targetDir].
  void writePrimaryStylesheet([String targetDir = '.']) {
    io.writeString('$targetDir/$primaryStylesheetName', primaryStylesheetData);
  }

  /// The file name of the default CodeRay stylesheet.
  String get coderayStylesheetName => defaultCoderayStylesheetName;

  /// Reads the contents of the default CodeRay stylesheet.
  String get coderayStylesheetData => _coderayStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/$coderayStylesheetName'),
  );

  /// Writes the CodeRay stylesheet to [targetDir].
  void writeCoderayStylesheet([String targetDir = '.']) {
    io.writeString('$targetDir/$coderayStylesheetName', coderayStylesheetData);
  }

  /// The file name of the Pygments stylesheet for [style].
  String pygmentsStylesheetName([String? style]) =>
      'pygments-${style ?? pygmentsDefaultStyle}.css';

  /// Generates the Pygments stylesheet with the specified [style].
  ///
  /// Always returns the library-unavailable fallback (see
  /// [pygmentsUnavailableStylesheet]) until the syntax-highlighter port
  /// provides the live Pygments CSS strategy.
  String pygmentsStylesheetData([String? style]) =>
      pygmentsUnavailableStylesheet;

  /// Writes the Pygments stylesheet for [style] to [targetDir].
  void writePygmentsStylesheet([String targetDir = '.', String? style]) {
    io.writeString(
      '$targetDir/${pygmentsStylesheetName(style)}',
      pygmentsStylesheetData(style),
    );
  }
}

/// Strips trailing ASCII whitespace and null bytes (unlike Dart's
/// `trimRight`, this leaves non-ASCII
/// whitespace untouched).
String _rstrip(String value) =>
    value.replaceAll(RegExp('[\x00 \t\n\v\f\r]+\$'), '');
