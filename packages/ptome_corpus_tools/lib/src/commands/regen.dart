/// `corpus regen`: converts every case with every profile and records
/// the results (or, with `--check`, verifies the recorded ones).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../oracle/ptome_runner.dart';
import '../oracle/ruby_pool.dart';
import '../spec/case.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/normalize.dart';
import '../spec/pixels.dart';
import '../spec/profile.dart';

final class RegenReport {
  int converted = 0;
  final List<String> changed = [];
  final List<String> undocumented = [];

  /// Binary results that change when the case is converted from another
  /// directory (a path in a PDF or an EPUB, which can't be normalized).
  final List<String> located = [];

  /// Results whose output matches the reference but whose log doesn't
  /// (diagnostic parity, to triage; not a failure).
  final List<String> logOnly = [];

  bool get clean => changed.isEmpty && undocumented.isEmpty && located.isEmpty;
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
          // One conversion at a time per worker, so each time limit
          // covers only its own conversion.
          final jobs = {
            for (final c in cases)
              for (final format in c.formats)
                if (profile.converts(format))
                  '${c.id}#${format.name}': (
                    c,
                    format,
                    c.conversion(format, profile),
                  ),
          };
          // (A whole book takes asciidoctor-pdf longer.)
          final timeout = Duration(
            seconds: profile.converts(Format.pdf) ? 60 : 10,
          );
          await for (final outcome in pool.convertAll([
            for (final (_, _, conversion) in jobs.values) conversion,
          ], timeout: timeout)) {
            final (c, format, _) = jobs[outcome.id]!;
            results.add((c, format, outcome));
          }
        } finally {
          await pool.close();
        }
      case PtomeProfile():
        for (final c in cases) {
          for (final format in c.formats) {
            final conversion = c.conversion(format, profile);
            final outcome = convertWithPtome(conversion);
            results.add((c, format, outcome));
            if (format.binary &&
                !_sameElsewhere(corpus, c, conversion, outcome)) {
              report.located.add('${c.id}#${format.name}');
            }
          }
        }
    }
    for (final (c, format, outcome) in results) {
      report.converted++;
      var now = record(
        outcome,
        baseDir: c.baseDir,
        blobPath: (hash) => c.blobPath(format, hash),
        write: !check,
      );
      final before = c.expected[format]?[profile.name];
      if (profile is PtomeProfile && format == Format.pdf) {
        now = now.withPixels(_pixels(c, profile, now));
      }
      if (before == null || !before.sameResult(now)) {
        report.changed.add('${c.id}#${format.name} [${profile.name}]');
      }
      if (!check) {
        // A PDF whose pages differ from the golden one's carries the
        // case's note of why (a bug of the gem's ptome doesn't copy).
        final pagesDiffer = now.pixels != null && now.pixels != 'identical';
        (c.expected[format] ??= {})[profile.name] = now.withDivergence(
          pagesDiffer && c.divergence != null
              ? c.divergence
              : before?.divergence,
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

/// How ptome's PDF [now] compares with the golden PDF of
/// [PtomeProfile.pdfCompareTo], pixel for pixel (null when there is none;
/// page images are kept by hash, so only new PDFs are rendered).
String? _pixels(Case c, PtomeProfile profile, Expected now) {
  final golden = c.expected[Format.pdf]?[profile.pdfCompareTo]?.hash;
  final hash = now.hash;
  if (golden == null || hash == null) return null;
  // (Not written when only checking.)
  if (!File(c.blobPath(Format.pdf, hash)).existsSync()) return null;
  // (The gem gives text, not a PDF, for an inline document.)
  if (!_isPdf(c.blobPath(Format.pdf, golden)) ||
      !_isPdf(c.blobPath(Format.pdf, hash))) {
    return null;
  }
  String pages(String hash) => p.join(cacheDir, 'pages', hash);
  return comparePages(
    pageImages(c.blobPath(Format.pdf, golden), pages(golden)),
    pageImages(c.blobPath(Format.pdf, hash), pages(hash)),
  );
}

bool _isPdf(String path) {
  final file = File(path).openSync();
  try {
    return String.fromCharCodes(file.readSync(5)) == '%PDF-';
  } finally {
    file.closeSync();
  }
}

/// Whether [c] converts to the same bytes as [outcome] from another
/// directory: through a link to ptome's package elsewhere, so that the
/// paths a case names relative to it (shared fixtures) still resolve.
bool _sameElsewhere(
  Corpus corpus,
  Case c,
  Conversion conversion,
  Outcome outcome,
) {
  final package = corpus.package;
  final temp = Directory.systemTemp.createTempSync('corpus-moved-');
  try {
    final link = Link(p.join(temp.path, 'ptome'))..createSync(package);
    final moved = convertWithPtome(
      conversion.at(p.join(link.path, p.relative(c.baseDir, from: package))),
    );
    return switch ((outcome, moved)) {
      (
        Converted(output: final Uint8List a),
        Converted(output: final Uint8List b),
      ) =>
        contentHash(a) == contentHash(b),
      _ => outcome.runtimeType == moved.runtimeType,
    };
  } finally {
    temp.deleteSync(recursive: true);
  }
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
