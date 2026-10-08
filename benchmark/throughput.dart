// In-process throughput benchmark: steady-state conversion time of a large
// document, excluding process startup (which `bench-exe.rb` measures).
//
// The corpus is built deterministically from in-repo samples (mdbasics,
// the syntax reference and the sample fixture), repeated --copies times.
//
// Usage (from the repo root):
//   dart run benchmark/throughput.dart [--copies 20] [--iterations 15]
//   dart compile exe benchmark/throughput.dart -o /tmp/throughput && \
//     /tmp/throughput
//   dart run benchmark/throughput.dart --write-corpus /tmp/large.adoc
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
    ..addOption('write-corpus', help: 'Write the corpus to a file and exit.');
  final options = parser.parse(args);
  final base = _sources.map((p) => File(p).readAsStringSync()).join('\n\n');
  final copies = int.parse(options['copies'] as String);
  final corpus = List.filled(copies, base).join('\n\n');
  final corpusPath = options['write-corpus'] as String?;
  if (corpusPath != null) {
    File(corpusPath).writeAsStringSync(corpus);
    return;
  }
  final iterations = int.parse(options['iterations'] as String);
  final warmup = int.parse(options['warmup'] as String);
  stdout.writeln('corpus: ${corpus.length} chars');
  for (final backend in options['backend'] as List<String>) {
    final convertOptions = asciidoctor.AsciidoctorOptions(
      safe: asciidoctor.SafeMode.safe,
      backend: backend,
      doctype: 'book',
      standalone: true,
    );
    for (var i = 0; i < warmup; i++) {
      asciidoctor.convert(corpus, convertOptions);
    }
    final loads = <int>[];
    final totals = <int>[];
    for (var i = 0; i < iterations; i++) {
      final watch = Stopwatch()..start();
      final doc = asciidoctor.load(corpus, options: convertOptions);
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
