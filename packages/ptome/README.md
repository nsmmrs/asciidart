# Ptome

[![CI](https://github.com/nsmmrs/ptome/actions/workflows/ci.yml/badge.svg)](https://github.com/nsmmrs/ptome/actions/workflows/ci.yml)

Ptome ("plain text tome": a tome with a silent p, like pterodactyl) is a
processor for AsciiDoc® documents, written in Dart. It converts AsciiDoc to
HTML 5, DocBook 5, man pages, EPUB 3 and PDF, and is meant as a drop-in
replacement for [Asciidoctor](https://asciidoctor.org) 2.1 (upstream
`main`, 2.1.0.alpha.0): the same documents, attributes, command-line
options and output. It is a library, a command line tool, and (compiled to
JavaScript) an npm package. It was called asciidart until 2026-10-08
([ADR-0018](../../adr/0018-ptome-and-the-plain-workspace.md)).

> Ptome follows Asciidoctor's development version (upstream `main` at
> `30fb8cd5`, which reports 2.1.0.alpha.0) and fixes bugs Asciidoctor still
> has ([PARITY.md](benchmark/PARITY.md#upstream-bugs-fixed)). The tag
> `asciidoctor-2.0.26-parity` marks the last commit that matched the
> 2.0.26 release byte for byte ([ADR-0017](../../adr/0017-follow-main-fix-bugs.md)).

> Ptome is an independent re-implementation, not affiliated with or
> endorsed by the Asciidoctor project. Report problems
> [here](https://github.com/nsmmrs/ptome/issues), not upstream.

## Why

- **Compatible, and checked.** Every change is compared byte for byte with
  the Asciidoctor gem built from upstream `main` on all three backends (the test
  corpus, `test/corpus`, run in CI on the Dart VM and Node.js) and over a corpus of about 4,500 real-world documents
  (`tool/corpus_parity.dart`); the command line passes the same end-to-end
  suite as the gem. Where Ptome differs on purpose, the difference is
  listed in [`benchmark/PARITY.md`](benchmark/PARITY.md). EPUB 3 output
  matches the asciidoctor-epub3 2.3.0 gem file by file
  (`tool/epub_parity.dart`).
- **PDF without Ruby or a browser.** `-b pdf` draws with
  [plain_pdf](https://github.com/nsmmrs/ptome/tree/master/packages/plain_pdf), a pure-Dart PDF library (its
  fonts and compression come from the
  [plain_fonts](https://github.com/nsmmrs/ptome/tree/master/packages/plain_fonts) and
  [plain_compression](https://github.com/nsmmrs/ptome/tree/master/packages/plain_compression) packages), and reads
  asciidoctor-pdf's YAML themes. Fonts are yours: a theme names any installed font, and `ptome doctor`
  installs the built-in themes' (Noto, M PLUS and the icon fonts). With
  `asciidoctor-compat`, the pages look as asciidoctor-pdf 2.3.27 sets them:
  792 of the 797 documents of that gem's spec suite look the same
  (`tool/pdf_look.dart`). By default, Ptome lays books out with its
  own typesetting: optimal line breaking, hyphenation, widows and orphans,
  ligatures, listings that never lose a line, and table styles by role
  ([`doc/pdf.md`](doc/pdf.md)).
- **Books as websites and indexes everywhere.** `-b multipage_html5`
  writes one linked page per chapter; an `[index]` section lists the index
  terms in HTML and EPUB too; `-a callout-links` links callouts both ways.
  [`doc/books.md`](doc/books.md) shows one source becoming a print PDF, a
  website, an EPUB and DocBook, and how to move from asciidoctor-pdf or a
  browser-based print pipeline.
- **Texts cited by numbered units.** The ptome language adds a small
  syntax to AsciiDoc for scripture, law, classics, drama, liturgy and
  specifications. It provides unit markers (`@`, `@6`, `@(a)`), ranges,
  note streams, references and quotations by address. Ptome works out
  every verse's or provision's anchor, label, reftext and link from the
  schemes a document names (`:units:`). Documents without `:units:` are
  unaffected ([`doc/units.md`](doc/units.md),
  [ADR-0019](../../adr/0019-units.md)).
- **Fast.** The compiled command converts a document 5–10x faster than the
  `asciidoctor` gem end to end, and about 2x faster in process
  ([`benchmark/BASELINE.md`](benchmark/BASELINE.md)).
- **No Ruby.** One self-contained executable, a Dart dependency, or an npm
  package for Node.js and browsers.

## Library

Ptome is not on pub.dev yet; depend on it from git:

```yaml
dependencies:
  ptome:
    git: https://github.com/nsmmrs/ptome.git
```

```dart
import 'package:ptome/ptome.dart';

void main() {
  print(asciidoc.convert('Hello, *World*!')); // <div class="paragraph">...

  final doc = asciidoc.parse('= Title\n:status: draft\n\n== Section\n\ntext');
  print('${doc.title} (${doc.attributes['status']})'); // Title (draft)
  for (final section in doc.descendants<Section>()) {
    print(section.title); // Section
  }
}
```

A `Ptome` object holds a configuration (safe mode, attributes,
extensions, an HTML override, highlighters) and `asciidoc` is the default
one. A parsed `Document` is a sealed tree of typed nodes, and its
`diagnostics` list what was reported while parsing and converting it.
[`doc/api.md`](doc/api.md) walks through the common uses: rendering,
reading metadata, querying the tree, custom renderers, HTML overrides,
extensions, diagnostics and files.

| Import | Contents |
| --- | --- |
| `package:ptome/ptome.dart` | parsing, converting, the document tree, extensions, overrides, diagnostics (no file system access: runs on the web and in Flutter) |
| `package:ptome/io.dart` | `parseFile`, `convertFile` and `convertTree` |
| `package:ptome/cli.dart` | `runCli`, for building your own command |

Everything else is private. `tool/api_surface.txt` records the public API,
and CI fails when it changes unnoticed.

## Command line

```sh
dart pub global activate --source git https://github.com/nsmmrs/ptome.git
ptome document.adoc
```

`ptome` takes the options of the `asciidoctor` command
(`ptome --help`, `man ./man/ptome.1`). Differences: the
Ruby-specific options (`-r`, `-I`, `--eruby`, `-w`) are not available,
messages start with `ptome:` and read like a Dart tool's, and
`--version` names Ptome and the Asciidoctor release it is compatible
with.

Native executables can be built with `tool/build-exes.sh` or
`dart compile exe bin/ptome.dart`.

### Custom converters

Ruby's Tilt templates cannot run on Dart. Instead
([ADR-0002](../../adr/0002-template-converter-strategy.md),
[cookbook](doc/templates.md)):

- `-T DIR` loads Mustache templates (`paragraph.mustache`, ...) on top of
  the built-in converter.
- An HTML override (`Ptome(html: ...)`) replaces the HTML of any node
  in Dart code. `ptome init-config DIR` generates a project for a
  custom command with such code (and extensions) compiled in.

## Syntax highlighting

`:source-highlighter: highlight.js` highlights source blocks at conversion,
with [plain_highlighting](https://github.com/nsmmrs/ptome/tree/master/packages/plain_highlighting) (highlight.js 11.12.0 in
Dart): the HTML is what highlight.js would produce in the browser, so any
highlight.js theme styles it (`highlightjs-theme`, default `github`), and
the page needs no JavaScript. `highlightjs-mode=client` keeps Asciidoctor's
behavior instead: the browser loads highlight.js and highlights the page.

Rouge, Pygments and CodeRay are not available; with them, source blocks are
left unhighlighted, as Asciidoctor does when their gem is missing. Custom
highlighters can be registered through the API (`Ptome(highlighters:
...)`).

## JavaScript and npm

The same core compiles to JavaScript as the npm package
[`ptome`](npm/README.md), with TypeScript types and a `ptome`
command. It runs on Node.js 20.19+ and in browsers
([ADR-0005](../../adr/0005-js-build.md)). Its API is generated from the Dart
API, with the same names and shapes
([ADR-0007](../../adr/0007-js-projection.md)):

```js
import { asciidoc, Section } from 'ptome'

const doc = asciidoc.parse('= Title\n\n== Section\n\ntext')
doc.descendants(Section).map((s) => s.title) // ['Section']
asciidoc.convert('Hello, *AsciiDoc*!')
```

## Versions

Ptome is compatible with Asciidoctor's development version: upstream
`main` at `30fb8cd5` (`tool/vendor.sh`), which reports **2.1.0.alpha.0**.
Documents see `{asciidoctor-version}` as 2.1.0.alpha.0 and
`{ptome-version}` as the version of Ptome. Documents that hit one
of the upstream bugs fixed here convert differently (the fixes are listed
in [PARITY.md](benchmark/PARITY.md#upstream-bugs-fixed)). For output
identical to the 2.0.26 release, use the tag `asciidoctor-2.0.26-parity`
([ADR-0017](../../adr/0017-follow-main-fix-bugs.md)).

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md). Bug reports are welcome at the
[issue tracker](https://github.com/nsmmrs/ptome/issues); include an
`.adoc` reproducer and, when the output differs from the gem, the gem's
output.

## Origins and license

Ptome began as a file-by-file port of
[Asciidoctor](https://github.com/asciidoctor/asciidoctor), the Ruby
implementation by Dan Allen, Sarah White, Ryan Waldron and the Asciidoctor
contributors, with byte-identical output as the bar. MIT licensed (see
[LICENSE](LICENSE)). The stylesheets, locale data and test fixtures taken
from Asciidoctor live under [`vendor/`](vendor/README.md), with their
license. Ptome ships no fonts: `ptome doctor` downloads the
built-in themes' fonts (SIL Open Font License 1.1 and MIT) from their
projects, with their licenses.

AsciiDoc® and AsciiDoc Language™ are trademarks of the Eclipse Foundation,
Inc.
