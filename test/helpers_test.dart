/// Port of `test/helpers_test.rb`.
library;

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

/// Stand-in for a namespaced application class (cf. `Asciidoctor::Document`).
class TestDocument;

void main() {
  group('Helpers', () {
    group('URI Encoding', () {
      test('should URI encode non-word characters generally', () {
        const given = r' !*/%&?\=';
        const expected = '%20%21%2A%2F%25%26%3F%5C%3D';
        expect(Helpers.encodeUriComponent(given), equals(expected));
      });

      test('should not URI encode select non-word characters', () {
        const given = '-.';
        expect(Helpers.encodeUriComponent(given), equals(given));
        expect(Helpers.encodeUriComponent('~'), equals('~'));
      });
    });

    group('URIs and Paths', () {
      test('rootname should return file name without extension', () {
        expect(Helpers.rootname('main.adoc'), equals('main'));
        expect(Helpers.rootname('docs/main.adoc'), equals('docs/main'));
      });

      test('rootname should file name if it has no extension', () {
        expect(Helpers.rootname('main'), equals('main'));
        expect(Helpers.rootname('docs/main'), equals('docs/main'));
      });

      test('rootname should ignore dot not in last segment', () {
        expect(Helpers.rootname('include.d/main'), equals('include.d/main'));
        expect(
          Helpers.rootname('include.d/main.adoc'),
          equals('include.d/main'),
        );
      });

      test('hasExtname should return whether path contains an extname', () {
        expect(Helpers.hasExtname('document.adoc'), isTrue);
        expect(Helpers.hasExtname('path/to/document.adoc'), isTrue);
        expect(Helpers.hasExtname('basename'), isFalse);
        expect(Helpers.hasExtname('include.d/basename'), isFalse);
      });

      test('uriSniffRx should detect URIs', () {
        expect(uriSniffRx.hasMatch('http://example.com'), isTrue);
        expect(uriSniffRx.hasMatch('https://example.com'), isTrue);
        expect(
          uriSniffRx.hasMatch(
            'data:image/gif;base64,R0lGODlhAQABAIAAAAUEBAAAACwAAAAAAQABAAACAkQBADs=',
          ),
          isTrue,
        );
      });

      test(
        'uriSniffRx should not detect an absolute Windows path as a URI',
        () {
          expect(uriSniffRx.hasMatch('c:/sample.adoc'), isFalse);
          expect(uriSniffRx.hasMatch(r'c:\sample.adoc'), isFalse);
        },
      );

      test('isUriish should detect a classloader path as a URI', () {
        // Ruby skips the classloader exclusion outside JRuby; Dart has no
        // JRuby, so the sniff always applies.
        const input = 'uri:classloader:/sample.png';
        expect(uriSniffRx.hasMatch(input), isTrue);
        expect(Helpers.isUriish(input), isTrue);
      });

      test(
        'uriSniffRx should not detect URI that does not start on first line',
        () {
          expect(uriSniffRx.hasMatch('text\nhttps://example.org'), isFalse);
        },
      );
    });

    group('Require Library', () {});

    group('Roman Numeral Conversion', () {
      test('should convert integer to roman numeral', () {
        expect(Helpers.intToRoman(1), equals('I'));
        expect(Helpers.intToRoman(4), equals('IV'));
        expect(Helpers.intToRoman(64), equals('LXIV'));
      });
    });
  });
}
