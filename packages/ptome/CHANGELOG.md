# Changelog

## 0.1.0 (unreleased)

First release of Ptome (called asciidart until 2026-10-08, ADR-0018), a
processor for AsciiDoc® documents written in Dart, compatible with
Asciidoctor's development version (upstream `main` at `30fb8cd5`, which
reports **2.1.0.alpha.0**), fixing bugs Asciidoctor still has. The tag
`asciidoctor-2.0.26-parity` marks the last commit that matched the 2.0.26
release byte for byte (ADR-0017). Not affiliated with or endorsed by the
Asciidoctor project.

- The ptome language: texts cited by numbered units (ADR-0019, ADR-0020,
  `doc/units.md`), read by ptome's own parser and rendered by every
  backend.
  - A document that names schemes (`:units: bible, kjv`, YAML files in the
    nearest `schemes/` directory) can write:
    - unit markers: `@`, `@@`, `@6`, `@(a)(1)`, bridges, `@^`, attributes;
    - ranges `[name}` … `{name]`;
    - note streams `note:x[…]`, placed as footnotes, entries or after the
      unit;
    - references by address (`<<Ps 86:15; 103:8–13>>`);
    - includes by ID and by address, with citations made from the work;
    - `[annotations]`, `[overlays]` and speeches;
    - defined terms, apparatus roles and term rules.
  - Ptome works out every unit's anchor, label and reftext. Labels out of
    sequence are warnings. How units look is in the scheme files, as text
    templates, styles and roles (scheme format 2).
  - `-a units-as-of=DATE` gives a statute as in force on that date, and
    `-a units!` reads a units document as plain AsciiDoc.
  - `ptome check FILE...` reads documents without converting them.
  - `include::text.adoc[parallel=translation.adoc]` sets two documents in
    one scheme side by side, unit by unit, matched by address.
  - `Document.units`, `Document.unit(idOrAddress)` and
    `Document.passage(address)` give the units in the Dart and JavaScript
    APIs: each `Unit` has its scheme, level, labels, ID, reftext, citation,
    source line, parent, children and notes; references by address and
    defined terms too. Units are nodes of their own in the tree
    (`UnitMark`, `NoteCall`, `NoteEntry`, `UnitBlock`) and in every
    backend (semantic HTML: `class="unit"`, `data-unit`).
  - `ptome check --format=json --list` reports units and problems (each
    with its kind, file, line and column) to tools.
  - Checked against the loci experiment's 26 documents (scripture, law,
    classics, drama, liturgy, a hymnal, a catechism, a specification) and
    a commonplace book quoting them all: the units model each yields
    agrees with the first, preprocessing implementation's
    (`tool/units_model_check.dart`).
  - Documents without `:units:` or `:works:` are unaffected.
- Follows Asciidoctor's development version (upstream `main` at
  `30fb8cd5`, 2.1.0.alpha.0) rather than the 2.0.26 release: the CLI's
  `--log-level` and `--sourcemap`; highlight.js `nohighlight`; `linenums` as
  a block option; ordered lists that start at their first marker; empty
  section IDs; the `~~~~` open block; a block style above the title keeping
  it in the body; block attributes overriding `imagesdir`; `cxx`; attribute
  lists in formatted text without `[`; dot-free attribute names; inline image
  IDs; `link=self`; Wistia videos; per-section `toclevels` and multipart
  outlines; table and column widths as attributes; page and thematic break
  classes; no generator meta with `reproducible`; DocBook quote roles; man
  page lists and table cells without spurious `.sp`; front matter with
  `+++`, skipped per include; a warning for URI includes without
  `allow-uri-read`; the main branch's stylesheet and locales. The corpus
  (17,900 conversions) is identical to the gem built from that commit.
- Fixes 25 bugs reported upstream that Asciidoctor (upstream `main` at
  `30fb8cd5`) still has, chosen by triaging
  all 610 open upstream issues (`doc/upstream-triage.md`). Each fix has a
  CLI test in `test/bugfix/` that fails on the gem and passes here
  (`tool/bugfix_check.sh`), and the output differences are listed in
  `benchmark/PARITY.md`: section IDs for punctuation-only titles and titles
  with footnotes; nested fonts in man pages; table cells after colspans and
  beside rowspans taking the right column spec, invalid column specs, tabs
  in literal cells and comments in AsciiDoc cells; `X//..` in paths;
  assigned author names; links in superscripts; icons in link text; `\]` in
  anchor reference text; anchors in section titles; em dashes next to
  formatted text and curved quotes; URLs ending in `>`; paragraphs that look
  like attribute lines; ancestor list continuations; headings beyond `<h6>`;
  quotes in image attributes.
