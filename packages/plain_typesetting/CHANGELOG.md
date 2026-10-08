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
- A compound's hyphen repeated at the next line's start where the
  language's typography has it so (`Paragraph.hyphenRepetition`,
  `HyphenRepetition.forLanguage`, as Typst does): a `PenaltyItem`'s
  `carry` is the width the next line starts with, which every breaker
  counts.
- Column sets can balance their last region (`ColumnsBox(balance:)`), and
  a floating box in columns can span them (`BoxStyle.floatSpan`, Typst's
  `scope: "parent"`): across the top or bottom of the region.
- A region holds as much content as fits with its notes under it (the
  most room found by halving), where it gave up when the notes of what
  fit first took most of the region.
