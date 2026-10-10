/// A test run as a gate: the corpus test is red until compatibility
/// settings close every difference, so a gate reads a run's JSON report
/// against the cases known red (`test/corpus/red.txt`, one `<case> <format>`
/// per line). Any other failure fails the gate; a listed case that passes is
/// reported, to be taken off the list: `--update` takes off the cases that
/// pass, and with `--add` also lists the run's new corpus failures (a new
/// red case is fixed, not listed, unless it is new to the corpus).
///
/// ```sh
/// dart test --file-reporter json:run.json
/// dart run tool/corpus_red.dart run.json [--update [--add]]
/// ```
library;

import 'dart:convert';
import 'dart:io';

const listPath = 'test/corpus/red.txt';

void main(List<String> arguments) {
  final args = [...arguments];
  final update = args.remove('--update');
  final add = args.remove('--add');
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/corpus_red.dart REPORT.json [--update [--add]]',
    );
    exit(64);
  }
  final (:failed, :passed, :others) = _results(File(args.single));
  final listFile = File(listPath);
  final listed = listFile.existsSync()
      ? {
          for (final line in listFile.readAsLinesSync())
            if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
        }
      : <String>{};
  if (update && others.isEmpty) {
    final red = add ? failed : failed.intersection(listed);
    listFile.writeAsStringSync(
      '# The corpus cases known red (`<case> <format>`): differences\n'
      "# compatibility settings haven't closed yet. Written by\n"
      '# `dart run tool/corpus_red.dart REPORT.json --update`.\n'
      '${(red.toList()..sort()).map((n) => '$n\n').join()}',
    );
    stdout.writeln('${red.length} red cases recorded in $listPath');
    final unlisted = failed.difference(red);
    if (unlisted.isNotEmpty) {
      stdout.writeln(
        '${unlisted.length} new failures not listed (--add lists them)',
      );
    }
    return;
  }
  final fresh = [...failed.difference(listed), ...others]..sort();
  final fixed = listed.intersection(passed).toList()..sort();
  stdout.writeln(
    'tests: ${passed.length} pass; corpus: ${failed.length} red '
    '(${listed.length} listed), ${fixed.length} fixed; '
    '${fresh.length} new failures',
  );
  for (final name in fixed) {
    stdout.writeln('  now green (take it off $listPath): $name');
  }
  for (final name in fresh) {
    stdout.writeln('  NEW FAILURE: $name');
  }
  exit(fresh.isEmpty ? 0 : 1);
}

/// The names of the tests that passed, of the corpus tests that failed, and
/// of the other tests that failed, in a JSON report (skipped tests are
/// none of them; a failure outside a test, such as a suite that doesn't
/// load, is one of the others).
({Set<String> failed, Set<String> passed, Set<String> others}) _results(
  File report,
) {
  final suites = <int, String>{};
  final names = <int, String>{};
  final corpus = <int>{};
  final failed = <String>{};
  final passed = <String>{};
  final others = <String>{};
  for (final line in report.readAsLinesSync()) {
    if (line.isEmpty) continue;
    final event = jsonDecode(line) as Map<String, Object?>;
    switch (event) {
      case {
        'type': 'suite',
        'suite': {'id': final int id, 'path': final String path},
      }:
        suites[id] = path;
      case {
        'type': 'testStart',
        'test': {
          'id': final int id,
          'name': final String name,
          'suiteID': final int suite,
        },
      }:
        names[id] = name;
        if (suites[suite]?.endsWith('corpus_test.dart') ?? false) {
          corpus.add(id);
        }
      case {
            'type': 'testDone',
            'testID': final int id,
            'result': final String result,
            'skipped': final bool skipped,
            'hidden': final bool hidden,
          }
          when !hidden && !skipped:
        if (result == 'success') {
          passed.add(names[id]!);
        } else {
          (corpus.contains(id) ? failed : others).add(names[id]!);
        }
    }
  }
  return (failed: failed, passed: passed, others: others);
}
