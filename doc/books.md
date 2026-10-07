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
  listings that never lose a line, highlighted code, footnotes at the
  bottom of the page, floating figures, chapter openers, a generated
  index with page numbers, roman then arabic page numbers, running heads,
  PDF/X-4 for the printer.
- **Website** (`multipage_html5`): a page per part and chapter
  (`multipage-level` for deeper sections), previous, up and next links,
  and every link (cross references, the table of contents, the index,
  callouts) rewritten across pages. A page is named after its section's
  id, or its `page-path` (`[#ch01,page-path=hypermedia-a-reintroduction/]`
  writes `hypermedia-a-reintroduction/index.html`, linked as the
  directory, so a site keeps its URLs); `multipage-toclevels` lists the
  pages' sections on the home page; docinfo (`docinfo=shared`) is on
  every page, for a site's own header, footer and scripts. A `toc::[]`
  macro takes the list of pages wherever it is (a contents page of its
  own: `[#contents,page-path=book/contents/]`), leaving the home page to
  the header and the preamble (a cover). The previous, up and next links
  read `multipage-nav-previous-template` (`&#8592; {{title}}`; also
  `{{basic-title}}` and `{{number}}`), `-up-` and `-next-template`, or are laid out by a `multipage_nav.mustache`
  template in a `-T` directory (`previous`, `up`, `next`, each with
  `href`, `title`, `basic-title` (without its number), `number` and
  `label`). The list's entries read
  `multipage-toc-entry-template` (`{{title}}`, `{{basic-title}}`,
  `{{number}}`), each with the section's kind and roles as its class
  (`chapter`, `part`, `chapter introduction`), and its section lists
  have the class `multipage-sections`, for a stylesheet that shows or
  hides them.
  `multipage-page-toclevels` puts a page's own sections at its top, as
  a table of contents (`toc-title`), or in a `multipage_toc.mustache`
  template (`title`, and `entries`: the list).
