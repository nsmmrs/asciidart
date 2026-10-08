/// asciidart, converting in-process through its public API.
library;

import 'package:asciidart/asciidart.dart';

import '../spec/conversion.dart';

/// Converts [conversion] with asciidart in the calling isolate.
Outcome convertWithAsciidart(Conversion conversion) {
  final log = <LogEntry>[];
  final asciidart = Asciidart(
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
      Format.pdf || Format.epub3 => asciidart.convertToBytes(
        conversion.input,
        backend: _backend(conversion.format),
        doctype: doctype,
        attributes: conversion.attributes,
      ),
      _ => asciidart.convert(
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

/// The first stack frame inside asciidart's own code.
String? _innermostFrame(StackTrace stack) {
  for (final line in stack.toString().split('\n')) {
    final at = line.indexOf('package:asciidart/');
    if (at >= 0) return line.substring(at).replaceAll(')', '');
  }
  return null;
}
