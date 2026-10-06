# Books with asciidart

One AsciiDoc source gives a print PDF, a website, an EPUB and DocBook,
each from one command and with no post-processing. This guide shows how,
and how to move a book from asciidoctor-pdf or from an HTML-to-print
pipeline (Paged.js and a browser). The Hypermedia Systems book is the test
case: `benchmark/HS.md` records what `tool/hs_acceptance.dart` checks on
it.

## One source, every format

```sh
asciidart -b pdf -a pdf-theme=book-theme.yml -o book.pdf book.adoc
asciidart -b multipage_html5 -a callout-links -o site/index.html book.adoc
asciidart -b epub3 -a callout-links -o book.epub book.adoc
asciidart -b docbook5 -o book.xml book.adoc
```

- **PDF**: asciidart's own typesetting (`doc/pdf.md`): optimal line
  breaking, hyphenation, widows and orphans, first-line indents,
  listings that never lose a line, a generated index with page numbers,
  roman then arabic page numbers, running heads, PDF/X-4 for the
  printer.
- **Website** (`multipage_html5`): a page per part and chapter
  (`multipage-level` for deeper sections), previous, up and next links,
  and every link (cross references, the table of contents, the index,
  callouts) rewritten across pages.
- **EPUB 3**: passes EPUBCheck; code wraps on small screens
  (`ebook-code-overflow=scroll` keeps lines whole).
- **DocBook 5**: valid against the DocBook 5.0 schema, for tools that
  read it (Pandoc, publishers' pipelines).

`benchmark/PARITY.md` lists where these differ from Asciidoctor's output,
and why.

## The index

Mark terms where they are discussed: `((term))` shows the term,
`(((term, subterm)))` hides it, and `indexterm:[term, see="other"]` and
`see-also` refer elsewhere. An `[index]` section at the end lists them:

```asciidoc
[index]
== Index
```

The PDF lists page numbers; HTML, the website and EPUB link to each
section the term is used in. `Document.index` gives the same entries to
programs (`doc/api.md`).

## Callouts

```asciidoc
----
const a = 1; // <1>
----
<1> Explained here.
```

Numbers needn't be kept in step by hand: `<.>` markers and `<.>` list
items are numbered in order (standard AsciiDoc, so other tools read the
source the same way).

In the PDF, the markers aren't part of the code when it is copied, and
each links to its explanation, which links back. In HTML and EPUB,
`-a callout-links` does the same, and reports markers no explanation
matches (and explanations no marker does) with their line.

## Print and web in one source

Each backend sets `backend-<name>`, so content can be for one output:

```asciidoc
ifdef::backend-pdf[]
This page intentionally left blank.
endif::[]

ifndef::backend-pdf[]
Try the example live at https://example.org[example.org].
endif::[]
```

The PDF's `basebackend` is `html`, as asciidoctor-pdf's is: use
`backend-pdf` to tell print from web.

## From asciidoctor-pdf

asciidart reads asciidoctor-pdf themes unchanged. Two ways to switch:

- **Same pages as before**: `-a pdf-compat` lays the document out as
  asciidoctor-pdf 2.3.27 does (763 of the 797 documents of its own test
  suite convert the same; `benchmark/PARITY.md`). Hyphenation
  (`hyphens`) works without the text-hyphen gem.
- **Better pages**: the default engine keeps the theme and improves the
  typesetting. Expect different line and page breaks: justified text is
  broken by Knuth and Plass and hyphenated, paragraphs and listings keep
  two lines on each side of a page break, captions stay with their
  blocks. `doc/pdf.md` lists the settings, each with a default; turn one
  off to come closer to the old pages (`base_line_breaking: greedy`,
  `:hyphens!:`, `prose_orphans: 1`, `prose_widows: 1`).

Optional gems asciidoctor-pdf uses (prawn-gmagick, rghost,
asciidoctor-mathematical) have no counterpart; text-hyphen's is built
in.

## From HTML and a browser (Paged.js)

What the HTML-to-print pipeline needed by hand, asciidart does from the
source:

| By hand in HTML and CSS | In asciidart |
| --- | --- |
| Paged.js, print CSS, print-to-PDF in a browser | `-b pdf` with a theme |
| Scrolling to the end so every page renders | Nothing: the whole book is laid out, the same bytes every time (`SOURCE_DATE_EPOCH`) |
| Code blocks that lose or repeat lines at page breaks | Listings split only between lines, every line once |
| Wide code cropped | Long lines wrap with a marker and a hanging indent |
| First-line indents that skip the first paragraph | `prose_text_indent_inner` |
| Emphasis inside italics | Upright automatically (`base_emphasis_inversion`) |
| A hand-made index | `[index]` in every format |
| Callouts re-implemented | Callouts in every format |
| A site generator plugin for chapters | `-b multipage_html5` |
| Fonts subset and embedded by the browser | Fonts subset and embedded by asciidart (PDF/X-4 for the printer) |

Move the print CSS's choices into a theme (`extends: default`, then page
size and margins, fonts, `prose`, `code`, running content); `doc/pdf.md`
and asciidoctor-pdf's theming guide document the keys.
