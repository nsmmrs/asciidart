/// Coverage of the measured pool, per Ruby profile and format, and the
/// set cover over all of them.
library;

import 'dart:io';
import 'dart:typed_data';

import '../oracle/ruby_pool.dart';
import '../select/cover.dart';
import '../spec/conversion.dart';
import '../spec/profile.dart';
import 'measure.dart';

/// One Ruby profile's measurements.
final class ProfileMeasurements {
  ProfileMeasurements(this.profile, this.universe, this.files);

  final RubyProfile profile;
  final CoverageUniverse universe;
  final Map<Format, MeasureFile> files;

  int get size => universe.lines.length + universe.branches.length;

  /// Element number of a branch arm (lines come first).
  int branch(int i) => universe.lines.length + i;

  Iterable<int> elements(Measurement m) =>
      m.lines.followedBy(m.branches.map(branch));

  Iterable<int> get loadTime =>
      universe.loadTimeLines.followedBy(universe.loadTimeBranches.map(branch));

  static Future<ProfileMeasurements?> load(
    RubyProfile profile, {
    required String repoRoot,
    List<Format> formats = const [
      Format.html5,
      Format.docbook5,
      Format.manpage,
    ],
  }) async {
    final files = <Format, MeasureFile>{
      for (final format in formats)
        if (File(measurePath(profile.name, format)).existsSync())
          format: MeasureFile.read(measurePath(profile.name, format)),
    };
    if (files.isEmpty) return null;
    var universe = files.values.first.universe!;
    if (universe.loadTimeLines.isEmpty) {
      // Older measurement files lack the load-time set; a worker reports it.
      final worker = await RubyWorker.start(
        profile,
        repoRoot: repoRoot,
        coverage: true,
      );
      universe = CoverageUniverse(
        universe.lines,
        universe.branches,
        loadTimeLines: worker.universe!.loadTimeLines,
        loadTimeBranches: worker.universe!.loadTimeBranches,
      );
      await worker.close();
    }
    return ProfileMeasurements(profile, universe, files);
  }
}

String _pct(int n, int of) => '${(100 * n / of).toStringAsFixed(2)}% ($n/$of)';

/// Prints union coverage per profile and format, then builds the set cover
/// over every profile's elements; returns the problem and the selection.
(CoverProblem, List<int>) poolStats(
  List<ProfileMeasurements> profiles, {
  StringSink? out,
}) {
  final sink = out ?? stdout;
  var offset = 0;
  final offsets = <ProfileMeasurements, int>{};
  for (final pm in profiles) {
    offsets[pm] = offset;
    offset += pm.size;
  }
  final problem = CoverProblem(offset);
  for (final pm in profiles) {
    final l = pm.universe.lines.length;
    final b = pm.universe.branches.length;
    final loaded = Uint8List(pm.size);
    for (final e in pm.loadTime) {
      loaded[e] = 1;
    }
    final all = Uint8List.fromList(loaded);
    for (final MapEntry(key: format, value: file) in pm.files.entries) {
      final union = Uint8List.fromList(loaded);
      var failed = 0;
      for (final m in file.measurements.values) {
        if (m.error != null) failed++;
        for (final e in pm.elements(m)) {
          union[e] = 1;
        }
        problem.add(
          '${m.id}#${format.name}',
          pm.elements(m).map((e) => e + offsets[pm]!),
          cost: m.micros,
        );
      }
      var lines = 0;
      var branches = 0;
      for (var e = 0; e < pm.size; e++) {
        if (union[e] == 0) continue;
        all[e] = 1;
        e < l ? lines++ : branches++;
      }
      sink.writeln(
        '${pm.profile.name} ${format.name}: lines ${_pct(lines, l)}, '
        'branches ${_pct(branches, b)}, ${file.measurements.length} conversions, $failed failed',
      );
    }
    var lines = 0;
    var branches = 0;
    for (var e = 0; e < pm.size; e++) {
      if (all[e] == 0) continue;
      e < l ? lines++ : branches++;
    }
    sink.writeln(
      '${pm.profile.name} all formats: lines ${_pct(lines, l)}, branches ${_pct(branches, b)}',
    );
  }
  final watch = Stopwatch()..start();
  final chosen = greedyCover(problem);
  final micros = chosen.fold(0, (sum, i) => sum + problem.costs[i]);
  sink.writeln(
    'set cover over ${profiles.map((p) => p.profile.name).join(' + ')}: '
    '${chosen.length} of ${problem.ids.length} conversions, '
    '${(micros / 1000).toStringAsFixed(0)} ms to convert (under coverage), '
    'solved in ${watch.elapsedMilliseconds} ms',
  );
  return (problem, chosen);
}