- Converts AsciiDoc to HTML 5, DocBook 5 and man pages. Output is
  byte-identical to the Asciidoctor gem (built from upstream `main` at
  `30fb8cd5`) on every backend, apart from the bugs fixed, checked in
  CI by `tool/parity.sh` over the fixture and parity corpora; the end-to-end
  CLI suite (134 tests) passes against both Ptome and the gem.
- A small, typed public API designed from usage scenarios
  (`doc/api.md`): a `Ptome` configuration (safe mode, attributes,
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
  `package:ptome/ptome.dart` has no file system access and runs on
  the web; `package:ptome/io.dart` adds `parseFile`, `convertFile` and
  `convertTree`; `package:ptome/cli.dart` runs the command line with a
  configuration compiled in. Everything else is private;
  `tool/api_surface.txt` records the public API and CI checks it.
- A PDF backend (`-b pdf`, native executable) that converts as the
  asciidoctor-pdf 2.3.27 gem does and reads its YAML themes unchanged, drawn
  with plain_pdf (Ptome's own pure-Dart PDF library; no Prawn code). It
  covers:
  - title pages, covers and backgrounds (PDF pages included);
  - running content;
  - tables, images (raster and SVG), icons and admonitions;
  - the table of contents, the index, footnotes and outlines;
  - `media=prepress` books (recto starts and inner and outer margins) and
    man pages.

  By default the layout is Ptome's own: justified paragraphs are
  broken as Typst's optimizer breaks them (its costs: even spacing, few
  hyphens, no lone word on the last line), other text one line at a
  time, never inside a word at a style change, and
  hyphenated in the document's language (hyph-utf8's patterns, 72
  languages; `:hyphens!:` turns it off; code spans stay whole; a word
  across formatting hyphenated whole), a compound's hyphen repeated at
  the next line's start in Portuguese, Spanish and the other languages
  whose typography has it so, URLs broken between their parts as Typst
  breaks them (`benchmark/TYPST.md`), and a
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
  `manpage`, `pdf`): an attribute, the `PTOME_COMPAT` environment
  variable, `compat:` in a project's `ptome.yml` or in
  `~/.config/ptome/config.yml`.
