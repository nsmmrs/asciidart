/// Files of a web page, for conversions in a browser (see `io.dart`).
///
/// A browser has no file system: the asynchronous conversions to PDF and
/// EPUB fetch the files the conversion reads (images, themes) relative to
/// the page instead, and serve them through the I/O seam while the
/// conversion runs. The page's directory stands for the root of the file
/// system (`/`, the working directory there).
library;

import 'dart:async';

/// The files a conversion may read, by path (`null` for a file that could
/// not be fetched), and the paths it asked for when [requested] is given.
final class PageFiles {
  /// Files by path, and where to record the paths asked for.
  new(this.files, {this.requested});

  /// Fetched files by path; `null` for a file that could not be fetched.
  final Map<String, List<int>?> files;

  /// The paths the conversion asked for, when they are being recorded.
  final Set<String>? requested;

  /// The contents of the file at [path], or `null` when it is missing;
  /// records [path] as asked for.
  List<int>? read(String path) {
    requested?.add(path);
    return files[path];
  }

  /// The paths asked for that have not been fetched yet.
  Iterable<String> get missing =>
      requested?.where((path) => !files.containsKey(path)) ?? const [];
}

const Symbol _key = #ptome.pageFiles;

/// The page files of the conversion under way, if any.
PageFiles? get currentPageFiles => Zone.current[_key] as PageFiles?;

/// Runs [body] (and the asynchronous work it starts) reading files from
/// [files] where there is no file system.
T withPageFiles<T>(PageFiles files, T Function() body) =>
    runZoned(body, zoneValues: {_key: files});
