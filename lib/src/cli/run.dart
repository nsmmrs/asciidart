/// Reusable command-line entrypoint for the Dart port of Asciidoctor.
///
/// The `bin/asciidart.dart` main delegates here, and XMonad-style custom
/// binaries (ADR-0002 T6, see `init_config.dart`) call [runCli] after
/// registering their own transforms. Behavior — argument parsing,
/// conversion, diagnostics, exit codes — is identical in both cases.
library;

import 'dart:async';

import 'package:asciidart/src/cli/diagnostics.dart';
import 'package:asciidart/src/cli/init_config.dart';
import 'package:asciidart/src/cli/invoker.dart';
import 'package:asciidart/src/io.dart' as io;

/// Runs the Asciidoctor CLI, reporting through the process exit code.
///
/// Library entrypoint for custom binaries: register transforms on
/// `TemplateRegistry.global` (from `package:asciidart/converter.dart`),
/// then `await runCli(args)`.
///
/// A first argument of `init-config` runs the project scaffold instead
/// of converting (see [runInitConfig]); everything else behaves exactly
/// like the stock CLI.
Future<void> runCli(List<String> args) async {
  // A failed stdout also completes its done future with the error. A
  // reader that went away (`asciidart ... | head`) ends the run quietly;
  // any other write failure is reported.
  unawaited(
    io.standardOutputDone.then<void>(
      (_) {},
      onError: (Object error) {
        if (io.isBrokenPipe(error)) return;
        io.standardError.writeln(failureLine(error));
        io.exitCode = 1;
      },
    ),
  );
  io.exitCode = await runCliCode(args);
}

/// Runs the Asciidoctor CLI, returning the process exit code.
///
/// Testable core of [runCli] (which only reports the result through the
/// process exit code). [out] and [err] buffer conversion output and
/// diagnostics (defaulting to the process streams). A failure that escapes the
/// invoker (with `--trace`, conversion failures are rethrown) is reported
/// with its backtrace and returns 1.
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
    // Last-resort CLI boundary for anything that escapes, Errors included.
  } on Object catch (e, stackTrace) {
    // The reader of the output went away (`asciidart ... | head`).
    if (io.isBrokenPipe(e)) return 0;
    (err ?? io.standardError)
      ..writeln(failureLine(e))
      ..writeln(stackTrace);
    return 1;
  }
}
