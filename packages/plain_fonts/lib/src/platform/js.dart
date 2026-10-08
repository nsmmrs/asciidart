/// The files of JavaScript: Node.js's, through its built-in modules (found
/// with `process.getBuiltinModule`, so the compiled code imports no
/// `node:*` module); none in a browser.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:plain_fonts/src/font_files.dart';
import 'package:plain_fonts/src/platform/none.dart';

@JS('globalThis.process')
external _Process? get _nodeProcess;

/// The platform's files: Node.js's, or none.
final FontFiles files = _nodeFiles() ?? NoFontFiles();

FontFiles? _nodeFiles() {
  final process = _nodeProcess;
  if (process == null) return null;
  final getBuiltinModule = process.getProperty<JSAny?>('getBuiltinModule'.toJS);
  if (getBuiltinModule == null || !getBuiltinModule.isA<JSFunction>()) {
    return null;
  }
  final fs = process.getBuiltinModule('node:fs');
  return fs == null ? null : _NodeFontFiles(process, fs as _Fs);
}

extension type _Process(JSObject _) implements JSObject {
  external JSObject? getBuiltinModule(String id);
  external JSObject get env;
  external String get platform;
}

extension type _Fs(JSObject _) implements JSObject {
  external _Stats statSync(String path);
  external JSUint8Array readFileSync(String path);
  external void writeFileSync(String path, String data, String encoding);
  external JSAny? mkdirSync(String path, JSObject options);
  external JSArray<JSString> readdirSync(String path);
  external int openSync(String path, String flags);
  external int readSync(
    int fd,
    JSUint8Array buffer,
    int offset,
    int length,
    JSAny? position,
  );
  external void closeSync(int fd);
}

extension type _Stats(JSObject _) implements JSObject {
  external bool isFile();
  external bool isDirectory();
  external double get mtimeMs;
  external double get size;
}

/// [body], a Node.js error turned into a [FontFilesException].
T _guard<T>(String path, T Function() body) {
  try {
    return body();
  } on Object catch (error) {
    // Node.js throws JavaScript errors.
    throw FontFilesException('$error', path);
  }
}

final class _NodeFontFiles implements FontFiles {
  new(this._process, this._fs);

  final _Process _process;
  final _Fs _fs;

  FontPlatform get _os => switch (_process.platform) {
    'darwin' => FontPlatform.macos,
    'win32' => FontPlatform.windows,
    _ => FontPlatform.linux,
  };

  Map<String, String> get _environment {
    final env = _process.env;
    final keys = (globalContext['Object']! as JSObject).callMethod<JSArray>(
      'keys'.toJS,
      env,
    );
    return {
      for (final key in keys.toDart.cast<JSString>())
        if (env.getProperty<JSAny?>(key) case final JSString value)
          key.toDart: value.toDart,
    };
  }

  @override
  List<String> get fontDirectories => fontDirectoriesFor(_os, _environment);

  @override
  String? get cacheDirectory => cacheDirectoryFor(_os, _environment);

  _Stats? _stat(String path) {
    try {
      return _fs.statSync(path);
      // A missing file throws a JavaScript error.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  @override
  bool isDirectory(String path) => _stat(path)?.isDirectory() ?? false;

  @override
  List<FontFolderEntry> list(String directory) {
    final separator = directory.endsWith('/') ? '' : '/';
    return [
      for (final name in _guard(
        directory,
        () => _fs.readdirSync(directory),
      ).toDart)
        if ('$directory$separator${name.toDart}' case final path)
          if (_stat(path) case final stats?)
            (
              path: path,
              name: name.toDart,
              isDirectory: stats.isDirectory(),
              isFile: stats.isFile(),
            ),
    ];
  }

  @override
  ({int size, DateTime modified}) stat(String path) {
    final stats = _guard(path, () => _fs.statSync(path));
    return (
      size: stats.size.round(),
      modified: DateTime.fromMillisecondsSinceEpoch(stats.mtimeMs.round()),
    );
  }

  @override
  List<int> read(String path) =>
      _guard(path, () => _fs.readFileSync(path).toDart);

  @override
  List<int> readRange(String path, int offset, int length) => _guard(path, () {
    final fd = _fs.openSync(path, 'r');
    try {
      final size = length < 0 ? 0 : length;
      final buffer = Uint8List(size).toJS;
      final read = _fs.readSync(fd, buffer, 0, size, offset.toJS);
      return buffer.toDart.sublist(0, read);
    } finally {
      _fs.closeSync(fd);
    }
  });

  @override
  void write(String path, String contents) => _guard(path, () {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    if (slash > 0) {
      _fs.mkdirSync(
        path.substring(0, slash),
        JSObject()..setProperty('recursive'.toJS, true.toJS),
      );
    }
    _fs.writeFileSync(path, contents, 'utf8');
  });
}
