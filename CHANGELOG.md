# Changelog

## 0.1.0 (unreleased)

First release of asciidart, an AsciiDoc processor for Dart compatible with
the Asciidoctor **2.0.26** release. Not affiliated with or endorsed by the
Asciidoctor project.

- Converts AsciiDoc to HTML 5, DocBook 5 and man pages. Output is
  byte-identical to the Asciidoctor 2.0.26 gem on every backend, checked in
  CI by `tool/parity.sh` over the fixture and parity corpora; the end-to-end
  CLI suite (134 tests) passes against both asciidart and the gem.
- Public libraries: `asciidart.dart` (`load`, `convert`, `convertFile`,
  typed `AsciidoctorOptions`, the document tree, logging), `extensions.dart`,
  `converter.dart`, `syntax_highlighter.dart` and `cli.dart`. The API is
  statically typed throughout (ADR-0004).
- Async variants (`loadAsync`, `convertAsync`, ...) fetch remote content for
  `allow-uri-read` (includes and data-URI images), honoring `cache-uri`.
- The `asciidart` command takes the options of the gem's `asciidoctor`
  command, except the Ruby-specific `-r`, `-I`, `--eruby` and `-w`.
  Messages start with `asciidart:` and read like a Dart tool's
  (`benchmark/PARITY.md`); `--version` names asciidart and the Asciidoctor
  release it is compatible with; `man/asciidart.1` documents it.
  `init-config` generates a project for a custom command with Dart converter
  functions compiled in.
- Custom converters: Mustache templates (`-T`) and Dart functions, in place
  of Ruby's Tilt templates (ADR-0002).
- `Asciidoctor.version` and `{asciidoctor-version}` report 2.0.26, so
  documents written for Asciidoctor keep working; `Asciidoctor.packageVersion`
  and `{asciidart-version}` report asciidart's version, which also appears
  in the HTML generator meta tag and the man page header.
- The compiled command converts 5–10x faster than the gem end to end, and
  about 2x faster in process (`benchmark/BASELINE.md`).
- The same core builds as the npm package `asciidart` for Node.js and
  browsers, with an Asciidoctor.js 4.1-style API (ADR-0005).
