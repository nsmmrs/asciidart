// The notoc option: a section left out of the contents (Ptome's).
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

const _book =
    '= Book\n:doctype: book\n:toc:\n\n'
    '[colophon%notoc]\n== Copyright\n\nText.\n\n'
    '== Chapter\n\nText.\n';

void main() {
  test('HTML contents leave the section out', () {
    final html = asciidoc.convert(_book, standalone: true);
    final toc = RegExp(r'<div id="toc"[\s\S]*?</ul>').stringMatch(html)!;
    expect(toc, contains('Chapter'));
    expect(toc, isNot(contains('Copyright')));
    // The section is still there.
    expect(html, contains('<h2 id="_copyright">Copyright</h2>'));
  });

  test("without the option, Asciidoctor's contents", () {
    final html = asciidoc.convert(
      _book.replaceFirst('%notoc', ''),
      standalone: true,
    );
    final toc = RegExp(r'<div id="toc"[\s\S]*?</ul>').stringMatch(html)!;
    expect(toc, contains('Copyright'));
  });
}
