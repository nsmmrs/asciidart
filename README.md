# Asciidoctor (Dart port)

Dart port of [Asciidoctor](https://asciidoctor.org), the fast text processor
for converting AsciiDoc to HTML and more.

> Status: skeleton (v0.1.0). The package layout, CLI entry point, and smoke
> tests are in place. Converter modules arrive in later phases.

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

## Lint

```sh
cd dart
dart analyze
```

## Layout

- `lib/asciidoctor.dart` — public library entry point
- `lib/src/version.dart` — version constant
- `bin/asciidoctor.dart` — CLI entry point
- `test/smoke_test.dart` — smoke tests
