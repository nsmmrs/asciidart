# The asciidart API

This is the supported API of asciidart, designed from how people use
Asciidoctor as a library. Everything not listed here is private: it may
change in any release. Each scenario below is also a test
(`test/api/scenarios_test.dart`), written only against the public libraries.

There are three libraries:

| Import | For |
| --- | --- |
| `package:asciidart/asciidart.dart` | parsing, converting, the document tree, extensions, output overrides, diagnostics; no file system access, so it runs on the web and in Flutter |
| `package:asciidart/io.dart` | reading and writing files |
| `package:asciidart/cli.dart` | the `asciidart` command line, for building a custom command |

`tool/api_surface.txt` records every public member; CI fails when the
public API changes without updating it.

## Principles

- **One entry point.** An `Asciidart` object holds a configuration
  (safe mode, attributes, extensions, output overrides, highlighters) and
  converts any number of documents. `asciidoc` is the default instance.
  There are no global registries: two instances never affect each other.
- **Typed all the way.** The document is a sealed node tree (`switch` over
  it is checked for exhaustiveness), closed sets are enums, and options are
  named parameters, not maps.
- **Results are values.** Diagnostics are part of the result, not log lines
  on a global logger.
- **Safe by default.** Like Asciidoctor's API, conversions run in the
  `secure` safe mode unless asked otherwise.

## 1. Render AsciiDoc to HTML

```dart
import 'package:asciidart/asciidart.dart';

final html = asciidoc.convert('Hello, *World*!'); // the body only
final page = asciidoc.convert(
  source,
  standalone: true, // a complete HTML page
  attributes: {'icons': 'font'},
);
```

`convert` also takes `backend` (`Backend.html5`, `xhtml5`, `docbook5`,
`manpage`, or a custom backend's name) and `doctype`.

## 2. Read metadata, then render

```dart
final doc = asciidoc.parse(cardSource);

final card = Card(
  title: doc.title ?? 'Untitled',
  status: doc.attributes['status'] ?? 'backlog',
  priority: doc.attributes.intValue('priority') ?? 3,
  labels: doc.attributes.listValue('labels'), // "a, b, c"
);
final body = doc.toHtml(); // render the same parse
```

`asciidoc.parseHeader(source)` stops after the document header, for reading
metadata cheaply.

Planned (FEAT-q7q980): `doc.withAttribute('status', 'done').source`
rewrites only that header line of the source.

## 3. Walk and query the tree

```dart
for (final section in doc.descendants<Section>()) {
  index.add(id: section.id, title: section.title, text: section.plainText);
}
final javaSamples = doc.descendants<Listing>().where((l) => l.language == 'java');
final brokenXrefs = doc.diagnostics.where((d) => d.code == DiagnosticCode.unknownReference);
```

Every node has `parent`, `document`, `id`, `roles`, `attributes` and
`location` (file and line). Blocks add `title`, `style` and `blocks`.

## 4. Your own renderer

```dart
Widget build(Block block) => switch (block) {
  final Section s => Column(children: [Heading(s.level, s.title), ...s.blocks.map(build)]),
  final Paragraph p => Text(p.plainText),
  final Listing l => CodeView(l.source, language: l.language),
  final Admonition a => Callout(a.kind, text: a.plainText),
  final UnorderedList u => Bullets([for (final item in u.items) item.plainText]),
  // ... the compiler reports any block kind left out
};
```

Planned (FEAT-q86s3x): `inlines` on text-bearing blocks, the inline content
as a typed tree instead of converted HTML.

## 5. Customize the HTML for some elements

```dart
final ad = Asciidart(
  html: (node, defaults) => switch (node) {
    final Admonition a => '<aside class="callout ${a.kind.name}">${defaults.content(a)}</aside>',
    final InlineImage i => defaults.render(i).replaceFirst('<img', '<img loading="lazy"'),
    _ => defaults.render(node),
  },
);
```

The override sees every node, blocks and inline elements alike;
`defaults.render(node)` is asciidart's own HTML for it and
`defaults.content(block)` the HTML of its children.

Mustache templates (`templateDirs`) work as with `asciidart -T`.

## 6. Extensions

```dart
final ad = Asciidart(
  extensions: [
    InlineMacro('issue', (m) => m.link('https://github.com/o/r/issues/${m.target}', text: '#${m.target}')),
    BlockMacro('youtube', (m) => m.html('<iframe src="https://youtube.com/embed/${m.target}"></iframe>')),
    CustomBlock('shout', (b) => b.paragraph(b.source.toUpperCase()), on: {BlockKind.paragraph}),
    IncludeResolver((request) => request.target.startsWith('db:') ? database.read(request.target) : null),
    TreeProcessor((doc) {
      for (final image in doc.descendants<Image>()) {
        image.target = cdn(image.target);
      }
    }),
    Postprocessor((output, doc) => output.replaceAll('<p>', '<p class="x">')),
  ],
);
```

The kinds: `Preprocessor` (edit the source lines before parsing),
`IncludeResolver` (supply included content; return `null` to fall back to
the default), `CustomBlock` (handle a block style), `BlockMacro`,
`InlineMacro`, `TreeProcessor` (inspect or change the parsed tree),
`Postprocessor` (edit the output), and `Docinfo` (add content to the HTML
head or footer). A resolver may return a `Future`; the asynchronous
methods (`parseAsync`, `convertAsync`) wait for it.

## 7. Fail on warnings

```dart
final doc = ad.parse(source, path: 'docs/index.adoc');
final html = doc.toHtml();
if (doc.diagnostics.any((d) => d.severity >= Severity.warning)) {
  for (final d in doc.diagnostics) print('${d.location}: ${d.message}');
}
```

Diagnostics collect while parsing and converting. `Diagnostic` has
`severity`, `message`, `location` and a `code` (a `DiagnosticCode`, `other`
for messages without a specific code). `Asciidart(onDiagnostic: ...)` sees
each one as it is reported, including those of `convert`, which returns
only the output.

## 8. Files

```dart
import 'package:asciidart/io.dart';

const ad = Asciidart(safe: SafeMode.unsafe);
final doc = await ad.convertFile('docs/index.adoc', toDir: 'build');
await for (final result in ad.convertTree('docs', toDir: 'build')) {
  print(result.outputPath);
}
```

`parseFile` reads a document from a file. File operations follow the
instance's safe mode like everything else: `SafeMode.safe` lets a document
include files below its own directory, and writing output outside the base
directory (as `convertTree` into `build/` does) needs `SafeMode.unsafe`, as
in Asciidoctor. `convertTree` skips files and folders whose names start
with `_` or `.` (partials meant to be included).

## Also supported

- **Remote content.** `parseAsync` and `convertAsync` fetch what a document
  includes from a URI once `allow-uri-read` is set.
- **Syntax highlighting.** `Asciidart(highlighters: {'name': MyHighlighter()})`
  registers a custom `Highlighter` under a `source-highlighter` name.
- **Templates.** `Asciidart(templateDirs: [...])` loads Mustache templates
  that replace the HTML of the nodes they name, as `asciidart -T` does.
- **Custom commands.** `runCli(args, asciidart: Asciidart(...))` runs the
  `asciidart` command line with extensions and overrides compiled in;
  `asciidart init-config` generates such a project.
- **Errors.** Problems that stop a conversion throw `AsciidartException`.
