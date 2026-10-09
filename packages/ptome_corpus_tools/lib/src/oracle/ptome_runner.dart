/// ptome, converting in-process through its public API.
library;

import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:ptome/ptome.dart';
// The font index is internal to ptome; its tests pin it the same way.
// ignore: implementation_imports
import 'package:ptome/src/font_index.dart';

import '../spec/conversion.dart';

/// The fonts PDFs and EPUBs are set in: only those vendored in ptome's
/// package (as ptome's tests use them), never the machine's, so recorded
/// results are the same on every machine. Keep in step with ptome's
/// `tool/vendored_fonts.dart`.
const _vendoredFontDirectories = [
  'vendor/asciidoctor-pdf/data/fonts',
  'vendor/asciidoctor-pdf/icons',
  'data/pdf-fonts',
  'vendor/asciidoctor-epub3/fonts',
];

final FontIndex _fonts = () {
  final library = Isolate.resolvePackageUriSync(
    Uri.parse('package:ptome/ptome.dart'),
  )!;
  final root = p.dirname(p.dirname(library.toFilePath()));
  return FontIndex([
    for (final dir in _vendoredFontDirectories) p.join(root, dir),
  ]);
}();

/// Converts [conversion] with ptome in the calling isolate.
Outcome convertWithPtome(Conversion conversion) {
  // The recorder is part of ptome's test harness.
  // ignore: invalid_use_of_visible_for_testing_member
  Fonts.installed = _fonts;
  final log = <LogEntry>[];
  final ptome = Ptome(
    safe: switch (conversion.safe) {
      Safe.unsafe => SafeMode.unsafe,
      Safe.safe => SafeMode.safe,
      Safe.server => SafeMode.server,
      Safe.secure => SafeMode.secure,
    },
    baseDir: conversion.baseDir,
    onDiagnostic: (d) =>
        log.add(LogEntry(d.severity.name, d.message, line: d.location?.line)),
  );
  final doctype = switch (conversion.doctype) {
    null => null,
    final name => Doctype.values.byName(name),
  };
  final watch = Stopwatch()..start();
  try {
    final Object output = switch (conversion.format) {
      Format.pdf || Format.epub3 => ptome.convertToBytes(
        conversion.input,
        backend: _backend(conversion.format),
        doctype: doctype,
        attributes: conversion.attributes,
      ),
      _ => ptome.convert(
        conversion.input,
        backend: _backend(conversion.format),
        doctype: doctype,
        standalone: conversion.standalone,
        attributes: conversion.attributes,
      ),
    };
    return Converted(
      id: conversion.id,
      micros: watch.elapsedMicroseconds,
      output: output,
      log: log,
    );
  } on Object catch (error, stack) {
    return Crashed(
      id: conversion.id,
      micros: watch.elapsedMicroseconds,
      error: '${error.runtimeType}: $error',
      frame: _innermostFrame(stack),
    );
  }
}

Backend _backend(Format format) => switch (format) {
  Format.html5 => Backend.html5,
  Format.xhtml5 => Backend.xhtml5,
  Format.docbook5 => Backend.docbook5,
  Format.manpage => Backend.manpage,
  Format.pdf => Backend.pdf,
  Format.epub3 => Backend.epub3,
};

/// The first stack frame inside ptome's own code.
String? _innermostFrame(StackTrace stack) {
  for (final line in stack.toString().split('\n')) {
    final at = line.indexOf('package:ptome/');
    if (at >= 0) return line.substring(at).replaceAll(')', '');
  }
  return null;
}
