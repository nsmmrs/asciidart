@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/font_index.dart';
import 'package:test/test.dart';

/// The fonts vendored with asciidoctor-pdf (subsets of Noto and M+, and
/// prawn-icon's icon fonts).
const _fonts = 'vendor/asciidoctor-pdf/data/fonts';
const _icons = 'vendor/asciidoctor-pdf/icons';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('font_index_test.'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// [path] with `/` between its parts (Windows lists them with `\`).
  String? slashed(String? path) => path?.replaceAll(r'\', '/');

  FontIndex index([List<String> dirs = const [_fonts, _icons]]) =>
      FontIndex(dirs, cacheFile: '${tmp.path}/cache/fonts.tsv');

  test('finds font files by name, in any case, through subfolders', () {
    final fonts = index();
    expect(
      slashed(fonts.fileNamed('NotoSerif-Regular-Subset.TTF')),
      '$_fonts/notoserif-regular-subset.ttf',
    );
    expect(
      slashed(fonts.fileNamed('fa-solid.ttf')),
      '$_icons/fas/fa-solid.ttf',
    );
    expect(fonts.fileNamed('nothing.ttf'), isNull);
  });

  test('finds a family in the style nearest the one asked for', () {
    final fonts = index();
    expect(fonts.find('noto  serif')?.fileName, 'notoserif-regular-subset.ttf');
    expect(
      fonts.find('Noto Serif', bold: true, italic: true)?.fileName,
      'notoserif-bold_italic-subset.ttf',
    );
    expect(
      fonts.find('Noto Sans', bold: true)?.fileName,
      'notosans-bold-subset.ttf',
    );
    // M+ 1p has only its regular face: it is the nearest to a bold italic.
    final fallback = fonts.find('M+ 1p', bold: true, italic: true)!;
    expect(fallback.fileName, 'mplus1p-regular-fallback.ttf');
    expect((fallback.bold, fallback.italic), (false, false));
    expect(fonts.hasFamily('Noto Emoji'), isTrue);
    expect(fonts.find('No Such Family'), isNull);
  });

  test('matches the legacy family too, and reads weights', () {
    final solid = index().find('Font Awesome 5 Free Solid')!;
    expect(solid.family, 'Font Awesome 5 Free');
    expect(solid.weight, 900);
    expect(solid.bold, isTrue);
  });

  test('keeps what it read in its cache, and rereads what changed', () {
    final copy = Directory('${tmp.path}/fonts')..createSync();
    File('$_fonts/notosans-regular-subset.ttf').copySync('${copy.path}/a.ttf');
    expect(index([copy.path]).find('Noto Sans')?.fileName, 'a.ttf');
    final cache = File('${tmp.path}/cache/fonts.tsv');
    expect(cache.readAsLinesSync(), hasLength(1));
    // Another font under the same name: the cache entry no longer matches.
    File('$_fonts/notoserif-regular-subset.ttf').copySync('${copy.path}/a.ttf');
    final fonts = index([copy.path]);
    expect(fonts.find('Noto Serif')?.fileName, 'a.ttf');
    expect(fonts.find('Noto Sans'), isNull);
    expect(cache.readAsStringSync(), contains('Noto Serif'));
  });

  test('reads WOFF and WOFF2 fonts, and decodes them', () {
    final fonts = index(['test/fixtures/fonts']);
    final regular = fonts.find('Noto Serif')!;
    expect(regular.fileName, 'notoserif-regular-ascii.woff2');
    final bold = fonts.find('Noto Serif', bold: true)!;
    expect(bold.fileName, 'notoserif-bold-ascii.woff');
    expect((bold.bold, bold.italic), (true, false));
    // The cache keeps them like any font.
    expect(
      File('${tmp.path}/cache/fonts.tsv').readAsStringSync(),
      contains('notoserif-bold-ascii.woff\t'),
    );
    expect(index(['test/fixtures/fonts']).find('Noto Serif'), isNotNull);
    // The font they wrap: a TrueType font.
    expect(fonts.fontBytes(regular.path).take(4), [0, 1, 0, 0]);
    expect(
      FontIndex.familyOf(
        File('test/fixtures/fonts/notoserif-bold-ascii.woff').readAsBytesSync(),
      ),
      'Noto Serif',
    );
  });

  test('skips folders that are missing and files that are not fonts', () {
    final dir = Directory('${tmp.path}/odd')..createSync();
    File('${dir.path}/broken.ttf').writeAsStringSync('not a font');
    final fonts = index(['${tmp.path}/missing', dir.path, _fonts]);
    expect(
      fonts.files.map(slashed),
      contains(slashed('${dir.path}/broken.ttf')),
    );
    expect(fonts.fonts.where((f) => f.fileName == 'broken.ttf'), isEmpty);
    expect(fonts.hasFamily('Noto Serif'), isTrue);
  });
}
