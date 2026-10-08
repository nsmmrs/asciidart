/// Builds `cases/anchor` from the measured pool: select the conversions
/// that keep the pool's coverage, cut each down, sanitize it, verify it
/// converts the same way, and write it as a case.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../pool/dart_measure.dart';
import '../pool/entry.dart';
import '../pool/measure.dart';
import '../pool/source.dart';
import '../pool/stats.dart';
import '../sanitize/sanitizer.dart';
import '../sanitize/word_map.dart';
import '../select/cover.dart';
import '../select/reduce.dart';
import '../spec/conversion.dart';
import '../spec/corpus.dart';
import '../spec/profile.dart';
import 'oracle.dart';

/// The formats whose conversions Ruby measures (and asciidart must match).
const rubyFormats = [Format.html5, Format.docbook5, Format.manpage];

/// The formats only asciidart converts here; their candidates are verified
/// through the document's html5 conversion.
const asciidartFormats = [Format.xhtml5, Format.pdf, Format.epub3];

final class AnchorReport {
  int candidates = 0;
  int chosen = 0;
  final List<String> emitted = [];
  final Map<String, String> skipped = {};

  /// Case id → words left original (sanitizing them changed the result).
  final Map<String, List<String>> residue = {};
}

/// Chooses the anchor conversions: those whose Ruby main and asciidart
/// outputs agree (for asciidart-only formats: whose html5 outputs agree),
/// from entries without Ruby-only options, covering what they all cover.
(CoverProblem, List<int>) chooseAnchors(
  Corpus corpus,
  Map<String, PoolEntry> entries, {
  void Function(String)? log,
}) {
  final ruby = corpus.profiles.values.whereType<RubyProfile>().toList();
  final asciidart = corpus.profiles.values.whereType<AsciidartProfile>().single;
  final reference = asciidart.compareTo!;
  final measurements = <String, ProfileMeasurements>{};
  for (final profile in ruby) {
    final files = {
      for (final format in rubyFormats)
        if (File(measurePath(profile.name, format)).existsSync())
          format: MeasureFile.read(measurePath(profile.name, format)),
    };
    final universe = files.values.first.universe!;
    measurements[profile.name] = ProfileMeasurements(profile, universe, files);
  }
  final asciidartHashes = {
    for (final format in rubyFormats)
      format: MeasureFile.read(measurePath(asciidart.name, format))
          .measurements,
  };
  bool agrees(String id, Format format) {
    final mine = asciidartHashes[format]?[id];
    final theirs = measurements[reference]?.files[format]?.measurements[id];
    return mine?.hash != null && mine!.hash == theirs?.hash;
  }

  bool eligible(String id) {
    final entry = entries[id];
    return entry != null && entry.extra.isEmpty;
  }

  // asciidart elements by name across the formats' marginal files.
  final dartNames = <String, int>{};
  final dartSets = <String, List<int>>{};
  for (final format in [...rubyFormats, ...asciidartFormats]) {
    final file = File(dartCoveragePath(format));
    if (!file.existsSync()) continue;
    final records = <Map<String, Object?>>[];
    List<String>? universe;
    for (final line in file.readAsLinesSync()) {
      final json = jsonDecode(line) as Map<String, Object?>;
      if (json['universe'] case final List<Object?> u) {
        universe = u.cast<String>();
      } else {
        records.add(json);
      }
    }
    if (universe == null) continue; // still being written
    for (final record in records) {
      final key = '${record['id']}#${format.name}';
      dartSets[key] = [
        for (final e in (record['new']! as List).cast<int>())
          dartNames.putIfAbsent(universe[e], () => dartNames.length),
      ];
    }
  }

  var offset = 0;
  final offsets = <String, int>{};
  for (final pm in measurements.values) {
    offsets[pm.profile.name] = offset;
    offset += pm.size;
  }
  final problem = CoverProblem(offset + dartNames.length);
  for (final pm in measurements.values) {
    for (final MapEntry(key: format, value: file) in pm.files.entries) {
      for (final m in file.measurements.values) {
        if (!eligible(m.id) || !agrees(m.id, format) || m.error != null)
          continue;
        problem.add(
          '${m.id}#${format.name}',
          pm.elements(m).map((e) => e + offsets[pm.profile.name]!),
          cost: m.micros,
        );
      }
    }
  }
  for (final MapEntry(:key, :value) in dartSets.entries) {
    final hash = key.lastIndexOf('#');
    final id = key.substring(0, hash);
    final format = Format.parse(key.substring(hash + 1));
    final proxy = rubyFormats.contains(format) ? format : Format.html5;
    if (!eligible(id) || !agrees(id, proxy)) continue;
    problem.add(key, value.map((e) => e + offset));
  }
  final chosen = greedyCover(problem);
  log?.call(
    'anchor cover: ${chosen.length} of ${problem.ids.length} eligible conversions',
  );
  return (problem, chosen);
}

