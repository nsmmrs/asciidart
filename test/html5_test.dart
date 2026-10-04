// Adjacent-string joins here are markup/paths, not prose; joined values
// are asserted byte-identical by tests.
// ignore_for_file: missing_whitespace_between_adjacent_strings
// The `<<` append operator intentionally returns its receiver (Ruby
// parity); statement uses discard it.
// ignore_for_file: unnecessary_statements
/// Tests for the HTML5 converter port (`html5.dart`).
///
/// Port of the html5-output assertions in the Ruby suite (`test/blocks_test.rb`,
/// `test/sections_test.rb`, `test/lists_test.rb`, `test/tables_test.rb`, etc.).
/// Nodes are constructed directly (no parsing); each test converts one node
/// through [Html5Converter.convert] and asserts the exact HTML string
/// (byte-identical contract per `adr/0001-dart-rewrite-goals.md` D4).
///
/// Substitution-dependent paths are covered with stub nodes ([StubBlock],
/// [StubSection], [StubListItem], [StubCell], [StubDocument]) that return
/// fixed content/titles/text, using plain-text inputs for which the real
/// substitutions are the identity. The tests that need real substitution
/// output parse small sources via [parseDoc] instead (the parser and
/// substitutors waves are merged).
library;

import 'dart:io';

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/composite.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/table.dart';
import 'package:test/test.dart';

/// Records log messages for assertions.
class FakeLogger implements NodeLogger {
  /// Messages by severity.
  final List<Object?> warns = <Object?>[];
  final List<Object?> errors = <Object?>[];

  @override
  void debug(Object? message) {}

  @override
  void info(Object? message) {}

  @override
  void warn(Object? message) {
    warns.add(message);
  }

  @override
  void error(Object? message) {
    errors.add(message);
  }

  @override
  void fatal(Object? message) {}
}

/// Runs [body] with a recording logger installed.
void usingMemoryLogger(void Function(FakeLogger logger) body) {
  final saved = AbstractNode.currentLogger;
  final logger = FakeLogger();
  AbstractNode.currentLogger = logger;
  try {
    body(logger);
  } finally {
    AbstractNode.currentLogger = saved;
  }
}

/// A block returning fixed content/title/alt (avoids the substitutors wave).
class StubBlock extends Block {
  /// Creates a stub block with fixed [content], [title] and [alt].
  new(
    super.parent,
    super.context, {
    super.attributes,
    super.contentModel,
    this.stubbedContent = '',
    this.stubTitle,
    this.stubAlt,
  });

  /// The value [content] returns.
  final String? stubbedContent;

  /// The value [title] returns (`null` means [hasTitle] is false).
  final String? stubTitle;

  /// The value [alt] returns (`null` means the empty string).
  final String? stubAlt;

  @override
  String? content() => stubbedContent;

  @override
  String? get title => stubTitle;

  @override
  bool get hasTitle => stubTitle != null;

  @override
  String get alt => stubAlt ?? '';
}

/// A section returning a fixed title (avoids the substitutors wave).
class StubSection extends Section {
  /// Creates a stub section with fixed [title].
  new({
    AbstractBlock? parent,
    int? level,
    Object? numbered = false,
    Map<String, Object?>? attributes,
    this.stubTitle,
  }) : super(parent, level, numbered, attributes);

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
  // ignore: use_super_parameters, reason: text is also captured for stubText.
  new(AbstractBlock parent, [String? text])
    : stubText = text,
      super(parent, text);

  /// The value [text] returns.
  final String? stubText;

  @override
  String? get text => stubText;
}

/// A table cell returning fixed text/content (avoids the substitutors wave).
class StubCell extends Cell {
  /// Creates a stub cell with fixed [text] and [content].
  new(
    Column? column,
    String? cellText, {
    Map<String, Object?>? attributes = const <String, Object?>{},
    Map<String, Object?>? opts,
    this.stubText,
    this.stubContent,
  }) : super(column, cellText, attributes, opts);

  /// The value [text] returns.
  final String? stubText;

  /// The value [content] returns.
  final Object? stubContent;

  @override
  String? get text => stubText;

  @override
  Object? content() => stubContent;
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

/// A document applying identity replacements (for plain-text inputs only).
///
/// Real `sub_replacements` output is the substitutors wave's job; the
/// converter tests only use inputs without replaceable characters, for
/// which the identity is byte-identical.
class StubDocument extends Document {
  /// Creates a stub document (see [Document.new]).
  new([super.data, super.options]);

  @override
  String subReplacements(String text) => text;
}

/// A [NodeSyntaxHighlighter] returning fixed markup.
class FakeHighlighter implements NodeSyntaxHighlighter {
  /// Creates a fake highlighter with fixed results.
  new({
    this.name = 'fake',
    this.canHighlight = true,
    this.formatResult = '<pre>highlighted</pre>',
    this.headResult = '<style>fake</style>',
    this.footerResult = '<script>fake</script>',
    this.head = true,
    this.footer = false,
  });

  @override
  final String name;

  @override
  final bool canHighlight;

  /// The value [format] returns.
  final String formatResult;

  /// The value [docinfo] returns for `'head'`.
  final String headResult;

  /// The value [docinfo] returns for `'footer'`.
  final String footerResult;

  /// The value [hasDocinfo] returns for `'head'`.
  final bool head;

  /// The value [hasDocinfo] returns for `'footer'`.
  final bool footer;

  /// The last [format] call arguments.
  Map<String, Object?>? lastFormatArgs;

  @override
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  ) {
    lastFormatArgs = <String, Object?>{
      'node': node,
      'language': language,
      'opts': opts,
    };
    return formatResult;
  }

  @override
  bool hasDocinfo(String location) => location == 'head' ? head : footer;

  @override
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  }) => location == 'head' ? headResult : footerResult;
}

/// Creates a document with an [Html5Converter] installed.
///
/// [attributes] are assigned directly; [options] go to the constructor
/// (`'safe'`, `'backend'`, `'doctype'`, ...). When [plainSubs] is set, a
/// [StubDocument] (identity replacements) is returned; when [xml] is set,
/// the converter runs in XML mode.
Document makeDoc({
  Map<String, Object?> attributes = const <String, Object?>{},
  Map<String, Object?> options = const <String, Object?>{},
  bool plainSubs = false,
  bool xml = false,
}) {
  final opts = <String, Object?>{'backend': 'html5', ...options};
  final doc =
      (plainSubs ? StubDocument(<String>[], opts) : Document(<String>[], opts))
        ..converter = Html5Converter(
          'html5',
          xml ? const {'htmlsyntax': 'xml'} : const {},
        )
        ..attributes.addAll(attributes);
  return doc;
}

/// The [Html5Converter] installed on [doc].
Html5Converter convOf(Document doc) => doc.converter as Html5Converter;

/// Parses [src] into an embedded HTML5 document (port of the
/// `document_from_string` test helper), for the tests that need real
/// substitution output now that the parser and substitutors waves are
/// merged.
Document parseDoc(String src, [Map<String, Object?>? options]) {
  final opts = <String, Object?>{
    'backend': 'html5',
    'standalone': false,
    ...?options,
  };
  return Document(src, opts).parse();
}

/// Converts [src] to embedded HTML5 (port of `convert_string_to_embedded`).
String convertEmbedded(String src, [Map<String, Object?>? options]) =>
    parseDoc(src, options).convert()! as String;

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test/fixtures').existsSync()) {
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

/// Creates a paragraph stub under [doc] with [text] content.
StubBlock para(
  Document doc,
  String text, {
  Map<String, Object?> attributes = const <String, Object?>{},
  String? title,
}) => StubBlock(
  doc,
  'paragraph',
  attributes: Map<String, Object?>.of(attributes),
  stubbedContent: text,
  stubTitle: title,
);

