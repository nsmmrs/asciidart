// Soft hyphens put into inline markup (lib/src/pdf/hyphenate.dart).
import 'package:ptome/src/pdf/hyphenate.dart';
import 'package:test/test.dart';

void main() {
  final english = hyphenatorFor('en_us')!;
  String marks(String markup, {bool acrossTags = false}) => hyphenateMarkup(
    markup,
    english,
    skipCode: true,
    lettersOnly: true,
    acrossTags: acrossTags,
  ).replaceAll('­', '-');

  test('each text between tags alone, as asciidoctor-pdf', () {
    expect(marks("It's a <em>Tree</em>beard."), "It's a <em>Tree</em>beard.");
    expect(marks('hyphenation'), 'hy-phen-ation');
  });

  test('a word across formatting tags, whole (Typst)', () {
    // Typst's case hyphenate-between-shape-runs: Tree-beard.
    expect(
      marks("It's a <em>Tree</em>beard.", acrossTags: true),
      "It's a <em>Tree-</em>beard.",
    );
    expect(
      marks('<strong>hyphen</strong>ation', acrossTags: true),
      '<strong>hy-phen-</strong>ation',
    );
  });

  test('a word ends at a character reference and other tags', () {
    expect(
      marks('hyphen&#8203;ation', acrossTags: true),
      'hy-phen&#8203;ation',
    );
    expect(marks('hyphen<br>ation', acrossTags: true), 'hy-phen<br>ation');
    expect(
      marks('hyphen<code>ation</code>', acrossTags: true),
      'hy-phen<code>ation</code>',
    );
  });

  test('bare links and code stay whole; stray characters are kept', () {
    expect(
      marks(
        '<a href="x" class="bare">hyphenation</a> hyphenation',
        acrossTags: true,
      ),
      '<a href="x" class="bare">hyphenation</a> hy-phen-ation',
    );
    expect(
      marks('a & hyphenation < b', acrossTags: true),
      'a & hy-phen-ation < b',
    );
    expect(marks('a & hyphenation < b'), 'a & hy-phen-ation < b');
  });
}
