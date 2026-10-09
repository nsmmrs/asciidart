/// The black-box corpus: every case converts with ptome to the result
/// recorded for the ptome profile (test/corpus, built by
/// packages/ptome_corpus_tools).
library;

import 'dart:convert';

import 'package:ptome/ptome.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:test/test.dart';

import 'support/corpus.dart';

void main() {
  // On JavaScript the PDF and EPUB backends are loaded on demand.
  setUpAll(() async {
    for (final format in [Format.pdf, Format.epub3]) {
      await const Ptome().loadBackend(format.backend);
    }
  });

  for (final c in loadCases()) {
    group(c.id, () {
      for (final format in c.formats) {
        final expected = c.expected[format];
        test(
          format.name,
          skip:
              c.knownIssues[format] ??
              (format == Format.pdf && _onJs
                  ? 'PDF bytes depend on the platform (compression)'
                  : null) ??
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

const _onJs = bool.fromEnvironment('dart.library.js_interop');

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
    final want = utf8.decode(io.readBytes(c.blobPath(format, expected.hash!)));
    return 'output differs at ${firstDifference(want, output)}';
  }
  return 'log differs:\n'
      '  expected ${expected.logLines}\n'
      '  got      ${actual.logLines}';
}
