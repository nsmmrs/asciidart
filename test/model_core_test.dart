/// Direct behavioral tests for the document-model core port.
///
/// Covers `abstract_node.dart`, `abstract_block.dart`, `block.dart` and
/// `inline.dart`. The Ruby suite has no unit tests for these classes, so
/// every expectation below was verified against the Ruby implementation via
/// `ruby -Ilib` probes (see the commit message for the observed outputs).
///
/// Substitution-dependent paths (`title` with text, `alt` with text,
/// `reftext` with text, styled `xreftext`, `content` with non-empty subs)
/// throw [UnimplementedError] until the substitutors wave lands; those
/// tests pin the seam so the wave knows what to unlock. Vacuous
/// substitutions (empty text, `null`/empty subs) already pass through, as
/// in Ruby.
library;

import 'dart:convert' show utf8;
import 'dart:io' show Directory, File;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/callouts.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/substitutors.dart';
import 'package:test/test.dart';

/// Records conversions for assertions.
class FakeConverter implements NodeConverter {
  /// Nodes passed to [convert], in order.
  final List<AbstractNode> converted = <AbstractNode>[];

  /// Computes the conversion result (default emits a `<nodeName>` marker).
  Object? Function(AbstractNode node)? handler;

  @override
  Object? convert(AbstractNode node) {
    converted.add(node);
    return handler?.call(node) ?? '<${node.nodeName}>';
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

/// Stands in for `Document` (document wave) in these tests.
class FakeDocument extends AbstractBlock implements NodeDocument {
  // ignore: use_super_parameters, reason: explicit super hardcodes the document context.
  new({
    Map<String, Object?>? attributes,
    this.safe = SafeMode.safe,
    String? baseDir,
    PathResolver? pathResolver,
    this.compatMode = false,
  }) : baseDir = baseDir ?? Directory.current.path,
       pathResolver = pathResolver ?? PathResolver(),
       super(null, 'document', attributes: attributes);

  @override
  int safe;

  @override
  final String baseDir;

  @override
  final PathResolver pathResolver;

  @override
  bool compatMode;

  @override
  final FakeConverter converter = FakeConverter();

  @override
  final Map<String, Object?> catalog = <String, Object?>{
    'refs': <String, Object?>{},
  };

  @override
  final Callouts callouts = Callouts();

  @override
  bool nested() => false;

  @override
  bool sourcemap = false;

  /// Counters by name (mirrors `Document#counter` storage).
  final Map<String, Object?> counters = <String, Object?>{};

  /// Counter stores as `(name, value, block)` records.
  ///
  /// Mirrors `increment_and_store_counter`, which stashes an attribute
  /// entry for later playback rather than a plain block attribute (Ruby
  /// leaves `block.attributes['example-number']` unset).
  final List<({String name, Object? value, AbstractBlock block})>
  storedCounters = <({String name, Object? value, AbstractBlock block})>[];

  /// Attribute maps passed to [playbackAttributes], in order.
  final List<Map<String, Object?>> playedBack = <Map<String, Object?>>[];

  @override
  Object? counter(String name, [Object? seed]) {
    final Object? next;
    if (counters.containsKey(name)) {
      next = Helpers.nextVal(counters[name]!);
    } else if (seed != null) {
      next = seed is String && int.tryParse(seed) != null
          ? int.parse(seed)
          : seed;
    } else {
      next = 1;
    }
    counters[name] = next;
    attributes[name] = next;
    return next;
  }

  @override
  Object? incrementAndStoreCounter(String counterName, AbstractBlock block) {
    final value = counter(counterName);
    storedCounters.add((name: counterName, value: value, block: block));
    return value;
  }

  @override
  void playbackAttributes(Map<String, Object?> blockAttributes) {
    playedBack.add(blockAttributes);
  }
}

/// Stands in for `Section` (section wave) in these tests.
class FakeSection extends AbstractBlock implements NodeSection {
  // ignore: use_super_parameters, reason: explicit super hardcodes the section context.
  new(
    AbstractBlock? parent, {
    Map<String, Object?>? attributes,
    this.numbered = false,
    this.sectname,
  }) : super(parent, 'section', attributes: attributes);

  @override
  int index = 0;

  @override
  Object? numbered;

  @override
  String? sectname;
}

/// Stands in for the reader cursor (reader wave) in these tests.
class FakeSourceLocation implements NodeSourceLocation {
  new(this.file, this.lineno);

  @override
  final String? file;

  @override
  final int? lineno;
}

/// A block with canned URI responses for [AbstractNode.fetchUri].
class UriBlock extends Block {
  new(
    super.parent,
    super.context, {
    super.attributes,
    this.response,
    this.fetchError,
  });

  /// The canned fetch response.
  ({List<int> body, String? contentType})? response;

  /// An error [fetchUri] throws instead of responding.
  Exception? fetchError;

  /// URIs passed to [fetchUri], in order.
  final List<String> fetchedUris = <String>[];

  @override
  ({List<int> body, String? contentType}) fetchUri(String uri) {
    fetchedUris.add(uri);
    final error = fetchError;
    if (error != null) throw error;
    return response!;
  }
}

void main() {
  late FakeLogger testLogger;
  late NodeLogger savedLogger;
  late Directory fixtureDir;

  setUp(() {
    savedLogger = AbstractNode.currentLogger;
    testLogger = FakeLogger();
    AbstractNode.currentLogger = testLogger;
    fixtureDir = Directory.systemTemp.createTempSync('model_core');
    Directory('${fixtureDir.path}/img').createSync();
    File('${fixtureDir.path}/img/a.png')
        .writeAsBytesSync(utf8.encode('PNGDATA'));
    File('${fixtureDir.path}/img/empty.txt').writeAsStringSync('');
    File('${fixtureDir.path}/norm.txt').writeAsStringSync('line1  \nline2\n');
  });

  tearDown(() {
    AbstractNode.currentLogger = savedLogger;
    fixtureDir.deleteSync(recursive: true);
  });

  FakeDocument makeDoc({
    Map<String, Object?>? attributes,
    int safe = SafeMode.safe,
  }) => FakeDocument(
    attributes: attributes,
    safe: safe,
    baseDir: fixtureDir.path,
  );

  group('construction', () {
    test('document node refers to itself with no parent', () {
      final doc = makeDoc();
      expect(doc.context, equals('document'));
      expect(doc.nodeName, equals('document'));
      expect(doc.document, same(doc));
      expect(doc.parent, isNull);
      expect(doc.level, equals(0));
      expect(doc.isBlock, isTrue);
      expect(doc.isInline, isFalse);
    });

    test('document context without NodeDocument throws StateError', () {
      expect(() => Block(null, 'document'), throwsA(isA<StateError>()));
    });

    test('block takes document and level from parent', () {
      final doc = makeDoc();
      final block = Block(doc, 'paragraph', source: 'a');
      expect(block.context, equals('paragraph'));
      expect(block.nodeName, equals('paragraph'));
      expect(block.document, same(doc));
      expect(block.parent, same(doc));
      expect(block.level, equals(0));
      expect(block.lines, equals(['a']));
      expect(block.contentModel, equals('simple'));
      expect(block.isBlock, isTrue);
      expect(block.isInline, isFalse);
    });

    test('detached block has null document and level', () {
      final block = Block(null, 'paragraph', source: 'z');
      expect(block.document, isNull);
      expect(block.parent, isNull);
      expect(block.level, isNull);
    });

    test('attributes map is copied, not aliased', () {
      final source = <String, Object?>{'a': '1'};
      final block = Block(makeDoc(), 'paragraph', attributes: source);
      expect(block.attributes, equals({'a': '1'}));
      expect(block.attributes, isNot(same(source)));
      source['a'] = 'changed';
      expect(block.attributes['a'], equals('1'));
    });

    test('id starts unset', () {
      expect(Block(makeDoc(), 'paragraph').id, isNull);
      expect(Inline(makeDoc(), 'quoted', text: 'x').id, isNull);
    });

    test('section context starts at level zero', () {
      final section = FakeSection(makeDoc());
      expect(section.context, equals('section'));
      expect(section.level, equals(0));
    });

    test('parent setter re-points document', () {
      final doc = makeDoc();
      final open = Block(doc, 'open')..contentModel = 'compound';
      final detached = Block(null, 'paragraph');
      detached.parent = open;
      expect(detached.parent, same(open));
      expect(detached.document, same(doc));
    });
  });

  group('attr', () {
    late FakeDocument doc;
    late Block block;

    setUp(() {
      doc = makeDoc();
      doc.attributes['x'] = 'doc-x';
      doc.attributes['y'] = 'doc-y';
      block = Block(doc, 'paragraph', attributes: {'x': 'node-x', 'f': false});
    });

    test('reads node attribute, default, and fallbacks', () {
      expect(block.attr('x'), equals('node-x'));
      expect(block.attr('missing', 'dflt'), equals('dflt'));
      expect(block.attr('missing', 'dflt', true), equals('dflt'));
      expect(block.attr('missing', 'dflt', 'y'), equals('doc-y'));
    });

    test('false values count as missing', () {
      expect(block.attr('f', 'dflt'), equals('dflt'));
      expect(block.attr('f', 'dflt', true), equals('dflt'));
    });

    test('hasAttr finds node, document, and compared values', () {
      expect(block.hasAttr('x'), isTrue);
      expect(block.hasAttr('missing'), isFalse);
      expect(block.hasAttr('missing', null, true), isFalse);
      expect(block.hasAttr('missing', null, 'y'), isTrue);
      expect(block.hasAttr('x', 'node-x'), isTrue);
      expect(block.hasAttr('x', 'nope'), isFalse);
      expect(block.hasAttr('missing', 'doc-y', 'y'), isTrue);
      expect(block.hasAttr('missing', 'nope', 'y'), isFalse);
    });

    test('hasAttr without expected value sees false-valued keys', () {
      expect(block.hasAttr('f'), isTrue);
      expect(block.hasAttr('f', false), isTrue);
    });

    test('document node never falls back', () {
      expect(doc.attr('missing', 'dflt', true), equals('dflt'));
      expect(doc.hasAttr('missing', null, true), isFalse);
    });

    test('setAttr reports overwrite refusals', () {
      expect(block.setAttr('n', 'v'), isTrue);
      expect(block.setAttr('n', 'w', false), isFalse);
      expect(block.setAttr('n', 'w'), isTrue);
      expect(block.attr('n'), equals('w'));
    });

    test('removeAttr returns previous value', () {
      block.setAttr('n', 'w');
      expect(block.removeAttr('n'), equals('w'));
      expect(block.removeAttr('n'), isNull);
    });

    test('updateAttributes returns the node attributes', () {
      final updated = block.updateAttributes({'u': 1});
      expect(updated, same(block.attributes));
      expect(block.attr('u'), equals(1));
    });
  });

  group('options', () {
    test('hasOption, setOption, and enabledOptions', () {
      final block = Block(
        makeDoc(),
        'paragraph',
        attributes: {'a-option': '', '-option': ''},
      );
      expect(block.hasOption('a'), isTrue);
      expect(block.hasOption('missing'), isFalse);
      expect(block.enabledOptions, equals({'a', ''}));
      block.setOption('b');
      expect(block.hasOption('b'), isTrue);
      expect(block.attributes['b-option'], equals(''));
    });
  });

  group('roles', () {
    test('roles splits blank runs and empties', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.roles, isEmpty);
      expect(block.role, isNull);
      block.attributes['role'] = 'a  b';
      expect(block.roles, equals(['a', 'b']));
      block.attributes['role'] = ' a ';
      expect(block.roles, equals(['a']));
      block.attributes['role'] = 'a\tb\nc';
      expect(block.roles, equals(['a', 'b', 'c']));
      block.attributes['role'] = false;
      expect(block.roles, isEmpty);
    });

    test('hasRole checks presence and equality', () {
      final block = Block(makeDoc(), 'paragraph', attributes: {'role': 'a b'});
      expect(block.hasRole(), isTrue);
      expect(block.hasRole('a b'), isTrue);
      expect(block.hasRole('a'), isFalse);
      expect(Block(makeDoc(), 'paragraph').hasRole(), isFalse);
      expect(
        Block(makeDoc(), 'paragraph', attributes: {'role': false}).hasRole(),
        isTrue,
      );
    });

    test('includesRole matches whole names only', () {
      final block = Block(
        makeDoc(),
        'paragraph',
        attributes: {'role': 'thumb lead'},
      );
      expect(block.includesRole('thumb'), isTrue);
      expect(block.includesRole('hum'), isFalse);
      expect(Block(makeDoc(), 'paragraph').includesRole('x'), isFalse);
    });

    test('role setter joins lists like Ruby', () {
      final block = Block(makeDoc(), 'paragraph');
      block.role = 'solo';
      expect(block.role, equals('solo'));
      block.role = ['a', 'b'];
      expect(block.role, equals('a b'));
      block.role = [
        'a',
        ['b', null],
        'c',
      ];
      expect(block.role, equals('a b  c'));
    });

    test('addRole and removeRole report changes', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.addRole('x'), isTrue);
      expect(block.role, equals('x'));
      expect(block.addRole('x'), isFalse);
      expect(block.addRole('y'), isTrue);
      expect(block.role, equals('x y'));
      expect(block.removeRole('x'), isTrue);
      expect(block.role, equals('y'));
      expect(block.removeRole('x'), isFalse);
      expect(block.removeRole('y'), isTrue);
      expect(block.attributes.containsKey('role'), isFalse);
    });

