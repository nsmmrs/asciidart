/// Tests for the template converter port (`template.dart`) and the
/// pre-flattened render context (`template_context.dart`).
///
/// Covers ADR-0002 wave A: the [TemplateLoader] seam contract, the
/// [TemplateRegistry] (Mustache sources + path-(a) functions + helpers), the
/// [MustacheTemplate] adapter (raw-by-default, lenient), context flattening
/// (content/text/id/role/title/attr-lambda/document/items), and composite
/// integration (template wins per transform, built-in fallback).
///
/// Nodes come from small parsed documents (`Document(src, opts).parse()`),
/// so content/title/attr values exercise the real parser and substitutors.
library;

import 'package:asciidoctor/src/composite.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/template.dart';
import 'package:test/test.dart';

/// Parses [src] into an embedded HTML5 document.
Document parseDoc(String src) => Document(src, const <String, Object?>{
  'backend': 'html5',
  'standalone': false,
}).parse();

/// In-memory [TemplateLoader] resolving synchronously.
class MapLoader implements TemplateLoader {
  /// Creates a loader returning [sources].
  new(this.sources);

  /// The sources this loader returns.
  final Map<String, String> sources;

  @override
  Map<String, String> load() => sources;
}

/// In-memory [TemplateLoader] resolving asynchronously.
class AsyncMapLoader implements TemplateLoader {
  /// Creates a loader returning [sources].
  new(this.sources);

  /// The sources this loader returns.
  final Map<String, String> sources;

  @override
  Future<Map<String, String>> load() async => sources;
}

