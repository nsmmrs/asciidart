// The text path pinned to what plain_pdf wrote before it was made faster
// (commit 17001e86): digests of the shaped glyphs of the 14 standard fonts
// and of the content streams drawing seeded random text in standard and
// embedded fonts, with kerning, word and character spacing, rise, skew and
// emboldening.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

const fontNames = [
  'Helvetica', 'Helvetica-Bold', 'Helvetica-Oblique', //
  'Helvetica-BoldOblique', 'Times-Roman', 'Times-Bold', 'Times-Italic',
  'Times-BoldItalic', 'Courier', 'Courier-Bold', 'Courier-Oblique',
  'Courier-BoldOblique', 'Symbol', 'ZapfDingbats',
];

/// Seeded random text: letters, spaces and punctuation, some Latin-1, some
/// of WinAnsi's high codes, some characters the fonts lack.
List<String> texts(int seed, int count) {
  final random = math.Random(seed);
  const alphabet =
      // One alphabet, not words.
      // ignore: missing_whitespace_between_adjacent_strings
      'AVAWAToTeYoLTPaffi fl  .,;:!?-()[]"\'éüÅß'
      '—’“€•Œα→中\u{1F600}'
      'abcdefghijklmnopqrstuvwxyz0123456789';
  final runes = alphabet.runes.toList();
  return [
    for (var i = 0; i < count; i++)
      String.fromCharCodes([
        for (var k = random.nextInt(40); k > 0; k--)
          runes[random.nextInt(runes.length)],
      ]),
  ];
}

String digest(StringBuffer text) =>
    md5.convert(utf8.encode(text.toString())).toString();

void main() {
  test('standard fonts shape as before', () {
    final out = StringBuffer();
    for (final name in fontNames) {
      final font = StandardFont.named(name);
      for (final kerning in const [true, false]) {
        for (final text in texts(name.length, 300)) {
          for (final g in font.shape(text, kerning: kerning)) {
            out.write('${g.id} ${g.text} ${g.advance} ${g.kerning};');
          }
          out.write('\n');
        }
      }
    }
    expect(digest(out), '42f55400c8801a23c95cfa6b9a7e6d41');
  });

  test('text is drawn as before', () {
    final serif = EmbeddedFont.parse(
      File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
    );
    final out = StringBuffer();
    final random = math.Random(3);
    for (final font in [
      StandardFont.helvetica,
      StandardFont.timesRoman,
      StandardFont.named('Symbol'),
      serif,
    ]) {
      final document = PdfDocument();
      final page = document.addPage(const Rect(0, 0, 595, 842));
      for (final text in texts(font.name.length, 200)) {
        final style = TextStyle(
          font,
          [11.0, 9.5, 10.333333, 12.0][random.nextInt(4)],
          wordSpacing: [0.0, 0.0, 0.4, -1.25, 2.7182818][random.nextInt(5)],
          characterSpacing: [0.0, 0.0, 0.1, 0.33][random.nextInt(4)],
          rise: [0.0, 0.0, 0.0, 2.5][random.nextInt(4)],
          skew: [0.0, 0.0, 0.0, 0.2][random.nextInt(4)],
          embolden: [0.0, 0.0, 0.0, 0.4][random.nextInt(4)],
          kerning: random.nextInt(5) != 0,
        );
        final width = page.canvas.text(
          text,
          random.nextDouble() * 500,
          random.nextDouble() * 800,
          style,
        );
        out.write('$width;');
      }
      final pdf = document.save(
        options: const PdfWriterOptions(compress: false, deterministic: true),
      );
      out
        ..write(latin1.decode(pdf))
        ..write('\n');
    }
    expect(digest(out), '8f310e833e583d8a362a12beb84d7521');
  });
}
