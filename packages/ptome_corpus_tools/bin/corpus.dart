import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:ptome_corpus_tools/ptome_corpus_tools.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('corpus', "The tools that build ptome's corpus.")
        ..addCommand(PoolCommand())
        ..addCommand(AnchorCommand())
        ..addCommand(GenCommand())
        ..addCommand(FuzzCommand())
        ..addCommand(TriageCommand())
        ..addCommand(CoverageCommand())
        ..addCommand(OraclesCommand())
        ..addCommand(DartCoverageCommand())
        ..addCommand(PromoteCommand());
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
