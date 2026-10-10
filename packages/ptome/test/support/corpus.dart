/// Reads the corpus in `test/corpus`: AsciiDoc documents with the files the
/// Asciidoctor command line writes for them (the goldens), and converts
/// them with ptome the same way.
///
/// ```text
/// test/corpus/
///   goldens.yml           the release compared with, and the attributes
///                         every conversion gets (a fixed clock)
///   <case>/
///     input.adoc          the document, with the files it reads beside it
///     case.yml            optional: formats, safe, doctype, attributes,
///                         defects (formats whose golden shows an Asciidoctor
///                         defect ptome doesn't reproduce, with what it is)
///     expected/<release>/<format>/<file>   what Asciidoctor wrote
///     ptome.yml           the last ptome PDFs and EPUBs found equal to the
///                         goldens, by hash
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:ptome/io.dart';
import 'package:ptome/ptome.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:yaml/yaml.dart';

import '../../tool/vendored_font_directories.dart';
import 'delete.dart';

/// The corpus directory (tests run from the package root).
final String corpusRoot = p.posix.join(io.currentDirectory, 'test', 'corpus');

/// The formats a case can have goldens of, by their backend names.
enum Format {
  html5(Backend.html5),
  xhtml5(Backend.xhtml5),
  docbook5(Backend.docbook5),
  manpage(Backend.manpage),
  pdf(Backend.pdf),
  epub3(Backend.epub3);

  new(this.backend);

  final Backend backend;

  /// Whether the file is compared by more than its bytes (a PDF by its
  /// pages, an EPUB by the files in it), with the last ptome file found
  /// equal kept by its hash.
  bool get expensive => this == pdf || this == epub3;
}

/// The corpus: the release compared with, and the cases.
final class Corpus {
  new _(this.release, this.attributes, this.cases);

  /// The goldens compared with (`asciidoctor-2.0.26`).
  final String release;

  /// The attributes every conversion gets.
  final Map<String, String> attributes;

  final List<Case> cases;
}

/// One document, its options and its goldens.
final class Case {
  new _({
    required this.name,
    required this.dir,
    required this.safe,
    required this.doctype,
    required this.attributes,
    required this.goldens,
    required this.verified,
    required this.defects,
  });

  final String name;
  final String dir;
  final SafeMode safe;
  final Doctype? doctype;

  /// The case's own attributes (`name!` unsets).
  final Map<String, String> attributes;

  /// The golden file of each format.
  final Map<Format, String> goldens;

  /// The hash of the last ptome PDF or EPUB found equal to the golden.
  final Map<Format, String> verified;

  /// The formats whose golden shows a defect of Asciidoctor's that ptome
  /// doesn't reproduce, with what it is: they aren't compared.
  final Map<Format, String> defects;

  String get input => p.posix.join(dir, 'input.adoc');

  /// Converts the case to [format] with ptome as the command line does
  /// (`-b <format> -D <dir> input.adoc`), with [attributes] under the
  /// case's own; the file written.
  Future<Uint8List> convert(
    Format format,
    Map<String, String> attributes,
  ) async {
    // (Inside the case: a safe mode keeps the output there.)
    final scratch = p.posix.join(dir, '.ptome');
    final out = p.posix.join(scratch, format.name);
    try {
      final document = await Ptome(safe: safe).convertFile(
        input,
        toDir: out,
        mkdirs: true,
        backend: format.backend,
        doctype: doctype,
        attributes: {...attributes, ...this.attributes},
      );
      final written = [
        if (io.isDirectory(out))
          for (final entry in io.listDirectory(out))
            if (entry.isFile && !entry.name.endsWith('.css')) entry.path,
      ];
      if (written.length != 1) {
        throw StateError(
          'ptome wrote ${written.length} files: '
          '${document.diagnostics.map((d) => d.message).join('; ')}',
        );
      }
      return Uint8List.fromList(io.readBytes(written.single));
    } finally {
      deleteTree(scratch);
    }
  }

