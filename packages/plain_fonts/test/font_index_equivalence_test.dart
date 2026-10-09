// The font index against a frozen copy of its code from before the
// performance work (test/frozen/font_index.dart): the same files, fonts,
// cache files and answers, on the test fonts and, when the machine has
// them, the fonts in /usr/share/fonts.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

import 'frozen/font_index.dart' as frozen;

String _describe(
  String path,
  int index,
  String family,
  String legacyFamily,
  String subfamily,
  int weight,
  int width,
  bool italic,
) =>
    '$path#$index $family/$legacyFamily/$subfamily '
    '$weight $width $italic';

String _new(InstalledFont? f) => f == null
    ? 'none'
    : _describe(
        f.path,
        f.index,
        f.family,
        f.legacyFamily,
        f.subfamily,
        f.weight,
        f.width,
        f.italic,
      );

String _old(frozen.InstalledFont? f) => f == null
    ? 'none'
    : _describe(
        f.path,
        f.index,
        f.family,
        f.legacyFamily,
        f.subfamily,
        f.weight,
        f.width,
        f.italic,
      );

void _expectSameIndex(FontIndex index, frozen.FontIndex old) {
  expect(index.files, old.files);
  expect(index.fonts.map(_new).toList(), old.fonts.map(_old).toList());
  expect(index.passedOverWebFonts, old.passedOverWebFonts);
  final names = {
    for (final f in old.fonts) ...[
      f.family,
      f.legacyFamily,
      f.family.toUpperCase(),
      ' ${f.legacyFamily.replaceAll(' ', '  ')}\t',
    ],
    'no such family',
    '',
  };
  for (final name in names) {
    expect(index.hasFamily(name), old.hasFamily(name), reason: name);
    for (final bold in [false, true]) {
      for (final italic in [false, true]) {
        expect(
          _new(index.find(name, bold: bold, italic: italic)),
          _old(old.find(name, bold: bold, italic: italic)),
          reason: '$name $bold $italic',
        );
      }
    }
  }
  final files = {
    for (final f in old.files) ...[
      f.split('/').last,
      f.split('/').last.toUpperCase(),
    ],
    'none.ttf',
  };
  for (final name in files) {
    expect(index.fileNamed(name), old.fileNamed(name), reason: name);
  }
}

void main() {
  final roots = [
    'test/fonts',
    if (Directory('/usr/share/fonts').existsSync()) '/usr/share/fonts',
  ];
  for (final root in roots) {
    test('$root: the same index, cached or not', () {
      final temp = Directory.systemTemp.createTempSync('font-index-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final memory = {
        'one.ttf': File('test/fonts/notoserif-features.ttf').readAsBytesSync(),
      };
      for (var run = 0; run < 2; run++) {
        final index = FontIndex(
          [root],
          cacheFile: '${temp.path}/new.tsv',
          memory: memory,
        );
        final old = frozen.FontIndex(
          [root],
          cacheFile: '${temp.path}/old.tsv',
          memory: memory,
        );
        _expectSameIndex(index, old);
        expect(
          File('${temp.path}/new.tsv').readAsStringSync(),
          File('${temp.path}/old.tsv').readAsStringSync(),
        );
      }
      _expectSameIndex(FontIndex([root]), frozen.FontIndex([root]));
    }, timeout: const Timeout.factor(10));
  }

  test('cut and damaged font files: the same index', () {
    final temp = Directory.systemTemp.createTempSync('font-index-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final random = Random(5);
    final sources = [
      for (final file in Directory('test/fonts').listSync().whereType<File>())
        if (!file.path.endsWith('.md')) file,
    ];
    for (var i = 0; i < 120; i++) {
      final source = sources[i % sources.length];
      final bytes = source.readAsBytesSync();
      final copy = Uint8List.fromList(bytes);
      for (var k = 0; k < random.nextInt(4); k++) {
        copy[random.nextInt(min(copy.length, 600))] = random.nextInt(256);
      }
      final cut = switch (i % 4) {
        0 => copy.length,
        1 => random.nextInt(min(copy.length, 5000)),
        _ => random.nextInt(copy.length),
      };
      File('${temp.path}/$i-${source.uri.pathSegments.last}')
          .writeAsBytesSync(Uint8List.sublistView(copy, 0, cut));
    }
    _expectSameIndex(FontIndex([temp.path]), frozen.FontIndex([temp.path]));
  });

  test('familyOf', () {
    for (final file in Directory('test/fonts').listSync().whereType<File>()) {
      final bytes = file.readAsBytesSync();
      expect(
        FontIndex.familyOf(bytes),
        frozen.FontIndex.familyOf(bytes),
        reason: file.path,
      );
    }
  });
}
