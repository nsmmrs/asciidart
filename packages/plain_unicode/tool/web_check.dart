// Compiled to JavaScript in CI: finds the line breaks of a multilingual
// text and maps its case, printing a digest; the CI job compares it with
// the Dart VM's, as the results must be the same on both.
import 'dart:convert';

import 'package:plain_unicode/plain_unicode.dart';

const String _text =
    'Straße ΣΟΦΟΣ — "quoted", 日本語のテキスト, '
    'עברית 123-456 http://example.org/path 👩‍👩‍👧 İstanbul ŉ';

void main() {
  final parts = [
    [for (final b in lineBreaks(_text)) '${b.offset}${b.mandatory ? '!' : ''}']
        .join(','),
    upperCase(_text),
    lowerCase(_text),
    lowerCase(_text, finalSigma: true),
  ];
  // An Adler-32 style checksum: its sums stay small enough for
  // JavaScript's numbers.
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(parts.join('\u0000'))) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${parts.first.length} $b-$a');
}
