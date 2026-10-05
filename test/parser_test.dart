/// Port of `test/parser_test.rb` (complete).
///
/// Parser working attribute maps are [BlockAttributes], with positional
/// attributes under `'1'`, `'2'`, ... and the attribute entries alongside.
library;

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

/// Creates an unparsed document (port of `empty_document`).
Document emptyDocument([
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => Document.lines(<String>[], options);

/// Parses [src] into a document (port of `document_from_string`).
Document documentFromString([
  String src = '',
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => Document(src, options).parse();

/// Splits [source] into lines with Ruby `split` semantics (trailing empty
/// fields are dropped).
List<String> _splitLines(String source) {
  final lines = source.split('\n');
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Parses header metadata from [source] (port of `parse_header_metadata`).
Map<String, Object?> parseHeaderMetadata(String source, [Document? doc]) =>
    Parser.parseHeaderMetadata(Reader(_splitLines(source)), document: doc);

/// Runs [body] with a memory logger installed (port of
/// `using_memory_logger`).
void usingMemoryLogger(void Function(MemoryLogger logger) body) {
  final previous = LoggerManager.logger;
  final memoryLogger = MemoryLogger();
  LoggerManager.logger = memoryLogger;
  try {
    body(memoryLogger);
  } finally {
    LoggerManager.logger = previous;
  }
}

/// Asserts [logger] recorded [text] at [severity] (port of
/// `assert_message`).
void assertLogMessage(MemoryLogger logger, Severity severity, String text) {
  final found = logger.messages.any(
    (m) => m.severity == severity && m.message.toString() == text,
  );
  expect(
    found,
    isTrue,
    reason:
        'expected log $severity: $text; '
        'got '
        '${logger.messages.map((m) => '${m.severity}: ${m.message}').toList()}',
  );
}

void main() {
  group('Parser', () {
    test('is_section_title?', () {
      expect(
        Parser.isSectionTitle('AsciiDoc Home Page', '=================='),
        equals(0),
      );
      expect(Parser.isSectionTitle('=== AsciiDoc Home Page'), equals(2));
    });

    test('sanitize attribute name', () {
      expect(Parser.sanitizeAttributeName('Foo Bar'), equals('foobar'));
      expect(Parser.sanitizeAttributeName('foo'), equals('foo'));
      expect(
        Parser.sanitizeAttributeName('Foo 3^ # - Bar['),
        equals('foo3-bar'),
      );
    });

    test('store attribute with value', () {
      final (attrName, attrValue) = Parser.storeAttribute('foo', 'bar');
      expect(attrName, equals('foo'));
      expect(attrValue, equals('bar'));
    });

    test('store attribute with negated value', () {
      for (final entry in {'foo!': null, '!foo': null, 'foo': null}.entries) {
        final (attrName, attrValue) = Parser.storeAttribute(
          entry.key,
          entry.value,
        );
        expect(attrName, equals(entry.key.replaceAll('!', '')));
        expect(attrValue, isNull);
      }
    });

    test('store accessible attribute on document with value', () {
      final doc = emptyDocument();
      // TEMP-SEAM (parser): stands in for `doc.setAttribute('foo', 'baz')`,
      // which throws until the substitutors wave lands; observably
      // identical for a plain value.
      doc.attributes['foo'] = 'baz';
      final attrs = BlockAttributes();
      final (attrName, attrValue) = Parser.storeAttribute(
        'foo',
        'bar',
        doc,
        attrs,
      );
      expect(attrName, equals('foo'));
      expect(attrValue, equals('bar'));
      expect(doc.attr('foo'), equals('bar'));
      expect(attrs.attributeEntries, isNotNull);
      final entries = attrs.attributeEntries!;
      expect(entries, hasLength(1));
      expect(entries[0].name, equals('foo'));
      expect(entries[0].value, equals('bar'));
    });

    test('store accessible attribute on document with value that '
        'contains attribute reference', () {
      final doc = emptyDocument();
      // TEMP-SEAM (parser): stands in for `setAttribute`, which throws
      // until the substitutors wave lands; observably identical for
      // plain values.
      doc.attributes['foo'] = 'baz';
      doc.attributes['release'] = 'ultramega';
      final attrs = BlockAttributes();
      final (attrName, attrValue) = Parser.storeAttribute(
        'foo',
        '{release}',
        doc,
        attrs,
      );
      expect(attrName, equals('foo'));
      expect(attrValue, equals('ultramega'));
      expect(doc.attr('foo'), equals('ultramega'));
      expect(attrs.attributeEntries, isNotNull);
      final entries = attrs.attributeEntries!;
      expect(entries, hasLength(1));
      expect(entries[0].name, equals('foo'));
      expect(entries[0].value, equals('ultramega'));
    });

    test('store inaccessible attribute on document with value', () {
      final doc = emptyDocument(
        const AsciidoctorOptions(attributes: {'foo': 'baz'}),
      );
      final attrs = BlockAttributes();
      final (attrName, attrValue) = Parser.storeAttribute(
        'foo',
        'bar',
        doc,
        attrs,
      );
      expect(attrName, equals('foo'));
      expect(attrValue, equals('bar'));
      expect(doc.attr('foo'), equals('baz'));
      expect(attrs.attributeEntries, isNull);
    });

    test('store accessible attribute on document with negated value', () {
      for (final entry in {'foo!': null, '!foo': null, 'foo': null}.entries) {
        final doc = emptyDocument();
        // TEMP-SEAM (parser): stands in for `setAttribute`, which throws
        // until the substitutors wave lands; observably identical for a
        // plain value.
        doc.attributes['foo'] = 'baz';
        final attrs = BlockAttributes();
        final (attrName, attrValue) = Parser.storeAttribute(
          entry.key,
          entry.value,
          doc,
          attrs,
        );
        expect(attrName, equals(entry.key.replaceAll('!', '')));
        expect(attrValue, isNull);
        expect(attrs.attributeEntries, isNotNull);
        final entries = attrs.attributeEntries!;
        expect(entries, hasLength(1));
        expect(entries[0].name, equals('foo'));
        expect(entries[0].value, isNull);
      }
    });

    test('store inaccessible attribute on document with negated value', () {
      for (final entry in {'foo!': null, '!foo': null, 'foo': null}.entries) {
        final doc = emptyDocument(
          const AsciidoctorOptions(attributes: {'foo': 'baz'}),
        );
        final attrs = BlockAttributes();
        final (attrName, attrValue) = Parser.storeAttribute(
          entry.key,
          entry.value,
          doc,
          attrs,
        );
        expect(attrName, equals(entry.key.replaceAll('!', '')));
        expect(attrValue, isNull);
        expect(attrs.attributeEntries, isNull);
      }
    });

    test('parse style attribute with id and role', () {
      final attributes = <String, String>{'1': 'style#id.role'};
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, equals('style'));
      expect(attributes['style'], equals('style'));
      expect(attributes['id'], equals('id'));
      expect(attributes['role'], equals('role'));
      expect(attributes['1'], equals('style#id.role'));
    });

    test('parse style attribute with style, role, id and option', () {
      final attributes = <String, String>{'1': 'style.role#id%fragment'};
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, equals('style'));
      expect(attributes['style'], equals('style'));
      expect(attributes['id'], equals('id'));
      expect(attributes['role'], equals('role'));
      expect(attributes['fragment-option'], equals(''));
      expect(attributes['1'], equals('style.role#id%fragment'));
      expect(attributes.containsKey('options'), isFalse);
    });

    test('parse style attribute with style, id and multiple roles', () {
      final attributes = <String, String>{'1': 'style#id.role1.role2'};
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, equals('style'));
      expect(attributes['style'], equals('style'));
      expect(attributes['id'], equals('id'));
      expect(attributes['role'], equals('role1 role2'));
      expect(attributes['1'], equals('style#id.role1.role2'));
    });

    test('parse style attribute with style, multiple roles and id', () {
      final attributes = <String, String>{'1': 'style.role1.role2#id'};
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, equals('style'));
      expect(attributes['style'], equals('style'));
      expect(attributes['id'], equals('id'));
      expect(attributes['role'], equals('role1 role2'));
      expect(attributes['1'], equals('style.role1.role2#id'));
    });

    test('parse style attribute with positional and original style', () {
      final attributes = <String, String>{
        '1': 'new_style',
        'style': 'original_style',
      };
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, equals('new_style'));
      expect(attributes['style'], equals('new_style'));
      expect(attributes['1'], equals('new_style'));
    });

    test('parse style attribute with id and role only', () {
      final attributes = <String, String>{'1': '#id.role'};
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, isNull);
      expect(attributes['id'], equals('id'));
      expect(attributes['role'], equals('role'));
      expect(attributes['1'], equals('#id.role'));
    });

    test('parse empty style attribute', () {
      final attributes = <String, String>{};
      final style = Parser.parseStyleAttribute(attributes);
      expect(style, isNull);
      expect(attributes['id'], isNull);
      expect(attributes['role'], isNull);
      expect(attributes['1'], isNull);
    });

    test(
      'parse style attribute with option should preserve existing options',
      () {
        final attributes = <String, String>{
          '1': '%header',
          'footer-option': '',
        };
        final style = Parser.parseStyleAttribute(attributes);
        expect(style, isNull);
        expect(attributes['header-option'], equals(''));
        expect(attributes['footer-option'], equals(''));
      },
    );

    test('an empty block anchor clears the id', () {
      final doc = load('[#keep]\n[[]]\n--\nBlock content\n--\n');
      final block = doc.blocks.single;
      expect(block.id, isNull);
      expect(block.blocks.single.contextName, equals('paragraph'));
    });

    test('parse author first', () {
      final metadata = parseHeaderMetadata('Stuart');
      expect(metadata.length, equals(5));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Stuart'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Stuart'));
      expect(metadata['authorinitials'], equals('S'));
    });

    test('parse author first last', () {
      final metadata = parseHeaderMetadata('Yukihiro Matsumoto');
      expect(metadata.length, equals(6));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Yukihiro Matsumoto'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Yukihiro'));
      expect(metadata['lastname'], equals('Matsumoto'));
      expect(metadata['authorinitials'], equals('YM'));
    });

    test('parse author first middle last', () {
      final metadata = parseHeaderMetadata('David Heinemeier Hansson');
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('David Heinemeier Hansson'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('David'));
      expect(metadata['middlename'], equals('Heinemeier'));
      expect(metadata['lastname'], equals('Hansson'));
      expect(metadata['authorinitials'], equals('DHH'));
    });

    test('parse author first middle last email', () {
      final metadata = parseHeaderMetadata(
        'David Heinemeier Hansson <rails@ruby-lang.org>',
      );
      expect(metadata.length, equals(8));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('David Heinemeier Hansson'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('David'));
      expect(metadata['middlename'], equals('Heinemeier'));
      expect(metadata['lastname'], equals('Hansson'));
      expect(metadata['email'], equals('rails@ruby-lang.org'));
      expect(metadata['authorinitials'], equals('DHH'));
    });

    test('parse author first email', () {
      final metadata = parseHeaderMetadata('Stuart <founder@asciidoc.org>');
      expect(metadata.length, equals(6));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Stuart'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Stuart'));
      expect(metadata['email'], equals('founder@asciidoc.org'));
      expect(metadata['authorinitials'], equals('S'));
    });

    test('parse author first last email', () {
      final metadata = parseHeaderMetadata(
        'Stuart Rackham <founder@asciidoc.org>',
      );
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Stuart Rackham'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Stuart'));
      expect(metadata['lastname'], equals('Rackham'));
      expect(metadata['email'], equals('founder@asciidoc.org'));
      expect(metadata['authorinitials'], equals('SR'));
    });

    test('parse author with hyphen', () {
      final metadata = parseHeaderMetadata('Tim Berners-Lee <founder@www.org>');
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Tim Berners-Lee'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Tim'));
      expect(metadata['lastname'], equals('Berners-Lee'));
      expect(metadata['email'], equals('founder@www.org'));
      expect(metadata['authorinitials'], equals('TB'));
    });

    test('parse author with single quote', () {
      final metadata = parseHeaderMetadata(
        "Stephen O'Grady <founder@redmonk.com>",
      );
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals("Stephen O'Grady"));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Stephen'));
      expect(metadata['lastname'], equals("O'Grady"));
      expect(metadata['email'], equals('founder@redmonk.com'));
      expect(metadata['authorinitials'], equals('SO'));
    });

    test('parse author with dotted initial', () {
      final metadata = parseHeaderMetadata('Heiko W. Rupp <hwr@example.de>');
      expect(metadata.length, equals(8));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Heiko W. Rupp'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Heiko'));
      expect(metadata['middlename'], equals('W.'));
      expect(metadata['lastname'], equals('Rupp'));
      expect(metadata['email'], equals('hwr@example.de'));
      expect(metadata['authorinitials'], equals('HWR'));
    });

    test('parse author with underscore', () {
      final metadata = parseHeaderMetadata('Tim_E Fella');
      expect(metadata.length, equals(6));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Tim E Fella'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Tim E'));
      expect(metadata['lastname'], equals('Fella'));
      expect(metadata['authorinitials'], equals('TF'));
    });

    test('parse author name with letters outside basic latin', () {
      final metadata = parseHeaderMetadata('Stéphane Brontë');
      expect(metadata.length, equals(6));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Stéphane Brontë'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Stéphane'));
      expect(metadata['lastname'], equals('Brontë'));
      expect(metadata['authorinitials'], equals('SB'));
    });

    test('parse ideographic author names', () {
      final metadata = parseHeaderMetadata('李 四 <si.li@example.com>');
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('李 四'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('李'));
      expect(metadata['lastname'], equals('四'));
      expect(metadata['email'], equals('si.li@example.com'));
      expect(metadata['authorinitials'], equals('李四'));
    });

    test('parse author condenses whitespace', () {
      final metadata = parseHeaderMetadata(
        'Stuart       Rackham     <founder@asciidoc.org>',
      );
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Stuart Rackham'));
      expect(metadata['authors'], equals(metadata['author']));
      expect(metadata['firstname'], equals('Stuart'));
      expect(metadata['lastname'], equals('Rackham'));
      expect(metadata['email'], equals('founder@asciidoc.org'));
      expect(metadata['authorinitials'], equals('SR'));
    });

    test('parse invalid author line becomes author', () {
      final metadata = parseHeaderMetadata(
        '   Stuart       Rackham, founder of AsciiDoc   <founder@asciidoc.org>',
      );
      expect(metadata.length, equals(5));
      expect(metadata['authorcount'], equals('1'));
      expect(
        metadata['author'],
        equals('Stuart Rackham, founder of AsciiDoc <founder@asciidoc.org>'),
      );
      expect(metadata['authors'], equals(metadata['author']));
      expect(
        metadata['firstname'],
        equals('Stuart Rackham, founder of AsciiDoc <founder@asciidoc.org>'),
      );
      expect(metadata['authorinitials'], equals('S'));
    });

    test('parse multiple authors', () {
      final metadata = parseHeaderMetadata(
        'Doc Writer <doc.writer@asciidoc.org>; John Smith '
        '<john.smith@asciidoc.org>',
      );
      expect(metadata['authorcount'], equals('2'));
      expect(metadata['authors'], equals('Doc Writer, John Smith'));
      expect(metadata['author'], equals('Doc Writer'));
      expect(metadata['author_1'], equals('Doc Writer'));
      expect(metadata['author_2'], equals('John Smith'));
    });

    test('should not parse multiple authors if semi-colon is not '
        'followed by space', () {
      final metadata = parseHeaderMetadata('Joe Doe;Smith Johnson');
      expect(metadata['authorcount'], equals('1'));
    });

    test('skips blank author entries in implicit author line', () {
      final metadata = parseHeaderMetadata(
        'Doc Writer; ; John Smith <john.smith@asciidoc.org>;',
      );
      expect(metadata['authorcount'], equals('2'));
      expect(metadata['author_1'], equals('Doc Writer'));
      expect(metadata['author_2'], equals('John Smith'));
    });

    test('catalogCallouts finds each callout form', () {
      for (final text in [
        'a <1>',
        'a <.>',
        r'a \<1>',
        'a <!--1-->',
        'a <!1>',
        'a <--1-->',
        'a <b> <1>',
      ]) {
        expect(Parser.catalogCallouts(text, emptyDocument()), isTrue);
      }
      for (final text in ['a <b>', 'a <', 'a <1> b', '<html> x', '']) {
        expect(Parser.catalogCallouts(text, emptyDocument()), isFalse);
      }
    });

    test('parse name with more than 3 parts in author attribute', () {
      final doc = emptyDocument();
      parseHeaderMetadata(':author: Leroy  Harold  Scherer,  Jr.', doc);
      expect(doc.attributes['author'], equals('Leroy Harold Scherer, Jr.'));
      expect(doc.attributes['firstname'], equals('Leroy'));
      expect(doc.attributes['middlename'], equals('Harold'));
      expect(doc.attributes['lastname'], equals('Scherer, Jr.'));
    });

    test('use explicit authorinitials if set after implicit author line', () {
      const input = 'Jean-Claude Van Damme\n:authorinitials: JCVD\n';
      final doc = emptyDocument();
      parseHeaderMetadata(input, doc);
      expect(doc.attributes['authorinitials'], equals('JCVD'));
    });

    test('use explicit authorinitials if set after author attribute', () {
      const input = ':author: Jean-Claude Van Damme\n:authorinitials: JCVD\n';
      final doc = emptyDocument();
      parseHeaderMetadata(input, doc);
      expect(doc.attributes['authorinitials'], equals('JCVD'));
    });

    test('use implicit authors if value of authors attribute matches '
        'computed value', () {
      const input =
          'Doc Writer; Junior Writer\n'
          ':authors: Doc Writer, Junior Writer\n';
      final doc = emptyDocument();
      parseHeaderMetadata(input, doc);
      expect(doc.attributes['authors'], equals('Doc Writer, Junior Writer'));
      expect(doc.attributes['author_1'], equals('Doc Writer'));
      expect(doc.attributes['author_2'], equals('Junior Writer'));
    });

    test('replace implicit authors if value of authors attribute does '
        'not match computed value', () {
      const input =
          'Doc Writer; Junior Writer\n'
          ':authors: Stuart Rackham; Dan Allen; Sarah White\n';
      final doc = emptyDocument();
      final metadata = parseHeaderMetadata(input, doc);
      expect(metadata['authorcount'], equals('3'));
      expect(doc.attributes['authorcount'], equals('3'));
      expect(
        doc.attributes['authors'],
        equals('Stuart Rackham, Dan Allen, Sarah White'),
      );
      expect(doc.attributes['author_1'], equals('Stuart Rackham'));
      expect(doc.attributes['author_2'], equals('Dan Allen'));
      expect(doc.attributes['author_3'], equals('Sarah White'));
    });

    test('sets authorcount to 0 if document has no authors', () {
      const input = '';
      final doc = emptyDocument();
      final metadata = parseHeaderMetadata(input, doc);
      expect(doc.attributes['authorcount'], equals('0'));
      expect(metadata['authorcount'], equals('0'));
    });

    test('returns empty hash if document has no authors and invoked '
        'without document', () {
      final metadata = parseHeaderMetadata('');
      expect(metadata, isEmpty);
    });

    test('does not drop name joiner when using multiple authors', () {
      const input = 'Kismet Chameleon; Lazarus het_Draeke';
      final doc = emptyDocument();
      parseHeaderMetadata(input, doc);
      expect(doc.attributes['authorcount'], equals('2'));
      expect(
        doc.attributes['authors'],
        equals('Kismet Chameleon, Lazarus het Draeke'),
      );
      expect(doc.attributes['author_1'], equals('Kismet Chameleon'));
      expect(doc.attributes['author_2'], equals('Lazarus het Draeke'));
      expect(doc.attributes['lastname_2'], equals('het Draeke'));
    });

    test(
      'allows authors to be overridden using explicit author attributes',
      () {
        const input =
            'Kismet Chameleon; Johnny Bravo; Lazarus het_Draeke\n'
            ':author_2: Danger Mouse\n';
        final doc = emptyDocument();
        parseHeaderMetadata(input, doc);
        expect(doc.attributes['authorcount'], equals('3'));
        expect(
          doc.attributes['authors'],
          equals('Kismet Chameleon, Danger Mouse, Lazarus het Draeke'),
        );
        expect(doc.attributes['author_1'], equals('Kismet Chameleon'));
        expect(doc.attributes['author_2'], equals('Danger Mouse'));
        expect(doc.attributes['author_3'], equals('Lazarus het Draeke'));
        expect(doc.attributes['lastname_3'], equals('het Draeke'));
      },
    );

    test('removes formatting before partitioning author defined using '
        'author attribute', () {
      const input =
          ':author: pass:n[http://example.org/community/team.html[Ze_**Project** team]]';
      final doc = emptyDocument();
      parseHeaderMetadata(input, doc);
      expect(doc.attributes['authorcount'], equals('1'));
      expect(
        doc.attributes['authors'],
        equals(
          '<a href="http://example.org/community/team.html">Ze <strong>Project</strong> team</a>',
        ),
      );
      expect(doc.attributes['firstname'], equals('Ze Project'));
      expect(doc.attributes['lastname'], equals('team'));
    });

    test('parse rev number date remark', () {
      const input =
          'Ryan Waldron\n'
          'v0.0.7, 2013-12-18: The first release you can stand on\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(9));
      expect(metadata['revnumber'], equals('0.0.7'));
      expect(metadata['revdate'], equals('2013-12-18'));
      expect(
        metadata['revremark'],
        equals('The first release you can stand on'),
      );
    });

    test('parse rev number, data, and remark as attribute references', () {
      const input =
          'Author Name\n'
          'v{project-version}, {release-date}: {release-summary}\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(9));
      expect(metadata['revnumber'], equals('{project-version}'));
      expect(metadata['revdate'], equals('{release-date}'));
      expect(metadata['revremark'], equals('{release-summary}'));
    });

    test(
      'should resolve attribute references in rev number, data, and remark',
      () {
        const input =
            '= Document Title\n'
            'Author Name\n'
            '{project-version}, {release-date}: {release-summary}\n';
        final doc = documentFromString(
          input,
          const AsciidoctorOptions(
            attributes: {
              'project-version': '1.0.1',
              'release-date': '2018-05-15',
              'release-summary': 'The one you can count on!',
            },
          ),
        );
        expect(doc.attr('revnumber'), equals('1.0.1'));
        expect(doc.attr('revdate'), equals('2018-05-15'));
        expect(doc.attr('revremark'), equals('The one you can count on!'));
      },
    );

    test('parse rev date', () {
      const input = 'Ryan Waldron\n2013-12-18\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(7));
      expect(metadata['revdate'], equals('2013-12-18'));
    });

    test('parse rev number with trailing comma', () {
      const input = 'Stuart Rackham\nv8.6.8,\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(7));
      expect(metadata['revnumber'], equals('8.6.8'));
      expect(metadata.containsKey('revdate'), isFalse);
    });

    // Asciidoctor recognizes a standalone revision without a trailing comma.
    test('parse rev number', () {
      const input = 'Stuart Rackham\nv8.6.8\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(7));
      expect(metadata['revnumber'], equals('8.6.8'));
      expect(metadata.containsKey('revdate'), isFalse);
    });

    // While compliant w/ AsciiDoc, this is just sloppy parsing.
    test('treats arbitrary text on rev line as revdate', () {
      const input = 'Ryan Waldron\nfoobar\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(7));
      expect(metadata['revdate'], equals('foobar'));
    });

    test('parse rev date remark', () {
      const input =
          'Ryan Waldron\n'
          '2013-12-18:  The first release you can stand on\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(8));
      expect(metadata['revdate'], equals('2013-12-18'));
      expect(
        metadata['revremark'],
        equals('The first release you can stand on'),
      );
    });

    test('should not mistake attribute entry as rev remark', () {
      const input = 'Joe Cool\n:page-layout: post\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata['revremark'], isNot(equals('page-layout: post')));
      expect(metadata.containsKey('revdate'), isFalse);
    });

    test('parse rev remark only', () {
      const input = 'Joe Cool\n :Must start revremark-only line with space\n';
      final metadata = parseHeaderMetadata(input);
      expect(
        metadata['revremark'],
        equals('Must start revremark-only line with space'),
      );
      expect(metadata.containsKey('revdate'), isFalse);
    });

    test('skip line comments before author', () {
      const input = '// Asciidoctor\n// release artist\nRyan Waldron\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(6));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Ryan Waldron'));
      expect(metadata['firstname'], equals('Ryan'));
      expect(metadata['lastname'], equals('Waldron'));
      expect(metadata['authorinitials'], equals('RW'));
    });

    test('skip block comment before author', () {
      const input = '////\nAsciidoctor\nrelease artist\n////\nRyan Waldron\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(6));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Ryan Waldron'));
      expect(metadata['firstname'], equals('Ryan'));
      expect(metadata['lastname'], equals('Waldron'));
      expect(metadata['authorinitials'], equals('RW'));
    });

    test('skip block comment before rev', () {
      const input =
          'Ryan Waldron\n'
          '////\n'
          'Asciidoctor\n'
          'release info\n'
          '////\n'
          'v0.0.7, 2013-12-18\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(8));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Ryan Waldron'));
      expect(metadata['revnumber'], equals('0.0.7'));
      expect(metadata['revdate'], equals('2013-12-18'));
    });

    test('break header at line with three forward slashes', () {
      const input = 'Joe Cool\nv1.0\n///\nstuff\n';
      final metadata = parseHeaderMetadata(input);
      expect(metadata.length, equals(7));
      expect(metadata['authorcount'], equals('1'));
      expect(metadata['author'], equals('Joe Cool'));
      expect(metadata['revnumber'], equals('1.0'));
    });

    test('attribute entry overrides generated author initials', () {
      final doc = emptyDocument();
      final metadata = parseHeaderMetadata(
        'Stuart Rackham <founder@asciidoc.org>\n:Author Initials: SJR',
        doc,
      );
      expect(metadata['authorinitials'], equals('SR'));
      expect(doc.attributes['authorinitials'], equals('SJR'));
    });

    test('adjust indentation to 0', () {
      final lines = ['    def names', '', '      @name.split', '', '    end'];
      Parser.adjustIndentation(lines);
      expect(lines.join('\n'), equals('def names\n\n  @name.split\n\nend'));
    });

    test('adjust indentation mixed with tabs and spaces to 0', () {
      final lines = ['    def names', '', '\t  @name.split', '', '    end'];
      Parser.adjustIndentation(lines, 0, 4);
      expect(lines.join('\n'), equals('def names\n\n  @name.split\n\nend'));
    });

    test('expands tabs to spaces', () {
      final lines = [
        'Filesystem\t\t\t\tSize\tUsed\tAvail\tUse%\tMounted on',
        'Filesystem              Size    Used    Avail   Use%    Mounted on',
        'devtmpfs\t\t\t\t3.9G\t   0\t 3.9G\t  0%\t/dev',
        '/dev/mapper/fedora-root\t 48G\t 18G\t  29G\t 39%\t/',
      ];
      Parser.adjustIndentation(lines, 0, 4);
      expect(
        lines.join('\n'),
        equals(
          'Filesystem              Size    Used    Avail   Use%    Mounted on\n'
          'Filesystem              Size    Used    Avail   Use%    Mounted on\n'
          'devtmpfs                3.9G       0     3.9G     0%    /dev\n'
          '/dev/mapper/fedora-root  48G     18G      29G    39%    /',
        ),
      );
    });

    test('adjust indentation to non-zero', () {
      final lines = ['    def names', '', '      @name.split', '', '    end'];
      Parser.adjustIndentation(lines, 2);
      expect(
        lines.join('\n'),
        equals('  def names\n\n    @name.split\n\n  end'),
      );
    });

    test('preserve block indent if indent is -1', () {
      const input =
          '    def names\n'
          '\n'
          '      @name.split\n'
          '\n'
          '    end\n';
      // Ruby `String#lines` keeps the separators.
      final lines = RegExp(r'.*\n|.+$')
          .allMatches(input)
          .map((m) => m.group(0)!)
          .toList();
      Parser.adjustIndentation(lines, -1);
      expect(lines.join(), equals(input));
    });

    test('adjust indentation handles empty lines gracefully', () {
      final lines = <String>[];
      Parser.adjustIndentation(lines);
      expect(lines, isEmpty);
    });

    test('should warn if inline anchor is already in use', () {
      const input =
          '[#in-use]\n'
          'A paragraph with an id.\n'
          '\n'
          'Another paragraph\n'
          '[[in-use]]that uses an id\n'
          'which is already in use.\n';
      usingMemoryLogger((logger) {
        documentFromString(input);
        assertLogMessage(
          logger,
          Severity.warn,
          '<stdin>: line 5: id assigned to anchor already in use: in-use',
        );
      });
    });

    test('generates section ids from the fully substituted title', () {
      final doc = documentFromString('== A -- B\n\n== _Em_ *Strong*');
      expect(doc.blocks[0].id, equals('_ab'));
      expect(doc.blocks[1].id, equals('_em_strong'));
    });

    test('node applySubs defaults to the normal substitutions', () {
      final doc = documentFromString('text');
      expect(
        doc.applySubs('*a* -- b'),
        equals('<strong>a</strong>&#8201;&#8212;&#8201;b'),
      );
      expect(doc.applySubs('*a*', null), equals('*a*'));
    });

    test('applies normal substitutions to quote credits', () {
      final doc = documentFromString('> quoted\n> -- *Md* Author, _Book_\n');
      final quote = doc.blocks[0];
      expect(quote.attr('attribution'), equals('<strong>Md</strong> Author'));
      expect(quote.attr('citetitle'), equals('<em>Book</em>'));
    });

    test('marker-derived ordered list style has no list marker keyword', () {
      // Ruby assigns the implicit style as a Symbol, which misses the
      // String-keyed ORDERED_LIST_KEYWORDS, so no HTML type attribute is
      // emitted; an explicit style (a String) does get one.
      final implicit =
          documentFromString('a. one\nb. two').blocks[0] as ListBlock;
      expect(implicit.style, equals('loweralpha'));
      expect(implicit.listMarkerKeyword(), isNull);
      expect(implicit.listMarkerKeyword('loweralpha'), equals('a'));
      final explicit =
          documentFromString('[loweralpha]\n. one\n. two').blocks[0]
              as ListBlock;
      expect(explicit.listMarkerKeyword(), equals('a'));
      final nested = documentFromString('. one\n.. two').blocks[0] as ListBlock;
      final inner = nested.items[0].blocks[0] as ListBlock;
      expect(inner.style, equals('loweralpha'));
      expect(inner.listMarkerKeyword(), equals('a'));
    });
  });
}
