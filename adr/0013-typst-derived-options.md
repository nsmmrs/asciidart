# ADR-0013: Typst's Layout as Settings, Not a Mode

**Status:** Final. Decided on 2026-10-07.

## Context

To bring the Hypermedia Systems book to its Typst edition's look, the
modern PDF engine gained about sixty theme keys and a dozen behaviors
taken from Typst (`doc/typst-look.md` lists them). The book's build then
matched the Typst build page by page (tags `hs-golden-parity-2026-10-06`
in asciidart and libpdf, `golden-parity-2026-10-06` in the book's port).
Some of what made the last pages match was Typst's own defects copied on
purpose: the contents page listed in the index for the headings that
carry an index term, a URL that never breaks after `://` when its host
starts with a digit, index terms that lost a space in the Typst build
(fixed in the source since).

Matching Typst is not asciidart's goal. A writer should be able to set
a book Typst's way, and every other way, by choosing values; nobody
should get Typst's defects by default, or find a key whose only meaning
is "do what Typst does".

## Decision

1. **No Typst mode.** No key or attribute is named after Typst or means
   "Typst's way". Each Typst behavior is a value of a key that has other
   sensible values: `index_sort: code-point` beside the default
   alphabetical index, `image_placement: auto` beside `here`, `top`,
   `bottom` and `next`, `base_leading` beside `base_line_height`.
   `doc/typst-look.md` is the one place that maps Typst to keys.

2. **Typst's defects are not kept.** A key or behavior whose only use is
   to reproduce a defect is removed: `toc_index_terms` (the contents page
   in the index), the URL rule for hosts that start with a digit. The tags
   above keep the state that reproduced them.

3. **Keys are described on their own terms.** `doc/pdf.md` says what a
   key does and what its values are; Typst is named only where it helps
   to recognize the behavior, never as the definition.

4. **Booleans that are amounts become amounts.** A switch that turns on
   one fixed amount (`base_overhang: true`, the hanging of punctuation)
   takes a number too, so a book can hang less or more; `true` keeps its
   meaning.

5. **Behaviors without keys stay when they are better for every book:**
   the line breaking opportunities of UAX #14, hyphenating words of
   letters only, a too-wide last line that only shrinks, anchors that take
   no width, index terms that take no room, floats kept out of the space
   between the blocks around them. Each is in `doc/typst-look.md`, "What
   has no key".

6. **An example theme shows the Typst-like settings** (`example/themes/
   book-typst-like-theme.yml`), with the fonts asciidart bundles, so the
   keys are used together and tested.

## Consequences

- The book's port keeps its Typst-like design in its own theme, through
  these keys; its pages match the Typst build except where the Typst
  build had a defect (17 of 316 pages, `benchmark/HS.md`).
- Lane epic EPIC-c01y1z holds one card per change.
