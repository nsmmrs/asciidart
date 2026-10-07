# asciidart

asciidart is an AsciiDoc processor written in Dart and compiled to
JavaScript. It converts AsciiDoc to HTML 5, DocBook 5 and man pages
compatibly with [Asciidoctor](https://asciidoctor.org) (its development
version, 2.1.0.alpha.0, with fixes for bugs it still has), and is not
affiliated with or endorsed by the Asciidoctor project.

It runs on Node.js (20.19 or later) and in browsers, ships TypeScript
types, and provides the `asciidart` command. Its API is the Dart API's, with
the same names and shapes: see
[the usage scenarios](https://github.com/nsmmrs/asciidart/blob/master/doc/api.md).

## Render and read

```js
import { asciidoc, Section } from 'asciidart'

asciidoc.convert('Hello, *World*!') // '<div class="paragraph">...'

const doc = asciidoc.parse('= Title\n:status: draft\n\n== Section\n\ntext')
doc.title // 'Title'
doc.attributes.get('status') // 'draft'
doc.descendants(Section).map((s) => s.title) // ['Section']
doc.toHtml()
```

`require('asciidart')` works too. A parsed document is a tree of classes
(`Section`, `Paragraph`, `Listing`, `Admonition`, lists, tables, inline
elements), so `instanceof` tells nodes apart, and the same node is always
the same object.

## Configure

```js
import { Admonition, Asciidart, InlineMacro, SafeMode } from 'asciidart'

const ad = new Asciidart({
  safe: SafeMode.server,
  attributes: { icons: 'font' },
  extensions: [
    new InlineMacro('issue', (m) =>
      m.link(`https://example.org/issues/${m.target}`, { text: `#${m.target}` })
    ),
  ],
  html: (node, defaults) =>
    node instanceof Admonition
      ? `<aside class="${node.kind}">${defaults.content(node)}</aside>`
      : defaults.render(node),
})

ad.convert('See issue:42[].', { standalone: true })
```

Extensions are `InlineMacro`, `BlockMacro`, `CustomBlock`,
`IncludeResolver`, `TreeProcessor`, `Preprocessor`, `Postprocessor` and
`Docinfo`. `doc.diagnostics` lists what was reported while parsing and
converting a document, and `onDiagnostic` sees each message as it happens.

## Asynchronous work and files

`parse` and `convert` are synchronous. `parseAsync` and `convertAsync` fetch
remote content (`allow-uri-read`) and wait for an `IncludeResolver` that
returns a promise. On Node.js, `parseFile`, `convertFile` and `convertTree`
read and write files:

```js
const ad = new Asciidart({ safe: SafeMode.unsafe })
await ad.convertFile('docs/index.adoc')
for await (const result of ad.convertTree('docs', { toDir: 'build' })) {
  console.log(result.outputPath)
}
```

## Command line

```console
$ npx asciidart -o - document.adoc
```

The command takes the options of the `asciidoctor` command.

## Coming from Asciidoctor.js

The output follows Asciidoctor (2.1.0.alpha.0, plus bug fixes). The API is not Asciidoctor.js's:
properties replace `get*` methods, extensions are classes taking a
function, and an `html` override replaces converter classes. Callbacks are
synchronous, except an `IncludeResolver`. Errors thrown by your callbacks
reach the caller unchanged.

The same library is available for Dart
([repository](https://github.com/nsmmrs/asciidart)).

## License

MIT. Asciidoctor's stylesheets and locale data are included unchanged.
