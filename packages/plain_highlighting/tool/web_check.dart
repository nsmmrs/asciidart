// Compiled to JavaScript in CI: highlights code in several languages, and
// detects one, printing a digest of the HTML; the CI job compares it with
// the Dart VM's, as the output must be the same on both.
import 'dart:convert';

import 'package:plain_highlighting/plain_highlighting.dart';

const _samples = {
  'dart': 'final greeting = "hello \${name}"; // a comment\n',
  'python': 'def greet(name):\n    return f"hi {name}"  # comment\n',
  'javascript': 'const x = /a+b/g.test(`t\${1 + 2}`);\n',
  'rust': 'fn main() { let v: Vec<u8> = vec![1, 2]; println!("{v:?}"); }\n',
  'xml': '<doc a="1"><!-- c --><![CDATA[x]]></doc>\n',
  'sql': "SELECT id, name FROM users WHERE name LIKE 'a%';\n",
};

void main() {
  final parts = [
    for (final MapEntry(key: language, value: code) in _samples.entries)
      highlighting.highlight(code, language: language).html,
    highlighting.highlightAuto(_samples['python']!).language ?? '-',
  ];
  // An Adler-32 style checksum: its sums stay small enough for
  // JavaScript's numbers.
  var a = 1;
  var b = 0;
  final bytes = utf8.encode(parts.join('\u0000'));
  for (final byte in bytes) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${parts.length} ${bytes.length} $b-$a');
}
