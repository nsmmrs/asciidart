/// `ptome check`: reads documents written in numbered units (ADR-0020)
/// without converting them, and prints each document's units and the
/// problems found (labels out of sequence, references not found).
library;

import 'dart:convert';

import 'package:ptome/src/abstract_node.dart' show SafeMode;
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/load.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/options.dart';
import 'package:ptome/src/units/citation.dart';
import 'package:ptome/src/units/document.dart' show Loc;
import 'package:ptome/src/units/engine.dart';

/// Usage text for `check` (printed by `--help` and on misuse).
const String checkUsage = '''
Usage: ptome check [options] FILE...

Analyzes documents written in numbered units (a header with :units: or
:works:) without converting them. Prints each document's problems: labels
out of sequence, repeated or going backwards, and references, notes or
quotations not found. Then prints a line counting its units by level, its
notes and references. Exits with status 1 when any document has a problem.

Options:
  -q, --quiet          print only each document's summary line
      --format=json    print a JSON array with an object for each document
                       (its units by level, notes, references and problems,
                       each problem with its kind, file, line and column)
      --list           list every unit (with --format=json: its ID, scheme,
                       level, citation, file and line)
  -h, --help           show this help
''';

/// Runs `ptome check` with [args] (the arguments after `check`) and returns
/// the exit status: 0 when no document has a problem, 1 when one does, 64
/// on misuse.
int runCheck(List<String> args, {StringSink? out, StringSink? err}) {
  final stdout = out ?? io.standardOutput;
  final stderr = err ?? io.standardError;
  var quiet = false;
  var json = false;
  var list = false;
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '-h' || '--help':
        stdout.write(checkUsage);
        return 0;
      case '-q' || '--quiet':
        quiet = true;
      case '--list':
        list = true;
      case '--format=json':
        json = true;
      case '--format' when i + 1 < args.length && args[i + 1] == 'json':
        json = true;
        i++;
      case '--format=text':
        json = false;
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
  final documents = <String>[];
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
      if (json) {
        documents.add('{"path": ${jsonEncode(path)}, "units": null}');
      } else {
        stdout.writeln('$path: not written in units');
      }
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
    if (json) {
      documents.add(
        _documentJson(
          path,
          analysis,
          counts,
          list: list,
          ms: watch.elapsedMilliseconds,
        ),
      );
      continue;
    }
    if (list) {
      final ordered = [...analysis.units]
        ..sort((a, b) => a.start.compareTo(b.start));
      for (final u in ordered) {
        stdout.writeln(
          '${_where(u.start).$1}:${_where(u.start).$2}: '
          '${u.level.scheme.name}.${u.level.name} '
          '${passageText(Passage(u, u), analysis.config)} #${u.id}',
        );
      }
    }
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
  if (json) stdout.writeln('[\n${documents.join(',\n')}\n]');
  return problems > 0 ? 1 : 0;
}

/// Where [loc] was read: the file, 1-based line and column.
(String, int, int) _where(Loc loc) {
  final origin = loc.file.originOf(loc.line);
  return origin == null
      ? (loc.file.path, loc.line + 1, loc.column + 1)
      : (origin.path, origin.line, origin.column + loc.column + 1);
}

/// The JSON object for the document at [path] and its [analysis].
String _documentJson(
  String path,
  Analysis analysis,
  Map<String, int> counts, {
  required bool list,
  required int ms,
}) {
  String problem(Diagnostic d) {
    final at = d.loc == null ? null : _where(d.loc!);
    return '{"severity": "${d.error ? 'error' : 'warning'}", '
        '"kind": "${d.problem.name}", '
        '"message": ${jsonEncode(d.message)}'
        '${at == null ? '' : ', "path": ${jsonEncode(at.$1)}, '
                  '"line": ${at.$2}, "column": ${at.$3}'}}';
  }

  final out = StringBuffer()
    ..write('{"path": ${jsonEncode(path)}, ')
    ..write('"units": {')
    ..write(
      [
        for (final MapEntry(:key, :value) in counts.entries)
          '${jsonEncode(key)}: $value',
      ].join(', '),
    )
    ..write('}, ')
    ..write('"notes": ${analysis.notes.length}, ')
    ..write('"references": ${analysis.refs.length}, ')
    ..write('"problems": [${analysis.diagnostics.map(problem).join(', ')}], ')
    ..write('"ms": $ms');
  if (list) {
    final ordered = [...analysis.units]
      ..sort((a, b) => a.start.compareTo(b.start));
    String unit(Unit u) {
      final (file, line, _) = _where(u.start);
      final citation = passageText(Passage(u, u), analysis.config);
      return '{"id": ${jsonEncode(u.id)}, '
          '"scheme": ${jsonEncode(u.level.scheme.name)}, '
          '"level": ${jsonEncode(u.level.name)}, '
          '"citation": ${jsonEncode(citation)}, '
          '"path": ${jsonEncode(file)}, "line": $line}';
    }

    out.write(', "list": [${ordered.map(unit).join(', ')}]');
  }
  out.write('}');
  return out.toString();
}
