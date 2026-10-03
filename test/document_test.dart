/// Port of `test/document_test.rb` (156 tests).
///
/// Tests that parse or convert (directly or through the `documentFromString`
/// default of `parse: true`) are skipped with [needsParser] until the parser
/// wave lands; the parser wave must un-skip them. XML/CSS assertions in
/// skipped bodies route through [assertXpath]/[assertCss] stubs that throw
/// until an XML-matching helper is ported. Non-parse tests pass now.
library;

import 'dart:io' show Directory;

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:test/test.dart';

/// Skip reason for tests requiring the parser wave.
const String needsParser = 'needs Parser.parse (parser wave)';

/// Built-in converter element names (port of `BUILT_IN_ELEMENTS`).
const List<String> builtInElements = <String>[
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
  'stem',
  'olist',
  'open',
  'page_break',
  'paragraph',
  'pass',
  'preamble',
  'quote',
  'section',
  'sidebar',
  'table',
  'thematic_break',
  'toc',
  'ulist',
  'verse',
  'video',
];

/// Records log messages for assertions.
class FakeLogger implements NodeLogger {
  /// Messages by severity.
  final List<Object?> debugs = <Object?>[];
  final List<Object?> infos = <Object?>[];
  final List<Object?> warns = <Object?>[];
  final List<Object?> errors = <Object?>[];
  final List<Object?> fatals = <Object?>[];

