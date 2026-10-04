# asciidoctor (Dart)

[![CI](https://github.com/nsmmrs/asciidoctor-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/nsmmrs/asciidoctor-dart/actions/workflows/ci.yml)

An unofficial Dart port of [Asciidoctor](https://asciidoctor.org) 2.0.26.
It converts AsciiDoc to HTML 5, DocBook 5 and man pages, with output
identical to the Ruby original. It is a library, a command line tool, and
(compiled to JavaScript) an npm package.

> This project is not affiliated with the Asciidoctor project. Report
> problems with this port [here](https://github.com/nsmmrs/asciidoctor-dart/issues),
> not upstream.

## Why

- **Same output.** Every release is checked byte for byte against the
  Asciidoctor 2.0.26 gem on all three backends (`tool/parity.sh`, run in
  CI), and the command line passes the same end-to-end suite as the gem.
- **Fast.** The compiled command converts a document 5–10x faster than the
  `asciidoctor` gem end to end, and about 2x faster in process
  (`benchmark/BASELINE.md`).
- **No Ruby.** One self-contained executable, or a Dart dependency, or an
  npm package for Node.js and browsers.

## Library

```sh
dart pub add asciidoctor
```

```dart
import 'package:asciidoctor/asciidoctor.dart';

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
| `package:asciidoctor/asciidoctor.dart` | `load`, `convert`, `convertFile` and their async variants, `AsciidoctorOptions`, the document tree, logging |
| `package:asciidoctor/extensions.dart` | `Extensions`, `Registry` and the processor kinds |
| `package:asciidoctor/converter.dart` | converters, the converter factory, function and Mustache templates |
| `package:asciidoctor/syntax_highlighter.dart` | the syntax highlighter API |
| `package:asciidoctor/cli.dart` | `runCli`, for building your own command |

`example/asciidoctor_example.dart` shows a tree walk, an extension and a
custom converter. Remote content (`allow-uri-read`) needs the async API
(`loadAsync`, `convertAsync`, ...), which fetches what the document
includes before converting.

## Command line

```sh
dart pub global activate asciidoctor
asciidoctor document.adoc
```

It takes the options of the `asciidoctor` command (`asciidoctor --help`).
Differences: the Ruby-specific options (`-r`, `-I`, `--eruby`, `-w`) are
not available, and messages read like a Dart tool's
(`benchmark/PARITY.md` lists every difference). If the Ruby gem is also
installed, whichever `asciidoctor` comes first on `PATH` wins.

Native executables can be built with `tool/build-exes.sh` or
`dart compile exe bin/asciidoctor.dart`.

### Custom converters

Ruby's Tilt templates cannot run on Dart. Instead
([ADR-0002](adr/0002-template-converter-strategy.md),
[cookbook](doc/templates.md)):

- `-T DIR` loads Mustache templates (`paragraph.mustache`, ...) on top of
  the built-in converter.
- Dart functions override transforms in code. `asciidoctor init-config DIR`
  generates a project for a custom command with your functions compiled in.

## JavaScript and npm

The same core compiles to JavaScript as the npm package
[`asciidoctor-dart`](npm/README.md), with an API shaped after
Asciidoctor.js 4.1, TypeScript types, and an `asciidoctor-dart` command. It
runs on Node.js 20.19+ and in browsers ([ADR-0005](adr/0005-js-build.md)).

```js
import { convert } from 'asciidoctor-dart'

const html = await convert('Hello, *AsciiDoc*!')
```

## Versions

The port matches the Asciidoctor **2.0.26** release
([ADR-0003](adr/0003-target-latest-stable.md)); `Asciidoctor.version` and
`{asciidoctor-version}` report 2.0.26, and `{asciidoctor-dart-version}` the
version of this package. Work toward Asciidoctor 2.1 lives on the `2.1.0`
branch until upstream releases it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports are welcome at the
[issue tracker](https://github.com/nsmmrs/asciidoctor-dart/issues); include
an `.adoc` reproducer and, when the output differs from the gem, the gem's
output.

## Origins and license

A file-by-file port of [Asciidoctor](https://github.com/asciidoctor/asciidoctor),
the Ruby implementation by Dan Allen, Sarah White, Ryan Waldron and the
Asciidoctor contributors, with byte-identical output as the bar. MIT
licensed (see [LICENSE](LICENSE)); the license text, stylesheets, locale
data and man page are unchanged from upstream.
