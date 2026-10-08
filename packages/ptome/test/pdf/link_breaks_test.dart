// Where the modern engine breaks URLs: Typst's rules (text_box.dart's
// linkBreaks; typst-layout's linebreak_link).
import 'package:ptome/src/pdf/text_box.dart';
import 'package:test/test.dart';

/// [text] with a `|` at each place a line may break in its URLs.
String _cut(String text) {
  final cuts = linkBreaks(text).cuts;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (cuts.contains(i)) out.write('|');
    out.write(text[i]);
  }
  return out.toString();
}

void main() {
  test('between parts of other characters, letters and digits', () {
    expect(_cut('www.url.com'), 'www.|url.|com');
    expect(_cut('https://a.org/x/b2c'), 'https://a.|org/|x/|b|2|c');
    expect(_cut('see https://a.org/b-c'), 'see https://a.|org/|b-|c');
  });

  test('before an opening bracket, never after it', () {
    expect(_cut('https://example.com/(ab)'), 'https://example.|com/|(ab)');
  });

  test('a long part breaks after any character', () {
    expect(
      _cut('https://hi.com/%%%%%%%%abcdef'),
      'https://hi.|com/|%|%|%|%|%|%|%|%|abcdef',
    );
    // 16 bytes with its separator: after every character.
    expect(
      _cut('http://creativecommons.org'),
      'http://c|r|e|a|t|i|v|e|c|o|m|m|o|n|s|.|org',
    );
  });

  test('a URL ends before trailing punctuation and unbalanced brackets', () {
    expect(linkBreaks('For https://myhost.tld.').spans, [(12, 22)]);
    expect(linkBreaks('(see https://a.org/x)').spans, [(13, 20)]);
    expect(linkBreaks('no URL here').spans, isEmpty);
  });
}
