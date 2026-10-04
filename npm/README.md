# asciidoctor-dart

An unofficial port of [Asciidoctor](https://asciidoctor.org) 2.0.26,
written in Dart and compiled to JavaScript. It converts AsciiDoc to HTML 5,
DocBook 5 and man pages with output identical to the Ruby original, behind
an API shaped after [Asciidoctor.js](https://github.com/asciidoctor/asciidoctor.js)
4.1. It is not affiliated with the Asciidoctor project.

It runs on Node.js (20.19 or later) and in browsers, and ships the
`asciidoctor-dart` command.

## Usage

```js
import { convert, load } from 'asciidoctor-dart'

const html = await convert('Hello, *AsciiDoc*!')

const doc = await load('= Title\n\n== Section\n\ncontent')
console.log(doc.getTitle(), doc.getBlocks().length)
console.log(await doc.convert())
```

```console
$ npx asciidoctor-dart -o - document.adoc
```

The same package is also published for Dart on pub.dev as `asciidoctor`.
