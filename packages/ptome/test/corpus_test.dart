/// The corpus (test/corpus): every case converts with ptome, with
/// `asciidoctor-compat`, to the files the Asciidoctor command line writes
/// for it. Text formats match the golden file's bytes (its generator
/// stamp aside); a PDF matches its pages, pixel for pixel, an EPUB the
/// files in it, and the last ptome file found equal is kept by its hash
/// (ptome.yml), so an unchanged one isn't compared again.
@Tags(['corpus'])
library;

import 'dart:convert';

import 'package:ptome/ptome.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:test/test.dart';

import 'support/corpus.dart';

void main() {
  final corpus = loadCorpus();
  final attributes = {...corpus.attributes, 'asciidoctor-compat': 'true'};

  // On JavaScript the PDF and EPUB backends are loaded on demand.
  setUpAll(() async {
    for (final format in [Format.pdf, Format.epub3]) {
      await const Ptome().loadBackend(format.backend);
    }
  });

  for (final c in corpus.cases) {
    group(c.name, () {
      for (final MapEntry(key: format, value: golden) in c.goldens.entries) {
        test(
          format.name,
          skip: format.expensive && _onJs
              ? 'compared by its pages or files on the Dart VM'
              : null,
          () async {
            final want = io.readBytes(golden);
            final got = await c.convert(format, attributes);
            if (!format.expensive) {
              final (a, b) = (_text(want), _text(got));
              if (sha256Of(utf8.encode(a)) == sha256Of(utf8.encode(b))) {
                return;
              }
              fail(
                'differs from ${corpus.release} at ${firstDifference(a, b)}',
              );
            }
            final hash = sha256Of(got);
            if (c.verified[format] == hash) return;
            final result = format == Format.pdf
                ? comparePages(want, got)
                : compareEntries(want, got);
            if (result == null) {
              markTestSkipped(
                format == Format.pdf ? 'needs pdftoppm' : 'needs unzip',
              );
              return;
            }
            if (result != 'identical') {
              fail('differs from ${corpus.release}: $result');
            }
            // Equal: kept by its hash from now on (commit ptome.yml).
            c.promote(corpus.release, format, hash);
          },
        );
      }
    });
  }
}

String _text(List<int> bytes) =>
    withoutGenerator(utf8.decode(bytes, allowMalformed: true));

const _onJs = bool.fromEnvironment('dart.library.js_interop');
