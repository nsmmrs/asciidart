/// Tests for the converter framework port.
///
/// Covers `converter.dart` (port of `lib/asciidoctor/converter.rb`) and
/// `composite.dart` (port of `lib/asciidoctor/converter/composite.rb`).
///
/// Each `Port of` comment cites the originating test in
/// `test/converter_test.rb`. Most ported tests use fake converters and
/// directly-constructed fake nodes (no parsing); the `converter` /
/// `converter_factory` / `read_svg_contents` tests parse and convert for
/// real. Template-converter tests stay skipped as empty placeholders with
/// [needsTemplateConverter] until the template wave (TASK-9mfkvk) lands;
/// Ruby-metaprogramming tests with no Dart counterpart stay skipped with
/// [noDartCounterpart].
///
/// Global-registry tests clean up with `addTearDown(Converter.unregisterAll)`
/// and use unique backend names per test: `provided` registrations survive
/// `unregisterAll` by design (mirroring Ruby's `PROVIDED` map), so shared
/// names would leak between tests.
library;

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/composite.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:test/test.dart';

/// Reason for placeholder tests blocked on the template wave
/// (TASK-9mfkvk): Tilt/ERB/Haml/Slim template converters have no Dart port.
/// These stay skipped until that wave lands; do not attempt them here.
const String needsTemplateConverter =
    'template-wave-blocked (TASK-9mfkvk): needs Tilt/ERB/Haml/Slim '
    'template-converter port';

/// Reason for permanently-skipped tests with no Dart counterpart.
///
/// Ruby's converter tests lean on metaprogramming (`Module#included`
/// hooks, `method_missing` delegation with `respond_to?` probes) that
/// Dart cannot express; the behaviors themselves (handler dispatch,
/// missing-handler warnings) are covered by the ported tests around them.
const String noDartCounterpart =
    'permanent skip: Ruby metaprogramming with no Dart counterpart';

/// A minimal [Converter] returning [result] for every node.
class FakeConverter extends Converter {
  /// The value [convert] returns.
  final String result;

  /// Creates a converter returning [result] (default `'fake content'`).
  FakeConverter(super.backend, [super.opts, this.result = 'fake content']);

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) => result;
}

/// A [ConverterBase] with handlers wired through [handle].
class FakeBaseConverter extends ConverterBase {
  /// Creates a converter registering [handlers] for [backend].
  FakeBaseConverter(
    super.backend, [
    super.opts,
    Map<String, ConvertHandler> handlers = const <String, ConvertHandler>{},
  ]) {
    handlers.forEach(handle);
  }
}

/// A [Converter] that overrides nothing (pins default [Converter] behavior).
class BareConverter extends Converter {
  /// Creates a bare converter for [backend].
  BareConverter(super.backend, [super.opts]);
}

/// A block whose [content] is fixed (avoids the substitutors wave).
class StubBlock extends Block {
  /// The value [content] returns.
  final String? stubbedContent;

  /// Creates a stub block with fixed [content].
  StubBlock(super.parent, super.context, this.stubbedContent);

  @override
  String? content() => stubbedContent;
}

/// A bare node that is neither block nor inline content (for [contentOnly]).
class BareNode extends AbstractNode {
  /// Creates a bare node with node name `'bare'`.
  BareNode() : super(null, 'bare');

  @override
  bool get isBlock => false;

  @override
  bool get isInline => false;
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

/// Installs [logger] as the shared logger, restoring the previous one after.
void useLogger(FakeLogger logger) {
  final saved = AbstractNode.currentLogger;
  AbstractNode.currentLogger = logger;
  addTearDown(() {
    AbstractNode.currentLogger = saved;
  });
}

/// Registers the global registry cleanup after each test using it.
void cleanGlobalRegistry() {
  addTearDown(Converter.unregisterAll);
}

/// A custom HTML converter returning `'document'` for every node (port of
/// `CustomHtmlConverterA`).
class CustomHtmlConverterA extends Converter {
  /// Creates the converter for [backend] with [opts].
  CustomHtmlConverterA(super.backend, [super.opts]);

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) => 'document';
}

/// A custom text converter returning `'document'` for every node (port of
/// `CustomTextConverterA`).
class CustomTextConverterA extends Converter {
  /// Creates the converter for [backend] with [opts].
  CustomTextConverterA(super.backend, [super.opts]);

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) => 'document';
}

