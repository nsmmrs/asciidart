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
  print(convert('Hello, *World*!')); // <div class="paragraph">...

  final doc = load(
    '= Title\n\n== Section\n\ntext',
    options: const AsciidoctorOptions(safe: SafeMode.safe),
  );
  print(doc.doctitle()); // Title
}
```

The public libraries:

| Import | Contents |
| --- | --- |
| `package:asciidart/asciidart.dart` | `load`, `convert`, `convertFile` and their async variants, `AsciidoctorOptions`, the document tree, logging |
| `package:asciidart/extensions.dart` | `Extensions`, `Registry` and the processor kinds |
| `package:asciidart/converter.dart` | converters, the converter factory, function and Mustache templates |
| `package:asciidart/syntax_highlighter.dart` | the syntax highlighter API |
| `package:asciidart/cli.dart` | `runCli`, for building your own command |

`example/asciidart_example.dart` shows a tree walk, an extension and a
custom converter. Remote content (`allow-uri-read`) needs the async API
(`loadAsync`, `convertAsync`, ...), which fetches what the document
includes before converting.

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
- Dart functions override transforms in code. `asciidart init-config DIR`
  generates a project for a custom command with your functions compiled in.

## JavaScript and npm

The same core compiles to JavaScript as the npm package
[`asciidart`](npm/README.md), with TypeScript types and an `asciidart`
command. It runs on Node.js 20.19+ and in browsers
([ADR-0005](adr/0005-js-build.md)).

```js
import { convert } from 'asciidart'

const html = await convert('Hello, *AsciiDoc*!')
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
