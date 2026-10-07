# Changelog

## 0.1.0 (unreleased)

First release of asciidart, an AsciiDoc processor for Dart compatible with
the Asciidoctor **2.0.26** release. Not affiliated with or endorsed by the
Asciidoctor project.

- Converts AsciiDoc to HTML 5, DocBook 5 and man pages. Output is
  byte-identical to the Asciidoctor 2.0.26 gem on every backend, checked in
  CI by `tool/parity.sh` over the fixture and parity corpora; the end-to-end
  CLI suite (134 tests) passes against both asciidart and the gem.
- A small, typed public API designed from usage scenarios
  (`doc/api.md`): an `Asciidart` configuration (safe mode, attributes,
  extensions, an HTML override, highlighters, Mustache templates) with
  `parse`, `parseHeader`, `convert` and asynchronous variants; the default
  configuration `asciidoc`; a sealed tree of typed nodes (`Section`,
  `Paragraph`, `Listing`, `Admonition`, lists, tables, inline elements)
  with `descendants<T>()` and `plainText`; inline content as a typed tree
  (`inlines`, `titleInlines`: text and formatted text, links, images...,
  nested; ADR-0008); typed attributes; source-preserving edits of header
  attributes (`withAttribute`, `withoutAttribute`: only the entry's lines
  change); an EPUB 3 backend in the native executable (`-b epub3`), the
  same EPUB as the asciidoctor-epub3 2.3.0 gem file by file (ADR-0009);
  diagnostics
  collected per document; callback-based extensions (`InlineMacro`,
  `BlockMacro`, `CustomBlock`, `IncludeResolver` (may be asynchronous),
  `TreeProcessor`, `Preprocessor`, `Postprocessor`, `Docinfo`).
  `package:asciidart/asciidart.dart` has no file system access and runs on
  the web; `package:asciidart/io.dart` adds `parseFile`, `convertFile` and
  `convertTree`; `package:asciidart/cli.dart` runs the command line with a
  configuration compiled in. Everything else is private;
  `tool/api_surface.txt` records the public API and CI checks it.
- A PDF backend (`-b pdf`, native executable) that converts as the
  asciidoctor-pdf 2.3.27 gem does and reads its YAML themes unchanged, drawn
  with libpdf (asciidart's own pure-Dart PDF library; no Prawn code). It
  covers:
  - title pages, covers and backgrounds (PDF pages included);
  - running content;
  - tables, images (raster and SVG), icons and admonitions;
  - the table of contents, the index, footnotes and outlines;
  - `media=prepress` books (recto starts and inner and outer margins) and
    man pages.

  By default the layout is asciidart's own: justified paragraphs are
  broken as Typst's optimizer breaks them (its costs: even spacing, few
  hyphens, no lone word on the last line), other text one line at a
  time, never inside a word at a style change, and
  hyphenated in the document's language (hyph-utf8's patterns, 72
  languages; `:hyphens!:` turns it off; code spans stay whole), and a
  paragraph leaves at least two lines on either side of a page break
  (`prose_orphans`, `prose_widows`). Text is kerned by the font's GPOS
  pairs and set with its standard ligatures (`base_font_ligatures: none`
  turns them off), emphasis inside italic text is upright
  (`base_emphasis_inversion`), and paragraph indents may be given in
  `em` or `rem`. Listings split only between lines, leaving at least two
  on either side of a page break (`code_orphans`, `code_widows`); a line
  too long for the block wraps with a return arrow past its end and a
  hanging indent (`code_wrap_marker`, `code_wrap_indent`); a caption
  stays with its block; and text in a column too narrow for a single
  character is set anyway rather than dropped. Callout markers are left out
  when code is copied (marked content with an empty ActualText) and link
  to their callout list items, which link back. Blank pages (before a
  recto start) carry no running content unless
  `running_content_on_blank_pages` is true. Tables with a role take the
  theme's `table_role_<role>_*` keys, and a cell whose text is a phrase
  with a role, `table_cell_role_<role>_*`. `base_line_breaking: optimal`
  optimizes ragged text too, `greedy` breaks any text one line at a time. `doc/pdf.md` lists every setting. With `asciidoctor-compat` (or
  `-a pdf-compat`) the settings default to asciidoctor-pdf's look: 792 of
  the 797 documents of the gem's spec suite look the same, page image
  against page image (`benchmark/PARITY.md`), 6 to 15 times faster than
  the gem (`benchmark/BASELINE.md`). `hyphens` and `base_hyphens`
  hyphenate as the gem does with text-hyphen.
- The index in HTML and EPUB: an `[index]` section lists the document's
  index terms by letter, with subterms, see and see-also references, and a
  link to each section a term is used in (Asciidoctor renders it empty;
  `index-html!` keeps its output). `Document.index` gives the same as typed
  `IndexLetter` and `IndexEntry` values.
- A `multipage_html5` backend (native executable): a book as a website,
  one page per part and chapter (`multipage-level` for deeper sections),
  a home page listing them, previous, up and next links, cross references,
  the TOC, the index and callout links rewritten across pages, footnotes
  on the page they are on.
