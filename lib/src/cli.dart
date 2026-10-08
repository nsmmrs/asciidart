/// The `ascii_docs` subcommands.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'anchor/build.dart';
import 'commands/check.dart';
import 'commands/coverage.dart';
import 'fuzz/loop.dart';
import 'fuzz/oracles.dart';
import 'fuzz/promote.dart';
import 'oracle/ptome_runner.dart';
import 'oracle/dart_coverage.dart';
import 'fuzz/triage.dart';
import 'gen/generator.dart';
import 'gen/serialize.dart';
import 'commands/regen.dart';
import 'pool/capture.dart';
import 'pool/entry.dart';
import 'pool/index.dart';
import 'pool/measure.dart';
import 'pool/source.dart';
import 'pool/stats.dart';
import 'pool/dart_measure.dart';
import 'spec/conversion.dart';
import 'spec/corpus.dart';
import 'spec/profile.dart';

final class RegenCommand extends Command<int> {
  RegenCommand() {
    argParser
      ..addMultiOption(
        'profile',
        abbr: 'p',
        help: 'Profiles to run (default: all).',
      )
      ..addFlag(
        'check',
        help: 'Write nothing; fail if a recorded result changed.',
      )
      ..addOption(
        'jobs',
        abbr: 'j',
        defaultsTo: '4',
        help: 'Ruby workers per profile.',
      );
  }

  @override
  String get name => 'regen';

  @override
  String get description =>
      'Convert cases with each profile and record the results.\n'
      'Arguments limit the cases to those whose id starts with one of them.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final names = args.multiOption('profile');
    final profiles = [
      for (final MapEntry(:key, :value) in corpus.profiles.entries)
        if (names.isEmpty || names.contains(key)) value,
    ];
    final check = args.flag('check');
    final cases = corpus.cases(args.rest);
    final report = await regen(
      corpus,
      cases,
      profiles: profiles,
      check: check,
      jobs: int.parse(args.option('jobs')!),
    );
    stdout.writeln(
      '${report.converted} conversions, ${cases.length} cases, '
      '${report.changed.length} ${check ? 'mismatched' : 'changed'}',
    );
    for (final id in report.changed) {
      stdout.writeln('  ${check ? 'mismatch' : 'changed'}: $id');
    }
    for (final id in report.undocumented) {
      stdout.writeln(
        '  differs from its reference without a divergence note: $id',
      );
    }
    if (report.logOnly.isNotEmpty) {
      stdout.writeln(
        '  ${report.logOnly.length} with the same output but a different log (triage/log-differences.txt)',
      );
      File(p.join(corpus.root, 'triage', 'log-differences.txt'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('${report.logOnly.join('\n')}\n');
    }
    return (check && report.changed.isNotEmpty) ||
            report.undocumented.isNotEmpty
        ? 1
        : 0;
  }
}

final class TestCommand extends Command<int> {
  TestCommand() {
    argParser.addMultiOption(
      'format',
      abbr: 'f',
      help: 'Formats to check (default: all).',
      allowed: [for (final f in Format.values) f.name],
    );
  }

  @override
  String get name => 'test';

  @override
  String get description =>
      'Convert cases with ptome and compare with the recorded results.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final profile = corpus.profiles.values.whereType<PtomeProfile>().single;
    final cases = corpus.cases(args.rest);
    final report = checkCases(
      cases,
      profile,
      formats: {
        for (final name in args.multiOption('format')) Format.parse(name),
      },
    );
    for (final failure in report.failures) {
      stdout.writeln('FAIL ${failure.testId}\n${failure.detail}');
    }
    stdout.writeln(
      '${report.passed} passed, ${report.failures.length} failed, '
      '${report.skipped} skipped in ${report.watch.elapsedMilliseconds} ms',
    );
    return report.failures.isEmpty ? 0 : 1;
  }
}

/// `ascii_docs pool ...`: the raw pool (fetch, index, capture, measure).
final class PoolCommand extends Command<int> {
  PoolCommand() {
    addSubcommand(_PoolFetch());
    addSubcommand(_PoolIndex());
    addSubcommand(_PoolCapture());
    addSubcommand(_PoolMeasure());
    addSubcommand(_PoolStats());
    addSubcommand(_PoolDartCoverage());
  }

