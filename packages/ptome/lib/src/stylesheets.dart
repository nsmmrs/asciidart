/// A utility class for working with the built-in stylesheets.
///
/// Dart port of `lib/asciidoctor/stylesheets.rb`.
///
/// Stylesheet data comes from the compile-time
/// embedded data in [EmbeddedData] (see `tool/embed_data.dart`). The returned
/// strings are identical: file contents with trailing whitespace stripped.
library;

import 'package:ptome/src/data.g.dart';
import 'package:ptome/src/io.dart' as io;

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
  /// stylesheet as it is, without Ptome's house rules (ADR-0011).
  static const String classicStylesheetKey = 'asciidoctor';

  /// The value of the `stylesheet` attribute that names the stylesheet of
  /// Asciidoctor's latest stable release (2.0.26), which
  /// `asciidoctor-compat` uses for HTML.
  static const String stableStylesheetKey = 'asciidoctor-2.0.26';

  /// Whether [key] names one of the stylesheets Ptome carries (Asciidoctor's,
  /// or the stable release's).
  static bool isAsciidoctor(String? key) =>
      key == classicStylesheetKey || key == stableStylesheetKey;

  String? _primaryStylesheetData;
  String? _classicStylesheetData;
  String? _stableStylesheetData;

  /// The file name of the primary stylesheet.
  String get primaryStylesheetName => defaultStylesheetName;

  /// The default stylesheet: Asciidoctor's, then Ptome's house rules
  /// (doc/style.md).
  String get primaryStylesheetData => _primaryStylesheetData ??=
      '$classicStylesheetData\n'
      '${_rstrip(EmbeddedData.file('stylesheets/ptome-house.css'))}';

  /// Asciidoctor's default stylesheet, as it is (`stylesheet=asciidoctor`).
  String get classicStylesheetData => _classicStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-default.css'),
  );

  /// The stylesheet of Asciidoctor's latest stable release
  /// (`stylesheet=asciidoctor-2.0.26`, data/stylesheets/asciidoctor-2.0.26.css,
  /// as the 2.0.26 gem has it).
  String get stableStylesheetData => _stableStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-2.0.26.css'),
  );

  /// The built-in stylesheet for a `stylesheet` attribute of [key]: the
  /// classic one for [classicStylesheetKey], the stable release's for
  /// [stableStylesheetKey], else the default.
  String dataFor(String? key) => switch (key) {
    classicStylesheetKey => classicStylesheetData,
    stableStylesheetKey => stableStylesheetData,
    _ => primaryStylesheetData,
  };

  /// The Google Fonts families the built-in stylesheet of [key] is set in
  /// (the `webfonts` attribute's default): the stable release's monospace
  /// face is Droid Sans Mono, the others' Noto Sans Mono.
  String webfontsFor(String? key) =>
      'Open+Sans:300,300italic,400,400italic,600,600italic%7C'
      'Noto+Serif:400,400italic,700,700italic%7C'
      '${key == stableStylesheetKey ? 'Droid' : 'Noto'}+Sans+Mono:400,700';

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
