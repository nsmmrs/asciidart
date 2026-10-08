/// The fonts the backends that set text in fonts of their own (PDF, EPUB)
/// and `ptome doctor` find: the plain_fonts package's index, with
/// Ptome's policy.
///
/// The folders searched are those of `PTOME_FONT_PATH` (separated as
/// `PATH` is), then [Fonts.extraDirectories], then the user's and the
/// system's font folders, read through Ptome's I/O seam and cached in
/// Ptome's cache folder. A conversion's own fonts ([Fonts.withFonts])
/// come first.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:plain_fonts/plain_fonts.dart';
import 'package:ptome/src/io.dart' as io;

export 'package:plain_fonts/plain_fonts.dart' show FontIndex, InstalledFont;

/// The machine's fonts, and those of the conversion under way.
abstract final class Fonts {
  /// The index of the fonts in force: those given to [withFonts] around
  /// the work under way, else the [installed] ones.
  static FontIndex get current => switch (Zone.current[_zoneKey]) {
    final FontIndex index => index,
    _ => installed,
  };

  static final Object _zoneKey = Object();

  /// Runs [body] with [fonts] (file names and their bytes) found before
  /// the installed ones ([current]).
  static T withFonts<T>(Map<String, List<int>> fonts, T Function() body) {
    if (fonts.isEmpty) return body();
    final index = FontIndex(
      installed.directories,
      cacheFile: installed.cacheFile,
      memory: fonts,
      fileSystem: _files,
    );
    return runZoned(body, zoneValues: {_zoneKey: index});
  }

  /// The installed fonts ([machine]), looked at once per process (and
  /// again once the web font decoder is loaded, if they were passed over).
  static FontIndex get installed => switch (_installed) {
    final index? when !index.passedOverWebFonts || !FontIndex.decodesWebFonts =>
      index,
    _ => _installed = machine(),
  };
  static FontIndex? _installed;

  /// Replaces the installed fonts (null: the folders again).
  @visibleForTesting
  static set installed(FontIndex? index) => _installed = index;

  /// The machine's fonts: `PTOME_FONT_PATH`'s folders, then
  /// [extraDirectories], then the user's and the system's font folders.
  static FontIndex machine() => FontIndex.system(
    before: [...fontPath, ...extraDirectories],
    cacheFile: _cacheFile(),
    fileSystem: _files,
  );

  /// Folders searched before the user's and the system's (the tests and
  /// tools point it at the fonts vendored with asciidoctor-pdf).
  static List<String> get extraDirectories => _extraDirectories;
  static set extraDirectories(List<String> directories) {
    _extraDirectories = directories;
    _installed = null;
  }

  static List<String> _extraDirectories = const [];

  /// The folders of `PTOME_FONT_PATH`.
  static List<String> get fontPath => [
    for (final dir in (io.environment['PTOME_FONT_PATH'] ?? '').split(
      io.isWindows ? ';' : ':',
    ))
      if (dir.isNotEmpty) dir,
  ];

  static String? _cacheFile() {
    try {
      return '${io.cacheDirectory}/ptome/font-index.tsv';
      // No cache folder (a browser): no cache.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  static final FontFiles _files = _PtomeFontFiles();
}

/// The font files as Ptome's I/O seam reads them (so that an embedder's
/// `ptomeHost` applies to fonts too).
final class _PtomeFontFiles implements FontFiles {
  @override
  List<String> get fontDirectories => io.fontDirectories;

  @override
  String? get cacheDirectory {
    try {
      return io.cacheDirectory;
      // None in a browser.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  @override
  bool isDirectory(String path) => io.isDirectory(path);

  @override
  List<FontFolderEntry> list(String directory) => [
    for (final entry in io.listDirectory(directory))
      (
        path: entry.path,
        name: entry.name,
        isDirectory: entry.isDirectory,
        isFile: entry.isFile,
      ),
  ];

  @override
  ({int size, DateTime modified}) stat(String path) =>
      (size: io.fileSize(path), modified: io.modificationTime(path));

  @override
  List<int> read(String path) => io.readBytes(path);

  @override
  List<int> readRange(String path, int offset, int length) =>
      io.readFileRange(path, offset, length);

  @override
  void write(String path, String contents) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    if (slash > 0) io.createDirectories(path.substring(0, slash));
    io.writeString(path, contents);
  }
}
