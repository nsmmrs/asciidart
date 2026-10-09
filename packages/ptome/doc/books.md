# Books with Ptome

One AsciiDoc source gives a print PDF, a website, an EPUB and DocBook,
each from one command and with no post-processing. This guide shows how,
and how to move a book from asciidoctor-pdf or from an HTML-to-print
pipeline (Paged.js and a browser).

## One source, every format

```sh
ptome -b pdf -a pdf-theme=book-theme.yml -o book.pdf book.adoc
ptome -b multipage_html5 -a callout-links -o site/index.html book.adoc
ptome -b epub3 -a callout-links -o book.epub book.adoc
ptome -b docbook5 -o book.xml book.adoc
```

- **PDF**: Ptome's own typesetting (`doc/pdf.md`): optimal line
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
`:index-category-headings!:` leaves out the letter above each group, in
every format (a PDF theme's `index_category_headings` takes
precedence).
`Document.index` gives the same entries to programs (`doc/api.md`).

## Print pages in the EPUB

An EPUB can carry the print edition's page numbers, so readers (and
accessibility tools) can go to "page 42" as in the paper book: build the
PDF with a page map, then the EPUB with it.

```sh
ptome -b pdf -a pdf-page-map=book.pages.json book.adoc
ptome -b epub3 -a epub-page-map=book.pages.json book.adoc
```

The EPUB marks each page where its first block starts (a page that starts
inside a paragraph is marked after that paragraph) and lists the pages in
its navigation (`page-list`).

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

A book whose every code block is a numbered listing, titled or not
(showing a caption only where it has one),
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

Ptome reads asciidoctor-pdf themes unchanged. Two ways to switch:

- **Pages that look as before**: `asciidoctor-compat` (`compat: [pdf]`
  in `ptome.yml`, or `-a pdf-compat`; "From Asciidoctor" below) sets
  pages as asciidoctor-pdf 2.3.27 does: its default theme, margins that
  add, one line at a time, no hyphenation unless asked, footnotes at the
  end (792 of the 797 documents of its own test suite look the same;
  `benchmark/PARITY.md`). Hyphenation (`hyphens`) works without the
  text-hyphen gem.
- **Better pages**: without it, Ptome keeps your theme and improves
  the typesetting (without a theme, it uses Ptome's house theme:
  `-a pdf-theme=default` for asciidoctor-pdf's). Expect different line
  and page breaks: justified text is broken by Knuth and Plass and
  hyphenated, paragraphs and listings keep two lines on each side of a
  page break, captions stay with their blocks. `doc/pdf.md` lists the
  settings, each with a default; set one in the theme to come closer to
  the old pages (`base_line_breaking: greedy`, `base_hyphens: false`,
  `prose_orphans: 1`, `block_margin_collapse: false`).

Optional gems asciidoctor-pdf uses (prawn-gmagick, rghost,
asciidoctor-mathematical) have no counterpart; text-hyphen's is built
in.

## From Asciidoctor

The HTML is Asciidoctor's, element for element. Its look by default is
Ptome's house style (`doc/style.md`, ADR-0011): Asciidoctor's
stylesheet followed by a few rules (a measure of about 80 characters,
near-black headings, tables with rows only), the same style as the PDF,
the website and the EPUB.

To keep Asciidoctor's look while migrating, turn on
`asciidoctor-compat` (ADR-0015), for every format or a list of them:

```yaml
# ptome.yml, in the project (the nearest one above the document)
compat: true            # or: compat: [html, pdf]
```

The same setting, from the first place that gives it:

| Where | Example |
| --- | --- |
| The command line or the document | `-a asciidoctor-compat=html,pdf`, `:asciidoctor-compat:` |
| The environment | `PTOME_COMPAT=true` |
| The project | `compat:` in `ptome.yml`, in the document's directory or one above it |
| The user | `compat:` in `~/.config/ptome/config.yml` (`$XDG_CONFIG_HOME`) |

The value is `true` (every format), `false`, or formats: `html` (HTML
pages and the website), `epub`, `docbook`, `manpage`, `pdf`; backend
names work too (`html5`, `epub3`...). A value from the environment or a
file is a default: the document's own `:asciidoctor-compat:` (or
`:asciidoctor-compat!:`) wins.

