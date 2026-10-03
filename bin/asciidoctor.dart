// Command-line entry point for the Dart port of Asciidoctor.
//
// Port of `bin/asciidoctor`: parses arguments via `Invoker`, runs the
// processor, and exits with the invoker's exit code.
import 'dart:io';

import 'package:asciidoctor/src/cli/invoker.dart';

Future<void> main(List<String> args) async {
  try {
    final invoker = Invoker.fromArgs(args);
    await invoker.invokeAsync();
    exitCode = invoker.code;
  } catch (e, stackTrace) {
    // Mirror Ruby's uncaught-exception behavior (`bin/asciidoctor` has no
    // rescue): the message plus backtrace go to STDERR and the process
    // exits 1. Reached for `--trace` re-raises and for the errors
    // `Options.parse!` lets propagate (ambiguous option, needless
    // argument, unloadable `--require` under `--trace`).
    stderr.writeln(e);
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}
