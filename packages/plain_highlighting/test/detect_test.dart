/// Auto-detection matches highlight.js: for upstream's detection samples
/// and markup inputs, `highlightAuto` picks the same language, with the
/// same relevance and runner-up, as highlight.js 11.12.0
/// (`test/reference/detect.json`, from `tool/generate/reference.mjs`).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:hilite/hilite.dart';
import 'package:test/test.dart';

void main() {
  final reference = (jsonDecode(
    File('test/reference/detect.json').readAsStringSync(),
  ) as Map<String, Object?>).cast<String, Map<String, Object?>>();
  for (final MapEntry(key: path, value: expected) in reference.entries) {
    test(path, () {
      final code = File('vendor/highlight.js/test/$path').readAsStringSync();
      final result = hilite.highlightAuto(code);
      expect(
        (
          language: result.language,
          relevance: result.relevance,
          secondBest: result.secondBest?.language,
        ),
        (
          language: expected['language'],
          relevance: expected['relevance'],
          secondBest: expected['secondBest'],
        ),
      );
    });
  }
}
