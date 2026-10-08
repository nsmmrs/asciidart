/// The files of the Dart VM, through `dart:io`.
library;

import 'dart:io' as io;

import 'package:plain_fonts/src/font_files.dart';

/// The platform's files.
final FontFiles files = _VmFontFiles();

final class _VmFontFiles implements FontFiles {
  FontPlatform get _os => io.Platform.isMacOS
      ? FontPlatform.macos
      : io.Platform.isWindows
      ? FontPlatform.windows
      : FontPlatform.linux;

  @override
  List<String> get fontDirectories =>
      fontDirectoriesFor(_os, io.Platform.environment);

  @override
  String? get cacheDirectory => cacheDirectoryFor(_os, io.Platform.environment);

  @override
  bool isDirectory(String path) => io.FileSystemEntity.isDirectorySync(path);

  @override
  List<FontFolderEntry> list(String directory) => [
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
  ];

  @override
  ({int size, DateTime modified}) stat(String path) {
    final stat = io.File(path).statSync();
    if (stat.type == io.FileSystemEntityType.notFound) {
      throw io.PathNotFoundException(path, const io.OSError('not found'));
    }
    return (size: stat.size, modified: stat.modified);
  }

  @override
  List<int> read(String path) => io.File(path).readAsBytesSync();

  @override
  List<int> readRange(String path, int offset, int length) {
    final file = io.File(path).openSync();
    try {
      file.setPositionSync(offset);
      return file.readSync(length < 0 ? 0 : length);
    } finally {
      file.closeSync();
    }
  }

  @override
  void write(String path, String contents) {
    io.File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  }
}
