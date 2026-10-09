/// `corpus regen`: converts every case with every profile and records
/// the results (or, with `--check`, verifies the recorded ones).
library;

import 'dart:io';

import '../oracle/ptome_runner.dart';
import '../oracle/ruby_pool.dart';
import '../spec/case.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/profile.dart';

final class RegenReport {
  int converted = 0;
  final List<String> changed = [];
  final List<String> undocumented = [];

  /// Results whose output matches the reference but whose log doesn't
  /// (diagnostic parity, to triage; not a failure).
  final List<String> logOnly = [];

  bool get clean => changed.isEmpty && undocumented.isEmpty;
}

/// Regenerates [cases] for [profiles]; with [check], writes nothing and
/// reports each recorded result that no longer matches.
Future<RegenReport> regen(
  Corpus corpus,
  List<Case> cases, {
  required List<Profile> profiles,
  bool check = false,
  int jobs = 4,
}) async {
  final report = RegenReport();
  for (final profile in profiles) {
    final results = <(Case, Format, Outcome)>[];
    switch (profile) {
      case RubyProfile():
        final pool = await RubyPool.start(
          profile,
          repoRoot: corpus.toolsRoot,
          size: jobs,
        );
        try {
          results.addAll(
            await Future.wait([
              for (final c in cases)
                for (final format in c.formats)
                  if (!format.binary)
                    pool
                        .convert(c.conversion(format, profile))
                        .then((outcome) => (c, format, outcome)),
            ]),
          );
        } finally {
          await pool.close();
        }
      case PtomeProfile():
        for (final c in cases) {
          for (final format in c.formats) {
            results.add((
              c,
              format,
              convertWithPtome(c.conversion(format, profile)),
            ));
          }
        }
    }
    for (final (c, format, outcome) in results) {
      report.converted++;
      final now = record(
        outcome,
        baseDir: c.baseDir,
        blobPath: (hash) => c.blobPath(format, hash),
        write: !check,
      );
      final before = c.expected[format]?[profile.name];
      if (before == null || !before.sameResult(now)) {
        report.changed.add('${c.id}#${format.name} [${profile.name}]');
      }
      if (!check) {
        (c.expected[format] ??= {})[profile.name] = now.withDivergence(
          before?.divergence,
        );
      }
    }
  }
  for (final c in cases) {
    _checkDivergences(c, corpus, report);
    if (!check) {
      c.writeVersions();
      _collectGarbage(c);
    }
  }
  return report;
}

/// An ptome result that differs from the one it is compared to must
/// say why.
void _checkDivergences(Case c, Corpus corpus, RegenReport report) {
  for (final MapEntry(key: format, value: profiles) in c.expected.entries) {
    for (final MapEntry(key: name, value: expected) in profiles.entries) {
      final profile = corpus.profiles[name];
      if (profile is! PtomeProfile || profile.compareTo == null) continue;
      final reference = profiles[profile.compareTo];
      if (reference == null || reference.sameBehavior(expected)) continue;
      final id = '${c.id}#${format.name} [$name]';
      if (expected.divergence == null && c.divergence != null) {
        profiles[name] = expected.withDivergence(c.divergence);
      } else if (expected.divergence == null) {
        if (expected.hash != null && expected.hash == reference.hash) {
          report.logOnly.add(id);
        } else {
          report.undocumented.add(id);
        }
      }
    }
  }
}

/// Deletes the blobs no profile refers to any more.
void _collectGarbage(Case c) {
  final dir = Directory(c.expectedDir);
  if (!dir.existsSync()) return;
  final live = {
    for (final MapEntry(key: format, value: profiles) in c.expected.entries)
      for (final expected in profiles.values)
        if (expected.hash case final hash?) c.blobPath(format, hash),
  };
  for (final file in dir.listSync().whereType<File>()) {
    if (!live.contains(file.path)) file.deleteSync();
  }
}
