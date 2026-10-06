# Hypermedia Systems acceptance

The Hypermedia Systems authors left AsciiDoc for Typst because no
toolchain gave them a print-quality PDF, an index outside PDF, a book
website, valid DocBook or an EPUB without hand work (lane EPIC-xj1gxj).
`tool/hs_acceptance.dart` builds their AsciiDoc sources
(bigskysoftware/hypermedia-systems-old at
`2e8c4be47f64de281d0e325599bcbe69e7ed05ce`) with the asciidart executable
and checks what they had to fix by hand.

```sh
dart run tool/hs_acceptance.dart --exe dist/asciidart-linux-x64 \
  --report benchmark/HS.md
```

(`--report` replaces the results table below and its date.)

The book's chapters are used unmodified. Two adaptations, both in the
harness:

- The master file (`book/HypermediaSystems.adoc`) is copied to the root of
  the repository: its includes and images are relative to it there, as in
  the old website's build.
- An `[index]` section is appended to the copy. The book's index
  (`book/INDEX.adoc`) was made by hand, for want of one in the HTML; this
  one is generated from the index terms of the chapters.

The PDF uses `tool/hs/hs-theme.yml`, a print theme modeled on the Typst
edition: US Letter, wide inside margins, Yrsa (the font the AsciiDoc
edition shipped), indented paragraphs and running footers. It is set by
the modern engine: justified paragraphs broken where their spacing is
most even and hyphenated (US English patterns; code spans stay whole),
no widows or orphans, Yrsa's ligatures and GPOS kerning, emphasis
upright inside italic text, and a first-line indent of 1em on each
paragraph that follows another, with no space between them. HTML, EPUB
and the website (`multipage_html5`) are built with `callout-links`. The
book isn't vendored: its `book/` directory isn't under its repository's
license.

## Latest run (2026-10-06)

| Check | Result | Detail |
| --- | --- | --- |
| PDF build | pass | 3266 ms, 2149 KB, 10 errors, 4 warnings |
| HTML build | pass | 186 ms, 1048 KB, 6 errors, 5 warnings |
| EPUB 3 build | pass | 376 ms, 1855 KB, 6 errors, 5 warnings |
| DocBook 5 build | pass | 209 ms, 894 KB, 6 errors, 4 warnings |
| Multi-page HTML build | pass | 198 ms, 31 KB, 6 errors, 5 warnings |
| PDF byte-stable across runs | pass | SOURCE_DATE_EPOCH=0 |
| PDF has each listing line once (#122) | pass | 600 distinct lines of 24+ characters: 0 missing, 0 repeated |
| PDF crops no text (#106) | pass | 0 words past the page edge, 0 past the margin |
| PDF index with page numbers | pass | 324 entries with page numbers |
| PDF front matter roman, body arabic from 1 | pass | first labels i 1 2 3 4 5; "1" on page 2 |
| PDF time for the whole book | pass | 3266 ms for 339 pages |
| HTML index with links | pass | 356 links to uses |
| Multi-page HTML links resolve | pass | 21 pages, 1508 links, 0 broken |
| HTML callouts linked both ways (callout-links) | pass | 502 markers, 489 items |
| DocBook 5 validates (RELAX NG 5.0) | pass | valid |
| EPUBCheck passes | pass | no errors |

Errors in the builds are the sources' own, and Asciidoctor reports them
too: nested sections in an introduction, and emphasis marks around
`_hyperscript` that don't pair up.

Where Asciidoctor's output for these sources is invalid, asciidart's
isn't: emphasis cut open by index terms is balanced, `[introduction]`
and a misplaced `[partintro]` become DocBook chapters and sections,
emphasis and quotes inside literals become phrases and quotation marks,
and in EPUB a non-numeric image width is left out and a link to the
book's old website (`link:/client-side-scripting/#_hyperscript[]`) goes
to its chapter. `benchmark/PARITY.md` lists these differences, and
`test/divergences` reproduces each on both CLIs.

## What the authors had to do by hand, and what asciidart does

| Issue (`EPIC-xj1gxj`) | asciidart |
| --- | --- |
| Paged.js and print-to-PDF in a browser, a different PDF each run | `-b pdf`, byte-stable |
| Lines of code lost or repeated at page breaks (#122) | Listings split between lines, two lines kept on each side |
| Wide code cropped (#106) | Long lines wrap with a marker and a hanging indent |
| First-line indents, emphasis in italics, hyphenation, Knuth–Plass | The modern engine's defaults and theme keys (`doc/pdf.md`) |
| A hand-made index | `[index]` in PDF, HTML, the website and EPUB |
| Callouts re-implemented | Callouts in every format, kept out of copied code |
| A static-site plugin for chapter pages | `-b multipage_html5` |
| DocBook that Pandoc couldn't use | Valid DocBook 5.0 |
| An EPUB with unknown defects | EPUBCheck passes |
| Print vendors' requirements | PDF/X-4, bleed, a layout report |
