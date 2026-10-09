/// The black-box corpus: every case converts with ptome to the result
/// recorded for the ptome profile (test/corpus, built by
/// packages/ptome_corpus_tools).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/corpus.dart';

void main() {
  for (final c in loadCases()) {
    group(c.id, () {
      for (final format in c.formats) {
        final expected = c.expected[format];
        test(
          format.name,
          skip:
              c.knownIssues[format] ??
              (expected == null ? 'no ptome result recorded' : null),
          () {
            final (:result, :output) = c.convert(format);
            if (result.matches(expected!)) return;
            fail(_explain(c, format, expected, result, output));
          },
        );
      }
    });
  }
}

String _explain(
  Case c,
  Format format,
  Result expected,
  Result actual,
  Object? output,
) {
  if (expected.error != null || actual.error != null) {
    return 'expected ${expected.error ?? 'output'}, '
        'got ${actual.error ?? 'output'}';
  }
  if (expected.hash != actual.hash) {
    if (output is! String) {
      return 'output ${actual.hash} differs from ${expected.hash}';
    }
    final want = File(c.blobPath(format, expected.hash!)).readAsStringSync();
    return 'output differs at ${firstDifference(want, output)}';
  }
  return 'log differs:\n'
      '  expected ${expected.logLines}\n'
      '  got      ${actual.logLines}';
}
