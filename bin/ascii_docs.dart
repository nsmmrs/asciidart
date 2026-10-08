import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:ascii_docs/ascii_docs.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('ascii_docs', 'The ascii-docs corpus tools.')
        ..addCommand(RegenCommand())
        ..addCommand(TestCommand());
  try {
    exitCode = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}
