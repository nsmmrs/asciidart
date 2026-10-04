import 'package:asciidoctor/asciidoctor.dart';

void main() {
  // Convert an AsciiDoc string to an HTML fragment.
  final html = convert('Hello, *World*!');
  // Examples print their result to the console.
  // ignore: avoid_print
  print(html);

  // Convert a file to a standalone HTML document.
  // convertFile('doc.adoc', {'standalone': true, 'to_file': 'doc.html'});
}
