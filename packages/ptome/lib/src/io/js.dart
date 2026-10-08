/// The I/O seam on JavaScript (see `io.dart`).
///
/// On Node.js, the built-in modules this file uses (`fs`, `zlib`) come from
/// `process.getBuiltinModule`, so the compiled bundle never imports
/// `node:*` modules and stays safe for bundlers; an embedder can also
/// supply them as `globalThis.ptomeHost` (`{fs, process, zlib}`).
/// Without them (in a browser), there is no file system: files read as
/// missing, the working directory is `/`, the environment is empty, and
/// output goes to the console.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart' show deflate;
import 'package:plain_fonts/plain_fonts.dart'
    show FontPlatform, cacheDirectoryFor, fontDirectoriesFor;
import 'package:ptome/src/errors.dart';
import 'package:ptome/src/io/types.dart';
import 'package:ptome/src/remote.dart';

@JS('globalThis.ptomeHost')
external _Host? get _injectedHost;

@JS('globalThis.process')
external _NodeProcess? get _nodeProcess;

/// The Node.js built-ins this file uses, or `null` outside Node.js.
final _Host? _host = _injectedHost ?? _nodeHost();

/// The Node.js built-ins, found through `process.getBuiltinModule` (Node.js
/// 20.16 and later), or `null` outside Node.js.
_Host? _nodeHost() {
  final process = _nodeProcess;
  if (process == null) return null;
  final getBuiltinModule = process.getProperty<JSAny?>('getBuiltinModule'.toJS);
  if (getBuiltinModule == null || !getBuiltinModule.isA<JSFunction>()) {
    return null;
  }
  final fs = process.getBuiltinModule('node:fs');
  if (fs == null) return null;
  return _Host(
    JSObject()
      ..setProperty('fs'.toJS, fs)
      ..setProperty('process'.toJS, process)
      ..setProperty('zlib'.toJS, process.getBuiltinModule('node:zlib'))
      ..setProperty(
        'childProcess'.toJS,
        process.getBuiltinModule('node:child_process'),
      ),
  );
}

extension type _NodeProcess(JSObject _) implements JSObject {
  external JSObject? getBuiltinModule(String id);
}

/// The Node.js built-ins: injected as `globalThis.ptomeHost`, or
/// found through `process.getBuiltinModule`.
extension type _Host(JSObject _) implements JSObject {
  external _Fs get fs;
  external _Process get process;
  external _Zlib? get zlib;
  external _ChildProcess? get childProcess;
}

extension type _ChildProcess(JSObject _) implements JSObject {
  external JSAny execFileSync(
    String file,
    JSArray<JSString> args,
    JSObject options,
  );
}

extension type _Fs(JSObject _) implements JSObject {
  external _Stats? statSync(String path, JSObject options);
  external JSUint8Array readFileSync(JSAny pathOrFd);
  external void writeFileSync(String path, String data, String encoding);
  @JS('writeFileSync')
  external void writeFileBytesSync(String path, JSUint8Array data);
  external void appendFileSync(String path, String data, String encoding);
  external JSAny? mkdirSync(String path, JSObject options);
  external JSArray<JSString> readdirSync(String path, JSObject options);
  external int openSync(String path, String flags);
  external int readSync(
    int fd,
    JSUint8Array buffer,
    int offset,
    int length,
    JSAny? position,
  );
  external void closeSync(int fd);
  external void accessSync(String path, int mode);
}

extension type _Stats(JSObject _) implements JSObject {
  external bool isFile();
  external bool isDirectory();
  external bool isFIFO();
  external double get mtimeMs;
  external double get size;
}

extension type _Process(JSObject _) implements JSObject {
  external String cwd();
  external JSObject get env;
  external String get platform;
  external int get pid;
  external String get version;
  external _Stdin get stdin;
  external _Stream get stdout;
  external _Stream get stderr;
  external int? get exitCode;
  external set exitCode(int? value);
}

extension type _Stdin(JSObject _) implements JSObject {
  external bool? get isTTY;
}

extension type _Stream(JSObject _) implements JSObject {
  external bool write(String chunk);
}

extension type _Zlib(JSObject _) implements JSObject {
  external JSUint8Array deflateRawSync(JSUint8Array bytes);
}

extension type _Console(JSObject _) implements JSObject {
  external void log(String message);
  external void error(String message);
}

@JS('console')
external _Console get _console;

@JS('Object.keys')
external JSArray<JSString> _keys(JSObject object);

