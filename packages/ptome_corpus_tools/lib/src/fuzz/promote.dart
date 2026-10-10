/// Turns fuzzer finds into corpus cases: the queued documents that reach
/// Ruby code the committed cases don't, on which Ruby and ptome agree, cut
/// down to what keeps that code reached, written as cases (`<id>-<format>`)
/// with their goldens.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../commands/coverage.dart';
import '../select/cover.dart';
import '../select/reduce.dart';
import '../spec/case.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import 'engine.dart';
import 'loop.dart';

final class PromoteReport {
  int candidates = 0;
  int disagreeing = 0;
  final List<String> written = [];

  /// What writing their goldens reported.
  String goldens = '';
}

Future<PromoteReport> promote(
  Corpus corpus, {
  int jobs = 4,
  void Function(String)? log,
}) async {
  final report = PromoteReport();
  final engine = await FuzzEngine.start(corpus, jobs: jobs, workDir: fuzzDir);
  final lineCount = engine.universe.lines.length;
  // What the committed cases already reach.
  final have = (await measureCases(
    corpus,
    engine.ruby,
    corpus.cases(),
    jobs: jobs,
  )).cases;

  final dir = Directory(p.join(fuzzDir, 'queue'));
  final docs = <String, (String, FuzzOptions)>{};
  if (dir.existsSync()) {
    for (final file in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.adoc'),
    )) {
      final meta = File(file.path.replaceFirst(RegExp(r'\.adoc$'), '.json'));
      final options = meta.existsSync()
          ? FuzzOptions.fromJson(
              jsonDecode(meta.readAsStringSync()) as Map<String, Object?>,
            )
          : const FuzzOptions();
      // A case is a whole document, as the command line converts it.
      docs[p.basenameWithoutExtension(file.path)] = (
        file.readAsStringSync(),
        FuzzOptions(
          doctype: options.doctype,
          standalone: true,
          attributes: options.attributes,
        ),
      );
    }
  }
  Set<int> fresh(Examination exam) => {
    for (final l in exam.coverage?.lines ?? const <int>[])
      if (have[l] == 0) l,
    for (final b in exam.coverage?.branches ?? const <int>[])
      if (have[lineCount + b] == 0) lineCount + b,
  };
  bool agrees(Examination exam) => !exam.findings.any(
    (f) => f.kind == 'differs' || f.kind == 'crash' || f.kind == 'timeout',
  );

  final problem = CoverProblem(have.length);
  final keys = <String, (String, Format)>{};
  await Future.wait([
    for (final MapEntry(key: id, value: (text, options)) in docs.entries)
      for (final format in [
        Format.html5,
        Format.docbook5,
        if (options.doctype == 'manpage') Format.manpage,
      ])
        engine.examine(text, format, options, id: id).then((exam) {
          report.candidates++;
          final gain = fresh(exam);
          if (gain.isEmpty) return;
          if (!agrees(exam)) {
            report.disagreeing++;
            return;
          }
          final key = '$id#${format.name}';
          keys[key] = (id, format);
          problem.add(key, gain);
        }),
  ]);
  final chosen = greedyCover(problem);
  log?.call(
    '${problem.ids.length} agreeing candidates reach new code; ${chosen.length} chosen',
  );

  for (final i in chosen) {
    final key = problem.ids[i];
    final (id, format) = keys[key]!;
    final (text, options) = docs[id]!;
    final target = problem.sets[i].toSet();
    final reduced = await reduceLines(text.split('\n'), (lines) async {
      final exam = await engine.examine(
        lines.join('\n'),
        format,
        options,
        id: id,
      );
      return agrees(exam) && fresh(exam).containsAll(target);
    });
    final name = '$id-${format.name}';
    corpus.write(
      name,
      reduced.join('\n'),
      CaseOptions(
        source: 'gen:$id',
        formats: [format],
        safe: Safe.safe,
        doctype: options.doctype,
        attributes: {
          for (final MapEntry(:key, :value) in options.attributes.entries)
            if (!corpus.attributes.containsKey(key)) key: value,
        },
      ),
    );
    report.written.add(name);
    log?.call(
      'found case ${report.written.last}: ${text.split('\n').length} -> ${reduced.length} lines, ${target.length} new elements',
    );
  }
  await engine.close();
  report.goldens = await corpus.generateGoldens(report.written, jobs: jobs);
  return report;
}