  @override
  String get name => 'pool';

  @override
  String get description => 'Build and measure the raw document pool.';
}

final class _PoolFetch extends Command<int> {
  @override
  String get name => 'fetch';

  @override
  String get description =>
      'Check out every source in sources.toml (arguments: source names).';

  @override
  Future<int> run() async {
    final corpus = Corpus.open();
    final sources = PoolSource.load(p.join(corpus.root, 'sources.toml'));
    var failed = 0;
    for (final source in sources) {
      if (argResults!.rest.isNotEmpty &&
          !argResults!.rest.contains(source.name))
        continue;
      try {
        await source.fetch();
        stdout.writeln('fetched ${source.name}');
      } on ProcessException catch (e) {
        failed++;
        stderr.writeln('${source.name}: ${e.message}');
      }
    }
    return failed == 0 ? 0 : 1;
  }
}

final class _PoolIndex extends Command<int> {
  @override
  String get name => 'index';

  @override
  String get description =>
      'Write the pool manifest: documents, heredocs and captured test inputs.';

  @override
  Future<int> run() async {
    final corpus = Corpus.open();
    final entries = <PoolEntry>[];
    for (final source in PoolSource.load(p.join(corpus.root, 'sources.toml'))) {
      if (!Directory(source.checkout).existsSync()) {
        stderr.writeln('${source.name}: not fetched');
        continue;
      }
      final found = indexSource(source);
      stdout.writeln('${source.name}: ${found.length}');
      entries.addAll(found);
    }
    for (final profile in corpus.profiles.values.whereType<RubyProfile>()) {
      final found = capturedEntries(profile);
      stdout.writeln('capture-${profile.name}: ${found.length}');
      entries.addAll(found);
    }
    PoolEntry.writeAll(entries);
    stdout.writeln('${entries.length} entries -> $manifestPath');
    return 0;
  }
}

final class _PoolCapture extends Command<int> {
  @override
  String get name => 'capture';

  @override
  String get description =>
      "Record the documents each Ruby profile's test suite converts.";

  @override
  Future<int> run() async {
    final corpus = Corpus.open();
    for (final profile in corpus.profiles.values.whereType<RubyProfile>()) {
      final n = await capture(profile, repoRoot: corpus.root);
      stdout.writeln('${profile.name}: $n documents');
    }
    return 0;
  }
}

final class _PoolMeasure extends Command<int> {
  _PoolMeasure() {
    argParser
      ..addMultiOption('profile', abbr: 'p', help: 'Profiles (default: all).')
      ..addMultiOption(
        'format',
        abbr: 'f',
        defaultsTo: ['html5', 'docbook5', 'manpage'],
        allowed: [for (final f in Format.values) f.name],
      )
      ..addOption(
        'jobs',
        abbr: 'j',
        defaultsTo: '${Platform.numberOfProcessors ~/ 2}',
      );
  }

  @override
  String get name => 'measure';

  @override
  String get description =>
      'Convert every pool entry with each profile; record coverage and output hashes.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final entries = PoolEntry.readAll();
    final names = args.multiOption('profile');
    for (final profile in corpus.profiles.values) {
      if (names.isNotEmpty && !names.contains(profile.name)) continue;
      for (final name in args.multiOption('format')) {
        final format = Format.parse(name);
        if (profile is RubyProfile && format.binary) continue;
        final watch = Stopwatch()..start();
        final failed = await measure(
          profile,
          format,
          entries,
          repoRoot: corpus.root,
          defaults: corpus.defaults.attributes,
          jobs: int.parse(args.option('jobs')!),
          progress: (n) => stderr.write('\r${profile.name} ${format.name}: $n'),
        );
        stderr.write('\r');
        stdout.writeln(
          '${profile.name} ${format.name}: ${entries.length} entries, $failed failed, '
          '${watch.elapsed.inSeconds}s',
        );
      }
    }
    return 0;
  }
}

