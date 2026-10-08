# ptome

[![CI](https://github.com/nsmmrs/ptome/actions/workflows/ci.yml/badge.svg)](https://github.com/nsmmrs/ptome/actions/workflows/ci.yml)

**[Ptome](packages/ptome)** ("plain text tome") is a processor for
AsciiDoc® documents, written in Dart: HTML 5, DocBook 5, man pages, EPUB 3
and PDF, compatible with Asciidoctor. This repository is a pub workspace
holding Ptome and the pure-Dart libraries it is built on
([ADR-0018](adr/0018-ptome-and-the-plain-workspace.md)).

| Package | What it is |
|---|---|
| [ptome](packages/ptome) | The AsciiDoc processor: library, command line, npm package |

The `plain_*` libraries share one philosophy: pure Dart, written from the
specification, the same bytes on every platform, statically typed, and
tested against outside oracles. Each is published and versioned on its
own.

See [CONTRIBUTING.md](CONTRIBUTING.md) to work on any of them.

## License

MIT; see [LICENSE](LICENSE) and each package's own license file.

AsciiDoc® and AsciiDoc Language™ are trademarks of the Eclipse Foundation,
Inc.
