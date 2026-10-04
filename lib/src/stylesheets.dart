/// A utility class for working with the built-in stylesheets.
///
/// Dart port of `lib/asciidoctor/stylesheets.rb`.
///
/// Unlike the Ruby implementation, which reads stylesheet data from
/// `STYLESHEETS_DIR` at runtime, this port reads from the compile-time
/// embedded data in [EmbeddedData] (see `tool/embed_data.dart`). The returned
/// strings are identical: file contents with trailing whitespace stripped.
library;

import 'dart:io';

import 'package:asciidoctor/src/data.g.dart';

/// A utility class for working with the built-in stylesheets.
///
/// See the library documentation for an overview.
class Stylesheets {
  /// Creates a stylesheets helper. Prefer [Stylesheets.instance].
  Stylesheets();

  /// File name of the default Asciidoctor stylesheet.
  static const String defaultStylesheetName = 'asciidoctor.css';

  /// File name of the default CodeRay stylesheet.
  ///
  /// Mirrors `SyntaxHighlighter::CodeRay.stylesheet_basename`, which the Ruby
  /// implementation delegates to.
  static const String defaultCoderayStylesheetName = 'coderay-asciidoctor.css';

  /// Default Pygments style name.
  ///
  /// Mirrors `SyntaxHighlighter::Pygments::DEFAULT_STYLE`, which the Ruby
  /// implementation delegates to.
  static const String pygmentsDefaultStyle = 'default';

  /// Fallback returned when the Pygments stylesheet cannot be generated.
  ///
  /// Mirrors the Ruby `Pygments.read_stylesheet` branch taken when the
  /// Pygments library is unavailable. The syntax-highlighter port owns the
  /// live Pygments CSS strategy; until it lands, the library is always
  /// unavailable in the Dart port.
  static const String pygmentsUnavailableStylesheet =
      '/* Pygments CSS disabled because Pygments is not available. */';

  static Stylesheets? _instance;

  /// Returns the shared [Stylesheets] instance.
  static Stylesheets get instance => _instance ??= Stylesheets();

  String? _primaryStylesheetData;
  String? _coderayStylesheetData;

  /// The file name of the primary stylesheet.
  String get primaryStylesheetName => defaultStylesheetName;

  /// Reads the contents of the default Asciidoctor stylesheet.
  String get primaryStylesheetData => _primaryStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-default.css'),
  );

  /// Generates code to embed the primary stylesheet.
  ///
  /// Returns the primary stylesheet data wrapped in a `<style>` tag.
  /// Deprecated in the Ruby implementation; kept for parity.
  String embedPrimaryStylesheet() =>
      '<style>\n$primaryStylesheetData\n</style>';

  /// Writes the primary stylesheet to [targetDir].
  void writePrimaryStylesheet([String targetDir = '.']) {
    File('$targetDir/$primaryStylesheetName')
        .writeAsStringSync(primaryStylesheetData);
  }

  /// The file name of the default CodeRay stylesheet.
  String get coderayStylesheetName => defaultCoderayStylesheetName;

  /// Reads the contents of the default CodeRay stylesheet.
  String get coderayStylesheetData => _coderayStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/$coderayStylesheetName'),
  );

  /// Generates code to embed the CodeRay stylesheet.
  ///
  /// Returns the CodeRay stylesheet data wrapped in a `<style>` tag.
  /// Deprecated in the Ruby implementation; kept for parity.
  String embedCoderayStylesheet() =>
      '<style>\n$coderayStylesheetData\n</style>';

  /// Writes the CodeRay stylesheet to [targetDir].
  void writeCoderayStylesheet([String targetDir = '.']) {
    File('$targetDir/$coderayStylesheetName')
        .writeAsStringSync(coderayStylesheetData);
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

  /// Generates code to embed the Pygments stylesheet.
  ///
  /// Returns the Pygments stylesheet data for the specified [style] wrapped
  /// in a `<style>` tag. Deprecated in the Ruby implementation; kept for
  /// parity.
  String embedPygmentsStylesheet([String? style]) =>
      '<style>\n${pygmentsStylesheetData(style)}\n</style>';

  /// Writes the Pygments stylesheet for [style] to [targetDir].
  void writePygmentsStylesheet([String targetDir = '.', String? style]) {
    File('$targetDir/${pygmentsStylesheetName(style)}')
        .writeAsStringSync(pygmentsStylesheetData(style));
  }
}

/// Strips trailing ASCII whitespace and null bytes, mirroring Ruby's
/// `String#rstrip` (which, unlike Dart's `trimRight`, leaves non-ASCII
/// whitespace untouched).
String _rstrip(String value) =>
    value.replaceAll(RegExp('[\x00 \t\n\v\f\r]+\$'), '');
