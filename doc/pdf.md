# PDF output

`asciidart -b pdf` writes a PDF with asciidart's own PDF library, libpdf,
and reads asciidoctor-pdf's YAML themes unchanged (`pdf-theme`,
`pdf-themesdir`, `pdf-fontsdir`). It needs an output file and the native
executable.

There are two layout engines:

- **Modern** (the default): asciidart's own typesetting, described
  below.
- **Compatibility** (`-a pdf-compat`): the layout of asciidoctor-pdf
  2.3.27, Prawn's line wrapping included. `benchmark/PARITY.md` records how
  closely it matches the gem. The keys below are not read in this mode,
  except `base_hyphens` and the `hyphens` attribute, which the gem has.

## The modern engine

Every setting has a default. Each one is a key of the theme (as written
in the YAML, `prose_orphans` is `prose: { orphans: 2 }`) or an attribute
of the document.

### Paragraphs

| Key | Default | What it does |
| --- | --- | --- |
| `base_line_breaking` | `optimal` | `optimal` breaks justified text where its spacing is most even over the whole paragraph (Knuth and Plass); `greedy` fills one line at a time, as Prawn does. |
| `prose_orphans` | `2` | The fewest lines of a paragraph left at the bottom of a page. |
| `prose_widows` | `2` | The fewest lines of a paragraph carried to the top of the next page. |
| `prose_text_indent` | `0` | The indent of every paragraph's first line. Numbers are points; `1.5em` is relative to the paragraph's font size, `2rem` to the base font size. |
| `prose_text_indent_inner` | `0` | The indent of the first line of a paragraph that follows another paragraph only (not the first after a heading, a list or a block), as books set it. |
| `prose_margin_inner` | none | The space between two paragraphs; `0` with `prose_text_indent_inner` for indented, unspaced paragraphs. |

### Space around blocks

Each kind of block has its own space above and below:
`<category>_margin_top` and `<category>_margin_bottom`, for the
categories `prose` (paragraphs), `code` (listing and literal blocks),
`image`, `media`, `table`, `quote`, `verse`, `sidebar`, `example`,
`admonition`, `list`, `description_list`, `callout_list`, `open`,
`thematic_break`, `pass` and `stem`. Below a block, the space is its own
or `block_margin_bottom` (asciidoctor-pdf's one setting for all blocks),
and at least the space the next block wants above it: adjacent margins
collapse to the larger, as in CSS. Above the first block after a heading,
what the heading's margin below leaves; none at the start of another
container, or at the top of a page.

A quote's attribution has its own space above (`quote_cite_margin_top`,
`verse_cite_margin_top`; `block_margin_bottom` by default) and alignment
(`quote_cite_text_align: right`).

### Hyphenation

Justified text is hyphenated in the document's language (`lang`, else
US English), with the hyph-utf8 patterns for 72 languages
(`vendor/hyph-utf8`). Code spans and bare links are left whole.

| Setting | What it does |
| --- | --- |
| `:hyphens!:` | Turns hyphenation off. |
| `:hyphens:` (or theme `base_hyphens: true`) | Hyphenates all text, not only justified text, in the document's language. |
| `:hyphens: de` (or `base_hyphens: de`) | Hyphenates all text in that language. A language without patterns is reported. |

### Fonts

| Key | Default | What it does |
| --- | --- | --- |
| `base_font_ligatures` | `normal` | `none` sets text without the font's standard ligatures (fi, fl...). Fixed-pitch fonts are never ligated. |
| `base_emphasis_inversion` | `true` | Emphasis inside italic text is upright (and emphasis inside that, italic again). `false` sets all emphasis in italic. |
| `base_font_variant_numeric` | none | `oldstyle-nums` sets numbers in old-style figures (`onum`), when the font has them; also `lining-nums`, `tabular-nums`, `proportional-nums`. |
| `role_<role>_font_variant` | none | `small-caps` sets text with the role (`[.sc]#Text#`) in small capitals (`smcp`), or in smaller capitals when the font has none. `role_<role>_font_variant_numeric` takes the numeric values above. |

Text is kerned by the font's OpenType (GPOS) pairs. A style the font
catalog lacks for a family (a display face with no italic) is made from
one it has: an italic slanted, a bold stroked (asciidoctor-pdf stops with
an error).

### Footnotes

Footnotes are at the bottom of the page their reference is on, under a
short rule, numbered from 1 in each chapter (or page, or through the
document); one that doesn't fit goes on at the bottom of the next page.

