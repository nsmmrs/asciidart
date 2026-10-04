/// Reusable command-line entrypoint for the Dart port of Asciidoctor.
///
/// The `bin/asciidoctor.dart` main delegates here, and XMonad-style custom
/// binaries (ADR-0002 T6, see `init_config.dart`) call [runCli] after
/// registering their own transforms. Behavior — argument parsing,
/// conversion, diagnostics, exit codes — is identical in both cases.
library;

import 'dart:io';

import 'package:asciidoctor/src/cli/init_config.dart';
import 'package:asciidoctor/src/cli/invoker.dart';

/// Runs the Asciidoctor CLI, reporting through [exitCode].
///
/// Library entrypoint for custom binaries: register transforms on
/// `TemplateRegistry.global` (from `package:asciidoctor/asciidoctor.dart`),
/// then `await runCli(args)`.
///
/// A first argument of `init-config` runs the project scaffold instead
/// of converting (see [runInitConfig]); everything else behaves exactly
/// like the stock CLI.
Future<void> runCli(List<String> args) async {
  exitCode = await runCliCode(args);
}

/// Runs the Asciidoctor CLI, returning the process exit code.
///
/// Testable core of [runCli] (which only reports the result through
/// [exitCode]). [out] and [err] buffer conversion output and diagnostics
/// (defaulting to the process streams); the uncaught-exception path
/// writes the error plus backtrace and returns 1, mirroring
/// `bin/asciidoctor`'s lack of a rescue.
Future<int> runCliCode(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  if (args.isNotEmpty && args.first == 'init-config') {
    return runInitConfig(args.sublist(1), out: out, err: err);
  }
  try {
    final invoker = Invoker.fromArgs(args, out: out, err: err);
    if (out != null) invoker.redirectStreams(out, err);
    await invoker.invokeAsync();
    return invoker.code;
    // Last-resort CLI boundary: mirror Ruby's uncaught-exception exit for
    // anything that escapes, Errors included.
    // ignore: avoid_catches_without_on_clauses
  } catch (e, stackTrace) {
    // Mirror Ruby's uncaught-exception behavior (`bin/asciidoctor` has no
    // rescue): the message plus backtrace go to STDERR and the process
    // exits 1. Reached for `--trace` re-raises and for the errors
    // `Options.parse!` lets propagate (ambiguous option, needless
    // argument, unloadable `--require` under `--trace`).
    (err ?? stderr)
      ..writeln(e)
      ..writeln(stackTrace);
    return 1;
  }
}
