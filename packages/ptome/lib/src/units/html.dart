/// Units in HTML (ADR-0020), for the HTML5 and EPUB 3 converters: a unit's
/// mark is a span with the unit's ID and what it is (`class="unit"`,
/// `data-scheme`, `data-level`, `data-unit`), around its label; a note's
/// caller and its unit's entry are spans of their stream; a unit that is
/// blocks is a `div` around them.
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/inline.dart';

/// [value] escaped for an attribute in double quotes.
String _attr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');

/// The `data-` attributes for [names] that [attributes] has.
String _data(Map<String, String> attributes, List<String> names) => [
  for (final name in names)
    if (attributes[name] case final value?) ' data-$name="${_attr(value)}"',
].join();

/// A unit's mark: `<span id="v-exo-34-6" class="unit" data-scheme="bible"
/// data-level="verse" data-unit="Exod 34:6"><sup>6</sup></span>`; a
/// unit's end, `class="unit-end"`.
String htmlUnitMark(Inline node) {
  final id = node.id == null ? '' : ' id="${_attr(node.id!)}"';
  final kind = node.type == 'end' ? 'unit-end' : 'unit';
  final data = _data(node.attributes, const ['scheme', 'level', 'unit']);
  return '<span$id class="$kind"$data>${node.text ?? ''}</span>';
}

/// A note's caller (`class="note-call"`) or its unit's entry
/// (`class="note-entry"` and the entry's role), with its stream.
String htmlNote(Inline node) {
  final kind = node.type == 'entry' ? 'note-entry' : 'note-call';
  final role = node.role;
  final data = _data(node.attributes, const ['stream']);
  return '<span class="$kind${role == null ? '' : ' ${_attr(role)}'}"$data>'
      '${node.text ?? ''}</span>';
}

/// A unit that is blocks, around their [content].
String htmlUnitBlock(AbstractBlock node, String content) {
  final id = node.id == null ? '' : ' id="${_attr(node.id!)}"';
  final role = node.role;
  final data = _data(node.attributes, const ['scheme', 'level', 'unit']);
  return '<div$id class="unit${role == null ? '' : ' ${_attr(role)}'}"$data>\n'
      '$content\n'
      '</div>';
}
