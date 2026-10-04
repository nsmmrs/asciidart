// The `<<` append operator intentionally returns its receiver (Ruby
// parity); statement uses discard it.
// ignore_for_file: unnecessary_statements
/// Behavioral tests for the structural document model port.
///
/// Covers `section.dart`, `list.dart`, `table.dart` against the merged
/// model-core (`abstract_node.dart`, `abstract_block.dart`, `block.dart`,
/// `inline.dart`) with direct construction + assertion tests.
/// Every expectation was verified against the real Ruby classes with
/// `ruby -Ilib` probes (see the subagent report for the probe log).
///
/// `FakeDocument` stands in for `Document` (not yet ported): it extends
/// [AbstractBlock] with the `'document'` context and implements the
/// document surface the structural classes call (`attributes`, `catalog`,
/// `counter`, `callouts`, `converter`, `playbackAttributes`,
/// `incrementAndStoreCounter`, `nested`, `sourcemap`, `compatMode`).
/// Its `counter`/`incrementAndStoreCounter` only implement the
/// fresh-counter path; see the class docs.
library;

import 'package:asciidoctor/asciidoctor.dart';
import 'package:test/test.dart';

/// Records conversions instead of performing them.
class FakeConverter implements NodeConverter {
  /// Nodes converted so far, in order.
  final List<AbstractNode> converted = <AbstractNode>[];

  /// Records [node] and returns a string identifying it.
  @override
  String convert(AbstractNode node) {
    converted.add(node);
    final extra = node is Inline ? ':${node.type}=${node.text}' : '';
    return '<${node.nodeName}$extra>';
  }
}

/// Records log messages for assertions.
class FakeLogger implements NodeLogger {
  /// Messages by severity.
  final List<Object?> debugs = <Object?>[];
  final List<Object?> infos = <Object?>[];
  final List<Object?> warns = <Object?>[];
  final List<Object?> errors = <Object?>[];
  final List<Object?> fatals = <Object?>[];

  @override
  void debug(Object? message) {
    debugs.add(message);
  }

  @override
  void info(Object? message) {
    infos.add(message);
  }

  @override
  void warn(Object? message) {
    warns.add(message);
  }

  @override
  void error(Object? message) {
    errors.add(message);
  }

  @override
  void fatal(Object? message) {
    fatals.add(message);
  }
}

/// Minimal stand-in for `Document`.
///
/// Mirrors `Document#<<` (numeral assignment for sections). The
/// [counter]/[incrementAndStoreCounter] implementations cover the
/// fresh-counter path only (no parent document, attribute locking, or
/// preset attribute values); sufficient for the structural tests, which
/// always start from a fresh catalog.
class FakeDocument extends AbstractBlock implements NodeDocument {
  /// Creates a document with [attributes] (and optional [parent], which a
  /// document-context node ignores, as in Ruby).
  // ignore: use_super_parameters (explicit super call fixes the context)
  new({Map<String, Object?>? attributes, AbstractBlock? parent})
    : super(parent, 'document', attributes: attributes);

  /// The document catalog (only `refs` is used here).
  @override
  final Map<String, Map<String, Object?>> catalog =
      <String, Map<String, Object?>>{'refs': <String, Object?>{}};

  /// Counter storage backing [counter].
  final Map<String, Object?> documentCounters = <String, Object?>{};

  /// The document callouts catalog (the real ported implementation).
  @override
  final Callouts callouts = Callouts();

  /// The document converter (fake).
  @override
  final FakeConverter converter = FakeConverter();

  /// The safe mode level the document runs under.
  @override
  int safe = SafeMode.safe;

  /// The base directory used to resolve relative paths.
  @override
  String baseDir = '';

  /// The path resolver used to resolve system and web paths.
  @override
  final PathResolver pathResolver = PathResolver();

  /// Whether source locations are tracked.
  @override
  bool sourcemap = false;

  /// The document compatibility mode flag.
  @override
  bool compatMode = false;

  /// Whether this document is nested inside another one.
  bool isNested = false;

  /// Whether this document is nested (mirrors `Document#nested?`).
  @override
  bool nested() => isNested;

  /// Attribute maps passed to [playbackAttributes], in order.
  final List<Map<String, Object?>> playbacked = <Map<String, Object?>>[];

  /// Records [blockAttributes] (mirrors `Document#playback_attributes`).
  @override
  void playbackAttributes(Map<String, Object?> blockAttributes) {
    playbacked.add(blockAttributes);
  }

  /// Returns the next value of the counter [name], seeding it with [seed].
  ///
  /// Mirrors the fresh-counter path of `Document#counter`.
  @override
  dynamic counter(String name, [Object? seed]) {
    if (documentCounters.containsKey(name)) {
      final next = Helpers.nextVal(documentCounters[name]!);
      documentCounters[name] = next;
      attributes[name] = next;
      return next;
    }
    if (seed != null) {
      final asInt = rubyToInteger(seed);
      final value = seed == asInt.toString() ? asInt : seed;
      documentCounters[name] = value;
      attributes[name] = value;
      return value;
    }
    documentCounters[name] = 1;
    attributes[name] = 1;
    return 1;
  }

  /// Increments the counter [counterName], stores it on [block], and
  /// returns it.
  ///
  /// Simplified mirror of `Document#increment_and_store_counter` (which
  /// routes through `AttributeEntry`; only the stored value and return
  /// value matter here).
  @override
  dynamic incrementAndStoreCounter(String counterName, AbstractBlock block) {
    final value = counter(counterName);
    block.attributes[counterName] = value;
    return value;
  }

  /// Appends [block], assigning an index/numeral to sections first.
  ///
  /// Mirrors `Document#<<`.
  @override
  AbstractBlock operator <<(AbstractBlock block) {
    if (block.context == 'section') assignNumeral(block as Section);
    return super << block;
  }
}

/// Minimal stand-in for `Reader`, exposing the cursor surface the table
/// parser context calls.
class FakeReader {
  /// Creates a reader returning [markData] from [mark].
  new({
    this.markData = const <Object?>[],
    this.prevLineCursor,
    this.beforeMarkCursor,
  });

  /// Data returned by [mark].
  final List<Object?> markData;

  /// Value returned by [cursorAtPrevLine].
  final Object? prevLineCursor;

  /// Value returned by [cursorBeforeMark].
  final Object? beforeMarkCursor;

  /// How often [mark] was called.
  int marks = 0;

  /// Records a mark and returns [markData].
  List<Object?> mark() {
    marks += 1;
    return markData;
  }

  /// Returns [prevLineCursor].
  Object? cursorAtPrevLine() => prevLineCursor;

  /// Returns [beforeMarkCursor].
  Object? cursorBeforeMark() => beforeMarkCursor;
}

/// Minimal source location with `file`/`lineno` and `dup`.
class FakeCursor implements NodeSourceLocation {
  /// Creates a cursor for [file]:[lineno].
  new(this.file, this.lineno);

  /// The source file.
  @override
  final String? file;

  /// The source line number.
  @override
  final int? lineno;

  /// Copies this cursor.
  FakeCursor dup() => FakeCursor(file, lineno);

  /// Advances the line number (recorded for assertions).
  int advancedBy = 0;

  /// Advances by [lines].
  void advance(int lines) {
    advancedBy += lines;
  }
}

