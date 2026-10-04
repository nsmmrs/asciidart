/// The I/O seam on the Dart VM, through `dart:io` (see `io.dart`).
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/io/types.dart';
import 'package:asciidoctor/src/remote.dart';

/// Runs [body], turning a `dart:io` file system failure into an
/// [IoException].
T _guard<T>(T Function() body) {
  try {
    return body();
  } on io.FileSystemException catch (e) {
    throw IoException(
      e.message,
      path: e.path,
      reason: e.osError?.message,
      errorCode: e.osError?.errorCode,
    );
  }
}

/// Whether [path] names a regular file.
bool isFile(String path) => io.FileSystemEntity.isFileSync(path);

/// Whether [path] names a directory.
bool isDirectory(String path) => io.FileSystemEntity.isDirectorySync(path);

/// Whether [path] names a named pipe (FIFO).
bool isPipe(String path) =>
    io.FileSystemEntity.typeSync(path) == io.FileSystemEntityType.pipe;

/// Whether the file at [path] grants read permission to anyone.
bool isReadable(String path) => (io.File(path).statSync().mode & 0x124) != 0;

/// The contents of the file at [path]; throws [IoException].
List<int> readBytes(String path) =>
    _guard(() => io.File(path).readAsBytesSync());

/// The last modification time of the file at [path].
DateTime modificationTime(String path) =>
    _guard(() => io.File(path).lastModifiedSync());

/// Writes [contents] to the file at [path] as UTF-8, replacing it.
void writeString(String path, String contents) =>
    _guard(() => io.File(path).writeAsStringSync(contents));

/// Creates the directory at [path] and any missing parents.
void createDirectories(String path) =>
    _guard(() => io.Directory(path).createSync(recursive: true));

/// Whether anything exists at [path].
bool exists(String path) =>
    io.FileSystemEntity.typeSync(path) != io.FileSystemEntityType.notFound;

/// The entries directly inside [directory], following links; throws
/// [IoException].
List<DirectoryEntry> listDirectory(String directory) => _guard(
  () => [
    for (final entry in io.Directory(directory).listSync())
      (
        path: entry.path,
        name: entry.uri.pathSegments.lastWhere(
          (segment) => segment.isNotEmpty,
          orElse: () => entry.path,
        ),
        isDirectory: entry is io.Directory,
        isFile: entry is io.File,
      ),
  ],
);

/// Opens and closes the file at [path], so that a missing file, a
/// directory or a permission problem surfaces as an [IoException] before
/// anything else happens.
void probeReadable(String path) =>
    _guard(() => io.File(path).openSync().closeSync());

/// A sink appending UTF-8 text to the file at [path].
ClosableSink openAppend(String path) =>
    _FileSink(io.File(path).openWrite(mode: io.FileMode.append));

final class _FileSink implements ClosableSink {
  new(this._sink);

  final io.IOSink _sink;

  @override
  void write(Object? object) => _sink.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _sink.writeln(object);

  @override
  Future<void> close() => _sink.close();
}

/// The current working directory.
String get currentDirectory {
  // Forward slashes on Windows too, as Asciidoctor reports paths there.
  final path = io.Directory.current.path;
  return io.Platform.isWindows ? path.replaceAll(r'\', '/') : path;
}

/// The environment variables of the process.
Map<String, String> get environment => io.Platform.environment;

/// The path separator of the platform (`/` or `\`).
String get pathSeparator => io.Platform.pathSeparator;

/// Whether the platform is Windows.
bool get isWindows => io.Platform.isWindows;

/// The process id.
int get processId => io.pid;

/// The runtime, as shown by `asciidoctor --version`.
String get runtimeName => 'Dart ${io.Platform.version}';

/// Reads all of standard input as UTF-8.
String readStdin() {
  final bytes = <int>[];
  int byte;
  while ((byte = io.stdin.readByteSync()) != -1) {
    bytes.add(byte);
  }
  return utf8.decode(bytes);
}

/// Standard output, writing UTF-8.
StringSink get standardOutput => io.stdout..encoding = utf8;

/// Standard error, writing UTF-8.
StringSink get standardError => io.stderr;

/// Completes when standard output is closed, or with the error that made
/// a write to it fail.
Future<void> get standardOutputDone => io.stdout.done;

/// Sets the exit code the process reports when it ends.
set exitCode(int value) => io.exitCode = value;

/// Whether [error] reports that the reader of an output stream went away.
bool isBrokenPipe(Object error) {
  final code = switch (error) {
    io.FileSystemException(:final osError) => osError?.errorCode,
    io.StdoutException(:final osError) => osError?.errorCode,
    IoException(:final errorCode) => errorCode,
    _ => null,
  };
  // EPIPE on Linux and macOS; ERROR_BROKEN_PIPE and ERROR_NO_DATA on
  // Windows.
  return const {32, 109, 232}.contains(code);
}

/// The standard output of running [executable] with [arguments], or
/// `null` when it cannot be run or fails.
String? commandOutput(String executable, List<String> arguments) {
  try {
    final result = io.Process.runSync(executable, arguments);
    if (result.exitCode != 0) return null;
    return '${result.stdout}';
  } on io.ProcessException {
    return null;
  }
}

/// Decompresses gzip [bytes].
List<int> gunzip(List<int> bytes) => io.gzip.decode(bytes);

/// Fetches [uri] with an HTTP GET, following redirects; throws when the
/// response is not 2xx.
Future<RemoteResource> fetchUri(Uri uri) async {
  final client = io.HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw AsciidoctorException(
        'cannot read $uri: HTTP ${response.statusCode}',
      );
    }
    return (body: body, contentType: response.headers.contentType?.mimeType);
  } finally {
    client.close(force: true);
  }
}
