// Font metrics and widths, against Prawn 2.4's (measured with Prawn
// itself, through asciidoctor-pdf 2.3.27's bundled fonts and Prawn's AFM
// files, at 10.5 points): the metrics the same, the widths within a
// little of them (asciidart shapes with OpenType: GPOS kerning, widths
// not truncated to the unit).
@TestOn('vm')
library;

import 'package:asciidart/src/pdf/fonts.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

void main() {
  final warnings = <String>[];
  late FontCatalog catalog;
  setUpAll(() {
    useVendoredFonts();
    catalog = FontCatalog(ThemeLoader().load(), warn: warnings.add);
  });
  double round(double v) => (v * 1e6).roundToDouble() / 1e6;

  test('ascender, descender, line gap and height', () {
    for (final (family, style, ascender, descender, gap, height) in [
      ('Noto Serif', 'normal', 11.214, 3.066, 0.0, 14.28),
      ('Noto Serif', 'bold', 11.214, 3.066, 0.0, 14.28),
      ('M+ 1mn', 'normal', 9.03, 1.47, 0.945, 11.445),
      ('Helvetica', 'normal', 7.539, 2.1735, 2.4255, 12.138),
    ]) {
      final font = catalog.font(family, style);
      expect(round(font.ascenderAt(10.5)), ascender, reason: family);
      expect(round(font.descenderAt(10.5)), descender, reason: family);
      expect(round(font.lineGapAt(10.5)), gap, reason: family);
      expect(round(font.heightAt(10.5)), height, reason: family);
    }
  });

  test('widths, with and without kerning', () {
    for (final (family, style, text, kerned, plain) in [
      ('Noto Serif', 'normal', 'AV', 13.63868, 14.4795),
      ('Noto Serif', 'normal', 'Typography', 59.93359, 60.354),
      (
        'Noto Serif',
        'normal',
        'The quick brown fox jumps over the lazy dog.',
        228.2175,
        228.2175,
      ),
      ('Noto Serif', 'normal', 'WAVE To', 45.42382, 47.208),
      ('Noto Serif', 'normal', 'fi fl', 17.073, 17.073),
      ('Noto Serif', 'bold', 'AV', 14.38418, 15.225),
      ('Noto Serif', 'bold', 'Typography', 63.19909, 63.6195),
      (
        'Noto Serif',
        'bold',
        'The quick brown fox jumps over the lazy dog.',
        241.521,
        241.521,
      ),
      ('Noto Serif', 'bold', 'WAVE To', 47.47132, 49.2555),
      ('Noto Serif', 'bold', 'fi fl', 18.6585, 18.6585),
      ('M+ 1mn', 'normal', 'AV', 10.5, 10.5),
      ('M+ 1mn', 'normal', 'Typography', 52.5, 52.5),
      (
        'M+ 1mn',
        'normal',
        'The quick brown fox jumps over the lazy dog.',
        231.0,
        231.0,
      ),
      ('M+ 1mn', 'normal', 'WAVE To', 36.75, 36.75),
      ('M+ 1mn', 'normal', 'fi fl', 26.25, 26.25),
      ('Helvetica', 'normal', 'AV', 13.272, 14.007),
      ('Helvetica', 'normal', 'Typography', 53.655, 55.44),
      (
        'Helvetica',
        'normal',
        'The quick brown fox jumps over the lazy dog.',
        209.2545,
        210.672,
      ),
      // (Kerned by the AFM's `space T` pair too, which Prawn leaves out.)
      ('Helvetica', 'normal', 'WAVE To', 43.05, 46.095),
      ('Helvetica', 'normal', 'fi fl', 13.419, 13.419),
    ]) {
      final font = catalog.font(family, style);
      expect(
        font.widthOf(text, 10.5),
        closeTo(kerned, 0.004 * kerned + 0.05),
        reason: '$family $text',
      );
      expect(
        font.widthOf(text, 10.5, kerning: false),
        closeTo(plain, 0.004 * plain + 0.05),
        reason: '$family $text',
      );
    }
  });

  test('relative font sizes', () {
    expect(resolveFontSize('1.5em', 10, 12), 15);
    expect(resolveFontSize('80%', 10, 12), 8);
    expect(resolveFontSize('2rem', 10, 12), 24);
    expect(resolveFontSize('9', 10, 12), 9);
  });

  test('icon fonts and unknown families', () {
    expect(catalog.hasIcons('fas'), isTrue);
    expect(catalog.font('fas').hasGlyph(0xf015), isTrue);
    // A family that isn't installed: a built-in font, said once.
    expect(catalog.font('Nope'), isA<AfmFont>());
    catalog.font('Nope');
    expect(warnings, hasLength(1));
    expect(
      warnings.single,
      'font family Nope is not installed: using Helvetica for Nope (normal); '
      "`asciidart doctor` installs the default themes' fonts",
    );
    expect(catalog.font('Some Serif', 'bold'), isA<AfmFont>());
    expect(warnings.last, contains('using Times-Bold'));
  });
}
