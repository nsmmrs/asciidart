/// One pool document and how to convert it; the pool manifest is one JSON
/// entry per line (`$ASCII_DOCS_CACHE/pool/manifest.jsonl`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../spec/conversion.dart';
import 'source.dart';

String get manifestPath => p.join(poolDir, 'manifest.jsonl');

final class PoolEntry {
  const PoolEntry({
    required this.id,
    required this.source,
    required this.baseDir,
    this.path,
    this.text,
    this.doctype,
    this.safe,
    this.standalone,
    this.attributes = const {},
    this.extra = const {},
  }) : assert((path == null) != (text == null), 'path or text');

  /// `<source>/<path>` for files, `<source>/<file>:<line>` for heredocs,
  /// `capture-<profile>/<test>:<line>.<n>` for captured test inputs.
  final String id;
  final String source;

  /// The directory includes resolve against.
  final String baseDir;

  /// The document file, or null when [text] holds the document.
  final String? path;
  final String? text;

  final String? doctype;
  final Safe? safe;
  final bool? standalone;
  final Map<String, String> attributes;

  /// Other Asciidoctor API options a captured test passed (Ruby only).
  final Map<String, Object?> extra;

  String get input =>
      text ?? utf8.decode(File(path!).readAsBytesSync(), allowMalformed: true);

  /// The conversion of this entry to [format], with [defaults] under the
  /// entry's own attributes.
  Conversion conversion(
    Format format, {
    Map<String, String> defaults = const {},
  }) => Conversion(
    id: '$id#${format.name}',
    input: input,
    format: format,
    baseDir: baseDir,
    doctype: doctype,
    safe: safe ?? Safe.safe,
    standalone: standalone ?? false,
    attributes: {...defaults, ...attributes},
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'base_dir': baseDir,
    'path': ?path,
    'text': ?text,
    'doctype': ?doctype,
    'safe': ?safe?.name,
    'standalone': ?standalone,
    if (attributes.isNotEmpty) 'attributes': attributes,
    if (extra.isNotEmpty) 'extra': extra,
  };

  static PoolEntry fromJson(Map<String, Object?> json) => PoolEntry(
    id: json['id']! as String,
    source: json['source']! as String,
    baseDir: json['base_dir']! as String,
    path: json['path'] as String?,
    text: json['text'] as String?,
    doctype: json['doctype'] as String?,
    safe: switch (json['safe']) {
      final String name => Safe.parse(name),
      _ => null,
    },
    standalone: json['standalone'] as bool?,
    attributes: (json['attributes'] as Map? ?? const {}).cast<String, String>(),
    extra: (json['extra'] as Map? ?? const {}).cast<String, Object?>(),
  );

  static List<PoolEntry> readAll([String? path]) => [
    for (final line in File(path ?? manifestPath).readAsLinesSync())
      if (line.isNotEmpty) fromJson(jsonDecode(line) as Map<String, Object?>),
  ];

  static void writeAll(List<PoolEntry> entries, [String? path]) {
    final file = File(path ?? manifestPath)..parent.createSync(recursive: true);
    file.writeAsStringSync(
      entries.map((e) => jsonEncode(e.toJson())).join('\n') +
          (entries.isEmpty ? '' : '\n'),
    );
  }
}
