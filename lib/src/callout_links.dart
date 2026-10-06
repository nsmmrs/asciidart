/// Callouts linked both ways in the HTML-based converters, with the
/// `callout-links` attribute set (asciidart's; Asciidoctor has none): each
/// marker links to its callout list item and is left out when the code is
/// copied, and each item links back to its first marker.
library;

import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/list.dart';

/// [marker], with `callout-links` set, as a link to its callout list item
/// that copying leaves out.
String calloutLink(Inline node, String marker) {
  final id = node.id;
  if (id == null || !node.document!.hasAttr('callout-links')) return marker;
  return '<a id="$id" class="conum-link" href="#$id-item" '
      'style="user-select:none">$marker</a>';
}

/// The ids of the callouts the callout list [item] explains, with
/// `callout-links` set; else none.
List<String> calloutIds(ListItem item) =>
    item.document!.hasAttr('callout-links')
    ? [
        for (final id in (item.attr('coids') ?? '').split(' '))
          if (id.isNotEmpty) id,
      ]
    : const [];

/// An anchor for each callout the callout list [item] explains (their
/// links lead there).
String calloutItemAnchors(ListItem item) =>
    [for (final id in calloutIds(item)) '<a id="$id-item"></a>'].join();

/// [label] as a link back to the first callout the callout list [item]
/// explains.
String calloutBack(ListItem item, String label) => switch (calloutIds(item)) {
  [final first, ...] => '<a href="#$first">$label</a>',
  _ => label,
};

/// A link from the callout list [item] (when its number isn't one) back
/// to its first callout.
String calloutBackArrow(ListItem item) => switch (calloutIds(item)) {
  [final first, ...] =>
    ' <a class="conum-back" href="#$first" '
        'title="Back to the code">&#8617;</a>',
  _ => '',
};
