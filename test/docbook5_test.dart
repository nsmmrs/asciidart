/// Tests for the DocBook 5 converter port (`docbook5.dart`).
///
/// Port of the docbook-output assertions in the Ruby suite
/// (`test/blocks_test.rb`, `test/sections_test.rb`, `test/lists_test.rb`,
/// `test/tables_test.rb`, `test/document_test.rb`, etc.). Nodes are
/// constructed directly (no parsing); each test converts one node through
/// [Docbook5Converter.convert] and asserts the exact XML string
/// (byte-identical contract per `adr/0001-dart-rewrite-goals.md` D4).
///
/// Substitution-dependent paths are covered with stub nodes ([StubBlock],
/// [StubSection], [StubListItem], [StubListBlock], [StubCell], [StubTable],
/// [StubInline], [StubDocument]) that return fixed content/titles/text,
/// using plain-text inputs for which the real substitutions are the
/// identity. The tests that need real substitution output parse small
/// sources via [parseDoc] instead (the parser and substitutors waves are
/// merged).
library;

import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

/// Records log messages for assertions.
class FakeLogger extends LoggerBase {
  /// Creates a recording logger.
  new() : super(Severity.warn);

  /// Warning messages, in logging order.
  final List<String> warns = <String>[];

  /// Error messages, in logging order.
  final List<String> errors = <String>[];

  @override
  Severity? get maxSeverity => null;

  @override
  void add(Severity severity, LogMessage message) {
    if (severity == Severity.warn) warns.add('$message');
    if (severity == Severity.error) errors.add('$message');
  }

  @override
  Future<void> close() async {}
}

/// Runs [body] with a recording logger installed.
void usingMemoryLogger(void Function(FakeLogger logger) body) {
  final saved = LoggerManager.logger;
  final logger = FakeLogger();
  LoggerManager.logger = logger;
  try {
    body(logger);
  } finally {
    LoggerManager.logger = saved;
  }
}

/// A block returning fixed content/title/alt/reftext (avoids the
/// substitutors wave).
class StubBlock extends Block {
  /// Creates a stub block with fixed [content], [title], [alt] and
  /// [reftext].
  new(
    super.parent,
    super.context, {
    super.attributes,
    super.contentModel,
    this.stubbedContent = '',
    this.stubTitle,
    this.stubAlt,
    this.stubReftext,
    this.contentFn,
    this.childContent = false,
  });

  /// The value [content] returns.
  final String? stubbedContent;

  /// The value [title] returns (`null` means [hasTitle] is false).
  final String? stubTitle;

  /// The value [alt] returns (`null` means the empty string).
  final String? stubAlt;

  /// The value [reftext] returns.
  final String? stubReftext;

  /// Computes [content] dynamically when set (takes precedence over
  /// [stubbedContent]).
  final String? Function()? contentFn;

  /// Whether [content] converts the child blocks (for compound parents
  /// with a stubbed title; takes precedence over [stubbedContent] but not
  /// [contentFn]).
  final bool childContent;

  @override
  String? content() {
    if (contentFn != null) return contentFn!();
    if (childContent) return super.content();
    return stubbedContent;
  }

  @override
  String? get title => stubTitle;

  @override
  bool get hasTitle => stubTitle != null;

  @override
  String get alt => stubAlt ?? '';

  @override
  String? get reftext => stubReftext;
}

/// A section returning a fixed title (avoids the substitutors wave).
class StubSection extends Section {
  /// Creates a stub section with fixed [title].
  new({
    AbstractBlock? parent,
    int? level,
    bool numbered = false,
    Map<String, String>? attributes,
    this.stubTitle,
  }) : super(parent, level) {
    this.numbered = numbered;
    if (attributes != null) updateAttributes(attributes);
  }

  /// The value [title] returns (`null` means [hasTitle] is false).
  final String? stubTitle;

  @override
  String? get title => stubTitle;

  @override
  bool get hasTitle => stubTitle != null;
}

/// A list item returning fixed text (avoids the substitutors wave).
class StubListItem extends ListItem {
  /// Creates a stub item with fixed [text].
  new(super.parent, [super.text]) : stubText = text;

  /// The value [text] returns.
  final String? stubText;

  @override
  String? get text => stubText;
}

/// A list returning a fixed title (avoids the substitutors wave).
class StubListBlock extends ListBlock {
  /// Creates a stub list with fixed [title].
  new(super.parent, super.context, {super.attributes, this.stubTitle});

  /// The value [title] returns (`null` means [hasTitle] is false).
  final String? stubTitle;

  @override
  String? get title => stubTitle;

  @override
  bool get hasTitle => stubTitle != null;
}

/// A table cell returning fixed text/content (avoids the substitutors wave).
class StubCell extends Cell {
  /// Creates a stub cell with fixed [text] and [content].
  new(
    Column? column,
    String? cellText, {
    CellSpec? spec = const CellSpec(),
    this.stubText,
    this.stubParagraphs = const <String>[],
    this.stubContent = '',
  }) : super(column, cellText, spec);

  /// The value [text] returns.
  final String? stubText;

  /// The value [paragraphs] returns.
  final List<String> stubParagraphs;

  /// The value [content] returns.
  final String stubContent;

  @override
  String get text => stubText ?? '';

  @override
  List<String> get paragraphs => stubParagraphs;

  @override
  String content() => stubContent;
}

/// A table returning a fixed title (avoids the substitutors wave).
class StubTable extends Table {
  /// Creates a stub table with fixed [title].
  new(super.parent, super.attributes, {this.stubTitle});

  /// The value [title] returns (`null` means [hasTitle] is false).
  final String? stubTitle;

  @override
  String? get title => stubTitle;

  @override
  bool get hasTitle => stubTitle != null;
}

/// An inline node returning fixed reftext (avoids the substitutors wave).
class StubInline extends Inline {
  /// Creates a stub inline node with fixed [reftext].
  new(
    super.parent,
    super.context, {
    super.text,
    super.attributes,
    super.id,
    super.type,
    super.target,
    this.stubReftext,
  });

  /// The value [reftext] returns.
  final String? stubReftext;

  @override
  String? get reftext => stubReftext;
}

/// A document applying identity substitutions (for plain-text inputs only).
///
/// Real `sub_replacements` / `apply_reftext_subs` output is the
/// substitutors wave's job; the converter tests only use inputs without
/// substitutable characters, for which the identity is byte-identical.
class StubDocument extends Document {
  /// Creates a stub document (see [Document.new]).
  new([super.source, super.options]);

  @override
  String subReplacements(String text) => text;

  @override
  String applyReftextSubs(String text) => text;
}

/// Creates a document with a [Docbook5Converter] installed.
///
/// [attributes] are assigned directly; [options] go to the constructor.
/// When [plainSubs] is set, a [StubDocument] (identity substitutions) is
/// returned.
Document makeDoc({
  Map<String, String> attributes = const <String, String>{},
  AsciidoctorOptions options = const AsciidoctorOptions(),
  bool plainSubs = false,
}) {
  final opts = options.copyWith(
    backend: 'docbook5',
    standalone: options.standalone ?? true,
  );
  return (plainSubs ? StubDocument(null, opts) : Document(null, opts))
    ..converter = Docbook5Converter('docbook5')
    ..attributes.addAll(attributes);
}

/// The [Docbook5Converter] installed on [doc].
Docbook5Converter convOf(Document doc) => doc.converter as Docbook5Converter;

