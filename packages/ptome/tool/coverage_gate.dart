/// The coverage gate: what a test run reached of ptome's own code (its
/// lines and branch arms) must not fall below the floor recorded in
/// `tool/coverage_floor.txt`, so new code comes with tests (the corpus's
/// cases first). `--update` records the run's coverage as the new floor.
///
/// ```sh
/// dart test --branch-coverage --coverage=coverage
/// dart run tool/coverage_gate.dart coverage [--update]
/// ```
library;

import 'dart:convert';
import 'dart:io';

const floorPath = 'tool/coverage_floor.txt';

void main(List<String> arguments) {
  final args = [...arguments];
  final update = args.remove('--update');
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/coverage_gate.dart COVERAGE_DIR [--update]',
    );
    exit(64);
  }
  final run = _coverage(Directory(args.single));
  if (update) {
    File(floorPath).writeAsStringSync(
      "# The least coverage of ptome's code a test run may reach, in\n"
      '# percent (dart run tool/coverage_gate.dart DIR --update).\n'
      'lines ${_floor(run.lines)}\n'
      'branches ${_floor(run.branches)}\n',
    );
    stdout.writeln('coverage floor recorded: ${_describe(run)}');
    return;
  }
  final floor = {
    for (final line in File(floorPath).readAsLinesSync())
      if (line.split(' ') case [final name, final value]
          when !line.startsWith('#'))
        name: double.parse(value),
  };
  final failures = [
    if (run.lines < floor['lines']!)
      'lines ${run.lines.toStringAsFixed(2)}% < ${floor['lines']}%',
    if (run.branches < floor['branches']!)
      'branches ${run.branches.toStringAsFixed(2)}% < ${floor['branches']}%',
  ];
  stdout.writeln(
    'coverage: ${_describe(run)} (floor: lines ${floor['lines']}%, '
    'branches ${floor['branches']}%)',
  );
  for (final failure in failures) {
    stdout.writeln('  BELOW THE FLOOR: $failure');
  }
  if (failures.isEmpty &&
      (run.lines >= floor['lines']! + 0.5 ||
          run.branches >= floor['branches']! + 0.5)) {
    stdout.writeln('  above the floor: raise it with --update');
  }
  exit(failures.isEmpty ? 0 : 1);
}

/// [percent] less a fifth of a point (runs that start processes and
/// isolates vary a little), rounded down to a tenth.
String _floor(double percent) =>
    (((percent - 0.2) * 10).floor() / 10).toString();

typedef _Coverage = ({double lines, double branches});

String _describe(_Coverage c) =>
    'lines ${c.lines.toStringAsFixed(2)}%, '
    'branches ${c.branches.toStringAsFixed(2)}%';

/// The share of ptome's lines and branch arms the run in [dir] reached, in
/// percent, from the JSON hit maps `dart test --coverage` writes (one per
/// test suite, merged).
_Coverage _coverage(Directory dir) {
  final lines = <String, bool>{};
  final branches = <String, bool>{};
  void merge(Map<String, bool> into, String source, List<Object?> hits) {
    for (var i = 0; i + 1 < hits.length; i += 2) {
      if (hits[i] case final int line) {
        final key = '$source:$line';
        final hit = switch (hits[i + 1]) {
          final int count => count > 0,
          _ => false,
        };
        into[key] = (into[key] ?? false) || hit;
      }
    }
  }

  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    if (jsonDecode(file.readAsStringSync()) case {
      'coverage': final List<Object?> entries,
    }) {
      for (final entry in entries) {
        if (entry case {'source': final String source}
            when source.startsWith('package:ptome/')) {
          if (entry case {'hits': final List<Object?> hits}) {
            merge(lines, source, hits);
          }
          if (entry case {'branchHits': final List<Object?> hits}) {
            merge(branches, source, hits);
          }
        }
      }
    }
  }
  double share(Map<String, bool> hits) => hits.isEmpty
      ? 0
      : 100 * hits.values.where((hit) => hit).length / hits.length;
  return (lines: share(lines), branches: share(branches));
}
