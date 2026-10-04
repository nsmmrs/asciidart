/// Tests for the embedded `data/` files and the [Stylesheets] helper.
///
/// The byte-for-byte tests guard the `tool/embed_data.dart` contract: every
/// value in [EmbeddedData.files] must round-trip to the exact bytes of its
/// source file under the repository `data/` directory.
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidoctor/src/data.g.dart';
import 'package:asciidoctor/src/stylesheets.dart';
import 'package:test/test.dart';

/// Reads the repository `data/` file at [relativePath].
///
/// Tests run with the package root (`dart/`) as the working directory.
List<int> readDataFile(String relativePath) =>
    File('${Directory.current.path}/data/$relativePath').readAsBytesSync();

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
          'stylesheets/asciidoctor-default.css',
          'stylesheets/coderay-asciidoctor.css',
        ]),
      );
      expect(keys, hasLength(39));
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

    test('primary stylesheet data is the embedded file rstripped', () {
      final raw = utf8.decode(
        readDataFile('stylesheets/asciidoctor-default.css'),
      );
      expect(raw, endsWith('\n'));
      expect(stylesheets.primaryStylesheetData, equals(rstrip(raw)));
      expect(stylesheets.primaryStylesheetData, isNot(endsWith('\n')));
    });

    test('write primary stylesheet writes exact data', () {
      stylesheets.writePrimaryStylesheet(tempDir.path);
      final written = File('${tempDir.path}/asciidoctor.css')
          .readAsStringSync();
      expect(written, equals(stylesheets.primaryStylesheetData));
    });

    test('coderay stylesheet name', () {
      expect(
        stylesheets.coderayStylesheetName,
        equals('coderay-asciidoctor.css'),
      );
    });

    test('coderay stylesheet data is the embedded file rstripped', () {
      final raw = utf8.decode(
        readDataFile('stylesheets/coderay-asciidoctor.css'),
      );
      expect(raw, endsWith('\n'));
      expect(stylesheets.coderayStylesheetData, equals(rstrip(raw)));
    });

    test('write coderay stylesheet writes exact data', () {
      stylesheets.writeCoderayStylesheet(tempDir.path);
      final written = File('${tempDir.path}/coderay-asciidoctor.css')
          .readAsStringSync();
      expect(written, equals(stylesheets.coderayStylesheetData));
    });

    test('pygments stylesheet name defaults to the default style', () {
      expect(
        stylesheets.pygmentsStylesheetName(),
        equals('pygments-default.css'),
      );
      expect(
        stylesheets.pygmentsStylesheetName('monokai'),
        equals('pygments-monokai.css'),
      );
    });

    test('pygments stylesheet data reports the library as unavailable', () {
      // Mirrors the Ruby branch taken when the Pygments library cannot be
      // loaded; the syntax-highlighter port owns the live strategy.
      expect(
        stylesheets.pygmentsStylesheetData(),
        equals(
          '/* Pygments CSS disabled because Pygments is not available. */',
        ),
      );
      expect(
        stylesheets.pygmentsStylesheetData('monokai'),
        equals(stylesheets.pygmentsStylesheetData()),
      );
    });

    test('write pygments stylesheet writes exact data', () {
      stylesheets.writePygmentsStylesheet(tempDir.path, 'monokai');
      final written = File('${tempDir.path}/pygments-monokai.css')
          .readAsStringSync();
      expect(written, equals(stylesheets.pygmentsStylesheetData('monokai')));
    });
  });
}
