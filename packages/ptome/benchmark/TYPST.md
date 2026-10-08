# Typst parity

The modern PDF engine measured against Typst's own test suite
(typst/typst v0.14.2, `tests/suite`; lane EPIC-n7s6v0).
`tool/typst_parity.dart` compiles each case's Typst test with the Typst
0.14.2 CLI under the test runner's defaults (a page 120pt wide with 10pt
margins, unbounded height, 10pt text, the bundled fonts and the dev
assets' only) and converts its AsciiDoc twin with Ptome, the theme
saying what the test's `#set` rules say, with the same font files. The
cases are in `test/typst/<name>/` (`typst.typ`, `doc.adoc`, `theme.yml`;
the tests are Typst's, Apache-2.0: `test/typst/NOTICE`).

```sh
dart run tool/typst_parity.dart --report benchmark/TYPST.md   # -v: each line
```

The columns: the lines of each PDF; how many break at the same words;
the largest difference (points) of a line's left or right edge; of the
distance from the first line's top to a line's top (the line spacing);
and of the first line's top (Ptome's minus Typst's).

## Findings

Each has a card under EPIC-n7s6v0.

- Line breaking matches where both break one line at a time (simple
  breaking, hard breaks): the same words on each line, the same edges.
- The modern engine wraps left-aligned text as Prawn does: a style change
  inside a word is a break opportunity (`emp__has__ized`), and a word
  across a style change isn't hyphenated whole (`__Tree__beard`). Typst
  breaks ragged text with its optimizer too.
- Optimal breaking differs in its costs: Typst's hyphenation and runt
  costs, its cubic badness (the spaces stretch and shrink by the same
  amounts as here), and its hanging punctuation (`overhang`, on by
  default), which lets commas and hyphens into the margin.
- Typst repeats a compound's hyphen at the next line's start in
  Portuguese and Spanish.
- A word longer than the line: Typst lets it overflow into the margin;
  the modern engine breaks it between characters, so that no text is
  cropped. A deliberate difference.
- The vertical model: with `base_leading` (Typst's model: a line's box
  from its cap height to its baseline, the leading between boxes, the
  margins between blocks Typst's spacing), lines and paragraphs fall
  where Typst's do, to a hundredth of a point (a line of a bolder font
  than its paragraph's aside: Typst takes that line's cap height).

## Latest run (2026-10-07)

| Case | Lines (Typst, Ptome) | Broken alike | Edges | Line tops | First line | Pages |
| --- | --- | --- | --- | --- | --- | --- |
| hs-justify-indent | 6, 6 | 6 of 6 | 0.00 | 0.00 | -0.00 | 1, 1 |
| hyphenate-between-shape-runs | 2, 2 | 0 of 2 | 22.65 | 0.00 | +0.00 | 1, 1 |
| hyphenate-es-repeat-hyphen | 5, 5 | 1 of 5 | 15.49 | 0.00 | +0.00 | 1, 1 |
| hyphenate-pt-repeat-hyphen | 3, 3 | 2 of 3 | 3.38 | 0.00 | +0.00 | 1, 1 |
| justify | 6, 6 | 6 of 6 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-avoid-runts | 5, 5 | 2 of 5 | 2.50 | 0.00 | +0.00 | 1, 1 |
| justify-knuth-story-optimized | 21, 21 | 21 of 21 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-knuth-story-simple | 24, 24 | 24 of 24 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-knuth-story-simple-hyphens | 22, 22 | 22 of 22 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-manual-linebreak | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-no-leading-spaces | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-shrink-last-line | 1, 1 | 1 of 1 | 0.00 | 0.00 | +0.00 | 1, 1 |
| justify-without-justifiables | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-hyphen-nbsp | 2, 2 | 2 of 2 | 0.11 | 0.00 | +0.00 | 1, 1 |
| linebreak-manual | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-manual-directly-after-automatic | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-optimized-without-justify | 4, 4 | 4 of 4 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-overflow | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-overflow-double | 2, 4 | 0 of 2 | 77.62 | 0.00 | +0.00 | 1, 1 |
| linebreak-shape-run | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-simple-without-justify | 4, 4 | 4 of 4 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-basic | 19, 19 | 19 of 19 | 0.00 | 0.00 | +0.00 | 3, 3 |
| par-leading-and-spacing | 5, 5 | 5 of 5 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-metadata-after-trimmed-space | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-spacing-and-first-line-indent | 4, 4 | 4 of 4 | 0.00 | 0.00 | -0.00 | 1, 1 |
