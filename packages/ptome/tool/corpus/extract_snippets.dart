/// Extracts the AsciiDoc snippets embedded in Asciidoctor's Ruby tests
/// (squiggly heredocs) into standalone files for the corpus parity check.
///
/// ```sh
/// dart run tool/corpus/extract_snippets.dart ASCIIDOCTOR_CHECKOUT/test
/// ```
///
/// Each `<<~'EOS'` heredoc, and each `<<~EOS` heredoc without
/// interpolation or escapes, becomes `snippet-<test>-<line>.adoc` in the
/// test directory itself, so includes of `fixtures/...` resolve as they do
/// in the Ruby tests. Existing snippet files are replaced.
library;

import 'dart:io';

final RegExp _opener = RegExp(r"<<~('?)([A-Z_]+)\1");

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: extract_snippets.dart ASCIIDOCTOR_TEST_DIR');
    exitCode = 2;
    return;
  }
  final dir = Directory(args.single);
  for (final old in dir.listSync()) {
    if (old is File && old.uri.pathSegments.last.startsWith('snippet-')) {
      old.deleteSync();
    }
  }
  var count = 0;
  final tests = dir.listSync().whereType<File>().where(
    (file) => file.path.endsWith('_test.rb'),
  );
  for (final test in tests) {
    final name = test.uri.pathSegments.last.replaceAll('_test.rb', '');
    final lines = test.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = _opener.firstMatch(lines[i]);
      if (match == null) continue;
      final quoted = match[1]!.isNotEmpty;
      final terminator = match[2]!;
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length && lines[j].trim() != terminator) {
        body.add(lines[j]);
        j++;
      }
      if (j == lines.length) continue;
      final text = body.join('\n');
      if (!quoted && (text.contains('#{') || text.contains(r'\'))) continue;
      if (body.every((line) => line.trim().isEmpty)) continue;
      File('${dir.path}/snippet-$name-${i + 1}.adoc')
          .writeAsStringSync('${_dedent(body).join('\n')}\n');
      count++;
      i = j;
    }
  }
  stdout.writeln('extracted $count snippets into ${dir.path}');
}

/// Removes the common leading whitespace of [lines], as a squiggly heredoc
/// does (blank lines do not count toward it).
List<String> _dedent(List<String> lines) {
  var indent = -1;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final width = line.length - line.trimLeft().length;
    if (indent == -1 || width < indent) indent = width;
  }
  if (indent <= 0) return lines;
  return [
    for (final line in lines)
      if (line.length >= indent) line.substring(indent) else line.trimLeft(),
  ];
}