  /// Records [hash] as the last ptome file of [format] found equal to the
  /// golden of [release] (`ptome.yml`).
  void promote(String release, Format format, String hash) {
    verified[format] = hash;
    io.writeString(
      p.posix.join(dir, 'ptome.yml'),
      '# The last ptome files found equal to the goldens (by their pages,\n'
      '# or the files in them), by SHA-256; written by the corpus test.\n'
      '$release:\n'
      '${[for (final f in Format.values)
        if (verified[f] case final h?) '  ${f.name}: $h\n'].join()}',
    );
  }
}

/// The corpus, with every PDF and EPUB set in the vendored fonts only (never
/// the machine's).
Corpus loadCorpus() {
  Fonts.installed = FontIndex([
    for (final dir in vendoredFontDirectories)
      p.posix.join(io.currentDirectory, dir),
  ]);
  final settings = _yaml(p.posix.join(corpusRoot, 'goldens.yml'));
  final release = settings['release']! as String;
  final cases = <Case>[];
  for (final entry in io.listDirectory(
    corpusRoot,
  )..sort((a, b) => a.name.compareTo(b.name))) {
    final dir = p.posix.join(corpusRoot, entry.name);
    if (!entry.isDirectory || !io.isFile(p.posix.join(dir, 'input.adoc'))) {
      continue;
    }
    final meta = io.isFile(p.posix.join(dir, 'case.yml'))
        ? _yaml(p.posix.join(dir, 'case.yml'))
        : const <String, Object?>{};
    final goldens = <Format, String>{};
    final expected = p.posix.join(dir, 'expected', release);
    if (io.isDirectory(expected)) {
      for (final format in io.listDirectory(expected)) {
        final files = io.listDirectory(format.path).where((e) => e.isFile);
        if (files.isNotEmpty) {
          goldens[Format.values.byName(format.name)] = files.first.path;
        }
      }
    }
    final ptome = io.isFile(p.posix.join(dir, 'ptome.yml'))
        ? _yaml(p.posix.join(dir, 'ptome.yml'))
        : const <String, Object?>{};
    cases.add(
      Case._(
        name: entry.name,
        dir: dir,
        safe: SafeMode.values.byName(meta['safe'] as String? ?? 'unsafe'),
        doctype: switch (meta['doctype']) {
          final String name => Doctype.values.byName(name),
          _ => null,
        },
        attributes: _attributes(meta['attributes']),
        goldens: goldens,
        verified: {
          for (final MapEntry(:key, :value) in _map(ptome[release]).entries)
            Format.values.byName(key): '$value',
        },
        defects: {
          for (final MapEntry(:key, :value) in _map(meta['defects']).entries)
            Format.values.byName(key): '$value',
        },
      ),
    );
  }
  return Corpus._(release, _attributes(settings['attributes']), cases);
}

Map<String, Object?> _yaml(String path) =>
    _map(loadYaml(utf8.decode(io.readBytes(path))));

Map<String, Object?> _map(Object? value) => {
  if (value case final Map<Object?, Object?> map)
    for (final MapEntry(:key, :value) in map.entries) '$key': value,
};

/// Attributes as given to the command line: `false` unsets.
Map<String, String> _attributes(Object? value) => {
  for (final MapEntry(:key, :value) in _map(value).entries)
    if (value == false) '$key!': '' else key: '$value',
};

final _generator = RegExp(
  r'(<meta name="generator" content=")[^"]*(")|^(\.\\" Generator: ).*$',
  multiLine: true,
);

/// [text] with the generator's name and version left out (the only part of
/// a file that says what wrote it).
String withoutGenerator(String text) => text.replaceAllMapped(
  _generator,
  (m) => m[3] != null ? '${m[3]}GENERATOR' : '${m[1]}GENERATOR${m[2]}',
);

