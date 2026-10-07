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

## asciidoctor-pdf's look

With `asciidoctor-compat` naming the PDF (ADR-0015; `doc/books.md`), a
document without a theme of its own gets asciidoctor-pdf's (`default`),
and these keys default as asciidoctor-pdf sets pages, unless the theme
sets them. On asciidoctor-pdf's own test documents, the pages look the
same (`benchmark/PARITY.md`).

| Key | With `asciidoctor-compat` | Otherwise |
| --- | --- | --- |
| `block_margin_collapse` | `false`: spaces add | `true` |
| `base_line_breaking` | `greedy` | `auto` |
| `base_hyphens` | `false` (unless `:hyphens:`) | justified text hyphenated |
| `prose_orphans`, `prose_widows`, `code_orphans`, `code_widows` | `1` | `2` |
| `footnotes_placement` | `end` | `page` |
| `toc_macro_in_section` | `false` | `true` |
| `running_content_on_openers` | `true` | `false` |

## The modern engine

Its default theme is asciidart's house theme (`asciidart`, `doc/style.md`):
asciidoctor-pdf's default with a shorter measure, more open lines,
headings in the sans, code in a tint and tables with rows only.
`-a pdf-theme=default` is asciidoctor-pdf's theme; a theme of your own
`extends: asciidart` or `extends: default`.

Every setting has a default. Each one is a key of the theme (as written
in the YAML, `prose_orphans` is `prose: { orphans: 2 }`) or an attribute
of the document. `doc/typst-look.md` lists the keys that set a book as
Typst sets it, with the values that do. A key that takes one of a set of values
(`image_placement`, `index_sort`...) reports a value it doesn't know, once,
and is read as unset.

