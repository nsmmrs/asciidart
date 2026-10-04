import 'package:asciidoctor/asciidoctor.dart';

void main() {
  // Convert an AsciiDoc string to an HTML fragment.
  final html = convert('Hello, *World*!');
  print(html);

  // Convert a file to a standalone HTML document.
  // convertFile('doc.adoc', {'standalone': true, 'to_file': 'doc.html'});
}