`asciidoctor-compat` aims at the files Asciidoctor's latest stable
release writes (2.0.26, with asciidoctor-pdf 2.3.27 and asciidoctor-epub3
2.3.0; the test corpus checks it, ADR-0022). It is not a mode: it gives
settings of the engine the values that release's tools have, each of which
a document can also set alone.

| Format | With `asciidoctor-compat` |
| --- | --- |
| HTML, website | Asciidoctor 2.0.26's stylesheet alone (`stylesheet=asciidoctor-2.0.26`, its web fonts with it), and the HTML behaviors below |
| EPUB | asciidoctor-epub3's stylesheet alone |
| DocBook, man pages | the behaviors below |
| PDF | asciidoctor-pdf's default theme when the document names none, and its page rules (`doc/pdf.md`, "asciidoctor-pdf's look"): the pages look as its pages do |
| Every format | `{asciidoctor-version}` is 2.0.26 (when the setting comes with the conversion), and the language behaviors below |

Ptome follows Asciidoctor's main line, which changed these things since
2.0.26; each is an attribute, whose value with `asciidoctor-compat` is the
release's:

| Attribute | Ptome | With `asciidoctor-compat` |
| --- | --- | --- |
| `html-widths` | `attribute`: `width="50%"` on tables, columns and horizontal lists | `style`: `style="width: 50%;"` |
| `highlightjs-mode` | `server`: code highlighted at conversion | `client`: highlight.js 9.18.3 in the browser |
| `html-generator` | `unless-reproducible`: no generator tag with `reproducible` | `always` |
| `html-toc` | `ptome`: parts at level 0, entries classed by level, a section's own `toclevels` | `2.0.26` |
| `html-page-break` | `class`: `<div class="page-break">` | `style`: `page-break-after: always` |
| `html-break-roles` | `kept`: a thematic break's role is its class | `dropped` |
| `html-wistia` | `embed`: Wistia's player | `video`: a video element |
| `html-nohighlight` | `honored`: the `nohighlight` option leaves a block plain | `ignored` |
| `docbook-quote-roles` | `written`: `<quote role="double">` | `none`: `<quote>` |
| `manpage-cells` | `none`: a table cell starts with its text | `spaced`: with `.sp` |
| `manpage-empty-items` | `compact`: a list item without text starts with its block | `spaced`: an empty line, then `.sp` |
| `empty-ids` | `none`: `[[]]` gives a section no ID | `empty`: an empty ID |
| `tilde-blocks` | `open`: `~~~~` delimits an open block | `text` |
| `cxx-attribute` | `defined`: `{cxx}` is C++ | `undefined` |
| `list-start` | `marker`: a list starting `3.` starts at 3 | `one` |
| `include-link` | `all`: an include that falls back to a link keeps its attributes | `role`: `role=include` alone |
| `link-self` | `image`: `link=self` links an image to itself | `self`: to the URL `self` |
| `inline-image-ids` | `kept` | `dropped` |
| `include-front-matter` | `honored`: an include's `skip-front-matter` option | `ignored` |
| `doctitle-style` | `section`: a style above the document title makes it a section of that style | `title`: the style is dropped |
| `image-imagesdir` | `kept`: an image's own `imagesdir` wins | `replaced`: the document's |
| `toml-front-matter` | `skipped`: `skip-front-matter` skips TOML front matter (`+++`) as YAML | `kept` |

Bug fixes and repairs (valid XHTML in the EPUB, its landmarks, the
index in every format) stay in every case. Each format's own setting
still works alone: `-a stylesheet=asciidoctor`, `-a
epub3-stylesheet=asciidoctor-epub3`, `-a pdf-theme=default`.

## From HTML and a browser (Paged.js)

What the HTML-to-print pipeline needed by hand, Ptome does from the
source:

| By hand in HTML and CSS | In Ptome |
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
| Fonts subset and embedded by the browser | Fonts subset and embedded by Ptome (PDF/X-4 for the printer) |

Move the print CSS's choices into a theme (`extends: default`, then page
size and margins, fonts, `prose`, `code`, running content); `doc/pdf.md`
and asciidoctor-pdf's theming guide document the keys.

