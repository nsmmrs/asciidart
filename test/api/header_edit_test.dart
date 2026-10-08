/// Source-preserving edits of header attributes (`Document.withAttribute`,
/// `withoutAttribute`): only the lines of the edited entry change.
library;

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

const card = '''
= Fix the thing
Ada Lovelace
:status: backlog
:priority:   2
// keep this comment
:labels: a, b

Body text.
''';

String set(String source, String name, String value) =>
    asciidoc.parse(source).withAttribute(name, value).source;

String remove(String source, String name) =>
    asciidoc.parse(source).withoutAttribute(name).source;

void main() {
  test('rewrites only the entry that sets the attribute', () {
    expect(
      set(card, 'status', 'done'),
      card.replaceFirst(':status: backlog', ':status: done'),
    );
  });

  test('the edited source is parsed with the same settings', () {
    final doc = asciidoc
        .parse(card, attributes: {'x': '1'})
        .withAttribute('status', 'done');
    expect(doc.attributes['status'], 'done');
    expect(doc.attributes['x'], '1');
    expect(doc.blocks, isNotEmpty);
    final header = asciidoc.parseHeader(card).withAttribute('status', 'done');
    expect(header.blocks, isEmpty);
  });

  test('an edit to the same value returns the document as it is', () {
    final doc = asciidoc.parse(card);
    expect(identical(doc.withAttribute('priority', '2'), doc), isTrue);
    expect(identical(doc.withoutAttribute('missing'), doc), isTrue);
  });

  test('adds a missing attribute at the end of the header', () {
    expect(
      set(card, 'owner', 'me'),
      card.replaceFirst(':labels: a, b\n', ':labels: a, b\n:owner: me\n'),
    );
    expect(set('= T\n\nx\n', 'a', ''), '= T\n:a:\n\nx\n');
    expect(
      set('= T\nAda\nv1.0\n\nx\n', 'a', '1'),
      '= T\nAda\nv1.0\n:a: 1\n\nx\n',
    );
  });

  test('without a title, after the leading entries or at the top', () {
    expect(set(':a: 1\n\ntext\n', 'b', '2'), ':a: 1\n:b: 2\n\ntext\n');
    expect(set('text\n', 'b', '2'), ':b: 2\n\ntext\n');
    expect(set('\ntext\n', 'b', '2'), ':b: 2\n\ntext\n');
    expect(set('', 'b', '2'), ':b: 2\n');
  });

  test('removes the entries of an attribute', () {
    expect(remove(card, 'labels'), card.replaceFirst(':labels: a, b\n', ''));
    expect(remove('= T\n:a: 1\n:b: 2\n:a: 3\n\nx\n', 'a'), '= T\n:b: 2\n\nx\n');
  });

  test('the last entry wins and is the one rewritten', () {
    expect(
      set('= T\n:a: 1\n:a: 2\n\nx\n', 'a', '3'),
      '= T\n:a: 1\n:a: 3\n\nx\n',
    );
  });

  test('an unset entry becomes a set one', () {
    expect(set('= T\n:a!:\n\nx\n', 'a', 'on'), '= T\n:a: on\n\nx\n');
    expect(set('= T\n:!a:\n\nx\n', 'a', 'on'), '= T\n:a: on\n\nx\n');
  });

  test('a value continued over several lines is replaced whole', () {
    expect(
      set('= T\n:desc: one \\\n  two\n:x: y\n\nb\n', 'desc', 'new'),
      '= T\n:desc: new\n:x: y\n\nb\n',
    );
    expect(remove('= T\n:desc: one +\n  two\n\nb\n', 'desc'), '= T\n\nb\n');
  });

  test('names are matched as the parser stores them', () {
    expect(
      set('= T\n:Status: a\n\nx\n', 'status', 'b'),
      '= T\n:Status: b\n\nx\n',
    );
    expect(
      set('= T\n:numbered:\n\nx\n', 'sectnums', 'all'),
      '= T\n:numbered: all\n\nx\n',
    );
  });

  test('keeps CRLF line endings and trailing spaces elsewhere', () {
    expect(
      set('= T  \r\n:a: 1\r\n\r\nx\r\n', 'b', '2'),
      '= T  \r\n:a: 1\r\n:b: 2\r\n\r\nx\r\n',
    );
  });

  test('entries in the body are not header attributes', () {
    expect(
      set('= T\n\npara\n\n:status: body\n', 'status', 'h'),
      '= T\n:status: h\n\npara\n\n:status: body\n',
    );
  });

  test('refuses entries under preprocessor conditionals', () {
    for (final source in [
      '= T\nifdef::foo[]\n:status: a\nendif::[]\n\nx\n',
      '= T\n:foo:\nifdef::foo[]\n:status: a\nendif::[]\n\nx\n',
      '= T\nifdef::foo[:status: a]\n\nx\n',
    ]) {
      expect(
        () => asciidoc.parse(source).withAttribute('status', 'b'),
        throwsA(isA<PtomeException>()),
        reason: source,
      );
    }
    // Other attributes of such a header can be edited.
    expect(
      set('= T\nifdef::foo[]\n:status: a\nendif::[]\n\nx\n', 'owner', 'me'),
      '= T\nifdef::foo[]\n:status: a\nendif::[]\n:owner: me\n\nx\n',
    );
  });

  test('ignores look-alike entries in a block comment', () {
    expect(
      set('= T\n////\n:status: x\n////\n:status: a\n\nb\n', 'status', 'c'),
      '= T\n////\n:status: x\n////\n:status: c\n\nb\n',
    );
  });

  test('rejects values of more than one line and invalid names', () {
    final doc = asciidoc.parse(card);
    expect(() => doc.withAttribute('a', 'one\ntwo'), throwsArgumentError);
    expect(() => doc.withAttribute('!!', 'x'), throwsArgumentError);
  });
}
