/// Compares EPUB files the asciidart CLI writes with those of the
/// asciidoctor-epub3 gem, file by file.
///
/// Usage:
///
/// ```sh
/// dart run tool/epub_parity.dart --exe-a GEM --exe-b ASCIIDART DOC.adoc...
/// dart run tool/epub_parity.dart A.epub B.epub
/// ```
///
/// Each document is converted by both executables (`-b epub3`, with the
/// `reproducible` attribute, `TZ=UTC`); the two EPUBs must have the same
/// entries in the same order, `mimetype` first and stored, and the same
/// bytes in every entry once the dates that change with every run
/// (`dcterms:modified`, `dc:date`) are normalized. The ZIP compression
/// itself is not compared (zlib versions differ). The messages (stderr)
/// must match too, the program name and intentional rewordings aside.
///
/// With `--epubcheck EPUBCHECK.jar`, both EPUBs are also validated, and
/// EPUBCheck must report the same messages for both (asciidart adds no
/// error of its own; the fixtures have some on purpose).
///
/// Exits 1 when any pair differs; the differences are written to stdout.
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidart/src/epub3/zip.dart';

import 'corpus_parity.dart' show rewordings;

final RegExp _volatile = RegExp(
  '<meta property="dcterms:modified">[^<]*</meta>|<dc:date>[^<]*</dc:date>',
);

void main(List<String> args) {
  String? exeA;
  String? exeB;
  String? epubcheck;
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--exe-a':
        exeA = args[++i];
      case '--exe-b':
        exeB = args[++i];
      case '--epubcheck':
        epubcheck = args[++i];
      default:
        rest.add(args[i]);
    }
  }
  var failures = 0;
  if (exeA == null || exeB == null) {
    if (rest.length != 2) {
      stderr.writeln('usage: epub_parity.dart A.epub B.epub');
      exit(2);
    }
    failures += _compare(rest[0], rest[1]) ? 0 : 1;
  } else {
    final tmp = Directory.systemTemp.createTempSync('epub_parity.');
    try {
      for (final doc in rest) {
        final a = _convert(exeA, doc, '${tmp.path}/a');
        final b = _convert(exeB, doc, '${tmp.path}/b');
        if (a.epub == null || b.epub == null) {
          if (a.epub == null && b.epub == null) continue; // both refuse
          stdout.writeln('FAIL $doc: conversion failed on one side');
          failures += 1;
          continue;
        }
        var same = _compare(a.epub!, b.epub!, label: doc);
        if (epubcheck != null) {
          final checkA = _epubcheck(epubcheck, a.epub!);
          final checkB = _epubcheck(epubcheck, b.epub!);
          if (checkA != checkB) {
            if (same) stdout.writeln('FAIL $doc');
            stdout.writeln(
              '  EPUBCheck reports differ:\n    A: $checkA\n    B: $checkB',
            );
            same = false;
          }
        }
        if (a.messages != b.messages) {
          if (same) stdout.writeln('FAIL $doc');
          stdout.writeln(
            '  messages differ:\n    A: ${a.messages}\n    B: ${b.messages}',
          );
          same = false;
        }
        failures += same ? 0 : 1;
      }
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }
  stdout.writeln(
    failures == 0
        ? 'epub_parity: all identical'
        : 'epub_parity: $failures differ',
  );
  exit(failures == 0 ? 0 : 1);
}

/// What EPUBCheck reports for [epub]: its messages, without the file
/// names.
String _epubcheck(String jar, String epub) {
  final result = Process.runSync('java', ['-jar', jar, '-q', epub]);
  final name = RegExp.escape(epub.split('/').last);
  return [
    for (final line in '${result.stdout}${result.stderr}'.split('\n'))
      if (RegExp('^(?:ERROR|FATAL|WARNING)').hasMatch(line))
        line.replaceAll(RegExp('$name/?'), ''),
  ].join('\n');
}

/// Converts [doc] with [exe] into [outDir]: the EPUB written (or `null`)
/// and the messages, with the program name and output directory left out.
({String? epub, String messages}) _convert(
  String exe,
  String doc,
  String outDir,
) {
  Directory(outDir).createSync(recursive: true);
  final name = doc.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
  final out = '$outDir/$name.epub';
  final file = File(out);
  if (file.existsSync()) file.deleteSync();
  final result = Process.runSync(
    exe,
    ['-b', 'epub3', '-a', 'reproducible', '-o', out, doc],
    environment: {'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'},
    workingDirectory: File(doc).parent.path,
  );
  final messages = (result.stderr as String)
      .replaceAll(RegExp('^asciid(?:octor|art): ', multiLine: true), '')
      .replaceAll(outDir, '<out>')
      .trim();
  var canonical = messages;
  for (final (pattern, replacement) in rewordings) {
    canonical = canonical.replaceAllMapped(
      pattern,
      (m) => replacement.replaceAllMapped(
        RegExp(r'\$(\d)'),
        (g) => m[int.parse(g[1]!)] ?? '',
      ),
    );
  }
  return (
    epub: result.exitCode == 0 && file.existsSync() ? out : null,
    messages: canonical,
  );
}

bool _compare(String pathA, String pathB, {String? label}) {
  final name = label ?? pathB;
  List<({String name, int method, List<int> bytes})> entries(String path) =>
      readZip(
        File(path).readAsBytesSync(),
        (bytes) => ZLibCodec(raw: true).decode(bytes),
      );
  final a = entries(pathA);
  final b = entries(pathB);
  final problems = <String>[];
  if (b.isEmpty || b.first.name != 'mimetype' || b.first.method != 0) {
    problems.add('mimetype is not the first entry, stored');
  }
  final namesA = [for (final e in a) e.name];
  final namesB = [for (final e in b) e.name];
  if (namesA.join('\n') != namesB.join('\n')) {
    final onlyA = namesA.where((n) => !namesB.contains(n)).toList();
    final onlyB = namesB.where((n) => !namesA.contains(n)).toList();
    final reordered = onlyA.isEmpty && onlyB.isEmpty
        ? '\n  (same entries, different order)'
        : '';
    problems.add(
      'entries differ:\n  only in A: $onlyA\n  only in B: $onlyB$reordered',
    );
  }
  final byName = {for (final e in b) e.name: e.bytes};
  for (final entry in a) {
    final other = byName[entry.name];
    if (other == null) continue;
    if (_same(entry.bytes, other)) continue;
    final textA = _normalize(entry.bytes);
    final textB = _normalize(other);
    if (textA != null && textA == textB) continue;
    problems.add('${entry.name} differs${_firstDifference(textA, textB)}');
  }
  if (problems.isEmpty) return true;
  stdout.writeln('FAIL $name');
  for (final problem in problems) {
    stdout.writeln('  $problem');
  }
  return false;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String? _normalize(List<int> bytes) {
  try {
    return utf8.decode(bytes).replaceAll(_volatile, '<volatile/>');
  } on FormatException {
    return null;
  }
}

String _firstDifference(String? a, String? b) {
  if (a == null || b == null) return ' (binary)';
  final linesA = a.split('\n');
  final linesB = b.split('\n');
  for (var i = 0; i < linesA.length || i < linesB.length; i++) {
    final x = i < linesA.length ? linesA[i] : '<end>';
    final y = i < linesB.length ? linesB[i] : '<end>';
    if (x != y) {
      return ' at line ${i + 1}:\n    A: ${_clip(x)}\n    B: ${_clip(y)}';
    }
  }
  return '';
}

String _clip(String line) =>
    line.length > 200 ? '${line.substring(0, 200)}...' : line;
