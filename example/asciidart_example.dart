// Examples print their results to the console.
// ignore_for_file: avoid_print

import 'package:asciidart/asciidart.dart';
import 'package:asciidart/converter.dart';
import 'package:asciidart/extensions.dart';

Future<void> main() async {
  // Convert a string to an HTML fragment.
  print(convert('Hello, *World*!'));

  // Load a document and walk its tree.
  const source = '''
= Release Notes
:revnumber: 0.1.0

== Features

* Fast
* Faithful

== Fixes

Nothing yet.
''';
  final doc = load(
    source,
    options: const AsciidoctorOptions(safe: SafeMode.safe),
  );
  print('${doc.doctitle()} (${doc.attr('revnumber')})');
  for (final section in doc.sections) {
    print('- ${section.title}: ${section.blocks.length} block(s)');
  }

  // An inline macro extension: emoji:wave[] becomes <strong>:wave:</strong>.
  final extensions = Extensions.create(
    build: (registry) {
      registry.inlineMacro(
        name: 'emoji',
        build: (processor) {
          processor.onProcess = (parent, target, attributes) => processor
              .createInline(parent, 'quoted', ':$target:', type: 'strong');
        },
      );
    },
  );
  print(
    convert(
      'Hi emoji:wave[]',
      AsciidoctorOptions(extensionRegistry: extensions),
    ),
  );

  // Override one transform of the HTML converter with a Dart function.
  final templates = TemplateRegistry()
    ..registerFunction(
      'paragraph',
      (node, [opts]) => '<p class="custom">${(node as Block).content()}</p>',
    );
  final converter = TemplateConverter(
    'html5',
    const ConverterOptions(),
    templates,
  ).withFallback(Html5Converter('html5'));
  print(
    convert(
      'Custom paragraph.\n\n----\nlisting\n----',
      AsciidoctorOptions(converter: converter),
    ),
  );

  // Remote content: the async API fetches what a document includes once
  // allow-uri-read is set (here nothing is remote, so nothing is fetched).
  final html = await convertAsync(
    'Fetched on demand.',
    const AsciidoctorOptions(attributes: {'allow-uri-read': ''}),
  );
  print(html);
}
