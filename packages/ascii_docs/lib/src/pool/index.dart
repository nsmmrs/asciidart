/// Lists the pool's documents: every file a source's `documents` globs
/// match, and every heredoc in the Ruby files its `heredocs` globs match.
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'entry.dart';
import 'source.dart';

/// The entries of [source] (which must be fetched).
List<PoolEntry> indexSource(PoolSource source) {
  final root = source.checkout;
  final entries = <PoolEntry>[];
  List<File> matching(List<String> globs) {
    final files = <String, File>{};
    for (final pattern in globs) {
      for (final entity in Glob(
        pattern,
      ).listSync(root: root, followLinks: false)) {
        if (entity is File &&
            !entity.path.contains('${p.separator}.git${p.separator}')) {
          files[entity.path] = File(entity.path);
        }
      }
    }
    return files.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  }

  for (final file in matching(source.documents)) {
    entries.add(
      PoolEntry(
        id: '${source.name}/${p.relative(file.path, from: root)}',
        source: source.name,
        baseDir: p.dirname(file.path),
        path: file.path,
        // Whole documents convert as pages, with the stylesheet linked
        // rather than embedded (it changes between versions).
        standalone: true,
        attributes: const {'linkcss': '@'},
      ),
    );
  }
  for (final file in matching(source.heredocs)) {
    final rel = p.relative(file.path, from: root);
    for (final (line, text) in heredocs(file.readAsStringSync())) {
      entries.add(
        PoolEntry(
          id: '${source.name}/$rel:$line',
          source: source.name,
          baseDir: p.dirname(file.path),
          text: text,
        ),
      );
    }
  }
  return entries;
}

final _opener = RegExp(r"""<<~(['"]?)([A-Z_][A-Z0-9_]*)\1""");

/// The squiggly heredocs of a Ruby [source], with the line each starts on:
/// quoted ones, and unquoted ones without interpolation or escapes (whose
/// text is then exactly what Ruby would make of them).
List<(int, String)> heredocs(String source) {
  final lines = source.split('\n');
  final found = <(int, String)>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _opener.firstMatch(lines[i]);
    if (match == null) continue;
    final quote = match[1]!;
    final terminator = match[2]!;
    final body = <String>[];
    var j = i + 1;
    while (j < lines.length && lines[j].trim() != terminator) {
      body.add(lines[j]);
      j++;
    }
    if (j == lines.length) continue;
    final text = _dedent(body);
    if (quote != "'" && (text.contains('#{') || text.contains(r'\'))) continue;
    found.add((i + 1, text.isEmpty ? '' : '$text\n'));
    i = j;
  }
  return found;
}

/// Strips the indentation the least indented non-blank line has, as Ruby's
/// `<<~` does.
String _dedent(List<String> lines) {
  var indent = -1;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final n = line.length - line.trimLeft().length;
    if (indent < 0 || n < indent) indent = n;
  }
  if (indent < 0) indent = 0;
  return [
    for (final line in lines)
      line.length >= indent ? line.substring(indent) : line.trimLeft(),
  ].join('\n');
}