| Setting | Default | What it does |
| --- | --- | --- |
| `footnotes_placement` (theme) | `page` | `end` sets them at the end of each chapter (or of the document), as asciidoctor-pdf does. |
| `footnotes_numbering` (theme) | `chapter` | From 1 in each `chapter` (asciidoctor-pdf's), on each `page` (footnotes at the bottom of the page: references and notes numbered where they land), or through the whole `document`. |
| `footnotes_separator_width`, `_color`, `_length` (theme) | `0.5`, the base border color, `33.33%` | The rule above them. |
| `footnotes_margin_top` (theme) | the font size | The space between the text and the rule. |
| `:show-link-uri: footnote` | | A link's URI in a footnote (print books), not after the link text in brackets (`show-link-uri` set, or print media). A bare link shows its URI already. |

### Listings

| Key | Default | What it does |
| --- | --- | --- |
| `code_orphans` | `2` | The fewest lines of a listing left at the bottom of a page. |
| `code_widows` | `2` | The fewest lines of a listing carried to the top of the next page. |
| `code_wrap_indent` | `1em` | How far past its own indentation a code line that is too long goes on, on the next line. |
| `code_wrap_marker` | arrow | `none` leaves out the return arrow drawn past the end of a line that wraps. |

With `source-highlighter=highlight.js`, source blocks are highlighted by
hilite (the highlighter the HTML backends use) and their tokens set in the
colors, weights and styles of the highlight.js theme `highlightjs-theme`
names (`github` by default; any of highlight.js 11.12.0's themes). The
block's background stays the PDF theme's.

A caption stays with the block it is above. Callout markers aren't part
of the text when code is copied, and link to their callout list item,
which links back.

### Images

| Key | Default | What it does |
| --- | --- | --- |
| `image_placement` | `here` | An image (with its caption) floats, as figures do in books: when it doesn't fit the rest of the page, to the top of the next page, the text after it filling the room; when it fits, to the top (`top`) or the bottom (`bottom`) of its page, or the nearer of the two (`auto`), the text flowing around it, or it stays (`next`). Never past a heading or a page break; an image in a list, table, sidebar or other block stays there. |

### Tables

| Key | What it does |
| --- | --- |
| `table_role_<role>_<key>` | For a table with the role (`[.wide]`), replaces `table_<key>`: every table with the role is styled once, in the theme. |
| `table_cell_role_<role>_background_color`, `_font_color`, `_font_style`, `_font_size`, `_font_family`, `_text_align` | Style a cell whose whole text is a phrase with the role (`\|[.paid]#Paid#`). |

AsciiDoc has no syntax for a cell's role, so a cell takes the role of its
text. In HTML, the same cells can be styled with CSS:
`td:has(> p > span.paid:only-child) { background: #dfd; }`.

### Index

| Key | Default | What it does |
| --- | --- | --- |
| `index_pagenum_text_align` | `left` | `right` sets each entry's page numbers in a column at the right, in tabular figures, as books do; `left` follows the term with them. |
| `index_category_headings` | `true` | `false` leaves out the letter heading above each group of terms. |
| `index_font_family`, `_font_size`, `_font_color`, `_font_style` | the base font | The index's font. |

Each page is listed once (`hypermedia, 13, 20`); the
`index-pagenum-sequence-style` attribute chooses otherwise as in
asciidoctor-pdf (`range` joins consecutive pages, `term` lists a page for
each use, which is asciidoctor-pdf's default).

### Pages

| Key | Default | What it does |
| --- | --- | --- |
| `running_content_on_blank_pages` | `false` | A blank page (the verso before a chapter that starts on a recto page) has no header or footer unless this is `true`. |
| `running_content_on_openers` | `false` | A page that opens a part or chapter has no header or footer unless this is `true`. |
| `header_title_style`, `footer_title_style` | `document` | As in asciidoctor-pdf (`document`, `toc`, `basic`), and `numeral`: a numbered part or chapter as its numeral and its title (`I Hypermedia Concepts`, `3. A Web 1.0 Application`), an unnumbered one as its title. |

A part or chapter with the `noheader` or `nofooter` option (as
asciidoctor-pdf reads them on the `toc` macro) has no header or footer on
its pages: `[colophon%notitle%noheader%nofooter]` for a copyright page.

### Headings

| Key | Default | What it does |
| --- | --- | --- |
| `heading_h1_label_display`, `heading_h2_label_display` | `inline` | `block` sets a part's or chapter's label ("Part I", "Chapter 1") on a line of its own above its title, without the period. |
| `heading_h1_label_font_color`, `_font_size`, `_font_family`, `_font_style` (and `h2`) | the heading's | The label's font. |

A section with a role the theme styles is set in a box, as a sidebar is:
`section_role_<role>_background_color`, `_border_color`, `_border_width`
(one width, or one per side), `_border_radius`, `_padding`, `_margin_top`,
`_font_family`, `_font_size`, `_font_color` and `_font_style`, and its
heading's `_heading_font_family`, `_heading_font_size`,
`_heading_font_color`, `_heading_font_style`, `_heading_margin_top` and
`_heading_margin_bottom` (`[.html-note]` and
`section: { role: { html-note: { background-color: F5F5FF } } }`). It
stays a section: it is numbered, and listed in the contents.

A part on a page of its own is asciidoctor-pdf's
`heading_part_break_after: always`; a title lower on its page,
`heading_h2_padding: [3in, 0, 0, 0]`.

A column too narrow for even one character keeps its text (set past its
edge, with a warning), where the gem leaves the table out.

### Print

| Setting | What it does |
| --- | --- |
| `page_bleed` (theme) | How far backgrounds run past the page for trimming (`0.125in`): the page is the `TrimBox`, the sheet (`MediaBox`, `BleedBox`) grows by the bleed on every side. |
| `-a pdf-standard=PDF/X-4` | Writes PDF/X-4: PDF 1.6, an output intent, `Trapped`, the PDF/X identification in the information and XMP, a `TrimBox` on every page. |
| `-a pdf-output-intent=FILE` | The ICC profile of the printing condition (the printer gives it); PDF/X-4 needs one. |
| `-a pdf-output-condition=NAME` | The printing condition's identifier (`Custom` by default). |
| `-a pdf-layout-report=FILE` | Writes, next to the PDF, each block that breaks across pages, with its source line and pages (`book.adoc: line 66: listing on pages 2-3`), for proofreading. |

Preflight messages report what keeps a PDF/X-4 from conforming: a font
that isn't embedded (a built-in PDF font in the theme), a profile that
isn't an output profile, and content in RGB with a CMYK printing
condition (asciidart's colors are RGB: use an RGB output profile, or
convert the PDF to the printer's CMYK).

### Messages

Layout warnings name the file and line of the block they are about
(`doc.adoc: line 6: table column 1 is too narrow for its text`): `-b pdf`
keeps every block's source location. `--progress` reports each phase of
a conversion as it finishes, and `-v` how many pages were laid out.
