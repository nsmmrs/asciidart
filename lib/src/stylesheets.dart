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

  /// The shared [Stylesheets] instance (created lazily on first access).
  static final Stylesheets instance = Stylesheets();

  String? _primaryStylesheetData;

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
}

/// Strips trailing ASCII whitespace and null bytes (unlike Dart's
/// `trimRight`, this leaves non-ASCII
/// whitespace untouched).
String _rstrip(String value) =>
    value.replaceAll(RegExp('[\x00 \t\n\v\f\r]+\$'), '');
