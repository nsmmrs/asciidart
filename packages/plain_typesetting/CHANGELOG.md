# Changelog

## 0.1.0-dev (unreleased)

- Paragraph and page layout (`Paragraph`, the line breakers, `FlowLayout`
  and its boxes), the math layout (`MathLayout`), geometry, colors, the
  text style and `Graphic` moved from plain_pdf with their history, and
  the shaping loop from plain_pdf's embedded fonts (`OpenTypeShaper`).
- Independent of PDF: layouts draw on the `Canvas` interface and render
  into a `LayoutDocument` of `LayoutPage`s, set text in `Font`s, and link
  to `LinkTarget`s, which a backend implements (plain_pdf). `render` gives
  back the backend's own page type.
- Renamed from plain_pdf's names: `PdfRect` to `Rect`, `PdfMatrix` to
  `Matrix`, `PdfColor` to `Color`, `PdfTextStyle` to `TextStyle`.
- `OpenTypeShaper` is a `Font` on its own, compared with HarfBuzz.
- `KnuthPlassLineBreaker` is the optimal breaker, with TeX's costs by
  default (tolerance: a badness of 200; 10000 demerits for two hyphenated
  lines in a row or adjacent lines far apart in fitness; 5000 for a
  hyphenated next-to-last line), an emergency-stretch pass
  (`emergencyStretch`), and ragged lines broken as TeX's `\rightskip`
  sets them (`raggedStretch`). Fills are counted apart, so lines after a
  forced break inside a paragraph stretch as they should.
  `demeritsOf` gives the demerits of any breaks, for checking. It
  replaces the breaker modeled on another engine's (ADR-0021).
- Side notes still waiting when the text ends go on pages of their own
  (margin only) instead of being dropped; `LayoutResult.unsetSideNotes`
  names any no page's side column has room for.
- A compound's hyphen repeated at the next line's start where the
  language's typography has it so (`Paragraph.hyphenRepetition`,
  `HyphenRepetition.forLanguage`): a `PenaltyItem`'s
  `carry` is the width the next line starts with, which every breaker
  counts.
- Column sets can balance their last region (`ColumnsBox(balance:)`), and
  a floating box in columns can span them (`BoxStyle.floatSpan`, as
  LaTeX's `figure*`): across the top or bottom of the region.
- Blocks floating to a side (`BoxStyle.side`, `sideWidth`, `sideGap`):
  the blocks after one are set beside it, each whole or, where it doesn't
  fit beside it, below it; what doesn't fit in its region goes on at the
  top of the next, before anything else, the content there going around
  it (a sidebar through the next page's banner); a forced break waits for
  it. A block's first children can be set again at the top of each later
  piece of it (`BlockBox.repeatedHead`), and on the piece its floating
  block goes on to.
- Side notes (`FlowLayout.sideNotes`, `sideColumn`): boxes set beside the
  line their anchor is on, in a column of the page's choosing (a reference
  Bible's center column), pushed down where they crowd and carried to the
  next page where they don't fit.
- A region holds as much content as fits with its notes under it (the
  most room found by halving), where it gave up when the notes of what
  fit first took most of the region.
- `LinedContent`: custom content made of lines laid out once per width;
  the layout asks how many fit and keeps as many as the page breaker
  allows (orphans and widows, as for paragraphs), the content placing
  that many. `PageBreaker.linesToKeep` is that rule apart from measuring
  (a page breaker implements it too).
- Faster, with the same output: math items moved in place and glyph
  metrics cached; a `FlowLayout` keeps its paragraphs' lines and widths
  from one `layout` to the next.
