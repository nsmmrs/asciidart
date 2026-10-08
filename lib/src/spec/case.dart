/// A corpus case: one input document, the formats it converts to, and the
/// expected output of each profile for each format.
///
/// ```text
/// cases/<set>/<name>/
///   case.toml       description, provenance, options, attributes, formats
///   input.adoc      the document
///   expected/       <format>.<hash>.<ext> blobs, one per distinct output
///   versions.toml   [<format>.<profile>] output = "<hash>", log = [...]
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import 'conversion.dart';
import 'profile.dart';

/// Options every case starts from (`defaults.toml`).
final class Defaults {
  const Defaults({
    this.safe = Safe.safe,
    this.standalone = false,
    this.attributes = const {},
  });

  final Safe safe;
  final bool standalone;
  final Map<String, String> attributes;

  static Defaults load(String path) {
    final map = TomlDocument.loadSync(path).toMap();
    return Defaults(
      safe: Safe.parse(map['safe'] as String? ?? 'safe'),
      standalone: map['standalone'] as bool? ?? false,
      attributes: _strings(map['attributes']),
    );
  }
}

/// What a case records about one profile's output for one format: an
/// output blob, or the error the conversion stopped with.
final class Expected {
  const Expected({this.hash, this.error, this.log = const [], this.divergence})
    : assert((hash == null) != (error == null), 'output or error');

  /// The content address of the output blob.
  final String? hash;

  /// `<ErrorClass>: <message>` (or `timeout`) when the conversion failed.
  final String? error;
  final List<LogEntry> log;

  /// Why this output differs from the profile it is compared to (a link to
  /// the fixed upstream bug), if it does.
  final String? divergence;

  /// Whether this records the same result as [other] (ignoring the note).
  bool sameResult(Expected other) =>
      hash == other.hash &&
      error == other.error &&
      log.length == other.log.length &&
      [for (var i = 0; i < log.length; i++) log[i] == other.log[i]]
          .every((x) => x);

  /// Whether this behaves like [other] across implementations: the same
  /// output and log, or both stopped with an error (whose wording is each
  /// implementation's own).
  bool sameBehavior(Expected other) =>
      (error != null && other.error != null) ||
      (hash == other.hash && error == other.error && _sameLog(other));

  bool _sameLog(Expected other) =>
      log.length == other.log.length &&
      [
        for (var i = 0; i < log.length; i++)
          log[i].severity == other.log[i].severity &&
              log[i].line == other.log[i].line,
      ].every((x) => x);

  Expected withDivergence(String? divergence) =>
      Expected(hash: hash, error: error, log: log, divergence: divergence);

  Map<String, Object> toToml() => {
    'output': ?hash,
    'error': ?error,
    if (log.isNotEmpty) 'log': [for (final entry in log) '$entry'],
    'divergence': ?divergence,
  };

  static Expected fromToml(Map<String, Object?> table) => Expected(
    hash: table['output'] as String?,
    error: table['error'] as String?,
    log: [
      for (final entry in (table['log'] as List? ?? const []))
        LogEntry.parse(entry as String),
    ],
    divergence: table['divergence'] as String?,
  );
}

final class Case {
  Case({
    required this.id,
    required this.dir,
    required this.input,
    required this.formats,
    required this.baseDir,
    this.description = '',
    this.source = '',
    this.features = const [],
    this.doctype,
    this.safe = Safe.safe,
    this.standalone = false,
    this.attributes = const {},
    Map<Format, Map<String, Expected>>? expected,
  }) : expected = expected ?? {};

  /// The case directory relative to `cases/`, such as `curated/table-span`.
  final String id;
  final String dir;
  final String input;
  final List<Format> formats;
  final String baseDir;
  final String description;

  /// Where the case came from: `handmade`, `pool:<source>/<path>`,
  /// `gen:<version>/<seed>`, `bugfix:<issue>`.
  final String source;
  final List<String> features;
  final String? doctype;
  final Safe safe;
  final bool standalone;

  /// The case's own attributes (over the defaults).
  final Map<String, String> attributes;

  /// Format → profile → expected output.
  final Map<Format, Map<String, Expected>> expected;

  String get expectedDir => p.join(dir, 'expected');
  String get versionsPath => p.join(dir, 'versions.toml');

  /// The blob of [hash] for [format].
  String blobPath(Format format, String hash) =>
      p.join(expectedDir, '${format.name}.$hash.${format.extension}');

