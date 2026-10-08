// In-process throughput benchmark: steady-state conversion time of a large
// document, excluding process startup (which `bench-exe.rb` measures).
//
// The corpus is built deterministically from in-repo samples (mdbasics,
// the syntax reference and the sample fixture), repeated --copies times;
// with --file, a document read from a file (its includes too, unsafe), such
// as the Hypermedia Systems book that tool/hs_acceptance.dart clones
// (~/.cache/asciidart-work/hs-old/HypermediaSystems.adoc, benchmark/HS.md).
//
// Usage (from the package folder):
//   dart run benchmark/throughput.dart [--copies 20] [--iterations 15]
//   dart compile exe benchmark/throughput.dart -o /tmp/throughput && \
//     /tmp/throughput
//   dart run benchmark/throughput.dart --write-corpus /tmp/large.adoc
//   dart run benchmark/throughput.dart --file PATH/TO/book.adoc
//   dart run benchmark/throughput.dart --two-byte
//
// --two-byte times the corpus with its apostrophes curly (’) and a verse
// mark (`@ `) before each line of prose, as in loci's Bible dialect: text
// outside Latin-1 takes the VM's slower two-byte paths, which the plain
// corpus never reaches (the e-mail pass once cost the KJV 12 s this way).
//
// Every backend is warmed up before any is timed: the first one timed in
// a cold heap ran about 2x slower from heap growth alone. Diagnostics (the
// corpus repeats ids) are dropped, so that only conversion is timed.
import 'dart:io';

import 'package:args/args.dart';
import 'package:ptome/src/internal.dart' as asciidoctor;

const _sources = [
  'vendor/asciidoctor/benchmark/sample-data/mdbasics.adoc',
  'vendor/asciidoctor/data/reference/syntax.adoc',
  'vendor/asciidoctor/test/fixtures/sample.adoc',
];

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('copies', defaultsTo: '20', help: 'Corpus repetitions.')
    ..addOption('iterations', defaultsTo: '15', help: 'Timed iterations.')
    ..addOption('warmup', defaultsTo: '5', help: 'Untimed iterations.')
    ..addMultiOption(
      'backend',
      defaultsTo: ['html5', 'docbook5', 'manpage'],
      help: 'Backends to time.',
    )
    ..addFlag(
      'two-byte',
      negatable: false,
      help: 'Curly apostrophes and verse marks in the corpus.',
    )
    ..addOption('write-corpus', help: 'Write the corpus to a file and exit.')
    ..addOption('file', help: 'Time this document instead of the corpus.');
  final options = parser.parse(args);
  final file = options['file'] as String?;
  final base = _sources.map((p) => File(p).readAsStringSync()).join('\n\n');
  final copies = int.parse(options['copies'] as String);
  final plain = List.filled(copies, base).join('\n\n');
  final corpus = options['two-byte'] as bool ? _twoByte(plain) : plain;
  final corpusPath = options['write-corpus'] as String?;
  if (corpusPath != null) {
    File(corpusPath).writeAsStringSync(corpus);
    return;
  }
  final iterations = int.parse(options['iterations'] as String);
  final warmup = int.parse(options['warmup'] as String);
  stdout.writeln(
    file == null ? 'corpus: ${corpus.length} chars' : 'document: $file',
  );
  final backends = options['backend'] as List<String>;
  asciidoctor.Document Function() loader(String backend) {
    final convertOptions = file == null
        ? asciidoctor.AsciidoctorOptions(
            safe: asciidoctor.SafeMode.safe,
            backend: backend,
            doctype: 'book',
            standalone: true,
            logger: asciidoctor.NullLogger(),
          )
        : asciidoctor.AsciidoctorOptions(
            safe: asciidoctor.SafeMode.unsafe,
            backend: backend,
            standalone: true,
            logger: asciidoctor.NullLogger(),
          );
    return () => file == null
        ? asciidoctor.load(corpus, options: convertOptions)
        : asciidoctor.loadFile(file, options: convertOptions);
  }

  for (final backend in backends) {
    final load = loader(backend);
    for (var i = 0; i < warmup; i++) {
      load().convert();
    }
  }
  for (final backend in backends) {
    final load = loader(backend);
    final loads = <int>[];
    final totals = <int>[];
    for (var i = 0; i < iterations; i++) {
      final watch = Stopwatch()..start();
      final doc = load();
      loads.add(watch.elapsedMicroseconds);
      doc.convert();
      totals.add(watch.elapsedMicroseconds);
    }
    stdout.writeln(
      '${backend.padRight(8)} total ${_median(totals)} ms  '
      'load ${_median(loads)} ms  (median of $iterations)',
    );
  }
}

String _median(List<int> micros) {
  final sorted = [...micros]..sort();
  return (sorted[sorted.length ~/ 2] / 1000).toStringAsFixed(1);
}

/// [corpus] with its apostrophes curly and `@ ` before each line that
/// starts with a letter (prose, not markup).
String _twoByte(String corpus) => corpus
    .replaceAll("'", '\u2019')
    .replaceAllMapped(RegExp('^(?=[A-Za-z])', multiLine: true), (_) => '@ ');
