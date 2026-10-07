# ADR-0010: Generated Text Comes from Templates

**Status:** Final. Decided on 2026-10-06 (lane TASK-0pqx3l, EPIC-bwfj5z).

## Context

Converters write text the document doesn't contain: a caption's number
(`Listing 36. `), a footnote's marker (`[1]`), a callout's (`①`), a
chapter's label (`Chapter 1`), a running head's numeral, the website's
`← Previous` links, the separator between page numbers in an index.
Asciidoctor and asciidoctor-pdf hard-code most of them; a few are theme
keys (`ulist_marker_disc_content`, `menu_caret_content`) or attributes
(`listing-caption`, `chapter-signifier`).

Bringing the Hypermedia Systems book to its Typst edition's look needed
other forms of several of them (`Listing 36: `, a superscript `1`, `[1]`
callouts, `I Hypermedia Concepts`). Waves 1 and 2 added them as switches
(`heading_h2_label_display: block`, `header_title_style: numeral`,
`toc_numbered: false`) or as one-off templates (`conum_glyphs: '[%d]'`).
The user's direction: *anything like the superscript formatting or the
previous/next formatting should be configurable with string templates or
Mustache templates, not with presets* ("the Asciidoctor way or the Typst
way").

## Decision

1. **One template syntax: Mustache.** Every new template is a Mustache
   template, rendered with `package:mustache_template` (the engine of the
   `-T` templates, ADR-0002): `{{name}}` for a value (names may have
   hyphens: `{{chapter-numeral}}`), `{{#name}}...{{/name}}` for a part that
   appears only when the value is set (and not empty), `{{^name}}...{{/name}}`
   for one that appears only when it isn't. Values aren't HTML-escaped by
   the template: the converter escapes them for its output, and a
   template's own markup (`<sup>`, `<strong>`) is the output's.
   asciidoctor-pdf's `{attribute}` references in running content keep
   working as they do in the gem; a template may use both (the Mustache
   part is rendered first).

2. **Where templates live.**
   - **PDF:** theme keys named `<thing>_content`, as the gem's
     (`footnotes_reference_content`, `heading_h2_content`,
     `toc_entry_content`), in the modern engine; the compatibility mode
     reads none of the new ones.
   - **Text every backend writes** (caption numbers): document attributes
     named `<thing>-template` (`listing-caption-template`), applied in the
     core so HTML, EPUB, PDF and DocBook agree.
   - **HTML, EPUB and the website:** short texts (navigation labels,
     footnote markers) as document attributes `<thing>-template`; a page's
     structure (the website's navigation, home page, contents page) as
     Mustache templates in a `-T` directory, under names the converter
     documents (`multipage_nav.mustache`).

3. **Templates in document attributes escape AsciiDoc.** An attribute
   entry's value goes through attribute substitution, which would replace
   `{name}` inside `{{name}}` when the document defines `name`. Template
   values use names no document attribute has (each template documents
   its names), and `pass:[...]` keeps a value as written:
   `:listing-caption-template: pass:[{{caption}} {{number}}: ]`.

4. **Defaults are today's output.** Every template defaults to what the
   converter writes now, so documents and themes without them convert
   byte for byte as before (the parity gates keep checking it).

5. **Switches become templates.** The modern engine's switch-like keys
   from waves 1 and 2 are unreleased; they are replaced by templates
   (FEAT-3x6f9c): `heading_h<n>_label_display` by `heading_h<n>_content`,
   `header_title_style: numeral` by running content with optional parts,
   `toc_numbered` by `toc_entry_content`, `conum_glyphs: '[%d]'` and
   `callout_list_marker_content: '%d.'` by `{{number}}` templates (the
   title page's authors already have the gem's templates). Layout
   (placement, spacing, alignment) stays in keyed values: a template is
   for text.

## Inventory

Generated text a book may want otherwise, and the card that makes it a
template (✓ already configurable):

| Text | Default | Where |
| --- | --- | --- |
| Caption numbers (listing, figure, table, example) | `Listing 36. ` | core attribute (FEAT-35dcbn) |
| Appendix caption | `Appendix A: ` | core attribute (FEAT-35dcbn) |
| Footnote reference, footnote label | `[1]` | PDF key, HTML/EPUB attribute (FEAT-w1y9r2) |
| Callout marker, callout list marker | `①` | PDF key (FEAT-3x6f9c) |
| Chapter and part headings with their labels | `Chapter 1. Title` | PDF key (FEAT-3x6f9c) |
| Running heads | `{chapter-title}` | PDF key, optional parts (FEAT-3x6f9c) |
| Contents entries | `1.1. Title` | PDF key (FEAT-3x6f9c) |
| Title page authors | `A, B` | ✓ gem keys (`title_page_authors_content`, `_delimiter`) |
| Website navigation, home page, contents page | `← Title` | attribute and Mustache (FEAT-bkg33y) |
| List bullets, menu caret, kbd separator | `•`, ` › `, `+` | ✓ gem keys |
| Chapter and part signifiers, caption words | `Chapter`, `Listing` | ✓ attributes |
| Cross reference text | `Section 1.2, “Title”` | ✓ `xrefstyle` |
| Index see and see-also | `(see X)` | later, when a book needs it |
| Section numbers' separator | `1.2.` | later, when a book needs it |

## Consequences

- One syntax to learn and document; conditionals (an unnumbered chapter's
  head without `. `) need no line-dropping rule.
- Converters gain a small helper that renders a template with named
  values (and caches the parsed template).
- Themes for the compatibility mode are unaffected; documents that set no
  template are unaffected.
