/// Platform-neutral types of the I/O seam (see `io.dart`).
library;

/// A failed file system or process operation.
///
/// [toString] renders the message, the [path] (when the message does not
/// already name it) and the operating system's [reason], as the CLI prints
/// them.
class IoException implements Exception {
  /// Creates an exception for [message] about [path].
  const new(this.message, {this.path, this.reason, this.errorCode});

  /// What failed (for example `Cannot open file`).
  final String message;

  /// The path the operation was about, if any.
  final String? path;

  /// The operating system's description of the failure, if any.
  final String? reason;

  /// The operating system's error code, if any.
  final int? errorCode;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    final p = path;
    if (p != null && p.isNotEmpty && !message.contains(p)) {
      buffer.write(': $p');
    }
    final r = reason;
    if (r != null && r.isNotEmpty) buffer.write(' ($r)');
    return buffer.toString();
  }
}

/// An entry of a directory listing: its `path` (the directory joined with
/// its `name`) and whether it is (or links to) a directory or a regular
/// file.
typedef DirectoryEntry = ({
  String path,
  String name,
  bool isDirectory,
  bool isFile,
});

/// A text sink that is closed when the writer is done with it.
abstract interface class ClosableSink implements StringSink {
  /// Flushes and closes the sink.
  Future<void> close();
}