@JS('fetch')
external JSPromise<_Response> _fetch(String url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external _Headers get headers;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _Headers(JSObject _) implements JSObject {
  external String? get(String name);
}

/// Runs [body], turning a thrown Node.js error into an [IoException].
T _guard<T>(String message, String path, T Function() body) {
  try {
    return body();
  } on IoException {
    rethrow;
    // Node.js errors are JavaScript objects, not Dart exceptions.
  } on Object catch (error) {
    throw _ioException(message, path, error);
  }
}

IoException _ioException(String message, String path, Object error) {
  String? code;
  String? reason;
  int? errno;
  if (error case final JSObject object) {
    code = object.getProperty<JSString?>('code'.toJS)?.toDart;
    reason = object.getProperty<JSString?>('message'.toJS)?.toDart;
    // Node.js reports errno negated (-2 for ENOENT).
    errno = object.getProperty<JSNumber?>('errno'.toJS)?.toDartInt.abs();
  }
  return IoException(
    message,
    path: path,
    reason: reason ?? code,
    errorCode: errno,
  );
}

IoException _noFileSystem(String path) => IoException(
  'Cannot open file',
  path: path,
  reason: 'no file system in this environment',
);

JSObject _options(Map<String, Object> entries) {
  final object = JSObject();
  entries.forEach((key, value) {
    object.setProperty(key.toJS, switch (value) {
      final bool flag => flag.toJS,
      final String text => text.toJS,
      final int number => number.toJS,
      _ => throw ArgumentError.value(value, key),
    });
  });
  return object;
}

_Stats? _stat(String path) {
  final host = _host;
  if (host == null) return null;
  try {
    return host.fs.statSync(path, _options({'throwIfNoEntry': false}));
    // Node.js errors are JavaScript objects, not Dart exceptions.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
}

/// Whether [path] names a regular file.
bool isFile(String path) => _stat(path)?.isFile() ?? false;

/// Whether [path] names a directory.
bool isDirectory(String path) => _stat(path)?.isDirectory() ?? false;

/// Whether [path] names a named pipe (FIFO).
bool isPipe(String path) => _stat(path)?.isFIFO() ?? false;

/// Whether the file at [path] grants read permission.
bool isReadable(String path) {
  final host = _host;
  if (host == null) return false;
  try {
    host.fs.accessSync(path, 4); // fs.constants.R_OK
    return true;
    // Node.js errors are JavaScript objects, not Dart exceptions.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return false;
  }
}

/// The contents of the file at [path]; throws [IoException].
List<int> readBytes(String path) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  return _guard(
    'Cannot open file',
    path,
    () => host.fs.readFileSync(path.toJS).toDart,
  );
}

/// The last modification time of the file at [path].
DateTime modificationTime(String path) {
  final stats = _stat(path);
  if (stats == null) throw _noFileSystem(path);
  return DateTime.fromMillisecondsSinceEpoch(stats.mtimeMs.round());
}

/// Writes [contents] to the file at [path] as UTF-8, replacing it.
void writeString(String path, String contents) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  _guard(
    'Cannot write file',
    path,
    () => host.fs.writeFileSync(path, contents, 'utf8'),
  );
}

/// Writes [bytes] to the file at [path], replacing it.
void writeBytes(String path, List<int> bytes) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  _guard(
    'Cannot write file',
    path,
    () => host.fs.writeFileBytesSync(path, Uint8List.fromList(bytes).toJS),
  );
}

/// [bytes] compressed with raw DEFLATE (no zlib header): Node.js's zlib,
/// or plain_compression's deflate where there is none (a browser).
List<int> deflateRaw(List<int> bytes) {
  final zlib = _host?.zlib;
  if (zlib == null) return deflate(bytes);
  return zlib.deflateRawSync(Uint8List.fromList(bytes).toJS).toDart;
}

/// The size of the file at [path], in bytes.
int fileSize(String path) {
  final stats = _stat(path);
  if (stats == null) throw _noFileSystem(path);
  return stats.size.round();
}

/// [length] bytes of the file at [path] from [offset] (fewer at its end).
List<int> readFileRange(String path, int offset, int length) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  return _guard('Cannot open file', path, () {
    final fd = host.fs.openSync(path, 'r');
    try {
      final size = length < 0 ? 0 : length;
      final buffer = Uint8List(size).toJS;
      final read = host.fs.readSync(fd, buffer, 0, size, offset.toJS);
      return buffer.toDart.sublist(0, read);
    } finally {
      host.fs.closeSync(fd);
    }
  });
}