final class _PoolStats extends Command<int> {
  _PoolStats() {
    argParser
      ..addMultiOption(
        'profile',
        abbr: 'p',
        help: 'Ruby profiles (default: all).',
      )
      ..addOption(
        'write',
        help: 'Write the chosen conversion ids to this file.',
      );
  }

  @override
  String get name => 'stats';

  @override
  String get description =>
      'Coverage of the measured pool, and the set cover over it.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final names = args.multiOption('profile');
    final profiles = [
      for (final profile in corpus.profiles.values.whereType<RubyProfile>())
        if (names.isEmpty || names.contains(profile.name))
          ?await ProfileMeasurements.load(profile, repoRoot: corpus.root),
    ];
    final (problem, chosen) = poolStats(profiles);
    if (args.option('write') case final path?) {
      File(path).writeAsStringSync(
        '${[for (final i in chosen) problem.ids[i]].join('\n')}\n',
      );
    }
    return 0;
  }
}

final class _PoolDartCoverage extends Command<int> {
  _PoolDartCoverage() {
    argParser
      ..addOption(
        'format',
        abbr: 'f',
        defaultsTo: 'html5',
        allowed: [for (final f in Format.values) f.name],
      )
      ..addOption(
        'first',
        help:
            'A file of conversion ids (id#format) to run first, such as '
            'the Ruby set cover.',
      );
  }

  @override
  String get name => 'dart-cov';

  @override
  String get description =>
      "Record which pool entries reach ptome code earlier ones didn't "
      '(run with `dart --branch-coverage`).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final format = Format.parse(args.option('format')!);
    final first = switch (args.option('first')) {
      final String path => File(path).readAsLinesSync(),
      null => const <String>[],
    };
    final result = await measureDartCoverage(
      format,
      PoolEntry.readAll(),
      defaults: corpus.defaults.attributes,
      profile: corpus.profiles.values.whereType<PtomeProfile>().single,
      first: [
        for (final id in first)
          if (id.endsWith('#${format.name}'))
            id.substring(0, id.lastIndexOf('#')),
      ],
    );
    stdout.writeln('ptome ${format.name}: $result');
    return 0;
  }
}

/// `ascii_docs anchor`: builds cases/anchor from the measured pool.
final class AnchorCommand extends Command<int> {
  AnchorCommand() {
    argParser
      ..addOption('limit', help: 'Build at most this many anchors.')
      ..addOption('lanes', defaultsTo: '4', help: 'Parallel oracles.')
      ..addFlag('reduce', defaultsTo: true, help: 'Cut documents down first.');
  }

  @override
  String get name => 'anchor';

  @override
  String get description =>
      'Select, reduce, sanitize and verify pool documents into cases/anchor.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final report = await buildAnchors(
      corpus,
      lanes: int.parse(args.option('lanes')!),
      limit: switch (args.option('limit')) {
        final String n => int.parse(n),
        null => null,
      },
      reduce: args.flag('reduce'),
      log: stdout.writeln,
    );
    stdout.writeln(
      '${report.emitted.length} anchors written, ${report.skipped.length} skipped '
      '(${report.chosen} chosen of ${report.candidates} eligible), '
      '${report.residue.length} with original words kept',
    );
    for (final MapEntry(:key, :value) in report.residue.entries) {
      stdout.writeln('  residue $key: ${value.join(' ')}');
    }
    return 0;
  }
}

/// `ascii_docs gen SEED`: prints a generated document.
final class GenCommand extends Command<int> {
  @override
  String get name => 'gen';

  @override
  String get description => 'Print the document a seed generates.';

  @override
  Future<int> run() async {
    for (final arg in argResults!.rest) {
      final generated = generate(int.parse(arg));
      stdout.writeln(serialize(generated.doc));
      stderr.writeln(
        'seed $arg: doctype ${generated.options.doctype ?? 'article'}, '
        'attributes ${generated.options.attributes}, '
        '${generated.words.length} tracked words, '
        'pathological ${generated.pathological}',
      );
    }
    return 0;
  }
}

