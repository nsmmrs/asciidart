/// `ptome check`: reads documents written in numbered units (ADR-0020)
/// without converting them, and prints each document's units and the
/// problems found (labels out of sequence, references not found).
library;

import 'package:ptome/src/abstract_node.dart' show SafeMode;
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/load.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/options.dart';

/// Usage text for `check` (printed by `--help` and on misuse).
const String checkUsage = '''
Usage: ptome check [options] FILE...

Analyzes documents written in numbered units (a header with :units: or
:works:) without converting them. Prints each document's problems: labels
out of sequence, repeated or going backwards, and references, notes or
quotations not found. Then prints a line counting its units by level, its
notes and references. Exits with status 1 when any document has a problem.

Options:
  -q, --quiet    print only each document's summary line
  -h, --help     show this help
''';

/// Runs `ptome check` with [args] (the arguments after `check`) and returns
/// the exit status: 0 when no document has a problem, 1 when one does, 64
/// on misuse.
int runCheck(List<String> args, {StringSink? out, StringSink? err}) {
  final stdout = out ?? io.standardOutput;
  final stderr = err ?? io.standardError;
  var quiet = false;
  final files = <String>[];
  for (final arg in args) {
    switch (arg) {
      case '-h' || '--help':
        stdout.write(checkUsage);
        return 0;
      case '-q' || '--quiet':
        quiet = true;
      case _ when arg.startsWith('-'):
        stderr
          ..writeln('ptome check: unknown option $arg')
          ..write(checkUsage);
        return 64;
      default:
        files.add(arg);
    }
  }
  if (files.isEmpty) {
    stderr.write(checkUsage);
    return 64;
  }
  var problems = 0;
  for (final path in files) {
    if (!io.isFile(path)) {
      stderr.writeln('ptome: ERROR: input file $path is missing');
      problems++;
      continue;
    }
    final watch = Stopwatch()..start();
    // Read as conversion reads it, its messages kept: the units' problems
    // are the session's diagnostics.
    final previous = LoggerManager.logger;
    LoggerManager.logger = MemoryLogger();
    final analysis = () {
      try {
        return loadFile(
          path,
          options: const AsciidoctorOptions(safe: SafeMode.unsafe),
        ).unitsSession?.analysis;
      } on Exception catch (e) {
        stderr.writeln('ptome: ERROR: $path: $e');
        return null;
      } finally {
        LoggerManager.logger = previous;
      }
    }();
    if (analysis == null) {
      stdout.writeln('$path: not written in units');
      problems++;
      continue;
    }
    final counts = <String, int>{};
    for (final u in analysis.units) {
      final level = '${u.level.scheme.name}.${u.level.name}';
      counts[level] = (counts[level] ?? 0) + 1;
    }
    final diagnostics = analysis.diagnostics;
    final errors = diagnostics.where((d) => d.error).length;
    problems += diagnostics.length;
    if (!quiet) {
      for (final d in diagnostics) {
        final where = d.loc == null ? '' : '${d.loc}: ';
        stdout.writeln(
          'ptome: ${d.error ? 'ERROR' : 'WARNING'}: $where${d.message}',
        );
      }
    }
    final units = counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
    stdout.writeln(
      '$path: ${units.isEmpty ? 'no units' : units}; '
      '${analysis.notes.length} notes, ${analysis.refs.length} references; '
      '$errors errors, ${diagnostics.length - errors} warnings '
      '(${watch.elapsedMilliseconds} ms)',
    );
  }
  return problems > 0 ? 1 : 0;
}
