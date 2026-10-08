/// HTML escaping in one pass gives what the regular expression and
/// `replaceAll` calls it replaced gave, on random text.
library;

import 'dart:math';

import 'package:plain_highlighting/src/utils.dart';
import 'package:test/test.dart';

/// The escaping before (the oracle).
String _oracle(String value) {
  if (!RegExp('[&<>"\']').hasMatch(value)) return value;
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

void main() {
  test('escaping matches the oracle', () {
    final random = Random(11);
    final pool = '&<>"\'a; #x27\né\u{1F600}'.runes.toList();
    for (var n = 0; n < 20000; n++) {
      final text = String.fromCharCodes([
        for (var i = random.nextInt(24); i > 0; i--)
          pool[random.nextInt(pool.length)],
      ]);
      final expected = _oracle(text);
      expect(escapeHtml(text), expected, reason: text);
      final buffer = StringBuffer('>');
      expect(writeEscapedHtml(buffer, text), expected != text);
      expect(buffer.toString(), '>$expected');
      final start = random.nextInt(text.length + 1);
      final end = start + random.nextInt(text.length - start + 1);
      final slice = StringBuffer();
      writeEscapedHtml(slice, text, start, end);
      expect(slice.toString(), _oracle(text.substring(start, end)));
    }
    const plain = 'no specials';
    expect(identical(escapeHtml(plain), plain), isTrue);
  });
}
