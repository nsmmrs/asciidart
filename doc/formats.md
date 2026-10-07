# What each format does with a book

asciidart writes a book as a PDF, a single HTML page, a website
(`multipage_html5`), an EPUB 3 and DocBook 5 (and man pages, for the
`manpage` doctype). ADR-0012 sets the goal: every feature of a book
works in every format, in the form that format's readers expect, unless
the medium has no place for it. This table records where each one is. A
**gap** is a feature a format should have and doesn't yet; lane epic
EPIC-m31mf9 has a card for each. *n/a* is a
feature the format has no use for.

| Feature | PDF | HTML | Website | EPUB 3 | DocBook 5 |
| --- | --- | --- | --- | --- | --- |
| Index (`[index]`, `((term))`) | page numbers | links to sections, by letter | its own page, links across pages | links, by letter; **gap:** EPUB Indexes semantics (`epub:type="index"`, a landmark) | `<indexterm>`, `<index/>` |
| Index order and layout (`index_sort`) | theme keys | **gap:** by letter only | **gap:** by letter only | **gap:** by letter only | the processor's |
| Contents (`:toc:`, `toc::[]` in a section) | yes | yes | a page of its own | navigation; `toc::[]` lists the contents there | a chapter of `toc::[]` alone is `<toc>` |
| `%notoc` sections | yes | yes | yes | yes | n/a |
| Footnotes | bottom of the page | end of the page | end of each page | pop-up notes | `<footnote>` |
| Footnote marker templates | theme keys; **gap:** the `footnote-*-template` attributes aren't read | attributes | attributes | attributes | n/a |
| Callouts linked both ways | always | `callout-links` | `callout-links` | `callout-links` | `<co>`, `<calloutlist>` |
| Caption templates, `<kind>-numbering: all`, `%unnumbered` | yes | yes | yes | yes | titles (the processor numbers) |
| Text files as images (`image::art.txt[]`) | the text, in the code font | the text, `<pre>` in the image block | same | same, the file not packed | `<literallayout>` in the media object |
| Figure placement (`placement=`, `image_placement`) | floats | n/a | n/a | n/a | `floatstyle` (`before`, `none`) |
| Keep together (`%unbreakable`) | yes | **gap:** print CSS `break-inside: avoid` | **gap:** same | **gap:** same | **gap:** `keep-together` processing instruction |
| Hyphenation (`:hyphens:`) | patterns, 72 languages | **gap:** CSS `hyphens: auto` | **gap:** same | **gap:** asciidoctor-epub3's `hyphens` attribute | n/a |
| Roles for text (`[.sc]#...#`) | theme `role_<role>_*` | CSS (the author's) | CSS | CSS | `role` attribute |
| Built-in roles (`small-caps`, `big`, `small`, colors) | **gap:** `small-caps` needs a theme key | colors, sizes; **gap:** no `small-caps` | same | same | `role` attribute |
| Section roles (a boxed `[.html-note]`) | theme `section_role_<role>_*` | class (CSS) | class | class | `role` |
| Source highlighting | hilite | hilite | hilite | hilite | `language` |
| Math (`stem:[]`) | **gap:** shown as source | MathJax | MathJax | **gap:** shown as source (asciidoctor-epub3 writes MathML for AsciiMath) | `<mathphrase>` |
| Cover (`front-cover-image`) | cover page | **gap:** none | **gap:** none on the home page | cover | `<cover>` |
| Title page, dedication, colophon | yes | headings | pages | pages; **gap:** no landmarks for them | `<dedication>`, `<colophon>` |
| Book metadata (`isbn`, `editor`, `copyright`) | **gap:** not in the PDF's metadata | `<meta>` (author, copyright) | same | OPF | **gap:** not in `<info>` |
| Running heads, page numbers | yes | n/a | n/a | **gap:** a `page-list` mapping to the print pages (optional) | n/a |
| Page paths (`page-path`) | n/a | n/a | yes | n/a | n/a |
| Show link URIs (`show-link-uri`) | footnote or after | n/a | n/a | n/a | n/a |
| Help text lists the backend | **gap:** `--help` names html5, xhtml5, docbook5, manpage only | | **gap:** same | **gap:** same | |
