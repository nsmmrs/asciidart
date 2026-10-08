/// The `ptome` command line, for building a custom command.
library;

import 'package:ptome/src/api/api.dart';
import 'package:ptome/src/cli/run.dart' as impl;

/// Runs the `ptome` command line with [args], reporting through the
/// process exit code.
///
/// With [Ptome], its extensions, HTML override and highlighters apply to
/// every conversion, and its attributes and template directories come
/// before those given on the command line: a custom command with Dart code
/// compiled in. `ptome init-config DIR` generates a project for one.
///
/// ```dart
/// import 'package:ptome/ptome.dart';
/// import 'package:ptome/cli.dart';
///
/// Future<void> main(List<String> args) => runCli(
///   args,
///   ptome: Ptome(extensions: [/* ... */]),
/// );
/// ```
Future<void> runCli(List<String> args, {Ptome? ptome}) => impl.runCli(
  args,
  configure: ptome == null ? null : (options) => configureCli(ptome, options),
);
