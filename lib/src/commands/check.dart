/// `ascii_docs test`: converts every case with ptome in-process and
/// compares each result with the one recorded for the ptome profile.
library;

import 'dart:io';

import '../oracle/ptome_runner.dart';
import '../spec/case.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/normalize.dart';
import '../spec/profile.dart';

/// One (case, format) whose result no longer matches.
final class Mismatch {
  const Mismatch(this.testId, this.detail);

  final String testId;
  final String detail;
}

final class CheckReport {
  int passed = 0;
  int skipped = 0;
  final List<Mismatch> failures = [];
  final Stopwatch watch = Stopwatch();
}

/// Checks [cases] against [profile]'s recorded results; [formats] limits
/// the formats (all when empty).
CheckReport checkCases(
  List<Case> cases,
  PtomeProfile profile, {
  Set<Format> formats = const {},
}) {
  final report = CheckReport()..watch.start();
  for (final c in cases) {
    for (final format in c.formats) {
      if (formats.isNotEmpty && !formats.contains(format)) continue;
      final expected = c.expected[format]?[profile.name];
      final testId = '${c.id}#${format.name}';
      if (expected == null || c.knownIssues.containsKey(format)) {
        report.skipped++;
        continue;
      }
      final outcome = convertWithPtome(c.conversion(format, profile));
      final actual = record(
        outcome,
        baseDir: c.baseDir,
        blobPath: (hash) => c.blobPath(format, hash),
        write: false,
      );
      if (actual.sameResult(expected)) {
        report.passed++;
      } else {
        report.failures.add(
          Mismatch(testId, _explain(c, format, expected, actual, outcome)),
        );
      }
    }
  }
  report.watch.stop();
  return report;
}

String _explain(
  Case c,
  Format format,
  Expected expected,
  Expected actual,
  Outcome outcome,
) {
  if (expected.error != null || actual.error != null) {
    return 'expected ${expected.error ?? 'output'}, got ${actual.error ?? 'output'}';
  }
  if (expected.hash != actual.hash) {
    if (format.binary || outcome is! Converted) {
      return 'output ${actual.hash} differs from ${expected.hash}';
    }
    final want = File(c.blobPath(format, expected.hash!)).readAsStringSync();
    final got = normalizeText(outcome.output as String, baseDir: c.baseDir);
    return 'output differs:\n${firstDifference(want, got)}';
  }
  return 'log differs:\n  expected ${expected.log}\n  got      ${actual.log}';
}

/// The first differing line of [want] and [got], with its line number.
String firstDifference(String want, String got) {
  final a = want.split('\n');
  final b = got.split('\n');
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '<end>';
    final y = i < b.length ? b[i] : '<end>';
    if (x != y) return '  line ${i + 1}:\n  - $x\n  + $y';
  }
  return '  (no line differs)';
}