/// The folders fonts are installed in, the user's first, on Node.js (as
/// on the Dart VM); none in a browser.
List<String> get fontDirectories {
  final os = _fontPlatform;
  return os == null ? const [] : fontDirectoriesFor(os, environment);
}

/// The operating system Node.js runs on, or null in a browser.
FontPlatform? get _fontPlatform => switch (_host?.process.platform) {
  null => null,
  'darwin' => FontPlatform.macos,
  'win32' => FontPlatform.windows,
  _ => FontPlatform.linux,
};

/// The folder fonts are installed in for this user alone (Node.js).
String get userFontDirectory {
  final dirs = fontDirectories;
  if (dirs.isEmpty) {
    throw UnsupportedError('font folders are not available in a browser');
  }
  return dirs.first;
}

/// The folder for this user's caches (Node.js).
String get cacheDirectory {
  final os = _fontPlatform;
  if (os == null) {
    throw UnsupportedError('a cache folder is not available in a browser');
  }
  return cacheDirectoryFor(os, environment);
}

/// Whether standard input is a terminal (Node.js).
bool get hasTerminal => _host?.process.stdin.isTTY ?? false;

/// A line read from standard input, without its line break; null at its
/// end (Node.js).
String? readLine() {
  final host = _host;
  if (host == null) return null;
  final bytes = <int>[];
  final view = Uint8List(1).toJS;
  var failures = 0;
  while (true) {
    final int read;
    try {
      read = host.fs.readSync(0, view, 0, 1, null);
      failures = 0;
      // A read that would block (EAGAIN) is tried again, for a while.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (++failures > 100000) return null;
      continue;
    }
    if (read == 0) return bytes.isEmpty ? null : utf8.decode(bytes);
    final byte = view.toDart[0];
    if (byte == 0x0a) {
      return utf8.decode(bytes).replaceFirst(RegExp(r'\r$'), '');
    }
    bytes.add(byte);
  }
}

/// The physical cores of the machine: one (the JavaScript build runs
/// everything serially).
int get physicalCores => 1;

/// Whether [zlibEncode] and [zlibDecode] are the platform's own: not on
/// JavaScript (where the PDF backend doesn't run).
bool get hasNativeZlib => false;

/// [bytes] compressed in zlib format at [level] (1-9).
List<int> zlibEncode(List<int> bytes, int level) =>
    throw UnsupportedError('zlib is unavailable in this environment');

/// [bytes] (zlib format) expanded.
List<int> zlibDecode(List<int> bytes) =>
    throw UnsupportedError('zlib is unavailable in this environment');

/// Creates the directory at [path] and any missing parents.
void createDirectories(String path) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  _guard(
    'Creation failed',
    path,
    () => host.fs.mkdirSync(path, _options({'recursive': true})),
  );
}

/// Whether anything exists at [path].
bool exists(String path) => _stat(path) != null;

/// The entries directly inside [directory], following links; throws
/// [IoException].
List<DirectoryEntry> listDirectory(String directory) {
  final host = _host;
  if (host == null) throw _noFileSystem(directory);
  final names = _guard(
    'Directory listing failed',
    directory,
    () => host.fs.readdirSync(directory, _options({})),
  ).toDart;
  final separator = directory.endsWith('/') ? '' : '/';
  return [
    for (final name in names)
      (
        path: '$directory$separator${name.toDart}',
        name: name.toDart,
        isDirectory: isDirectory('$directory$separator${name.toDart}'),
        isFile: isFile('$directory$separator${name.toDart}'),
      ),
  ];
}

/// Opens and closes the file at [path], so that a missing file, a
/// directory or a permission problem surfaces as an [IoException] before
/// anything else happens.
void probeReadable(String path) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  _guard('Cannot open file', path, () {
    if (isDirectory(path)) {
      throw IoException(
        'Cannot open file',
        path: path,
        reason: 'Is a directory',
      );
    }
    host.fs.closeSync(host.fs.openSync(path, 'r'));
  });
}

/// A sink appending UTF-8 text to the file at [path].
ClosableSink openAppend(String path) {
  final host = _host;
  if (host == null) throw _noFileSystem(path);
  return _AppendSink(host.fs, path);
}

final class _AppendSink extends _TextSink implements ClosableSink {
  new(this._fs, this._path);

  final _Fs _fs;
  final String _path;

  @override
  void emit(String text) => _fs.appendFileSync(_path, text, 'utf8');

