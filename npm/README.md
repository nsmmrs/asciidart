# asciidart

asciidart, an AsciiDoc processor written in Dart, compiled to JavaScript.
It converts AsciiDoc to HTML 5, DocBook 5 and man pages compatibly with
[Asciidoctor](https://asciidoctor.org) 2.0.26, behind an API shaped after
[Asciidoctor.js](https://github.com/asciidoctor/asciidoctor.js) 4.1. It is
not affiliated with or endorsed by the Asciidoctor project.

It runs on Node.js (20.19 or later) and in browsers, ships TypeScript
types, and provides the `asciidart` command.

## Usage

```js
import { convert, load } from 'asciidart'

const html = await convert('Hello, *AsciiDoc*!')

const doc = await load('= Title\n\n== Section\n\ncontent', { safe: 'safe' })
console.log(doc.getTitle(), doc.getBlocks().length)
console.log(await doc.convert())
```

`require('asciidart')` works too. Options use the Asciidoctor.js
names (`safe`, `backend`, `doctype`, `attributes`, `standalone`, `to_file`,
`base_dir`, ...).

```console
$ npx asciidart -o - document.adoc
```

The command takes the options of the `asciidoctor` command.

## Extensions

```js
import { convert, Extensions } from 'asciidart'

const registry = Extensions.create(function () {
  this.inlineMacro('emoji', function () {
    this.process(function (parent, target) {
      return this.createInline(parent, 'quoted', `:${target}:`, { type: 'strong' })
    })
  })
})

await convert('Hi emoji:wave[]', { extension_registry: registry })
```

`Extensions.register` adds a group to every document. Preprocessors, tree
processors, postprocessors, include processors, docinfo processors, block
processors and block and inline macros are supported, with the
Asciidoctor.js DSL or as classes.

## Converters

```js
import { convert, Html5Converter } from 'asciidart'

class Custom extends Html5Converter {
  convert_paragraph(node) {
    return `<p class="custom">${node.getContent()}</p>`
  }
}

await convert('Some text.', { converter: new Custom() })
```

`ConverterFactory.register(MyConverter, 'mybackend')` adds a backend;
subclass `ConverterBase` and add `convert_<name>` methods.

Converters and extension functions run synchronously: return values, not
promises. Inside them, node methods such as `getContent()` return their
values directly (`await` still works).

## Differences from Asciidoctor.js

- Output follows Asciidoctor 2.0.26 exactly. Asciidoctor.js 4.1 is a
  separate JavaScript implementation and differs in places.
- Converters and extensions must be synchronous.
- Not included: the semantic HTML converter, highlight.js integration, the
  HTTP cache classes and `Timings`.
- Remote content (`allow-uri-read`) is fetched with `fetch`; in the browser
  there is no file access, so includes and templates need Node.js.

The same code is available for Dart as the `asciidoctor` package
([repository](https://github.com/nsmmrs/asciidart)).

## License

MIT. Asciidoctor's stylesheets, locale data and man page are included
unchanged; `src/logging.js` is adapted from Asciidoctor.js (MIT).
