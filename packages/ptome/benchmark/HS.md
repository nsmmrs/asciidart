# Hypermedia Systems acceptance

The Hypermedia Systems authors left AsciiDoc for Typst because no
toolchain gave them a print-quality PDF, an index outside PDF, a book
website, valid DocBook or an EPUB without hand work (lane EPIC-xj1gxj).
`tool/hs_acceptance.dart` builds their AsciiDoc sources
(bigskysoftware/hypermedia-systems-old at
`2e8c4be47f64de281d0e325599bcbe69e7ed05ce`) with the Ptome executable
and checks what they had to fix by hand.

```sh
dart run tool/hs_acceptance.dart --exe dist/ptome-linux-x64 \
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

Where Asciidoctor's output for these sources is invalid, Ptome's
isn't: emphasis cut open by index terms is balanced, `[introduction]`
and a misplaced `[partintro]` become DocBook chapters and sections,
emphasis and quotes inside literals become phrases and quotation marks,
and in EPUB a non-numeric image width is left out and a link to the
book's old website (`link:/client-side-scripting/#_hyperscript[]`) goes
to its chapter. `benchmark/PARITY.md` lists these differences, and
`test/divergences` reproduces each on both CLIs.

## What the authors had to do by hand, and what Ptome does

| Issue (`EPIC-xj1gxj`) | Ptome |
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
AsciiDoc only: valid AsciiDoc as Ptome reads it, no post-processing.
The edited sources are a local branch of hypermedia-systems-old (never
vendored here), built with

