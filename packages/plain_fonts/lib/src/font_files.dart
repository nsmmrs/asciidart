/// The file access the font index needs, and where each operating system
/// keeps its fonts and caches.
library;

import 'package:fonts/src/platform/none.dart'
    if (dart.library.io) 'package:fonts/src/platform/vm.dart'
    if (dart.library.js_interop) 'package:fonts/src/platform/js.dart'
    as host;

/// An entry of a folder.
typedef FontFolderEntry = ({
  String path,
  String name,
  bool isDirectory,
  bool isFile,
});

/// The file access a `FontIndex` needs: listing folders, reading files
/// whole or in ranges, and writing its cache. [FontFiles.platform] is the
/// platform's (`dart:io` on the Dart VM, the built-in modules on Node.js,
/// none in a browser); an embedder can give its own.
abstract interface class FontFiles {
  /// The platform's files.
  static FontFiles get platform => host.files;

  /// The folders fonts are installed in on this machine, the user's first
  /// (none without a file system).
  List<String> get fontDirectories;

  /// The folder for this user's caches, or null when there is none.
  String? get cacheDirectory;

  /// Whether [path] names a folder.
  bool isDirectory(String path);

  /// The entries directly inside [directory]; throws when it can't be
  /// listed.
  List<FontFolderEntry> list(String directory);

  /// The size and modification time of the file at [path]; throws when
  /// there is none.
  ({int size, DateTime modified}) stat(String path);

  /// The contents of the file at [path].
  List<int> read(String path);

  /// [length] bytes of the file at [path] from [offset] (fewer at its end).
  List<int> readRange(String path, int offset, int length);

  /// Writes [contents] (UTF-8) to the file at [path], creating its folder.
  void write(String path, String contents);
}

/// A file or folder that couldn't be read or written.
final class FontFilesException implements Exception {
  /// An exception about [path].
  const new(this.message, this.path);

  /// What went wrong.
  final String message;

  /// The file or folder.
  final String path;

  @override
  String toString() => 'FontFilesException: $message: $path';
}

/// The operating systems whose font folders are known.
enum FontPlatform {
  /// Linux and the other Unix-like systems (the XDG folders).
  linux,

  /// macOS.
  macos,

  /// Windows.
  windows,
}

/// The folders fonts are installed in on [os], the user's first, given
/// the [environment]: on Linux `$XDG_DATA_HOME/fonts`, `~/.fonts` and
/// `fonts` in each of `$XDG_DATA_DIRS`; on macOS the user's, the local and
/// the system `Library/Fonts`; on Windows the user's and the system's.
List<String> fontDirectoriesFor(
  FontPlatform os,
  Map<String, String> environment,
) {
  final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '';
  switch (os) {
    case FontPlatform.macos:
      return [
        '$home/Library/Fonts',
        '/Library/Fonts',
        '/System/Library/Fonts',
        '/System/Library/Fonts/Supplemental',
        '/Network/Library/Fonts',
      ];
    case FontPlatform.windows:
      final windows =
          environment['WINDIR'] ?? environment['SystemRoot'] ?? r'C:\Windows';
      return [
        if (environment['LOCALAPPDATA'] case final local?)
          '$local\\Microsoft\\Windows\\Fonts',
        '$windows\\Fonts',
      ];
    case FontPlatform.linux:
      final dataHome = environment['XDG_DATA_HOME'] ?? '$home/.local/share';
      final dataDirs =
          (environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
              .split(':')
              .where((dir) => dir.isNotEmpty);
      return [
        '$dataHome/fonts',
        '$home/.fonts',
        for (final dir in dataDirs) '$dir/fonts',
      ];
  }
}

/// The folder for this user's caches on [os], given the [environment]:
/// `$XDG_CACHE_HOME` (`~/.cache`) on Linux, `~/Library/Caches` on macOS,
/// `%LOCALAPPDATA%` on Windows.
String cacheDirectoryFor(FontPlatform os, Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '';
  return switch (os) {
    FontPlatform.macos => '$home/Library/Caches',
    FontPlatform.windows =>
      environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local',
    FontPlatform.linux => environment['XDG_CACHE_HOME'] ?? '$home/.cache',
  };
}
