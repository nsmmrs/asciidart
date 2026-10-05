/// One-line rendering of conversion failures for the command line.
library;

import 'package:asciidart/src/errors.dart';
import 'package:asciidart/src/io.dart' as io;

/// Renders [error] as the `asciidart: FAILED:` line the CLI prints when a
/// conversion fails.
///
/// The message is the error's own description, without the type name Dart
/// puts in front of it (`Bad state:`, `Invalid argument(s):`, ...).
String failureLine(Object error) => 'asciidart: FAILED: ${describe(error)}';

/// The description of [error] without its type name.
String describe(Object error) => switch (error) {
  AsciidoctorException(:final message) => message,
  io.IoException() => '$error',
  ArgumentError(:final message?) => '$message',
  StateError(:final message) => message,
  UnsupportedError(:final message?) => message,
  FormatException(:final message) => message,
  _ => '$error',
};
