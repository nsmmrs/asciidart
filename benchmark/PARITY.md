# Parity with Asciidoctor

asciidart is compatible with Asciidoctor 2.0.26, and this file is the
ledger of that claim: the gates below compare it with the gem, and every
difference that remains is deliberate and listed under
[Known intentional differences](#known-intentional-differences).

Byte-identical gate (ADR-0001 D4): the asciidart CLI against the
Asciidoctor **2.0.26** gem, via `tool/differential.dart` (normalization:
version stamps and timestamps only). `master` targets 2.0.26 per
[ADR-0003](../adr/0003-target-latest-stable.md); the earlier port of
upstream `main` (2.1.0.alpha.0) is preserved on the `2.1.0` branch.

## Corpus

- `vendor/asciidoctor/test/fixtures/**` (upstream's fixtures, `*.adoc`,
  `*.asciidoc`, recursive) plus
  `vendor/asciidoctor/data/reference/syntax.adoc`: 30 files per backend.
- `test/parity/**` (documents of our own) plus the syntax reference: 12 files
  per backend. These pin the places where 2.0.26 differs from upstream
  `main` (tilde open blocks, ordered list starts, `link=self`, front matter,
  table and manpage layout, ...) and the differences the corpus check found;
  see [`test/parity/README.md`](../test/parity/README.md).

## Method

From the repository root, with the gem on `PATH`
(`gem install asciidoctor -v 2.0.26`):

```sh
tool/build-exes.sh
tool/parity.sh dist/asciidart-linux-x64
```

`tool/parity.sh` runs both corpora on html5, docbook5 and manpage. Each file
is converted as `<exe> -b <backend> -o - -q <input>` with `TZ=UTC` and
`SOURCE_DATE_EPOCH=0`. CI runs the same script on every push, against the
native executable (`dart-exe-e2e` job) and against the npm package's CLI on
Node.js (`npm` job, `tool/parity.sh test/e2e/bin/asciidart-node`).

## Verdict (2026-10-05): PASS — 126/126 identical

| Corpus | html5 | docbook5 | manpage |
| --- | --: | --: | --: |
| fixtures | 30/30 | 30/30 | 30/30 |
| parity | 12/12 | 12/12 | 12/12 |

Warnings on stderr were compared by hand over the parity corpus and match
too (the harness passes `-q`). The e2e suite (`test/e2e/`, 134 tests) passes
with no skips against the Dart CLI, the Node.js CLI and the gem. The Node.js
CLI gives the same 126/126.

## Corpus check (2026-10-05): 17,900 of 17,900 conversions identical

Beyond the gate above, `tool/corpus_parity.dart` compares stdout, warnings
and exit codes over a large corpus of real documents: the Asciidoctor
repository at `v2.0.26` (fixtures, docs, and 1,451 snippets extracted from
its Ruby tests), the AsciiDoc language docs, Asciidoctor.js, the PDF, EPUB3,
Diagram and Maven plugin docs, Antora, git's `Documentation/`, and the
Quarkus, Hibernate and Spring Boot reference docs: 4,475 files, each
converted as html5, embedded html5, docbook5 and manpage.

```sh
tool/corpus/fetch.sh /tmp/corpus           # pinned in tool/corpus/sources.txt
dart run tool/corpus_parity.dart --exe-a asciidoctor \
  --exe-b "dist/asciidart-linux-x64 -a highlightjs-mode=client -a index-html! -a asciidoctor-compat=true@" \
  --out /tmp/corpus-results /tmp/corpus
```

The reference is the 2.0.26 gem with the `asciimath` gem (asciidart has
its own port, ADR-0014) and no other optional gems (asciidart provides
none of Rouge, Pygments or CodeRay, and behaves as the gem does without
them), and asciidart runs with `highlightjs-mode=client` so that
documents using highlight.js compare with the gem's browser markup, and
with `index-html!` so that documents with an index section compare with
the gem's empty one, and with `asciidoctor-compat` (ADR-0015; a default
the document may override, as `@` makes it) so that a page embeds
Asciidoctor's stylesheet alone and no cover (see the intentional
differences). What asciidart adds to a block with the `unbreakable`
option (the class in HTML, `<?dbfo keep-together="always"?>` in DocBook)
is removed from both outputs before they are compared. The check found and drove fixes
for: `cols=""`, `%autowidth` with a width, nested description list items
with attached blocks, line breaks in AsciiMath blocks, Ruby's ASCII-only
`\s` and `strip` against Unicode spaces, `\p{Blank}`, full case mapping
(`ß` → `SS`), a dropped table cell's line number, an empty block anchor
crash, and the missing "not available" warnings. `test/parity/` keeps
reproducers of each.

