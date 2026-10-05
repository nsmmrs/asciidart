# Changelog

## bugfix branch

The `2.1.0` branch plus fixes for 25 bugs reported upstream that
Asciidoctor (upstream `main` at `30fb8cd5`) still has, chosen by triaging
all 610 open upstream issues (`doc/upstream-triage.md`). Each fix has a
CLI test in `test/bugfix/` that fails on the gem and passes here
(`tool/bugfix_check.sh`), and the output differences are listed in
`benchmark/PARITY.md`: section IDs for punctuation-only titles and titles
with footnotes; nested fonts in man pages; table cells after colspans and
beside rowspans taking the right column spec, invalid column specs, tabs
in literal cells and comments in AsciiDoc cells; `X//..` in paths;
assigned author names; links in superscripts; icons in link text; `\]` in
anchor reference text; anchors in section titles; em dashes next to
formatted text and curved quotes; URLs ending in `>`; paragraphs that look
like attribute lines; ancestor list continuations; headings beyond `<h6>`;
quotes in image attributes.

## 2.1.0 branch

This branch matches Asciidoctor's development version (upstream `main` at
`30fb8cd5`, 2.1.0.alpha.0) instead of the 2.0.26 release: the CLI's
`--log-level` and `--sourcemap`; highlight.js `nohighlight`; `linenums` as
a block option; ordered lists that start at their first marker; empty
section IDs; the `~~~~` open block; a block style above the title keeping
it in the body; block attributes overriding `imagesdir`; `cxx`; attribute
lists in formatted text without `[`; dot-free attribute names; inline image
IDs; `link=self`; Wistia videos; per-section `toclevels` and multipart
outlines; table and column widths as attributes; page and thematic break
classes; no generator meta with `reproducible`; DocBook quote roles; man
page lists and table cells without spurious `.sp`; front matter with
`+++`, skipped per include; a warning for URI includes without
`allow-uri-read`; the main branch's stylesheet and locales. The corpus
(17,900 conversions) is identical to the gem built from that commit.

## 0.1.0 (unreleased)

First release of asciidart, an AsciiDoc processor for Dart compatible with
the Asciidoctor **2.0.26** release. Not affiliated with or endorsed by the
Asciidoctor project.

- Converts AsciiDoc to HTML 5, DocBook 5 and man pages. Output is
  byte-identical to the Asciidoctor 2.0.26 gem on every backend, checked in
  CI by `tool/parity.sh` over the fixture and parity corpora; the end-to-end
  CLI suite (134 tests) passes against both asciidart and the gem.
- A small, typed public API designed from usage scenarios
  (`doc/api.md`): an `Asciidart` configuration (safe mode, attributes,
  extensions, an HTML override, highlighters, Mustache templates) with
  `parse`, `parseHeader`, `convert` and asynchronous variants; the default
  configuration `asciidoc`; a sealed tree of typed nodes (`Section`,
  `Paragraph`, `Listing`, `Admonition`, lists, tables, inline elements)
  with `descendants<T>()` and `plainText`; inline content as a typed tree
  (`inlines`, `titleInlines`: text and formatted text, links, images...,
  nested; ADR-0008); typed attributes; diagnostics
  collected per document; callback-based extensions (`InlineMacro`,
  `BlockMacro`, `CustomBlock`, `IncludeResolver` (may be asynchronous),
  `TreeProcessor`, `Preprocessor`, `Postprocessor`, `Docinfo`).
  `package:asciidart/asciidart.dart` has no file system access and runs on
  the web; `package:asciidart/io.dart` adds `parseFile`, `convertFile` and
  `convertTree`; `package:asciidart/cli.dart` runs the command line with a
  configuration compiled in. Everything else is private;
  `tool/api_surface.txt` records the public API and CI checks it.
- Remote content (`allow-uri-read`): `parseAsync` and `convertAsync` fetch
  includes and data-URI images, honoring `cache-uri`.
- The `asciidart` command takes the options of the gem's `asciidoctor`
  command, except the Ruby-specific `-r`, `-I`, `--eruby` and `-w`.
  Messages start with `asciidart:` and read like a Dart tool's
  (`benchmark/PARITY.md`); `--version` names asciidart and the Asciidoctor
  release it is compatible with; `man/asciidart.1` documents it.
  `init-config` generates a project for a custom command with Dart converter
  functions compiled in.
- Syntax highlighting with highlight.js at conversion (hilite, a Dart port
  of highlight.js 11.12.0); `highlightjs-mode=client` gives Asciidoctor's
  browser-side markup. Rouge, Pygments and CodeRay behave as when their gems
  are missing.
- Custom converters: Mustache templates (`-T`, `templateDirs`) and HTML
  overrides in Dart, in place of Ruby's Tilt templates (ADR-0002).
- `{asciidoctor-version}` (and `asciidoctorVersion` in the API) report
  2.0.26, so documents written for Asciidoctor keep working;
  `{asciidart-version}` (`asciidartVersion`) reports asciidart's version,
  which also appears in the HTML generator meta tag and the man page
  header.
- The compiled command converts 5–10x faster than the gem end to end, and
  about 2x faster in process (`benchmark/BASELINE.md`).
- The same core builds as the npm package `asciidart` for Node.js and
  browsers (ADR-0005). Its API is generated from the Dart API, with the
  same names and shapes, plus TypeScript declarations
  (`tool/generate_js.dart`, ADR-0007).
