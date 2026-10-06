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
  --report /tmp/hs-report.md
```

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
paragraph that follows another, with no space between them. The book isn't
vendored: its `book/` directory isn't under its repository's license.

## Latest run (2026-10-06)

| Check | Result | Detail |
| --- | --- | --- |
| PDF build | pass | 2946 ms, 2096 KB, 10 errors, 4 warnings |
| HTML build | pass | 162 ms, 902 KB, 6 errors, 4 warnings |
| EPUB 3 build | pass | 312 ms, 1836 KB, 6 errors, 4 warnings |
| DocBook 5 build | pass | 155 ms, 894 KB, 6 errors, 4 warnings |
| PDF byte-stable across runs | pass | SOURCE_DATE_EPOCH=0 |
| PDF has each listing line once (#122) | pass | 600 distinct lines of 24+ characters: 0 missing, 0 repeated |
| PDF crops no text (#106) | pass | 0 words past the page edge, 0 past the margin |
| PDF index with page numbers | pass | 324 entries with page numbers |
| PDF front matter roman, body arabic from 1 | pass | first labels i 1 2 3 4 5; "1" on page 2 |
| PDF time for the whole book | pass | 2946 ms for 339 pages |
| HTML index with links | FAIL | 0 links to uses |
| DocBook 5 validates (RELAX NG 5.0) | FAIL | 9 errors; /home/nes/.cache/asciidart-work/hs-out/HypermediaSystems.xml:9469: parser error : Opening and ending tag mismatch: emphasis line 9469 and primary |
| EPUBCheck passes | FAIL | 18 errors; ERROR(RSC-005): /home/nes/.cache/asciidart-work/hs-out/HypermediaSystems.epub/EPUB/nav.xhtml(12,27): Error while parsing file: Heading elements must contain text |

Errors in the builds are the sources' own, and Asciidoctor reports them
too: nested sections in an introduction, and emphasis marks around
`_hyperscript` that don't pair up. The DocBook and EPUB failures are the
next cards (FEAT-86wssj, FEAT-fdbns0), and so is the HTML index
(FEAT-wnjjxk).
