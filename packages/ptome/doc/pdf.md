# PDF output

`ptome -b pdf` writes a PDF with Ptome's own PDF library, plain_pdf,
and reads asciidoctor-pdf's YAML themes unchanged (`pdf-theme`,
`pdf-themesdir`, `pdf-fontsdir`). It needs an output file, and sets text
in the fonts installed on the machine (`ptome doctor` installs the
built-in themes'; see [Fonts](#fonts)). The API makes PDFs too, on the Dart
VM, on Node.js and in a browser (see `doc/api.md`).

It lays documents out with Ptome's own typesetting, described below.
With `asciidoctor-compat` (or `-a pdf-compat`), its settings default to
asciidoctor-pdf's look instead (next section; ADR-0015).

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
| `block_split_end` | `region` | `content` |
| `code_highlight` | `none` | `colors` |
| `code_wrap_indent` | `0` | `1em` |
| `code_wrap_marker` | `none` | `arrow` |
| `footnotes_placement` | `end` | `page` |
| `toc_macro_in_section` | `false` | `true` |
| `running_content_on_openers` | `true` | `false` |
| `base_glyph_widths` | `thousandths` | `exact` |
| `base_kerning_source` | `kern_table` | `font` |
| `url_breaks` | `delimiters` | `chicago` |
| `base_slash_breaks` | `false` | `true` |
| `base_space_breaks` | `all` | `unicode` |
| `base_border_offset_fit` | `false` | `true` |
| `base_hyphen_breaks` | `around` | `after` |
| `index_terms_paragraph` | `line` | `none` |
| `svg_placement` | `page_origin` | `exact` |
| `table_borders` | `with-cells` | `above` |
| `stem_math` | `source` | `typeset` |

## The modern engine

Its default theme is Ptome's house theme (`ptome`, `doc/style.md`):
asciidoctor-pdf's default with a shorter measure, more open lines,
headings in the sans, code in a tint and tables with rows only.
`-a pdf-theme=default` is asciidoctor-pdf's theme; a theme of your own
`extends: ptome` or `extends: default`.

Every setting has a default. Each one is a key of the theme (as written
in the YAML, `prose_orphans` is `prose: { orphans: 2 }`) or an attribute
of the document. A key that takes one of a set of values
(`image_placement`, `base_line_breaking`...) reports a value it doesn't know, once,
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
| `base_glyph_widths` | `exact` | How wide a glyph is: `exact`, its advance in the font; `thousandths`, its advance in whole 1000ths of the em, truncated, both where lines are measured and in the widths the PDF gives viewers. |
| `base_kerning_source` | `font` | Which pairs kern text: `font`, the font's GPOS pair adjustments (its `kern` feature), else its `kern` table; `kern_table`, the first subtable of its `kern` table alone, as early font engines read it. |
| `base_line_breaking` | `auto` | How lines break: `auto` breaks justified and left-aligned text where the lines' demerits are least (Knuth and Plass's total fit with TeX's costs: even spacing, few hyphens, never two hyphens in a row if it can help it; ragged lines with even ends, as plain TeX's `\raggedright`) and centered or right-aligned text one line at a time; `optimal` optimizes any text; `greedy` fills one line at a time. A style change inside a word is never a break. |
| `base_leading` | none | Lines measured from cap height to baseline: each line's box runs from its tallest cap height to its baseline, with this space between boxes (`0.6em`, or points); a text's first line has its cap height at the top and its last line ends at its baseline, so the margins between blocks are the visible space between their text (CSS's `text-box-trim` and `text-box-edge: cap alphabetic`). In place of `base_line_height`; a category's own (`title_page_title_leading`, `code_leading`...) for its text. |
| `base_overhang` | `0` | How far a justified line's last character hangs into the margin, so the edge looks straight (margin kerning, Hàn Thế Thành's character protrusion): the line stretches into a part of the character's width, as LaTeX's microtype package's default protrusion has it (0.7 of a period; 0.5 of a comma, colon or hyphen; 0.3 of a semicolon; 0.2 of an en dash, 0.15 of an em dash; a little of some letters), times this amount. `1` (or `true`) hangs them that far, `0.5` half as far, `0` (or `false`) not at all. |
| `base_typographic_scripts` | `false` | Superscripts and subscripts (footnote references) in the font's own glyphs for them (its `sups` and `subs` features) at the text's size, when it has them for every character (true superior and inferior figures); else smaller and raised as usual. |
| `base_justify_width` | room | `widest`: justified lines are set to the width of the paragraph's widest line (an overfull line shrunk to the room), as a paragraph in a block sized to its content is (CSS's `width: fit-content`); in a quote or a section role: `quote_base_justify_width`, `section_role_<role>_base_justify_width`. |
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
(the plain_hyphenation package). Code spans and bare links are left whole.

