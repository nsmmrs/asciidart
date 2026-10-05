# asciidart

[![CI](https://github.com/nsmmrs/asciidart/actions/workflows/ci.yml/badge.svg)](https://github.com/nsmmrs/asciidart/actions/workflows/ci.yml)

An AsciiDoc processor written in Dart. It converts AsciiDoc to HTML 5,
DocBook 5 and man pages, and is meant as a drop-in replacement for
[Asciidoctor](https://asciidoctor.org) 2.0.26: the same documents,
attributes, command-line options and output. It is a library, a command
line tool, and (compiled to JavaScript) an npm package.

> asciidart is an independent re-implementation, not affiliated with or
> endorsed by the Asciidoctor project. Report problems
> [here](https://github.com/nsmmrs/asciidart/issues), not upstream.

## Why

- **Compatible, and checked.** Every change is compared byte for byte with
  the Asciidoctor 2.0.26 gem on all three backends (`tool/parity.sh`, run
  in CI) and over a corpus of about 4,500 real-world documents
  (`tool/corpus_parity.dart`); the command line passes the same end-to-end
  suite as the gem. Where asciidart differs on purpose, the difference is
  listed in [`benchmark/PARITY.md`](benchmark/PARITY.md).
- **Fast.** The compiled command converts a document 5–10x faster than the
  `asciidoctor` gem end to end, and about 2x faster in process
  ([`benchmark/BASELINE.md`](benchmark/BASELINE.md)).
- **No Ruby.** One self-contained executable, a Dart dependency, or an npm
  package for Node.js and browsers.

## Library

asciidart is not on pub.dev yet; depend on it from git:

```yaml
dependencies:
  asciidart:
    git: https://github.com/nsmmrs/asciidart.git
```

```dart
import 'package:asciidart/asciidart.dart';

void main() {
  print(asciidoc.convert('Hello, *World*!')); // <div class="paragraph">...

  final doc = asciidoc.parse('= Title\n:status: draft\n\n== Section\n\ntext');
  print('${doc.title} (${doc.attributes['status']})'); // Title (draft)
  for (final section in doc.descendants<Section>()) {
    print(section.title); // Section
  }
}
```

An `Asciidart` object holds a configuration (safe mode, attributes,
extensions, an HTML override, highlighters) and `asciidoc` is the default
one. A parsed `Document` is a sealed tree of typed nodes, and its
`diagnostics` list what was reported while parsing and converting it.
[`doc/api.md`](doc/api.md) walks through the common uses: rendering,
reading metadata, querying the tree, custom renderers, HTML overrides,
extensions, diagnostics and files.

| Import | Contents |
| --- | --- |
| `package:asciidart/asciidart.dart` | parsing, converting, the document tree, extensions, overrides, diagnostics (no file system access: runs on the web and in Flutter) |
| `package:asciidart/io.dart` | `parseFile`, `convertFile` and `convertTree` |
| `package:asciidart/cli.dart` | `runCli`, for building your own command |

Everything else is private. `tool/api_surface.txt` records the public API,
and CI fails when it changes unnoticed.

## Command line

```sh
dart pub global activate --source git https://github.com/nsmmrs/asciidart.git
asciidart document.adoc
```

`asciidart` takes the options of the `asciidoctor` command
(`asciidart --help`, `man ./man/asciidart.1`). Differences: the
Ruby-specific options (`-r`, `-I`, `--eruby`, `-w`) are not available,
messages start with `asciidart:` and read like a Dart tool's, and
`--version` names asciidart and the Asciidoctor release it is compatible
with.

Native executables can be built with `tool/build-exes.sh` or
`dart compile exe bin/asciidart.dart`.

### Custom converters

Ruby's Tilt templates cannot run on Dart. Instead
([ADR-0002](adr/0002-template-converter-strategy.md),
[cookbook](doc/templates.md)):

- `-T DIR` loads Mustache templates (`paragraph.mustache`, ...) on top of
  the built-in converter.
- An HTML override (`Asciidart(html: ...)`) replaces the HTML of any node
  in Dart code. `asciidart init-config DIR` generates a project for a
  custom command with such code (and extensions) compiled in.

## Syntax highlighting

`:source-highlighter: highlight.js` highlights source blocks at conversion,
with [hilite](https://github.com/nsmmrs/hilite) (highlight.js 11.12.0 in
Dart): the HTML is what highlight.js would produce in the browser, so any
highlight.js theme styles it (`highlightjs-theme`, default `github`), and
the page needs no JavaScript. `highlightjs-mode=client` keeps Asciidoctor's
behavior instead: the browser loads highlight.js and highlights the page.

Rouge, Pygments and CodeRay are not available; with them, source blocks are
left unhighlighted, as Asciidoctor does when their gem is missing. Custom
highlighters can be registered through the API (`Asciidart(highlighters:
...)`).

## JavaScript and npm

The same core compiles to JavaScript as the npm package
[`asciidart`](npm/README.md), with TypeScript types and an `asciidart`
command. It runs on Node.js 20.19+ and in browsers
([ADR-0005](adr/0005-js-build.md)). Its API is generated from the Dart
API, with the same names and shapes
([ADR-0007](adr/0007-js-projection.md)):

```js
import { asciidoc, Section } from 'asciidart'

const doc = asciidoc.parse('= Title\n\n== Section\n\ntext')
doc.descendants(Section).map((s) => s.title) // ['Section']
asciidoc.convert('Hello, *AsciiDoc*!')
```

## Versions

asciidart is compatible with the Asciidoctor **2.0.26** release
([ADR-0003](adr/0003-target-latest-stable.md)). Documents see
`{asciidoctor-version}` as 2.0.26 (so `ifdef::asciidoctor[]` and version
checks keep working) and `{asciidart-version}` as the version of
asciidart. Compatibility with Asciidoctor 2.1 lives on the `2.1.0` branch.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports are welcome at the
[issue tracker](https://github.com/nsmmrs/asciidart/issues); include an
`.adoc` reproducer and, when the output differs from the gem, the gem's
output.

## Origins and license

asciidart began as a file-by-file port of
[Asciidoctor](https://github.com/asciidoctor/asciidoctor), the Ruby
implementation by Dan Allen, Sarah White, Ryan Waldron and the Asciidoctor
contributors, with byte-identical output as the bar. MIT licensed (see
[LICENSE](LICENSE)). The stylesheets, locale data and test fixtures taken
from Asciidoctor live under [`vendor/`](vendor/README.md), with their
license.
