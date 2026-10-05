/// Pre-flattened Mustache render context for template-converter nodes.
///
/// Port foundation for the render context of
/// `lib/asciidoctor/converter/template.rb` (ADR-0002, T2). Asciidoctor's
/// Tilt templates execute with the node as `self`, so they call arbitrary
/// node methods.
/// `package:mustache_template` resolves Map keys and dotted paths only — Dart
/// object members are invisible to it (probe recorded in ADR-0002 T2) — so
/// [buildTemplateContext] pre-flattens each node to a Map before rendering.
///
/// ## Context vocabulary
///
/// Every render receives these keys (`null` when the node has no value, which
/// renders as empty output in the lenient adapter, see `template.dart`):
///
/// - `content`: Converted content: `AbstractBlock.content()`, the text of an
///   [Inline], else `null`.
/// - `text`: Inline/list-item text (`Inline.text`, `ListItem.text`), else
///   `null`.
/// - `id`: The node id (`AbstractNode.id`).
/// - `role`: The node role (`AbstractNode.role`).
/// - `roles`: All roles (`AbstractNode.roles`).
/// - `title`: Converted block title (`AbstractBlock.title`, caption excluded;
///   the doctitle on documents), else `null`.
/// - `caption`: Block caption (`AbstractBlock.caption`), else `null`.
/// - `context`: The node context (e.g. `'paragraph'`).
/// - `node_name`: The node name (e.g. `'inline_quoted'` on inlines).
/// - `attributes`: Shallow copy of the node attribute map (supports dotted
///   lookups such as `{{attributes.foo}}` and truthiness sections).
/// - `attr`: Section lambda for attributes with arguments:
///   `{{#attr}}name{{/attr}}`, with an optional `=default` suffix
///   (`{{#attr}}lang=en{{/attr}}`). Falls back to the document attributes,
///   as `attr` does.
/// - `document`: Shallow document map (`title`, `attributes`); `null` while the
///   node is detached. Never nested recursively.
/// - `items`: List items, each pre-flattened with [buildTemplateContext]
///   (description-list pairs become `{'terms': [...], 'description': ...}`);
///   `null` on non-list nodes.
/// - `sections`: Child sections of a document or section node, each
///   pre-flattened with [buildTemplateContext] (so
///   `{{#sections}}{{title}}{{/sections}}` lists them and nesting recurses);
///   `null` on other nodes. This is what a custom `outline` template iterates.
///
/// The per-call options (`toclevels`, `sectnumlevels`) and `helpers`
/// (path-(a) lambdas per ADR-0002 T4) are merged in as top-level keys; on
/// collision the explicit call-site values win over the node-derived ones.
///
/// The render context is the boundary with `package:mustache_template`,
/// which reads untyped maps, lists, strings, booleans and lambdas; it is
/// the one place where values are `Object?`.
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/converter.dart' show ConvertOptions;
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/list.dart';
import 'package:mustache_template/mustache_template.dart' show LambdaContext;

/// Computes one custom helper value for [node] on every render.
///
/// Helpers are path-(a) Dart lambdas (ADR-0002 T4): unlike Asciidoctor's
/// per-directory `helpers.rb` (arbitrary loadable code), this port
/// receives helper code through registration, and the context builder injects
/// each computed value into the render context under its registered name.
typedef TemplateHelper = Object? Function(AbstractNode node);

/// Flattens [node] to the Mustache render context described above.
///
/// [helpers] are evaluated against [node] and injected by name; [opts] are
/// merged in as top-level keys (winning on collision).
Map<String, Object?> buildTemplateContext(
  AbstractNode node, {
  Map<String, TemplateHelper> helpers = const <String, TemplateHelper>{},
  ConvertOptions? opts,
}) {
  final context = <String, Object?>{
    'content': _contentOf(node),
    'text': _textOf(node),
    'id': node.id,
    'role': node.role,
    'roles': node.roles,
    'title': node is AbstractBlock ? node.title : null,
    'caption': node is AbstractBlock ? node.caption : null,
    'context': node.context,
    'node_name': node.nodeName,
    'attributes': Map<String, Object?>.of(node.attributes),
    'attr': _attrLambda(node),
    'document': _documentOf(node),
    'items': _itemsOf(node),
    'sections': _sectionsOf(node),
  };
  for (final entry in helpers.entries) {
    context[entry.key] = entry.value(node);
  }
  if (opts?.toclevels case final toclevels?) context['toclevels'] = toclevels;
  if (opts?.sectnumlevels case final levels?) {
    context['sectnumlevels'] = levels;
  }
  return context;
}

/// The converted content of [node].
String? _contentOf(AbstractNode node) {
  if (node is AbstractBlock) return node.content();
  if (node is Inline) return node.text;
  return null;
}

/// The primary text of [node] when it has one (inlines, list items).
String? _textOf(AbstractNode node) {
  if (node is Inline) return node.text;
  if (node is ListItem) return node.text;
  return null;
}

/// Section lambda resolving `{{#attr}}name[=default]{{/attr}}`.
///
/// The section body is rendered first (so it may itself contain tags), then
/// looked up with document fallback, as `attr` does.
Object Function(LambdaContext) _attrLambda(AbstractNode node) {
  return (LambdaContext ctx) {
    final spec = ctx.renderString().trim();
    final equals = spec.indexOf('=');
    if (equals == -1) return node.attr(spec, null, spec) ?? '';
    final name = spec.substring(0, equals);
    return node.attr(name, spec.substring(equals + 1), name) ?? '';
  };
}

/// Shallow document map for [node]'s document (`null` while detached).
///
/// Deliberately shallow (title + attributes only): the full document tree is
/// never nested into its own render context.
Map<String, Object?>? _documentOf(AbstractNode node) {
  final doc = node.document;
  if (doc == null) return null;
  return <String, Object?>{
    'title': doc.attr('doctitle'),
    'attributes': Map<String, Object?>.of(doc.attributes),
  };
}

/// Pre-flattened list items, or `null` when [node] is not a list.
///
/// Outline-list items flatten to their own render contexts.
/// Description-list pairs flatten to `{'terms': [...], 'description': ...}`.
List<Map<String, Object?>>? _itemsOf(AbstractNode node) {
  if (node is! ListBlock) return null;
  if (node.context == 'dlist') {
    return <Map<String, Object?>>[
      for (final entry in node.entries) _flattenDlistEntry(entry),
    ];
  }
  return <Map<String, Object?>>[
    for (final item in node.items) buildTemplateContext(item),
  ];
}

/// Pre-flattened child sections, or `null` on non-sectioned nodes.
///
/// Only document and section nodes carry sections; each child section
/// flattens to its own render context (recursing into subsections), so a
/// custom `outline` template iterates them with `{{#sections}}`. The
/// recursion always terminates: section nesting is finite and the
/// flattened children never re-enter their own ancestors.
List<Map<String, Object?>>? _sectionsOf(AbstractNode node) {
  if (node is! AbstractBlock) return null;
  if (node.context != 'document' && node.context != 'section') return null;
  return <Map<String, Object?>>[
    for (final section in node.sections) buildTemplateContext(section),
  ];
}

/// Flattens one description-list entry.
Map<String, Object?> _flattenDlistEntry(DlistEntry entry) {
  final description = entry.description;
  return <String, Object?>{
    'terms': <Map<String, Object?>>[
      for (final term in entry.terms) buildTemplateContext(term),
    ],
    'description': description == null
        ? null
        : buildTemplateContext(description),
  };
}
