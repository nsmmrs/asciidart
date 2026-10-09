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
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:ptome/ptome.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:toml/toml.dart';

import '../../tool/vendored_font_directories.dart';

/// The corpus directory (tests run from the package root). Files are read
/// through ptome's I/O seam, so the corpus runs on Node.js too.
final String corpusRoot = p.posix.join(io.currentDirectory, 'test', 'corpus');

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
  const new({this.hash, this.error, this.log = const [], this.pixels});

  final String? hash;
  final String? error;
  final List<LogEntry> log;

  /// How a PDF's pages compare with the golden PDF's, pixel for pixel, as
  /// recorded (`identical`, or where they first differ).
  final String? pixels;

  List<String> get logLines => [for (final entry in log) formatLog(entry)];

  /// Whether this is the result [other] records: the same output and log,
  /// or both a crash (whose wording is the platform's).
  bool matches(Result other) =>
      (error != null && other.error != null) ||
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
    required this.goldenPdf,
    required this.caseDir,
  });

  /// The case directory (where `case.toml` is; [dir] is the input's).
  final String caseDir;

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

  /// The hash of the golden PDF (asciidoctor-pdf's, the ptome profile's
  /// `pdf-compare-to`), whose pages ptome's must equal pixel for pixel.
  final String? goldenPdf;

  /// Records [hash] (a PDF whose pages were just found identical to the
  /// golden PDF's) as ptome's in place of [old] in `versions.toml` (its
  /// pixels identical), so that the hash passes on later runs. ptome's
  /// PDFs aren't kept, only their hashes.
  void promotePdf(String old, String hash) {
    final path = p.posix.join(caseDir, 'versions.toml');
    final text = utf8.decode(io.readBytes(path));
    final start = text.indexOf('[pdf.$ptomeProfile]');
    final end = switch (text.indexOf('\n[', start + 1)) {
      -1 => text.length,
      final at => at,
    };
    final section = text
        .substring(start, end)
        .replaceFirst("output = '$old'", "output = '$hash'")
        .replaceFirst(RegExp("pixels = '[^']*'"), "pixels = 'identical'");
    io.writeString(
      path,
      text.substring(0, start) + section + text.substring(end),
    );
  }

  /// How the pages of [pdf] (whose hash is [hash]) compare with the golden
  /// PDF's: `identical`, or where they first differ; null when they can't
  /// be rendered (no `pdftoppm`).
  String? comparePages(Uint8List pdf, String hash) {
    final golden = _pages(
      io.readBytes(blobPath(Format.pdf, goldenPdf!)),
      goldenPdf!,
    );
    final pages = _pages(pdf, hash);
    if (golden == null || pages == null) return null;
    if (golden.length != pages.length) {
      return 'pages: ${pages.length}, not ${golden.length}';
    }
    for (var i = 0; i < golden.length; i++) {
      final (a, b) = (golden[i], pages[i]);
      if (a.length != b.length) return 'page ${i + 1}: another size';
      var differ = 0;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) differ++;
      }
      if (differ > 0) {
        final share = (differ / a.length * 100).toStringAsFixed(3);
        return 'page ${i + 1}: $share%';
      }
    }
    return 'identical';
  }

  String blobPath(Format format, String hash) =>
      p.posix.join(dir, 'expected', '${format.name}.$hash.${format.extension}');

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

/// Where page images are kept, by the hash of their PDF.
final String _pagesRoot = p.posix.join(
  io.currentDirectory,
  '.dart_tool',
  'corpus-pages',
);

/// The gray page images of [pdf] (whose hash is [hash]) at 50 dpi, as the
/// corpus tools render them (`pdftoppm -gray`), rendered once; null
/// without `pdftoppm`.
List<List<int>>? _pages(List<int> pdf, String hash) {
  final dir = p.posix.join(_pagesRoot, hash);
  final done = p.posix.join(dir, 'done');
  if (!io.isFile(done)) {
    io.createDirectories(dir);
    final file = p.posix.join(dir, 'document.pdf');
    io.writeBytes(file, pdf);
    final rendered = io.commandOutput('pdftoppm', [
      '-r',
      '50',
      '-gray',
      file,
      p.posix.join(dir, 'p'),
    ]);
    if (rendered == null) return null;
    io.writeString(done, '');
  }
  final pages = [
    for (final entry in io.listDirectory(dir))
      if (entry.name.endsWith('.pgm')) entry.name,
  ]..sort((a, b) => _pageNumber(a).compareTo(_pageNumber(b)));
  return [for (final page in pages) io.readBytes(p.posix.join(dir, page))];
}

int _pageNumber(String name) =>
    int.parse(RegExp(r'(\d+)\.pgm$').firstMatch(name)![1]!);

/// Every case under `test/corpus/cases`, in id order. PDFs and EPUBs are
/// set in the vendored fonts only, never the machine's, so results are the
/// same on every machine.
List<Case> loadCases() {
  Fonts.installed = FontIndex([
    for (final dir in vendoredFontDirectories)
      p.posix.join(io.currentDirectory, dir),
  ]);
  final defaults = _table(_toml(p.posix.join(corpusRoot, 'defaults.toml')));
  final profile = _table(
    _toml(p.posix.join(corpusRoot, 'profiles.toml'))[ptomeProfile],
  );
  final casesRoot = p.posix.join(corpusRoot, 'cases');
  final cases = <Case>[];
  void walk(String dir) {
    if (io.isFile(p.posix.join(dir, 'case.toml'))) {
      cases.add(_load(dir, casesRoot, defaults, profile));
      return;
    }
    ([
      for (final entry in io.listDirectory(dir))
        if (entry.isDirectory) p.posix.join(dir, entry.name),
    ]..sort()).forEach(walk);
  }

  walk(casesRoot);
  return cases;
}

Case _load(
  String dir,
  String casesRoot,
  Map<String, Object?> defaults,
  Map<String, Object?> profile,
) {
  final meta = _toml(p.posix.join(dir, 'case.toml'));
  final options = _table(meta['options']);
  final versions = io.isFile(p.posix.join(dir, 'versions.toml'))
      ? _toml(p.posix.join(dir, 'versions.toml'))
      : const <String, Object?>{};
  final input = p.posix.normalize(
    p.posix.join(dir, options['input'] as String? ?? 'input.adoc'),
  );
  return Case._(
    id: p.posix.relative(dir, from: casesRoot),
    dir: p.posix.dirname(input),
    input: utf8.decode(io.readBytes(input), allowMalformed: true),
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
    caseDir: dir,
    goldenPdf: switch (profile['pdf-compare-to']) {
      final String golden =>
        _table(_table(versions['pdf'])[golden])['output'] as String?,
      _ => null,
    },
  );
}

Result _result(Map<String, Object?> table) => Result(
  hash: table['output'] as String?,
  error: table['error'] as String?,
  pixels: table['pixels'] as String?,
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

Map<String, Object?> _toml(String path) =>
    TomlDocument.parse(utf8.decode(io.readBytes(path))).toMap();

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
    .replaceAll(baseDir, '{base}')
    .replaceAll(_native(baseDir), '{base}')
    .replaceAll(io.currentDirectory, '{cwd}')
    .replaceAll(_native(io.currentDirectory), '{cwd}');

/// [path] with the platform's separators (on Windows, backslashes).
String _native(String path) => io.isWindows ? path.replaceAll('/', r'\') : path;

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
