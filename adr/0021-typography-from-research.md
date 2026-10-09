# ADR-0021: Typography from Research, Not from Another Engine

**Status:** Accepted on 2026-10-09. Supersedes [ADR-0013](0013-typst-derived-options.md).

## Context

The modern PDF engine took its line breaking, its link breaking, its
hanging punctuation amounts and a dozen smaller behaviors from Typst,
because the Hypermedia Systems book had moved to Typst and its AsciiDoc
edition was brought to match the Typst build page by page (ADR-0013).
That made Typst's choices, and some of its shortcuts, ptome's defaults,
and kept parity tooling, Typst's tests and a Typst-like example theme in
the repository.

Matching another engine is not the goal. The goal is the best typography
the literature and the standards describe.

## Decision

1. **Every layout rule rests on published research or a standard, never
   on another engine's code.** Where a rule needs a value, the value comes
   from the source that established it.
2. **Line breaking is Knuth and Plass's total fit** ("Breaking paragraphs
   into lines", 1981) with TeX's costs (The TeXbook, chapter 14):
   tolerance a badness of 200, line penalty 10, 10000 demerits for two
   hyphenated lines in a row or adjacent lines in distant fitness classes,
   5000 for a hyphenated next-to-last line, explicit hyphens at
   `\exhyphenpenalty` 50, and a pass with emergency stretch. Lines of
   different widths (an indent, a drop's lines) are exact: every active
   break knows its line number. Ragged lines are broken as plain TeX's
   `\raggedright` sets them (a finite right stretch), so their ends are
   even. The Typst breaker is removed.
3. **URLs break as The Chicago Manual of Style has them**: after a colon or
   a double slash; before a single slash, a tilde, a period, a comma, a
   hyphen, an underscore, a question mark, a number sign or a percent
   sign; before or after an equals sign or an ampersand; never with an
   added hyphen.
4. **Hanging punctuation is margin kerning** (Hàn Thế Thành,
   "Micro-typographic extensions to the TeX typesetting system", 2000),
   with the right-hand amounts of LaTeX's microtype package's default set.
5. **Options that are sound typography stay, described on their own
   terms** (CSS, TeX and LaTeX, the orthographies that repeat a hyphen):
   lines set from their cap heights (CSS's `text-box-edge: cap
   alphabetic`), floats that never come before their text, a running head
   that sees the page's top mark, list and term layouts, widows and
   orphans. Options whose only purpose was to copy Typst go: the index in
   code point order (`index-sort: code-point`).
6. **No parity tooling.** The Typst parity tool and Typst's test cases,
   the Hypermedia Systems acceptance against its Typst build, the
   Typst-like example theme, `doc/typst-look.md` and the hypher
   hyphenation oracle are removed. Hyphenation stays checked against
   Hyphenopoly and pub.dev's `hyphenation` package.

## Consequences

- The output changes where Typst's choices and the research differ: line
  breaks (TeX's costs, ragged lines optimized), URL breaks, hanging
  amounts.
- The Hypermedia Systems book is a large test document, no longer a parity
  target.
- What the literature offers beyond this is the next work: font expansion
  (the other half of Hàn Thế Thành's microtypography), protrusion that the
  line breaker counts, left-margin protrusion, a last line not too short,
  globally optimal pagination (Plass, 1981; Brüggemann-Klein, Klein and
  Wohlfeil; Mittelbach's DocEng papers), and Chicago's alphabetizing
  rules for the index (letter by letter or word by word).
