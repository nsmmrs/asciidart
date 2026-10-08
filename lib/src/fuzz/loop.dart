/// The fuzz loop: generate documents, convert each with Ruby (with
/// coverage) and asciidart, keep those that reach code nothing reached
/// before, and record findings by signature.
///
/// State lives in `$ASCII_DOCS_CACHE/fuzz`: `queue/` (documents that
/// reached new code), `findings/<signature hash>/` (one reproducer per
/// signature), `coverage.bin` (what the pool and the queue reach).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../gen/generator.dart';
import '../gen/serialize.dart';
import '../oracle/asciidart_pool.dart';
import '../oracle/ruby_pool.dart';
import '../pool/measure.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/normalize.dart';
import '../spec/profile.dart';
import 'oracles.dart';

String get fuzzDir => p.join(cacheDir, 'fuzz');

final class FuzzReport {
  int documents = 0;
  int conversions = 0;
  int kept = 0;
  int newElements = 0;
  final Map<String, int> findings = {};
  final Map<String, String> firstSeen = {};
  final Stopwatch watch = Stopwatch();

  String summary() =>
      '$documents documents ($conversions conversions) in ${watch.elapsed.inSeconds}s '
      '(${(documents / (watch.elapsedMilliseconds / 1000)).toStringAsFixed(0)}/s); '
      '$kept kept for $newElements new elements; '
      '${findings.length} distinct findings (${findings.values.fold(0, (a, b) => a + b)} total)';
}

Future<FuzzReport> fuzz(
  Corpus corpus, {
  required Duration duration,
  int jobs = 4,
  int seed = 1,
  GenConfig config = const GenConfig(),
  void Function(String)? log,
}) async {
  final ruby = corpus.profiles.values.whereType<RubyProfile>().firstWhere(
    (p) =>
        p.name ==
        corpus.profiles.values.whereType<AsciidartProfile>().single.compareTo,
  );
  final asciidart = corpus.profiles.values.whereType<AsciidartProfile>().single;
  final rubyPool = await RubyPool.start(
    ruby,
    repoRoot: corpus.root,
    size: jobs,
    coverage: true,
  );
  final dartPool = await AsciidartPool.start(size: jobs);
  final universe = rubyPool.universe!;
  final lineCount = universe.lines.length;
  final covered = _baseline(ruby, universe);
  final base = Directory(p.join(fuzzDir, 'base'))..createSync(recursive: true);
  final report = FuzzReport()..watch.start();
  final deadline = DateTime.now().add(duration);
  var nextSeed = seed;

  Future<void> lane() async {
    while (DateTime.now().isBefore(deadline)) {
      final s = nextSeed++;
      final generated = generate(s, config: config);
      final text = serialize(generated.doc);
      report.documents++;
      final formats = [
        Format.html5,
        Format.docbook5,
        if (generated.options.doctype == 'manpage') Format.manpage,
      ];
      var gained = 0;
      final found = <Finding>[];
      for (final format in formats) {
        final conversion = Conversion(
          id: 'gen-$s#${format.name}',
          input: text,
          format: format,
          baseDir: base.path,
          doctype: generated.options.doctype,
          standalone: generated.options.standalone,
          attributes: {
            ...corpus.defaults.attributes,
            ...generated.options.attributes,
          },
        );
        Conversion withAttrs(Map<String, String> extra) => Conversion(
          id: conversion.id,
          input: conversion.input,
          format: format,
          baseDir: conversion.baseDir,
          doctype: conversion.doctype,
          standalone: conversion.standalone,
          attributes: {...extra, ...conversion.attributes},
        );
        final results = await Future.wait([
          rubyPool.convert(
            withAttrs(ruby.attributes),
            timeout: const Duration(seconds: 10),
          ),
          dartPool.convert(
            withAttrs(asciidart.attributes),
            timeout: const Duration(seconds: 10),
          ),
        ]);
        report.conversions += 2;
        final (rubyOut, dartOut) = (results[0], results[1]);
        final coverage = switch (rubyOut) {
          Converted(:final coverage) || Crashed(:final coverage) => coverage,
          TimedOut() => null,
        };
        for (final l in coverage?.lines ?? const <int>[]) {
          if (covered[l] == 0) {
            covered[l] = 1;
            gained++;
          }
        }
        for (final b in coverage?.branches ?? const <int>[]) {
          if (covered[lineCount + b] == 0) {
            covered[lineCount + b] = 1;
            gained++;
          }
        }
        final words = generated.contentChecked
            ? generated.words
            : const <String>{};
        found
          ..addAll(
            checkOutcome(rubyOut, conversion, engine: ruby.name, words: words),
          )
          ..addAll(
            checkOutcome(
              dartOut,
              conversion,
              engine: asciidart.name,
              words: words,
            ),
          );
        if (rubyOut case Converted(output: final String a)) {
          if (dartOut case Converted(output: final String b)) {
            final difference = compareOutputs(
              normalizeText(a, baseDir: base.path),
              normalizeText(b, baseDir: base.path),
              referenceName: ruby.name,
              otherName: asciidart.name,
            );
            if (difference != null) found.add(difference);
          }
        }
        for (final finding in found) {
          _record(report, finding, format, s, text, generated, log);
        }
        found.clear();
      }
      if (gained > 0) {
        report.kept++;
        report.newElements += gained;
        final dir = Directory(p.join(fuzzDir, 'queue'))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'gen-$s.adoc')).writeAsStringSync(text);
        File(p.join(dir.path, 'gen-$s.json')).writeAsStringSync(
          jsonEncode({
            'seed': s,
            'generator': generatorVersion,
            'gained': gained,
            'doctype': generated.options.doctype,
            'standalone': generated.options.standalone,
            'attributes': generated.options.attributes,
          }),
        );
        log?.call('seed $s: +$gained elements');
      }
    }
  }

  await Future.wait([for (var i = 0; i < jobs; i++) lane()]);
  report.watch.stop();
  await rubyPool.close();
  dartPool.close();
  return report;
}

