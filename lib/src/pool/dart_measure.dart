/// ptome's coverage over the pool: entries run one after another in
/// this isolate, and each is credited with the elements it reached first
/// (marginal sets; `--first` entries run first, so the rest are credited
/// only with what those leave uncovered).
///
/// `$ASCII_DOCS_CACHE/pool/measure/ptome/<format>.cov.jsonl`: one
/// `{"id", "us", "first"?, "new": [...]}` per entry that reached something
/// new (and every first entry), then `{"universe": [...], "hit": n}`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../oracle/ptome_runner.dart';
import '../oracle/dart_coverage.dart';
import '../spec/conversion.dart';
import '../spec/profile.dart';
import 'entry.dart';
import 'measure.dart';
import 'source.dart';

String dartCoveragePath(Format format) =>
    p.join(poolDir, 'measure', 'ptome', '${format.name}.cov.jsonl');

/// Runs [entries] (those in [first] first, then the rest cheapest first);
/// returns a summary line.
Future<String> measureDartCoverage(
  Format format,
  List<PoolEntry> entries, {
  required Map<String, String> defaults,
  required PtomeProfile profile,
  List<String> first = const [],
}) async {
  if (!DartCoverage.branchCoverage) {
    stderr.writeln(
      'warning: no --branch-coverage; recording coverage points only',
    );
  }
  // Entries that hung or crashed the measurement run are left out (no
  // time limit in-process); the rest go cheapest first.
  final measured = File(measurePath(profile.name, format)).existsSync()
      ? MeasureFile.read(measurePath(profile.name, format)).measurements
      : const <String, Measurement>{};
  final byId = {for (final e in entries) e.id: e};
  final firstSet = first.toSet();
  final rest =
      [
        for (final e in entries)
          if (!firstSet.contains(e.id) && measured[e.id]?.error != 'timeout')
            e.id,
      ]..sort(
        (a, b) =>
            (measured[a]?.micros ?? 0).compareTo(measured[b]?.micros ?? 0),
      );
  final order = [...first.where(byId.containsKey), ...rest];

  final coverage = await DartCoverage.connect();
  final out = File(dartCoveragePath(format))
    ..parent.createSync(recursive: true);
  final sink = out.openWrite();
  var previous = await coverage.hits();
  var credited = 0;
  final watch = Stopwatch()..start();
  for (final id in order) {
    final entry = byId[id]!;
    final outcome = convertWithPtome(
      entry.conversion(format, defaults: {...profile.attributes, ...defaults}),
    );
    final now = await coverage.hits();
    final fresh = now.difference(previous);
    final isFirst = firstSet.contains(id);
    if (fresh.isNotEmpty || isFirst) {
      credited++;
      sink.writeln(
        jsonEncode({
          'id': id,
          'us': outcome.micros,
          if (isFirst) 'first': true,
          'new': fresh.toList()..sort(),
        }),
      );
    }
    previous = now;
  }
  sink.writeln(
    jsonEncode({'universe': coverage.universe, 'hit': previous.length}),
  );
  await sink.close();
  await coverage.close();
  return '${order.length} entries, $credited credited, ${previous.length}/'
      '${coverage.universe.length} elements hit, ${watch.elapsed.inSeconds}s';
}
