/// The `asciidart` command line, for building a custom command.
library;

import 'package:asciidart/src/api/api.dart';
import 'package:asciidart/src/cli/run.dart' as impl;

/// Runs the `asciidart` command line with [args], reporting through the
/// process exit code.
///
/// With [asciidart], its extensions, HTML override and highlighters apply to
/// every conversion, and its attributes and template directories come
/// before those given on the command line: a custom command with Dart code
/// compiled in. `asciidart init-config DIR` generates a project for one.
///
/// ```dart
/// import 'package:asciidart/asciidart.dart';
/// import 'package:asciidart/cli.dart';
///
/// Future<void> main(List<String> args) => runCli(
///   args,
///   asciidart: Asciidart(extensions: [/* ... */]),
/// );
/// ```
Future<void> runCli(List<String> args, {Asciidart? asciidart}) => impl.runCli(
  args,
  configure: asciidart == null
      ? null
      : (options) => configureCli(asciidart, options),
);