  @override
  Future<void> close() async {}
}

/// A [StringSink] that hands every write to [emit].
abstract class _TextSink implements StringSink {
  void emit(String text);

  @override
  void write(Object? object) => emit('$object');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      emit(objects.join(separator));

  @override
  void writeCharCode(int charCode) => emit(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => emit('$object\n');
}

final class _StreamSink extends _TextSink {
  new(this._stream);

  final _Stream _stream;

  @override
  void emit(String text) => _stream.write(text);
}

/// Buffers text into lines for the console of a browser.
final class _ConsoleSink extends _TextSink {
  new({required this.error});

  final bool error;
  final StringBuffer _line = StringBuffer();

  @override
  void emit(String text) {
    var rest = text;
    var newline = rest.indexOf('\n');
    while (newline != -1) {
      _line.write(rest.substring(0, newline));
      final line = _line.toString();
      _line.clear();
      error ? _console.error(line) : _console.log(line);
      rest = rest.substring(newline + 1);
      newline = rest.indexOf('\n');
    }
    _line.write(rest);
  }
}

/// The current working directory.
String get currentDirectory => _host?.process.cwd() ?? '/';

/// The environment variables of the process.
Map<String, String> get environment {
  final host = _host;
  if (host == null) return const {};
  final env = host.process.env;
  return {
    for (final key in _keys(env).toDart)
      key.toDart: env.getProperty<JSString?>(key)?.toDart ?? '',
  };
}

/// The path separator of the platform (`/` or `\`).
String get pathSeparator => isWindows ? r'\' : '/';

/// Whether the platform is Windows.
bool get isWindows => _host?.process.platform == 'win32';

/// The process id.
int get processId => _host?.process.pid ?? 0;

/// The runtime, as shown by `asciidoctor --version`.
String get runtimeName {
  final host = _host;
  return host == null ? 'JavaScript' : 'Node.js ${host.process.version}';
}

/// Reads all of standard input as UTF-8.
String readStdin() {
  final host = _host;
  if (host == null) return '';
  return utf8.decode(host.fs.readFileSync(0.toJS).toDart);
}

StringSink? _stdout;
StringSink? _stderr;

/// Standard output, writing UTF-8.
StringSink get standardOutput => _stdout ??= switch (_host) {
  final host? => _StreamSink(host.process.stdout),
  null => _ConsoleSink(error: false),
};

/// Standard error, writing UTF-8.
StringSink get standardError => _stderr ??= switch (_host) {
  final host? => _StreamSink(host.process.stderr),
  null => _ConsoleSink(error: true),
};

/// Completes when standard output is closed. The npm wrapper handles a
/// closed pipe on the stream itself, so this never completes.
Future<void> get standardOutputDone => Completer<void>().future;

/// Sets the exit code the process reports when it ends.
set exitCode(int value) {
  final host = _host;
  if (host != null) host.process.exitCode = value;
}

/// Whether [error] reports that the reader of an output stream went away.
bool isBrokenPipe(Object error) => switch (error) {
  IoException(:final reason, :final errorCode) =>
    reason == 'EPIPE' || errorCode == 32,
  final JSObject object =>
    object.getProperty<JSString?>('code'.toJS)?.toDart == 'EPIPE',
  _ => false,
};

/// Running other programs is not supported on JavaScript; always `null`.
String? commandOutput(String executable, List<String> arguments) {
  final childProcess = _host?.childProcess;
  if (childProcess == null) return null;
  try {
    final output = childProcess.execFileSync(
      executable,
      [for (final a in arguments) a.toJS].toJS,
      JSObject()
        ..setProperty('encoding'.toJS, 'utf8'.toJS)
        ..setProperty(
          'stdio'.toJS,
          ['ignore'.toJS, 'pipe'.toJS, 'ignore'.toJS].toJS,
        ),
    );
    return output.isA<JSString>() ? (output as JSString).toDart : null;
    // It couldn't be run, or it failed.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
}

/// Fetches [uri] with the global `fetch`, following redirects; throws when
/// the response is not 2xx.
Future<RemoteResource> fetchUri(Uri uri) async {
  final response = await _fetch('$uri').toDart;
  if (!response.ok) {
    throw AsciidoctorException('cannot read $uri: HTTP ${response.status}');
  }
  final buffer = await response.arrayBuffer().toDart;
  final contentType = response.headers.get('content-type');
  return (
    body: buffer.toDart.asUint8List(),
    contentType: contentType?.split(';').first.trim(),
  );
}
