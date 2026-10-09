/// Reads the black-box corpus in `test/corpus` (written by
/// `packages/ptome_corpus_tools`) and converts its cases with ptome.
///
/// ```text
/// test/corpus/
///   profiles.toml     the implementations recorded; [ptome] is checked here
///   defaults.toml     options every case starts from
///   cases/<set>/<name>/
///     case.toml       description, source, formats, options, attributes
///     input.adoc      the document
///     expected/       <format>.<hash>.<ext>, one blob per distinct output
///     versions.toml   [<format>.<profile>] output | error, log, divergence
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:ptome/ptome.dart';
import 'package:ptome/src/font_index.dart';
import 'package:toml/toml.dart';

import '../vendored_fonts.dart';
import 'paths.dart';

/// The corpus directory (tests run from the package root).
final String corpusRoot = p.absolute('test', 'corpus');

/// The profile whose recorded results ptome is checked against.
const ptomeProfile = 'ptome';

/// The output formats a case can name, with their blob extensions.
enum Format {
  html5('html'),
  xhtml5('xhtml'),
  docbook5('xml'),
  manpage('man'),
  pdf('pdf'),
  epub3('epub');

  new(this.extension);

  final String extension;

  bool get binary => this == pdf || this == epub3;

  Backend get backend => switch (this) {
    html5 => Backend.html5,
    xhtml5 => Backend.xhtml5,
    docbook5 => Backend.docbook5,
    manpage => Backend.manpage,
    pdf => Backend.pdf,
    epub3 => Backend.epub3,
  };
}

/// One logged message: `severity:line: message` in `versions.toml`.
typedef LogEntry = ({String severity, int? line, String message});

String formatLog(LogEntry entry) =>
    '${entry.severity}:${entry.line ?? ''}: ${entry.message}';

/// What a conversion gave, normalized: an output blob's hash or an error.
final class Result {
  const new({this.hash, this.error, this.log = const []});

  final String? hash;
  final String? error;
  final List<LogEntry> log;

  List<String> get logLines => [for (final entry in log) formatLog(entry)];

  bool matches(Result other) =>
      hash == other.hash &&
      error == other.error &&
      logLines.join('\n') == other.logLines.join('\n');
}

/// One case: a document, its options, and ptome's recorded result per
/// format.
final class Case {
  new _({
    required this.id,
    required this.dir,
    required this.input,
    required this.formats,
    required this.doctype,
    required this.safe,
    required this.standalone,
    required this.attributes,
    required this.knownIssues,
    required this.expected,
  });

  /// The case directory relative to `cases/`.
  final String id;
  final String dir;
  final String input;
  final List<Format> formats;
  final Doctype? doctype;
  final SafeMode safe;
  final bool standalone;
  final Map<String, String> attributes;

  /// Formats ptome can't be checked on yet, with the reason.
  final Map<Format, String> knownIssues;

  /// ptome's recorded result per format.
  final Map<Format, Result> expected;

  String blobPath(Format format, String hash) =>
      p.join(dir, 'expected', '${format.name}.$hash.${format.extension}');

  /// Converts the case to [format] with ptome, normalized as recorded.
  ({Result result, Object? output}) convert(Format format) {
    final log = <LogEntry>[];
    final ptome = Ptome(
      safe: safe,
      baseDir: dir,
      onDiagnostic: (d) => log.add((
        severity: d.severity.name,
        line: d.location?.line,
        message: normalizeText(d.message, baseDir: dir),
      )),
    );
    try {
      final output = format.binary
          ? ptome.convertToBytes(
              input,
              backend: format.backend,
              doctype: doctype,
              attributes: attributes,
            )
          : normalizeText(
              ptome.convert(
                input,
                backend: format.backend,
                doctype: doctype,
                standalone: standalone,
                attributes: attributes,
              ),
              baseDir: dir,
            );
      final bytes = switch (output) {
        final String text => utf8.encode(text),
        final Uint8List bytes => bytes,
        _ => throw StateError('output'),
      };
      return (
        result: Result(hash: contentHash(bytes), log: log),
        output: output,
      );
    } on Object catch (error) {
      final message = normalizeText(
        '${error.runtimeType}: $error'.split('\n').first,
        baseDir: dir,
      );
      return (result: Result(error: message), output: null);
    }
  }
}

