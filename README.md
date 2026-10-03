# Asciidoctor (Dart port)

Dart port of [Asciidoctor](https://asciidoctor.org), the text processor
for converting AsciiDoc to HTML 5, DocBook 5, and Unix man pages.

> Status: working CLI (v0.1.0). All three backends, the option parser, and
> the extension framework are ported; the bats e2e suite passes 131/131
> against this CLI and the differential corpus is byte-identical to Ruby
> (see `../benchmark/PARITY.md`).
>
> Performance (measured 2026-10-03, see `../benchmark/BASELINE.md`): the
> AOT-compiled binary converts the benchmark corpus **3.5–8.8x faster**
> than the Ruby CLI end to end. `dart run` (JIT dev mode) is not a
> performance target and runs ~13–15x slower than Ruby per spawn.

## Prerequisites

- Dart SDK `^3.13.0` (check with `dart --version`)

## Setup

```sh
cd dart
dart pub get
```

## Run the tests

```sh
cd dart
dart test
```

## Run the CLI

```sh
cd dart
dart run bin/asciidoctor.dart --version
dart run bin/asciidoctor.dart --help
```

## Build a native executable

```sh
cd dart
mkdir -p build
dart compile exe bin/asciidoctor.dart -o build/asciidoctor
./build/asciidoctor --version
```

## Custom converter templates

Two override paths (Tilt templates cannot run on Dart; see
[ADR-0002](../adr/0002-template-converter-strategy.md) and the
[cookbook](doc/templates.md)):

- **Mustache files:** `-T templates` loads `paragraph.mustache`-style
  overrides on top of the built-in converter (last `-T` wins per
  transform; `-E` accepts `mustache` and `dart`).
- **Dart functions:** register per-transform handlers in code; they win
  over Mustache files per transform.

For a compiled-in custom binary (XMonad-style):

```sh
asciidoctor init-config my-config
cd my-config
dart pub get
dart compile exe bin/main.dart -o my-asciidoctor
```

## Lint

```sh
cd dart
dart analyze
```

## Regenerating the embedded data

`lib/src/data.g.dart` embeds `data/locale/*.adoc` and `data/stylesheets/*`
as compile-time string constants so the package never reads them from disk
at runtime. It is generated — do not edit it by hand. After changing any
file under the repository `data/` directory, regenerate it from `dart/`:

```sh
cd dart
dart run tool/embed_data.dart
dart format lib/src/data.g.dart
dart test test/stylesheets_test.dart
```

`test/stylesheets_test.dart` asserts every embedded value round-trips to
the exact bytes of its source file.

## Layout

- `lib/asciidoctor.dart` — public library entry point
- `lib/src/version.dart` — version constant
- `lib/src/path_resolver.dart` — path resolution, cleaning, and jail
  confinement (port of `lib/asciidoctor/path_resolver.rb`)
- `lib/src/stylesheets.dart` — built-in stylesheets helper (port of
  `lib/asciidoctor/stylesheets.rb`)
- `lib/src/data.g.dart` — generated compile-time copy of `data/` (see above)
- `tool/embed_data.dart` — generator for `lib/src/data.g.dart`
- `bin/asciidoctor.dart` — CLI entry point
- `test/smoke_test.dart` — smoke tests
- `test/paths_test.dart` — path resolver tests (port of `test/paths_test.rb`)
- `test/stylesheets_test.dart` — embedded-data and stylesheets tests
