# Changelog

## 0.1.0-dev (unreleased)

- Faster, with the same output byte for byte: CFF subsets in one pass
  (a CJK font's 100-glyph subset 60 to 7 ms), TrueType subsets assembled
  once, WOFF2 glyf rebuilt into one buffer, GPOS kerning through
  typed-array accelerators (about 20 times faster per uncached pair),
  `glyphFor` without building the `characterMap` Map, `FontIndex.find`
  and `hasFamily` by family key (microseconds instead of a millisecond
  with 780 fonts), and a cold font index scan opening each file twice.
- A read past the end of a font's data is still a `FontFormatException`,
  now with the message "read past the end of the font" (without the
  offset).
- The OpenType MATH table (`OpenTypeMathTable`, `MathConstant`,
  `MathVariant`, `GlyphConstruction`, `GlyphPart`) from plain_pdf, with
  its history.
- Renamed from `fonts` to `plain_fonts`, and moved with its history into the
  ptome pub workspace (github.com/nsmmrs/ptome, `packages/plain_fonts`;
  ptome's ADR-0018).
- OpenType reading (TrueType and CFF outlines, collections, cmap formats
  0, 4, 6 and 12, `kern` and GPOS kerning, GSUB substitutions), TrueType and CFF subsetting, and WOFF and WOFF2 decoding,
  extracted from plain_pdf with their history.
- The installed-font index, from asciidart: fonts by file name or by
  family and style, in the platform's font folders (the Dart VM, Node.js)
  or files an embedder gives, their headers cached; WOFF and WOFF2 fonts
  decoded (on JavaScript, by a part loaded on demand).