| Setting | What it does |
| --- | --- |
| `:hyphens!:` (or theme `base_hyphens: false`) | Turns hyphenation off, of justified text too. |
| `:hyphens:` (or theme `base_hyphens: true`) | Hyphenates all text, not only justified text, in the document's language. |
| `:hyphens: de` (or `base_hyphens: de`) | Hyphenates all text in that language. A language without patterns is reported. |

### Fonts

Ptome compiles no fonts in: a theme names the fonts it wants, and they
come from the machine. A `font_catalog` file is looked up in
`pdf-fontsdir` (by default the theme's folder), then among the installed
fonts, those of the folders in `PTOME_FONT_PATH` (separated as `PATH`
is) and then this user's and the system's font folders: by the file's
name, then by the family and style its catalog entry gives. `GEM_FONTS_DIR`
names the built-in themes' fonts wherever they are installed, M PLUS 1
Code and M PLUS 1p (their successors on Google Fonts) stand in for
asciidoctor-pdf's M+ 1mn and M+ 1p, and a `font_family` that isn't in the
catalog names any installed family (`base_font_family: Inter`).

WOFF and WOFF2 fonts are found like TrueType and OpenType ones (and
embedded as the fonts they wrap). Through the API, fonts can also be given
as bytes, and in a browser the page's web fonts are used too (see
`doc/api.md`).

A font that isn't installed is replaced by a built-in PDF font (Courier
for a monospace family, Times for a serif one, else Helvetica), with one
warning; an icon set whose font is missing shows its icons as text, and
math with no math font installed is shown as its source.

`ptome doctor` lists the fonts of the built-in themes (Noto Serif,
Noto Sans, M+ 1mn, the M+ 1p and Noto Emoji fallbacks, Noto Sans Math and
the Font Awesome, Foundation and Payment icon fonts), where they are
found, and offers to download the missing ones from their official
sources into this user's font folder (`--yes` without asking, `--check`
to only check).

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

Side notes: a phrase whose role the theme sets beside the text
(`role_<role>_display: side`) leaves its line and is set level with it in
a side column, in the role's style, each under the one before it where they
crowd, above the page's footnotes; what doesn't fit goes on at the top of
the next page's column. A reference Bible's cross-references,
`[.xref]##*34:6* ^a^{nbsp}<<v-psa-86-15,Ps 86:15>>##` after a verse
number, fill its center column this way.

| Key | Default | What it does |
| --- | --- | --- |
| `role_<role>_display` | | `side`: phrases with the role are side notes. Their text is aligned by `role_<role>_text_align` (`left`). |
| `side_notes_column` | `center` in columns, else `outside` | `center`: the gap between the middle columns (make `page_column_gap` wide enough); `outside`: the outer margin (the right one, or on a verso page of a `prepress` book the left one). |
| `side_notes_padding` | `0.5em` | The space kept on each side of the column. |
| `side_notes_item_spacing` | `0.25em` | The space between two notes. |

### Listings

