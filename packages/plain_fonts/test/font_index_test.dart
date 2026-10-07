// The font index: font files found by name and by family and style, their
// headers cached, WOFF fonts decoded, fonts given as bytes, and the
// platform's folders (or files an embedder gives).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fonts/fonts.dart';
import 'package:test/test.dart';

/// Files in memory, for an index that reads no disk.
final class _MemoryFiles implements FontFiles {
  new(this.files);

  final Map<String, List<int>> files;
  final Map<String, String> written = {};

  @override
  List<String> get fontDirectories => const ['/fonts'];

  @override
  String? get cacheDirectory => null;

  @override
  bool isDirectory(String path) =>
      files.keys.any((file) => file.startsWith('$path/'));

  @override
  List<FontFolderEntry> list(String directory) => [
    for (final path in files.keys)
      if (path.startsWith('$directory/') &&
          !path.substring(directory.length + 1).contains('/'))
        (
          path: path,
          name: path.substring(directory.length + 1),
          isDirectory: false,
          isFile: true,
        ),
  ];

  @override
  ({int size, DateTime modified}) stat(String path) =>
      (size: files[path]!.length, modified: DateTime(2026));

  @override
  List<int> read(String path) =>
      files[path] ??
      (written[path] != null
          ? utf8.encode(written[path]!)
          : throw FontFilesException('missing', path));

  @override
  List<int> readRange(String path, int offset, int length) {
    final data = files[path]!;
    return data.sublist(
      offset.clamp(0, data.length),
      (offset + length).clamp(0, data.length),
    );
  }

  @override
  void write(String path, String contents) => written[path] = contents;
}

Uint8List _font(String name) => File('test/fonts/$name').readAsBytesSync();

void main() {
  late Directory tmp;
  late String dir;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('font_index_test.');
    dir = '${tmp.path}/fonts';
    Directory('$dir/sub').createSync(recursive: true);
    for (final (name, to) in [
      ('notoserif-regular-latin.ttf', 'NotoSerif-Regular.ttf'),
      ('mplus1p-regular-multilingual.ttf', 'sub/mplus1p.ttf'),
      ('libertinus-smcp.otf', 'Libertinus.otf'),
      ('notoserif-features.woff2', 'web/Features.woff2'),
    ]) {
      File('$dir/$to')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(_font(name));
    }
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  FontIndex index([List<String>? dirs]) =>
      FontIndex(dirs ?? [dir], cacheFile: '${tmp.path}/cache/fonts.tsv');

  String? slashed(String? path) => path?.replaceAll(r'\', '/');

  test('finds font files by name, in any case, through subfolders', () {
    final fonts = index();
    expect(slashed(fonts.fileNamed('MPLUS1P.TTF')), '$dir/sub/mplus1p.ttf');
    expect(fonts.fileNamed('nothing.ttf'), isNull);
  });

  test('finds a family in the style nearest the one asked for', () {
    final fonts = index();
    expect(fonts.find('noto  serif')?.fileName, 'NotoSerif-Regular.ttf');
    expect(fonts.find('Libertinus Serif')?.fileName, 'Libertinus.otf');
    final nearest = fonts.find('M+ 1p', bold: true, italic: true)!;
    expect(nearest.fileName, 'mplus1p.ttf');
    expect((nearest.bold, nearest.italic), (false, false));
    expect(fonts.hasFamily('m+ 1P'), isTrue);
    expect(fonts.find('No Such Family'), isNull);
  });

  test('reads WOFF2 fonts, and gives the fonts they wrap', () {
    final fonts = index();
    final web = fonts.fonts.firstWhere((f) => f.fileName == 'Features.woff2');
    expect(web.family, 'Noto Serif');
    expect(fonts.fontBytes(web.path).take(4), [0, 1, 0, 0]);
    expect(FontIndex.familyOf(_font('notoserif-features.woff')), 'Noto Serif');
    expect(FontIndex.familyOf(utf8.encode('not a font')), isNull);
    expect(FontIndex.decodesWebFonts, isTrue);
  });

  test('keeps what it read in its cache, and rereads what changed', () {
    final copy = Directory('${tmp.path}/copy')..createSync();
    File('$dir/Libertinus.otf').copySync('${copy.path}/a.otf');
    expect(index([copy.path]).find('Libertinus Serif')?.fileName, 'a.otf');
    final cache = File('${tmp.path}/cache/fonts.tsv');
    expect(cache.readAsLinesSync(), hasLength(1));
    // Another font under the same name: the cache entry no longer matches.
    File('$dir/NotoSerif-Regular.ttf').copySync('${copy.path}/a.otf');
    final fonts = index([copy.path]);
    expect(fonts.find('Noto Serif')?.fileName, 'a.otf');
    expect(fonts.find('Libertinus Serif'), isNull);
    expect(cache.readAsStringSync(), contains('Noto Serif'));
  });

  test('skips folders that are missing and files that are not fonts', () {
    File('$dir/broken.ttf').writeAsStringSync('not a font');
    final fonts = index(['${tmp.path}/missing', dir]);
    expect(fonts.files.map(slashed), contains('$dir/broken.ttf'));
    expect(fonts.fonts.where((f) => f.fileName == 'broken.ttf'), isEmpty);
    expect(fonts.hasFamily('Noto Serif'), isTrue);
  });

  test('fonts given as bytes come first', () {
    final fonts = FontIndex(
      [dir],
      memory: {'Mine.otf': _font('libertinus-smcp.otf')},
    );
    final mine = fonts.find('Libertinus Serif')!;
    expect(mine.path, 'memory:/Mine.otf');
    expect(fonts.isInMemory(mine.path), isTrue);
    expect(fonts.bytes(mine.path), _font('libertinus-smcp.otf'));
    expect(fonts.fileNamed('mine.otf'), 'memory:/Mine.otf');
  });

  test('reads the files an embedder gives', () {
    final files = _MemoryFiles({
      '/fonts/Serif.ttf': _font('notoserif-regular-latin.ttf'),
      '/fonts/readme.txt': utf8.encode('hello'),
    });
    final fonts = FontIndex.system(
      cacheFile: '/cache/fonts.tsv',
      fileSystem: files,
    );
    expect(fonts.directories, ['/fonts']);
    expect(fonts.find('Noto Serif')?.path, '/fonts/Serif.ttf');
    expect(files.written['/cache/fonts.tsv'], contains('Noto Serif'));
  });

  test("each platform's font and cache folders", () {
    const env = {'HOME': '/home/me', 'XDG_DATA_DIRS': '/usr/share'};
    expect(fontDirectoriesFor(FontPlatform.linux, env), [
      '/home/me/.local/share/fonts',
      '/home/me/.fonts',
      '/usr/share/fonts',
    ]);
    expect(
      fontDirectoriesFor(FontPlatform.macos, env).first,
      '/home/me/Library/Fonts',
    );
    expect(
      fontDirectoriesFor(FontPlatform.windows, const {
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        'WINDIR': r'C:\Windows',
      }),
      [
        r'C:\Users\me\AppData\Local\Microsoft\Windows\Fonts',
        r'C:\Windows\Fonts',
      ],
    );
    expect(cacheDirectoryFor(FontPlatform.linux, env), '/home/me/.cache');
    expect(FontFiles.platform.fontDirectories, isNotEmpty);
  });
}
