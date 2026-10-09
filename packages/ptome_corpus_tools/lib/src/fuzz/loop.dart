/// The fuzz loop: fresh generated documents and mutations of documents
/// that reached new code, converted by Ruby (with coverage) and ptome;
/// documents that reach code nothing reached before join the queue, and
/// findings are recorded by signature.
///
/// State lives in `$ASCII_DOCS_CACHE/fuzz`: `queue/` (documents that
/// reached new code), `findings/<signature hash>/` (one reproducer per
/// signature), `coverage-<profile>.bin` (what the pool and the queue reach).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../gen/generator.dart';
import '../gen/rng.dart';
import '../gen/serialize.dart';
import '../oracle/ruby_pool.dart';
import '../pool/measure.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/profile.dart';
import 'engine.dart';
import 'mutate.dart';
import 'oracles.dart';

String get fuzzDir => p.join(cacheDir, 'fuzz');

final class FuzzReport {
  int documents = 0;
  int generated = 0;
  int mutated = 0;
  int kept = 0;
  int newElements = 0;
  final Map<String, int> findings = {};
  final Stopwatch watch = Stopwatch();

  String summary() =>
      '$documents documents ($generated generated, $mutated mutated) in '
      '${watch.elapsed.inSeconds}s '
      '(${(documents / (watch.elapsedMilliseconds / 1000)).toStringAsFixed(0)}/s); '
      '$kept kept for $newElements new elements; '
      '${findings.length} distinct findings (${findings.values.fold(0, (a, b) => a + b)} total)';
}

/// A document in the queue, to mutate.
final class QueueEntry {
  QueueEntry(this.id, this.text, this.options);

  final String id;
  final String text;
  final FuzzOptions options;
}

Future<FuzzReport> fuzz(
  Corpus corpus, {
  required Duration duration,
  int jobs = 4,
  int seed = 1,
  GenConfig config = const GenConfig(),
  double mutation = 0.5,
  void Function(String)? log,
}) async {
  final engine = await FuzzEngine.start(corpus, jobs: jobs, workDir: fuzzDir);
  final universe = engine.universe;
  final lineCount = universe.lines.length;
  final covered = _baseline(engine.ruby, universe);
  final queue = _loadQueue(corpus);
  log?.call('queue: ${queue.length} documents to mutate');
  final report = FuzzReport()..watch.start();
  final deadline = DateTime.now().add(duration);
  final rng = Rng(seed * 7919 + 1);
  var nextSeed = seed;

  Future<void> lane() async {
    while (DateTime.now().isBefore(deadline)) {
      final String id;
      final String text;
      final FuzzOptions options;
      var words = const <String>{};
      if (queue.isNotEmpty && rng.chance(mutation)) {
        // Recent finds first, more often.
        final parent =
            queue[queue.length -
                1 -
                rng.below(
                  rng.chance(0.5)
                      ? queue.length
                      : (queue.length < 16 ? queue.length : 16),
                )];
        final s = nextSeed++;
        id = 'mut-$s';
        text = mutate(
          parent.text,
          Rng(s),
          donors: [for (var i = 0; i < 2; i++) rng.pick(queue).text],
        );
        options = parent.options;
        report.mutated++;
      } else {
        final s = nextSeed++;
        final generated = generate(s, config: config);
        id = 'gen-$s';
        text = serialize(generated.doc);
        options = FuzzOptions(
          doctype: generated.options.doctype,
          standalone: generated.options.standalone,
          attributes: generated.options.attributes,
        );
        if (generated.contentChecked) words = generated.words;
        report.generated++;
      }
      report.documents++;
      var gained = 0;
      for (final format in [
        Format.html5,
        Format.docbook5,
        if (options.doctype == 'manpage') Format.manpage,
      ]) {
        final exam = await engine.examine(
          text,
          format,
          options,
          id: id,
          words: words,
        );
        for (final l in exam.coverage?.lines ?? const <int>[]) {
          if (covered[l] == 0) {
            covered[l] = 1;
            gained++;
          }
        }
        for (final b in exam.coverage?.branches ?? const <int>[]) {
          if (covered[lineCount + b] == 0) {
            covered[lineCount + b] = 1;
            gained++;
          }
        }
        for (final finding in exam.findings) {
          _record(report, finding, format, id, text, options, log);
        }
      }
      if (gained > 0) {
        report.kept++;
        report.newElements += gained;
        queue.add(QueueEntry(id, text, options));
        final dir = Directory(p.join(fuzzDir, 'queue'))
          ..createSync(recursive: true);
        File(p.join(dir.path, '$id.adoc')).writeAsStringSync(text);
        File(p.join(dir.path, '$id.json')).writeAsStringSync(
          jsonEncode({
            'generator': generatorVersion,
            'gained': gained,
            ...options.toJson(),
          }),
        );
        log?.call('$id: +$gained elements');
      }
    }
  }

  await Future.wait([for (var i = 0; i < jobs; i++) lane()]);
  report.watch.stop();
  saveCoverage(engine.ruby, covered);
  // How often each signature came up, for triage to start with the most
  // frequent (merged with earlier runs).
  final summary = File(p.join(fuzzDir, 'signatures.json'));
  final counts = summary.existsSync()
      ? (jsonDecode(summary.readAsStringSync()) as Map<String, Object?>)
            .cast<String, int>()
      : <String, int>{};
  for (final MapEntry(:key, :value) in report.findings.entries) {
    counts[key] = (counts[key] ?? 0) + value;
  }
  summary.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(counts));
  await engine.close();
  return report;
}

