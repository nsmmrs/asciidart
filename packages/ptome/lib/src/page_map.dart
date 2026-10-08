/// The print edition's page map (ADR-0012): the PDF writes it
/// (`pdf-page-map`), the EPUB reads it (`epub-page-map`) to mark the
/// print pages.
library;

import 'dart:convert';

/// The page labels of a PDF, and for each block, where it starts in the
/// source (`file:line`) and the first and last pages it is on.
final class PageMap {
  /// A page map of [labels] and [blocks].
  const new({required this.labels, required this.blocks});

  /// The label of each page, in order.
  final List<String> labels;

  /// The first and last page (counted from 1) of each block, by where it
  /// starts in the source (`file:line`).
  final Map<String, (int, int)> blocks;

  /// The map as the JSON file the PDF writes.
  String toJson() {
    final json = {
      'labels': labels,
      'blocks': [
        for (final MapEntry(:key, value: (first, last)) in blocks.entries)
          {'at': key, 'first': first, 'last': last},
      ],
    };
    return '${const JsonEncoder.withIndent(' ').convert(json)}\n';
  }

  /// The map in [json], or null when it is not one. JSON is untyped: this
  /// is the one place its values become typed.
  static PageMap? parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded case {
      'labels': final List<Object?> labels,
      'blocks': final List<Object?> blocks,
    }) {
      return PageMap(
        labels: [for (final l in labels) '$l'],
        blocks: {
          for (final b in blocks)
            if (b case {
              'at': final String at,
              'first': final int first,
              'last': final int last,
            })
              at: (first, last),
        },
      );
    }
    return null;
  }
}
