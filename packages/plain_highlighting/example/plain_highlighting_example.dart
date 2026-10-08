// Examples print their results to the console.
// ignore_for_file: avoid_print

import 'package:plain_highlighting/plain_highlighting.dart';

void main() {
  // Highlight code in a known language (a name or an alias).
  final dart = highlighting.highlight(
    'final greeting = "hi";',
    language: 'dart',
  );
  print(dart.html);

  // Let plain_highlighting pick the language.
  final auto = highlighting.highlightAuto(
    'SELECT name FROM users WHERE id = 1;',
  );
  print('${auto.language} (relevance ${auto.relevance}): ${auto.html}');

  // Language names and aliases.
  print(highlighting.hasLanguage('js')); // true
  print(highlighting.displayName('sh')); // Bash
}
