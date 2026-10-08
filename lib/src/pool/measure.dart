/// Converts every pool entry to each format with each profile and records,
/// per conversion, the output hash (or error) and, for Ruby profiles, the
/// lines and branch arms it reached.
///
/// `$ASCII_DOCS_CACHE/pool/measure/<profile>/<format>.jsonl`: a header
/// `{"universe": {"lines": [...], "branches": [...]}}` (Ruby only), then
/// one `{"id", "us", "hash" | "error", "lines"?, "branches"?}` per entry.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../oracle/asciidart_pool.dart';
import '../oracle/ruby_pool.dart';
import '../spec/conversion.dart';
import '../spec/normalize.dart';
import '../spec/profile.dart';
import 'entry.dart';
import 'source.dart';

String measurePath(String profile, Format format) =>
    p.join(poolDir, 'measure', profile, '${format.name}.jsonl');

/// One measured conversion.
final class Measurement {
  const Measurement({
    required this.id,
    required this.micros,
    this.hash,
    this.error,
    this.lines = const [],
    this.branches = const [],
  });

  final String id;
  final int micros;
  final String? hash;
  final String? error;
  final List<int> lines;
  final List<int> branches;

  Map<String, Object?> toJson() => {
    'id': id,
    'us': micros,
    'hash': ?hash,
    'error': ?error,
    if (lines.isNotEmpty) 'lines': lines,
    if (branches.isNotEmpty) 'branches': branches,
  };

  static Measurement fromJson(Map<String, Object?> json) => Measurement(
    id: json['id']! as String,
    micros: json['us']! as int,
    hash: json['hash'] as String?,
    error: json['error'] as String?,
    lines: (json['lines'] as List? ?? const []).cast<int>(),
    branches: (json['branches'] as List? ?? const []).cast<int>(),
  );

  static Measurement of(Outcome outcome, {required String baseDir}) {
    final id = outcome.id.substring(0, outcome.id.lastIndexOf('#'));
    final coverage = switch (outcome) {
      Converted(:final coverage) || Crashed(:final coverage) => coverage,
      TimedOut() => null,
    };
    return Measurement(
      id: id,
      micros: outcome.micros,
      hash: switch (outcome) {
        Converted(:final output) => contentHash(
          outputBytes(output, baseDir: baseDir),
        ),
        _ => null,
      },
      error: switch (outcome) {
        Crashed(:final error, :final frame) =>
          '${error.split('\n').first} @ $frame',
        TimedOut() => 'timeout',
        Converted() => null,
      },
      lines: coverage?.lines ?? const [],
      branches: coverage?.branches ?? const [],
    );
  }
}

/// A measurement file: the universe (Ruby) and the measurements by id.
final class MeasureFile {
  const MeasureFile(this.universe, this.measurements);

  final CoverageUniverse? universe;
  final Map<String, Measurement> measurements;

  static MeasureFile read(String path) {
    CoverageUniverse? universe;
    final measurements = <String, Measurement>{};
    for (final line in File(path).readAsLinesSync()) {
      if (line.isEmpty) continue;
      final json = jsonDecode(line) as Map<String, Object?>;
      if (json['universe'] case final Map<String, Object?> u) {
        universe = CoverageUniverse.fromJson(u);
      } else {
        final m = Measurement.fromJson(json);
        measurements[m.id] = m;
      }
    }
    return MeasureFile(universe, measurements);
  }
}

/// Measures [entries] with [profile] for [format], writing the
/// measurement file; returns how many conversions failed.
Future<int> measure(
  Profile profile,
  Format format,
  List<PoolEntry> entries, {
  required String repoRoot,
  required Map<String, String> defaults,
  int jobs = 4,
  void Function(int done)? progress,
}) async {
  final out = File(measurePath(profile.name, format))
    ..parent.createSync(recursive: true);
  final sink = out.openWrite();
  final byId = {for (final e in entries) e.id: e};
  final conversions = [
    for (final e in entries)
      e.conversion(format, defaults: {...profile.attributes, ...defaults}),
  ];
  var failed = 0;
  var done = 0;
  void write(Outcome outcome) {
    final id = outcome.id.substring(0, outcome.id.lastIndexOf('#'));
    final m = Measurement.of(outcome, baseDir: byId[id]!.baseDir);
    if (m.error != null) failed++;
    sink.writeln(jsonEncode(m.toJson()));
    if (++done % 1000 == 0) progress?.call(done);
  }

  switch (profile) {
    case RubyProfile():
      final pool = await RubyPool.start(
        profile,
        repoRoot: repoRoot,
        size: jobs,
        coverage: true,
      );
      final universe = pool.universe!;
      sink.writeln(jsonEncode({'universe': universe.toJson()}));
      await pool.convertAll(conversions).forEach(write);
      await pool.close();
    case AsciidartProfile():
      final pool = await AsciidartPool.start(size: jobs);
      await pool.convertAll(conversions).forEach(write);
      pool.close();
  }
  await sink.close();
  return failed;
}
