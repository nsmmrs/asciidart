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

## The AsciiDoc edition at the Typst edition's features

The authors' current edition is Typst (bigskysoftware/hypermedia-systems:
`lib/style.typ`, `definitions.typ`, `indexing.typ`, `code-callouts.typ`;
pandoc for the EPUB, muteferrika for the website). Lane EPIC-0yhk8f
brings the AsciiDoc edition to the same features with changes to its
AsciiDoc only: valid AsciiDoc as asciidart reads it, no post-processing.
The edited sources are a local branch of hypermedia-systems-old (never
vendored here), built with

```sh
dart run tool/hs_acceptance.dart --exe build/asciidart \
  --source ~/Work/ports/hypermedia-systems-asciidart --report benchmark/HS.md
```

The edits so far: a master file at the root that sets its PDF theme
(after `lib/style.typ`, with Libertinus and Jaro) and generates the index;
the front matter (copyright page, dedication, foreword) as `[colophon]`,
`[dedication]` and `[preface]` sections, the first two `%notitle`; the
contents after the foreword; section numbers turned on again after each
chapter's unnumbered HTML Notes (the old site built chapters one by one);
chapter 7's first sections at section level; the Opportunity boxes
without a label; chapter 9's closing quote in small capitals.

| Typst edition | AsciiDoc | Status |
| --- | --- | --- |
| Title page: the title in Jaro, upper case, slanted | Document title, `title_page` theme keys | Slant: FEAT-fq3c90 |
| Copyright and dedication pages without a heading or running content | `[colophon%notitle%noheader%nofooter]`, `[dedication%...]` | Done |
| Foreword (page 1), then the contents | `[preface]`, `toc::[]`, `page_numbering_start_at: 4` | Done |
| Contents: no dot leaders, four levels | `toc` theme keys, `toclevels` | Done |
| Part openers alone on a recto page, no running content | `:media: prepress`, `heading_part_break_after: always` | Done |
| Chapter openers: sunk, a gray "Chapter N" line, no running content | `heading_h2_padding`, `heading_h2_label_display: block` | Done |
| Running heads: `14 · I Hypermedia Concepts`, `3. A Web 1.0 Application · 71` | `header` theme keys, `header_title_style: toc` | Done (`14 · I: Hypermedia Concepts`) |
| Introduction unnumbered; numbers to four levels | `:sectnums!:` around it, `sectnumlevels` | Done |
| HTML Notes boxed, and in the contents | `[.html-note]` sections | FEAT-t089sr |
| Sidebars: a gray fill, rules above and below, sans | `sidebar` theme keys | Done |
| "Opportunity" boxes: a blue fill, rules, a bold title, no label | `[IMPORTANT]` with a title, `:important-caption:` empty, `admonition` theme keys | Done |
| Listings: "Listing N" captions, callouts | Titles, `listing-caption`, callouts | Done |
| Listings highlighted | `source-highlighter=highlight.js` | Done |
| Figures: "Figure N" captions below, centered | `image_caption_*` theme keys | Done |
| Figures float to the top or bottom of a page | Images | FEAT-9dmbh2 |
| Footnotes at the bottom of the page | `footnote:[]` (the modern engine's default) | Done (numbered per chapter, Typst per page) |
| Links show their URL in a footnote | `:show-link-uri: footnote` | Done |
| Justified, hyphenated, first-line indents | Modern engine, `prose` theme keys | Done |
| Small capitals | `[.sc]#...#`, `role_sc_font_variant` | Done |
| Index: two columns in sans, no letter headings, page numbers in a column, each page once | `[index]`, `index_pagenum_text_align: right`, `index_category_headings: false`, `index_font_*` | Done |
| Index terms keep the emphasis around them whole | `(((...)))` | Done |
| No space before a paragraph that starts with an index term | `(((...)))` | Done |
| Website: a page per front matter part, part and chapter, previous and next | `multipage_html5` | Done |
| Website: the same URLs (`/hypermedia-a-reintroduction/`) and a full contents | Sections | FEAT-95fvvy |
| Website: landing page, footer, stylesheet, color customizer | Docinfo, `stylesheet` | FEAT-95fvvy, FEAT-y6ndrm |
| Website and EPUB: listings highlighted | `source-highlighter=highlight.js` | Done |
| EPUB: cover, rights, ISBN, editor | `front-cover-image`, `copyright`, `isbn`, `editor` | ISBN and editor: FEAT-9b8gpj |

Not in scope: the Markdown export and the Kindle file, which the Typst
edition makes with pandoc and calibre; the same tools read asciidart's
DocBook and EPUB.

## Latest run, edited edition (2026-10-06)

| Check | Result | Detail |
| --- | --- | --- |
| PDF build | pass | 10775 ms, 2250 KB, 0 errors, 0 warnings |
| HTML build | pass | 514 ms, 1083 KB, 0 errors, 1 warnings |
| EPUB 3 build | pass | 1072 ms, 1872 KB, 0 errors, 2 warnings |
| DocBook 5 build | pass | 648 ms, 902 KB, 0 errors, 0 warnings |
| Multi-page HTML build | pass | 571 ms, 32 KB, 0 errors, 1 warnings |
| PDF byte-stable across runs | pass | SOURCE_DATE_EPOCH=0 |
| PDF has each listing line once (#122) | pass | 600 distinct lines of 24+ characters: 0 missing, 0 repeated |
| PDF crops no text (#106) | pass | 0 words past the page edge, 0 past the margin |
| PDF index with page numbers | pass | 329 entries with page numbers |
| PDF front matter roman, body arabic from 1 | pass | first labels i 1 2 3 4 5; "1" on page 2 |
| PDF time for the whole book | pass | 10775 ms for 323 pages |
| HTML index with links | pass | 356 links to uses |
| Multi-page HTML links resolve | pass | 24 pages, 1529 links, 0 broken |
| HTML callouts linked both ways (callout-links) | pass | 502 markers, 489 items |
| DocBook 5 validates (RELAX NG 5.0) | pass | valid |
| EPUBCheck passes | pass | no errors |
