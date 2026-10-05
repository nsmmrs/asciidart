// Examples print their results to the console.
// ignore_for_file: avoid_print

import 'package:asciidart/asciidart.dart';

Future<void> main() async {
  // Convert a string to HTML (the body only).
  print(asciidoc.convert('Hello, *World*!'));

  // Parse a document, read its metadata and walk its tree.
  const source = '''
= Release Notes
:revnumber: 0.1.0
:labels: fast, faithful

== Features

* Fast
* Faithful

== Fixes

Nothing yet.
''';
  final doc = asciidoc.parse(source);
  print('${doc.title} ${doc.attributes['revnumber']}');
  print(doc.attributes.listValue('labels'));
  for (final section in doc.descendants<Section>()) {
    print('- ${section.title}: ${section.plainText.split('\n').join(', ')}');
  }

  // A configuration with an extension and an HTML override.
  final ad = Asciidart(
    extensions: [
      // issue:42[] links to the issue tracker.
      InlineMacro(
        'issue',
        (m) => m.link(
          'https://github.com/nsmmrs/asciidart/issues/${m.target}',
          text: '#${m.target}',
        ),
      ),
    ],
    html: (node, defaults) => switch (node) {
      final Admonition a =>
        '<aside class="${a.kind.name}">${defaults.content(a)}</aside>',
      _ => defaults.render(node),
    },
  );
  print(ad.convert('See issue:42[].\n\nNOTE: Overridden.'));

  // Diagnostics are part of the result.
  final broken = asciidoc.parse('See <<missing>>.')..convert();
  for (final d in broken.diagnostics) {
    print('${d.severity.name}: ${d.message}');
  }
}
