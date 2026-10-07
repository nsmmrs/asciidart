# ADR-0015: One Setting for Asciidoctor Compatibility

**Status:** Final. Decided on 2026-10-07. Supersedes ADR-0011's point 4
(the classic looks named per format) as the way to ask for them, and the
PDF backend's two engines.

## Context

asciidart diverges from Asciidoctor on purpose: bug fixes, a house style
(ADR-0011), a modern PDF engine. Someone migrating a project needs the old
output first, then the new one where they choose. Until now that took one
attribute per format (`stylesheet=asciidoctor`,
`epub3-stylesheet=asciidoctor-epub3`, `pdf-theme=default`) and, for the
PDF, a second layout engine that imitates asciidoctor-pdf and Prawn line
by line (`pdf-compat`): twice the PDF code, kept for byte-level parity.

The user's direction (2026-10-07): a config-file or environment setting
turns backwards compatibility on by default, for every format or a list
of them. For the PDF the goal is not the same bytes but a correct modern
PDF that *looks* like asciidoctor-pdf's, within reason; the
Prawn-imitation engine goes. The other formats stay close to
byte-for-byte, with bug fixes and clearly worthwhile improvements.

## Decision

1. **The setting.** `asciidoctor-compat`, with the value `true` (every
   format), `false`, or a comma-separated list of formats: `html` (html5,
   xhtml5, multipage_html5), `epub` (epub3), `docbook` (docbook5),
   `manpage`, `pdf`. Where it comes from, the first found wins:
   - `-a asciidoctor-compat=...` on the command line, or the document's
     own attribute entry;
   - the environment variable `ASCIIDART_COMPAT`;
   - `compat:` in a project's `asciidart.yml` (the nearest one in the
     input's directory or a directory above it);
   - `compat:` in the user's `$XDG_CONFIG_HOME/asciidart/config.yml`
     (`~/.config/asciidart/config.yml`).
   The library API reads the attribute alone; the CLI resolves the
   environment and the files into it (as a default the document may
   override).

2. **What it changes, per format.**
   - **HTML, website:** Asciidoctor's stylesheet alone (no house rules).
     The markup is Asciidoctor's either way; opt-in features stay opt-in;
     bug fixes and repairs stay.
   - **EPUB:** asciidoctor-epub3's stylesheet alone; repairs (valid XHTML,
     landmarks, the `mathml` property) stay.
   - **DocBook, man pages:** nothing to change: the output is
     Asciidoctor's, with its repairs.
   - **PDF:** asciidoctor-pdf's default theme when the document names
     none, and the modern engine's defaults set to look like
     asciidoctor-pdf's pages: its line breaking (one line at a time), no
     hyphenation unless asked, footnotes at the end of the chapter, its
     spacing and pagination rules. Every modern key keeps working: a theme
     can still turn on better typesetting.

3. **One PDF engine.** The Prawn-imitation engine is removed once the
   modern engine, set up as in point 2, matches asciidoctor-pdf's pages
   closely on asciidoctor-pdf's own test documents (the corpus the PDF
   parity gate uses). `-a pdf-compat` stays as a synonym for
   `asciidoctor-compat=pdf`.

4. **The PDF gate becomes a look gate.** `tool/pdf_look.dart` renders the
   gem's pages once (cached), then converts with asciidart and compares
   the page images (blurred, as `scripts/pagediff.sh` does for the
   Hypermedia Systems book), reporting each document's largest page
   difference. Text and structure (outline, links, page labels) are still
   compared with `tool/pdf_parity.dart`. The bar is set in the epic from
   the first full run; documents above it get cards or a written reason.

## Consequences

- `doc/books.md` ("From Asciidoctor") describes the one setting; the
  per-format attributes stay as finer controls.
- Removing the second engine deletes the compatibility branches of the
  PDF converter and the Prawn line wrapper; the converter's tests written
  for byte parity become look tests or go.
- Lane epic (named in its cards) carries the work, ahead of PDF math.
