/// `ascii_docs coverage`: what the committed cases reach in each Ruby
/// profile, against what the pool reaches (and against an exclusion list,
/// `exclusions/<profile>.txt`, of elements nothing should be expected to
/// reach).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../oracle/ruby_pool.dart';
import '../pool/measure.dart';
import '../spec/case.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/profile.dart';

final class ProfileCoverage {
  ProfileCoverage(
    this.profile,
    this.universe,
    this.cases,
    this.pool,
    this.excluded,
  );

  final RubyProfile profile;
  final CoverageUniverse universe;

  /// Elements reached: by the cases (with load time), by the pool.
  final Uint8List cases;
  final Uint8List? pool;
  final Set<int> excluded;

  int get lineCount => universe.lines.length;

  String element(int e) =>
      e < lineCount ? universe.lines[e] : universe.branches[e - lineCount];

  /// Counts of (lines, branches) set in [bits].
  (int, int) count(Uint8List bits, {bool withExcluded = false}) {
    var lines = 0;
    var branches = 0;
    for (var e = 0; e < bits.length; e++) {
      if (bits[e] == 0 && !(withExcluded && excluded.contains(e))) continue;
      e < lineCount ? lines++ : branches++;
    }
    return (lines, branches);
  }

  /// Elements the pool reaches and the cases don't.
  List<String> lost() => [
    if (pool != null)
      for (var e = 0; e < pool!.length; e++)
        if (pool![e] == 1 && cases[e] == 0 && !excluded.contains(e)) element(e),
  ];

  /// Elements neither reach nor excluded.
  List<String> unreached() => [
    for (var e = 0; e < cases.length; e++)
      if (cases[e] == 0 && !excluded.contains(e)) element(e),
  ];
}

Future<ProfileCoverage> measureCases(
  Corpus corpus,
  RubyProfile profile,
  List<Case> cases, {
  int jobs = 4,
}) async {
  final pool = await RubyPool.start(
    profile,
    repoRoot: corpus.root,
    size: jobs,
    coverage: true,
  );
  final universe = pool.universe!;
  final lines = universe.lines.length;
  final reached = Uint8List(lines + universe.branches.length);
  for (final l in universe.loadTimeLines) {
    reached[l] = 1;
  }
  for (final b in universe.loadTimeBranches) {
    reached[lines + b] = 1;
  }
  final conversions = [
    for (final c in cases)
      for (final format in c.formats)
        if (!format.binary) c.conversion(format, profile),
  ];
  await pool.convertAll(conversions).forEach((outcome) {
    final coverage = switch (outcome) {
      Converted(:final coverage) || Crashed(:final coverage) => coverage,
      TimedOut() => null,
    };
    for (final l in coverage?.lines ?? const <int>[]) {
      reached[l] = 1;
    }
    for (final b in coverage?.branches ?? const <int>[]) {
      reached[lines + b] = 1;
    }
  });
  await pool.close();

  Uint8List? poolBits;
  for (final format in Format.values) {
    final path = measurePath(profile.name, format);
    if (!File(path).existsSync()) continue;
    poolBits ??= Uint8List(reached.length);
    for (final m in MeasureFile.read(path).measurements.values) {
      for (final l in m.lines) {
        poolBits[l] = 1;
      }
      for (final b in m.branches) {
        poolBits[lines + b] = 1;
      }
    }
  }
  if (poolBits != null) {
    for (final l in universe.loadTimeLines) {
      poolBits[l] = 1;
    }
    for (final b in universe.loadTimeBranches) {
      poolBits[lines + b] = 1;
    }
  }

  final excluded = <int>{};
  final exclusions = File(
    p.join(corpus.root, 'exclusions', '${profile.name}.txt'),
  );
  if (exclusions.existsSync()) {
    final index = {
      for (var i = 0; i < universe.lines.length; i++) universe.lines[i]: i,
      for (var i = 0; i < universe.branches.length; i++)
        universe.branches[i]: lines + i,
    };
    for (final line in exclusions.readAsLinesSync()) {
      final key = line.split('#').first.trim();
      if (index[key] case final e?) excluded.add(e);
    }
  }
  return ProfileCoverage(profile, universe, reached, poolBits, excluded);
}
