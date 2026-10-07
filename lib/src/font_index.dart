/// The fonts installed on the machine, found by file name or by family
/// and style, for the backends that set text in fonts of their own (PDF,
/// EPUB) and for `asciidart doctor`.
///
/// The folders searched are those of `ASCIIDART_FONT_PATH` (separated as
/// `PATH` is), then the user's and the system's font folders. Each font
/// file's family, style, weight and width come from its `name` and `OS/2`
/// tables, read without loading the font, and are kept in a cache file
/// (by path, size and modification time) so that later runs only look at
/// what changed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:asciidart/src/io.dart' as io;
import 'package:meta/meta.dart';

/// A font found in the font folders (one font of a file: a collection
/// holds several).
@immutable
final class InstalledFont {
  /// A font of the file at [path] (the [index]th of a collection).
  const new({
    required this.path,
    required this.index,
    required this.family,
    required this.legacyFamily,
    required this.subfamily,
    required this.weight,
    required this.width,
    required this.italic,
  });

  /// The font file.
  final String path;

  /// The font's place in its collection (0 for a single font).
  final int index;

  /// The family: the typographic family when the font names one (`Noto
  /// Serif`, where its legacy family may be `Noto Serif Light`).
  final String family;

  /// The legacy family (name 1), which a family lookup also matches.
  final String legacyFamily;

  /// The style name (`Regular`, `Bold Italic`).
  final String subfamily;

  /// The weight class (400 regular, 700 bold).
  final int weight;

  /// The width class (5 normal; less is condensed, more expanded).
  final int width;

  /// Whether the font is italic or oblique.
  final bool italic;

  /// Whether the font is bold (a weight of 600 or more).
  bool get bold => weight >= 600;

  /// The file's name, without its folder.
  String get fileName => _baseName(path);
}

/// The font files of a list of folders, by file name, and their fonts by
/// family and style.
final class FontIndex {
  /// The fonts in [directories] (searched in order, with their
  /// subfolders), their headers cached in [cacheFile] when given.
  new(this.directories, {this.cacheFile});

  /// The machine's fonts: `ASCIIDART_FONT_PATH`'s folders, then
  /// [extraDirectories], then the user's and the system's font folders.
  new machine()
    : this([
        ...fontPath,
        ...extraDirectories,
        ...io.fontDirectories,
      ], cacheFile: _defaultCacheFile());

  /// The folders searched, in order.
  final List<String> directories;

  /// Where the fonts' names and styles are kept between runs.
  final String? cacheFile;

  /// The installed fonts: `ASCIIDART_FONT_PATH`'s folders, then
  /// [extraDirectories], then the user's and the system's font folders.
  /// The installed fonts ([FontIndex.machine]), looked at once per process.
  // (One index for the process, built when first needed.)
  // ignore: prefer_constructors_over_static_methods
  static FontIndex get installed => _installed ??= FontIndex.machine();
  static FontIndex? _installed;

  /// Replaces the installed fonts (null: the folders again).
  @visibleForTesting
  static set installed(FontIndex? index) => _installed = index;

  /// Folders searched before the user's and the system's (the tests and
  /// tools point it at the fonts vendored with asciidoctor-pdf).
  static List<String> get extraDirectories => _extraDirectories;
  static set extraDirectories(List<String> directories) {
    _extraDirectories = directories;
    _installed = null;
  }

  static List<String> _extraDirectories = const [];

  /// The folders of `ASCIIDART_FONT_PATH`.
  static List<String> get fontPath => [
    for (final dir in (io.environment['ASCIIDART_FONT_PATH'] ?? '').split(
      io.isWindows ? ';' : ':',
    ))
      if (dir.isNotEmpty) dir,
  ];

