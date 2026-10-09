import 'dart:io';

import 'package:ptome/io.dart';
import 'package:ptome/ptome.dart';

Future<void> main(List<String> a) async {
  final dir = a[0];
  await const Ptome(safe: SafeMode.unsafe).convertFile(
    '$dir/input.adoc',
    toDir: a[1],
    mkdirs: true,
    backend: Backend.epub3,
    attributes: {
      'asciidoctor-compat': 'true',
      'docdate': '2026-01-01',
      'doctime': '00:00:00 +0000',
      'docdatetime': '2026-01-01 00:00:00 +0000',
      'localdate': '2026-01-01',
      'localtime': '00:00:00 +0000',
      'localdatetime': '2026-01-01 00:00:00 +0000',
      'docyear': '2026',
      'localyear': '2026',
    },
  );
  stdout.writeln('ok');
}