Text the engine generates (a heading's label, a running head, a contents
entry, a callout marker) comes from templates where a book may want it
otherwise: Mustache templates (ADR-0010), `{{name}}` for a value and
`{{#name}}...{{/name}}` for a part written only when the value is set. A
template may hold the text markup (`<font>`, `<strong>`, `<sup>`); a
newline is `\n` in a double-quoted YAML string. `<font width="0.3em">&nbsp;</font>`
sets a space of that width (a length, `em` of the text's size), which the
line breaker never stretches: a fixed gap between a heading's number and
its title.

### Paragraphs

| Key | Default | What it does |
| --- | --- | --- |
| `base_line_breaking` | `auto` | How lines break: `auto` breaks justified text where the lines' costs are least (even spacing, few hyphens, no lone word on the last line: Knuth and Plass's method, with Typst's costs) and other text one line at a time; `optimal` optimizes any text (ragged lines balanced); `greedy` fills one line at a time. A style change inside a word is never a break. |
| `base_leading` | none | Lines measured from cap height to baseline: each line's box runs from its tallest cap height to its baseline, with this space between boxes (`0.6em`, or points); a text's first line has its cap height at the top and its last line ends at its baseline, so the margins between blocks are the visible space between their text (Typst's model; CSS's `text-box-trim`). In place of `base_line_height`; a category's own (`title_page_title_leading`, `code_leading`...) for its text. |
| `base_overhang` | `0` | How far punctuation and dashes at the end of a justified line hang into the margin, so the edge looks straight: the line stretches into a part of the character's width (0.55 of a hyphen, 0.8 of a period or comma, 0.3 of a colon, 0.2 of a dash), times this amount. `1` (or `true`) hangs them that far, as Typst's `overhang` and microtype's protrusion; `0.5` half as far; `0` (or `false`) not at all. |
| `base_typographic_scripts` | `false` | Superscripts and subscripts (footnote references) in the font's own glyphs for them (its `sups` and `subs` features) at the text's size, when it has them for every character, as Typst's `super` and `sub`; else smaller and raised as usual. |
| `base_justify_width` | room | `widest`: justified lines are set to the width of the paragraph's widest line (an overfull line shrunk to the room), as a paragraph in a block sized to its content is (CSS's `width: fit-content`, Typst's content-sized blocks); in a quote or a section role: `quote_base_justify_width`, `section_role_<role>_base_justify_width`. |
| `base_text_align_last` | `left` | Where a justified paragraph's last line goes (`center`, `right`), as CSS's `text-align-last` (`table_base_text_align_last: center`: table cells justified, their last lines centered). |
| `prose_orphans` | `2` | The fewest lines of a paragraph left at the bottom of a page. |
| `prose_widows` | `2` | The fewest lines of a paragraph carried to the top of the next page. |
| `prose_text_indent` | `0` | The indent of every paragraph's first line. Numbers are points; `1.5em` is relative to the paragraph's font size, `2rem` to the base font size. |
| `prose_text_indent_inner` | `0` | The indent of the first line of a paragraph that follows another paragraph only (not the first after a heading, a list or a block), as books set it. |
| `prose_margin_inner` | none | The space between two paragraphs; `0` with `prose_text_indent_inner` for indented, unspaced paragraphs. |
| `role_<role>_text_indent`, `role_<role>_margin_bottom` | the prose's | A paragraph with the role: its first line's indent (`0` for none) and the space below it (`[.dedication]` paragraphs, unindented and spaced). |
| `role_<role>_margin_top`, `role_<role>_margin_bottom` | the block's | Any block with the role: the space above and below it, in place of its category's. |

### Space around blocks

Each kind of block has its own space above and below:
`<category>_margin_top` and `<category>_margin_bottom`, for the
categories `prose` (paragraphs), `code` (listing and literal blocks),
`image`, `media`, `table`, `quote`, `verse`, `sidebar`, `example`,
`admonition`, `list`, `description_list`, `callout_list`, `open`,
`thematic_break`, `pass` and `stem`. Below a block, the space is its own
or `block_margin_bottom` (asciidoctor-pdf's one setting for all blocks),
and at least the space the next block wants above it: adjacent margins
collapse to the larger, as in CSS, also with the space above the next
section's heading. Above the first block after a heading, what the
heading's margin below leaves; none at the start of another container,
or at the top of a page. `block_margin_collapse: false` adds them
instead, as asciidoctor-pdf does: a block's space below, then the next
heading's space above, and no `<category>_margin_top`. A block that ends with a page break ends there:
none of its space below goes to the next page.

A quote's attribution has its own space above (`quote_cite_margin_top`,
`verse_cite_margin_top`; `block_margin_bottom` by default) and alignment
(`quote_cite_text_align: right`). Inside a quote, a sidebar or a
description list, its category's keys stand for the theme's, as a section
role's do (`sidebar_prose_margin_bottom`):
`quote_base_justify_width: widest` (its lines justified to the widest, as
in a block sized to its content),
`quote_list_margin_top` for the lists in a quote. An admonition's keys
stand in the same way (`admonition_prose_margin_bottom`). A sidebar's
title has its own space below (`sidebar_title_margin_bottom`;
`heading_margin_bottom` by default).

A framed block split across pages (a sidebar, an example, a quote, a
section with a styled role) is open where it breaks: its border and
padding at the start of its first piece and the end of its last, as
asciidoctor-pdf does. `<category>_box_decoration_break: clone` gives every
piece its padding and border at both ends instead, as CSS's
`box-decoration-break: clone`.

### Contents, lists, title page

A `toc::[]` macro that opens a section (its first block) is that
section's contents: under its heading, on its page, without a title of
its own, and the section listed in itself: a Contents chapter.
`toc_macro_in_section: false` sets it as asciidoctor-pdf does instead: on
a page of its own after the heading, with its title.

| Key | Default | What it does |
| --- | --- | --- |
| `toc_entry_content` | the numbered title | A template for each contents entry: `'{{title}}'` lists titles without their numbers (also `{{number}}`, `{{numbered-title}}`). |
| `toc_entry_spacing` | the leading under `base_leading`, else none | The space between contents entries. |
| `description_list_term_display` | `block` | `inline` runs a term in before its description, in the term's font, the lines after the first hanging by `description_list_description_indent`. |
| `description_list_term_gap` | an en space | With `inline` terms, the space after the term (a length, `0.6em`). |
| `image_float_clearance` | none | The space between a floating image (`image_placement`) and the text: below it at the top of a page, above it at the bottom (a length, `1.5em`). |
| `olist_text_align` | `list_text_align` | An ordered list's text alignment (`justify` for numbered lists justified while bullet lists stay ragged). |
| `callout_list_text_align` | `list_text_align` | A callout list's text alignment. |
| `olist_body_indent`, `olist_marker_width` | `list_body_indent`, the marker's | An ordered list's space between its numbers and its text, and the boxes its numbers are set in, at their left (`0`, `1em`: the text right after a 1em box), or `auto` for each number's own width. |
| `olist_role_<role>_<key>` | none | For an ordered list with the role (`[.plain]`), replaces `olist_<key>` (`olist_role_plain_marker_width: auto` sets its numbers at their own width). |
| `ulist_marker_nesting` | `all` | `ulist`: a bullet list's marker follows its level among bullet lists alone (a bullet list in a numbered list's item keeps the first marker); `all` counts every enclosing list, as asciidoctor-pdf does. |
| `callout_list_indent`, `callout_list_marker_width`, `callout_list_marker_text_align` | none, the marker's, `center` | A callout list set in, its markers in boxes that wide, aligned so (`12`, `1em`, `left`: callouts set as a numbered list); `callout_list_marker_font_*` (family, size, style, color, `_variant_numeric`) style them. |
| `caption_indent`, `<category>_caption_indent` | none | A caption set in from the left (`code_caption_indent: 12`: over a code block's padded code). |
| `olist_marker_font_variant_numeric` | none | An ordered list's numbers in old-style (`oldstyle-nums`) or other figures (with `olist_marker_font_family`, `_font_color`...). |
| `title_page_authors_delimiter` | `, ` | Its spaces are kept as written: `'    '` sets the authors in a row with a gap (asciidoctor-pdf collapses them to one). |
| `list_body_indent` | none | The marker at `list_indent`, the text this far after the widest marker (else the text at `list_indent`, the marker a space before it, as asciidoctor-pdf). |
| `title_page_title_skew` (also `_subtitle_`, `_authors_`, `_revision_`) | none | Degrees the text leans right, sheared as one block about its last baseline (the upper lines further right), in place of a slanted face. |

### Hyphenation

Justified text is hyphenated in the document's language (`lang`, else
US English), with the hyph-utf8 patterns for 72 languages
(`vendor/hyph-utf8`). Code spans and bare links are left whole.