/// The anchors and earlier finds, to mutate.
List<QueueEntry> _loadQueue(Corpus corpus) {
  final queue = <QueueEntry>[];
  for (final c in corpus.cases(['anchor/', 'found/'])) {
    queue.add(
      QueueEntry(
        c.id,
        c.input,
        FuzzOptions(
          doctype: c.doctype,
          standalone: c.standalone,
          attributes: c.attributes,
        ),
      ),
    );
  }
  final dir = Directory(p.join(fuzzDir, 'queue'));
  if (dir.existsSync()) {
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.adoc'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final meta = File(file.path.replaceFirst(RegExp(r'\.adoc$'), '.json'));
      queue.add(
        QueueEntry(
          p.basenameWithoutExtension(file.path),
          file.readAsStringSync(),
          meta.existsSync()
              ? FuzzOptions.fromJson(
                  jsonDecode(meta.readAsStringSync()) as Map<String, Object?>,
                )
              : const FuzzOptions(),
        ),
      );
    }
  }
  return queue;
}

void _record(
  FuzzReport report,
  Finding finding,
  Format format,
  String id,
  String text,
  FuzzOptions options,
  void Function(String)? log,
) {
  final signature = '${format.name}|${finding.signature}';
  final count = report.findings[signature] =
      (report.findings[signature] ?? 0) + 1;
  if (count > 1) return;
  final dir = Directory(p.join(fuzzDir, 'findings', signatureHash(signature)));
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
      'id': id,
      'generator': generatorVersion,
      ...options.toJson(),
    }),
  );
  log?.call(
    'finding ${finding.kind} [${finding.engine ?? '*'}] ${format.name}: ${finding.detail.split('\n').first}',
  );
}

String signatureHash(String signature) =>
    sha256.convert(utf8.encode(signature)).toString().substring(0, 12);

/// What the pool and earlier fuzzing already reach in [profile].
Uint8List _baseline(RubyProfile profile, CoverageUniverse universe) {
  final size = universe.lines.length + universe.branches.length;
  final covered = Uint8List(size);
  final saved = File(p.join(fuzzDir, 'coverage-${profile.name}.bin'));
  if (saved.existsSync() && saved.lengthSync() == size) {
    covered.setAll(0, saved.readAsBytesSync());
    return covered;
  }
  for (final l in universe.loadTimeLines) {
    covered[l] = 1;
  }
  for (final b in universe.loadTimeBranches) {
    covered[universe.lines.length + b] = 1;
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
