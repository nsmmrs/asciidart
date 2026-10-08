// Compiled to JavaScript in CI: hyphenates words in several languages
// (each language decoded from its Brotli stream), printing a digest; the
// CI job compares it with the Dart VM's, as the results must be the same.
import 'dart:convert';

import 'package:plain_hyphenation/plain_hyphenation.dart';

const Map<String, List<String>> _words = {
  'en': ['hyphenation', 'algorithm', 'associate', 'typesetting'],
  'de': ['Silbentrennung', 'Donaudampfschifffahrt', 'Informationen'],
  'fr': ['anticonstitutionnellement', 'typographie'],
  'ru': ['разумом', 'государство'],
  'fi': ['avioliiton', 'ammattiopetusta'],
};

void main() {
  final parts = [
    for (final MapEntry(key: language, value: words) in _words.entries)
      for (final word in words)
        '$word:${hyphenatorFor(language)!.hyphenate(word)}',
  ];
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(parts.join(','))) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${parts.length} $b-$a');
}
