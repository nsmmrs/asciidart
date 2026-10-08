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

The paragraph cases (lane TASK-p51s1b): the tests of `justify.typ`,
`linebreak.typ`, `hyphenate.typ` and `model/par.typ` that AsciiDoc and
theme keys can say.

- Lines break where Typst's do, with the same edges, in 37 of the 41
  cases: one line at a time (simple breaking, hard breaks) and optimal
  breaking (Typst's costs: cubic badness, hyphenation and runt costs, two
  dashes in a row; `base_line_breaking`), hanging punctuation
  (`overhang`), the vertical model (`base_leading`: lines and paragraphs
  to a hundredth of a point).
- Hyphenation reads a word across formatting (`__Tree__beard` is
  hyphenated Tree-beard), and a compound's hyphen is repeated at the next
  line's start in the languages whose typography has it so (`:lang:`
  Portuguese, Czech, Croatian, Polish, Slovak, Lower Sorbian; Spanish
  before a lowercase word). URLs break as Typst breaks them: between
  parts of punctuation, letters and digits, never after an opening
  bracket, and after any character of a long part. None of this changes
  the Asciidoctor compatibility setting (`asciidoctor-compat=pdf`), which
  breaks as asciidoctor-pdf does. (A hyphen after a word across
  formatting is set in another style than Typst's: 0.17 points.)

The differences left, each deliberate or out of reach:

- `justify-avoid-runts`: both layouts cost the same (77.777: one line of
  14 letters, no runt); which of the tied lines is the short one comes
  down to the rounding of the widths' sums. (Typst's string also ends in
  two spaces, which AsciiDoc collapses.)
- `linebreak-overflow-double`, `issue-hyphenate-in-link`: a word or URL
  longer than the line. Typst lets it overflow into the margin; the
  modern engine breaks it where it fits, so that no text is cropped.
- `linebreak-link-justify`: one line breaks after `www.url.` where Typst
  breaks after `www.`, the lines close in cost.
- Not in AsciiDoc: hanging indents (`par-hanging-indent`), justified
  breaks (`#linebreak(justify: true)`), blocks of a given width and grids
  (`hyphenate`, `hyphenate-shy`, `hyphenate-outside-of-words`), costs
  set per paragraph (`costs-*`), CJK and Thai.

## Latest run (2026-10-08)

| Case | Lines (Typst, ptome) | Broken alike | Edges | Line tops | First line | Pages |
| --- | --- | --- | --- | --- | --- | --- |
| hs-justify-indent | 6, 6 | 6 of 6 | 0.00 | 0.00 | -0.00 | 1, 1 |
| hyphenate-between-shape-runs | 2, 2 | 2 of 2 | 0.17 | 0.00 | +0.00 | 1, 1 |
| hyphenate-es-capitalized-names | 6, 6 | 6 of 6 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-es-repeat-hyphen | 5, 5 | 5 of 5 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-pt-dash-emphasis | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-pt-no-repeat-hyphen | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-pt-repeat-hyphen | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-pt-repeat-hyphen-hyphenate-true-with-emphasis | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-pt-repeat-hyphen-natural-word-breaking | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-punctuation | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| hyphenate-repeat-style | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| issue-hyphenate-after-tag | 2, 2 | 2 of 2 | 0.17 | 0.00 | -0.00 | 1, 1 |
| issue-hyphenate-in-link | 3, 3 | 0 of 3 | 18.55 | 0.00 | +0.00 | 1, 1 |
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
| linebreak-link | 9, 9 | 9 of 9 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-link-end | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-link-justify | 7, 7 | 5 of 7 | 0.00 | 0.00 | -0.00 | 1, 1 |
| linebreak-manual | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-manual-consecutive | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-manual-directly-after-automatic | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-manual-trailing-multiple | 1, 1 | 1 of 1 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-narrow-nbsp | 3, 3 | 3 of 3 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-optimized-without-justify | 4, 4 | 4 of 4 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-overflow | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-overflow-double | 2, 4 | 0 of 2 | 77.62 | 0.00 | +0.00 | 1, 1 |
| linebreak-shape-run | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| linebreak-simple-without-justify | 4, 4 | 4 of 4 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-basic | 19, 19 | 19 of 19 | 0.00 | 0.00 | +0.00 | 3, 3 |
| par-explicit-trim-space | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-leading-and-spacing | 5, 5 | 5 of 5 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-metadata-after-trimmed-space | 2, 2 | 2 of 2 | 0.00 | 0.00 | +0.00 | 1, 1 |
| par-spacing-and-first-line-indent | 4, 4 | 4 of 4 | 0.00 | 0.00 | -0.00 | 1, 1 |
