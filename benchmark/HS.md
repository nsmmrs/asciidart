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
| PDF build | pass | 8774 ms, 2147 KB, 6 errors, 4 warnings |
| HTML build | pass | 401 ms, 1048 KB, 6 errors, 5 warnings |
| EPUB 3 build | pass | 910 ms, 1855 KB, 6 errors, 5 warnings |
| DocBook 5 build | pass | 492 ms, 894 KB, 6 errors, 4 warnings |
| Multi-page HTML build | pass | 459 ms, 31 KB, 6 errors, 5 warnings |
| PDF byte-stable across runs | pass | SOURCE_DATE_EPOCH=0 |
| PDF has each listing line once (#122) | pass | 600 distinct lines of 24+ characters: 0 missing, 0 repeated |
| PDF crops no text (#106) | pass | 0 words past the page edge, 0 past the margin |
| PDF index with page numbers | pass | 331 entries with page numbers |
| PDF index lists each page once | pass | no page listed twice for a term |
| PDF front matter roman, body arabic from 1 | pass | first labels i 1 2 3 4 5; "1" on page 2 |
| PDF time for the whole book | pass | 8774 ms for 339 pages |
| HTML index with links | pass | 356 links to uses |
| Multi-page HTML links resolve | pass | 21 pages, 1508 links, 0 broken |
| HTML callouts linked both ways (callout-links) | pass | 502 markers, 489 items |
| DocBook 5 validates (RELAX NG 5.0) | pass | valid |
| EPUBCheck passes | pass | no errors |

Errors in the builds are the sources' own, and Asciidoctor reports them
too: nested sections in an introduction. (Emphasis marks around
`_hyperscript` used to pair across index terms; they no longer do.)
Timings in both tables are from a busy machine (a load average of 25);
on an idle one the whole PDF takes about 3 seconds.

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

The edits: a master file at the root that sets its PDF theme
(after `lib/style.typ`, with Libertinus and Jaro) and generates the index;
the front matter (copyright page, dedication, foreword) as `[colophon]`,
`[dedication]` and `[preface]` sections, the first two `%notitle`; the
contents after the foreword; section numbers turned on again after each
chapter's unnumbered HTML Notes (the old site built chapters one by one);
chapter 7's first sections at section level; the Opportunity boxes
without a label; chapter 9's closing quote in small capitals; a stray
callout in chapter 6; `page-path` on each part and chapter; the site's
docinfo (colors, footer, the Typst site's color customizer); the
EPUB's ISBN, editor and cover; `build.sh` for each format, as the Typst
edition's justfile. Every feature is the AsciiDoc's own or asciidart's
(each in `doc/pdf.md` or `doc/books.md`); none is a workaround.

| Typst edition | AsciiDoc | Status |
| --- | --- | --- |
| Title page: the title in Jaro, upper case, slanted | Document title, `title_page` theme keys (`font_style: italic`: Jaro has no italic, the modern engine slants it) | Done |
| Copyright and dedication pages without a heading or running content | `[colophon%notitle%noheader%nofooter]`, `[dedication%...]` | Done |
| Foreword (page 1), then the contents | `[preface]`, `toc::[]`, `page_numbering_start_at: 4` | Done |
| Contents: no dot leaders, four levels | `toc` theme keys, `toclevels` | Done |
| Part openers alone on a recto page, no running content | `:media: prepress`, `heading_part_break_after: always` | Done |
| Chapter openers: sunk, a gray "Chapter N" line, no running content | `heading_h2_padding`, `heading_h2_label_display: block` | Done |
| Running heads: `14 · I Hypermedia Concepts`, `3. A Web 1.0 Application · 71` | `header` theme keys, `header_title_style: toc` | Done (`14 · I: Hypermedia Concepts`) |
| Introduction unnumbered; numbers to four levels | `:sectnums!:` around it, `sectnumlevels` | Done |
| HTML Notes boxed, and in the contents | `[.html-note]` sections, `section_role_html-note_*` theme keys | Done |
| Sidebars: a gray fill, rules above and below, sans | `sidebar` theme keys | Done |
| "Opportunity" boxes: a blue fill, rules, a bold title, no label | `[IMPORTANT]` with a title, `:important-caption:` empty, `admonition` theme keys | Done |
| Listings: "Listing N" captions, callouts | Titles, `listing-caption`, callouts | Done |
| Listings highlighted | `source-highlighter=highlight.js` | Done |
| Figures: "Figure N" captions below, centered | `image_caption_*` theme keys | Done |
| Figures float to the next page when they don't fit, the text filling in | `image_placement: auto` | Done (to the top of the next page; Typst also to the bottom) |
| Footnotes at the bottom of the page | `footnote:[]` (the modern engine's default) | Done (numbered per chapter, Typst per page) |
| Links show their URL in a footnote | `:show-link-uri: footnote` | Done |
| Justified, hyphenated, first-line indents | Modern engine, `prose` theme keys | Done |
| Small capitals | `[.sc]#...#`, `role_sc_font_variant` | Done |
| Index: two columns in sans, no letter headings, page numbers in a column, each page once | `[index]`, `index_pagenum_text_align: right`, `index_category_headings: false`, `index_font_*` | Done |
| Index terms keep the emphasis around them whole | `(((...)))` | Done |
| No space before a paragraph that starts with an index term | `(((...)))` | Done |
| Website: a page per front matter part, part and chapter, previous and next | `multipage_html5` | Done |
| Website: the same URLs (`/hypermedia-a-reintroduction/`) and a full contents | `page-path` on each part and chapter, `multipage-toclevels` | Done |
| Website: footer, colors, color customizer | `docinfo=shared` (the edition's own script, as the Typst site's) | Done |
| Website and EPUB: listings highlighted | `source-highlighter=highlight.js` (the EPUB packs the theme) | Done |
| EPUB: cover, rights, ISBN, editor | `front-cover-image`, `copyright`, `isbn`, `editor` | Done |

### Spacing against the Typst edition

`tool/hs/spacing.dart TYPST.pdf ASCIIDOC.pdf` measures the distance (in
points, from a line's top to the next one's) between the same passages
in both editions. With the edited edition's theme (the per-element
`<category>_margin_*` keys), the AsciiDoc edition has 319 pages to the
Typst edition's 316. What is left: the Typst authors rewrapped their code
to 73 columns (fewer listing lines wrap there), and listings without a
caption sit 1.5 points lower.

| Probe | Typst | AsciiDoc | Difference |
| --- | --- | --- | --- |
| paragraph to paragraph (line pitch) | 15.1 | 15.1 | -0.0 |
| paragraph to section heading | 25.0 | 26.4 | +1.3 |
| section heading to quote | 19.7 | 20.4 | +0.7 |
| quote to its attribution | 33.5 | 34.4 | +0.9 |
| quote attribution to paragraph | 19.9 | 20.5 | +0.6 |
| paragraph to definition term | 21.1 | 21.1 | -0.0 |
| definition to paragraph | 21.1 | 21.1 | -0.0 |
| paragraph to listing caption | 21.6 | 19.0 | -2.6 |
| paragraph to code (no caption) | 21.8 | 23.3 | +1.5 |
| listing caption to code | 14.2 | 13.8 | -0.4 |
| code line pitch | 11.3 | 11.4 | +0.1 |
| code to callout list | 18.4 | 18.5 | +0.1 |
| callout list item to item | 15.1 | 15.1 | -0.0 |
| callout list to paragraph | 15.1 | 15.1 | -0.0 |
| bullet item to item | 15.1 | 15.1 | -0.0 |
| sidebar title to text | 15.9 | 17.5 | +1.6 |
| paragraph to sidebar | 47.4 | 47.4 | -0.0 |
| subsection heading to paragraph | 16.9 | 16.9 | -0.0 |

Not in scope: the Markdown export and the Kindle file, which the Typst
edition makes with pandoc and calibre; the same tools read asciidart's
DocBook and EPUB.

## Latest run, edited edition (2026-10-06)

| Check | Result | Detail |
| --- | --- | --- |
| PDF build | pass | 10422 ms, 2340 KB, 0 errors, 0 warnings |
| HTML build | pass | 1039 ms, 1295 KB, 0 errors, 0 warnings |
| EPUB 3 build | pass | 1533 ms, 2738 KB, 0 errors, 0 warnings |
| DocBook 5 build | pass | 631 ms, 902 KB, 0 errors, 0 warnings |
| Multi-page HTML build | pass | 1076 ms, 43 KB, 0 errors, 0 warnings |
| PDF byte-stable across runs | pass | SOURCE_DATE_EPOCH=0 |
| PDF has each listing line once (#122) | pass | 600 distinct lines of 24+ characters: 0 missing, 0 repeated |
| PDF crops no text (#106) | pass | 0 words past the page edge, 0 past the margin |
| PDF index with page numbers | pass | 329 entries with page numbers |
| PDF index lists each page once | pass | no page listed twice for a term |
| PDF front matter roman, body arabic from 1 | pass | first labels i ii iii iv 1 2; "1" on page 5 |
| PDF time for the whole book | pass | 10422 ms for 337 pages |
| HTML index with links | pass | 356 links to uses |
| Multi-page HTML links resolve | pass | 24 pages, 1627 links, 0 broken |
| HTML callouts linked both ways (callout-links) | pass | 502 markers, 489 items |
| DocBook 5 validates (RELAX NG 5.0) | pass | valid |
| EPUBCheck passes | pass | no errors |
