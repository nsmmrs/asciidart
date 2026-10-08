/// ptome, converting in-process through its public API.
library;

import 'package:ptome/ptome.dart';

import '../spec/conversion.dart';

/// Converts [conversion] with ptome in the calling isolate.
Outcome convertWithPtome(Conversion conversion) {
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