/// Parses [src] into a standalone DocBook document (port of the
/// `document_from_string` test helper), for the tests that need real
/// substitution output now that the parser and substitutors waves are
/// merged.
Document parseDoc(
  String src, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => Document(
  src,
  options.copyWith(backend: 'docbook5', standalone: options.standalone ?? true),
).parse();

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/vendor/asciidoctor/test/fixtures')
            .existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'repository checkout not found above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Assigns a header with [title] to [doc].
void setDocHeader(Document doc, String title) {
  final header = StubSection(parent: doc, level: 0, stubTitle: title)
    ..sectname = 'header';
  doc.header = header;
}

/// Creates a paragraph stub under [parent] with [text] content.
StubBlock para(
  AbstractBlock parent, [
  String text = '',
  Map<String, String> attributes = const <String, String>{},
  String? title,
]) => StubBlock(
  parent,
  BlockContext.paragraph,
  attributes: Map<String, String>.of(attributes),
  stubbedContent: text,
  stubTitle: title,
);

void main() {
  group('registration', () {
    test('registerFor registers the docbook5 backend as provided', () {
      Docbook5Converter.registerFor();
      final created = Converter.create('docbook5');
      expect(created, isA<Docbook5Converter>());
      expect(created!.backend, 'docbook5');
      // Provided registrations survive unregisterAll (mirrors PROVIDED).
      Converter.unregisterAll();
      expect(Converter.create('docbook5'), isA<Docbook5Converter>());
    });

    test('backend traits mirror init_backend_traits', () {
      final traits = Docbook5Converter('docbook5').backendTraits;
      expect(traits.basebackend, 'docbook');
      expect(traits.filetype, 'xml');
      expect(traits.outfilesuffix, '.xml');
      expect(traits.supportsTemplates, isTrue);
    });

    test('handles reports every template transform', () {
      final conv = Docbook5Converter('docbook5');
      for (final transform in const [
        'admonition',
        'audio',
        'colist',
        'dlist',
        'document',
        'embedded',
        'example',
        'floating_title',
        'image',
        'inline_anchor',
        'inline_break',
        'inline_button',
        'inline_callout',
        'inline_footnote',
        'inline_image',
        'inline_indexterm',
        'inline_kbd',
        'inline_menu',
        'inline_quoted',
        'listing',
        'literal',
        'olist',
        'open',
        'page_break',
        'paragraph',
        'pass',
        'preamble',
        'quote',
        'section',
        'sidebar',
        'stem',
        'table',
        'thematic_break',
        'toc',
        'ulist',
        'verse',
        'video',
      ]) {
        expect(conv.handles(transform), isTrue, reason: transform);
      }
      expect(conv.handles('outline'), isFalse);
    });
  });

  group('convertDocument', () {
    test('minimal document without header', () {
      final doc = makeDoc(attributes: const {'noheader': ''});
      expect(
        convOf(doc).convert(doc),
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<article xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0" xml:lang="en">\n'
        '</article>',
      );
    });

    test('toc and sectnums processing instructions', () {
      final doc = makeDoc(
        attributes: const {'noheader': '', 'toc': '', 'sectnums': ''},
      );
      expect(
        convOf(doc).convert(doc),
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<?asciidoc-toc?>\n'
        '<?asciidoc-numbered?>\n'
        '<article xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0" xml:lang="en">\n'
        '</article>',
      );
    });

    test('toc and sectnums maxdepth processing instructions', () {
      final doc = makeDoc(
        attributes: const {
          'noheader': '',
          'toc': '',
          'toclevels': '1',
          'sectnums': '',
          'sectnumlevels': '2',
        },
      );
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<?asciidoc-toc maxdepth="1"?>\n'));
      expect(output, contains('<?asciidoc-numbered maxdepth="2"?>\n'));
    });

    test('nolang suppresses xml:lang', () {
      final doc = makeDoc(attributes: const {'noheader': '', 'nolang': ''});
      expect(
        convOf(doc).convert(doc),
        contains(
          '<article xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0">\n',
        ),
      );
    });

    test('lang attribute sets xml:lang', () {
      final doc = makeDoc(attributes: const {'noheader': '', 'lang': 'fr'});
      expect(
        convOf(doc).convert(doc),
        contains('version="5.0" xml:lang="fr">\n'),
      );
    });

    test('document id is deferred to the root tag', () {
      final doc = makeDoc(attributes: const {'noheader': ''})..id = 'mydoc';
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('xml:lang="en" xml:id="mydoc">\n'));
      expect(doc.id, 'mydoc');
    });

    test('document id generated on demand is reset after conversion', () {
      final doc = makeDoc(attributes: const {'noheader': ''});
      late Inline xref;
      final block = StubBlock(
        doc,
        BlockContext.paragraph,
        contentFn: () => convOf(doc).convert(xref)!,
      );
      doc.append(block);
      xref = Inline(block, InlineContext.anchor, type: 'xref');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('xml:lang="en" xml:id="__article-root__">\n'));
      expect(output, contains('<xref linkend="__article-root__"/>'));
      expect(doc.id, isNull);
    });

    test('document with header and single author', () {
      final doc = makeDoc(
        attributes: const {
          'author': 'John Doe',
          'firstname': 'John',
          'lastname': 'Doe',
          'email': 'john@example.com',
          'authorinitials': 'JD',
          'reproducible': '',
        },
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      expect(
        convOf(doc).convert(doc),
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<article xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0" xml:lang="en">\n'
        '<info>\n'
        '<title>Doc Title</title>\n'
        '<author>\n'
        '<personname>\n'
        '<firstname>John</firstname>\n'
        '<surname>Doe</surname>\n'
        '</personname>\n'
        '<email>john@example.com</email>\n'
        '</author>\n'
        '<authorinitials>JD</authorinitials>\n'
        '</info>\n'
        '</article>',
      );
    });

    test('document title with subtitle', () {
      final doc = makeDoc(
        attributes: const {'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Main Title: Sub Title');
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains('<title>Main Title</title>\n<subtitle>Sub Title</subtitle>\n'),
      );
    });

    test('revdate without reproducible emits date', () {
      final doc = makeDoc(
        attributes: const {'revdate': '2024-01-02'},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<date>2024-01-02</date>\n'));
    });

    test('docdate emits date unless reproducible', () {
      final doc = makeDoc(plainSubs: true);
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<date>${doc.attr('docdate')}</date>\n'));
    });

    test('revhistory with revnumber and revremark', () {
      final doc = makeDoc(
        attributes: const {
          'revdate': '2024-01-02',
          'revnumber': '1.0',
          'authorinitials': 'JD',
          'revremark': 'First release',
        },
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains(
          '<revhistory>\n'
          '<revision>\n'
          '<revnumber>1.0</revnumber>\n'
          '<date>2024-01-02</date>\n'
          '<authorinitials>JD</authorinitials>\n'
          '<revremark>First release</revremark>\n'
          '</revision>\n'
          '</revhistory>\n',
        ),
      );
    });

    test('multiple authors use authorgroup', () {
      final doc = makeDoc(
        attributes: const {
          'author': 'John Doe',
          'firstname': 'John',
          'lastname': 'Doe',
          'authorcount': '2',
          'author_2': 'Jane Roe',
          'firstname_2': 'Jane',
          'lastname_2': 'Roe',
          'reproducible': '',
        },
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<authorgroup>\n'));
      expect(output, contains('<firstname>John</firstname>\n'));
      expect(output, contains('<firstname>Jane</firstname>\n'));
      expect(output, contains('</authorgroup>\n'));
      expect(output, isNot(contains('<authorinitials>')));
    });

    test('copyright with year', () {
      final doc = makeDoc(
        attributes: const {'copyright': 'Acme Corp 2020', 'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains(
          '<copyright>\n<holder>Acme Corp</holder>\n<year>2020</year>\n</copyright>\n',
        ),
      );
    });

    test('copyright with year range', () {
      final doc = makeDoc(
        attributes: const {'copyright': 'Acme 2019-2020', 'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains('<holder>Acme</holder>\n<year>2019-2020</year>\n'),
      );
    });

    test('copyright without year', () {
      final doc = makeDoc(
        attributes: const {'copyright': 'Acme Corp', 'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<copyright>\n<holder>Acme Corp</holder>\n'));
      expect(output, isNot(contains('<year>')));
    });

    test('orgname', () {
      final doc = makeDoc(
        attributes: const {'orgname': 'Acme', 'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<orgname>Acme</orgname>\n'));
    });

    test('front cover image', () {
      final doc = makeDoc(
        attributes: const {
          'front-cover-image': 'cover.png',
          'reproducible': '',
        },
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains(
          '<cover role="front">\n'
          '<mediaobject>\n'
          '<imageobject>\n'
          '<imagedata fileref="cover.png"/>\n'
          '</imageobject>\n'
          '</mediaobject>\n'
          '</cover>\n',
        ),
      );
    });

    test('front cover image macro with sizes', () {
      final doc = makeDoc(
        attributes: const {
          'front-cover-image': 'image::cover.png[Cover,800,600]',
          'reproducible': '',
        },
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains(
          '<imagedata fileref="cover.png" contentwidth="800" contentdepth="600"/>\n',
        ),
      );
    });

    test('back cover image implies front placeholder', () {
      final doc = makeDoc(
        attributes: const {'back-cover-image': 'back.png', 'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final output = convOf(doc).convert(doc)!;
      expect(output, contains('<cover role="front"/>\n<cover role="back">\n'));
    });

    test('manpage document', () {
      final doc = makeDoc(
        attributes: const {
          'noheader': '',
          'mantitle': 'mycmd',
          'manvolnum': '1',
          'mansource': 'My Project',
          'manmanual': 'User Commands',
          'mannames': '',
          'manpurpose': 'do things',
        },
        options: const AsciidoctorOptions(doctype: 'manpage'),
        plainSubs: true,
      )..mannames = ['mycmd', 'my-alias'];
      expect(
        convOf(doc).convert(doc),
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<article xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0" xml:lang="en">\n'
        '<refentry>\n'
        '<refmeta>\n'
        '<refentrytitle>mycmd</refentrytitle>\n'
        '<manvolnum>1</manvolnum>\n'
        '<refmiscinfo class="source">My Project</refmiscinfo>\n'
        '<refmiscinfo class="manual">User Commands</refmiscinfo>\n'
        '</refmeta>\n'
        '<refnamediv>\n'
        '<refname>mycmd</refname>\n'
        '<refname>my-alias</refname>\n'
        '<refpurpose>do things</refpurpose>\n'
        '</refnamediv>\n'
        '</refentry>\n'
        '</article>',
      );
    });

    test('manpage defaults source and manual to nbsp', () {
      final doc = makeDoc(
        attributes: const {'noheader': '', 'mantitle': 'mycmd'},
        options: const AsciidoctorOptions(doctype: 'manpage'),
        plainSubs: true,
      );
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains('<refmiscinfo class="source">&#160;</refmiscinfo>\n'),
      );
      expect(
        output,
        contains('<refmiscinfo class="manual">&#160;</refmiscinfo>\n'),
      );
      expect(output, isNot(contains('<manvolnum>')));
      expect(output, isNot(contains('<refname>')));
      expect(output, isNot(contains('<refpurpose>')));
    });

    test('manpage title with markup', () {
      // Port of document_test.rb 'should apply replacements substitution
      // to value of mantitle attribute used in DocBook output'.
      const input =
          '= foo\\--bar(1)\n'
          'Author Name\n'
          ':doctype: manpage\n'
          ':man manual: Foo Bar Manual\n'
          ':man source: Foo Bar 1.0\n'
          '\n'
          '== NAME\n'
          '\n'
          'foo--bar - puts the foo in your bar\n';
      final doc = parseDoc(input);
      expect(doc.attr('mantitle'), equals(r'foo\--bar'));
      final result = doc.convert();
      expect(result, contains('<title>foo--bar(1)</title>'));
      expect(result, contains('<refentrytitle>foo--bar</refentrytitle>'));
    });

    test('root abstract moves to info tag', () {
      final doc = makeDoc(
        attributes: const {'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final abstract = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'Abstract text',
      )..style = 'abstract';
      doc.append(abstract);
      doc.append(para(doc, 'Body text'));
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains('<abstract>\n<simpara>Abstract text</simpara>\n</abstract>\n'),
      );
      expect(output, contains('<simpara>Body text</simpara>\n'));
      expect(
        output.indexOf('<simpara>Abstract text</simpara>'),
        lessThan(output.indexOf('<simpara>Body text</simpara>')),
      );
      // The abstract is restored to the document tree after conversion.
      expect(doc.blocks[0], same(abstract));
      expect(abstract.hasOption('root'), isFalse);
    });

    test('abstract inside preamble moves to info tag', () {
      final doc = makeDoc(
        attributes: const {'reproducible': ''},
        plainSubs: true,
      );
      setDocHeader(doc, 'Doc Title');
      final preamble = Block(
        doc,
        BlockContext.preamble,
        contentModel: ContentModel.compound,
      );
      final abstract = StubBlock(
        preamble,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'Abstract text',
      )..style = 'abstract';
      preamble.append(abstract);
      doc.append(preamble);
      doc.append(para(doc, 'Body text'));
      final output = convOf(doc).convert(doc)!;
      expect(
        output,
        contains('<abstract>\n<simpara>Abstract text</simpara>\n</abstract>\n'),
      );
      expect(output, contains('<simpara>Body text</simpara>\n'));
      // The preamble is restored to the document tree after conversion.
      expect(doc.blocks[0], same(preamble));
      expect(preamble.blocks, [same(abstract)]);
    });

    test('body blocks are joined with line feeds', () {
      final doc = makeDoc(attributes: const {'noheader': ''});
      doc.append(para(doc, 'one'));
      doc.append(para(doc, 'two'));
      expect(
        convOf(doc).convert(doc),
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<article xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0" xml:lang="en">\n'
        '<simpara>one</simpara>\n'
        '<simpara>two</simpara>\n'
        '</article>',
      );
    });

    test(testOn: 'vm', 'docinfo files are included', () {
      // Slice of document_test.rb 'should include docinfo files in docbook
      // backend': the private `basic-docinfo.xml` lands in the header and
      // the shared `docinfo.xml` (with `{revnumber}` substituted) under
      // `docinfo1`.
      final output = loadFile(
        '${_findRepoRoot()}/vendor/asciidoctor/test/fixtures/basic.adoc',
        options: const AsciidoctorOptions(
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo': ''},
        ),
      ).convert();
      expect(output, isNotEmpty);
      expect(output, contains('<copyright>'));
      expect(output, isNot(contains('<productname>')));

      final sharedOutput = loadFile(
        '${_findRepoRoot()}/vendor/asciidoctor/test/fixtures/basic.adoc',
        options: const AsciidoctorOptions(
          standalone: true,
          backend: 'docbook',
          safe: SafeMode.server,
          attributes: {'docinfo1': ''},
        ),
      ).convert();
      expect(sharedOutput, isNotEmpty);
      expect(sharedOutput, contains('<productname>Asciidoctor™</productname>'));
      expect(sharedOutput, contains('<edition>1.0</edition>'));
      expect(sharedOutput, isNot(contains('<copyright>')));
    });

    test('full document from source', () {
      // Oracle from Ruby `Asciidoctor.convert` of the same input with
      // `backend: 'docbook'`; exercises the full document template in
      // `lib/asciidoctor/converter/docbook5.rb`.
      const input = '= Doc Title\nAuthor Name\n\nHello, *world*!\n';
      final output = parseDoc(input).convert();
      expect(output, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(output, contains('<article'));
      expect(output, contains('<title>Doc Title</title>'));
      expect(
        output,
        contains(
          '<simpara>Hello, <emphasis role="strong">world</emphasis>!</simpara>',
        ),
      );
    });
  });

  group('convertEmbedded', () {
    test('body blocks without root element', () {
      final doc = makeDoc();
      doc.append(para(doc, 'one'));
      doc.append(para(doc, 'two'));
      expect(
        convOf(doc).convert(doc, 'embedded'),
        '<simpara>one</simpara>\n<simpara>two</simpara>',
      );
    });

    test('root abstract is excluded from embedded output', () {
      final doc = makeDoc();
      final abstract = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'Abstract text',
      )..style = 'abstract';
      doc.append(abstract);
      doc.append(para(doc, 'Body text'));
      expect(
        convOf(doc).convert(doc, 'embedded'),
        '<simpara>Body text</simpara>',
      );
      expect(doc.blocks[0], same(abstract));
    });

    test('abstract is retained when backend is not docbook5', () {
      final doc = (makeDoc())..converter = Docbook5Converter('docbook45');
      final abstract = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'Abstract text',
      )..style = 'abstract';
      doc.append(abstract);
      expect(
        convOf(doc).convert(doc, 'embedded'),
        '<abstract>\n<simpara>Abstract text</simpara>\n</abstract>',
      );
    });
  });

  group('convertSection', () {
    test('section with title and content', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 1,
        stubTitle: 'Section Title',
      )..sectname = 'section';
      section.append(para(section, 'content'));
      expect(
        convOf(doc).convert(section),
        '<section>\n'
        '<title>Section Title</title>\n'
        '<simpara>content</simpara>\n'
        '</section>',
      );
    });

    test('section with id and role', () {
      final doc = makeDoc();
      final section =
          StubSection(
              parent: doc,
              level: 1,
              attributes: const {'role': 'lead'},
              stubTitle: 'Section Title',
            )
            ..sectname = 'section'
            ..id = 'section_title';
      section.append(para(section, 'content'));
      expect(
        convOf(doc).convert(section),
        '<section xml:id="section_title" role="lead">\n'
        '<title>Section Title</title>\n'
        '<simpara>content</simpara>\n'
        '</section>',
      );
    });

    test('special section with notitle option omits title', () {
      final doc = makeDoc();
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Hidden')
        ..sectname = 'appendix'
        ..special = true
        ..setOption('notitle');
      section.append(para(section, 'content'));
      expect(
        convOf(doc).convert(section),
        '<appendix>\n<simpara>content</simpara>\n</appendix>',
      );
    });

    test('manpage section maps to refsection', () {
      final doc = makeDoc(
        options: const AsciidoctorOptions(doctype: 'manpage'),
      );
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Name')
        ..sectname = 'section';
      section.append(para(section, 'mycmd - do things'));
      expect(
        convOf(doc).convert(section),
        '<refsection>\n'
        '<title>Name</title>\n'
        '<simpara>mycmd - do things</simpara>\n'
        '</refsection>',
      );
    });

    test('manpage synopsis section maps to refsynopsisdiv', () {
      final doc = makeDoc(
        options: const AsciidoctorOptions(doctype: 'manpage'),
      );
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Synopsis')
        ..sectname = 'synopsis';
      expect(
        convOf(doc).convert(section),
        '<refsynopsisdiv>\n<title>Synopsis</title>\n\n</refsynopsisdiv>',
      );
    });
  });

  group('convertAdmonition', () {
    test('admonition with simple content', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.admonition,
        attributes: const {'name': 'NOTE'},
        contentModel: ContentModel.simple,
        stubbedContent: 'Be careful',
      );
      expect(
        convOf(doc).convert(node),
        '<NOTE>\n<simpara>Be careful</simpara>\n</NOTE>',
      );
    });

    test('admonition with title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.admonition,
        attributes: const {'name': 'TIP'},
        contentModel: ContentModel.simple,
        stubbedContent: 'Useful',
        stubTitle: 'Take note',
      );
      expect(
        convOf(doc).convert(node),
        '<TIP>\n<title>Take note</title>\n<simpara>Useful</simpara>\n</TIP>',
      );
    });

    test('admonition with compound content', () {
      final doc = makeDoc();
      final node = Block(
        doc,
        BlockContext.admonition,
        attributes: const {'name': 'WARNING'},
        contentModel: ContentModel.compound,
      );
      node.append(para(node, 'first'));
      node.append(para(node, 'second'));
      expect(
        convOf(doc).convert(node),
        '<WARNING>\n'
        '<simpara>first</simpara>\n'
        '<simpara>second</simpara>\n'
        '</WARNING>',
      );
    });
  });

  group('convertColist', () {
    test('callout list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.colist);
      final item = StubListItem(list, 'About this line')
        ..attributes['coids'] = 'CO1-1';
      list.append(item);
      expect(
        convOf(doc).convert(list),
        '<calloutlist>\n'
        '<callout arearefs="CO1-1">\n'
        '<para>About this line</para>\n'
        '</callout>\n'
        '</calloutlist>',
      );
    });

    test('callout list with title and nested blocks', () {
      final doc = makeDoc();
      final list = StubListBlock(
        doc,
        BlockContext.colist,
        stubTitle: 'Callouts',
      );
      final item = StubListItem(list, 'About this line')
        ..attributes['coids'] = 'CO1-1 CO1-2';
      item.append(para(item, 'Extra detail'));
      list.append(item);
      expect(
        convOf(doc).convert(list),
        '<calloutlist>\n'
        '<title>Callouts</title>\n'
        '<callout arearefs="CO1-1 CO1-2">\n'
        '<para>About this line</para>\n'
        '<simpara>Extra detail</simpara>\n'
        '</callout>\n'
        '</calloutlist>',
      );
    });
  });

  group('convertDlist', () {
    ListBlock dlist(Document doc, {String? style, String? title, String? id}) {
      final list = StubListBlock(doc, BlockContext.dlist, stubTitle: title)
        ..style = style
        ..id = id;
      final terms = [StubListItem(list, 'term')];
      final dd = StubListItem(list, 'description');
      list.entries.add(DlistEntry(terms, dd));
      return list;
    }

    test('description list uses variablelist', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(dlist(doc)),
        '<variablelist>\n'
        '<varlistentry>\n'
        '<term>term</term>\n'
        '<listitem>\n'
        '<simpara>description</simpara>\n'
        '</listitem>\n'
        '</varlistentry>\n'
        '</variablelist>',
      );
    });

    test('qanda list', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(dlist(doc, style: 'qanda')),
        '<qandaset>\n'
        '<qandaentry>\n'
        '<question>\n'
        '<simpara>term</simpara>\n'
        '</question>\n'
        '<answer>\n'
        '<simpara>description</simpara>\n'
        '</answer>\n'
        '</qandaentry>\n'
        '</qandaset>',
      );
    });

    test('glossary list has no list wrapper', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(dlist(doc, style: 'glossary')),
        '<glossentry>\n'
        '<glossterm>term</glossterm>\n'
        '<glossdef>\n'
        '<simpara>description</simpara>\n'
        '</glossdef>\n'
        '</glossentry>',
      );
    });

    test('titled list with id', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(dlist(doc, title: 'Terms', id: 'terms')),
        '<variablelist xml:id="terms">\n'
        '<title>Terms</title>\n'
        '<varlistentry>\n'
        '<term>term</term>\n'
        '<listitem>\n'
        '<simpara>description</simpara>\n'
        '</listitem>\n'
        '</varlistentry>\n'
        '</variablelist>',
      );
    });

    test('term without description', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.dlist);
      list.entries.add(DlistEntry([StubListItem(list, 'lonely')]));
      expect(
        convOf(doc).convert(list),
        '<variablelist>\n'
        '<varlistentry>\n'
        '<term>lonely</term>\n'
        '<listitem>\n'
        '</listitem>\n'
        '</varlistentry>\n'
        '</variablelist>',
      );
    });

    test('description with nested blocks', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.dlist);
      final dd = StubListItem(list)..text = null;
      dd.append(para(dd, 'nested'));
      list.entries.add(DlistEntry([StubListItem(list, 'term')], dd));
      expect(
        convOf(doc).convert(list),
        '<variablelist>\n'
        '<varlistentry>\n'
        '<term>term</term>\n'
        '<listitem>\n'
        '<simpara>nested</simpara>\n'
        '</listitem>\n'
        '</varlistentry>\n'
        '</variablelist>',
      );
    });

    test('horizontal list without title', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(dlist(doc, style: 'horizontal')),
        '<informaltable tabstyle="horizontal" frame="none" colsep="0" '
        'rowsep="0">\n'
        '<tgroup cols="2">\n'
        '<colspec colwidth="15*"/>\n'
        '<colspec colwidth="85*"/>\n'
        '<tbody valign="top">\n'
        '<row>\n'
        '<entry>\n'
        '<simpara>term</simpara>\n'
        '</entry>\n'
        '<entry>\n'
        '<simpara>description</simpara>\n'
        '</entry>\n'
        '</row>\n'
        '</tbody>\n'
        '</tgroup>\n'
        '</informaltable>',
      );
    });

    test('horizontal list with title and widths', () {
      final doc = makeDoc();
      final list = dlist(doc, style: 'horizontal', title: 'Terms')
        ..attributes['labelwidth'] = '30'
        ..attributes['itemwidth'] = '70';
      final output = convOf(doc).convert(list)!;
      expect(
        output,
        startsWith(
          '<table tabstyle="horizontal" frame="none" colsep="0" rowsep="0">\n'
          '<title>Terms</title>\n'
          '<tgroup cols="2">\n'
          '<colspec colwidth="30*"/>\n'
          '<colspec colwidth="70*"/>\n',
        ),
      );
      expect(output, endsWith('</tbody>\n</tgroup>\n</table>'));
    });
  });

  group('convertExample', () {
    test('example with title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.example,
        contentModel: ContentModel.compound,
        stubTitle: 'Example',
        childContent: true,
      );
      node.append(para(node, 'content'));
      expect(
        convOf(doc).convert(node),
        '<example>\n'
        '<title>Example</title>\n'
        '<simpara>content</simpara>\n'
        '</example>',
      );
    });

    test('example without title uses informalexample', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.example,
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
      );
      expect(
        convOf(doc).convert(node),
        '<informalexample>\n<simpara>content</simpara>\n</informalexample>',
      );
    });
  });

  group('convertFloatingTitle', () {
    test('floating title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.floatingTitle,
        stubTitle: 'Floating',
      )..level = 2;
      expect(
        convOf(doc).convert(node),
        '<bridgehead renderas="sect2">Floating</bridgehead>',
      );
    });

    test('floating title with id and role', () {
      final doc = makeDoc();
      final node =
          StubBlock(
              doc,
              BlockContext.floatingTitle,
              attributes: const {'role': 'small'},
              stubTitle: 'Floating',
            )
            ..level = 3
            ..id = 'float';
      expect(
        convOf(doc).convert(node),
        '<bridgehead xml:id="float" role="small" renderas="sect3">Floating</bridgehead>',
      );
    });
  });

  group('convertImage', () {
    test('image without title uses informalfigure', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.image,
        attributes: const {'target': 'diagram.png'},
        stubAlt: 'Diagram',
      );
      expect(
        convOf(doc).convert(node),
        '<informalfigure>\n'
        '<mediaobject>\n'
        '<imageobject>\n'
        '<imagedata fileref="diagram.png"/>\n'
        '</imageobject>\n'
        '<textobject><phrase>Diagram</phrase></textobject>\n'
        '</mediaobject>\n'
        '</informalfigure>',
      );
    });

    test('image with title, align and sizes', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.image,
        attributes: const {
          'target': 'diagram.png',
          'align': 'center',
          'width': '800',
          'height': '600',
        },
        stubAlt: 'Diagram',
        stubTitle: 'Diagram',
      )..id = 'diagram';
      expect(
        convOf(doc).convert(node),
        '<figure xml:id="diagram">\n'
        '<title>Diagram</title>\n'
        '<mediaobject>\n'
        '<imageobject>\n'
        '<imagedata fileref="diagram.png" contentwidth="800" contentdepth="600" align="center"/>\n'
        '</imageobject>\n'
        '<textobject><phrase>Diagram</phrase></textobject>\n'
        '</mediaobject>\n'
        '</figure>',
      );
    });

    test('image with scaledwidth', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.image,
        attributes: const {'target': 'diagram.png', 'scaledwidth': '50%'},
      );
      final output = convOf(doc).convert(node)!;
      expect(
        output,
        contains('<imagedata fileref="diagram.png" width="50%"/>\n'),
      );
    });

    test('image with scale', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.image,
        attributes: const {'target': 'diagram.png', 'scale': '80'},
      );
      final output = convOf(doc).convert(node)!;
      expect(
        output,
        contains('<imagedata fileref="diagram.png" scale="80"/>\n'),
      );
    });
  });

  group('convertListing', () {
    test('listing without title uses screen', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.listing,
        contentModel: ContentModel.verbatim,
        stubbedContent: 'listing block',
      );
      expect(convOf(doc).convert(node), '<screen>listing block</screen>');
    });

    test('listing with title uses formalpara', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.listing,
        contentModel: ContentModel.verbatim,
        stubbedContent: 'listing block',
        stubTitle: 'title',
      );
      expect(
        convOf(doc).convert(node),
        '<formalpara>\n'
        '<title>title</title>\n'
        '<para>\n'
        '<screen>listing block</screen>\n'
        '</para>\n'
        '</formalpara>',
      );
    });

    test('source block with language', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.listing,
        attributes: const {'language': 'ruby'},
        contentModel: ContentModel.verbatim,
        stubbedContent: 'puts 1',
      )..style = 'source';
      expect(
        convOf(doc).convert(node),
        '<programlisting language="ruby" linenumbering="unnumbered">puts 1</programlisting>',
      );
    });

    test('source block with linenums and start', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.listing,
        attributes: const {'language': 'ruby', 'linenums': '', 'start': '3'},
        contentModel: ContentModel.verbatim,
        stubbedContent: 'puts 1',
      )..style = 'source';
      expect(
        convOf(doc).convert(node),
        '<programlisting language="ruby" linenumbering="numbered" startinglinenumber="3">puts 1</programlisting>',
      );
    });

    test('source block without language uses screen', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.listing,
        contentModel: ContentModel.verbatim,
        stubbedContent: 'code',
        stubTitle: 'title',
      )..style = 'source';
      expect(
        convOf(doc).convert(node),
        '<formalpara>\n'
        '<title>title</title>\n'
        '<para>\n'
        '<screen linenumbering="unnumbered">code</screen>\n'
        '</para>\n'
        '</formalpara>',
      );
    });
  });

  group('convertLiteral', () {
    test('literal without title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.literal,
        contentModel: ContentModel.verbatim,
        stubbedContent: 'literal',
      );
      expect(
        convOf(doc).convert(node),
        '<literallayout class="monospaced">literal</literallayout>',
      );
    });

    test('literal with title uses formalpara', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.literal,
        contentModel: ContentModel.verbatim,
        stubbedContent: 'literal',
        stubTitle: 'title',
      );
      expect(
        convOf(doc).convert(node),
        '<formalpara>\n'
        '<title>title</title>\n'
        '<para>\n'
        '<literallayout class="monospaced">literal</literallayout>\n'
        '</para>\n'
        '</formalpara>',
      );
    });
  });

  group('convertStem', () {
    test('latexmath stem without title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.stem,
        contentModel: ContentModel.raw,
        stubbedContent: 'x^2',
      )..style = 'latexmath';
      expect(
        convOf(doc).convert(node),
        '<informalequation>\n'
        '<alt><![CDATA[x^2]]></alt>'
        '\n'
        '<mathphrase><![CDATA[x^2]]></mathphrase>'
        '\n'
        '</informalequation>',
      );
    });

    test('asciimath stem without mathml falls back to mathphrase', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.stem,
        contentModel: ContentModel.raw,
        stubbedContent: 'x^2',
      )..style = 'asciimath';
      expect(
        convOf(doc).convert(node),
        '<informalequation>\n'
        '<mathphrase><![CDATA[x^2]]></mathphrase>\n'
        '</informalequation>',
      );
    });

    test('stem with title uses equation', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.stem,
        contentModel: ContentModel.raw,
        stubbedContent: 'x^2',
        stubTitle: 'Equation',
      )..style = 'latexmath';
      expect(
        convOf(doc).convert(node),
        '<equation>\n'
        '<title>Equation</title>\n'
        '<alt><![CDATA[x^2]]></alt>'
        '\n'
        '<mathphrase><![CDATA[x^2]]></mathphrase>'
        '\n'
        '</equation>',
      );
    });

    test('specialcharacters sub is restored after conversion', () {
      final doc = makeDoc();
      final node =
          StubBlock(
              doc,
              BlockContext.stem,
              contentModel: ContentModel.raw,
              stubbedContent: 'x',
            )
            ..style = 'latexmath'
            ..subs = [Sub.specialcharacters, Sub.quotes];
      convOf(doc).convert(node);
      expect(node.subs, [Sub.specialcharacters, Sub.quotes]);
      node.subs = [Sub.quotes];
      convOf(doc).convert(node);
      expect(node.subs, [Sub.quotes]);
    });
  });

  group('convertOlist', () {
    test('ordered list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.olist);
      list.append(StubListItem(list, 'first'));
      list.append(StubListItem(list, 'second'));
      expect(
        convOf(doc).convert(list),
        '<orderedlist>\n'
        '<listitem>\n'
        '<simpara>first</simpara>\n'
        '</listitem>\n'
        '<listitem>\n'
        '<simpara>second</simpara>\n'
        '</listitem>\n'
        '</orderedlist>',
      );
    });

    test('ordered list with style, start and title', () {
      final doc = makeDoc();
      final list =
          StubListBlock(
              doc,
              BlockContext.olist,
              attributes: const {'start': '3'},
              stubTitle: 'Steps',
            )
            ..style = 'lowerroman'
            ..id = 'steps';
      list.append(StubListItem(list, 'first'));
      expect(
        convOf(doc).convert(list),
        '<orderedlist xml:id="steps" numeration="lowerroman" '
        'startingnumber="3">\n'
        '<title>Steps</title>\n'
        '<listitem>\n'
        '<simpara>first</simpara>\n'
        '</listitem>\n'
        '</orderedlist>',
      );
    });

    test('item with id, role and nested blocks', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.olist);
      final item = StubListItem(list, 'first')
        ..attributes['role'] = 'lead'
        ..id = 'item1';
      item.append(para(item, 'nested'));
      list.append(item);
      expect(
        convOf(doc).convert(list),
        '<orderedlist>\n'
        '<listitem xml:id="item1" role="lead">\n'
        '<simpara>first</simpara>\n'
        '<simpara>nested</simpara>\n'
        '</listitem>\n'
        '</orderedlist>',
      );
    });
  });

  group('convertOpen', () {
    test('abstract block', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'Abstract text',
      )..style = 'abstract';
      expect(
        convOf(doc).convert(node),
        '<abstract>\n<simpara>Abstract text</simpara>\n</abstract>',
      );
    });

    test('abstract in partintro is wrapped in info', () {
      final doc = makeDoc();
      final partintro = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.compound,
      )..style = 'partintro';
      final abstract = StubBlock(
        partintro,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'Abstract text',
      )..style = 'abstract';
      partintro.append(abstract);
      expect(
        convOf(doc).convert(abstract),
        '<info>\n<abstract>\n<simpara>Abstract text</simpara>\n</abstract>\n</info>',
      );
    });

    test('abstract in book without doctitle warns and drops content', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc(options: const AsciidoctorOptions(doctype: 'book'));
        final node = StubBlock(
          doc,
          BlockContext.open,
          contentModel: ContentModel.simple,
          stubbedContent: 'Abstract text',
        )..style = 'abstract';
        doc.append(node);
        expect(convOf(doc).convert(node), '');
        expect(
          logger.warns.single,
          'abstract block cannot be used in a document without a '
          'doctitle when doctype is book. Excluding block content.',
        );
      });
    });

    test('partintro in book part', () {
      final doc = makeDoc(options: const AsciidoctorOptions(doctype: 'book'));
      final part = StubSection(parent: doc, level: 0)..sectname = 'part';
      final node =
          Block(part, BlockContext.open, contentModel: ContentModel.compound)
            ..style = 'partintro'
            ..level = 0;
      node.append(para(node, 'intro'));
      expect(
        convOf(doc).convert(node),
        '<partintro>\n<simpara>intro</simpara>\n</partintro>',
      );
    });

    test('partintro outside book part logs error and drops content', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc();
        final node = StubBlock(
          doc,
          BlockContext.open,
          contentModel: ContentModel.simple,
          stubbedContent: 'intro',
        )..style = 'partintro';
        expect(convOf(doc).convert(node), '');
        expect(
          logger.errors.single,
          'partintro block can only be used when doctype is book and must be '
          'a child of a book part. Excluding block content.',
        );
      });
    });

    test('open block with title uses formalpara', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
        stubTitle: 'Title',
      );
      expect(
        convOf(doc).convert(node),
        '<formalpara>\n<title>Title</title>\n<para>content</para>\n</formalpara>',
      );
    });

    test('open block with id and compound content uses para', () {
      final doc = makeDoc();
      final node = Block(
        doc,
        BlockContext.open,
        contentModel: ContentModel.compound,
      )..id = 'open1';
      node.append(para(node, 'content'));
      expect(
        convOf(doc).convert(node),
        '<para xml:id="open1">\n<simpara>content</simpara>\n</para>',
      );
    });

    test('open block with role and simple content uses simpara', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.open,
        attributes: const {'role': 'lead'},
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
      );
      expect(
        convOf(doc).convert(node),
        '<simpara role="lead">content</simpara>',
      );
    });

    test('plain open block encloses content', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.open,
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
      );
      expect(convOf(doc).convert(node), '<simpara>content</simpara>');
    });
  });

  group('convertPageBreak', () {
    test('page break', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.pageBreak,
        contentModel: ContentModel.empty,
      );
      expect(
        convOf(doc).convert(node),
        '<simpara><?asciidoc-pagebreak?></simpara>',
      );
    });
  });

  group('convertParagraph', () {
    test('paragraph', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(para(doc, 'content')),
        '<simpara>content</simpara>',
      );
    });

    test('paragraph with title uses formalpara', () {
      final doc = makeDoc();
      final node = para(doc, 'content', const {}, 'Title');
      expect(
        convOf(doc).convert(node),
        '<formalpara>\n<title>Title</title>\n<para>content</para>\n</formalpara>',
      );
    });

    test('paragraph with id, role and reftext', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.paragraph,
        attributes: const {'role': 'lead'},
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
        stubReftext: 'Intro',
      )..id = 'intro';
      expect(
        convOf(doc).convert(node),
        '<simpara xml:id="intro" role="lead" xreflabel="Intro">content</simpara>',
      );
    });

    test('reftext with markup is sanitized', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.paragraph,
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
        stubReftext: 'See <b>this  thing</b>',
      )..id = 'intro';
      expect(
        convOf(doc).convert(node),
        '<simpara xml:id="intro" xreflabel="See this thing">content</simpara>',
      );
    });

    test('reftext quotes are escaped', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.paragraph,
        contentModel: ContentModel.simple,
        stubbedContent: 'content',
        stubReftext: 'Say "hi"',
      )..id = 'intro';
      expect(
        convOf(doc).convert(node),
        '<simpara xml:id="intro" xreflabel="Say &quot;hi&quot;">content</simpara>',
      );
    });
  });

  group('convertPreamble', () {
    test('preamble passes content through', () {
      final doc = makeDoc();
      final node = Block(
        doc,
        BlockContext.preamble,
        contentModel: ContentModel.compound,
      );
      node.append(para(node, 'content'));
      expect(convOf(doc).convert(node), '<simpara>content</simpara>');
    });

    test('preamble in book uses preface', () {
      final doc = makeDoc(options: const AsciidoctorOptions(doctype: 'book'));
      final node = Block(
        doc,
        BlockContext.preamble,
        contentModel: ContentModel.compound,
      );
      node.append(para(node, 'content'));
      expect(
        convOf(doc).convert(node),
        '<preface>\n<title></title>\n<simpara>content</simpara>\n</preface>',
      );
    });
  });

  group('convertQuote', () {
    test('quote block', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.quote,
        contentModel: ContentModel.simple,
        stubbedContent: 'quoted',
      );
      expect(
        convOf(doc).convert(node),
        '<blockquote>\n<simpara>quoted</simpara>\n</blockquote>',
      );
    });

    test('quote with attribution and citetitle', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.quote,
        attributes: const {'attribution': 'Author', 'citetitle': 'Work'},
        contentModel: ContentModel.simple,
        stubbedContent: 'quoted',
        stubTitle: 'Quote',
      );
      expect(
        convOf(doc).convert(node),
        '<blockquote>\n'
        '<title>Quote</title>\n'
        '<attribution>\n'
        'Author\n'
        '<citetitle>Work</citetitle>\n'
        '</attribution>\n'
        '<simpara>quoted</simpara>\n'
        '</blockquote>',
      );
    });

    test('epigraph quote', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.quote,
        attributes: const {'role': 'epigraph'},
        contentModel: ContentModel.simple,
        stubbedContent: 'quoted',
      );
      expect(
        convOf(doc).convert(node),
        '<epigraph role="epigraph">\n<simpara>quoted</simpara>\n</epigraph>',
      );
    });
  });

  group('convertSidebar', () {
    test('sidebar block', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.sidebar,
        contentModel: ContentModel.compound,
        stubTitle: 'Side',
        childContent: true,
      );
      node.append(para(node, 'content'));
      expect(
        convOf(doc).convert(node),
        '<sidebar>\n<title>Side</title>\n<simpara>content</simpara>\n</sidebar>',
      );
    });
  });

  group('convertTable', () {
    StubTable table(
      Document doc, {
      String? title,
      Map<String, String> attributes = const <String, String>{},
    }) {
      // NOTE the Table constructor only reads widths from its attributes
      // (as in Ruby); the remaining attributes are assigned directly.
      final node = StubTable(doc, <String, String>{}, stubTitle: title);
      node.attributes.addAll(attributes);
      node.createColumns([const ColumnSpec(), const ColumnSpec()]);
      final head = [
        StubCell(
          node.columns[0],
          'Name',
          stubText: 'Name',
          stubParagraphs: ['Name'],
        ),
        StubCell(
          node.columns[1],
          'Value',
          stubText: 'Value',
          stubParagraphs: ['Value'],
        ),
      ];
      final body = [
        StubCell(node.columns[0], 'a', stubText: 'a', stubParagraphs: ['a']),
        StubCell(node.columns[1], 'b', stubText: 'b', stubParagraphs: ['b']),
      ];
      node.rows.head.add(head);
      node.rows.body.add(body);
      return node;
    }

    test('table with head and body', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(table(doc, title: 'Data')),
        '<table frame="all" rowsep="1" colsep="1">\n'
        '<title>Data</title>\n'
        '<tgroup cols="2">\n'
        '<colspec colname="col_1" colwidth="50*"/>\n'
        '<colspec colname="col_2" colwidth="50*"/>\n'
        '<thead>\n'
        '<row>\n'
        '<entry align="left" valign="top">Name</entry>\n'
        '<entry align="left" valign="top">Value</entry>\n'
        '</row>\n'
        '</thead>\n'
        '<tbody>\n'
        '<row>\n'
        '<entry align="left" valign="top"><simpara>a</simpara></entry>\n'
        '<entry align="left" valign="top"><simpara>b</simpara></entry>\n'
        '</row>\n'
        '</tbody>\n'
        '</tgroup>\n'
        '</table>',
      );
    });

    test('table without title uses informaltable', () {
      final doc = makeDoc();
      final output = convOf(doc).convert(table(doc))!;
      expect(output, startsWith('<informaltable frame="all"'));
      expect(output, endsWith('</informaltable>'));
      expect(output, isNot(contains('<title>')));
    });

    test('frame ends maps to topbot', () {
      final doc = makeDoc();
      final output = convOf(doc)
          .convert(table(doc, attributes: const {'frame': 'ends'}))!;
      expect(output, contains('frame="topbot"'));
    });

    test('grid none disables seps', () {
      final doc = makeDoc();
      final output = convOf(doc)
          .convert(table(doc, attributes: const {'grid': 'none'}))!;
      expect(output, contains('rowsep="0" colsep="0"'));
    });

    test('pgwide, orientation and unbreakable', () {
      final doc = makeDoc();
      final node = table(doc, attributes: const {'orientation': 'landscape'})
        ..setOption('pgwide')
        ..setOption('unbreakable');
      final output = convOf(doc).convert(node)!;
      expect(output, contains(' pgwide="1" frame="all"'));
      expect(output, contains(' orient="land">\n'));
      expect(output, contains('<?dbfo keep-together="always"?>\n'));
    });

    test('width emits table-width processing instructions', () {
      final doc = makeDoc();
      final node = table(doc, attributes: const {'width': '80%'});
      final output = convOf(doc).convert(node)!;
      expect(output, contains('<?dbhtml table-width="80%"?>\n'));
      expect(output, contains('<?dbfo table-width="80%"?>\n'));
      expect(output, contains('<?dblatex table-width="80%"?>\n'));
    });

    test('cell spans', () {
      final doc = makeDoc();
      final node = (StubTable(doc, <String, String>{}))
        ..createColumns([const ColumnSpec(), const ColumnSpec()]);
      final cell =
          StubCell(
              node.columns[0],
              'wide',
              stubText: 'wide',
              stubParagraphs: ['wide'],
            )
            ..colspan = 2
            ..rowspan = 2;
      node.rows.body.add([cell]);
      final output = convOf(doc).convert(node)!;
      expect(
        output,
        contains(
          '<entry align="left" valign="top" namest="col_1" nameend="col_2" morerows="1"><simpara>wide</simpara></entry>\n',
        ),
      );
    });

    test('header and literal cell styles', () {
      final doc = makeDoc();
      final node = (StubTable(doc, <String, String>{}))
        ..createColumns([const ColumnSpec(), const ColumnSpec()]);
      final header = StubCell(
        node.columns[0],
        'h',
        stubText: 'h',
        stubParagraphs: ['h1', 'h2'],
      )..style = 'header';
      final literal = StubCell(
        node.columns[1],
        'l',
        stubText: 'l',
        stubParagraphs: ['l'],
      )..style = 'literal';
      node.rows.body.add([header, literal]);
      final output = convOf(doc).convert(node)!;
      expect(
        output,
        contains(
          '<simpara><emphasis role="strong">h1</emphasis></simpara><simpara><emphasis role="strong">h2</emphasis></simpara>',
        ),
      );
      expect(
        output,
        contains('<literallayout class="monospaced">l</literallayout>'),
      );
    });

    test('asciidoc cell style uses converted content', () {
      final doc = makeDoc();
      final node = (StubTable(doc, <String, String>{}))
        ..createColumns([const ColumnSpec()]);
      final cell = StubCell(
        node.columns[0],
        'a',
        stubText: 'a',
        stubContent: '<simpara>a</simpara>',
      )..style = 'asciidoc';
      node.rows.body.add([cell]);
      final output = convOf(doc).convert(node)!;
      expect(output, contains('<simpara>a</simpara></entry>\n'));
    });

    test('cellbgcolor emits dbfo processing instruction', () {
      final doc = makeDoc(attributes: const {'cellbgcolor': '#fff'});
      final output = convOf(doc).convert(table(doc))!;
      expect(output, contains('<?dbfo bgcolor="#fff"?></entry>\n'));
    });

    test('table without body rows warns', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc();
        final node = (StubTable(doc, <String, String>{}))
          ..createColumns([const ColumnSpec()]);
        node.rows.head.add([
          StubCell(node.columns[0], 'h', stubText: 'h', stubParagraphs: ['h']),
        ]);
        convOf(doc).convert(node);
        expect(logger.warns.single, 'tables must have at least one body row');
      });
    });
  });

  group('convertUlist', () {
    test('unordered list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.ulist);
      list.append(StubListItem(list, 'first'));
      list.append(StubListItem(list, 'second'));
      expect(
        convOf(doc).convert(list),
        '<itemizedlist>\n'
        '<listitem>\n'
        '<simpara>first</simpara>\n'
        '</listitem>\n'
        '<listitem>\n'
        '<simpara>second</simpara>\n'
        '</listitem>\n'
        '</itemizedlist>',
      );
    });

    test('unordered list with mark and title', () {
      final doc = makeDoc();
      final list = StubListBlock(doc, BlockContext.ulist, stubTitle: 'Items')
        ..style = 'square';
      list.append(StubListItem(list, 'first'));
      expect(
        convOf(doc).convert(list),
        '<itemizedlist mark="square">\n'
        '<title>Items</title>\n'
        '<listitem>\n'
        '<simpara>first</simpara>\n'
        '</listitem>\n'
        '</itemizedlist>',
      );
    });

    test('bibliography list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, BlockContext.ulist)..style = 'bibliography';
      list.append(StubListItem(list, 'Doe. Work.'));
      expect(
        convOf(doc).convert(list),
        '<bibliodiv>\n'
        '<bibliomixed>\n'
        '<bibliomisc>Doe. Work.</bibliomisc>\n'
        '</bibliomixed>\n'
        '</bibliodiv>',
      );
    });

    test('checklist', () {
      final doc = makeDoc();
      final list = ListBlock(
        doc,
        BlockContext.ulist,
        attributes: const {'checklist-option': ''},
      );
      final done = StubListItem(list, 'Done')
        ..attributes.addAll(const {'checkbox': '', 'checked': ''});
      final todo = StubListItem(list, 'Todo')..attributes['checkbox'] = '';
      list.blocks.addAll([done, todo]);
      expect(
        convOf(doc).convert(list),
        '<itemizedlist mark="none">\n'
        '<listitem>\n'
        '<simpara>&#10003; Done</simpara>\n'
        '</listitem>\n'
        '<listitem>\n'
        '<simpara>&#10063; Todo</simpara>\n'
        '</listitem>\n'
        '</itemizedlist>',
      );
    });
  });

  group('convertVerse', () {
    test('verse block', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.verse,
        contentModel: ContentModel.verbatim,
        stubbedContent: 'line one\nline two',
      );
      expect(
        convOf(doc).convert(node),
        '<blockquote>\n<literallayout>line one\nline two</literallayout>\n</blockquote>',
      );
    });

    test('epigraph verse', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.verse,
        attributes: const {'role': 'epigraph', 'attribution': 'Author'},
        contentModel: ContentModel.verbatim,
        stubbedContent: 'quoted',
      );
      expect(
        convOf(doc).convert(node),
        '<epigraph role="epigraph">\n'
        '<attribution>\n'
        'Author\n'
        '</attribution>\n'
        '<literallayout>quoted</literallayout>\n'
        '</epigraph>',
      );
    });
  });

  group('skipped and delegated transforms', () {
    test('audio, video and toc are skipped', () {
      final doc = makeDoc();
      expect(convOf(doc).convert(StubBlock(doc, BlockContext.audio)), isNull);
      expect(convOf(doc).convert(StubBlock(doc, BlockContext.video)), isNull);
      expect(convOf(doc).convert(StubBlock(doc, BlockContext.toc)), isNull);
    });

    test('pass returns content only', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        BlockContext.pass,
        contentModel: ContentModel.raw,
        stubbedContent: '<custom/>',
      );
      expect(convOf(doc).convert(node), '<custom/>');
    });
  });

  group('convertInlineAnchor', () {
    test('ref anchor', () {
      final doc = makeDoc();
      final node = StubInline(
        para(doc),
        InlineContext.anchor,
        id: 'here',
        type: 'ref',
        stubReftext: 'Here',
      );
      expect(
        convOf(doc).convert(node),
        '<anchor xml:id="here" xreflabel="Here"/>',
      );
    });

    test('ref anchor without reftext uses bracketed id', () {
      final doc = makeDoc();
      final node = StubInline(
        para(doc),
        InlineContext.anchor,
        id: 'here',
        type: 'ref',
      );
      expect(
        convOf(doc).convert(node),
        '<anchor xml:id="here" xreflabel="[here]"/>',
      );
    });

    test('xref with path uses link', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.anchor,
        text: 'See',
        attributes: const {'path': 'other.xml'},
        type: 'xref',
        target: 'other.xml#sec',
      );
      expect(
        convOf(doc).convert(node),
        '<link xl:href="other.xml#sec">See</link>',
      );
    });

    test('xref with path and no text uses path', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.anchor,
        attributes: const {'path': 'other.xml'},
        type: 'xref',
        target: 'other.xml',
      );
      expect(
        convOf(doc).convert(node),
        '<link xl:href="other.xml">other.xml</link>',
      );
    });

    test('xref without text uses xref tag', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.anchor,
        attributes: const {'refid': 'sec1'},
        type: 'xref',
      );
      expect(convOf(doc).convert(node), '<xref linkend="sec1"/>');
    });

    test('xref with text uses link tag', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.anchor,
        text: 'Section',
        attributes: const {'refid': 'sec1'},
        type: 'xref',
      );
      expect(convOf(doc).convert(node), '<link linkend="sec1">Section</link>');
    });

    test('xref without refid generates document id', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.anchor, type: 'xref');
      expect(convOf(doc).convert(node), '<xref linkend="__article-root__"/>');
      expect(doc.id, '__article-root__');
    });

    test('link', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.anchor,
        text: 'Example',
        type: 'link',
        target: 'https://example.org',
      );
      expect(
        convOf(doc).convert(node),
        '<link xl:href="https://example.org">Example</link>',
      );
    });

    test('bibref anchor', () {
      final doc = makeDoc();
      final node = StubInline(
        para(doc),
        InlineContext.anchor,
        id: 'doe2020',
        type: 'bibref',
        stubReftext: 'Doe',
      );
      expect(
        convOf(doc).convert(node),
        '<anchor xml:id="doe2020" xreflabel="[Doe]"/>[Doe]',
      );
    });

    test('bibref without reftext uses id', () {
      final doc = makeDoc();
      final node = StubInline(
        para(doc),
        InlineContext.anchor,
        id: 'doe2020',
        type: 'bibref',
      );
      expect(
        convOf(doc).convert(node),
        '<anchor xml:id="doe2020" xreflabel="[doe2020]"/>[doe2020]',
      );
    });

    test('unknown anchor type warns and returns null', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc();
        final node = Inline(para(doc), InlineContext.anchor, type: 'bogus');
        expect(convOf(doc).convert(node), isNull);
        expect(logger.warns.single, 'unknown anchor type: :bogus');
      });
    });
  });

  group('convertInlineBreak', () {
    test('line break', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.lineBreak, text: 'x');
      expect(convOf(doc).convert(node), 'x<?asciidoc-br?>');
    });
  });

  group('convertInlineButton', () {
    test('button', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.button, text: 'OK');
      expect(convOf(doc).convert(node), '<guibutton>OK</guibutton>');
    });
  });

  group('convertInlineCallout', () {
    test('callout', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.callout, id: 'CO1-1');
      expect(convOf(doc).convert(node), '<co xml:id="CO1-1"/>');
    });
  });

  group('convertInlineFootnote', () {
    test('footnote reference', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.footnote,
        type: 'xref',
        target: 'fn1',
      );
      expect(convOf(doc).convert(node), '<footnoteref linkend="fn1"/>');
    });

    test('footnote', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.footnote,
        text: 'note',
        id: 'fn1',
      );
      expect(
        convOf(doc).convert(node),
        '<footnote xml:id="fn1"><simpara>note</simpara></footnote>',
      );
    });
  });

  group('convertInlineImage', () {
    test('inline image', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.image,
        attributes: const {'alt': 'Alt'},
        target: 'img.png',
      );
      expect(
        convOf(doc).convert(node),
        '<inlinemediaobject>\n'
        '<imageobject>\n'
        '<imagedata fileref="img.png"/>\n'
        '</imageobject>\n'
        '<textobject><phrase>Alt</phrase></textobject>\n'
        '</inlinemediaobject>',
      );
    });

    test('icon image', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.image,
        type: 'icon',
        target: 'note',
      );
      final output = convOf(doc).convert(node)!;
      expect(
        output,
        contains('<imagedata fileref="./images/icons/note.png"/>\n'),
      );
    });

    test('inline image with sizes and link', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.image,
        attributes: const {
          'alt': 'Alt',
          'width': '100',
          'link': 'https://example.org',
        },
        type: 'image',
        target: 'img.png',
      );
      final output = convOf(doc).convert(node)!;
      expect(output, startsWith('<link xl:href="https://example.org">'));
      expect(output, contains(' contentwidth="100"/>\n'));
    });

    test('self link is used literally', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.image,
        attributes: const {'link': 'self'},
        target: 'img.png',
      );
      final output = convOf(doc).convert(node)!;
      expect(output, startsWith('<link xl:href="self">'));
    });
  });

  group('convertInlineIndexterm', () {
    test('visible index term', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.indexterm,
        text: 'cats',
        type: 'visible',
      );
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n<primary>cats</primary>\n</indexterm>cats',
      );
    });

    test('single term', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.indexterm, terms: ['cats']);
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n<primary>cats</primary>\n</indexterm>',
      );
    });

    test('two terms', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.indexterm,
        terms: ['cats', 'big'],
      );
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n<primary>cats</primary><secondary>big</secondary>\n</indexterm>',
      );
    });

    test('three terms with promotion', () {
      final doc = makeDoc(attributes: const {'indexterm-promotion-option': ''});
      final node = Inline(
        para(doc),
        InlineContext.indexterm,
        terms: ['cats', 'big', 'lions'],
      );
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n'
        '<primary>cats</primary><secondary>big</secondary><tertiary>lions</tertiary>\n'
        '</indexterm>\n'
        '<indexterm>\n'
        '<primary>big</primary><secondary>lions</secondary>\n'
        '</indexterm>\n'
        '<indexterm>\n'
        '<primary>lions</primary>\n'
        '</indexterm>',
      );
    });

    test('two terms with promotion', () {
      final doc = makeDoc(attributes: const {'indexterm-promotion-option': ''});
      final node = Inline(
        para(doc),
        InlineContext.indexterm,
        terms: ['cats', 'big'],
      );
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n'
        '<primary>cats</primary><secondary>big</secondary>\n'
        '</indexterm>\n'
        '<indexterm>\n'
        '<primary>big</primary>\n'
        '</indexterm>',
      );
    });

    test('term with see reference', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.indexterm,
        attributes: const {'see': 'felines'},
        terms: ['cats'],
      );
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n<primary>cats</primary>\n<see>felines</see>\n</indexterm>',
      );
    });

    test('term with see-also references', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.indexterm,
        terms: ['cats'],
        seeAlso: ['dogs', 'birds'],
      );
      expect(
        convOf(doc).convert(node),
        '<indexterm>\n'
        '<primary>cats</primary>\n'
        '<seealso>dogs</seealso>\n'
        '<seealso>birds</seealso>\n'
        '</indexterm>',
      );
    });
  });

  group('convertInlineKbd', () {
    test('single key', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.kbd, keys: ['Enter']);
      expect(convOf(doc).convert(node), '<keycap>Enter</keycap>');
    });

    test('key combination', () {
      final doc = makeDoc();
      final node = Inline(para(doc), InlineContext.kbd, keys: ['Ctrl', 'S']);
      expect(
        convOf(doc).convert(node),
        '<keycombo><keycap>Ctrl</keycap><keycap>S</keycap></keycombo>',
      );
    });
  });

  group('convertInlineMenu', () {
    test('menu without item', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.menu,
        attributes: const {'menu': 'File'},
        submenus: <String>[],
      );
      expect(convOf(doc).convert(node), '<guimenu>File</guimenu>');
    });

    test('menu with item', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.menu,
        attributes: const {'menu': 'File', 'menuitem': 'Open'},
        submenus: <String>[],
      );
      expect(
        convOf(doc).convert(node),
        '<menuchoice><guimenu>File</guimenu> <guimenuitem>Open</guimenuitem></menuchoice>',
      );
    });

    test('menu with submenus', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.menu,
        attributes: const {'menu': 'File', 'menuitem': 'doc.adoc'},
        submenus: ['Recent'],
      );
      expect(
        convOf(doc).convert(node),
        '<menuchoice><guimenu>File</guimenu> <guisubmenu>Recent</guisubmenu> <guimenuitem>doc.adoc</guimenuitem></menuchoice>',
      );
    });
  });

  group('convertInlineQuoted', () {
    test('quoted types', () {
      final doc = makeDoc();
      const cases = {
        'monospaced': ['<literal>', '</literal>'],
        'emphasis': ['<emphasis>', '</emphasis>'],
        'strong': ['<emphasis role="strong">', '</emphasis>'],
        'double': ['<quote>', '</quote>'],
        'single': ['<quote>', '</quote>'],
        'mark': ['<emphasis role="marked">', '</emphasis>'],
        'superscript': ['<superscript>', '</superscript>'],
        'subscript': ['<subscript>', '</subscript>'],
      };
      for (final entry in cases.entries) {
        final node = Inline(
          para(doc),
          InlineContext.quoted,
          text: 'x',
          type: entry.key,
        );
        expect(
          convOf(doc).convert(node),
          '${entry.value[0]}x${entry.value[1]}',
          reason: entry.key,
        );
      }
    });

    test('quoted with role uses phrase when supported', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.quoted,
        text: 'x',
        attributes: const {'role': 'red'},
        type: 'emphasis',
      );
      expect(
        convOf(doc).convert(node),
        '<emphasis><phrase role="red">x</phrase></emphasis>',
      );
    });

    test('quoted with role extends tag when phrase unsupported', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.quoted,
        text: 'x',
        attributes: const {'role': 'red'},
        type: 'monospaced',
      );
      expect(convOf(doc).convert(node), '<literal role="red">x</literal>');
    });

    test('quoted with id prepends anchor', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.quoted,
        text: 'x',
        id: 'q1',
        type: 'strong',
      );
      expect(
        convOf(doc).convert(node),
        '<anchor xml:id="q1"/><emphasis role="strong">x</emphasis>',
      );
    });

    test('unknown quoted type passes text through', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.quoted,
        text: 'x',
        type: 'bogus',
      );
      expect(convOf(doc).convert(node), 'x');
    });

    test('asciimath falls back to mathphrase', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.quoted,
        text: 'x^2',
        type: 'asciimath',
      );
      expect(
        convOf(doc).convert(node),
        '<inlineequation><mathphrase><![CDATA[x^2]]></mathphrase></inlineequation>',
      );
    });

    test('latexmath passes source to alt and mathphrase', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc),
        InlineContext.quoted,
        text: 'x^2',
        type: 'latexmath',
      );
      expect(
        convOf(doc).convert(node),
        '<inlineequation><alt><![CDATA[x^2]]></alt><mathphrase><![CDATA[x^2]]></mathphrase></inlineequation>',
      );
    });
  });

  group('literals (asciidart: DocBook allows no emphasis in them)', () {
    test('an emphasis or a quote in a literal becomes a phrase or marks', () {
      expect(
        repairDocbook(
          '<literal>a <emphasis>b</emphasis> "<quote>q</quote>"</literal>',
        ),
        '<literal>a <phrase role="emphasis">b</phrase> "&#8220;q&#8221;"</literal>',
      );
    });

    test('a literal in a literal, an emphasis around both', () {
      expect(
        repairDocbook(
          '<literal><emphasis role="strong">bold <literal>m</literal> text'
          '</emphasis></literal>',
        ),
        '<literal><phrase role="strong">bold <literal>m</literal> text'
        '</phrase></literal>',
      );
    });

    test('an emphasis outside a literal is left alone', () {
      const xml = '<emphasis>a <literal>b</literal> c</emphasis>';
      expect(repairDocbook(xml), xml);
    });
  });
}
