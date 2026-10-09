/// One probe of a document: the Ruby profiles' coverage and outputs, and
/// ptome's output, for one format.
library;

import '../oracle/ptome_pool.dart';
import '../oracle/ruby_pool.dart';
import '../spec/conversion.dart';
import '../spec/normalize.dart';
import '../spec/profile.dart';

/// What a probe saw.
final class Probe {
  const Probe({
    required this.coverage,
    required this.outputs,
    required this.ptome,
    this.includes = const {},
  });

  /// The files the Ruby profiles included.
  final Set<String> includes;

  /// Ruby profile → elements reached (lines, then branch arms offset by
  /// the line count).
  final Map<String, Set<int>> coverage;

  /// Ruby profile → normalized output, or null if the conversion failed.
  final Map<String, String?> outputs;

  /// ptome's normalized output, or null if it failed.
  final String? ptome;

  /// Whether ptome matched [reference]'s output.
  bool agrees(String reference) =>
      ptome != null &&
      outputs[reference] != null &&
      outputs[reference] == ptome;

  /// Whether this reached every element [target] did, in every profile.
  bool covers(Probe target) => target.coverage.entries.every(
    (e) => coverage[e.key]?.containsAll(e.value) ?? false,
  );
}

/// A coverage worker for each Ruby profile, plus ptome in-process.
final class AnchorOracle {
  AnchorOracle._(
    this._workers,
    this._profiles,
    this._repoRoot,
    this.ptome,
    this._isolate,
  );

  final Map<String, RubyWorker> _workers;
  final Map<String, RubyProfile> _profiles;
  final String _repoRoot;
  final PtomeProfile ptome;

  /// ptome runs in its own isolate, beside the Ruby workers.
  final PtomePool _isolate;
  int probes = 0;

  static Future<AnchorOracle> start(
    List<RubyProfile> profiles,
    PtomeProfile ptome, {
    required String repoRoot,
  }) async {
    final workers = <String, RubyWorker>{
      for (final profile in profiles)
        profile.name: await RubyWorker.start(
          profile,
          repoRoot: repoRoot,
          coverage: true,
        ),
    };
    return AnchorOracle._(
      workers,
      {for (final p in profiles) p.name: p},
      repoRoot,
      ptome,
      await PtomePool.start(),
    );
  }

  /// Converts [conversion] with every Ruby profile (with coverage) and,
  /// unless [ptome] is false, with ptome.
  Future<Probe> probe(Conversion conversion, {bool ptome = true}) async {
    probes++;
    // The Ruby workers convert while ptome does, in this isolate.
    final pending = <String, Future<Outcome>>{};
    for (final name in _workers.keys.toList()) {
      if (_workers[name]!.dead) {
        _workers[name] = await RubyWorker.start(
          _profiles[name]!,
          repoRoot: _repoRoot,
          coverage: true,
        );
      }
      pending[name] = _workers[name]!.convert(
        _withProfile(conversion, _profiles[name]!.attributes),
        timeout: const Duration(seconds: 20),
      );
    }
    final mine = ptome
        ? await _isolate.convert(
            _withProfile(conversion, this.ptome.attributes),
            timeout: const Duration(seconds: 20),
          )
        : null;
    final coverage = <String, Set<int>>{};
    final outputs = <String, String?>{};
    final includes = <String>{};
    for (final MapEntry(key: name, value: future) in pending.entries) {
      final outcome = await future;
      if (outcome is Converted) includes.addAll(outcome.includes);
      final lines = _workers[name]!.universe!.lines.length;
      final reached = switch (outcome) {
        Converted(:final coverage) || Crashed(:final coverage) => coverage,
        TimedOut() => null,
      };
      coverage[name] = {
        ...?reached?.lines,
        for (final b in reached?.branches ?? const <int>[]) lines + b,
      };
      outputs[name] = switch (outcome) {
        Converted(:final output) => normalizeText(
          output as String,
          baseDir: conversion.baseDir,
        ),
        _ => null,
      };
    }
    return Probe(
      coverage: coverage,
      outputs: outputs,
      includes: includes,
      ptome: switch (mine) {
        Converted(:final output) when output is String => normalizeText(
          output,
          baseDir: conversion.baseDir,
        ),
        _ => null,
      },
    );
  }

  Conversion _withProfile(Conversion c, Map<String, String> attributes) =>
      Conversion(
        id: c.id,
        input: c.input,
        format: c.format,
        baseDir: c.baseDir,
        doctype: c.doctype,
        safe: c.safe,
        standalone: c.standalone,
        attributes: {...attributes, ...c.attributes},
        extra: c.extra,
      );

  Future<void> close() {
    _isolate.close();
    return _closeWorkers();
  }

  Future<void> _closeWorkers() => Future.wait([
    for (final w in _workers.values)
      if (!w.dead) w.close(),
  ]);
}
