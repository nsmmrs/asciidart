// Examples print their results to the console.
// ignore_for_file: avoid_print

import 'package:hilite/hilite.dart';

void main() {
  // Highlight code in a known language (a name or an alias).
  final dart = hilite.highlight('final greeting = "hi";', language: 'dart');
  print(dart.html);

  // Let hilite pick the language.
  final auto = hilite.highlightAuto('SELECT name FROM users WHERE id = 1;');
  print('${auto.language} (relevance ${auto.relevance}): ${auto.html}');

  // Language names and aliases.
  print(hilite.hasLanguage('js')); // true
  print(hilite.displayName('sh')); // Bash
}
