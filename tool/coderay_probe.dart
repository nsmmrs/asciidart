// Differential probe: runs the Dart CodeRay stack over JSON cases from
// stdin and prints JSON outputs. Case schema:
// {source, language, cssMode: class|style, numberLines: null|table|inline,
//  startLineNumber, highlightLines: [int], hasCallouts: bool}
// Output: [{ok, html} | {ok, error}] per case.
import 'dart:convert';
import 'dart:io';

import 'package:asciidoctor/src/highlight/coderay.dart';
import 'package:asciidoctor/src/highlight/coderay_lexer.dart';
import 'package:asciidoctor/src/highlight/highlight.dart';

Future<void> main() async {
  final input = await stdin.transform(utf8.decoder).join();
  final cases = jsonDecode(input) as List;
  final results = <Map<String, Object?>>[];
  for (final c in cases) {
    final m = (c as Map).cast<String, Object?>();
    try {
      final adapter = CodeRayAdapter(lexer: const CodeRaySourceLexer());
      final numberLines = m['numberLines'] as String?;
      final result = adapter.highlight(
        source: m['source']! as String,
        language: m['language'] as String?,
        cssMode: m['cssMode'] == 'style' ? CssMode.inline : CssMode.classes,
        numberLines: numberLines == null
            ? null
            : numberLines == 'table'
            ? LineNumbersMode.table
            : LineNumbersMode.inline,
        startLineNumber: (m['startLineNumber'] as num?)?.toInt() ?? 1,
        highlightLines: ((m['highlightLines'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        hasCallouts: m['hasCallouts'] == true,
      );
      results.add({'ok': true, 'html': result.html});
    } catch (e) {
      results.add({
        'ok': false,
        'error': '${e.runtimeType}: $e'.split('\n').first,
      });
    }
  }
  stdout.write(jsonEncode(results));
}