void main() {
  group('registration', () {
    test('registerFor registers the html5 backend as provided', () {
      Html5Converter.registerFor();
      final created = Converter.create('html5');
      expect(created, isA<Html5Converter>());
      expect(created!.backend, 'html5');
      // Provided registrations survive unregisterAll (mirrors PROVIDED).
      Converter.unregisterAll();
      expect(Converter.create('html5'), isA<Html5Converter>());
    });

    test('backend traits mirror init_backend_traits', () {
      final conv = Html5Converter('html5');
      expect(conv.baseBackend, 'html');
      expect(conv.fileType, 'html');
      expect(conv.htmlSyntax, 'html');
      expect(conv.outfileSuffix, '.html');
      expect(conv.supportsTemplates, isTrue);
    });

    test('xml mode is selected by the htmlsyntax option', () {
      final conv = Html5Converter('html5', const {'htmlsyntax': 'xml'});
      expect(conv.htmlSyntax, 'xml');
    });

    test('handles reports every template transform', () {
      final conv = Html5Converter('html5');
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
        'outline',
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
      expect(conv.handles('no_such_transform'), isFalse);
    });

    test('composite converter delegates to the html5 converter', () {
      final doc = makeDoc();
      final composite = CompositeConverter('html5', [convOf(doc)]);
      doc.converter = composite;
      expect(
        composite.convert(para(doc, 'Hi')),
        '<div class="paragraph">\n<p>Hi</p>\n</div>',
      );
    });

    test('unknown transform warns and returns null', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc();
        expect(convOf(doc).convert(doc, 'no_such_transform'), isNull);
        expect(logger.warns, hasLength(1));
        expect(
          logger.warns.single.toString(),
          contains('missing convert handler for no_such_transform'),
        );
      });
    });
  });

  group('convertParagraph', () {
    test('bare paragraph', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(para(doc, 'Hello, world!')),
        '<div class="paragraph">\n<p>Hello, world!</p>\n</div>',
      );
    });

    test('paragraph with id and role', () {
      final doc = makeDoc();
      final node = para(doc, 'Text', attributes: const {'role': 'lead'})
        ..id = 'p1';
      expect(
        convOf(doc).convert(node),
        '<div id="p1" class="paragraph lead">\n<p>Text</p>\n</div>',
      );
    });

    test('paragraph with id and no role', () {
      final doc = makeDoc();
      final node = para(doc, 'Text')..id = 'p1';
      expect(
        convOf(doc).convert(node),
        '<div id="p1" class="paragraph">\n<p>Text</p>\n</div>',
      );
    });

    test('titled paragraph', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(para(doc, 'Text', title: 'Title')),
        '<div class="paragraph">\n'
        '<div class="title">Title</div>\n'
        '<p>Text</p>\n'
        '</div>',
      );
    });

    test('paragraph with substitutions in content', () {
      // Exercises the converter through real `apply_subs` output
      // (`lib/asciidoctor/substitutors.rb`); oracle from Ruby
      // `Asciidoctor.convert '*bold* and _italic_', standalone: false`.
      expect(
        convertEmbedded('*bold* and _italic_'),
        '<div class="paragraph">\n'
        '<p><strong>bold</strong> and <em>italic</em></p>\n'
        '</div>',
      );
    });
  });

  group('convertSection', () {
    test('level 1 section with id and content', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 1,
        stubTitle: 'Section Title',
      )..id = 'section_title';
      section.blocks.add(para(doc, 'Body')..parent = section);
      doc.blocks.add(section);
      expect(
        convOf(doc).convert(section),
        '<div class="sect1">\n'
        '<h2 id="section_title">Section Title</h2>\n'
        '<div class="sectionbody">\n'
        '<div class="paragraph">\n<p>Body</p>\n</div>\n'
        '</div>\n'
        '</div>',
      );
    });

    test('level 2 section nests content directly', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 2,
        stubTitle: 'Subsection',
      );
      section.blocks.add(para(doc, 'Body')..parent = section);
      expect(
        convOf(doc).convert(section),
        '<div class="sect2">\n'
        '<h3>Subsection</h3>\n'
        '<div class="paragraph">\n<p>Body</p>\n</div>\n'
        '</div>',
      );
    });

    test('level 0 section renders as h1', () {
      final doc = makeDoc();
      final section = StubSection(parent: doc, level: 0, stubTitle: 'Part')
        ..id = 'part';
      expect(
        convOf(doc).convert(section),
        '<h1 id="part" class="sect0">Part</h1>\n',
      );
    });

    test('numbered section below sectnumlevels', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 1,
        numbered: true,
        stubTitle: 'Numbered',
      )..id = 'n1';
      doc << section;
      expect(
        convOf(doc).convert(section),
        '<div class="sect1">\n'
        '<h2 id="n1">1. Numbered</h2>\n'
        '<div class="sectionbody">\n\n</div>\n'
        '</div>',
      );
    });

    test('section with role', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 1,
        attributes: const {'role': 'special'},
        stubTitle: 'T',
      );
      expect(
        convOf(doc).convert(section),
        '<div class="sect1 special">\n'
        '<h2>T</h2>\n'
        '<div class="sectionbody">\n\n</div>\n'
        '</div>',
      );
    });

    test('sectlinks wraps title in link', () {
      final doc = makeDoc(attributes: const {'sectlinks': ''});
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Linked')
        ..id = 'linked';
      expect(
        convOf(doc).convert(section),
        '<div class="sect1">\n'
        '<h2 id="linked"><a class="link" href="#linked">Linked</a></h2>\n'
        '<div class="sectionbody">\n\n</div>\n'
        '</div>',
      );
    });

    test('sectlinks preserves leading anchors', () {
      final doc = makeDoc(attributes: const {'sectlinks': ''});
      final section = StubSection(
        parent: doc,
        level: 1,
        stubTitle: '<a id="x"></a>Title',
      )..id = 't';
      expect(
        convOf(doc).convert(section),
        contains(
          '<h2 id="t"><a id="x"></a><a class="link" href="#t">Title</a></h2>',
        ),
      );
    });

    test('sectanchors prepends anchor by default', () {
      final doc = makeDoc(attributes: const {'sectanchors': ''});
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Anchored')
        ..id = 'anchored';
      expect(
        convOf(doc).convert(section),
        contains(
          '<h2 id="anchored"><a class="anchor" href="#anchored"></a>Anchored</h2>',
        ),
      );
    });

    test('sectanchors appends anchor when after', () {
      final doc = makeDoc(attributes: const {'sectanchors': 'after'});
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Anchored')
        ..id = 'anchored';
      expect(
        convOf(doc).convert(section),
        contains(
          '<h2 id="anchored">Anchored<a class="anchor" href="#anchored"></a></h2>',
        ),
      );
    });

    test('captioned section uses captioned title', () {
      final doc = makeDoc();
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Body')
        ..caption = 'Caption. ';
      expect(convOf(doc).convert(section), contains('<h2>Caption. Body</h2>'));
    });

    test('book chapter uses chapter signifier', () {
      final doc = makeDoc(
        options: const {'doctype': 'book'},
        attributes: const {'chapter-signifier': 'Chapter'},
      );
      final section =
          StubSection(parent: doc, level: 1, numbered: true, stubTitle: 'Intro')
            ..sectname = 'chapter'
            ..id = 'intro';
      doc << section;
      expect(
        convOf(doc).convert(section),
        contains('<h2 id="intro">Chapter 1. Intro</h2>'),
      );
    });
  });

  group('convertOutline', () {
    test('no sections returns null', () {
      final doc = makeDoc();
      expect(convOf(doc).convert(doc, 'outline'), isNull);
    });

    test('flat sections', () {
      final doc = makeDoc();
      doc <<
          (StubSection(parent: doc, level: 1, stubTitle: 'One')..id = 'one') <<
          (StubSection(parent: doc, level: 1, stubTitle: 'Two')..id = 'two');
      expect(
        convOf(doc).convert(doc, 'outline'),
        '<ul class="sectlevel1">\n'
        '<li><a href="#one">One</a></li>\n'
        '<li><a href="#two">Two</a></li>\n'
        '</ul>',
      );
    });

    test('nested sections recurse', () {
      final doc = makeDoc();
      final parent = StubSection(parent: doc, level: 1, stubTitle: 'P')
        ..id = 'p';
      parent <<
          (StubSection(parent: parent, level: 2, stubTitle: 'C')..id = 'c');
      doc << parent;
      expect(
        convOf(doc).convert(doc, 'outline'),
        '<ul class="sectlevel1">\n'
        '<li><a href="#p">P</a>\n'
        '<ul class="sectlevel2">\n'
        '<li><a href="#c">C</a></li>\n'
        '</ul>\n'
        '</li>\n'
        '</ul>',
      );
    });

    test('sections deeper than toclevels are skipped', () {
      final doc = makeDoc(attributes: const {'toclevels': '1'});
      final parent = StubSection(parent: doc, level: 1, stubTitle: 'P')
        ..id = 'p';
      parent <<
          (StubSection(parent: parent, level: 2, stubTitle: 'C')..id = 'c');
      doc << parent;
      expect(
        convOf(doc).convert(doc, 'outline'),
        '<ul class="sectlevel1">\n<li><a href="#p">P</a></li>\n</ul>',
      );
    });

    test('toclevels option overrides the document attribute', () {
      final doc = makeDoc();
      final parent = StubSection(parent: doc, level: 1, stubTitle: 'P')
        ..id = 'p';
      parent <<
          (StubSection(parent: parent, level: 2, stubTitle: 'C')..id = 'c');
      doc << parent;
      expect(
        convOf(doc).convert(doc, 'outline', const {'toclevels': 1}),
        '<ul class="sectlevel1">\n<li><a href="#p">P</a></li>\n</ul>',
      );
    });

    test('numbered sections show sectnums', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 1,
        numbered: true,
        stubTitle: 'Numbered',
      )..id = 'n';
      doc << section;
      expect(
        convOf(doc).convert(doc, 'outline'),
        '<ul class="sectlevel1">\n'
        '<li><a href="#n">1. Numbered</a></li>\n'
        '</ul>',
      );
    });

    test('anchor tags are stripped from titles', () {
      final doc = makeDoc();
      doc <<
          (StubSection(parent: doc, level: 1, stubTitle: 'A<a href="#x">b</a>C')
            ..id = 's');
      expect(
        convOf(doc).convert(doc, 'outline'),
        '<ul class="sectlevel1">\n<li><a href="#s">AbC</a></li>\n</ul>',
      );
    });
  });

  group('convertListing', () {
    test('plain listing honors prewrap', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'listing', stubbedContent: 'line');
      expect(
        convOf(doc).convert(node),
        '<div class="listingblock">\n'
        '<div class="content">\n'
        '<pre>line</pre>\n'
        '</div>\n'
        '</div>',
      );
    });

    test('listing without prewrap gets nowrap class', () {
      final doc = makeDoc();
      doc.attributes.remove('prewrap');
      final node = StubBlock(doc, 'listing', stubbedContent: 'line');
      expect(
        convOf(doc).convert(node),
        contains('<pre class="nowrap">line</pre>'),
      );
    });

    test('nowrap option forces nowrap class', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'listing',
        attributes: const {'nowrap-option': ''},
        stubbedContent: 'line',
      );
      expect(
        convOf(doc).convert(node),
        contains('<pre class="nowrap">line</pre>'),
      );
    });

    test('source listing without highlighter emits language hooks', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'listing',
        attributes: const {'language': 'ruby'},
        stubbedContent: 'puts "hi"',
      )..style = 'source';
      expect(
        convOf(doc).convert(node),
        '<div class="listingblock">\n'
        '<div class="content">\n'
        '<pre class="highlight"><code class="language-ruby" data-lang="ruby">puts "hi"</code></pre>\n'
        '</div>\n'
        '</div>',
      );
    });

    test('source listing with highlighter delegates to format', () {
      final doc = makeDoc();
      final hl = FakeHighlighter();
      doc.syntaxHighlighter = hl;
      final node = StubBlock(
        doc,
        'listing',
        attributes: const {'language': 'ruby'},
        stubbedContent: 'puts "hi"',
      )..style = 'source';
      expect(convOf(doc).convert(node), contains('<pre>highlighted</pre>'));
      expect(hl.lastFormatArgs!['language'], 'ruby');
      expect(
        (hl.lastFormatArgs!['opts']! as Map<String, Object?>)['css_mode'],
        'class',
      );
      expect(
        (hl.lastFormatArgs!['opts']! as Map<String, Object?>)['nowrap'],
        isFalse,
      );
    });

    test('titled source listing shows captioned title', () {
      final doc = makeDoc();
      final node =
          StubBlock(
              doc,
              'listing',
              attributes: const {'language': 'ruby'},
              stubbedContent: 'x',
              stubTitle: 'Example',
            )
            ..style = 'source'
            ..caption = 'Listing 1. ';
      expect(
        convOf(doc).convert(node),
        contains('<div class="title">Listing 1. Example</div>'),
      );
    });
  });

  group('convertLiteral', () {
    test('literal block', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'literal', stubbedContent: '  spaced');
      expect(
        convOf(doc).convert(node),
        '<div class="literalblock">\n'
        '<div class="content">\n'
        '<pre>  spaced</pre>\n'
        '</div>\n'
        '</div>',
      );
    });

    test('titled literal block', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'literal',
        stubbedContent: 'x',
        stubTitle: 'T',
      )..id = 'l1';
      expect(
        convOf(doc).convert(node),
        contains(
          '<div id="l1" class="literalblock">\n<div class="title">T</div>',
        ),
      );
    });
  });

  group('convertStem', () {
    test('latexmath stem is wrapped in display delimiters', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'stem', stubbedContent: 'E=mc^2')
        ..style = 'latexmath';
      expect(
        convOf(doc).convert(node),
        '<div class="stemblock">\n'
        '<div class="content">\n'
        r'\[E=mc^2\]'
        '\n'
        '</div>\n'
        '</div>',
      );
    });

    test('already-delimited stem is not wrapped twice', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'stem', stubbedContent: r'\(x\)')
        ..style = 'latexmath';
      // Block delimiters differ from the inline ones, so wrapping applies.
      expect(convOf(doc).convert(node), contains(r'\[\(x\)\]'));
      final node2 = StubBlock(doc, 'stem', stubbedContent: r'\[x\]')
        ..style = 'latexmath';
      expect(convOf(doc).convert(node2), contains(r'\[x\]'));
      expect(convOf(doc).convert(node2), isNot(contains(r'\[\[x\]')));
    });

    test('asciimath stem splits blank-line breaks', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'stem', stubbedContent: 'a\n\nb')
        ..style = 'asciimath';
      expect(
        convOf(doc).convert(node),
        '<div class="stemblock">\n'
        '<div class="content">\n'
        r'\$a\$'
        '\n<br>\n'
        r'\$b\$'
        '\n'
        '</div>\n'
        '</div>',
      );
    });

    test('empty stem renders empty equation', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'stem')..style = 'latexmath';
      expect(convOf(doc).convert(node), contains(r'\[\]'));
    });

    test('null stem content renders empty equation', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'stem', stubbedContent: null)
        ..style = 'latexmath';
      expect(
        convOf(doc).convert(node),
        '<div class="stemblock">\n<div class="content">\n\n</div>\n</div>',
      );
    });
  });

  group('convertAdmonition', () {
    test('note without icons shows text label', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'admonition',
        attributes: const {'name': 'note', 'textlabel': 'Note'},
        stubbedContent: '<div class="paragraph">\n<p>Hi</p>\n</div>',
      );
      expect(
        convOf(doc).convert(node),
        '<div class="admonitionblock note">\n'
        '<table>\n'
        '<tr>\n'
        '<td class="icon">\n'
        '<div class="title">Note</div>\n'
        '</td>\n'
        '<td class="content">\n'
        '<div class="paragraph">\n<p>Hi</p>\n</div>\n'
        '</td>\n'
        '</tr>\n'
        '</table>\n'
        '</div>',
      );
    });

    test('font icons render an <i> label', () {
      final doc = makeDoc(attributes: const {'icons': 'font'});
      final node = StubBlock(
        doc,
        'admonition',
        attributes: const {'name': 'tip', 'textlabel': 'Tip'},
        stubbedContent: 'x',
      );
      expect(
        convOf(doc).convert(node),
        contains('<i class="fa icon-tip" title="Tip"></i>'),
      );
    });

    test('image icons render an <img> label', () {
      final doc = makeDoc(attributes: const {'icons': ''});
      final node = StubBlock(
        doc,
        'admonition',
        attributes: const {'name': 'note', 'textlabel': 'Note'},
        stubbedContent: 'x',
      );
      expect(
        convOf(doc).convert(node),
        contains('<img src="./images/icons/note.png" alt="Note">'),
      );
    });

    test('titled admonition with id and role', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'admonition',
        attributes: const {
          'name': 'warning',
          'textlabel': 'Warning',
          'role': 'big',
        },
        stubbedContent: 'x',
        stubTitle: 'Beware',
      )..id = 'a1';
      expect(
        convOf(doc).convert(node),
        contains('<div id="a1" class="admonitionblock warning big">'),
      );
      expect(
        convOf(doc).convert(node),
        contains('<div class="title">Beware</div>'),
      );
    });
  });

  group('convertUlist', () {
    test('basic bullet list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'ulist')..style = 'bullet';
      list
        ..blocks.add(StubListItem(list, 'One'))
        ..blocks.add(StubListItem(list, 'Two'));
      expect(
        convOf(doc).convert(list),
        '<div class="ulist bullet">\n'
        '<ul class="bullet">\n'
        '<li>\n<p>One</p>\n</li>\n'
        '<li>\n<p>Two</p>\n</li>\n'
        '</ul>\n'
        '</div>',
      );
    });

    test('checklist without icons uses glyphs', () {
      final doc = makeDoc();
      final list = ListBlock(
        doc,
        'ulist',
        attributes: const {'checklist-option': ''},
      )..style = 'bullet';
      final done = StubListItem(list, 'Done')
        ..attributes.addAll(const {'checkbox': '', 'checked': ''});
      final todo = StubListItem(list, 'Todo')..attributes['checkbox'] = '';
      list.blocks.addAll([done, todo]);
      final output = convOf(doc).convert(list)! as String;
      expect(output, contains('<div class="ulist checklist bullet">'));
      expect(output, contains('<ul class="checklist">'));
      expect(output, contains('<p>&#10003; Done</p>'));
      expect(output, contains('<p>&#10063; Todo</p>'));
    });

    test('checklist with font icons uses <i> markers', () {
      final doc = makeDoc(attributes: const {'icons': 'font'});
      final list = ListBlock(
        doc,
        'ulist',
        attributes: const {'checklist-option': ''},
      );
      final done = StubListItem(list, 'Done')
        ..attributes.addAll(const {'checkbox': '', 'checked': ''});
      list.blocks.add(done);
      expect(
        convOf(doc).convert(list),
        contains('<p><i class="fa fa-check-square-o"></i> Done</p>'),
      );
    });

    test('interactive checklist renders checkboxes', () {
      final doc = makeDoc();
      final list = ListBlock(
        doc,
        'ulist',
        attributes: const {'checklist-option': '', 'interactive-option': ''},
      );
      final done = StubListItem(list, 'Done')
        ..attributes.addAll(const {'checkbox': '', 'checked': ''});
      list.blocks.add(done);
      expect(
        convOf(doc).convert(list),
        contains(
          '<p><input type="checkbox" data-item-complete="1" checked> Done</p>',
        ),
      );
    });

    test('interactive checklist in xml mode self-closes inputs', () {
      final doc = makeDoc(xml: true);
      final list = ListBlock(
        doc,
        'ulist',
        attributes: const {'checklist-option': '', 'interactive-option': ''},
      );
      final todo = StubListItem(list, 'Todo')..attributes['checkbox'] = '';
      list.blocks.add(todo);
      expect(
        convOf(doc).convert(list),
        contains('<p><input type="checkbox" data-item-complete="0"/> Todo</p>'),
      );
    });

    test('item with id, role and nested blocks', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'ulist');
      final item = StubListItem(list, 'Text')
        ..id = 'i1'
        ..attributes['role'] = 'r';
      item.blocks.add(para(doc, 'Nested')..parent = item);
      list.blocks.add(item);
      final output = convOf(doc).convert(list)! as String;
      expect(output, contains('<li id="i1" class="r">'));
      expect(
        output,
        contains('<p>Text</p>\n<div class="paragraph">\n<p>Nested</p>\n</div>'),
      );
    });
  });

  group('convertOlist', () {
    test('ordered list with type and start', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'olist', attributes: const {'start': '3'})
        ..style = 'loweralpha';
      list.blocks.add(StubListItem(list, 'One'));
      expect(
        convOf(doc).convert(list),
        '<div class="olist loweralpha">\n'
        '<ol class="loweralpha" type="a" start="3">\n'
        '<li>\n<p>One</p>\n</li>\n'
        '</ol>\n'
        '</div>',
      );
    });

    test('reversed list appends boolean attribute', () {
      final doc = makeDoc();
      final list = ListBlock(
        doc,
        'olist',
        attributes: const {'reversed-option': ''},
      )..style = 'arabic';
      list.blocks.add(StubListItem(list, 'One'));
      expect(
        convOf(doc).convert(list),
        contains('<ol class="arabic" reversed>'),
      );
    });

    test('reversed list in xml mode renders name pair', () {
      final doc = makeDoc(xml: true);
      final list = ListBlock(
        doc,
        'olist',
        attributes: const {'reversed-option': ''},
      )..style = 'arabic';
      list.blocks.add(StubListItem(list, 'One'));
      expect(
        convOf(doc).convert(list),
        contains('<ol class="arabic" reversed="reversed">'),
      );
    });
  });

  group('convertDlist', () {
    test('labeled list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'dlist');
      final term = StubListItem(list, 'Term');
      final def = StubListItem(list, 'Definition');
      list.items.add(<Object?>[
        <Object?>[term],
        def,
      ]);
      expect(
        convOf(doc).convert(list),
        '<div class="dlist">\n'
        '<dl>\n'
        '<dt class="hdlist1">Term</dt>\n'
        '<dd>\n'
        '<p>Definition</p>\n'
        '</dd>\n'
        '</dl>\n'
        '</div>',
      );
    });

    test('qanda list', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'dlist')..style = 'qanda';
      list.items.add(<Object?>[
        <Object?>[StubListItem(list, 'Question')],
        StubListItem(list, 'Answer'),
      ]);
      final output = convOf(doc).convert(list)! as String;
      expect(output, contains('<div class="qlist qanda">'));
      expect(output, contains('<p><em>Question</em></p>'));
      expect(output, contains('<p>Answer</p>'));
    });

    test('horizontal list with widths', () {
      final doc = makeDoc();
      final list = ListBlock(
        doc,
        'dlist',
        attributes: const {'labelwidth': '20%', 'itemwidth': '80%'},
      )..style = 'horizontal';
      list.items.add(<Object?>[
        <Object?>[StubListItem(list, 'A'), StubListItem(list, 'B')],
        StubListItem(list, 'Def'),
      ]);
      final output = convOf(doc).convert(list)! as String;
      expect(output, contains('<div class="hdlist">'));
      expect(output, contains('<col width="20%">'));
      expect(output, contains('<col width="80%">'));
      expect(output, contains('<td class="hdlist1">'));
      expect(output, contains('A\n<br>\nB'));
      expect(output, contains('<td class="hdlist2">'));
    });

    test('term without description renders no dd', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'dlist');
      list.items.add(<Object?>[
        <Object?>[StubListItem(list, 'Lonely')],
        null,
      ]);
      final output = convOf(doc).convert(list)! as String;
      expect(output, contains('<dt class="hdlist1">Lonely</dt>'));
      expect(output, isNot(contains('<dd>')));
    });
  });

  group('convertColist', () {
    test('callout list without icons renders an ol', () {
      final doc = makeDoc();
      final list = ListBlock(doc, 'colist');
      list.blocks.add(StubListItem(list, 'First'));
      expect(
        convOf(doc).convert(list),
        '<div class="colist">\n'
        '<ol>\n'
        '<li>\n<p>First</p>\n</li>\n'
        '</ol>\n'
        '</div>',
      );
    });

    test('callout list with font icons renders a table', () {
      final doc = makeDoc(attributes: const {'icons': 'font'});
      final list = ListBlock(doc, 'colist');
      list.blocks.add(StubListItem(list, 'First'));
      final output = convOf(doc).convert(list)! as String;
      expect(output, contains('<table>'));
      expect(
        output,
        contains('<td><i class="conum" data-value="1"></i><b>1</b></td>'),
      );
    });

    test('callout list with image icons renders img labels', () {
      final doc = makeDoc(attributes: const {'icons': ''});
      final list = ListBlock(doc, 'colist');
      list.blocks.add(StubListItem(list, 'First'));
      expect(
        convOf(doc).convert(list),
        contains('<img src="./images/icons/callouts/1.png" alt="1">'),
      );
    });
  });

  group('convertExample', () {
    test('example block', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'example', stubbedContent: 'Body');
      expect(
        convOf(doc).convert(node),
        '<div class="exampleblock">\n'
        '<div class="content">\n'
        'Body\n'
        '</div>\n'
        '</div>',
      );
    });

    test('titled example shows captioned title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'example',
        stubbedContent: 'Body',
        stubTitle: 'Sample',
      )..caption = 'Example 1. ';
      expect(
        convOf(doc).convert(node),
        contains('<div class="title">Example 1. Sample</div>'),
      );
    });

    test('collapsible example renders details', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'example',
        attributes: const {'collapsible-option': ''},
        stubbedContent: 'Body',
        stubTitle: 'More',
      )..id = 'e1';
      expect(
        convOf(doc).convert(node),
        '<details id="e1">\n'
        '<summary class="title">More</summary>\n'
        '<div class="content">\n'
        'Body\n'
        '</div>\n'
        '</details>',
      );
    });

    test('open collapsible example without title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'example',
        attributes: const {'collapsible-option': '', 'open-option': ''},
        stubbedContent: 'Body',
      );
      expect(
        convOf(doc).convert(node),
        contains('<details open>\n<summary class="title">Details</summary>'),
      );
    });
  });

  group('convertOpen', () {
    test('open block with custom style and role', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'open',
        attributes: const {'role': 'r'},
        stubbedContent: 'Body',
      )..style = 'custom';
      expect(
        convOf(doc).convert(node),
        '<div class="openblock custom r">\n'
        '<div class="content">\n'
        'Body\n'
        '</div>\n'
        '</div>',
      );
    });

    test('abstract block renders quoteblock', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'open', stubbedContent: 'Abs')
        ..style = 'abstract'
        ..parent = doc;
      expect(
        convOf(doc).convert(node),
        '<div class="quoteblock abstract">\n'
        '<blockquote>\n'
        'Abs\n'
        '</blockquote>\n'
        '</div>',
      );
    });

    test('abstract block in doctitleless book is dropped with warning', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc(options: const {'doctype': 'book'});
        final node = StubBlock(doc, 'open', stubbedContent: 'Abs')
          ..style = 'abstract'
          ..parent = doc;
        expect(convOf(doc).convert(node), '');
        expect(logger.warns, hasLength(1));
        expect(
          logger.warns.single.toString(),
          contains('abstract block cannot be used'),
        );
      });
    });

    test('misplaced partintro is dropped with error', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc();
        final node = StubBlock(doc, 'open', stubbedContent: 'x')
          ..style = 'partintro'
          ..parent = doc;
        expect(convOf(doc).convert(node), '');
        expect(logger.errors, hasLength(1));
        expect(
          logger.errors.single.toString(),
          contains('partintro block can only be used'),
        );
      });
    });
  });

  group('convertPreamble', () {
    test('preamble wraps content in sectionbody', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'preamble', stubbedContent: 'Intro');
      expect(
        convOf(doc).convert(node),
        '<div id="preamble">\n'
        '<div class="sectionbody">\n'
        'Intro\n'
        '</div>\n'
        '</div>',
      );
    });

    test('preamble with toc-placement preamble includes toc', () {
      final doc = makeDoc(
        attributes: const {'toc-placement': 'preamble', 'toc': ''},
      );
      doc << (StubSection(parent: doc, level: 1, stubTitle: 'S')..id = 's');
      final node = StubBlock(doc, 'preamble', stubbedContent: 'Intro');
      final output = convOf(doc).convert(node)! as String;
      expect(output, contains('<div id="toc" class="toc">'));
      expect(output, contains('<div id="toctitle">Table of Contents</div>'));
      expect(output, contains('<a href="#s">S</a>'));
    });
  });

  group('convertQuote', () {
    test('quote block', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'quote', stubbedContent: 'Quoted');
      expect(
        convOf(doc).convert(node),
        '<div class="quoteblock">\n'
        '<blockquote>\n'
        'Quoted\n'
        '</blockquote>\n'
        '</div>',
      );
    });

    test('quote with attribution and citetitle', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'quote',
        attributes: const {'attribution': 'Author', 'citetitle': 'Source'},
        stubbedContent: 'Quoted',
      );
      expect(
        convOf(doc).convert(node),
        contains(
          '<div class="attribution">\n&#8212; Author<br>\n<cite>Source</cite>\n</div>',
        ),
      );
    });

    test('quote with attribution only', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'quote',
        attributes: const {'attribution': 'Author'},
        stubbedContent: 'Quoted',
      );
      expect(
        convOf(doc).convert(node),
        contains('<div class="attribution">\n&#8212; Author\n</div>'),
      );
    });
  });

  group('convertVerse', () {
    test('verse block', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'verse', stubbedContent: 'Line 1\nLine 2');
      expect(
        convOf(doc).convert(node),
        '<div class="verseblock">\n'
        '<pre class="content">Line 1\nLine 2</pre>\n'
        '</div>',
      );
    });

    test('verse with attribution', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'verse',
        attributes: const {'attribution': 'Poet'},
        stubbedContent: 'Verse',
      );
      expect(
        convOf(doc).convert(node),
        contains('<div class="attribution">\n&#8212; Poet\n</div>'),
      );
    });
  });

  group('convertSidebar', () {
    test('sidebar block with title', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'sidebar',
        stubbedContent: 'Aside',
        stubTitle: 'Side',
      );
      expect(
        convOf(doc).convert(node),
        '<div class="sidebarblock">\n'
        '<div class="content">\n'
        '<div class="title">Side</div>\n'
        'Aside\n'
        '</div>\n'
        '</div>',
      );
    });
  });

  group('convertFloatingTitle', () {
    test('floating title', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'floating_title', stubTitle: 'Float')
        ..style = 'float'
        ..level = 1;
      expect(convOf(doc).convert(node), '<h2 class="float">Float</h2>');
    });
  });

  group('convertPageBreak', () {
    test('page break', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(StubBlock(doc, 'page_break')),
        '<div class="page-break"></div>',
      );
    });
  });

  group('convertThematicBreak', () {
    test('thematic break', () {
      final doc = makeDoc();
      expect(convOf(doc).convert(StubBlock(doc, 'thematic_break')), '<hr>');
    });

    test('thematic break with role in xml mode', () {
      final doc = makeDoc(xml: true);
      final node = StubBlock(
        doc,
        'thematic_break',
        attributes: const {'role': 'heavy'},
      );
      expect(convOf(doc).convert(node), '<hr class="heavy"/>');
    });
  });

  group('convertPass', () {
    test('pass returns content only', () {
      final doc = makeDoc();
      final node = StubBlock(doc, 'pass', stubbedContent: '<b>raw</b>');
      expect(convOf(doc).convert(node), '<b>raw</b>');
    });
  });

  group('convertImage', () {
    test('basic image', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'image',
        attributes: const {'target': 'pic.png', 'alt': 'Pic'},
        stubAlt: 'Pic',
      );
      expect(
        convOf(doc).convert(node),
        '<div class="imageblock">\n'
        '<div class="content">\n'
        '<img src="pic.png" alt="Pic">\n'
        '</div>\n'
        '</div>',
      );
    });

    test('image with dimensions, link, alignment and title', () {
      final doc = makeDoc();
      final node =
          StubBlock(
              doc,
              'image',
              attributes: const {
                'target': 'pic.png',
                'alt': 'Pic',
                'width': '100',
                'height': '80',
                'link': 'https://example.org',
                'align': 'center',
                'role': 'framed',
              },
              stubAlt: 'Pic',
              stubTitle: 'Figure',
            )
            ..id = 'fig'
            ..caption = 'Figure 1. ';
      final output = convOf(doc).convert(node)! as String;
      expect(
        output,
        contains(
          '<a class="image" href="https://example.org"><img src="pic.png" alt="Pic" width="100" height="80"></a>',
        ),
      );
      expect(
        output,
        contains('<div id="fig" class="imageblock text-center framed">'),
      );
      expect(output, contains('<div class="title">Figure 1. Figure</div>'));
    });

    test('image with link=self links to the image', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'image',
        attributes: const {'target': 'pic.png', 'alt': 'Pic', 'link': 'self'},
        stubAlt: 'Pic',
      );
      expect(
        convOf(doc).convert(node),
        contains('<a class="image" href="pic.png"><img src="pic.png"'),
      );
    });

    test('image alt with quotes is encoded', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'image',
        attributes: const {'target': 'pic.png'},
        stubAlt: 'say "hi"',
      );
      expect(
        convOf(doc).convert(node),
        contains('<img src="pic.png" alt="say &quot;hi&quot;">'),
      );
    });

    test('interactive svg with fallback', () {
      final doc = makeDoc(options: const {'safe': 'safe'});
      final node = StubBlock(
        doc,
        'image',
        attributes: const {
          'target': 'fig.svg',
          'fallback': 'fig.png',
          'interactive-option': '',
        },
        stubAlt: 'Fig',
      );
      expect(
        convOf(doc).convert(node),
        contains(
          '<object type="image/svg+xml" data="fig.svg"><img src="fig.png" alt="Fig"></object>',
        ),
      );
    });

    test('image with substitutions in alt text', () {
      // Port of blocks_test.rb 'should apply specialcharacters and
      // replacement substitutions to alt text'.
      const input = 'A tiger\'s "roar" is < a bear\'s "growl"';
      const expected =
          'A tiger&#8217;s &quot;roar&quot; is &lt; a bear&#8217;s '
          '&quot;growl&quot;';
      final result = convertEmbedded('image::images/tiger-roar.png[$input]');
      expect(result, contains('alt="$expected"'));
    });
  });

  group('readSvgContents', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('html5');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    Document svgDoc(Map<String, Object?> attributes) => makeDoc(
      options: {'safe': 'safe', 'base_dir': tmp.path},
      attributes: attributes,
    );

    test('preamble is stripped', () {
      File('${tmp.path}/fig.svg')
          .writeAsStringSync('<?xml version="1.0"?>\n<svg><circle/></svg>');
      final doc = svgDoc(const {});
      final node = StubBlock(doc, 'image');
      expect(
        convOf(doc).readSvgContents(node, 'fig.svg'),
        '<svg><circle/></svg>',
      );
    });

    test('width and height replace dimension attributes', () {
      File('${tmp.path}/fig.svg').writeAsStringSync(
        '<svg width="10" height="10" style="x"><circle/></svg>',
      );
      final doc = svgDoc(const {});
      final node = StubBlock(
        doc,
        'image',
        attributes: const {'width': '100', 'height': '50'},
      );
      expect(
        convOf(doc).readSvgContents(node, 'fig.svg'),
        '<svg width="100" height="50"><circle/></svg>',
      );
    });

    test('inline svg image embeds the file', () {
      File('${tmp.path}/fig.svg').writeAsStringSync('<svg><circle/></svg>');
      final doc = svgDoc(const {});
      final node = StubBlock(
        doc,
        'image',
        attributes: const {'target': 'fig.svg', 'inline-option': ''},
        stubAlt: 'Fig',
      );
      expect(convOf(doc).convert(node), contains('<svg><circle/></svg>'));
    });

    test('inline svg with link=self renders no link', () {
      File('${tmp.path}/fig.svg').writeAsStringSync('<svg><circle/></svg>');
      final doc = svgDoc(const {});
      final node = StubBlock(
        doc,
        'image',
        attributes: const {
          'target': 'fig.svg',
          'inline-option': '',
          'link': 'self',
        },
        stubAlt: 'Fig',
      );
      final output = convOf(doc).convert(node)! as String;
      expect(output, contains('<svg><circle/></svg>'));
      expect(output, isNot(contains('<a class="image"')));
    });

    test('missing svg returns null', () {
      final doc = svgDoc(const {});
      final node = StubBlock(doc, 'image');
      expect(convOf(doc).readSvgContents(node, 'nope.svg'), isNull);
    });
  });

  group('convertAudio', () {
    test('basic audio', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'audio',
        attributes: const {'target': 'podcast.mp3'},
      );
      expect(
        convOf(doc).convert(node),
        '<div class="audioblock">\n'
        '<div class="content">\n'
        '<audio src="podcast.mp3" controls>\n'
        'Your browser does not support the audio tag.\n'
        '</audio>\n'
        '</div>\n'
        '</div>',
      );
    });

    test('audio with time range and options', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'audio',
        attributes: const {
          'target': 'podcast.mp3',
          'start': '10',
          'end': '20',
          'autoplay-option': '',
          'loop-option': '',
          'nocontrols-option': '',
        },
      );
      expect(
        convOf(doc).convert(node),
        contains('<audio src="podcast.mp3#t=10,20" autoplay loop>'),
      );
    });
  });

  group('convertVideo', () {
    test('vimeo video', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'video',
        attributes: const {
          'target': '12345',
          'poster': 'vimeo',
          'width': '640',
          'height': '360',
        },
      );
      expect(
        convOf(doc).convert(node),
        '<div class="videoblock">\n'
        '<div class="content">\n'
        '<iframe width="640" height="360" src="https://player.vimeo.com/video/12345" frameborder="0" allowfullscreen></iframe>\n'
        '</div>\n'
        '</div>',
      );
    });

    test('youtube video with playlist syntax', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'video',
        attributes: const {
          'target': 'abc123/PLxyz',
          'poster': 'youtube',
          'width': '640',
        },
      );
      expect(
        convOf(doc).convert(node),
        contains(
          'src="https://www.youtube.com/embed/abc123?rel=0&amp;list=PLxyz"',
        ),
      );
    });

    test('youtube video with loop injects playlist', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'video',
        attributes: const {
          'target': 'abc123',
          'poster': 'youtube',
          'loop-option': '',
          'nofullscreen-option': '',
        },
      );
      expect(
        convOf(doc).convert(node),
        contains(
          'src="https://www.youtube.com/embed/abc123?rel=0&amp;loop=1&amp;playlist=abc123&amp;fs=0"',
        ),
      );
    });

    test('wistia video with start and loop', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'video',
        attributes: const {
          'target': 'abc',
          'poster': 'wistia',
          'start': '5',
          'loop-option': '',
        },
      );
      expect(
        convOf(doc).convert(node),
        contains(
          '<iframe src="https://fast.wistia.com/embed/iframe/abc?time=5&amp;endVideoBehavior=loop" frameborder="0" allowfullscreen class="wistia_embed" name="wistia_embed"></iframe>',
        ),
      );
    });

    test('plain video file', () {
      final doc = makeDoc();
      final node = StubBlock(
        doc,
        'video',
        attributes: const {
          'target': 'movie.mp4',
          'poster': 'poster.png',
          'preload': 'none',
        },
      );
      expect(
        convOf(doc).convert(node),
        contains(
          '<video src="movie.mp4" poster="poster.png" controls preload="none">',
        ),
      );
    });
  });

  group('convertTable', () {
    Table makeTable(
      Document doc, {
      Map<String, Object?> attributes = const <String, Object?>{},
      int columns = 2,
      String? title,
      String? caption,
    }) {
      final table = StubTable(
        doc,
        Map<String, Object?>.of(attributes),
        stubTitle: title,
      );
      if (caption != null) {
        table.caption = caption;
      }
      table.createColumns([
        for (var i = 0; i < columns; i++) {'width': 1},
      ]);
      return table;
    }

    test('basic table with head and body', () {
      final doc = makeDoc();
      final table = makeTable(doc);
      final headCell = StubCell(table.columns[0], 'H', stubText: 'H');
      final bodyCell = StubCell(
        table.columns[0],
        'B',
        stubText: 'B',
        stubContent: const ['B'],
      );
      table.rows.head = [
        [headCell, StubCell(table.columns[1], 'H2', stubText: 'H2')],
      ];
      table.rows.body = [
        [
          bodyCell,
          StubCell(
            table.columns[1],
            'B2',
            stubText: 'B2',
            stubContent: const ['B2'],
          ),
        ],
      ];
      table.attributes['rowcount'] = 1;
      expect(
        convOf(doc).convert(table),
        '<table class="tableblock frame-all grid-all stretch">\n'
        '<colgroup>\n'
        '<col width="50%">\n'
        '<col width="50%">\n'
        '</colgroup>\n'
        '<thead>\n'
        '<tr>\n'
        '<th class="tableblock halign-left valign-top">H</th>\n'
        '<th class="tableblock halign-left valign-top">H2</th>\n'
        '</tr>\n'
        '</thead>\n'
        '<tbody>\n'
        '<tr>\n'
        '<td class="tableblock halign-left valign-top"><p class="tableblock">B</p></td>\n'
        '<td class="tableblock halign-left valign-top"><p class="tableblock">B2</p></td>\n'
        '</tr>\n'
        '</tbody>\n'
        '</table>',
      );
    });

    test('table with caption, frame, grid, stripes and float', () {
      final doc = makeDoc(attributes: const {'table-caption': 'Table'});
      final table = makeTable(
        doc,
        attributes: const {'width': '50%'},
        title: 'Data',
        caption: 'Table 1. ',
      );
      table.attributes.addAll(const {
        'frame': 'topbot',
        'grid': 'none',
        'stripes': 'even',
        'float': 'left',
        'role': 'spread',
      });
      table.attributes['rowcount'] = 1;
      table.rows.body = [
        [
          StubCell(
            table.columns[0],
            'x',
            stubText: 'x',
            stubContent: const ['x'],
          ),
          StubCell(
            table.columns[1],
            'y',
            stubText: 'y',
            stubContent: const ['y'],
          ),
        ],
      ];
      final output = convOf(doc).convert(table)! as String;
      expect(
        output,
        contains(
          '<table class="tableblock frame-ends grid-none stripes-even '
          'left spread" width="50%">',
        ),
      );
      expect(
        output,
        contains('<caption class="title">Table 1. Data</caption>'),
      );
    });

    test('autowidth table fits content', () {
      final doc = makeDoc();
      final table = makeTable(doc);
      table.attributes['autowidth-option'] = '';
      table.attributes['rowcount'] = 1;
      table.rows.body = [
        [
          StubCell(
            table.columns[0],
            'x',
            stubText: 'x',
            stubContent: const ['x'],
          ),
          StubCell(
            table.columns[1],
            'y',
            stubText: 'y',
            stubContent: const ['y'],
          ),
        ],
      ];
      final output = convOf(doc).convert(table)! as String;
      expect(
        output,
        contains('class="tableblock frame-all grid-all fit-content"'),
      );
      expect(output, contains('<colgroup>\n<col>\n<col>\n</colgroup>'));
    });

    test('colspan, rowspan and header-styled cell', () {
      final doc = makeDoc();
      final table = makeTable(doc);
      table.attributes['rowcount'] = 1;
      final spanned = StubCell(
        table.columns[0],
        'S',
        attributes: {'colspan': 2, 'rowspan': 2},
        stubText: 'S',
        stubContent: const ['S'],
      )..style = 'header';
      table.rows.body = [
        [spanned],
      ];
      expect(
        convOf(doc).convert(table),
        contains(
          '<th class="tableblock halign-left valign-top" colspan="2" rowspan="2"><p class="tableblock">S</p></th>',
        ),
      );
    });

    test('asciidoc and literal cells', () {
      final doc = makeDoc();
      final table = makeTable(doc);
      table.attributes['rowcount'] = 1;
      final asciidocCell = StubCell(
        table.columns[0],
        'doc',
        stubText: 'doc',
        stubContent: '<div class="paragraph">\n<p>Inner</p>\n</div>',
      )..style = 'asciidoc';
      final literalCell = StubCell(table.columns[1], 'lit', stubText: 'lit')
        ..style = 'literal';
      table.rows.body = [
        [asciidocCell, literalCell],
      ];
      final output = convOf(doc).convert(table)! as String;
      expect(
        output,
        contains(
          '<div class="content"><div class="paragraph">\n<p>Inner</p>\n</div></div>',
        ),
      );
      expect(output, contains('<div class="literal"><pre>lit</pre></div>'));
    });

    test('multi-paragraph cell joins paragraphs', () {
      final doc = makeDoc();
      final table = makeTable(doc, columns: 1);
      table.attributes['rowcount'] = 1;
      table.rows.body = [
        [
          StubCell(
            table.columns[0],
            'x',
            stubText: 'x',
            stubContent: const ['A', 'B'],
          ),
        ],
      ];
      expect(
        convOf(doc).convert(table),
        contains('<p class="tableblock">A</p>\n<p class="tableblock">B</p>'),
      );
    });

    test('cellbgcolor adds cell styles', () {
      final doc = makeDoc(attributes: const {'cellbgcolor': '#fff'});
      final table = makeTable(doc, columns: 1);
      table.attributes['rowcount'] = 1;
      table.rows.body = [
        [
          StubCell(
            table.columns[0],
            'x',
            stubText: 'x',
            stubContent: const ['x'],
          ),
        ],
      ];
      expect(
        convOf(doc).convert(table),
        contains('style="background-color: #fff;"'),
      );
    });

    test('table without rows renders no colgroup', () {
      final doc = makeDoc();
      final table = makeTable(doc);
      table.attributes['rowcount'] = 0;
      expect(
        convOf(doc).convert(table),
        '<table class="tableblock frame-all grid-all stretch">\n</table>',
      );
    });
  });

  group('convertToc', () {
    test('toc without macro placement is disabled', () {
      final doc = makeDoc(attributes: const {'toc': ''});
      doc << (StubSection(parent: doc, level: 1, stubTitle: 'S')..id = 's');
      expect(
        convOf(doc).convert(StubBlock(doc, 'toc')),
        '<!-- toc disabled -->',
      );
    });

    test('toc macro renders outline', () {
      final doc = makeDoc(
        attributes: const {'toc-placement': 'macro', 'toc': ''},
      );
      doc << (StubSection(parent: doc, level: 1, stubTitle: 'S')..id = 's');
      expect(
        convOf(doc).convert(StubBlock(doc, 'toc')),
        '<div id="toc" class="toc">\n'
        '<div id="toctitle" class="title">Table of Contents</div>\n'
        '<ul class="sectlevel1">\n<li><a href="#s">S</a></li>\n</ul>\n'
        '</div>',
      );
    });

    test('toc macro with id, title and levels', () {
      final doc = makeDoc(
        attributes: const {'toc-placement': 'macro', 'toc': ''},
      );
      final parent = StubSection(parent: doc, level: 1, stubTitle: 'P')
        ..id = 'p';
      parent <<
          (StubSection(parent: parent, level: 2, stubTitle: 'C')..id = 'c');
      doc << parent;
      final node = StubBlock(
        doc,
        'toc',
        attributes: const {'levels': '1', 'role': 'manual'},
        stubTitle: 'Contents',
      )..id = 'mytoc';
      final output = convOf(doc).convert(node)! as String;
      expect(output, contains('<div id="mytoc" class="manual">'));
      expect(
        output,
        contains('<div id="mytoctitle" class="title">Contents</div>'),
      );
      expect(output, contains('<a href="#p">P</a>'));
      expect(output, isNot(contains('<a href="#c">C</a>')));
    });
  });

  group('convertInlineAnchor', () {
    Inline anchor(
      Document doc, {
      String? text,
      String? type,
      String? target,
      String? id,
      Map<String, Object?> attributes = const <String, Object?>{},
    }) => Inline(
      para(doc, ''),
      'anchor',
      text: text,
      type: type,
      target: target,
      id: id,
      attributes: Map<String, Object?>.of(attributes),
    );

    test('xref with path', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        text: 'See',
        type: 'xref',
        target: 'other.html#s',
        attributes: const {'path': 'other.html#s'},
      );
      expect(convOf(doc).convert(node), '<a href="other.html#s">See</a>');
    });

    test('xref with path and no text uses path', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        type: 'xref',
        target: 'other.html',
        attributes: const {'path': 'other.html', 'role': 'r'},
      );
      expect(
        convOf(doc).convert(node),
        '<a href="other.html" class="r">other.html</a>',
      );
    });

    test('xref without path and with text', () {
      final doc = makeDoc();
      final node = anchor(doc, text: 'Text', type: 'xref', target: '#s');
      expect(convOf(doc).convert(node), '<a href="#s">Text</a>');
    });

    test('xref resolves ref title', () {
      final doc = makeDoc();
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Sec')
        ..id = 's';
      (doc.catalog['refs']! as Map<String, Object?>)['s'] = section;
      final node = anchor(
        doc,
        type: 'xref',
        target: '#s',
        attributes: const {'refid': 's'},
      );
      expect(convOf(doc).convert(node), '<a href="#s">Sec</a>');
    });

    test('xref strips anchors from resolved text', () {
      final doc = makeDoc();
      final section = StubSection(
        parent: doc,
        level: 1,
        stubTitle: 'A<a href="#y">b</a>',
      )..id = 's';
      (doc.catalog['refs']! as Map<String, Object?>)['s'] = section;
      final node = anchor(
        doc,
        type: 'xref',
        target: '#s',
        attributes: const {'refid': 's'},
      );
      expect(convOf(doc).convert(node), '<a href="#s">Ab</a>');
    });

    test('unresolved xref shows bracketed refid', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        type: 'xref',
        target: '#missing',
        attributes: const {'refid': 'missing'},
      );
      expect(convOf(doc).convert(node), '<a href="#missing">[missing]</a>');
    });

    test('empty refid resolves to top placeholder', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        type: 'xref',
        target: '#',
        attributes: const {'refid': ''},
      );
      expect(convOf(doc).convert(node), '<a href="#">[^top]</a>');
    });

    test('ref anchor', () {
      final doc = makeDoc();
      expect(
        convOf(doc).convert(anchor(doc, type: 'ref', id: 'x')),
        '<a id="x"></a>',
      );
    });

    test('link with title and role', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        text: 'Text',
        type: 'link',
        target: 'https://example.org',
        attributes: const {'title': 'Title', 'role': 'r'},
      )..id = 'l1';
      expect(
        convOf(doc).convert(node),
        '<a href="https://example.org" id="l1" class="r" title="Title">Text</a>',
      );
    });

    test('link with blank window gets noopener', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        text: 'Text',
        type: 'link',
        target: 'https://example.org',
        attributes: const {'window': '_blank'},
      );
      expect(
        convOf(doc).convert(node),
        '<a href="https://example.org" target="_blank" rel="noopener">Text</a>',
      );
    });

    test('link with nofollow and blank window', () {
      final doc = makeDoc();
      final node = anchor(
        doc,
        text: 'Text',
        type: 'link',
        target: 'https://example.org',
        attributes: const {'window': '_blank', 'nofollow-option': ''},
      );
      expect(
        convOf(doc).convert(node),
        '<a href="https://example.org" target="_blank" rel="nofollow noopener">Text</a>',
      );
    });

    test('bibref', () {
      final doc = makeDoc();
      final node = StubInline(
        para(doc, ''),
        'anchor',
        type: 'bibref',
        id: 'b1',
        stubReftext: 'Ref',
      );
      expect(convOf(doc).convert(node), '<a id="b1"></a>[Ref]');
    });

    test('unknown anchor type warns and returns null', () {
      usingMemoryLogger((logger) {
        final doc = makeDoc();
        final node = anchor(doc, type: 'bogus');
        expect(convOf(doc).convert(node), isNull);
        expect(
          logger.warns.single.toString(),
          contains('unknown anchor type: :bogus'),
        );
      });
    });

    test('xref with xrefstyle against captioned block', () {
      // Oracle from Ruby `Asciidoctor.convert` of the same input with
      // `:xrefstyle: full` (cf. `AbstractNode#xreftext` in
      // `lib/asciidoctor/abstract_node.rb`).
      const input =
          ':xrefstyle: full\n\nSee <<tiger>>.\n\n[#tiger]\n.Tiger\n'
          'image::tiger.png[Tiger]\n';
      expect(
        convertEmbedded(input),
        contains(
          '<p>See <a href="#tiger">Figure 1, &#8220;Tiger&#8221;</a>.</p>',
        ),
      );
    });

    test('recursive xref guard', () {
      // Port of links_test.rb 'should break circular xref reference in
      // section title'.
      const input = '[#a]\n== A <<b>>\n\n[#b]\n== B <<a>>\n';
      final output = convertEmbedded(input);
      expect(output, contains('<h2 id="a">A <a href="#b">B [a]</a></h2>'));
      expect(output, contains('<h2 id="b">B <a href="#a">[a]</a></h2>'));
    });
  });

  group('convertInlineBreak', () {
    test('line break', () {
      final doc = makeDoc();
      final node = Inline(para(doc, ''), 'break', text: 'x');
      expect(convOf(doc).convert(node), 'x<br>');
    });

    test('line break in xml mode', () {
      final doc = makeDoc(xml: true);
      final node = Inline(para(doc, ''), 'break', text: 'x');
      expect(convOf(doc).convert(node), 'x<br/>');
    });
  });

  group('convertInlineButton', () {
    test('button', () {
      final doc = makeDoc();
      final node = Inline(para(doc, ''), 'button', text: 'OK');
      expect(convOf(doc).convert(node), '<b class="button">OK</b>');
    });
  });

  group('convertInlineCallout', () {
    test('font icon callout', () {
      final doc = makeDoc(attributes: const {'icons': 'font'});
      final node = Inline(para(doc, ''), 'callout', text: '1');
      expect(
        convOf(doc).convert(node),
        '<i class="conum" data-value="1"></i><b>(1)</b>',
      );
    });

    test('image callout', () {
      final doc = makeDoc(attributes: const {'icons': ''});
      final node = Inline(para(doc, ''), 'callout', text: '1');
      expect(
        convOf(doc).convert(node),
        '<img src="./images/icons/callouts/1.png" alt="1">',
      );
    });

    test('callout with array guard renders comment', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'callout',
        text: '1',
        attributes: const {
          'guard': ['<!--', '-->'],
        },
      );
      expect(
        convOf(doc).convert(node),
        '&lt;!--<b class="conum">(1)</b>--&gt;',
      );
    });

    test('callout with string guard', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'callout',
        text: '1',
        attributes: const {'guard': '-->'},
      );
      expect(convOf(doc).convert(node), '--><b class="conum">(1)</b>');
    });
  });

  group('convertInlineFootnote', () {
    test('footnote reference', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'footnote',
        attributes: const {'index': 1},
      )..id = 'f1';
      expect(
        convOf(doc).convert(node),
        '<sup class="footnote" id="_footnote_f1">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
      );
    });

    test('footnote xref', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'footnote',
        type: 'xref',
        attributes: const {'index': 2},
      );
      expect(
        convOf(doc).convert(node),
        '<sup class="footnoteref">[<a class="footnote" href="#_footnotedef_2" title="View footnote.">2</a>]</sup>',
      );
    });

    test('unresolved footnote xref', () {
      final doc = makeDoc();
      final node = Inline(para(doc, ''), 'footnote', text: 'f', type: 'xref');
      expect(
        convOf(doc).convert(node),
        '<sup class="footnoteref red" title="Unresolved footnote reference.">[f]</sup>',
      );
    });

    test('footnote without index returns null', () {
      final doc = makeDoc();
      final node = Inline(para(doc, ''), 'footnote', text: 'f');
      expect(convOf(doc).convert(node), isNull);
    });
  });

  group('convertInlineImage', () {
    Inline image(
      Document doc, {
      String? type,
      String? target,
      String? id,
      Map<String, Object?> attributes = const <String, Object?>{},
    }) => Inline(
      para(doc, ''),
      'image',
      type: type,
      target: target,
      id: id,
      attributes: Map<String, Object?>.of(attributes),
    );

    test('basic inline image', () {
      final doc = makeDoc();
      final node = image(
        doc,
        target: 'pic.png',
        attributes: const {'alt': 'Pic', 'width': '10', 'title': 'T'},
      );
      expect(
        convOf(doc).convert(node),
        '<span class="image"><img src="pic.png" alt="Pic" width="10" title="T"></span>',
      );
    });

    test('font icon with size and flip', () {
      final doc = makeDoc(attributes: const {'icons': 'font'});
      final node = image(
        doc,
        type: 'icon',
        target: 'star',
        attributes: const {'size': '2x', 'flip': 'h'},
      );
      expect(
        convOf(doc).convert(node),
        '<span class="icon"><i class="fa fa-star fa-2x fa-flip-h"></i></span>',
      );
    });

    test('image icon', () {
      final doc = makeDoc(attributes: const {'icons': ''});
      final node = image(
        doc,
        type: 'icon',
        target: 'star',
        attributes: const {'alt': 'Star'},
      );
      expect(
        convOf(doc).convert(node),
        '<span class="icon"><img src="./images/icons/star.png" alt="Star"></span>',
      );
    });

    test('icon without icons attribute shows bracketed alt', () {
      final doc = makeDoc();
      final node = image(
        doc,
        type: 'icon',
        target: 'star',
        attributes: const {'alt': 'Star'},
      );
      expect(convOf(doc).convert(node), '<span class="icon">[Star&#93;</span>');
    });

    test('inline image with link, float, role and id', () {
      final doc = makeDoc();
      final node = image(
        doc,
        target: 'pic.png',
        id: 'i1',
        attributes: const {
          'alt': 'Pic',
          'link': 'https://example.org',
          'float': 'left',
          'role': 'r',
        },
      );
      expect(
        convOf(doc).convert(node),
        '<span id="i1" class="image left r"><a class="image" href="https://example.org"><img src="pic.png" alt="Pic"></a></span>',
      );
    });

    test('interactive inline svg with fallback', () {
      final doc = makeDoc(options: const {'safe': 'safe'});
      final node = image(
        doc,
        target: 'fig.svg',
        attributes: const {
          'alt': 'Fig',
          'fallback': 'fig.png',
          'interactive-option': '',
        },
      );
      expect(
        convOf(doc).convert(node),
        '<span class="image"><object type="image/svg+xml" data="fig.svg"><img src="fig.png" alt="Fig"></object></span>',
      );
    });
  });

  group('convertInlineIndexterm', () {
    test('visible index term shows text', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'indexterm',
        text: 'cats',
        type: 'visible',
      );
      expect(convOf(doc).convert(node), 'cats');
    });

    test('hidden index term renders nothing', () {
      final doc = makeDoc();
      final node = Inline(para(doc, ''), 'indexterm', text: 'cats');
      expect(convOf(doc).convert(node), '');
    });
  });

  group('convertInlineKbd', () {
    test('single key', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'kbd',
        attributes: const {
          'keys': ['Ctrl'],
        },
      );
      expect(convOf(doc).convert(node), '<kbd>Ctrl</kbd>');
    });

    test('key sequence', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'kbd',
        attributes: const {
          'keys': ['Ctrl', 'S'],
        },
      );
      expect(
        convOf(doc).convert(node),
        '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>S</kbd></span>',
      );
    });
  });

  group('convertInlineMenu', () {
    test('menu reference without items', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'menu',
        attributes: const {'menu': 'File', 'submenus': <String>[]},
      );
      expect(convOf(doc).convert(node), '<b class="menuref">File</b>');
    });

    test('menu with item', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'menu',
        attributes: const {
          'menu': 'File',
          'submenus': <String>[],
          'menuitem': 'Open',
        },
      );
      expect(
        convOf(doc).convert(node),
        '<span class="menuseq"><b class="menu">File</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Open</b></span>',
      );
    });

    test('menu with submenus and font caret', () {
      final doc = makeDoc(attributes: const {'icons': 'font'});
      final node = Inline(
        para(doc, ''),
        'menu',
        attributes: const {
          'menu': 'File',
          'submenus': ['New', 'Project'],
          'menuitem': 'Go',
        },
      );
      expect(
        convOf(doc).convert(node),
        '<span class="menuseq"><b class="menu">File</b>'
        '&#160;<i class="fa fa-angle-right caret"></i> '
        '<b class="submenu">New</b>'
        '&#160;<i class="fa fa-angle-right caret"></i> '
        '<b class="submenu">Project</b>'
        '&#160;<i class="fa fa-angle-right caret"></i> '
        '<b class="menuitem">Go</b></span>',
      );
    });
  });

  group('convertInlineQuoted', () {
    test('tagged and untagged quotes', () {
      const cases = {
        'monospaced': ['<code>', '</code>'],
        'emphasis': ['<em>', '</em>'],
        'strong': ['<strong>', '</strong>'],
        'double': ['&#8220;', '&#8221;'],
        'single': ['&#8216;', '&#8217;'],
        'mark': ['<mark>', '</mark>'],
        'superscript': ['<sup>', '</sup>'],
        'subscript': ['<sub>', '</sub>'],
        'asciimath': [r'\$', r'\$'],
        'latexmath': [r'\(', r'\)'],
        'bogus': ['', ''],
      };
      for (final entry in cases.entries) {
        final doc = makeDoc();
        final node = Inline(
          para(doc, ''),
          'quoted',
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

    test('quoted with role on tag type', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'quoted',
        text: 'x',
        type: 'strong',
        attributes: const {'role': 'r'},
      );
      expect(convOf(doc).convert(node), '<strong class="r">x</strong>');
    });

    test('quoted with role on text type', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'quoted',
        text: 'x',
        type: 'double',
        attributes: const {'role': 'r'},
      );
      expect(
        convOf(doc).convert(node),
        '<span class="r">&#8220;x&#8221;</span>',
      );
    });

    test('quoted with id on tag type', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'quoted',
        text: 'x',
        type: 'mark',
        id: 'm1',
      );
      expect(convOf(doc).convert(node), '<mark id="m1">x</mark>');
    });

    test('quoted with id and role on text type', () {
      final doc = makeDoc();
      final node = Inline(
        para(doc, ''),
        'quoted',
        text: 'x',
        type: 'single',
        id: 'q1',
        attributes: const {'role': 'r'},
      );
      expect(
        convOf(doc).convert(node),
        '<span id="q1" class="r">&#8216;x&#8217;</span>',
      );
    });
  });

  group('convertDocument', () {
    test('minimal standalone document', () {
      final doc = makeDoc(attributes: const {'reproducible': ''});
      doc.attributes.remove('last-update-label');
      doc.attributes.remove('notitle'); // standalone default
      setDocHeader(doc, 'Doc Title');
      doc.blocks.add(para(doc, 'Body'));
      expect(
        convOf(doc).convert(doc),
        '<!DOCTYPE html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '<meta charset="UTF-8">\n'
        '<meta http-equiv="X-UA-Compatible" content="IE=edge">\n'
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1.0">\n'
        '<title>Doc Title</title>\n'
        '</head>\n'
        '<body class="article">\n'
        '<div id="header">\n'
        '<h1>Doc Title</h1>\n'
        '</div>\n'
        '<div id="content">\n'
        '<div class="paragraph">\n<p>Body</p>\n</div>\n'
        '</div>\n'
        '<div id="footer">\n'
        '<div id="footer-text">\n'
        '</div>\n'
        '</div>\n'
        '</body>\n'
        '</html>',
      );
    });

    test('generator meta is omitted when reproducible', () {
      final doc = makeDoc(attributes: const {'reproducible': ''});
      expect(convOf(doc).convert(doc), isNot(contains('generator')));
      final doc2 = makeDoc();
      expect(
        convOf(doc2).convert(doc2),
        contains('<meta name="generator" content="Asciidoctor 0.1.0">'),
      );
    });

    test('metadata attributes render meta tags', () {
      final doc = makeDoc(
        plainSubs: true,
        attributes: const {
          'app-name': 'App',
          'description': 'Desc',
          'keywords': 'a, b',
          'authors': 'Writer',
          'copyright': '2024',
        },
      );
      final output = convOf(doc).convert(doc)! as String;
      expect(output, contains('<meta name="application-name" content="App">'));
      expect(output, contains('<meta name="description" content="Desc">'));
      expect(output, contains('<meta name="keywords" content="a, b">'));
      expect(output, contains('<meta name="author" content="Writer">'));
      expect(output, contains('<meta name="copyright" content="2024">'));
    });

    test('author meta strips markup', () {
      final doc = makeDoc(
        plainSubs: true,
        attributes: const {'authors': 'A <b>x</b>'},
      );
      expect(
        convOf(doc).convert(doc),
        contains('<meta name="author" content="A x">'),
      );
    });

    test('favicon variants', () {
      final cases = {
        '': '<link rel="icon" type="image/x-icon" href="favicon.ico">',
        'icon.ico': '<link rel="icon" type="image/x-icon" href="icon.ico">',
        'icon.png': '<link rel="icon" type="image/png" href="icon.png">',
        'noext': '<link rel="icon" type="image/x-icon" href="noext">',
      };
      for (final entry in cases.entries) {
        final doc = makeDoc(attributes: {'favicon': entry.key});
        expect(
          convOf(doc).convert(doc),
          contains(entry.value),
          reason: 'favicon=${entry.key}',
        );
      }
    });

    test('default stylesheet with linkcss and webfonts', () {
      final doc = makeDoc(
        attributes: const {'stylesheet': '', 'linkcss': '', 'webfonts': ''},
      );
      final output = convOf(doc).convert(doc)! as String;
      expect(
        output,
        contains(
          '<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Open+Sans:300,300italic,400,400italic,600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CNoto+Sans+Mono:400,700">',
        ),
      );
      expect(output, contains('asciidoctor.css">'));
    });

    test('default stylesheet embedded without linkcss', () {
      final doc = makeDoc(attributes: const {'stylesheet': 'DEFAULT'});
      doc.attributes.remove('linkcss'); // secure mode forces linkcss
      final output = convOf(doc).convert(doc)! as String;
      expect(output, contains('<style>\n'));
      expect(output, contains('\n</style>'));
      expect(output.length, greaterThan(10000));
    });

    test('custom stylesheet linked', () {
      final doc = makeDoc(
        attributes: const {
          'stylesheet': 'custom.css',
          'stylesdir': 'css',
          'linkcss': '',
        },
      );
      expect(
        convOf(doc).convert(doc),
        contains('<link rel="stylesheet" href="css/custom.css">'),
      );
    });

    test('custom stylesheet embedded from file', () {
      final tmp = Directory.systemTemp.createTempSync('html5');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/custom.css').writeAsStringSync('body{color:red}');
      final doc = makeDoc(
        options: {'base_dir': tmp.path},
        attributes: const {'stylesheet': 'custom.css', 'stylesdir': '.'},
      );
      doc.attributes.remove('linkcss'); // secure mode forces linkcss
      expect(
        convOf(doc).convert(doc),
        contains('<style>\nbody{color:red}\n</style>'),
      );
    });

    test('font icons from remote cdn', () {
      final doc = makeDoc(
        attributes: const {'icons': 'font', 'iconfont-remote': ''},
      );
      expect(
        convOf(doc).convert(doc),
        contains(
          '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">',
        ),
      );
    });

    test('font icons from local stylesdir', () {
      final doc = makeDoc(
        attributes: const {'icons': 'font', 'stylesdir': 'css'},
      );
      expect(
        convOf(doc).convert(doc),
        contains('<link rel="stylesheet" href="css/font-awesome.css">'),
      );
    });

    test('syntax highlighter head and footer docinfo', () {
      final doc = (makeDoc())
        ..syntaxHighlighter = FakeHighlighter(footer: true);
      final output = convOf(doc).convert(doc)! as String;
      expect(
        output.indexOf('<style>fake</style>'),
        lessThan(output.indexOf('</head>')),
      );
      expect(
        output.indexOf('<script>fake</script>'),
        greaterThan(output.indexOf('</body>') - 200),
      );
    });

    test('missing head docinfo removes placeholder', () {
      final doc = (makeDoc())..syntaxHighlighter = FakeHighlighter(head: false);
      final output = convOf(doc).convert(doc)! as String;
      expect(output, isNot(contains('fake')));
      expect(output, contains('</head>'));
    });

    test('sectioned document with toc in header', () {
      final doc = makeDoc(
        attributes: const {'toc': '', 'toc-class': 'toc', 'toc-title': 'TOC'},
      );
      doc << (StubSection(parent: doc, level: 1, stubTitle: 'S')..id = 's');
      final output = convOf(doc).convert(doc)! as String;
      expect(output, contains('<body class="article toc toc-header">'));
      expect(
        output,
        contains('<div id="toc" class="toc">\n<div id="toctitle">TOC</div>'),
      );
      expect(output, contains('<a href="#s">S</a>'));
    });

    test('author and revision details', () {
      final doc = makeDoc(
        plainSubs: true,
        attributes: const {
          'author': 'Doc Writer',
          'revnumber': '1.0',
          'revdate': '2024-01-01',
          'revremark': 'Stable',
        },
      );
      setDocHeader(doc, 'T');
      final output = convOf(doc).convert(doc)! as String;
      expect(
        output,
        contains(
          '<div class="details">\n'
          '<span id="author" class="author">Doc Writer</span><br>\n'
          '<span id="revnumber">version 1.0,</span>\n'
          '<span id="revdate">2024-01-01</span>\n'
          '<br><span id="revremark">Stable</span>\n'
          '</div>',
        ),
      );
      expect(output, contains('Version 1.0<br>'));
    });

    test('footnotes section', () {
      final doc = makeDoc();
      doc.footnotes.add(const Footnote(1, 'f1', 'Note text'));
      final output = convOf(doc).convert(doc)! as String;
      expect(
        output,
        contains(
          '<div id="footnotes">\n'
          '<hr>\n'
          '<div class="footnote" id="_footnotedef_1">\n'
          '<a href="#_footnoteref_1">1</a>. Note text\n'
          '</div>\n'
          '</div>',
        ),
      );
    });

    test('nofootnotes suppresses footnotes section', () {
      final doc = makeDoc(attributes: const {'nofootnotes': ''});
      doc.footnotes.add(const Footnote(1, 'f1', 'Note text'));
      expect(convOf(doc).convert(doc), isNot(contains('id="footnotes"')));
    });

    test('noheader, nofooter and notitle', () {
      final doc = makeDoc(
        attributes: const {'noheader': '', 'nofooter': '', 'notitle': ''},
      );
      setDocHeader(doc, 'T');
      doc.blocks.add(para(doc, 'Body'));
      final output = convOf(doc).convert(doc)! as String;
      expect(output, isNot(contains('id="header"')));
      expect(output, isNot(contains('id="footer"')));
      expect(output, contains('<div id="content">'));
    });

    test('max-width styles header, content and footer', () {
      final doc = makeDoc(attributes: const {'max-width': '800px'});
      setDocHeader(doc, 'T');
      final output = convOf(doc).convert(doc)! as String;
      expect(output, contains('<div id="header" style="max-width: 800px;">'));
      expect(output, contains('<div id="content" style="max-width: 800px;">'));
      expect(output, contains('<div id="footer" style="max-width: 800px;">'));
    });

    test('nolang omits lang attribute', () {
      final doc = makeDoc(attributes: const {'nolang': ''});
      expect(convOf(doc).convert(doc), contains('<html>'));
      final doc2 = makeDoc(attributes: const {'lang': 'fr'});
      expect(convOf(doc2).convert(doc2), contains('<html lang="fr">'));
    });

    test('xml mode uses xmlns and slashed voids', () {
      final doc = makeDoc(xml: true);
      final output = convOf(doc).convert(doc)! as String;
      expect(
        output,
        contains('<html xmlns="http://www.w3.org/1999/xhtml" lang="en">'),
      );
      expect(output, contains('<meta charset="UTF-8"/>'));
    });

    test('stem enables mathjax scripts', () {
      final doc = makeDoc(attributes: const {'stem': ''});
      final output = convOf(doc).convert(doc)! as String;
      expect(output, contains('MathJax.Hub.Config({'));
      expect(output, contains('inlineMath: [${r'["\\(", "\\)"]'}],'));
      expect(output, contains('displayMath: [${r'["\\[", "\\]"]'}],'));
      expect(output, contains('delimiters: [${r'["\\$", "\\$"]'}],'));
      expect(output, contains('autoNumber: "none"'));
      expect(
        output,
        contains(
          '<script src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.9/MathJax.js?config=TeX-MML-AM_CHTML"></script>',
        ),
      );
    });

    test('empty eqnums selects AMS numbering', () {
      final doc = makeDoc(attributes: const {'stem': '', 'eqnums': ''});
      expect(convOf(doc).convert(doc), contains('autoNumber: "AMS"'));
    });

    test('manpage document', () {
      final doc = makeDoc(
        options: const {'doctype': 'manpage'},
        attributes: const {
          'manpurpose': 'do things',
          'mannames': ['mycmd'],
        },
      );
      doc.attributes['title'] = 'mycmd(1)';
      doc.attributes.remove('notitle'); // standalone default
      doc <<
          (StubSection(parent: doc, level: 1, stubTitle: 'SYNOPSIS')
            ..id = 'synopsis');
      final output = convOf(doc).convert(doc)! as String;
      expect(output, contains('<h1>mycmd(1) Manual Page</h1>'));
      expect(
        output,
        contains(
          '<h2>NAME</h2>\n<div class="sectionbody">\n<p>mycmd - do things</p>\n</div>',
        ),
      );
    });

    test('author email rendering', () {
      // Oracle from Ruby `Asciidoctor.convert` of the same input
      // (standalone); exercises the author/email header template in
      // `lib/asciidoctor/converter/html5.rb`.
      const input =
          '= Document Title\nAuthor Name <author@example.org>\n\ncontent\n';
      final output =
          parseDoc(input, const {'standalone': true}).convert()! as String;
      expect(output, contains('<meta name="author" content="Author Name">'));
      expect(
        output,
        contains(
          '<span id="email" class="email">'
          '<a href="mailto:author@example.org">author@example.org</a>'
          '</span>',
        ),
      );
    });

    test('docinfo files are included', () {
      // Slice of document_test.rb 'should include docinfo files for html
      // backend' (the `'docinfo'` case): private head, header and footer
      // files from `test/fixtures` are spliced into the standalone page.
      final output =
          convertFile('${_findRepoRoot()}/test/fixtures/basic.adoc', const {
                'to_file': false,
                'standalone': true,
                'safe': SafeMode.server,
                'attributes': 'linkcss copycss! docinfo',
              })!
              as String;
      expect(output, contains('<script src="modernizr.js"></script>'));
      expect(output, contains('<nav class="navbar">'));
      expect(output, contains('plusone.js'));
    });

    test('full document from source', () {
      // Oracle from Ruby `Asciidoctor.convert` of the same input
      // (standalone); exercises the full document template in
      // `lib/asciidoctor/converter/html5.rb`.
      const input = '= Doc Title\n\nHello, *world*!\n';
      final output =
          parseDoc(input, const {'standalone': true}).convert()! as String;
      expect(output, contains('<!DOCTYPE html>'));
      expect(output, contains('<title>Doc Title</title>'));
      expect(output, contains('<h1>Doc Title</h1>'));
      expect(output, contains('<p>Hello, <strong>world</strong>!</p>'));
    });
  });

  group('convertEmbedded', () {
    test('embedded document with header', () {
      final doc = makeDoc();
      doc.attributes.remove('notitle'); // :showtitle: is set
      setDocHeader(doc, 'T');
      doc.blocks.add(para(doc, 'Body'));
      expect(
        convOf(doc).convert(doc, 'embedded'),
        '<h1>T</h1>\n'
        '<div class="paragraph">\n<p>Body</p>\n</div>',
      );
    });

    test('embedded document with toc', () {
      final doc = makeDoc(attributes: const {'toc': ''});
      doc << (StubSection(parent: doc, level: 1, stubTitle: 'S')..id = 's');
      final output = convOf(doc).convert(doc, 'embedded')! as String;
      expect(
        output,
        contains(
          '<div id="toc" class="toc">\n'
          '<div id="toctitle">Table of Contents</div>\n'
          '<ul class="sectlevel1">',
        ),
      );
    });

    test('embedded manpage', () {
      final doc = makeDoc(
        options: const {'doctype': 'manpage'},
        attributes: const {
          'manpurpose': 'do things',
          'mannames': ['mycmd'],
        },
      );
      doc.attributes['title'] = 'mycmd(1)';
      doc.attributes.remove('notitle'); // :showtitle: is set
      expect(
        convOf(doc).convert(doc, 'embedded'),
        '<h1>mycmd(1) Manual Page</h1>\n'
        '<h2>Name</h2>\n'
        '<div class="sectionbody">\n'
        '<p>mycmd - do things</p>\n'
        '</div>\n',
      );
    });

    test('embedded footnotes', () {
      final doc = makeDoc();
      doc.blocks.add(para(doc, 'Body'));
      doc.footnotes.add(const Footnote(1, 'f1', 'Note'));
      final output = convOf(doc).convert(doc, 'embedded')! as String;
      expect(output, contains('<div id="footnotes">\n<hr>'));
    });
  });
}
