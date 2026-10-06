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

Text is kerned by the font's OpenType (GPOS) pairs.

### Listings

| Key | Default | What it does |
| --- | --- | --- |
| `code_orphans` | `2` | The fewest lines of a listing left at the bottom of a page. |
| `code_widows` | `2` | The fewest lines of a listing carried to the top of the next page. |
| `code_wrap_indent` | `1em` | How far past its own indentation a code line that is too long goes on, on the next line. |
| `code_wrap_marker` | arrow | `none` leaves out the return arrow drawn past the end of a line that wraps. |

A caption stays with the block it is above. Callout markers aren't part
of the text when code is copied, and link to their callout list item,
which links back.

### Tables

| Key | What it does |
| --- | --- |
| `table_role_<role>_<key>` | For a table with the role (`[.wide]`), replaces `table_<key>`: every table with the role is styled once, in the theme. |
| `table_cell_role_<role>_background_color`, `_font_color`, `_font_style`, `_font_size`, `_font_family`, `_text_align` | Style a cell whose whole text is a phrase with the role (`\|[.paid]#Paid#`). |

AsciiDoc has no syntax for a cell's role, so a cell takes the role of its
text. In HTML, the same cells can be styled with CSS:
`td:has(> p > span.paid:only-child) { background: #dfd; }`.

### Pages

| Key | Default | What it does |
| --- | --- | --- |
| `running_content_on_blank_pages` | `false` | A blank page (the verso before a chapter that starts on a recto page) has no header or footer unless this is `true`. |

A column too narrow for even one character keeps its text (set past its
edge, with a warning), where the gem leaves the table out.