void main() {
  late FakeLogger testLogger;
  late NodeLogger savedLogger;

  setUp(() {
    savedLogger = AbstractNode.currentLogger;
    testLogger = FakeLogger();
    AbstractNode.currentLogger = testLogger;
  });

  tearDown(() {
    AbstractNode.currentLogger = savedLogger;
  });

  group('Ruby shims', () {
    test('isTruthy matches Ruby truthiness', () {
      expect(isTruthy(null), isFalse);
      expect(isTruthy(false), isFalse);
      expect(isTruthy(true), isTrue);
      expect(isTruthy(0), isTrue);
      expect(isTruthy(''), isTrue);
      expect(isTruthy(<int>[]), isTrue);
    });

    test('rubyToInteger matches to_i', () {
      expect(rubyToInteger(12), equals(12));
      expect(rubyToInteger(12.9), equals(12));
      expect(rubyToInteger('12abc'), equals(12));
      expect(rubyToInteger('  -12x'), equals(-12));
      expect(rubyToInteger('+12'), equals(12));
      expect(rubyToInteger('abc'), equals(0));
      expect(rubyToInteger(''), equals(0));
      expect(rubyToInteger(null), equals(0));
      expect(() => rubyToInteger(true), throwsStateError);
    });

    test('rubyToDouble matches to_f', () {
      expect(rubyToDouble(800), equals(800.0));
      expect(rubyToDouble('12.9x'), equals(12.9));
      expect(rubyToDouble('abc'), equals(0.0));
      expect(rubyToDouble(null), equals(0.0));
    });

    test('rubySplit drops trailing empties like Ruby split', () {
      expect(rubySplit('a\n', '\n'), equals(['a']));
      expect(rubySplit('a\n\n', '\n'), equals(['a']));
      expect(rubySplit('', '\n'), equals([]));
      expect(rubySplit('a\n\nb', '\n'), equals(['a', '', 'b']));
      expect(rubySplit('p1\n\np2', RegExp(r'\n{2,}')), equals(['p1', 'p2']));
    });

    test('chopLast, chompSuffix, squeezeChar, lstrip', () {
      expect(chopLast('ab\r\n'), equals('ab'));
      expect(chopLast('a'), equals(''));
      expect(chopLast(''), equals(''));
      expect(chompSuffix('Figure 1. ', '. '), equals('Figure 1'));
      expect(chompSuffix('Figure 1', '. '), equals('Figure 1'));
      expect(squeezeChar('a"b""c', '"'), equals('a"b"c'));
      expect(lstrip('  \n x'), equals('x'));
    });

    test('transliterateSqueeze matches tr_s', () {
      expect(transliterateSqueeze('hello', 'l', 'r'), equals('hero'));
      expect(transliterateSqueeze('a  b', ' _.-', '_'), equals('a_b'));
      expect(transliterateSqueeze('__a__', ' _.-', '_'), equals('_a_'));
      expect(transliterateSqueeze('aabb', ' _.-', '_'), equals('aabb'));
      expect(transliterateSqueeze('a.b-c d', ' _.-', '_'), equals('a_b_c_d'));
      expect(transliterateSqueeze('a  b', ' .-', '-'), equals('a-b'));
    });

    test('splitWords and inspectString', () {
      expect(splitWords('  a  b\tc '), equals(['a', 'b', 'c']));
      expect(splitWords(''), equals([]));
      expect(splitWords('   '), equals([]));
      expect(inspectString('a"b'), equals(r'"a\"b"'));
      expect(inspectString(null), equals('nil'));
    });
  });

  group('AbstractNode attributes', () {
    test('constructor links document and copies attributes', () {
      final doc = FakeDocument();
      final passed = <String, Object?>{'a': '1'};
      final block = Block(doc, 'paragraph', attributes: passed);
      expect(block.document, same(doc));
      expect(block.parent, same(doc));
      expect(block.attributes, equals({'a': '1'}));
      passed['a'] = 'mutated';
      expect(block.attributes['a'], equals('1'));
      expect(block.context, equals('paragraph'));
      expect(block.nodeName, equals('paragraph'));
      expect(block.id, isNull);
    });

    test('document-context node is its own document and ignores parent', () {
      final outer = FakeDocument();
      final section = Section(outer, 1);
      final doc = FakeDocument(parent: section);
      expect(doc.document, same(doc));
      expect(doc.parent, isNull);
      expect(doc.level, equals(0));
    });

    test('parentless node has null document', () {
      final section = Section();
      expect(section.document, isNull);
      expect(section.parent, isNull);
    });

    test('attr reads node attributes with default', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', attributes: {'a': '1'});
      expect(block.attr('a'), equals('1'));
      expect(block.attr('missing'), isNull);
      expect(block.attr('missing', 'dflt'), equals('dflt'));
    });

    test('attr falls back to document attributes', () {
      final doc = FakeDocument(attributes: {'x': 'dx', 'b': 'db'});
      final block = Block(doc, 'paragraph');
      expect(block.attr('x', 'dflt', true), equals('dx'));
      expect(block.attr('a', 'dflt', 'b'), equals('db'));
      expect(block.attr('a', 'dflt', 'missing'), equals('dflt'));
      // No fallback without a fallback name.
      expect(block.attr('x', 'dflt'), equals('dflt'));
      expect(block.attr('x'), isNull);
    });

    test('attr fallback is skipped for parentless nodes', () {
      final block = Block(null, 'paragraph');
      expect(block.attr('x', 'dflt', true), equals('dflt'));
    });

    test('hasAttr checks presence, value and fallback', () {
      final doc = FakeDocument(attributes: {'x': 'dx'});
      final block = Block(doc, 'paragraph', attributes: {'a': '1'});
      expect(block.hasAttr('a'), isTrue);
      expect(block.hasAttr('missing'), isFalse);
      expect(block.hasAttr('a', '1'), isTrue);
      expect(block.hasAttr('a', '2'), isFalse);
      expect(block.hasAttr('x', null, true), isTrue);
      expect(block.hasAttr('x', 'dx', true), isTrue);
      expect(block.hasAttr('x', 'other', true), isFalse);
      expect(block.hasAttr('x'), isFalse);
    });

    test('setAttr and removeAttr', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph');
      expect(block.setAttr('a'), isTrue);
      expect(block.attributes['a'], equals(''));
      expect(block.setAttr('a', '1', false), isFalse);
      expect(block.attributes['a'], equals(''));
      expect(block.setAttr('a', '1'), isTrue);
      expect(block.attributes['a'], equals('1'));
      expect(block.removeAttr('a'), equals('1'));
      expect(block.removeAttr('a'), isNull);
    });

    test('options', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph');
      expect(block.hasOption('header'), isFalse);
      block
        ..setOption('header')
        ..setOption('footer');
      expect(block.hasOption('header'), isTrue);
      expect(block.enabledOptions, equals({'header', 'footer'}));
    });

    test('roles', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', attributes: {'role': 'a b c'});
      expect(block.role, equals('a b c'));
      expect(block.roles, equals(['a', 'b', 'c']));
      expect(block.hasRole(), isTrue);
      expect(block.hasRole('a b c'), isTrue);
      expect(block.hasRole('a'), isFalse);
      expect(block.includesRole('b'), isTrue);
      expect(block.includesRole('bc'), isFalse);
      final plain = Block(doc, 'paragraph');
      expect(plain.roles, equals([]));
      expect(plain.hasRole(), isFalse);
      expect(plain.includesRole('b'), isFalse);
      final empty = Block(doc, 'paragraph', attributes: {'role': '  '});
      expect(empty.roles, equals([]));
    });

    test('role setter joins lists like Array#join', () {
      final doc = FakeDocument();
      final block = (Block(doc, 'paragraph'))..role = ['a', 'b'];
      expect(block.attributes['role'], equals('a b'));
      block.role = ['a', null];
      expect(block.attributes['role'], equals('a '));
      block.role = 'x y';
      expect(block.attributes['role'], equals('x y'));
    });

    test('addRole and removeRole', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph');
      expect(block.addRole('a'), isTrue);
      expect(block.attributes['role'], equals('a'));
      expect(block.addRole('a'), isFalse);
      expect(block.addRole('b'), isTrue);
      expect(block.attributes['role'], equals('a b'));
      expect(block.removeRole('missing'), isFalse);
      expect(block.removeRole('a'), isTrue);
      expect(block.attributes['role'], equals('b'));
      expect(block.removeRole('b'), isTrue);
      expect(block.attributes.containsKey('role'), isFalse);
    });

    test('updateAttributes merges and returns attributes', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', attributes: {'a': '1'});
      final result = block.updateAttributes({'b': '2'});
      expect(result, same(block.attributes));
      expect(block.attributes, equals({'a': '1', 'b': '2'}));
    });

    test('reftext is null when unset; hasReftext', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph');
      expect(block.reftext, isNull);
      expect(block.hasReftext, isFalse);
      block.setAttr('reftext', 'Text');
      expect(block.hasReftext, isTrue);
    });

    test('parent setter repoints document', () {
      final doc = FakeDocument();
      final a = Section(doc, 1);
      final b = Section(doc, 1);
      final para = (Block(a, 'paragraph'))..parent = b;
      expect(para.parent, same(b));
      expect(para.document, same(doc));
    });
  });

  group('AbstractBlock', () {
    test('levels: document/section start at 0, children inherit', () {
      final doc = FakeDocument();
      expect(doc.level, equals(0));
      final section = Section(doc, 1);
      expect(section.level, equals(1));
      final para = Block(section, 'paragraph');
      expect(para.level, equals(1));
      final orphan = Block(null, 'paragraph');
      expect(orphan.level, isNull);
    });

    test('append reuses parent, fixes foreign parent, returns self', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      final other = Section(doc, 1);
      final para = Block(other, 'paragraph');
      final result = section << para;
      expect(result, same(section));
      expect(para.parent, same(section));
      expect(para.document, same(doc));
      expect(section.blocks, equals([para]));
      expect(section.hasBlocks, isTrue);
      // Appending again keeps the same parent without churn.
      expect(section.append(para), same(section));
      expect(para.parent, same(section));
      expect(Block(doc, 'paragraph').hasBlocks, isFalse);
    });

    test('sections selects section children', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      final child = Section(section, 2);
      final para = Block(section, 'paragraph');
      section << child << para;
      expect(section.sections, equals([child]));
      expect(section.hasSections, isTrue);
      expect(para.hasSections, isFalse);
    });

    test('context setter refreshes node name', () {
      final doc = FakeDocument();
      final block = (Block(doc, 'paragraph'))..context = 'sidebar';
      expect(block.context, equals('sidebar'));
      expect(block.nodeName, equals('sidebar'));
    });

    test('title accessors convert a set title', () {
      final doc = Document(<String>[]);
      final block = Block(doc, 'paragraph');
      expect(block.title, isNull);
      expect(block.hasTitle, isFalse);
      expect(block.sourceTitle, isNull);
      block.title = 'Hello';
      expect(block.hasTitle, isTrue);
      expect(block.sourceTitle, equals('Hello'));
      // Converting a set title performs real substitutions.
      expect(block.title, equals('Hello'));
      block.title = 'Other';
      expect(block.sourceTitle, equals('Other'));
    });

    test('hasSub and removeSub', () {
      final doc = FakeDocument();
      final item = ListItem(ListBlock(doc, 'ulist'), 'x');
      expect(item.hasSub('quotes'), isTrue);
      expect(item.hasSub('callouts'), isFalse);
      item.removeSub('quotes');
      expect(item.hasSub('quotes'), isFalse);
      // The shared default list is untouched (items get a copy).
      expect(normalSubs, contains('quotes'));
    });

    test('listMarkerKeyword', () {
      final doc = FakeDocument();
      final list = (ListBlock(doc, 'olist'))..style = 'lowerroman';
      expect(list.listMarkerKeyword(), equals('i'));
      expect(list.listMarkerKeyword('upperalpha'), equals('A'));
      expect(list.listMarkerKeyword('arabic'), isNull);
      list.style = null;
      expect(list.listMarkerKeyword(), isNull);
    });

    test('convert plays back attributes and converts', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', attributes: {'a': '1'});
      final result = block.convert();
      expect(result, equals('<paragraph>'));
      expect(doc.playbacked, equals([block.attributes]));
      expect(doc.converter.converted, equals([block]));
    });

    test('compound content joins converted children', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      section << Block(section, 'paragraph') << Block(section, 'paragraph');
      expect(section.content(), equals('<paragraph>\n<paragraph>'));
    });

    test('caption, admonition textlabel and captionedTitle', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph');
      expect(block.caption, isNull);
      block.caption = 'Figure 1. ';
      expect(block.caption, equals('Figure 1. '));
      final admonition = Block(
        doc,
        'admonition',
        attributes: {'textlabel': 'NOTE:'},
      );
      expect(admonition.caption, equals('NOTE:'));
      // captionedTitle reads the caption field (not the admonition label).
      expect(block.captionedTitle(), equals('Figure 1. '));
      expect(Block(doc, 'paragraph').captionedTitle(), equals(''));
    });

    test('file and lineno follow the source location', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph');
      expect(block.file, isNull);
      expect(block.lineno, isNull);
      block.sourceLocation = FakeCursor('doc.adoc', 7);
      expect(block.file, equals('doc.adoc'));
      expect(block.lineno, equals(7));
    });

    test('xreftext without title returns null', () {
      final doc = FakeDocument();
      expect(Block(doc, 'paragraph').xreftext(), isNull);
    });

    test('isBlock and isInline', () {
      final doc = FakeDocument();
      expect(doc.isBlock, isTrue);
      expect(doc.isInline, isFalse);
      expect(Block(doc, 'paragraph').isBlock, isTrue);
    });

    test('nextAdjacentBlock walks siblings and lists', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      doc << section;
      final list = ListBlock(section, 'dlist');
      final para = Block(section, 'paragraph');
      section << list << para;
      final terms = ListItem(list, 'term');
      final desc = ListItem(list, 'def');
      final terms2 = ListItem(list, 'term2');
      final desc2 = ListItem(list, 'def2');
      list.items.addAll([
        <Object?>[
          [terms],
          desc,
        ],
        <Object?>[
          [terms2],
          desc2,
        ],
      ]);
      expect(list.nextAdjacentBlock(), same(para));
      // Description-list items advance to the next pair.
      expect(desc.nextAdjacentBlock(), same(list.items[1]));
      expect(terms.nextAdjacentBlock(), same(list.items[1]));
      // Last pair members advance past the list.
      expect(desc2.nextAdjacentBlock(), same(para));
      // Trailing blocks yield null.
      expect(para.nextAdjacentBlock(), isNull);
      expect(section.nextAdjacentBlock(), isNull);
      expect(doc.nextAdjacentBlock(), isNull);
    });

    test('assignNumeral numbers plain, chapter and appendix sections', () {
      final doc = FakeDocument(attributes: {'appendix-caption': 'Appendix'});
      final s1 = Section(doc, 1, true)..sectname = 'section';
      final ch = Section(doc, 1, true)..sectname = 'chapter';
      final app = Section(doc, 1, true)..sectname = 'appendix';
      final part = Section(doc, 1, true)..sectname = 'part';
      final plain = Section(doc, 1)..sectname = 'section';
      doc
        ..assignNumeral(s1)
        ..assignNumeral(ch)
        ..assignNumeral(app)
        ..assignNumeral(part)
        ..assignNumeral(plain);
      expect([s1.index, s1.numeral], equals([0, '1']));
      expect([ch.index, ch.numeral], equals([1, '1']));
      expect([
        app.index,
        app.numeral,
        app.caption,
      ], equals([2, 'A', 'Appendix A: ']));
      // The ordinal is shared: s1 consumed 1, so the part is II (verified).
      expect([part.index, part.numeral], equals([3, 'II']));
      expect([plain.index, plain.numeral], equals([4, null]));
      // A second chapter continues the chapter counter.
      final ch2 = Section(doc, 1, true)..sectname = 'chapter';
      doc.assignNumeral(ch2);
      expect(ch2.numeral, equals('2'));
      // Unnumbered sections still consume indexes.
      expect(doc.nextSectionIndex, equals(6));
    });

    test('assignNumeral without appendix caption falls back', () {
      final doc = FakeDocument();
      final app = Section(doc, 1, true)..sectname = 'appendix';
      doc.assignNumeral(app);
      expect(app.numeral, equals('A'));
      expect(app.caption, equals('A. '));
    });

    test('reindexSections renumbers after removal', () {
      final doc = FakeDocument();
      final a = Section(doc, 1, true)..title = 'A';
      final b = Section(doc, 1, true)..title = 'B';
      final c = Section(doc, 1, true)..title = 'C';
      // Separate statements: `<<` returns the static AbstractBlock type,
      // so chaining would bypass the FakeDocument override.
      doc << a;
      doc << b;
      doc << c;
      doc.blocks.removeAt(0);
      doc.reindexSections();
      expect(
        doc.sections.map(
          (s) => [(s as Section).sourceTitle, s.index, s.numeral],
        ),
        equals([
          ['B', 0, '1'],
          ['C', 1, '2'],
        ]),
      );
    });

    test('assignCaption builds figure captions with counters', () {
      final doc = FakeDocument(attributes: {'figure-caption': 'Figure'});
      final img = Block(doc, 'image')
        ..title = 'Tiger'
        ..assignCaption(null, 'figure');
      expect(img.caption, equals('Figure 1. '));
      expect(img.numeral, equals(1));
      // A second captioned figure continues the counter.
      final img2 = Block(doc, 'image')
        ..title = 'Lion'
        ..assignCaption(null, 'figure');
      expect(img2.caption, equals('Figure 2. '));
      // Explicit captions win; untitled blocks stay captionless.
      final explicit = Block(doc, 'image')
        ..title = 'T'
        ..assignCaption('Custom. ');
      expect(explicit.caption, equals('Custom. '));
      final untitled = (Block(doc, 'image'))..assignCaption(null, 'figure');
      expect(untitled.caption, isNull);
    });
  });

  group('Block', () {
    test('content models default per context', () {
      final doc = FakeDocument();
      expect(Block(doc, 'paragraph').contentModel, equals('simple'));
      expect(Block(doc, 'listing').contentModel, equals('verbatim'));
      expect(Block(doc, 'literal').contentModel, equals('verbatim'));
      expect(Block(doc, 'image').contentModel, equals('empty'));
      expect(Block(doc, 'audio').contentModel, equals('empty'));
      expect(Block(doc, 'video').contentModel, equals('empty'));
      expect(Block(doc, 'stem').contentModel, equals('raw'));
      expect(Block(doc, 'pass').contentModel, equals('raw'));
      expect(Block(doc, 'open').contentModel, equals('compound'));
      expect(Block(doc, 'page_break').contentModel, equals('empty'));
      expect(Block(doc, 'thematic_break').contentModel, equals('empty'));
      expect(
        Block(doc, 'paragraph', contentModel: 'verbatim').contentModel,
        equals('verbatim'),
      );
    });

    test('source string is prepared into lines; lists are copied', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', source: 'a  \nb\t\n');
      expect(block.lines, equals(['a', 'b']));
      expect(block.source(), equals('a\nb'));
      final input = ['x', 'y'];
      final listed = Block(doc, 'paragraph', source: input);
      expect(listed.lines, equals(['x', 'y']));
      input.add('mutated');
      expect(listed.lines, equals(['x', 'y']));
      expect(Block(doc, 'paragraph').lines, equals([]));
      expect(Block(doc, 'paragraph', source: '').lines, equals([]));
      expect(Block(doc, 'paragraph').source(), equals(''));
    });

    test('simple content with deferred subs returns raw source', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', source: 'a<b>\nc');
      expect(block.subs, equals([]));
      expect(block.content(), equals('a<b>\nc'));
    });

    test('verbatim content strips blank edge lines', () {
      final doc = FakeDocument();
      final listing = Block(doc, 'listing', source: '\n\ncode\n\n');
      expect(listing.content(), equals('code'));
      // The source preparation rstrips every line up front (verified).
      final indented = Block(doc, 'literal', source: '  a\n  \n  b  \n\n');
      expect(indented.content(), equals('  a\n\n  b'));
      final single = Block(doc, 'listing', source: 'solo');
      expect(single.content(), equals('solo'));
      final blank = Block(doc, 'listing', source: '\n\n');
      expect(blank.content(), equals(''));
    });

    test('compound content joins children; empty and unknown models', () {
      final doc = FakeDocument();
      final open = Block(doc, 'open')..contentModel = 'compound';
      open << Block(open, 'paragraph', source: 'a');
      expect(open.content(), equals('<paragraph>'));
      expect(Block(doc, 'image').content(), isNull);
      expect(testLogger.warns, isEmpty);
      final weird = Block(doc, 'paragraph', contentModel: 'bogus');
      expect(weird.content(), isNull);
      expect(
        testLogger.warns.single,
        contains("unknown content model 'bogus'"),
      );
    });

    test('explicit null subs disables resolution', () {
      final doc = FakeDocument();
      final block = Block(
        doc,
        'paragraph',
        attributes: {'subs': 'quotes'},
        subs: null,
      );
      expect(block.defaultSubs, equals([]));
      expect(block.subs, equals([]));
      expect(block.attributes.containsKey('subs'), isFalse);
    });

    test('specified subs resolve eagerly via commitSubs', () {
      final doc = Document(<String>[]);
      // 'default' honors the subs attribute, then defaultSubs.
      expect(
        Block(doc, 'paragraph', subs: 'default', defaultSubs: ['quotes']).subs,
        equals(['quotes']),
      );
      expect(
        Block(
          doc,
          'paragraph',
          attributes: {'subs': 'quotes'},
          subs: ['quotes'],
        ).subs,
        equals(['quotes']),
      );
      expect(Block(doc, 'paragraph', subs: 'normal').subs, equals(normalSubs));
    });

    test('blockname aliases context; toString shape', () {
      final doc = FakeDocument();
      final block = Block(doc, 'paragraph', source: 'hi');
      expect(block.blockname, equals('paragraph'));
      expect(
        block.toString(),
        matches(
          // Ruby-faithful `#<...>` shape (the merged core's Block pins it;
          // the reference regex omitted the brackets).
          RegExp(
            r'^#<Block@\d+ \{context: :paragraph, content_model: :simple, style: nil, lines: 1\}>$',
          ),
        ),
      );
      final compound = Block(doc, 'open')..contentModel = 'compound';
      compound << Block(compound, 'paragraph');
      expect(compound.toString(), contains('blocks: 1'));
      expect(compound.toString(), contains('content_model: :compound'));
    });
  });

  group('Inline', () {
    test('construction assigns fields and node name', () {
      final doc = FakeDocument();
      final para = Block(doc, 'paragraph');
      final inline = Inline(
        para,
        'anchor',
        text: 'Text',
        id: 'a1',
        type: 'ref',
        target: 't',
      );
      expect(inline.text, equals('Text'));
      expect(inline.id, equals('a1'));
      expect(inline.type, equals('ref'));
      expect(inline.target, equals('t'));
      expect(inline.context, equals('anchor'));
      expect(inline.nodeName, equals('inline_anchor'));
      expect(inline.document, same(doc));
      expect(inline.isBlock, isFalse);
      expect(inline.isInline, isTrue);
      expect(inline.parent, same(para));
    });

    test('content aliases text; convert', () {
      final doc = FakeDocument();
      final para = Block(doc, 'paragraph');
      final inline = Inline(para, 'quoted', text: 'hi', type: 'strong');
      expect(inline.content(), equals('hi'));
      expect(inline.convert(), equals('<inline_quoted:strong=hi>'));
      expect(doc.converter.converted, equals([inline]));
    });

    test('alt returns the alt attribute or empty string', () {
      final doc = FakeDocument();
      final para = Block(doc, 'paragraph');
      expect(Inline(para, 'image').alt, equals(''));
      expect(
        Inline(para, 'image', attributes: {'alt': 'Alt'}).alt,
        equals('Alt'),
      );
    });

    test('reftext nodes: text is the reftext', () {
      final doc = Document(<String>[]);
      final para = Block(doc, 'paragraph');
      final ref = Inline(para, 'anchor', text: 'Name', type: 'ref');
      final bib = Inline(para, 'anchor', text: '[1]', type: 'bibref');
      final other = Inline(para, 'anchor', text: 'Name', type: 'link');
      final empty = Inline(para, 'anchor', type: 'ref');
      expect(ref.hasReftext, isTrue);
      expect(bib.hasReftext, isTrue);
      expect(other.hasReftext, isFalse);
      expect(empty.hasReftext, isFalse);
      expect(empty.reftext, isNull);
      expect(ref.xreftext(), equals('Name'));
      expect(ref.reftext, equals('Name'));
    });
  });

  group('Section', () {
    test('constructor defaults and nesting', () {
      final bare = Section();
      expect([
        bare.level,
        bare.special,
        bare.numbered,
        bare.index,
      ], equals([1, false, false, 0]));
      expect(bare.context, equals('section'));
      final doc = FakeDocument();
      final top = Section(doc, 1, true);
      expect([
        top.level,
        top.special,
        top.numbered,
        top.index,
      ], equals([1, false, true, 0]));
      top.special = true;
      final child = Section(top);
      expect([
        child.level,
        child.special,
        child.numbered,
        child.index,
      ], equals([2, true, false, 0]));
      final explicit = Section(top, 5);
      expect(explicit.level, equals(5));
      expect(child.document, same(doc));
    });

    test('name aliases title; sections tracks children', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      expect(section.name, isNull);
      expect(section.hasSections, isFalse);
      section << Section(section, 2);
      expect(section.hasSections, isTrue);
      // Non-section children do not count.
      section << Block(section, 'paragraph');
      expect(section.sections, hasLength(1));
    });

    test('appending a section assigns its index', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      final a = Section(section, 2);
      final b = Section(section, 2);
      section << a;
      section << b;
      expect([a.index, b.index], equals([0, 1]));
      expect(section.nextSectionIndex, equals(2));
    });

    test('sectnum chains numerals with delimiters', () {
      final doc = FakeDocument();
      final a = Section(doc, 1, true)..sectname = 'section';
      final b = Section(a, 2, true)..sectname = 'section';
      final c = Section(doc, 1, true)..sectname = 'section';
      doc << a;
      a << b;
      doc << c;
      expect([a.numeral, a.sectnum()], equals(['1', '1.']));
      expect([b.numeral, b.sectnum()], equals(['1', '1.1.']));
      expect([c.numeral, c.sectnum()], equals(['2', '2.']));
      expect(b.sectnum(',', false), equals('1,1'));
      expect(a.sectnum('.', ''), equals('1'));
    });

    test('generateIdFromTitle delegates to the static generator', () {
      final doc = FakeDocument();
      final section = Section(doc, 1);
      // No title means the conversion throws only when a title is set;
      // with no title the `!` on null throws instead (both throw).
      expect(section.generateIdFromTitle, throwsA(anything));
    });

    test('toString shape with and without title', () {
      final doc = FakeDocument();
      final section = Section(doc, 1, true)
        ..title = 'A'
        ..numeral = '1';
      section << Block(section, 'paragraph');
      section << Block(section, 'paragraph');
      expect(
        section.toString(),
        matches(
          RegExp(r'^#Section@\d+ \{level: 1, title: "1\. A", blocks: 2\}$'),
        ),
      );
      final untitled = Section(doc, 1);
      expect(untitled.toString(), isNot(contains('level:')));
    });

    test('xreftext without title returns null', () {
      final doc = FakeDocument();
      expect(Section(doc, 1).xreftext(), isNull);
      expect(Section(doc, 1).xreftext('full'), isNull);
    });
  });

  group('Section.generateId', () {
    test('basic IDs and repeat stability', () {
      final doc = FakeDocument();
      expect(Section.generateId('Foo Bar', doc), equals('_foo_bar'));
      // The catalog is not updated by generation itself.
      expect(Section.generateId('Foo Bar', doc), equals('_foo_bar'));
    });

    test('custom separator and empty prefix', () {
      final doc = FakeDocument(
        attributes: {'idseparator': '-', 'idprefix': ''},
      );
      expect(
        Section.generateId('  Foo..Bar--Baz  ', doc),
        equals('foo-bar-baz'),
      );
    });

    test('multi-character separator truncates and mutates attributes', () {
      final doc = FakeDocument(attributes: {'idseparator': '--'});
      expect(Section.generateId('A B', doc), equals('_a-b'));
      expect(doc.attributes['idseparator'], equals('-'));
    });

    test('empty separator deletes spaces', () {
      final doc = FakeDocument(attributes: {'idseparator': ''});
      expect(Section.generateId('A B', doc), equals('_ab'));
    });

    test('tags and entities are stripped', () {
      final doc = FakeDocument(
        attributes: {'idprefix': 'x', 'idseparator': '_'},
      );
      expect(
        Section.generateId('Tom & Jerry <b>Hi</b>', doc),
        equals('xtom_jerry_hi'),
      );
      expect(Section.generateId('R&D', doc), equals('xrd'));
    });

    test('taken IDs gain a numeric suffix from index 2', () {
      final doc = FakeDocument();
      doc.catalog['refs']!['_foo'] = Object();
      expect(Section.generateId('Foo', doc), equals('_foo_2'));
      doc.catalog['refs']!['_foo_2'] = Object();
      expect(Section.generateId('Foo', doc), equals('_foo_3'));
    });

    test('missing separator attribute falls back to underscore', () {
      final doc = FakeDocument();
      doc.attributes.remove('idseparator');
      expect(Section.generateId('A B', doc), equals('_a_b'));
    });

    test('non-ASCII word characters are kept (parity gate)', () {
      // Ruby `\p{Word}` keeps letters like `ü` (`lib/asciidoctor/rx.rb:263`);
      // Dart `\w` is ASCII-only, so the shared `ccWord` regex is required.
      final doc = FakeDocument();
      expect(Section.generateId('Überschrift', doc), equals('_überschrift'));
    });
  });

  group('List', () {
    test('outline detection and item aliases', () {
      final doc = FakeDocument();
      final ulist = ListBlock(doc, 'ulist');
      final olist = ListBlock(doc, 'olist');
      expect(ulist.isOutline, isTrue);
      expect(olist.isOutline, isTrue);
      expect(ListBlock(doc, 'dlist').isOutline, isFalse);
      expect(ListBlock(doc, 'colist').isOutline, isFalse);
      final item = ListItem(ulist, 'x');
      ulist << item;
      expect(ulist.items, same(ulist.blocks));
      expect(ulist.content(), same(ulist.blocks));
      expect(ulist.hasItems, isTrue);
      expect(ListBlock(doc, 'ulist').hasItems, isFalse);
    });

    test('convert passes through; colist advances callouts', () {
      final doc = FakeDocument();
      final ulist = ListBlock(doc, 'ulist');
      expect(ulist.convert(), equals('<ulist>'));
      expect(doc.playbacked, hasLength(1));

      final colist = ListBlock(doc, 'colist');
      expect(doc.callouts.register(1), equals('CO1-1'));
      expect(doc.callouts.calloutIds(1), equals('CO1-1'));
      final result = colist.convert();
      expect(result, equals('<colist>'));
      // The list advanced: no more ids on the new list.
      expect(doc.callouts.readNextId(), isNull);
    });

    test('toString shape', () {
      final doc = FakeDocument();
      final list = ListBlock(doc, 'ulist');
      list << ListItem(list, 'x');
      expect(
        list.toString(),
        matches(
          RegExp(r'^#ListBlock@\d+ \{context: :ulist, style: nil, items: 1\}$'),
        ),
      );
    });
  });

  group('ListItem', () {
    test('constructor takes level and copies default subs', () {
      final doc = FakeDocument();
      final list = (ListBlock(doc, 'ulist'))..level = 2;
      final item = ListItem(list, 'text');
      expect(item.level, equals(2));
      expect(item.subs, equals(normalSubs));
      expect(item.subs, isNot(same(normalSubs)));
      expect(item.context, equals('list_item'));
      expect(item.list, same(list));
      expect(item.marker, isNull);
      item.marker = '*';
      expect(item.marker, equals('*'));
    });

    test('hasText and text', () {
      final doc = Document(<String>[]);
      final list = ListBlock(doc, 'ulist');
      expect(ListItem(list).hasText, isFalse);
      expect(ListItem(list, '').hasText, isFalse);
      final item = ListItem(list, 'a');
      expect(item.hasText, isTrue);
      expect(ListItem(list).text, isNull);
      // Default subs perform real work...
      expect(item.text, equals('a'));
      // ...but with vacuous subs the raw text comes back.
      item.subs = [];
      expect(item.text, equals('a'));
      item.text = 'b';
      expect(item.text, equals('b'));
    });

    test('simple and compound content', () {
      final doc = FakeDocument();
      final list = ListBlock(doc, 'ulist');
      final bare = ListItem(list, 'x');
      expect(bare.isSimple, isTrue);
      expect(bare.isCompound, isFalse);
      final nested = ListItem(list, 'x');
      nested << ListBlock(nested, 'olist');
      expect(nested.isSimple, isTrue);
      final complex = ListItem(list, 'x');
      complex << Block(complex, 'paragraph');
      expect(complex.isSimple, isFalse);
      expect(complex.isCompound, isTrue);
    });

    test('foldFirst folds the first block into the text', () {
      final doc = FakeDocument();
      final list = ListBlock(doc, 'ulist');
      final folded = (ListItem(list))..subs = [];
      folded << Block(folded, 'paragraph', source: 'cont');
      folded.foldFirst();
      expect(folded.text, equals('cont'));
      expect(folded.blocks, isEmpty);
      final prefixed = (ListItem(list, 'item'))..subs = [];
      prefixed << Block(prefixed, 'paragraph', source: 'cont');
      prefixed.foldFirst();
      expect(prefixed.text, equals('item\ncont'));
    });

    test('toString shape', () {
      final doc = FakeDocument();
      final list = ListBlock(doc, 'ulist');
      final item = ListItem(list, 'x');
      expect(
        item.toString(),
        matches(
          RegExp(
            r'^#ListItem@\d+ \{list_context: :ulist, text: "x", blocks: 0\}$',
          ),
        ),
      );
    });
  });

  group('Table', () {
    test('constructor resolves table widths', () {
      final doc = FakeDocument();
      final table = Table(doc, <String, Object?>{});
      expect(table.context, equals('table'));
      expect(table.attributes['tablepcwidth'], equals(100));
      expect(table.rows.body, isEmpty);
      expect(table.columns, isEmpty);
      expect(table.hasHeaderOption, equals(false));
      (<String, int>{
        'abc': 100,
        '0%': 0,
        '50': 50,
        '50%': 50,
        '0': 0,
        '100': 100,
        '101': 100,
        '-5': 100,
      }).forEach((width, expected) {
        expect(
          Table(doc, {'width': width}).attributes['tablepcwidth'],
          equals(expected),
          reason: 'width $width',
        );
      });
      expect(Table(doc, {'width': 50}).attributes['tablepcwidth'], equals(50));
    });

    test('absolute widths follow the pagewidth attribute', () {
      final doc = FakeDocument(attributes: {'pagewidth': 800});
      final table = Table(doc, {'width': '50%'});
      expect(table.attributes['tableabswidth'], equals(400));
      table.createColumns([
        {'width': 1},
        {'width': 1},
      ]);
      expect(
        table.columns.map(
          (c) => [c.attributes['colpcwidth'], c.attributes['colabswidth']],
        ),
        equals([
          [50, 200],
          [50, 200],
        ]),
      );
    });

    test('rotate option sets landscape orientation', () {
      final doc = FakeDocument();
      // An empty string is truthy in Ruby, so it enables the option.
      expect(
        Table(doc, {'rotate-option': ''}).attributes['orientation'],
        equals('landscape'),
      );
      expect(Table(doc, <String, Object>{}).attributes['orientation'], isNull);
    });

    test('headerRow gates on body emptiness', () {
      final doc = FakeDocument();
      final table = Table(doc, <String, Object?>{})
        ..createColumns([
          {'width': 1},
        ]);
      expect(table.headerRow, equals(false));
      table.hasHeaderOption = true;
      expect(table.headerRow, equals(true));
      table.rows.body.add([Cell(table.columns[0], 'a', {})]);
      expect(table.headerRow, equals(false));
      table.rows.body.clear();
      table.hasHeaderOption = 'implicit';
      expect(table.headerRow, equals('implicit'));
    });

    test('createColumns assigns relative widths', () {
      final doc = FakeDocument();
      final table = Table(doc, <String, Object?>{});
      final colspecs = [
        <String, Object?>{'width': 1},
        <String, Object?>{'width': 2},
        <String, Object?>{'width': 1},
      ];
      table.createColumns(colspecs);
      expect(table.attributes['colcount'], equals(3));
      expect(
        table.columns.map((c) => c.attributes['colpcwidth']),
        equals([25, 50, 25]),
      );
      // Column numbers resolve into the caller specs (as in Ruby).
      expect(colspecs[0]['colnumber'], equals(1));
      expect(colspecs[2]['colnumber'], equals(3));
    });

    test('autowidth columns split the remainder; balance to final', () {
      final doc = FakeDocument();
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': -1},
          {'width': -1},
          {'width': -1},
        ]);
      expect(
        table.columns.map(
          (c) => [c.attributes['width'], c.attributes['colpcwidth']],
        ),
        equals([
          [33.3333, 33.3333],
          [33.3333, 33.3333],
          [33.3333, 33.3334],
        ]),
      );
    });

    test('autowidth over 100 warns and zeroes autowidth columns', () {
      final doc = FakeDocument();
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 60},
          {'width': 60},
          {'width': -1},
        ]);
      expect(
        table.columns.map(
          (c) => [c.attributes['width'], c.attributes['colpcwidth']],
        ),
        equals([
          [60, 50],
          [60, 50],
          [0, 0],
        ]),
      );
      expect(
        testLogger.warns.single,
        contains('total column width must not exceed 100%'),
      );
    });

    test('zero widths fall back to an equal split', () {
      final doc = FakeDocument();
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 0},
          {'width': 0},
        ]);
      expect(
        table.columns.map((c) => c.attributes['colpcwidth']),
        equals([50, 50]),
      );
      final single = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1},
        ]);
      expect(single.columns.single.attributes['colpcwidth'], equals(100));
    });

    test('partitionHeaderFooter splits head, body and foot', () {
      FakeDocument makeDoc() => FakeDocument();
      Table makeTable(FakeDocument doc, int cols) {
        final table = (Table(doc, <String, Object?>{}))
          ..createColumns(
            List.generate(cols, (_) => <String, Object?>{'width': 1}),
          );
        return table;
      }

      final doc = makeDoc();
      final table = makeTable(doc, 2);
      for (final text in ['h1|h2', 'a|b', 'c|d']) {
        final parts = text.split('|');
        table.rows.body.add([
          Cell(table.columns[0], parts[0], {}),
          Cell(table.columns[1], parts[1], {}),
        ]);
      }
      table
        ..hasHeaderOption = true
        ..partitionHeaderFooter({});
      expect(table.attributes['rowcount'], equals(3));
      expect(table.rows.head, hasLength(1));
      expect(table.rows.body, hasLength(2));
      expect(table.rows.foot, isEmpty);
      expect(
        table.rows.head.single.map((c) => c.source()),
        equals(['h1', 'h2']),
      );

      final doc2 = makeDoc();
      final withFoot = makeTable(doc2, 2);
      for (final text in ['h1|h2', 'a|b', 'f1|f2']) {
        final parts = text.split('|');
        withFoot.rows.body.add([
          Cell(withFoot.columns[0], parts[0], {}),
          Cell(withFoot.columns[1], parts[1], {}),
        ]);
      }
      withFoot
        ..hasHeaderOption = true
        ..partitionHeaderFooter({'footer-option': ''});
      expect(withFoot.rows.head, hasLength(1));
      expect(withFoot.rows.body, hasLength(1));
      expect(
        withFoot.rows.foot.single.map((c) => c.source()),
        equals(['f1', 'f2']),
      );
    });

    test('partitionHeaderFooter with nil header option reinitializes', () {
      final doc = FakeDocument();
      // Cells built while the header is implicit defer literal handling.
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1},
        ])
        ..hasHeaderOption = 'implicit';
      final cell = Cell(table.columns.single, '  x  \n\n', {
        'style': 'literal',
      });
      expect(cell.contentModel, equals('simple'));
      table.rows.body.add([cell]);
      table
        ..hasHeaderOption = null
        ..partitionHeaderFooter({});
      expect(table.hasHeaderOption, equals(false));
      expect(table.attributes['rowcount'], equals(1));
      // The row stays in the body, rebuilt as a literal cell.
      final rebuilt = table.rows.body.single.single;
      expect(rebuilt, isNot(same(cell)));
      expect(rebuilt.contentModel, equals('verbatim'));
      expect(rebuilt.source(), equals('  x'));
      expect(rebuilt.subs, same(basicSubs));
    });
  });

  group('TableRows', () {
    TableRows makeRows() {
      final doc = FakeDocument();
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1},
        ]);
      final rows = TableRows();
      rows.head.add([Cell(table.columns.single, 'h', {})]);
      rows.body.add([Cell(table.columns.single, 'b', {})]);
      return rows;
    }

    test('index operator, bySection and toMap', () {
      final rows = makeRows();
      expect(rows['head'], same(rows.head));
      expect(rows['body'], same(rows.body));
      expect(rows['foot'], same(rows.foot));
      expect(() => rows['bogus'], throwsArgumentError);
      expect(rows.bySection.map((e) => e.$1), equals(['head', 'body', 'foot']));
      expect(rows.bySection[1].$2, same(rows.body));
      expect(rows.toMap().keys, equals(['head', 'body', 'foot']));
      expect(rows.toMap()['body'], same(rows.body));
    });
  });

  group('Column', () {
    test('constructor resolves defaults into caller attributes', () {
      final doc = FakeDocument();
      final table = Table(doc, <String, Object?>{});
      final column = Column(table, 0);
      expect(column.table, same(table));
      expect(column.context, equals('table_column'));
      expect(column.style, isNull);
      expect(
        column.attributes,
        equals({'colnumber': 1, 'width': 1, 'halign': 'left', 'valign': 'top'}),
      );
      expect(column.isBlock, isFalse);
      expect(column.isInline, isFalse);
      // Explicit values survive; the caller map gains the colnumber.
      final attrs = <String, Object?>{
        'style': 'strong',
        'width': 2,
        'halign': 'center',
      };
      final styled = Column(table, 1, attrs);
      expect(styled.style, equals('strong'));
      expect(styled.attributes['width'], equals(2));
      expect(styled.attributes['halign'], equals('center'));
      expect(styled.attributes['valign'], equals('top'));
      expect(attrs['colnumber'], equals(2));
    });

    test('assignWidth resolves percentage and absolute widths', () {
      final doc = FakeDocument();
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1},
          {'width': 3},
        ]);
      expect(
        table.columns.map((c) => c.attributes['colpcwidth']),
        equals([25, 75]),
      );
      // Whole values become ints; fractional values stay doubles.
      final thirds = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1},
          {'width': 1},
          {'width': 1},
        ]);
      expect(
        thirds.columns.map((c) => c.attributes['colpcwidth']),
        equals([33.3333, 33.3333, 33.3334]),
      );
      expect(thirds.columns[0].attributes['colpcwidth'], isA<double>());
      expect(table.columns[0].attributes['colpcwidth'], isA<int>());
    });
  });

  group('Cell', () {
    Table makeTable(AbstractBlock doc) {
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1},
        ]);
      return table;
    }

    test('normal cells strip text and lift spans', () {
      final doc = FakeDocument();
      final table = makeTable(doc);
      final col = table.columns.single;
      final attrs = <String, Object?>{
        'colspan': 2,
        'rowspan': 3,
        'halign': 'center',
      };
      final cell = Cell(col, ' x\ny\n\nz ', attrs);
      expect(cell.source(), equals('x\ny\n\nz'));
      expect(cell.colspan, equals(2));
      expect(cell.rowspan, equals(3));
      expect(cell.contentModel, equals('simple'));
      expect(cell.subs, same(normalSubs));
      expect(cell.column, same(col));
      // Spans are removed from the attributes; the rest merge in.
      expect(attrs.containsKey('colspan'), isFalse);
      expect(attrs.containsKey('rowspan'), isFalse);
      expect(cell.attributes['halign'], equals('center'));
      // Column attributes are inherited, then overridden.
      expect(cell.attributes['colnumber'], equals(1));
      // Null text becomes the empty string (AsciidoctorJ convention).
      expect(Cell(col, null, {}).source(), equals(''));
    });

    test('empty attributes leave spans unset', () {
      final doc = FakeDocument();
      final col = makeTable(doc).columns.single;
      final cell = Cell(col, 'a', {});
      expect(cell.colspan, isNull);
      expect(cell.rowspan, isNull);
      expect(cell.style, isNull);
    });

    test('styles resolve from column, then cell attributes', () {
      final doc = FakeDocument();
      final table = (Table(doc, <String, Object?>{}))
        ..createColumns([
          {'width': 1, 'style': 'strong'},
        ]);
      final col = table.columns.single;
      expect(Cell(col, 'a', {}).style, equals('strong'));
      expect(Cell(col, 'a', {'style': 'emphasis'}).style, equals('emphasis'));
      // In the header row the cell style is ignored.
      table.hasHeaderOption = true;
      expect(Cell(col, 'a', {'style': 'emphasis'}).style, isNull);
    });

    test('header cells defer anchor cataloging until reinitialized', () {
      final doc = Document(<String>[]);
      final table = (makeTable(doc))..hasHeaderOption = true;
      // Would catalog (parser) if done eagerly; header cells defer it.
      final cell = Cell(table.columns.single, '[[hx]] H', {}, {
        'cursor': FakeCursor('t.adoc', 1),
      });
      final refs = doc.catalog['refs']! as Map<String, Object?>;
      expect(refs, isNot(contains('hx')));
      // Plain cells reinitialize to themselves.
      final plain = Cell(table.columns.single, 'H', {});
      expect(plain.reinitialize(true), same(plain));
      // The anchored cell catalogs on reinitialization.
      cell.reinitialize(true);
      expect(refs, contains('hx'));
    });

    test('implicit header with literal style rebuilds on reinitialize', () {
      final doc = FakeDocument();
      final table = (makeTable(doc))..hasHeaderOption = 'implicit';
      final cell = Cell(table.columns.single, '  lit  \n\n', {
        'style': 'literal',
      });
      expect(cell.contentModel, equals('simple'));
      table.hasHeaderOption = false;
      final rebuilt = cell.reinitialize(false);
      expect(rebuilt, isNot(same(cell)));
      expect(rebuilt.contentModel, equals('verbatim'));
      expect(rebuilt.source(), equals('  lit'));
      expect(rebuilt.subs, same(basicSubs));
      // Explicit header rows just clear the deferred arguments.
      table.hasHeaderOption = 'implicit';
      final cell2 = Cell(table.columns.single, 'x', {'style': 'literal'});
      expect(cell2.reinitialize(true), same(cell2));
    });

    test('literal cells rstrip and drop leading blank lines', () {
      final doc = FakeDocument();
      final col = makeTable(doc).columns.single;
      final cell = Cell(col, '  lit\n  lines  \n\n', {'style': 'literal'});
      expect(cell.source(), equals('  lit\n  lines'));
      expect(cell.contentModel, equals('verbatim'));
      expect(cell.subs, same(basicSubs));
      final blanky = Cell(col, '\n\nlit', {'style': 'literal'});
      expect(blanky.source(), equals('lit'));
    });

    test('lines splits without trailing empties', () {
      final doc = FakeDocument();
      final col = makeTable(doc).columns.single;
      expect(Cell(col, 'a', {}).lines(), equals(['a']));
      expect(Cell(col, 'a\nb\n', {}).lines(), equals(['a', 'b']));
    });

    test('content of an empty cell is an empty list', () {
      final doc = FakeDocument();
      final col = makeTable(doc).columns.single;
      expect(Cell(col, '', {}).content(), equals([]));
    });

    test('content styles paragraphs through the converter', () {
      final doc = FakeDocument();
      final col = makeTable(doc).columns.single;
      final multi = (Cell(col, 'p1\n\np2', {'style': 'strong'}))..subs = [];
      expect(
        multi.content(),
        equals(['<inline_quoted:strong=p1>', '<inline_quoted:strong=p2>']),
      );
      final single = (Cell(col, 'x', {'style': 'strong'}))..subs = [];
      expect(single.content(), equals(['<inline_quoted:strong=x>']));
      final header = (Cell(col, 'x', {'style': 'header'}))..subs = [];
      expect(header.content(), equals(['x']));
      final plain = (Cell(col, 'x', {}))..subs = [];
      expect(plain.content(), equals(['x']));
    });

    test('cell text applies subs; vacuous subs pass through', () {
      final doc = Document(<String>[]);
      final col = makeTable(doc).columns.single;
      final cell = Cell(col, 'a', {});
      expect(cell.text, equals('a'));
      cell.subs = [];
      expect(cell.text, equals('a'));
      cell.text = 'b';
      expect(cell.text, equals('b'));
    });

    test('source locations are captured when the sourcemap is on', () {
      final doc = FakeDocument()..sourcemap = true;
      final col = makeTable(doc).columns.single;
      final cell = Cell(col, 'a', {}, {'cursor': FakeCursor('t.adoc', 3)});
      expect(cell.file, equals('t.adoc'));
      expect(cell.lineno, equals(3));
    });

    test('null column and asciidoc style are out of scope', () {
      final doc = FakeDocument();
      final table = makeTable(doc);
      final col = table.columns.single;
      // Ruby raises NoMethodError here (verified); the port throws too.
      expect(() => Cell(null, 't'), throwsA(anything));
      expect(() => Cell(null, 't', null), throwsA(anything));
      // AsciiDoc cells build a nested document, which needs a real
      // Document; with the FakeDocument test double the cast fails.
      // (Real-document coverage: the `asciidoc cell` test below.)
      expect(() => Cell(col, 't', {'style': 'asciidoc'}), throwsA(anything));
      final asciidocCol = Column(table, 1, {'style': 'asciidoc'});
      expect(() => Cell(asciidocCol, 't', null), throwsA(anything));
      // A null-attributes cell on a plain column is a normal cell.
      expect(Cell(col, 't', null).contentModel, equals('simple'));
    });

    test('asciidoc cell builds a nested document', () {
      // Unit-level cover for e2e #115 (xref from asciidoc table cell):
      // Ruby parses the cell text into an inner document eagerly.
      final doc = load('|===\na|See *this*\n|===\n');
      final table = doc.blocks.single as Table;
      final cell = table.rows.body.single.single;
      expect(cell.style, equals('asciidoc'));
      expect(cell.innerDocument, isA<Document>());
      expect(cell.innerDocument!.blocks, hasLength(1));
      expect(cell.content()! as String, contains('<strong>this</strong>'));
    });

    test('toString carries text, spans and attributes', () {
      final doc = FakeDocument();
      final col = makeTable(doc).columns.single;
      final cell = Cell(col, 'a', {});
      final rendered = cell.toString();
      expect(rendered, contains('[text: a, colspan: 1, rowspan: 1,'));
      expect(rendered, contains('colnumber: 1'));
    });
  });

  group('TableParserContext', () {
    (FakeDocument, Table, FakeReader) makeParts({int cols = 0}) {
      final doc = FakeDocument();
      final table = Table(doc, <String, Object?>{});
      if (cols > 0) {
        table.createColumns(
          List.generate(cols, (_) => <String, Object?>{'width': 1}),
        );
      }
      return (doc, table, FakeReader());
    }

    test('defaults: psv, pipe delimiter, unset colcount', () {
      final (_, table, reader) = makeParts();
      final pc = TableParserContext(reader, table);
      expect(pc.format, equals('psv'));
      expect(pc.delimiter, equals('|'));
      expect(pc.colcount, equals(-1));
      expect(pc.buffer, equals(''));
      expect(pc.table, same(table));
      expect(reader.marks, equals(1));
      // Faithful quirk: delimiterRe is always null in Ruby (verified).
      expect(pc.delimiterRe, isNull);
    });

    test('formats: csv, dsv, tsv alias and nested psv', () {
      final (_, table, reader) = makeParts();
      expect(
        TableParserContext(reader, table, {'format': 'csv'}).format,
        equals('csv'),
      );
      expect(
        TableParserContext(reader, table, {'format': 'csv'}).delimiter,
        equals(','),
      );
      expect(
        TableParserContext(reader, table, {'format': 'dsv'}).delimiter,
        equals(':'),
      );
      final tsv = TableParserContext(reader, table, {'format': 'tsv'});
      expect(tsv.format, equals('csv'));
      expect(tsv.delimiter, equals('\t'));
      final nestedDoc = FakeDocument()..isNested = true;
      final nestedTable = Table(nestedDoc, <String, Object?>{});
      final nested = TableParserContext(FakeReader(), nestedTable, {
        'format': 'psv',
      });
      expect(nested.format, equals('psv'));
      expect(nested.delimiter, equals('!'));
      // The default (no format) also honors nesting.
      expect(
        TableParserContext(FakeReader(), nestedTable).delimiter,
        equals('!'),
      );
    });

    test('illegal format logs an error and falls back to psv', () {
      final (_, table, reader) = makeParts();
      final pc = TableParserContext(reader, table, {'format': 'bogus'});
      expect(pc.format, equals('psv'));
      expect(pc.delimiter, equals('|'));
      expect(testLogger.errors.single, contains('illegal table format: bogus'));
    });

    test('separators: empty, tab escape and custom values', () {
      final (_, table, reader) = makeParts();
      final csv = TableParserContext(reader, table, {
        'format': 'csv',
        'separator': ';',
      });
      expect(csv.delimiter, equals(';'));
      expect(csv.matchDelimiter('a;b')?.group(0), equals(';'));
      // An empty separator restores the format default.
      final empty = TableParserContext(reader, table, {
        'format': 'csv',
        'separator': '',
      });
      expect(empty.delimiter, equals(','));
      // A literal backslash-t (not a tab) selects the tsv delimiter.
      final tabbed = TableParserContext(reader, table, {'separator': r'\t'});
      expect(tabbed.delimiter, equals('\t'));
      // Custom separators are regex-escaped: '.' matches a literal dot.
      final dotted = TableParserContext(reader, table, {'separator': '.'});
      expect(dotted.matchDelimiter('a.b'), isNotNull);
      expect(dotted.matchDelimiter('axb'), isNull);
    });

    test('delimiter matching and skipping', () {
      final (_, table, reader) = makeParts();
      final pc = TableParserContext(reader, table);
      expect(pc.startsWithDelimiter('|a'), isTrue);
      expect(pc.startsWithDelimiter('a|'), isFalse);
      final match = pc.matchDelimiter('a|b');
      expect(match?.group(0), equals('|'));
      expect(match?.start, equals(1));
      expect(pc.matchDelimiter('ab'), isNull);
      pc
        ..buffer = 'x'
        ..skipPastDelimiter('pre');
      expect(pc.buffer, equals('xpre|'));
      pc
        ..buffer = 'x'
        ..skipPastEscapedDelimiter(r'pre\');
      expect(pc.buffer, equals('xpre|'));
      pc
        ..buffer = 'x'
        ..skipPastEscapedDelimiter('a\r\n');
      expect(pc.buffer, equals('xa|'));
    });

    test('bufferHasUnclosedQuotes', () {
      final (_, table, reader) = makeParts();
      final pc = (TableParserContext(reader, table))..buffer = '"ab';
      expect(pc.bufferHasUnclosedQuotes(), isTrue);
      pc.buffer = '"ab"';
      expect(pc.bufferHasUnclosedQuotes(), isFalse);
      pc.buffer = '"';
      expect(pc.bufferHasUnclosedQuotes(), isTrue);
      expect(pc.bufferHasUnclosedQuotes('cd"'), isFalse);
      pc.buffer = '';
      expect(pc.bufferHasUnclosedQuotes('"a'), isTrue);
      expect(pc.bufferHasUnclosedQuotes('a'), isFalse);
    });

    test('cellspec stack is FIFO with empty default', () {
      final (_, table, reader) = makeParts();
      final pc = TableParserContext(reader, table);
      expect(pc.takeCellspect(), isNull);
      pc
        ..pushCellspect({'a': 1})
        ..pushCellspect();
      expect(pc.takeCellspect(), equals({'a': 1}));
      expect(pc.takeCellspect(), equals({}));
      expect(pc.takeCellspect(), isNull);
    });

    test('cell open state and closeOpenCell', () {
      final (_, table, reader) = makeParts();
      final pc = TableParserContext(reader, table);
      expect(pc.isCellOpen, isFalse);
      expect(pc.isCellClosed, isTrue);
      pc.keepCellOpen();
      expect(pc.isCellOpen, isTrue);
      pc.markCellClosed();
      expect(pc.isCellClosed, isTrue);
      // closeOpenCell closes an open cell and advances the line number.
      pc
        ..pushCellspect({})
        ..buffer = 'x'
        ..keepCellOpen()
        ..closeOpenCell({'b': 2});
      expect(pc.isCellClosed, isTrue);
      expect(pc.takeCellspect(), equals({'b': 2}));
      expect(table.rows.body.single.single.source(), equals('x'));
    });

    test('closeCell runs the psv flow and closes rows', () {
      final (_, table, reader) = makeParts(cols: 2);
      final pc = TableParserContext(reader, table);
      expect(pc.colcount, equals(2));
      pc
        ..pushCellspect({})
        ..buffer = 'a'
        ..closeCell();
      expect(table.rows.body, isEmpty);
      pc
        ..pushCellspect({})
        ..buffer = 'b'
        ..closeCell();
      expect(table.rows.body, hasLength(1));
      expect(table.rows.body.single.map((c) => c.source()), equals(['a', 'b']));
      expect(reader.marks, equals(3));
    });

    test('closeCell without colcount closes rows at end of line', () {
      // No predefined columns: colcount starts at -1 and rows close on
      // end-of-line (or once a second line has been seen).
      final (_, table, reader) = makeParts();
      final pc = (TableParserContext(reader, table))
        ..pushCellspect({})
        ..buffer = 'a'
        ..closeCell();
      expect(table.rows.body, isEmpty);
      expect(table.columns, hasLength(1));
      pc
        ..pushCellspect({})
        ..buffer = 'b'
        ..closeCell(true);
      expect(table.rows.body.single.map((c) => c.source()), equals(['a', 'b']));
      expect(table.columns, hasLength(2));
      expect(pc.colcount, equals(2));
    });

    test('closeOpenCell advances lines so later rows close implicitly', () {
      final (_, table, _) = makeParts();
      (TableParserContext(FakeReader(), table))
        ..closeOpenCell()
        ..closeOpenCell()
        ..buffer = 'a'
        ..closeCell();
      expect(table.rows.body, hasLength(1));
    });

    test('closeCell honors repeatcol and colspan', () {
      final (_, table, reader) = makeParts();
      (TableParserContext(reader, table))
        ..pushCellspect({'repeatcol': 2})
        ..buffer = 'x'
        ..closeCell(true);
      expect(table.rows.body.single, hasLength(2));
      expect(table.columns, hasLength(2));

      final (_, table2, reader2) = makeParts();
      (TableParserContext(reader2, table2))
        ..pushCellspect({'colspan': 2})
        ..buffer = 'y'
        ..closeCell(true);
      expect(table2.columns, hasLength(2));
      expect(table2.rows.body.single.single.colspan, equals(2));
    });

    test('closeCell runs the csv flow with quote handling', () {
      final (_, table, reader) = makeParts();
      final pc = TableParserContext(reader, table, {'format': 'csv'});
      for (final text in ['a', '"b ""q"" c"', 'd']) {
        pc
          ..buffer = text
          ..closeCell(true);
      }
      expect(table.rows.body, hasLength(3));
      expect(
        table.rows.body.map((row) => row.single.source()),
        equals(['a', 'b "q" c', 'd']),
      );
      // A lone quote logs an error and yields an empty cell.
      pc
        ..buffer = '"'
        ..closeCell(true);
      expect(table.rows.body.last.single.source(), equals(''));
      expect(testLogger.errors.single, contains('unclosed quote in CSV data'));
    });

    test('rowspans count towards later rows', () {
      final (_, table, _) = makeParts(cols: 2);
      final pc = (TableParserContext(FakeReader(), table))
        ..pushCellspect({'rowspan': 2})
        ..buffer = 'a'
        ..closeCell()
        ..pushCellspect({})
        ..buffer = 'b'
        ..closeCell();
      expect(table.rows.body, hasLength(1));
      // The second row needs a single cell: the rowspan fills the gap.
      pc
        ..pushCellspect({})
        ..buffer = 'c'
        ..closeCell();
      expect(table.rows.body, hasLength(2));
      expect(table.rows.body[1], hasLength(1));
    });

    test('overrunning cells are dropped with an error', () {
      final (_, table, _) = makeParts(cols: 1);
      (TableParserContext(FakeReader(), table))
        ..pushCellspect({'colspan': 2})
        ..buffer = 'wide'
        ..closeCell();
      expect(table.rows.body, isEmpty);
      expect(testLogger.errors.single, contains('dropping cell'));
    });

    test('missing leading separator recovers with an error', () {
      final (_, table, _) = makeParts();
      (TableParserContext(FakeReader(), table))
        ..buffer = 'a'
        ..closeCell(true);
      expect(
        testLogger.errors.single,
        contains('table missing leading separator'),
      );
      expect(table.rows.body.single.single.source(), equals('a'));
    });

    test('closeTable reports incomplete rows only', () {
      final (_, table, _) = makeParts();
      TableParserContext(FakeReader(), table).closeTable();
      expect(testLogger.errors, isEmpty);
      final (_, table2, _) = makeParts();
      (TableParserContext(FakeReader(), table2))
        ..pushCellspect({})
        ..buffer = 'a'
        ..closeCell()
        ..closeTable();
      expect(testLogger.errors.single, contains('incomplete row'));
    });
  });

  group('substitution seams', () {
    test('converting titles and texts applies substitutions', () {
      final doc = Document(<String>[]);
      final block = Block(doc, 'paragraph')..title = 'T';
      expect(block.title, equals('T'));
      expect(ListItem(ListBlock(doc, 'ulist'), 'x').text, equals('x'));
      final col = Column(Table(doc, <String, Object?>{}), 0);
      expect(Cell(col, 'x', {}).text, equals('x'));
      final withRef = Block(doc, 'paragraph', attributes: {'reftext': 'R'});
      expect(withRef.reftext, equals('R'));
      final withAlt = Block(doc, 'image', attributes: {'alt': 'A'});
      expect(withAlt.alt, equals('A'));
      expect(block.xreftext('full'), equals('T'));
    });

    test('anchor cataloging uses parser.dart', () {
      final doc = Document(<String>[]);
      final table = Table(doc, <String, Object?>{});
      final col = Column(table, 0);
      Cell(col, '[[id]] text', {});
      Parser.catalogInlineAnchor('id2', null, table, null, doc);
      final refs = doc.catalog['refs']! as Map<String, Object?>;
      expect(refs, contains('id'));
      expect(refs, contains('id2'));
    });
  });
}
