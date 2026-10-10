/// A corpus case: a directory of `packages/ptome/test/corpus` with the
/// document, the files it reads, and the goldens (ptome's ADR-0022).
///
/// ```text
/// <case>/
///   input.adoc      the document, with the files it reads beside it
///   case.yml        source, formats, safe, doctype, attributes, defects
///   expected/<release>/<format>/<file>   what Asciidoctor wrote
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'conversion.dart';
import 'profile.dart';

/// What `case.yml` says: where the document came from and how it converts.
final class CaseOptions {
  const CaseOptions({
    required this.source,
    required this.formats,
    this.safe = Safe.unsafe,
    this.doctype,
    this.attributes = const {},
    this.keptWords = const [],
    this.defects = const {},
  });

  /// Where the case came from: `handmade`, `pool:<source>/<path>`,
  /// `gen:<id>`, `bugfix:<issue>`.
  final String source;
  final List<Format> formats;

  /// The command line's `-S` (its default: unsafe).
  final Safe safe;
  final String? doctype;

  /// The case's own attributes, as `-a` options; `name!` unsets.
  final Map<String, String> attributes;

  /// Words the sanitizer left original (replacing them changed the
  /// conversion).
  final List<String> keptWords;

  /// Formats whose golden shows an Asciidoctor defect ptome doesn't
  /// reproduce, with what it is.
  final Map<Format, String> defects;

  static CaseOptions read(String path) {
    final yaml = switch (loadYaml(File(path).readAsStringSync())) {
      final YamlMap map => map,
      _ => YamlMap(),
    };
    return CaseOptions(
      source: yaml['source'] as String? ?? '',
      formats: [
        for (final name in yaml['formats'] as YamlList? ?? YamlList())
          Format.parse('$name'),
      ],
      safe: Safe.parse(yaml['safe'] as String? ?? 'unsafe'),
      doctype: yaml['doctype'] as String?,
      attributes: {
        for (final MapEntry(:key, :value)
            in (yaml['attributes'] as YamlMap? ?? YamlMap()).entries)
          if (value == false) '$key!': '' else '$key': '$value',
      },
      keptWords: [
        for (final word in yaml['kept-words'] as YamlList? ?? YamlList())
          '$word',
      ],
      defects: {
        for (final MapEntry(:key, :value)
            in (yaml['defects'] as YamlMap? ?? YamlMap()).entries)
          Format.parse('$key'): '$value',
      },
    );
  }

  /// `case.yml`, as the corpus's cases write it.
  String toYaml() {
    String q(String s) => jsonEncode(s); // a JSON string is a YAML one
    return [
      'source: ${q(source)}',
      'formats: [${formats.map((f) => f.name).join(', ')}]',
      'safe: ${safe.name}',
      if (doctype != null) 'doctype: ${q(doctype!)}',
      if (attributes.isNotEmpty) ...[
        'attributes:',
        for (final MapEntry(:key, :value) in attributes.entries)
          key.endsWith('!')
              ? '  ${q(key.substring(0, key.length - 1))}: false'
              : '  ${q(key)}: ${q(value)}',
      ],
      if (keptWords.isNotEmpty) ...[
        '# Original words left in place (replacing them changed the conversion).',
        'kept-words: [${keptWords.map(q).join(', ')}]',
      ],
      if (defects.isNotEmpty) ...[
        'defects:',
        for (final MapEntry(:key, :value) in defects.entries)
          '  ${key.name}: ${q(value)}',
      ],
      '',
    ].join('\n');
  }
}

final class Case {
  Case({
    required this.name,
    required this.dir,
    required this.input,
    required this.options,
    required this.corpusAttributes,
  });

  /// The directory's name.
  final String name;
  final String dir;

  /// The document's text.
  final String input;
  final CaseOptions options;

  /// The attributes every conversion of the corpus gets (`goldens.yml`).
  final Map<String, String> corpusAttributes;

  List<Format> get formats => options.formats;
  String get source => options.source;
  String? get doctype => options.doctype;
  Safe get safe => options.safe;
  Map<String, String> get attributes => options.attributes;

  /// The conversion [profile] runs for [format]: a whole document, as the
  /// command line converts it, with the corpus's attributes, then the
  /// profile's, then the case's.
  Conversion conversion(Format format, Profile profile) => Conversion(
    id: '$name#${format.name}',
    input: input,
    format: format,
    baseDir: dir,
    doctype: doctype,
    safe: safe,
    standalone: true,
    attributes: mergeAttributes({
      ...corpusAttributes,
      ...profile.attributes,
    }, attributes),
  );

  /// The case in [dir].
  static Case load(String dir, {required Map<String, String> attributes}) {
    final options = File(p.join(dir, 'case.yml'));
    return Case(
      name: p.basename(dir),
      dir: dir,
      input: utf8.decode(
        File(p.join(dir, 'input.adoc')).readAsBytesSync(),
        allowMalformed: true,
      ),
      options: options.existsSync()
          ? CaseOptions.read(options.path)
          : const CaseOptions(source: '', formats: [Format.html5]),
      corpusAttributes: attributes,
    );
  }
}

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