- Math in the PDF: AsciiMath and LaTeX math are typeset (ADR-0014), inline at the
  text's size and in display style in STEM blocks, by plain_pdf's math layout
  (the OpenType MATH table's rules) in the bundled Noto Sans Math or the
  theme's `math_font_family`; copied, a formula gives its source. The
  AsciiMath and LaTeX converters live in plain_math (ADR-0018), checked
  against the asciimath gem, Temml and KaTeX; LaTeX's `\text` reads TeX's text
  mode, including `$...$` math in it.
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
  and source code highlighted by plain_highlighting in a highlight.js theme
  (`source-highlighter=highlight.js`, `highlightjs-theme`).
- What a reference Bible needs, from theme keys any book can use: a book
  in columns with its chapter headings across them and each chapter's
  columns balanced (`page_columns`), running content from the first and
  last marks on the page (`running_content_marks`, `{page-first-mark}`),
  headings set as drops beside the first lines (`heading_h<n>_drop_lines`),
  figures that span the columns (`image_scope`), and phrases with a role
  set beside their line in the center column or the outer margin
  (`role_<role>_display: side`, `side_notes_column`).
- Layouts no PDF library we know of makes: a sidebar that floats beside
  the text (`role_<role>_float`) and goes on at the top of the next page,
  through the repeated banner there (`heading_h<n>_repeat`), the blocks
  beside it narrowed or, where they don't fit beside it, set below it;
  banners (`heading_h<n>_background_color`, negative side margins), rules
  of rounded bars under headings (`heading_h<n>_rule_*`), shadows and
  background images on framed blocks, and role keys for example blocks
  and sidebars (`example_role_<role>_*`, links in them included).
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
- The `ptome` command takes the options of the gem's `asciidoctor`
  command, except the Ruby-specific `-r`, `-I`, `--eruby` and `-w`.
  Messages start with `ptome:` and read like a Dart tool's
  (`benchmark/PARITY.md`); `--version` names Ptome and the Asciidoctor
  release it is compatible with; `man/ptome.1` documents it.
  `init-config` generates a project for a custom command with Dart converter
  functions compiled in.
- Syntax highlighting with highlight.js at conversion (plain_highlighting, a Dart port
  of highlight.js 11.12.0); `highlightjs-mode=client` gives Asciidoctor's
  browser-side markup. Rouge, Pygments and CodeRay behave as when their gems
  are missing.
- Custom converters: Mustache templates (`-T`, `templateDirs`) and HTML
  overrides in Dart, in place of Ruby's Tilt templates (ADR-0002).
- `{asciidoctor-version}` (and `asciidoctorVersion` in the API) report
  2.1.0.alpha.0, so documents written for Asciidoctor keep working;
  `{ptome-version}` (`ptomeVersion`) reports Ptome's version,
  which also appears in the HTML generator meta tag and the man page
  header.
- The compiled command converts 5–10x faster than the gem end to end, and
  about 2x faster in process (`benchmark/BASELINE.md`).
- Text outside Latin-1 no longer falls off a cliff: each inline pass is
  tried only where it can match, and its guards are answered from the
  characters a paragraph holds. The KJV converts to HTML in 0.9 s instead
  of 10.5 s (Ruby: 2.2 s), Greek *Ethics* in 42 ms instead of 688 ms. Text
  boxes in the PDF keep their placements and line breaks across the
  layout's probes and passes: the whole KJV as a PDF takes 11.8 s instead
  of 27.4 s, in half the memory.
- Fonts are the machine's, not compiled in: the PDF backend finds a
  theme's fonts among the installed ones (by file name, then by family;
  `PTOME_FONT_PATH` adds folders), falls back to the built-in PDF
  fonts with a warning when one is missing, and `ptome doctor`
  checks the built-in themes' fonts and downloads the missing ones from
  Google Fonts and their projects into the user's font folder. An EPUB
  embeds fonts only with `-a epub-embed-fonts`. The executable is 14.9 MB
  instead of 31.5 (the highlighting languages are compressed data, not
  code; the npm bundle is 1.57 MB).
- PDFs and EPUBs through the API and on JavaScript: `convertToBytes`,
  `convertToBytesAsync` and `convertFile` with `Backend.pdf` or
  `Backend.epub3`. Fonts can be given as bytes (`fonts`). The npm package
  loads the PDF and EPUB code on demand, so pages that only make HTML
  don't download it, and its command makes PDFs and EPUBs as the native
  one does. On Node.js, installed fonts come from the font folders. In a
  browser, the page's web fonts are used (`pageFonts`), and so are the
  visitor's installed fonts of the families asked for (`localFonts`,
  through Local Font Access). In a browser, the images and the theme a
  conversion reads are fetched relative to the page (includes are not).
  WOFF and WOFF2 fonts work everywhere fonts do. EPUBs also work in a browser without a host zlib: they are
  compressed with plain_compression's deflate there (the Dart VM and
  Node.js keep their zlib), and ZIP reading and `.gz` man pages use
  plain_compression on every platform. Font reading and the installed-font
  index live in plain_fonts, compression and ZIP in plain_compression,
  both in this workspace (ADR-0018). The PDF converter lays out with
  plain_typesetting (shaping, paragraphs, pages, math), which draws on
  plain_pdf's canvas.
- PDFs are the same on every run when sections have no ids (`sectids`
  unset): their destinations were named after a hash code that changed
  from run to run; they are numbered in order (`__section-1`...).
- Speed on every core (ADR-0016): the work a PDF or EPUB doesn't need in
  order (PNG images, compression) runs on the physical cores (`-a
  jobs=N`, `1` for none), with the same bytes at any number of workers;
  the index and page-numbered footnotes lay out again only from the
  pages they change; line breaks are kept per paragraph. The Hypermedia
  Systems PDF takes 2.1 s, from 3.8 s (Typst 0.15.1: 3.7 s); `-j` batches
  run on the same pool, each worker taking the next file as it finishes
  one, with every backend the executable has (PDF and EPUB included).
- The same core builds as the npm package `ptome` for Node.js and
  browsers (ADR-0005). Its API is generated from the Dart API, with the
  same names and shapes, plus TypeScript declarations
  (`tool/generate_js.dart`, ADR-0007).
