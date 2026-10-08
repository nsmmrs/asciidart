/// Upstream's markup tests (`vendor/highlight.js/test/markup`): each
/// `<language>/<name>.txt` highlighted as `<language>` gives exactly
/// `<name>.expect.txt` (both trimmed, as upstream compares them).
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_highlighting/plain_highlighting.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('vendor/highlight.js/test/markup');
  final languages = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in languages) {
    final language = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    group(language, () {
      final cases =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.expect.txt'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final expected in cases) {
        final source = File(expected.path.replaceFirst('.expect.txt', '.txt'));
        final name = expected.uri.pathSegments.last.replaceFirst(
          '.expect.txt',
          '',
        );
        test(name, () {
          final actual = highlighting
              .highlight(source.readAsStringSync(), language: language)
              .html;
          expect(actual.trim(), expected.readAsStringSync().trim());
        });
      }
    });
  }
}