/// The SHA-256 of [bytes], in hex.
String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

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

/// Where page images and unpacked EPUBs are kept, by their file's hash.
final String _scratch = p.posix.join(
  io.currentDirectory,
  '.dart_tool',
  'corpus',
);

/// How the pages of [pdf] compare with those of [golden]: `identical`, or
/// where they first differ; null without `pdftoppm`.
String? comparePages(List<int> golden, List<int> pdf) {
  final a = _pages(golden);
  final b = _pages(pdf);
  if (a == null || b == null) return null;
  if (a.length != b.length) return 'pages: ${b.length}, not ${a.length}';
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return 'page ${i + 1}: another size';
    var differ = 0;
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) differ++;
    }
    if (differ > 0) {
      final share = (differ / a[i].length * 100).toStringAsFixed(3);
      return 'page ${i + 1}: $share% of its pixels';
    }
  }
  return 'identical';
}

/// The gray page images of [pdf] at 50 dpi (`pdftoppm -gray`), made once.
List<List<int>>? _pages(List<int> pdf) {
  final dir = p.posix.join(_scratch, 'pages', sha256Of(pdf));
  if (!io.isFile(p.posix.join(dir, 'done'))) {
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
    io.writeString(p.posix.join(dir, 'done'), '');
  }
  int number(String name) =>
      int.parse(RegExp(r'(\d+)\.pgm$').firstMatch(name)![1]!);
  final pages = [
    for (final entry in io.listDirectory(dir))
      if (entry.name.endsWith('.pgm')) entry.name,
  ]..sort((a, b) => number(a).compareTo(number(b)));
  return [for (final page in pages) io.readBytes(p.posix.join(dir, page))];
}

/// How the files in [epub] compare with those in [golden]: `identical` (the
/// same names and bytes, generator stamps aside), or the first that
/// differs; null without `unzip`.
String? compareEntries(List<int> golden, List<int> epub) {
  final a = _entries(golden);
  final b = _entries(epub);
  if (a == null || b == null) return null;
  final names = {...a.keys, ...b.keys}.toList()..sort();
  for (final name in names) {
    final (x, y) = (a[name], b[name]);
    if (x == null) return '$name: not in the golden';
    if (y == null) return '$name: missing';
    final (want, got) = (_entryText(name, x), _entryText(name, y));
    if (want == got) continue;
    return _isText(name)
        ? '$name: ${firstDifference(want, got)}'
        : '$name: other bytes';
  }
  return 'identical';
}

bool _isText(String name) =>
    name.endsWith('.xhtml') ||
    name.endsWith('.opf') ||
    name.endsWith('.ncx') ||
    name.endsWith('.css') ||
    name.endsWith('.xml');

String _entryText(String name, List<int> bytes) => _isText(name)
    ? withoutGenerator(utf8.decode(bytes, allowMalformed: true))
    : base64.encode(bytes);

/// The files in [epub], by their paths, unpacked once (`unzip`).
Map<String, List<int>>? _entries(List<int> epub) {
  final hash = sha256Of(epub);
  final dir = p.posix.join(_scratch, 'epubs', hash);
  if (!io.isFile(p.posix.join(dir, '.done'))) {
    io.createDirectories(dir);
    final file = p.posix.join(_scratch, 'epubs', '$hash.epub');
    io.writeBytes(file, epub);
    final unpacked = io.commandOutput('unzip', ['-q', '-o', file, '-d', dir]);
    if (unpacked == null) return null;
    io.writeString(p.posix.join(dir, '.done'), '');
  }
  final entries = <String, List<int>>{};
  void walk(String path, String prefix) {
    for (final entry in io.listDirectory(path)) {
      final name = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isDirectory) {
        walk(entry.path, name);
      } else if (name != '.done') {
        entries[name] = io.readBytes(entry.path);
      }
    }
  }

  walk(dir, '');
  return entries;
}
