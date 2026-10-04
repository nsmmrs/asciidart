/// One-line rendering of conversion failures for the command line.
library;

import 'dart:io' show FileSystemException, OSError, StdoutException;

import 'package:asciidoctor/src/errors.dart';

/// Renders [error] as the `asciidoctor: FAILED:` line the CLI prints when a
/// conversion fails.
///
/// The message is the error's own description, without the type name Dart
/// puts in front of it (`Bad state:`, `Invalid argument(s):`, ...).
String failureLine(Object error) => 'asciidoctor: FAILED: ${describe(error)}';

/// The description of [error] without its type name.
String describe(Object error) => switch (error) {
  AsciidoctorException(:final message) => message,
  FileSystemException(:final message, :final path, :final osError) =>
    _fileSystemMessage(message, path, osError?.message),
  ArgumentError(:final message?) => '$message',
  StateError(:final message) => message,
  UnsupportedError(:final message?) => message,
  FormatException(:final message) => message,
  _ => '$error',
};

String _fileSystemMessage(String message, String? path, String? reason) {
  final buffer = StringBuffer(message);
  if (path != null && !message.contains(path)) buffer.write(': $path');
  if (reason != null && reason.isNotEmpty) buffer.write(' ($reason)');
  return buffer.toString();
}

/// Whether [error] reports that the reader of an output stream went away
/// (`asciidoctor ... | head`), which ends the run quietly instead of failing
/// it.
bool isBrokenPipe(Object error) {
  final OSError? osError;
  switch (error) {
    case FileSystemException(osError: final e):
      osError = e;
    case StdoutException(osError: final e):
      osError = e;
    default:
      return false;
  }
  // EPIPE on Linux and macOS; ERROR_BROKEN_PIPE and ERROR_NO_DATA on
  // Windows.
  return const {32, 109, 232}.contains(osError?.errorCode);
}