| Key | Default | What it does |
| --- | --- | --- |
| `code_orphans` | `2` | The fewest lines of a listing left at the bottom of a page. |
| `code_widows` | `2` | The fewest lines of a listing carried to the top of the next page. |
| `block_split_end` | `content` | Where the piece of a framed block (code, sidebar, example, admonition...) that a page's end cuts off ends: `content`, under its last line; `region`, at the page's bottom margin, its background and border with it. |
| `url_breaks` | `chicago` | Where a link's URL may break across lines: `chicago`, at The Chicago Manual of Style's points (before a slash, a period, a hyphen..., after `://`), `www.` links too; `delimiters`, after `/`, `?`, `&` and `#` only, never leaving a single character, links with a scheme only. |
| `index_terms_paragraph` | `none` | A paragraph of hidden index terms alone (`(((term)))` on a line of its own): `none`, it takes no room (its anchors go with the block after it); `line`, it is an empty line, as any paragraph. |
| `base_hyphen_breaks` | `after` | Where a word with hyphens in it may break: `after`, after a hyphen (as the Unicode line breaking algorithm has it); `around`, before a hyphen too (`--kef` / `-mnuthn`). |
| `base_border_offset_fit` | `true` | Whether the room around a highlighted or boxed word (its `border_offset`) counts when a line is fit; with `false` the line is fit without it and set a little tighter. |
| `base_space_breaks` | `unicode` | Where a space breaks a line: `unicode`, as the Unicode line breaking algorithm has it (not before closing punctuation, a colon, a slash..., nor after an opening bracket, spaces between or not); `all`, at every space. |
| `base_slash_breaks` | `true` | Whether a line may break after a slash in prose (`and/or`), as the Unicode line breaking algorithm allows. |
| `svg_placement` | `exact` | Where an SVG image is placed when it's scaled: `exact`, at its box; `page_origin`, as one drawn at its own size and scaled about the page's origin, with the scale and the translation each to five decimals (a hundred-thousandth of a point or so off). |
| `code_highlight` | `colors` | With `source-highlighter=highlight.js`: `colors`, the tokens colored as the `highlightjs-theme` colors them; `none`, the code as plain text. |
| `code_wrap_indent` | `1em` | How far past its own indentation a code line that is too long goes on, on the next line. |
| `code_wrap_marker` | arrow | `none` leaves out the return arrow drawn past the end of a line that wraps. |
| `code_role_<role>_<key>` | none | For a code block with the role (`[source.bare]`), replaces `code_<key>` (`code_role_bare_padding: 0`); its margins come from `role_<role>_margin_top` and `_bottom`. |

With `code_wrap_indent: 0` and `code_wrap_marker: none`, a long code line wraps as prose does: at the line breaking algorithm's opportunities (spaces, after a slash), as many words on a line as fit, the next line at the left.

