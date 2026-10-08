/// Tests for the embedded `data/` files and the [Stylesheets] helper.
///
/// The byte-for-byte tests guard the `tool/embed_data.dart` contract: every
/// value in [EmbeddedData.files] must round-trip to the exact bytes of its
/// source file under the repository `data/` directory.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

/// Reads the repository `data/` file at [relativePath].
///
/// Tests run with the package root (`dart/`) as the working directory.
/// Ptome's own files (`data/`, the house stylesheet) before
/// Asciidoctor's (`vendor/asciidoctor/data/`).
List<int> readDataFile(String relativePath) {
  final own = File('${Directory.current.path}/data/$relativePath');
  return (own.existsSync()
          ? own
          : File(
              '${Directory.current.path}/vendor/asciidoctor/data/$relativePath',
            ))
      .readAsBytesSync();
}

/// Mirrors Ruby's `String#rstrip` for building expectations independently of
/// the helper under test.
String rstrip(String value) =>
    value.replaceAll(RegExp('[\x00 \t\n\v\f\r]+\$'), '');

void main() {
  group('EmbeddedData', () {
    test('embeds all locale attributes and stylesheets', () {
      final keys = EmbeddedData.files.keys.toList()..sort();
      expect(keys.where((key) => key.startsWith('locale/')), hasLength(37));
      expect(
        keys.where((key) => key.startsWith('stylesheets/')),
        orderedEquals([
          'stylesheets/ptome-epub3-house.css',
          'stylesheets/ptome-house.css',
          'stylesheets/asciidoctor-default.css',
          'stylesheets/coderay-asciidoctor.css',
        ]),
      );
      expect(keys, hasLength(41));
    });

    test('embedded bytes equal the data files byte-for-byte', () {
      expect(EmbeddedData.files, isNotEmpty);
      for (final MapEntry(:key, value: content) in EmbeddedData.files.entries) {
        expect(
          utf8.encode(content),
          orderedEquals(readDataFile(key)),
          reason: 'embedded `$key` must match data/$key byte-for-byte',
        );
      }
    });

    test('file() looks up embedded content by relative path', () {
      expect(
        EmbeddedData.file('locale/attributes-en.adoc'),
        equals(EmbeddedData.files['locale/attributes-en.adoc']),
      );
    });
  });

  group('Stylesheets', () {
    late Stylesheets stylesheets;
    late Directory tempDir;

    setUp(() {
      stylesheets = Stylesheets();
      tempDir = Directory.systemTemp.createTempSync('asciidoctor-stylesheets');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('instance returns the shared instance', () {
      expect(Stylesheets.instance, same(Stylesheets.instance));
    });

    test('primary stylesheet name', () {
      expect(stylesheets.primaryStylesheetName, equals('asciidoctor.css'));
      expect(Stylesheets.defaultStylesheetName, equals('asciidoctor.css'));
    });

    test('the classic stylesheet is the embedded file rstripped', () {
      final raw = utf8.decode(
        readDataFile('stylesheets/asciidoctor-default.css'),
      );
      expect(raw, endsWith('\n'));
      expect(stylesheets.classicStylesheetData, equals(rstrip(raw)));
      expect(stylesheets.dataFor('asciidoctor'), equals(rstrip(raw)));
    });

    test('the default stylesheet is the classic one, then the house rules', () {
      final house = utf8.decode(readDataFile('stylesheets/ptome-house.css'));
      expect(
        stylesheets.primaryStylesheetData,
        equals('${stylesheets.classicStylesheetData}\n${rstrip(house)}'),
      );
      expect(stylesheets.dataFor(''), stylesheets.primaryStylesheetData);
      expect(stylesheets.primaryStylesheetData, isNot(endsWith('\n')));
    });

    test('write primary stylesheet writes exact data', () {
      stylesheets.writePrimaryStylesheet(tempDir.path);
      final written = File('${tempDir.path}/asciidoctor.css')
          .readAsStringSync();
      expect(written, equals(stylesheets.primaryStylesheetData));
      stylesheets.writePrimaryStylesheet(tempDir.path, 'asciidoctor');
      expect(
        File('${tempDir.path}/asciidoctor.css').readAsStringSync(),
        equals(stylesheets.classicStylesheetData),
      );
    });
  });
}
