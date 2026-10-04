/// Tests for the converter framework port.
///
/// Covers `converter.dart` (port of `lib/asciidoctor/converter.rb`) and
/// `composite.dart` (port of `lib/asciidoctor/converter/composite.rb`).
///
/// Each `Port of` comment cites the originating test in
/// `test/converter_test.rb`. Most ported tests use fake converters and
/// directly-constructed fake nodes (no parsing); the `converter` /
/// `converter_factory` / `read_svg_contents` tests parse and convert for
/// real. Tilt-engine-specific template tests with no Dart counterpart stay
/// skipped as empty placeholders with [noTiltCounterpart];
/// Ruby-metaprogramming tests with no Dart counterpart stay skipped with
/// [noDartCounterpart].
///
/// Global-registry tests clean up with `addTearDown(Converter.unregisterAll)`
/// and use unique backend names per test: `provided` registrations survive
/// `unregisterAll` by design (mirroring Ruby's `PROVIDED` map), so shared
/// names would leak between tests.
///
/// Template tests (template wave C) build real `*.mustache` directories
/// with [makeTemplateDir] and convert through the real registry + loader;
/// Tilt-engine-specific tests (Haml/Slim/ERB formats, engine options, JRuby
/// classloader) stay skipped with [noTiltCounterpart].
library;

import 'dart:io';

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

import 'document_test.dart' show assertXpath;
import 'support/doc_helpers.dart';

/// Reason for permanently-skipped Tilt-engine-specific tests.
///
/// Haml/Slim/ERB formats, per-engine options and the JRuby classloader
/// have no Dart counterpart by design: file templates are Mustache-only
/// (ADR-0002 rules Tilt parity out of scope) and logic-heavy templates
/// take path (a) instead.
const String noTiltCounterpart =
    'permanent skip: Tilt-engine-specific behavior (Haml/Slim/ERB/JRuby) '
    'with no Dart counterpart (ADR-0002: Mustache-only file templates)';

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
  /// Creates a converter returning [result] (default `'fake content'`).
  new(super.backend, [super.opts, this.result = 'fake content']);

  /// The value [convert] returns.
  final String result;

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => result;
}

/// A [ConverterBase] with handlers wired through [handle].
class FakeBaseConverter extends ConverterBase {
  /// Creates a converter registering [handlers] for [backend].
  new(
    super.backend, [
    super.opts,
    Map<String, ConvertHandler> handlers = const <String, ConvertHandler>{},
  ]) {
    handlers.forEach(handle);
  }
}

/// A [Converter] that overrides only [convert] (pins default [Converter]
/// behavior).
class BareConverter extends Converter {
  /// Creates a bare converter for [backend].
  new(super.backend, [super.opts]);

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => null;
}

/// A block whose [content] is fixed (avoids the substitutors wave).
class StubBlock extends Block {
  /// Creates a stub block with fixed [content].
  new(super.parent, super.context, this.stubbedContent);

  /// The value [content] returns.
  final String? stubbedContent;

  @override
  String? content() => stubbedContent;
}

/// A bare node that is neither block nor inline content (for `contentOnly`).
class BareNode extends AbstractNode {
  /// Creates a bare node with node name `'bare'`.
  new() : super(null, 'bare');

  @override
  bool get isBlock => false;

  @override
  bool get isInline => false;
}

/// Records log messages for assertions.
class FakeLogger extends LoggerBase {
  /// Creates a recording logger.
  new() : super(Severity.debug);

  /// Messages by severity, in logging order.
  final List<String> debugs = <String>[];
  final List<String> infos = <String>[];
  final List<String> warns = <String>[];
  final List<String> errors = <String>[];
  final List<String> fatals = <String>[];

  @override
  Severity? get maxSeverity => null;

  @override
  void add(Severity severity, LogMessage message) {
    switch (severity) {
      case Severity.debug:
        debugs.add('$message');
      case Severity.info:
        infos.add('$message');
      case Severity.warn:
        warns.add('$message');
      case Severity.error:
        errors.add('$message');
      case Severity.fatal || Severity.unknown:
        fatals.add('$message');
    }
  }

  @override
  Future<void> close() async {}
}

