/// The ptome command line for tests that run it as a subprocess: the
/// production executable when `PTOME_EXE` names one (CI builds it once
/// and runs every test on it), else the sources compiled to a kernel
/// snapshot once per test file (a fraction of a second per run, where
/// `dart run` compiles them again each time).
library;

import 'dart:io';

/// The executable and the arguments before the CLI's own.
Future<List<String>> ptomeCommand() => _command;

final Future<List<String>> _command = () async {
  if (Platform.environment['PTOME_EXE'] case final exe? when exe.isNotEmpty) {
    return [exe];
  }
  final root = _packageRoot();
  final dir = Directory('$root/.dart_tool/cli_test')
    ..createSync(recursive: true);
  final kernel = '${dir.path}/ptome-$pid.dill';
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'kernel',
    '$root/bin/ptome.dart',
    '-o',
    kernel,
  ]);
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return [Platform.resolvedExecutable, kernel];
}();

/// Deletes the kernel snapshot (call in `tearDownAll`).
Future<void> deletePtomeCommand() async {
  final command = await _command;
  if (command.length < 2) return;
  final kernel = File(command.last);
  if (kernel.existsSync()) kernel.deleteSync();
}

/// Runs the ptome command line with [args].
Future<ProcessResult> runPtome(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final command = await ptomeCommand();
  return await Process.run(
    command.first,
    [...command.skip(1), ...args],
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

String _packageRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/bin/ptome.dart').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('no ptome package above');
    dir = parent;
  }
  return dir.path;
}