/// Every case under `test/corpus/cases`, in id order. PDFs and EPUBs are
/// set in the vendored fonts only, never the machine's, so results are the
/// same on every machine.
List<Case> loadCases() {
  Fonts.installed = FontIndex([
    for (final dir in vendoredFontDirectories) p.absolute(dir),
  ]);
  final defaults = _table(_toml(p.join(corpusRoot, 'defaults.toml')));
  final profile = _table(
    _toml(p.join(corpusRoot, 'profiles.toml'))[ptomeProfile],
  );
  final casesRoot = p.join(corpusRoot, 'cases');
  final cases = <Case>[];
  void walk(Directory dir) {
    if (File(p.join(dir.path, 'case.toml')).existsSync()) {
      cases.add(_load(dir.path, casesRoot, defaults, profile));
      return;
    }
    (dir.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        .forEach(walk);
  }

  walk(Directory(casesRoot));
  return cases;
}

Case _load(
  String dir,
  String casesRoot,
  Map<String, Object?> defaults,
  Map<String, Object?> profile,
) {
  final meta = _toml(p.join(dir, 'case.toml'));
  final options = _table(meta['options']);
  final versions = File(p.join(dir, 'versions.toml')).existsSync()
      ? _toml(p.join(dir, 'versions.toml'))
      : const <String, Object?>{};
  final input = p.normalize(
    p.join(dir, options['input'] as String? ?? 'input.adoc'),
  );
  return Case._(
    id: p.relative(dir, from: casesRoot),
    dir: p.dirname(input),
    input: utf8.decode(File(input).readAsBytesSync(), allowMalformed: true),
    formats: [
      for (final name in meta['formats'] as List? ?? const ['html5'])
        Format.values.byName(name as String),
    ],
    doctype: switch (options['doctype']) {
      final String name => Doctype.values.byName(name),
      _ => null,
    },
    safe: SafeMode.values.byName(
      options['safe'] as String? ?? defaults['safe'] as String? ?? 'safe',
    ),
    standalone:
        options['standalone'] as bool? ??
        defaults['standalone'] as bool? ??
        false,
    // The profile's attributes are soft defaults under the case's own.
    attributes: _merge(
      _strings(profile['attributes']),
      _merge(_strings(defaults['attributes']), _strings(meta['attributes'])),
    ),
    knownIssues: {
      for (final MapEntry(:key, :value) in _table(meta['known-issues']).entries)
        Format.values.byName(key): value! as String,
    },
    expected: {
      for (final MapEntry(:key, :value) in versions.entries)
        if (_table(value)[ptomeProfile] case final Map<Object?, Object?> t)
          Format.values.byName(key): _result(t.cast<String, Object?>()),
    },
  );
}

Result _result(Map<String, Object?> table) => Result(
  hash: table['output'] as String?,
  error: table['error'] as String?,
  log: [
    for (final line in table['log'] as List? ?? const []) _log(line as String),
  ],
);

LogEntry _log(String text) {
  final first = text.indexOf(':');
  final second = text.indexOf(':', first + 1);
  final line = text.substring(first + 1, second);
  return (
    severity: text.substring(0, first),
    line: line.isEmpty ? null : int.parse(line),
    message: text.substring(second + 2),
  );
}

Map<String, Object?> _toml(String path) => TomlDocument.loadSync(path).toMap();

Map<String, Object?> _table(Object? value) =>
    (value as Map? ?? const {}).cast<String, Object?>();

/// A TOML attribute table as API attributes: `name = false` unsets.
Map<String, String> _strings(Object? table) => {
  for (final MapEntry(:key, :value) in _table(table).entries)
    if (value == false) '$key!': '' else key: '$value',
};

/// [over] on top of [base]; an unset (`name!`) in [over] drops `name`.
Map<String, String> _merge(
  Map<String, String> base,
  Map<String, String> over,
) => {
  for (final MapEntry(:key, :value) in base.entries)
    if (!over.containsKey('$key!') &&
        !over.containsKey(key.replaceAll('!', '')))
      key: value,
  ...over,
};

final _versionStamp = RegExp('(?:Asciidoctor|Ptome) [0-9][0-9A-Za-z.+_~-]*');
final _lastUpdated = RegExp(
  r'Last updated \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}',
);
final _manDate = RegExp(r'^(\.\\" +Date: ).*$', multiLine: true);

/// The volatile parts of a text output or message that are not the
/// document's doing: version stamps, the HTML footer's time, the manpage
/// date, the case directory (`{base}`) and the working directory (`{cwd}`).
String normalizeText(String text, {required String baseDir}) => text
    .replaceAll(_versionStamp, 'Asciidoctor VERSION')
    .replaceAll(_lastUpdated, 'Last updated DATETIME')
    .replaceAllMapped(_manDate, (m) => '${m[1]}DATE')
    .replaceAll(posixPath(baseDir), '{base}')
    .replaceAll(baseDir, '{base}')
    .replaceAll(currentPath, '{cwd}')
    .replaceAll(Directory.current.path, '{cwd}');

/// 12 hex digits of the SHA-256 of [bytes].
String contentHash(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 12);

/// The first differing line of [want] and [got].
String firstDifference(String want, String got) {
  final a = want.split('\n');
  final b = got.split('\n');
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '<end>';
    final y = i < b.length ? b[i] : '<end>';
    if (x != y) return 'line ${i + 1}:\n- $x\n+ $y';
  }
  return '(no line differs)';
}