| Setting | What it does |
| --- | --- |
| `:hyphens!:` (or theme `base_hyphens: false`) | Turns hyphenation off, of justified text too. |
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
| `footnotes_reference_content` (theme) | `[{{number}}]` | A template for a reference, raised in the text; the number links to the note. `'{{number}}'` gives a plain superscript number. Without the key, the document's `footnote-reference-template` (as in HTML and EPUB); likewise `footnote-label-template` for the label. |
| `footnotes_label_content` (theme) | `[{{number}}] ` | A template for the label before a note; the number links back to the reference. |
| `footnotes_margin_top` (theme) | the font size | The space between the text and the rule. |
| `footnotes_indent` (theme) | none | How far each note's first line is set in (a length, `1em` of the notes' size). |
| `footnotes_label_gap` (theme) | none | The space after a note's label (a length). |
| `footnotes_item_spacing` (theme) | none | The space above each note (at least half the notes' size between the rule and the first). Under `base_leading` the rule takes no room. |
| `:show-link-uri: footnote` | | A link's URI in a footnote (print books), not after the link text in brackets (`show-link-uri` set, or print media). A bare link shows its URI already. |

### Listings

| Key | Default | What it does |
| --- | --- | --- |
| `code_orphans` | `2` | The fewest lines of a listing left at the bottom of a page. |
| `code_widows` | `2` | The fewest lines of a listing carried to the top of the next page. |
| `code_wrap_indent` | `1em` | How far past its own indentation a code line that is too long goes on, on the next line. |
| `code_wrap_marker` | arrow | `none` leaves out the return arrow drawn past the end of a line that wraps. |
| `code_role_<role>_<key>` | none | For a code block with the role (`[source.bare]`), replaces `code_<key>` (`code_role_bare_padding: 0`); its margins come from `role_<role>_margin_top` and `_bottom`. |

With `code_wrap_indent: 0` and `code_wrap_marker: none`, a long code line wraps as prose does: at the line breaking algorithm's opportunities (spaces, after a slash), as many words on a line as fit, the next line at the left.

With `source-highlighter=highlight.js`, source blocks are highlighted by
hilite (the highlighter the HTML backends use) and their tokens set in the
colors, weights and styles of the highlight.js theme `highlightjs-theme`
names (`github` by default; any of highlight.js 11.12.0's themes). The
block's background stays the PDF theme's.

A caption stays with the block it is above. Callout markers aren't part
of the text when code is copied, and link to their callout list item,
which links back. They may be text rather than circled numbers:
`conum_glyphs: '[{{number}}]'` (a template), in `conum_font_style` and
`conum_font_variant_numeric` (`oldstyle-nums`), and a callout list's
markers their own (`callout_list_marker_content: '{{number}}.'`).

### Images

| Key | Default | What it does |
| --- | --- | --- |
| `image_placement` | `here` | An image (with its caption) floats, as figures do in books: when it doesn't fit the rest of the page, to the top of the next page, the text after it filling the room; when it fits, to the top (`top`) or the bottom (`bottom`) of its page, or the nearer of the two (`auto`), the text flowing around it, or it stays (`next`). Never past a heading or a page break; an image in a list, table, sidebar or other block stays there. An image's own `placement` attribute chooses for it (`image::x.png[placement=bottom]`; `none` keeps it in the flow). |
| `image_text_font_family`, `_font_size`, `_font_color`, `_leading` | the code font's | The font of a text file shown as an image (below). |

An image whose target is a text file (`image::diagram.txt[]`, ASCII art)
is set as its text: every line as it is, in the code font (or
`image_text_*`), the block as wide as its longest line and aligned,
captioned and floated as an image. A book can show a picture in HTML and
the text in print with an attribute:
`:diagram-ext: svg` and `ifdef::backend-pdf[:diagram-ext: txt]`, then
`image::diagram/http-get.{diagram-ext}[]`.

### Tables

| Key | What it does |
| --- | --- |
| `table_role_<role>_<key>` | For a table with the role (`[.wide]`), replaces `table_<key>`: every table with the role is styled once, in the theme. |
| `table_base_<key>` | In the modern engine, the base keys inside an AsciiDoc cell (`table_base_text_align_last: center`). |
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
| `index_sort` | `letter` | `letter`: the terms under their first letter's heading (`index_category_headings`), each term's subterms under it. `code-point`: every term in one list (as Typst's in-dexter index): each entry is keyed by its term and its parents' terms joined with commas, and the keys are sorted by code point (`HTTP methods` before `HTTP, cookies`). A subterm's entry shows the terms after the first, under a line with the first when the entry before it starts with another term. |
| `index_item_spacing` | `0` | The space after each entry (`code-point` index). |
| `index_subterm_indent` | `0` | How far a subterm's entry is indented (`code-point` index; a length, such as `1em`). |
| `index_hanging_indent` | twice `description_list_description_indent` | How far an entry's wrapped lines are indented (`code-point` index). |

Each page is listed once (`hypermedia, 13, 20`); the
`index-pagenum-sequence-style` attribute chooses otherwise as in
asciidoctor-pdf (`range` joins consecutive pages, `term` lists a page for
each use, which is asciidoctor-pdf's default). With `media` other than
`screen`, consecutive pages are joined, unless the attribute is `page`.

### Pages

| Key | Default | What it does |
| --- | --- | --- |
| `running_content_on_blank_pages` | `false` | A blank page (the verso before a chapter that starts on a recto page) has no header or footer unless this is `true`. |
| `running_content_on_openers` | `false` | A page that opens a part or chapter has no header or footer unless this is `true`. |
| `section_role_<role>_running_content_on_openers` | | `true` keeps the running content on the first page of a part or chapter with that role (a foreword set as an ordinary heading). |
| `header_title_style`, `footer_title_style` | `document` | As in asciidoctor-pdf (`document`, `toc`, `basic`). |

Running content may be a template: `'{{#chapter-numeral}}{{chapter-numeral}}. {{/chapter-numeral}}{{chapter-title}} · {page-number}'`
writes `3. A Web 1.0 Application · 71`, and on an unnumbered chapter's
pages `Introduction · 15` (the numeral part left out, where a line that
refers to a missing `{attribute}` is dropped). `{{top-title}}` and
`{{top-numeral}}` are the last part or chapter that started before the
page (on a page where a chapter starts, the one before it), else the
document's title: a head that names what the page continues (as Typst's
headers do). With `title_style: basic`,
the titles come without their numbers.

A part or chapter with the `noheader` or `nofooter` option (as
asciidoctor-pdf reads them on the `toc` macro) has no header or footer on
its pages: `[colophon%notitle%noheader%nofooter]` for a copyright page.

### Headings

| Key | Default | What it does |
| --- | --- | --- |
| `heading_h<n>_content` | the numbered title | A template for the heading's text, with `{{title}}`, `{{numbered-title}}`, `{{number}}` (`1.2.`, a part's `I`), `{{numeral}}` (`1`, `I`) and `{{signifier}}` (`Chapter`, `Part`). A chapter's label on a line of its own, in gray: `"{{#numeral}}<font color=\"#8C8C8C\">{{signifier}} {{numeral}}</font>\n{{/numeral}}{{title}}"` (markup attributes in double quotes). |
| `heading_float_barrier` | `true` | A heading starts after the floating images waiting for the next page; `false` lets it pass them. |
| `heading_min_height_after` | asciidoctor-pdf's | `auto`: a heading moves to the next page unless the block after it can start under it (as much of it as may start a page: a paragraph's first `prose_orphans` lines): a sticky heading; a length works as in asciidoctor-pdf. |
| `heading_h<n>_leading` | the base leading | Under `base_leading`, the space between the heading's lines (a part's title: `5`). |
| `heading_h<n>_vertical_align` | `top` | `middle` or `bottom`: a heading that starts its page (a part's title page) in the middle or at the bottom of it. |

A section with a role the theme styles is set in a box, as a sidebar is:
`section_role_<role>_background_color`, `_border_color`, `_border_width`
(one width, or one per side), `_border_radius`, `_padding`, `_margin_top`,
`_font_family`, `_font_size`, `_font_color` and `_font_style`, and its
heading's `_heading_font_family`, `_heading_font_size`,
`_heading_font_color`, `_heading_font_style`, `_heading_margin_top` and
`_heading_margin_bottom` (`[.html-note]` and
`section: { role: { html-note: { background-color: F5F5FF } } }`). It
stays a section: it is numbered, and listed in the contents.
`_vertical_align: middle` (or `bottom`) sets a section that starts a page
and fits on it in the middle (at the bottom) of the page: a dedication. Any other key of the theme
under the role's (`section_role_<role>_prose_margin_bottom`) takes the place
of that key (`prose_margin_bottom`) inside the section.

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
| `-a pdf-page-map=FILE` | Writes, next to the PDF, a JSON map of its pages: their labels, and each block's source line with the pages it is on. An EPUB of the same source reads it (`epub-page-map`) to mark the print edition's pages. |

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
