import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:ascii_docs/ascii_docs.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('ascii_docs', 'The ascii-docs corpus tools.')
        ..addCommand(RegenCommand())
        ..addCommand(TestCommand())
        ..addCommand(PoolCommand())
        ..addCommand(AnchorCommand())
        ..addCommand(GenCommand())
        ..addCommand(FuzzCommand())
        ..addCommand(TriageCommand())
        ..addCommand(CoverageCommand());
  var code = 0;
  try {
    code = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    code = 64;
  }
  // Worker processes and isolates must not keep a finished command alive.
  await stdout.flush();
  exit(code);
}