/// `ascii_docs fuzz`: the fuzz loop.
final class FuzzCommand extends Command<int> {
  FuzzCommand() {
    argParser
      ..addOption('seconds', defaultsTo: '60')
      ..addOption(
        'jobs',
        abbr: 'j',
        defaultsTo: '${Platform.numberOfProcessors ~/ 2}',
      )
      ..addOption('seed', defaultsTo: '1', help: 'The first seed.')
      ..addOption('pathology', defaultsTo: '0.08')
      ..addOption(
        'mutation',
        defaultsTo: '0.5',
        help: 'Share of mutated documents.',
      )
      ..addOption(
        'blocks',
        defaultsTo: '24',
        help: 'Most blocks per generated document.',
      );
  }

  @override
  String get name => 'fuzz';

  @override
  String get description =>
      'Generate documents; keep those that reach new code; record findings.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final report = await fuzz(
      Corpus.open(),
      duration: Duration(seconds: int.parse(args.option('seconds')!)),
      jobs: int.parse(args.option('jobs')!),
      seed: int.parse(args.option('seed')!),
      config: GenConfig(
        pathology: double.parse(args.option('pathology')!),
        maxBlocks: int.parse(args.option('blocks')!),
      ),
      mutation: double.parse(args.option('mutation')!),
      log: stdout.writeln,
    );
    stdout.writeln(report.summary());
    final top = report.findings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final MapEntry(:key, :value) in top.take(40)) {
      stdout.writeln('  ${value.toString().padLeft(5)}  $key');
    }
    return 0;
  }
}

/// `ascii_docs triage`: minimizes recorded findings and lists them.
final class TriageCommand extends Command<int> {
  TriageCommand() {
    argParser.addOption('top', help: 'Only the N most frequent signatures.');
    argParser.addOption(
      'jobs',
      abbr: 'j',
      defaultsTo: '${Platform.numberOfProcessors ~/ 2}',
    );
  }

  @override
  String get name => 'triage';

  @override
  String get description =>
      'Minimize the recorded findings and list them by kind.';

  @override
  Future<int> run() async {
    final results = await minimizeFindings(
      Corpus.open(),
      jobs: int.parse(argResults!.option('jobs')!),
      top: switch (argResults!.option('top')) {
        final String n => int.parse(n),
        null => null,
      },
      log: stderr.writeln,
    );
    results.sort(
      (a, b) => '${a.json['kind']}${a.json['engine']}'.compareTo(
        '${b.json['kind']}${b.json['engine']}',
      ),
    );
    for (final r in results) {
      final lines = r.minimized.split('\n');
      stdout.writeln(
        '== ${r.json['kind']} [${r.json['engine']}] ${r.json['format']} '
        '(${p.basename(r.dir)}, ${lines.length} lines)\n'
        '${(r.json['detail']! as String).split('\n').take(2).join('\n')}\n'
        '${lines.take(12).map((l) => '  | $l').join('\n')}\n',
      );
    }
    return 0;
  }
}

/// `ascii_docs coverage`: the committed cases' Ruby coverage.
final class CoverageCommand extends Command<int> {
  CoverageCommand() {
    argParser
      ..addMultiOption(
        'profile',
        abbr: 'p',
        help: 'Ruby profiles (default: all).',
      )
      ..addOption(
        'jobs',
        abbr: 'j',
        defaultsTo: '${Platform.numberOfProcessors ~/ 2}',
      )
      ..addOption(
        'lost',
        help: 'Write the elements the pool reaches and the cases miss to this file.',
      )
      ..addFlag(
        'gate',
        help: 'Fail unless every element is reached or excluded.',
      );
  }

  @override
  String get name => 'coverage';

