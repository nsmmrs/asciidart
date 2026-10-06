# Typst parity

The modern PDF engine measured against Typst's own test suite
(typst/typst v0.14.2, `tests/suite`; lane EPIC-n7s6v0).
`tool/typst_parity.dart` compiles each case's Typst test with the Typst
0.14.2 CLI under the test runner's defaults (a page 120pt wide with 10pt
margins, unbounded height, 10pt text, the bundled fonts and the dev
assets' only) and converts its AsciiDoc twin with asciidart, the theme
saying what the test's `#set` rules say, with the same font files. The
cases are in `test/typst/<name>/` (`typst.typ`, `doc.adoc`, `theme.yml`;
the tests are Typst's, Apache-2.0: `test/typst/NOTICE`).

```sh
dart run tool/typst_parity.dart --report benchmark/TYPST.md   # -v: each line
```

The columns: the lines of each PDF; how many break at the same words;
the largest difference (points) of a line's left or right edge; of the
distance from the first line's top to a line's top (the line spacing);
and of the first line's top (asciidart's minus Typst's).

## Findings

- Line breaking matches: same words on each line, the same edges.
- The vertical model differs. Typst's `leading` is the space between a
  line's baseline and the next one's cap height (lines 11.58 points
  apart in 10-point Libertinus Serif with 5 points of leading), and a
  paragraph's `spacing` takes the leading's place between paragraphs;
  its first line's cap height sits at the top of the page. The modern
  engine's lines are the font's height times `base_line_height` apart,
  a paragraph's margin added to that, and its first line's ascender at
  the top.

## Latest run (2026-10-06)

| Case | Lines (Typst, asciidart) | Broken alike | Edges | Line tops | First line | Pages |
| --- | --- | --- | --- | --- | --- | --- |
| justify | 6, 6 | 6 of 6 | 0.00 | 4.28 | +2.36 | 1, 1 |