void main() {
  group('TemplateRegistry', () {
    test('registers templates and reports handles per name', () {
      final registry = TemplateRegistry();
      expect(registry.handles('paragraph'), isFalse);
      registry.registerTemplate('paragraph', '<p>{{content}}</p>');
      expect(registry.handles('paragraph'), isTrue);
      expect(registry.handles('section'), isFalse);
    });

    test('re-registering a name replaces it (last-wins)', () {
      final registry = (TemplateRegistry())
        ..registerTemplate('paragraph', 'first');
      registry.registerTemplate('paragraph', 'second');
      expect(registry.templates['paragraph'], 'second');
    });

    test('templates getter returns a copy of the sources', () {
      final registry = TemplateRegistry(
        templates: const {'paragraph': '<p>{{content}}</p>'},
      );
      final copy = registry.templates;
      expect(copy, {'paragraph': '<p>{{content}}</p>'});
      copy['paragraph'] = 'mutated';
      expect(registry.templates['paragraph'], '<p>{{content}}</p>');
    });

    test('registers functions and helpers', () {
      final registry = TemplateRegistry();
      registry.registerFunction('paragraph', (node, [opts]) => 'fn');
      registry.registerHelper('up', (node) => node.nodeName.toUpperCase());
      expect(registry.handles('paragraph'), isTrue);
      expect(registry.functions.keys, contains('paragraph'));
      expect(registry.helpers.keys, contains('up'));
    });

    test('consumes a TemplateLoader map (wave-B seam)', () async {
      final syncSources = MapLoader(const {'paragraph': '<p>{{content}}</p>'})
          .load();
      expect(syncSources, isA<Map<String, String>>());
      final asyncSources = await AsyncMapLoader(const {
        'paragraph': '<p>{{content}}</p>',
      }).load();
      final registry = TemplateRegistry(templates: asyncSources);
      expect(registry.handles('paragraph'), isTrue);
    });
  });

  group('MustacheTemplate adapter', () {
    test('renders content raw by default (no double-escaping)', () {
      final paragraph = parseDoc('*bold*').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '<p>{{content}}</p>');
      expect(converter.convert(paragraph), '<p><strong>bold</strong></p>');
    });

    test('escapes when the registry opts into htmlEscapeValues', () {
      final paragraph = parseDoc('*bold*').blocks[0];
      final converter = TemplateConverter(
        'html5',
        const <String, Object?>{},
        TemplateRegistry(htmlEscapeValues: true),
      )..register('paragraph', '<p>{{content}}</p>');
      expect(
        converter.convert(paragraph),
        '<p>&lt;strong&gt;bold&lt;&#x2F;strong&gt;</p>',
      );
    });

    test('renders missing keys as empty (lenient)', () {
      final paragraph = parseDoc('hi').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '<p>{{missing}}!</p>');
      expect(converter.convert(paragraph), '<p>!</p>');
    });
  });

  group('context flattening', () {
    test('exposes id, role, title, context and node_name', () {
      final paragraph = parseDoc('[#myid.myrole]\n.My Title\ncontent')
          .blocks[0];
      final converter = TemplateConverter('html5')
        ..register(
          'paragraph',
          '{{id}}|{{role}}|{{title}}|{{context}}|{{node_name}}',
        );
      expect(
        converter.convert(paragraph),
        'myid|myrole|My Title|paragraph|paragraph',
      );
    });

    test('exposes attributes and dotted attribute paths', () {
      final paragraph = parseDoc('[foo="bar"]\ncontent').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '{{attributes.foo}}');
      expect(converter.convert(paragraph), 'bar');
    });

    test('attr lambda resolves node attributes', () {
      final paragraph = parseDoc('[foo="bar"]\ncontent').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '{{#attr}}foo{{/attr}}');
      expect(converter.convert(paragraph), 'bar');
    });

    test('attr lambda falls back to document attributes', () {
      final paragraph = parseDoc(':lang: fr\n\ncontent').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '{{#attr}}lang{{/attr}}');
      expect(converter.convert(paragraph), 'fr');
    });

    test('attr lambda supports =default', () {
      final paragraph = parseDoc('content').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '{{#attr}}lang=en{{/attr}}');
      expect(converter.convert(paragraph), 'en');
    });

    test('attr lambda renders missing attributes as empty', () {
      final paragraph = parseDoc('content').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '[{{#attr}}nope{{/attr}}]');
      expect(converter.convert(paragraph), '[]');
    });

    test('exposes document title and attributes', () {
      final doc = parseDoc('= Doc Title\n:foo: bar\n\ncontent');
      final converter = TemplateConverter('html5')
        ..register(
          'paragraph',
          '{{document.title}}|{{document.attributes.foo}}',
        );
      expect(converter.convert(doc.blocks[0]), 'Doc Title|bar');
    });

    test('iterates outline-list items with text', () {
      final list = parseDoc('* a\n* b\n').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('ulist', '{{#items}}[{{text}}]{{/items}}');
      expect(converter.convert(list), '[a][b]');
    });

    test('flattens description-list pairs', () {
      final list = parseDoc('term:: def\n').blocks[0];
      final converter = TemplateConverter('html5')
        ..register(
          'dlist',
          '{{#items}}{{#terms}}{{text}}={{/terms}}'
              '{{description.text}}{{/items}}',
        );
      expect(converter.convert(list), 'term=def');
    });

    test('exposes table captions', () {
      final table = parseDoc('.My table\n|===\n| a\n|===\n').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('table', '{{caption}}{{title}}');
      expect(converter.convert(table), 'Table 1. My table');
    });

    test('converts inline nodes through inline templates', () {
      final doc = parseDoc('content');
      final inline = Inline(
        doc,
        'quoted',
        text: '<em>x</em>',
        type: 'emphasis',
      );
      expect(inline.nodeName, 'inline_quoted');
      final converter = TemplateConverter('html5')
        ..register('inline_quoted', 'Q:{{content}}');
      expect(converter.convert(inline), 'Q:<em>x</em>');
    });
  });

  group('path-(a) functions', () {
    test('function transforms convert the node', () {
      final paragraph = parseDoc('hi').blocks[0];
      final converter = TemplateConverter('html5')
        ..registerFunction('paragraph', (node, [opts]) => 'FN');
      expect(converter.convert(paragraph), 'FN');
    });

    test('functions receive convert opts', () {
      final paragraph = parseDoc('hi').blocks[0];
      Map<String, Object?>? seen;
      final converter = TemplateConverter('html5')
        ..registerFunction('paragraph', (node, [opts]) {
          seen = opts;
          return 'FN';
        });
      converter.convert(paragraph, 'paragraph', const {'x': 1});
      expect(seen, {'x': 1});
    });

    test('functions win over templates for the same transform', () {
      final paragraph = parseDoc('hi').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', 'template')
        ..registerFunction('paragraph', (node, [opts]) => 'function');
      expect(converter.convert(paragraph), 'function');
    });

    test('helpers are injected into the render context', () {
      final paragraph = parseDoc('hi').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '{{up}}')
        ..registerHelper('up', (node) => node.nodeName.toUpperCase());
      expect(converter.convert(paragraph), 'PARAGRAPH');
    });
  });

  group('TemplateConverter semantics', () {
    test('raises StateError for a missing transform', () {
      final section = parseDoc('== Section\n\ntext\n').blocks[0];
      final converter = TemplateConverter('html5');
      expect(
        () => converter.convert(section),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Could not find a custom template to handle transform: section',
          ),
        ),
      );
    });

    test('trims only the right side for non-document transforms', () {
      final paragraph = parseDoc('hi').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '  <p>x</p>\n\n');
      expect(converter.convert(paragraph), '  <p>x</p>');
    });

    test('strips document output on both sides', () {
      final doc = parseDoc('hi');
      final converter = TemplateConverter('html5')
        ..register('document', '\n<div>{{content}}</div>\n');
      final result = converter.convert(doc)! as String;
      expect(result.startsWith('<div>'), isTrue);
      expect(result.endsWith('</div>'), isTrue);
    });

    test('convert opts become template locals', () {
      final paragraph = parseDoc('hi').blocks[0];
      final converter = TemplateConverter('html5')
        ..register('paragraph', '{{extra}}');
      expect(
        converter.convert(paragraph, 'paragraph', const {'extra': 'X'}),
        'X',
      );
    });

    test('does not claim supportsTemplates (mirrors Ruby)', () {
      expect(TemplateConverter('html5').supportsTemplates, isFalse);
    });
  });

  group('composite integration', () {
    test('template wins per transform, builtin handles the rest', () {
      final doc = parseDoc('para\n\n* a\n* b\n');
      final templateConverter = TemplateConverter('html5')
        ..register('paragraph', '<p class="custom">{{content}}</p>');
      final composite = templateConverter.withFallback(Html5Converter('html5'));
      expect(composite, isA<CompositeConverter>());
      expect(composite.convert(doc.blocks[0]), '<p class="custom">para</p>');
      expect(composite.convert(doc.blocks[1]), contains('<ul>'));
    });

    test('composite adopts the fallback backend traits', () {
      final composite = TemplateConverter('html5')
          .withFallback(Html5Converter('html5'));
      expect(composite.outfileSuffix, '.html');
      expect(composite.baseBackend, 'html');
    });

    test('converterFor caches the template for its transform', () {
      final doc = parseDoc('para');
      final templateConverter = TemplateConverter('html5')
        ..register('paragraph', '<p>{{content}}</p>');
      final composite = templateConverter.withFallback(Html5Converter('html5'));
      expect(composite.converterFor('paragraph'), same(templateConverter));
      expect(composite.converterFor('ulist'), isA<Html5Converter>());
      expect(composite.convert(doc.blocks[0]), '<p>para</p>');
    });
  });
}
