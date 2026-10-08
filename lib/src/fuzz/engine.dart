/// Converts one document with Ruby (with coverage) and ptome and
/// returns what the oracles say: shared by the fuzz loop and the
/// finding minimizer.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../oracle/ruby_pool.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/normalize.dart';
import '../spec/profile.dart';
import 'oracles.dart';

/// How to convert a fuzzed document.
final class FuzzOptions {
  const FuzzOptions({
    this.doctype,
    this.standalone = false,
    this.attributes = const {},
  });

  final String? doctype;
  final bool standalone;
  final Map<String, String> attributes;

  Map<String, Object?> toJson() => {
    'doctype': doctype,
    'standalone': standalone,
    'attributes': attributes,
  };

  static FuzzOptions fromJson(Map<String, Object?> json) => FuzzOptions(
    doctype: json['doctype'] as String?,
    standalone: json['standalone'] as bool? ?? false,
    attributes: (json['attributes'] as Map? ?? const {}).cast<String, String>(),
  );
}

/// One document converted to one format by both engines.
final class Examination {
  const Examination(this.findings, this.coverage);

  final List<Finding> findings;

  /// What Ruby reached, or null if it timed out.
  final CaseCoverage? coverage;
}

final class FuzzEngine {
  FuzzEngine._(
    this.corpus,
    this.ruby,
    this.ptome,
    this.rubyPool,
    this.dartPool,
    this.baseDir,
  );

  final Corpus corpus;
  final RubyProfile ruby;
  final PtomeProfile ptome;
  final RubyPool rubyPool;

  /// ptome in worker processes (bin/ptome_worker.dart, compiled AOT): a
  /// document that hangs or crashes it costs one process.
  final RubyPool dartPool;

  /// An empty directory to convert in (includes resolve to nothing).
  final String baseDir;

  CoverageUniverse get universe => rubyPool.universe!;

  static Future<FuzzEngine> start(
    Corpus corpus, {
    required int jobs,
    required String workDir,
  }) async {
    final ptome = corpus.profiles.values.whereType<PtomeProfile>().single;
    final ruby = corpus.profiles[ptome.compareTo]! as RubyProfile;
    final base = Directory(p.join(workDir, 'base'))
      ..createSync(recursive: true);
    return FuzzEngine._(
      corpus,
      ruby,
      ptome,
      await RubyPool.start(
        ruby,
        repoRoot: corpus.root,
        size: jobs,
        coverage: true,
      ),
      await RubyPool.withWorkers(() => _ptomeWorker(corpus.root), size: jobs),
      base.path,
    );
  }

  static Future<RubyWorker> _ptomeWorker(String root) => RubyWorker.spawn(
    [
      'systemd-run',
      '--user',
      '--scope',
      '-q',
      '-p',
      'MemoryMax=2G',
      '-p',
      'MemorySwapMax=0', //
      ptomeWorkerExecutable(root),
    ],
    environment: {...Platform.environment, 'TZ': 'UTC'},
  );

  Future<Examination> examine(
    String text,
    Format format,
    FuzzOptions options, {
    String id = 'doc',
    Set<String> words = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    Conversion conversion(Map<String, String> profileAttributes) => Conversion(
      id: '$id#${format.name}',
      input: text,
      format: format,
      baseDir: baseDir,
      doctype: options.doctype,
      standalone: options.standalone,
      attributes: {
        ...profileAttributes,
        ...corpus.defaults.attributes,
        ...options.attributes,
      },
    );
    final reference = conversion(const {});
    final results = await Future.wait([
      rubyPool.convert(conversion(ruby.attributes), timeout: timeout),
      dartPool.convert(conversion(ptome.attributes), timeout: timeout),
    ]);
    final (rubyOut, dartOut) = (results[0], results[1]);
    final findings = [
      ...checkOutcome(rubyOut, reference, engine: ruby.name, words: words),
      ...checkOutcome(dartOut, reference, engine: ptome.name, words: words),
    ];
    if (rubyOut case Converted(output: final String a)) {
      if (dartOut case Converted(output: final String b)) {
        final difference = compareOutputs(
          normalizeText(a, baseDir: baseDir),
          normalizeText(b, baseDir: baseDir),
          referenceName: ruby.name,
          otherName: ptome.name,
        );
        if (difference != null) findings.add(difference);
      }
    }
    return Examination(findings, switch (rubyOut) {
      Converted(:final coverage) || Crashed(:final coverage) => coverage,
      TimedOut() => null,
    });
  }

  Future<void> close() async {
    await rubyPool.close();
    await dartPool.close();
  }
}

/// build/ptome_worker, compiled from bin/ptome_worker.dart when missing or
/// older than the sources (ascii-docs' and the ptome checkout's).
String ptomeWorkerExecutable(String root) {
  final exe = File(p.join(root, 'build', 'ptome_worker'));
  DateTime newest(String dir) {
    var latest = DateTime(1970);
    final d = Directory(dir);
    if (!d.existsSync()) return latest;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final m = f.lastModifiedSync();
      if (m.isAfter(latest)) latest = m;
    }
    return latest;
  }

  final config = File(p.join(root, '.dart_tool', 'package_config.json'));
  final ptomeRoot = RegExp(r'"name": "ptome",\s*"rootUri": "([^"]+)"')
      .firstMatch(config.existsSync() ? config.readAsStringSync() : '')?[1];
  final sources = [
    newest(p.join(root, 'lib')),
    newest(p.join(root, 'bin')),
    if (ptomeRoot != null)
      newest(
        p.join(
          p.normalize(
            p.join(
              root,
              '.dart_tool',
              Uri.decodeFull(ptomeRoot).replaceFirst('file://', ''),
            ),
          ),
          'lib',
        ),
      ),
  ].reduce((a, b) => a.isAfter(b) ? a : b);
  if (!exe.existsSync() || exe.lastModifiedSync().isBefore(sources)) {
    exe.parent.createSync(recursive: true);
    final result = Process.runSync(Platform.resolvedExecutable, [
      'compile',
      'exe',
      p.join(root, 'bin', 'ptome_worker.dart'),
      '-o',
      exe.path, //
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'dart',
        ['compile', 'exe'],
        '${result.stdout}${result.stderr}',
        result.exitCode,
      );
    }
  }
  return exe.path;
}