## Known intentional differences

- asciidart names itself: the HTML generator meta tag and the man page
  header say `Asciidart <version>` (`{asciidart-version}`) instead of
  `Asciidoctor 2.0.26`; `--version` prints `Asciidart <version> (compatible
  with Asciidoctor 2.0.26) [https://github.com/nsmmrs/asciidart]` and a
  runtime line naming the Dart runtime; `--help` shows `asciidart` in its
  usage lines; `-h manpage` prints asciidart(1); and messages start with
  `asciidart:` (`asciidart: WARNING: ...`) instead of `asciidoctor:`. The
  `asciidoctor` and `asciidoctor-version` attributes keep their values, so
  documents see the same thing as under the gem. The parity tools treat
  either name as the same stamp or prefix.
- Fatal errors are reported as one `asciidart: FAILED: <message>` line in
  plain wording, without Ruby exception classes, gem names or `Processing
  aborted.` (for example `asciidart: FAILED: failed to load <stdin>:
  missing converter for backend 'pdf'`). Log messages (warnings, errors)
  keep Asciidoctor's wording. Library callers catch `AsciidoctorException`.
- A reader that closes stdout early (`asciidart -o - doc.adoc | head`)
  ends the run quietly with exit code 0; the gem reports a broken pipe.
- Remote content (`allow-uri-read`) is read by the CLI and by the
  asynchronous API (`convertAsync`, `loadAsync`, ...), which fetch it over
  HTTP before converting; the synchronous API reads it only through an
  `AsciidoctorOptions.uriReader`. The `cache-uri` attribute keeps fetched
  content for later conversions in the same process instead of an on-disk
  cache (the gem needs the `open-uri-cached` gem for it).
- An unknown CLI option prints Ruby's `Did you mean?` hint only in Ruby;
  that suggestion engine depends on the Ruby version (see the notes at the
  top of `lib/src/cli/options.dart`).
- Dart-only features (Mustache templates, `init-config`, `-j/--jobs`) have
  no Ruby counterpart.
- DocBook and EPUB output is valid XML where Asciidoctor's isn't
  (`test/divergences/xml_output.bats` reproduces each case on both
  CLIs): tags are balanced (emphasis that opens inside an index term and
  closes after it); a section style DocBook has no element for
  (`[introduction]`) gives a chapter or section, and `[partintro]`
  outside a part a section; emphasis and quotes inside a `<literal>`
  become phrases and quotation marks; the copyright's year comes before
  its holder, and a copyright without a year is a legal notice. In EPUB, an image width is a
  number of pixels or a percentage (another value is left out), an empty
  `toc-title` gives the navigation Asciidoctor's default title, and a
  link to a path from a website's root goes to its id in the book, or is
  text. With `source-highlighter=highlight.js`, an EPUB's code is
  highlighted at conversion and the theme's stylesheet is in the EPUB
  (`styles/highlightjs.css`), where the gem links highlight.js's
  stylesheet and scripts outside it (`test/divergences/epub_output.bats`).
  EPUB parity compares the gem's chapters with these repairs made. The
  `isbn` and `editor` attributes (which the gem ignores) add an ISBN
  identifier and editors to an EPUB's metadata, and
  `epub-unique-identifier: isbn` makes the ISBN its unique identifier.
  `ebook-code-overflow=scroll` makes code lines scroll rather than wrap.
