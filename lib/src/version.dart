/// Version information for asciidart.
abstract final class Asciidoctor {
  /// The Asciidoctor release whose behavior asciidart is compatible with.
  ///
  /// Reported as the `asciidoctor-version` document attribute and by
  /// `--version`, so documents that check `{asciidoctor-version}` see the
  /// release whose behavior they get. See ADR-0003.
  static const String version = '2.0.26';

  /// The version of this package: the `asciidart-version` document
  /// attribute, the HTML generator meta tag and the man page header. Keep in
  /// sync with `version:` in pubspec.yaml.
  static const String packageVersion = '0.1.0';
}
