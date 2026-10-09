/// Files and paths for the units engine, through ptome's platform I/O so
/// the engine compiles to native code and to JavaScript alike. Paths use
/// `/`; on Windows a backslash also separates.
library;

import 'dart:convert';

import 'package:ptome/src/io.dart' as io;

/// The file's text, decoded as UTF-8.
String readText(String path) => utf8.decode(io.readBytes(path));

/// The file's lines, without their line terminators.
List<String> readLines(String path) =>
    const LineSplitter().convert(readText(path));

/// Whether [path] is a file.
bool isFile(String path) => io.isFile(path);

/// Whether [path] is a directory.
bool isDirectory(String path) => io.isDirectory(path);

/// The files under [dir], recursively, as full paths.
List<String> listFiles(String dir) {
  final out = <String>[];
  void walk(String d) {
    for (final e in io.listDirectory(d)) {
      final full = e.path;
      if (e.isDirectory) {
        walk(full);
      } else {
        out.add(full);
      }
    }
  }

  walk(dir);
  return out;
}

String _slashes(String path) =>
    io.isWindows ? path.replaceAll(r'\', '/') : path;

/// Whether [path] starts at the root (or a drive, on Windows).
bool isAbsolute(String path) {
  final s = _slashes(path);
  return s.startsWith('/') || RegExp('^[A-Za-z]:/').hasMatch(s);
}

/// [b] under the directory [a], or [b] itself when it is absolute.
String join(String a, String b) {
  if (isAbsolute(b) || a.isEmpty) return b;
  final s = _slashes(a);
  return s.endsWith('/') ? '$s$b' : '$s/$b';
}

/// The directory part of [path] (`.` for a bare name).
String dirname(String path) {
  final s = _slashes(path);
  final i = s.lastIndexOf('/');
  if (i < 0) return '.';
  if (i == 0) return '/';
  return s.substring(0, i);
}

/// The last segment of [path].
String basename(String path) {
  final s = _slashes(path);
  return s.substring(s.lastIndexOf('/') + 1);
}

/// [path] made absolute against the current directory, normalized.
String absolute(String path) => isAbsolute(path)
    ? normalize(path)
    : normalize(join(io.currentDirectory, path));

/// [path] with `.` and `..` segments resolved and repeated slashes removed.
String normalize(String path) {
  final s = _slashes(path);
  final root = s.startsWith('/') ? '/' : '';
  final out = <String>[];
  for (final part in s.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && out.isNotEmpty && out.last != '..') {
      out.removeLast();
    } else if (part != '..' || root.isEmpty) {
      out.add(part);
    }
  }
  final joined = root + out.join('/');
  return joined.isEmpty ? '.' : joined;
}

/// [path] relative to the directory [from].
String relative(String path, {required String from}) {
  final a = absolute(path).split('/');
  final b = absolute(from).split('/');
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  final parts = [for (var j = i; j < b.length; j++) '..', ...a.sublist(i)];
  return parts.isEmpty ? '.' : parts.join('/');
}

/// The `schemes/` directory nearest above [path].
String? schemesDir(String path) {
  var dir = dirname(absolute(path));
  while (true) {
    final candidate = join(dir, 'schemes');
    if (isDirectory(candidate)) return candidate;
    final parent = dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}
