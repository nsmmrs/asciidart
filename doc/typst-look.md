# A Typst-like PDF

The modern engine can set a book the way Typst sets it: the Hypermedia
Systems edition built with asciidart matched its Typst build page by
page, within a tenth of a percent of each page's pixels
(`benchmark/HS.md`). There is no "Typst mode". Each thing Typst does is a
key of the theme with a range of values of its own, and Typst's way is one
value in that range. This page lists them: what Typst does, the value that
does the same, and the values that make sense besides.

asciidart's defaults are not Typst's (ADR-0011). Lengths are points
unless they say `em` (of the element's font size) or `%`.

## Lines and paragraphs

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `base_leading` | `par(leading)`, with lines measured from the cap height to the baseline (`top-edge`, `bottom-edge`) | `0.65em` (the Hypermedia Systems book: `0.6em`) | `0.3em`–`1em`; unset, lines use asciidoctor-pdf's `base_line_height` model |
| `<category>_leading` | a `par(leading)` set for one element | as `base_leading` | as `base_leading` |
| `base_line_breaking` | `par(linebreaks)` | `auto` | `auto`, `optimal`, `greedy` |
| `base_overhang` | `text(overhang)` | `true` | `true`, `false` |
| `base_typographic_scripts` | `super(typographic: true)`, `sub(...)` | `true` | `true`, `false` |
| `base_justify_width` | a paragraph in a block sized to its content | `widest` (in quotes, terms, sidebars) | `room` (default), `widest` |
| `base_text_align_last` | the alignment of a justified paragraph | `center` (Typst's centered table cells) | `left`, `center`, `right` |
| `prose_margin_bottom` | `par(spacing)` | `1.2em` (the book: its leading) | `0`–`2em` |
| `prose_text_indent_inner` | `par(first-line-indent)` (after a paragraph only) | `1em` | `0`–`3em` |
| `prose_orphans`, `prose_widows` | its widow and orphan prevention | `2` | `1`–`4` |
| `:hyphens:` / `base_hyphens` | `text(hyphenate: auto)`: justified text only | (default) | off, justified (default), all, a language |

## Space around blocks

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `<category>_margin_top`, `_margin_bottom` | `block(above, below)` for that element | the element's spacing | any length; adjacent margins collapse to the larger |
| `role_<role>_margin_top`, `_margin_bottom` | a show rule on one kind of block | | any length |
| `<category>_<key>`, for `quote`, `sidebar`, `admonition`, `description_list` | a set rule scoped by a show rule (`show quote: set block(spacing: 1em)`) | | any key of the theme |
| `<category>_box_decoration_break` | a breakable block's inset on each piece | `clone` | `slice` (default), `clone` |
| `quote_cite_margin_top`, `quote_cite_text_align` | the attribution's `v()` and alignment | `0.9em`, `right` | any length; `left`, `center`, `right` |

## Headings

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `heading_h<n>_margin_top`, `_margin_bottom` | the heading's block spacing: `1.44em / scale` above (`1.8em` for level 1), `0.75em / scale` below; the scale 1.4, 1.2, 1 for levels 1, 2, 3+ | computed per level | any length |
| `heading_min_height_after` | sticky headings | `auto` | `auto`, a length (asciidoctor-pdf's), `0` |
| `heading_float_barrier` | headings don't flush waiting figures | `false` | `true` (default), `false` |
| `heading_h<n>_content` | `heading(numbering)` and its show rule | `'{{#number}}{{number}}<font width="0.3em">&nbsp;</font>{{/number}}{{title}}'` | any template |
| `heading_h<n>_leading` | the heading's `par(leading)` | | as `base_leading` |
| `heading_h<n>_vertical_align` | `align(horizon)` on a page of its own | `middle` | `top`, `middle`, `bottom` |
| `title_page_title_skew` (and `_subtitle_`, `_authors_`) | `skew(ax: ...)` | degrees | `-20`–`20` |

## Lists, terms and callouts

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `list_indent`, `list_body_indent` | `list(indent, body-indent)` | `0`, `0.5em` | `0`–`2em` |
| `olist_marker_width` | an enum numbering in `box(width: ...)` | the book: `1em` | a length, `auto` (the number's width) |
| `olist_body_indent` | `enum(body-indent)` | `0.5em` (the book: `0`) | `0`–`2em` |
| `olist_text_align`, `callout_list_text_align` | `enum`'s paragraphs justified | `justify` | any alignment |
| `ulist_marker_nesting` | list markers by list depth alone | `ulist` | `all` (default), `ulist` |
| `olist_role_<role>_<key>` | a set rule for one list | | any `olist_` key |
| `callout_list_indent`, `_marker_width`, `_marker_text_align`, `_marker_content` | callouts as an `enum` | `1em`, `1em`, `left`, `'{{number}}.'` | lengths; alignments; templates |
| `description_list_term_display`, `_term_gap` | `terms(separator: h(0.6em))`, run in | `inline`, `0.6em` | `block` (default), `inline`; `0`–`2em` |
| `description_list_description_indent` | `terms(hanging-indent)` | `2em` (the book: `1em`) | `0`–`3em` |

## Code

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `code_wrap_indent`, `code_wrap_marker` | raw text wraps to the left edge, unmarked | `0`, `none` | `0`–`4em`; `arrow` (default), `none` |
| `code_padding`, `code_caption_indent` | a code figure's inset, its caption over the code | `[0, 1em]`, `1em` | any lengths |
| `codespan_font_size` | `raw` at `0.8em` | `0.8em` | `0.7em`–`1em` |
| `code_role_<role>_<key>` | a set rule for some raw blocks | | any `code_` key |
| `conum_glyphs` | callout markers as text | `'[{{number}}]'` | any template; circled numbers (default) |

## Figures

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `image_placement`, `image::x[placement=...]` | `figure(placement)` | `auto` | `here` (default), `auto`, `top`, `bottom`, `next`; `none` on an image |
| `image_float_clearance` | `place(clearance)` | `1.5em` | `0`–`3em` |
| `image_caption_margin_inside` | `figure(gap)` | `0.65em` | `0`–`2em` |
| `image::x.txt[]`, `image_text_*` | an ASCII-art figure of raw text | the code font, leading `0.5em` | any font keys |

## Footnotes

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `footnotes_numbering` | footnotes numbered where they are | `page` | `chapter` (default), `page`, `document` |
| `footnotes_reference_content`, `_label_content` | `super(number)` | `'{{number}}'`, `'<sup>{{number}}</sup>'` | any template |
| `footnotes_font_size`, `footnotes_leading` | `footnote.entry`'s text and `par(leading)` | `0.85em`, `0.5em` | any |
| `footnotes_indent` | `footnote.entry(indent)` | `1em` | `0`–`2em` |
| `footnotes_label_gap` | the space after the number | `0.05em` | `0`–`1em` |
| `footnotes_item_spacing` | `footnote.entry(gap)` | `0.5em` | `0`–`1em` |
| `footnotes_margin_top` | `footnote.entry(clearance)` | `1em` | `0`–`2em` |
| `footnotes_separator_length`, `_width`, `_color` | `footnote.entry(separator)` | `30%`, `0.5`, black | any |

## Tables

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `table_border_width`, `table_grid_width` and colors | `table(stroke)` | `1`, black | any |
| `table_cell_padding` | `table(inset)` | `5pt` (the book: `6`) | any |
| `table_base_<key>` | set rules inside a table's cells | `table_base_text_align_last: center` | any base key |

## Contents, index and running heads

| Key | Typst | Typst's value | Range |
| --- | --- | --- | --- |
| `toc::[]` as a section's first block | `outline()` under a `= Contents` heading | | |
| `toc_entry_content` | the outline's entries | `'{{title}}'` | any template |
| `toc_entry_spacing` | each entry a paragraph | the leading | any length |
| `toc_index_terms` | the outline sets each heading again, its index markers with it | `true` | `false` (default), `true` |
| `index_sort` | in-dexter's one list of joined keys | `code-point` | by letter (default), `code-point` |
| `index_item_spacing`, `index_subterm_indent`, `index_hanging_indent` | in-dexter's `v(5pt)`, `h(1em)`, `hanging-indent: 2em` | `5`, `1em`, `2em` | any lengths |
| `index_pagenum_text_align`, `index_category_headings` | the page numbers in a column, no letters | `right`, `false` | `left`, `right`; `true`, `false` |
| `index-pagenum-sequence-style` (attribute) | each page once | `page` | `page`, `range`, `term` |
| `header_*_content` with `{{top-title}}`, `{{top-numeral}}` | a header that queries the last heading before the page | | any template |
| `running_content_on_openers`, `section_role_<role>_running_content_on_openers` | a header on a page that starts a chapter | | `true`, `false` |

## What has no key

Some of what the modern engine took from Typst is how it works, not a
setting, because it was an improvement over asciidoctor-pdf's layout for
any book:

- Line breaks follow UAX #14: after a slash, a `?` or a `!` before a
  letter, never beside an opening or closing bracket; a URL breaks as
  Typst breaks a link, and not at all when its host starts with a digit.
- Only words of letters are hyphenated; a hyphen's cost counts letters.
- A last line justified only because it is too wide only shrinks.
- An anchor takes no width; a paragraph of index terms alone takes no
  room and keeps with the block after it.
- Images float only at the top level (not in a list, a table or a
  sidebar).

ADR-0013 keeps them: they are better for any book. What only reproduced
Typst's defects (the contents page listed in the index, URLs that don't
break when their host starts with a digit) was removed; the tags
`hs-golden-parity-2026-10-06` keep the state that did.
