# Ptome

Ptome ("plain text tome") is a processor for AsciiDoc® documents, written
in Dart and compiled to JavaScript. It converts AsciiDoc to HTML 5,
DocBook 5, man pages, PDF and EPUB compatibly with
[Asciidoctor](https://asciidoctor.org) (its development version,
2.1.0.alpha.0, with fixes for bugs it still has), and is not affiliated
with or endorsed by the Asciidoctor project. It was called asciidart until
2026-10-08.

It runs on Node.js (20.19 or later) and in browsers, ships TypeScript
types, and provides the `ptome` command. Its API is the Dart API's, with
the same names and shapes: see
[the usage scenarios](https://github.com/nsmmrs/ptome/blob/master/doc/api.md).

## Render and read

```js
import { asciidoc, Section } from 'ptome'

asciidoc.convert('Hello, *World*!') // '<div class="paragraph">...'

const doc = asciidoc.parse('= Title\n:status: draft\n\n== Section\n\ntext')
doc.title // 'Title'
doc.attributes.get('status') // 'draft'
doc.descendants(Section).map((s) => s.title) // ['Section']
doc.toHtml()
```

`require('ptome')` works too. A parsed document is a tree of classes
(`Section`, `Paragraph`, `Listing`, `Admonition`, lists, tables, inline
elements), so `instanceof` tells nodes apart, and the same node is always
the same object.

## Configure

```js
import { Admonition, Ptome, InlineMacro, SafeMode } from 'ptome'

const ad = new Ptome({
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
const ad = new Ptome({ safe: SafeMode.unsafe })
await ad.convertFile('docs/index.adoc')
for await (const result of ad.convertTree('docs', { toDir: 'build' })) {
  console.log(result.outputPath)
}
```

## PDFs and EPUBs

`convertToBytesAsync` makes a PDF or an EPUB, as a `Uint8Array`. Their
code is a part of the package loaded the first time it's needed, so pages
that only make HTML don't download it. (`loadBackend` loads it ahead, and
`convertToBytes` is the synchronous version once it is loaded.)

```js
const pdf = await new Ptome().convertToBytesAsync(source, { backend: 'pdf' })
```

Text is set in the fonts the theme names, found by family:

- `fonts: [new FontFile('Inter-Regular.ttf', bytes), ...]` gives fonts
  directly (TrueType, OpenType, WOFF or WOFF2). They are searched first.
- In a browser, the page's own web fonts are found next (`pageFonts`, on
  by default). Their `@font-face` sources are fetched again, usually from
  the browser's cache, so they must be same-origin or allow CORS.
- `localFonts: ['Inter']` takes those families from the visitor's
  installed fonts. This uses the Local Font Access API, so it works only
  in Chromium-based browsers, over HTTPS, and after the visitor allows it.
  The browser only asks when the conversion starts from a click or a key
  press.
- On Node.js, the installed fonts are found in the system's and the
  user's font folders. `npx ptome doctor` installs the default
  themes' fonts.

A font that can't be found is replaced by a built-in PDF font, with a
warning.

In a browser there is no file system, so `convertToBytesAsync` fetches the
files the conversion reads (images, a theme) relative to the page instead:
`image::images/logo.png[]` in a document converted on
`https://example.org/docs/` comes from
`https://example.org/docs/images/logo.png`. The page's directory stands for
the root of the file system, so a path can't reach above it. Includes are
not read this way; with `allow-uri-read` set, a URL can be included.

## Command line

```console
$ npx ptome -o - document.adoc
```

The command takes the options of the `asciidoctor` command.

## Coming from Asciidoctor.js

The output follows Asciidoctor (2.1.0.alpha.0, plus bug fixes). The API is not Asciidoctor.js's:
properties replace `get*` methods, extensions are classes taking a
function, and an `html` override replaces converter classes. Callbacks are
synchronous, except an `IncludeResolver`. Errors thrown by your callbacks
reach the caller unchanged.

The same library is available for Dart
([repository](https://github.com/nsmmrs/ptome)).

## License

MIT. Asciidoctor's stylesheets and locale data are included unchanged.

AsciiDoc® and AsciiDoc Language™ are trademarks of the Eclipse Foundation,
Inc.
