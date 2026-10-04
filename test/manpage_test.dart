/// Tests for the manpage converter port (`manpage.dart`).
///
/// Port of the manpage-output assertions in the Ruby suite
/// (`test/manpage_test.rb`). Nodes are constructed directly (no parsing);
/// each test converts one node through [ManpageConverter] and asserts the
/// exact groff string (byte-identical contract per
/// `adr/0001-dart-rewrite-goals.md` D4).
///
/// Substitution-dependent paths are covered with stub nodes ([StubBlock],
/// [StubSection], [StubListItem], [StubCell], [StubTable]) that return
/// fixed content/titles/text, using plain-text inputs for which the real
/// substitutions are the identity. Tests that need real substitution
/// output parse small sources instead (the parser and substitutors waves
/// are merged).
library;

import 'dart:io';

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/manpage.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/table.dart';
import 'package:test/test.dart';

/// The troff leader marker (mirrors the private `_esc` in `manpage.dart`).
final String esc = String.fromCharCode(27);

/// Escaped backslash (mirrors the private `_escBs` in `manpage.dart`).
final String escBs = '$esc\\';

/// Escaped full stop (mirrors the private `_escFs` in `manpage.dart`).
final String escFs = '$esc.';

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
  new(super.parent, [super.text]) : stubText = text;

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

/// Creates a document with a [ManpageConverter] installed.
///
/// [attributes] are assigned directly; [options] go to the constructor.
Document makeDoc({
  Map<String, Object?> attributes = const <String, Object?>{},
  Map<String, Object?> options = const <String, Object?>{},
}) {
  final opts = <String, Object?>{'backend': 'manpage', ...options};
  final doc = (Document(<String>[], opts))
    ..converter = ManpageConverter('manpage');
  doc.attributes.addAll(attributes);
  return doc;
}

/// Creates a document with the standard manpage attributes installed.
Document manDoc({
  Map<String, Object?> attributes = const <String, Object?>{},
  Map<String, Object?> options = const <String, Object?>{},
}) => makeDoc(
  attributes: {
    'mantitle': 'command',
    'manvolnum': '1',
    'manname': 'command',
    'manmanual': 'Command Manual',
    'mansource': 'Command 1.2.3',
    'docdate': '2026-10-03',
    'manpurpose': 'does stuff',
    'authors': 'Author Name',
    'author': 'Author Name',
    'asciidoctor-version': '2.1.0.alpha.0',
    ...attributes,
  },
  options: options,
);

/// The [ManpageConverter] installed on [doc].
ManpageConverter convOf(Document doc) => doc.converter as ManpageConverter;

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

/// Creates a table with one column per entry in [widths] under [doc].
Table makeTable(Document doc, List<int> widths) {
  final table = (Table(doc, <String, Object?>{}))
    ..createColumns(widths.map((w) => <String, Object?>{'width': w}).toList());
  return table;
}

/// Creates a body text cell in column [col] of [table] with [text].
StubCell textCell(
  Table table,
  int col,
  String text, {
  Map<String, Object?> attributes = const <String, Object?>{},
}) => StubCell(
  table.columns[col],
  text,
  attributes: Map<String, Object?>.of(attributes),
  stubText: text,
  stubContent: <String>[text],
);

/// Appends a `[terms, description]` pair to the dlist [node].
void addDlistPair(ListBlock node, List<ListItem> terms, ListItem? dd) {
  node.items.add(<Object?>[terms, dd]);
}

/// Registers [ref] under [id] in the refs catalog of [doc].
void registerRef(Document doc, String id, Object? ref) {
  (doc.catalog['refs']! as Map<String, Object?>)[id] = ref;
}

/// Registers a footnote with [index] and [text] on [doc].
void addFootnote(Document doc, Object? index, String text) {
  (doc.catalog['footnotes']! as List<Footnote>).add(
    Footnote(index, 'fn$index', text),
  );
}

/// Converts a bare link with [target] (and optional [text]) through [conv].
String linkText(
  ManpageConverter conv,
  AbstractBlock parent,
  String target, [
  String? text,
]) => conv.convertInlineAnchor(
  Inline(parent, 'anchor', type: 'link', target: target, text: text ?? target),
)!;

