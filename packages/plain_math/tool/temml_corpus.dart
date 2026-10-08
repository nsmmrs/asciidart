/// Writes `test/fixtures/temml/expressions.json` from Temml's screen test
/// pages (`test/katex-tests.md`, `test/mozilla-tests.md` and
/// `test/LaTeXML-tests.md` in a Temml checkout, given as the argument):
/// the LaTeX of each table's Temml column (whichever has math in it):
/// `$...$`, or `$$...$$` for display math, by page and section.
///
/// ```sh
/// dart run tool/temml_corpus.dart path/to/temml/test
/// ```
library;

import 'dart:convert';
import 'dart:io';

/// A table's cell border: a `|` with space (or the line's end) on both
/// sides (one in LaTeX, as in `\left|`, has none before it).
final RegExp _cellBorder = RegExp(r'(?<=^|\s)\|(?=\s|$)');

const List<String> _pages = [
  'katex-tests.md',
  'mozilla-tests.md',
  'LaTeXML-tests.md',
];

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/temml_corpus.dart <temml/test>');
    exitCode = 64;
    return;
  }
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final expressions = <Map<String, Object>>[];
  for (final page in _pages) {
    var section = '';
    final table = <List<String>>[];
    void flush() {
      // The Temml column is the one with math in it; its text, joined
      // across the table's rows, holds whole expressions (one may span
      // rows).
      final column = [
        for (final row in table)
          for (final (i, cell) in row.indexed)
            if (cell.contains(r'$')) i,
      ].firstOrNull;
      if (column != null) {
        final text = [
          for (final row in table)
            if (column < row.length) row[column],
        ].join(' ');
        for (final (tex, display) in _math(text)) {
          expressions.add({
            'page': page,
            'section': section,
            'tex': tex,
            'display': display,
          });
        }
      }
      table.clear();
    }

    for (final line in File('${args.single}/$page').readAsLinesSync()) {
      if (line.startsWith('|')) {
        table.add([
          for (final cell in line.split(_cellBorder).skip(1)) cell.trim(),
        ]);
      } else if (!line.startsWith('+')) {
        flush();
        if (line.startsWith('#')) {
          section = line.replaceFirst(RegExp('^#+ *'), '');
        }
      }
    }
    flush();
  }
  const path = 'test/fixtures/temml/expressions.json';
  File('$root/$path').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(expressions)}\n',
  );
  stdout.writeln('temml_corpus: ${expressions.length} expressions in $path');
}

/// The math in [text]: `$...$` and `$$...$$` (display), where a `$` in
/// braces (text mode's own math, as in `\text{for $a$}`) or after a
/// backslash belongs to the math around it.
Iterable<(String, bool)> _math(String text) sync* {
  var i = 0;
  while ((i = text.indexOf(r'$', i)) >= 0) {
    final display = text.startsWith(r'$$', i);
    final start = i + (display ? 2 : 1);
    var depth = 0;
    var end = -1;
    for (var j = start; j < text.length; j++) {
      final c = text[j];
      if (c == r'\') {
        j++;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      } else if (c == r'$' && depth == 0) {
        end = j;
        break;
      }
    }
    if (end < 0) return;
    yield (text.substring(start, end).trim(), display);
    i = end + (display ? 2 : 1);
  }
}