  static String? _defaultCacheFile() {
    try {
      return '${io.cacheDirectory}/asciidart/font-index.tsv';
      // No cache folder (JavaScript): no cache.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  List<String>? _files;
  List<InstalledFont>? _fonts;

  /// The font files, folder by folder, in order.
  List<String> get files => _files ??= _walk();

  /// The first font file named [name] (any case).
  String? fileNamed(String name) {
    final lower = name.toLowerCase();
    for (final file in files) {
      if (_baseName(file).toLowerCase() == lower) return file;
    }
    return null;
  }

  /// Every font of every file.
  List<InstalledFont> get fonts => _fonts ??= _read();

  /// Whether a font of [family] (any case) is installed.
  bool hasFamily(String family) {
    final wanted = _key(family);
    return fonts.any(
      (font) =>
          _key(font.family) == wanted || _key(font.legacyFamily) == wanted,
    );
  }

  /// The font of [family] (any case) nearest to [bold] and [italic]: the
  /// italic ones first when [italic], then the normal width, then the
  /// nearest weight (700 for bold, 400 otherwise); null when no font of
  /// the family is installed. The font found may lack the style asked for
  /// (see [InstalledFont.bold] and [InstalledFont.italic]).
  InstalledFont? find(String family, {bool bold = false, bool italic = false}) {
    final wanted = _key(family);
    final target = bold ? 700 : 400;
    InstalledFont? best;
    var bestScore = 1 << 30;
    for (final font in fonts) {
      if (_key(font.family) != wanted && _key(font.legacyFamily) != wanted) {
        continue;
      }
      final score =
          (font.italic == italic ? 0 : 100000) +
          (font.width - 5).abs() * 1000 +
          (font.weight - target).abs();
      if (score < bestScore) {
        best = font;
        bestScore = score;
      }
    }
    return best;
  }

  static String _key(String family) =>
      family.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _extensions = {'.ttf', '.otf', '.ttc', '.otc'};

  List<String> _walk() {
    final found = <String>[];
    final seen = <String>{};
    void visit(String dir, int depth) {
      if (depth > 8 || !seen.add(dir)) return;
      final List<io.DirectoryEntry> entries;
      try {
        entries = io.listDirectory(dir)
          ..sort((a, b) => a.name.compareTo(b.name));
      } on Exception {
        return;
      }
      for (final entry in entries) {
        if (entry.isDirectory) {
          visit(entry.path, depth + 1);
        } else if (entry.isFile) {
          final dot = entry.name.lastIndexOf('.');
          if (dot >= 0 &&
              _extensions.contains(entry.name.substring(dot).toLowerCase())) {
            found.add(entry.path);
          }
        }
      }
    }

    for (final dir in directories) {
      if (io.isDirectory(dir)) visit(dir, 0);
    }
    return found;
  }

  List<InstalledFont> _read() {
    final cached = _readCache();
    final lines = <String>[];
    final fonts = <InstalledFont>[];
    var changed = false;
    for (final path in files) {
      final int size;
      final int modified;
      try {
        size = io.fileSize(path);
        modified = io.modificationTime(path).millisecondsSinceEpoch;
      } on Exception {
        continue;
      }
      final stamp = '$path\t$size\t$modified';
      var entries = cached[stamp];
      if (entries == null) {
        changed = true;
        entries = [
          for (final font in _parse(path))
            [
              stamp,
              font.index,
              _clean(font.family),
              _clean(font.legacyFamily),
              _clean(font.subfamily),
              font.weight,
              font.width,
              if (font.italic) 1 else 0,
            ].join('\t'),
        ];
      }
      for (final line in entries) {
        lines.add(line);
        if (_fromLine(line) case final font?) fonts.add(font);
      }
    }
    if (changed || cached.length != files.length) _writeCache(lines);
    return fonts;
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'[\t\r\n]'), ' ');

  static InstalledFont? _fromLine(String line) {
    final f = line.split('\t');
    if (f.length != 10) return null;
    return InstalledFont(
      path: f[0],
      index: int.tryParse(f[3]) ?? 0,
      family: f[4],
      legacyFamily: f[5],
      subfamily: f[6],
      weight: int.tryParse(f[7]) ?? 400,
      width: int.tryParse(f[8]) ?? 5,
      italic: f[9] == '1',
    );
  }

  /// The cached lines, by `path\tsize\tmodified`.
  Map<String, List<String>> _readCache() {
    final file = cacheFile;
    final out = <String, List<String>>{};
    if (file == null) return out;
    try {
      if (!io.isFile(file)) return out;
      final text = utf8.decode(io.readBytes(file), allowMalformed: true);
      for (final line in const LineSplitter().convert(text)) {
        final f = line.split('\t');
        if (f.length != 10) continue;
        (out['${f[0]}\t${f[1]}\t${f[2]}'] ??= []).add(line);
      }
    } on Exception {
      // An unreadable cache is rebuilt.
    }
    return out;
  }

  void _writeCache(List<String> lines) {
    final file = cacheFile;
    if (file == null) return;
    try {
      final slash = file.lastIndexOf(RegExp(r'[/\\]'));
      if (slash > 0) io.createDirectories(file.substring(0, slash));
      io.writeString(file, lines.isEmpty ? '' : '${lines.join('\n')}\n');
    } on Exception {
      // Not cached, then.
    }
  }

  /// The fonts of the file at [path], read from its headers.
  static List<InstalledFont> _parse(String path) {
    try {
      final header = _bytes(path, 0, 12);
      if (header.length < 12) return const [];
      final offsets = <int>[];
      if (_tag(header, 0) == 'ttcf') {
        final count = _u32(header, 8).clamp(0, 256);
        final table = _bytes(path, 12, 4 * count);
        for (var i = 0; i + 4 <= table.length; i += 4) {
          offsets.add(_u32(table, i));
        }
      } else {
        offsets.add(0);
      }
      return [
        for (final (index, offset) in offsets.indexed)
          ?_parseFont(path, index, offset),
      ];
    } on Exception {
      return const [];
    }
  }

  static InstalledFont? _parseFont(String path, int index, int offset) {
    final head = _bytes(path, offset, 12);
    if (head.length < 12) return null;
    final version = _u32(head, 0);
    if (version != 0x00010000 &&
        version != 0x4f54544f && // OTTO
        version != 0x74727565) {
      // true
      return null;
    }
    final count = _u16(head, 4);
    final records = _bytes(path, offset + 12, 16 * count);
    Uint8List? table(String tag) {
      for (var i = 0; i + 16 <= records.length; i += 16) {
        if (_tag(records, i) == tag) {
          return _bytes(path, _u32(records, i + 8), _u32(records, i + 12));
        }
      }
      return null;
    }

    final names = table('name');
    if (names == null) return null;
    final legacy = _name(names, 1);
    if (legacy == null) return null;
    final subfamily = _name(names, 17) ?? _name(names, 2) ?? 'Regular';
    var weight = 400;
    var width = 5;
    var italic = RegExp(
      'italic|oblique',
      caseSensitive: false,
    ).hasMatch(subfamily);
    if (table('OS/2') case final os2? when os2.length >= 64) {
      weight = _u16(os2, 4);
      width = _u16(os2, 6);
      final selection = _u16(os2, 62);
      italic = italic || selection & 0x0001 != 0 || selection & 0x0200 != 0;
    }
    return InstalledFont(
      path: path,
      index: index,
      family: _name(names, 16) ?? legacy,
      legacyFamily: legacy,
      subfamily: subfamily,
      weight: weight,
      width: width,
      italic: italic,
    );
  }

  /// Name [id] of a `name` table: the Windows English one first, then any
  /// Unicode one, then a Macintosh one.
  static String? _name(Uint8List table, int id) {
    if (table.length < 6) return null;
    final count = _u16(table, 2);
    final strings = _u16(table, 4);
    String? unicode;
    String? mac;
    for (var i = 0; i < count; i++) {
      final record = 6 + 12 * i;
      if (record + 12 > table.length) break;
      if (_u16(table, record + 6) != id) continue;
      final platform = _u16(table, record);
      final language = _u16(table, record + 4);
      final length = _u16(table, record + 8);
      final start = strings + _u16(table, record + 10);
      if (start + length > table.length) continue;
      final raw = Uint8List.sublistView(table, start, start + length);
      if (platform == 3 || platform == 0) {
        final text = String.fromCharCodes([
          for (var k = 0; k + 1 < raw.length; k += 2)
            (raw[k] << 8) | raw[k + 1],
        ]);
        if (platform == 3 && language == 0x409) return text;
        unicode ??= text;
      } else if (platform == 1) {
        mac ??= latin1.decode(raw);
      }
    }
    return unicode ?? mac;
  }

  static Uint8List _bytes(String path, int offset, int length) => length <= 0
      ? Uint8List(0)
      : Uint8List.fromList(io.readFileRange(path, offset, length));

  static int _u16(Uint8List b, int at) =>
      at + 2 > b.length ? 0 : (b[at] << 8) | b[at + 1];

  static int _u32(Uint8List b, int at) => at + 4 > b.length
      ? 0
      : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static String _tag(Uint8List b, int at) =>
      at + 4 > b.length ? '' : String.fromCharCodes(b.sublist(at, at + 4));
}

String _baseName(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? path : path.substring(slash + 1);
}