With `source-highlighter=highlight.js`, source blocks are highlighted by
plain_highlighting (the highlighter the HTML backends use) and their tokens set in the
colors, weights and styles of the highlight.js theme `highlightjs-theme`
names (`github` by default; any of highlight.js 11.12.0's themes). The
block's background stays the PDF theme's.

A caption stays with the block it is above. Callout markers aren't part
of the text when code is copied, and link to their callout list item,
which links back. They may be text rather than circled numbers:
`conum_glyphs: '[{{number}}]'` (a template), in `conum_font_style` and
`conum_font_variant_numeric` (`oldstyle-nums`), and a callout list's
markers their own (`callout_list_marker_content: '{{number}}.'`).

### Math

AsciiMath (`stem:[]`, `asciimath:[]`, `[stem]` blocks with `:stem:` or
`:stem: asciimath`) is typeset: converted to MathML (the same as the
DocBook and EPUB backends', ADR-0014), then laid out by plain_pdf's math
layout in a font with an OpenType `MATH` table, by its rules (scripts,
fractions, radicals, limits, accents, delimiters that grow with what they
enclose, larger operators in display style). Inline formulas stand on the
baseline at the text's size, in its color; a block is in display style.
Copied, a formula gives its source.

LaTeX math (`latexmath:[]`, `:stem: latexmath`) is typeset the same way,
converted to MathML by ptome: math mode as documents use it (KaTeX's
and MathJax's common commands: `\frac`, `\sqrt[n]`, `\left`...`\right`,
scripts and limits, Greek and symbols, function names and
`\operatorname`, accents and braces, `\text` and the `\math...`
alphabets, `\color`, `\boxed`, spaces, the `matrix` environments,
`cases`, `array`, `aligned`). A command it doesn't know is shown as
written, and reported. Parentheses written plainly keep their size, as in
TeX; `\left` and `\right` grow them.

| Key | Default | What it does |
| --- | --- | --- |
| `math_font_family` | Noto Sans Math (bundled) | The font formulas are set in: a family of the font catalog whose font has a `MATH` table (STIX Two Math, Libertinus Math, New Computer Modern Math...). A character it lacks comes from the base font. |
| `stem_font_size`, `stem_font_color` | the base font's | A STEM block's size and color. |
| `stem_text_align` | `center` | Where a STEM block's formula goes: `left`, `center`, `right`. A formula wider than the room is scaled down to fit it. |

### Images

| Key | Default | What it does |
| --- | --- | --- |
| `image_placement` | `here` | An image (with its caption) floats, as figures do in books: when it doesn't fit the rest of the page, to the top of the next page, the text after it filling the room; when it fits, to the top (`top`) or the bottom (`bottom`) of its page, or the nearer of the two (`auto`), the text flowing around it, or it stays (`next`). Never past a heading or a page break; an image in a list, table, sidebar or other block stays there. An image's own `placement` attribute chooses for it (`image::x.png[placement=bottom]`; `none` keeps it in the flow). |
| `image_scope`, `image_role_<role>_scope` | `column` | `page`: in columns, an image (with its caption) spans them, floating across the top or the bottom of its page (the nearer, or as its placement says): a map in a two-column book. An image's own `scope` attribute chooses for it (`page` or `parent`). |
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
| `stem_math` | `typeset` | How math (`stem`, `latexmath`, `asciimath`) is set: `typeset`, as a formula; `source`, its source, in a code block or as code inline (as asciidoctor-pdf sets it without a math renderer). |
| `table_borders` | `above` | When a table's cell borders are painted: `above`, after every cell's content, so nothing covers them; `with-cells`, each cell's before its content. |
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
| `running_content_marks` | | A prefix of anchor ids (`v-`): those anchors are the pages' marks, and running content may refer to `{page-first-mark}` and `{page-last-mark}`, the reference text of the first and last on the page (a page without one has the last one before it): a Bible's running head, `EXODUS 33:14`, from `[[v-exo-33-14,Exodus 33:14]]`. |
| `running_content_units` | | A level of a document in units (`verse`, or `bible.verse`; see `doc/units.md`): running content may refer to `{page-first-unit}` and `{page-last-unit}`, the first and last unit of that level on the page as its scheme cites them, and `{page-units}`, the range they make, what its ends share said once (`Gen 2:20–3:7`; `{page-units-long}`: `Genesis 2:20–3:7`). A page without one has the last one before it. |

Running content may be a template: `'{{#chapter-numeral}}{{chapter-numeral}}. {{/chapter-numeral}}{{chapter-title}} · {page-number}'`
writes `3. A Web 1.0 Application · 71`, and on an unnumbered chapter's
pages `Introduction · 15` (the numeral part left out, where a line that
refers to a missing `{attribute}` is dropped). `{{top-title}}` and
`{{top-numeral}}` are the last part or chapter that started before the
page (on a page where a chapter starts, the one before it), else the
document's title: a head that names what the page continues (TeX's
`\topmark`). With `title_style: basic`,
the titles come without their numbers.

A part or chapter with the `noheader` or `nofooter` option (as
asciidoctor-pdf reads them on the `toc` macro) has no header or footer on
its pages: `[colophon%notitle%noheader%nofooter]` for a copyright page.

`page_columns` (with `page_column_gap`) sets an article's body in columns,
as asciidoctor-pdf does, and a book's too: each chapter's heading across
the page, its content in the columns under it, which are balanced where
the chapter ends, so that the next chapter starts under its shorter
column (with `heading_chapter_break_before: auto`). The asciidoctor-pdf
compatibility setting keeps a book in one column, as the gem does.

### Sidebars, callouts and banners

A block whose role the theme floats goes to the left or the right of the
page, the blocks after it beside it: each one beside it whole, narrowed, or,
where it doesn't fit beside it, below it at full width (a section's blocks
each so). Where the floating block doesn't fit on its page, the rest goes on
at the top of the next one, before anything else there, what is set there
going around it too: a report's sidebar that runs from one page into the
next, through the banner at the top of the second. A page break waits for
it, and the repeated headings of its section (`heading_h<n>_repeat`) are set
beside it.

