# ADR-0011: One House Style for Every Format

**Status:** Final. Decided on 2026-10-07.

## Context

Each of asciidart's formats looks like the tool it was ported from: the
HTML page like Asciidoctor's stylesheet (Open Sans headings in red, Noto
Serif text, a 62.5em column, 1.6 line height), the PDF like
asciidoctor-pdf's default theme (Noto Serif 10.5pt at 1.15 line height,
lines of about 95 characters on Letter paper), the EPUB like
asciidoctor-epub3's (M+ 1p headings), the website like the HTML page. A
book exported to all four doesn't look like one book, and some defaults
work against the reader: the PDF's measure is long and its lines tight,
the HTML's column is wider than a comfortable measure.

The user's direction (2026-10-07): sane defaults, based on Asciidoctor's
output but improved by the rules of good typesetting (Butterick's
*Practical Typography* and *Typography for Lawyers*, Bringhurst's *The
Elements of Typographic Style*), unified so a book exported to HTML, a
website, EPUB and PDF has one visual style; technical publishers' books
(O'Reilly's) as the model for code, notes and figures.

## Decision

1. **A house style, defined once** as design values in `doc/style.md`:
   the families' roles (a serif for text, a sans for headings and
   labels, a monospace for code), sizes, line spacing, measure, paragraph
   spacing, heading scale and spacing, colors, code blocks, admonitions,
   tables, captions, footnotes, the index. Each format implements the same
   values in its own units: points in the PDF theme, `rem` and `ch` in the
   stylesheets.

2. **Markup doesn't change; looks do.** The HTML, the website's pages, the
   EPUB's content documents and DocBook keep Asciidoctor's and
   asciidoctor-epub3's markup (the parity corpora compare it). The house
   style lives in what each format uses for its look: the PDF theme of the
   modern engine, the HTML stylesheet, the EPUB's stylesheet.

3. **The house style is the default.** asciidart is not yet released, so
   its defaults can still be its own:
   - **PDF:** the modern engine's default theme is the house theme
     (`asciidart`), which extends asciidoctor-pdf's default. `-a pdf-compat`
     keeps asciidoctor-pdf's layout and theme.
   - **HTML and the website:** the default stylesheet is Asciidoctor's,
     followed by the house rules, in one file (still named
     `asciidoctor.css` when `linkcss` writes it, so links don't change).
   - **EPUB:** asciidoctor-epub3's stylesheet, followed by the house rules.

4. **The classic looks keep a name.** `-a stylesheet=asciidoctor` (HTML,
   website) embeds Asciidoctor's stylesheet as it is; `-a
   epub3-stylesheet=asciidoctor-epub3` uses asciidoctor-epub3's alone;
   `-a pdf-theme=default` is asciidoctor-pdf's theme in the modern engine.
   The parity gates and the tests ported from Asciidoctor set them, so they
   keep comparing like with like.

5. **Typesetting rules the defaults follow** (each in `doc/style.md` with
   its value): a measure of 60 to 75 characters; line spacing of 130 to
   145% in print and 160% on screen; paragraphs set apart by space, not
   indented (technical books' convention), text justified and hyphenated
   in print, ragged on screen; headings in the sans, bold, near-black, a
   modest scale, more space above than below and kept with what follows;
   color only for links and labels; code in a light tint, no border;
   tables with horizontal rules only; small capitals from the font; real
   superscript footnote markers where the format allows.

6. **The fonts are the ones asciidart already bundles** (Noto Serif, Noto
   Sans and M+ 1mn in the PDF; Noto Serif, M+ 1p and M+ 1mn in the EPUB;
   the web fonts the HTML stylesheet already loads). Choosing other faces is a theme's job; bundling more
   fonts is not part of this decision.

## Consequences

- Converting the same document with asciidart and Asciidoctor gives the
  same HTML markup and a different look by default; `doc/books.md` ("From
  asciidoctor-pdf", a new "From Asciidoctor" note) says how to keep the old
  look.
- Tests that check the default look were ported from Asciidoctor; they set
  the classic stylesheet. New tests check the house style's values.
- Lane epic EPIC-b03p4g carries the work.
