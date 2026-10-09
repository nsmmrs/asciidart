/// Turns fuzzer finds into corpus cases: the queued documents that reach
/// Ruby code the committed cases don't, on which Ruby and ptome agree, cut
/// down to what keeps that code reached, written to `cases/found`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../commands/coverage.dart';
import '../select/cover.dart';
import '../select/reduce.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import 'engine.dart';
import 'loop.dart';

final class PromoteReport {
  int candidates = 0;
  int disagreeing = 0;
  final List<String> written = [];
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
      docs[p.basenameWithoutExtension(file.path)] = (
        file.readAsStringSync(),
        meta.existsSync()
            ? FuzzOptions.fromJson(
                jsonDecode(meta.readAsStringSync()) as Map<String, Object?>,
              )
            : const FuzzOptions(),
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
    final caseDir = Directory(
      p.join(corpus.casesRoot, 'found', '$id-${format.name}'),
    )..createSync(recursive: true);
    File(p.join(caseDir.path, 'input.adoc'))
        .writeAsStringSync(reduced.join('\n'));
    String q(String s) => jsonEncode(s);
    File(p.join(caseDir.path, 'case.toml')).writeAsStringSync(
      [
        'description = "Found by the fuzzer: reaches code no other case did."',
        'source = ${q('gen:$id')}',
        'formats = ["${format.name}"]',
        if (options.doctype != null || options.standalone) '\n[options]',
        if (options.doctype != null) 'doctype = ${q(options.doctype!)}',
        if (options.standalone) 'standalone = true',
        if (options.attributes.isNotEmpty) '\n[attributes]',
        for (final MapEntry(:key, :value) in options.attributes.entries)
          if (!corpus.defaults.attributes.containsKey(key))
            '${q(key)} = ${q(value)}',
        '',
      ].join('\n'),
    );
    report.written.add(p.relative(caseDir.path, from: corpus.casesRoot));
    log?.call(
      'found case ${report.written.last}: ${text.split('\n').length} -> ${reduced.length} lines, ${target.length} new elements',
    );
  }
  await engine.close();
  return report;
}
