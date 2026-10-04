/// Pre-flattened Mustache render context for template-converter nodes.
///
/// Port foundation for the render context of
/// `lib/asciidoctor/converter/template.rb` (ADR-0002, T2). Tilt templates in
/// Ruby execute with the node as `self`, so they call arbitrary node methods.
/// `package:mustache_template` resolves Map keys and dotted paths only — Dart
/// object members are invisible to it (probe recorded in ADR-0002 T2) — so
/// [buildTemplateContext] pre-flattens each node to a Map before rendering.
///
/// ## Context vocabulary
///
/// Every render receives these keys (`null` when the node has no value, which
/// renders as empty output in the lenient adapter, see `template.dart`):
///
/// | Key | Value |
/// | --- | ----- |
/// | `content` | Converted content: `AbstractBlock.content()` (usually a String; a List of items for lists, mirroring Ruby, which templates can iterate as a section), `Inline.content()` (the text), else `null`. |
/// | `text` | Inline/list-item text (`Inline.text`, `ListItem.text`), else `null`. |
/// | `id` | The node id (`AbstractNode.id`). |
/// | `role` | The node role (`AbstractNode.role`). |
/// | `roles` | All roles (`AbstractNode.roles`). |
/// | `title` | Converted block title (`AbstractBlock.title`, caption excluded; the doctitle on documents), else `null`. |
/// | `caption` | Block caption (`AbstractBlock.caption`), else `null`. |
/// | `context` | The node context (e.g. `'paragraph'`). |
/// | `node_name` | The node name (e.g. `'inline_quoted'` on inlines). |
/// | `attributes` | Shallow copy of the node attribute map (supports dotted lookups such as `{{attributes.foo}}` and truthiness sections). |
/// | `attr` | Section lambda for attributes with arguments: `{{#attr}}name{{/attr}}`, with an optional `=default` suffix (`{{#attr}}lang=en{{/attr}}`). Falls back to the document attributes, mirroring Ruby's inheriting `attr` default in Tilt templates. |
/// | `document` | Shallow document map (`title`, `attributes`); `null` while the node is detached. Never nested recursively. |
/// | `items` | List items, each pre-flattened with [buildTemplateContext] (description-list pairs become `{'terms': [...], 'description': ...}`); `null` on non-list nodes. |
/// | `sections` | Child sections of a document or section node, each pre-flattened with [buildTemplateContext] (so `{{#sections}}{{title}}{{/sections}}` lists them and nesting recurses); `null` on other nodes. This is what a custom `outline` template iterates. |
///
/// [opts] (the per-call options map, mirroring the Tilt locals in Ruby's
/// `TemplateConverter#convert`) and [helpers] (path-(a) lambdas per ADR-0002
/// T4) are merged in as top-level keys; on collision the explicit call-site
/// values win over the node-derived ones.
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:mustache_template/mustache_template.dart' show LambdaContext;

/// Computes one custom helper value for [node] on every render.
///
/// Helpers are path-(a) Dart lambdas (ADR-0002 T4): unlike Ruby's
/// per-directory `helpers.rb` (arbitrary loadable code), the Dart port
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
  Map<String, Object?>? opts,
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
  if (opts != null) context.addAll(opts);
  return context;
}

/// The converted content of [node], mirroring Ruby's `content` call in Tilt
/// templates (a List of items on lists, a String elsewhere).
Object? _contentOf(AbstractNode node) {
  if (node is AbstractBlock) return node.content();
  if (node is Inline) return node.content();
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
/// looked up with document fallback, mirroring Ruby's inheriting `attr`
/// default as used by Tilt templates.
Object Function(LambdaContext) _attrLambda(AbstractNode node) {
  return (LambdaContext ctx) {
    final spec = ctx.renderString().trim();
    final equals = spec.indexOf('=');
    final Object? value;
    if (equals == -1) {
      value = node.attr(spec, null, true);
    } else {
      value = node.attr(
        spec.substring(0, equals),
        spec.substring(equals + 1),
        true,
      );
    }
    return value?.toString() ?? '';
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
    'title': doc.attr('doctitle')?.toString(),
    'attributes': Map<String, Object?>.of(doc.attributes),
  };
}

/// Pre-flattened list items, or `null` when [node] is not a list.
///
/// Outline-list items flatten to their own render contexts.
/// Description-list pairs flatten to `{'terms': [...], 'description': ...}`.
Object? _itemsOf(AbstractNode node) {
  if (node is! ListBlock) return null;
  if (node.context == 'dlist') {
    return <Map<String, Object?>>[
      for (final pair in node.items) _flattenDlistPair(pair! as List<Object?>),
    ];
  }
  return <Object?>[
    for (final item in node.items)
      if (item is AbstractNode) buildTemplateContext(item) else item.toString(),
  ];
}

/// Pre-flattened child sections, or `null` on non-sectioned nodes.
///
/// Only document and section nodes carry sections; each child section
/// flattens to its own render context (recursing into subsections), so a
/// custom `outline` template iterates them with `{{#sections}}`. The
/// recursion always terminates: section nesting is finite and the
/// flattened children never re-enter their own ancestors.
Object? _sectionsOf(AbstractNode node) {
  if (node is! AbstractBlock) return null;
  if (node.context != 'document' && node.context != 'section') return null;
  return <Object?>[
    for (final section in node.sections) buildTemplateContext(section),
  ];
}

/// Flattens one `[terms, description]` description-list pair.
Map<String, Object?> _flattenDlistPair(List<Object?> pair) {
  final terms = pair[0]! as List<Object?>;
  final description = pair[1];
  return <String, Object?>{
    'terms': <Object?>[
      for (final term in terms)
        if (term is AbstractNode)
          buildTemplateContext(term)
        else
          term.toString(),
    ],
    'description': description is AbstractNode
        ? buildTemplateContext(description)
        : null,
  };
}