/// A custom converter handling only the `document` transform (port of the
/// anonymous `Converter::Base` subclass in the factory test).
class CustomDocumentConverter extends ConverterBase {
  /// Creates the converter for [backend] with [opts].
  CustomDocumentConverter(super.backend, [super.opts]) {
    handle('document', (node, [opts]) => 'document');
  }
}

/// Creates a document from [src] (port of `document_from_string`).
///
/// Defaults to `standalone: true` and `parse: true`, like the Ruby helper.
Document documentFromString(String src, [Map<String, Object?>? options]) {
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  opts.putIfAbsent('standalone', () => true);
  final parse = opts.remove('parse') ?? true;
  final doc = Document(src, opts);
  return (parse == true) ? doc.parse() : doc;
}

/// Resolves a fixture path (port of `fixture_path`).
String fixturePath(String name) => '../test/fixtures/$name';

void main() {
  group('Converter', () {
    group('View options', () {
      test(
        'should set Haml format to html5 for html5 backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should set Haml format to xhtml for docbook backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should configure Slim to resolve includes in specified template dirs',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should coerce template_dirs option to an Array',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should set Slim format to html for html5 backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should set Slim format to nil for docbook backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should set safe mode of Slim AsciiDoc engine to match document safe '
        'mode when Slim >= 3',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should support custom template engine options for known engine',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should support custom template engine options',
        skip: needsTemplateConverter,
        () {},
      );
    });

    group('Custom backends', () {
      test(
        'should load Haml templates for default backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should set outfilesuffix according to backend info',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should not override outfilesuffix attribute if locked',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should load Haml templates for docbook5 backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should use Haml templates in place of built-in templates',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should allow custom backend to emulate a known backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should create template converter even when a converter is not '
        'registered for the specified backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should use built-in global cache to cache templates',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should use custom cache to cache templates',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should be able to disable template cache',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should load ERB templates using ERBTemplate if eruby is not set',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should load ERB templates using ErubiTemplate if eruby is set to '
        'erubi',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should load Slim templates for default backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should load Slim templates for docbook5 backend',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should use Slim templates in place of built-in templates',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should be able to override the outline using a custom template',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'resolves templates from classloader when using JRuby',
        skip: needsTemplateConverter,
        () {},
      );
    });

    group('Custom converters', () {
      test(
        'should not expose included method on Converter class',
        // Permanent: Ruby `Module#included` hook privacy has no Dart
        // counterpart.
        skip: noDartCounterpart,
        () {},
      );

      test('should derive backend traits for the given backend', () {
        // Port of test/converter_test.rb: 'should derive backend traits for
        // the given backend'. Extra cases verified via `ruby -Ilib -e`.
        expect(
          Converter.deriveBackendTraits('dita2'),
          equals(<String, Object?>{
            'basebackend': 'dita',
            'filetype': 'dita',
            'outfilesuffix': '.dita',
          }),
        );
        expect(
          Converter.deriveBackendTraits(null),
          equals(<String, Object?>{}),
        );
        expect(
          Converter.deriveBackendTraits('html5'),
          equals(<String, Object?>{
            'basebackend': 'html',
            'filetype': 'html',
            'htmlsyntax': 'html',
            'outfilesuffix': '.html',
          }),
        );
        expect(
          Converter.deriveBackendTraits('custom', 'html'),
          equals(<String, Object?>{
            'basebackend': 'html',
            'filetype': 'html',
            'htmlsyntax': 'html',
            'outfilesuffix': '.html',
          }),
        );
        expect(
          Converter.deriveBackendTraits('manpage'),
          equals(<String, Object?>{
            'basebackend': 'manpage',
            'filetype': 'man',
            'outfilesuffix': '.man',
          }),
        );
      });

      test('should use specified converter for current backend', () {
        // Port of test/converter_test.rb: 'should use specified converter
        // for current backend'. Adapted: Dart passes a factory where Ruby
        // passes the class.
        const input = '= Document Title\n\npreamble\n\n== Section\n\ncontent\n';
        final doc = documentFromString(input, {
          'converter': CustomHtmlConverterA.new,
        });
        expect(doc.converter, isA<CustomHtmlConverterA>());
        expect(doc.attributes['filetype'], equals('html'));
        expect(doc.convert(), equals('document'));
      });
      test('should use specified converter for specified backend', () {
        // Port of test/converter_test.rb: 'should use specified converter
        // for specified backend'. Adapted: Dart passes a factory where
        // Ruby passes the class.
        const input = '= Document Title\n\npreamble\n\n== Section\n\ncontent\n';
        final doc = documentFromString(input, {
          'backend': 'text',
          'converter': CustomTextConverterA.new,
        });
        expect(doc.converter, isA<CustomTextConverterA>());
        expect(doc.attributes['filetype'], equals('text'));
        expect(doc.convert(), equals('document'));
      });

      test('should warn when convert method for node is missing', () {
        // Port of test/converter_test.rb: 'should warn when convert method
        // for node is missing'. Adapted: converts a directly-constructed
        // node instead of parsing (the Ruby `NoMethodError` half asserts
        // that `Document#convert_document` does not exist, which is
        // Document API surface, not converter behavior).
        cleanGlobalRegistry();
        final logger = FakeLogger();
        useLogger(logger);
        final converter = FakeBaseConverter('fizzbuzz');
        final node = Block(null, 'paragraph');
        expect(converter.convert(node), isNull);
        expect(logger.warns, hasLength(1));
        expect(
          logger.warns.single.toString(),
          startsWith(
            'missing convert handler for paragraph node in fizzbuzz backend (',
          ),
        );
        expect(logger.warns.single.toString(), endsWith(')'));
        expect(logger.warns.single.toString(), contains('FakeBaseConverter'));
        // An explicit transform names the transform, not the node.
        expect(converter.convert(node, 'document'), isNull);
        expect(
          logger.warns.last.toString(),
          startsWith(
            'missing convert handler for document node in fizzbuzz backend (',
          ),
        );
      });

      test('should get converter from specified converter factory', () {
        // Port of test/converter_test.rb: 'should get converter from
        // specified converter factory'. Adapted: Dart passes a factory
        // where Ruby passes the anonymous class.
        const input = '= Document Title\n\npreamble\n\n== Section\n\ncontent\n';
        final converterFactory = CustomFactory({
          'html5': CustomDocumentConverter.new,
        });
        final doc = documentFromString(input, {
          'converter_factory': converterFactory,
        });
        expect(doc.converter, isA<CustomDocumentConverter>());
        expect(doc.attributes['filetype'], equals('html'));
        expect(doc.convert(), equals('document'));
      });
      test(
        'should allow converter to set htmlsyntax when basebackend is html',
        () {
          // Port of test/converter_test.rb: 'should allow converter to set
          // htmlsyntax when basebackend is html'.
          Html5Converter.registerFor();
          addTearDown(Converter.unregisterAll);
          const input = 'image::sunset.jpg[]';
          final converter = Converter.create('html5', const {
            'htmlsyntax': 'xml',
          })!;
          final doc = documentFromString(input, {'converter': converter});
          expect(doc.converter, same(converter));
          expect(doc.attr('htmlsyntax'), equals('xml'));
          final output = doc.convert(const {'standalone': false}) as String;
          expect(output, contains('<img src="sunset.jpg" alt="sunset"/>'));
        },
      );

      test('should use converter registered for backend', () {
        // Port of test/converter_test.rb: 'should use converter registered
        // for backend'. Adapted: converts a directly-constructed node
        // instead of parsing a document.
        cleanGlobalRegistry();
        final before = Converter.converters.length;
        Converter.register(FakeConverter.new, const ['reg-backend']);
        expect(Converter.forBackend('reg-backend'), equals(FakeConverter.new));
        final converters = Converter.converters;
        expect(converters.length, before + 1);
        expect(converters['reg-backend'], equals(FakeConverter.new));
        final converter = Converter.create('reg-backend')!;
        expect(converter, isA<FakeConverter>());
        expect(converter.backend, 'reg-backend');
        converter
          ..baseBackend = 'text'
          ..fileType = 'text'
          ..outfileSuffix = '.fb';
        expect(
          converter.backendTraits(),
          equals(<String, Object?>{
            'basebackend': 'text',
            'filetype': 'text',
            'outfilesuffix': '.fb',
          }),
        );
        expect(converter.convert(Block(null, 'paragraph')), 'fake content');
      });

      test('should be able to register converter for backend name', () {
        // Port of test/converter_test.rb: 'should be able to register
        // converter using symbol'. Adapted: Dart backends are always
        // strings (Ruby coerces the symbol with `to_s`).
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['reg-name']);
        expect(Converter.forBackend('reg-name'), equals(FakeConverter.new));
      });

      test('should use basebackend to compute filetype and outfilesuffix', () {
        // Port of test/converter_test.rb: 'should use basebackend to
        // compute filetype and outfilesuffix'. Adapted: asserts the
        // converter's backend traits directly (the `doc.outfilesuffix`
        // half needs a Document).
        cleanGlobalRegistry();
        expect(Converter.forBackend('reg-slides'), isNull);
        Converter.register(
          (String backend, Map<String, Object?> opts) =>
              FakeBaseConverter(backend, opts)..baseBackend = 'html',
          const ['reg-slides'],
        );
        final converter = Converter.create('reg-slides')!;
        expect(
          converter.backendTraits(),
          equals(<String, Object?>{
            'basebackend': 'html',
            'filetype': 'html',
            'htmlsyntax': 'html',
            'outfilesuffix': '.html',
          }),
        );
      });

      test(
        'should be able to register converter from converter class itself',
        () {
          // Port of test/converter_test.rb: 'should be able to register
          // converter from converter class itself'. Adapted to the explicit
          // registration pattern: the converter class exposes a static
          // `registerFor` that calls `Converter.register` (there is no
          // class-level `register_for` DSL in Dart).
          cleanGlobalRegistry();
          expect(Converter.forBackend('reg-self'), isNull);
          _SelfRegisteringConverter.registerFor(const ['reg-self']);
          expect(
            Converter.forBackend('reg-self'),
            equals(_SelfRegisteringConverter.new),
          );
        },
      );

      test('should report handles as true on converter by default', () {
        // Port of test/converter_test.rb: 'should map handles? method on
        // converter to respond_to? implementation by default'. Adapted:
        // the Ruby fake includes only the `Converter` module (whose
        // `handles?` returns true); the Dart fake extends only `Converter`.
        final converter = BareConverter('myhtml');
        expect(converter.handles('paragraph'), isTrue);
        expect(converter.handles('convert_paragraph'), isTrue);
      });

      test(
        'should not configure converter to support templates by default',
        skip: needsTemplateConverter,
        () {},
      );
      test(
        'should wrap converter in composite converter with template converter '
        'if it declares that it supports templates',
        skip: needsTemplateConverter,
        () {},
      );

      test('should map Factory.new to DefaultFactoryProxy constructor by '
          'default', () {
        // Port of test/converter_test.rb: 'should map Factory.new to
        // DefaultFactoryProxy constructor by default'. Adapted: uses an
        // explicitly registered fake backend (no built-ins are registered
        // in the framework wave).
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['reg-proxy-default']);
        final factory = ConverterFactory();
        expect(factory, isA<DefaultFactoryProxy>());
        expect(
          factory.forBackend('reg-proxy-default'),
          equals(Converter.forBackend('reg-proxy-default')),
        );
      });

      test('should map Factory.new to CustomFactory constructor if proxy '
          'keyword arg is false', () {
        // Port of test/converter_test.rb: 'should map Factory.new to
        // CustomFactory constructor if proxy keyword arg is false'.
        // Adapted: uses an explicitly registered fake backend so the
        // lookup is meaningful (a proxy-less factory must not see it).
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['reg-proxy-off']);
        final factory = ConverterFactory(null, false);
        expect(factory, isA<CustomFactory>());
        expect(factory, isNot(isA<DefaultFactoryProxy>()));
        expect(factory.forBackend('reg-proxy-off'), isNull);
      });

      test('should default to catch all converter', () {
        // Port of test/converter_test.rb: 'should default to catch all
        // converter'. Adapted: the Ruby test relies on the lazily-loaded
        // `html5` built-in to prove explicit registrations win; the port
        // registers an explicit fake backend instead, and converts a
        // directly-constructed node instead of parsing.
        cleanGlobalRegistry();
        Converter.register(
          (String backend, Map<String, Object?> opts) =>
              FakeConverter(backend, opts, 'foobaz content'),
          const ['*'],
        );
        Converter.register(FakeConverter.new, const [
          'reg-explicit',
        ], provided: true);
        final catchAll = Converter.forBackend('catchall-all');
        expect(Converter.forBackend('catchall-whatever'), same(catchAll));
        expect(Converter.forBackend('reg-explicit'), isNot(same(catchAll)));
        expect(Converter.converters['*'], isNull);
        final converter = Converter.create('catchall-foobaz')!;
        expect(converter.convert(Block(null, 'paragraph')), 'foobaz content');
      });

      test('should use catch all converter from custom factory only if no '
          'other converter matches', () {
        // Port of test/converter_test.rb: 'should use catch all converter
        // from custom factory only if no other converter matches'.
        final factory = CustomFactory(const {
          'factory-foo': FakeConverter.new,
          '*': FakeBaseConverter.new,
        });
        expect(factory.forBackend('factory-foo'), equals(FakeConverter.new));
        expect(factory.forBackend('factory-nada'), isA<ConverterFactoryFn>());
        expect(
          factory.forBackend('factory-nada'),
          equals(FakeBaseConverter.new),
        );
        // A custom factory never consults the global registry.
        expect(
          factory.forBackend('factory-html5'),
          equals(FakeBaseConverter.new),
        );
      });

      test('should prefer catch all converter from proxy over statically '
          'registered catch all converter', () {
        // Port of test/converter_test.rb: 'should prefer catch all
        // converter from proxy over statically registered catch all
        // converter'. Adapted: the Ruby test relies on the lazily-loaded
        // `html5` built-in; the port registers an explicit fake backend.
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['*']);
        Converter.register(FakeConverter.new, const [
          'reg-proxy-explicit',
        ], provided: true);
        final factory = DefaultFactoryProxy(const {'*': FakeBaseConverter.new});
        expect(
          factory.forBackend('catchall-proxied'),
          equals(FakeBaseConverter.new),
        );
        expect(
          factory.forBackend('reg-proxy-explicit'),
          equals(FakeConverter.new),
        );
      });

      test('should prefer converter in proxy with same name as provided '
          'converter', () {
        // Port of test/converter_test.rb: 'should prefer converter in proxy
        // with same name as provided converter'. Adapted: registers the
        // fake backend with `provided: true` (no built-ins exist yet).
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const [
          'reg-provided',
        ], provided: true);
        final factory = DefaultFactoryProxy(const {
          'reg-provided': FakeBaseConverter.new,
        });
        expect(
          factory.forBackend('reg-provided'),
          equals(FakeBaseConverter.new),
        );
      });

      test('should allow nil to be registered as converter', () {
        // Port of test/converter_test.rb: 'should allow nil to be
        // registered as converter'. Adapted: seeds the global registry
        // first so the test proves an explicit `null` shadows it.
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['reg-shadowed']);
        final factory = DefaultFactoryProxy(const {'reg-shadowed': null});
        expect(factory.forBackend('reg-shadowed'), isNull);
        expect(factory.create('reg-shadowed'), isNull);
      });

      test('should create a new custom factory when Converter::Factory.new is '
          'invoked', () {
        // Port of test/converter_test.rb: 'should create a new custom
        // factory when Converter::Factory.new is invoked'.
        final factory = ConverterFactory(const {
          'factory-mine': FakeConverter.new,
        });
        expect(factory, isA<CustomFactory>());
        expect(factory.forBackend('factory-mine'), equals(FakeConverter.new));
      });

      test(
        'should delegate to method on HTML 5 converter with convert_ prefix '
        'if called without prefix',
        // Permanent: Ruby's `method_missing`/`respond_to?` delegation has
        // no Dart counterpart; handler dispatch is covered by the
        // ConverterBase tests in this file.
        skip: noDartCounterpart,
        () {},
      );
      test(
        'should not delegate unprefixed method on HTML 5 converter if '
        'converter does not handle transform',
        // Permanent: see the test above.
        skip: noDartCounterpart,
        () {},
      );
      test('can call read_svg_contents on built-in HTML5 converter; should '
          'remove markup prior the root svg element', () {
        // Port of test/converter_test.rb: 'can call read_svg_contents on
        // built-in HTML5 converter; should remove markup prior the root
        // svg element'.
        final doc = documentFromString('image::circle.svg[]', {
          'base_dir': fixturePath(''),
        });
        final converter = doc.converter as Html5Converter;
        final result = converter.readSvgContents(doc.blocks[0], 'circle.svg');
        expect(result, isNotNull);
        expect(result!.startsWith('<svg'), isTrue);
      });
    });

    group('Framework seams', () {
      test('convert raises UnimplementedError by default', () {
        // Mirrors Ruby's `NotImplementedError` from `Converter#convert`.
        final converter = BareConverter('bare');
        expect(
          () => converter.convert(Block(null, 'paragraph')),
          throwsA(
            isA<UnimplementedError>().having(
              (error) => error.message,
              'message',
              'BareConverter (backend: bare) must implement the convert method',
            ),
          ),
        );
      });

      test('create returns a registered instance as-is', () {
        // Verified via `ruby -Ilib -e` (`equal?` on the created instance).
        cleanGlobalRegistry();
        final instance = FakeConverter('seam-instance');
        Converter.register(instance, const ['seam-instance']);
        expect(Converter.forBackend('seam-instance'), same(instance));
        expect(Converter.create('seam-instance'), same(instance));
      });

      test(
        'create instantiates a registered factory with backend and opts',
        () {
          cleanGlobalRegistry();
          String? seenBackend;
          Map<String, Object?>? seenOpts;
          Converter.register((String backend, Map<String, Object?> opts) {
            seenBackend = backend;
            seenOpts = opts;
            return FakeConverter(backend, opts);
          }, const ['seam-factory']);
          final created = Converter.create('seam-factory', const {
            'htmlsyntax': 'xml',
          })!;
          expect(created, isA<FakeConverter>());
          expect(seenBackend, 'seam-factory');
          expect(seenOpts, equals(const {'htmlsyntax': 'xml'}));
        },
      );

      test('create returns null when nothing is registered', () {
        // Verified via `ruby -Ilib -e` (`create 'nope'` is `nil`).
        cleanGlobalRegistry();
        expect(Converter.create('seam-missing'), isNull);
        expect(CustomFactory().create('seam-missing'), isNull);
      });

      test(
        'create with template_dirs throws until the template wave lands',
        () {
          cleanGlobalRegistry();
          Converter.register(FakeConverter.new, const ['seam-tmpl-plain']);
          // Registered converter that does not support templates: returned
          // as-is, exactly as in Ruby (no composite wrapping).
          final plain = Converter.create('seam-tmpl-plain', const {
            'template_dirs': ['templates'],
          });
          expect(plain, isA<FakeConverter>());
          // Anything needing a TemplateConverter reports the missing wave.
          Converter.register(
            (String backend, Map<String, Object?> opts) =>
                FakeBaseConverter(backend, opts)..supportsTemplates = true,
            const ['seam-tmpl-supported'],
          );
          expect(
            () => Converter.create('seam-tmpl-supported', const {
              'template_dirs': ['templates'],
            }),
            throwsUnimplementedError,
          );
          expect(
            () => Converter.create('seam-tmpl-missing', const {
              'template_dirs': ['templates'],
            }),
            throwsUnimplementedError,
          );
        },
      );

      test('register rejects registrations of unknown shape', () {
        cleanGlobalRegistry();
        expect(
          () => Converter.register('nope', const ['seam-garbage']),
          throwsArgumentError,
        );
        expect(
          () => CustomFactory(const {'seam-garbage': 42}),
          throwsArgumentError,
        );
      });

      test('converters returns a copy of the registry', () {
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['seam-copy']);
        final snapshot = Converter.converters;
        snapshot['seam-copy'] = null;
        snapshot['seam-injected'] = FakeConverter.new;
        expect(Converter.forBackend('seam-copy'), equals(FakeConverter.new));
        expect(Converter.converters.containsKey('seam-injected'), isFalse);
      });

      test('unregisterAll keeps provided registrations only', () {
        // Mirrors Ruby, where `unregister_all` keeps `PROVIDED` backends.
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const [
          'seam-provided',
        ], provided: true);
        Converter.register(FakeConverter.new, const ['seam-custom']);
        Converter.register(FakeConverter.new, const ['*']);
        Converter.unregisterAll();
        expect(
          Converter.forBackend('seam-provided'),
          equals(FakeConverter.new),
        );
        expect(Converter.forBackend('seam-custom'), isNull);
        expect(Converter.forBackend('seam-other'), isNull);
      });

      test('proxy unregisterAll also clears the global registry', () {
        // Mirrors Ruby: `DefaultFactoryProxy#unregister_all` delegates to
        // `DefaultFactory#unregister_all` (verified via `ruby -Ilib -e`).
        cleanGlobalRegistry();
        Converter.register(FakeConverter.new, const ['seam-global']);
        final factory = DefaultFactoryProxy(const {
          'seam-local': FakeConverter.new,
        });
        factory.unregisterAll();
        expect(factory.forBackend('seam-local'), isNull);
        expect(Converter.forBackend('seam-global'), isNull);
      });

      test('supportsTemplates defaults to false', () {
        // Ruby default is `nil` (falsy); the port uses `false`.
        expect(FakeConverter('seam-traits').supportsTemplates, isFalse);
        expect(FakeBaseConverter('seam-traits').supportsTemplates, isFalse);
      });

      test('backendInfo aliases backendTraits', () {
        final converter = FakeConverter('seam-info');
        expect(converter.backendInfo(), equals(converter.backendTraits()));
      });

      test('base dispatches to the registered handler for the node name', () {
        AbstractNode? seen;
        final converter = FakeBaseConverter('seam-dispatch', const {}, {
          'paragraph': (node, [opts]) {
            seen = node;
            return '<p>hi</p>';
          },
        });
        final node = Block(null, 'paragraph');
        expect(converter.handles('paragraph'), isTrue);
        expect(converter.handles('sidebar'), isFalse);
        expect(converter.convert(node), '<p>hi</p>');
        expect(seen, same(node));
      });

      test('base passes opts to the handler only when non-null', () {
        final seen = <Map<String, Object?>?>[];
        final converter = FakeBaseConverter('seam-opts', const {}, {
          'paragraph': (node, [opts]) {
            seen.add(opts);
            return 'ok';
          },
        });
        final node = Block(null, 'paragraph');
        expect(converter.convert(node), 'ok');
        expect(
          converter.convert(node, 'paragraph', const {'outline': true}),
          'ok',
        );
        expect(seen, [
          isNull,
          equals(const {'outline': true}),
        ]);
      });

      test('base honors an explicit transform over the node name', () {
        final converter = FakeBaseConverter('seam-transform', const {}, {
          'custom': (node, [opts]) => 'custom!',
        });
        expect(
          converter.convert(Block(null, 'paragraph'), 'custom'),
          'custom!',
        );
      });

      test('base contentOnly converts block and inline content', () {
        final converter = FakeBaseConverter('seam-content-only');
        expect(
          converter.contentOnly(StubBlock(null, 'sidebar', '<aside/>')),
          '<aside/>',
        );
        expect(converter.contentOnly(Inline(null, 'quoted', text: 'hi')), 'hi');
        expect(() => converter.contentOnly(BareNode()), throwsArgumentError);
      });

      test('base skip returns null', () {
        final converter = FakeBaseConverter('seam-skip');
        expect(converter.skip(Block(null, 'paragraph')), isNull);
      });
    });

    group('CompositeConverter', () {
      FakeBaseConverter paragraphConverter(String backend) => FakeBaseConverter(
        backend,
        const {},
        {'paragraph': (node, [opts]) => '<p>first</p>'},
      );

      FakeBaseConverter sidebarConverter(String backend) =>
          FakeBaseConverter(backend, const {}, {
            'paragraph': (node, [opts]) => '<p>second</p>',
            'sidebar': (node, [opts]) => '<aside/>',
          });

      test('delegates to the first converter handling the transform', () {
        final first = paragraphConverter('seam-composite');
        final second = sidebarConverter('seam-composite');
        final composite = CompositeConverter('seam-composite', [first, second]);
        expect(composite.converters, [same(first), same(second)]);
        expect(composite.convert(Block(null, 'paragraph')), '<p>first</p>');
        expect(composite.convert(StubBlock(null, 'sidebar', '')), '<aside/>');
      });

      test('passes the transform and opts through to the delegate', () {
        String? seenTransform;
        Map<String, Object?>? seenOpts;
        final delegate = FakeBaseConverter('seam-passthrough', const {}, {
          'paragraph': (node, [opts]) {
            seenOpts = opts;
            return 'ok';
          },
        });
        final composite = CompositeConverter('seam-passthrough', [delegate]);
        // A delegate that records the transform it was asked to convert.
        final recording = _RecordingConverter('seam-passthrough');
        final composite2 = CompositeConverter('seam-passthrough', [recording]);
        expect(
          composite.convert(Block(null, 'paragraph'), 'paragraph', const {
            'k': 'v',
          }),
          'ok',
        );
        expect(seenOpts, equals(const {'k': 'v'}));
        composite2.convert(Block(null, 'paragraph'), 'paragraph', const {
          'k': 'v',
        });
        seenTransform = recording.seenTransform;
        expect(seenTransform, 'paragraph');
        expect(recording.seenOpts, equals(const {'k': 'v'}));
        expect(delegate.handles('paragraph'), isTrue);
      });

      test('converterFor caches the selected converter', () {
        final composite = CompositeConverter('seam-cache', [
          paragraphConverter('seam-cache'),
          sidebarConverter('seam-cache'),
        ]);
        expect(
          composite.converterFor('paragraph'),
          same(composite.converters.first),
        );
        expect(
          composite.converterFor('paragraph'),
          same(composite.converterFor('paragraph')),
        );
        expect(
          composite.converterFor('sidebar'),
          same(composite.converters[1]),
        );
      });

      test('findConverter throws a StateError when nothing handles it', () {
        final composite = CompositeConverter('seam-find', [
          paragraphConverter('seam-find'),
        ]);
        expect(
          composite.findConverter('paragraph'),
          same(composite.converters.first),
        );
        expect(
          () => composite.findConverter('table'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Could not find a converter to handle transform: table',
            ),
          ),
        );
        expect(
          () => composite.convert(StubBlock(null, 'table', '')),
          throwsStateError,
        );
      });

      test('adopts the backend traits source', () {
        final source = FakeConverter('seam-source')
          ..baseBackend = 'docbook'
          ..fileType = 'xml'
          ..outfileSuffix = '.xml';
        final composite = CompositeConverter('seam-adopt', [
          FakeConverter('seam-adopt'),
        ], backendTraitsSource: source);
        // Shared by reference, as in Ruby (`init_backend_traits` assigns).
        expect(composite.backendTraits(), same(source.backendTraits()));
        expect(composite.baseBackend, 'docbook');
      });

      test('notifies ComposedAware delegates', () {
        final delegate = _ComposedProbe('seam-composed');
        final composite = CompositeConverter('seam-composed', [delegate]);
        expect(delegate.seen, same(composite));
      });

      test('handles no transform itself', () {
        // Verified via `ruby -Ilib -e`: `CompositeConverter` defines no
        // `convert_*` methods, so `handles?` is always false.
        final composite = CompositeConverter('seam-handles', [
          paragraphConverter('seam-handles'),
        ]);
        expect(composite.handles('paragraph'), isFalse);
      });
    });
  });
}