void main() {
  group('registration', () {
    test('registerFor registers the manpage backend as provided', () {
      ManpageConverter.registerFor();
      final created = Converter.create('manpage');
      expect(created, isA<ManpageConverter>());
      expect(created!.backend, 'manpage');
      // Provided registrations survive unregisterAll (mirrors PROVIDED).
      Converter.unregisterAll();
      expect(Converter.create('manpage'), isA<ManpageConverter>());
    });

    test('backend traits mirror init_backend_traits', () {
      final conv = ManpageConverter('manpage');
      expect(conv.baseBackend, 'manpage');
      expect(conv.fileType, 'man');
      expect(conv.outfileSuffix, '.man');
      expect(conv.supportsTemplates, isTrue);
    });

    test('convert dispatches on the node name', () {
      final doc = manDoc();
      final node = para(doc, 'hello');
      expect(convOf(doc).convert(node), '.sp\nhello');
      final br = Block(doc, 'page_break');
      expect(convOf(doc).convert(br), '.bp');
    });
  });

  group('document', () {
    test('converts a document with standard manpage attributes', () {
      final doc = manDoc();
      const expected =
          '\'\\" t\n'
          '.\\"     Title: command\n'
          '.\\"    Author: Author Name\n'
          '.\\" Generator: Asciidoctor 2.1.0.alpha.0\n'
          '.\\"      Date: 2026-10-03\n'
          '.\\"    Manual: Command Manual\n'
          '.\\"    Source: Command 1.2.3\n'
          '.\\"  Language: English\n'
          '.\\"\n'
          '.TH "COMMAND" "1" "2026-10-03" "Command 1.2.3" "Command Manual"\n'
          '.ie \\n(.g .ds Aq \\(aq\n'
          ".el       .ds Aq '\n"
          '.ss \\n[.ss] 0\n'
          '.nh\n'
          '.ad l\n'
          '.de URL\n'
          '\\fI\\\\\$2\\fP <\\\\\$1>\\\\\$3\n'
          '..\n'
          '.als MTO URL\n'
          '.if \\n[.g] \\{\\\n'
          '.  mso www.tmac\n'
          '.  am URL\n'
          '.    ad l\n'
          '.  .\n'
          '.  am MTO\n'
          '.    ad l\n'
          '.  .\n'
          '.  LINKSTYLE blue R < >\n'
          '.\\}\n'
          '.SH "NAME"\n'
          'command \\- does stuff\n'
          '\n'
          '.SH "AUTHOR"\n'
          '.sp\n'
          'Author Name';
      expect(convOf(doc).convertDocument(doc), expected);
    });

    test('raises when mantitle is missing', () {
      final doc = manDoc();
      doc.attributes.remove('mantitle');
      expect(
        () => convOf(doc).convertDocument(doc),
        throwsA(
          isStateError.having(
            (e) => e.message,
            'message',
            'asciidoctor: ERROR: doctype must be set to manpage when using '
                'manpage backend',
          ),
        ),
      );
    });

    test('strips invalid characters from mantitle', () {
      final doc = manDoc(
        attributes: {'mantitle': 'foo<bar>baz', 'manname': 'foobaz'},
      );
      final output = convOf(doc).convertDocument(doc);
      expect(output, contains('.\\"     Title: foobaz\n'));
      expect(output, contains('.TH "FOOBAZ"'));
    });

    test('omits the date when reproducible is set', () {
      final doc = manDoc(attributes: {'reproducible': ''});
      final output = convOf(doc).convertDocument(doc);
      expect(output, isNot(contains('Date:')));
      expect(output, contains('.TH "COMMAND" "1" "" '));
    });

    test('uses blank placeholders for empty manual and source', () {
      final doc = manDoc();
      doc.attributes.remove('manmanual');
      doc.attributes.remove('mansource');
      final output = convOf(doc).convertDocument(doc);
      expect(output, contains('.\\"    Manual: \\ \\&\n'));
      expect(output, contains('.\\"    Source: \\ \\&\n'));
      expect(output, contains(r'.TH "COMMAND" "1" "2026-10-03" "\ \&" "\ \&"'));
    });

    test('collapses whitespace in manual and source', () {
      final doc = manDoc(
        attributes: {
          'manmanual': 'General\nCommands\nManual',
          'mansource': 'Control\nAll\nThe\nThings\n5.0',
        },
      );
      final output = convOf(doc).convertDocument(doc);
      expect(output, contains('Manual: General Commands Manual'));
      expect(output, contains('Source: Control All The Things 5.0'));
      expect(
        output,
        contains('"Control All The Things 5.0" "General Commands Manual"'),
      );
    });

    test('honors a custom man-linkstyle', () {
      final doc = manDoc(attributes: {'man-linkstyle': r'cyan B \[fo] \[fc]'});
      expect(
        convOf(doc).convertDocument(doc),
        contains('.  LINKSTYLE cyan B \\[fo] \\[fc]\n'),
      );
    });

    test('does not escape hyphens in mannames in the NAME section', () {
      final doc = manDoc(
        attributes: {
          'manname': 'git-describe',
          'mannames': ['git-describe'],
        },
      );
      expect(
        convOf(doc).convertDocument(doc),
        contains('\n.SH "NAME"\ngit-describe \\- does stuff\n'),
      );
    });

    test('outputs multiple mannames in the NAME section', () {
      final doc = manDoc(
        attributes: {
          'mannames': ['command', 'alt_command'],
        },
      );
      expect(
        convOf(doc).convertDocument(doc),
        contains('command, alt_command \\- does stuff\n'),
      );
    });

    test('honors a custom manname-title', () {
      final doc = manDoc(attributes: {'manname-title': 'Name'});
      expect(convOf(doc).convertDocument(doc), contains('.SH "NAME"\n'));
    });

    test('skips the NAME section when noheader is set', () {
      final doc = manDoc(attributes: {'noheader': ''});
      expect(convOf(doc).convertDocument(doc), isNot(contains('.SH "NAME"')));
    });

    test('skips the NAME section without manpurpose', () {
      final doc = manDoc();
      doc.attributes.remove('manpurpose');
      expect(convOf(doc).convertDocument(doc), isNot(contains('.SH "NAME"')));
    });

    test('falls back to the AUTHOR(S) placeholder without authors', () {
      final doc = manDoc();
      doc.attributes.remove('authors');
      expect(
        convOf(doc).convertDocument(doc),
        contains('.\\"    Author: [see the "AUTHOR(S)" section]\n'),
      );
    });

    test('emits an AUTHORS section for multiple authors', () {
      final doc = manDoc(
        attributes: {'authorcount': 2, 'author_2': 'Second Author'},
      );
      final output = convOf(doc).convertDocument(doc);
      expect(
        output,
        contains('.SH "AUTHORS"\n.sp\nAuthor Name\n.sp\nSecond Author'),
      );
    });

    test('emits no author section without authors', () {
      final doc = manDoc();
      doc.attributes.remove('authors');
      doc.attributes.remove('author');
      final output = convOf(doc).convertDocument(doc);
      expect(output, isNot(contains('.SH "AUTHOR"')));
      expect(output, isNot(contains('.SH "AUTHORS"')));
    });

    test('converts child blocks into the body', () {
      final doc = manDoc();
      doc.append(para(doc, 'hello'));
      final output = convOf(doc).convertDocument(doc);
      expect(output, contains('command \\- does stuff\n.sp\nhello\n'));
    });

    test('emits a NOTES section for footnotes', () {
      final doc = manDoc();
      addFootnote(doc, 1, 'first footnote');
      addFootnote(doc, 2, 'second footnote');
      expect(
        convOf(doc).convertDocument(doc),
        contains(
          '.SH "NOTES"\n.IP [1]\nfirst footnote\n.IP [2]\nsecond footnote',
        ),
      );
    });

    test('suppresses footnotes with nofootnotes', () {
      final doc = manDoc(attributes: {'nofootnotes': ''});
      addFootnote(doc, 1, 'first footnote');
      expect(convOf(doc).convertDocument(doc), isNot(contains('.SH "NOTES"')));
    });
  });

  group('embedded', () {
    test('converts content and footnotes without header or authors', () {
      final doc = manDoc();
      doc.append(para(doc, 'hello'));
      addFootnote(doc, 1, 'first footnote');
      expect(
        convOf(doc).convertEmbedded(doc),
        '.sp\nhello\n.SH "NOTES"\n.IP [1]\nfirst footnote',
      );
    });

    test('converts an empty embedded document', () {
      final doc = manDoc();
      expect(convOf(doc).convertEmbedded(doc), '');
    });
  });

  group('section', () {
    test('uppercases level-1 titles', () {
      final doc = manDoc();
      final node = StubSection(parent: doc, level: 1, stubTitle: 'Options')
        ..sectname = 'section'
        ..append(para(doc, 'body'));
      expect(convOf(doc).convertSection(node), '.SH "OPTIONS"\n.sp\nbody');
    });

    test('uppercases titles without mangling formatting macros', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final quoted = conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: 'double', text: 'Main'),
      )!;
      final italic = conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: 'emphasis', text: '&lt;Options&gt;'),
      )!;
      // Simulate the substituted title the parser would produce.
      final node = StubSection(
        parent: doc,
        level: 1,
        stubTitle: '$quoted $italic',
      )..sectname = 'section';
      expect(
        conv.convertSection(node),
        '.SH "\\(lqMAIN\\(rq \\fI<OPTIONS>\\fP"\n',
      );
    });

    test('does not uppercase monospace spans in titles', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final mono = conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: 'monospaced', text: 'show'),
      )!;
      final node = StubSection(parent: doc, level: 1, stubTitle: '$mono option')
        ..sectname = 'section';
      expect(conv.convertSection(node), '.SH "\\f(CRshow\\fP OPTION"\n');
    });

    test('uses SS and the captioned title below level 1', () {
      final doc = manDoc();
      final node = StubSection(parent: doc, level: 2, stubTitle: 'Options')
        ..sectname = 'section'
        ..caption = 'Section 1. '
        ..append(para(doc, 'body'));
      expect(
        convOf(doc).convertSection(node),
        '.SS "Section 1. Options"\n.sp\nbody',
      );
    });
  });

  group('admonition', () {
    test('converts a simple admonition', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'admonition',
        attributes: {'textlabel': 'Note', 'style': 'NOTE'},
        contentModel: 'simple',
        stubbedContent: 'Watch out.',
      );
      expect(
        convOf(doc).convertAdmonition(node),
        '.if n .sp\n'
        '.RS 4\n'
        '.it 1 an-trap\n'
        '.nr an-no-space-flag 1\n'
        '.nr an-break-flag 1\n'
        '.br\n'
        '.ps +1\n'
        '.B Note\n'
        '.ps -1\n'
        '.br\n'
        '.sp\n'
        'Watch out.\n'
        '.sp .5v\n'
        '.RE',
      );
    });

    test('appends the title after the label', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'admonition',
        attributes: {'textlabel': 'Warning', 'style': 'WARNING'},
        contentModel: 'simple',
        stubbedContent: 'Watch out.',
        stubTitle: 'Be careful',
      );
      final output = convOf(doc).convertAdmonition(node);
      expect(output, contains('.B Warning\\fP: Be careful\n'));
    });
  });

  group('colist', () {
    test('generates a callout list with formatting commands', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'colist');
      node.append(StubListItem(node, 'Installs the asciidoctor gem'));
      expect(
        convOf(doc).convertColist(node),
        '.TS\n'
        'tab(:);\n'
        'r lw(\\n(.lu*75u/100u).\n'
        "\\fB(1)\\fP\\h'-2n':T{\n"
        'Installs the asciidoctor gem\n'
        'T}\n'
        '.TE',
      );
    });

    test('numbers items sequentially', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'colist');
      node
        ..append(StubListItem(node, 'first'))
        ..append(StubListItem(node, 'second'));
      final output = convOf(doc).convertColist(node);
      expect(output, contains("\\fB(1)\\fP\\h'-2n':T{\nfirst\nT}"));
      expect(output, contains("\\fB(2)\\fP\\h'-2n':T{\nsecond\nT}"));
    });

    test('emits the title when set', () {
      final doc = manDoc();
      final node = StubListBlock(doc, 'colist', stubTitle: 'Callouts');
      expect(convOf(doc).convertColist(node), startsWith('.sp\n.B Callouts'));
    });
  });

  group('dlist', () {
    test('converts terms and descriptions', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'dlist');
      addDlistPair(node, [
        StubListItem(node, '--help'),
      ], StubListItem(node, 'Output a usage message and exit.'));
      expect(
        convOf(doc).convertDlist(node),
        '.sp\n\\-\\-help\n.RS 4\nOutput a usage message and exit.\n.RE',
      );
    });

    test('joins multiple terms with commas', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'dlist');
      addDlistPair(node, [
        StubListItem(node, '-V'),
        StubListItem(node, '--version'),
      ], StubListItem(node, 'Output the version number.'));
      expect(
        convOf(doc).convertDlist(node),
        contains('-V, \\-\\-version\n.RS 4'),
      );
    });

    test('numbers qanda questions', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'dlist')..style = 'qanda';
      addDlistPair(node, [
        StubListItem(node, 'What?'),
      ], StubListItem(node, 'That.'));
      addDlistPair(node, [
        StubListItem(node, 'Why?'),
      ], StubListItem(node, 'Because.'));
      final output = convOf(doc).convertDlist(node);
      expect(output, contains('.sp\n1. What?\n.RS 4\nThat.\n.RE'));
      expect(output, contains('.sp\n2. Why?\n.RS 4\nBecause.\n.RE'));
    });

    test('drops the space before block content without dd text', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'dlist');
      final dd = StubListItem(node, '')..append(para(doc, 'description'));
      addDlistPair(node, [StubListItem(node, 'term')], dd);
      expect(
        convOf(doc).convertDlist(node),
        '.sp\nterm\n.RS 4\ndescription\n.RE',
      );
    });

    test('emits the title when set', () {
      final doc = manDoc();
      final node = StubListBlock(doc, 'dlist', stubTitle: 'Options');
      expect(convOf(doc).convertDlist(node), startsWith('.sp\n.B Options'));
    });
  });

  group('example and sidebar', () {
    test('converts an example with a captioned title', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'example',
        contentModel: 'compound',
        stubbedContent: '.sp\nexample body',
        stubTitle: 'Title here',
      )..caption = 'Example 1. ';
      expect(
        convOf(doc).convertExample(node),
        '.sp\n.B Example 1. Title here\n.br\n.RS 4\n.sp\nexample body\n.RE',
      );
    });

    test('converts an untitled example', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'example',
        contentModel: 'simple',
        stubbedContent: 'example body',
      );
      expect(
        convOf(doc).convertExample(node),
        '.sp\n.RS 4\n.sp\nexample body\n.RE',
      );
    });

    test('converts a sidebar with a title', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'sidebar',
        contentModel: 'compound',
        stubbedContent: '.sp\nsidebar body',
        stubTitle: 'Title here',
      );
      expect(
        convOf(doc).convertSidebar(node),
        '.sp\n.B Title here\n.br\n.RS 4\n.sp\nsidebar body\n.RE',
      );
    });

    test('converts a floating title', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'floating_title',
        stubTitle: 'A floating title',
      );
      expect(convOf(doc).convertFloatingTitle(node), '.SS "A floating title"');
    });
  });

  group('image', () {
    test('replaces a block image with alt text in brackets', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'image',
        attributes: {'target': 'signs-point-to-yes.jpg'},
        stubAlt: 'signs point to yes',
      );
      expect(convOf(doc).convertImage(node), '.sp\n[signs point to yes]');
    });

    test('manifies image alt text and titles', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'image',
        attributes: {'target': 'rainbow.jpg'},
        stubTitle: 'Figure - one',
        stubAlt: 'That&#8217;s a double rainbow++!',
      );
      expect(
        convOf(doc).convertImage(node),
        '.sp\n.B Figure \\- one\n.br\n[That\\(cqs a double rainbow++!]',
      );
    });
  });

  group('listing and literal', () {
    test('converts a listing block', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'listing',
        contentModel: 'verbatim',
        stubbedContent: r'$ gem install x',
      );
      expect(
        convOf(doc).convertListing(node),
        '.sp\n.if n .RS 4\n.nf\n.fam C\n\$ gem install x\n.fam\n.fi\n.if n .RE',
      );
    });

    test('emits listing titles with captions', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'listing',
        contentModel: 'verbatim',
        stubbedContent: 'x',
        stubTitle: 'Install',
      )..caption = 'Listing 1. ';
      expect(
        convOf(doc).convertListing(node),
        startsWith('.sp\n.B Listing 1. Install\n.br\n'),
      );
    });

    test('escapes repeated spaces in literal content', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'literal',
        contentModel: 'verbatim',
        stubbedContent: '  ,---.          ,-----.\n  |Bob|          |Alice|',
      );
      expect(
        convOf(doc).convertLiteral(node),
        '.sp\n.if n .RS 4\n.nf\n.fam C\n'
        '  ,\\-\\-\\-.\\&          ,\\-\\-\\-\\-\\-.\n'
        '  |Bob|\\&          |Alice|\n'
        '.fam\n.fi\n.if n .RE',
      );
    });

    test('expands tabs in literal content', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'literal',
        contentModel: 'verbatim',
        stubbedContent: 'a\tb',
      );
      expect(
        convOf(doc).convertLiteral(node),
        contains('\n.fam C\na\\&        b\n.fam\n'),
      );
    });

    test('emits literal titles without captions', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'literal',
        contentModel: 'verbatim',
        stubbedContent: 'x',
        stubTitle: 'Output',
      );
      expect(
        convOf(doc).convertLiteral(node),
        startsWith('.sp\n.B Output\n.br\n'),
      );
    });
  });

  group('olist', () {
    test('converts ordered items', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'olist');
      node.append(StubListItem(node, 'five'));
      expect(
        convOf(doc).convertOlist(node),
        '.sp\n'
        '.RS 4\n'
        '.ie n \\{\\\n'
        "\\h'-04' 1.\\h'+01'\\c\n"
        '.\\}\n'
        '.el \\{\\\n'
        '.  sp -1\n'
        '.  IP " 1." 4.2\n'
        '.\\}\n'
        'five\n'
        '.RE',
      );
    });

    test('honors the start attribute', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'olist', attributes: {'start': '5'});
      node
        ..append(StubListItem(node, 'five'))
        ..append(StubListItem(node, 'six'));
      final output = convOf(doc).convertOlist(node);
      expect(output, contains('.  IP " 5." 4.2\n.\\}\nfive\n.RE'));
      expect(output, contains('.  IP " 6." 4.2\n.\\}\nsix\n.RE'));
    });

    test('drops principal text of an empty item', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'olist');
      final item = StubListItem(node, '')..append(para(doc, 'the main text'));
      node.append(item);
      expect(
        convOf(doc).convertOlist(node),
        endsWith('.\\}\nthe main text\n.RE'),
      );
    });

    test('emits the title when set', () {
      final doc = manDoc();
      final node = StubListBlock(doc, 'olist', stubTitle: 'Steps');
      expect(convOf(doc).convertOlist(node), startsWith('.sp\n.B Steps'));
    });
  });

  group('ulist', () {
    test('converts unordered items', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'ulist');
      node.append(StubListItem(node, 'one'));
      expect(
        convOf(doc).convertUlist(node),
        '.sp\n'
        '.RS 4\n'
        '.ie n \\{\\\n'
        "\\h'-04'\\(bu\\h'+03'\\c\n"
        '.\\}\n'
        '.el \\{\\\n'
        '.  sp -1\n'
        '.  IP \\(bu 2.3\n'
        '.\\}\n'
        'one\n'
        '.RE',
      );
    });

    test('drops principal text of an empty item', () {
      final doc = manDoc();
      final node = ListBlock(doc, 'ulist');
      final item = StubListItem(node, '')..append(para(doc, 'the main text'));
      node.append(item);
      expect(
        convOf(doc).convertUlist(node),
        endsWith('.\\}\nthe main text\n.RE'),
      );
    });

    test('emits the title when set', () {
      final doc = manDoc();
      final node = StubListBlock(doc, 'ulist', stubTitle: 'Items');
      expect(convOf(doc).convertUlist(node), startsWith('.sp\n.B Items'));
    });
  });

  group('open, page break, paragraph, pass, preamble, toc', () {
    test('encloses abstract content', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'open',
        contentModel: 'simple',
        stubbedContent: 'abstract text',
      )..style = 'abstract';
      expect(convOf(doc).convertOpen(node), '.sp\nabstract text');
    });

    test('encloses partintro content', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'open',
        contentModel: 'simple',
        stubbedContent: 'partintro text',
      )..style = 'partintro';
      expect(convOf(doc).convertOpen(node), '.sp\npartintro text');
    });

    test('returns plain content for unstyled open blocks', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'open',
        contentModel: 'compound',
        stubbedContent: '.sp\nopen text',
      );
      expect(convOf(doc).convertOpen(node), '.sp\nopen text');
    });

    test('converts a page break', () {
      final doc = manDoc();
      expect(convOf(doc).convertPageBreak(Block(doc, 'page_break')), '.bp');
    });

    test('converts a paragraph', () {
      final doc = manDoc();
      expect(convOf(doc).convertParagraph(para(doc, 'hello')), '.sp\nhello');
    });

    test('converts a titled paragraph', () {
      final doc = manDoc();
      expect(
        convOf(doc).convertParagraph(para(doc, 'hello', title: 'Title')),
        '.sp\n.B Title\n.br\nhello',
      );
    });

    test('normalizes whitespace in a paragraph', () {
      final doc = manDoc();
      final node = para(
        doc,
        'Oh, here it goes again\n'
        '  I should have known,\n'
        '    should have known,\n'
        'should have known again',
      );
      expect(
        convOf(doc).convertParagraph(node),
        '.sp\n'
        'Oh, here it goes again\n'
        'I should have known,\n'
        'should have known,\n'
        'should have known again',
      );
    });

    test('pass returns content only', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'pass',
        contentModel: 'raw',
        stubbedContent: 'raw text',
      );
      expect(convOf(doc).convert(node), 'raw text');
    });

    test('preamble returns content only', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'preamble',
        contentModel: 'compound',
        stubbedContent: '.sp\npreamble text',
      );
      expect(convOf(doc).convert(node), '.sp\npreamble text');
    });

    test('toc is skipped', () {
      final doc = manDoc();
      expect(convOf(doc).convert(Block(doc, 'toc')), isNull);
    });
  });

  group('quote', () {
    test('indents quote blocks', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'quote',
        attributes: {'attribution': 'James Baldwin'},
        contentModel: 'compound',
        stubbedContent:
            '.sp\nNot everything that is faced can be changed.\n'
            'But nothing can be changed until it is faced.',
      );
      expect(
        convOf(doc).convertQuote(node),
        '.RS 3\n'
        '.ll -.6i\n'
        '.sp\n'
        'Not everything that is faced can be changed.\n'
        'But nothing can be changed until it is faced.\n'
        '.br\n'
        '.RE\n'
        '.ll\n'
        '.RS 5\n'
        '.ll -.10i\n'
        '\\(em James Baldwin\n'
        '.RE\n'
        '.ll',
      );
    });

    test('emits quote titles', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'quote',
        contentModel: 'simple',
        stubbedContent: 'quoted',
        stubTitle: 'A quote',
      );
      expect(
        convOf(doc).convertQuote(node),
        startsWith('.sp\n.RS 3\n.B A quote\n.br\n.RE\n'),
      );
    });

    test('prefixes citetitles to attributions', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'quote',
        attributes: {'citetitle': 'Book', 'attribution': 'Author'},
        contentModel: 'simple',
        stubbedContent: 'quoted',
      );
      expect(
        convOf(doc).convertQuote(node),
        contains('.ll -.10i\nBook \\(em Author\n.RE'),
      );
    });
  });

  group('verse', () {
    test('preserves hard line breaks', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      String q(String type, String text) => conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: type, text: text),
      )!;
      final node = StubBlock(
        doc,
        'verse',
        contentModel: 'verbatim',
        stubbedContent:
            '${q('emphasis', 'command')} [${q('emphasis', 'OPTION')}]&#8230; '
            '${q('emphasis', 'FILE')}&#8230;',
      );
      expect(
        conv.convertVerse(node),
        '.sp\n'
        '.nf\n'
        '\\fIcommand\\fP [\\fIOPTION\\fP].\\|.\\|. \\fIFILE\\fP.\\|.\\|.\n'
        '.fi\n'
        '.br',
      );
    });

    test('emits verse attributions', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'verse',
        attributes: {'attribution': 'Poet'},
        contentModel: 'verbatim',
        stubbedContent: 'a line',
        stubTitle: 'A poem',
      );
      expect(
        convOf(doc).convertVerse(node),
        '.sp\n.B A poem\n.br\n.sp\n.nf\na line\n.fi\n.br\n'
        '.in +.5i\n.ll -.5i\n\\(em Poet\n.in\n.ll',
      );
    });
  });

  group('stem', () {
    test('strips latexmath delimiters', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'stem',
        contentModel: 'raw',
        stubbedContent: r'\[x^2\]',
      )..style = 'latexmath';
      expect(convOf(doc).convertStem(node), '.sp\nx^2 (latexmath)');
    });

    test('strips asciimath delimiters', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'stem',
        contentModel: 'raw',
        stubbedContent: r'\$x^2\$',
      )..style = 'asciimath';
      expect(convOf(doc).convertStem(node), '.sp\nx^2 (asciimath)');
    });

    test('keeps equations without delimiters', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'stem',
        contentModel: 'raw',
        stubbedContent: 'x^2',
        stubTitle: 'Equation',
      )..style = 'latexmath';
      expect(
        convOf(doc).convertStem(node),
        '.sp\n.B Equation\n.br\nx^2 (latexmath)',
      );
    });
  });

  group('video and thematic break', () {
    test('converts a video block', () {
      final doc = manDoc();
      final node = StubBlock(doc, 'video', attributes: {'target': 'vid.mp4'});
      expect(convOf(doc).convertVideo(node), '.sp\n<vid.mp4> (video)');
    });

    test('appends start and end params', () {
      final doc = manDoc();
      final node = StubBlock(
        doc,
        'video',
        attributes: {'target': 'vid.mp4', 'start': '10', 'end': '20'},
        stubTitle: 'Clip',
      );
      expect(
        convOf(doc).convertVideo(node),
        '.sp\n.B Clip\n.br\n<vid.mp4&start=10&end=20> (video)',
      );
    });

    test('converts a thematic break', () {
      final doc = manDoc();
      expect(
        convOf(doc).convertThematicBreak(Block(doc, 'thematic_break')),
        ".sp\n.ce\n\\l'\\n(.lu*25u/100u\\(ap'",
      );
    });
  });

  group('table', () {
    test('converts body rows', () {
      final doc = manDoc();
      final table = makeTable(doc, [50, 50]);
      table.rows.body.add([textCell(table, 0, 'a'), textCell(table, 1, 'b')]);
      expect(
        convOf(doc).convertTable(table),
        '.TS\n'
        'allbox tab(:);\n'
        'lt lt.\n'
        'T{\n'
        'a\n'
        'T}:T{\n'
        'b\n'
        'T}\n'
        '.TE\n'
        '.sp',
      );
    });

    test('creates header, body and footer rows in order', () {
      final doc = manDoc();
      final table = (makeTable(doc, [100]))..hasHeaderOption = true;
      table.rows.head.add([textCell(table, 0, 'Header')]);
      table.rows.body.add([textCell(table, 0, 'Body 1')]);
      table.rows.body.add([textCell(table, 0, 'Body 2')]);
      table.rows.foot.add([textCell(table, 0, 'Footer')]);
      expect(
        convOf(doc).convertTable(table),
        '.TS\n'
        'allbox tab(:);\n'
        'ltB.\n'
        'T{\n'
        'Header\n'
        'T}\n'
        '.T&\n'
        'lt.\n'
        'T{\n'
        'Body 1\n'
        'T}\n'
        'T{\n'
        'Body 2\n'
        'T}\n'
        'T{\n'
        'Footer\n'
        'T}\n'
        '.TE\n'
        '.sp',
      );
    });

    test('manifies table titles', () {
      final doc = manDoc();
      final table =
          StubTable(doc, <String, Object?>{}, stubTitle: 'Table of options')
            ..caption = 'Table 1. '
            ..createColumns(
              List.generate(3, (_) => <String, Object?>{'width': 1}),
            )
            ..hasHeaderOption = true;
      table.rows.head.add([
        textCell(table, 0, 'Name'),
        textCell(table, 1, 'Description'),
        textCell(table, 2, 'Default'),
      ]);
      table.rows.body.add([
        textCell(table, 0, 'dim'),
        textCell(table, 1, 'dimension of the object'),
        textCell(table, 2, '3'),
      ]);
      expect(
        convOf(doc).convertTable(table),
        '.sp\n'
        '.it 1 an-trap\n'
        '.nr an-no-space-flag 1\n'
        '.nr an-break-flag 1\n'
        '.br\n'
        '.B Table 1. Table of options\n'
        '.TS\n'
        'allbox tab(:);\n'
        'ltB ltB ltB.\n'
        'T{\n'
        'Name\n'
        'T}:T{\n'
        'Description\n'
        'T}:T{\n'
        'Default\n'
        'T}\n'
        '.T&\n'
        'lt lt lt.\n'
        'T{\n'
        'dim\n'
        'T}:T{\n'
        'dimension of the object\n'
        'T}:T{\n'
        '3\n'
        'T}\n'
        '.TE\n'
        '.sp',
      );
    });

    test('preserves breaks between paragraphs in normal cells', () {
      final doc = manDoc();
      final table = makeTable(doc, [100]);
      final cell = StubCell(
        table.columns[0],
        'x',
        stubText: 'x',
        stubContent: <String>['first paragraph', 'second paragraph'],
      );
      table.rows.body.add([cell]);
      expect(
        convOf(doc).convertTable(table),
        contains('T{\nfirst paragraph\n.sp\nsecond paragraph\nT}'),
      );
    });

    test('manifies and preserves whitespace in literal cells', () {
      final doc = manDoc();
      final table = makeTable(doc, [50, 50]);
      final literal = StubCell(
        table.columns[1],
        'b\nc    _d_\n.',
        attributes: {'style': 'literal'},
        stubText: 'b\nc    _d_\n.',
      );
      table.rows.body.add([textCell(table, 0, 'a'), literal]);
      expect(
        convOf(doc).convertTable(table),
        '.TS\n'
        'allbox tab(:);\n'
        'lt lt.\n'
        'T{\n'
        'a\n'
        'T}:T{\n'
        '.nf\n'
        'b\n'
        'c\\&    _d_\n'
        '\\&.\n'
        '.fi\n'
        'T}\n'
        '.TE\n'
        '.sp',
      );
    });

    test('converts asciidoc cells from converted content', () {
      final doc = manDoc();
      final table = makeTable(doc, [100]);
      final cell = StubCell(
        table.columns[0],
        'x',
        stubText: 'x',
        stubContent: '.sp\nasciidoc body',
      )..style = 'asciidoc';
      table.rows.body.add([cell]);
      expect(
        convOf(doc).convertTable(table),
        contains('T{\n.sp\nasciidoc body\nT}'),
      );
    });

    test('marks colspan cells with st', () {
      final doc = manDoc();
      final table = (makeTable(doc, [1, 1, 1]))..hasHeaderOption = true;
      table.rows.head.add([
        textCell(table, 0, 'wide cell', attributes: {'colspan': 3}),
      ]);
      table.rows.body.add([
        textCell(table, 0, 'a'),
        textCell(table, 1, 'b'),
        textCell(table, 2, 'c'),
      ]);
      final output = convOf(doc).convertTable(table);
      expect(output, contains('ltB st st.\nT{\nwide cell\nT}\n.T&'));
    });

    test('inserts placeholders for rowspan cells', () {
      final doc = manDoc();
      final table = makeTable(doc, [50, 50]);
      table.rows.body.add([
        textCell(table, 0, 'a', attributes: {'rowspan': 2}),
        textCell(table, 1, 'b'),
      ]);
      table.rows.body.add([textCell(table, 1, 'c')]);
      expect(
        convOf(doc).convertTable(table),
        contains('T{\na\nT}:T{\nb\nT}\nT{\nT}:T{\nc\nT}'),
      );
    });
  });

  group('inline anchor', () {
    test('converts links to URL macros', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'link',
        target: 'http://asciidoc.org',
        text: 'AsciiDoc',
      );
      expect(
        convOf(doc).convertInlineAnchor(node),
        '${escBs}c\n${escFs}URL "http://asciidoc.org" "AsciiDoc" ',
      );
    });

    test('blanks the text for bare links', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'link',
        target: 'http://asciidoc.org',
        text: 'http://asciidoc.org',
      );
      expect(
        convOf(doc).convertInlineAnchor(node),
        '${escBs}c\n${escFs}URL "http://asciidoc.org" "" ',
      );
    });

    test('escapes quotes in link text', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'link',
        target: 'http://example.org',
        text: 'say "hi"',
      );
      expect(
        convOf(doc).convertInlineAnchor(node),
        contains('"say $escBs(dqhi$escBs(dq" '),
      );
    });

    test('converts email links to MTO macros', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'link',
        target: 'mailto:doc@example.org',
        text: 'Contact the doc',
      );
      expect(
        convOf(doc).convertInlineAnchor(node),
        '${escBs}c\n${escFs}MTO "doc$escBs(atexample.org" '
        '"Contact the doc" ',
      );
    });

    test('blanks the text for implicit emails', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'link',
        target: 'mailto:doc@example.org',
        text: 'doc@example.org',
      );
      expect(
        convOf(doc).convertInlineAnchor(node),
        '${escBs}c\n${escFs}MTO "doc$escBs(atexample.org" "" ',
      );
    });

    test('keeps explicit xref text', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'xref',
        target: '#sec',
        text: 'Section',
      );
      expect(convOf(doc).convertInlineAnchor(node), 'Section');
    });

    test('resolves automatic xref text from the catalog', () {
      final doc = manDoc();
      final section = StubSection(parent: doc, level: 2, stubTitle: 'Options')
        ..sectname = 'section';
      registerRef(doc, 'sec-options', section);
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'xref',
        target: '#sec-options',
        attributes: {'refid': 'sec-options'},
      );
      expect(convOf(doc).convertInlineAnchor(node), 'Options');
    });

    test('uppercases reftext matching a level-1 section title', () {
      final doc = manDoc();
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Foo Bar')
        ..sectname = 'section';
      registerRef(doc, 'sec-foo-bar', section);
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'xref',
        target: '#sec-foo-bar',
        attributes: {'refid': 'sec-foo-bar'},
      );
      expect(convOf(doc).convertInlineAnchor(node), 'FOO BAR');
    });

    test('falls back to the refid for unresolved xrefs', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'xref',
        target: '#missing',
        attributes: {'refid': 'missing'},
      );
      expect(convOf(doc).convertInlineAnchor(node), '[missing]');
    });

    test('hides ref and bibref anchors', () {
      final doc = manDoc();
      final parent = para(doc, '');
      expect(
        convOf(doc).convertInlineAnchor(
          Inline(parent, 'anchor', type: 'ref', target: 'a'),
        ),
        '',
      );
      expect(
        convOf(doc).convertInlineAnchor(
          Inline(parent, 'anchor', type: 'bibref', target: 'b'),
        ),
        '',
      );
    });

    test('warns and returns null for unknown anchor types', () {
      usingMemoryLogger((logger) {
        final doc = manDoc();
        final node = Inline(
          para(doc, ''),
          'anchor',
          type: 'weird',
          target: 't',
          text: 'x',
        );
        expect(convOf(doc).convertInlineAnchor(node), isNull);
        expect(logger.warns, ['unknown anchor type: :weird']);
      });
    });

    test('resolves styled xref text', () {
      // Port of manpage_test.rb 'should reference image with title usign
      // styled xref', in end-to-end form: the StubBlock unit context
      // bypasses title subs, so only a parsed document yields the
      // quote-escaped man output.
      const input =
          '= command (1)\n'
          'Author Name\n'
          ':doctype: manpage\n'
          ':man manual: Command Manual\n'
          ':man source: Command 1.2.3\n'
          '\n'
          '== NAME\n'
          '\n'
          'command - does stuff\n'
          '\n'
          '== SYNOPSIS\n'
          '\n'
          'To get your fortune, see <<magic-8-ball>>.\n'
          '\n'
          '.Magic 8-Ball\n'
          '[#magic-8-ball]\n'
          'image::signs-point-to-yes.jpg[]\n';
      final doc = Document(input, {
        'backend': 'manpage',
        'standalone': true,
        'attributes': {'xrefstyle': 'full'},
      }).parse();
      final lines = (doc.convert()! as String).split('\n');
      expect(
        lines,
        contains(r'To get your fortune, see Figure 1, \(lqMagic 8\-Ball\(rq.'),
      );
      expect(lines, contains(r'.B Figure 1. Magic 8\-Ball'));
    });
  });

  group('other inlines', () {
    test('converts inline breaks', () {
      final doc = manDoc();
      final node = Inline(para(doc, ''), 'break', text: 'Before break.');
      expect(convOf(doc).convertInlineBreak(node), 'Before break.\n${escFs}br');
    });

    test('converts inline buttons', () {
      final doc = manDoc();
      final node = Inline(para(doc, ''), 'button', text: 'Save');
      expect(
        convOf(doc).convertInlineButton(node),
        '<${escBs}fB>[${escBs}0Save${escBs}0]</${escBs}fP>',
      );
    });

    test('converts inline callouts', () {
      final doc = manDoc();
      final node = Inline(para(doc, ''), 'callout', text: '1');
      expect(
        convOf(doc).convertInlineCallout(node),
        '<${escBs}fB>(1)</${escBs}fP>',
      );
    });

    test('converts footnotes by index', () {
      final doc = manDoc();
      final node = Inline(para(doc, ''), 'footnote', attributes: {'index': 1});
      expect(convOf(doc).convertInlineFootnote(node), '[1]');
    });

    test('converts footnote xrefs by text', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'footnote',
        type: 'xref',
        text: 'does-not-exist',
      );
      expect(convOf(doc).convertInlineFootnote(node), '[does-not-exist]');
    });

    test('returns null for footnotes without index or xref', () {
      final doc = manDoc();
      final node = Inline(para(doc, ''), 'footnote');
      expect(convOf(doc).convertInlineFootnote(node), isNull);
    });

    test('converts inline images to bracketed alt text', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'image',
        attributes: {'alt': 'signs point to yes'},
      );
      expect(convOf(doc).convertInlineImage(node), '[signs point to yes]');
    });

    test('appends the link for linked inline images', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'image',
        attributes: {
          'alt': 'signs point to yes',
          'link': 'https://example.org/ball',
        },
      );
      expect(
        convOf(doc).convertInlineImage(node),
        '[signs point to yes] <https://example.org/ball>',
      );
    });

    test('converts visible index terms to their text', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'indexterm',
        type: 'visible',
        text: 'term',
      );
      expect(convOf(doc).convertInlineIndexterm(node), 'term');
    });

    test('hides non-visible index terms', () {
      final doc = manDoc();
      final node = Inline(para(doc, ''), 'indexterm', text: 'term');
      expect(convOf(doc).convertInlineIndexterm(node), '');
    });

    test('converts a single key', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'kbd',
        attributes: {
          'keys': ['Enter'],
        },
      );
      expect(
        convOf(doc).convertInlineKbd(node),
        '<${escBs}f(CR>Enter</${escBs}fP>',
      );
    });

    test('joins key sequences with plus', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'kbd',
        attributes: {
          'keys': ['Ctrl', 's'],
        },
      );
      expect(
        convOf(doc).convertInlineKbd(node),
        '<${escBs}f(CR>Ctrl${escBs}0+${escBs}0s</${escBs}fP>',
      );
    });

    test('converts a single menu reference', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'menu',
        attributes: {'menu': 'File', 'submenus': <String>[]},
      );
      expect(
        convOf(doc).convertInlineMenu(node),
        '<${escBs}fI>File</${escBs}fP>',
      );
    });

    test('converts a menu sequence', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'menu',
        attributes: {
          'menu': 'File',
          'submenus': <String>[],
          'menuitem': 'New Tab',
        },
      );
      final caret = '${escBs}0$escBs(fc${escBs}0';
      expect(
        convOf(doc).convertInlineMenu(node),
        '<${escBs}fI>File${caret}New Tab</${escBs}fP>',
      );
    });

    test('converts a menu sequence with submenus', () {
      final doc = manDoc();
      final node = Inline(
        para(doc, ''),
        'menu',
        attributes: {
          'menu': 'View',
          'submenus': ['Zoom'],
          'menuitem': 'Zoom In',
        },
      );
      final caret = '${escBs}0$escBs(fc${escBs}0';
      expect(
        convOf(doc).convertInlineMenu(node),
        '<${escBs}fI>View</${escBs}fP>'
        '$caret<${escBs}fI>Zoom</${escBs}fP>'
        '$caret<${escBs}fI>Zoom In</${escBs}fP>',
      );
    });

    test('converts quoted spans without word boundaries', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      String? q(String type) => conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: type, text: 'text'),
      );
      expect(q('emphasis'), '<${escBs}fI>text</${escBs}fP>');
      expect(q('strong'), '<${escBs}fB>text</${escBs}fP>');
      expect(q('monospaced'), '<${escBs}f(CR>text</${escBs}fP>');
      expect(q('single'), '<$escBs(oq>text</$escBs(cq>');
      expect(q('double'), '<$escBs(lq>text</$escBs(rq>');
      expect(q('mark'), 'text');
    });
  });

  group('manify entities', () {
    const cases = <String, String>{
      '&#169; &amp; &#174; are translated, but not the &amp;.':
          r'\(co & \(rg are translated, but not the &.',
      'A &#43; B': 'A + B',
      '0&#176; is freezing': r'0\(de is freezing',
      'go &#8212; to': r'go \(em to',
      'go&#8212;&#8203;to': r'go\(emto',
      "'command'": r'\*(Aqcommand\*(Aq',
      'a-b': r'a\-b',
      '&lt;tag&gt;': '<tag>',
      'a&#160;b': r'a\~b',
      '&#169; 2026': r'\(co 2026',
      '&#174;': r'\(rg',
      '&#8482;': r'\(tm',
      'a&#8201;b': 'a b',
      'a&#8211;b': r'a\(enb',
      '&#8216;hi&#8217;': r'\(oqhi\(cq',
      '&#8220;hi&#8221;': r'\(lqhi\(rq',
      '&#8592; back': r'\(<- back',
      'forth &#8594;': r'forth \(->',
      '&#8656; wide': r'\(lA wide',
      'wide &#8658;': r'wide \(rA',
      'a&#8203;b': r'a\:b',
      'AT&amp;T': 'AT&T',
      '&#8230;': r'\&.\|.\|.',
      'x &#8230;.': r'x .\|.\|..',
    };
    for (final entry in cases.entries) {
      test('manifies ${entry.key}', () {
        final doc = manDoc();
        expect(
          convOf(doc).convertParagraph(para(doc, entry.key)),
          '.sp\n${entry.value}',
        );
      });
    }

    test('leaves non-ellipsis dots alone', () {
      final doc = manDoc();
      expect(
        convOf(doc).convertParagraph(para(doc, 'commit&#8230; here')),
        '.sp\ncommit.\\|.\\|. here',
      );
      expect(
        convOf(doc).convertParagraph(para(doc, 'commit... here')),
        '.sp\ncommit... here',
      );
    });

    test('escapes a lone period', () {
      final doc = manDoc();
      expect(convOf(doc).convertParagraph(para(doc, '.')), '.sp\n\\&.');
    });

    test('escapes raw macros at line starts', () {
      final doc = manDoc();
      final node = para(doc, 'AAA visible\n.if 1 .nx\nBBB visible');
      expect(
        convOf(doc).convertParagraph(node),
        '.sp\nAAA visible\n\\&.if 1 .nx\nBBB visible',
      );
    });

    test('escapes ellipsis at the start of a line', () {
      final doc = manDoc();
      final node = para(doc, '&#8230;rest');
      expect(convOf(doc).convertParagraph(node), '.sp\n\\&.\\|.\\|.rest');
    });
  });

  group('manify backslashes and boundaries', () {
    test('preserves literal backslashes in content', () {
      final doc = manDoc();
      final node = para(doc, '\\.foo \\ bar \\\\ baz\\\nmore');
      expect(
        convOf(doc).convertParagraph(node),
        '.sp\n\\(rs.foo \\(rs bar \\(rs\\(rs baz\\(rs\nmore',
      );
    });

    test('escapes literal escape sequences', () {
      final doc = manDoc();
      expect(
        convOf(doc).convertParagraph(para(doc, r'\fB makes text bold')),
        '.sp\n\\(rsfB makes text bold',
      );
    });

    test('preserves backslashes in escape sequences', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      String q(String type, String text) => conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: type, text: text),
      )!;
      final node = para(
        doc,
        '${q('double', 'hello')} ${q('single', 'goodbye')} '
        '${q('strong', 'strong')} ${q('emphasis', 'weak')} '
        "${q('monospaced', 'even')}",
      );
      expect(
        conv.convertParagraph(node),
        '.sp\n\\(lqhello\\(rq \\(oqgoodbye\\(cq '
        r'\fBstrong\fP \fIweak\fP \f(CReven\fP',
      );
    });

    test('preserves inline breaks', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final br = conv.convertInlineBreak(
        Inline(para(doc, ''), 'break', text: 'Before break.'),
      );
      expect(
        conv.convertParagraph(para(doc, '$br\nAfter break.')),
        '.sp\nBefore break.\n.br\nAfter break.',
      );
    });

    test('collapses whitespace in titles', () {
      final doc = manDoc();
      final node = para(doc, 'body', title: 'a  b\tc\nd');
      expect(convOf(doc).convertParagraph(node), '.sp\n.B a b c d\n.br\nbody');
    });

    test('strips trailing whitespace', () {
      final doc = manDoc();
      expect(convOf(doc).convertParagraph(para(doc, 'hello   ')), '.sp\nhello');
    });

    test('formats buttons, keys and menus in context', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final btn = conv.convertInlineButton(Inline(parent, 'button', text: 'S'));
      final kbd = conv.convertInlineKbd(
        Inline(
          parent,
          'kbd',
          attributes: {
            'keys': ['Ctrl', 's'],
          },
        ),
      );
      final menu = conv.convertInlineMenu(
        Inline(
          parent,
          'menu',
          attributes: {
            'menu': 'File',
            'submenus': <String>[],
            'menuitem': 'New',
          },
        ),
      );
      expect(
        conv.convertParagraph(para(doc, '$btn $kbd $menu')),
        '.sp\n\\fB[\\0S\\0]\\fP \\f(CRCtrl\\0+\\0s\\fP '
        r'\fIFile\0\(fc\0New\fP',
      );
    });
  });

  group('URL and MTO macros', () {
    test('leaves no blank line before a URL macro', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final link = conv.convertInlineAnchor(
        Inline(
          parent,
          'anchor',
          type: 'link',
          target: 'http://asciidoc.org',
          text: 'AsciiDoc',
        ),
      )!;
      expect(
        conv.convertParagraph(para(doc, link)),
        '.sp\n.URL "http://asciidoc.org" "AsciiDoc" ""',
      );
    });

    test('does not swallow content following a URL', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final link = conv.convertInlineAnchor(
        Inline(
          parent,
          'anchor',
          type: 'link',
          target: 'http://asciidoc.org',
          text: 'AsciiDoc',
        ),
      )!;
      expect(
        conv.convertParagraph(para(doc, '$link can be used.')),
        '.sp\n.URL "http://asciidoc.org" "AsciiDoc" ""\ncan be used.',
      );
    });

    test('passes adjacent characters as the final URL argument', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final link = conv.convertInlineAnchor(
        Inline(
          parent,
          'anchor',
          type: 'link',
          target: 'http://asciidoc.org',
          text: 'AsciiDoc',
        ),
      )!;
      expect(
        conv.convertParagraph(para(doc, 'This is $link.')),
        '.sp\nThis is \\c\n.URL "http://asciidoc.org" "AsciiDoc" "."',
      );
    });

    test('moves trailing content after a URL to the next line', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final link = conv.convertInlineAnchor(
        Inline(
          parent,
          'anchor',
          type: 'link',
          target: 'http://asciidoc.org',
          text: 'AsciiDoc',
        ),
      )!;
      expect(
        conv.convertParagraph(
          para(doc, 'This is $link, which can be used to write content.'),
        ),
        '.sp\nThis is \\c\n.URL "http://asciidoc.org" "AsciiDoc" ","\n'
        'which can be used to write content.',
      );
    });

    test('leaves no blank lines between contiguous URLs', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      String link(String target, String text) => conv.convertInlineAnchor(
        Inline(parent, 'anchor', type: 'link', target: target, text: text),
      )!;
      final first = link('http://clisp.sf.net', 'CLISP');
      final second = link('http://ccl.clozure.com', 'Clozure CL');
      expect(
        conv.convertParagraph(
          para(doc, 'The implementations are\n$first,\n$second,\nand done.'),
        ),
        '.sp\nThe implementations are\n'
        '.URL "http://clisp.sf.net" "CLISP" ","\n'
        '.URL "http://ccl.clozure.com" "Clozure CL" ","\n'
        'and done.',
      );
    });

    test('keeps monospaced text inside links', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final mono = conv.convertInlineQuoted(
        Inline(parent, 'quoted', type: 'monospaced', text: 'cat'),
      )!;
      final link = conv.convertInlineAnchor(
        Inline(parent, 'anchor', type: 'link', target: 'cat', text: mono),
      )!;
      expect(
        conv.convertParagraph(para(doc, 'Enter the $link command.')),
        '.sp\nEnter the \\c\n.URL "cat" "\\f(CRcat\\fP" ""\ncommand.',
      );
    });

    test('formats MTO macros in context', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final mto = conv.convertInlineAnchor(
        Inline(
          parent,
          'anchor',
          type: 'link',
          target: 'mailto:doc@example.org',
          text: 'Contact the doc',
        ),
      )!;
      expect(
        conv.convertParagraph(para(doc, mto)),
        '.sp\n.MTO "doc\\(atexample.org" "Contact the doc" ""',
      );
    });

    test('formats implicit emails with trailing punctuation', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final mto = linkText(
        conv,
        parent,
        'mailto:doc@example.org',
        'doc@example.org',
      );
      expect(
        conv.convertParagraph(para(doc, 'Bugs fixed daily by $mto.')),
        '.sp\nBugs fixed daily by \\c\n'
        r'.MTO "doc\(atexample.org" "" "."',
      );
    });
  });

  group('footnote macros', () {
    test('formats a footnote with a bare URL', () {
      final doc = manDoc();
      addFootnote(
        doc,
        1,
        linkText(convOf(doc), para(doc, ''), 'https://e.org'),
      );
      expect(
        convOf(doc).convertEmbedded(doc),
        '\n.SH "NOTES"\n.IP [1]\n.URL "https://e.org" "" ""',
      );
    });

    test('formats a footnote with text before a bare URL', () {
      final doc = manDoc();
      final bare = linkText(convOf(doc), para(doc, ''), 'https://e.org');
      addFootnote(doc, 1, 'see $bare');
      expect(
        convOf(doc).convertEmbedded(doc),
        '\n.SH "NOTES"\n.IP [1]\nsee \\c\n.URL "https://e.org" "" ""',
      );
    });

    test('formats a footnote with text after a bare URL', () {
      final doc = manDoc();
      final bare = linkText(convOf(doc), para(doc, ''), 'https://e.org');
      addFootnote(doc, 1, '$bare is the place');
      expect(
        convOf(doc).convertEmbedded(doc),
        '\n.SH "NOTES"\n.IP [1]\n.URL "https://e.org" "" ""\nis the place',
      );
    });

    test('formats a footnote with a URL macro and punctuation', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final link = conv.convertInlineAnchor(
        Inline(
          para(doc, ''),
          'anchor',
          type: 'link',
          target: 'https://example.org',
          text: 'example site',
        ),
      )!;
      addFootnote(doc, 1, 'go to $link.');
      expect(
        conv.convertEmbedded(doc),
        '\n.SH "NOTES"\n.IP [1]\ngo to \\c\n'
        '.URL "https://example.org" "example site" "."',
      );
    });

    test('restores newlines collapsed in footnote macros', () {
      final doc = manDoc();
      final conv = convOf(doc);
      final parent = para(doc, '');
      final link = conv.convertInlineAnchor(
        Inline(
          parent,
          'anchor',
          type: 'link',
          target: 'https://example.org',
          text: 'example site',
        ),
      )!;
      // Simulate normalize_text collapsing the newline after \c.
      addFootnote(doc, 1, 'go to ${link.replaceAll('\n', ' ')}.');
      expect(
        conv.convertEmbedded(doc),
        '\n.SH "NOTES"\n.IP [1]\ngo to \\c\n'
        '.URL "https://example.org" "example site" "."',
      );
    });

    test('manifies footnote text', () {
      final doc = manDoc();
      addFootnote(doc, 1, 'a -- b');
      expect(convOf(doc).convertEmbedded(doc), contains('.IP [1]\na \\-\\- b'));
    });
  });

  group('writeAlternatePages', () {
    test('writes .so stubs for alternate names', () {
      final dir = Directory.systemTemp.createTempSync('manpage_test');
      try {
        ManpageConverter.writeAlternatePages(
          ['command', 'alt1', 'alt2'],
          '1',
          '${dir.path}/command.1',
        );
        expect(File('${dir.path}/alt1.1').readAsStringSync(), '.so command.1');
        expect(File('${dir.path}/alt2.1').readAsStringSync(), '.so command.1');
        expect(File('${dir.path}/command.1').existsSync(), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('does nothing for a single name', () {
      final dir = Directory.systemTemp.createTempSync('manpage_test');
      try {
        ManpageConverter.writeAlternatePages(
          ['command'],
          '1',
          '${dir.path}/command.1',
        );
        expect(dir.listSync(), isEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('does nothing without names', () {
      ManpageConverter.writeAlternatePages(null, '1', '/nonexistent/x.1');
    });
  });

  group('substitution integration', () {
    test('resolves xrefstyle full on sections', () {
      final doc = manDoc();
      doc.attributes['xrefstyle'] = 'full';
      final section = StubSection(parent: doc, level: 1, stubTitle: 'Options')
        ..sectname = 'chapter'
        ..numbered = true;
      registerRef(doc, 'sec-options', section);
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'xref',
        target: '#sec-options',
        attributes: {'refid': 'sec-options'},
      );
      expect(convOf(doc).convertInlineAnchor(node), contains('Options'));
    });

    test('breaks circular references in section titles', () {
      final doc = manDoc();
      // Sections whose titles contain xrefs to each other resolve through
      // the substitutors wave; the converter must not recurse forever.
      final sectionA = StubSection(parent: doc, level: 1, stubTitle: 'A B [A]')
        ..sectname = 'section';
      registerRef(doc, 'a', sectionA);
      final node = Inline(
        para(doc, ''),
        'anchor',
        type: 'xref',
        target: '#a',
        attributes: {'refid': 'a'},
      );
      expect(convOf(doc).convertInlineAnchor(node), 'A B [A]');
    });
  });
}