  /// All recorded messages.
  List<Object?> get messages => <Object?>[
    ...debugs,
    ...infos,
    ...warns,
    ...errors,
    ...fatals,
  ];

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

/// Runs [body] with a memory logger installed (port of
/// `using_memory_logger`).
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

/// Creates an empty document (port of `empty_document`; never parses unless
/// `options['parse']` is `true`).
Document emptyDocument([Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  final parse = opts.remove('parse') == true;
  final doc = Document(<String>[], opts);
  return parse ? doc.parse() : doc;
}

/// Creates a document from [src] (port of `document_from_string`).
///
/// Defaults to `standalone: true` and `parse: true`, like the Ruby helper.
Document documentFromString(String src, [Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts.putIfAbsent('standalone', () => true);
  final parse = opts.remove('parse') ?? true;
  if (opts['standalone'] == true) {
    final attrs =
        (opts['attributes'] as Map<String, Object?>?) ?? <String, Object?>{};
    attrs['linkcss'] = '';
    opts['attributes'] = attrs;
  }
  final templateDir = const String.fromEnvironment('TEMPLATE_DIR');
  if (templateDir.isNotEmpty) {
    opts.putIfAbsent('template_dir', () => templateDir);
  }
  final doc = Document(src, opts);
  return (parse == true) ? doc.parse() : doc;
}

/// Converts [src] to a standalone document (port of `convert_string`).
String convertString(String src, [Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts.remove('keep_namespaces');
  return documentFromString(src, opts).convert() as String;
}

/// Converts [src] to an embedded document (port of
/// `convert_string_to_embedded`).
String convertStringToEmbedded(String src, [Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts['standalone'] = false;
  return documentFromString(src, opts).convert() as String;
}

/// Converts the file at [path] (port of `Asciidoctor.convert_file`).
///
/// API wave: stub throwing [UnimplementedError]; all callers are skipped.
String convertFile(
  String path, {
  Object? toFile,
  bool standalone = false,
  String? backend,
  Object? safe,
  Map<String, Object?>? attributes,
}) => throw UnimplementedError('API wave: convertFile is not yet ported.');

/// Loads [input] into a parsed document (port of `Asciidoctor.load`).
///
/// API wave: stub throwing [UnimplementedError]; all callers are skipped.
Document asciidoctorLoad(
  String input, {
  Object? backend,
  bool standalone = false,
}) => throw UnimplementedError('API wave: asciidoctorLoad is not yet ported.');

/// Loads a sample document (port of `example_document`).
///
/// Fixture wave: stub throwing [UnimplementedError]; all callers are skipped.
Document exampleDocument(String name) => throw UnimplementedError(
  'Fixture wave: exampleDocument is not yet ported.',
);

/// Asserts [content] matches [xpath] [count] times (port of `assert_xpath`).
///
/// XML-match wave: stub throwing [UnimplementedError]; all callers are
/// skipped.
void assertXpath(String xpath, String? content, int count) =>
    throw UnimplementedError('XML-match wave: assertXpath is not yet ported.');

/// Asserts [content] matches [css] [count] times (port of `assert_css`).
///
/// XML-match wave: stub throwing [UnimplementedError]; all callers are
/// skipped.
void assertCss(String css, String? content, int count) =>
    throw UnimplementedError('XML-match wave: assertCss is not yet ported.');

/// Returns the nodes matching [xpath] in [content] (port of
/// `xmlnodes_at_xpath`).
///
/// XML-match wave: stub throwing [UnimplementedError]; all callers are
/// skipped.
dynamic xmlnodesAtXpath(String xpath, String? content, [int? count]) =>
    throw UnimplementedError(
      'XML-match wave: xmlnodesAtXpath is not yet ported.',
    );

/// Decodes a numeric character reference (port of `decode_char`).
String decodeChar(int number) => String.fromCharCode(number);

/// Joins a fixture [name] to the fixtures directory (port of
/// `fixture_path`).
String fixturePath(String name) => '../test/fixtures/$name';

/// The Ruby test directory (port of `testdir`).
String get testdir => '../test';

void main() {
  group('Document', () {
    group('Example document', () {
      test('document title', skip: needsParser, () {
        final doc = exampleDocument('asciidoc_index');
        expect(doc.doctitle(), equals('AsciiDoc Home Page'));
        expect(doc.name(), equals('AsciiDoc Home Page'));
        expect(doc.header, isNotNull);
        expect(doc.header!.context, equals('section'));
        expect(doc.header!.sectname, equals('header'));
        expect(doc.blocks.length, equals(14));
        expect(doc.blocks[0].context, equals('preamble'));
        expect(doc.blocks[1].context, equals('section'));

        // Verify compat-mode is set when atx-style doctitle is used.
        final result = doc.blocks[0].convert();
        assertXpath('//em[text()="Stuart Rackham"]', result as String?, 1);
      });
    });

    group('Default settings', () {
      test('safe mode level set to SECURE by default', () {
        final doc = emptyDocument();
        expect(doc.safe, equals(SafeMode.secure));
      });

      test('safe mode level set using string', () {
        var doc = emptyDocument({'safe': 'server'});
        expect(doc.safe, equals(SafeMode.server));

        doc = emptyDocument({'safe': 'foo'});
        expect(doc.safe, equals(SafeMode.secure));
      });

      test('safe mode level set using symbol', () {
        // Dart has no symbols; option values are strings instead.
        var doc = emptyDocument({'safe': 'server'});
        expect(doc.safe, equals(SafeMode.server));

        doc = emptyDocument({'safe': 'foo'});
        expect(doc.safe, equals(SafeMode.secure));
      });

      test('safe mode level set using integer', () {
        var doc = emptyDocument({'safe': 10});
        expect(doc.safe, equals(SafeMode.server));

        doc = emptyDocument({'safe': 100});
        expect(doc.safe, equals(100));
      });

      test('safe mode attributes are set on document', () {
        final doc = emptyDocument();
        expect(doc.attr('safe-mode-level'), equals(SafeMode.secure));
        expect(doc.attr('safe-mode-name'), equals('secure'));
        expect(doc.hasAttr('safe-mode-secure'), isTrue);
        expect(doc.hasAttr('safe-mode-unsafe'), isFalse);
        expect(doc.hasAttr('safe-mode-safe'), isFalse);
        expect(doc.hasAttr('safe-mode-server'), isFalse);
      });

      test('safe mode level can be set in the constructor', () {
        final doc = Document(<String>[], {'safe': SafeMode.safe});
        expect(doc.safe, equals(SafeMode.safe));
      });

      test('safe mode level cannot be modified', () {
        // `safe` is a final field in Dart, so reassignment is a compile
        // error and there is no runtime behavior to assert (Ruby raises
        // NoMethodError instead).
        final doc = emptyDocument();
        expect(doc.safe, equals(SafeMode.secure));
      });

      test(
        'toc and sectnums should be enabled by default in DocBook backend',
        skip: needsParser,
        () {
          final doc = documentFromString('content', {'backend': 'docbook'});
          expect(doc.hasAttr('toc'), isTrue);
          expect(doc.hasAttr('sectnums'), isTrue);
          final result = doc.convert() as String;
          expect(result, contains('<?asciidoc-toc?>'));
          expect(result, contains('<?asciidoc-numbered?>'));
        },
      );

      test(
        'maxdepth attribute should be set on asciidoc-toc and '
        'asciidoc-numbered processing instructions in DocBook backend',
        skip: needsParser,
        () {
          final doc = documentFromString('content', {
            'backend': 'docbook',
            'attributes': {'toclevels': '1', 'sectnumlevels': '1'},
          });
          expect(doc.hasAttr('toc'), isTrue);
          expect(doc.hasAttr('sectnums'), isTrue);
          final result = doc.convert() as String;
          expect(result, contains('<?asciidoc-toc maxdepth="1"?>'));
          expect(result, contains('<?asciidoc-numbered maxdepth="1"?>'));
        },
      );

      test(
        'should be able to disable toc and sectnums in document header '
        'in DocBook backend',
        skip: needsParser,
        () {
          const input = '= Document Title\n:toc!:\n:sectnums!:\n';
          final doc = documentFromString(input, {'backend': 'docbook'});
          expect(doc.hasAttr('toc'), isFalse);
          expect(doc.hasAttr('sectnums'), isFalse);
        },
      );

      test(
        'noheader attribute should suppress info element when converting '
        'to DocBook',
        skip: needsParser,
        () {
          const input = '= Document Title\n:noheader:\n\ncontent\n';
          final result = convertString(input, {'backend': 'docbook'});
          assertXpath('/article', result, 1);
          assertXpath('/article/info', result, 0);
        },
      );

      test(
        'should be able to disable section numbering using numbered '
        'attribute in document header in DocBook backend',
        skip: needsParser,
        () {
          const input = '= Document Title\n:numbered!:\n';
          final doc = documentFromString(input, {'backend': 'docbook'});
          expect(doc.hasAttr('sectnums'), isFalse);
        },
      );
    });

    group('Docinfo files', () {
      test(
        'should include docinfo files for html backend',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          final cases = <String, Map<String, int>>{
            'docinfo': {
              'head_script': 1,
              'meta': 0,
              'top_link': 0,
              'footer_script': 1,
              'navbar': 1,
            },
            'docinfo=private': {
              'head_script': 1,
              'meta': 0,
              'top_link': 0,
              'footer_script': 1,
              'navbar': 1,
            },
            'docinfo1': {
              'head_script': 0,
              'meta': 1,
              'top_link': 1,
              'footer_script': 0,
              'navbar': 0,
            },
            'docinfo=shared': {
              'head_script': 0,
              'meta': 1,
              'top_link': 1,
              'footer_script': 0,
              'navbar': 0,
            },
            'docinfo2': {
              'head_script': 1,
              'meta': 1,
              'top_link': 1,
              'footer_script': 1,
              'navbar': 1,
            },
            'docinfo docinfo2': {
              'head_script': 1,
              'meta': 1,
              'top_link': 1,
              'footer_script': 1,
              'navbar': 1,
            },
            'docinfo=private,shared': {
              'head_script': 1,
              'meta': 1,
              'top_link': 1,
              'footer_script': 1,
              'navbar': 1,
            },
            'docinfo=private-head': {
              'head_script': 1,
              'meta': 0,
              'top_link': 0,
              'footer_script': 0,
              'navbar': 0,
            },
            'docinfo=private-header': {
              'head_script': 0,
              'meta': 0,
              'top_link': 0,
              'footer_script': 0,
              'navbar': 1,
            },
            'docinfo=shared-head': {
              'head_script': 0,
              'meta': 1,
              'top_link': 0,
              'footer_script': 0,
              'navbar': 0,
            },
            'docinfo=private-footer': {
              'head_script': 0,
              'meta': 0,
              'top_link': 0,
              'footer_script': 1,
              'navbar': 0,
            },
            'docinfo=shared-footer': {
              'head_script': 0,
              'meta': 0,
              'top_link': 1,
              'footer_script': 0,
              'navbar': 0,
            },
            r'docinfo=private-head\ ,\ shared-footer': {
              'head_script': 1,
              'meta': 0,
              'top_link': 1,
              'footer_script': 0,
              'navbar': 0,
            },
          };

          // NOTE the Ruby test passes the attribute overrides as a string;
          // Document takes a map, so the API wave owns that translation.
          cases.forEach((attrVal, markup) {
            final output = convertFile(
              sampleInputPath,
              toFile: false,
              standalone: true,
              safe: SafeMode.server,
              attributes: {'_attr_string_': 'linkcss copycss! $attrVal'},
            );
            expect(output, isNotEmpty);
            assertCss(
              'script[src="modernizr.js"]',
              output,
              markup['head_script']!,
            );
            assertCss(
              'meta[http-equiv="imagetoolbar"]',
              output,
              markup['meta']!,
            );
            assertCss('body > a#top', output, markup['top_link']!);
            assertCss('body > script', output, markup['footer_script']!);
            assertCss('body > nav.navbar', output, markup['navbar']!);
            assertCss('body > nav.navbar + #header', output, markup['navbar']!);
          });
        },
      );

      test(
        'should include docinfo header even if noheader attribute is set',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');
          final output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo': 'private-header', 'noheader': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body > nav.navbar', output, 1);
          assertCss('body > nav.navbar + #content', output, 1);
        },
      );

      test(
        'should include docinfo footer even if nofooter attribute is set',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');
          final output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo1': '', 'nofooter': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body > a#top', output, 1);
        },
      );

      test(
        'should include user docinfo after built-in docinfo',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');
          final attrs = <String, Object?>{
            'docinfo': 'shared',
            'source-highlighter': 'highlight.js',
            'linkcss': '',
            'copycss': null,
          };
          final output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: 'safe',
            attributes: attrs,
          );
          assertCss(
            'link[rel=stylesheet] + meta[http-equiv=imagetoolbar]',
            output,
            1,
          );
          assertCss('meta[http-equiv=imagetoolbar] + *', output, 0);
          assertCss('script + a#top', output, 1);
          assertCss('a#top + *', output, 0);
        },
      );

      test(
        'should include docinfo files for html backend with custom docinfodir',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo': '', 'docinfodir': 'custom-docinfodir'},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 1);
          assertCss('meta[name="robots"]', output, 0);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo1': '', 'docinfodir': 'custom-docinfodir'},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 0);
          assertCss('meta[name="robots"]', output, 1);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo2': '', 'docinfodir': './custom-docinfodir'},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 1);
          assertCss('meta[name="robots"]', output, 1);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {
              'docinfo2': '',
              'docinfodir': 'custom-docinfodir/subfolder',
            },
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.js"]', output, 0);
          assertCss('meta[name="robots"]', output, 0);
        },
      );

      test(
        'should include docinfo files in docbook backend',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo': ''},
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 0);
          assertCss('copyright', output, 1);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo1': ''},
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 1);
          assertXpath('//xmlns:productname[text()="Asciidoctor™"]', output, 1);
          assertCss('edition', output, 1);
          // Verifies substitutions are performed.
          assertXpath('//xmlns:edition[text()="1.0"]', output, 1);
          assertCss('copyright', output, 0);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 1);
          assertXpath('//xmlns:productname[text()="Asciidoctor™"]', output, 1);
          assertCss('edition', output, 1);
          // Verifies substitutions are performed.
          assertXpath('//xmlns:edition[text()="1.0"]', output, 1);
          assertCss('copyright', output, 1);
        },
      );

      test(
        'should use header docinfo in place of default header',
        skip: needsParser,
        () {
          final output = convertFile(
            fixturePath('sample.adoc'),
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo': 'private-header', 'noheader': ''},
          );
          expect(output, isNotEmpty);
          assertCss('article > info', output, 1);
          assertCss('article > info > title', output, 1);
          assertCss('article > info > revhistory', output, 1);
          assertCss('article > info > revhistory > revision', output, 2);
        },
      );

      test(
        'should include docinfo footer files for html backend',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body script', output, 1);
          assertCss('a#top', output, 0);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo1': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body script', output, 0);
          assertCss('a#top', output, 1);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('body script', output, 1);
          assertCss('a#top', output, 1);
        },
      );

      test(
        'should include docinfo footer files in DocBook backend',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo': ''},
          );
          expect(output, isNotEmpty);
          assertCss('article > revhistory', output, 1);
          // Verifies substitutions are performed.
          assertXpath(
            '/xmlns:article/xmlns:revhistory/xmlns:revision/xmlns:revnumber[text()="1.0"]',
            output,
            1,
          );
          assertCss('glossary', output, 0);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo1': ''},
          );
          expect(output, isNotEmpty);
          assertCss('article > revhistory', output, 0);
          assertCss('glossary[xml|id="_glossary"]', output, 1);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('article > revhistory', output, 1);
          // Verifies substitutions are performed.
          assertXpath(
            '/xmlns:article/xmlns:revhistory/xmlns:revision/xmlns:revnumber[text()="1.0"]',
            output,
            1,
          );
          assertCss('glossary[xml|id="_glossary"]', output, 1);
        },
      );

      test(
        'should force encoding of docinfo files to UTF-8',
        skip: needsParser,
        () {
          // Dart strings are always UTF-8; there are no default external
          // or internal encodings to manipulate.
          final sampleInputPath = fixturePath('basic.adoc');
          final output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
            attributes: {'docinfo': 'private,shared'},
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 1);
          expect(output, contains('<productname>Asciidoctor™</productname>'));
          assertCss('edition', output, 1);
          // Verifies substitutions are performed.
          assertXpath('//xmlns:edition[text()="1.0"]', output, 1);
          assertCss('copyright', output, 1);
        },
      );

      test(
        'should not include docinfo files by default',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: SafeMode.server,
          );
          expect(output, isNotEmpty);
          assertCss('script[src="modernizr.js"]', output, 0);
          assertCss('meta[http-equiv="imagetoolbar"]', output, 0);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            safe: SafeMode.server,
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 0);
          assertCss('copyright', output, 0);
        },
      );

      test(
        'should not include docinfo files if safe mode is SECURE or greater',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('basic.adoc');

          var output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('script[src="modernizr.js"]', output, 0);
          assertCss('meta[http-equiv="imagetoolbar"]', output, 0);

          output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            backend: 'docbook',
            attributes: {'docinfo2': ''},
          );
          expect(output, isNotEmpty);
          assertCss('productname', output, 0);
          assertCss('copyright', output, 0);
        },
      );

      test(
        'should substitute attributes in docinfo files by default',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('subs.adoc');
          usingMemoryLogger((logger) {
            final output = convertFile(
              sampleInputPath,
              toFile: false,
              standalone: true,
              safe: 'server',
              attributes: {
                'docinfo': '',
                'bootstrap-version': null,
                'linkcss': '',
                'attribute-missing': 'drop-line',
              },
            );
            expect(output, isNotEmpty);
            assertCss('script', output, 0);
            assertXpath(
              '//meta[@name="copyright"][@content="(C) OpenDevise"]',
              output,
              1,
            );
            expect(
              logger.infos,
              contains(
                'dropping line containing reference to missing attribute: '
                'bootstrap-version',
              ),
            );
          });
        },
      );

      test(
        'should apply explicit substitutions to docinfo files',
        skip: needsParser,
        () {
          final sampleInputPath = fixturePath('subs.adoc');
          final output = convertFile(
            sampleInputPath,
            toFile: false,
            standalone: true,
            safe: 'server',
            attributes: {
              'docinfo': '',
              'docinfosubs': 'attributes,replacements',
              'linkcss': '',
            },
          );
          expect(output, isNotEmpty);
          assertCss('script[src="bootstrap.3.2.0.min.js"]', output, 1);
          assertXpath(
            '//meta[@name="copyright"][@content="${decodeChar(169)} OpenDevise"]',
            output,
            1,
          );
        },
      );
    });

    group('MathJax', () {
      test(
        'should add MathJax script to HTML head if stem attribute is set',
        skip: needsParser,
        () {
          final output = convertString('', {
            'attributes': {'stem': ''},
          });
          expect(output, contains('<script type="text/x-mathjax-config">'));
          expect(output, contains(r'inlineMath: [["\\(", "\\)"]]'));
          expect(output, contains(r'displayMath: [["\\[", "\\]"]]'));
          expect(output, contains(r'delimiters: [["\\$", "\\$"]]'));
        },
      );
    });

    group('Converter', () {
      test(
        'convert methods on built-in converter are registered by default',
        () {
          final doc = emptyDocument();
          expect(doc.attributes['backend'], equals('html5'));
          expect(doc.attributes.containsKey('backend-html5'), isTrue);
          expect(doc.attributes['basebackend'], equals('html'));
          expect(doc.attributes.containsKey('basebackend-html'), isTrue);
          expect(doc.converter, isNotNull);
          // Converter wave: assert the converter type and that it responds
          // to convert_<element> for every builtInElements entry.
          expect(builtInElements, isNotEmpty);
        },
      );

      test('convert methods on built-in converter are registered when '
          'backend is docbook5', () {
        final doc = emptyDocument({
          'attributes': {'backend': 'docbook5'},
        });
        expect(doc.attributes['backend'], equals('docbook5'));
        expect(doc.attributes.containsKey('backend-docbook5'), isTrue);
        expect(doc.attributes['basebackend'], equals('docbook'));
        expect(doc.attributes.containsKey('basebackend-docbook'), isTrue);
        expect(doc.converter, isNotNull);
        // Converter wave: assert the converter type and that it responds
        // to convert_<element> for every builtInElements entry.
      });

      test(
        'should add favicon if favicon attribute is set',
        skip: needsParser,
        () {
          final cases = <String, List<String>>{
            '': ['favicon.ico', 'image/x-icon'],
            '/favicon.ico': ['/favicon.ico', 'image/x-icon'],
            '/img/favicon.png': ['/img/favicon.png', 'image/png'],
          };
          cases.forEach((val, hrefAndType) {
            final result = convertString('= Untitled', {
              'attributes': {'favicon': val},
            });
            assertCss('link[rel="icon"]', result, 1);
            assertCss('link[rel="icon"][href="${hrefAndType[0]}"]', result, 1);
            assertCss('link[rel="icon"][type="${hrefAndType[1]}"]', result, 1);
          });
        },
      );
    });

    group('Structure', () {
      test('document with no doctitle', skip: needsParser, () {
        final doc = documentFromString('Snorf');
        expect(doc.doctitle(), isNull);
        expect(doc.name(), isNull);
        expect(doc.hasHeader, isFalse);
        expect(doc.header, isNull);
      });

      test(
        'should enable compat mode for document with legacy doctitle',
        skip: needsParser,
        () {
          const input = 'Document Title\n==============\n\n+content+\n';
          final doc = documentFromString(input);
          expect(doc.hasAttr('compat-mode'), isTrue);
          final result = doc.convert() as String;
          assertXpath('//code[text()="content"]', result, 1);
        },
      );

      test(
        'should not enable compat mode for document with legacy doctitle '
        'if compat mode disable by header',
        skip: needsParser,
        () {
          const input =
              'Document Title\n==============\n:compat-mode!:\n\n+content+\n';
          final doc = documentFromString(input);
          expect(doc.attr('compat-mode'), isNull);
          final result = doc.convert() as String;
          assertXpath('//code[text()="content"]', result, 0);
        },
      );

      test(
        'should not enable compat mode for document with legacy doctitle '
        'if compat mode is locked by API',
        skip: needsParser,
        () {
          const input = 'Document Title\n==============\n\n+content+\n';
          final doc = documentFromString(input, {
            'attributes': {'compat-mode': null},
          });
          expect(doc.attributeLocked('compat-mode'), isTrue);
          expect(doc.attr('compat-mode'), isNull);
          final result = doc.convert() as String;
          assertXpath('//code[text()="content"]', result, 0);
        },
      );

      test(
        'should apply max-width to each top-level container',
        skip: needsParser,
        () {
          const input = '= Document Title\n\ncontentfootnote:[placeholder]\n';
          final output = convertString(input, {
            'attributes': {'max-width': '70em'},
          });
          assertCss('body[style]', output, 0);
          assertCss('#header[style="max-width: 70em;"]', output, 1);
          assertCss('#content[style="max-width: 70em;"]', output, 1);
          assertCss('#footnotes[style="max-width: 70em;"]', output, 1);
          assertCss('#footer[style="max-width: 70em;"]', output, 1);
        },
      );

      test('title partition API with default separator', () {
        final title = DocumentTitle('Main Title: And More: Subtitle');
        expect(title.main, equals('Main Title: And More'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('title partition API with custom separator', () {
        final title = DocumentTitle(
          'Main Title:: And More:: Subtitle',
          separator: '::',
        );
        expect(title.main, equals('Main Title:: And More'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('document with subtitle', skip: needsParser, () {
        const input = '= Main Title: *Subtitle*\nAuthor Name\n\ncontent\n';
        final doc = documentFromString(input);
        final title =
            doc.doctitle(partition: true, sanitize: true) as DocumentTitle;
        expect(title.hasSubtitle, isTrue);
        expect(title.sanitized, isTrue);
        expect(title.main, equals('Main Title'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test('document with subtitle and custom separator', skip: needsParser, () {
        const input =
            '[separator=::]\n= Main Title:: *Subtitle*\nAuthor Name\n\ncontent\n';
        final doc = documentFromString(input);
        final title =
            doc.doctitle(partition: true, sanitize: true) as DocumentTitle;
        expect(title.hasSubtitle, isTrue);
        expect(title.sanitized, isTrue);
        expect(title.main, equals('Main Title'));
        expect(title.subtitle, equals('Subtitle'));
      });

      test(
        'should not honor custom separator for doctitle if attribute is '
        'locked by API',
        skip: needsParser,
        () {
          const input =
              '[separator=::]\n= Main Title - *Subtitle*\nAuthor Name\n\ncontent\n';
          final doc = documentFromString(input, {
            'attributes': {'title-separator': ' -'},
          });
          final title =
              doc.doctitle(partition: true, sanitize: true) as DocumentTitle;
          expect(title.hasSubtitle, isTrue);
          expect(title.sanitized, isTrue);
          expect(title.main, equals('Main Title'));
          expect(title.subtitle, equals('Subtitle'));
        },
      );

      test(
        'document with doctitle defined as attribute entry',
        skip: needsParser,
        () {
          const input =
              ':doctitle: Document Title\n\npreamble\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Document Title'));
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('Document Title'));
          expect(doc.firstSection!.title, equals('Document Title'));
        },
      );

      test(
        'document with doctitle defined as attribute entry followed by '
        'block with title',
        skip: needsParser,
        () {
          const input =
              ':doctitle: Document Title\n\n.Block title\nBlock content\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Document Title'));
          expect(doc.hasHeader, isTrue);
          expect(doc.blocks.length, equals(1));
          expect(doc.blocks[0].context, equals('paragraph'));
          expect(doc.blocks[0].title, equals('Block title'));
        },
      );

      test(
        'document with title attribute entry overrides doctitle',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n:title: Override\n\n{doctitle}\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Override'));
          expect(doc.title, equals('Override'));
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('Document Title'));
          expect(doc.firstSection!.title, equals('Document Title'));
          assertXpath(
            '//*[@id="preamble"]//p[text()="Document Title"]',
            doc.convert() as String,
            1,
          );
        },
      );

      test(
        'document with blank title attribute entry overrides doctitle',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n:title:\n\n{doctitle}\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals(''));
          expect(doc.title, equals(''));
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('Document Title'));
          expect(doc.firstSection!.title, equals('Document Title'));
          assertXpath(
            '//*[@id="preamble"]//p[text()="Document Title"]',
            doc.convert() as String,
            1,
          );
        },
      );

      test(
        'document header can reference intrinsic doctitle attribute',
        skip: needsParser,
        () {
          const input =
              '= ACME Documentation\n:intro: Welcome to the {doctitle}!\n\n{intro}\n';
          final doc = documentFromString(input);
          expect(
            doc.attr('intro'),
            equals('Welcome to the ACME Documentation!'),
          );
          assertXpath(
            '//p[text()="Welcome to the ACME Documentation!"]',
            doc.convert() as String,
            1,
          );
        },
      );

      test(
        'document with title attribute entry overrides doctitle attribute '
        'entry',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n:snapshot: {doctitle}\n:doctitle: doctitle\n:title: Override\n\n'
              '{snapshot}, {doctitle}\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Override'));
          expect(doc.title, equals('Override'));
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('doctitle'));
          expect(doc.firstSection!.title, equals('doctitle'));
          assertXpath(
            '//*[@id="preamble"]//p[text()="Document Title, doctitle"]',
            doc.convert() as String,
            1,
          );
        },
      );

      test(
        'document with doctitle attribute entry overrides implicit doctitle',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n:snapshot: {doctitle}\n:doctitle: Override\n\n'
              '{snapshot}, {doctitle}\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Override'));
          expect(doc.attributes['title'], isNull);
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('Override'));
          expect(doc.firstSection!.title, equals('Override'));
          assertXpath(
            '//*[@id="preamble"]//p[text()="Document Title, Override"]',
            doc.convert() as String,
            1,
          );
        },
      );

      test(
        'doctitle attribute entry above header overrides implicit doctitle',
        skip: needsParser,
        () {
          const input =
              ':doctitle: Override\n= Document Title\n\n{doctitle}\n\n== First Section\n';
          final doc = documentFromString(input);
          expect(doc.doctitle(), equals('Override'));
          expect(doc.attributes['title'], isNull);
          expect(doc.hasHeader, isTrue);
          expect(doc.header!.title, equals('Override'));
          expect(doc.firstSection!.title, equals('Override'));
          assertXpath(
            '//*[@id="preamble"]//p[text()="Override"]',
            doc.convert() as String,
            1,
          );
        },
      );

      test(
        'should apply header substitutions to value of the doctitle '
        'attribute assigned from implicit doctitle',
        skip: needsParser,
        () {
          const input =
              '= <Foo> {plus} <Bar>\n\nThe name of the game is {doctitle}.\n';
          final doc = documentFromString(input);
          expect(doc.attr('doctitle'), equals('&lt;Foo&gt; &#43; &lt;Bar&gt;'));
          expect(
            doc.blocks[0].content() as String,
            contains('&lt;Foo&gt; &#43; &lt;Bar&gt;'),
          );
        },
      );

      test(
        'should substitute attribute reference in implicit document title '
        'for attribute defined earlier in header',
        skip: needsParser,
        () {
          usingMemoryLogger((logger) {
            const input =
                ':project-name: ACME\n= {project-name} Docs\n\n{doctitle}\n';
            final doc = documentFromString(input, {
              'attributes': {'attribute-missing': 'warn'},
            });
            expect(logger.messages, isEmpty);
            expect(doc.attr('doctitle'), equals('ACME Docs'));
            expect(doc.doctitle(), equals('ACME Docs'));
            assertXpath('//p[text()="ACME Docs"]', doc.convert() as String, 1);
          });
        },
      );

      test(
        'should not warn if implicit document title contains attribute '
        'reference for attribute defined later in header',
        skip: needsParser,
        () {
          usingMemoryLogger((logger) {
            const input =
                '= {project-name} Docs\n:project-name: ACME\n\n{doctitle}\n';
            final doc = documentFromString(input, {
              'attributes': {'attribute-missing': 'warn'},
            });
            expect(logger.messages, isEmpty);
            expect(doc.attr('doctitle'), equals('{project-name} Docs'));
            expect(doc.doctitle(), equals('ACME Docs'));
            assertXpath(
              '//p[text()="{project-name} Docs"]',
              doc.convert() as String,
              1,
            );
          });
        },
      );

      test(
        'should recognize document title when preceded by blank lines',
        skip: needsParser,
        () {
          const input = '\n= Title\n\npreamble\n\n== Section 1\n\ntext\n';
          final output = convertString(input, {'safe': SafeMode.safe});
          assertCss('#header h1', output, 1);
          assertCss('#content h1', output, 0);
        },
      );

      test(
        'should recognize document title when preceded by blank lines '
        'introduced by a preprocessor conditional',
        skip: needsParser,
        () {
          const input =
              'ifdef::sectids[]\n\n:foo: bar\nendif::[]\n= Title\n\npreamble\n\n== Section 1\n\ntext\n';
          final output = convertString(input, {'safe': SafeMode.safe});
          assertCss('#header h1', output, 1);
          assertCss('#content h1', output, 0);
        },
      );

      test(
        'should recognize document title when preceded by blank lines '
        'after an attribute entry',
        skip: needsParser,
        () {
          const input =
              ':doctype: book\n\n= Title\n\npreamble\n\n== Section 1\n\ntext\n';
          final output = convertString(input, {'safe': SafeMode.safe});
          assertCss('#header h1', output, 1);
          assertCss('#content h1', output, 0);
        },
      );

      test(
        'should recognize document title in include file when preceded by '
        'blank lines',
        skip: needsParser,
        () {
          const input =
              'include::fixtures/include-with-leading-blank-line.adoc[]\n';
          final output = convertString(input, {
            'safe': SafeMode.safe,
            'attributes': {'docdir': testdir},
          });
          assertXpath('//h1[text()="Document Title"]', output, 1);
          assertCss('#toc', output, 1);
        },
      );

      test(
        'should include specified lines even when leading lines are skipped',
        skip: needsParser,
        () {
          const input =
              'include::fixtures/include-with-leading-blank-line.adoc[lines=6]\n';
          final output = convertString(input, {
            'safe': SafeMode.safe,
            'attributes': {'docdir': testdir},
          });
          assertXpath('//h2[text()="Section"]', output, 1);
        },
      );

      test(
        'document with multiline attribute entry but only one line should '
        'not crash',
        skip: needsParser,
        () {
          // Port of Asciidoctor::LINE_CONTINUATION (' \\').
          final input = ':foo: bar \\';
          final doc = documentFromString(input);
          expect(doc.attributes['foo'], equals('bar'));
        },
      );

      test('should sanitize contents of HTML title element', skip: needsParser, () {
        const input =
            '= *Document* image:logo.png[] _Title_ image:another-logo.png[another logo]\n\ncontent\n';
        final output = convertString(input);
        assertXpath('/html/head/title[text()="Document Title"]', output, 1);
        final nodes = xmlnodesAtXpath('//*[@id="header"]/h1', output);
        expect((nodes as dynamic).length, equals(1));
        expect(
          output,
          contains(
            '<h1><strong>Document</strong> <span class="image"><img src="logo.png" alt="logo"></span> '
            '<em>Title</em> <span class="image"><img src="another-logo.png" alt="another logo"></span></h1>',
          ),
        );
      });

      test('should not choke on empty source', () {
        final doc = Document('');
        expect(doc.blocks, isEmpty);
        expect(doc.doctitle(), isNull);
        expect(doc.hasHeader, isFalse);
        expect(doc.header, isNull);
      });

      test('should not choke on nil source', () {
        final doc = Document(null);
        expect(doc.blocks, isEmpty);
        expect(doc.doctitle(), isNull);
        expect(doc.hasHeader, isFalse);
        expect(doc.header, isNull);
      });

      test('with metadata', skip: needsParser, () {
        const input =
            '= AsciiDoc\nStuart Rackham <founder@asciidoc.org>\nv8.6.8, 2012-07-12: See changelog.\n'
            ':description: AsciiDoc user guide\n:keywords: asciidoc,documentation\n:copyright: Stuart Rackham\n'
            '\n== Version 8.6.8\n\nmore info...\n';
        final output = convertString(input);
        assertXpath(
          '//meta[@name="author"][@content="Stuart Rackham"]',
          output,
          1,
        );
        assertXpath(
          '//meta[@name="description"][@content="AsciiDoc user guide"]',
          output,
          1,
        );
        assertXpath(
          '//meta[@name="keywords"][@content="asciidoc,documentation"]',
          output,
          1,
        );
        assertXpath(
          '//meta[@name="copyright"][@content="Stuart Rackham"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="author"][text()="Stuart Rackham"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="email"]/a[@href="mailto:founder@asciidoc.org"][text()="founder@asciidoc.org"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="revnumber"][text()="version 8.6.8,"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="revdate"][text()="2012-07-12"]',
          output,
          1,
        );
        assertXpath(
          '//*[@id="header"]/*[@class="details"]/span[@id="revremark"][text()="See changelog."]',
          output,
          1,
        );
      });

      test(
        'should parse revision line if date is empty',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nAuthor Name\nv1.0.0,:remark\n\ncontent\n';
          final doc = documentFromString(input);
          expect(doc.attributes['revnumber'], equals('1.0.0'));
          expect(doc.attributes['revdate'], isNull);
          expect(doc.attributes['revremark'], equals('remark'));
        },
      );

      test(
        'should include revision history in DocBook output if revdate and '
        'revnumber is set',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nAuthor Name\n:revdate: 2011-11-11\n:revnumber: 1.0\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertCss('revhistory', output, 1);
          assertCss('revhistory > revision', output, 1);
          assertCss('revhistory > revision > date', output, 1);
          assertCss('revhistory > revision > revnumber', output, 1);
        },
      );

      test(
        'should include revision history in DocBook output if revdate and '
        'revremark is set',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nAuthor Name\n:revdate: 2011-11-11\n:revremark: features!\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertCss('revhistory', output, 1);
          assertCss('revhistory > revision', output, 1);
          assertCss('revhistory > revision > date', output, 1);
          assertCss('revhistory > revision > revremark', output, 1);
        },
      );

      test(
        'should not include revision history in DocBook output if revdate '
        'is not set',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nAuthor Name\n:revnumber: 1.0\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertCss('revhistory', output, 0);
        },
      );

      test('with metadata to DocBook 5', skip: needsParser, () {
        const input =
            '= AsciiDoc\nStuart Rackham <founder@asciidoc.org>\n\n== Version 8.6.8\n\nmore info...\n';
        final output = convertString(input, {'backend': 'docbook5'});
        assertXpath('/article/info', output, 1);
        assertXpath('/article/info/title[text()="AsciiDoc"]', output, 1);
        assertXpath('/article/info/author/personname', output, 1);
        assertXpath(
          '/article/info/author/personname/firstname[text()="Stuart"]',
          output,
          1,
        );
        assertXpath(
          '/article/info/author/personname/surname[text()="Rackham"]',
          output,
          1,
        );
        assertXpath(
          '/article/info/author/email[text()="founder@asciidoc.org"]',
          output,
          1,
        );
        assertCss('article:root:not([xml|id])', output, 1);
        assertCss('article:root[xml|lang="en"]', output, 1);
      });

      test('with document ID to Docbook 5', skip: needsParser, () {
        const input = '[[document-id]]\n= Document Title\n\nmore info...\n';
        final output = convertString(input, {
          'backend': 'docbook',
          'keep_namespaces': true,
        });
        assertCss('article:root[xml|id="document-id"]', output, 1);
      });

      test(
        'with author defined using attribute entry to DocBook',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n:author: Doc Writer\n:email: thedoctor@asciidoc.org\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertXpath('/article/info/author', output, 1);
          assertXpath(
            '/article/info/author/personname/firstname[text()="Doc"]',
            output,
            1,
          );
          assertXpath(
            '/article/info/author/personname/surname[text()="Writer"]',
            output,
            1,
          );
          assertXpath(
            '/article/info/author/email[text()="thedoctor@asciidoc.org"]',
            output,
            1,
          );
          assertXpath('/article/info/authorinitials[text()="DW"]', output, 1);
        },
      );

      test(
        'should substitute replacements in author names in HTML output',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nStephen O\'Grady <founder@redmonk.com>\n\ncontent\n';
          final output = convertString(input);
          assertXpath(
            '//meta[@name="author"][@content="Stephen O${decodeChar(8217)}Grady"]',
            output,
            1,
          );
          assertXpath(
            '//span[@id="author"][text()="Stephen O${decodeChar(8217)}Grady"]',
            output,
            1,
          );
        },
      );

      test(
        'should substitute replacements in author names in DocBook output',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nStephen O\'Grady <founder@redmonk.com>\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertXpath('//author', output, 1);
          assertXpath(
            '//author/personname/surname[text()="O${decodeChar(8217)}Grady"]',
            output,
            1,
          );
        },
      );

      test('should sanitize content of HTML meta authors tag', skip: needsParser, () {
        const input =
            '= Document Title\n:author: pass:n[http://example.org/community/team.html[Ze *Product* team]]\n\ncontent\n';
        final output = convertString(input);
        assertXpath(
          '//meta[@name="author"][@content="Ze Product team"]',
          output,
          1,
        );
      });

      test(
        'should not double escape ampersand in author attribute',
        skip: needsParser,
        () {
          const input = '= Document Title\nR&D Lab\n\n{author}\n';
          final output = convertString(input);
          expect(output, contains('R&amp;D Lab'));
        },
      );

      test('should include multiple authors in HTML output', skip: needsParser, () {
        const input =
            '= Document Title\nDoc Writer <thedoctor@asciidoc.org>; Junior Writer <junior@asciidoctor.org>\n\ncontent\n';
        final output = convertString(input);
        assertXpath('//span[@id="author"]', output, 1);
        assertXpath('//span[@id="author"][text()="Doc Writer"]', output, 1);
        assertXpath('//span[@id="email"]', output, 1);
        assertXpath('//span[@id="email"]/a', output, 1);
        assertXpath(
          '//span[@id="email"]/a[@href="mailto:thedoctor@asciidoc.org"][text()="thedoctor@asciidoc.org"]',
          output,
          1,
        );
        assertXpath('//span[@id="author2"]', output, 1);
        assertXpath('//span[@id="author2"][text()="Junior Writer"]', output, 1);
        assertXpath('//span[@id="email2"]', output, 1);
        assertXpath('//span[@id="email2"]/a', output, 1);
        assertXpath(
          '//span[@id="email2"]/a[@href="mailto:junior@asciidoctor.org"][text()="junior@asciidoctor.org"]',
          output,
          1,
        );
      });

      test(
        'should create authorgroup in DocBook when multiple authors',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nDoc Writer <thedoctor@asciidoc.org>; Junior Writer <junior@asciidoctor.org>\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertXpath('/article/info/author', output, 0);
          assertXpath('/article/info/authorgroup', output, 1);
          assertXpath('/article/info/authorgroup/author', output, 2);
          assertXpath(
            '(/article/info/authorgroup/author)[1]/personname/firstname[text()="Doc"]',
            output,
            1,
          );
          assertXpath(
            '(/article/info/authorgroup/author)[2]/personname/firstname[text()="Junior"]',
            output,
            1,
          );
        },
      );

      test(
        'should process author defined by attribute when implicit doctitle '
        'is absent',
        skip: needsParser,
        () {
          const input =
              ':author: Doc Writer\n\n{lastname}, {firstname} ({authorinitials})\n';
          final doc = documentFromString(input, {'standalone': false});
          expect(doc.attr('author'), equals('Doc Writer'));
          expect(doc.attr('author_1'), isNull);
          expect(doc.attr('lastname'), equals('Writer'));
          expect(doc.attr('firstname'), equals('Doc'));
          expect(doc.attr('authorinitials'), equals('DW'));
          expect(doc.attr('authorcount'), equals(1));
          final output = doc.convert() as String;
          assertXpath('//p[text()="Writer, Doc (DW)"]', output, 1);
        },
      );

      test(
        'should process author and authorinitials defined by attribute '
        'when implicit doctitle is absent',
        skip: needsParser,
        () {
          const input =
              ':authorinitials: DOC\n:author: Doc Writer\n\n{lastname}, {firstname} ({authorinitials})\n';
          final doc = documentFromString(input, {'standalone': false});
          expect(doc.attr('author'), equals('Doc Writer'));
          expect(doc.attr('authorinitials'), equals('DOC'));
          expect(doc.attr('authorcount'), equals(1));
          final output = doc.convert() as String;
          assertXpath('//p[text()="Writer, Doc (DOC)"]', output, 1);
        },
      );

      test(
        'should process authors defined by attribute when implicit '
        'doctitle is absent',
        skip: needsParser,
        () {
          const input =
              ':authors: Doc Writer; Other Author\n\n{lastname}, {firstname} ({authorinitials})\n';
          final doc = documentFromString(input, {'standalone': false});
          expect(doc.attr('author'), equals('Doc Writer'));
          expect(doc.attr('authors'), equals('Doc Writer, Other Author'));
          expect(doc.attr('author_1'), equals('Doc Writer'));
          expect(doc.attr('lastname'), equals('Writer'));
          expect(doc.attr('lastname_1'), equals('Writer'));
          expect(doc.attr('firstname'), equals('Doc'));
          expect(doc.attr('firstname_1'), equals('Doc'));
          expect(doc.attr('authorinitials'), equals('DW'));
          expect(doc.attr('authorinitials_1'), equals('DW'));
          expect(doc.attr('author_2'), equals('Other Author'));
          expect(doc.attr('authorinitials_2'), equals('OA'));
          expect(doc.attr('authorcount'), equals(2));
          final output = doc.convert() as String;
          assertXpath('//p[text()="Writer, Doc (DW)"]', output, 1);
        },
      );

      test(
        'should process authors and authorinitials defined by attribute '
        'when implicit doctitle is absent',
        skip: needsParser,
        () {
          const input =
              ':authorinitials: DOC\n:authors: Doc Writer; Other Author\n\n{lastname}, {firstname} ({authorinitials})\n';
          final doc = documentFromString(input, {'standalone': false});
          expect(doc.attr('author'), equals('Doc Writer'));
          expect(doc.attr('author_1'), equals('Doc Writer'));
          // FIXME this should be supported, but isn't yet
          //expect(doc.attr('authorinitials'), equals('DOC'));
          expect(doc.attr('authorinitials'), equals('DW'));
          expect(doc.attr('author_2'), equals('Other Author'));
          expect(doc.attr('authorcount'), equals(2));
          final output = doc.convert() as String;
          //assertXpath('//p[text()="Writer, Doc (DOC)"]', output, 1);
          assertXpath('//p[text()="Writer, Doc (DW)"]', output, 1);
        },
      );

      test(
        'should set authorcount to 0 if document has no header',
        skip: needsParser,
        () {
          final doc = documentFromString('content');
          expect(doc.attr('authorcount'), equals(0));
        },
      );

      test(
        'should set authorcount to 0 if author not set by attribute and '
        'implicit doctitle is missing',
        skip: needsParser,
        () {
          const input = ':idprefix:\n\n== Section Title\n\ncontent\n';
          final doc = documentFromString(input);
          expect(doc.attr('authorcount'), equals(0));
        },
      );

      test(
        'should set authorcount to 0 if author not set by attribute and '
        'document starts with level-0 section with style',
        skip: needsParser,
        () {
          const input =
              ':doctype: book\n\n[preface]\n= Preface\n\ncontent\n\n= Part\n\n== Chapter\n\ncontent\n';
          final doc = documentFromString(input);
          expect(doc.attr('authorcount'), equals(0));
        },
      );

      test(
        'with author defined by indexed attribute name',
        skip: needsParser,
        () {
          const input = '= Document Title\n:author_1: Doc Writer\n\n{author}\n';
          final doc = documentFromString(input);
          expect(doc.attr('author'), equals('Doc Writer'));
          expect(doc.attr('author_1'), equals('Doc Writer'));
        },
      );

      test(
        'with authors defined using attribute entry to DocBook',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n:authors: Doc Writer; Junior Writer\n:email_1: thedoctor@asciidoc.org\n'
              ':email_2: junior@asciidoc.org\n\ncontent\n';
          final output = convertString(input, {'backend': 'docbook'});
          assertXpath('/article/info/author', output, 0);
          assertXpath('/article/info/authorgroup', output, 1);
          assertXpath('/article/info/authorgroup/author', output, 2);
          assertXpath(
            '(/article/info/authorgroup/author)[1]/personname/firstname[text()="Doc"]',
            output,
            1,
          );
          assertXpath(
            '(/article/info/authorgroup/author)[1]/email[text()="thedoctor@asciidoc.org"]',
            output,
            1,
          );
          assertXpath(
            '(/article/info/authorgroup/author)[2]/personname/firstname[text()="Junior"]',
            output,
            1,
          );
          assertXpath(
            '(/article/info/authorgroup/author)[2]/email[text()="junior@asciidoc.org"]',
            output,
            1,
          );
        },
      );

      test(
        'should populate copyright element in DocBook output if copyright '
        'attribute is defined',
        skip: needsParser,
        () {
          const input =
              '= Jet Bike\n:copyright: ACME, Inc.\n\nEssential for catching road runners.\n';
          final output = convertString(input, {'backend': 'docbook5'});
          assertXpath('/article/info/copyright', output, 1);
          assertXpath(
            '/article/info/copyright/holder[text()="ACME, Inc."]',
            output,
            1,
          );
        },
      );

      test(
        'should populate copyright element in DocBook output if copyright '
        'attribute is defined with year',
        skip: needsParser,
        () {
          const input =
              '= Jet Bike\n:copyright: ACME, Inc. 1956\n\nEssential for catching road runners.\n';
          final output = convertString(input, {'backend': 'docbook5'});
          assertXpath('/article/info/copyright', output, 1);
          assertXpath(
            '/article/info/copyright/holder[text()="ACME, Inc."]',
            output,
            1,
          );
          assertXpath('/article/info/copyright/year', output, 1);
          assertXpath('/article/info/copyright/year[text()="1956"]', output, 1);
        },
      );

      test(
        'should populate copyright element in DocBook output if copyright '
        'attribute is defined with year range',
        skip: needsParser,
        () {
          const input =
              '= Jet Bike\n:copyright: ACME, Inc. 1956-2018\n\nEssential for catching road runners.\n';
          final output = convertString(input, {'backend': 'docbook5'});
          assertXpath('/article/info/copyright', output, 1);
          assertXpath(
            '/article/info/copyright/holder[text()="ACME, Inc."]',
            output,
            1,
          );
          assertXpath('/article/info/copyright/year', output, 1);
          assertXpath(
            '/article/info/copyright/year[text()="1956-2018"]',
            output,
            1,
          );
        },
      );

      test('with header footer', skip: needsParser, () {
        final doc = documentFromString('= Title\n\nparagraph');
        expect(doc.hasAttr('embedded'), isFalse);
        final result = doc.convert() as String;
        assertXpath('/html', result, 1);
        assertXpath('//*[@id="header"]', result, 1);
        assertXpath('//*[@id="header"]/h1', result, 1);
        assertXpath('//*[@id="footer"]', result, 1);
        assertXpath('//*[@id="content"]', result, 1);
      });

      test('does not output footer if nofooter is set', skip: needsParser, () {
        const input = ':nofooter:\n\ncontent\n';
        final result = convertString(input);
        assertXpath('//*[@id="footer"]', result, 0);
      });

      test('can disable last updated in footer', skip: needsParser, () {
        final doc = documentFromString('= Document Title\n\npreamble', {
          'attributes': {'last-update-label!': ''},
        });
        final result = doc.convert() as String;
        assertXpath('//*[@id="footer-text"]', result, 1);
        assertXpath(
          '//*[@id="footer-text"][normalize-space(text())=""]',
          result,
          1,
        );
      });

      test(
        'should create embedded document if standalone option passed to '
        'constructor is false',
        skip: needsParser,
        () {
          final doc = Document('= Document Title\n\ncontent', {
            'standalone': false,
          }).parse();
          expect(doc.hasAttr('embedded'), isTrue);
          final result = doc.convert() as String;
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 0);
          assertXpath('/*[@id="header"]', result, 0);
          assertXpath('/*[@id="footer"]', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
        },
      );

      test(
        'should create embedded document if standalone option passed to '
        'convert method is false',
        skip: needsParser,
        () {
          final doc = Document('= Document Title\n\ncontent', {
            'standalone': true,
          }).parse();
          expect(doc.hasAttr('embedded'), isFalse);
          final result = doc.convert({'standalone': false}) as String;
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 1);
          assertXpath('/*[@id="header"]', result, 0);
          assertXpath('/*[@id="footer"]', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
        },
      );

      test(
        'should create embedded document if deprecated header_footer '
        'option is false',
        skip: needsParser,
        () {
          final doc = Document('= Document Title\n\ncontent', {
            'header_footer': false,
          }).parse();
          expect(doc.hasAttr('embedded'), isTrue);
          final result = doc.convert() as String;
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 0);
          assertXpath('/*[@id="header"]', result, 0);
          assertXpath('/*[@id="footer"]', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
        },
      );

      test(
        'should create embedded document if header_footer option passed '
        'to convert method is false',
        skip: needsParser,
        () {
          final doc = Document('= Document Title\n\ncontent', {
            'header_footer': true,
          }).parse();
          expect(doc.hasAttr('embedded'), isFalse);
          final result = doc.convert({'header_footer': false}) as String;
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 1);
          assertXpath('/*[@id="header"]', result, 0);
          assertXpath('/*[@id="footer"]', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
        },
      );

      test(
        'enable title in embedded document by unassigning notitle attribute',
        skip: needsParser,
        () {
          const input = '= Document Title\n\ncontent\n';
          final result = convertStringToEmbedded(input, {
            'attributes': {'notitle!': ''},
          });
          assertXpath('/html', result, 0);
          assertXpath('/h1', result, 1);
          assertXpath('/*[@id="header"]', result, 0);
          assertXpath('/*[@id="footer"]', result, 0);
          assertXpath('/*[@class="paragraph"]', result, 1);
          assertXpath('(/*)[1]/self::h1', result, 1);
          assertXpath('(/*)[2]/self::*[@class="paragraph"]', result, 1);
        },
      );

      test(
        'should be able to enable doctitle for embedded document',
        skip: needsParser,
        () {
          final cases = <List<Object?>>[
            [
              {'notitle': null},
              null,
            ],
            [
              {'notitle': null},
              [':!showtitle:'],
            ],
            [
              {'notitle': false},
              null,
            ],
            [
              {'notitle': '@'},
              [':!notitle:'],
            ],
            [
              {'notitle': '@'},
              [':showtitle:'],
            ],
            [
              {'showtitle': ''},
              [':notitle:'],
            ],
            [
              {'showtitle': '@'},
              null,
            ],
            [
              {'showtitle': false},
              [':!notitle:'],
            ],
            [
              <String, Object?>{},
              [':!notitle:'],
            ],
            [
              <String, Object?>{},
              [':notitle:', ':showtitle:'],
            ],
            [
              <String, Object?>{},
              [':showtitle:'],
            ],
            [
              <String, Object?>{},
              [':!showtitle:', ':!notitle:'],
            ],
          ];
          for (final entry in cases) {
            final apiAttrs = entry[0] as Map<String, Object?>;
            final attrEntries = entry[1] as List<String>?;
            final input =
                '= Document Title${attrEntries == null ? '' : '\n${attrEntries.join('\n')}'}'
                '\n\nifdef::showtitle[showtitle: set]\n'
                'ifndef::showtitle[showtitle: not set]\n'
                'ifdef::notitle[notitle: set]\n'
                'ifndef::notitle[notitle: not set]\n';
            final result = convertStringToEmbedded(input, {
              'attributes': apiAttrs,
            });
            assertXpath('/html', result, 0);
            assertXpath('/h1', result, 1);
            assertXpath('(/*)[1]/self::h1', result, 1);
            assertXpath('(/*)[2]/self::*[@class="paragraph"]', result, 1);
            // NOTE showtitle may not match notitle if never used
            expect(result, contains('notitle: not set'));
          }
        },
      );

      test(
        'should be able to explicitly disable doctitle for embedded document',
        skip: needsParser,
        () {
          final cases = <List<Object?>>[
            [
              {'notitle': ''},
              null,
            ],
            [
              {'notitle': '@'},
              null,
            ],
            [
              {'notitle': '@'},
              [':!showtitle:'],
            ],
            [
              {'showtitle': null},
              null,
            ],
            [
              {'showtitle': false},
              null,
            ],
            [
              {'showtitle': '@'},
              [':notitle:'],
            ],
            [
              <String, Object?>{},
              [':notitle:'],
            ],
            [
              <String, Object?>{},
              [':!showtitle:'],
            ],
            [
              <String, Object?>{},
              [':!showtitle:', ':notitle:'],
            ],
          ];
          for (final entry in cases) {
            final apiAttrs = entry[0] as Map<String, Object?>;
            final attrEntries = entry[1] as List<String>?;
            final input =
                '= Document Title${attrEntries == null ? '' : '\n${attrEntries.join('\n')}'}'
                '\n\nifdef::showtitle[showtitle: set]\n'
                'ifndef::showtitle[showtitle: not set]\n'
                'ifdef::notitle[notitle: set]\n'
                'ifndef::notitle[notitle: not set]\n';
            final result = convertStringToEmbedded(input, {
              'attributes': apiAttrs,
            });
            assertXpath('/html', result, 0);
            assertXpath('/h1', result, 0);
            assertXpath('/*[@class="paragraph"]', result, 1);
            // NOTE showtitle may not match notitle if never used
            expect(result, contains('notitle: set'));
          }
        },
      );

      test('parse header only', skip: needsParser, () {
        const input = '= Document Title\nAuthor Name\n:foo: bar\n\npreamble\n';
        final doc = documentFromString(input, {'parse_header_only': true});
        expect(doc.doctitle(), equals('Document Title'));
        expect(doc.author, equals('Author Name'));
        expect(doc.attributes['foo'], equals('bar'));
        // There would be at least 1 block had it parsed beyond the header.
        expect(doc.blocks.length, equals(0));
      });

      test('should parse header only when docytpe is manpage', skip: needsParser, () {
        const input =
            '= cmd(1)\nAuthor Name\n:doctype: manpage\n\n== Name\n\ncmd - does stuff\n';
        final doc = documentFromString(input, {'parse_header_only': true});
        expect(doc.doctitle(), equals('cmd(1)'));
        expect(doc.author, equals('Author Name'));
        expect(doc.attributes['mantitle'], equals('cmd'));
        expect(doc.attributes['manvolnum'], equals('1'));
        expect(doc.attributes['manname'], isNull);
        expect(doc.attributes['manpurpose'], isNull);
        expect(doc.blocks.length, equals(0));
      });

      test(
        'should not warn when parsing header only when docytpe is manpage '
        'and body is empty',
        skip: needsParser,
        () {
          const input = '= cmd(1)\nAuthor Name\n:doctype: manpage\n';
          usingMemoryLogger((logger) {
            final doc = documentFromString(input, {'parse_header_only': true});
            expect(logger.messages, isEmpty);
            expect(doc.doctitle(), equals('cmd(1)'));
            expect(doc.author, equals('Author Name'));
            expect(doc.attributes['mantitle'], equals('cmd'));
            expect(doc.attributes['manvolnum'], equals('1'));
            expect(doc.attributes['manname'], isNull);
            expect(doc.attributes['manpurpose'], isNull);
            expect(doc.blocks.length, equals(0));
          });
        },
      );

      test('outputs footnotes in footer', skip: needsParser, () {
        const input =
            'A footnote footnote:[An example footnote.];\n'
            'a second footnote with a reference ID footnote:note2[Second footnote.];\n'
            'and finally a reference to the second footnote footnote:note2[].\n';
        final output = convertString(input);
        assertCss('#footnotes', output, 1);
        assertCss('#footnotes .footnote', output, 2);
        assertCss('#footnotes .footnote#_footnotedef_1', output, 1);
        assertXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_1"]/a[@href="#_footnoteref_1"][text()="1"]',
          output,
          1,
        );
        final text1 = xmlnodesAtXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_1"]/text()',
          output,
        );
        expect(
          (text1 as dynamic).text.toString().trim(),
          equals('. An example footnote.'),
        );
        assertCss('#footnotes .footnote#_footnotedef_2', output, 1);
        assertXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_2"]/a[@href="#_footnoteref_2"][text()="2"]',
          output,
          1,
        );
        final text2 = xmlnodesAtXpath(
          '//div[@id="footnotes"]/div[@id="_footnotedef_2"]/text()',
          output,
        );
        expect(
          (text2 as dynamic).text.toString().trim(),
          equals('. Second footnote.'),
        );
      });

      test(
        'outputs footnotes block in embedded document by default',
        skip: needsParser,
        () {
          const input =
              'Text that has supporting information{empty}footnote:[An example footnote.].';
          final output = convertStringToEmbedded(input);
          assertCss('#footnotes', output, 1);
          assertCss('#footnotes .footnote', output, 1);
          assertCss('#footnotes .footnote#_footnotedef_1', output, 1);
          assertXpath(
            '/div[@id="footnotes"]/div[@id="_footnotedef_1"]/a[@href="#_footnoteref_1"][text()="1"]',
            output,
            1,
          );
          final text = xmlnodesAtXpath(
            '/div[@id="footnotes"]/div[@id="_footnotedef_1"]/text()',
            output,
          );
          expect(
            (text as dynamic).text.toString().trim(),
            equals('. An example footnote.'),
          );
        },
      );

      test(
        'does not output footnotes block in embedded document if '
        'nofootnotes attribute is set',
        skip: needsParser,
        () {
          const input =
              'Text that has supporting information{empty}footnote:[An example footnote.].';
          final output = convertStringToEmbedded(input, {
            'attributes': {'nofootnotes': ''},
          });
          assertCss('#footnotes', output, 0);
        },
      );
    });

    group('Catalog', () {
      test(
        'should alias document catalog as document references',
        skip: needsParser,
        () {
          const input =
              '= Document Title\n\n== Section A\n\nContent\n\n== Section B\n\nContent.footnote:[commentary]\n';
          final doc = documentFromString(input);
          expect(doc.catalog, isNotNull);
          expect(
            (doc.catalog.keys.toList()..sort()),
            orderedEquals([
              'callouts',
              'footnotes',
              'ids',
              'images',
              'includes',
              'links',
              'refs',
            ]),
          );
          expect(doc.catalog, same(doc.references));
          expect(doc.catalog['footnotes'], same(doc.references['footnotes']));
          expect(doc.catalog['refs'], same(doc.references['refs']));
          expect(doc.resolveId('Section A'), equals('_section_a'));
        },
      );

      test('should return empty :ids table', () {
        final doc = emptyDocument();
        expect(doc.catalog['ids'], isNotNull);
        expect(doc.catalog['ids'] as Map, isEmpty);
        expect((doc.catalog['ids'] as Map<String, Object?>)['foobar'], isNull);
      });

      test(
        'should register entry in :refs table with reftext when request is '
        'made to register entry in :ids table',
        skip: 'needs Substitutors.apply_reftext_subs (substitutors wave)',
        () {
          final doc = emptyDocument();
          doc.register('ids', ['foobar', 'Foo Bar']);
          expect(doc.catalog['ids'] as Map, isEmpty);
          expect(doc.catalog['refs'] as Map, isNotEmpty);
          final ref =
              (doc.catalog['refs'] as Map<String, Object?>)['foobar'] as Inline;
          expect(ref.reftext, equals('Foo Bar'));
          expect(doc.resolveId('Foo Bar'), equals('foobar'));
        },
      );

      test('should return nil if there is already an entry for ID in the '
          ':refs table', () {
        final doc = emptyDocument();
        final ref = <Object?>[
          'tigers',
          Inline(
            doc,
            'anchor',
            text: '[tigers]',
            type: 'ref',
            target: 'tigers',
          ),
          '[tigers]',
        ];
        expect(doc.register('refs', ref), same(ref[1]));
        expect(doc.register('refs', ref), isNull);
      });

      test('should record imagesdir when image is registered with catalog', () {
        final doc = emptyDocument({
          'attributes': {'imagesdir': 'img'},
          'catalog_assets': true,
        });
        doc.register('images', 'diagram.svg');
        final images = doc.catalog['images'] as List<ImageReference>;
        expect(images.length, equals(1));
        expect(images[0].target, equals('diagram.svg'));
        expect(images[0].imagesdir, equals('img'));
      });

      test(
        'should catalog assets inside nested document',
        skip: needsParser,
        () {
          const input =
              'image::outer.png[]\n\n|===\na|\nimage::inner.png[]\n|===\n';
          final doc = documentFromString(input, {'catalog_assets': true});
          final images = doc.catalog['images'] as List<ImageReference>;
          expect(images, isNotEmpty);
          expect(images.length, equals(2));
          expect(
            images.map((image) => image.target).toList(),
            orderedEquals(['outer.png', 'inner.png']),
          );
        },
      );
    });

    group('Backends and Doctypes', () {
      test('html5 backend doctype article', skip: needsParser, () {
        final result = convertString('= Title\n\nparagraph', {
          'attributes': {'backend': 'html5'},
        });
        assertXpath('/html', result, 1);
        assertXpath('/html/body[@class="article"]', result, 1);
        assertXpath('/html//*[@id="header"]/h1[text()="Title"]', result, 1);
        assertXpath(
          '/html//*[@id="content"]//p[text()="paragraph"]',
          result,
          1,
        );
      });

      test('html5 backend doctype book', skip: needsParser, () {
        final result = convertString('= Title\n\nparagraph', {
          'attributes': {'backend': 'html5', 'doctype': 'book'},
        });
        assertXpath('/html', result, 1);
        assertXpath('/html/body[@class="book"]', result, 1);
        assertXpath('/html//*[@id="header"]/h1[text()="Title"]', result, 1);
        assertXpath(
          '/html//*[@id="content"]//p[text()="paragraph"]',
          result,
          1,
        );
      });

      test('xhtml5 backend should map to html5 and set htmlsyntax to xml', () {
        const input = 'content';
        final doc = documentFromString(input, {
          'backend': 'xhtml5',
          'parse': false,
        });
        expect(doc.backend, equals('html5'));
        expect(doc.attr('htmlsyntax'), equals('xml'));
      });

      test('xhtml backend should map to html5 and set htmlsyntax to xml', () {
        const input = 'content';
        final doc = documentFromString(input, {
          'backend': 'xhtml',
          'parse': false,
        });
        expect(doc.backend, equals('html5'));
        expect(doc.attr('htmlsyntax'), equals('xml'));
      });

      test(
        'honor htmlsyntax attribute passed via API if backend is html',
        skip: needsParser,
        () {
          const input = '---';
          final doc = documentFromString(input, {
            'safe': 'safe',
            'attributes': {'htmlsyntax': 'xml'},
          });
          expect(doc.backend, equals('html5'));
          expect(doc.attr('htmlsyntax'), equals('xml'));
          final result = doc.convert({'standalone': false}) as String;
          expect(result, equals('<hr/>'));
        },
      );

      test(
        'honor htmlsyntax attribute in document header if followed by '
        'backend attribute',
        skip: needsParser,
        () {
          const input = ':htmlsyntax: xml\n:backend: html5\n\n---\n';
          final doc = documentFromString(input, {'safe': 'safe'});
          expect(doc.backend, equals('html5'));
          expect(doc.attr('htmlsyntax'), equals('xml'));
          final result = doc.convert({'standalone': false}) as String;
          expect(result, equals('<hr/>'));
        },
      );

      test(
        'does not honor htmlsyntax attribute in document header if not '
        'followed by backend attribute',
        skip: needsParser,
        () {
          const input = ':backend: html5\n:htmlsyntax: xml\n\n---\n';
          final result = convertStringToEmbedded(input, {'safe': 'safe'});
          expect(result, equals('<hr>'));
        },
      );

      test(
        'should close all short tags when htmlsyntax is xml',
        skip: needsParser,
        () {
          const input =
              '= Document Title\nAuthor Name\nv1.0, 2001-01-01\n:icons:\n:favicon:\n\n'
              'image:tiger.png[]\n\nimage::tiger.png[]\n\n* [x] one\n* [ ] two\n\n'
              '|===\n|A |B\n|===\n\n[horizontal, labelwidth="25%", itemwidth="75%"]\n'
              'term:: description\n\nNOTE: note\n\n[quote,Author,Source]\n____\nQuote me.\n____\n\n'
              '[verse,Author,Source]\n____\nA tall tale.\n____\n\n[options="autoplay,loop"]\n'
              'video::screencast.ogg[]\n\nvideo::12345[vimeo]\n\n[options="autoplay,loop"]\n'
              'audio::podcast.ogg[]\n\none +\ntwo\n\n\'\'\'\n';
          final result = convertString(input, {
            'safe': 'safe',
            'backend': 'xhtml',
          });
          // XML-match wave: parse result as strict XML; flunk with the
          // parser message and result when not well-formed.
          expect(result, isNotEmpty);
        },
      );

      test(
        'xhtml backend should emit elements in proper namespace',
        skip: needsParser,
        () {
          const input = 'content';
          final result = convertString(input, {
            'safe': 'safe',
            'backend': 'xhtml',
            'keep_namespaces': true,
          });
          assertXpath(
            '//*[not(namespace-uri()="http://www.w3.org/1999/xhtml")]',
            result,
            0,
          );
        },
      );

      test(
        'should parse out subtitle when backend is DocBook',
        skip: needsParser,
        () {
          const input = '= Document Title: Subtitle\n:doctype: book\n\ntext\n';
          final result = convertString(input, {'backend': 'docbook5'});
          assertXpath('/book', result, 1);
          assertXpath('/book/info/title[text()="Document Title"]', result, 1);
          assertXpath('/book/info/subtitle[text()="Subtitle"]', result, 1);
        },
      );

      test(
        'should be able to set doctype to article when converting to DocBook',
        skip: needsParser,
        () {
          const input =
              '= Title\nAuthor Name\n\npreamble\n\n== First Section\n\nsection body\n';
          final result = convertString(input, {
            'keep_namespaces': true,
            'attributes': {'backend': 'docbook5'},
          });
          assertXpath('/xmlns:article', result, 1);
          final doc = xmlnodesAtXpath('/xmlns:article', result, 1);
          expect(
            (doc as dynamic).namespaces['xmlns'],
            equals('http://docbook.org/ns/docbook'),
          );
          expect(
            (doc as dynamic).namespaces['xmlns:xl'],
            equals('http://www.w3.org/1999/xlink'),
          );
          assertXpath('/xmlns:article[@version="5.0"]', result, 1);
          assertXpath(
            '/xmlns:article/xmlns:info/xmlns:title[text()="Title"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:simpara[text()="preamble"]',
            result,
            1,
          );
          assertXpath('/xmlns:article/xmlns:section', result, 1);
          assertCss(
            'article:root > section[xml|id="_first_section"]',
            result,
            1,
          );
        },
      );

      test(
        'should set doctype to article by default for document with no '
        'title when converting to DocBook',
        skip: needsParser,
        () {
          final result = convertString('text', {
            'attributes': {'backend': 'docbook'},
          });
          assertXpath('/article', result, 1);
          assertXpath('/article/info/title', result, 1);
          assertXpath('/article/info/title[text()="Untitled"]', result, 1);
          assertXpath('/article/info/date', result, 1);
        },
      );

      test(
        'should be able to convert DocBook manpage output when backend is '
        'DocBook and doctype is manpage',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n:mansource: Asciidoctor\n:manmanual: Asciidoctor Manual\n\n'
              '== NAME\n\nasciidoctor - Process text\n\n== SYNOPSIS\n\nsome text\n\n'
              '== First Section\n\nsection body\n';
          final result = convertString(input, {
            'keep_namespaces': true,
            'attributes': {'backend': 'docbook5', 'doctype': 'manpage'},
          });
          assertXpath('/xmlns:article', result, 1);
          assertXpath('/xmlns:article/xmlns:refentry', result, 1);
          final doc = xmlnodesAtXpath('/xmlns:article', result, 1);
          expect(
            (doc as dynamic).namespaces['xmlns'],
            equals('http://docbook.org/ns/docbook'),
          );
          expect(
            (doc as dynamic).namespaces['xmlns:xl'],
            equals('http://www.w3.org/1999/xlink'),
          );
          expect((doc as dynamic).attr('version'), equals('5.0'));
          assertXpath(
            '/xmlns:article/xmlns:info/xmlns:title[text()="asciidoctor(1)"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refentrytitle[text()="asciidoctor"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:manvolnum[text()="1"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="source"][text()="Asciidoctor"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="manual"][text()="Asciidoctor Manual"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refnamediv/xmlns:refname[text()="asciidoctor"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refnamediv/xmlns:refpurpose[text()="Process text"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refsynopsisdiv',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refsynopsisdiv/xmlns:simpara[text()="some text"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refsection',
            result,
            1,
          );
          assertCss(
            'article:root > refentry > refsection[xml|id="_first_section"]',
            result,
            1,
          );
        },
      );

      test(
        'should output non-breaking space for source and manual in docbook '
        'manpage output if absent from source',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n\n== NAME\n\nasciidoctor - Process text\n\n== SYNOPSIS\n\nsome text\n';
          final result = convertString(input, {
            'keep_namespaces': true,
            'attributes': {'backend': 'docbook5', 'doctype': 'manpage'},
          });
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="source"][text()="${decodeChar(160)}"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refmiscinfo[@class="manual"][text()="${decodeChar(160)}"]',
            result,
            1,
          );
        },
      );

      test(
        'should apply replacements substitution to value of mantitle '
        'attribute used in DocBook output',
        skip: needsParser,
        () {
          const input =
              '= foo\\--bar(1)\nAuthor Name\n:doctype: manpage\n:man manual: Foo Bar Manual\n'
              ':man source: Foo Bar 1.0\n\n== NAME\n\nfoo--bar - puts the foo in your bar\n';
          final doc = asciidoctorLoad(
            input,
            backend: 'docbook',
            standalone: true,
          );
          expect(doc.attr('mantitle'), equals('foo\\--bar'));
          final result = doc.convert() as String;
          assertXpath(
            '/xmlns:article/xmlns:info/xmlns:title[text()="foo--bar(1)"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:article/xmlns:refentry/xmlns:refmeta/xmlns:refentrytitle[text()="foo--bar"]',
            result,
            1,
          );
        },
      );

      test(
        'should be able to set doctype to book when converting to DocBook',
        skip: needsParser,
        () {
          const input =
              '= Title\nAuthor Name\n\npreamble\n\n== First Chapter\n\nchapter body\n';
          final result = convertString(input, {
            'keep_namespaces': true,
            'attributes': {'backend': 'docbook5', 'doctype': 'book'},
          });
          assertXpath('/xmlns:book', result, 1);
          final doc = xmlnodesAtXpath('/xmlns:book', result, 1);
          expect(
            (doc as dynamic).namespaces['xmlns'],
            equals('http://docbook.org/ns/docbook'),
          );
          expect(
            (doc as dynamic).namespaces['xmlns:xl'],
            equals('http://www.w3.org/1999/xlink'),
          );
          assertXpath('/xmlns:book[@version="5.0"]', result, 1);
          assertXpath(
            '/xmlns:book/xmlns:info/xmlns:title[text()="Title"]',
            result,
            1,
          );
          assertXpath(
            '/xmlns:book/xmlns:preface/xmlns:simpara[text()="preamble"]',
            result,
            1,
          );
          assertXpath('/xmlns:book/xmlns:chapter', result, 1);
          assertCss('book:root > chapter[xml|id="_first_chapter"]', result, 1);
        },
      );

      test(
        'should be able to set doctype to book for document with no title '
        'when converting to DocBook',
        skip: needsParser,
        () {
          final result = convertString('text', {
            'attributes': {'backend': 'docbook5', 'doctype': 'book'},
          });
          assertXpath('/book', result, 1);
          assertXpath('/book/info/date', result, 1);
          // NOTE simpara cannot be a direct child of book, so content must
          // be treated as a preface.
          assertXpath('/book/preface/simpara[text()="text"]', result, 1);
        },
      );

      test(
        'adds refname to DocBook output for each name defined in NAME '
        'section of manpage',
        skip: needsParser,
        () {
          const input =
              '= eve(1)\nAndrew Stanton\nv1.0.0\n:doctype: manpage\n:manmanual: EVE\n:mansource: EVE\n\n'
              '== NAME\n\neve, islifeform - analyzes an image to determine if it\'s a picture of a life form\n\n'
              '== SYNOPSIS\n\n*eve* [\'OPTION\']... \'FILE\'...\n';
          final result = convertString(input, {'backend': 'docbook5'});
          assertXpath('/article/refentry/refnamediv/refname', result, 2);
          assertXpath(
            '(/article/refentry/refnamediv/refname)[1][text()="eve"]',
            result,
            1,
          );
          assertXpath(
            '(/article/refentry/refnamediv/refname)[2][text()="islifeform"]',
            result,
            1,
          );
        },
      );

      test(
        'adds a front and back cover image to DocBook 5 when doctype is book',
        skip: needsParser,
        () {
          const input =
              '= Title\n:doctype: book\n:imagesdir: images\n'
              ':front-cover-image: image:front-cover.jpg[scaledwidth=210mm]\n'
              ':back-cover-image: image:back-cover.jpg[]\n\npreamble\n\n'
              '== First Chapter\n\nchapter body\n';
          final result = convertString(input, {
            'attributes': {'backend': 'docbook5'},
          });
          assertXpath('//info/cover[@role="front"]', result, 1);
          assertXpath(
            '//info/cover[@role="front"]//imagedata[@fileref="images/front-cover.jpg"]',
            result,
            1,
          );
          assertXpath('//info/cover[@role="back"]', result, 1);
          assertXpath(
            '//info/cover[@role="back"]//imagedata[@fileref="images/back-cover.jpg"]',
            result,
            1,
          );
        },
      );

      test('should be able to set backend using :backend option key', () {
        final doc = emptyDocument({'backend': 'html5'});
        expect(doc.attributes['backend'], equals('html5'));
      });

      test(':backend option should override backend attribute', () {
        final doc = emptyDocument({
          'backend': 'html5',
          'attributes': {'backend': 'docbook5'},
        });
        expect(doc.attributes['backend'], equals('html5'));
      });

      test('should be able to set doctype using :doctype option key', () {
        final doc = emptyDocument({'doctype': 'book'});
        expect(doc.attributes['doctype'], equals('book'));
      });

      test(':doctype option should override doctype attribute', () {
        final doc = emptyDocument({
          'doctype': 'book',
          'attributes': {'doctype': 'article'},
        });
        expect(doc.attributes['doctype'], equals('book'));
      });

      test('do not override explicit author initials', skip: needsParser, () {
        const input =
            '= AsciiDoc\nStuart Rackham <founder@asciidoc.org>\n:Author Initials: SJR\n\nmore info...\n';
        final output = convertString(input, {
          'attributes': {'backend': 'docbook5'},
        });
        assertXpath('/article/info/authorinitials[text()="SJR"]', output, 1);
      });

      test(
        'attribute entry can appear immediately after document title',
        skip: needsParser,
        () {
          const input = 'Reference Guide\n===============\n:toc:\n\npreamble\n';
          final doc = documentFromString(input);
          expect(doc.hasAttr('toc'), isTrue);
          expect(doc.attr('toc'), equals(''));
        },
      );

      test(
        'attribute entry can appear before author line under document title',
        skip: needsParser,
        () {
          const input =
              'Reference Guide\n===============\n:toc:\nDan Allen\n\npreamble\n';
          final doc = documentFromString(input);
          expect(doc.hasAttr('toc'), isTrue);
          expect(doc.attr('toc'), equals(''));
          expect(doc.attr('author'), equals('Dan Allen'));
        },
      );

      test(
        'should parse mantitle and manvolnum from document title for '
        'manpage doctype',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor ( 1 )\n:doctype: manpage\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n';
          final doc = documentFromString(input);
          expect(doc.attr('mantitle'), equals('asciidoctor'));
          expect(doc.attr('manvolnum'), equals('1'));
        },
      );

      test(
        'should perform attribute substitution on mantitle in manpage doctype',
        skip: needsParser,
        () {
          const input =
              '= {app}(1)\n:doctype: manpage\n:app: Asciidoctor\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n';
          final doc = documentFromString(input);
          expect(doc.attr('mantitle'), equals('asciidoctor'));
        },
      );

      test(
        'should consume name section as manname and manpurpose for manpage '
        'doctype',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n:doctype: manpage\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n';
          final doc = documentFromString(input);
          expect(doc.attr('manname'), equals('asciidoctor'));
          expect(
            doc.attr('manpurpose'),
            equals(
              'converts AsciiDoc source files to HTML, DocBook and other formats',
            ),
          );
          expect(doc.attr('manname-id'), equals('_name'));
          expect(doc.blocks.length, equals(0));
        },
      );

      test(
        'should set docname and outfilesuffix from manname and manvolnum '
        'for manpage backend and doctype',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n:doctype: manpage\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n';
          final doc = documentFromString(input, {'backend': 'manpage'});
          expect(doc.attributes['docname'], equals('asciidoctor'));
          expect(doc.attributes['outfilesuffix'], equals('.1'));
        },
      );

      test(
        'should mark synopsis as special section in manpage doctype',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n:doctype: manpage\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n\n'
              '== SYNOPSIS\n\n*asciidoctor* [\'OPTION\']... \'FILE\'..\n';
          final doc = documentFromString(input);
          final synopsisSection = doc.blocks.first as Section;
          expect(synopsisSection.context, equals('section'));
          expect(synopsisSection.special, isTrue);
          expect(synopsisSection.sectname, equals('synopsis'));
        },
      );

      test(
        'should output special header block in HTML for manpage doctype',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n:doctype: manpage\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n\n'
              '== SYNOPSIS\n\n*asciidoctor* [\'OPTION\']... \'FILE\'..\n';
          final output = convertString(input);
          assertCss('body.manpage', output, 1);
          assertXpath(
            '//body/*[@id="header"]/h1[text()="asciidoctor(1) Manual Page"]',
            output,
            1,
          );
          assertXpath(
            '//body/*[@id="header"]/h1/following-sibling::h2[text()="NAME"]',
            output,
            1,
          );
          assertXpath('//h2[@id="_name"][text()="NAME"]', output, 1);
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]',
            output,
            1,
          );
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]/p[text()="asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats"]',
            output,
            1,
          );
          assertXpath(
            '//*[@id="content"]/*[@class="sect1"]/h2[text()="SYNOPSIS"]',
            output,
            1,
          );
        },
      );

      test(
        'should output special header block in embeddable HTML for manpage '
        'doctype',
        skip: needsParser,
        () {
          const input =
              '= asciidoctor(1)\n:doctype: manpage\n:showtitle:\n\n== NAME\n\nasciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats\n\n'
              '== SYNOPSIS\n\n*asciidoctor* [\'OPTION\']... \'FILE\'..\n';
          final output = convertStringToEmbedded(input);
          assertXpath('/h1[text()="asciidoctor(1) Manual Page"]', output, 1);
          assertXpath('/h1/following-sibling::h2[text()="NAME"]', output, 1);
          assertXpath('//h2[@id="_name"][text()="NAME"]', output, 1);
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]',
            output,
            1,
          );
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]/p[text()="asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats"]',
            output,
            1,
          );
        },
      );

      test(
        'should output all mannames in name section in man page output',
        skip: needsParser,
        () {
          const input =
              '= eve(1)\n:doctype: manpage\n\n== NAME\n\neve, probe - analyzes an image to determine if it is a picture of a life form\n\n'
              '== SYNOPSIS\n\n*eve* [OPTION]... FILE...\n';
          final output = convertString(input);
          assertCss('body.manpage', output, 1);
          assertXpath(
            '//h2[text()="NAME"]/following-sibling::*[@class="sectionbody"]/p[text()="eve, probe - analyzes an image to determine if it is a picture of a life form"]',
            output,
            1,
          );
        },
      );
    });

    group('Secure Asset Path', () {
      test('allows us to specify a path relative to the current dir', () {
        final doc = emptyDocument();
        final legitPath = '${Directory.current.path}/foo';
        expect(doc.normalizeAssetPath(legitPath), equals(legitPath));
      });

      test('keeps naughty absolute paths from getting outside', () {
        const naughtyPath = '/etc/passwd';
        usingMemoryLogger((logger) {
          final doc = emptyDocument();
          final securePath = doc.normalizeAssetPath(naughtyPath);
          expect(securePath, isNot(equals(naughtyPath)));
          expect(securePath, equals('${doc.baseDir}/etc/passwd'));
          expect(logger.warns, hasLength(1));
          expect(
            logger.warns.single,
            equals('path is outside of jail; recovering automatically'),
          );
        });
      });

      test('keeps naughty relative paths from getting outside', () {
        const naughtyPath = 'safe/ok/../../../../../etc/passwd';
        usingMemoryLogger((logger) {
          final doc = emptyDocument();
          final securePath = doc.normalizeAssetPath(naughtyPath);
          expect(securePath, isNot(equals(naughtyPath)));
          expect(securePath, startsWith('${doc.baseDir}/'));
        });
      });

      test('should raise an exception when a converter cannot be resolved '
          'before conversion', () {
        const input = '= Document Title\n\ntext\n';
        expect(
          () => Document(input, {'backend': 'unknownBackend'}),
          throwsA(
            isA<UnimplementedError>().having(
              (error) => error.message,
              'message',
              contains("missing converter for backend 'unknownBackend'"),
            ),
          ),
        );
      });

      test('should raise an exception when a converter cannot be resolved '
          'while parsing', () {
        const input = '= Document Title\n\n== A _Big_ Section\n\ntext\n';
        expect(
          () => Document(input, {'backend': 'unknownBackend'}),
          throwsA(
            isA<UnimplementedError>().having(
              (error) => error.message,
              'message',
              contains("missing converter for backend 'unknownBackend'"),
            ),
          ),
        );
      });
    });

    group('Date time attributes', () {
      test(
        'should compute docyear and docdatetime from docdate and doctime',
        () {
          final doc = Document(<String>[], {
            'attributes': {'docdate': '2015-01-01', 'doctime': '10:00:00-0700'},
          });
          expect(doc.attr('docdate'), equals('2015-01-01'));
          expect(doc.attr('docyear'), equals('2015'));
          expect(doc.attr('doctime'), equals('10:00:00-0700'));
          expect(doc.attr('docdatetime'), equals('2015-01-01 10:00:00-0700'));
        },
      );

      test('should allow docdate and doctime to be overridden', () {
        final doc = Document(<String>[], {
          'input_mtime': DateTime.now(),
          'attributes': {'docdate': '2015-01-01', 'doctime': '10:00:00-0700'},
        });
        expect(doc.attr('docdate'), equals('2015-01-01'));
        expect(doc.attr('docyear'), equals('2015'));
        expect(doc.attr('doctime'), equals('10:00:00-0700'));
        expect(doc.attr('docdatetime'), equals('2015-01-01 10:00:00-0700'));
      });

      test('should compute docdatetime from doctime', () {
        final doc = Document(<String>[], {
          'attributes': {'doctime': '10:00:00-0700'},
        });
        expect(doc.attr('doctime'), equals('10:00:00-0700'));
        expect(doc.attr('docdatetime') as String, endsWith(' 10:00:00-0700'));
      });

      test('should compute docyear from docdate', () {
        final doc = Document(<String>[], {
          'attributes': {'docdate': '2015-01-01'},
        });
        expect(doc.attr('docyear'), equals('2015'));
        expect(doc.attr('docdatetime') as String, startsWith('2015-01-01 '));
      });

      test('should allow doctime to be overridden', () {
        // NOTE Dart cannot unset SOURCE_DATE_EPOCH (Platform.environment is
        // read-only); this test assumes it is not set, as in the Ruby test
        // which deletes it first.
        final doc = Document(<String>[], {
          'input_mtime': DateTime(2019, 1, 2, 3, 4, 5),
          'attributes': {'doctime': '10:00:00-0700'},
        });
        expect(doc.attr('docdate'), equals('2019-01-02'));
        expect(doc.attr('docyear'), equals('2019'));
        expect(doc.attr('doctime'), equals('10:00:00-0700'));
        expect(doc.attr('docdatetime'), equals('2019-01-02 10:00:00-0700'));
      });

      test('should allow docdate to be overridden', () {
        // NOTE Dart cannot unset SOURCE_DATE_EPOCH (Platform.environment is
        // read-only); this test assumes it is not set, as in the Ruby test
        // which deletes it first. Dart also has no fixed-offset DateTime,
        // so the expected offset is derived from the input value; a UTC
        // input additionally locks the exact 'UTC' rendering.
        final input = DateTime(2019, 1, 2, 3, 4, 5);
        final doc = Document(<String>[], {
          'input_mtime': input,
          'attributes': {'docdate': '2015-01-01'},
        });
        expect(doc.attr('docdate'), equals('2015-01-01'));
        expect(doc.attr('docyear'), equals('2015'));
        final offset = input.timeZoneOffset;
        final zone = offset == Duration.zero
            ? 'UTC'
            : '${offset.isNegative ? '-' : '+'}'
                  '${offset.inHours.abs().toString().padLeft(2, '0')}'
                  '${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
        expect(doc.attr('docdatetime'), equals('2015-01-01 03:04:05 $zone'));

        final utcDoc = Document(<String>[], {
          'input_mtime': DateTime.utc(2019, 1, 2, 3, 4, 5),
          'attributes': {'docdate': '2015-01-01'},
        });
        expect(utcDoc.attr('docdatetime'), equals('2015-01-01 03:04:05 UTC'));
      });
    });
  });
}