/// Documents the explicit registration pattern for backend waves: each
/// converter class exposes a static `registerFor` used by document
/// initialization (idempotent; `provided: true` survives `unregisterAll`).
class _SelfRegisteringConverter extends ConverterBase {
  /// Creates a self-registering converter.
  _SelfRegisteringConverter(super.backend, [super.opts]);

  /// Registers this converter for [backends].
  static void registerFor([List<String> backends = const ['reg-self']]) {
    Converter.register(_SelfRegisteringConverter.new, backends);
  }

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) => 'self';
}

/// Records the transform and options it was asked to convert with.
class _RecordingConverter extends Converter {
  /// The last transform seen by [convert].
  String? seenTransform;

  /// The last options seen by [convert].
  Map<String, Object?>? seenOpts;

  /// Creates a recording converter.
  _RecordingConverter(super.backend);

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
  ]) {
    seenTransform = transform ?? node.nodeName;
    seenOpts = opts;
    return 'recorded';
  }
}

/// A [ComposedAware] delegate recording the composite it joined.
class _ComposedProbe extends Converter implements ComposedAware {
  /// The composite passed to [composed].
  CompositeConverter? seen;

  /// Creates a probe converter.
  _ComposedProbe(super.backend);

  @override
  void composed(CompositeConverter composite) {
    seen = composite;
  }
}
