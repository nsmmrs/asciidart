/// Version information for the Dart port of Asciidoctor.
abstract final class Asciidoctor {
  /// The Asciidoctor release whose behavior this port matches.
  ///
  /// Reported as the `asciidoctor-version` document attribute, in the HTML
  /// generator meta tag and the man page header, and by `--version`, so
  /// documents that check `{asciidoctor-version}` see the release they get.
  /// See ADR-0003.
  static const String version = '2.0.26';

  /// The version of this package (the `asciidoctor-dart-version` document
  /// attribute). Keep in sync with `version:` in pubspec.yaml.
  static const String packageVersion = '0.1.0';
}