- Quotes (emphasis, strong, monospace...) pair around an index term,
  never into it: in `(((_hyperscript, event filter))) an _event filter_`
  the emphasis is `event filter` and the term `_hyperscript`, where
  Asciidoctor pairs the underscores across the term, prints a stray tag
  and splits the term (`test/divergences/index_terms.bats`). The term's
  own text is quoted alone.
- Generated text from templates (ADR-0010): `footnote-reference-template`
  and `footnote-label-template` set the footnote markers in HTML and EPUB,
  `<kind>-caption-template` a caption's number (`listing`, `figure`,
  `table`, `example`, `appendix`) in every backend; without them the
  output is Asciidoctor's.
- A section with the `notoc` option is left out of the contents (HTML,
  PDF, EPUB, the website's list); Asciidoctor has no such option.
- `callout-links` (off by default) links callouts and their list items
  both ways in HTML and EPUB, keeps markers out of copied code, and warns
  about callouts no list item explains (`no callout list item for <3>`,
  `no callout list for <1>`). The modern PDF engine always does the
  first two.
- `--help` and `-h manpage` describe `-T` and `-E` as they work in this
  build (Mustache templates) instead of mentioning tilt and gems.
- The Ruby-only options `-r/--require`, `-I/--load-path`, `--eruby` and
  `-w/--warnings` do not exist here and are rejected as unknown options;
  extensions are compiled into a custom binary instead (see
  `asciidart init-config`). `-q` silences log messages only, since there
  are no script warnings.
- highlight.js is asciidart's syntax highlighter, and highlights at
  conversion: with `source-highlighter=highlight.js`, source blocks come out
  highlighted (by hilite, a Dart port of highlight.js 11.12.0, byte for byte
  what highlight.js produces in the browser), and the page links only the
  theme's stylesheet (highlight.js 11.12.0 on the CDN, or `highlightjsdir`).
  The gem's behavior, markup for the browser plus the highlight.js 9.18.3
  scripts, is `highlightjs-mode=client`. Blocks with callouts have their
  spans closed at each line end, so the callout numbers sit outside them.
- The default HTML stylesheet (embedded, or written as `asciidoctor.css`
  with `linkcss`) is Asciidoctor's followed by asciidart's house rules
  (ADR-0011, `doc/style.md`): a narrower measure, near-black headings,
  tables with rows only, and the classes asciidart's own features use
  (`small-caps`, `unbreakable`, text images, the index's columns, the
  cover). The markup is Asciidoctor's. `-a stylesheet=asciidoctor`
  embeds (or writes) Asciidoctor's stylesheet alone. Likewise an EPUB's
  `styles/epub3.css` is asciidoctor-epub3's followed by the house rules
  (`-a epub3-stylesheet=asciidoctor-epub3` for its alone; EPUB parity
  passes it), and the modern PDF engine's default theme is asciidart's
  (`-a pdf-theme=default` for asciidoctor-pdf's).
- An `[index]` section lists the document's index terms in HTML and EPUB
  (Asciidoctor and asciidoctor-epub3 render it empty, Asciidoctor issue
  #450): a heading per letter, the terms with their subterms, a link to
  each section a term is used in, and its see and see-also references.
  Each use gets an anchor (`<a id="_indexterm_N"></a>`) where the term is.
  Only documents with an index section change; `index-html!` turns it
  off. In an EPUB the index is marked up with the EPUB Indexes vocabulary
  (`epub:type="index"`, `index-entry`, `index-term`, `index-locator`...)
  and has a landmark; a term in a section title is indexed too.
- An EPUB's landmarks name the front and back matter (dedication,
  colophon, acknowledgments, index) and its "Start of Content" is the
  first chapter after the front matter, where asciidoctor-epub3's is the
  first chapter (`test/divergences/epub_output.bats`); EPUB parity
  compares navigation documents without their landmarks.
- Where Asciidoctor has no output for a book feature, asciidart writes
  its own (ADR-0012, `doc/formats.md`): a text file shown as an image
  (`image::art.txt[]`) is its text in every backend (Asciidoctor writes an
  `<img>` no browser shows); `toc::[]` lists the contents in an EPUB; a
  chapter of `toc::[]` alone is DocBook's `<toc>`; an image's `placement`
  is DocBook's `floatstyle`; a block with `%unbreakable` has the class
  `unbreakable` in HTML and EPUB and DocBook XSL's keep-together
  instruction; `:hyphens:` adds a `hyphens: auto` style to HTML and EPUB.
  `--help` lists the backends asciidart has built in. `index-sort:
  code-point` and `index-category-headings!` set the HTML and EPUB
  index's order and letter headings; `front-cover-image` is shown before
  the header of an HTML page (the website's home page); DocBook's `<info>`
  has the `isbn` (`biblioid`) and `editor` attributes.
- Rouge, Pygments and CodeRay are not available: they behave as the gem does
  without their gems (no highlighting, the highlighter's `<pre>` class kept),
  and warn in asciidart's words, once: `Rouge syntax highlighting is not
  available. Functionality disabled.` (likewise Pygments and CodeRay).
  AsciiMath is converted to MathML in DocBook and EPUB by asciidart's port
  of the `asciimath` gem 2.0.6 (ADR-0014), as Asciidoctor and
  asciidoctor-epub3 do with that gem installed; the parity references
  install it too. An EPUB content document with MathML declares the
  `mathml` property (the gem doesn't; EPUBCheck requires it).
- The `missing convert handler` warning names the converter by its Dart
  class (`ManpageConverter`) instead of the Ruby one
  (`Asciidoctor::Converter::ManPageConverter`).

## EPUB3 (`-b epub3`)

The native executable converts to EPUB 3 as the asciidoctor-epub3 2.3.0
gem does (on Asciidoctor 2.0.26), checked file by file by
`tool/epub_parity.dart`: the entries of the EPUB, their order (`mimetype`
first, stored), and the bytes of every file once the dates that change
with each run (`dcterms:modified`, `dc:date`) are set aside; the messages
too. ZIP compression is not compared (zlib versions differ). With
`--epubcheck`, EPUBCheck must report the same for both EPUBs.

```sh
gem install asciidoctor-epub3 -v 2.3.0
dart run tool/epub_parity.dart --exe-a "$(command -v asciidoctor-epub3)" \
  --exe-b dist/asciidart-linux-x64 --epubcheck epubcheck.jar \
  $(find vendor/asciidoctor-epub3/test/fixtures -name '*.adoc')
```

Verdict (2026-10-05): the 72 documents of the gem's spec fixtures
(`vendor/asciidoctor-epub3/test/fixtures`, run in CI) are identical, with
the same EPUBCheck reports; so are 499 of a 500-document sample of the
corpus (the 136 books and 364 other documents), the one left being the
first difference below.

Intentional differences:

- A preamble whose only block is a list becomes the abstract, as in the
  gem, but its list is written as a list: the gem writes a dump of Ruby
  objects there (Asciidoctor's `List#content` is the array of items).
- AsciiMath is MathML, as in the gem with the asciimath gem (asciidart's
  port, ADR-0014), and its content document declares `mathml`; the
  highlighters asciidart lacks warn in its own words.
- A custom theme (`epub3-stylesdir`) is read as compiled CSS (`epub3.css`,
  `epub3-css3-only.css`): the gem compiles SCSS, for which asciidart has no
  compiler.
- `revdate` is read in the forms Asciidoctor and documents use (ISO 8601,
  `2026-01-31`, `31 January 2026`, `January 31, 2026`...); Ruby's
  `Time.parse` reads more, so a date in another form is reported as not
  parseable and the document date is used.
- Writing to standard output (`-o -`) is refused with a message; the gem
  fails with an internal error.
- The EPUB3 backend is in the native executable only, not in the npm
  package (see [ADR-0009](../adr/0009-epub3-backend.md)).


## PDF (`-b pdf`)

The PDF backend converts as the asciidoctor-pdf 2.3.27 gem does (on
Asciidoctor 2.0.26, with its default dependencies: Prawn 2.4.0,
prawn-svg 0.34.2, prawn-table, prawn-icon; no optional gems). It reads the
gem's YAML themes unchanged, and it draws with libpdf, asciidart's own PDF
library. Prawn's line wrapping and asciidoctor-pdf's page rules are
imitated in asciidart; no Prawn code is ported.

Since the Hypermedia Systems roadmap (lane EPIC-xj1gxj), `-b pdf`
defaults to asciidart's own layout (optimal line breaking, hyphenation,
widows and orphans). This compatibility mode is selected with
`-a pdf-compat`, and everything in this section describes that mode.

`tool/pdf_parity.dart` compares two PDFs on what a reader sees, not on
their bytes:

- the words, in order (`pdftotext`);
- where each word is, to the point (`pdftotext -bbox`);
- the outline, the link annotations (target and rectangle) and the page
  labels;
- the rendered pages: the mean gray difference, and the share of pixels
  whose color differs from every pixel around them, on the worst page.

The converter tests (`test/pdf/converter_test.dart`) hold 32 fixtures and
the gem's chronicles and edge-cases examples to all of these, against PDFs
the gem made (`SOURCE_DATE_EPOCH=0`).

### Look check (2026-10-07): 793 of 797 documents look the same

ADR-0015 asks of the default engine with `asciidoctor-compat` (pdf) that
its pages look like asciidoctor-pdf's, not that they be the same bytes.
`tool/pdf_look.dart` renders the gem's pages of the same 797 documents
once (gray, 50 dpi, cached), then converts each with asciidart, renders
its pages and compares them blurred (a 5-pixel box; a pixel differs when
the grays differ by more than 10%). A document looks the same when no
page differs on more than 0.5% of its pixels (a line of body text one
point off is about 1%).

```sh
dart run tool/pdf_look.dart --gem <gem wrapper> \
  --exe "<asciidart wrapper with -a asciidoctor-compat=pdf>" \
  --cache <gem pages> --out <dir> [--pairs] ~/.cache/asciidart-work/pdfcorpus/*.adoc
```

793 documents look the same (748 before the look's defaults,
`doc/pdf.md`, and the fixes the check found: title logos fitted to the
page, autowidth columns as wide as their images, words longer than a line
across index terms broken, a heading kept with a whole unbreakable block,
a broken background image reported, not a failure). The other 4:

- *The gem fails* (1): `font-002` (a font that isn't in the catalog).
- *A gem quirk, not copied* (1): `table-098`, a page break inside an
  AsciiDoc table cell: the gem drops the cell's text after it and moves
  the rest to a new page.
- *Within 0.6%* (2): `table-118` (CJK text with a fallback font) and
  `hyphens-006` (a word the gem's patterns don't break).

### Corpus check (2026-10-06): 763 of 797 documents the same

`tool/pdf_spec_corpus.dart` extracts the documents of the gem's own spec
suite: every `to_pdf` heredoc, with the options the spec converts it with
(doctype, attributes, footer, inline theme). That gives 797 documents
covering every feature the gem tests. Each is converted by the gem and by
asciidart and compared as above:

```sh
dart run tool/pdf_spec_corpus.dart ~/.cache/asciidart-work/pdfcorpus
dart run tool/pdf_parity.dart --exe-a <gem wrapper> --exe-b <asciidart wrapper> \
  --out <dir> ~/.cache/asciidart-work/pdfcorpus/*.adoc
```

The wrappers read each document's `.opts`. 763 documents match on every
count. Of the other 34:

- *The gem fails, or both do* (4): `font-002` (a font that isn't in the
  catalog) and `page-040`, `page-042`, `page-043`.
- *Gem bugs, not copied* (3):
  - A front cover that is a missing PDF page turns every later page into
    US Letter (`cover_page-021`, `cover_page-024`); asciidart keeps the
    theme's page size.
  - A broken SVG page background moves the body text to x = 0
    (`page-041`).
- *Text extraction only, the pages identical* (6):
  - A character the font has no glyph for is drawn as `.notdef`. The gem's
    PDF maps it to the character, asciidart's doesn't (libpdf writes CID
    fonts with Identity-H, where `.notdef` can't stand for several
    characters): `table-118`, `font-004`, `font-005`, `admonition-009`.
  - `footnote-027` and `source-069` differ in reading order only.
- *Hyphenation patterns* (1): `hyphens-006` breaks a word the gem's
  patterns don't (see Intentional differences).
- *Not done yet* (20):
  - Footnotes inside AsciiDoc table cells (`table-081`, `table-082`); a
    page break inside an AsciiDoc cell (`table-098`).
  - Autowidth tables: vertical alignment (`table-086`), inline images
    (`table-033`, `table-034`, `table-035`), and `table-100`.
  - Title page background images in two placements (`title_page-026`,
    `title_page-027`).
  - An SVG image in a centered document title (`image-005`).
  - The dot leader of a TOC entry ending in a code span (`toc-003`).
  - Index entries in some arrangements (`index-005`, `index-007`).
  - A footnote reference in a table cell (`footnote-025`).
  - An abstract's first line with a theme override (`abstract-018`).
  - An inline icon image (`icon-001`).
  - `heading_min_height_after: auto` with an image (`section-060`).
  - `cover_page-005`; `admonition-011`.

### Theme keys

`tool/pdf_theme_keys.dart` lists the keys of the theming guide (2.3.27)
that the converter never reads over the corpus. Most come from the corpus,
not from asciidart: it never sets a header, for instance, and the header
keys are read whenever a theme gives the header a height. Not supported:

- `code_highlight_background_color`, `code_line_gap`: options of the gem's
  Rouge formatter. asciidart highlights with hilite (colors from a
  highlight.js theme).
- `block_anchor_top`: only moves where a block's destination points.
- `abstract_text_decoration`, `abstract_title_text_decoration`,
  `base_text_decoration`, `callout_list_text_align`: documented, but the
  gem doesn't read them either.

### Intentional differences

- The non-full-screen page mode (`page_mode: fullscreen ...`) is written in
  the viewer preferences, where ISO 32000 puts it; the gem writes it in the
  catalog, where viewers ignore it.
- Fonts are embedded as CID fonts (Identity-H) with subsets of TrueType
  and CFF outlines; Prawn embeds simple fonts. Text extracts the same,
  except for `.notdef` (above).
- Source highlighting uses hilite rather than Rouge; when the gem is run
  without Rouge, as in the corpus, neither highlights.
- Optional gems behave as not installed: asciidoctor-mathematical (STEM
  stays source text), prawn-gmagick (GIF and other formats are reported),
  rghost (`optimize`). PDF pages as images, covers and
  backgrounds (prawn-templates) are supported natively, through libpdf's
  PDF reader.
- Hyphenation (`hyphens`, `base_hyphens`) is built in, the gem's with
  the optional text-hyphen gem installed (as the corpus is converted, and
  as the gem's spec suite runs). The patterns are hyph-utf8's, for 72
  languages (`vendor/hyph-utf8`): text-hyphen's US English patterns may
  be used for non-commercial purposes only. The two sets break some words
  differently (`hyphens-006`: "vi-cious").
- The parity tool compares what a reader sees; object order, compression
  and IDs differ.
