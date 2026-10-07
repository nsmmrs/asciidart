/// No file system (a platform with neither `dart:io` nor JavaScript).
library;

import 'package:fonts/src/font_files.dart';

/// The platform's files: none.
final FontFiles files = NoFontFiles();

/// No fonts and no files: every read fails.
final class NoFontFiles implements FontFiles {
  @override
  List<String> get fontDirectories => const [];

  @override
  String? get cacheDirectory => null;

  @override
  bool isDirectory(String path) => false;

  @override
  List<FontFolderEntry> list(String directory) => throw _none(directory);

  @override
  ({int size, DateTime modified}) stat(String path) => throw _none(path);

  @override
  List<int> read(String path) => throw _none(path);

  @override
  List<int> readRange(String path, int offset, int length) => throw _none(path);

  @override
  void write(String path, String contents) => throw _none(path);

  static FontFilesException _none(String path) =>
      FontFilesException('no file system here', path);
}