/// Reduces, sanitizes, verifies and writes the chosen conversions.
Future<AnchorReport> buildAnchors(
  Corpus corpus, {
  int lanes = 4,
  int? limit,
  bool reduce = true,
  void Function(String)? log,
}) async {
  final entries = {for (final e in PoolEntry.readAll()) e.id: e};
  final (problem, chosen) = chooseAnchors(corpus, entries, log: log);
  final report = AnchorReport()
    ..candidates = problem.ids.length
    ..chosen = chosen.length;
  final work = [for (final i in chosen) problem.ids[i]];
  if (limit != null && work.length > limit) work.length = limit;
  final ruby = corpus.profiles.values.whereType<RubyProfile>().toList();
  final asciidart = corpus.profiles.values.whereType<AsciidartProfile>().single;
  final map = WordMap();
  var next = 0;
  Future<void> lane() async {
    final oracle = await AnchorOracle.start(
      ruby,
      asciidart,
      repoRoot: corpus.root,
    );
    try {
      while (next < work.length) {
        final key = work[next++];
        final hash = key.lastIndexOf('#');
        final entry = entries[key.substring(0, hash)]!;
        final format = Format.parse(key.substring(hash + 1));
        try {
          final watch = Stopwatch()..start();
          final before = oracle.probes;
          final result = await _anchor(
            corpus,
            oracle,
            entry,
            format,
            map: map,
            reduce: reduce,
            reference: asciidart.compareTo!,
            log: log,
          );
          switch (result) {
            case (final String id, final List<String> residue):
              report.emitted.add(id);
              if (residue.isNotEmpty) report.residue[id] = residue;
              log?.call(
                'anchor ${report.emitted.length}/${work.length}: $id '
                '(${oracle.probes - before} probes, ${watch.elapsed.inSeconds}s)'
                '${residue.isEmpty ? '' : ' (${residue.length} words kept)'}',
              );
            case final String reason:
              report.skipped[key] = reason;
              log?.call('skipped $key: $reason');
          }
        } on Object catch (e) {
          report.skipped[key] = 'error: $e';
          log?.call('skipped $key: $e');
        }
      }
    } finally {
      await oracle.close();
    }
  }

  await Future.wait([for (var i = 0; i < lanes; i++) lane()]);
  return report;
}

