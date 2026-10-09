/// Cuts each recorded finding down to the smallest document that still
/// produces it (same signature), and lists them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../select/reduce.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import 'engine.dart';
import 'loop.dart';

final class TriagedFinding {
  TriagedFinding(this.dir, this.json, this.minimized);

  final String dir;
  final Map<String, Object?> json;
  final String minimized;
}

/// Minimizes every finding without a `min.adoc` (in parallel lanes).
Future<List<TriagedFinding>> minimizeFindings(
  Corpus corpus, {
  int jobs = 4,
  int? top,
  void Function(String)? log,
}) async {
  final root = Directory(p.join(fuzzDir, 'findings'));
  if (!root.existsSync()) return const [];
  var dirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  // The most frequent signatures first (fuzz runs count them).
  final summary = File(p.join(fuzzDir, 'signatures.json'));
  if (top != null && summary.existsSync()) {
    final counts = (jsonDecode(
      summary.readAsStringSync(),
    ) as Map<String, Object?>).cast<String, int>();
    final ranked = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final wanted = {for (final s in ranked.take(top)) signatureHash(s)};
    dirs = [
      for (final d in dirs)
        if (wanted.contains(p.basename(d.path))) d,
    ];
  }
  final engine = await FuzzEngine.start(corpus, jobs: jobs, workDir: fuzzDir);
  final results = <TriagedFinding>[];
  var next = 0;
  Future<void> lane() async {
    while (next < dirs.length) {
      final dir = dirs[next++].path;
      final json = jsonDecode(
        File(p.join(dir, 'finding.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      final minFile = File(p.join(dir, 'min.adoc'));
      if (minFile.existsSync()) {
        results.add(TriagedFinding(dir, json, minFile.readAsStringSync()));
        continue;
      }
      final signature = json['signature']! as String;
      final format = Format.parse(json['format']! as String);
      final options = FuzzOptions.fromJson(json);
      Future<bool> reproduces(List<String> lines) async {
        final exam = await engine.examine(
          lines.join('\n'),
          format,
          options,
          timeout: const Duration(seconds: 5),
        );
        return exam.findings.any(
          (f) => '${format.name}|${f.signature}' == signature,
        );
      }

      final input = File(p.join(dir, 'input.adoc')).readAsStringSync();
      final lines = input.split('\n');
      if (!await reproduces(lines)) {
        log?.call('${p.basename(dir)}: does not reproduce ($signature)');
        minFile.writeAsStringSync(input);
        results.add(TriagedFinding(dir, json..['reproduces'] = false, input));
        continue;
      }
      var budget = 400;
      final minimized = (await reduceLines(
        lines,
        (c) async => budget-- > 0 && await reproduces(c),
      )).join('\n');
      minFile.writeAsStringSync(minimized);
      log?.call(
        '${p.basename(dir)}: ${lines.length} -> ${minimized.split('\n').length} lines ($signature)',
      );
      results.add(TriagedFinding(dir, json, minimized));
    }
  }

  await Future.wait([for (var i = 0; i < jobs; i++) lane()]);
  await engine.close();
  return results;
}