void _record(
  FuzzReport report,
  Finding finding,
  Format format,
  int seed,
  String text,
  Generated generated,
  void Function(String)? log,
) {
  final signature = '${format.name}|${finding.signature}';
  final count = report.findings[signature] =
      (report.findings[signature] ?? 0) + 1;
  if (count > 1) return;
  final hash = sha256
      .convert(utf8.encode(signature))
      .toString()
      .substring(0, 12);
  final dir = Directory(p.join(fuzzDir, 'findings', hash));
  if (dir.existsSync()) return; // seen in an earlier run
  dir.createSync(recursive: true);
  File(p.join(dir.path, 'input.adoc')).writeAsStringSync(text);
  File(p.join(dir.path, 'finding.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'signature': signature,
      'kind': finding.kind,
      'engine': finding.engine,
      'format': format.name,
      'detail': finding.detail,
      'seed': seed,
      'generator': generatorVersion,
      'doctype': generated.options.doctype,
      'standalone': generated.options.standalone,
      'attributes': generated.options.attributes,
    }),
  );
  report.firstSeen[signature] = dir.path;
  log?.call(
    'finding ${finding.kind} [${finding.engine ?? '*'}] ${format.name}: ${finding.detail.split('\n').first}',
  );
}

/// What the pool and earlier fuzzing already reach in [profile].
Uint8List _baseline(RubyProfile profile, CoverageUniverse universe) {
  final size = universe.lines.length + universe.branches.length;
  final covered = Uint8List(size);
  for (final l in universe.loadTimeLines) {
    covered[l] = 1;
  }
  for (final b in universe.loadTimeBranches) {
    covered[universe.lines.length + b] = 1;
  }
  final saved = File(p.join(fuzzDir, 'coverage-${profile.name}.bin'));
  if (saved.existsSync() && saved.lengthSync() == size) {
    covered.setAll(0, saved.readAsBytesSync());
    return covered;
  }
  for (final format in Format.values) {
    final path = measurePath(profile.name, format);
    if (!File(path).existsSync()) continue;
    for (final m in MeasureFile.read(path).measurements.values) {
      for (final l in m.lines) {
        covered[l] = 1;
      }
      for (final b in m.branches) {
        covered[universe.lines.length + b] = 1;
      }
    }
  }
  return covered;
}

/// Saves what the fuzzer has reached, so the next run starts from it.
void saveCoverage(RubyProfile profile, Uint8List covered) {
  File(p.join(fuzzDir, 'coverage-${profile.name}.bin'))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(covered);
}