```sh
dart run tool/hs_acceptance.dart --exe build/ptome \
  --source ~/Work/ports/hypermedia-systems-ptome --report benchmark/HS.md
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
docinfo (footer, the Typst site's color customizer); the
EPUB's ISBN, editor and cover; `build.sh` for each format, as the Typst
edition's justfile. Then the Typst edition's text: its listings (rewrapped
to 73 columns, its callout changes), its later wording (a word-level merge
that keeps this edition's markup and index terms), its chapter titles and
figure references by number; and its look: caption, footnote and website
navigation templates (ADR-0010), the website's and the EPUB's stylesheets
after the Typst edition's, its anchors as section ids, the title page and
the dedication as its. Every feature is the AsciiDoc's own or Ptome's
(each in `doc/pdf.md` or `doc/books.md`); none is a workaround.

| Typst edition | AsciiDoc | Status |
| --- | --- | --- |
| Title page: the title in Jaro, upper case, slanted | Document title, `title_page` theme keys (`font_style: italic`: Jaro has no italic, the modern engine slants it) | Done |
| Copyright and dedication pages without a heading or running content | `[colophon%notitle%noheader%nofooter]`, `[dedication%...]` | Done |
| Foreword (page 1), then the contents | `[preface]`, `toc::[]`, `page_numbering_start_at: 4` | Done |
| Contents: no dot leaders, no numbers, four levels | `toc` theme keys, `toc_entry_content: '{{title}}'`, `toclevels` | Done |
| Part openers alone on a recto page, no running content | `:media: prepress`, `heading_part_break_after: always` | Done |
| Chapter openers: sunk, a gray "Chapter N" line, no running content | `heading_h2_padding`, `heading_h2_content` (a template) | Done |
| Running heads: `14 · I Hypermedia Concepts`, `3. A Web 1.0 Application · 71` | `header` theme keys, `{{#part-numeral}}...{{/part-numeral}}` templates | Done |
| Introduction unnumbered; numbers to four levels | `:sectnums!:` around it, `sectnumlevels` | Done |
| HTML Notes boxed, and in the contents | `[.html-note]` sections, `section_role_html-note_*` theme keys | Done |
| Sidebars: a gray fill, rules above and below, sans | `sidebar` theme keys | Done |
| "Opportunity" boxes: a blue fill, rules, a bold title, no label | `[IMPORTANT]` with a title, `:important-caption:` empty, `admonition` theme keys | Done |
| Listings: "Listing N:" captions, callouts | Titles, `listing-caption-template: pass:[{{caption}} {{number}}: ]`, callouts | Done |
| Callout markers `[1]` in bold gray old-style sans; explanations a numbered list | `conum_glyphs: '[{{number}}]'`, `conum_font_*`, `callout_list_marker_content: '{{number}}.'` | Done |
| Definition terms run in, hanging indent | `description_list_term_display: inline` | Done |
| Ordered list numbers in old-style sans | `olist_marker_font_family`, `olist_marker_font_variant_numeric` | Done |
| Quote attributions at the right | `quote_cite_text_align: right` | Done |
| Spacing: lists, figures, quotes, sidebars, definition lists each their own | `<category>_margin_top`, `<category>_margin_bottom`, `sidebar_title_margin_bottom` | Done (317 pages to 320) |
| Listings highlighted | `source-highlighter=highlight.js` | Done |
| Figures: "Figure N:" captions below, centered; referred to by number | `image_caption_*` theme keys, `figure-caption-template`, `:xrefstyle: short` | Done |
| Figures at the top or bottom of their page, or the next page's top when they don't fit, the text filling in | `image_placement: auto` | Done |
| Footnotes at the bottom of the page, numbered per page, a superscript number | `footnote:[]` (the modern engine's default), `footnotes_numbering: page`, `footnotes_reference_content`, `footnotes_label_content`, `footnote-reference-template` | Done |
| Links show their URL in a footnote | `:show-link-uri: footnote` | Done |
| Justified, hyphenated, first-line indents | Modern engine, `prose` theme keys | Done |
| Small capitals | `[.sc]#...#`, `role_sc_font_variant` | Done |
| Index: two columns in sans, no letter headings, page numbers in a column, each page once | `[index]`, `index_pagenum_text_align: right`, `index_category_headings: false`, `index_font_*` | Done |
| Index terms keep the emphasis around them whole | `(((...)))` | Done |
| No space before a paragraph that starts with an index term | `(((...)))` | Done |
| Website: a page per front matter part, part and chapter, previous and next | `multipage_html5` | Done |
| Website: the same URLs (`/hypermedia-a-reintroduction/`) and a full contents | `page-path` on each part and chapter, `multipage-toclevels` | Done |
| Website: footer, colors, color customizer | `docinfo=shared` (the edition's own script, as the Typst site's) | Done |
| Website: the Typst site's stylesheet (fonts, layout, dark mode), a Contents box on each page, a contents page with numbered chapters, no section numbers | `stylesheet`, `linkcss`, `multipage-page-toclevels`, `multipage_toc.mustache`, the list's classes (`chapter introduction`), `-a sectnums!` | Done |
| Website: "Previous: Title", "Next: Title" | `multipage_nav.mustache` with `{{basic-title}}` | Done |
| Website: the Typst site's anchors (`#what-is-hypermedia-`) | `:idprefix:`, `:idseparator: -`, explicit ids where punctuation differs | Done (246 of 257; the rest are titles repeated in other chapters) |
| Website and EPUB: listings highlighted | `source-highlighter=highlight.js` (the EPUB packs the theme) | Done |
| EPUB: cover, rights, ISBN (its identifier), editor | `front-cover-image`, `copyright`, `isbn`, `epub-unique-identifier: isbn`, `editor` | Done |
| EPUB: pandoc's stylesheet, no section numbers | `epub3-stylesdir`, `-a sectnums!` | Done |
| Title page: the title large, on two lines, at the inner margin | `title_page_title_font_size`, `_line_height`, `_margin_left` | Done |
| Dedication: three lines in the middle of the page | `section_role_<role>_vertical_align: middle`, `role_<role>_text_indent`, `role_<role>_margin_bottom` | Done |

### Spacing against the Typst edition

`tool/hs/spacing.dart TYPST.pdf ASCIIDOC.pdf` measures the distance (in
points, from a line's top to the next one's) between the same passages
in both editions. The Typst edition is built as its README says (Typst
0.14.2, `typst compile --font-path fonts`, with Libertinus), but its code
font, Berkeley Mono, is commercial and not in its repository: the
reference here sets code and ASCII art in DejaVu Sans Mono instead
(`mono-font` changed in a copy of the sources). Without a monospace font
Typst falls back to a proportional one and breaks the diagrams.

With the edited edition's theme (the per-element `<category>_margin_*`
keys), every probe of the text is within a tenth of a point. The probes
of code differ by up to 2.5 points, and the page count (317 to 320), but
they measure the stand-in font, not Berkeley Mono, whose metrics aren't
available.

| Probe | Typst | AsciiDoc | Difference |
| --- | --- | --- | --- |
| paragraph to paragraph (line pitch) | 15.1 | 15.1 | -0.0 |
| paragraph to section heading | 25.0 | 25.1 | +0.0 |
| section heading to quote | 19.7 | 19.7 | -0.0 |
| quote to its attribution | 33.5 | 33.5 | +0.0 |
| quote attribution to paragraph | 19.9 | 19.9 | -0.0 |
| paragraph to definition term | 21.1 | 21.1 | -0.0 |
| definition to paragraph | 21.1 | 21.1 | -0.0 |
| paragraph to listing caption | 21.6 | 21.6 | +0.0 |
| paragraph to code (no caption) | 22.7 | 21.8 | -0.9 |
| listing caption to code | 16.3 | 13.8 | -2.5 |
| code line pitch | 12.2 | 11.4 | -0.8 |
| code to callout list | 18.4 | 18.5 | +0.1 |
| callout list item to item | 15.1 | 15.1 | -0.0 |
| callout list to paragraph | 15.1 | 15.1 | -0.0 |
| bullet item to item | 15.1 | 15.1 | -0.0 |
| sidebar title to text | 15.9 | 15.9 | -0.0 |
| paragraph to sidebar | 47.4 | 47.4 | -0.0 |
| subsection heading to paragraph | 16.9 | 16.9 | -0.0 |

### Page by page against the golden build

The Hypermedia Systems team shared a build of the Typst edition (Typst
0.15.1, 316 Letter pages) that embeds every font it uses, Berkeley Mono
included. Its fonts were extracted for local comparison builds (the port's
`scripts/extract-golden-fonts.py`: the TrueType subsets get a cmap rebuilt
from their ToUnicode maps and the PDF's own glyph widths), and its pages
rasterized once (`pdftoppm -gray -r 100`). The port's
`scripts/pagediff.sh` converts the edited edition with those fonts
(`build.sh pdf-golden`), rasterizes the same pages and compares each pair
with ImageMagick: the pixels that differ by more than 15% once both images
are blurred by a pixel (the same glyphs embedded by Typst and by libpdf
rasterize a little differently at their edges, which the blur absorbs;
anything moved by half a pixel still shows). A page passes under 0.1% of
its pixels. `tool/hs/page_lines.dart` compares the words' positions
exactly.

Result: 316 pages against 316, every page under the threshold (the largest
0.095%; 251 pages under 0.02%). The text, line breaks, page breaks, figure
placement, footnotes, running heads, contents and index are the golden
build's.

The golden PDF and the fonts taken from it are licensed for this
comparison only: neither is committed anywhere.

The page-for-page match copied a few defects of the Typst build on
purpose (tags `hs-golden-parity-2026-10-06` in Ptome and libpdf,
`golden-parity-2026-10-06` in the port): index terms that lost the space
before a parenthesis, a heading that lost its `<progress>`, a callout
turned into a bullet, lists and code blocks set differently because of
how pandoc converted them, the contents page listed in the index. The
port's source has the intended content since (2026-10-07, ADR-0013), so
19 of the 316 pages differ from the Typst build: the pages of those
places and the pages after them in their chapters, the index's.

Not in scope: the Markdown export and the Kindle file, which the Typst
edition makes with pandoc and calibre; the same tools read Ptome's
DocBook and EPUB.

### Build time against Typst (2026-10-07)

The golden build (`build.sh pdf-golden`, 316 pages) against the Typst
edition compiled by Typst 0.15.1 from its sources, on the same machine
(12 cores), each the median of three runs:

| | Before | After |
| --- | --- | --- |
| Ptome (native executable) | 10.1 s | 3.8 s |
| Typst 0.15.1 | 3.9 s | 3.9 s |

Typst spreads its work over the cores (8 s of user time and 4 s of
system time for the 3.9 s); Ptome works on one. What `tool/profile.dart`
(CPU samples from the VM) found and what changed, each change keeping the
PDF the same, byte for byte until the last, page image for page image
after it:

- The line breaker computed a hyphenation's cost (the letters on each
  side) for every line that could end there; it is the same for all, so
  it is computed once (libpdf).
- Patterns built inside the line wrapping's loops are built once; the
  tokenizer and the trimming of spaces, which ran for every piece of
  text, are written out as scans (checked against the patterns on 200,000
  random strings).
- A word's width is shaped once per font and features, not at each
  measurement.
- Streams are compressed, and PNG data read, with the Dart VM's native
  zlib rather than libpdf's Dart one (`PdfWriterOptions.zlib`).

### Using every core (2026-10-07)

The same build on the `multicore` branch (ADR-0016), median of five runs
on a quiet machine (6 cores, 12 threads); each step keeps the PDF the
same, byte for byte, at 1, 2, 6 and 12 workers (`tool/jobs_check.dart`):

| | Wall time | CPU time |
| --- | --- | --- |
| Ptome before the branch | 3.82 s | 4.26 s |
| Ptome, one core (`-a jobs=1`) | 2.83 s | |
| Ptome, physical cores (default, 6) | 2.08 s | 3.75 s |
| Ptome, 12 workers | 2.07 s | |
| Typst 0.15.1 | 3.72 s | 11.77 s |

What changed:

- Work done more than once is done once: a paragraph's line breaks are
  kept for the widths it is broken at again; the index is filled in by
  laying out again from the last clean page before it (557 → 9 ms), and
  page-numbered footnotes from the first page whose numbers changed,
  taking back the runs of pages where none did (605 → 123 ms).
- PNG images with transparency are encoded on other cores from the
  moment the walk reads them (the save: 1078 → 156 ms), and the pages'
  content streams are compressed there once they are painted (156 →
  56 ms).
- hilite's first auto-detection, which compiles every grammar (one
  listing is an HTTP response with an HTML body), takes 103 ms instead of
  180.

Laying out chapters on several workers was measured before being built
(`tool/spike_chunks.dart`) and isn't: every worker would repeat the parse
and the walk, which slow down 1.5–3x as workers are added, as processes
as much as isolates (ADR-0016, "Measured").

## Latest run, edited edition (2026-10-06)

| Check | Result | Detail |
| --- | --- | --- |
| PDF build | pass | 20978 ms, 2136 KB, 0 errors, 0 warnings |
| HTML build | pass | 926 ms, 1290 KB, 0 errors, 0 warnings |
| EPUB 3 build | pass | 1461 ms, 2735 KB, 0 errors, 0 warnings |
| DocBook 5 build | pass | 507 ms, 901 KB, 0 errors, 0 warnings |
| Multi-page HTML build | pass | 966 ms, 5 KB, 0 errors, 0 warnings |
| PDF byte-stable across runs | pass | SOURCE_DATE_EPOCH=0 |
| PDF has each listing line once (#122) | pass | 641 distinct lines of 24+ characters: 0 missing, 0 repeated |
| PDF crops no text (#106) | pass | 0 words past the page edge, 297 past the margin |
| PDF index with page numbers | pass | 319 entries with page numbers |
| PDF index lists each page once | pass | no page listed twice for a term |
| PDF front matter roman, body arabic from 1 | pass | first labels i ii iii iv 1 2; "1" on page 5 |
| PDF time for the whole book | pass | 20978 ms for 314 pages |
| HTML index with links | pass | 347 links to uses |
| Multi-page HTML links resolve | pass | 25 pages, 2013 links, 0 broken |
| HTML callouts linked both ways (callout-links) | pass | 491 markers, 488 items |
| DocBook 5 validates (RELAX NG 5.0) | pass | valid |
| EPUBCheck passes | pass | no errors |