    test('addRole to an empty role prefixes a blank', () {
      final block = Block(makeDoc(), 'paragraph');
      block.role = '';
      expect(block.addRole('x'), isTrue);
      expect(block.role, equals(' x'));
    });
  });

  group('reftext', () {
    test('hasReftext tracks the attribute', () {
      expect(Block(makeDoc(), 'paragraph').hasReftext, isFalse);
      expect(
        Block(makeDoc(), 'paragraph', attributes: {'reftext': 'R'}).hasReftext,
        isTrue,
      );
    });

    test('reftext without text returns null', () {
      expect(Block(makeDoc(), 'paragraph').reftext, isNull);
    });

    test('reftext with text applies reftext substitutions', () {
      final block = Block(
        Document(<String>[]),
        'paragraph',
        attributes: {'reftext': 'R *x*'},
      );
      expect(block.reftext, equals('R <strong>x</strong>'));
    });
  });

  group('convert', () {
    test('convert plays back attributes and delegates', () {
      final doc = makeDoc();
      final block = Block(doc, 'paragraph', source: 'hi');
      final result = block.convert();
      expect(result, equals('<paragraph>'));
      expect(doc.converter.converted, equals([block]));
      expect(doc.playedBack, equals([block.attributes]));
    });

    test('render aliases convert', () {
      final doc = makeDoc();
      final block = Block(doc, 'paragraph', source: 'hi');
      expect(block.render(), equals('<paragraph>'));
      expect(doc.converter.converted, equals([block]));
    });

    test('compound content joins converted children', () {
      final doc = makeDoc();
      final open = Block(doc, 'open');
      open << Block(open, 'paragraph', source: 'a *b*');
      doc.converter.handler = (node) => '[${node.nodeName}]';
      expect(open.content(), equals('[paragraph]'));
    });

    test('empty content model returns null silently', () {
      final block = Block(makeDoc(), 'image');
      expect(block.content(), isNull);
      expect(testLogger.warns, isEmpty);
    });

    test('unknown content model warns and returns null', () {
      final block = Block(makeDoc(), 'image')..contentModel = 'bogus';
      expect(block.content(), isNull);
      expect(testLogger.warns, hasLength(1));
      final message = testLogger.warns.single.toString();
      expect(
        message,
        startsWith("unknown content model 'bogus' for block: #<Block@"),
      );
      expect(message, contains('{context: :image'));
      expect(message, contains('content_model: :bogus'));
      expect(message, contains('style: nil, lines: 0}'));
    });
  });

  group('tree', () {
    test('append operators parent and return self', () {
      final doc = makeDoc();
      final open = Block(doc, 'open');
      final first = Block(doc, 'paragraph', source: 'x');
      expect(open << first, same(open));
      expect(first.parent, same(open));
      expect(first.document, same(doc));
      expect(open.blocks, equals([first]));
      final second = Block(doc, 'paragraph', source: 'y');
      expect(open.append(second), same(open));
      expect(open.blocks, equals([first, second]));
    });

    test('re-appending appends again', () {
      final open = Block(makeDoc(), 'open');
      final child = Block(open, 'paragraph');
      open << child << child;
      expect(open.blocks, equals([child, child]));
      expect(child.parent, same(open));
    });

    test('hasBlocks and sections filter children', () {
      final doc = makeDoc();
      final open = Block(doc, 'open');
      expect(open.hasBlocks, isFalse);
      expect(open.hasSections, isFalse);
      expect(open.sections, isEmpty);
      final section = FakeSection(open);
      open << Block(open, 'paragraph') << section;
      expect(open.hasBlocks, isTrue);
      expect(open.hasSections, isFalse);
      expect(open.sections, equals([section]));
    });

    test('context setter re-derives the node name', () {
      final block = Block(makeDoc(), 'paragraph');
      block.context = 'sidebar';
      expect(block.context, equals('sidebar'));
      expect(block.nodeName, equals('sidebar'));
    });

    test('file and lineno read the source location', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.file, isNull);
      expect(block.lineno, isNull);
      block.sourceLocation = FakeSourceLocation('doc.adoc', 12);
      expect(block.file, equals('doc.adoc'));
      expect(block.lineno, equals(12));
    });
  });

  group('title', () {
    test('unset title reads null', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.title, isNull);
      expect(block.hasTitle, isFalse);
    });

    test('set title applies title substitutions', () {
      final block = Block(Document(<String>[]), 'example')..title = 'T *em*';
      expect(block.hasTitle, isTrue);
      expect(block.title, equals('T <strong>em</strong>'));
      block.title = null;
      expect(block.hasTitle, isFalse);
      expect(block.title, isNull);
    });

    test('captionedTitle without caption or title is empty', () {
      expect(Block(makeDoc(), 'paragraph').captionedTitle(), equals(''));
    });
  });

  group('subs predicates', () {
    test('hasSub and removeSub track the subs list', () {
      final block = Block(makeDoc(), 'paragraph')..subs = ['quotes'];
      expect(block.hasSub('quotes'), isTrue);
      expect(block.hasSub('macros'), isFalse);
      block.removeSub('quotes');
      expect(block.subs, isEmpty);
    });
  });

  group('alt', () {
    test('block alt without text is empty', () {
      expect(Block(makeDoc(), 'image').alt, equals(''));
    });

    test('block alt with text encodes special characters', () {
      final block = Block(
        Document(<String>[]),
        'image',
        attributes: {'alt': 'A & B'},
      );
      expect(block.alt, equals('A &amp; B'));
    });
  });

  group('caption', () {
    test('admonition caption routes to textlabel', () {
      final admonition = Block(
        makeDoc(),
        'admonition',
        attributes: {'textlabel': 'Look!'},
      )..caption = 'ignored';
      expect(admonition.caption, equals('Look!'));
      final note = Block(makeDoc(), 'example')..caption = 'Example 1. ';
      expect(note.caption, equals('Example 1. '));
      expect(Block(makeDoc(), 'example').caption, isNull);
    });
  });

  group('listMarkerKeyword', () {
    test('maps styles and explicit types', () {
      final block = Block(makeDoc(), 'open');
      expect(block.listMarkerKeyword('lowerroman'), equals('i'));
      expect(block.listMarkerKeyword(), isNull);
      expect(Block(makeDoc(), 'olist').listMarkerKeyword(), isNull);
      block.style = 'upperalpha';
      expect(block.listMarkerKeyword(), equals('A'));
    });
  });

  group('number', () {
    test('number coerces integer-like numerals', () {
      final block = Block(makeDoc(), 'section');
      expect(block.number, isNull);
      block.numeral = '5';
      expect(block.number, equals(5));
      block.numeral = 'A';
      expect(block.number, equals('A'));
      block.numeral = ' 7 ';
      expect(block.number, equals(7));
      block.numeral = '0x10';
      expect(block.number, equals(16));
      block.numeral = '010';
      expect(block.number, equals(8));
      block.numeral = 5;
      expect(block.number, equals(5));
    });

    test('number setter stringifies', () {
      final block = Block(makeDoc(), 'section');
      block.number = 5;
      expect(block.numeral, equals('5'));
    });
  });

  group('findBy', () {
    late FakeDocument doc;
    late FakeSection section;
    late Block first;
    late Block second;
    late Block image;

    setUp(() {
      doc = makeDoc();
      section = FakeSection(doc);
      doc << section;
      first = Block(section, 'paragraph', source: 'one');
      second = Block(section, 'paragraph', source: 'two');
      section << first << second;
      image = Block(
        section,
        'image',
        attributes: {'target': 'a.png', 'role': 'thumb'},
      )..id = 'fig1';
      section << image;
    });

    test('matches everything, contexts, roles, and ids', () {
      expect(doc.findBy(), hasLength(5));
      expect(doc.findBy(context: 'paragraph'), equals([first, second]));
      expect(doc.findBy(role: 'thumb'), equals([image]));
      expect(doc.findBy(id: 'fig1').map((n) => n.context), equals(['image']));
      expect(doc.findBy(context: 'paragraph', style: 'x'), isEmpty);
    });

    test('filter runs only on matching nodes', () {
      final visits = <String>[];
      doc.findBy(
        context: 'paragraph',
        filter: (node) {
          visits.add(node.context);
          return true;
        },
      );
      expect(visits, equals(['paragraph', 'paragraph']));
    });

    test('prune, reject, and stop verdicts', () {
      final pruned = doc.findBy(
        filter: (node) =>
            node.context == 'section' ? FindByVerdict.prune : true,
      );
      expect(pruned.map((n) => n.context), equals(['document', 'section']));
      final rejected = doc.findBy(
        filter: (node) =>
            node.context == 'section' ? FindByVerdict.reject : true,
      );
      expect(rejected.map((n) => n.context), equals(['document']));
      var visits = 0;
      final stopped = doc.findBy(
        filter: (node) {
          visits += 1;
          return visits > 2 ? FindByVerdict.stop : true;
        },
      );
      expect(stopped, hasLength(2));
      expect(visits, equals(3));
    });

    test('false filter with id stops immediately', () {
      expect(doc.findBy(id: 'fig1', filter: (_) => false), isEmpty);
    });

    test('false filter still visits children', () {
      final found = doc.findBy(
        context: 'paragraph',
        filter: (node) => node == first ? false : true,
      );
      expect(found, equals([second]));
    });

    test('query aliases findBy', () {
      expect(doc.query(context: 'section'), equals([section]));
    });

    test('section search skips non-section subtrees', () {
      final open = Block(doc, 'open');
      doc << open;
      final nested = FakeSection(open);
      open << nested;
      var visits = 0;
      final found = doc.findBy(
        context: 'section',
        filter: (_) {
          visits += 1;
          return true;
        },
      );
      // The nested section hides inside a non-section block, so Ruby's
      // section-search optimization never visits it either.
      expect(found, equals([section]));
      expect(visits, equals(1));
    });
  });

  group('nextAdjacentBlock', () {
    test('walks siblings then past the parent', () {
      final doc = makeDoc();
      final section = FakeSection(doc);
      doc << section;
      final first = Block(section, 'paragraph', source: 'one');
      final second = Block(section, 'paragraph', source: 'two');
      final image = Block(section, 'image');
      section << first << second << image;
      expect(first.nextAdjacentBlock(), same(second));
      expect(second.nextAdjacentBlock(), same(image));
      expect(image.nextAdjacentBlock(), isNull);
      expect(doc.nextAdjacentBlock(), isNull);
      expect(section.nextAdjacentBlock(), isNull);
    });

    test('detached node throws StateError', () {
      expect(Block(null, 'paragraph').nextAdjacentBlock, throwsStateError);
    });
  });

  group('xreftext', () {
    test('without title or reftext returns null', () {
      expect(Block(makeDoc(), 'paragraph').xreftext(), isNull);
    });

    test('short style with title and bare caption chomps', () {
      final block = Block(makeDoc(), 'example')
        ..title = 'NoCap'
        ..caption = 'Ex. ';
      expect(block.xreftext('short'), equals('Ex'));
    });

    test('short style with numeral resolves the prefix', () {
      final doc = makeDoc(attributes: {'example-caption': 'Example'});
      final block = Block(doc, 'example')
        ..title = 'T'
        ..caption = 'Example 1. '
        ..numeral = 1;
      expect(block.xreftext('short'), equals('Example 1'));
    });

    test('basic style and plain call read the title', () {
      final block = Block(Document(<String>[]), 'example')..title = 'NoCap';
      expect(block.xreftext('weird'), equals('NoCap'));
      expect(block.xreftext(), equals('NoCap'));
    });

    test('full style combines caption and title', () {
      final block = Block(Document(<String>[]), 'example')
        ..title = 'T'
        ..caption = 'Example 1. ';
      // Ruby: `%(#{caption.chomp '. '}, #{quoted_title})`.
      expect(block.xreftext('full'), equals('Example 1, &#8220;T&#8221;'));
    });

    test('explicit reftext wins over the title', () {
      final block = Block(
        Document(<String>[]),
        'paragraph',
        attributes: {'reftext': 'R *em*'},
      );
      expect(block.xreftext(), equals('R <strong>em</strong>'));
    });
  });

  group('assignCaption', () {
    test('skips captioned and untitled blocks', () {
      final captioned = Block(makeDoc(), 'example')
        ..title = 'T'
        ..caption = 'Keep. ';
      captioned.assignCaption(null);
      expect(captioned.caption, equals('Keep. '));
      final untitled = Block(makeDoc(), 'example');
      untitled.assignCaption(null);
      expect(untitled.caption, isNull);
    });

    test('explicit value wins over the document caption', () {
      final doc = makeDoc(attributes: {'caption': 'Doc. '});
      final valued = Block(doc, 'example')..title = 'T';
      valued.assignCaption('Given. ');
      expect(valued.caption, equals('Given. '));
      final fallback = Block(doc, 'example')..title = 'T';
      fallback.assignCaption(null);
      expect(fallback.caption, equals('Doc. '));
    });

    test('auto caption numbers from the document', () {
      final doc = makeDoc(attributes: {'example-caption': 'Example'});
      final block = Block(doc, 'example')..title = 'T *em*';
      block.assignCaption(null);
      expect(block.caption, equals('Example 1. '));
      expect(block.numeral, equals(1));
      expect(block.attributes.containsKey('example-number'), isFalse);
      expect(doc.storedCounters, hasLength(1));
      expect(doc.storedCounters.single.name, equals('example-number'));
      expect(doc.storedCounters.single.value, equals(1));
    });

    test('figure context never auto captions', () {
      // Ruby's caption map holds 'figure' as a string key that context
      // (symbol) lookups never match.
      final doc = makeDoc(attributes: {'figure-caption': 'Figure'});
      final figure = Block(doc, 'figure')..title = 'T';
      figure.assignCaption(null);
      expect(figure.caption, isNull);
      expect(figure.numeral, isNull);
    });
  });

  group('assignNumeral', () {
    late FakeDocument doc;

    setUp(() {
      doc = makeDoc(attributes: {'appendix-caption': 'Appendix'});
    });

    test('appendix takes a letter and caption', () {
      final section = FakeSection(doc, numbered: true, sectname: 'appendix');
      doc.assignNumeral(section);
      expect(section.numeral, equals('A'));
      expect(section.caption, equals('Appendix A: '));
      expect(section.index, equals(0));
    });

    test('chapter takes the next chapter number', () {
      final section = FakeSection(doc, numbered: true, sectname: 'chapter');
      doc.assignNumeral(section);
      expect(section.numeral, equals('1'));
    });

    test('part takes a roman numeral', () {
      final section = FakeSection(doc, numbered: true, sectname: 'part');
      doc.assignNumeral(section);
      expect(section.numeral, equals('I'));
    });

    test('numbered section takes the next ordinal', () {
      doc.assignNumeral(FakeSection(doc, numbered: true, sectname: 'part'));
      final section = FakeSection(doc, numbered: true, sectname: 'section');
      doc.assignNumeral(section);
      expect(section.numeral, equals('2'));
      expect(section.index, equals(1));
    });

    test('unnumbered section takes only an index', () {
      final section = FakeSection(doc, numbered: false, sectname: 'section');
      doc.assignNumeral(section);
      expect(section.numeral, isNull);
      expect(section.index, equals(0));
    });

    test('non-section argument throws', () {
      expect(
        () => doc.assignNumeral(Block(doc, 'paragraph')),
        throwsA(isA<TypeError>()),
      );
    });

    test('reindexSections reassigns in document order', () {
      final first = FakeSection(doc, numbered: true, sectname: 'section');
      final second = FakeSection(doc, numbered: true, sectname: 'section');
      doc
        ..assignNumeral(first)
        ..assignNumeral(second);
      doc << first << second;
      doc.blocks.removeAt(0);
      doc.reindexSections();
      expect(second.index, equals(0));
      expect(second.numeral, equals('1'));
    });
  });

  group('block', () {
    test('content models default by context', () {
      const expected = {
        'audio': 'empty',
        'image': 'empty',
        'listing': 'verbatim',
        'literal': 'verbatim',
        'stem': 'raw',
        'open': 'compound',
        'page_break': 'empty',
        'pass': 'raw',
        'thematic_break': 'empty',
        'video': 'empty',
        'paragraph': 'simple',
        'sidebar': 'simple',
      };
      for (final entry in expected.entries) {
        expect(
          Block(makeDoc(), entry.key).contentModel,
          equals(entry.value),
          reason: entry.key,
        );
      }
      expect(
        Block(makeDoc(), 'paragraph', contentModel: 'verbatim').contentModel,
        equals('verbatim'),
      );
    });

    test('lines come from strings, lists, or nothing', () {
      final doc = makeDoc();
      expect(Block(doc, 'paragraph').lines, isEmpty);
      expect(Block(doc, 'paragraph', source: '').lines, isEmpty);
      expect(Block(doc, 'paragraph', source: <String>[]).lines, isEmpty);
      expect(Block(doc, 'paragraph', source: 'a\nb').lines, equals(['a', 'b']));
      final input = ['x'];
      final fromList = Block(doc, 'paragraph', source: input);
      expect(fromList.lines, equals(['x']));
      expect(fromList.lines, isNot(same(input)));
    });

    test('source joins lines', () {
      expect(
        Block(makeDoc(), 'paragraph', source: 'a\nb').source(),
        equals('a\nb'),
      );
      expect(Block(makeDoc(), 'paragraph').source(), equals(''));
    });

    test('blockname aliases context', () {
      expect(Block(makeDoc(), 'listing').blockname, equals('listing'));
    });

    test('toString mirrors the Ruby shape', () {
      final text = Block(makeDoc(), 'paragraph', source: ['a', 'b']).toString();
      expect(text, startsWith('#<Block@'));
      expect(
        text,
        endsWith(
          ' {context: :paragraph, content_model: :simple, '
          'style: nil, lines: 2}>',
        ),
      );
      final compound = Block(makeDoc(), 'open')..style = 's';
      compound << Block(compound, 'paragraph');
      expect(compound.toString(), contains('blocks: 1'));
      expect(compound.toString(), contains('style: "s"'));
    });
  });

  group('subs wiring', () {
    test('absent subs defers resolution', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.defaultSubs, isNull);
      expect(block.subs, isEmpty);
    });

    test('null subs prevents resolution', () {
      final block = Block(
        makeDoc(),
        'paragraph',
        attributes: {'subs': 'quotes'},
        subs: null,
      );
      expect(block.defaultSubs, equals(<String>[]));
      expect(block.attributes.containsKey('subs'), isFalse);
    });

    test('given subs resolve eagerly via commitSubs', () {
      final doc = Document(<String>[]);
      expect(
        Block(doc, 'paragraph', subs: const ['quotes']).subs,
        equals(['quotes']),
      );
      expect(Block(doc, 'paragraph', subs: 'default').subs, equals(normalSubs));
      expect(Block(doc, 'paragraph', subs: 'normal').subs, equals(normalSubs));
    });

    test('simple and verbatim content apply subs on read', () {
      final doc = Document(<String>[]);
      // Deferred (empty) subs are vacuous in Ruby: the source passes
      // through, with blank edge lines stripped for verbatim blocks.
      expect(Block(doc, 'paragraph', source: 'a').content(), equals('a'));
      expect(Block(doc, 'listing', source: 'a').content(), equals('a'));
      final quoted = Block(doc, 'paragraph', source: 'a')..subs = ['quotes'];
      expect(quoted.content(), equals('a'));
    });
  });

  group('inline', () {
    test('construction sets node name, type, and target', () {
      final doc = makeDoc();
      final node = Inline(
        doc,
        'quoted',
        text: 'x',
        type: 'strong',
        target: 't',
        id: 'i',
      );
      expect(node.nodeName, equals('inline_quoted'));
      expect(node.context, equals('quoted'));
      expect(node.text, equals('x'));
      expect(node.type, equals('strong'));
      expect(node.target, equals('t'));
      expect(node.id, equals('i'));
      expect(node.document, same(doc));
      expect(node.isBlock, isFalse);
      expect(node.isInline, isTrue);
      expect(node.content(), equals('x'));
    });

    test('convert delegates without playback', () {
      final doc = makeDoc();
      final node = Inline(doc, 'quoted', text: 'hi', type: 'strong');
      expect(node.convert(), equals('<inline_quoted>'));
      expect(doc.converter.converted, equals([node]));
      expect(doc.playedBack, isEmpty);
    });

    test('render aliases convert', () {
      final node = Inline(makeDoc(), 'quoted', text: 'hi');
      expect(node.render(), equals('<inline_quoted>'));
    });

    test('alt reads the attribute or defaults empty', () {
      expect(
        Inline(makeDoc(), 'image', attributes: {'alt': 'A'}).alt,
        equals('A'),
      );
      expect(Inline(makeDoc(), 'image').alt, equals(''));
    });

    test('reference nodes carry reftext in text', () {
      final ref = Inline(
        Document(<String>[]),
        'anchor',
        text: 'T',
        type: 'ref',
      );
      expect(ref.hasReftext, isTrue);
      expect(ref.reftext, equals('T'));
      expect(
        Inline(makeDoc(), 'anchor', text: 'T', type: 'bibref').hasReftext,
        isTrue,
      );
      expect(
        Inline(makeDoc(), 'quoted', text: 'T', type: 'strong').hasReftext,
        isFalse,
      );
      final untexted = Inline(makeDoc(), 'anchor', type: 'ref');
      expect(untexted.hasReftext, isFalse);
      expect(untexted.reftext, isNull);
      expect(untexted.xreftext(), isNull);
    });

    test('xreftext without text returns null', () {
      expect(Inline(makeDoc(), 'image').xreftext(), isNull);
    });
  });

  group('paths', () {
    test('normalizeSystemPath jails to the base directory', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(
        block.normalizeSystemPath('x/../y.txt'),
        equals('${fixtureDir.path}/y.txt'),
      );
    });

    test('normalizeSystemPath without jail recovers with a warning', () {
      final pathWarnings = <String>[];
      final doc = FakeDocument(
        baseDir: fixtureDir.path,
        pathResolver: PathResolver(onWarn: pathWarnings.add),
      );
      final block = Block(doc, 'paragraph');
      final resolved = block.normalizeSystemPath('../y.txt');
      expect(resolved, equals('${fixtureDir.path}/y.txt'));
      expect(pathWarnings, hasLength(1));
    });

    test('normalizeSystemPath without recovery throws SecurityError', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(
        () => block.normalizeSystemPath('../y.txt', recover: false),
        throwsA(isA<SecurityError>()),
      );
    });

    test('normalizeSystemPath below safe joins the start', () {
      final doc = makeDoc(safe: SafeMode.unsafe);
      final block = Block(doc, 'paragraph');
      expect(
        block.normalizeSystemPath('y.txt', start: 'sub'),
        equals('${fixtureDir.path}/sub/y.txt'),
      );
      expect(
        block.normalizeSystemPath('y.txt'),
        equals('${fixtureDir.path}/y.txt'),
      );
    });

    test('normalizeWebPath joins and preserves URIs', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.normalizeWebPath('a.png', 'img'), equals('img/a.png'));
      expect(
        block.normalizeWebPath('https://x/y z'),
        equals('https://x/y%20z'),
      );
    });

    test('normalizeAssetPath roots at the base directory', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(
        block.normalizeAssetPath('img/a.png'),
        equals('${fixtureDir.path}/img/a.png'),
      );
    });
  });

  group('read', () {
    test('readAsset reads raw and normalized', () {
      final block = Block(makeDoc(), 'paragraph');
      final path = '${fixtureDir.path}/norm.txt';
      expect(block.readAsset(path), equals('line1  \nline2\n'));
      expect(block.readAsset(path, normalize: true), equals('line1\nline2'));
    });

    test('readAsset warns on failure when asked', () {
      final block = Block(makeDoc(), 'paragraph');
      final missing = '${fixtureDir.path}/nope';
      expect(block.readAsset(missing), isNull);
      expect(testLogger.warns, isEmpty);
      expect(block.readAsset(missing, warnOnFailure: true), isNull);
      expect(
        testLogger.warns.single,
        equals('<stdin>: file does not exist or cannot be read: $missing'),
      );
    });

    test('readContents reads files relative to start', () {
      final block = Block(makeDoc(safe: SafeMode.safe), 'paragraph');
      expect(
        block.readContents('img/a.png', start: fixtureDir.path, label: 'pic'),
        equals('PNGDATA'),
      );
    });

    test('readContents warns for empty contents when asked', () {
      final block = Block(makeDoc(safe: SafeMode.safe), 'paragraph');
      final target = '${fixtureDir.path}/img/empty.txt';
      expect(
        block.readContents(
          'img/empty.txt',
          start: fixtureDir.path,
          warnIfEmpty: true,
        ),
        equals(''),
      );
      expect(
        testLogger.warns.single,
        equals('contents of asset is empty: $target'),
      );
    });

    test('readContents of missing file warns and returns null', () {
      final block = Block(makeDoc(safe: SafeMode.safe), 'paragraph');
      expect(
        block.readContents('img/nope.txt', start: fixtureDir.path),
        isNull,
      );
      expect(testLogger.warns, hasLength(1));
    });

    test('readContents of URI without allow-uri-read warns', () {
      final block = Block(makeDoc(), 'paragraph');
      const uri = 'https://example.com/x.adoc';
      expect(block.readContents(uri), isNull);
      expect(
        testLogger.warns.single,
        equals(
          'cannot retrieve contents of asset at URI: $uri '
          '(allow-uri-read attribute not enabled)',
        ),
      );
    });

    test('readContents of URI fetches when allowed', () {
      final doc = makeDoc(attributes: {'allow-uri-read': ''});
      final block = UriBlock(
        doc,
        'paragraph',
        response: (body: utf8.encode('a  \nb\n'), contentType: 'text/plain'),
      );
      const uri = 'https://example.com/x.adoc';
      expect(block.readContents(uri), equals('a  \nb\n'));
      expect(block.fetchedUris, equals([uri]));
      expect(block.readContents(uri, normalize: true), equals('a\nb'));
    });

    test('readContents of URI resolves against a URI start', () {
      final doc = makeDoc(attributes: {'allow-uri-read': ''});
      final block = UriBlock(
        doc,
        'paragraph',
        response: (body: utf8.encode('x'), contentType: 'text/plain'),
      );
      block.readContents('b.adoc', start: 'https://example.com/a/');
      expect(block.fetchedUris.single, equals('https://example.com/a/b.adoc'));
    });

    test('readContents warns when the fetch fails', () {
      final doc = makeDoc(attributes: {'allow-uri-read': ''});
      final block = UriBlock(
        doc,
        'paragraph',
        fetchError: Exception('refused'),
      );
      const uri = 'https://example.com/x.adoc';
      expect(block.readContents(uri), isNull);
      expect(
        testLogger.warns.single,
        equals('could not retrieve contents of asset at URI: $uri'),
      );
    });

    test('readContents with cache-uri requires the cache library', () {
      final doc = makeDoc(attributes: {'allow-uri-read': '', 'cache-uri': ''});
      final block = UriBlock(
        doc,
        'paragraph',
        response: (body: utf8.encode('x'), contentType: 'text/plain'),
      );
      expect(
        () => block.readContents('https://example.com/x.adoc'),
        throwsStateError,
      );
    });

    test('default fetchUri throws instead of warning', () {
      final doc = makeDoc(attributes: {'allow-uri-read': ''});
      final block = Block(doc, 'paragraph');
      expect(
        () => block.readContents('https://example.com/x.adoc'),
        throwsUnimplementedError,
      );
      expect(testLogger.warns, isEmpty);
    });
  });

  group('uris', () {
    test('imageUri and mediaUri resolve web paths', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.imageUri('a.png'), equals('a.png'));
      expect(block.mediaUri('v.mp4', null), equals('v.mp4'));
    });

    test('iconUri builds from name, icon, and icontype', () {
      final doc = makeDoc(attributes: {'iconsdir': 'icons', 'icontype': 'svg'});
      final block = Block(doc, 'paragraph');
      expect(block.iconUri('note'), equals('icons/note.svg'));
      block.setAttr('icon', 'custom');
      expect(block.iconUri('note'), equals('icons/custom.svg'));
      block.setAttr('icon', 'custom.png');
      expect(block.iconUri('note'), equals('icons/custom.png'));
    });

    test('data-uri images embed file bytes', () {
      final doc = makeDoc(safe: SafeMode.safe, attributes: {'data-uri': ''});
      final block = Block(doc, 'paragraph');
      expect(
        block.imageUri('img/a.png', null),
        equals('data:image/png;base64,UE5HREFUQQ=='),
      );
      expect(
        block.generateDataUri('img/a.png', null),
        equals('data:image/png;base64,UE5HREFUQQ=='),
      );
    });

    test('missing embedded image warns with empty payload', () {
      final doc = makeDoc(safe: SafeMode.safe, attributes: {'data-uri': ''});
      final block = Block(doc, 'paragraph');
      expect(
        block.imageUri('img/nope.png', null),
        equals('data:image/png;base64,'),
      );
      expect(
        testLogger.warns.single,
        equals(
          'image to embed not found or not readable: '
          '${fixtureDir.path}/img/nope.png',
        ),
      );
    });

    test('generateDataUriFromUri embeds fetched bytes', () {
      final doc = makeDoc(attributes: {'allow-uri-read': ''});
      final block = UriBlock(
        doc,
        'paragraph',
        response: (body: utf8.encode('IMGBYTES'), contentType: 'image/png'),
      );
      expect(
        block.generateDataUriFromUri('https://example.com/a.png'),
        equals('data:image/png;base64,SU1HQllURVM='),
      );
    });

    test('generateDataUriFromUri warns and echoes on failure', () {
      final doc = makeDoc(attributes: {'allow-uri-read': ''});
      final block = UriBlock(
        doc,
        'paragraph',
        fetchError: Exception('refused'),
      );
      const uri = 'http://127.0.0.1:1/nope.png';
      expect(block.generateDataUriFromUri(uri), equals(uri));
      expect(
        testLogger.warns.single,
        equals('could not retrieve image data from URI: $uri'),
      );
    });

    test('generateDataUriFromUri with cache requires open-uri', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(
        () => block.generateDataUriFromUri('https://example.com/a.png', true),
        throwsStateError,
      );
    });
  });

  group('misc', () {
    test('isUri sniffs URI schemes', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.isUri('https://x'), isTrue);
      expect(block.isUri('rel/path'), isFalse);
    });

    test('logger is shared and replaceable', () {
      final block = Block(makeDoc(), 'paragraph');
      expect(block.logger, same(testLogger));
      expect(AbstractNode.currentLogger, same(testLogger));
    });

    test('safe mode levels match Ruby', () {
      expect(SafeMode.unsafe, equals(0));
      expect(SafeMode.safe, equals(1));
      expect(SafeMode.server, equals(10));
      expect(SafeMode.secure, equals(20));
    });
  });
}