/// Installs [logger] as the shared logger, restoring the previous one after.
void useLogger(FakeLogger logger) {
  final saved = LoggerManager.logger;
  LoggerManager.logger = logger;
  addTearDown(() {
    LoggerManager.logger = saved;
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
  new(super.backend, [super.opts]);

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => 'document';
}

/// A custom text converter returning `'document'` for every node (port of
/// `CustomTextConverterA`).
class CustomTextConverterA extends Converter {
  /// Creates the converter for [backend] with [opts].
  new(super.backend, [super.opts]);

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => 'document';
}

/// A custom converter handling only the `document` transform (port of the
/// anonymous `Converter::Base` subclass in the factory test).
class CustomDocumentConverter extends ConverterBase {
  /// Creates the converter for [backend] with [opts].
  new(super.backend, [super.opts]) {
    handle('document', (node, [opts]) => 'document');
  }
}

/// Resolves a fixture path (port of `fixture_path`).
String fixturePath(String name) => 'test/fixtures/$name';

/// Creates a template directory holding [files] (name to source).
///
/// The directory is deleted after the test. Names are flat Mustache
/// filenames (`paragraph.mustache`); see [VmTemplateLoader] for the
/// resolution semantics.
Directory makeTemplateDir(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('converter-template-test');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final entry in files.entries) {
    File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
  }
  return dir;
}

/// Returns the [TemplateConverter] handling [transform] on [doc].
///
/// Asserts the document converted through a template chain (a
/// [CompositeConverter] whose first delegate is the template converter).
TemplateConverter templateConverterFor(Document doc, String transform) {
  final converter = doc.converter as CompositeConverter;
  final selected = converter.findConverter(transform);
  expect(selected, isA<TemplateConverter>());
  return selected as TemplateConverter;
}

/// A custom [Converter] that never supports templates (port of Ruby's
/// `CustomConverterD`: a plain `Converter` includee without template
/// support).
class TemplatelessConverter extends Converter {
  /// Creates the converter for [backend] with [opts].
  new(super.backend, [super.opts]);

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) {
    if (node is Document) {
      return node.blocks.map(convert).join('\n');
    }
    if ((transform ?? node.nodeName) == 'paragraph') {
      return '<div class="paragraph"><p>${(node as Block).content()}</p></div>';
    }
    return (node as Block).content();
  }
}