  @override
  String get description =>
      "What the cases reach in each Ruby profile, against the pool and the exclusions.\n"
      'Arguments limit the cases to those whose id starts with one of them.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final names = args.multiOption('profile');
    final cases = corpus.cases(args.rest);
    var failed = false;
    final lostOut = StringBuffer();
    final eligible = eligibleUnion(corpus);
    for (final profile in corpus.profiles.values.whereType<RubyProfile>()) {
      if (names.isNotEmpty && !names.contains(profile.name)) continue;
      final result = await measureCases(
        corpus,
        profile,
        cases,
        jobs: int.parse(args.option('jobs')!),
      );
      String pct(int n, int of) => '${(100 * n / of).toStringAsFixed(2)}%';
      final l = result.universe.lines.length;
      final b = result.universe.branches.length;
      final (cl, cb) = result.count(result.cases);
      stdout.writeln(
        '${profile.name}: ${cases.length} cases reach lines ${pct(cl, l)} ($cl/$l), branches ${pct(cb, b)} ($cb/$b)',
      );
      if (result.pool case final pool?) {
        final (pl, pb) = result.count(pool);
        final lost = result.lost();
        stdout.writeln(
          '  pool: lines ${pct(pl, l)}, branches ${pct(pb, b)}; ${lost.length} pool elements the cases miss',
        );
        lostOut.writeln('# ${profile.name}');
        lost.forEach(lostOut.writeln);
      }
      if (eligible[profile.name] case final union?) {
        final withLoad = Uint8List.fromList(union);
        for (final l in result.universe.loadTimeLines) {
          withLoad[l] = 1;
        }
        for (final b in result.universe.loadTimeBranches) {
          withLoad[result.lineCount + b] = 1;
        }
        final (el, eb) = result.count(withLoad);
        final missed = [
          for (var e = 0; e < union.length; e++)
            if (union[e] == 1 &&
                result.cases[e] == 0 &&
                !result.excluded.contains(e))
              result.element(e),
        ];
        stdout.writeln(
          '  eligible pool (agreeing, no Ruby-only options): lines ${pct(el, l)}, branches ${pct(eb, b)}; '
          '${missed.length} of its elements the cases miss',
        );
        lostOut.writeln('# ${profile.name} eligible');
        missed.forEach(lostOut.writeln);
      }
      final unreached = result.unreached();
      stdout.writeln(
        '  ${result.excluded.length} excluded, ${unreached.length} neither reached nor excluded',
      );
      if (unreached.isNotEmpty) failed = true;
    }
    if (args.option('lost') case final path?)
      File(path).writeAsStringSync(lostOut.toString());
    return args.flag('gate') && failed ? 1 : 0;
  }
}

/// `ascii_docs oracles`: runs the fuzzer's invariants over every recorded
/// output, which must pass them (apart from known upstream bugs).
final class OraclesCommand extends Command<int> {
  OraclesCommand() {
    argParser.addFlag(
      'update',
      help: 'Accept the current hits as the baseline (triage/oracle-baseline.txt).',
    );
  }

  @override
  String get name => 'oracles';

  @override
  String get description =>
      "Check every recorded output against the fuzzer's invariants (false positives show here).";

  @override
  Future<int> run() async {
    final corpus = Corpus.open();
    final counts = <String, int>{};
    final hits = <String>[];
    var checked = 0;
    for (final c in corpus.cases(argResults!.rest)) {
      for (final MapEntry(key: format, value: profiles) in c.expected.entries) {
        if (format.binary) continue;
        for (final MapEntry(key: profile, value: expected)
            in profiles.entries) {
          final hash = expected.hash;
          if (hash == null) continue;
          checked++;
          final output = File(c.blobPath(format, hash)).readAsStringSync();
          for (final f in checkInvariants(
            output,
            format,
            input: c.input,
            log: expected.log,
          )) {
            final key = '${f.kind} [$profile] ${format.name}';
            counts[key] = (counts[key] ?? 0) + 1;
            hits.add('${c.id}#${format.name} [$profile]: ${f.kind}');
          }
        }
      }
    }
    // Hits already reviewed (upstream behavior both implementations share,
    // or known bugs) are listed in the baseline; only new ones fail.
    final baselineFile = File(
      p.join(corpus.root, 'triage', 'oracle-baseline.txt'),
    );
    if (argResults!.flag('update')) {
      baselineFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('${(hits..sort()).join('\n')}\n');
    }
    final baseline = baselineFile.existsSync()
        ? baselineFile.readAsLinesSync().toSet()
        : <String>{};
    final fresh = [
      for (final h in hits)
        if (!baseline.contains(h)) h,
    ];
    stdout.writeln(
      '$checked outputs checked, ${hits.length} hits, ${fresh.length} not in the baseline',
    );
    for (final MapEntry(:key, :value) in counts.entries) {
      stdout.writeln('  $value  $key');
    }
    fresh.forEach(stdout.writeln);
    return fresh.isEmpty ? 0 : 1;
  }
}