/// One anchor: `(case id, residue words)`, or why it was skipped.
Future<Object> _anchor(
  Corpus corpus,
  AnchorOracle oracle,
  PoolEntry entry,
  Format format, {
  required WordMap map,
  required bool reduce,
  required String reference,
  void Function(String)? log,
}) async {
  // asciidart-only formats are checked through the document's html5.
  final checked = rubyFormats.contains(format) ? format : Format.html5;
  final defaults = corpus.defaults.attributes;
  Conversion conversion(String input, String baseDir) => Conversion(
    id: entry.id,
    input: input,
    format: checked,
    baseDir: baseDir,
    doctype: entry.doctype,
    safe: entry.safe ?? Safe.safe,
    standalone: entry.standalone ?? false,
    attributes: {...defaults, ...entry.attributes},
  );

  final original = entry.input;
  await oracle.probe(conversion(original, entry.baseDir)); // warm lazy paths
  final target = await oracle.probe(conversion(original, entry.baseDir));
  if (!target.agrees(reference)) return 'outputs differ on a second run';

  var input = original;
  if (reduce && checked == format) {
    // Ruby coverage alone guides the cut (asciidart agreement is checked
    // once, after); past the budget the smallest passing document so far
    // is kept.
    var budget = reduceBudget;
    final lines = await reduceLines(original.split('\n'), (candidate) async {
      if (budget-- <= 0) return false;
      final probe = await oracle.probe(
        conversion(candidate.join('\n'), entry.baseDir),
        asciidart: false,
      );
      return probe.covers(target);
    });
    input = lines.join('\n');
  }
  var reduced = await oracle.probe(conversion(input, entry.baseDir));
  if (!reduced.agrees(reference)) {
    input = original;
    reduced = target;
  }
  log?.call(
    '  ${entry.id}#${format.name}: ${original.split('\n').length} -> '
    '${input.split('\n').length} lines',
  );

  final slug = _slug(entry, format);
  final stage = p.join(poolDir, '..', 'anchor', 'stage', slug);
  // The document and every file it includes, laid out as they were,
  // relative to the deepest directory holding them all.
  final includes = [
    for (final f in reduced.includes)
      if (File(f).existsSync()) f,
  ];
  final root = _commonAncestor([
    entry.baseDir,
    for (final f in includes) p.dirname(f),
  ]);
  if (!p.isWithin(cacheDir, root) && root != entry.baseDir) {
    return 'includes reach outside the pool ($root)';
  }
  final inputRel = p.join(p.relative(entry.baseDir, from: root), 'input.adoc');
  final stagedBase = p.normalize(p.join(stage, p.dirname(inputRel)));

  // One map per document, one to one over the words it and its includes
  // use, so sanitizing can't merge two words (and the IDs made of them).
  final vocabulary = <String>{
    for (final m in wordPattern.allMatches(input)) m[0]!,
    for (final path in includes)
      for (final m in wordPattern.allMatches(_read(path))) m[0]!,
  };
  final documentMap = WordMap.forVocabulary(vocabulary);
  Future<(bool, Sanitizer)> attempt(Set<String> restore) async {
    final sanitizer = Sanitizer(documentMap, restore: restore);
    final dir = Directory(stage);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final text = sanitizer.sanitize(input);
    File(p.join(stage, inputRel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    for (final path in includes) {
      final source = _read(path);
      final isDoc = const {
        '.adoc',
        '.asciidoc',
        '.asc',
        '.ad',
        '.txt',
      }.contains(p.extension(path));
      File(p.join(stage, p.relative(path, from: root)))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          isDoc ? sanitizer.sanitize(source) : sanitizer.sanitizeCode(source),
        );
    }
    final probe = await oracle.probe(conversion(text, stagedBase));
    final ok =
        probe.covers(target) &&
        probe.agrees(reference) &&
        shapeOf(probe.outputs[reference]!) ==
            shapeOf(reduced.outputs[reference]!);
    return (ok, sanitizer);
  }

  var (ok, sanitizer) = await attempt(const {});
  var restore = <String>{};
  if (!ok) {
    final words = sanitizer.replaced.toList()..sort();
    final (all, _) = await attempt(words.toSet());
    if (!all)
      return 'staged copy fails even unsanitized (includes outside the document?)';
    var budget = restoreBudget;
    restore = (await ddmin(
      words,
      (subset) async => budget-- > 0 && (await attempt(subset.toSet())).$1,
    )).toSet();
    (ok, sanitizer) = await attempt(restore);
    if (!ok) return 'no restore set verifies';
  }

  final caseDir = p.join(corpus.casesRoot, 'anchor', entry.source, slug);
  final dir = Directory(caseDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  _copyTree(stage, caseDir);
  Directory(stage).deleteSync(recursive: true);
  File(p.join(caseDir, 'case.toml')).writeAsStringSync(
    _caseToml(entry, format, input: inputRel, kept: restore.toList()..sort()),
  );
  return (
    p.relative(caseDir, from: corpus.casesRoot),
    restore.toList()..sort(),
  );
}

/// Probes a reduction may spend before it settles for what it has.
const reduceBudget = 600;

/// Probes the search for words to leave original may spend.
const restoreBudget = 200;

void _copyTree(String from, String to) {
  for (final entity in Directory(from).listSync(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)))
      ..parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
}

String _slug(PoolEntry entry, Format format) {
  final base = p.basenameWithoutExtension(entry.id.replaceAll(':', '-'));
  final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  final hash = sha256.convert(utf8.encode(entry.id)).toString().substring(0, 8);
  return '$clean-${format.name}-$hash';
}

String _read(String path) =>
    utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);

/// The deepest directory containing every one of [dirs].
String _commonAncestor(List<String> dirs) {
  var root = p.normalize(dirs.first);
  for (final dir in dirs.skip(1)) {
    final d = p.normalize(dir);
    while (root != d && !p.isWithin(root, d)) {
      root = p.dirname(root);
    }
  }
  return root;
}

String _caseToml(
  PoolEntry entry,
  Format format, {
  required String input,
  List<String> kept = const [],
}) {
  String q(String s) =>
      jsonEncode(s); // a TOML basic string is JSON-compatible here
  final options = [
    if (input != 'input.adoc') 'input = ${q(input)}',
    if (entry.doctype != null) 'doctype = ${q(entry.doctype!)}',
    if (entry.safe != null) 'safe = ${q(entry.safe!.name)}',
    if (entry.standalone != null) 'standalone = ${entry.standalone}',
  ];
  return [
    'description = "Anchor: a pool document cut down and sanitized."',
    'source = ${q('pool:${entry.id}')}',
    'formats = ["${format.name}"]',
    if (kept.isNotEmpty)
      '# Original words left in place (replacing them changed the conversion).\n'
          'kept-words = [${kept.map(q).join(', ')}]',
    if (options.isNotEmpty) '\n[options]\n${options.join('\n')}',
    if (entry.attributes.isNotEmpty)
      '\n[attributes]\n${[for (final MapEntry(:key, :value) in entry.attributes.entries) '${q(key)} = ${q(value)}'].join('\n')}',
    '',
  ].join('\n');
}
