/// The `asciidoctor` command line as a library.
///
/// Call `runCli` from your own `main` to build a custom binary, for example
/// one that registers extensions or transform functions first (see
/// `asciidoctor init-config`).
library;

export 'src/cli/run.dart' show runCli;
