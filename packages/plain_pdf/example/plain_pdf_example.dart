import 'dart:io';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

void main(List<String> args) {
  final document = PdfDocument(info: const PdfInfo(title: 'Hello'));
  final page = document.addPage(const Rect(0, 0, 595, 842)); // A4
  final style = TextStyle(StandardFont.helvetica, 24);
  page.canvas
    ..setFillColor(Color.hex('#1565c0'))
    ..roundedRect(const Rect(72, 700, 451, 60), 8)
    ..fill()
    ..setFillColor(const Color.gray(1))
    ..text('Hello, PDF', 90, 722, style);
  page.link(
    const Rect(72, 700, 451, 60),
    const LinkTarget.uri('https://example.org/'),
  );
  File(args.isEmpty ? 'hello.pdf' : args.first)
      .writeAsBytesSync(document.save());
}