- Valid DocBook and EPUB where Asciidoctor's output isn't (unbalanced
  emphasis around index terms, section styles DocBook has no element for,
  emphasis in literals, invalid image widths, an empty TOC title, links
  from a website's root): the Hypermedia Systems book validates against
  the DocBook 5.0 schema and passes EPUBCheck.
- `asciidoctor-compat` (ADR-0015) keeps Asciidoctor's look while
  migrating, for every format or a list (`html`, `epub`, `docbook`,
  `manpage`, `pdf`): an attribute, the `ASCIIDART_COMPAT` environment
  variable, `compat:` in a project's `asciidart.yml` or in
  `~/.config/asciidart/config.yml`.
- Math in the PDF: AsciiMath and LaTeX math are typeset (ADR-0014), inline at the
  text's size and in display style in STEM blocks, by libpdf's math layout
  (the OpenType MATH table's rules) in the bundled Noto Sans Math or the
  theme's `math_font_family`; copied, a formula gives its source.
- Old-style numerals and small capitals from the font's OpenType
  features (`base_font_variant_numeric: oldstyle-nums`,
  `role_<role>_font_variant: small-caps`), in the modern PDF engine.
- Books in the modern PDF engine: footnotes at the bottom of the page
  (`footnotes_placement`), links' URIs as footnotes
  (`show-link-uri=footnote`), chapter and part openers without running
  content and with their label on a line of their own
  (`heading_h2_content`, a template), `noheader` and `nofooter` on a section,
  floating images (`image_placement: auto`), sections with a styled role
  in a box (`section_role_<role>_*`), an index with each page once and
  page numbers in a column
  (`index_pagenum_text_align`, `index_category_headings`, `index_font_*`),
  and source code highlighted by hilite in a highlight.js theme
  (`source-highlighter=highlight.js`, `highlightjs-theme`).
- Generated text from templates (ADR-0010): caption numbers
  (`<kind>-caption-template`, `appendix-caption-template`) in every
  format, footnote markers (`footnote-reference-template`,
  `footnote-label-template`; the PDF's `footnotes_reference_content`,
  `footnotes_label_content`), callout markers, headings, running content
  and contents entries in the modern PDF engine (`{{number}}`,
  `{{title}}`, optional parts), and the website's navigation and list of
  pages (`multipage-nav-*-template`, `multipage_nav.mustache`,
  `multipage-toc-entry-template`). The website: a `toc::[]` macro takes
  the list of pages (a contents page), `multipage-page-toclevels` puts a
  page's own sections at its top (`multipage_toc.mustache`), the list's
  entries carry the section's kind and roles as classes. The `notoc`
  option leaves a section out of the contents; `epub-unique-identifier:
  isbn` makes the ISBN the EPUB's identifier. In the modern PDF engine,
  a styled section role can sit in the middle of its page
  (`section_role_<role>_vertical_align`), a paragraph role has its own
  indent and space below (`role_<role>_text_indent`, `_margin_bottom`),
  a sidebar's title its own space below (`sidebar_title_margin_bottom`).
- Print: `pdf-standard=PDF/X-4` with an output intent
  (`pdf-output-intent`, the printer's ICC profile), a bleed from the
  theme (`page_bleed`), and a layout report of the blocks that break
  across pages (`pdf-layout-report`), with preflight messages.
- `--progress` reports each phase of a conversion as it finishes; the
  modern PDF engine's layout warnings name the source line of the block.
- `callout-links`: callouts and their list items linked both ways in HTML
  and EPUB, markers kept out of copied code, and warnings for callouts no
  list item explains.
- Remote content (`allow-uri-read`): `parseAsync` and `convertAsync` fetch
  includes and data-URI images, honoring `cache-uri`.
- The `asciidart` command takes the options of the gem's `asciidoctor`
  command, except the Ruby-specific `-r`, `-I`, `--eruby` and `-w`.
  Messages start with `asciidart:` and read like a Dart tool's
  (`benchmark/PARITY.md`); `--version` names asciidart and the Asciidoctor
  release it is compatible with; `man/asciidart.1` documents it.
  `init-config` generates a project for a custom command with Dart converter
  functions compiled in.
- Syntax highlighting with highlight.js at conversion (hilite, a Dart port
  of highlight.js 11.12.0); `highlightjs-mode=client` gives Asciidoctor's
  browser-side markup. Rouge, Pygments and CodeRay behave as when their gems
  are missing.
- Custom converters: Mustache templates (`-T`, `templateDirs`) and HTML
  overrides in Dart, in place of Ruby's Tilt templates (ADR-0002).
- `{asciidoctor-version}` (and `asciidoctorVersion` in the API) report
  2.0.26, so documents written for Asciidoctor keep working;
  `{asciidart-version}` (`asciidartVersion`) reports asciidart's version,
  which also appears in the HTML generator meta tag and the man page
  header.
- The compiled command converts 5–10x faster than the gem end to end, and
  about 2x faster in process (`benchmark/BASELINE.md`).
- The same core builds as the npm package `asciidart` for Node.js and
  browsers (ADR-0005). Its API is generated from the Dart API, with the
  same names and shapes, plus TypeScript declarations
  (`tool/generate_js.dart`, ADR-0007).
