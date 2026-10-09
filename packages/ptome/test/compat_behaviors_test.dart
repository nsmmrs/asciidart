/// Every behavior `asciidoctor-compat` sets is documented with both its
/// values (doc/books.md, "From Asciidoctor").
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/compat.dart';
import 'package:test/test.dart';

void main() {
  final doc = File('doc/books.md').readAsStringSync();
  for (final behavior in Behavior.values) {
    test(behavior.attribute, () {
      final row = doc
          .split('\n')
          .firstWhere(
            (line) => line.startsWith('| `${behavior.attribute}` |'),
            orElse: () => '',
          );
      expect(row, isNotEmpty, reason: 'documented in doc/books.md');
      expect(row, contains('`${behavior.ptome}`'));
      expect(row, contains('`${behavior.stable}`'));
    });
  }
}
