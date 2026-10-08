# plain_typesetting

Typesetting in pure Dart, independent of the output format. It lays out
text and pages and draws them on a `Canvas`; a backend implements the
canvas, its pages and its fonts
([plain_pdf](https://github.com/nsmmrs/ptome/tree/master/packages/plain_pdf)
for PDF).

- **Fonts and shaping.** `Font` is what layout needs from a font: metrics,
  coverage and shaping. `OpenTypeShaper` sets text in an OpenType font
  (read by plain_fonts): each character's glyph, the single substitutions
  of the features asked for (`onum`, `smcp`...), `liga` ligatures, and
  kerning by GPOS pairs or the `kern` table.
- **Paragraphs.** Inline content (text runs with colors, links, anchors,
  underlines and backgrounds; inline images) becomes the boxes, glue and
  penalties of Knuth and Plass's model. Break opportunities come from UAX
  #14 (plain_unicode) and a `Hyphenator`, and a `LineBreaker` chooses the
  breaks: first fit, Knuth-Plass, or your own.
- **Pages.** `FlowLayout` lays a tree of boxes (blocks, paragraphs,
  images, tables, columns, floats, notes, custom content) out on pages
  from `PageTemplate`s, with orphans and widows, keeps, page breaks,
  running headers and footers, anchors and marks, and lays out again only
  from what changed. `render` adds the pages to a `LayoutDocument`.
- **Math.** `MathLayout` sets a plain_math tree by the rules of the
  OpenType MATH table: scripts, fractions, radicals, stretchy delimiters,
  large operators, accents, tables and spacing.

```dart
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

final font = OpenTypeShaper(
  OpenTypeFont.parse(File('NotoSerif-Regular.ttf').readAsBytesSync()),
);
final lines = const KnuthPlassLineBreaker().breakLines(
  Paragraph([
    TextRun('A paragraph of text to break into lines.', TextStyle(font, 10)),
  ]),
  (line) => 120, // the width of each line, in points
);
// Draw each line on any Canvas: line.paint(canvas, x, top).
```

Tests lay out paragraphs, pages and formulas on a recording canvas, and,
with the `tools` tag, compare the shaper with HarfBuzz (`tool/oracles/`):
every run of the test text, with ligatures and kerning on and off and the
`onum` and `smcp` features, shapes as HarfBuzz shapes it in four fonts.
plain_pdf's tests set the same layouts in PDF, byte for byte against
golden files.

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace, whose PDF converter lays out with it.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE).
