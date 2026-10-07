# ADR-0012: Every Format Is First-Class

**Status:** Final. Decided on 2026-10-07.

## Context

asciidart started as a port of Asciidoctor's HTML and DocBook converters,
then gained a PDF backend, an EPUB 3 backend and a website
(`multipage_html5`). The Hypermedia Systems work pushed the PDF far ahead:
an index with page numbers and a Typst-like layout, footnotes at the
bottom of the page, floating figures, text files shown as images,
hyphenation, keep-together blocks. A probe document with every book
feature, converted by every backend (`doc/formats.md`), shows what the
other formats do with them: some drop a feature with a warning (the EPUB
and `toc::[]`), some write broken output (a text file as an `<img>`),
some leave out what their format can say (DocBook's `<info>` without the
ISBN, EPUB's index without its semantics).

## Decision

1. **A feature of the book works in every format**, in the form that
   format's readers expect: the PDF's index has page numbers, the
   website's links to pages, the EPUB's is marked up as an EPUB index,
   DocBook's is `<index/>` for the processor. A format leaves a feature
   out only when its medium has no place for it (running heads on a
   website, page paths in a PDF); `doc/formats.md` marks those *n/a*.

2. **One setting, read by every format.** What the document says (its
   attributes, block attributes and options, roles) is read by every
   backend: `footnote-reference-template` sets the PDF's markers as well
   as the HTML's, `%unbreakable` keeps a block together on paper and in
   print CSS. A backend's own configuration (the PDF theme, a stylesheet)
   decides only how it looks, and a theme key that differs from the
   document's setting takes precedence in the PDF (ADR-0010's theme keys
   stay).

3. **Asciidoctor's output stays the default where asciidart is a
   drop-in.** A feature that changes Asciidoctor's HTML or DocBook for a
   document that doesn't use it is a documented divergence, or opt-in
   (as `callout-links` and `index-html` are), so the parity corpora keep
   comparing like with like. Features for markup Asciidoctor has no
   output for (a text file as an image, `%unbreakable` in HTML) are new
   output, not divergences.

4. **The gaps are lane cards** (`doc/formats.md` names each), worked in
   this order: broken output first (text images), then dropped features
   (EPUB contents), then features a format can say and doesn't (EPUB
   index semantics, DocBook metadata, hyphenation, keep-together), then
   larger additions (math in the PDF and EPUB, a cover on the website,
   an EPUB page list).

## Consequences

- `doc/formats.md` is kept current: a card that closes a gap changes its
  cell.
- New book features land in every backend at once, or with a card for
  each backend they don't reach yet.
- Math typesetting in the PDF (no TeX engine in Dart) and an EPUB page
  list (it needs the PDF's layout) are the expensive gaps; they are
  planned, not promised, and may close as "rendered as images" or as an
  option that needs both builds.
