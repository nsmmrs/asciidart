// Math drawn on a PDF page (plain_typesetting's math layout in an
// embedded Noto Sans Math), read back by pdftotext.
import 'dart:convert';
import 'dart:io';

import 'package:plain_math/plain_math.dart';
import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

void main() {
  final font = EmbeddedFont.parse(
    File('test/fonts/notosansmath-subset.ttf').readAsBytesSync(),
  );
  final layout = MathLayout(font);
  MathBox box(String mathml, {bool display = false}) =>
      layout.layout(parseMathML(mathml), size: 10, display: display);
  String math(String inner) =>
      '<math xmlns="http://www.w3.org/1998/Math/MathML">$inner</math>';

  test('drawn: identifiers in math italic', () {
    final doc = PdfDocument();
    final page = doc.addPage(const Rect(0, 0, 200, 100));
    box(math('<mi>x</mi><mo>+</mo><mn>1</mn>')).paintAt(page.canvas, 10, 50);
    final file = File(
      '${Directory.systemTemp.createTempSync('math').path}/x.pdf',
    )..writeAsBytesSync(doc.save());
    // (UTF-8 both ways: Windows decodes output in its code page.)
    final text =
        Process.runSync('pdftotext', [
              '-enc',
              'UTF-8',
              file.path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    expect(text.trim(), '\u{1d465}+1');
  }, skip: _has('pdftotext') ? false : 'needs pdftotext');
}
