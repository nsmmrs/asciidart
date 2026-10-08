# Changelog

## 0.1.0-dev (unreleased)

- `PatternHyphenator` (Liang's algorithm) from plain_pdf, with its
  history, and the hyph-utf8 patterns of 72 languages, their aliases and
  `patternTag` from ptome, in one package.
- The patterns are stored Brotli-compressed, one stream per language
  family (808 KiB of source, from 1.5 MB of base64 zlib), and decoded a
  family at a time.
- Tested against hypher and Hyphenopoly on the UDHR's words in 19
  languages.
