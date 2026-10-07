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

  /// The value of the `stylesheet` attribute that names Asciidoctor's
  /// stylesheet as it is, without asciidart's house rules (ADR-0011).
  static const String classicStylesheetKey = 'asciidoctor';

  String? _primaryStylesheetData;
  String? _classicStylesheetData;

  /// The file name of the primary stylesheet.
  String get primaryStylesheetName => defaultStylesheetName;

  /// The default stylesheet: Asciidoctor's, then asciidart's house rules
  /// (doc/style.md).
  String get primaryStylesheetData => _primaryStylesheetData ??=
      '$classicStylesheetData\n'
      '${_rstrip(EmbeddedData.file('stylesheets/asciidart-house.css'))}';

  /// Asciidoctor's default stylesheet, as it is (`stylesheet=asciidoctor`).
  String get classicStylesheetData => _classicStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-default.css'),
  );

  /// The built-in stylesheet for a `stylesheet` attribute of [key]: the
  /// classic one for [classicStylesheetKey], else the default.
  String dataFor(String? key) => key == classicStylesheetKey
      ? classicStylesheetData
      : primaryStylesheetData;

  /// Writes the built-in stylesheet for a `stylesheet` attribute of [key] to
  /// [targetDir].
  void writePrimaryStylesheet([String targetDir = '.', String? key]) {
    io.writeString('$targetDir/$primaryStylesheetName', dataFor(key));
  }
}

/// Strips trailing ASCII whitespace and null bytes (unlike Dart's
/// `trimRight`, this leaves non-ASCII
/// whitespace untouched).
String _rstrip(String value) =>
    value.replaceAll(RegExp('[\x00 \t\n\v\f\r]+\$'), '');
