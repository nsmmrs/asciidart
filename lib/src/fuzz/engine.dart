/// Converts one document with Ruby (with coverage) and asciidart and
/// returns what the oracles say: shared by the fuzz loop and the
/// finding minimizer.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../oracle/asciidart_pool.dart';
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
    this.asciidart,
    this.rubyPool,
    this.dartPool,
    this.baseDir,
  );

  final Corpus corpus;
  final RubyProfile ruby;
  final AsciidartProfile asciidart;
  final RubyPool rubyPool;
  final AsciidartPool dartPool;

  /// An empty directory to convert in (includes resolve to nothing).
  final String baseDir;

  CoverageUniverse get universe => rubyPool.universe!;

  static Future<FuzzEngine> start(
    Corpus corpus, {
    required int jobs,
    required String workDir,
  }) async {
    final asciidart = corpus.profiles.values
        .whereType<AsciidartProfile>()
        .single;
    final ruby = corpus.profiles[asciidart.compareTo]! as RubyProfile;
    final base = Directory(p.join(workDir, 'base'))
      ..createSync(recursive: true);
    return FuzzEngine._(
      corpus,
      ruby,
      asciidart,
      await RubyPool.start(
        ruby,
        repoRoot: corpus.root,
        size: jobs,
        coverage: true,
      ),
      await AsciidartPool.start(size: jobs),
      base.path,
    );
  }

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
      dartPool.convert(conversion(asciidart.attributes), timeout: timeout),
    ]);
    final (rubyOut, dartOut) = (results[0], results[1]);
    final findings = [
      ...checkOutcome(rubyOut, reference, engine: ruby.name, words: words),
      ...checkOutcome(dartOut, reference, engine: asciidart.name, words: words),
    ];
    if (rubyOut case Converted(output: final String a)) {
      if (dartOut case Converted(output: final String b)) {
        final difference = compareOutputs(
          normalizeText(a, baseDir: baseDir),
          normalizeText(b, baseDir: baseDir),
          referenceName: ruby.name,
          otherName: asciidart.name,
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
    dartPool.close();
  }
}
