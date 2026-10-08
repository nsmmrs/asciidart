/// `ascii_docs regen`: converts every case with every profile and records
/// the results (or, with `--check`, verifies the recorded ones).
library;

import 'dart:io';

import '../oracle/asciidart_runner.dart';
import '../oracle/ruby_pool.dart';
import '../spec/case.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/profile.dart';

final class RegenReport {
  int converted = 0;
  final List<String> changed = [];
  final List<String> undocumented = [];

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
          repoRoot: corpus.root,
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
      case AsciidartProfile():
        for (final c in cases) {
          for (final format in c.formats) {
            results.add((
              c,
              format,
              convertWithAsciidart(c.conversion(format, profile)),
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

/// An asciidart result that differs from the one it is compared to must
/// say why.
void _checkDivergences(Case c, Corpus corpus, RegenReport report) {
  for (final MapEntry(key: format, value: profiles) in c.expected.entries) {
    for (final MapEntry(key: name, value: expected) in profiles.entries) {
      final profile = corpus.profiles[name];
      if (profile is! AsciidartProfile || profile.compareTo == null) continue;
      final reference = profiles[profile.compareTo];
      if (reference == null || reference.sameBehavior(expected)) continue;
      if (expected.divergence == null) {
        report.undocumented.add('${c.id}#${format.name} [$name]');
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