- **EPUB 3**: passes EPUBCheck; code wraps on small screens
  (`ebook-code-overflow=scroll` keeps lines whole). Its metadata takes
  an ISBN (`:isbn: 979-8-9909918-0-4`) and editors (`:editor: William
  Talcott`, several separated by semicolons) besides the authors and the
  `copyright`; `:epub-unique-identifier: isbn` makes the ISBN the EPUB's
  unique identifier (the uuid stays, as another).
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
section the term is used in (the EPUB's marked up as an EPUB index).
`:index-sort: code-point` orders the terms by code point (capitals
first) instead of alphabetically, and `:index-category-headings!:` leaves
out the letter above each group, in every format (a PDF theme's
`index_sort` and `index_category_headings` take precedence).
`Document.index` gives the same entries to programs (`doc/api.md`).

## Footnotes

`footnote:[...]` notes are at the bottom of the page in the PDF
(`doc/pdf.md`), at the end of the page on the website, and pop up in
EPUB readers. Their markers are templates (ADR-0010), `{{number}}` the
number: `:footnote-reference-template: {{number}}` (the default is
`[{{number}}]`) and `:footnote-label-template: {{number}}.{sp}` (HTML and
EPUB; `footnotes_reference_content` and `footnotes_label_content` in a
PDF theme). The number stays a link to the note and back.

## Caption numbers

A caption's number comes from a template (ADR-0010) where the book
wants it otherwise than `Listing 36. `: `<kind>-caption-template` for
`listing`, `figure`, `table`, `example` and `appendix`, with
`{{caption}}` (the word: `listing-caption`) and `{{number}}`, in every
format:

```asciidoc
:listing-caption: Listing
:listing-caption-template: pass:[{{caption}} {{number}}: ]
```

(`pass:[...]` keeps the trailing space, which AsciiDoc trims from an
attribute's value; `{sp}` at the end does too.) Cross references keep
their text: `Listing 36` with `:xrefstyle: short`, a figure's or an
image's too.

A book whose every code block is a numbered listing, titled or not (as
Typst numbers every figure, showing a caption only where it has one),
counts the untitled ones too with `<kind>-numbering: all`
(`listing-numbering`, `figure-numbering`, `table-numbering`,
`example-numbering`): they show no caption, but the titled ones after
them are numbered past them. A block with the `unnumbered` option
(`[source%unnumbered,bash]`) isn't counted.

```asciidoc
:listing-numbering: all
```

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

## Contents

A section with the `notoc` option stays out of the contents (the PDF's,
HTML's, the website's list of pages and the EPUB's navigation) while it
stays a section: `[colophon%notitle%notoc]` for a copyright page.

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
- **Better pages**: the default engine keeps your theme and improves the
  typesetting (without a theme, it uses asciidart's house theme:
  `-a pdf-theme=default` for asciidoctor-pdf's). Expect different line and page breaks: justified text is
  broken by Knuth and Plass and hyphenated, paragraphs and listings keep
  two lines on each side of a page break, captions stay with their
  blocks. `doc/pdf.md` lists the settings, each with a default; turn one
  off to come closer to the old pages (`base_line_breaking: greedy`,
  `:hyphens!:`, `prose_orphans: 1`, `prose_widows: 1`).

Optional gems asciidoctor-pdf uses (prawn-gmagick, rghost,
asciidoctor-mathematical) have no counterpart; text-hyphen's is built
in.

## From Asciidoctor

The HTML is Asciidoctor's, element for element. Its look by default is
asciidart's house style (`doc/style.md`, ADR-0011): Asciidoctor's
stylesheet followed by a few rules (a measure of about 80 characters,
near-black headings, tables with rows only), the same style as the PDF,
the website and the EPUB. To keep Asciidoctor's look exactly:

```sh
asciidart -a stylesheet=asciidoctor book.adoc          # HTML, the website
asciidart -b epub3 -a epub3-stylesheet=asciidoctor-epub3 book.adoc
asciidart -b pdf -a pdf-theme=default book.adoc        # or -a pdf-compat
```

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

## From Typst

The Hypermedia Systems book moved from AsciiDoc to Typst; its Typst
edition's features in AsciiDoc (`benchmark/HS.md` checks the whole book):

| Typst | AsciiDoc |
| --- | --- |
| `#index[term]`, `#indexed[term]` | `(((term)))`, `((term))` |
| `#figure(caption: [...], ...)` | `.Title` above the listing or image (`listing-caption`, `figure-caption`) |
| `#set figure(placement: auto)` | `image_placement: auto` (theme) |
| `#footnote[...]` | `footnote:[...]`, at the bottom of the page |
| `#show link: ... footnote(it.dest)` | `:show-link-uri: footnote` |
| `#smallcaps[...]` | `[.sc]#...#` and `role_sc_font_variant: small-caps` |
| `#quote(block: true, attribution: [...])` | `[quote, Author, Source]` |
| A boxed note in the contents (`html-note`) | A section with a role, `section_role_<role>_*` (theme) |
| `#important[Title][...]` | `[IMPORTANT]` with a `.Title`, `:important-caption:` empty |
| `@label`, `<label>` | `<<id>>`, `[#id]` |
| `set page(header: ...)` | `header_recto_*`, `header_verso_*` (theme), `{part-title}`, `{chapter-title}` |
| `pagebreak(to: "odd")` before chapters | `:media: prepress` |
| A chapter's label above its title | `heading_h2_content` (theme): a template with `{{signifier}}`, `{{numeral}}` and `{{title}}` |
| `#make-index()` in two columns | `[index]`, `index_columns`, `index_pagenum_text_align: right` (theme) |
| `#show raw: ...` highlighting | `:source-highlighter: highlight.js` |
| pandoc for the EPUB | `-b epub3` (`isbn`, `editor`, `front-cover-image`) |
| A site generator (muteferrika) | `-b multipage_html5`, `page-path`, docinfo |

