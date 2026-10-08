/// Compares plain_highlighting with highlight.js on real code: reads the JSON
/// Lines file written by `tool/generate/differential.mjs` and highlights each
/// block again, reporting every difference in HTML, relevance or detected
/// language.
///
/// Usage: dart run tool/differential.dart FILE
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_highlighting/plain_highlighting.dart';

void main(List<String> args) {
  var same = 0;
  var differ = 0;
  for (final line in File(args.single).readAsLinesSync()) {
    if (line.isEmpty) continue;
    final entry = jsonDecode(line) as Map<String, Object?>;
    final code = entry['code']! as String;
    final language = entry['language']! as String;
    final r = highlighting.highlight(code, language: language);
    final problems = [
      if (r.html != entry['html']) 'html',
      if (r.relevance != entry['relevance']) 'relevance',
      if (r.illegal != entry['illegal']) 'illegal',
    ];
    final auto = entry['auto'] as Map<String, Object?>?;
    if (auto != null) {
      final a = highlighting.highlightAuto(code);
      if (a.language != auto['language']) {
        problems.add('auto ${auto['language']} -> ${a.language}');
      } else if (a.html != auto['html'] || a.relevance != auto['relevance']) {
        problems.add('auto output');
      }
    }
    if (problems.isEmpty) {
      same++;
    } else {
      differ++;
      stdout.writeln(
        '$language: ${problems.join(', ')}: '
                '${code.length > 60 ? '${code.substring(0, 60)}...' : code}'
            .replaceAll('\n', r'\n'),
      );
    }
  }
  stdout.writeln('differential: $same same, $differ different');
  if (differ > 0) exitCode = 1;
}