void main() {
  group('Converter', () {
    group('View options', () {
      test(
        'should set Haml format to html5 for html5 backend',
        // Permanent: Haml engine options have no Mustache counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should set Haml format to xhtml for docbook backend',
        // Permanent: Haml engine options have no Mustache counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should configure Slim to resolve includes in specified template dirs',
        // Permanent: Slim includes have no Mustache counterpart (the Dart
        // adapter exposes no partials).
        skip: noTiltCounterpart,
        () {},
      );
      test('should load templates from a single template dir', () {
        // Port of test/converter_test.rb: 'should coerce template_dirs
        // option to an Array'. Adapted: Dart holds no `@template_dirs`
        // ivar to probe, so the coercion is proven behaviorally — a lone
        // String resolves as one directory and its templates load.
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final doc = documentFromString(
          'hi',
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        expect(doc.converter, isA<CompositeConverter>());
        expect(
          templateConverterFor(doc, 'paragraph').templates['paragraph'],
          equals('<p>{{content}}</p>'),
        );
      });
      test(
        'should set Slim format to html for html5 backend',
        // Permanent: Slim engine options have no Mustache counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should set Slim format to nil for docbook backend',
        // Permanent: Slim engine options have no Mustache counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should set safe mode of Slim AsciiDoc engine to match document safe '
        'mode when Slim >= 3',
        // Permanent: Slim engine options have no Mustache counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should support custom template engine options for known engine',
        // Permanent: the Dart port defines no `template_engine_options`
        // vocabulary (Mustache leniency/escaping are registry-level, not
        // per-render options).
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should support custom template engine options',
        // Permanent: see the test above.
        skip: noTiltCounterpart,
        () {},
      );
    });

    group('Custom backends', () {
      test('should load Mustache templates for default backend', () {
        // Port of test/converter_test.rb: 'should load Haml templates for
        // default backend' (adapted: Haml -> Mustache; the node name is
        // the basename minus `.mustache`, with no `block_` prefix).
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final doc = documentFromString(
          '',
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        expect(doc.converter, isA<CompositeConverter>());
        expect(
          templateConverterFor(doc, 'paragraph').templates['paragraph'],
          equals('<p>{{content}}</p>'),
        );
      });
      test('should set outfilesuffix according to backend info', () {
        // Port of test/converter_test.rb: 'should set outfilesuffix
        // according to backend info'. The composite adopts the fallback
        // converter's traits, so the suffix is unchanged by templates.
        final plain = documentFromString('content');
        expect(plain.attributes['outfilesuffix'], equals('.html'));
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final withTemplates = documentFromString(
          'content',
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        expect(withTemplates.attributes['outfilesuffix'], equals('.html'));
      });
      test('should not override outfilesuffix attribute if locked', () {
        // Port of test/converter_test.rb: 'should not override
        // outfilesuffix attribute if locked'. Attributes passed through
        // the options are locked, so the converter-derived suffix never
        // replaces them, with or without templates.
        final plain = documentFromString(
          'content',
          const AsciidoctorOptions(attributes: {'outfilesuffix': '.foo'}),
        );
        expect(plain.attributes['outfilesuffix'], equals('.foo'));
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final withTemplates = documentFromString(
          'content',
          AsciidoctorOptions(
            templateDirs: [dir.path],
            templateCache: false,
            attributes: {'outfilesuffix': '.foo'},
          ),
        );
        expect(withTemplates.attributes['outfilesuffix'], equals('.foo'));
      });
      test('should load Mustache templates for docbook5 backend', () {
        // Port of test/converter_test.rb: 'should load Haml templates for
        // docbook5 backend' (adapted: Haml -> Mustache). Divergence: Dart
        // resolves flat names with no backend infix, so the same file
        // serves docbook5 (no `block_*.xml.haml` split).
        final dir = makeTemplateDir({
          'paragraph.mustache': '<simpara>{{content}}</simpara>',
        });
        final doc = documentFromString(
          '',
          AsciidoctorOptions(
            backend: 'docbook5',
            templateDirs: [dir.path],
            templateCache: false,
          ),
        );
        expect(doc.converter, isA<CompositeConverter>());
        expect(
          templateConverterFor(doc, 'paragraph').templates['paragraph'],
          equals('<simpara>{{content}}</simpara>'),
        );
      });
      test('should use Mustache templates in place of built-in templates', () {
        // Port of test/converter_test.rb: 'should use Haml templates in
        // place of built-in templates' (adapted: Haml -> Mustache file
        // templates; unhandled transforms fall back to the built-in
        // converter).
        const input =
            '= Document Title\n'
            'Author Name\n'
            '\n'
            '== Section One\n'
            '\n'
            'Sample paragraph\n'
            '\n'
            '.Related\n'
            '****\n'
            'Sidebar content\n'
            '****\n';
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
          'sidebar.mustache':
              '<aside>'
              '{{#title}}<header><h1>{{title}}</h1></header>{{/title}}'
              '{{content}}'
              '</aside>',
        });
        final output = convertStringToEmbedded(
          input,
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        assertXpath('/*[@class="sect1"]/*[@class="sectionbody"]/p', output, 1);
        assertXpath('//aside', output, 1);
        assertXpath(
          '/*[@class="sect1"]/*[@class="sectionbody"]/p/following-sibling::aside',
          output,
          1,
        );
        assertXpath('//aside/header/h1[text()="Related"]', output, 1);
        assertXpath(
          '//aside/header/following-sibling::p[text()="Sidebar content"]',
          output,
          1,
        );
      });
      test('should allow custom backend to emulate a known backend', () {
        // Port of test/converter_test.rb: 'should allow custom backend to
        // emulate a known backend'. `backend: 'html5-tweaks:html'`
        // resolves traits through the delegate backend while the
        // template converter handles the overridden transforms.
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
          'embedded.mustache': '{{content}}',
        });
        final doc = documentFromString(
          'content',
          AsciidoctorOptions(
            backend: 'html5-tweaks:html',
            standalone: false,
            templateDirs: [dir.path],
            templateCache: false,
          ),
        );
        expect(doc.basebackend('html'), isTrue);
        expect(doc.backend, equals('html5-tweaks'));
        final converter = doc.converter as CompositeConverter;
        expect(converter.findConverter('embedded'), isA<TemplateConverter>());
        expect(
          converter.findConverter('admonition'),
          isNot(isA<TemplateConverter>()),
        );
        expect(doc.convert(), equals('<p>content</p>'));
      });
      test('should create template converter even when a converter is not '
          'registered for the specified backend', () {
        // Port of test/converter_test.rb: 'should create template
        // converter even when a converter is not registered for the
        // specified backend' (adapted: Haml -> Mustache). The factory
        // returns a bare template converter whose traits derive from
        // the backend name.
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
          'embedded.mustache': '{{content}}',
        });
        final output = convertStringToEmbedded(
          'paragraph content',
          AsciidoctorOptions(
            backend: 'unknown',
            templateDirs: [dir.path],
            templateCache: false,
          ),
        );
        expect(output, equals('<p>paragraph content</p>'));
      });
      test('should use built-in global cache to cache templates', () {
        // Port of test/converter_test.rb: 'should use built-in global
        // cache to cache templates' (adapted: the Dart cache stores scan
        // maps — node name to source — rather than Tilt objects, so reuse
        // is proven by serving a stale scan after the file changes).
        TemplateCache.clearCaches();
        addTearDown(TemplateCache.clearCaches);
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        documentFromString('hi', AsciidoctorOptions(templateDirs: [dir.path]));
        expect(TemplateCache.shared.scans, isNotEmpty);
        // Rewriting the file must not matter: the cached scan wins.
        File('${dir.path}/paragraph.mustache')
            .writeAsStringSync('<p>changed</p>');
        final cached = documentFromString(
          'hi',
          AsciidoctorOptions(templateDirs: [dir.path]),
        );
        expect(
          templateConverterFor(cached, 'paragraph').templates['paragraph'],
          equals('<p>{{content}}</p>'),
        );
        // template_cache: false bypasses the shared cache (fresh scan,
        // no shared writes) while conversion still works.
        final scansBefore = TemplateCache.shared.scans.length;
        final uncached = documentFromString(
          'hi',
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        expect(
          templateConverterFor(uncached, 'paragraph').templates['paragraph'],
          equals('<p>changed</p>'),
        );
        expect(TemplateCache.shared.scans.length, equals(scansBefore));
      });
      test('should use custom cache to cache templates', () {
        // Port of test/converter_test.rb: 'should use custom cache to
        // cache templates' (adapted: a [TemplateCache] instance replaces
        // Ruby's Hash store).
        TemplateCache.clearCaches();
        addTearDown(TemplateCache.clearCaches);
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final custom = TemplateCache();
        final doc = documentFromString(
          'hi',
          AsciidoctorOptions(
            templateDirs: [dir.path],
            templateCacheStore: custom,
          ),
        );
        expect(custom.scans, isNotEmpty);
        expect(
          custom.scans.values.first['paragraph'],
          equals('<p>{{content}}</p>'),
        );
        expect(TemplateCache.shared.scans, isEmpty);
        expect(
          templateConverterFor(doc, 'paragraph'),
          isA<TemplateConverter>(),
        );
      });
      test('should be able to disable template cache', () {
        // Port of test/converter_test.rb: 'should be able to disable
        // template cache'.
        TemplateCache.clearCaches();
        addTearDown(TemplateCache.clearCaches);
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final doc = documentFromString(
          'hi',
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        expect(doc.converter, isA<CompositeConverter>());
        expect(TemplateCache.shared.scans, isEmpty);
      });
      test(
        'should load ERB templates using ERBTemplate if eruby is not set',
        // Permanent: ERB/eRuby evaluation has no Dart counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test(
        'should load ERB templates using ErubiTemplate if eruby is set to '
        'erubi',
        // Permanent: ERB/eRuby evaluation has no Dart counterpart.
        skip: noTiltCounterpart,
        () {},
      );
      test('should load several Mustache templates for default backend', () {
        // Port of test/converter_test.rb: 'should load Slim templates for
        // default backend' (adapted: Slim -> Mustache; paragraph plus
        // sidebar in one directory).
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
          'sidebar.mustache': '<aside>{{content}}</aside>',
        });
        final doc = documentFromString(
          '',
          AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
        );
        expect(doc.converter, isA<CompositeConverter>());
        final selected = templateConverterFor(doc, 'paragraph');
        expect(selected.templates['paragraph'], equals('<p>{{content}}</p>'));
        expect(
          selected.templates['sidebar'],
          equals('<aside>{{content}}</aside>'),
        );
        expect(templateConverterFor(doc, 'sidebar'), same(selected));
      });
      test('should load Mustache templates for docbook5 backend with explicit '
          'engine', () {
        // Port of test/converter_test.rb: 'should load Slim templates
        // for docbook5 backend' (adapted: Slim -> Mustache with an
        // explicit `template_engine`, proving the engine option flows
        // through document creation).
        final dir = makeTemplateDir({
          'paragraph.mustache': '<simpara>{{content}}</simpara>',
        });
        final doc = documentFromString(
          '',
          AsciidoctorOptions(
            backend: 'docbook5',
            templateDirs: [dir.path],
            templateCache: false,
            templateEngine: 'mustache',
          ),
        );
        expect(doc.converter, isA<CompositeConverter>());
        expect(
          templateConverterFor(doc, 'paragraph').templates['paragraph'],
          equals('<simpara>{{content}}</simpara>'),
        );
      });
      test(
        'should use code-registered transforms in place of built-in templates',
        () {
          // Port of test/converter_test.rb: 'should use Slim templates in
          // place of built-in templates' (adapted: path (a) — the `dart`
          // engine resolves code-registered transforms and scans no
          // files, so the empty directory contributes nothing).
          TemplateRegistry.resetGlobal();
          addTearDown(TemplateRegistry.resetGlobal);
          TemplateRegistry.global.registerFunction(
            'paragraph',
            (node, [opts]) => '<p>fn:${(node as Block).content()}</p>',
          );
          final dir = makeTemplateDir(<String, String>{});
          final output = convertStringToEmbedded(
            'Sample paragraph',
            AsciidoctorOptions(
              templateDirs: [dir.path],
              templateCache: false,
              templateEngine: 'dart',
            ),
          );
          expect(output, contains('<p>fn:Sample paragraph</p>'));
          expect(output, isNot(contains('class="paragraph"')));
        },
      );
      test(
        'should be able to override the outline using a custom template',
        () {
          // Port of test/converter_test.rb: 'should be able to override the
          // outline using a custom template' (adapted: `outline.mustache`
          // iterates the `sections` context key).
          const input =
              ':toc:\n'
              '= Document Title\n'
              '\n'
              '== Section One\n'
              '\n'
              '== Section Two\n'
              '\n'
              '== Section Three\n';
          final dir = makeTemplateDir({
            'outline.mustache':
                '<ul>{{#sections}}<li>{{title}}</li>{{/sections}}</ul>',
          });
          final output = documentFromString(
            input,
            AsciidoctorOptions(templateDirs: [dir.path], templateCache: false),
          ).convert();
          assertXpath('//*[@id="toc"]/ul', output, 1);
          assertXpath('//*[@id="toc"]/ul[1]/li', output, 3);
          assertXpath(
            '//*[@id="toc"]/ul[1]/li[1][text()="Section One"]',
            output,
            1,
          );
        },
      );
      test(
        'resolves templates from classloader when using JRuby',
        // Permanent: JRuby-only (classloader URIs have no Dart analog).
        skip: noTiltCounterpart,
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
        (String, String, String, String?) traits(
          String backend, [
          String? basebackend,
        ]) {
          final derived = BackendTraits.derive(backend, basebackend);
          return (
            derived.basebackend,
            derived.filetype,
            derived.outfilesuffix,
            derived.htmlsyntax,
          );
        }

        expect(traits('dita2'), equals(('dita', 'dita', '.dita', null)));
        expect(traits('html5'), equals(('html', 'html', '.html', 'html')));
        expect(
          traits('custom', 'html'),
          equals(('html', 'html', '.html', 'html')),
        );
        expect(traits('manpage'), equals(('manpage', 'man', '.man', null)));
      });

      test('should use specified converter for current backend', () {
        // Port of test/converter_test.rb: 'should use specified converter
        // for current backend'. Adapted: Dart passes a factory where Ruby
        // passes the class.
        const input = '= Document Title\n\npreamble\n\n== Section\n\ncontent\n';
        final doc = documentFromString(
          input,
          AsciidoctorOptions(converter: CustomHtmlConverterA('html5')),
        );
        expect(doc.converter, isA<CustomHtmlConverterA>());
        expect(doc.attributes['filetype'], equals('html'));
        expect(doc.convert(), equals('document'));
      });
      test('should use specified converter for specified backend', () {
        // Port of test/converter_test.rb: 'should use specified converter
        // for specified backend'. Adapted: Dart passes a factory where
        // Ruby passes the class.
        const input = '= Document Title\n\npreamble\n\n== Section\n\ncontent\n';
        final doc = documentFromString(
          input,
          AsciidoctorOptions(
            backend: 'text',
            converter: CustomTextConverterA('text'),
          ),
        );
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
          logger.warns.single,
          startsWith(
            'missing convert handler for paragraph node in fizzbuzz backend (',
          ),
        );
        expect(logger.warns.single, endsWith(')'));
        expect(logger.warns.single, contains('FakeBaseConverter'));
        // An explicit transform names the transform, not the node.
        expect(converter.convert(node, 'document'), isNull);
        expect(
          logger.warns.last,
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
        final doc = documentFromString(
          input,
          AsciidoctorOptions(converterFactory: converterFactory),
        );
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
          final converter = Converter.create(
            'html5',
            const ConverterOptions(htmlsyntax: 'xml'),
          )!;
          final doc = documentFromString(
            input,
            AsciidoctorOptions(converter: converter),
          );
          expect(doc.converter, same(converter));
          expect(doc.attr('htmlsyntax'), equals('xml'));
          final output = doc.convert(standalone: false);
          expect(output, contains('<img src="sunset.jpg" alt="sunset"/>'));
        },
      );

      test('should use converter registered for backend', () {
        // Port of test/converter_test.rb: 'should use converter registered
        // for backend'. Adapted: converts a directly-constructed node
        // instead of parsing a document.
        cleanGlobalRegistry();
        final before = Converter.registeredBackends.length;
        Converter.register(FakeConverter.new, const ['reg-backend']);
        expect(Converter.forBackend('reg-backend'), equals(FakeConverter.new));
        expect(Converter.registeredBackends.length, before + 1);
        expect(Converter.registeredBackends, contains('reg-backend'));
        final converter = Converter.create('reg-backend')!;
        expect(converter, isA<FakeConverter>());
        expect(converter.backend, 'reg-backend');
        converter.backendTraits = BackendTraits(
          basebackend: 'text',
          filetype: 'text',
          outfilesuffix: '.fb',
        );
        final traits = converter.backendTraits;
        expect((
          traits.basebackend,
          traits.filetype,
          traits.outfilesuffix,
        ), equals(('text', 'text', '.fb')));
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
          (backend, opts) =>
              FakeBaseConverter(backend, opts)
                ..backendTraits = BackendTraits.derive(backend, 'html'),
          const ['reg-slides'],
        );
        final traits = Converter.create('reg-slides')!.backendTraits;
        expect((
          traits.basebackend,
          traits.filetype,
          traits.htmlsyntax,
          traits.outfilesuffix,
        ), equals(('html', 'html', 'html', '.html')));
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
          _SelfRegisteringConverter.registerFor();
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
        () {
          // Port of test/converter_test.rb: 'should not configure converter
          // to support templates by default'. A converter that does not
          // declare template support is returned as-is; the templates are
          // ignored and its own rendering wins.
          cleanGlobalRegistry();
          Converter.register(TemplatelessConverter.new, const ['tmpl-less']);
          final dir = makeTemplateDir({
            'paragraph.mustache': '<p>{{content}}</p>',
          });
          final doc = documentFromString(
            'paragraph',
            AsciidoctorOptions(
              backend: 'tmpl-less',
              templateDirs: [dir.path],
              templateCache: false,
            ),
          );
          expect(doc.converter, isA<TemplatelessConverter>());
          expect(
            (doc.converter as TemplatelessConverter)
                .backendTraits
                .supportsTemplates,
            isFalse,
          );
          final output = doc.convert();
          assertXpath(
            '//*[@class="paragraph"]/p[text()="paragraph"]',
            output,
            1,
          );
        },
      );
      test('should wrap converter in composite converter with template '
          'converter '
          'if it declares that it supports templates', () {
        // Port of test/converter_test.rb: 'should wrap converter in
        // composite converter with template converter if it declares
        // that it supports templates'. `supportsTemplates = true`
        // opts into the composite; the file template wins per
        // transform while the custom converter handles the rest.
        cleanGlobalRegistry();
        Converter.register((backend, opts) {
          final converter = (FakeBaseConverter(backend, opts, {
            'document': (node, [opts]) =>
                '<body>${(node as AbstractBlock).content()}</body>',
            'embedded': (node, [opts]) =>
                '<body>${(node as AbstractBlock).content()}</body>',
            'paragraph': (node, [opts]) =>
                '<div class="paragraph"><p>${(node as AbstractBlock).content()}</p></div>',
          }))..backendTraits.supportsTemplates = true;
          return converter;
        }, const ['tmpl-wrapped']);
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        final doc = documentFromString(
          'paragraph',
          AsciidoctorOptions(
            backend: 'tmpl-wrapped',
            templateDirs: [dir.path],
            templateCache: false,
          ),
        );
        expect(doc.converter, isA<CompositeConverter>());
        final output = doc.convert();
        assertXpath('//*[@class="paragraph"]/p[text()="paragraph"]', output, 0);
        assertXpath('//body/p[text()="paragraph"]', output, 1);
      });

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
        final factory = ConverterFactory(proxyDefault: false);
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
          (backend, opts) => FakeConverter(backend, opts, 'foobaz content'),
          const ['*'],
        );
        Converter.register(FakeConverter.new, const [
          'reg-explicit',
        ], provided: true);
        final catchAll = Converter.forBackend('catchall-all');
        expect(Converter.forBackend('catchall-whatever'), same(catchAll));
        expect(Converter.forBackend('reg-explicit'), isNot(same(catchAll)));
        expect(Converter.registeredBackends, isNot(contains('*')));
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
        final factory = ConverterFactory(
          converters: const {'factory-mine': FakeConverter.new},
        );
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
        final doc = documentFromString(
          'image::circle.svg[]',
          AsciidoctorOptions(baseDir: fixturePath('')),
        );
        final converter = doc.converter as Html5Converter;
        final result = converter.readSvgContents(doc.blocks[0], 'circle.svg');
        expect(result, isNotNull);
        expect(result!.startsWith('<svg'), isTrue);
      });
    });

    group('Framework seams', () {
      test('create returns a registered instance as-is', () {
        // Verified via `ruby -Ilib -e` (`equal?` on the created instance).
        cleanGlobalRegistry();
        final instance = FakeConverter('seam-instance');
        Converter.registerInstance(instance, const ['seam-instance']);
        expect(Converter.create('seam-instance'), same(instance));
      });

      test(
        'create instantiates a registered factory with backend and opts',
        () {
          cleanGlobalRegistry();
          String? seenBackend;
          ConverterOptions? seenOpts;
          Converter.register((backend, opts) {
            seenBackend = backend;
            seenOpts = opts;
            return FakeConverter(backend, opts);
          }, const ['seam-factory']);
          final created = Converter.create(
            'seam-factory',
            const ConverterOptions(htmlsyntax: 'xml'),
          )!;
          expect(created, isA<FakeConverter>());
          expect(seenBackend, 'seam-factory');
          expect(seenOpts?.htmlsyntax, equals('xml'));
        },
      );

      test('create returns null when nothing is registered', () {
        // Verified via `ruby -Ilib -e` (`create 'nope'` is `nil`).
        cleanGlobalRegistry();
        expect(Converter.create('seam-missing'), isNull);
        expect(CustomFactory().create('seam-missing'), isNull);
      });

      test('create with template_dirs engages a real template chain', () {
        // Template wave C: `template_dirs` builds a composite over
        // supporting converters (as-is otherwise), a bare template
        // converter for unknown backends, and honors `delegate_backend`
        // plus lone-String coercion — all against the real loader.
        cleanGlobalRegistry();
        TemplateCache.clearCaches();
        addTearDown(TemplateCache.clearCaches);
        Converter.register(FakeConverter.new, const ['seam-tmpl-plain']);
        final dir = makeTemplateDir({
          'paragraph.mustache': '<p>{{content}}</p>',
        });
        // Registered converter that does not support templates: returned
        // as-is, exactly as in Ruby (no composite wrapping).
        final plain = Converter.create(
          'seam-tmpl-plain',
          ConverterOptions(templateDirs: [dir.path]),
        );
        expect(plain, isA<FakeConverter>());
        // Supporting converter: composite with the template converter
        // ahead, templates loaded from the directory.
        Converter.register(
          (backend, opts) =>
              FakeBaseConverter(backend, opts)
                ..backendTraits.supportsTemplates = true,
          const ['seam-tmpl-supported'],
        );
        final composite = Converter.create(
          'seam-tmpl-supported',
          ConverterOptions(templateDirs: [dir.path]),
        );
        expect(composite, isA<CompositeConverter>());
        final chain = composite! as CompositeConverter;
        expect(chain.converters[0], isA<TemplateConverter>());
        expect(chain.converters[1], isA<FakeBaseConverter>());
        expect(chain.findConverter('paragraph'), isA<TemplateConverter>());
        // Unknown backend: bare template converter with derived traits.
        final bare = Converter.create(
          'seam-tmpl-missing',
          ConverterOptions(templateDirs: [dir.path]),
        );
        expect(bare, isA<TemplateConverter>());
        expect(
          (bare! as TemplateConverter).templates['paragraph'],
          equals('<p>{{content}}</p>'),
        );
        // delegate_backend names the fallback for unknown backends.
        final delegated = Converter.create(
          'seam-tmpl-missing',
          ConverterOptions(
            templateDirs: [dir.path],
            delegateBackend: 'seam-tmpl-plain',
          ),
        );
        expect(delegated, isA<CompositeConverter>());
        // A delegate_backend without template_dirs stays inert.
        expect(
          Converter.create(
            'seam-tmpl-missing',
            const ConverterOptions(delegateBackend: 'seam-tmpl-plain'),
          ),
          isNull,
        );
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
        final factory = (DefaultFactoryProxy(const {
          'seam-local': FakeConverter.new,
        }))..unregisterAll();
        expect(factory.forBackend('seam-local'), isNull);
        expect(Converter.forBackend('seam-global'), isNull);
      });

      test('supportsTemplates defaults to false', () {
        // Ruby default is `nil` (falsy); the port uses `false`.
        expect(
          FakeConverter('seam-traits').backendTraits.supportsTemplates,
          isFalse,
        );
        expect(
          FakeBaseConverter('seam-traits').backendTraits.supportsTemplates,
          isFalse,
        );
      });

      test('base dispatches to the registered handler for the node name', () {
        AbstractNode? seen;
        final converter = FakeBaseConverter(
          'seam-dispatch',
          const ConverterOptions(),
          {
            'paragraph': (node, [opts]) {
              seen = node;
              return '<p>hi</p>';
            },
          },
        );
        final node = Block(null, 'paragraph');
        expect(converter.handles('paragraph'), isTrue);
        expect(converter.handles('sidebar'), isFalse);
        expect(converter.convert(node), '<p>hi</p>');
        expect(seen, same(node));
      });

      test('base passes opts to the handler only when non-null', () {
        final seen = <ConvertOptions?>[];
        final converter = FakeBaseConverter(
          'seam-opts',
          const ConverterOptions(),
          {
            'paragraph': (node, [opts]) {
              seen.add(opts);
              return 'ok';
            },
          },
        );
        final node = Block(null, 'paragraph');
        expect(converter.convert(node), 'ok');
        expect(
          converter.convert(
            node,
            'paragraph',
            const ConvertOptions(toclevels: 1),
          ),
          'ok',
        );
        expect(seen, [isNull, same(const ConvertOptions(toclevels: 1))]);
      });

      test('base honors an explicit transform over the node name', () {
        final converter = FakeBaseConverter(
          'seam-transform',
          const ConverterOptions(),
          {'custom': (node, [opts]) => 'custom!'},
        );
        expect(
          converter.convert(Block(null, 'paragraph'), 'custom'),
          'custom!',
        );
      });

      test('base contentOnly converts block content', () {
        final converter = FakeBaseConverter('seam-content-only');
        expect(
          converter.contentOnly(StubBlock(null, 'sidebar', '<aside/>')),
          '<aside/>',
        );
        // Inline has no content in 2.0.26 (the alias came with #3220).
        expect(
          () => converter.contentOnly(Inline(null, 'quoted', text: 'hi')),
          throwsArgumentError,
        );
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
        const ConverterOptions(),
        {'paragraph': (node, [opts]) => '<p>first</p>'},
      );

      FakeBaseConverter sidebarConverter(String backend) =>
          FakeBaseConverter(backend, const ConverterOptions(), {
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
        ConvertOptions? seenOpts;
        final delegate = FakeBaseConverter(
          'seam-passthrough',
          const ConverterOptions(),
          {
            'paragraph': (node, [opts]) {
              seenOpts = opts;
              return 'ok';
            },
          },
        );
        final composite = CompositeConverter('seam-passthrough', [delegate]);
        // A delegate that records the transform it was asked to convert.
        final recording = _RecordingConverter('seam-passthrough');
        final composite2 = CompositeConverter('seam-passthrough', [recording]);
        expect(
          composite.convert(
            Block(null, 'paragraph'),
            'paragraph',
            const ConvertOptions(sectnumlevels: 2),
          ),
          'ok',
        );
        expect(seenOpts, equals(const ConvertOptions(sectnumlevels: 2)));
        composite2.convert(
          Block(null, 'paragraph'),
          'paragraph',
          const ConvertOptions(sectnumlevels: 2),
        );
        seenTransform = recording.seenTransform;
        expect(seenTransform, 'paragraph');
        expect(
          recording.seenOpts,
          equals(const ConvertOptions(sectnumlevels: 2)),
        );
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
          ..backendTraits = BackendTraits(
            basebackend: 'docbook',
            filetype: 'xml',
            outfilesuffix: '.xml',
          );
        final composite = CompositeConverter('seam-adopt', [
          FakeConverter('seam-adopt'),
        ], backendTraitsSource: source);
        // Shared by reference, as in Ruby (`init_backend_traits` assigns).
        expect(composite.backendTraits, same(source.backendTraits));
        expect(composite.backendTraits.basebackend, 'docbook');
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
  new(super.backend, [super.opts]);

  /// Registers this converter for [backends].
  static void registerFor([List<String> backends = const ['reg-self']]) {
    Converter.register(_SelfRegisteringConverter.new, backends);
  }

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => 'self';
}

/// Records the transform and options it was asked to convert with.
class _RecordingConverter extends Converter {
  /// Creates a recording converter.
  new(super.backend);

  /// The last transform seen by [convert].
  String? seenTransform;

  /// The last options seen by [convert].
  ConvertOptions? seenOpts;

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) {
    seenTransform = transform ?? node.nodeName;
    seenOpts = opts;
    return 'recorded';
  }
}

/// A [ComposedAware] delegate recording the composite it joined.
class _ComposedProbe extends Converter implements ComposedAware {
  /// Creates a probe converter.
  new(super.backend);

  /// The composite passed to [composed].
  CompositeConverter? seen;

  @override
  void composed(CompositeConverter composite) {
    seen = composite;
  }

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => null;
}
