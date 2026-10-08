/// Times hilite over the source blocks of a differential file
/// (`tool/generate/differential.mjs`): the first pass (which compiles each
/// language on first use) and the best of five warm passes.
///
/// Usage: dart run benchmark/throughput.dart FILE
library;

import 'dart:convert';
import 'dart:io';

import 'package:hilite/hilite.dart';

void main(List<String> args) {
  final blocks = [
    for (final line in File(args.single).readAsLinesSync())
      if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];
  var chars = 0;
  for (final b in blocks) {
    chars += (b['code']! as String).length;
  }
  int pass() {
    final sw = Stopwatch()..start();
    for (final b in blocks) {
      hilite.highlight(
        b['code']! as String,
        language: b['language']! as String,
      );
    }
    return sw.elapsedMilliseconds;
  }

  final cold = pass();
  final warm = [for (var i = 0; i < 5; i++) pass()]..sort();
  stdout.writeln(
    'hilite: ${blocks.length} blocks, ${(chars / 1024).round()} KiB: '
    'first pass $cold ms, warm ${warm.first} ms',
  );
}
