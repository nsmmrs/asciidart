/// Source positions within AsciiDoc input.
library;

/// A position in the source: the file, its directory, the path shown in
/// messages, and a 1-based line number.
///
/// Port of `Asciidoctor::Reader::Cursor`. Also used as the source location
/// of blocks when source maps are enabled, and as the location attached to
/// log messages.
class Cursor {
  /// Creates a cursor. [file] and [dir] are file system paths or URIs
  /// (as strings); [path] is the path shown in messages.
  new(this.file, [this.dir, this.path, this.lineno = 1]);

  /// The file under the cursor, if known (a path or a URI).
  final String? file;

  /// The directory of [file], if known (a path or a URI).
  final String? dir;

  /// The document-relative path of [file].
  final String? path;

  /// The 1-based line number under the cursor.
  int lineno;

  /// Advances the line number by [num].
  void advance(int num) {
    lineno += num;
  }

  /// Returns a copy of this cursor.
  Cursor dup() => Cursor(file, dir, path, lineno);

  /// `path: line N` summary of this cursor.
  String get lineInfo => '$path: line $lineno';

  @override
  String toString() => lineInfo;
}

/// Where a line of text was read: its file (a path or a URI, if known), the
/// path shown in messages, its 1-based line, and the 0-based column its text
/// starts at in that line (after a list marker or a description-list term).
typedef LineOrigin = ({String? file, String path, int line, int column});
