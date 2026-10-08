# Changelog

## 0.1.0-dev (unreleased)

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