| Key | Default | What it does |
| --- | --- | --- |
| `role_<role>_float` | | `left` or `right`: blocks with the role (an open block, a sidebar, an image) float to that side. |
| `role_<role>_float_width` | a third of the text's width | Its width: a length or a percentage of the page's text width. |
| `role_<role>_float_gap` | the font size | The space between it and the blocks beside it. |
| `example_role_<role>_<key>`, `sidebar_role_<role>_<key>` | | For an example block or a sidebar with the role (`[.callout]`), replaces `example_<key>` or `sidebar_<key>`; `_link_font_color` and `_link_text_decoration` style the links in it (a pill-shaped link). |
| `<category>_shadow_color` | | A shadow under a framed block (`example`, `sidebar`, their roles' keys): `_shadow_offset` (right and down, `[0, 2]`), `_shadow_blur` (`4`), `_shadow_opacity` (`0.3`). |
| `<category>_background_image` | | An image over a framed block's background, clipped to it: `image:stripes.svg[fit=contain,position=right top]`, as `page_background_image`. |
| `sidebar_title_rule_width` | | A rule under a sidebar's title, as `heading_h<n>_rule_*`. |

`test/pdf/fixtures/report` lays out a personal report with them: banners
over each page of a category, a gauge floated beside the first paragraph, a
callout with a shadow and stripes, and a gray sidebar of two boxes that goes
on at the top of the next page.

### Headings

| Key | Default | What it does |
| --- | --- | --- |
| `heading_h<n>_content` | the numbered title | A template for the heading's text, with `{{title}}`, `{{numbered-title}}`, `{{number}}` (`1.2.`, a part's `I`), `{{numeral}}` (`1`, `I`) and `{{signifier}}` (`Chapter`, `Part`). A chapter's label on a line of its own, in gray: `"{{#numeral}}<font color=\"#8C8C8C\">{{signifier}} {{numeral}}</font>\n{{/numeral}}{{title}}"` (markup attributes in double quotes). |
| `heading_float_barrier` | `true` | A heading starts after the floating images waiting for the next page; `false` lets it pass them. |
| `heading_min_height_after` | asciidoctor-pdf's | `auto`: a heading moves to the next page unless the block after it can start under it (as much of it as may start a page: a paragraph's first `prose_orphans` lines): a sticky heading; a length works as in asciidoctor-pdf. |
| `heading_h<n>_leading` | the base leading | Under `base_leading`, the space between the heading's lines (a part's title: `5`). |
| `heading_h<n>_vertical_align` | `top` | `middle` or `bottom`: a heading that starts its page (a part's title page) in the middle or at the bottom of it. |
| `heading_h<n>_background_color` | | A fill behind the heading and its padding, rounded by `heading_h<n>_border_radius`: a banner. |
| `heading_h<n>_margin_left`, `_margin_right` | `0` | The heading's side margins; negative ones reach out past the text's edges. Beside a block floating to a side, a heading reaches no nearer it than the float's gap. |
| `heading_h<n>_repeat` | `false` | `true`: the heading is set again at the top of each page its section goes on to (a report's category banner and subject, under one another), and on the page a sidebar of the section goes on to. |
| `heading_h<n>_rule_width` | | A rule under the heading, as a box of its own (beside a block floating to a side, the heading may be set beside it and the rule under it): `_rule_color`, `_rule_margin_top`, `_rule_margin_bottom`; `_rule_dash`, lengths of dashes and gaps in turn, and `_rule_cap` (`round` or `square`) for a rule of rounded bars. |
| `heading_h<n>_drop_lines` | | `2` or more: the heading set as a drop beside that many first lines of the section's first paragraph (a Bible's chapter number, an initial), its capitals from the first line's to the last line's baseline, the heading itself left out (its anchor and running content stay). `_drop_content` is a template for its text (`{{numeral}}` by default; `{{title}}`, and the section's attributes as `{{attr-<name>}}`: `[number=34]` gives `{{attr-number}}`); `_drop_font_family`, `_font_style`, `_font_color`; `_drop_gap` (`0.3em`) after it; `_drop_skip_roles` the roles of paragraphs it passes (a psalm's title). |

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
condition (Ptome's colors are RGB: use an RGB output profile, or
convert the PDF to the printer's CMYK).

### Cores

The work that doesn't depend on the order of the pages runs on the
machine's other cores while the document is walked and laid out: PNG
images with transparency (or interlaced) are encoded again, and the
pages' content streams compressed. Object numbers, page numbers and the
order of everything in the file are decided on the main isolate, so the
PDF is the same, byte for byte, with any number of workers (ADR-0016;
`tool/jobs_check.dart` checks it on the PDF fixtures, the gem's examples
and a book).

| Setting | What it does |
| --- | --- |
| `-a jobs=N` | Uses N workers; `1` for none. By default, one for each physical core. |

The command line and the asynchronous API (`convertFileAsync`,
`convertToTargetAsync`) use them; the synchronous API converts on one
core, as do the files of a `-j` batch (each on a core of its own) and
JavaScript. An EPUB compresses its files on the workers the same way.

### Messages

Layout warnings name the file and line of the block they are about
(`doc.adoc: line 6: table column 1 is too narrow for its text`): `-b pdf`
keeps every block's source location. `--progress` reports each phase of
a conversion as it finishes, and `-v` how many pages were laid out.
