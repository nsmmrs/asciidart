/// The I/O seam's API, implemented by `vm.dart` (through `dart:io`) and
/// `js.dart` (through the Node.js built-ins the npm package injects, or
/// nothing in a browser).
///
/// This file is selected only on a platform with neither, where every
/// operation is unsupported.
library;

import 'package:asciidart/src/io/types.dart';
import 'package:asciidart/src/remote.dart';

Never _unsupported() =>
    throw UnsupportedError('file and process access is unavailable here');

/// Whether [path] names a regular file.
bool isFile(String path) => _unsupported();

/// Whether [path] names a directory.
bool isDirectory(String path) => _unsupported();

/// Whether [path] names a named pipe (FIFO).
bool isPipe(String path) => _unsupported();

/// Whether the file at [path] grants read permission to anyone.
bool isReadable(String path) => _unsupported();

/// The contents of the file at [path]; throws [IoException].
List<int> readBytes(String path) => _unsupported();

/// The last modification time of the file at [path].
DateTime modificationTime(String path) => _unsupported();

/// Writes [contents] to the file at [path] as UTF-8, replacing it.
void writeString(String path, String contents) => _unsupported();

/// Writes [bytes] to the file at [path], replacing it.
void writeBytes(String path, List<int> bytes) => _unsupported();

/// [bytes] compressed with raw DEFLATE (no zlib header).
List<int> deflateRaw(List<int> bytes) => _unsupported();

/// [bytes] (raw DEFLATE) expanded.
List<int> inflateRaw(List<int> bytes) => _unsupported();

/// The size of the file at [path], in bytes.
int fileSize(String path) => _unsupported();

/// [length] bytes of the file at [path] from [offset] (fewer at its end).
List<int> readFileRange(String path, int offset, int length) => _unsupported();

/// The folders fonts are installed in, the user's first.
List<String> get fontDirectories => const [];

/// The folder fonts are installed in for this user alone.
String get userFontDirectory => _unsupported();

/// The folder for this user's caches.
String get cacheDirectory => _unsupported();

/// Whether standard input is a terminal (someone can answer a question).
bool get hasTerminal => false;

/// A line read from standard input, without its line break; null at its
/// end.
String? readLine() => _unsupported();

/// The physical cores of the machine.
int get physicalCores => 1;

/// Whether [zlibEncode] and [zlibDecode] are the platform's own (faster
/// than the PDF library's).
bool get hasNativeZlib => false;

/// [bytes] compressed in zlib format at [level] (1-9).
List<int> zlibEncode(List<int> bytes, int level) => _unsupported();

/// [bytes] (zlib format) expanded.
List<int> zlibDecode(List<int> bytes) => _unsupported();

/// Creates the directory at [path] and any missing parents.
void createDirectories(String path) => _unsupported();

/// Whether anything exists at [path].
bool exists(String path) => _unsupported();

/// The entries directly inside [directory], following links; throws
/// [IoException].
List<DirectoryEntry> listDirectory(String directory) => _unsupported();

/// Opens and closes the file at [path], so that a missing file, a
/// directory or a permission problem surfaces as an [IoException] before
/// anything else happens.
void probeReadable(String path) => _unsupported();

/// A sink appending UTF-8 text to the file at [path].
ClosableSink openAppend(String path) => _unsupported();

/// The current working directory.
String get currentDirectory => _unsupported();

/// The environment variables of the process.
Map<String, String> get environment => _unsupported();

/// The path separator of the platform (`/` or `\`).
String get pathSeparator => _unsupported();

/// Whether the platform is Windows.
bool get isWindows => _unsupported();

/// The process id.
int get processId => _unsupported();

/// The runtime, as shown by `asciidoctor --version` (for example
/// `Dart 3.13.5` or `Node.js v22.0.0`).
String get runtimeName => _unsupported();

/// Reads all of standard input as UTF-8.
String readStdin() => _unsupported();

/// Standard output, writing UTF-8.
StringSink get standardOutput => _unsupported();

/// Standard error, writing UTF-8.
StringSink get standardError => _unsupported();

/// Completes when standard output is closed, or with the error that made
/// a write to it fail.
Future<void> get standardOutputDone => _unsupported();

/// Sets the exit code the process reports when it ends.
set exitCode(int value) => _unsupported();

/// Whether [error] reports that the reader of an output stream went away.
bool isBrokenPipe(Object error) => _unsupported();

/// The standard output of running [executable] with [arguments], or
/// `null` when it cannot be run or fails.
String? commandOutput(String executable, List<String> arguments) =>
    _unsupported();

/// Decompresses gzip [bytes].
List<int> gunzip(List<int> bytes) => _unsupported();

/// Fetches [uri] with an HTTP GET, following redirects; throws when the
/// response is not 2xx.
Future<RemoteResource> fetchUri(Uri uri) => _unsupported();