  /// The conversion [profile] runs for [format].
  Conversion conversion(Format format, Profile profile) => Conversion(
    id: '$id#${format.name}',
    input: input,
    format: format,
    baseDir: baseDir,
    doctype: doctype,
    safe: safe,
    standalone: standalone,
    // Profile attributes are defaults: a case may set or unset them.
    attributes: mergeAttributes(profile.attributes, attributes),
  );

  /// Reads the case in [dir] (whose path relative to [casesRoot] is its id).
  static Case load(
    String dir, {
    required String casesRoot,
    required Defaults defaults,
  }) {
    final meta = TomlDocument.loadSync(p.join(dir, 'case.toml')).toMap();
    final options = (meta['options'] as Map? ?? const {})
        .cast<String, Object?>();
    // The document may sit below the case directory (with the files it
    // includes around it); its directory is the base directory.
    final inputPath = p.join(dir, options['input'] as String? ?? 'input.adoc');
    final baseDir = switch (options['base_dir']) {
      null => p.dirname(inputPath),
      final String relative => p.normalize(p.join(casesRoot, '..', relative)),
      final other => throw FormatException('$dir: base_dir $other'),
    };
    final versionsFile = File(p.join(dir, 'versions.toml'));
    final expected = <Format, Map<String, Expected>>{};
    if (versionsFile.existsSync()) {
      final versions = TomlDocument.parse(versionsFile.readAsStringSync())
          .toMap();
      for (final MapEntry(:key, :value) in versions.entries) {
        expected[Format.parse(key)] = {
          for (final MapEntry(key: profile, value: table)
              in (value as Map).cast<String, Object?>().entries)
            profile: Expected.fromToml((table! as Map).cast<String, Object?>()),
        };
      }
    }
    return Case(
      id: p.relative(dir, from: casesRoot),
      dir: dir,
      input: utf8.decode(
        File(inputPath).readAsBytesSync(),
        allowMalformed: true,
      ),
      formats: [
        for (final name in (meta['formats'] as List? ?? const ['html5']))
          Format.parse(name as String),
      ],
      baseDir: baseDir,
      description: meta['description'] as String? ?? '',
      source: meta['source'] as String? ?? '',
      features: [
        for (final f in (meta['features'] as List? ?? const [])) f as String,
      ],
      doctype: options['doctype'] as String?,
      safe: Safe.parse(options['safe'] as String? ?? defaults.safe.name),
      standalone: options['standalone'] as bool? ?? defaults.standalone,
      attributes: mergeAttributes(
        defaults.attributes,
        _strings(meta['attributes']),
      ),
      expected: expected,
    );
  }

  /// Every case under [casesRoot] (a directory with a `case.toml`), by id.
  static List<Case> loadAll(String casesRoot, {required Defaults defaults}) {
    final cases = <Case>[];
    void walk(Directory dir) {
      if (File(p.join(dir.path, 'case.toml')).existsSync()) {
        cases.add(
          Case.load(dir.path, casesRoot: casesRoot, defaults: defaults),
        );
        return;
      }
      final children = dir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      children.forEach(walk);
    }

    if (Directory(casesRoot).existsSync()) walk(Directory(casesRoot));
    return cases;
  }

  /// Writes `versions.toml` from [expected].
  void writeVersions() {
    final map = <String, Object>{
      for (final format in Format.values)
        if (expected[format] case final profiles? when profiles.isNotEmpty)
          format.name: {
            for (final name in profiles.keys.toList()..sort())
              name: profiles[name]!.toToml(),
          },
    };
    File(versionsPath).writeAsStringSync(
      '# Generated by `ascii_docs regen`; edit only the divergence fields.\n'
      '${TomlDocument.fromMap(map)}',
    );
  }
}

Map<String, String> _strings(Object? table) => {
  for (final MapEntry(:key, :value) in (table as Map? ?? const {}).entries)
    // `name = false` unsets the attribute, as the API's `name!` does.
    if (value == false) '$key!': '' else key as String: value.toString(),
};

/// [over] on top of [base], where an unset (`name!`) in [over] also drops
/// `name` from [base].
Map<String, String> mergeAttributes(
  Map<String, String> base,
  Map<String, String> over,
) => {
  for (final MapEntry(:key, :value) in base.entries)
    if (!over.containsKey('$key!') &&
        !over.containsKey(key.replaceAll('!', '')))
      key: value,
  ...over,
};
