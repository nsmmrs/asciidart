import 'dart:io';

import 'package:args/args.dart';
import 'package:asciidoctor/asciidoctor.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag(
      'version',
      abbr: 'V',
      negatable: false,
      help: 'Print the version and exit.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage message.',
    );

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln('Usage: asciidoctor [options] [files]');
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (results.flag('version')) {
    stdout.writeln('Asciidoctor ${Asciidoctor.version} (Dart port)');
    return;
  }

  if (results.flag('help') || results.rest.isEmpty) {
    stdout.writeln('Usage: asciidoctor [options] [files]');
    stdout.writeln();
    stdout.writeln(parser.usage);
    return;
  }

  // Skeleton: conversion is not implemented yet (later phases).
  stderr.writeln('asciidoctor: conversion is not implemented yet.');
  exitCode = 69; // EX_UNAVAILABLE
}
