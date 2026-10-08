/// Paths in the form the port reports them on every platform.
///
/// Asciidoctor normalizes paths to forward slashes, on Windows too, so
/// expected paths built from the working or temporary directory must use
/// them as well.
library;

import 'dart:io';

/// [path] with forward slashes.
String posixPath(String path) => path.replaceAll(r'\', '/');

/// The working directory, with forward slashes.
String get currentPath => posixPath(Directory.current.path);

/// A new directory under the system temporary directory, named with
/// [prefix], whose path uses forward slashes.
Directory createTempDir(String prefix) =>
    Directory(posixPath(Directory.systemTemp.createTempSync(prefix).path));
