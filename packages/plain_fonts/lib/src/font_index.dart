/// The fonts installed on a machine, found by file name or by family and
/// style.
///
/// A [FontIndex] searches folders (and fonts given as bytes): each font
/// file's family, style, weight and width come from its `name` and `OS/2`
/// tables, read without loading the font, and can be kept in a cache file
/// (by path, size and modification time) so that later runs only look at
/// what changed. WOFF and WOFF2 fonts are decoded to be read (on
/// JavaScript, once [FontIndex.loadWebFontDecoder] has loaded the decoder:
/// until then they are passed over).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_fonts/src/font_files.dart';
import 'package:plain_fonts/src/web_fonts.dart' as web_fonts;

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
  /// subfolders), their headers cached in [cacheFile] when given; the
  /// fonts in [memory] (file names and their bytes) come first.
  new(
    this.directories, {
    this.cacheFile,
    Map<String, List<int>> memory = const {},
    FontFiles? fileSystem,
  }) : fileSystem = fileSystem ?? FontFiles.platform,
       _memory = {
         for (final MapEntry(:key, :value) in memory.entries)
           '$_memoryPrefix$key': value,
       };

  /// The machine's fonts: those of [before], then the user's and the
  /// system's font folders ([FontFiles.fontDirectories]).
  new system({
    List<String> before = const [],
    String? cacheFile,
    Map<String, List<int>> memory = const {},
    FontFiles? fileSystem,
  }) : this(
         [...before, ...(fileSystem ?? FontFiles.platform).fontDirectories],
         cacheFile: cacheFile,
         memory: memory,
         fileSystem: fileSystem,
       );

  /// Where the font files are read.
  final FontFiles fileSystem;

  /// The fonts given as bytes, by their paths (`memory:/name`).
  final Map<String, List<int>> _memory;

  static const String _memoryPrefix = 'memory:/';

  /// The bytes of the font file at [path] (a file, or one given in
  /// memory).
  List<int> bytes(String path) => _memory[path] ?? fileSystem.read(path);

  /// The TrueType or OpenType font at [path]: its [bytes], decoded when
  /// it is a WOFF or WOFF2 font.
  List<int> fontBytes(String path) {
    final data = bytes(path);
    return _isWebFont(data) ? _decodeWebFont(data) : data;
  }

  static bool _isWebFont(List<int> b) =>
      b.length >= 4 &&
      b[0] == 0x77 && // w
      b[1] == 0x4f && // O
      b[2] == 0x46 && // F
      (b[3] == 0x46 || b[3] == 0x32); // F, 2

  static Uint8List _decodeWebFont(List<int> bytes) {
    final decode = web_fonts.webFontDecoder;
    if (decode == null) {
      throw StateError('the WOFF and WOFF2 decoder is not loaded');
    }
    return decode(bytes);
  }

  /// Whether WOFF or WOFF2 files were passed over, the decoder not loaded
  /// (an index built again once it is finds them).
  bool get passedOverWebFonts => _passedOverWebFonts;
  bool _passedOverWebFonts = false;

  /// Loads the WOFF and WOFF2 decoder: on JavaScript, a part of the program
  /// loaded on demand; on the Dart VM it is always there.
  static Future<void> loadWebFontDecoder() => web_fonts.loadWebFontDecoder();

  /// Whether the WOFF and WOFF2 decoder is loaded.
  static bool get decodesWebFonts => web_fonts.webFontDecoder != null;

  /// The family of the (first) font in [bytes], or null when they are not
  /// a font.
  static String? familyOf(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final fonts = _parse('', _rangesOf(data));
    return fonts.isEmpty ? null : fonts.first.family;
  }

  /// Whether the font at [path] was given as bytes.
  bool isInMemory(String path) => _memory.containsKey(path);

  /// The folders searched, in order.
  final List<String> directories;

  /// Where the fonts' names and styles are kept between runs.
  final String? cacheFile;

  List<String>? _files;
  List<InstalledFont>? _fonts;

  /// The font files, folder by folder, in order.
  List<String> get files => _files ??= [..._memory.keys, ..._walk()];

  /// The first font file named [name] (any case).
  String? fileNamed(String name) => _byFileName[name.toLowerCase()];

  /// The first file of each name, by its name in lowercase.
  late final Map<String, String> _byFileName = () {
    final byName = <String, String>{};
    for (final file in files) {
      byName.putIfAbsent(_baseName(file).toLowerCase(), () => file);
    }
    return byName;
  }();

  /// Every font of every file.
  List<InstalledFont> get fonts => _fonts ??= _read();

  /// The fonts of each family key (family or legacy family), in order.
  late final Map<String, List<InstalledFont>> _byFamily = () {
    final byFamily = <String, List<InstalledFont>>{};
    for (final font in fonts) {
      final family = _key(font.family);
      final legacy = _key(font.legacyFamily);
      (byFamily[family] ??= []).add(font);
      if (legacy != family) (byFamily[legacy] ??= []).add(font);
    }
    return byFamily;
  }();

  /// Whether a font of [family] (any case) is installed.
  bool hasFamily(String family) => _byFamily.containsKey(_key(family));

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
    for (final font in _byFamily[wanted] ?? const <InstalledFont>[]) {
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
      family.toLowerCase().replaceAll(_spaces, ' ').trim();

  static final RegExp _spaces = RegExp(r'\s+');

  static const _extensions = {
    '.ttf',
    '.otf',
    '.ttc',
    '.otc',
    '.woff',
    '.woff2',
  };

  static bool _isWebFontFile(String path) => _webFontFile.hasMatch(path);

  static final RegExp _webFontFile = RegExp(r'\.woff2?$', caseSensitive: false);

  List<String> _walk() {
    final found = <String>[];
    final seen = <String>{};
    void visit(String dir, int depth) {
      if (depth > 8 || !seen.add(dir)) return;
      final List<FontFolderEntry> entries;
      try {
        entries = fileSystem.list(dir)
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
      if (fileSystem.isDirectory(dir)) visit(dir, 0);
    }
    return found;
  }

  List<InstalledFont> _read() {
    final cached = _readCache();
    final lines = <String>[];
    final fonts = <InstalledFont>[];
    var changed = false;
    var read = 0;
    final decoding = web_fonts.webFontDecoder != null;
    for (final path in files) {
      if (!decoding && _isWebFontFile(path)) {
        _passedOverWebFonts = true;
        continue;
      }
      if (_memory[path] case final bytes?) {
        final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
        fonts.addAll(_parse(path, _rangesOf(data)));
        continue;
      }
      final int size;
      final int modified;
      try {
        final stat = fileSystem.stat(path);
        size = stat.size;
        modified = stat.modified.millisecondsSinceEpoch;
      } on Exception {
        continue;
      }
      read++;
      final stamp = '$path\t$size\t$modified';
      var entries = cached[stamp];
      if (entries == null) {
        changed = true;
        entries = [
          for (final font in _parse(path, _rangesIn(path)))
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
    if (changed || cached.length != read) _writeCache(lines);
    return fonts;
  }

  static String _clean(String text) => text.replaceAll(_breaks, ' ');

  static final RegExp _breaks = RegExp(r'[\t\r\n]');

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
      final text = utf8.decode(fileSystem.read(file), allowMalformed: true);
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
      fileSystem.write(file, lines.isEmpty ? '' : '${lines.join('\n')}\n');
    } on Exception {
      // Not cached, then.
    }
  }

  /// The fonts of the file at [path], read from its headers.
  static List<InstalledFont> _parse(String path, _Ranges read) {
    try {
      final header = read(0, 12);
      if (header.length < 12) return const [];
      if (_isWebFont(header)) {
        // The tables are compressed: the whole font, decoded.
        if (web_fonts.webFontDecoder == null) return const [];
        final length = _u32(header, 8);
        final decoded = _decodeWebFont(read(0, length));
        return _isWebFont(decoded)
            ? const []
            : _parse(path, _rangesOf(decoded));
      }
      final offsets = <int>[];
      if (_tag(header, 0) == 'ttcf') {
        final count = _u32(header, 8).clamp(0, 256);
        final table = read(12, 4 * count);
        for (var i = 0; i + 4 <= table.length; i += 4) {
          offsets.add(_u32(table, i));
        }
      } else {
        offsets.add(0);
      }
      return [
        for (final (index, offset) in offsets.indexed)
          ?_parseFont(path, read, index, offset),
      ];
    } on Exception {
      return const [];
    }
  }

  static InstalledFont? _parseFont(
    String path,
    _Ranges read,
    int index,
    int offset,
  ) {
    final head = read(offset, 12);
    if (head.length < 12) return null;
    final version = _u32(head, 0);
    if (version != 0x00010000 &&
        version != 0x4f54544f && // OTTO
        version != 0x74727565) {
      // true
      return null;
    }
    final count = _u16(head, 4);
    final records = read(offset + 12, 16 * count);
    int? recordOf(String tag) {
      for (var i = 0; i + 16 <= records.length; i += 16) {
        if (_tag(records, i) == tag) return i;
      }
      return null;
    }

    Uint8List? table(String tag) => switch (recordOf(tag)) {
      final i? => read(_u32(records, i + 8), _u32(records, i + 12)),
      null => null,
    };

    // The name and OS/2 tables, in one read when they are near each
    // other.
    if ((recordOf('name'), recordOf('OS/2')) case (final n?, final o?)) {
      final nameStart = _u32(records, n + 8);
      final os2Start = _u32(records, o + 8);
      final start = min(nameStart, os2Start);
      final end = max(
        nameStart + _u32(records, n + 12),
        os2Start + _u32(records, o + 12),
      );
      read.prefetch(start, end - start);
    }

    final names = table('name');
    if (names == null) return null;
    final legacy = _name(names, 1);
    if (legacy == null) return null;
    final subfamily = _name(names, 17) ?? _name(names, 2) ?? 'Regular';
    var weight = 400;
    var width = 5;
    var italic = _italic.hasMatch(subfamily);
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

  static final RegExp _italic = RegExp('italic|oblique', caseSensitive: false);

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

  /// Reads ranges of the file at [path].
  _Ranges _rangesIn(String path) => _FileRanges(fileSystem, path);

  /// Reads ranges of [data].
  static _Ranges _rangesOf(Uint8List data) => _BytesRanges(data);

  static int _u16(Uint8List b, int at) =>
      at + 2 > b.length ? 0 : (b[at] << 8) | b[at + 1];

  static int _u32(Uint8List b, int at) => at + 4 > b.length
      ? 0
      : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static String _tag(Uint8List b, int at) =>
      at + 4 > b.length ? '' : String.fromCharCodes(b.sublist(at, at + 4));
}

/// Reads ranges of a font file.
sealed class _Ranges {
  /// [length] bytes from [offset] (fewer at the end).
  Uint8List call(int offset, int length);

  /// Reads the range from [offset] for [length] bytes ahead, to give the
  /// ranges inside it without reading again.
  void prefetch(int offset, int length) {}
}

/// The ranges of a file: its first 4 KB (the header and table directory)
/// read once, a range prefetched, the others read as asked.
final class _FileRanges extends _Ranges {
  new(this._files, this._path);

  final FontFiles _files;
  final String _path;
  Uint8List? _head;
  int _windowStart = 0;
  Uint8List? _window;

  static const int _headSize = 4096;

  /// The largest range [prefetch] reads.
  static const int _windowSize = 1 << 16;

  Uint8List _read(int offset, int length) =>
      Uint8List.fromList(_files.readRange(_path, offset, length));

  @override
  Uint8List call(int offset, int length) {
    if (length <= 0) return Uint8List(0);
    final head = _head ??= _read(0, _headSize);
    if (offset >= 0 && offset + length <= head.length) {
      return Uint8List.sublistView(head, offset, offset + length);
    }
    if (_window case final window?) {
      final start = offset - _windowStart;
      if (start >= 0 && start + length <= window.length) {
        return Uint8List.sublistView(window, start, start + length);
      }
    }
    return _read(offset, length);
  }

  @override
  void prefetch(int offset, int length) {
    final head = _head;
    if (length <= 0 || length > _windowSize || offset < 0) return;
    if (head != null && offset + length <= head.length) return;
    try {
      _window = _read(offset, length);
      _windowStart = offset;
    } on Exception {
      // Each range is read as asked, then.
    }
  }
}

/// The ranges of a font given as bytes.
final class _BytesRanges extends _Ranges {
  new(this._data);

  final Uint8List _data;

  @override
  Uint8List call(int offset, int length) {
    final start = offset.clamp(0, _data.length);
    return Uint8List.sublistView(
      _data,
      start,
      (offset + length).clamp(start, _data.length),
    );
  }
}

final RegExp _slash = RegExp(r'[/\\]');

String _baseName(String path) {
  final slash = path.lastIndexOf(_slash);
  return slash < 0 ? path : path.substring(slash + 1);
}