/// `ascii_docs dart-coverage`: what the committed cases reach in ptome
/// (run with `dart --branch-coverage`).
final class DartCoverageCommand extends Command<int> {
  DartCoverageCommand() {
    argParser
      ..addOption(
        'unreached',
        help: 'Write the unreached elements to this file.',
      )
      ..addFlag(
        'gate',
        help: 'Fail unless every element is reached or excluded.',
      );
  }

  @override
  String get name => 'dart-coverage';

  @override
  String get description =>
      "What the cases reach in ptome's code (run with `dart --branch-coverage`).";

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final profile = corpus.profiles.values.whereType<PtomeProfile>().single;
    final coverage = await DartCoverage.connect();
    final cases = corpus.cases(args.rest);
    final watch = Stopwatch()..start();
    var conversions = 0;
    for (final c in cases) {
      for (final format in c.formats) {
        convertWithPtome(c.conversion(format, profile));
        conversions++;
      }
    }
    final converted = watch.elapsedMilliseconds;
    final hit = await coverage.hits();
    final excludedFile = File(p.join(corpus.root, 'exclusions', 'ptome.txt'));
    final excluded = excludedFile.existsSync()
        ? {
            for (final l in excludedFile.readAsLinesSync())
              l.split('#').first.trim(),
          }
        : <String>{};
    final universe = coverage.universe;
    final unreached = [
      for (var e = 0; e < universe.length; e++)
        if (!hit.contains(e) && !excluded.contains(universe[e])) universe[e],
    ];
    String pct(int n, int of) => '${(100 * n / of).toStringAsFixed(2)}%';
    final calls = [
      for (var e = 0; e < universe.length; e++)
        if (universe[e].endsWith(':c')) e,
    ];
    final branches = [
      for (var e = 0; e < universe.length; e++)
        if (universe[e].endsWith(':b')) e,
    ];
    final hitCalls = calls.where(hit.contains).length;
    final hitBranches = branches.where(hit.contains).length;
    stdout.writeln(
      'ptome: ${cases.length} cases, $conversions conversions in $converted ms; '
      'coverage points ${pct(hitCalls, calls.length)} ($hitCalls/${calls.length}), '
      'branch points ${pct(hitBranches, branches.length)} ($hitBranches/${branches.length}); '
      '${excluded.length} excluded, ${unreached.length} unreached'
      '${DartCoverage.branchCoverage ? '' : ' (no --branch-coverage: branch points not recorded)'}',
    );
    if (args.option('unreached') case final path?) {
      File(path).writeAsStringSync('${unreached.join('\n')}\n');
    }
    await coverage.close();
    return args.flag('gate') && unreached.isNotEmpty ? 1 : 0;
  }
}

/// `ascii_docs promote`: fuzzer finds that reach new code become cases.
final class PromoteCommand extends Command<int> {
  PromoteCommand() {
    argParser.addOption(
      'jobs',
      abbr: 'j',
      defaultsTo: '${Platform.numberOfProcessors ~/ 2}',
    );
  }

  @override
  String get name => 'promote';

  @override
  String get description =>
      'Write the queued fuzz documents that reach code no case does to cases/found.';

  @override
  Future<int> run() async {
    final report = await promote(
      Corpus.open(),
      jobs: int.parse(argResults!.option('jobs')!),
      log: stdout.writeln,
    );
    stdout.writeln(
      '${report.written.length} found cases written (${report.candidates} conversions examined, '
      '${report.disagreeing} reach new code but Ruby and ptome disagree: triage those)',
    );
    return 0;
  }
}
